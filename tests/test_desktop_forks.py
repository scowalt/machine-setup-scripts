import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

from extract_setup_fixture import validate_function
from test_bb_desktop_callers import caller_fixture

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'mac.sh').read_text()
FUNCTIONS = ('bb_desktop_fork_archive_url', 'omacal_fork_archive_url', 'unpack_fork_application',
             'install_fork_application', 'install_desktop_forks')
BB_FEED = 'https://github.com/scowalt/bb/releases/latest/download/latest-mac.yml'
BB_ARCHIVE = 'https://github.com/scowalt/bb/releases/latest/download/bb-0.48.1-fork.2-arm64.zip'
OMACAL_ARCHIVE = 'https://github.com/scowalt/omacal/releases/latest/download/omacal-fork-aarch64.app.zip'
FEED = '''version: 0.48.1-fork.2
files:
  - url: bb-0.48.1-fork.2-arm64.zip
    sha512: oeTncl79swNtgINo8xsQTNOIrmos7g5N9c9T0dRzRVOGFch4Q0Y4E3b3rUtNcnshT/l6jp8JPmjzz1ZkW3Hp8A==
    size: 198453345
  - url: bb-0.48.1-fork.2-arm64.dmg
    sha512: n/YoJaIYho55bqgzUJxbwQTgWvdIqUvzfjncamvxNyURCffQxHcB/2OAo+5wJDHOL0eVS9JlIZP2pC+fa0kXQA==
    size: 200389627
path: bb-0.48.1-fork.2-arm64.zip
sha512: oeTncl79swNtgINo8xsQTNOIrmos7g5N9c9T0dRzRVOGFch4Q0Y4E3b3rUtNcnshT/l6jp8JPmjzz1ZkW3Hp8A==
releaseDate: 2026-11-01T01:45:29.804Z
minimumSystemVersion: 22.0.0
'''
MOCKS = r'''
print_message() { printf 'message:%s\n' "$*"; }
print_success() { printf 'success:%s\n' "$*"; }
print_debug() { printf 'debug:%s\n' "$*"; }
print_error() { printf 'error:%s\n' "$*"; }
print_warning() { printf 'warning:%s\n' "$*"; }
curl() {
    local arg previous='' out='' url=''
    for arg in "$@"; do
        [[ "${previous}" != -o ]] || out="${arg}"
        previous="${arg}"
        url="${arg}"
    done
    printf 'curl:%s\n' "${url}" >> "${CALLS}"
    printf '%s\n' "$*" >> "${ARGS}"
    case "${url}" in
        */scowalt/bb/releases/latest/download/latest-mac.yml)
            [[ "${FAIL:-}" != feed ]] || return 22
            cat "${FEED_FILE}" ;;
        */scowalt/bb/releases/latest/download/bb-*-arm64.zip)
            [[ "${FAIL:-}" != bb-download ]] || return 22
            printf 'bb\n' > "${out}" ;;
        */scowalt/omacal/releases/latest/download/omacal-fork-aarch64.app.zip)
            [[ "${FAIL:-}" != omacal-download ]] || return 22
            printf 'omacal\n' > "${out}" ;;
        *) printf 'unexpected:url:%s\n' "${url}" >> "${CALLS}"; return 90 ;;
    esac
}
/usr/bin/ditto() {
    local kind app executable identifier
    printf 'ditto:%s\n' "${1} ${2}" >> "${CALLS}"
    [[ "${1} ${2}" == '-x -k' ]] || return 90
    kind=$(cat "${3}")
    [[ "${FAIL:-}" != "unpack-${kind}" ]] || return 1
    case "${kind}" in
        bb) app=bb.app; executable=bb; identifier=dev.bb.desktop ;;
        omacal) app=OmaCal.app; executable=omacal; identifier=com.omacal.app ;;
        *) return 90 ;;
    esac
    [[ "${FAIL:-}" != "wrong-id-${kind}" ]] || identifier=com.example.other
    mkdir -p "${4}/${app}/Contents/MacOS"
    printf 'CFBundleIdentifier=%s\nCFBundleExecutable=%s\n' "${identifier}" "${executable}" > "${4}/${app}/Contents/Info.plist"
    if [[ "${FAIL:-}" != "no-executable-${kind}" ]]; then
        printf '#!/bin/sh\n' > "${4}/${app}/Contents/MacOS/${executable}"
        /bin/chmod 755 "${4}/${app}/Contents/MacOS/${executable}"
    fi
}
/usr/libexec/PlistBuddy() {
    [[ "${1}" == -c && -f "${3}" ]] || return 1
    sed -n "s/^${2#Print :}=//p" "${3}" | head -n 1 | grep .
}
/usr/sbin/sysctl() {
    [[ "$*" == '-n hw.optional.arm64' ]] || return 90
    [[ "${ARM64:-1}" != missing ]] || return 1
    printf '%s\n' "${ARM64:-1}"
}
mv() {
    if [[ "${FAIL:-}" == move-bb && "${2}" == */bb.app ]] || [[ "${FAIL:-}" == move-omacal && "${2}" == */OmaCal.app ]]; then
        printf 'mv-failed:%s\n' "${2##*/}" >> "${CALLS}"
        return 1
    fi
    command mv "$@"
}
for forbidden in open sudo xattr codesign spctl launchctl killall pkill brew chmod chown softwareupdate; do
    eval "${forbidden}() { printf 'unexpected:${forbidden}:%s\n' \"\$*\" >> \"\${CALLS}\"; return 90; }"
done
'''


