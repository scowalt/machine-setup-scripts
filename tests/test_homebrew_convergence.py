import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

from extract_setup_fixture import validate_function

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'mac.sh').read_text()


def helpers(*names):
    blocks = []
    for name in names:
        match = re.search(rf'^{name}\(\) \{{\n.*?^\}}', SOURCE, re.M | re.S)
        if match:
            validate_function(match[0])
            blocks.append(match[0])
    return '\n'.join(blocks)


LOGGERS = '\n'.join(f'{name}() {{ printf "%s\\n" "$*"; }}' for name in
                    ('print_message', 'print_warning', 'print_error', 'print_success', 'print_debug'))


class HomebrewConvergence(unittest.TestCase):
    def core(self, app='valid', receipt=False, signature=0, race=False, inventory_failure=False, missing_other=False):
        with tempfile.TemporaryDirectory() as raw:
            home = Path(raw)
            bundle = home / 'Applications/1Password.app'
            bundle.parent.mkdir()
            if app == 'link':
                target = home / 'outside'; target.mkdir(); (target / 'sentinel').write_text('keep')
                bundle.symlink_to(target, target_is_directory=True)
            elif app == 'file':
                bundle.write_text('keep')
            elif app != 'absent':
                bundle.mkdir(); (bundle / 'sentinel').write_text('keep')
            code = helpers('verify_existing_1password_app', 'install_core_packages')
            code = code.replace('/Applications/1Password.app', str(bundle))
            code = code.replace('/usr/bin/codesign', 'fixture_codesign').replace('/usr/bin/stat', 'fixture_stat')
            packages = re.search(r'local packages=\((.*?)\)', code)[1]
            installed = [p for p in re.findall(r'"([^"]+)"', packages)
                         if p != '1password' and not (missing_other and p == 'gh')]
            code += '\n' + LOGGERS + r'''
ensure_brew_item_trusted() { return 0; }
fixture_stat() {
    printf 'stat\n' >> "${HOME}/probes"
    if [[ -f "${HOME}/raced" ]]; then printf 'changed\n'; else printf 'stable\n'; fi
}
fixture_codesign() {
    printf '%s\n' "$*" >> "${HOME}/probes"
    [[ "${RACE}" != 1 ]] || : > "${HOME}/raced"
    return "${SIGNATURE}"
}
brew() {
    printf '%s\n' "$*" >> "${HOME}/calls"
    case "$*" in
        'list --formula -1') printf '%s\n' "${INSTALLED}" ;;
        'list --cask -1')
            [[ "${INVENTORY_FAILURE}" != 1 ]] || return 1
            if [[ "${RECEIPT}" == 1 ]]; then printf '1password\n'; fi ;;
        'install gh') return 0 ;;
        'install 1password')
            if [[ -e "${HOME}/Applications/1Password.app" || -L "${HOME}/Applications/1Password.app" ]]; then
                printf "Error: 1password: It seems there is already an App at '/Applications/1Password.app'.\n"
                return 1
            fi ;;
        *) return 90 ;;
    esac
}
install_core_packages
'''
            result = subprocess.run(['/bin/bash', '-u', '-c', code], text=True, capture_output=True,
                                    env={'PATH': '/usr/bin:/bin', 'HOME': raw, 'INSTALLED': '\n'.join(installed),
                                         'SIGNATURE': str(signature), 'RACE': str(int(race)),
                                         'RECEIPT': str(int(receipt)), 'INVENTORY_FAILURE': str(int(inventory_failure))}, timeout=10)
            calls = (home / 'calls').read_text()
            probes = (home / 'probes').read_text() if (home / 'probes').exists() else ''
            if app == 'valid':
                self.assertEqual((bundle / 'sentinel').read_text(), 'keep')
            if app == 'link':
                self.assertEqual((home / 'outside/sentinel').read_text(), 'keep')
            self.assertEqual(result.stderr, '')
            return result, calls, probes

    def test_existing_signed_app_without_receipt_is_preserved_on_repeat(self):
        for _ in range(2):
            result, calls, probes = self.core()
            self.assertEqual(result.returncode, 0, result.stdout)
            self.assertNotIn('install 1password\n', calls)
            for requirement in ('--verify', '--deep', '--strict', 'anchor apple generic',
                                'com.1password.1password', '2BUA8C4S2C'):
                self.assertIn(requirement, probes)
            self.assertIn('preserv', result.stdout.lower())

    def test_absent_app_and_brew_registered_app_keep_native_behavior(self):
        for options, install in (({'app': 'absent'}, True), ({'receipt': True}, False)):
            result, calls, probes = self.core(**options)
            self.assertEqual(result.returncode, 0, result.stdout)
            self.assertEqual('install 1password\n' in calls, install)
            self.assertEqual(probes, '')

    def test_invalid_linked_and_changed_apps_fail_without_install_or_overwrite(self):
        for options in ({'signature': 1}, {'app': 'link'}, {'app': 'file'}, {'race': True}):
            with self.subTest(options=options):
                result, calls, _ = self.core(**options)
                self.assertEqual(result.returncode, 1, result.stdout)
                self.assertNotIn('install 1password\n', calls)
                self.assertIn('1password', result.stdout)

    def test_unverified_existing_app_does_not_stop_independent_packages(self):
        result, calls, _ = self.core(signature=1, missing_other=True)
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn('install gh\n', calls)
        self.assertNotIn('install 1password\n', calls)

    def test_failed_inventory_is_not_treated_as_absence(self):
        result, calls, _ = self.core(app='absent', inventory_failure=True)
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertNotIn('install ', calls)

    def doppler(self, legacy=False, dirty=False, referenced=False, remote='official', failure='', installed=True, work=False, native_git=False, state=''):
        with tempfile.TemporaryDirectory() as raw:
            home = Path(raw); tap = home / 'Library/Taps/dopplerhq/homebrew-cli'
            tap.mkdir(parents=True)
            if native_git:
                env = {**os.environ, 'HOME': raw, 'GIT_AUTHOR_NAME': 'Fixture', 'GIT_AUTHOR_EMAIL': 'fixture@example.invalid',
                       'GIT_COMMITTER_NAME': 'Fixture', 'GIT_COMMITTER_EMAIL': 'fixture@example.invalid'}
                def git(*args):
                    subprocess.run(['/usr/bin/git', '-C', str(tap), *args], env=env, check=True,
                                   stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                git('init', '-b', 'master')
                git('-c', 'commit.gpgsign=false', 'commit', '--allow-empty', '-m', 'inert fixture')
                git('remote', 'add', 'origin', 'https://github.com/DopplerHQ/homebrew-cli')
                git('update-ref', 'refs/remotes/origin/master', 'HEAD')
                git('symbolic-ref', 'refs/remotes/origin/HEAD', 'refs/remotes/origin/master')
                if dirty:
                    (tap / 'custom-file').write_text('preserve')
                if state == 'local-commit':
                    git('-c', 'commit.gpgsign=false', 'commit', '--allow-empty', '-m', 'preserve local commit')
                if state == 'ignored':
                    (tap / '.git/info/exclude').write_text('private-file\n')
                    (tap / 'private-file').write_text('preserve ignored file')
            else:
                (tap / '.git').mkdir()
                (tap / '.git/config').write_text('inert fixture')
                (tap / '.git/HEAD').write_text('inert fixture')
            if state == 'group-write':
                tap.chmod(0o775); (tap / '.git').chmod(0o775); (tap / '.git/config').chmod(0o664)
            if state == 'world-write':
                tap.chmod(0o777)
            if state == 'file-world-write':
                (tap / '.git/config').chmod(0o666)
            if state == 'linked-parent':
                parent = tap.parent; moved = parent.with_name('real-parent'); parent.rename(moved)
                parent.symlink_to(moved, target_is_directory=True)
            if state == 'worktree':
                (tap / '.git/config').unlink(); (tap / '.git/HEAD').unlink(); (tap / '.git').rmdir()
                (tap / '.git').write_text('gitdir: /do/not/follow')
            if legacy:
                (home / 'legacy').touch()
            tap_info = [{'name': 'dopplerhq/cli', 'installed': True, 'path': str(tap),
                         'remote': 'https://github.com/DopplerHQ/homebrew-cli' if remote == 'official' else 'https://example.invalid/custom'}]
            inventory = {'formulae': [], 'casks': [{'tap': 'dopplerhq/cli' if referenced else 'dopplerhq/doppler', 'token': 'doppler'}]}
            (home / 'tap.json').write_text(json.dumps(tap_info))
            (home / 'inventory.json').write_text('{' if state == 'malformed-inventory' else json.dumps(inventory))
            code = helpers('doppler_tap_git', 'doppler_tap_snapshot', 'retire_legacy_doppler_tap', 'ensure_brew_item_trusted',
                           'install_secrets_manager', 'list_unresolved_brew_outdated_items', 'update_brew')
            code += '\n' + LOGGERS + r'''
SETUP_BREW_TRUST_FAILURES=0
SETUP_TMUX_PINNED=0
install_setup_cleanup_traps() { :; }
report_unmanaged_untrusted_brew_items() { return 0; }
opencode_guarded_brew_upgrade() { brew upgrade; }
fixture_tap_git() {
    printf 'git %s\n' "$*" >> "${HOME}/calls"
    [[ "${FAILURE}" != git ]] || return 1
    case "$*" in
        *status*) [[ "${DIRTY}" != 1 ]] || printf '?? custom-file\n' ;;
        *rev-parse*) printf 'abc123\n' ;;
        *rev-list*) return 0 ;;
        *) return 90 ;;
    esac
}
if [[ "${NATIVE_GIT}" != 1 ]]; then
    doppler_tap_git() { fixture_tap_git "$@"; }
fi
command() {
    if [[ "$*" == '-v doppler' ]]; then [[ "${INSTALLED_DOPPLER}" == 1 ]]; else builtin command "$@"; fi
}
brew() {
    printf '%s\n' "$*" >> "${HOME}/calls"
    [[ "$*" != "${FAILURE}" ]] || return 1
    case "$*" in
        tap)
            printf 'dopplerhq/doppler\n'
            if [[ -f "${HOME}/legacy" ]]; then printf 'dopplerhq/cli\n'; fi ;;
        'tap dopplerhq/cli') : > "${HOME}/legacy" ;;
        'tap-info --json=v1 dopplerhq/cli') /bin/cat "${HOME}/tap.json" ;;
        'info --json=v2 --installed')
            if [[ "${STATE}" == 'mode-race' ]]; then chmod 775 "${HOME}/Library/Taps/dopplerhq/homebrew-cli"; fi
            /bin/cat "${HOME}/inventory.json" ;;
        'untap dopplerhq/cli')
            if [[ "${REFERENCED}" == 1 ]]; then printf 'uninstall-attempt\n'; return 99; fi
            local input
            if read -r input; then printf 'interactive-untap\n'; return 99; fi
            rm "${HOME}/legacy" ;;
        'trust --formula dopplerhq/cli/doppler'|'trust --cask dopplerhq/doppler/doppler'|'install --cask dopplerhq/doppler/doppler') return 0 ;;
        update)
            if [[ -f "${HOME}/legacy" ]]; then
                printf 'Error: Refusing automatic redirect from dopplerhq/cli to https://github.com/DopplerHQ/homebrew-doppler.git.\n' >&2
                return 1
            fi ;;
        'list --pinned'|'outdated --quiet'|'pin tmux'|'unpin tmux'|upgrade) return 0 ;;
        *) return 90 ;;
    esac
}
if [[ "${STATE}" == git-controls ]]; then
    export GIT_DIR="${HOME}/wrong-repository" GIT_WORK_TREE="${HOME}/wrong-worktree"
    export GIT_CONFIG_GLOBAL="${HOME}/wrong-config" GIT_CONFIG_COUNT=1
    export GIT_CONFIG_KEY_0=core.fsmonitor GIT_CONFIG_VALUE_0='do-not-execute-fixture-control'
fi
install_secrets_manager
setup_status=$?
update_brew
update_status=$?
[[ "${setup_status}" == 0 && "${update_status}" == 0 ]]
'''
            result = subprocess.run(['/bin/bash', '-u', '-c', code], text=True, capture_output=True,
                                    env={'PATH': '/usr/bin:/bin', 'HOME': raw, 'DIRTY': str(int(dirty)),
                                         'REFERENCED': str(int(referenced)), 'FAILURE': failure,
                                         'INSTALLED_DOPPLER': str(int(installed)), 'WORK_MACHINE': str(int(work)),
                                         'NATIVE_GIT': str(int(native_git)), 'STATE': state}, timeout=10)
            calls = (home / 'calls').read_text()
            self.assertNotIn('uninstall-attempt', result.stdout)
            self.assertNotIn('interactive-untap', result.stdout)
            return result, calls, (home / 'legacy').exists()

    def test_canonical_cask_does_not_reintroduce_redirecting_tap(self):
        result, calls, legacy = self.doppler()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn('tap dopplerhq/cli\n', calls)
        self.assertIn('trust --cask dopplerhq/doppler/doppler\n', calls)
        self.assertFalse(legacy)

    def test_unused_clean_legacy_tap_is_retired_before_update(self):
        result, calls, legacy = self.doppler(legacy=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('untap dopplerhq/cli\n', calls)
        self.assertLess(calls.index('untap dopplerhq/cli'), calls.index('update\n'))
        self.assertNotIn('--force', calls)
        self.assertFalse(legacy)

    def test_native_git_inspection_accepts_only_clean_unused_fixture_clone(self):
        for dirty in (False, True):
            result, calls, legacy = self.doppler(legacy=True, native_git=True, dirty=dirty)
            self.assertEqual(result.returncode, int(dirty), result.stdout + result.stderr)
            self.assertEqual(legacy, dirty)
            self.assertEqual('untap dopplerhq/cli\n' in calls, not dirty)

    def test_legacy_tap_paths_permissions_snapshots_and_local_commits_are_preserved(self):
        for state in ('world-write', 'file-world-write', 'linked-parent', 'worktree', 'mode-race', 'malformed-inventory', 'local-commit', 'ignored'):
            with self.subTest(state=state):
                result, calls, legacy = self.doppler(legacy=True, state=state, native_git=state in ('local-commit', 'ignored'))
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertNotIn('untap dopplerhq/cli\n', calls)
                self.assertTrue(legacy)
        result, calls, legacy = self.doppler(legacy=True, state='group-write')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(legacy)

    def test_native_git_inspection_ignores_inherited_git_controls(self):
        result, calls, legacy = self.doppler(legacy=True, native_git=True, state='git-controls')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('untap dopplerhq/cli\n', calls)
        self.assertFalse(legacy)

    def test_only_personal_canonical_cask_has_managed_trust_classification(self):
        code = helpers('report_unmanaged_untrusted_brew_items') + '\n' + LOGGERS + r'''
brew() {
    case "$*" in
        untrust) printf 'Untrusted casks:\n  dopplerhq/doppler/doppler\n' ;;
        'list --formula --full-name') return 0 ;;
        'list --cask -1') printf 'doppler\n' ;;
        *) return 90 ;;
    esac
}
report_unmanaged_untrusted_brew_items
'''
        with tempfile.TemporaryDirectory() as raw:
            for work in (False, True):
                result = subprocess.run(['/bin/bash', '-u', '-c', code], capture_output=True, text=True,
                                        env={'HOME': raw, 'PATH': '/usr/bin:/bin', 'WORK_MACHINE': str(int(work))}, timeout=10)
                self.assertEqual(result.returncode, int(work), result.stdout + result.stderr)
                self.assertEqual('Unmanaged Homebrew cask' in result.stdout, work)

    def test_uncertain_or_referenced_legacy_tap_is_preserved_and_fails(self):
        for options in ({'dirty': True}, {'referenced': True}, {'remote': 'custom'}, {'failure': 'git'},
                        {'failure': 'tap-info --json=v1 dopplerhq/cli'}, {'failure': 'info --json=v2 --installed'}):
            with self.subTest(options=options):
                result, calls, legacy = self.doppler(legacy=True, **options)
                self.assertEqual(result.returncode, 1, result.stdout)
                self.assertNotIn('untap dopplerhq/cli\n', calls)
                self.assertTrue(legacy)

    def test_install_trust_inventory_and_untap_failures_remain_failures(self):
        for options in ({'installed': False, 'failure': 'install --cask dopplerhq/doppler/doppler'},
                        {'failure': 'trust --cask dopplerhq/doppler/doppler'}, {'failure': 'tap'},
                        {'legacy': True, 'failure': 'untap dopplerhq/cli'}):
            with self.subTest(options=options):
                result, _, _ = self.doppler(**options)
                self.assertEqual(result.returncode, 1, result.stdout)

    def test_fresh_install_uses_cask_and_work_machine_is_untouched(self):
        result, calls, _ = self.doppler(installed=False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('install --cask dopplerhq/doppler/doppler', calls)
        result, calls, _ = self.doppler(work=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn('doppler', calls)


if __name__ == '__main__':
    os.umask(0o077)
    unittest.main()
