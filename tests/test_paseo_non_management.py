import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
BASH = ('mac.sh', 'ubuntu.sh', 'wsl.sh', 'pi.sh', 'bazzite.sh')
PWSH = os.environ.get('PWSH_BIN') or shutil.which('pwsh')
DOTFILES = os.environ.get('PASEO_UNMANAGED_DOTFILES_SOURCE')
LEGACY_ENV = '''PASEO_CHANNEL=invalid-retired-channel
PASEO_HOME=relative/invalid
PASEO_HOST=https://not-contacted.invalid
PASEO_ELECTRON_USER_DATA_DIR=relative/invalid
PASEO_MACOS_HEADLESS_CANARY=1
PASEO_VALIDATED_CMD=/not/executed
PASEO_MUSE_DEFER_DAEMON_SETUP=1
'''
SENTINELS = ('.paseo/config.json', '.paseo/paseo.pid', '.paseo/auth.json',
             '.paseo/plugin-settings/paseo-plain/settings.json',
             '.paseo/plugin-data/paseo-plain/data.json',
             '.paseo/setup-recovery/paseo-plain-retirement/state.json',
             '.config/Paseo/desktop-settings.json', '.config/paseo/github-token.env',
             '.config/systemd/user/paseo.service',
             '.config/systemd/user/paseo.service.d/github-token.conf',
             'Library/LaunchAgents/com.scowalt.paseo-daemon.plist',
             '.local/bin/paseo', '.local/bin/paseo-daemon-start',
             '.local/bin/paseo-enable-github-token',
             '.local/lib/node_modules/@getpaseo/cli/package.json',
             '.bun/install/global/node_modules/@getpaseo/cli/package.json')


def function(source, name, windows=False):
    prefix = f'function {name} ' if windows else f'{name}() '
    match = re.search(r'^' + re.escape(prefix) + r'\{\n.*?^\}', source, re.M | re.S)
    if not match:
        raise AssertionError(f'missing function {name}')
    return match[0]


def seed(home):
    for name in SENTINELS:
        file = home / name
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_text('unchanged malformed legacy fixture: ' + name)
        file.chmod(0o640)
    (home / '.env.local').write_text(LEGACY_ENV)
    (home / '.env.local').chmod(0o600)
    (home / '.paseo/linked-profile').symlink_to('config.json')


def snapshot(home):
    return {str(p.relative_to(home)): (p.lstat().st_mode,
            os.readlink(p) if p.is_symlink() else p.read_bytes() if p.is_file() else None)
            for p in home.rglob('*')}


