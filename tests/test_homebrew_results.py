"""Contract v4: ordinary Homebrew/OpenCode caller seams; no live setup/brew."""
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'mac.sh').read_text()


def function(name):
    return re.search(rf'^{name}\(\) \{{\n.*?^\}}', SOURCE, re.M | re.S)[0]


class HomebrewResults(unittest.TestCase):
    def run_setup(self, phase='', earlier=0, outdated='', pinned='', trust=0, readiness='ready'):
        tail = function('run_setup_tasks').split(
            '    if is_main_user; then\n        print_section "Final Updates"', 1)[1]
        script = r'''
set -eu
GREEN= BOLD= NC=
SETUP_TMUX_PINNED=0
SETUP_BREW_TRUST_FAILURES=0
print_message() { printf '%s\n' "$*"; }
print_warning() { printf '%s\n' "$*"; }
print_success() { printf '%s\n' "$*"; }
print_section() { :; }
is_main_user() { return 0; }
install_setup_cleanup_traps() { printf 'cleanup-armed\n'; }
report_unmanaged_untrusted_brew_items() { return "${TRUST}"; }
check_pending_reboot() { printf 'reboot-checked\n'; }
start_setup_log() { printf 'log-started\n'; }
finish_setup_log() { printf 'log-finalized=%s\n' "$1"; return "$1"; }
brew() {
    printf '%s\n' "$*" >> "${HOME}/brew-calls"
    if [[ "$*" == "${FAIL_PHASE}" ]]; then return 7; fi
    if [[ "${FAIL_PHASE}" == pinned-postcheck && "$*" == 'list --pinned' ]] && grep -qx upgrade "${HOME}/brew-calls"; then return 7; fi
    case "$*" in
        'outdated --quiet') printf '%s\n' "${OUTDATED}" ;;
        'list --pinned') printf '%s\n' "${PINNED}" ;;
    esac
}
'''
        script += '\n' + function('macos_developer_tools_ready_for')
        script += '\n' + function('macos_clt_summary')
        script += '\n' + function('list_unresolved_brew_outdated_items')
        script += '\n' + re.search(r'^opencode_guarded_brew_upgrade\(\) \(\n.*?^\)', SOURCE, re.M | re.S)[0]
        script += '\n' + function('update_brew')
        script += '\nrun_setup_tasks() {\nlocal _setup_had_errors=${EARLIER}\n'
        script += 'if is_main_user; then\n print_section "Final Updates"' + tail
        script += '\n' + function('main') + '\nmain\n'
        with tempfile.TemporaryDirectory() as home:
            result = subprocess.run(['bash', '-c', script], text=True, capture_output=True,
                                    env={'PATH': '/usr/bin:/bin', 'HOME': home,
                                         'FAIL_PHASE': phase, 'EARLIER': str(earlier),
                                         'OUTDATED': outdated, 'PINNED': pinned, 'TRUST': str(trust),
                                         'MACOS_DEVELOPER_TOOLS_STATE': readiness})
            calls_file = Path(home) / 'brew-calls'
            calls = calls_file.read_text().splitlines() if calls_file.exists() else []
        self.assertEqual(result.stderr, '')
        self.assertIn('reboot-checked', result.stdout)
        return result, calls

    def assert_incomplete(self, result):
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn('log-finalized=1', result.stdout)
        self.assertIn('Setup completed with errors', result.stdout)
        self.assertNotIn('✨ Setup complete!', result.stdout)

    def test_failed_upgrade_reaches_final_result_and_log(self):
        result, calls = self.run_setup('upgrade')
        self.assert_incomplete(result)
        self.assertIn('unpin tmux', calls)
        self.assertIn('upgrade=7', result.stdout)

    def test_unverified_postcheck_is_incomplete(self):
        for phase in ('outdated --quiet', 'list --pinned', 'pinned-postcheck'):
            with self.subTest(phase=phase):
                result, _ = self.run_setup(phase)
                self.assert_incomplete(result)
                self.assertIn('could not be verified', result.stdout)

    def test_other_failed_phases_and_cleanup(self):
        for phase in ('update', 'unpin tmux'):
            with self.subTest(phase=phase):
                result, calls = self.run_setup(phase)
                self.assert_incomplete(result)
                self.assertIn('upgrade', calls)
                self.assertIn('unpin tmux', calls)
                self.assertIn('cleanup-armed', result.stdout)

    def test_unpinned_outdated_and_trust_skips_are_incomplete(self):
        for options in ({'outdated': 'docker-desktop'}, {'trust': 1}):
            with self.subTest(options=options):
                result, _ = self.run_setup(**options)
                self.assert_incomplete(result)
                self.assertNotIn('Homebrew updated.', result.stdout)

    def test_success_and_intentional_exclusions(self):
        for options in ({}, {'outdated': 'tmux\nexample/pinned/tool', 'pinned': 'tool'}):
            with self.subTest(options=options):
                result, _ = self.run_setup(**options)
                self.assertEqual(result.returncode, 0, result.stdout)
                self.assertIn('Homebrew updated.', result.stdout)
                self.assertIn('log-finalized=0', result.stdout)

    def test_existing_user_tmux_pin_is_not_removed(self):
        result, calls = self.run_setup(pinned='tmux', outdated='tmux')
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertNotIn('pin tmux', calls)
        self.assertNotIn('unpin tmux', calls)
        self.assertNotIn('cleanup-armed', result.stdout)

    def test_unready_skips_all_final_brew_mutations_and_finalizes(self):
        for state in ('incompatible', 'unverified'):
            result, calls = self.run_setup(readiness=state)
            self.assert_incomplete(result)
            self.assertEqual(calls, [])
            self.assertIn('final Homebrew upgrades', result.stdout)
            self.assertEqual(result.stdout.count('log-finalized=1'), 1)

    def test_success_does_not_erase_an_earlier_failure(self):
        result, _ = self.run_setup(earlier=1)
        self.assert_incomplete(result)
        self.assertIn('Homebrew updated.', result.stdout)


if __name__ == '__main__':
    unittest.main()
