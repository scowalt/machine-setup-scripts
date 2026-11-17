from pathlib import Path
import re
import subprocess
import tempfile
import unittest

from extract_setup_fixture import definitions

ROOT = Path(__file__).resolve().parents[1]
UPSTREAM_INSTALLER = r'''
printf '%s\n' "$*" >> "${STARSHIP_TEST_ROOT}/installer-args"
bin_dir=/usr/local/bin
while [ "$#" -gt 0 ]; do
    case "$1" in
        -b) bin_dir="$2"; shift ;;
    esac
    shift
done
if [ "${bin_dir}" = /usr/local/bin ]; then
    sudo -v || { printf 'x Superuser not granted, aborting installation\n'; exit 1; }
fi
[ "${STARSHIP_TEST_FAIL:-0}" != 1 ] || exit 1
printf '#!/bin/sh\nexit 0\n' > "${bin_dir}/starship"
chmod 700 "${bin_dir}/starship"
'''


class StarshipInstallation(unittest.TestCase):
    def install(self, **env):
        with tempfile.TemporaryDirectory(prefix='starship-installation-') as tmp:
            root = Path(tmp)
            home, commands = root / 'home', root / 'commands'
            home.mkdir()
            commands.mkdir()
            (root / 'installer.sh').write_text(UPSTREAM_INSTALLER)
            for name, body in {
                'curl': 'printf "%s\\n" "$*" >> "${STARSHIP_TEST_ROOT}/curl-calls"\ncat "${STARSHIP_TEST_ROOT}/installer.sh"',
                'sudo': 'printf "%s\\n" "$*" >> "${STARSHIP_TEST_ROOT}/sudo-calls"\nexit 1',
            }.items():
                (commands / name).write_text('#!/bin/bash\n' + body + '\n')
                (commands / name).chmod(0o700)
            program = definitions((ROOT / 'ubuntu.sh').read_text()) + '\ninstall_starship\nstatus=$?\ncommand -v starship\nexit "${status}"\n'
            result = subprocess.run(['/bin/bash', '--noprofile', '--norc'], input=program, text=True, capture_output=True,
                                    env={'HOME': str(home), 'STARSHIP_TEST_ROOT': str(root),
                                         'PATH': f'{commands}:/usr/bin:/bin', **env})
            record = {name: (root / name).read_text().splitlines() if (root / name).exists() else []
                      for name in ('curl-calls', 'installer-args', 'sudo-calls')}
            return result, record, str(home / '.local/bin')

    def test_missing_starship_installs_into_the_user_bin_without_sudo(self):
        result, record, bin_dir = self.install()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('Starship installed.', result.stdout)
        self.assertEqual(result.stdout.splitlines()[-1], bin_dir + '/starship')
        self.assertEqual(record, {'curl-calls': ['-fsSL https://starship.rs/install.sh'],
                                  'installer-args': [f'-y -b {bin_dir}'], 'sudo-calls': []})

    def test_installer_failure_is_reported_instead_of_success(self):
        result, record, bin_dir = self.install(STARSHIP_TEST_FAIL='1')
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertNotIn('Starship installed.', result.stdout)
        self.assertIn(f'Failed to install Starship into {bin_dir}.', result.stdout + result.stderr)

    def test_ubuntu_setup_records_a_starship_failure(self):
        self.assertRegex((ROOT / 'ubuntu.sh').read_text(), re.compile(r'^    install_starship \|\| _setup_had_errors=1$', re.M))


if __name__ == '__main__':
    unittest.main(verbosity=2)