def function(name):
    block = re.search(rf'^{name}\(\) \{{\n.*?^\}}', SOURCE, re.M | re.S)[0]
    validate_function(block)
    return block


class Fixture(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='desktop-forks-')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.home = self.root / 'home'
        self.system = self.root / 'Applications'
        self.user = self.home / 'Applications'
        self.tmp = self.root / 'tmp'
        for directory in (self.home, self.system, self.tmp):
            directory.mkdir()
        self.calls = self.root / 'calls'
        self.args = self.root / 'curl-arguments'
        self.feed = self.root / 'feed.yml'
        self.feed.write_text(FEED)

    def forks(self):
        body = '\n'.join(function(name) for name in FUNCTIONS)
        needle = 'local _system_apps="/Applications"'
        self.assertEqual(body.count(needle), 1)
        return body.replace(needle, f'local _system_apps="{self.system}"')

    def execute(self, script, **variables):
        env = {'PATH': '/usr/bin:/bin', 'HOME': str(self.home), 'TMPDIR': str(self.tmp),
               'CALLS': str(self.calls), 'ARGS': str(self.args), 'FEED_FILE': str(self.feed), **variables}
        result = subprocess.run(['/bin/bash', '--noprofile', '--norc', '-c', script],
                                env=env, cwd=self.root, stdin=subprocess.DEVNULL, text=True,
                                capture_output=True, timeout=30)
        calls = self.calls.read_text().splitlines() if self.calls.exists() else []
        output = result.stdout + result.stderr
        self.assertEqual([c for c in calls if c.startswith('unexpected')], [], output)
        self.assertNotIn('command not found', output)
        self.assertEqual(list(self.tmp.iterdir()), [], 'staging directory must not outlive the installer')
        return result, calls

    def run_installer(self, **variables):
        return self.execute(MOCKS + self.forks() + '\ninstall_desktop_forks', **variables)

    def archives(self, calls):
        return [c for c in calls if c.startswith('curl:') and c.endswith('.zip')]


