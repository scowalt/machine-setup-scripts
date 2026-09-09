"""Exercise only the embedded installer, never the full provisioning scripts or real CLIs."""
import json
import os
from pathlib import Path
import subprocess
import shutil
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ('mac.sh', 'ubuntu.sh', 'wsl.sh', 'pi.sh', 'bazzite.sh', 'win.ps1')
NODE = shutil.which('node')


def installer(script):
    text = (ROOT / script).read_text()
    start = '// BEGIN PASEO PLAIN INSTALLER\n'
    end = '// END PASEO PLAIN INSTALLER'
    assert start in text, f'{script}: missing Paseo Plain installer'
    return text.split(start, 1)[1].split(end, 1)[0]


FAKE = r'''#!/usr/bin/env node
const fs = require('node:fs');
const path = require('node:path');
const home = process.env.PASEO_HOME;
const statePath = path.join(home, 'fake-state.json');
const state = JSON.parse(fs.readFileSync(statePath));
const args = process.argv.slice(2);
fs.appendFileSync(path.join(home, 'calls.jsonl'), JSON.stringify(args) + '\n');
const at = args.findIndex(a => ['daemon', 'plugin'].includes(a));
// Match the global arguments used by setup against Paseo 0.8's CLI contract.
// In particular, --home is NOT a global option, even before daemon status.
const globals = args.slice(0, at);
if (at < 0 || (globals.length && !(globals.length === 2 && globals[0] === '--host'))) {
  console.error(`error: unknown option '${globals[0]}'`);
  process.exit(1);
}
const command = args.slice(at);
if (command[0] === 'daemon' && command[1] === 'status') {
  console.log(JSON.stringify({localDaemon:'running', connectedDaemon:'reachable', home,
    listen:'127.0.0.1:19991', cliVersion:'0.8.0-beta.1', daemonVersion:'0.8.0-beta.1', ...state.status}));
} else if (command[0] === 'plugin' && command[1] === 'ls') {
  console.log(JSON.stringify(state.plugins || []));
} else if (command[0] === 'plugin' && command[1] === 'add') {
  if (state.fail) { console.error('provider-secret-must-not-be-logged'); process.exit(1); }
  state.plugins = [{id:'paseo-plain', source:'git', remote:'https://github.com/scowalt/paseo-plain.git',
    ref:'release', commit:'a'.repeat(40), enabled:true, status:'running'}];
  fs.writeFileSync(statePath, JSON.stringify(state));
  console.log(JSON.stringify(state.plugins[0]));
} else if (command[0] === 'plugin' && command[1] === 'update') {
  if (state.fail) { console.error('provider-secret-must-not-be-logged'); process.exit(1); }
  console.log(JSON.stringify([{id:'paseo-plain', updated:false}]));
} else { console.error('forbidden command'); process.exit(99); }
'''


