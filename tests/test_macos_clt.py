"""Inert extracted macOS CLT helper and caller contracts. No live platform operations."""
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

SOURCE = (Path(__file__).resolve().parents[1] / 'mac.sh').read_text()
REQUIRED = ('check_for_installed_developer_tools', 'check_xcode_license_approved',
            'check_xcode_minimum_version', 'check_clt_minimum_version',
            'check_if_xcode_needs_clt_installed', 'check_if_supported_sdk_available',
            'check_xcode_select_path', 'check_xcode_prefix_exists')


def function(name):
    return re.search(rf'^{name}\(\) \{{\n.*?^\}}', SOURCE, re.M | re.S)[0]


class CLT(unittest.TestCase):
    def run_case(self, expression, variables=None, existing_tool=False):
        with tempfile.TemporaryDirectory() as root:
            home = Path(root) / 'home'
            home.mkdir()
            if existing_tool:
                (Path(root) / 'absent-clt').mkdir()
            script = r'''
print_error() { printf 'ERROR:%s\n' "$*"; }
print_warning() { printf 'WARN:%s\n' "$*"; }
print_debug() { printf 'DEBUG:%s\n' "$*"; }
print_message() { printf 'MESSAGE:%s\n' "$*"; }
print_success() { printf 'SUCCESS:%s\n' "$*"; }
xcode-select() { [[ "$*" == -p ]] || return 90; [[ "${SELECT_OK:-1}" == 1 ]] && printf '%s\n' "${SELECTED:-/Library/Developer/CommandLineTools}"; }
xcrun() { [[ "$*" == '--find clang' ]] || return 90; [[ "${COMPILER_OK:-1}" == 1 ]]; }
softwareupdate() { [[ "$*" == --list ]] || return 90; printf 'query\n' >> "$HOME/calls"; [[ "${QUERY_OK:-1}" == 1 ]] || return 1; printf '%s\n' "${UPDATES:-No new software available.}"; }
sudo() {
    if [[ "$1" == /usr/bin/perl ]]; then
        if [[ "$*" == *O_EXCL* ]]; then printf 'create\n' >> "$HOME/calls"; [[ "${CREATE_OK:-1}" == 1 ]] || return 1; printf '1:2';
        else printf 'cleanup\n' >> "$HOME/calls"; [[ "${CLEAN_OK:-1}" == 1 ]]; fi
    elif [[ "$*" == softwareupdate\ --install\ *\ --verbose ]]; then
        printf 'install:%s\n' "$3" >> "$HOME/calls"; [[ "${INSTALL_OK:-1}" == 1 ]];
    else printf 'unexpected-sudo:%s\n' "$*" >> "$HOME/calls"; return 90; fi
}
command() { if [[ "$1" == -v && "$2" == brew ]]; then [[ "${BREW_OK:-1}" == 1 ]]; else builtin command "$@"; fi; }
brew() {
    if [[ "$*" == 'doctor --list-checks' ]]; then printf 'discovery\n' >> "$HOME/calls"; [[ "${DISCOVERY_OK:-1}" == 1 ]] || return 1; printf '%s\n' "$CHECKS";
    else printf 'doctor:%s\n' "$*" >> "$HOME/calls"; [[ "$*" == "doctor $REQUIRED_ARGS" ]] || return 90;
        [[ "${DOCTOR_OK:-1}" == 1 ]] || { printf '%s\n' 'Your Command Line Tools (CLT) does not support macOS 27. It is either outdated or was modified.'; return 1; }; fi
}
'''
            install = function('install_xcode_cli_tools')
            for original, replacement in (('/Library/Developer/CommandLineTools', str(Path(root) / 'absent-clt')),
                                          ('/Applications/Xcode.app', str(Path(root) / 'absent-xcode'))):
                self.assertEqual(install.count(' -e ' + original), 1)
                install = install.replace(' -e ' + original, ' -e ' + replacement)
            script += '\n'.join((install, function('verify_developer_tools_for_homebrew'),
                                 function('_install_clt_via_softwareupdate')))
            script += '\n' + expression + '\n'
            env = {'PATH': '/usr/bin:/bin', 'HOME': str(home), 'TMPDIR': root,
                   'CHECKS': '\n'.join(REQUIRED), 'REQUIRED_ARGS': ' '.join(REQUIRED)}
            env.update(variables or {})
            result = subprocess.run(['/bin/bash', '-c', script], env=env, text=True, capture_output=True)
            calls = (home / 'calls').read_text().splitlines() if (home / 'calls').exists() else []
            self.assertNotIn('unexpected-sudo', '\n'.join(calls))
            return result, calls

    def test_existing_no_offer_and_xcode(self):
        for selected in ('/Library/Developer/CommandLineTools', '/Applications/Xcode.app/Contents/Developer'):
            result, calls = self.run_case('install_xcode_cli_tools; verify_developer_tools_for_homebrew', {'SELECTED': selected})
            self.assertEqual(result.returncode, 0, result.stdout)
            self.assertIn('pending', result.stdout)
            self.assertIn('passed', result.stdout)
            self.assertNotIn('up to date', result.stdout)
            self.assertEqual(calls, ['query', 'discovery', 'doctor:doctor ' + ' '.join(REQUIRED)])

    def test_query_failure_and_diagnostics(self):
        result, calls = self.run_case('install_xcode_cli_tools', {'QUERY_OK': '0'})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('ERROR:', result.stdout)
        self.assertEqual(calls, ['query'])
        for key in ('DISCOVERY_OK', 'BREW_OK', 'COMPILER_OK', 'SELECT_OK'):
            result, calls = self.run_case('verify_developer_tools_for_homebrew', {key: '0'})
            self.assertNotEqual(result.returncode, 0, key)
            self.assertNotIn('doctor:', ' '.join(calls))
        for missing in REQUIRED:
            result, calls = self.run_case('verify_developer_tools_for_homebrew', {'CHECKS': '\n'.join(x for x in REQUIRED if x != missing)})
            self.assertNotEqual(result.returncode, 0, missing)
            self.assertNotIn('doctor:', ' '.join(calls))
        result, calls = self.run_case('verify_developer_tools_for_homebrew', {'DOCTOR_OK': '0'})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('does not support macOS 27', result.stdout)
        self.assertEqual(calls, ['discovery', 'doctor:doctor ' + ' '.join(REQUIRED)])

    def test_existing_tools_without_selection_are_preserved(self):
        result, calls = self.run_case('install_xcode_cli_tools', {'SELECT_OK': '0'}, existing_tool=True)
        self.assertEqual(result.returncode, 1)
        self.assertIn('Select a trusted installation manually', result.stdout)
        self.assertFalse(any(c in calls for c in ('create', 'cleanup')))

    def test_install_labels_and_failures(self):
        for label, expected in (('* Label: Command Line Tools for Xcode-27.0', 'Command Line Tools for Xcode-27.0'),
                                ('Label: Command Line Tools for Xcode 27', 'Command Line Tools for Xcode 27'),
                                ('* Command Line Tools for Xcode 27', 'Command Line Tools for Xcode 27')):
            result, calls = self.run_case('_install_clt_via_softwareupdate', {'UPDATES': label})
            self.assertEqual(result.returncode, 0, result.stdout)
            self.assertEqual(calls, ['create', 'query', 'install:' + expected, 'cleanup'])
        result, calls = self.run_case('_install_clt_via_softwareupdate', {'UPDATES': '* Label: Command Line Tools for Xcode-26\n* Label: Command Line Tools for Xcode-27'})
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn('install:Command Line Tools for Xcode-27', calls)
        for values in ({'QUERY_OK': '0'}, {'UPDATES': 'Unrelated software'}, {'INSTALL_OK': '0'},
                       {'CLEAN_OK': '0'}, {'INSTALL_OK': '0', 'CLEAN_OK': '0'}, {'CREATE_OK': '0'}):
            result, calls = self.run_case('_install_clt_via_softwareupdate', {'UPDATES': '* Label: Command Line Tools for Xcode-27', **values})
            self.assertNotEqual(result.returncode, 0, values)
            self.assertIn('ERROR:', result.stdout)
            if values.get('QUERY_OK') == '0' or values.get('CREATE_OK') == '0':
                self.assertFalse(any(c.startswith('install:') for c in calls))

    def test_actual_caller_and_finalization(self):
        names = re.findall(r'^([a-zA-Z_][a-zA-Z_0-9]*)\(\) \{', SOURCE, re.M)
        protected = {'run_setup_tasks', 'main', 'print_error', 'print_warning', 'print_debug',
                     'print_message', 'print_success', 'install_xcode_cli_tools',
                     'verify_developer_tools_for_homebrew', '_install_clt_via_softwareupdate'}
        stubs = '\n'.join(f'{n}() {{ printf "work:{n}\\n" >> "$HOME/calls"; }}' for n in set(names) - protected)
        # The actual caller and main run unchanged; only unrelated functions are inert.
        overrides = r'''
whoami() { printf 'fixture-user\n'; }
is_main_user() { [[ "$PERSONA" == primary ]]; }
paseo_release_channel() { printf 'stable'; }
check_dotfiles_access() { return 1; }
setup_dotfiles_deploy_key() { return 1; }
install_homebrew() { printf 'brew-bootstrap\n' >> "$HOME/calls"; : > "$HOME/brew-ready"; }
retire_infisical_brew() { printf 'retire\n' >> "$HOME/calls"; [[ "${RETIRE_OK:-1}" == 1 ]]; }
check_pending_reboot() { printf 'reboot\n' >> "$HOME/calls"; }
start_setup_log() { printf 'log-start\n' >> "$HOME/calls"; }
finish_setup_log() { printf 'final:%s\n' "$1" >> "$HOME/calls"; return "$1"; }
/opt/homebrew/bin/brew() { [[ "$*" == shellenv ]] || return 90; printf 'shellenv\n' >> "$HOME/calls"; printf 'export BREW_READY=1\n'; }
'''
        # Replace the tool mocks with stateful versions; command substitutions
        # run in subshells, so state is persisted in the temporary HOME.
        state = r'''
xcode-select() {
    [[ "$*" == -p ]] || return 90
    printf 'selection\n' >> "$HOME/calls"
    [[ "${INITIAL:-0}" == 1 && ! -f "$HOME/installed" ]] && return 1
    [[ "${POST_SELECT_OK:-1}" == 1 ]] || return 1
    printf '%s\n' "${SELECTED:-/Library/Developer/CommandLineTools}"
}
xcrun() { [[ "$*" == '--find clang' ]] || return 90; printf 'compiler\n' >> "$HOME/calls"; [[ "${COMPILER_OK:-1}" == 1 ]]; }
sudo() {
    if [[ "$1" == /usr/bin/perl ]]; then
        if [[ "$*" == *O_EXCL* ]]; then printf 'create\n' >> "$HOME/calls"; [[ "${CREATE_OK:-1}" == 1 ]] || return 1; printf '1:2';
        else printf 'cleanup\n' >> "$HOME/calls"; [[ "${CLEAN_OK:-1}" == 1 ]]; fi
    elif [[ "$*" == softwareupdate\ --install\ *\ --verbose ]]; then
        printf 'install:%s\n' "$3" >> "$HOME/calls"
        [[ "${INSTALL_OK:-1}" == 1 ]] || return 1
        : > "$HOME/installed"
    else printf 'unexpected-sudo:%s\n' "$*" >> "$HOME/calls"; return 90; fi
}
command() {
    if [[ "$1" == -v && "$2" == brew ]]; then
        [[ -f "$HOME/brew-ready" || "${BREW_READY:-}" == 1 ]]
    elif [[ "$1" == -v ]]; then return 1
    else builtin command "$@"; fi
}
'''
        # run_case's tool stubs are replaced by these definitions before invocation.
        base = stubs + '\n' + overrides + '\n' + state + '\n' + function('run_setup_tasks') + '\n' + function('main') + '\nmain'
        for persona in ('primary', 'secondary'):
            for failure in ('', 'QUERY_OK', 'INSTALL_OK', 'CLEAN_OK', 'DOCTOR_OK', 'RETIRE_OK'):
                if persona == 'secondary' and failure == 'RETIRE_OK':
                    continue
                with self.subTest(persona=persona, failure=failure):
                    variables = {'PERSONA': persona, 'INITIAL': '1', 'UPDATES': '* Label: Command Line Tools for Xcode-27.0'}
                    if failure:
                        variables[failure] = '0'
                    # Extract helpers as before; run_case wraps the entire real caller.
                    result, calls = self.run_case(base, variables)
                    expected = int(bool(failure))
                    self.assertEqual(result.returncode, expected, (failure, result.stdout, result.stderr, calls))
                    self.assertEqual(calls.count('final:' + str(expected)), 1, calls)
                    self.assertEqual(calls.count('reboot'), 1, calls)
                    self.assertIn('work:install_bun', calls)
                    self.assertLess(calls.index('install:Command Line Tools for Xcode-27.0') if failure not in ('QUERY_OK',) else calls.index('query'), calls.index('work:install_bun'))
                    if failure not in ('QUERY_OK', 'INSTALL_OK'):
                        self.assertLess(calls.index('doctor:doctor ' + ' '.join(REQUIRED)), calls.index('work:install_core_packages') if persona == 'primary' else calls.index('work:install_bun'))
                    self.assertIn('brew-bootstrap' if persona == 'primary' else 'shellenv', calls)
                    self.assertFalse(any('unexpected' in c or 'rm -rf' in c or 'xcode-select --switch' in c for c in calls))
                    self.assertIn('Setup completed with errors' if expected else 'Setup complete!', result.stdout)

    def test_native_sentinel_perl_on_temporary_paths(self):
        helper = function('_install_clt_via_softwareupdate')
        snippets = re.findall(r"sudo /usr/bin/perl (?:-MFcntl=[^ ]+ )?-e '([^']+)'", helper)
        self.assertEqual(len(snippets), 2)
        with tempfile.TemporaryDirectory() as root:
            sentinel = Path(root) / 'sentinel'
            target = Path(root) / 'target'
            target.write_text('preserve')
            def create():
                return subprocess.run(['/usr/bin/perl', '-MFcntl=O_WRONLY,O_CREAT,O_EXCL,O_NOFOLLOW',
                                       '-e', snippets[0], str(sentinel)], capture_output=True, text=True)
            def cleanup(identity):
                return subprocess.run(['/usr/bin/perl', '-e', snippets[1], str(sentinel), identity], capture_output=True)
            first = create()
            self.assertEqual(first.returncode, 0, first.stderr)
            self.assertNotEqual(create().returncode, 0)
            self.assertTrue(sentinel.exists())
            self.assertEqual(cleanup(first.stdout).returncode, 0)
            sentinel.symlink_to(target)
            self.assertNotEqual(create().returncode, 0)
            self.assertNotEqual(cleanup(first.stdout).returncode, 0)
            self.assertTrue(sentinel.is_symlink())
            sentinel.unlink()
            second = create()
            self.assertEqual(second.returncode, 0)
            old = Path(root) / 'old'
            sentinel.rename(old)  # retain old inode so it cannot be reused
            third = create()
            self.assertEqual(third.returncode, 0)
            self.assertNotEqual(cleanup(second.stdout).returncode, 0)
            self.assertEqual(cleanup(third.stdout).returncode, 0)
            self.assertEqual(target.read_text(), 'preserve')

    def test_finalization_seam(self):
        body = function('run_setup_tasks')
        self.assertIn('install_xcode_cli_tools || _setup_had_errors=1', body)
        self.assertEqual(body.count('verify_developer_tools_for_homebrew || _setup_had_errors=1'), 2)
        main = function('main')
        for status in (0, 1):
            result, _ = self.run_case(main + '\nstart_setup_log() { :; }\nrun_setup_tasks() { return ' + str(status) + '; }\nfinish_setup_log() { printf "FINAL:%s\\n" "$1"; return "$1"; }\nmain')
            self.assertEqual(result.returncode, status)
            self.assertEqual(result.stdout.count('FINAL:' + str(status)), 1)


if __name__ == '__main__':
    unittest.main()
