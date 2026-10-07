import functools
import plistlib
import re
import shlex
import subprocess
import unittest

import extract_setup_fixture
import test_bb_desktop as desktop


@functools.lru_cache(None)
def caller_fixture(entry):
    source = extract_setup_fixture.definitions((desktop.ROOT / (entry + '.sh')).read_text())
    names = set(re.findall(r'^([a-zA-Z_][a-zA-Z_0-9]*)\(\)\s*\{', source, re.M))
    retained = ('run_setup_tasks', 'main', 'install_bb_desktop')
    blocks = []
    for name in retained:
        start = source.index('\n' + name + '() {\n') + 1
        block = source[start:source.index('\n}\n', start) + 3]
        extract_setup_fixture.validate_function(block)
        blocks.append(block)
    stubs = '\n'.join(name + '() { :; }' for name in names if name not in retained)
    return stubs + '\n' + '\n'.join(blocks)


class DesktopCallers(unittest.TestCase):
    setUp = desktop.DesktopTests.setUp
    tearDown = desktop.DesktopTests.tearDown
    fetch = desktop.DesktopTests.fetch
    command = desktop.DesktopTests.command

    def run_entry(self, entry, number='1.2.3', independent=False, failure='', headless='0'):
        platform = 'macos' if entry == 'mac' else 'linux'
        script = caller_fixture(entry) + '''
check_dotfiles_access() { return 1; }
setup_dotfiles_deploy_key() { return 1; }
is_main_user() { return 0; }
whoami() { printf 'fixture-account\\n'; }
print_debug() { printf 'debug:%s\\n' "$*"; }
print_success() { printf 'success:%s\\n' "$*"; }
print_warning() { printf 'warning:%s\\n' "$*"; }
print_error() { printf 'error:%s\\n' "$*"; }
uname() { case "$1" in -s) printf '%s\\n' "$SYSTEM";; -m) printf '%s\\n' "$ARCH";; -r) printf 'native\\n';; esac; }
install_xcode_cli_tools() { return "$INDEPENDENT_FAILURE"; }
update_dependencies() { return "$INDEPENDENT_FAILURE"; }
install_secrets_manager() { return "$INDEPENDENT_FAILURE"; }
install_ntn_cli() { printf 'independent-work\\n'; }
check_pending_reboot() { printf 'reboot-reported\\n'; }
finish_setup_log() { printf 'final:%s\\n' "$1"; return "$1"; }
'''
        driver = desktop.ROOT / 'tests/fixtures/bb-desktop-operation.py'
        script += 'bb_desktop_payload() { /usr/bin/python3 -I -B ' + shlex.quote(str(driver)) + ' ' + entry + ' "$1"; }\nmain\n'
        result = subprocess.run(['/bin/bash', '--noprofile', '--norc', '-c', script], env={
            'PATH': '/usr/bin:/bin', 'HOME': str(self.home), 'SHELL': '/bin/bash',
            'SYSTEM': 'Darwin' if platform == 'macos' else 'Linux',
            'ARCH': 'arm64' if platform == 'macos' else 'x86_64',
            'WORK_MACHINE': '1', 'HEADLESS': headless, 'BB_SERVER': '0',
            'DESKTOP_FIXTURE_VERSION': number, 'DESKTOP_FIXTURE_FAILURE': failure,
            'INDEPENDENT_FAILURE': str(int(independent)), 'PYTHONDONTWRITEBYTECODE': '1',
        }, text=True, capture_output=True)
        expected_status = int(independent or (bool(failure) and headless != '1'))
        self.assertEqual(result.returncode, expected_status, result.stdout + result.stderr)
        self.assertIn('independent-work', result.stdout)
        self.assertIn('reboot-reported', result.stdout)
        self.assertEqual(result.stdout.count('final:'), 1)
        return result.stdout

    def layout(self, entry, mode):
        if entry == 'mac':
            paths = [self.home, self.home / 'Applications']
        else:
            paths = [self.home, self.home / '.local', self.home / '.local/opt',
                     self.home / '.local/opt/bb-desktop', self.home / '.local/share',
                     self.home / '.local/share/applications']
        for path in paths:
            path.mkdir(parents=True, exist_ok=True)
            path.chmod(mode)
        return {path: (path.stat().st_uid, path.stat().st_gid, path.stat().st_mode) for path in paths}

    def assert_version(self, entry, number):
        if entry == 'mac':
            info = self.home / 'Applications/bb.app/Contents/Info.plist'
            self.assertEqual(plistlib.loads(info.read_bytes())['CFBundleShortVersionString'], number)
        else:
            self.assertEqual(self.target.read_bytes(), desktop.appimage(number))
            self.assertIn('--appimage-extract-and-run', self.menu.read_text())

    def test_ordinary_callers_install_update_current_without_normalizing_directories(self):
        for entry in ('mac', 'ubuntu', 'bazzite'):
            for mode in (0o700, 0o755, 0o775, 0o2775):
                with self.subTest(entry=entry, mode=oct(mode)):
                    before = self.layout(entry, mode)
                    for number in ('1.2.3', '2.0.0'):
                        result = self.run_entry(entry, number)
                        self.assertIn('final:0', result)
                        self.assert_version(entry, number)
                        result = self.run_entry(entry, number)
                        self.assertIn('already current and verified', result)
                        self.assertIn('final:0', result)
                        if entry != 'mac':
                            self.assertIn('GUI/sandbox launch compatibility remains unverified', result)
                    result = self.run_entry(entry, '1.0.0')
                    self.assertIn('Newer verified bb desktop preserved', result)
                    self.assertIn('final:0', result)
                    self.assertEqual(before, {p: (p.stat().st_uid, p.stat().st_gid, p.stat().st_mode) for p in before})
                    if entry == 'mac':
                        desktop.shutil.rmtree(self.home / 'Applications/bb.app')
                    else:
                        self.target.unlink()
                        self.menu.unlink()

    def test_independent_and_real_desktop_failures_survive_reboot_and_final_logging(self):
        for entry in ('mac', 'ubuntu', 'bazzite'):
            with self.subTest(entry=entry):
                before = self.layout(entry, 0o775)
                result = self.run_entry(entry, independent=True)
                self.assertIn('installed and verified', result)
                self.assertIn('final:1', result)
                self.assert_version(entry, '1.2.3')
                result = self.run_entry(entry, '2.0.0', failure='integrity')
                self.assertIn('failed:integrity-mismatch', result)
                self.assertIn('final:1', result)
                self.assert_version(entry, '1.2.3')
                self.assertEqual(before, {p: (p.stat().st_uid, p.stat().st_gid, p.stat().st_mode) for p in before})
                if entry != 'mac':
                    self.target.unlink()
                    self.menu.unlink()

    def test_exact_headless_skips_real_operation_with_unsafe_layout_untouched(self):
        for entry in ('mac', 'ubuntu', 'bazzite'):
            before = self.layout(entry, 0o777)
            result = self.run_entry(entry, failure='integrity', headless='1')
            self.assertIn('Skipping bb desktop: HEADLESS=1', result)
            self.assertIn('final:0', result)
            self.assertFalse(self.target.exists())
            self.assertFalse((self.home / 'Applications/bb.app').exists())
            self.assertEqual(before, {p: (p.stat().st_uid, p.stat().st_gid, p.stat().st_mode) for p in before})


if __name__ == '__main__':
    unittest.main()