class NonManagement(unittest.TestCase):
    def test_sources_contain_no_legacy_operations_or_configuration(self):
        for name in (*BASH, 'win.ps1'):
            source = (ROOT / name).read_text()
            with self.subTest(script=name):
                executable = '\n'.join(line for line in source.splitlines() if ' | Last changed: ' not in line)
                self.assertNotRegex(executable.lower(), r'paseo|@getpaseo|paseo-plain')
                self.assertIn('OPENCODE_GO_API_KEY', executable)
                self.assertIn('muse-spark-1.3-contributor', executable)
                self.assertIn('gpt-6-astra', executable)
                self.assertIn('pi-mcp-adapter@2.32.1', executable)

    def test_real_bash_runners_preserve_state_and_aggregate_pi_failures(self):
        for name in BASH:
            source = (ROOT / name).read_text()
            names = set(re.findall(r'^(\w+)\(\) \{', source, re.M))
            code = '\n'.join(f'{n}() {{ :; }}' for n in names)
            code += '\n' + function(source, 'run_setup_tasks') + '\n' + function(source, 'main')
            code += '\n' + function(source, 'create_env_local')
            code += r'''
record() { printf '%s\n' "$1" >> "$EVENTS"; }
check_dotfiles_access() { return 1; }
setup_dotfiles_deploy_key() { return 1; }
whoami() { printf 'fixture\n'; }
brew() { :; }
unzip() { :; }
is_main_user() { return 0; }
bb_server_selection() { return 1; }
setup_bb_machine() { record bb-preparation; }
prepare_pi_profile_permissions() { record permissions; [[ "$FAILURE" != permissions ]]; }
configure_pi_opencode_go() { record go; [[ "$FAILURE" != go ]]; }
prepare_pi_mcp_adapter() { record adapter-preflight; [[ "$FAILURE" != adapter ]]; }
setup_pi_mcp_adapter() { record packages; }
refresh_pi_packages() { record refresh; }
remove_compound_engineering_resources() { record unrelated; }
check_pending_reboot() { record reboot; }
start_setup_log() { record log-start; }
finish_setup_log() { record "final:$1"; return "$1"; }
print_warning() { :; }
'''
            for cmd in ('paseo', 'systemctl', 'launchctl', 'loginctl', 'pgrep', 'ps', 'curl',
                        'npm', 'bun', 'pi', 'bb', 'chezmoi', 'sudo', 'kill', 'pkill'):
                code += f'\n{cmd}() {{ record FORBIDDEN:{cmd}; return 99; }}'
            code += '\nmain\n'
            for failure in ('none', 'permissions', 'go', 'adapter'):
                for headless in ('0', '1'):
                    with self.subTest(script=name, failure=failure, headless=headless), tempfile.TemporaryDirectory() as tmp:
                        home = Path(tmp) / 'home'; home.mkdir()
                        seed(home)
                        before = snapshot(home)
                        events = Path(tmp) / 'events'
                        env = {'PATH': '/usr/bin:/bin', 'HOME': str(home), 'EVENTS': str(events),
                               'FAILURE': failure, 'HEADLESS': headless, 'WORK_MACHINE': '1',
                               'PASEO_CHANNEL': 'invalid-process-channel', 'PASEO_HOME': '/outside/home'}
                        result = subprocess.run(['bash', '--noprofile', '--norc', '-c', code],
                                                cwd=tmp, env=env, capture_output=True, text=True, timeout=15)
                        self.assertEqual(result.returncode, int(failure != 'none'), result.stdout + result.stderr)
                        calls = events.read_text().splitlines()
                        self.assertEqual(snapshot(home), before)
                        self.assertIn('bb-preparation', calls)
                        self.assertIn('unrelated', calls)
                        self.assertIn('reboot', calls)
                        self.assertEqual(calls[-1], f'final:{int(failure != "none")}')
                        self.assertEqual('packages' in calls, failure == 'none')
                        self.assertEqual('refresh' in calls, failure == 'none')
                        self.assertFalse(any(c.startswith('FORBIDDEN:') for c in calls), calls)

    def test_fresh_bash_environment_templates_omit_legacy_knobs(self):
        for name in BASH:
            source = (ROOT / name).read_text()
            code = 'print_message() { :; }; print_debug() { :; }; print_success() { :; }\n'
            code += function(source, 'migrate_token_files') + '\n' + function(source, 'create_env_local') + '\ncreate_env_local\n'
            with self.subTest(script=name), tempfile.TemporaryDirectory() as tmp:
                result = subprocess.run(['bash', '-c', code], cwd=tmp,
                                        env={'PATH': '/usr/bin:/bin', 'HOME': tmp}, capture_output=True, text=True, timeout=10)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                text = (Path(tmp) / '.env.local').read_text()
                self.assertNotIn('PASEO', text)
                for key in ('HEADLESS', 'OPENCODE_GO_API_KEY', 'TELEGRAM_ALERTS_BOT_TOKEN'):
                    self.assertIn(key, text)

    @unittest.skipUnless(PWSH, 'Set PWSH_BIN for Windows inert caller/state fixtures')
    def test_windows_runner_preserves_legacy_state_and_pi_failure_result(self):
        source = (ROOT / 'win.ps1').read_text()
        names = set(re.findall(r'^function ([\w-]+)(?=\s|\()', source, re.M))
        self.assertIn('Write-Section', names)
        code = "$ErrorActionPreference='Stop'\n" + '\n'.join(f'function {n} {{ return $true }}' for n in names)
        code += '\n' + function(source, 'Invoke-WindowsSetupTasks', True)
        code += r'''
function Prepare-PiProfilePermissions { $env:FAILURE -ne 'permissions' }
function Set-PiOpenCodeGoProvider { $env:FAILURE -ne 'go' }
function Prepare-PiMcpAdapter { $env:FAILURE -ne 'adapter' }
function Setup-PiMcpAdapter { Add-Content $env:EVENTS packages; return $true }
function Remove-CompoundEngineeringResources { Add-Content $env:EVENTS unrelated }
function Test-PendingReboot { Add-Content $env:EVENTS reboot }
try { Invoke-WindowsSetupTasks } catch { Add-Content $env:EVENTS failed; exit 1 }
finally { Add-Content $env:EVENTS finalized }
'''
        for failure in ('none', 'permissions', 'go', 'adapter'):
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as tmp:
                home = Path(tmp) / 'home'; home.mkdir(); seed(home)
                before = snapshot(home)
                events = Path(tmp) / 'events'
                fixture = Path(tmp) / 'caller.ps1'; fixture.write_text(code)
                runtime = Path(tmp) / 'runtime'; runtime.mkdir()
                result = subprocess.run([PWSH, '-NoProfile', '-File', str(fixture)], cwd=tmp,
                                        env={'PATH': os.environ['PATH'], 'HOME': str(home), 'USERPROFILE': str(home),
                                             'XDG_CACHE_HOME': str(runtime / 'cache'), 'XDG_CONFIG_HOME': str(runtime / 'config'),
                                             'XDG_DATA_HOME': str(runtime / 'data'), 'POWERSHELL_TELEMETRY_OPTOUT': '1',
                                             'EVENTS': str(events), 'FAILURE': failure, 'PASEO_CHANNEL': 'invalid'},
                                        capture_output=True, text=True, timeout=20)
                self.assertEqual(result.returncode, int(failure != 'none'), result.stdout + result.stderr)
                self.assertEqual(snapshot(home), before)
                calls = events.read_text().splitlines()
                self.assertIn('unrelated', calls)
                self.assertIn('reboot', calls)
                self.assertEqual(calls[-1], 'finalized')
                self.assertEqual('packages' in calls, failure == 'none')

    @unittest.skipUnless(DOTFILES, 'Set PASEO_UNMANAGED_DOTFILES_SOURCE for cross-repository source contract')
    def test_dotfiles_stops_distribution_without_target_deletion(self):
        root = Path(DOTFILES).resolve()
        for name in ('private_dot_local/private_bin/executable_paseo-enable-github-token',
                     'dot_config/systemd/user/paseo.service.d/github-token.conf'):
            self.assertFalse((root / name).exists())
        tracked = subprocess.check_output(['git', '-C', str(root), 'ls-files', '-z']).decode().split('\0')
        for name in filter(None, tracked):
            path = root / name
            if not path.is_file() or name == 'README.md' or name.startswith(('docs/', 'backlog/', 'tests/')):
                continue
            with self.subTest(path=name):
                self.assertNotIn('paseo', path.read_text(errors='replace').lower())
        self.assertNotIn('paseo', (root / '.chezmoiremove').read_text().lower())


if __name__ == '__main__':
    unittest.main(verbosity=2)
