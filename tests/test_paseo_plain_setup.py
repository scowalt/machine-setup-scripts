"""Contract v5: retire Plain with legacy native PID modes, without daemon/permission changes."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ('mac.sh', 'ubuntu.sh', 'wsl.sh', 'pi.sh', 'bazzite.sh', 'win.ps1')
NODE = shutil.which('node')
PWSH = os.environ.get('PWSH_BIN') or shutil.which('pwsh')


def retirement(script='ubuntu.sh'):
    text = (ROOT / script).read_text()
    return text.split('// BEGIN PASEO PLAIN RETIREMENT\n', 1)[1].split('// END PASEO PLAIN RETIREMENT', 1)[0]


def wrapper(script):
    text = (ROOT / script).read_text()
    start, end = ('function Remove-PaseoPlain {', '\nfunction Install-PortlessCli') if script == 'win.ps1' else (
        'remove_paseo_plain() {', '\ninstall_portless_cli()')
    return start + text.split(start, 1)[1].split(end, 1)[0]


FAKE = r'''#!/usr/bin/env node
const fs = require('node:fs'), path = require('node:path'), assert = require('node:assert/strict');
const home = process.env.PASEO_HOME;
assert.equal(process.env.PASEO_HOST, undefined);
const statePath = path.join(home, 'fake-state.json');
const state = JSON.parse(fs.readFileSync(statePath));
const args = process.argv.slice(2);
fs.appendFileSync(path.join(home, 'calls.jsonl'), JSON.stringify(args) + '\n');
const at = args.indexOf('plugin');
const action = at < 0 ? 'status' : args[at + 1];
if (state.fail === action) { console.error('private-error-must-not-escape'); process.exit(23); }
if (state.invalid === action) { console.log('private-error-must-not-escape'); process.exit(0); }
if (state.pidAction && action === (state.pidActionAt || 'status')) {
  const pidFile = path.join(home, 'paseo.pid');
  if (state.pidAction === 'remote') {
    const pid = JSON.parse(fs.readFileSync(pidFile)); pid.listen = 'remote.example:19991';
    fs.writeFileSync(pidFile, JSON.stringify(pid));
  } else if (state.pidAction === 'inode') {
    const text = fs.readFileSync(pidFile); fs.renameSync(pidFile, pidFile + '.old');
    fs.writeFileSync(pidFile, text, {mode:0o664}); fs.chmodSync(pidFile, 0o664);
  } else if (state.pidAction === 'mode') fs.chmodSync(pidFile, 0o666);
  else if (state.pidAction === 'home-mode') fs.chmodSync(home, 0o755);
  else if (state.pidAction === 'heartbeat') fs.utimesSync(pidFile, new Date(), new Date());
  else throw new Error('invalid fixture mutation');
}
if (action === 'status') {
  assert.deepEqual(args, ['daemon', 'status', '--json']);
  console.log(JSON.stringify({localDaemon:'running', connectedDaemon:'reachable', home,
    listen:'127.0.0.1:19991', cliVersion:'0.8.0', daemonVersion:'0.8.0', ...state.status}));
} else {
  assert.deepEqual(args.slice(0, 3), ['--host', '127.0.0.1:19991', 'plugin']);
  if (action === 'ls') {
    assert.deepEqual(args.slice(3), ['ls', '--json']);
    if (state.changeConfig) {
      const file = path.join(home, 'config.json');
      const config = JSON.parse(fs.readFileSync(file));
      config.changed = true; fs.writeFileSync(file, JSON.stringify(config));
    }
    console.log(JSON.stringify(state.catalog ?? state.plugins));
  } else if (action === 'remove') {
    assert.deepEqual(args.slice(3), ['remove', 'paseo-plain', '--json']);
    if (state.timeout) { setInterval(() => {}, 1000); return; }
    if (!state.noop) {
      state.plugins = state.plugins.filter(p => p.id !== 'paseo-plain');
      const file = path.join(home, 'config.json');
      const config = JSON.parse(fs.readFileSync(file));
      delete config.plugins['paseo-plain'];
      if (state.changeUnrelated) delete config.plugins.unrelated;
      fs.writeFileSync(file, JSON.stringify(config));
      const sourcesFile = path.join(home, 'plugins/sources.json');
      if (fs.existsSync(sourcesFile)) {
        const sources = JSON.parse(fs.readFileSync(sourcesFile));
        if (sources['paseo-plain']) {
          delete sources['paseo-plain'];
          fs.writeFileSync(sourcesFile, JSON.stringify(sources));
          fs.rmSync(path.join(home, 'plugins/paseo-plain'), {recursive:true, force:true});
        }
      }
      fs.rmSync(path.join(home, 'plugin-settings/paseo-plain'), {recursive:true, force:true});
      fs.writeFileSync(statePath, JSON.stringify(state));
    }
    if (state.lostResponse) { console.error('private-error-must-not-escape'); process.exit(23); }
    console.log(JSON.stringify({id:'paseo-plain', enabled:false, status:'disabled'}));
  } else { throw new Error('forbidden operation'); }
}
'''


@unittest.skipIf(os.name == 'nt', 'Fake CLI uses POSIX executables; PowerShell wrapper is tested on POSIX')
class RetirementTest(unittest.TestCase):
    def setUp(self):
        previous_umask = os.umask(0o077)
        self.addCleanup(os.umask, previous_umask)
        temp = tempfile.TemporaryDirectory(prefix='plain-retirement-test-')
        self.addCleanup(temp.cleanup)
        self.home = Path(temp.name)
        self.paseo = self.home / '.paseo'
        self.paseo.mkdir()
        self.bin = self.home / 'bin'
        self.bin.mkdir()
        self.package = self.bin / 'node_modules/@getpaseo/cli'
        (self.package / 'bin').mkdir(parents=True)
        (self.package / 'package.json').write_text(json.dumps({
            'name': '@getpaseo/cli', 'version': '0.8.0', 'bin': {'paseo': 'bin/paseo'}}))
        (self.package / 'bin/paseo').write_text(FAKE)
        (self.bin / 'paseo').symlink_to(self.package / 'bin/paseo')
        (self.bin / 'paseo.cmd').write_text('@echo off\n')
        for name in ('node', 'bash', 'env'):
            (self.bin / name).symlink_to(shutil.which(name))
        for name in ('pi', 'npm', 'git', 'bun'):
            (self.bin / name).write_text('#!/bin/sh\nexit 99\n')
            (self.bin / name).chmod(0o700)
        self.env = {**os.environ, 'HOME': str(self.home), 'PASEO_HOME': str(self.paseo),
                    'PASEO_HOST': 'remote.example:9999', 'PATH': str(self.bin), 'PASEO_VALIDATED_CMD': ''}
        self.config = {'version': 1, 'pluginsEnabled': True, 'daemon': {'listen': '127.0.0.1:19991'},
                       'plugins': {'unrelated': {'source': 'directory', 'path': str(self.home / 'other'), 'enabled': False}}}
        self.state = {'plugins': [{'id': 'unrelated', 'enabled': False}]}
        self.save_config()

    def save_config(self):
        (self.paseo / 'config.json').write_text(json.dumps(self.config))

    def seed(self, managed=True, enabled=True, ref='main'):
        source = self.paseo / 'plugins/paseo-plain/aaaaaaaaaaaa-fixture/checkout' if managed else self.home / 'source'
        source.mkdir(parents=True, exist_ok=True)
        (source / 'index.server.ts').write_text('inert fixture; never execute')
        self.config['plugins']['paseo-plain'] = {'source': 'directory', 'path': str(source), 'enabled': enabled}
        self.state['plugins'].append({'id': 'paseo-plain', 'enabled': enabled, 'source': 'git' if managed else 'directory',
                                      'path': str(source), 'ref': ref})
        if managed:
            record = {'remote': 'https://example.invalid/custom.git', 'requestedRef': ref, 'trackingBranch': None,
                      'commit': 'a' * 40, 'pluginPath': '.', 'checkoutRoot': str(source)}
            (self.paseo / 'plugins/sources.json').write_text(json.dumps({'paseo-plain': record}))
        for relative, text in (('plugin-settings/paseo-plain/voice.json', 'malformed settings preserved verbatim'),
                               ('plugin-data/paseo-plain/configuration.json', '{"saved":"preferences"}'),
                               ('plugin-data/paseo-plain/cache.json', '["private cached text"]'),
                               ('setup-recovery/paseo-plain-release-to-main/state.json', '{"phase":"complete"}'),
                               ('setup-recovery/paseo-plain-release-to-main/checkout/keep.txt', 'old recovery source')):
            file = self.paseo / relative
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_text(text)
        self.save_config()
        return source

    def seed_legacy_pid_directory(self):
        # Match the deployed failure: a directory plugin, no managed store/settings,
        # and the PID mode native open('wx') produces under a legacy umask of 002.
        source = self.home / 'source'
        source.mkdir()
        (source / 'index.server.ts').write_text('inert source; never execute')
        self.config['plugins']['paseo-plain'] = {'source': 'directory', 'path': str(source), 'enabled': True}
        self.state['plugins'].append({'id': 'paseo-plain', 'enabled': True, 'status': 'running'})
        self.save_config()
        pid = self.paseo / 'paseo.pid'
        pid.write_text(json.dumps({'pid': 12345, 'uid': os.getuid(), 'hostname': 'fixture',
                                   'startedAt': '2026-09-16T09:00:00Z', 'listen': '127.0.0.1:19991'}))
        pid.chmod(0o664)
        return pid, source

    def test_legacy_native_pid_in_private_home_does_not_block_retirement(self):
        pid, source = self.seed_legacy_pid_directory()
        before = (pid.read_bytes(), pid.stat().st_mode, pid.stat().st_ino)
        self.assertEqual(self.paseo.stat().st_mode & 0o777, 0o700)
        self.assertFalse((self.paseo / 'plugins').exists())
        self.assertFalse((self.paseo / 'plugin-settings').exists())
        result = self.run_helper()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn('paseo-plain', json.loads((self.paseo / 'config.json').read_text())['plugins'])
        self.assertEqual((pid.read_bytes(), pid.stat().st_mode, pid.stat().st_ino), before)
        self.assertTrue(source.is_dir())
        self.assertEqual(len(self.removals()), 1)
        self.assertEqual(self.run_helper().returncode, 0)
        self.assertEqual(len(self.removals()), 1)

    def test_legacy_pid_all_wrappers_preserve_service_and_storage(self):
        scripts = SCRIPTS if PWSH else SCRIPTS[:-1]
        for script in scripts:
            with self.subTest(script=script):
                child = RetirementTest()
                child.setUp()
                try:
                    pid, source = child.seed_legacy_pid_directory()
                    protected = []
                    for relative in ('.config/systemd/user/paseo.service.d/fixture.conf',
                                     '.local/bin/paseo-daemon-start', '.paseo/plugin-data/paseo-plain/cache.json'):
                        file = child.home / relative
                        file.parent.mkdir(parents=True, exist_ok=True)
                        file.write_text('preserve this unrelated fixture data')
                        protected.append(file)
                    for directory in (child.home / '.config', child.home / '.config/systemd', child.home / '.config/systemd/user'):
                        directory.chmod(0o775)
                    protected += [pid, child.paseo, child.home / '.config/systemd/user', source]
                    def snapshot():
                        return [(p.stat().st_mode, p.stat().st_ino, p.read_bytes() if p.is_file() else None) for p in protected]
                    before = snapshot()
                    result = child.run_helper(script, wrapped=True)
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertEqual(snapshot(), before)
                    self.assertEqual(len(child.removals()), 1)
                    self.assertEqual(child.run_helper(script, wrapped=True).returncode, 0)
                    self.assertEqual(len(child.removals()), 1)
                finally:
                    child.doCleanups()

    def test_legacy_pid_requires_private_home_and_nonwritable_ancestors(self):
        pid, _ = self.seed_legacy_pid_directory()
        before = pid.read_bytes()
        for mode in (0o750, 0o755):
            self.paseo.chmod(mode)
            self.assert_failed(self.run_helper(), 'pid preflight: legacy-pid-requires-private-home')
            self.assertEqual(self.paseo.stat().st_mode & 0o777, mode)
        self.paseo.chmod(0o700)
        self.home.chmod(0o775)
        self.assert_failed(self.run_helper(), 'pid preflight: legacy-pid-unsafe-ancestor')
        self.assertEqual(self.home.stat().st_mode & 0o777, 0o775)
        self.assertEqual(pid.stat().st_mode & 0o777, 0o664)
        self.assertEqual(pid.read_bytes(), before)
        self.assertEqual(self.calls(), [])

    def test_legacy_pid_does_not_allow_other_writable_modes_or_hardlinks(self):
        pid, _ = self.seed_legacy_pid_directory()
        for mode in (0o660, 0o666, 0o777, 0o2664):
            pid.chmod(mode)
            self.assert_failed(self.run_helper(), 'pid preflight: unsafe-pid-permissions')
            self.assertEqual(pid.stat().st_mode & 0o7777, mode)
        pid.chmod(0o664)
        linked = self.home / 'other-pid-link'
        os.link(pid, linked)
        self.assert_failed(self.run_helper(), 'pid preflight: linked-pid-file')
        self.assertEqual(pid.read_bytes(), linked.read_bytes())
        self.assertEqual(self.calls(), [])

    def test_legacy_pid_does_not_allow_foreign_owner(self):
        self.seed_legacy_pid_directory()
        poison = """
