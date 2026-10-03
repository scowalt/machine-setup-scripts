"""Real extracted macOS helpers and run_setup_tasks/main; inert temporary fixtures only."""
import fcntl
import os
from pathlib import Path
import pty
import re
import subprocess
import tempfile
import termios
import unittest

SOURCE = (Path(__file__).resolve().parents[1] / 'mac.sh').read_text()
REQUIRED = ('check_for_installed_developer_tools', 'check_xcode_license_approved',
            'check_xcode_minimum_version', 'check_clt_minimum_version',
            'check_if_xcode_needs_clt_installed', 'check_if_supported_sdk_available',
            'check_xcode_select_path', 'check_xcode_prefix_exists')
LABEL = 'Command Line Tools for Xcode-27.0'
OFFER = '* Label: ' + LABEL + '\n\tTitle: Command Line Tools for Xcode, Version: 27.0, Size: 800000K, Recommended: YES,'
HELPERS = ('install_xcode_cli_tools', 'verify_developer_tools_for_homebrew',
           '_install_clt_via_softwareupdate', 'ensure_macos_developer_tools_ready')
HELPERS += tuple(re.findall(r'^(macos_\w+)\(\) \{', SOURCE, re.M))


def function(name):
    return re.search(rf'^{name}\(\) \{{\n.*?^\}}', SOURCE, re.M | re.S)[0]


