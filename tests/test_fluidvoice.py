from pathlib import Path
import re
import subprocess
import tempfile
import unittest

from extract_setup_fixture import validate_function

SOURCE = (Path(__file__).resolve().parents[1] / 'mac.sh').read_text()
MOCKS = r'''
print_message() { printf 'message:%s\n' "$*"; }
print_success() { printf 'success:%s\n' "$*"; }
print_debug() { printf 'debug:%s\n' "$*"; }
print_error() { printf 'error:%s\n' "$*"; }
brew() {
    printf 'brew:%s\n' "$*" >> "${CALLS}"
    case "$*" in
        'list --cask fluidvoice') [[ "${BREW_HAS:-0}" == 1 ]] ;;
        'install --cask fluidvoice') [[ "${INSTALL_OK:-1}" == 1 ]] ;;
        *) printf 'unexpected:brew\n' >> "${CALLS}"; return 90 ;;
    esac
}
sw_vers() {
    [[ "$*" == -productVersion ]] || return 90
    [[ -n "${MACOS:-}" ]] || return 1
    printf '%s\n' "${MACOS}"
}
for forbidden in open sudo curl xattr codesign launchctl killall; do
    eval "${forbidden}() { printf 'unexpected:${forbidden}\n' >> \"\${CALLS}\"; return 90; }"
done
'''


def function(name):
    block = re.search(rf'^{name}\(\) \{{\n.*?^\}}', SOURCE, re.M | re.S)[0]
    validate_function(block)
    return block


class FluidVoice(unittest.TestCase):
    def run_installer(self, **variables):
        with tempfile.TemporaryDirectory(prefix='fluidvoice-') as root:
            apps = Path(root) / 'Applications'
            apps.mkdir()
            if variables.pop('MANUAL_APP', False):
                (apps / 'FluidVoice.app').mkdir()
            body = function('install_fluidvoice')
            self.assertEqual(body.count('/Applications/FluidVoice.app'), 2)
            body = body.replace('/Applications/FluidVoice.app', f'{apps}/FluidVoice.app')
            calls = Path(root) / 'calls'
            env = {'PATH': '/usr/bin:/bin', 'HOME': root, 'CALLS': str(calls), 'MACOS': '15.4', **variables}
            result = subprocess.run(['/bin/bash', '--noprofile', '--norc', '-c', MOCKS + body + '\ninstall_fluidvoice'],
                                    env=env, stdin=subprocess.DEVNULL, text=True, capture_output=True, timeout=20)
            recorded = calls.read_text().splitlines() if calls.exists() else []
            self.assertNotIn('unexpected', '\n'.join(recorded), result.stdout + result.stderr)
            self.assertNotIn('command not found', result.stderr)
            return result, recorded

    def test_headed_mac_installs_the_cask(self):
        for headless in ('', '0', 'true'):
            with self.subTest(headless=headless):
                result, calls = self.run_installer(HEADLESS=headless)
                self.assertEqual(result.returncode, 0, result.stdout)
                self.assertEqual(calls, ['brew:list --cask fluidvoice', 'brew:install --cask fluidvoice'])
                self.assertIn('success:FluidVoice installed.', result.stdout)

    def test_exact_headless_skips_before_any_effect(self):
        result, calls = self.run_installer(HEADLESS='1')
        self.assertEqual(result.returncode, 0)
        self.assertEqual(calls, [])

    def test_existing_installations_are_preserved(self):
        result, calls = self.run_installer(BREW_HAS='1')
        self.assertEqual(result.returncode, 0)
        self.assertEqual(calls, ['brew:list --cask fluidvoice'])
        result, calls = self.run_installer(MANUAL_APP=True)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(calls, ['brew:list --cask fluidvoice'])
        self.assertIn('outside Homebrew', result.stdout)

    def test_older_macos_skips_without_failing(self):
        for version in ('14.7.1', '13.0'):
            with self.subTest(version=version):
                result, calls = self.run_installer(MACOS=version)
                self.assertEqual(result.returncode, 0)
                self.assertNotIn('brew:install --cask fluidvoice', calls)
        result, calls = self.run_installer(MACOS='26.1')
        self.assertIn('brew:install --cask fluidvoice', calls)

    def test_failures_are_reported_to_the_caller(self):
        result, calls = self.run_installer(INSTALL_OK='0')
        self.assertEqual(result.returncode, 1)
        self.assertIn('error:Failed to install FluidVoice.', result.stdout)
        result, calls = self.run_installer(MACOS='')
        self.assertEqual(result.returncode, 1)
        self.assertNotIn('brew:install --cask fluidvoice', calls)


if __name__ == '__main__':
    unittest.main()