const fixtureFs = require('node:fs'), fixtureLstat = fixtureFs.lstatSync;
fixtureFs.lstatSync = function(file, ...args) {
  const result = fixtureLstat.call(this, file, ...args);
  if (String(file).endsWith('/paseo.pid')) result.uid = process.getuid() + 1;
  return result;
};
"""
        self.assert_failed(self.run_helper(code=poison + retirement()), 'pid preflight: foreign-pid-owner')
        self.assertEqual(self.calls(), [])

    def test_legacy_pid_keeps_json_and_endpoint_guards(self):
        pid, _ = self.seed_legacy_pid_directory()
        for text, reason in (('{bad', 'pid preflight: invalid-json'),
                             ('{"listen":"127.0.0.1:19991","listen":"remote.example:19991"}', 'pid preflight: duplicate-key'),
                             ('{"listen":"remote.example:19991"}', 'nonlocal-pid-endpoint')):
            pid.write_text(text)
            self.assert_failed(self.run_helper(), reason)
        self.assertEqual(self.calls(), [])

    def test_legacy_pid_does_not_relax_config_or_source_registry_permissions(self):
        self.seed_legacy_pid_directory()
        config = self.paseo / 'config.json'
        config.chmod(0o664)
        self.assert_failed(self.run_helper(), 'preflight: unsafe-path')
        config.chmod(0o600)
        store = self.paseo / 'plugins'
        store.mkdir()
        registry = store / 'sources.json'
        registry.write_text('{}')
        registry.chmod(0o664)
        self.assert_failed(self.run_helper(), 'preflight: unsafe-path')
        self.assertEqual(self.calls(), [])

    def test_pid_changes_between_commands_block_before_mutation(self):
        for action in ('inode', 'mode', 'home-mode', 'remote'):
            for when in ('status', 'ls'):
                with self.subTest(action=action, when=when):
                    child = RetirementTest()
                    child.setUp()
                    try:
                        child.seed_legacy_pid_directory()
                        child.state.update(pidAction=action, pidActionAt=when)
                        child.assert_failed(child.run_helper(), 'pid preflight:')
                        self.assertEqual(child.removals(), [])
                        self.assertIn('paseo-plain', json.loads((child.paseo / 'config.json').read_text())['plugins'])
                    finally:
                        child.doCleanups()

    def test_native_pid_heartbeat_does_not_block_removal(self):
        self.seed_legacy_pid_directory()
        self.state['pidAction'] = 'heartbeat'
        result = self.run_helper()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(len(self.removals()), 1)

    def test_pid_leaf_swaps_do_not_follow_links_or_block_on_fifo(self):
        for kind in ('link', 'fifo'):
            with self.subTest(kind=kind):
                child = RetirementTest()
                child.setUp()
                try:
                    pid, _ = child.seed_legacy_pid_directory()
                    replacement = child.home / 'replacement'
                    if kind == 'fifo':
                        os.mkfifo(replacement)
                    else:
                        target = child.home / 'untouched'
                        target.write_text('not JSON; must not be read')
                        replacement.symlink_to(target)
                    poison = """