MOCKS = r'''
print_error() { printf 'ERROR:%s\n' "$*"; }
print_warning() { printf 'WARN:%s\n' "$*"; }
print_debug() { printf 'DEBUG:%s\n' "$*"; }
print_message() { printf 'MESSAGE:%s\n' "$*"; }
print_success() { printf 'SUCCESS:%s\n' "$*"; }
is_main_user() { [[ "${PERSONA:-primary}" == primary ]]; }
whoami() { printf 'fixture-user\n'; }
sw_vers() { printf '27.0\n'; }
pkgutil() { printf 'package-id: com.apple.pkg.CLTools_Executables\nversion: 26.0\n'; }
xcode-select() {
    printf 'selection:%s\n' "$*" >> "$HOME/calls"
    [[ "$*" == -p ]] || return 90
    [[ "${SELECT_OK:-1}" == 1 ]] || return 1
    [[ "${INITIAL:-0}" != 1 || -f "$HOME/installed" ]] || return 1
    if [[ -f "$HOME/changed" ]]; then printf '/Applications/Xcode.app/Contents/Developer\n'
    else printf '%s\n' "${DEVELOPER_DIR-${SELECTED}}"; fi
}
xcrun() {
    case "$*" in
        '--find clang') [[ "${COMPILER_OK:-1}" == 1 ]] ;;
        'clang --version') printf 'Apple clang version 17.0\n' ;;
        'xcodebuild -version') printf 'Xcode 27.0\n' ;;
        *) printf 'unexpected:xcrun:%s\n' "$*" >> "$HOME/calls"; return 90 ;;
    esac
}
softwareupdate() {
    printf 'apple:%s\n' "$*" >> "$HOME/calls"
    [[ "$*" == --list ]] || return 90
    [[ "${QUERY_CHANGE:-0}" != 1 ]] || touch "$HOME/changed"
    [[ "${QUERY_OK:-1}" == 1 ]] || { printf 'Fixture update query error\n'; return 1; }
    printf '%s\n' "$UPDATES"
}
sudo() {
    case "$*" in
        '-n true') printf 'sudo:cached\n' >> "$HOME/calls"; [[ "${CACHED:-1}" == 1 ]] ;;
        '-v') printf 'sudo:auth\n' >> "$HOME/calls"; [[ "${AUTH_OK:-1}" == 1 ]] ;;
        '-n softwareupdate --install '*| 'softwareupdate --install '*)
            printf 'sudo:%s\n' "$*" >> "$HOME/calls"
            [[ "$1" != -n ]] || shift
            [[ "$*" == "softwareupdate --install $LABEL --verbose" ]] || return 90
            [[ "${INSTALL_CHANGE:-0}" != 1 ]] || touch "$HOME/changed"
            [[ "${INSTALL_EXPIRE:-0}" != 1 ]] || return 1
            : > "$HOME/installed"
            [[ "${INSTALL_OK:-1}" == 1 ]] ;;
        /usr/bin/perl*)
            if [[ "$*" == *O_EXCL* ]]; then
                printf 'sentinel:create\n' >> "$HOME/calls"; [[ "${CREATE_OK:-1}" == 1 ]] || return 1; printf '1:2'
            else printf 'sentinel:cleanup\n' >> "$HOME/calls"; [[ "${CLEAN_OK:-1}" == 1 ]]; fi ;;
        *) printf 'unexpected:sudo:%s\n' "$*" >> "$HOME/calls"; return 90 ;;
    esac
}
command() {
    if [[ "$1" == -v && "$2" == brew ]]; then
        [[ "${BREW_OK:-1}" == 1 || -f "$HOME/brew-ready" ]]
    elif [[ "$1" == -v ]]; then
        [[ " ${MISSING:-} " != *" $2 "* ]] && printf '%s\n' "$2"
    else builtin command "$@"; fi
}
brew() {
    printf 'brew:%s\n' "$*" >> "$HOME/calls"
    if [[ "$*" == 'doctor --list-checks' ]]; then
        [[ "${DISCOVERY_OK:-1}" == 1 ]] || return 1
        printf '%s\n' "$CHECKS"; return
    fi
    [[ "$1" == doctor && $# == 2 ]] || { printf 'unexpected:brew\n' >> "$HOME/calls"; return 90; }
    [[ "${FAIL_CHECK:-check_if_supported_sdk_available}" == "$2" ]] || return 0
    [[ "${DIAGNOSTIC_CHANGE:-0}" != 1 ]] || touch "$HOME/changed"
    if [[ "${DIAGNOSTIC:-ready}" == ready || ( -f "$HOME/installed" && "${RECOVERS:-1}" == 1 ) ]]; then return 0; fi
    case "$DIAGNOSTIC" in
        incompatible) printf 'Warning: Your Command Line Tools (CLT) does not support macOS 27. It is either outdated or was modified.\n' ;;
        minimum) printf 'Warning: Your Command Line Tools are too outdated.\n' ;;
        crash) printf 'Error: fixture diagnostic exception\n' ;;
        misleading) printf 'Warning: Your Command Line Tools (CLT) does not support macOS 27.\nError: exception\n' ;;
        *) printf '%s\n' "$DIAGNOSTIC" ;;
    esac
    return "${DIAGNOSTIC_STATUS:-1}"
}
# Every independent executable probe is inert (no real tools, extensions or credentials).
git() { [[ "${PROBE_FAIL:-}" != git ]]; }
chezmoi() { printf 'chezmoi:%s\n' "$*" >> "$HOME/calls"; [[ "${PROBE_FAIL:-}" != chezmoi ]]; }
mise() { [[ "${PROBE_FAIL:-}" != mise ]]; }
jq() { [[ "${PROBE_FAIL:-}" != jq ]]; }
fish() { [[ "${PROBE_FAIL:-}" != fish ]]; }
/opt/homebrew/bin/fish() { [[ "${PROBE_FAIL:-}" != fish ]]; }
node() { [[ "${PROBE_FAIL:-}" != node ]]; }
curl() { [[ "$*" == --version && "${PROBE_FAIL:-}" != curl ]]; }
unzip() { [[ "$*" == -v && "${PROBE_FAIL:-}" != unzip ]]; }
tmux() { :; }
can_sudo() { printf 'unexpected:can_sudo\n' >> "$HOME/calls"; return 90; }
open() { printf 'unexpected:GUI\n' >> "$HOME/calls"; return 90; }
matt_pocock_skills_disabled() { [[ "${BAN_MATT_POCOCK_SKILLS:-0}" == 1 ]]; }
check_dotfiles_access() { [[ "${DOTFILES_ACCESS:-0}" == 1 ]]; }
setup_dotfiles_deploy_key() { return 1; }
install_homebrew() { printf 'brew-bootstrap\n' >> "$HOME/calls"; [[ "${BREW_BOOTSTRAP_OK:-1}" == 1 ]] || return 1; : > "$HOME/brew-ready"; }
/opt/homebrew/bin/brew() { [[ "$*" == shellenv ]] || return 90; printf 'shellenv\n' >> "$HOME/calls"; printf 'BREW_OK=1\n'; }
check_pending_reboot() { printf 'reboot\n' >> "$HOME/calls"; }
create_env_local() { [[ "${EARLIER_FAILURE:-0}" != 1 ]] || _setup_had_errors=1; }
start_setup_log() { printf 'log-start\n' >> "$HOME/calls"; }
finish_setup_log() { printf 'final:%s\n' "$1" >> "$HOME/calls"; return "$1"; }
'''


