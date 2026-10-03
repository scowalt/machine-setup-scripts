"""Real extracted macOS bootstrap/caller tests; inert commands and private paths.

CLT compatibility is not an orchestration gate. Actual operations still fail.
Run only through the audited run-fixture-matrix.py containment runner.
"""
import fcntl
import os
from pathlib import Path
import pty
import re
import subprocess
import tempfile
import termios
import unittest

from extract_setup_fixture import validate_function

SOURCE = (Path(__file__).resolve().parents[1] / 'mac.sh').read_text()
LABEL = 'Command Line Tools for Xcode-27.0'
OFFER = '* Label: ' + LABEL + '\n\tTitle: Command Line Tools for Xcode, Version: 27.0, Recommended: YES,'
HELPERS = ('install_xcode_cli_tools', '_install_clt_via_softwareupdate')


def function(name):
    block = re.search(rf'^{name}\(\) \{{\n.*?^\}}', SOURCE, re.M | re.S)[0]
    validate_function(block)
    return block


MOCKS = r'''
print_error() { printf 'ERROR:%s\n' "$*"; }
print_warning() { printf 'WARN:%s\n' "$*"; }
print_debug() { printf 'DEBUG:%s\n' "$*"; }
print_message() { printf 'MESSAGE:%s\n' "$*"; }
print_success() { printf 'SUCCESS:%s\n' "$*"; }
is_main_user() { [[ "${PERSONA:-primary}" == primary ]]; }
whoami() { printf 'fixture-user\n'; }
xcode-select() {
    printf 'selection:%s\n' "$*" >> "$HOME/calls"
    [[ "$*" == -p ]] || return 90
    [[ "${SELECT_OK:-1}" == 1 ]] || return 1
    [[ "${INITIAL:-0}" != 1 || -f "$HOME/installed" ]] || return 1
    printf '%s\n' "${DEVELOPER_DIR-${SELECTED}}"
}
xcrun() {
    printf 'xcrun:%s\n' "$*" >> "$HOME/calls"
    [[ "$*" == '--find clang' && "${COMPILER_OK:-1}" == 1 ]]
}
softwareupdate() {
    printf 'apple:%s\n' "$*" >> "$HOME/calls"
    [[ "$*" == --list ]] || return 90
    [[ "${QUERY_OK:-1}" == 1 ]] || return 1
    printf '%s\n' "$UPDATES"
}
sudo() {
    case "$*" in
        '-v') printf 'sudo:auth\n' >> "$HOME/calls" ;;
        'softwareupdate --install '*)
            printf 'sudo:%s\n' "$*" >> "$HOME/calls"
            [[ "$*" == "softwareupdate --install $LABEL --verbose" ]] || return 90
            : > "$HOME/installed"
            [[ "${INSTALL_OK:-1}" == 1 ]] ;;
        /usr/bin/perl*)
            if [[ "$*" == *O_EXCL* ]]; then
                printf 'sentinel:create\n' >> "$HOME/calls"
                [[ "${CREATE_OK:-1}" == 1 ]] || return 1
                printf '1:2'
            else
                printf 'sentinel:cleanup\n' >> "$HOME/calls"
                [[ "${CLEAN_OK:-1}" == 1 ]]
            fi ;;
        *) printf 'unexpected:sudo:%s\n' "$*" >> "$HOME/calls"; return 90 ;;
    esac
}
command() {
    if [[ "$*" == '-v brew' ]]; then [[ "${BREW_OK:-1}" == 1 ]]
    else builtin command "$@"; fi
}
brew() {
    printf 'brew:%s\n' "$*" >> "$HOME/calls"
    case "$*" in
        'doctor --list-checks') printf 'check_if_supported_sdk_available\n' ;;
        'doctor '*) printf 'Warning: Your Command Line Tools (CLT) does not support macOS 27.\n'; return "${DOCTOR_STATUS:-1}" ;;
        *) return 0 ;;
    esac
}
# No real dotfiles, application or platform command is executed.
chezmoi() { printf 'chezmoi:%s\n' "$*" >> "$HOME/calls"; }
tmux() { :; }
curl() { printf 'unexpected:curl\n' >> "$HOME/calls"; return 90; }
open() { printf 'unexpected:GUI\n' >> "$HOME/calls"; return 90; }
check_dotfiles_access() { [[ "${DOTFILES_ACCESS:-1}" == 1 ]]; }
setup_dotfiles_deploy_key() { return 1; }
install_homebrew() { printf 'brew-bootstrap\n' >> "$HOME/calls"; [[ "${FAIL_TASK:-}" != install_homebrew ]]; }
/opt/homebrew/bin/brew() { [[ "$*" == shellenv ]] || return 90; printf 'shellenv\n' >> "$HOME/calls"; }
check_pending_reboot() { printf 'reboot\n' >> "$HOME/calls"; }
create_env_local() { [[ "${EARLIER_FAILURE:-0}" != 1 ]] || _setup_had_errors=1; }
start_setup_log() { printf 'log-start\n' >> "$HOME/calls"; }
finish_setup_log() { printf 'final:%s\n' "$1" >> "$HOME/calls"; return "$1"; }
'''


