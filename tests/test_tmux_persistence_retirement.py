from pathlib import Path
import re
import subprocess
import tempfile
import unittest

from extract_setup_fixture import validate_function
from test_setup_rollback import BASH, ROOT, function


class TmuxPersistenceRetirement(unittest.TestCase):
    def test_setup_keeps_tmux_without_persistence_management(self):
        for name in (*BASH, 'win.ps1'):
            with self.subTest(script=name):
                source = (ROOT / name).read_text()
                self.assertNotRegex(source, r'tmux-resurrect|tmux-continuum|tmux-plugins/tpm|\.tmux/plugins')
                self.assertNotRegex(source, r'install_tmux_plugins|enable_tmux_service|tmux\.service')
                self.assertNotRegex(source, r'\btmux (?:source|source-file|new-session|kill-server)\b')
                if name != 'win.ps1':
                    self.assertRegex(source, r'local (?:packages|formulae)=\([^\n]*"tmux"')

    def test_callers_apply_dotfiles_without_contacting_tmux_or_services(self):
        for name in BASH:
            source = (ROOT / name).read_text()
            names = re.findall(r'^([A-Za-z_][A-Za-z_0-9]*)\(\) \{', source, re.M)
            code = '\n'.join(f'{n}() {{ :; }}' for n in names) + '\n'
            for helper in ('run_setup_tasks', 'main', *(('apply_chezmoi_config',) if name == 'pi.sh' else ())):
                block = function(source, helper)
                validate_function(block)
                code += block + '\n'
            code += r'''
record() { printf '%s\n' "$*" >> "$EVENTS"; }
whoami() { printf 'fixture\n'; }
is_main_user() { return 0; }
check_dotfiles_access() { return 0; }
bb_server_selection() { return 1; }
with_bb_dotfiles_umask() { shift; "$@"; }
chezmoi() { record "dotfiles:$*"; return "$APPLY_STATUS"; }
enable_user_lingering() { record lingering; }
install_ntn_cli() { record unrelated; }
check_pending_reboot() { record reboot; }
finish_setup_log() { record "final:$1"; return "$1"; }
'''
            for command in ('tmux', 'systemctl', 'launchctl', 'loginctl', 'curl', 'git', 'sudo',
                            'npm', 'bun', 'pi', 'bb', 'kill', 'pkill', 'brew',
                            'install_tmux_plugins', 'enable_tmux_service'):
                code += f'\n{command}() {{ record FORBIDDEN:{command}; return 99; }}'
            code += '\nmain\n'
            for apply_status in (0, 23):
                with self.subTest(script=name, apply_status=apply_status), tempfile.TemporaryDirectory() as tmp:
                    home = Path(tmp) / 'home'
                    home.mkdir()
                    credential = home / '.local/bin/git-credential-github-multi'
                    credential.parent.mkdir(parents=True)
                    credential.write_text('#!/bin/sh\nexit 99\n')
                    credential.chmod(0o700)
                    saved = home / '.tmux/resurrect/session.txt'
                    saved.parent.mkdir(parents=True)
                    saved.write_text('preserved session data\n')
                    events = Path(tmp) / 'events'
                    result = subprocess.run(
                        ['/bin/bash', '--noprofile', '--norc', '-c', code], cwd=home,
                        env={'PATH': '/usr/bin:/bin', 'HOME': str(home), 'EVENTS': str(events),
                             'SHELL': '/bin/bash', 'APPLY_STATUS': str(apply_status)},
                        capture_output=True, text=True, timeout=20,
                    )
                    expected = int(apply_status != 0)
                    self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
                    self.assertNotIn('command not found', result.stderr)
                    calls = events.read_text().splitlines()
                    self.assertTrue(any(c.startswith('dotfiles:apply --force') for c in calls), calls)
                    self.assertFalse(any(c.startswith('FORBIDDEN:') for c in calls), calls)
                    self.assertIn('unrelated', calls)
                    self.assertIn('reboot', calls)
                    self.assertEqual(calls[-1], f'final:{expected}')
                    if name in ('ubuntu.sh', 'pi.sh', 'bazzite.sh'):
                        self.assertIn('lingering', calls)
                    self.assertEqual(saved.read_text(), 'preserved session data\n')


if __name__ == '__main__':
    unittest.main(verbosity=2)