class DesktopForks(Fixture):
    def test_headless_flag_exactly_one_skips_before_any_effect(self):
        result, calls = self.run_installer(HEADLESS='1')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(calls, [])
        self.assertEqual(list(self.system.iterdir()), [])
        self.assertFalse(self.user.exists())
        self.assertIn('Headless machine', result.stdout)

    def test_every_other_headless_value_is_a_headed_machine(self):
        for value in (None, '', '0', 'true', 'false', '01', ' 1', '1 '):
            with self.subTest(value=value):
                for path in (*self.system.iterdir(), *self.tmp.iterdir()):
                    subprocess.run(['/bin/rm', '-rf', str(path)], check=True)
                if self.calls.exists():
                    self.calls.unlink()
                result, calls = self.run_installer(**({} if value is None else {'HEADLESS': value}))
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(sorted(p.name for p in self.system.iterdir()), ['OmaCal.app', 'bb.app'])

    def test_fresh_install_downloads_only_from_the_owner_forks_and_places_both_bundles(self):
        result, calls = self.run_installer()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual([c for c in calls if c.startswith('curl:')],
                         ['curl:' + BB_FEED, 'curl:' + BB_ARCHIVE, 'curl:' + OMACAL_ARCHIVE])
        self.assertEqual(calls.count('ditto:-x -k'), 2)
        self.assertEqual(sorted(p.name for p in self.system.iterdir()), ['OmaCal.app', 'bb.app'])
        self.assertTrue((self.system / 'bb.app/Contents/MacOS/bb').exists())
        self.assertTrue((self.system / 'OmaCal.app/Contents/MacOS/omacal').exists())
        self.assertFalse(self.user.exists())
        self.assertIn(f'success:bb desktop installed to {self.system}.', result.stdout)
        self.assertIn(f'success:OmaCal installed to {self.system}.', result.stdout)
        self.assertLess(result.stdout.index('bb desktop installed'), result.stdout.index('OmaCal installed'))

    def test_every_request_fails_on_http_errors_and_cannot_hang(self):
        self.run_installer()
        feed, *archives = [line.split() for line in self.args.read_text().splitlines()]
        self.assertEqual(len(archives), 2)
        for words in (feed, *archives):
            self.assertIn('-fsSL', words)
            self.assertIn('--connect-timeout', words)
        self.assertIn('--max-time', feed)
        for words in archives:
            self.assertIn('--speed-limit', words)
            self.assertIn('--speed-time', words)
            self.assertNotIn('--max-time', words)

    def test_second_run_downloads_nothing_and_changes_nothing(self):
        self.run_installer()
        before = sorted(str(p.relative_to(self.system)) for p in self.system.rglob('*'))
        self.calls.unlink()
        result, calls = self.run_installer()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(calls, [])
        self.assertEqual(sorted(str(p.relative_to(self.system)) for p in self.system.rglob('*')), before)
        self.assertEqual(result.stdout.count('leaving it untouched'), 2)

    def test_existing_entries_in_either_applications_directory_are_never_touched(self):
        kinds = ('directory', 'file', 'symlink', 'dangling')
        for location in ('system', 'user'):
            for kind in kinds:
                with self.subTest(location=location, kind=kind):
                    base = self.system if location == 'system' else self.user
                    base.mkdir(exist_ok=True)
                    target = base / 'bb.app'
                    if kind == 'directory':
                        target.mkdir()
                        (target / 'owner-state').write_text('custom fork; preserve exactly\n')
                    elif kind == 'file':
                        target.write_text('custom fork; preserve exactly\n')
                    elif kind == 'symlink':
                        (base / 'owner-fork.app').mkdir()
                        target.symlink_to('owner-fork.app', target_is_directory=True)
                    else:
                        target.symlink_to('missing-owner-fork.app')
                    before = [(p.name, os.readlink(p) if p.is_symlink() else None) for p in sorted(base.iterdir())]
                    if self.calls.exists():
                        self.calls.unlink()
                    result, calls = self.run_installer()
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertEqual(self.archives(calls), ['curl:' + OMACAL_ARCHIVE])
                    self.assertNotIn('curl:' + BB_FEED, calls)
                    self.assertEqual([(p.name, os.readlink(p) if p.is_symlink() else None)
                                      for p in sorted(base.iterdir()) if p.name != 'OmaCal.app'], before)
                    if kind == 'directory':
                        self.assertEqual((target / 'owner-state').read_text(), 'custom fork; preserve exactly\n')
                    if kind == 'file':
                        self.assertEqual(target.read_text(), 'custom fork; preserve exactly\n')
                    subprocess.run(['/bin/rm', '-rf', str(self.system), str(self.user)], check=True)
                    self.system.mkdir()

    def test_both_applications_present_means_no_network_and_no_staging(self):
        for base, names in ((self.system, ('bb.app',)), (self.user, ('OmaCal.app',))):
            base.mkdir(exist_ok=True)
            for name in names:
                (base / name).mkdir()
        result, calls = self.run_installer()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(calls, [])

    def test_intel_macs_are_skipped_because_only_arm64_builds_exist(self):
        for value in ('missing', '0'):
            with self.subTest(value=value):
                result, calls = self.run_installer(ARM64=value)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(calls, [])
                self.assertEqual(list(self.system.iterdir()), [])
                self.assertIn('Apple Silicon only', result.stdout)

    @unittest.skipIf(os.geteuid() == 0, 'root bypasses directory write permission')
    def test_unwritable_system_applications_fall_back_to_the_user_applications_directory(self):
        self.system.chmod(0o555)
        self.addCleanup(self.system.chmod, 0o755)
        result, calls = self.run_installer()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(list(self.system.iterdir()), [])
        self.assertEqual(sorted(p.name for p in self.user.iterdir()), ['OmaCal.app', 'bb.app'])
        self.assertIn(f'success:bb desktop installed to {self.user}.', result.stdout)

    def test_failures_report_error_leave_nothing_partial_and_do_not_block_the_other_application(self):
        cases = (
            ('feed', 'bb.app', 'Failed to locate the bb desktop release.'),
            ('bb-download', 'bb.app', 'Failed to download bb desktop.'),
            ('unpack-bb', 'bb.app', 'Failed to unpack bb desktop.'),
            ('wrong-id-bb', 'bb.app', 'The bb desktop archive does not contain the expected application.'),
            ('no-executable-bb', 'bb.app', 'The bb desktop archive does not contain the expected application.'),
            ('move-bb', 'bb.app', 'Failed to move bb desktop into'),
            ('omacal-download', 'OmaCal.app', 'Failed to download OmaCal.'),
            ('unpack-omacal', 'OmaCal.app', 'Failed to unpack OmaCal.'),
            ('wrong-id-omacal', 'OmaCal.app', 'The OmaCal archive does not contain the expected application.'),
            ('no-executable-omacal', 'OmaCal.app', 'The OmaCal archive does not contain the expected application.'),
            ('move-omacal', 'OmaCal.app', 'Failed to move OmaCal into'),
        )
        for failure, bundle, message in cases:
            with self.subTest(failure=failure):
                subprocess.run(['/bin/rm', '-rf', str(self.system)], check=True)
                self.system.mkdir()
                if self.calls.exists():
                    self.calls.unlink()
                result, calls = self.run_installer(FAIL=failure)
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertIn('error:' + message, result.stdout)
                other = 'OmaCal.app' if bundle == 'bb.app' else 'bb.app'
                self.assertEqual([p.name for p in self.system.iterdir()], [other])

    def test_feed_paths_that_are_not_a_plain_arm64_zip_name_are_rejected_before_downloading(self):
        feeds = {
            'missing': 'version: 1\nfiles: []\n',
            'traversal': 'path: ../bb-1-arm64.zip\n',
            'nested': 'path: other/bb-1-arm64.zip\n',
            'wrong-architecture': 'path: bb-1-x64.zip\n',
            'wrong-extension': 'path: bb-1-arm64.dmg\n',
            'query': 'path: bb-1-arm64.zip?token=1\n',
            'quoted': 'path: "bb-1-arm64.zip"\n',
            'other-project': 'path: other-1-arm64.zip\n',
        }
        for name, text in feeds.items():
            with self.subTest(feed=name):
                self.feed.write_text(text)
                if self.calls.exists():
                    self.calls.unlink()
                subprocess.run(['/bin/rm', '-rf', str(self.system)], check=True)
                self.system.mkdir()
                result, calls = self.run_installer()
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertEqual(self.archives(calls), ['curl:' + OMACAL_ARCHIVE])
                self.assertIn('error:Failed to locate the bb desktop release.', result.stdout)
                self.assertEqual([p.name for p in self.system.iterdir()], ['OmaCal.app'])

    def test_work_machines_install_like_personal_machines(self):
        result, calls = self.run_installer(WORK_MACHINE='1')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(sorted(p.name for p in self.system.iterdir()), ['OmaCal.app', 'bb.app'])

    def test_installer_never_launches_elevates_or_repairs_anything(self):
        result, calls = self.run_installer()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual({c.split(':')[0] for c in calls}, {'curl', 'ditto'})


