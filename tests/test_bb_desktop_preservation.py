import functools
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

import extract_setup_fixture
from test_bb_desktop import ROOT, SCRIPTS, seed, snapshot

PWSH = os.environ.get('PWSH_BIN')


@functools.lru_cache(None)
def caller_fixture(entry):
    source = extract_setup_fixture.definitions((ROOT / (entry + '.sh')).read_text())
    names = set(re.findall(r'^([a-zA-Z_][a-zA-Z_0-9]*)\(\)\s*\{', source, re.M))
    retained = ('run_setup_tasks', 'main')
    blocks = []
    for name in retained:
        start = source.index('\n' + name + '() {\n') + 1
        block = source[start:source.index('\n}\n', start) + 3]
        extract_setup_fixture.validate_function(block)
        blocks.append(block)
    stubs = '\n'.join(name + '() { :; }' for name in names if name not in retained)
    return stubs + '\n' + '\n'.join(blocks)


class DesktopCallers(unittest.TestCase):
    def run_entry(self, entry, home, failure='none', headless='0', work='0'):
        script = caller_fixture(entry) + r'''
check_dotfiles_access() { return 1; }
setup_dotfiles_deploy_key() { return 1; }
is_main_user() { return 0; }
bb_server_selection() { return 1; }
whoami() { printf 'fixture-account\n'; }
print_debug() { printf 'debug:%s\n' "$*"; }
print_warning() { printf 'warning:%s\n' "$*"; }
print_error() { printf 'error:%s\n' "$*"; }
install_bb_desktop() { echo FORBIDDEN:desktop-installer; return 99; }
bb_desktop_payload() { echo FORBIDDEN:desktop-payload; return 99; }
install_opencode_cli() { [[ "$FAILURE" != independent ]]; }
setup_bb_machine() { echo bb-preparation; }
refresh_bb_plugins() { echo plugin-refresh; [[ "$FAILURE" != plugins ]]; }
install_ntn_cli() { echo independent-work; }
check_pending_reboot() { echo reboot-reported; }
start_setup_log() { echo logging; }
finish_setup_log() { printf 'final:%s\n' "$1"; return "$1"; }
'''
        for command in ('curl', 'wget', 'npm', 'bun', 'bb', 'pi', 'brew', 'chezmoi', 'sudo',
                        'systemctl', 'launchctl', 'kill', 'pkill', 'ps', 'pgrep', 'tailscale',
                        'open', 'codesign', 'spctl', 'chmod', 'chown', 'rm', 'mv', 'cp', 'ln'):
            script += f'\n{command}() {{ echo FORBIDDEN:{command}; return 99; }}'
        script += '\nmain\n'
        before = snapshot(home)
        result = subprocess.run(['/bin/bash', '--noprofile', '--norc', '-c', script], cwd=home,
                                env={'PATH': '/usr/bin:/bin', 'HOME': str(home), 'SHELL': '/bin/bash',
                                     'HEADLESS': headless, 'WORK_MACHINE': work, 'BB_SERVER': '0',
                                     'FAILURE': failure}, stdin=subprocess.DEVNULL,
                                text=True, capture_output=True, timeout=20)
        self.assertEqual(result.returncode, int(failure != 'none'), result.stdout + result.stderr)
        self.assertNotIn('FORBIDDEN:', result.stdout + result.stderr)
        self.assertEqual(snapshot(home), before)
        for marker in ('bb-preparation', 'plugin-refresh', 'independent-work', 'reboot-reported'):
            self.assertIn(marker, result.stdout)
        self.assertEqual(result.stdout.count('final:'), 1)
        self.assertIn('final:' + str(int(failure != 'none')), result.stdout)
        self.assertLess(result.stdout.index('reboot-reported'), result.stdout.index('final:'))

    def test_all_bash_callers_preserve_absent_fork_duplicate_and_linked_desktop_state(self):
        for entry in SCRIPTS:
            for layout in ('absent', 'duplicates', 'links'):
                for headless in ('', '0', '1', 'true'):
                    for work in ('0', '1'):
                        with self.subTest(entry=entry, layout=layout, headless=headless, work=work), \
                                tempfile.TemporaryDirectory(prefix='bb-unmanaged-caller-') as root:
                            home = Path(root) / 'home'
                            home.mkdir()
                            seed(home, layout)
                            self.run_entry(entry, home, headless=headless, work=work)

    def test_independent_and_plugin_failures_still_reach_reboot_and_final_logging(self):
        for entry in SCRIPTS:
            for failure in ('independent', 'plugins'):
                with self.subTest(entry=entry, failure=failure), \
                        tempfile.TemporaryDirectory(prefix='bb-unmanaged-failure-') as root:
                    home = Path(root) / 'home'
                    home.mkdir()
                    seed(home, 'duplicates')
                    self.run_entry(entry, home, failure=failure)

    @unittest.skipUnless(PWSH, 'Set PWSH_BIN for inert Windows caller/state coverage')
    def test_windows_caller_preserves_apps_and_keeps_early_headless_and_failure_boundaries(self):
        for layout in ('absent', 'duplicates', 'links'):
            for headless in ('0', '1', 'true'):
                for failure in ('none', 'independent'):
                    with self.subTest(layout=layout, headless=headless, failure=failure), \
                            tempfile.TemporaryDirectory(prefix='bb-unmanaged-windows-') as root:
                        base = Path(root)
                        home = base / 'home'
                        home.mkdir()
                        seed(home, layout)
                        before = snapshot(home)
                        env = dict(os.environ, HOME=str(home), USERPROFILE=str(home), USERNAME='scowalt',
                                   XDG_CACHE_HOME=str(base / 'cache'), XDG_CONFIG_HOME=str(base / 'config'),
                                   XDG_DATA_HOME=str(base / 'data'), EVENTS=str(base / 'events'),
                                   FIXTURE_LOG_DIR=str(base / 'logs'), FAILURE=failure, HEADLESS=headless)
                        result = subprocess.run([PWSH, '-NoProfile', '-NonInteractive', '-File',
                                                 str(ROOT / 'tests/bb-desktop-windows-contract.ps1')],
                                                env=env, cwd=base, stdin=subprocess.DEVNULL,
                                                capture_output=True, text=True, timeout=20)
                        expected = int(headless == '1' or failure != 'none')
                        self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
                        self.assertEqual(snapshot(home), before)
                        events = (base / 'events').read_text().splitlines()
                        self.assertNotIn('FORBIDDEN', '\n'.join(events))
                        self.assertEqual(events.count('finalized'), 1)
                        self.assertEqual(events[-1], 'failed' if expected else 'finalized')
                        self.assertEqual('independent-work' in events, headless != '1')
                        self.assertEqual('reboot-reported' in events, headless != '1')
                        self.assertEqual('failed' in events, bool(expected))


if __name__ == '__main__':
    unittest.main(verbosity=2)
