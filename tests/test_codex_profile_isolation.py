#!/usr/bin/env python3
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from extract_setup_fixture import validate_function

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ('ubuntu.sh', 'wsl.sh', 'pi.sh', 'bazzite.sh')
PROFILES = ('.profile', '.bashrc', '.bash_profile', '.zshrc', '.zprofile')
CLEANUP_WARNING = 'WARNING: Could not safely inspect old Codex releases; skipped remaining cleanup.'
CLEANUP_DEFERRAL = 'Codex deferred optional old-release cleanup; remaining releases were retained.'


def function(script, name):
    source = (ROOT / script).read_text()
    start = source.index(f'\n{name}() {{\n') + 1
    end = source.index('\n}\n', start) + 3
    block = source[start:end]
    validate_function(block)
    return block


class CodexProfiles(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='codex-profile-test-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.home = self.root / 'account'
        self.home.mkdir()
        self.installer = self.root / 'installer'
        self.installer.write_text('''#!/bin/sh
set -eu
[ "${CODEX_NON_INTERACTIVE:-}" = 1 ] || exit 43
printf '%s\\n' "$HOME" > "$TEST_CAPTURE"
printf '%s\\n' "$(umask)" > "$TEST_CAPTURE.umask"
if [ -f "$HOME/stderr" ]; then
    find "$HOME/stderr" -type f -perm 0600 > "$TEST_CAPTURE.private-log"
fi
printf 'installer progress\\n'
for profile in .profile .bashrc .bash_profile .zshrc .zprofile; do
    printf 'export PATH=installer-change\\n' >> "$HOME/$profile"
done
printf '%s' "${TEST_STDERR:-}" >&2
[ "${TEST_STATUS:-0}" = 0 ] || exit "$TEST_STATUS"
bin="${CODEX_INSTALL_DIR:-$HOME/.local/bin}"
data="${CODEX_HOME:-$HOME/.codex}"
mkdir -p "$bin" "$data/packages/standalone"
printf '#!/bin/sh\\necho codex-cli 9.9.9\\n' > "$bin/codex"
chmod 700 "$bin/codex"
case "${TEST_BINARY:-working}" in
    missing) rm "$bin/codex" ;;
    broken) printf '#!/bin/sh\\nexit 17\\n' > "$bin/codex" ;;
esac
''')

    def invoke(self, script, custom=False, fail=False, stderr='', status=None, binary='working', block_stderr=False):
        env = {'HOME': str(self.home), 'PATH': os.defpath, 'LC_ALL': 'C',
               'TEST_INSTALLER': str(self.installer), 'TEST_CAPTURE': str(self.root / 'installer-home'),
               'TEST_STATUS': str(status if status is not None else (42 if fail else 0)),
               'TEST_STDERR': stderr, 'TEST_BINARY': binary,
               'TEST_BLOCK_STDERR': '1' if block_stderr else '0', 'TMPDIR': str(self.root)}
        if custom:
            env['CODEX_HOME'] = str(self.home / 'custom codex')
        code = '''
umask 022
print_message() { :; }
print_debug() { printf 'DEBUG: %s\\n' "$*"; }
print_success() { printf '%s\\n' "$*"; }
print_error() { printf '%s\\n' "$*" >&2; }
bun() { :; }
claude_code_trusted_curl() { printf /fixture-curl; }
claude_code_run_safely() {
    if [[ "$1" == /fixture-curl ]]; then
        shift
        while [[ "$1" != -o ]]; do shift; done
        cp "$TEST_INSTALLER" "$2"
        if [[ "$TEST_BLOCK_STDERR" == 1 ]]; then mkdir "${2%/*}/stderr"; fi
    else
        "$@"
    fi
}
''' + function(script, 'install_codex_cli') + '\ninstall_codex_cli\n'
        return subprocess.run(['bash', '--noprofile', '--norc', '-c', code], env=env, cwd=self.root,
                              capture_output=True, text=True, timeout=10)

    def test_installer_preserves_profiles_on_repeated_runs(self):
        for script in SCRIPTS:
            with self.subTest(script=script):
                before = {}
                for profile in PROFILES:
                    file = self.home / profile
                    file.write_text('# Chezmoi-owned; preserve exactly\n')
                    before[profile] = file.read_bytes()
                for _ in range(2):
                    result = self.invoke(script)
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertEqual({p: (self.home / p).read_bytes() for p in PROFILES}, before)
                self.assertTrue((self.home / '.local/bin/codex').is_file())
                self.assertTrue((self.home / '.codex/packages/standalone').is_dir())
                scratch = Path((self.root / 'installer-home').read_text().strip())
                self.assertNotEqual(scratch, self.home)
                self.assertFalse(scratch.exists(), 'Temporary installer HOME was leaked')

    def test_fresh_account_and_custom_codex_home(self):
        for script in SCRIPTS:
            with self.subTest(script=script):
                result = self.invoke(script, custom=True)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertTrue((self.home / 'custom codex/packages/standalone').is_dir())
                self.assertFalse((self.home / '.codex').exists())
                self.assertTrue(all(not (self.home / p).exists() for p in PROFILES))

    def test_successful_installer_reports_only_exact_cleanup_warning_as_deferral(self):
        for script in SCRIPTS:
            with self.subTest(script=script):
                result = self.invoke(script, stderr=CLEANUP_WARNING + '\n')
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn('DEBUG: ' + CLEANUP_DEFERRAL, result.stdout)
                self.assertNotIn(CLEANUP_WARNING, result.stdout + result.stderr)
                self.assertEqual(result.stderr, '')
                self.assertIn('Codex CLI installed/updated (codex-cli 9.9.9)', result.stdout)

    def test_diagnostics_are_private_without_changing_the_native_installer_umask(self):
        for script in SCRIPTS:
            with self.subTest(script=script):
                result = self.invoke(script)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn('installer progress', result.stdout)
                capture = self.root / 'installer-home'
                self.assertEqual(int(Path(str(capture) + '.umask').read_text().strip(), 8), 0o22)
                scratch = Path(capture.read_text().strip())
                self.assertEqual(Path(str(capture) + '.private-log').read_text().strip(), str(scratch / 'stderr'))
                self.assertFalse(scratch.exists())

    def test_diagnostic_reservation_failure_never_runs_the_installer(self):
        for script in SCRIPTS:
            with self.subTest(script=script):
                result = self.invoke(script, block_stderr=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('Failed to prepare Codex installer diagnostics.', result.stderr)
                self.assertFalse((self.root / 'installer-home').exists())
                self.assertFalse(list(self.root.glob('tmp.*')), 'Temporary installer HOME was leaked')

    def test_other_installer_diagnostics_are_preserved_including_unterminated_lines(self):
        diagnostics = ('WARNING: another operation failed.\n\n'
                       + CLEANUP_WARNING + ' Additional detail.\n'
                       + CLEANUP_WARNING + '\n  final diagnostic without newline')
        expected = diagnostics.replace(CLEANUP_WARNING + '\n', '') + '\n'
        for script in SCRIPTS:
            with self.subTest(script=script):
                result = self.invoke(script, stderr=diagnostics)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(result.stderr, expected)
                self.assertEqual(result.stdout.count(CLEANUP_DEFERRAL), 1)

    def test_cleanup_warning_does_not_hide_installer_failures_or_timeouts(self):
        for script in SCRIPTS:
            for status in (42, 124):
                with self.subTest(script=script, status=status):
                    result = self.invoke(script, stderr=CLEANUP_WARNING + '\n', status=status)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn(CLEANUP_WARNING, result.stderr)
                    self.assertIn(f'Codex installer failed with exit code {status}.', result.stderr)
                    self.assertNotIn(CLEANUP_DEFERRAL, result.stdout)
                    self.assertNotIn('Codex CLI installed/updated', result.stdout)
                    self.assertFalse(Path((self.root / 'installer-home').read_text().strip()).exists())

    def test_cleanup_deferral_never_substitutes_for_native_binary_verification(self):
        for script in SCRIPTS:
            for binary, error in (('missing', 'is missing'), ('broken', 'smoke test failed without Node.js')):
                with self.subTest(script=script, binary=binary):
                    result = self.invoke(script, stderr=CLEANUP_WARNING + '\n', binary=binary)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn(error, result.stderr)
                    self.assertNotIn('Codex CLI installed/updated', result.stdout)
                    self.assertFalse(Path((self.root / 'installer-home').read_text().strip()).exists())

    def test_failed_installer_preserves_profiles_and_cleans_temporary_home(self):
        for script in SCRIPTS:
            with self.subTest(script=script):
                profile = self.home / '.profile'
                profile.write_text('# keep on failure\n')
                result = self.invoke(script, fail=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('exit code 42', result.stderr)
                self.assertEqual(profile.read_text(), '# keep on failure\n')
                self.assertTrue(all(not (self.home / p).exists() for p in PROFILES if p != '.profile'))
                self.assertFalse(Path((self.root / 'installer-home').read_text().strip()).exists())


if __name__ == '__main__':
    unittest.main()