const fixtureFs = require('node:fs'), fixturePath = require('node:path'), fixtureOpen = fixtureFs.openSync;
let fixtureSwapped = false;
fixtureFs.openSync = function(file, ...args) {
  if (!fixtureSwapped && String(file).endsWith('/paseo.pid')) {
    fixtureSwapped = true;
    fixtureFs.renameSync(file, file + '.saved');
    fixtureFs.renameSync(fixturePath.join(process.env.HOME, 'replacement'), file);
  }
  return fixtureOpen.call(this, file, ...args);
};
"""
                    child.assert_failed(child.run_helper(code=poison + retirement()), 'pid preflight:')
                    self.assertEqual(child.calls(), [])
                    if kind == 'link':
                        self.assertEqual(target.read_text(), 'not JSON; must not be read')
                finally:
                    child.doCleanups()

    def run_helper(self, script='ubuntu.sh', code=None, wrapped=False):
        (self.paseo / 'fake-state.json').write_text(json.dumps(self.state))
        if wrapped and script == 'win.ps1':
            file = self.home / 'wrapper.ps1'
            file.write_text('function Write-Success($message) { Write-Host $message }\n' + wrapper(script) +
                            '\nif (-not (Remove-PaseoPlain)) { exit 1 }\n')
            args, content = [PWSH, '-NoProfile', '-NonInteractive', '-File', str(file)], None
        elif wrapped:
            args = [shutil.which('bash')]
            content = 'print_warning() { printf "%s\\n" "$1"; }; print_success() { printf "%s\\n" "$1"; };\n'
            content += wrapper(script) + '\nremove_paseo_plain\n'
        else:
            args, content = [NODE, '-'], code or retirement(script)
        result = subprocess.run(args, input=content, env=self.env, text=True, capture_output=True, timeout=20)
        self.state = json.loads((self.paseo / 'fake-state.json').read_text())
        self.assertNotIn('private-error-must-not-escape', result.stdout + result.stderr)
        return result

    def calls(self):
        file = self.paseo / 'calls.jsonl'
        return [json.loads(line) for line in file.read_text().splitlines()] if file.exists() else []

    def removals(self):
        return [args for args in self.calls() if 'remove' in args]

    def assert_failed(self, result, reason=None):
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        if reason:
            self.assertIn(reason, result.stdout)
        self.assertNotIn('Paseo Plain removed;', result.stdout)

    def test_absence_is_offline_noop_and_creates_no_storage(self):
        self.env['PATH'] = ''
        before = (self.paseo / 'config.json').read_bytes()
        result = self.run_helper()
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn('already absent', result.stdout)
        self.assertEqual(self.calls(), [])
        self.assertEqual((self.paseo / 'config.json').read_bytes(), before)
        self.assertFalse((self.paseo / 'setup-recovery').exists())
        self.env['PASEO_HOME'] = str(self.home / 'missing/nested')
        self.assertEqual(self.run_helper().returncode, 0)
        self.assertFalse((self.home / 'missing').exists())

    def test_removes_main_release_pinned_and_directory_even_disabled(self):
        # Each subcase uses a fresh fixture so backup reuse cannot conceal a retry bug.
        for managed, enabled, ref in ((True, True, 'main'), (True, False, 'release'),
                                      (True, True, 'a' * 40), (False, False, 'custom')):
            with self.subTest(managed=managed, enabled=enabled, ref=ref):
                child = RetirementTest()
                child.setUp()
                try:
                    source = child.seed(managed, enabled, ref)
                    child.config['pluginsEnabled'] = False
                    child.save_config()
                    data = child.paseo / 'plugin-data/paseo-plain/cache.json'
                    before = data.read_bytes()
                    result = child.run_helper()
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertEqual(data.read_bytes(), before)
                    self.assertEqual(source.exists(), not managed)
                    backup = child.paseo / 'setup-recovery/paseo-plain-retirement/plugin-settings/voice.json'
                    self.assertEqual(backup.read_text(), 'malformed settings preserved verbatim')
                    self.assertEqual(backup.stat().st_mode & 0o777, 0o600)
                    self.assertEqual(backup.parent.stat().st_mode & 0o777, 0o700)
                    self.assertTrue((child.paseo / 'setup-recovery/paseo-plain-release-to-main/checkout/keep.txt').exists())
                    saved = json.loads((child.paseo / 'config.json').read_text())
                    self.assertFalse(saved['pluginsEnabled'])
                    self.assertEqual(saved['plugins'], {'unrelated': child.config['plugins']['unrelated']})
                    self.assertEqual(len(child.removals()), 1)
                    self.assertEqual(child.run_helper().returncode, 0)
                    self.assertEqual(len(child.removals()), 1)
                finally:
                    child.doCleanups()

    def test_removal_without_native_settings_needs_no_backup(self):
        self.seed()
        shutil.rmtree(self.paseo / 'plugin-settings')
        result = self.run_helper()
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertFalse((self.paseo / 'setup-recovery/paseo-plain-retirement').exists())

    def test_custom_home_only_default_is_untouched(self):
        default = self.paseo
        self.paseo = self.home / 'custom home'
        self.paseo.mkdir()
        self.env['PASEO_HOME'] = str(self.paseo)
        before = (default / 'config.json').read_bytes()
        self.seed()
        self.assertEqual(self.run_helper().returncode, 0)
        self.assertEqual((default / 'config.json').read_bytes(), before)
        self.assertEqual(list(default.iterdir()), [default / 'config.json'])

    def test_unset_home_uses_default(self):
        self.seed()
        del self.env['PASEO_HOME']
        self.assertEqual(self.run_helper().returncode, 0)

    def test_invalid_home_never_falls_back(self):
        self.seed()
        for value in ('', '.', '../escape', str(self.home), str(self.home.parent / 'outside')):
            self.env['PASEO_HOME'] = value
            self.assert_failed(self.run_helper())
        self.assertEqual(self.calls(), [])

    def test_metadata_links_and_malformed_json_block_before_cli(self):
        self.seed()
        for relative in ('config.json', 'plugins/sources.json', 'paseo.pid'):
            file = self.paseo / relative
            original = file.read_text() if file.exists() else '{}'
            for text in ('{bad', '[]', '{"plugins":{},"plugins":{}}'):
                file.write_text(text)
                self.assert_failed(self.run_helper())
            file.write_text(original)
            target = self.home / 'outside-metadata'
            file.rename(target)
            file.symlink_to(target)
            self.assert_failed(self.run_helper(), 'unsafe-path')
            self.assertEqual(target.read_text(), original)
            file.unlink()
            target.rename(file)
        self.assertEqual(self.calls(), [])

    def test_linked_home_store_settings_or_ancestors_block(self):
        self.seed()
        for relative in ('plugins', 'plugins/paseo-plain', 'plugin-settings', 'plugin-settings/paseo-plain'):
            directory = self.paseo / relative
            target = self.home / 'outside-directory'
            directory.rename(target)
            directory.symlink_to(target, target_is_directory=True)
            self.assert_failed(self.run_helper(), 'unsafe-path')
            directory.unlink()
            target.rename(directory)
        alias = self.home / 'alias'
        alias.symlink_to(self.paseo, target_is_directory=True)
        self.env['PASEO_HOME'] = str(alias)
        self.assert_failed(self.run_helper(), 'unsafe-path')
        self.assertEqual(self.calls(), [])

    def test_writable_metadata_is_blocked_without_permission_changes(self):
        self.seed()
        file = self.paseo / 'config.json'
        file.chmod(0o664)
        before = file.read_bytes()
        self.assert_failed(self.run_helper(), 'unsafe-path')
        self.assertEqual(file.read_bytes(), before)
        self.assertEqual(file.stat().st_mode & 0o777, 0o664)
        self.assertEqual(self.calls(), [])

    def test_fifo_metadata_does_not_hang(self):
        self.seed()
        file = self.paseo / 'paseo.pid'
        os.mkfifo(file)
        self.assert_failed(self.run_helper(), 'unsafe-path')
        self.assertEqual(self.calls(), [])

    def test_nested_settings_links_are_rejected_and_targets_preserved(self):
        self.seed()
        target = self.home / 'private'
        target.write_text('keep')
        (self.paseo / 'plugin-settings/paseo-plain/link').symlink_to(target)
        self.assert_failed(self.run_helper(), 'unsafe-settings')
        self.assertEqual(target.read_text(), 'keep')
        self.assertEqual(self.removals(), [])

    def test_existing_or_incomplete_backups_block_without_overwrite(self):
        self.seed()
        journal = self.paseo / 'setup-recovery/paseo-plain-release-to-main/state.json'
        journal.write_text('{"phase":"adding"}')
        self.assert_failed(self.run_helper(), 'migration-needs-review')
        journal.write_text('{"phase":"complete"}')
        directory = self.paseo / 'setup-recovery/paseo-plain-retirement'
        directory.mkdir()
        (directory / 'keep').write_text('previous backup')
        self.assert_failed(self.run_helper(), 'retirement-backup-needs-review')
        self.assertEqual((directory / 'keep').read_text(), 'previous backup')
        self.assertEqual(self.removals(), [])

    def test_shared_managed_source_is_preserved(self):
        source = self.seed()
        self.config['plugins']['unrelated']['path'] = str(source)
        self.save_config()
        self.assert_failed(self.run_helper(), 'shared-source-needs-review')
        self.assertTrue(source.exists())
        self.assertEqual(self.calls(), [])

    def test_native_settings_source_and_shared_source_record_are_preserved(self):
        source = self.seed()
        self.config['plugins']['paseo-plain']['path'] = str(self.paseo / 'plugin-settings/paseo-plain')
        self.save_config()
        self.assert_failed(self.run_helper(), 'shared-source-needs-review')
        self.config['plugins']['paseo-plain']['path'] = str(source)
        self.save_config()
        registry = self.paseo / 'plugins/sources.json'
        records = json.loads(registry.read_text())
        records['unrelated'] = {**records['paseo-plain']}
        registry.write_text(json.dumps(records))
        self.assert_failed(self.run_helper(), 'shared-source-needs-review')
        self.assertTrue(source.exists())
        self.assertEqual(self.calls(), [])

    def test_preserved_storage_alias_into_deleted_tree_is_blocked(self):
        source = self.seed()
        original = self.paseo / 'plugin-data'
        original.rename(self.home / 'saved-data')
        original.symlink_to(source, target_is_directory=True)
        self.assert_failed(self.run_helper(), 'shared-source-needs-review')
        self.assertTrue(source.exists())
        self.assertEqual(self.calls(), [])

    def test_remote_endpoints_rejected_before_status(self):
        self.seed()
        for address in ('192.0.2.1:19991', '/tmp/socket', 'wss://example.invalid', '127.0.0.1:99999'):
            self.config['daemon']['listen'] = address
            self.save_config()
            self.assert_failed(self.run_helper(), 'nonlocal-endpoint')
        self.config['daemon']['listen'] = '127.0.0.1:19991'
        self.save_config()
        for value in ({'listen': 'remote.example:1234'}, {'sockPath': '/tmp/socket'},
                      {'listen': '127.0.0.1:19991', 'sockPath': 'remote.example:1234'}):
            (self.paseo / 'paseo.pid').write_text(json.dumps(value))
            self.assert_failed(self.run_helper(), 'nonlocal-pid-endpoint')
        self.assertEqual(self.calls(), [])

    def test_stopped_wrong_home_or_incompatible_daemon_deferred(self):
        self.seed()
        for status in ({'localDaemon': 'stopped'}, {'connectedDaemon': 'unreachable'},
                       {'home': str(self.home)}, {'listen': 'remote.example:1234'}, {'daemonVersion': '0.7.0'}):
            self.state['status'] = status
            self.assert_failed(self.run_helper(), 'removal deferred')
        self.assertEqual(self.removals(), [])

    def test_missing_cli_is_failure_not_silent_success(self):
        self.seed()
        self.env['PATH'] = ''
        self.assert_failed(self.run_helper(), 'compatible-cli-unavailable')
        self.assertEqual(self.calls(), [])

    def test_bad_cli_identity_is_never_executed(self):
        self.seed()
        metadata = self.package / 'package.json'
        original = metadata.read_text()
        for text in ('{bad', original.replace('@getpaseo/cli', 'foreign'),
                     original.replace('0.8.0', '0.4.0'), original.replace('bin/paseo', '../escape'),
                     original.replace('"version":', '"version":"0.4.0","version":')):
            metadata.write_text(text)
            self.assert_failed(self.run_helper(), 'compatible-cli-unavailable')
        self.assertEqual(self.calls(), [])

    def test_bun_cli_preferred_and_incompatible_managed_cli_blocks_fallback(self):
        self.seed()
        managed = self.home / '.bun/install/global/node_modules/@getpaseo/cli'
        shutil.copytree(self.package, managed)
        bindir = self.home / '.bun/bin'
        bindir.mkdir()
        (bindir / 'paseo').symlink_to(managed / 'bin/paseo')
        metadata = managed / 'package.json'
        metadata.write_text(metadata.read_text().replace('0.8.0', '0.9.0'))
        self.assert_failed(self.run_helper(), 'compatible-cli-unavailable')
        self.assertEqual(self.calls(), [])
        metadata.write_text(metadata.read_text().replace('0.9.0', '0.8.0'))
        (self.package / 'bin/paseo').write_text('process.exit(99)')
        self.assertEqual(self.run_helper().returncode, 0)

    def test_catalog_and_concurrent_config_change_block_removal(self):
        self.seed()
        for value in ({}, [None], [{'id': 'paseo-plain'}, {'id': 'paseo-plain'}], []):
            self.state['catalog'] = value
            self.assert_failed(self.run_helper())
        del self.state['catalog']
        self.state['changeConfig'] = True
        self.assert_failed(self.run_helper(), 'state-changed')
        self.assertEqual(self.removals(), [])

    def test_cli_failures_and_invalid_responses_have_safe_diagnostics(self):
        self.seed()
        for flag in ('fail', 'invalid'):
            for command in ('status', 'ls', 'remove'):
                self.state = {**self.state, flag: command}
                result = self.run_helper()
                self.assert_failed(result, 'exit-23' if flag == 'fail' else 'invalid-response-json')
                # Failed remove preserves settings and its exclusive recovery backup.
                backup = self.paseo / 'setup-recovery/paseo-plain-retirement'
                if backup.exists():
                    shutil.rmtree(backup)
            del self.state[flag]

    def test_timeout_retains_backup_and_does_not_retry_mutation(self):
        self.seed()
        self.state['timeout'] = True
        self.assert_failed(self.run_helper(code=retirement().replace('180000', '150')), 'timeout')
        self.assert_failed(self.run_helper(), 'retirement-backup-needs-review')
        self.assertEqual(len(self.removals()), 1)

    def test_lost_removal_response_never_reinstalls(self):
        self.seed()
        self.state['lostResponse'] = True
        self.assert_failed(self.run_helper(), 'exit-23')
        self.assertIn('already absent', self.run_helper().stdout)
        self.assertEqual(len(self.removals()), 1)
        self.assertTrue((self.paseo / 'setup-recovery/paseo-plain-retirement/plugin-settings/voice.json').exists())

    def test_noop_remove_and_unrelated_mutation_fail_verification(self):
        for flag in ('noop', 'changeUnrelated'):
            child = RetirementTest()
            child.setUp()
            try:
                child.seed()
                child.state[flag] = True
                child.assert_failed(child.run_helper(), 'removal-not-confirmed')
            finally:
                child.doCleanups()

    def test_orphan_sources_are_not_claimed_as_removed(self):
        self.seed()
        del self.config['plugins']['paseo-plain']
        self.save_config()
        self.assert_failed(self.run_helper(), 'orphan-source-needs-review')
        self.assertEqual(self.calls(), [])

    def test_all_bash_wrappers_propagate_failure(self):
        self.seed()
        for script in SCRIPTS[:-1]:
            self.state['fail'] = 'status'
            self.assert_failed(self.run_helper(script, wrapped=True), 'daemon status: exit-23')
        del self.state['fail']
        self.assertEqual(self.run_helper(wrapped=True).returncode, 0)
        self.assertIn('already absent', self.run_helper(wrapped=True).stdout)

    def test_wrappers_missing_node_and_unrecognized_output_fail_safely(self):
        self.seed()
        (self.bin / 'node').unlink()
        scripts = ('ubuntu.sh', 'win.ps1') if PWSH else ('ubuntu.sh',)
        for script in scripts:
            self.assert_failed(self.run_helper(script, wrapped=True), 'Node.js >=22.19 is required')
        fake = self.bin / 'node'
        fake.write_text('#!/bin/sh\necho private-error-must-not-escape\necho private-error-must-not-escape >&2\n')
        fake.chmod(0o700)
        for script in scripts:
            self.assert_failed(self.run_helper(script, wrapped=True), 'unexpected helper response')
        self.assertEqual(self.calls(), [])

    def test_explicit_cli_no_fallback(self):
        self.seed()
        self.env['PASEO_VALIDATED_CMD'] = str(self.home / 'missing')
        self.assert_failed(self.run_helper(wrapped=True), 'compatible-cli-unavailable')
        self.assertEqual(self.calls(), [])

    @unittest.skipUnless(PWSH, 'PowerShell is not available')
    def test_powershell_wrapper_success_absence_and_failure(self):
        self.seed()
        self.state['fail'] = 'status'
        self.assert_failed(self.run_helper('win.ps1', wrapped=True), 'daemon status: exit-23')
        del self.state['fail']
        self.assertEqual(self.run_helper('win.ps1', wrapped=True).returncode, 0)
        self.assertIn('already absent', self.run_helper('win.ps1', wrapped=True).stdout)

    def test_go_or_muse_failure_still_reaches_legacy_pid_retirement(self):
        pid, _ = self.seed_legacy_pid_directory()
        pid_before = (pid.read_bytes(), pid.stat().st_mode)
        text = (ROOT / 'ubuntu.sh').read_text()
        main = text.split('run_setup_tasks() {', 1)[1]
        block = main[main.index('    if ! prepare_pi_profile_permissions; then'):main.index('    print_section "Final Updates"')]
        inert = ('prepare_pi_profile_permissions', 'remove_rtk_resources', 'remove_attention_span_resources',
                 'setup_matt_pocock_skills', 'remove_pi_prose', 'install_pi_cli', 'configure_pi_defaults',
                 'remove_pi_synthetic_models', 'seed_pi_zai_models', 'remove_simple_english_skill',
                 'remove_show_me_skill', 'remove_pr_lens_skill', 'configure_pi_skill_ownership',
                 'remove_impeccable_resources', 'remove_compound_engineering_resources',
                 'prepare_pi_mcp_adapter', 'setup_pi_mcp_adapter', 'remove_pi_subagents',
                 'remove_pi_rpiv_packages', 'setup_pi_claude_bridge', 'setup_pi_companion_packages',
                 'setup_pi_goal_autoresearch')
        code = 'set -eu\n_setup_had_errors=0\n_pi_go_ready=0\nPI_PROFILE_MUTATIONS_BLOCKED=0\n'
        code += '\n'.join(f'{fn}() {{ :; }}' for fn in inert) + '\n'
        code += 'print_warning() { printf "%s\\n" "$1"; }; print_success() { printf "%s\\n" "$1"; };\n'
        code += 'configure_pi_opencode_go() { return "${GO_RESULT}"; }\n'
        code += 'configure_paseo_muse_profile() { PASEO_MUSE_DEFER_DAEMON_SETUP=1; print_warning "Paseo Muse deferred: process-inventory-unverified."; return 1; }\n'
        code += 'setup_headless_paseo_daemon() { printf unexpected-daemon > "$HOME/daemon-called"; return 1; }\n'
        code += wrapper('ubuntu.sh') + '\nexercise() {\n' + block + '\n}\nexercise\nprintf "continued:%s\\n" "${_setup_had_errors}"\n'
        for go_result in ('1', '0'):
            for fail in (True, False):
                self.save_config()
                self.state['fail'] = 'status' if fail else None
                (self.paseo / 'fake-state.json').write_text(json.dumps(self.state))
                result = subprocess.run([shutil.which('bash')], input=code,
                                        env={**self.env, 'GO_RESULT': go_result},
                                        text=True, capture_output=True, timeout=20)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn('continued:1', result.stdout)
                self.assertIn('removal failure' if fail else 'Paseo Plain removed;', result.stdout)
                self.assertFalse((self.home / 'daemon-called').exists())
                self.assertEqual((pid.read_bytes(), pid.stat().st_mode), pid_before)

    def test_shared_helpers_wiring_and_no_reinstallation(self):
        baseline = retirement()
        for script in SCRIPTS:
            text = (ROOT / script).read_text()
            self.assertEqual(retirement(script), baseline)
            self.assertNotIn('PLAIN INSTALLER', text)
            self.assertNotIn('install_paseo_plain', text)
            self.assertNotIn('Install-PaseoPlain', text)
            self.assertNotIn('https://github.com/scowalt/paseo-plain.git', text)
            if script.endswith('.sh'):
                self.assertGreater(text.rindex('    if ! remove_paseo_plain; then'), text.rindex('    elif install_pi_cli; then'))
                self.assertIn('    if ! remove_paseo_plain; then\n        _setup_had_errors=1\n    fi', text)
            else:
                self.assertGreater(text.rindex('    if (-not (Remove-PaseoPlain))'), text.rindex('    elseif (Install-PiCli)'))

    def test_legacy_pid_boundary_preserves_only_trusted_system_home_alias(self):
        if os.name == 'nt':
            self.skipTest('POSIX alias fixture')
        code = retirement()
        alias = code[code.index('function cliHomeAlias'):code.index('function cliDirectory')]
        boundary = code[code.index('function legacyPidBoundary'):code.index('function readPidState')]
        fixture = """