@unittest.skipIf(os.name == 'nt', 'Fake CLI executables require POSIX; the PowerShell wrapper runs on POSIX')
class SetupTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='plain-setup-test-')
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.paseo = self.home / '.paseo'
        self.paseo.mkdir()
        self.bin = self.home / 'bin'
        self.bin.mkdir()
        for command in ('paseo', 'pi', 'npm', 'git'):
            file = self.bin / command
            file.write_text(FAKE if command == 'paseo' else '#!/bin/sh\nexit 99\n')
            file.chmod(0o700)
        self.env = {**os.environ, 'HOME': str(self.home), 'PASEO_HOME': str(self.paseo),
                    'PATH': f'{self.bin}{os.pathsep}{os.environ["PATH"]}'}
        self.state = {'plugins': []}
        self.configure()

    def configure(self, config=None):
        (self.paseo / 'config.json').write_text(json.dumps(
            config if config is not None else {'pluginsEnabled': True, 'daemon': {'listen': '127.0.0.1:19991'}}))

    def run_installer(self, script='ubuntu.sh', cwd=None):
        (self.paseo / 'fake-state.json').write_text(json.dumps(self.state))
        result = subprocess.run([NODE, '-'], input=installer(script), env=self.env, cwd=cwd,
                                text=True, capture_output=True, timeout=15)
        self.state = json.loads((self.paseo / 'fake-state.json').read_text())
        self.assertNotIn('provider-secret-must-not-be-logged', result.stdout + result.stderr)
        return result

    def calls(self):
        file = self.paseo / 'calls.jsonl'
        return [json.loads(line) for line in file.read_text().splitlines()] if file.exists() else []

    def test_fresh_install_targets_local_daemon_and_enables_only_manual_controls(self):
        result = self.run_installer()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('installed', result.stdout)
        plugin_calls = [args for args in self.calls() if 'plugin' in args]
        install = next(args for args in plugin_calls if 'add' in args)
        self.assertIn('https://github.com/scowalt/paseo-plain.git', install)
        self.assertEqual(install[install.index('--ref') + 1], 'release')
        for args in plugin_calls:
            self.assertEqual(args[args.index('--host') + 1], '127.0.0.1:19991')
        saved = json.loads((self.paseo / 'plugin-data/paseo-plain/configuration.json').read_text())
        self.assertTrue(saved['values']['enabled'])
        self.assertTrue(json.loads((self.paseo / 'config.json').read_text())['pluginsEnabled'])
        self.assertFalse(any('rewrite' in arg or 'preview' in arg for args in self.calls() for arg in args))

    def test_default_home_is_forwarded_when_environment_override_is_unset_or_empty(self):
        for override in (None, ''):
            with self.subTest(override=override):
                if override is None:
                    self.env.pop('PASEO_HOME', None)
                else:
                    self.env['PASEO_HOME'] = override
                result = self.run_installer()
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(self.state['plugins'][0]['id'], 'paseo-plain')
                self.assertEqual(self.state['plugins'][0]['status'], 'running')
                self.assertEqual(self.env.get('PASEO_HOME'), override)

    def test_relative_custom_home_is_resolved_before_child_working_directory_changes(self):
        default_home = self.paseo
        self.paseo = self.home / 'custom daemon home'
        default_home.rename(self.paseo)
        default_home.mkdir()
        untouched = default_home / 'config.json'
        untouched.write_text('{"pluginsEnabled":false,"unrelated":"keep me"}')
        before = untouched.read_bytes()
        invocation = self.home / 'invocation'
        invocation.mkdir()
        self.env['PASEO_HOME'] = '../custom daemon home'
        self.env['PASEO_HOST'] = '192.0.2.10:29992'
        self.configure({'pluginsEnabled': True, 'daemon': {'listen': '127.0.0.1:29992'}})
        self.state['status'] = {'listen': '127.0.0.1:29992'}

        for outcome in ('installed', 'checked for updates'):
            result = self.run_installer(cwd=invocation)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn(outcome, result.stdout)
        self.assertTrue((self.paseo / 'plugin-data/paseo-plain/configuration.json').is_file())
        for args in self.calls():
            if 'plugin' in args:
                self.assertEqual(args[args.index('--host') + 1], '127.0.0.1:29992')
        self.assertEqual(untouched.read_bytes(), before)
        self.assertEqual(list(default_home.iterdir()), [untouched])
        self.assertEqual(self.env['PASEO_HOME'], '../custom daemon home')

    def test_every_standalone_entry_uses_the_same_tested_installer_after_prerequisites(self):
        baseline = installer('ubuntu.sh')
        for script in SCRIPTS:
            self.assertEqual(installer(script), baseline, script)
            text = (ROOT / script).read_text()
            if script.endswith('.sh'):
                self.assertGreater(text.rindex('    install_paseo_plain') if script == 'bazzite.sh' else text.rindex('    if ! install_paseo_plain'),
                                   text.rindex('    if install_pi_cli; then'), script)
                if script != 'wsl.sh':
                    self.assertGreater(text.rindex('install_paseo_plain'), text.rindex('    setup_headless_paseo_daemon'), script)
            else:
                self.assertGreater(text.rindex('    if (-not (Install-PaseoPlain))'), text.rindex('    if (Install-PiCli)'), script)

    @unittest.skipIf(os.name == 'nt', 'headless CLI provisioning uses Bash')
    def test_headless_setup_retains_the_selected_channel_instead_of_pinning_old_beta(self):
        (self.bin / 'paseo').write_text('#!/bin/sh\nprintf "0.8.0-beta.1\\n"\n')
        (self.bin / 'bun').write_text('#!/bin/sh\nprintf "%s\\n" "$@" > "$HOME/bun-args"\nexit 1\n')
        (self.bin / 'bun').chmod(0o700)
        for script in ('mac.sh', 'ubuntu.sh', 'pi.sh', 'bazzite.sh'):
            text = (ROOT / script).read_text()
            function = 'install_paseo_cli() {' + text.split('install_paseo_cli() {', 1)[1].split('\nwrite_paseo_daemon_wrapper()', 1)[0]
            channels = 'paseo_release_channel() {' + text.split('paseo_release_channel() {', 1)[1].split('\npaseo_desktop_is_running()', 1)[0]
            # Extract only the requested functions. Never source a provisioning entry point.
            prelude = '''
PASEO_PACKAGE="@getpaseo/cli"
HEADLESS=1
_paseo_setup_channel=""
read_env_local_value() { return 1; }
ensure_pi_node_runtime() { node --version >/dev/null; }
print_message() { :; }; print_warning() { :; }; print_error() { :; }
paseo_service_path() { printf '%s' "$PATH"; }
paseo_command_target() { command -v paseo; }
'''
            for channel, tag in (('', 'beta'), ('beta', 'beta'), ('stable', 'latest')):
                result = subprocess.run(['bash'], input=prelude + channels + function + '\ninstall_paseo_cli\n',
                                        env={**self.env, 'PASEO_CHANNEL': channel}, text=True, capture_output=True, timeout=10)
                self.assertNotEqual(result.returncode, 0, 'fake Bun deliberately stops before any real install')
                self.assertIn(f'@getpaseo/cli@{tag}', (self.home / 'bun-args').read_text(), (script, channel))

    def test_missing_prerequisites_are_deferred_without_invoking_real_tools(self):
        self.env['PATH'] = ''
        result = self.run_installer()
        self.assertEqual(result.returncode, 0)
        self.assertIn('install Paseo and Pi', result.stdout)
        self.assertEqual(self.calls(), [])

    def test_nonlocal_configuration_is_rejected_before_cli_use(self):
        self.configure({'pluginsEnabled': True, 'daemon': {'listen': '192.0.2.10:19991'}})
        result = self.run_installer()
        self.assertEqual(result.returncode, 0)
        self.assertIn('loopback', result.stdout)
        self.assertEqual(self.calls(), [])

    def test_nonlocal_pid_endpoint_is_rejected_before_status_can_probe_it(self):
        for endpoint in ({'listen': '192.0.2.10:19991'}, {'sockPath': '/tmp/unsupported.sock'}):
            (self.paseo / 'paseo.pid').write_text(json.dumps({'pid': 123, **endpoint}))
            result = self.run_installer()
            self.assertEqual(result.returncode, 0)
            self.assertIn('deferred', result.stdout)
            self.assertEqual(self.calls(), [])

    def test_bash_entry_function_reports_a_deferred_install_without_failing_setup(self):
        if os.name == 'nt':
            self.skipTest('Bash wrapper is checked on POSIX')
        text = (ROOT / 'ubuntu.sh').read_text()
        function = 'install_paseo_plain() {' + text.split('install_paseo_plain() {', 1)[1].split('\ninstall_portless_cli()', 1)[0]
        self.configure({'pluginsEnabled': False})
        result = subprocess.run(['bash'], input='print_warning() { printf "%s\\n" "$1"; }; print_success() { printf "%s\\n" "$1"; };\n' + function + '\ninstall_paseo_plain\n',
                                env=self.env, text=True, capture_output=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('deferred', result.stdout)
        self.assertEqual(self.calls(), [])

    @unittest.skipUnless(os.environ.get('PWSH_BIN') or shutil.which('pwsh'), 'PowerShell is not available')
    def test_powershell_entry_function_runs_only_the_installer(self):
        ps = os.environ.get('PWSH_BIN') or shutil.which('pwsh')
        text = (ROOT / 'win.ps1').read_text()
        function = 'function Install-PaseoPlain {' + text.split('function Install-PaseoPlain {', 1)[1].split('\nfunction Install-PortlessCli', 1)[0]
        fixture = self.home / 'wrapper-test.ps1'
        fixture.write_text('function Write-Success($message) { Write-Host $message }\n' + function + '\n$ok = Install-PaseoPlain; if (-not $ok) { exit 1 }\n')
        (self.paseo / 'fake-state.json').write_text(json.dumps(self.state))
        for enabled in (True, False):
            self.configure({'pluginsEnabled': enabled})
            result = subprocess.run([ps, '-NoProfile', '-NonInteractive', '-File', str(fixture)],
                                    env={**self.env, 'POWERSHELL_TELEMETRY_OPTOUT':'1', 'POWERSHELL_UPDATECHECK':'Off'},
                                    text=True, capture_output=True, timeout=20)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('installed' if enabled else 'deferred', result.stdout)

    def test_rerun_updates_only_owned_release_and_preserves_all_settings(self):
        self.run_installer()
        settings = self.paseo / 'plugin-data/paseo-plain/configuration.json'
        custom = '{"values":{"enabled":false,"style":"My own voice","model":"custom"},"revision":7,"error":null}'
        settings.write_text(custom)
        cache = settings.parent / 'cache.json'
        cache.write_text('[{"text":"private cached text"}]')
        self.state['plugins'].append({'id': 'unrelated', 'enabled': True, 'status': 'running'})
        result = self.run_installer()
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(settings.read_text(), custom)
        self.assertEqual(cache.read_text(), '[{"text":"private cached text"}]')
        updates = [args for args in self.calls() if 'update' in args]
        self.assertEqual(len(updates), 1)
        self.assertEqual(updates[0][updates[0].index('update') + 1], 'paseo-plain')
        self.assertNotIn('--all', updates[0])
        self.assertEqual(len([args for args in self.calls() if 'add' in args]), 1)

    def test_disabled_global_switch_never_calls_paseo_or_changes_configuration(self):
        for config in ({}, {'pluginsEnabled': False}, {'pluginsEnabled': 'true'}):
            self.configure(config)
            before = (self.paseo / 'config.json').read_bytes()
            result = self.run_installer()
            self.assertEqual(result.returncode, 0)
            self.assertIn('deferred', result.stdout)
            self.assertEqual(self.calls(), [])
            self.assertEqual((self.paseo / 'config.json').read_bytes(), before)
            self.assertFalse((self.paseo / 'plugin-data').exists())

    def test_incompatible_or_unreachable_daemon_is_not_modified(self):
        for status in ({'daemonVersion':'0.7.2'}, {'cliVersion':'0.7.2'}, {'daemonVersion':'0.9.0'},
                       {'localDaemon':'stopped'}, {'connectedDaemon':'auth_failed'},
                       {'home': str(self.home)}, {'listen':'192.0.2.10:19991'}):
            self.state['status'] = status
            result = self.run_installer()
            self.assertEqual(result.returncode, 0)
            self.assertIn('deferred', result.stdout)
        self.assertFalse(any('plugin' in args for args in self.calls()))
        self.assertFalse((self.paseo / 'plugin-data').exists())

    def test_source_conflicts_and_disabled_installations_remain_untouched(self):
        for plugin in ({'source':'directory'}, {'source':'git','remote':'https://example.com/other.git','ref':'release'},
                       {'source':'git','remote':'https://github.com/scowalt/paseo-plain.git','ref':'main'}, {'enabled':False}):
            self.state['plugins'] = [{'id':'paseo-plain', **plugin}]
            result = self.run_installer()
            self.assertEqual(result.returncode, 0)
            self.assertIn('deferred', result.stdout)
        self.assertFalse(any('add' in args or 'update' in args for args in self.calls()))

    def test_malformed_settings_and_symlink_storage_are_preserved(self):
        directory = self.paseo / 'plugin-data/paseo-plain'
        directory.mkdir(parents=True)
        settings = directory / 'configuration.json'
        settings.write_text('not json')
        result = self.run_installer()
        self.assertEqual(result.returncode, 1)
        self.assertEqual(settings.read_text(), 'not json')
        settings.unlink()
        settings.symlink_to(self.home / 'missing.json')
        result = self.run_installer()
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(settings.is_symlink())
        self.assertFalse((self.home / 'missing.json').exists())
        self.assertFalse(any('add' in args or 'update' in args for args in self.calls()))

    def test_failed_update_keeps_old_preferences_and_does_not_print_cli_errors(self):
        self.run_installer()
        self.state['fail'] = True
        settings = self.paseo / 'plugin-data/paseo-plain/configuration.json'
        original = settings.read_bytes()
        result = self.run_installer()
        self.assertEqual(result.returncode, 1)
        self.assertNotIn('checked for updates', result.stdout)
        self.assertEqual(settings.read_bytes(), original)
        self.assertEqual(self.state['plugins'][0]['commit'], 'a' * 40)


if __name__ == '__main__':
    unittest.main()