class CLT(unittest.TestCase):
    def run_case(self, variables=None, expression='install_xcode_cli_tools', caller=False,
                 terminal=False, existing=True):
        with tempfile.TemporaryDirectory() as root:
            home = Path(root) / 'home'; home.mkdir()
            clt = Path(root) / 'clt'
            if existing:
                clt.mkdir()
            env = {'PATH': '/usr/bin:/bin', 'HOME': str(home), 'TMPDIR': root, 'SHELL': '/bin/bash',
                   'SELECTED': str(clt), 'LABEL': LABEL, 'UPDATES': OFFER}
            env.update(variables or {})
            names = re.findall(r'^([a-zA-Z_][a-zA-Z_0-9]*)\(\) \{', SOURCE, re.M)
            script = '\n'.join(f'{n}() {{ printf "work:{n}\\n" >> "$HOME/calls"; [[ "${{FAIL_TASK:-}}" != {n} ]]; }}'
                               for n in set(names) - set(HELPERS)) + '\n' + MOCKS
            for name in HELPERS:
                body = function(name).replace('/Library/Developer/CommandLineTools', str(clt))
                body = body.replace(' -e /Applications/Xcode.app', ' -e ' + root + '/Xcode.app')
                script += '\n' + body
            if caller:
                script += '\n' + function('run_setup_tasks') + '\n' + function('main')
                credential = home / '.local/bin/git-credential-github-multi'
                credential.parent.mkdir(parents=True); credential.write_text('# fixture'); credential.chmod(0o700)
                script += '\nmain\n'
            else:
                script += '\n' + expression + '\n'
            master = slave = None
            if terminal:
                master, slave = pty.openpty()
                def controlling_tty():
                    os.setsid()
                    fcntl.ioctl(0, termios.TIOCSCTTY, 0)
                kwargs = {'stdin': slave, 'preexec_fn': controlling_tty}
            else:
                kwargs = {'stdin': subprocess.DEVNULL, 'start_new_session': True}
            try:
                result = subprocess.run(['/bin/bash', '-c', script], env=env, text=True,
                                        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20, **kwargs)
            finally:
                if master is not None:
                    os.close(master); os.close(slave)
            calls = (home / 'calls').read_text().splitlines() if (home / 'calls').exists() else []
            self.assertNotIn('unexpected:', '\n'.join(calls), (result.stdout, calls))
            self.assertNotIn('command not found', result.stderr)
            self.assertFalse(any(x in '\n'.join(calls) for x in ('--switch', '--reset', '--all', '--restart', 'rm -rf')))
            return result, calls

    def installs(self, calls):
        return [c for c in calls if 'softwareupdate --install' in c]

    def test_stale_sdk_does_not_gate_normal_work(self):
        common = ('initialize_chezmoi', 'install_tmux_plugins', 'install_codex_cli', 'install_gitea_client',
                  'setup_bb_machine', 'refresh_bb_plugins', 'setup_matt_pocock_skills',
                  'install_pi_cli', 'refresh_pi_packages', 'retire_global_backlog_mcp',
                  'prepare_pi_profile_permissions', 'install_claude_code', 'install_ntn_cli')
        for persona in ('primary', 'secondary'):
            for doctor in ('1', '2'):
                result, calls = self.run_case({'PERSONA': persona, 'DOCTOR_STATUS': doctor,
                    'SELECTED': '/Applications/Xcode-27.0.0.app/Contents/Developer'}, caller=True)
                for name in common + (() if persona == 'secondary' else
                        ('install_core_packages', 'install_gcloud_cli', 'setup_tailscale', 'update_brew')):
                    self.assertIn('work:' + name, calls)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(calls.count('final:0'), 1)
                self.assertEqual(calls.count('reboot'), 1)
                self.assertEqual(self.installs(calls), [])
                self.assertFalse(any(c.startswith('brew:doctor') for c in calls))
                self.assertNotIn('apple:--list', calls)

    def test_actual_failures_continue_later_work_and_finalize_nonzero(self):
        for task in ('install_homebrew', 'install_core_packages', 'install_sessionwatcher',
                     'install_secrets_manager', 'install_gcloud_cli', 'setup_tailscale',
                     'install_nerd_font', 'install_betterdisplay', 'initialize_chezmoi',
                     'install_tmux_plugins', 'install_opencode_cli', 'install_gitea_client',
                     'install_codex_cli', 'install_bun', 'install_sfw', 'install_gemini_cli',
                     'install_portless_cli', 'setup_bb_machine', 'refresh_bb_plugins',
                     'install_claude_code', 'install_ntn_cli', 'setup_matt_pocock_skills', 'update_brew'):
            with self.subTest(task=task):
                result, calls = self.run_case({'FAIL_TASK': task}, caller=True)
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertIn('work:update_brew', calls)
                self.assertIn('work:remove_compound_engineering_resources', calls)
                self.assertEqual(calls.count('reboot'), 1)
                self.assertEqual(calls.count('final:1'), 1)

    def test_real_profile_safety_failure_still_blocks_pi_not_unrelated_work(self):
        result, calls = self.run_case({'FAIL_TASK': 'prepare_pi_profile_permissions'}, caller=True)
        self.assertEqual(result.returncode, 1)
        self.assertNotIn('work:install_pi_cli', calls)
        self.assertNotIn('work:refresh_pi_packages', calls)
        self.assertIn('work:update_brew', calls)
        self.assertEqual(calls.count('final:1'), 1)

    def test_success_does_not_erase_earlier_failure(self):
        result, calls = self.run_case({'EARLIER_FAILURE': '1'}, caller=True)
        self.assertEqual(result.returncode, 1)
        self.assertIn('work:install_pi_cli', calls)
        self.assertIn('work:update_brew', calls)
        self.assertEqual(calls.count('final:1'), 1)

    def test_existing_selection_is_preserved_without_compiler_or_compatibility_preflight(self):
        for variables in ({}, {'PERSONA': 'secondary'}, {'COMPILER_OK': '0'},
                          {'SELECTED': '/Applications/Xcode.app/Contents/Developer'},
                          {'DEVELOPER_DIR': '/custom/Xcode/Contents/Developer'}):
            result, calls = self.run_case(variables)
            self.assertEqual(result.returncode, 0, result.stdout)
            self.assertEqual(calls, ['selection:-p'])

    def test_fresh_bootstrap_is_separate_and_failures_do_not_gate_ordinary_work(self):
        for failure in ('', 'QUERY_OK', 'INSTALL_OK', 'CLEAN_OK', 'CREATE_OK', 'COMPILER_OK'):
            values = {'INITIAL': '1', 'BREW_OK': '0'}
            if failure:
                values[failure] = '0'
            result, calls = self.run_case(values, caller=True, existing=False)
            self.assertEqual(result.returncode, int(bool(failure)), (failure, result.stdout, result.stderr))
            self.assertEqual(calls.count('final:' + str(int(bool(failure)))), 1)
            self.assertIn('work:install_codex_cli', calls)
            self.assertIn('work:update_brew', calls)
            self.assertLess(calls.index('sentinel:create'), calls.index('brew-bootstrap'))
            self.assertLessEqual(len(self.installs(calls)), 1)
        result, calls = self.run_case({'INITIAL': '1', 'PERSONA': 'secondary'}, caller=True, existing=False)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(self.installs(calls), [])
        self.assertNotIn('sentinel:create', calls)
        self.assertIn('work:install_codex_cli', calls)

    def test_existing_tools_without_selection_never_bootstrap(self):
        result, calls = self.run_case({'SELECT_OK': '0'})
        self.assertEqual(result.returncode, 1)
        self.assertIn('Select a trusted installation manually', result.stdout)
        self.assertEqual(self.installs(calls), [])
        self.assertNotIn('sentinel:create', calls)

    def test_homebrew_absent_preserves_bootstrap_toolchain_guard(self):
        helper = function('install_homebrew').replace('/Library/Developer/CommandLineTools', '${HOME}/bootstrap-clt')
        helper = helper.replace('/opt/homebrew/bin/brew', '${HOME}/bootstrap-brew')
        for variables in ({'SELECT_OK': '0'}, {}, {'SELECTED': '/Applications/Xcode.app/Contents/Developer'}):
            result, calls = self.run_case({'BREW_OK': '0', **variables}, expression=helper + '\ninstall_homebrew')
            self.assertEqual(result.returncode, 1)
            self.assertIn('Skipping Homebrew bootstrap', result.stdout)
            self.assertEqual(self.installs(calls), [])
            self.assertNotIn('sudo:auth', calls)
        fixture = r'''
mkdir -p "$HOME/bootstrap-clt/usr/bin"
printf '#!/bin/bash\nexit 0\n' > "$HOME/bootstrap-clt/usr/bin/git"
chmod +x "$HOME/bootstrap-clt/usr/bin/git"
curl() {
    printf 'brew-download\n' >> "$HOME/calls"
    printf '%s\n' 'printf "#!/bin/bash\\nexit 0\\n" > "$HOME/bootstrap-brew"; chmod +x "$HOME/bootstrap-brew"'
}
install_homebrew
'''
        result, calls = self.run_case({'BREW_OK': '0'}, expression=helper + '\n' + fixture, terminal=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('brew-download', calls)
        self.assertEqual(self.installs(calls), [])

    def test_original_bootstrap_label_formats_and_owned_sentinel(self):
        for offer, label in (('* Label: ' + LABEL, LABEL),
                             ('Label: Command Line Tools for Xcode 27', 'Command Line Tools for Xcode 27'),
                             ('* Command Line Tools for Xcode 27', 'Command Line Tools for Xcode 27'),
                             ('* Label: Command Line Tools for Xcode-26\n* Label: ' + LABEL, LABEL)):
            result, calls = self.run_case({'UPDATES': offer, 'LABEL': label}, expression='_install_clt_via_softwareupdate')
            self.assertEqual(result.returncode, 0, result.stdout)
            self.assertEqual(self.installs(calls), ['sudo:softwareupdate --install ' + label + ' --verbose'])
            self.assertEqual(calls.count('sentinel:create'), 1)
            self.assertEqual(calls.count('sentinel:cleanup'), 1)

    def test_native_sentinel_perl_on_temporary_paths(self):
        snippets = re.findall(r"sudo /usr/bin/perl (?:-MFcntl=[^ ]+ )?-e '([^']+)'", function('_install_clt_via_softwareupdate'))
        self.assertEqual(len(snippets), 2)
        with tempfile.TemporaryDirectory() as root:
            sentinel = Path(root) / 'sentinel'; target = Path(root) / 'target'; target.write_text('preserve')
            def create():
                return subprocess.run(['/usr/bin/perl', '-MFcntl=O_WRONLY,O_CREAT,O_EXCL,O_NOFOLLOW',
                                       '-e', snippets[0], str(sentinel)], capture_output=True, text=True)
            def cleanup(identity):
                return subprocess.run(['/usr/bin/perl', '-e', snippets[1], str(sentinel), identity], capture_output=True)
            first = create(); self.assertEqual(first.returncode, 0, first.stderr)
            self.assertNotEqual(create().returncode, 0)
            self.assertEqual(cleanup(first.stdout).returncode, 0)
            sentinel.symlink_to(target)
            self.assertNotEqual(create().returncode, 0); self.assertNotEqual(cleanup(first.stdout).returncode, 0)
            self.assertTrue(sentinel.is_symlink()); sentinel.unlink()
            second = create(); sentinel.rename(Path(root) / 'old'); third = create()
            self.assertNotEqual(cleanup(second.stdout).returncode, 0)
            self.assertEqual(cleanup(third.stdout).returncode, 0)
            self.assertEqual(target.read_text(), 'preserve')


if __name__ == '__main__':
    unittest.main()
