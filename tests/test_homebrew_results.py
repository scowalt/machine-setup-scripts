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
    if [[ "$*" == upgrade && "${WARN_CLT}" == 1 ]]; then
        printf 'Warning: Your Command Line Tools (CLT) does not support macOS 27.\n' >&2
    fi
    if [[ "$*" == "${FAIL_PHASE}" ]]; then return 7; fi
    if [[ "${FAIL_PHASE}" == pinned-postcheck && "$*" == 'list --pinned' ]] && grep -qx upgrade "${HOME}/brew-calls"; then return 7; fi
    case "$*" in
        'outdated --quiet') printf '%s\n' "${OUTDATED}" ;;
        'list --pinned') printf '%s\n' "${PINNED}" ;;
    esac
}
'''
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
                                         'MACOS_DEVELOPER_TOOLS_STATE': readiness, 'WARN_CLT': str(int(readiness != 'ready'))})
            calls_file = Path(home) / 'brew-calls'
            calls = calls_file.read_text().splitlines() if calls_file.exists() else []
        if readiness == 'ready':
            self.assertEqual(result.stderr, '')
        else:
            self.assertEqual(result.stderr, 'Warning: Your Command Line Tools (CLT) does not support macOS 27.\n')
        self.assertIn('reboot-checked', result.stdout)
        return result, calls

    def assert_incomplete(self, result):
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn('log-finalized=1', result.stdout)
        self.assertIn('Setup completed with errors', result.stdout)
        self.assertNotIn('✨ Setup complete!', result.stdout)

    def test_failed_upgrade_reaches_final_result_and_log(self):
        for readiness in ('ready', 'incompatible'):
            result, calls = self.run_setup('upgrade', readiness=readiness)
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

    def test_clt_warning_does_not_block_successful_upgrade_or_poison_final_result(self):
        for state in ('incompatible', 'unverified'):
            result, calls = self.run_setup(readiness=state)
            self.assertEqual(result.returncode, 0, result.stdout)
            self.assertIn('update', calls)
            self.assertIn('upgrade', calls)
            self.assertIn('outdated --quiet', calls)
            self.assertIn('Warning: Your Command Line Tools', result.stderr)
            self.assertIn('Homebrew updated.', result.stdout)
            self.assertEqual(result.stdout.count('log-finalized=0'), 1)

    def test_success_does_not_erase_an_earlier_failure(self):
        result, _ = self.run_setup(earlier=1)
        self.assert_incomplete(result)
        self.assertIn('Homebrew updated.', result.stdout)


if __name__ == '__main__':
    unittest.main()
