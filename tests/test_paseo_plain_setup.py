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
  if (state.failAt === 'disable-during-check') {
    const file = path.join(home, 'config.json');
    const config = JSON.parse(fs.readFileSync(file));
    config.pluginsEnabled = false;
    fs.writeFileSync(file, JSON.stringify(config));
  }
  console.log(JSON.stringify(state.plugins || []));
} else if (command[0] === 'plugin' && command[1] === 'add') {
  if (state.failAt === 'add-timeout') { setInterval(() => {}, 1000); return; }
  if (state.fail || state.failAt === 'add-before') { console.error('provider-secret-must-not-be-logged'); process.exit(1); }
  if (state.plugins.some(p => p.id === 'paseo-plain')) { console.error('ID already configured'); process.exit(1); }
  if (state.expectedNative && fs.readFileSync(path.join(home, 'plugin-settings/paseo-plain/voice.json'), 'utf8') !== state.expectedNative) {
    console.error('native settings not restored before activation'); process.exit(1);
  }
  const ref = command[command.indexOf('--ref') + 1];
  const commit = (state.addCommit || 'a').repeat(40);
  const checkout = path.join(home, 'plugins/paseo-plain', commit.slice(0, 12) + '-new', 'checkout');
  fs.mkdirSync(checkout, {recursive:true});
  fs.writeFileSync(path.join(checkout, 'index.server.ts'), 'new fixture plugin');
  const installed = {id:'paseo-plain', source:'git', remote:'https://github.com/scowalt/paseo-plain.git',
    ref, commit, path:checkout, enabled:true, status:state.failAt === 'add-after' ? 'failed' : 'running'};
  state.plugins.push(installed);
  const config = JSON.parse(fs.readFileSync(path.join(home, 'config.json')));
  config.plugins = {...config.plugins, 'paseo-plain':{source:'directory', path:checkout, enabled:true}};
  fs.writeFileSync(path.join(home, 'config.json'), JSON.stringify(config));
  const sourcesFile = path.join(home, 'plugins/sources.json');
  const sources = fs.existsSync(sourcesFile) ? JSON.parse(fs.readFileSync(sourcesFile)) : {};
  sources['paseo-plain'] = {remote:installed.remote, requestedRef:ref, trackingBranch:ref, commit, pluginPath:'.', checkoutRoot:checkout};
  fs.writeFileSync(sourcesFile, JSON.stringify(sources));
  fs.writeFileSync(statePath, JSON.stringify(state));
  if (['add-after', 'add-lost-response'].includes(state.failAt)) { console.error('provider-secret-must-not-be-logged'); process.exit(1); }
  console.log(JSON.stringify(installed));
} else if (command[0] === 'plugin' && command[1] === 'remove') {
  if (state.failAt === 'remove-before') { console.error('provider-secret-must-not-be-logged'); process.exit(1); }
  state.plugins = state.plugins.filter(p => p.id !== 'paseo-plain');
  const config = JSON.parse(fs.readFileSync(path.join(home, 'config.json')));
  delete config.plugins['paseo-plain'];
  fs.writeFileSync(path.join(home, 'config.json'), JSON.stringify(config));
  const sourcesFile = path.join(home, 'plugins/sources.json');
  const sources = JSON.parse(fs.readFileSync(sourcesFile));
  delete sources['paseo-plain'];
  fs.writeFileSync(sourcesFile, JSON.stringify(sources));
  fs.rmSync(path.join(home, 'plugins/paseo-plain'), {recursive:true, force:true});
  fs.rmSync(path.join(home, 'plugin-settings/paseo-plain'), {recursive:true, force:true});
  if (state.failAt === 'native-reappeared') {
    fs.mkdirSync(path.join(home, 'plugin-settings/paseo-plain'), {recursive:true});
    fs.writeFileSync(path.join(home, 'plugin-settings/paseo-plain/new.json'), 'new concurrent settings');
  }
  fs.writeFileSync(statePath, JSON.stringify(state));
  if (state.failAt === 'remove-after') { console.error('provider-secret-must-not-be-logged'); process.exit(1); }
  console.log(JSON.stringify({id:'paseo-plain', enabled:false, status:'disabled'}));
} else if (command[0] === 'plugin' && command[1] === 'update') {
  if (state.fail || command.includes('--ref')) { console.error('provider-secret-must-not-be-logged'); process.exit(1); }
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

    def run_installer(self, script='ubuntu.sh', cwd=None, cli_timeout=None):
        (self.paseo / 'fake-state.json').write_text(json.dumps(self.state))
        code = installer(script)
        if cli_timeout is not None:
            code = code.replace('180000', str(cli_timeout))
        result = subprocess.run([NODE, '-'], input=code, env=self.env, cwd=cwd,
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
        self.assertEqual(install[install.index('--ref') + 1], 'main')
        for args in plugin_calls:
            self.assertEqual(args[args.index('--host') + 1], '127.0.0.1:19991')
        saved = json.loads((self.paseo / 'plugin-data/paseo-plain/configuration.json').read_text())
        self.assertTrue(saved['values']['enabled'])
        self.assertTrue(json.loads((self.paseo / 'config.json').read_text())['pluginsEnabled'])
        self.assertFalse(any('rewrite' in arg or 'preview' in arg for args in self.calls() for arg in args))

    def seed_release(self):
        checkout = self.paseo / 'plugins/paseo-plain/aaaaaaaaaaaa-old/checkout'
        checkout.mkdir(parents=True)
        (checkout / 'index.server.ts').write_text('old fixture plugin')
        (checkout / 'paseo-plugin.json').write_text('{"id":"paseo-plain"}')
        record = {'remote': 'https://github.com/scowalt/paseo-plain.git', 'requestedRef': 'release',
                  'trackingBranch': 'release', 'commit': 'a' * 40, 'pluginPath': '.', 'checkoutRoot': str(checkout)}
        (self.paseo / 'plugins/sources.json').write_text(json.dumps({'paseo-plain': record, 'unrelated': {'keep': True}}))
        self.configure({'pluginsEnabled': True, 'daemon': {'listen': '127.0.0.1:19991'}, 'unrelated': 'keep',
                        'plugins': {'paseo-plain': {'source': 'directory', 'path': str(checkout), 'enabled': True},
                                    'unrelated': {'source': 'directory', 'path': '/fixture/other', 'enabled': False}}})
        self.state['plugins'] = [{'id': 'paseo-plain', 'source': 'git', 'remote': record['remote'],
                                 'ref': 'release', 'commit': record['commit'], 'path': str(checkout),
                                 'enabled': True, 'status': 'running'}, {'id': 'unrelated', 'enabled': False}]
        self.state['addCommit'] = 'b'
        data = self.paseo / 'plugin-data/paseo-plain'
        data.mkdir(parents=True, exist_ok=True)
        (data / 'configuration.json').write_text('{"values":{"enabled":false,"style":"Keep my voice"},"revision":7,"error":null}')
        (data / 'cache.json').write_text('[{"text":"private cached text"}]')
        native = self.paseo / 'plugin-settings/paseo-plain'
        native.mkdir(parents=True, exist_ok=True)
        (native / 'voice.json').write_text('{"custom":"native setting"}\n')
        self.state['expectedNative'] = (native / 'voice.json').read_text()
        return checkout

    def test_release_migration_preserves_state_and_runs_only_once(self):
        checkout = self.seed_release()
        data = self.paseo / 'plugin-data/paseo-plain'
        before = {p.name: p.read_bytes() for p in data.iterdir()}
        result = self.run_installer()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('migrated', result.stdout)
        installed = next(p for p in self.state['plugins'] if p['id'] == 'paseo-plain')
        self.assertEqual(installed['ref'], 'main')
        self.assertEqual(installed['status'], 'running')
        self.assertFalse(checkout.exists())
        self.assertEqual({p.name: p.read_bytes() for p in data.iterdir()}, before)
        native = self.paseo / 'plugin-settings/paseo-plain/voice.json'
        self.assertEqual(native.read_text(), self.state['expectedNative'])
        recovery = self.paseo / 'setup-recovery/paseo-plain-release-to-main'
        self.assertEqual(json.loads((recovery / 'state.json').read_text())['phase'], 'complete')
        self.assertEqual((recovery / 'checkout/index.server.ts').read_text(), 'old fixture plugin')
        self.assertEqual((recovery / 'checkout').stat().st_mode & 0o777, 0o700)
        self.assertTrue((recovery / 'RECOVERY.md').is_file())
        config = json.loads((self.paseo / 'config.json').read_text())
        self.assertEqual(config['unrelated'], 'keep')
        self.assertFalse(config['plugins']['unrelated']['enabled'])
        self.assertEqual(json.loads((self.paseo / 'plugins/sources.json').read_text())['unrelated'], {'keep': True})
        result = self.run_installer()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('checked for updates', result.stdout)
        self.assertEqual(sum('remove' in args for args in self.calls()), 1)
        self.assertEqual(sum('add' in args for args in self.calls()), 1)
        self.assertEqual(sum('update' in args for args in self.calls()), 1)

    def assert_stopped_migration_is_not_retried(self, failure, phase):
        checkout = self.seed_release()
        data = self.paseo / 'plugin-data/paseo-plain'
        before = {p.name: p.read_bytes() for p in data.iterdir()}
        self.state['failAt'] = failure
        result = self.run_installer(cli_timeout=300)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn('migration stopped', result.stdout)
        recovery = self.paseo / 'setup-recovery/paseo-plain-release-to-main'
        self.assertEqual(json.loads((recovery / 'state.json').read_text())['phase'], phase)
        self.assertEqual((recovery / 'checkout/index.server.ts').read_text(), 'old fixture plugin')
        self.assertEqual({p.name: p.read_bytes() for p in data.iterdir()}, before)
        self.assertEqual(checkout.exists(), failure == 'remove-before')
        mutations = [args for args in self.calls() if any(op in args for op in ('remove', 'add', 'update'))]
        self.state.pop('failAt')
        result = self.run_installer()
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn('migration stopped', result.stdout)
        self.assertEqual([args for args in self.calls() if any(op in args for op in ('remove', 'add', 'update'))], mutations)
        self.assertEqual(sum('remove' in args for args in mutations), 1)

    def test_failed_removal_keeps_recovery_and_blocks_retries(self):
        self.assert_stopped_migration_is_not_retried('remove-before', 'removing')

    def test_lost_removal_response_does_not_trigger_install_or_restore(self):
        self.assert_stopped_migration_is_not_retried('remove-after', 'removing')
        self.assertFalse(any('add' in args for args in self.calls()))
        self.assertFalse((self.paseo / 'plugin-settings/paseo-plain').exists())

    def test_failed_new_install_keeps_recovery_and_restored_native_settings(self):
        self.assert_stopped_migration_is_not_retried('add-before', 'adding')
        self.assertEqual((self.paseo / 'plugin-settings/paseo-plain/voice.json').read_text(), self.state['expectedNative'])

    def test_failed_activation_is_not_removed_by_a_retry(self):
        self.assert_stopped_migration_is_not_retried('add-after', 'adding')
        self.assertEqual(next(p for p in self.state['plugins'] if p['id'] == 'paseo-plain')['status'], 'failed')

    def test_lost_success_response_keeps_running_main_and_blocks_retries(self):
        self.assert_stopped_migration_is_not_retried('add-lost-response', 'adding')
        self.assertEqual(next(p for p in self.state['plugins'] if p['id'] == 'paseo-plain')['status'], 'running')

    def test_timed_out_install_keeps_recovery_and_blocks_retries(self):
        self.assert_stopped_migration_is_not_retried('add-timeout', 'adding')

    def test_restore_does_not_overwrite_reappearing_native_settings(self):
        self.assert_stopped_migration_is_not_retried('native-reappeared', 'restoring')
        self.assertEqual((self.paseo / 'plugin-settings/paseo-plain/new.json').read_text(), 'new concurrent settings')
        self.assertFalse(any('add' in args for args in self.calls()))

    def test_disabled_release_and_unverified_tracking_metadata_are_not_migrated(self):
        self.seed_release()
        self.state['plugins'][0]['enabled'] = False
        result = self.run_installer()
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn('disabled', result.stdout)
        self.state['plugins'][0]['enabled'] = True
        sources = self.paseo / 'plugins/sources.json'
        original = json.loads(sources.read_text())
        for change in ({'trackingBranch': None}, {'commit': 'b' * 40}, {'pluginPath': 'other'},
                       {'checkoutRoot': str(self.home)}, {'remote': 'https://example.com/other.git'}):
            with self.subTest(change=change):
                invalid = {**original, 'paseo-plain': {**original['paseo-plain'], **change}}
                sources.write_text(json.dumps(invalid))
                result = self.run_installer()
                self.assertEqual(result.returncode, 1, result.stdout)
        self.assertFalse((self.paseo / 'setup-recovery').exists())
        self.assertFalse(any('remove' in args or 'add' in args for args in self.calls()))

    def test_unsafe_backup_link_is_rejected_before_removal(self):
        checkout = self.seed_release()
        target = self.home / 'outside'
        target.write_text('do not copy this outside data')
        (checkout / 'external-link').symlink_to(target)
        result = self.run_installer()
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertTrue(checkout.exists())
        self.assertFalse(any('remove' in args for args in self.calls()))
        self.assertEqual(target.read_text(), 'do not copy this outside data')

    def test_concurrent_trust_change_aborts_before_removal(self):
        checkout = self.seed_release()
        self.state['failAt'] = 'disable-during-check'
        result = self.run_installer()
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertTrue(checkout.exists())
        self.assertFalse(json.loads((self.paseo / 'config.json').read_text())['pluginsEnabled'])
        self.assertFalse(any('remove' in args or 'add' in args for args in self.calls()))

    def test_windows_backup_permission_failure_copies_no_state_and_removes_nothing(self):
        self.seed_release()
        for name in ('paseo', 'pi'):
            shutil.copyfile(self.bin / name, self.bin / (name + '.exe'))
            (self.bin / (name + '.exe')).chmod(0o700)
        windows = self.home / 'Windows'
        powershell = windows / 'System32/WindowsPowerShell/v1.0/powershell.exe'
        powershell.parent.mkdir(parents=True)
        powershell.write_text('#!/bin/sh\nexit 1\n')
        powershell.chmod(0o700)
        (self.paseo / 'fake-state.json').write_text(json.dumps(self.state))
        code = "Object.defineProperty(process, 'platform', {value:'win32'});\n" + installer('ubuntu.sh')
        result = subprocess.run([NODE, '-'], input=code, env={**self.env, 'SystemRoot': str(windows)},
                                text=True, capture_output=True, timeout=15)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        recovery = self.paseo / 'setup-recovery/paseo-plain-release-to-main'
        self.assertTrue(recovery.is_dir())
        self.assertEqual(list(recovery.iterdir()), [])
        self.assertFalse(any('remove' in args or 'add' in args for args in self.calls()))

    def test_internal_relative_checkout_links_survive_recovery_copy(self):
        checkout = self.seed_release()
        (checkout / 'internal-link').symlink_to('index.server.ts')
        result = self.run_installer()
        self.assertEqual(result.returncode, 0, result.stdout)
        copied = self.paseo / 'setup-recovery/paseo-plain-release-to-main/checkout/internal-link'
        self.assertTrue(copied.is_symlink())
        self.assertEqual(copied.read_text(), 'old fixture plugin')

    def test_symlinked_or_incomplete_recovery_records_never_allow_a_fresh_install(self):
        recovery = self.paseo / 'setup-recovery/paseo-plain-release-to-main'
        recovery.mkdir(parents=True)
        for contents in ('not json', '{"version":1,"from":"release","to":"main","phase":"adding"}'):
            (recovery / 'state.json').write_text(contents)
            result = self.run_installer()
            self.assertEqual(result.returncode, 1)
            self.assertFalse((self.paseo / 'plugin-data').exists())
        (recovery / 'state.json').unlink()
        (recovery / 'state.json').symlink_to(self.home / 'nonexistent')
        result = self.run_installer()
        self.assertEqual(result.returncode, 1)
        self.assertFalse(any('add' in args for args in self.calls()))
        self.assertFalse((self.home / 'nonexistent').exists())

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
        self.seed_release()
        (self.paseo / 'fake-state.json').write_text(json.dumps(self.state))
        result = subprocess.run([ps, '-NoProfile', '-NonInteractive', '-File', str(fixture)],
                                env={**self.env, 'POWERSHELL_TELEMETRY_OPTOUT':'1', 'POWERSHELL_UPDATECHECK':'Off'},
                                text=True, capture_output=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('migrated from release to main', result.stdout)

    def test_rerun_updates_only_owned_main_and_preserves_all_settings(self):
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
                       {'source':'git','remote':'https://github.com/scowalt/paseo-plain.git','ref':'custom'}, {'enabled':False}):
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