class CLT(unittest.TestCase):
    def run_case(self, variables=None, expression='ensure_macos_developer_tools_ready', caller=False,
                 terminal=False, existing=True, linked=False):
        with tempfile.TemporaryDirectory() as root:
            home = Path(root) / 'home'; home.mkdir()
            clt = Path(root) / 'clt'
            if existing:
                clt.mkdir()
            if linked:
                clt.rmdir(); clt.symlink_to(home, target_is_directory=True)
            env = {'PATH': '/usr/bin:/bin', 'HOME': str(home), 'TMPDIR': root, 'SHELL': '/bin/bash',
                   'CHECKS': '\n'.join(REQUIRED), 'SELECTED': str(clt), 'LABEL': LABEL, 'UPDATES': OFFER}
            env.update(variables or {})
            names = re.findall(r'^([a-zA-Z_][a-zA-Z_0-9]*)\(\) \{', SOURCE, re.M)
            # All unrelated functions inert; actual caller, main and every CLT helper retained.
            script = '\n'.join(f'{n}() {{ printf "work:{n}\\n" >> "$HOME/calls"; }}'
                               for n in set(names) - set(HELPERS)) + '\n' + MOCKS
            for name in HELPERS:
                body = function(name).replace('/Library/Developer/CommandLineTools', str(clt))
                body = body.replace(' -L /Library ', ' -L ' + root + '/Library ')
                body = body.replace(' -L /Library/Developer ', ' -L ' + root + '/Library/Developer ')
                body = body.replace(' -e /Applications/Xcode.app', ' -e ' + root + '/Xcode.app')
                script += '\n' + body
            if caller:
                script += '\n' + function('run_setup_tasks') + '\n' + function('main')
                # Avoid credential bootstrap, even when testing successful dotfiles prerequisites.
                credential = home / '.local/bin/git-credential-github-multi'
                credential.parent.mkdir(parents=True); credential.write_text('# fixture'); credential.chmod(0o700)
                script += '\nmain\n'
            else:
                script += '\n' + expression + '\n'
            master = slave = None
            kwargs = {}
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
            self.assertFalse(any(x in '\n'.join(calls) for x in ('--switch', '--reset', '--all', '--restart', 'rm -rf', '--install-rosetta')))
            return result, calls

    def installs(self, calls):
        return [c for c in calls if 'softwareupdate --install' in c]

    def test_ready_never_queries_or_repairs_even_with_offer(self):
        for variables in ({}, {'PERSONA': 'secondary'}, {'SELECTED': '/Applications/Xcode.app/Contents/Developer'},
                          {'DEVELOPER_DIR': '/custom/Xcode/Contents/Developer'}):
            result, calls = self.run_case(variables)
            self.assertEqual(result.returncode, 0, result.stdout)
            self.assertNotIn('apple:--list', calls)
            self.assertEqual(self.installs(calls), [])
            self.assertEqual([c for c in calls if c.startswith('brew:doctor check')], ['brew:doctor ' + c for c in REQUIRED])

    def test_confirmed_repair_reverifies_and_repeated_healthy_run(self):
        for diagnostic, check in (('incompatible', 'check_if_supported_sdk_available'), ('minimum', 'check_clt_minimum_version')):
            result, calls = self.run_case({'DIAGNOSTIC': diagnostic, 'FAIL_CHECK': check},
                                          expression='ensure_macos_developer_tools_ready && ensure_macos_developer_tools_ready')
            self.assertEqual(result.returncode, 0, result.stdout)
            self.assertEqual(self.installs(calls), ['sudo:-n softwareupdate --install ' + LABEL + ' --verbose'])
            self.assertEqual(calls.count('apple:--list'), 1)
            self.assertEqual(calls.count('brew:doctor --list-checks'), 3)
            self.assertFalse(any(c.startswith('sentinel:') for c in calls))

    def test_unknown_unavailable_and_failed_checks_never_repair(self):
        cases = [{'DIAGNOSTIC': v} for v in ('crash', 'misleading', 'unknown warning')]
        cases += [{'DIAGNOSTIC': 'incompatible', 'DIAGNOSTIC_STATUS': '2'}, {'DISCOVERY_OK': '0'},
                  {'BREW_OK': '0'}, {'COMPILER_OK': '0'}, {'SELECT_OK': '0'}]
        cases += [{'CHECKS': '\n'.join(c for c in REQUIRED if c != missing)} for missing in REQUIRED]
        for variables in cases:
            with self.subTest(variables=variables):
                result, calls = self.run_case(variables)
                self.assertEqual(result.returncode, 1, result.stdout)
                self.assertIn('unverified', result.stdout)
                self.assertIn('https://developer.apple.com/download/all/', result.stdout)
                self.assertNotIn('apple:--list', calls)
                self.assertEqual(self.installs(calls), [])

    def test_ineligible_selections_and_secondary_verify_only(self):
        for variables, linked in (({'PERSONA': 'secondary'}, False), ({'SELECTED': '/Applications/Xcode.app/Contents/Developer'}, False),
                                  ({'DEVELOPER_DIR': '/custom/CLT'}, False), ({'DEVELOPER_DIR': ''}, False), ({}, True)):
            result, calls = self.run_case({'DIAGNOSTIC': 'incompatible', **variables}, linked=linked)
            self.assertEqual(result.returncode, 1, result.stdout)
            self.assertNotIn('apple:--list', calls)
            self.assertEqual(self.installs(calls), [])
            self.assertIn('Selected developer directory', result.stdout)
            self.assertIn('version: 26.0', result.stdout)
            self.assertIn('Apple clang version', result.stdout)
            if 'PERSONA' in variables:
                self.assertIn('machine owner', result.stdout)

    def test_no_malformed_ambiguous_or_failed_offer(self):
        for offer in ('No new software available.', '* Label: macOS 27', '* Label: Command Line Tools for Xcode-27 beta',
                      '* Label: Command Line Tools for Xcode-27;reboot', 'Command Line Tools for Xcode-27',
                      OFFER + '\n' + OFFER, OFFER + '\n* Label: Command Line Tools for Xcode-26.1',
                      '* Label: Command Line Tools for Xcode-27\x1b', '* Label: Command Line Tools unknown'):
            result, calls = self.run_case({'DIAGNOSTIC': 'incompatible', 'UPDATES': offer})
            self.assertEqual(result.returncode, 1, result.stdout)
            self.assertIn('no-safe-offer', result.stdout)
            self.assertEqual(self.installs(calls), [])
            self.assertNotIn('sudo:cached', calls)
        result, calls = self.run_case({'DIAGNOSTIC': 'incompatible', 'QUERY_OK': '0'})
        self.assertIn('query-failed', result.stdout)
        self.assertIn('not an empty offer', result.stdout)
        self.assertEqual(self.installs(calls), [])

    def test_privilege_tty_headless_and_expiry(self):
        for terminal in (False, True):
            for headless in ('', '0', '1', 'true'):
                for cached in ('0', '1'):
                    for auth in ('0', '1'):
                        values = {'DIAGNOSTIC': 'incompatible', 'HEADLESS': headless, 'CACHED': cached, 'AUTH_OK': auth}
                        result, calls = self.run_case(values, terminal=terminal)
                        prompt = cached == '0' and terminal and headless != '1'
                        success = cached == '1' or prompt and auth == '1'
                        self.assertEqual(calls.count('sudo:auth'), int(prompt), (values, terminal, calls))
                        self.assertEqual(len(self.installs(calls)), int(success))
                        self.assertEqual(result.returncode, int(not success), result.stdout)
        result, calls = self.run_case({'DIAGNOSTIC': 'incompatible', 'CACHED': '0', 'INSTALL_EXPIRE': '1'}, terminal=True)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(calls.count('sudo:auth'), 1)
        self.assertEqual(len(self.installs(calls)), 1)
        self.assertIn('sudo:-n softwareupdate --install ' + LABEL + ' --verbose', calls)

    def test_changed_selection_before_or_after_install(self):
        for key, count in (('DIAGNOSTIC_CHANGE', 0), ('QUERY_CHANGE', 0), ('INSTALL_CHANGE', 1)):
            result, calls = self.run_case({'DIAGNOSTIC': 'incompatible', key: '1'})
            self.assertEqual(result.returncode, 1)
            self.assertIn('selection-changed', result.stdout)
            self.assertEqual(len(self.installs(calls)), count)

    def test_discovery_failure_stays_failed_after_later_healthy_verification(self):
        result, calls = self.run_case({'DISCOVERY_OK': '0'}, expression='''
ensure_macos_developer_tools_ready
DISCOVERY_OK=1
ensure_macos_developer_tools_ready
''')
        self.assertEqual(result.returncode, 1)
        self.assertEqual(self.installs(calls), [])
        self.assertIn('passed', result.stdout)

    def test_install_failure_stays_failed_even_if_ready(self):
        result, calls = self.run_case({'DIAGNOSTIC': 'incompatible', 'INSTALL_OK': '0'})
        self.assertEqual(result.returncode, 1)
        self.assertEqual(calls.count('brew:doctor --list-checks'), 2)
        self.assertIn('passed', result.stdout)
        self.assertEqual(len(self.installs(calls)), 1)

    def test_success_without_readiness_never_retries(self):
        result, calls = self.run_case({'DIAGNOSTIC': 'incompatible', 'RECOVERS': '0'},
                                      expression='ensure_macos_developer_tools_ready; ensure_macos_developer_tools_ready')
        self.assertEqual(result.returncode, 1)
        self.assertEqual(len(self.installs(calls)), 1)
        self.assertIn('attempt-exhausted', result.stdout)

    def test_actual_caller_suppresses_all_dependents_but_continues(self):
        dependent = ('install_core_packages', 'install_sessionwatcher', 'install_secrets_manager', 'install_gcloud_cli',
                     'setup_tailscale', 'install_nerd_font', 'install_betterdisplay', 'install_codex_cli',
                     'install_gitea_client', 'update_brew', 'install_tmux_plugins', 'install_sfw', 'install_gemini_cli',
                     'install_portless_cli', 'setup_bb_machine', 'setup_matt_pocock_skills', 'install_pi_cli',
                     'refresh_pi_packages')
        for persona in ('primary', 'secondary'):
            for diagnostic in ('incompatible', 'crash'):
                result, calls = self.run_case({'PERSONA': persona, 'DIAGNOSTIC': diagnostic, 'UPDATES': '',
                                              'MISSING': 'git chezmoi mise jq fish node', 'DOTFILES_ACCESS': '1'}, caller=True)
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                for name in dependent + ('initialize_chezmoi', 'retire_global_backlog_mcp', 'prepare_pi_profile_permissions'):
                    self.assertNotIn('work:' + name, calls)
                for name in ('install_bun', 'install_claude_code', 'install_ntn_cli', 'remove_impeccable_resources', 'remove_compound_engineering_resources'):
                    self.assertIn('work:' + name, calls)
                self.assertEqual(calls.count('reboot'), 1)
                self.assertEqual(calls.count('final:1'), 1)
                self.assertIn('Skipped dependent work:', result.stdout)
                self.assertIn('Setup completed with errors', result.stdout)
                if persona == 'primary':
                    for name in ('block_public_upload_services', 'enable_ssh', 'configure_power_settings', 'enable_screen_sharing'):
                        self.assertIn('work:' + name, calls)

    def test_actual_caller_unresolved_matrix_always_finalizes_once(self):
        cases = ({'QUERY_OK': '0'}, {'RECOVERS': '0'}, {'INSTALL_EXPIRE': '1'},
                 {'DISCOVERY_OK': '0'}, {'CHECKS': REQUIRED[0]}, {'SELECT_OK': '0'}, {'COMPILER_OK': '0'},
                 {'SELECTED': '/Applications/Xcode.app/Contents/Developer'}, {'DEVELOPER_DIR': '/custom/Xcode'},
                 {'QUERY_CHANGE': '1'}, {'CACHED': '0', 'HEADLESS': '1'})
        for variables in cases:
            with self.subTest(variables=variables):
                result, calls = self.run_case({'DIAGNOSTIC': 'incompatible', **variables}, caller=True)
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                for name in ('install_core_packages', 'setup_tailscale', 'install_codex_cli', 'install_gitea_client',
                             'update_brew', 'initialize_chezmoi', 'setup_bb_machine', 'install_pi_cli'):
                    self.assertNotIn('work:' + name, calls)
                self.assertIn('work:install_bun', calls)
                self.assertIn('work:remove_compound_engineering_resources', calls)
                self.assertEqual(calls.count('reboot'), 1)
                self.assertEqual(calls.count('final:1'), 1)
                self.assertLessEqual(len(self.installs(calls)), 1)

    def test_independent_installer_prerequisites_are_not_assumed(self):
        result, calls = self.run_case({'DIAGNOSTIC': 'crash', 'PROBE_FAIL': 'curl'}, caller=True)
        self.assertEqual(result.returncode, 1)
        for name in ('install_bun', 'install_claude_code', 'install_ntn_cli'):
            self.assertNotIn('work:' + name, calls)
        self.assertIn('work:remove_compound_engineering_resources', calls)
        self.assertEqual(calls.count('final:1'), 1)

    def test_existing_independent_prerequisites_allow_safe_work(self):
        result, calls = self.run_case({'DIAGNOSTIC': 'crash', 'DOTFILES_ACCESS': '1'}, caller=True)
        self.assertEqual(result.returncode, 1)
        # A full dotfiles apply executes run scripts: installed binaries alone
        # do not prove that those scripts are independent of developer tools.
        self.assertNotIn('work:initialize_chezmoi', calls)
        for name in ('retire_global_backlog_mcp', 'prepare_pi_profile_permissions',
                     'remove_rtk_resources', 'remove_attention_span_resources', 'remove_simple_english_skill',
                     'remove_show_me_skill', 'remove_pr_lens_skill'):
            self.assertIn('work:' + name, calls)
        result, calls = self.run_case({'DIAGNOSTIC': 'crash', 'PROBE_FAIL': 'git', 'DOTFILES_ACCESS': '1'}, caller=True)
        self.assertNotIn('work:retire_global_backlog_mcp', calls)  # PATH presence is insufficient.
        self.assertEqual(calls.count('final:1'), 1)

    def test_caller_recovery_preserves_operations_and_earlier_failures(self):
        for variables, status in (({}, 0), ({'EARLIER_FAILURE': '1'}, 1), ({'INSTALL_OK': '0'}, 1)):
            result, calls = self.run_case({'DIAGNOSTIC': 'incompatible', **variables}, caller=True)
            self.assertEqual(result.returncode, status, result.stdout + result.stderr)
            self.assertIn('work:install_codex_cli', calls)
            self.assertIn('work:setup_tailscale', calls)
            self.assertEqual(calls.count('final:' + str(status)), 1)
            self.assertEqual(calls.count('reboot'), 1)
            self.assertEqual(len(self.installs(calls)), 1)
            self.assertIn('work:update_brew', calls)
        # An operation failure cannot be cleared by a later healthy verification.
        result, _ = self.run_case({'DIAGNOSTIC': 'incompatible', 'QUERY_OK': '0'}, expression='''
ensure_macos_developer_tools_ready
DIAGNOSTIC=ready
ensure_macos_developer_tools_ready
''')
        self.assertEqual(result.returncode, 1)

    def test_fresh_bootstrap_is_separate_and_cleanup_failure_permanent(self):
        for failure in ('', 'QUERY_OK', 'INSTALL_OK', 'CLEAN_OK', 'CREATE_OK'):
            values = {'INITIAL': '1', 'BREW_OK': '0'}
            if failure: values[failure] = '0'
            result, calls = self.run_case(values, caller=True, existing=False)
            self.assertEqual(result.returncode, int(bool(failure)), (failure, result.stdout, result.stderr))
            self.assertEqual(calls.count('final:' + str(int(bool(failure)))), 1)
            self.assertEqual(calls.count('reboot'), 1)
            self.assertLess(calls.index('sentinel:create'), calls.index('brew-bootstrap'))
            if failure not in ('QUERY_OK', 'CREATE_OK'):
                self.assertLess(next(i for i, c in enumerate(calls) if 'softwareupdate --install' in c), calls.index('brew-bootstrap'))
            if failure == 'CLEAN_OK':
                self.assertIn('work:install_codex_cli', calls)
            self.assertLessEqual(len(self.installs(calls)), 1)
        result, calls = self.run_case({'INITIAL': '1', 'PERSONA': 'secondary'}, caller=True, existing=False)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(self.installs(calls), [])
        self.assertNotIn('sentinel:create', calls)
        self.assertIn('machine owner', result.stdout)

    def test_unready_fresh_bootstrap_does_not_install_twice(self):
        result, calls = self.run_case({'INITIAL': '1', 'DIAGNOSTIC': 'incompatible', 'RECOVERS': '0'},
                                      caller=True, existing=False)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(len(self.installs(calls)), 1)
        self.assertNotIn('work:install_codex_cli', calls)
        self.assertIn('rather than installing again', result.stdout)

    def test_healthy_primary_and_secondary_callers(self):
        for persona in ('primary', 'secondary'):
            result, calls = self.run_case({'PERSONA': persona, 'DOTFILES_ACCESS': '1'}, caller=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            for name in ('initialize_chezmoi', 'install_pi_cli', 'setup_bb_machine', 'install_codex_cli', 'install_bun'):
                self.assertIn('work:' + name, calls)
            self.assertEqual(self.installs(calls), [])
            self.assertNotIn('apple:--list', calls)
            self.assertEqual(calls.count('reboot'), 1)
            self.assertEqual(calls.count('final:0'), 1)

    def test_existing_tools_without_selection_never_bootstrap(self):
        result, calls = self.run_case({'SELECT_OK': '0'}, expression='install_xcode_cli_tools')
        self.assertEqual(result.returncode, 1)
        self.assertIn('Select a trusted installation manually', result.stdout)
        self.assertEqual(self.installs(calls), [])
        self.assertNotIn('sentinel:create', calls)

    def test_homebrew_absent_bootstrap_guard_is_real(self):
        helper = function('install_homebrew').replace('/Library/Developer/CommandLineTools', '${HOME}/bootstrap-clt')
        helper = helper.replace('/opt/homebrew/bin/brew', '${HOME}/bootstrap-brew')
        for variables in ({'SELECT_OK': '0'}, {}, {'SELECTED': '/Applications/Xcode.app/Contents/Developer'}):
            result, calls = self.run_case({'BREW_OK': '0', **variables}, expression=helper + '\ninstall_homebrew')
            self.assertEqual(result.returncode, 1)
            self.assertIn('Skipping Homebrew bootstrap', result.stdout)
            self.assertEqual(self.installs(calls), [])
            self.assertNotIn('sudo:auth', calls)
        # Exercise the real positive installer/shellenv ordering too. The only
        # downloaded script is this inert temporary executable, never Homebrew.
        fixture = r'''
mkdir -p "$HOME/bootstrap-clt/usr/bin"
printf '#!/bin/bash\nexit 0\n' > "$HOME/bootstrap-clt/usr/bin/git"
chmod +x "$HOME/bootstrap-clt/usr/bin/git"
curl() {
    printf 'brew-download\n' >> "$HOME/calls"
    printf '%s\n' 'printf "#!/bin/bash\\nexit 0\\n" > "$HOME/bootstrap-brew"; chmod +x "$HOME/bootstrap-brew"'
}
install_homebrew && { BREW_OK=1; ensure_macos_developer_tools_ready; }
'''
        result, calls = self.run_case({'BREW_OK': '0'}, expression=helper + '\n' + fixture, terminal=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertLess(calls.index('brew-download'), calls.index('brew:doctor --list-checks'))
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
