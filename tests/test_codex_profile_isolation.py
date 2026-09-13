#!/usr/bin/env python3
"""Contract v1: extracted Codex installers must not modify account shell profiles."""
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ('ubuntu.sh', 'wsl.sh', 'pi.sh', 'bazzite.sh')
PROFILES = ('.profile', '.bashrc', '.bash_profile', '.zshrc', '.zprofile')


def function(script, name):
    match = re.search(r'^' + name + r'\(\) \{\n.*?^\}', (ROOT / script).read_text(), re.M | re.S)
    assert match, (script, name)
    return match.group(0)


class CodexProfiles(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='codex-profile-test-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.home = self.root / 'account'
        self.home.mkdir()
        self.installer = self.root / 'installer'
        # Boundary fixture deliberately exercises upstream's shell-profile writes.
        # CODEX_INSTALL_DIR and CODEX_HOME are the native installer's real inputs.
        self.installer.write_text('''#!/bin/sh
set -eu
[ "${CODEX_NON_INTERACTIVE:-}" = 1 ] || exit 43
printf '%s\\n' "$HOME" > "$TEST_CAPTURE"
for profile in .profile .bashrc .bash_profile .zshrc .zprofile; do
    printf 'export PATH=installer-change\\n' >> "$HOME/$profile"
done
[ "${TEST_FAIL:-0}" = 0 ] || exit 42
bin="${CODEX_INSTALL_DIR:-$HOME/.local/bin}"
data="${CODEX_HOME:-$HOME/.codex}"
mkdir -p "$bin" "$data/packages/standalone"
printf '#!/bin/sh\\necho codex-cli 9.9.9\\n' > "$bin/codex"
chmod 700 "$bin/codex"
''')

    def invoke(self, script, custom=False, fail=False):
        env = {'HOME': str(self.home), 'PATH': os.defpath, 'LC_ALL': 'C',
               'TEST_INSTALLER': str(self.installer), 'TEST_CAPTURE': str(self.root / 'installer-home'),
               'TEST_FAIL': '1' if fail else '0', 'TMPDIR': str(self.root)}
        if custom:
            env['CODEX_HOME'] = str(self.home / 'custom codex')
        code = '''
print_message() { :; }
print_debug() { :; }
print_success() { printf '%s\\n' "$*"; }
print_error() { printf '%s\\n' "$*" >&2; }
bun() { :; }
claude_code_trusted_curl() { printf /fixture-curl; }
claude_code_run_safely() {
    if [[ "$1" == /fixture-curl ]]; then
        shift
        while [[ "$1" != -o ]]; do shift; done
        cp "$TEST_INSTALLER" "$2"
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