const path = require('node:path'), assert = require('node:assert/strict');
let target = '/var/home';
const fs = {readlinkSync: () => target};
const directory = mode => ({uid:0, mode, isDirectory:()=>true, isSymbolicLink:()=>false});
const aliasStat = {uid:0, mode:0o120777, isDirectory:()=>false, isSymbolicLink:()=>true};
const cliInfo = file => file === '/home' ? aliasStat : directory(0o755), info = cliInfo;
const checkedPath = () => directory(0o700);
class SetupFailure extends Error {}
""" + alias + boundary + """
if (process.platform === 'linux') legacyPidBoundary('/home/fixture/.paseo');
else assert.throws(() => legacyPidBoundary('/home/fixture/.paseo'));
target = '/untrusted';
assert.throws(() => legacyPidBoundary('/home/fixture/.paseo'), /legacy-pid-unsafe-ancestor/);
"""
        result = subprocess.run([NODE, '-'], input=fixture, text=True, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_linux_system_home_alias_identity_is_unchanged(self):
        code = retirement()
        start, end = code.index('function cliHomeAlias'), code.index('function cliRegular')
        fixture = '''const path = require('node:path'), assert = require('node:assert/strict');
const fs = {readlinkSync: () => '/var/home'};
const directory = () => ({uid:0, mode:0o755, isDirectory:()=>true, isSymbolicLink:()=>false});
const alias = {uid:0, mode:0o120777, isDirectory:()=>false, isSymbolicLink:()=>true};
const cliInfo = file => file === '/home' ? alias : directory();
''' + code[start:end] + "assert.equal(cliDirectory('/home'), process.platform === 'linux');"
        result = subprocess.run([NODE, '-'], input=fixture, text=True, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == '__main__':
    unittest.main()
