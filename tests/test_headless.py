import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

from test_paseo_non_management import BASH, ROOT, PWSH, function


class Headless(unittest.TestCase):
    def run_bash(self, code, flags=None, envfile=''):
        with tempfile.TemporaryDirectory() as tmp:
            (Path(tmp) / '.env.local').write_text(envfile)
            return subprocess.run(['bash', '-c', code], cwd=tmp,
                                  env={'PATH': '/usr/bin:/bin', 'HOME': tmp, **(flags or {})},
                                  capture_output=True, text=True, timeout=10)

    def test_wsl_exact_flag_and_existing_environment_parsing(self):
        source = (ROOT / 'wsl.sh').read_text()
        code = 'print_error() { echo "$*"; }\n'
        code += function(source, 'env_local_flag_is_one') + '\n' + function(source, 'fail_unsupported_headless')
        code += '\nfail_unsupported_headless'
        for value in ('', '0', 'true', 'false', '1'):
            for from_file in (False, True):
                with self.subTest(value=value, from_file=from_file):
                    result = self.run_bash(code, {} if from_file else {'HEADLESS': value},
                                           f'export HEADLESS="{value}"\n' if from_file else '')
                    self.assertEqual(result.returncode, int(value == '1'), result.stdout + result.stderr)
                    self.assertNotIn('Paseo', result.stdout)
                    if value == '1': self.assertIn('no-login headless', result.stdout)
        self.assertEqual(self.run_bash(code, {'HEADLESS': '0'}, "HEADLESS='1'\n").returncode, 1)
        self.assertEqual(self.run_bash(code, {'HEADLESS': '1'}, 'HEADLESS=0\n').returncode, 1)
        main = function(source, 'run_setup_tasks')
        self.assertLess(main.index('fail_unsupported_headless || return 1'), main.index('    create_env_local'))

    def test_native_headless_platform_gates_preserve_wsl_and_container_limits(self):
        bodies = []
        for name in ('ubuntu.sh', 'pi.sh', 'bazzite.sh'):
            source = (ROOT / name).read_text()
            body = function(source, 'headless_platform_gate'); bodies.append(body)
            self.assertIn('    headless_platform_gate || return 1', function(source, 'run_setup_tasks'))
            for platform in ('native', 'wsl', 'container'):
                for value in ('', '0', 'true', 'false', '1'):
                    with self.subTest(script=name, platform=platform, value=value):
                        code = '''print_error() { echo "$*"; }
uname() { echo Linux; }
is_wsl_environment() { [[ "$PLATFORM" == wsl ]]; }
is_container_environment() { [[ "$PLATFORM" == container ]]; }
''' + body + '\nheadless_platform_gate'
                        result = self.run_bash(code, {'HEADLESS': value, 'PLATFORM': platform})
                        self.assertEqual(result.returncode, int(value == '1' and platform != 'native'))
                        self.assertNotIn('Paseo', result.stdout)
        self.assertTrue(all(b == bodies[0] for b in bodies))

    def test_ubuntu_passwordless_sudo_requires_both_exact_opt_ins(self):
        source = (ROOT / 'ubuntu.sh').read_text()
        body = function(source, 'setup_headless_sudo')
        self.assertEqual(body.count('/etc/sudoers.d/'), 1)
        body = body.replace('/etc/sudoers.d/', '${HOME}/sudoers/')
        code = '''print_message() { :; }; print_debug() { :; }; print_success() { :; }
can_sudo() { echo checked; return 0; }
sudo() { echo "sudo:$*" >&2; if [[ "$1" == tee ]]; then while IFS= read -r line; do :; done; fi; }
''' + body + '\nsetup_headless_sudo'
        for headless in ('', '0', 'true', 'false', '1'):
            for optin in ('', '0', 'true', 'false', '1'):
                with self.subTest(headless=headless, optin=optin):
                    result = self.run_bash(code, {'HEADLESS': headless, 'HEADLESS_PASSWORDLESS_SUDO': optin, 'USER': 'fixture'})
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    authorized = headless == optin == '1'
                    self.assertEqual('checked' in result.stdout, authorized)
                    self.assertEqual('sudo:tee' in result.stderr, authorized)
                    self.assertEqual('sudo:chmod 0440' in result.stderr, authorized)

    def test_ubuntu_tmux_keeps_generic_user_bus_fallback(self):
        source = (ROOT / 'ubuntu.sh').read_text()
        code = '''id() { echo 1234; }; whoami() { echo fixture; }
systemctl() {
    echo "${XDG_RUNTIME_DIR:-unset}|${DBUS_SESSION_BUS_ADDRESS:-unset}|$*"
    [[ "$*" != '--user is-active tmux.service' ]]
}
''' + function(source, 'systemctl_user') + '\nsystemctl_user is-active tmux.service'
        result = self.run_bash(code)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('/run/user/1234|unix:path=/run/user/1234/bus|--user is-active tmux.service', result.stdout)
        self.assertIn('--machine=fixture@ --user is-active tmux.service', result.stdout)
        self.assertIn('systemctl_user start tmux.service', function(source, 'enable_tmux_service'))

    def test_macos_and_bb_keep_exact_headless_effects(self):
        mac = (ROOT / 'mac.sh').read_text()
        for name in ('configure_power_settings', 'enable_screen_sharing'):
            self.assertIn('${HEADLESS:-}', function(mac, name))
            self.assertIn('"1"', function(mac, name))
        for name in BASH:
            text = (ROOT / name).read_text()
            self.assertIn('[[ "${HEADLESS:-}" == "1" ]]', function(text, 'install_bb_desktop'))
            self.assertIn('[[ "${HEADLESS:-}" != 1 ]]', function(text, 'bb_machine_platform_ready'))
            self.assertIn('bb_machine_platform_ready "${_platform}" || return 1', function(text, 'setup_bb_machine'))

    def test_windows_early_generic_gate_source(self):
        source = (ROOT / 'win.ps1').read_text()
        main = function(source, 'Invoke-WindowsSetupTasks', True)
        self.assertLess(main.index('    Assert-HeadlessUnsupported'), main.index('    New-TokenPlaceholders'))
        gate = function(source, 'Assert-HeadlessUnsupported', True)
        self.assertIn('Test-EnvLocalFlag "HEADLESS"', gate)
        self.assertIn('no-login headless operation', gate)
        self.assertNotIn('Paseo', gate)

    @unittest.skipUnless(PWSH, 'Set PWSH_BIN for actual Windows flag/gate fixtures')
    def test_windows_actual_flag_parser_and_gate(self):
        source = (ROOT / 'win.ps1').read_text()
        code = "$ErrorActionPreference='Stop'\nfunction Write-Error { param($Message) Write-Host $Message }\n"
        code += function(source, 'Test-EnvLocalFlag', True) + '\n' + function(source, 'Assert-HeadlessUnsupported', True)
        code += '\ntry { Assert-HeadlessUnsupported } catch { exit 1 }\n'
        with tempfile.TemporaryDirectory() as tmp:
            fixture = Path(tmp) / 'headless.ps1'; fixture.write_text(code)
            home = Path(tmp) / 'home'; home.mkdir()
            for value in ('', '0', 'true', 'false', '1'):
                for from_file in (False, True):
                    with self.subTest(value=value, from_file=from_file):
                        (home / '.env.local').write_text(f'HEADLESS={value}\n' if from_file else '')
                        result = subprocess.run([PWSH, '-NoProfile', '-File', str(fixture)], cwd=tmp,
                                                env={'PATH': os.environ['PATH'], 'HOME': str(home), 'USERPROFILE': str(home),
                                                     'HEADLESS': '' if from_file else value},
                                                capture_output=True, text=True, timeout=10)
                        self.assertEqual(result.returncode, int(value == '1'), result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main(verbosity=2)
