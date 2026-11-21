#!/usr/bin/env python3
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

from extract_setup_fixture import validate_function

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ('mac.sh', 'ubuntu.sh', 'wsl.sh', 'pi.sh', 'bazzite.sh')
PROFILES = ('.profile', '.bashrc', '.bash_profile', '.zshrc', '.config/fish/config.fish')
FAKE_VERSION = '1.5.14'
FUNCTION = 'install_agy_cli'

INSTALLER = '''#!/bin/bash
set -euo pipefail
printf '%s\\n' "$HOME" > "$TEST_CAPTURE.home"
printf '%s\\n' "$*" >> "$TEST_CAPTURE.argv"
printf 'run\\n' >> "$TEST_CAPTURE.count"
dir=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --dir) dir="$2"; shift ;;
    esac
    shift
done
if [ -e "$dir/agy" ]; then
    echo "Notice: 'agy' is already installed at $dir/agy."
    exit 0
fi
mkdir -p "$HOME/.cache/antigravity/staging"
for line in $(seq 1 30); do echo "installer line $line"; done
echo "Add this to your ~/.bashrc: export PATH=installer-change"
if [ "${TEST_STATUS:-0}" != 0 ]; then
    for profile in .profile .bashrc .bash_profile .zshrc; do
        echo 'export PATH=installer-change' >> "$HOME/$profile"
    done
    exit "$TEST_STATUS"
fi
mkdir -p "$dir"
case "${TEST_BINARY:-working}" in
    missing) exit 0 ;;
    broken) body='echo "agy: probe failure" >&2; exit 17' ;;
    silent) body='exit 0' ;;
    *) body='echo "$TEST_VERSION"' ;;
esac
cat > "$dir/agy" <<AGY
#!/bin/sh
case "\\$1" in
    install)
        for profile in .profile .bashrc .bash_profile .zshrc; do
            echo 'export PATH=installer-change' >> "\\$HOME/\\$profile"
        done
        mkdir -p "\\$HOME/.config/fish" "\\$HOME/.gemini"
        echo 'set -gx PATH installer-change' >> "\\$HOME/.config/fish/config.fish"
        exit 0
        ;;
esac
$body
AGY
chmod 755 "$dir/agy"
"$dir/agy" install --dir "$dir" || true
'''


def function(script):
    source = (ROOT / script).read_text()
    start = source.index(f'\n{FUNCTION}() {{\n') + 1
    end = source.index('\n}\n', start) + 3
    block = source[start:end]
    validate_function(block)
    return block


