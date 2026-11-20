import json
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

from extract_setup_fixture import validate_function

SOURCE = (Path(__file__).resolve().parents[1] / 'mac.sh').read_text()
XCODE = '/Applications/Xcode.app/Contents/Developer'
CLT = '/Library/Developer/CommandLineTools'


def function(name):
    block = re.search(rf'^{name}\(\) \{{\n.*?^\}}', SOURCE, re.M | re.S)[0]
    validate_function(block)
    return block


MOCKS = r'''
print_message() { printf 'message:%s\n' "$*"; }
print_success() { printf 'success:%s\n' "$*"; }
print_debug() { printf 'debug:%s\n' "$*"; }
print_warning() { printf 'warning:%s\n' "$*"; }
mise() {
    printf 'mise:%s\n' "$*" >> "$HOME/calls"
    case "$*" in
        'ls -C / --global --json rust') printf '%s\n' "$INVENTORY" ;;
        "install -C $HOME rust"|"use -g -y -C $HOME rust@stable") [[ "${FAIL:-}" != mise ]] ;;
        *) printf 'unexpected:mise\n' >> "$HOME/calls"; return 90 ;;
    esac
}
xcode-select() { [[ "$*" == -p && -n "$SELECTED" ]] && printf '%s\n' "$SELECTED"; }
xcrun() {
    printf 'xcrun:%s\n' "$*" >> "$HOME/calls"
    [[ "$*" == 'metal --version' && "${METAL:-0}" == 1 ]]
}
xcodebuild() {
    printf 'xcodebuild:%s\n' "$*" >> "$HOME/calls"
    [[ "$*" == '-downloadComponent MetalToolchain' && "${FAIL:-}" != download ]]
}
'''


class AppToolchain(unittest.TestCase):
    def run_case(self, expression, variables):
        with tempfile.TemporaryDirectory() as root:
            home = Path(root) / 'home'
            home.mkdir()
            env = {'PATH': '/usr/bin:/bin', 'HOME': str(home), 'TMPDIR': root,
                   'INVENTORY': '[]', 'SELECTED': XCODE}
            env.update(variables)
            script = MOCKS + function('install_rust_toolchain') + '\n' + function('install_metal_toolchain') + '\n' + expression
            result = subprocess.run(['/bin/bash', '-c', script], env=env, text=True, stdin=subprocess.DEVNULL,
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20)
            calls_file = home / 'calls'
            calls = calls_file.read_text().splitlines() if calls_file.exists() else []
            self.assertNotIn('unexpected:', '\n'.join(calls), result.stdout + result.stderr)
            return result, [c.replace(str(home), '$HOME') for c in calls]

    def rust(self, inventory, **variables):
        return self.run_case('install_rust_toolchain', {'INVENTORY': json.dumps(inventory), **variables})

    def test_rust_without_a_global_selection_selects_stable(self):
        result, calls = self.rust([])
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn('mise:use -g -y -C $HOME rust@stable', calls)

    def test_rust_keeps_an_existing_global_selection(self):
        result, calls = self.rust([{'version': '1.85.0', 'installed': True}])
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(calls, ['mise:ls -C / --global --json rust'])

        result, calls = self.rust([{'version': 'nightly', 'installed': False}])
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn('mise:install -C $HOME rust', calls)
        self.assertFalse(any('rust@stable' in c for c in calls))

    def test_rust_failures_are_reported(self):
        self.assertEqual(self.rust([], FAIL='mise')[0].returncode, 1)
        self.assertEqual(self.rust('not an inventory')[0].returncode, 1)
        self.assertEqual(self.run_case('unset -f mise; install_rust_toolchain', {})[0].returncode, 1)

    def test_metal_downloads_only_when_xcode_lacks_it(self):
        result, calls = self.run_case('install_metal_toolchain', {})
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn('xcodebuild:-downloadComponent MetalToolchain', calls)

        for variables in ({'METAL': '1'}, {'SELECTED': CLT}, {'SELECTED': ''}):
            result, calls = self.run_case('install_metal_toolchain', variables)
            self.assertEqual(result.returncode, 0, result.stdout)
            self.assertFalse(any(c.startswith('xcodebuild') for c in calls), variables)

    def test_core_packages_include_pnpm(self):
        packages = re.search(r'local packages=\(([^)]*)\)', function('install_core_packages'))[1].split()
        self.assertIn('"pnpm"', packages)

    def test_metal_download_failure_is_reported(self):
        self.assertEqual(self.run_case('install_metal_toolchain', {'FAIL': 'download'})[0].returncode, 1)


if __name__ == '__main__':
    unittest.main()
