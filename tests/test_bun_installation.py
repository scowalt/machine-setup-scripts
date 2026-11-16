from pathlib import Path
import subprocess
import tempfile
import unittest

from extract_setup_fixture import definitions

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ('ubuntu.sh', 'wsl.sh', 'pi.sh', 'bazzite.sh')
INSTALLER = 'printf "ran\\n" >> "${BUN_TEST_ROOT}/installer-runs"; mkdir -p "${HOME}/.bun/bin"; ' \
            'printf "#!/bin/sh\\nexit 0\\n" > "${HOME}/.bun/bin/bun"; chmod 700 "${HOME}/.bun/bin/bun"'


class BunInstallation(unittest.TestCase):
    def install(self, script, installed):
        with tempfile.TemporaryDirectory(prefix='bun-installation-') as tmp:
            root = Path(tmp)
            home, commands = root / 'home', root / 'commands'
            commands.mkdir()
            curl = commands / 'curl'
            curl.write_text('#!/bin/bash\nprintf "%s\\n" "$*" >> "${BUN_TEST_ROOT}/curl-calls"\nprintf \'%s\\n\' ' +
                            "'" + INSTALLER + "'\n")
            curl.chmod(0o700)
            if installed:
                subprocess.run(['/bin/bash', '-c', INSTALLER], check=True,
                               env={'HOME': str(home), 'BUN_TEST_ROOT': str(root), 'PATH': '/usr/bin:/bin'})
                (root / 'installer-runs').unlink()
            program = definitions((ROOT / script).read_text()) + '\ninstall_bun\ncommand -v bun\n'
            result = subprocess.run(['/bin/bash', '--noprofile', '--norc'], input=program, text=True, capture_output=True,
                                    env={'HOME': str(home), 'BUN_TEST_ROOT': str(root), 'PATH': f'{commands}:/usr/bin:/bin'})
            calls = (root / 'curl-calls').read_text().splitlines() if (root / 'curl-calls').exists() else []
            runs = (root / 'installer-runs').read_text().splitlines() if (root / 'installer-runs').exists() else []
            return result, calls, runs, str(home / '.bun/bin/bun')

    def test_existing_home_bun_outside_path_is_reused_without_reinstalling(self):
        for script in SCRIPTS:
            with self.subTest(script=script):
                result, calls, runs, bun = self.install(script, installed=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn('Bun is already installed.', result.stdout)
                self.assertEqual(result.stdout.splitlines()[-1], bun)
                self.assertEqual((calls, runs), ([], []))

    def test_missing_bun_runs_the_official_installer_once_and_activates_it(self):
        for script in SCRIPTS:
            with self.subTest(script=script):
                result, calls, runs, bun = self.install(script, installed=False)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn('Bun installed.', result.stdout)
                self.assertEqual(result.stdout.splitlines()[-1], bun)
                self.assertEqual((calls, runs), (['-fsSL https://bun.sh/install'], ['ran']))


if __name__ == '__main__':
    unittest.main(verbosity=2)