class Caller(Fixture):
    STUBS = r'''
check_dotfiles_access() { return 1; }
setup_dotfiles_deploy_key() { return 1; }
is_main_user() { return 0; }
whoami() { printf 'fixture-account\n'; }
fix_zsh_compaudit() { echo later-work; }
/opt/homebrew/bin/brew() { :; }
finish_setup_log() { printf 'final:%s\n' "$1"; return "$1"; }
'''

    def run_main(self, environment_file=None, secondary=False, **variables):
        if environment_file is not None:
            (self.home / '.env.local').write_text(environment_file)
        script = caller_fixture('mac') + MOCKS + self.forks() + self.STUBS
        script += '\nis_main_user() { return 1; }\n' if secondary else ''
        script += '\nmain\n'
        result = self.execute(script, **variables)
        self.assertIn('later-work', result[0].stdout)
        self.assertEqual(result[0].stdout.count('final:'), 1)
        return result

    def installed(self):
        return sorted(p.name for p in self.system.iterdir())

    def test_headed_machine_installs_both_applications_and_finishes_cleanly(self):
        result, calls = self.run_main()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('final:0', result.stdout)
        self.assertEqual(self.installed(), ['OmaCal.app', 'bb.app'])
        self.assertEqual(len(self.archives(calls)), 2)

    def test_secondary_accounts_get_the_applications_too(self):
        result, calls = self.run_main(secondary=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('Running secondary user setup', result.stdout)
        self.assertIn('final:0', result.stdout)
        self.assertEqual(self.installed(), ['OmaCal.app', 'bb.app'])

    def test_environment_file_alone_can_mark_the_machine_headless(self):
        result, calls = self.run_main('HEADLESS=1\n')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('final:0', result.stdout)
        self.assertEqual(calls, [])
        self.assertEqual(self.installed(), [])

    def test_process_flag_marks_the_machine_headless_without_an_environment_file(self):
        result, calls = self.run_main(HEADLESS='1')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(calls, [])
        self.assertEqual(self.installed(), [])

    def test_environment_file_overrides_a_headless_process_flag(self):
        result, calls = self.run_main('HEADLESS=0\n', HEADLESS='1')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.installed(), ['OmaCal.app', 'bb.app'])

    def test_install_failure_reaches_the_final_result_without_blocking_later_work(self):
        result, calls = self.run_main(FAIL='bb-download')
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn('final:1', result.stdout)
        self.assertIn('error:Failed to download bb desktop.', result.stdout)
        self.assertEqual(self.installed(), ['OmaCal.app'])

    def test_existing_applications_leave_setup_successful_and_untouched(self):
        for name in ('bb.app', 'OmaCal.app'):
            (self.system / name).mkdir()
            (self.system / name / 'owner-state').write_text('preserve exactly\n')
        result, calls = self.run_main()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(calls, [])
        for name in ('bb.app', 'OmaCal.app'):
            self.assertEqual((self.system / name / 'owner-state').read_text(), 'preserve exactly\n')


class Policy(unittest.TestCase):
    def test_only_the_owner_forks_are_referenced(self):
        body = '\n'.join(function(name) for name in FUNCTIONS)
        self.assertIn('github.com/scowalt/bb/releases/latest/download', body)
        self.assertIn('github.com/scowalt/omacal/releases/latest/download', body)
        for upstream in ('get-bb', 'x3me', 'desktop-latest', 'nightly'):
            self.assertNotIn(upstream, body)


if __name__ == '__main__':
    unittest.main(verbosity=2)