class AgyInstallation(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='agy-install-test-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.home = self.root / 'account'
        self.home.mkdir()
        self.installer = self.root / 'installer'
        self.installer.write_text(INSTALLER)
        self.capture = self.root / 'capture'

    def reset(self):
        shutil.rmtree(self.home)
        self.home.mkdir()
        for stale in self.root.glob('capture.*'):
            stale.unlink()

    def seed_profiles(self):
        before = {}
        for profile in PROFILES:
            file = self.home / profile
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_text('# Chezmoi-owned; preserve exactly\n')
            before[profile] = file.read_bytes()
        return before

    def invoke(self, script, os_name='Linux', arch='x86_64', bits='64', ldd='ldd (GNU libc) 2.39', status=0,
               binary='working', curl_fails=False):
        env = {'HOME': str(self.home), 'PATH': os.defpath, 'LC_ALL': 'C', 'TMPDIR': str(self.root),
               'TEST_INSTALLER': str(self.installer), 'TEST_CAPTURE': str(self.capture),
               'TEST_STATUS': str(status), 'TEST_BINARY': binary, 'TEST_VERSION': FAKE_VERSION,
               'TEST_OS': os_name, 'TEST_ARCH': arch, 'TEST_BITS': bits, 'TEST_LDD': ldd,
               'TEST_CURL_FAILS': '1' if curl_fails else '0'}
        code = '''
set -euo pipefail
print_message() { printf 'MESSAGE: %s\\n' "$*"; }
print_debug() { printf 'DEBUG: %s\\n' "$*"; }
print_success() { printf 'SUCCESS: %s\\n' "$*"; }
print_warning() { printf 'WARNING: %s\\n' "$*" >&2; }
uname() { if [[ "$1" == -s ]]; then printf '%s\\n' "$TEST_OS"; else printf '%s\\n' "$TEST_ARCH"; fi; }
ldd() { printf '%s\\n' "$TEST_LDD"; }
getconf() { [[ "$TEST_BITS" != fail ]] || return 1; printf '%s\\n' "$TEST_BITS"; }
claude_code_trusted_curl() { printf /fixture-curl; }
claude_code_run_safely() {
    if [[ "$1" == /fixture-curl ]]; then
        printf 'curl\\n' >> "$TEST_CAPTURE.curl"
        [[ "$TEST_CURL_FAILS" == 0 ]] || return 22
        shift
        while [[ "$1" != -o ]]; do shift; done
        cp "$TEST_INSTALLER" "$2"
    else
        "$@"
    fi
}
''' + function(script) + f'\n{FUNCTION} || exit $?\n'
        return subprocess.run(['bash', '--noprofile', '--norc', '-c', code], env=env, cwd=self.root,
                              capture_output=True, text=True, timeout=30)

    def installer_runs(self):
        count = Path(str(self.capture) + '.count')
        return len(count.read_text().split()) if count.exists() else 0

    def home_files(self):
        return sorted(str(p.relative_to(self.home)) for p in self.home.rglob('*') if p.is_file())

    def assert_no_scratch(self):
        self.assertEqual(list(self.root.glob('tmp.*')), [], 'Temporary installer HOME was leaked')

    def test_fresh_install_leaves_the_real_home_untouched(self):
        for script in SCRIPTS:
            for os_name, arch in (('Linux', 'x86_64'), ('Linux', 'aarch64'), ('Darwin', 'arm64'), ('Darwin', 'x86_64')):
                with self.subTest(script=script, platform=f'{os_name}:{arch}'):
                    self.reset()
                    before = self.seed_profiles()
                    result = self.invoke(script, os_name=os_name, arch=arch)
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertEqual({p: (self.home / p).read_bytes() for p in PROFILES}, before)
                    agy = self.home / '.local/bin/agy'
                    self.assertTrue(agy.is_file() and os.access(agy, os.X_OK))
                    self.assertEqual(self.home_files(), sorted(PROFILES + ('.local/bin/agy',)))
                    self.assertFalse((self.home / '.cache/antigravity').exists())
                    self.assertFalse((self.home / '.gemini').exists())
                    scratch = Path(Path(str(self.capture) + '.home').read_text().strip())
                    self.assertNotEqual(scratch, self.home)
                    self.assertFalse(scratch.exists(), 'Temporary installer HOME was leaked')
                    self.assertEqual(Path(str(self.capture) + '.argv').read_text().strip(),
                                     f'--dir {self.home}/.local/bin')
                    self.assertIn(f'SUCCESS: Antigravity CLI ready ({FAKE_VERSION}).', result.stdout)
                    self.assertNotIn('installer line', result.stdout + result.stderr)
                    self.assertNotIn('~/.bashrc', result.stdout + result.stderr)
                    self.assert_no_scratch()

    def test_second_run_downloads_and_installs_nothing(self):
        for script in SCRIPTS:
            with self.subTest(script=script):
                self.reset()
                before = self.seed_profiles()
                first = self.invoke(script)
                second = self.invoke(script)
                self.assertEqual(first.returncode, 0, first.stdout + first.stderr)
                self.assertEqual(second.returncode, 0, second.stdout + second.stderr)
                self.assertEqual(self.installer_runs(), 1)
                self.assertEqual(len(Path(str(self.capture) + '.curl').read_text().split()), 1)
                self.assertIn('DEBUG: Antigravity CLI is already installed; it updates itself.', second.stdout)
                self.assertIn(f'SUCCESS: Antigravity CLI ready ({FAKE_VERSION}).', second.stdout)
                self.assertEqual({p: (self.home / p).read_bytes() for p in PROFILES}, before)

    def test_unsupported_platforms_warn_and_continue(self):
        for script in SCRIPTS:
            for os_name, arch in (('Linux', 'armv7l'), ('Linux', 'i686'), ('Linux', 'riscv64'), ('FreeBSD', 'amd64')):
                with self.subTest(script=script, platform=f'{os_name}:{arch}'):
                    self.reset()
                    result = self.invoke(script, os_name=os_name, arch=arch)
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertIn(f'WARNING: Antigravity CLI has no {os_name} {arch} build; skipping.', result.stderr)
                    self.assertEqual(self.installer_runs(), 0)
                    self.assertFalse(Path(str(self.capture) + '.curl').exists())
                    self.assertEqual(self.home_files(), [])
                    self.assert_no_scratch()

    def test_ldd_reporting_musl_still_installs(self):
        for script in SCRIPTS:
            for arch in ('x86_64', 'aarch64'):
                with self.subTest(script=script, arch=arch):
                    self.reset()
                    before = self.seed_profiles()
                    result = self.invoke(script, arch=arch, ldd='musl libc (x86_64)\nVersion 1.2.5')
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertNotIn('musl', result.stdout + result.stderr)
                    self.assertEqual(self.installer_runs(), 1)
                    self.assertEqual(Path(str(self.capture) + '.argv').read_text().strip(),
                                     f'--dir {self.home}/.local/bin')
                    self.assertEqual({p: (self.home / p).read_bytes() for p in PROFILES}, before)

    def test_32_bit_userland_on_a_64_bit_arm_kernel_warns_and_continues(self):
        for script in SCRIPTS:
            with self.subTest(script=script):
                self.reset()
                result = self.invoke(script, arch='aarch64', bits='32')
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn('WARNING: Antigravity CLI has no 32-bit ARM build; skipping.', result.stderr)
                self.assertEqual(self.installer_runs(), 0)
                self.assertFalse(Path(str(self.capture) + '.curl').exists())
                self.assertEqual(self.home_files(), [])
                self.assert_no_scratch()

    def test_64_bit_arm_and_unknown_word_size_install(self):
        for script in SCRIPTS:
            for bits in ('64', 'fail'):
                with self.subTest(script=script, bits=bits):
                    self.reset()
                    result = self.invoke(script, arch='aarch64', bits=bits)
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertEqual(self.installer_runs(), 1)
                    self.assertTrue((self.home / '.local/bin/agy').is_file())

    def test_x86_64_ignores_word_size(self):
        for script in SCRIPTS:
            with self.subTest(script=script):
                self.reset()
                result = self.invoke(script, arch='x86_64', bits='32')
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(self.installer_runs(), 1)

    def test_failed_installer_warns_with_exit_code_and_keeps_profiles(self):
        for script in SCRIPTS:
            with self.subTest(script=script):
                self.reset()
                before = self.seed_profiles()
                result = self.invoke(script, status=42)
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertIn('WARNING: Antigravity CLI installer failed with exit code 42.', result.stderr)
                self.assertIn('installer line 30', result.stderr)
                self.assertNotIn('installer line 10\n', result.stderr)
                self.assertEqual({p: (self.home / p).read_bytes() for p in PROFILES}, before)
                self.assertEqual(self.home_files(), sorted(PROFILES))
                self.assertFalse(Path(Path(str(self.capture) + '.home').read_text().strip()).exists())
                self.assert_no_scratch()

    def test_failed_download_warns_and_never_runs_the_installer(self):
        for script in SCRIPTS:
            with self.subTest(script=script):
                self.reset()
                result = self.invoke(script, curl_fails=True)
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertIn('WARNING: Failed to download the Antigravity CLI installer.', result.stderr)
                self.assertEqual(self.installer_runs(), 0)
                self.assert_no_scratch()

    def test_installer_without_a_binary_fails(self):
        for script in SCRIPTS:
            with self.subTest(script=script):
                self.reset()
                result = self.invoke(script, binary='missing')
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertIn('installer completed, but', result.stderr)
                self.assertIn('/.local/bin/agy is missing.', result.stderr)
                self.assertNotIn('SUCCESS', result.stdout)
                self.assert_no_scratch()

    def test_failed_smoke_test_reports_exit_code_and_output(self):
        for script in SCRIPTS:
            with self.subTest(script=script):
                self.reset()
                result = self.invoke(script, binary='broken')
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertIn('agy: probe failure\n', result.stderr)
                self.assertIn('WARNING: Antigravity CLI smoke test failed (exit code 17).', result.stderr)
                self.assertNotIn('SUCCESS', result.stdout)

    def test_empty_version_output_fails_the_smoke_test(self):
        for script in SCRIPTS:
            with self.subTest(script=script):
                self.reset()
                result = self.invoke(script, binary='silent')
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertIn('WARNING: Antigravity CLI smoke test failed (exit code 0).', result.stderr)

    def test_function_is_identical_and_called_right_after_gemini(self):
        blocks = {script: function(script) for script in SCRIPTS}
        self.assertEqual(len(set(blocks.values())), 1)
        for script in SCRIPTS:
            with self.subTest(script=script):
                lines = (ROOT / script).read_text().splitlines()
                callers = [i for i, line in enumerate(lines) if re.fullmatch(r'\s+install_gemini_cli(?: \|\| _setup_had_errors=1)?', line)]
                self.assertEqual(len(callers), 1)
                self.assertEqual(lines[callers[0] + 1], '    install_agy_cli || _setup_had_errors=1')


if __name__ == '__main__':
    unittest.main()
