"""Extracted CLI maintenance fixtures. Never run setup or a live daemon."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
NODE = shutil.which('node')
BEGIN = '// BEGIN PASEO CLI CLEANUP'
END = '// END PASEO CLI CLEANUP'


def cleanup(script='ubuntu.sh'):
    text = (ROOT / script).read_text()
    return text[text.index(BEGIN):text.index(END) + len(END)]


class CleanupTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='paseo-cli-cleanup-')
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name) / 'home'
        self.home.mkdir(mode=0o700)
        self.retained = self.package(self.home / '.bun/install/global/node_modules', '0.8.0')
        self.retained_bin = self.home / '.bun/bin/paseo'
        self.retained_bin.parent.mkdir(parents=True)
        self.retained_bin.symlink_to(self.retained / 'bin/paseo')
        self.prefix = self.home / '.local/share/mise/installs/node/24.15.0'
        self.surplus = self.package(self.prefix / 'lib/node_modules', '0.4.0')
        self.command = self.prefix / 'bin/paseo'
        self.command.parent.mkdir(parents=True)
        self.command.symlink_to(self.surplus / 'bin/paseo')
        self.services = Path(self.temp.name) / 'services'
        self.services.mkdir()
        self.processes = ''
        self.extra = ''
        self.native_npm = False
        self.service_pid = ''
        self.service_state = ''
        self.runtime = ''

    def package(self, modules, version):
        root = modules / '@getpaseo/cli'
        (root / 'bin').mkdir(parents=True)
        (root / 'package.json').write_text(json.dumps({'name': '@getpaseo/cli', 'version': version,
                                                     'bin': {'paseo': 'bin/paseo'}}))
        (root / 'bin/paseo').write_text('#!/usr/bin/env node\nconsole.log("' + version + '")\n')
        (root / 'bin/paseo').chmod(0o755)
        return root

    def run_cleanup(self, script='ubuntu.sh'):
        # Replace OS inspection only. Package/home operations still reach real temporary files.
        prelude = r'''
const fs = require('node:fs'), cp = require('node:child_process');
const realSpawn = cp.spawnSync;
const services = process.env.FIXTURE_SERVICES;
const systemDirs = ['/etc/systemd/system', '/run/systemd/system', '/usr/lib/systemd/system', '/lib/systemd/system', '/etc/systemd/user'];
const map = p => {
  for (const dir of systemDirs) if (typeof p === 'string' && (p === dir || p.startsWith(dir + '/'))) return services + p.slice(dir.length);
  return p;
};
for (const name of ['readdirSync', 'lstatSync', 'statSync', 'readFileSync', 'readlinkSync']) {
  const original = fs[name];
  fs[name] = (p, ...args) => {
    if (name === 'readlinkSync' && typeof p === 'string' && p.startsWith('/proc/') && p.endsWith('/cwd')) return process.env.HOME;
    if (name === 'readFileSync' && typeof p === 'string' && p.startsWith('/proc/') && p.endsWith('/environ')) return Buffer.from('HOME=' + process.env.HOME + '\0');
    return original(map(p), ...args);
  };
}
if (process.env.FIXTURE_RUNTIME) Object.defineProperty(process, 'execPath', {value: process.env.FIXTURE_RUNTIME});
cp.spawnSync = (command, args, options) => {
  if (command === '/bin/ps') return {status: 0, stdout: process.env.FIXTURE_PROCESSES, stderr: ''};
  if (command === '/usr/bin/systemctl') return {status: process.env.FIXTURE_SERVICE ? 0 : 1,
    stdout: process.env.FIXTURE_SERVICE || '', stderr: ''};
  if (command === '/usr/bin/systemd-analyze') return {status: 0,
    stdout: systemDirs.concat(process.env.HOME + '/.config/systemd/user').join('\n') + '\n', stderr: ''};
  if (args.includes('--version')) return realSpawn(process.env.FIXTURE_REAL_NODE, args, options);
  if (args.includes('uninstall')) {
    const prefix = args[args.indexOf('--prefix') + 1];
    fs.appendFileSync(process.env.HOME + '/npm-calls', JSON.stringify(args) + '\n');
    if (process.env.FIXTURE_NPM_FAILURE) return {status: 1, stdout: 'PRIVATE-SENTINEL', stderr: 'PRIVATE-SENTINEL'};
    if (process.env.FIXTURE_NATIVE_NPM) return realSpawn(command, args, options);
    fs.unlinkSync(prefix + '/bin/paseo');
    fs.rmSync(prefix + '/lib/node_modules/@getpaseo/cli', {recursive: true});
    return {status: 0, stdout: '', stderr: ''};
  }
  throw Error('Unexpected external command');
};
'''
        file = Path(self.temp.name) / 'cleanup.cjs'
        # Scope the prelude to avoid colliding with the helper's imports.
        file.write_text('{\n' + prelude + self.extra + '\n}\n' + cleanup(script))
        env = {'PATH': os.environ['PATH'], 'HOME': str(self.home), 'FIXTURE_SERVICES': str(self.services),
               'FIXTURE_PROCESSES': self.processes, 'PASEO_HOME': str(self.home / '.paseo'),
               'FIXTURE_NATIVE_NPM': '1' if self.native_npm else ''}
        env['FIXTURE_SERVICE'] = self.service_state
        env['FIXTURE_RUNTIME'] = self.runtime
        env['FIXTURE_REAL_NODE'] = NODE
        if getattr(self, 'npm_failure', False):
            env['FIXTURE_NPM_FAILURE'] = '1'
        result = subprocess.run([NODE, str(file), str(self.home), str(self.retained_bin), self.service_pid],
                                env=env, text=True, capture_output=True, timeout=20)
        self.assertNotIn('PRIVATE-SENTINEL', result.stdout + result.stderr)
        return result

    def test_all_copies_and_platform_gates_match(self):
        baseline = cleanup()
        for script in ('ubuntu.sh', 'pi.sh', 'bazzite.sh', 'mac.sh'):
            self.assertEqual(cleanup(script), baseline)
            text = (ROOT / script).read_text()
            start = text.index('setup_headless_paseo_daemon() {')
            end = text.index('\n}\n', start)
            function = text[start:end]
            self.assertLess(function.index('wait_for_paseo_health'), function.index('cleanup_surplus_paseo_clis'))
            self.assertLess(function.index('HEADLESS'), function.index('cleanup_surplus_paseo_clis'))
            if script == 'mac.sh':
                self.assertLess(function.index('PASEO_MACOS_HEADLESS_CANARY'), function.index('cleanup_surplus_paseo_clis'))
        for script in ('win.ps1', 'wsl.sh'):
            self.assertNotIn(BEGIN, (ROOT / script).read_text())

    def test_failed_managed_convergence_or_health_never_calls_cleanup(self):
        inert = ('paseo_native_linux_preflight', 'paseo_macos_preflight', 'paseo_existing_managed_service_check',
                 'paseo_resolve_listen_target', 'stop_existing_paseo_daemon', 'paseo_listener_target_available',
                 'write_paseo_daemon_wrapper', 'paseo_service_owner_check', 'paseo_listener_audit')
        for script in ('ubuntu.sh', 'pi.sh', 'bazzite.sh', 'mac.sh'):
            text = (ROOT / script).read_text()
            start = text.index('setup_headless_paseo_daemon() {')
            function = text[start:text.index('\n}\n', start) + 3]
            prelude = '\n'.join(f'{name}() {{ :; }}' for name in inert) + '\n'
            prelude += 'HEADLESS=1\nPASEO_MACOS_HEADLESS_CANARY=1\n'
            prelude += "uname() { printf '%s\\n' '" + ('Darwin' if script == 'mac.sh' else 'Linux') + "'; }\n"
            prelude += 'print_error() { :; }; print_warning() { :; }; print_success() { :; };\n'
            prelude += 'configure_paseo_muse_profile() { [[ "$1" == verify-owner ]] || return 1; if [[ "${SCENARIO}" == owner-deferred ]]; then PASEO_MUSE_DEFER_DAEMON_SETUP=1; fi; }\n'
            prelude += 'install_paseo_cli() { [[ "${SCENARIO}" != cli-failure ]]; }\n'
            prelude += 'install_paseo_systemd_user_service() { [[ "${SCENARIO}" != restart-failure ]]; }\n'
            prelude += 'install_paseo_launchdaemon() { [[ "${SCENARIO}" != restart-failure ]]; }\n'
            prelude += 'wait_for_paseo_health() { [[ "${SCENARIO}" != health-failure ]]; }\n'
            prelude += 'paseo_linux_service_pid() { printf 4321; }; paseo_macos_service_pid() { printf 4321; };\n'
            prelude += 'cleanup_paseo_managed_service() { printf "service-failure-handled\\n"; }\n'
            prelude += 'cleanup_surplus_paseo_clis() { printf "cleanup:%s\\n" "$1"; }\n'
            for scenario in ('cli-failure', 'restart-failure', 'health-failure', 'owner-deferred', 'success'):
                with self.subTest(script=script, scenario=scenario):
                    result = subprocess.run(['bash'], input=prelude + function + '\nsetup_headless_paseo_daemon\n',
                        env={'PATH': os.environ['PATH'], 'HOME': str(self.home), 'SCENARIO': scenario},
                        text=True, capture_output=True, timeout=10)
                    self.assertEqual(result.returncode, 0 if scenario in ('success', 'owner-deferred') else 1, result.stdout + result.stderr)
                    self.assertEqual('cleanup:4321' in result.stdout, scenario == 'success')
                    if scenario in ('restart-failure', 'health-failure'):
                        self.assertIn('service-failure-handled', result.stdout)

    def test_unverified_retained_cli_prevents_removal(self):
        (self.retained / 'package.json').write_text('{PRIVATE-SENTINEL')
        result = self.run_cleanup()
        self.assertEqual(result.returncode, 1)
        self.assertIn('retained-unverified', result.stdout)
        self.assertTrue(self.surplus.exists())
        self.assertFalse((self.home / 'npm-calls').exists())

    def test_unusable_retained_cli_prevents_removal(self):
        (self.retained / 'bin/paseo').write_text('process.exit(1)')
        result = self.run_cleanup()
        self.assertEqual(result.returncode, 1)
        self.assertIn('retained-unusable', result.stdout)
        self.assertTrue(self.surplus.exists())

    def test_candidate_symlinks_and_unrelated_commands_are_preserved(self):
        original = self.surplus / 'package.json'
        moved = self.home / 'outside-package-json'
        original.rename(moved)
        original.symlink_to(moved)
        result = self.run_cleanup()
        self.assertEqual(result.returncode, 1)
        self.assertTrue(self.surplus.exists())
        self.assertTrue(original.is_symlink())
        original.unlink()
        moved.rename(original)
        self.command.unlink()
        self.command.write_text('#!/bin/sh\nexit 0\n')
        result = self.run_cleanup()
        self.assertEqual(result.returncode, 1)
        self.assertTrue(self.command.is_file())
        self.assertTrue(self.surplus.exists())

    def test_invalid_second_candidate_preflights_before_any_removal(self):
        package = self.package(self.home / '.local/lib/node_modules', '0.7.0')
        (package / 'package.json').write_text('{PRIVATE-SENTINEL')
        result = self.run_cleanup()
        self.assertEqual(result.returncode, 1)
        self.assertTrue(self.surplus.exists())
        self.assertTrue(package.exists())
        self.assertFalse((self.home / 'npm-calls').exists())

    def test_in_use_candidate_is_deferred_without_stopping_anything(self):
        self.processes = f'{os.getuid()} 4321 1 node {self.surplus}/bin/paseo daemon start\n'
        result = self.run_cleanup()
        self.assertEqual(result.returncode, 0)
        self.assertIn('paseo-cleanup:deferred:in-use', result.stdout)
        self.assertTrue(self.surplus.exists())
        self.assertFalse((self.home / 'npm-calls').exists())

    def test_stopped_service_reference_is_preserved(self):
        folder = self.home / '.config/systemd/user'
        folder.mkdir(parents=True)
        (folder / 'custom.service').write_text(f'[Service]\nExecStart={self.command} daemon start\n')
        result = self.run_cleanup()
        self.assertEqual(result.returncode, 0)
        self.assertIn('paseo-cleanup:deferred:service-reference', result.stdout)
        self.assertTrue(self.surplus.exists())

    def test_stopped_service_wrapper_reference_is_preserved(self):
        folder = self.home / '.config/systemd/user'
        folder.mkdir(parents=True)
        wrapper = self.home / 'my-daemon'
        wrapper.write_text(f'#!/bin/sh\nexec {self.command} daemon start\n')
        (folder / 'custom.service').write_text(f'[Service]\nExecStart={wrapper}\n')
        result = self.run_cleanup()
        self.assertIn('paseo-cleanup:deferred:service-reference', result.stdout)
        self.assertTrue(self.surplus.exists())

    def test_system_service_references_and_masked_units(self):
        masked = self.services / 'masked.service'
        masked.symlink_to('/dev/null')
        result = self.run_cleanup()
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertFalse(self.surplus.exists(), result.stdout)

    def test_system_service_candidate_reference_is_preserved(self):
        (self.services / 'legacy.service').write_text(f'[Service]\nExecStart={self.command} daemon start\n')
        result = self.run_cleanup()
        self.assertIn('paseo-cleanup:deferred:service-reference', result.stdout)
        self.assertTrue(self.surplus.exists())

    def test_unknown_paseo_process_is_preserved(self):
        self.processes = f'{os.getuid()} 4321 1 Paseo Daemon\n'
        result = self.run_cleanup()
        self.assertIn('paseo-cleanup:deferred:unknown-owner', result.stdout)
        self.assertTrue(self.surplus.exists())

    def seed_managed_service(self):
        self.service_pid = '4321'
        self.processes = (f'{os.getuid()} 4321 1 node {self.retained_bin} daemon start --foreground\n'
                          f'{os.getuid()} 4322 4321 Paseo Supervisor\n{os.getuid()} 4323 4322 Paseo Daemon\n')
        marker = 'Managed by scowalt machine setup: headless-paseo-daemon'
        wrapper = self.home / '.local/bin/paseo-daemon-start'
        wrapper.parent.mkdir(parents=True)
        wrapper.write_text(f"#!/bin/bash\n# {marker}\nset -euo pipefail\nexport HOME='{self.home}'\nexport PATH='/fixture/bin'\n"
                           f"[[ -x '{Path(self.runtime or NODE).resolve()}' ]] || exit 127\n[[ -x '{self.retained_bin}' ]] || exit 127\n"
                           f"export PASEO_SETUP_CLI='{self.retained_bin}'\n"
                           f"exec '{self.retained_bin}' daemon start --foreground --listen '127.0.0.1:6767'\n")
        wrapper.chmod(0o700)
        unit = self.home / '.config/systemd/user/paseo.service'
        unit.parent.mkdir(parents=True)
        unit.write_text(f'# {marker}\n[Service]\nExecStart={wrapper}\n')
        unit.chmod(0o600)
        group = f'/user.slice/user-{os.getuid()}.slice/user@{os.getuid()}.service/app.slice/paseo.service'
        self.service_state = '\n'.join(['Id=paseo.service', 'LoadState=loaded', 'ActiveState=active', 'SubState=running',
            'MainPID=4321', 'FragmentPath=' + str(unit), 'DropInPaths=', 'EnvironmentFiles=', 'NeedDaemonReload=no',
            'ControlGroup=' + group, 'ExecStart={ path=' + str(wrapper) + ' ; argv[]=' + str(wrapper) + ' ; }'])
        self.extra = '''
const read = fs.readFileSync;
fs.readFileSync = (p, ...args) => {
  if (['/proc/4321/environ', '/proc/4322/environ', '/proc/4323/environ'].includes(p)) return Buffer.from('HOME=' + process.env.HOME + '\\0PASEO_SETUP_CLI=' + process.env.HOME + '/.bun/bin/paseo\\0');
  if (['/proc/4321/cgroup', '/proc/4322/cgroup', '/proc/4323/cgroup'].includes(p)) return '0::/user.slice/user-' + process.getuid() + '.slice/user@' + process.getuid() + '.service/app.slice/paseo.service\\n';
  return read(p, ...args);
};
'''

    def test_verified_service_supervisor_and_daemon_titles_allow_cleanup(self):
        self.seed_managed_service()
        result = self.run_cleanup()
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertFalse(self.surplus.exists(), result.stdout)

    def test_process_titles_beyond_the_native_service_tree_remain_unverified(self):
        self.seed_managed_service()
        self.processes += f'{os.getuid()} 4324 4323 Paseo Supervisor\n'
        result = self.run_cleanup()
        self.assertIn('deferred', result.stdout)
        self.assertTrue(self.surplus.exists())

    def test_service_dropins_or_changed_loaded_pid_do_not_exempt_pathless_processes(self):
        self.seed_managed_service()
        original = self.service_state
        for before, after in (('DropInPaths=', 'DropInPaths=/custom/override.conf'),
                              ('MainPID=4321', 'MainPID=9999'), ('NeedDaemonReload=no', 'NeedDaemonReload=yes')):
            self.service_state = original.replace(before, after)
            result = self.run_cleanup()
            self.assertTrue(self.surplus.exists(), result.stdout)
            self.assertIn('deferred', result.stdout)
        self.assertFalse((self.home / 'npm-calls').exists())

    def test_other_home_worker_and_unrelated_pathless_daemon_are_preserved(self):
        self.seed_managed_service()
        self.extra += '''
const originalRead = fs.readFileSync;
fs.readFileSync = (p, ...args) => p === '/proc/4322/environ' ?
    Buffer.from('HOME=' + process.env.HOME + '\\0PASEO_HOME=/custom-home\\0') : originalRead(p, ...args);
'''
        result = self.run_cleanup()
        self.assertIn('deferred:unknown-owner', result.stdout)
        self.assertTrue(self.surplus.exists())

    def test_launch_origin_cwd_and_node_path_preserve_surplus_runtime_references(self):
        self.seed_managed_service()
        original = self.extra
        variants = [
            "const read = fs.readFileSync; fs.readFileSync = (p, ...a) => p === '/proc/4321/environ' ? Buffer.from('HOME=' + process.env.HOME + '\\0NODE_PATH=' + process.env.HOME + '/.local/share/mise/installs/node/24.15.0/lib/node_modules/@getpaseo/cli/node_modules\\0') : read(p, ...a);",
            "const link = fs.readlinkSync; fs.readlinkSync = (p, ...a) => p === '/proc/4321/cwd' ? process.env.HOME + '/.local/share/mise/installs/node/24.15.0/lib/node_modules/@getpaseo/cli' : link(p, ...a);",
            "const read = fs.readFileSync; fs.readFileSync = (p, ...a) => p === '/proc/4321/environ' ? Buffer.from('HOME=' + process.env.HOME + '\\0PASEO_SETUP_CLI=/old/launch/path\\0') : read(p, ...a);",
        ]
        for variant in variants:
            self.extra = original + '\n{\n' + variant + '\n}\n'
            result = self.run_cleanup()
            self.assertIn('deferred', result.stdout)
            self.assertTrue(self.surplus.exists(), result.stdout)
        self.assertFalse((self.home / 'npm-calls').exists())

    def test_wrapper_extra_shell_commands_cannot_prove_managed_ownership(self):
        self.seed_managed_service()
        wrapper = self.home / '.local/bin/paseo-daemon-start'
        wrapper.write_text(wrapper.read_text().rstrip() + ' & exec /usr/bin/env node /custom/other-cli.js\n')
        result = self.run_cleanup()
        self.assertIn('deferred:unknown-owner', result.stdout)
        self.assertTrue(self.surplus.exists())

    def test_verified_home_runtime_is_not_scanned_as_service_text(self):
        runtime = self.home / 'runtime/bin/node'
        runtime.parent.mkdir(parents=True)
        runtime.write_bytes(b'fixture-native-runtime' * 100000)
        runtime.chmod(0o700)
        package = self.home / 'runtime/lib/node_modules/npm'
        (package / 'bin').mkdir(parents=True)
        (package / 'package.json').write_text('{"name":"npm"}')
        (package / 'bin/npm-cli.js').write_text('fixture')
        self.runtime = str(runtime)
        self.seed_managed_service()
        result = self.run_cleanup()
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertFalse(self.surplus.exists(), result.stdout)

    def seed_macos_service(self):
        self.seed_managed_service()
        plist = self.services / 'com.scowalt.paseo-daemon.plist'
        plist.write_text('<plist><key>EnvironmentVariables</key><dict><key>HOME</key><string>' + str(self.home) + '</string></dict></plist>')
        plist.chmod(0o644)
        self.extra += r'''
Object.defineProperty(process, 'platform', {value: 'darwin'});
process.env.PASEO_MACOS_HEADLESS_CANARY = '1';
const launchFile = '/Library/LaunchDaemons/com.scowalt.paseo-daemon.plist';
const nativeMap = p => p === launchFile ? services + '/com.scowalt.paseo-daemon.plist' :
    typeof p === 'string' && (p === '/Library' || p.startsWith('/Library/') || p === '/System' || p.startsWith('/System/Library')) ? services : p;
for (const name of ['lstatSync', 'statSync', 'readFileSync']) {
  const original = fs[name];
  fs[name] = (p, ...a) => {
    const result = original(nativeMap(p), ...a);
    if ((name === 'lstatSync' || name === 'statSync') && p === launchFile) result.uid = 0;
    return result;
  };
}
const list = fs.readdirSync;
fs.readdirSync = (p, ...a) => p === '/Library/LaunchDaemons' ? list(services, ...a) :
    typeof p === 'string' && (p.startsWith('/Library/') || p.startsWith('/System/Library/')) ? [] : list(p, ...a);
const spawn = cp.spawnSync;
cp.spawnSync = (command, args, options) => {
  if (command === '/usr/bin/plutil') {
    const plist = {Label:'com.scowalt.paseo-daemon', UserName:require('node:os').userInfo().username,
      WorkingDirectory:process.env.HOME, ProgramArguments:[process.env.HOME + '/.local/bin/paseo-daemon-start'],
      EnvironmentVariables:{HOME:process.env.HOME, PATH:'/fixture/bin'}};
    if (process.env.FIXTURE_BAD_PLIST) plist.ProgramArguments = ['/custom/owner'];
    return {status:0, stdout:JSON.stringify(plist), stderr:''};
  }
  if (command === '/usr/bin/sudo') return {status:0, stdout:'path = ' + launchFile + '\nprogram = ' + process.env.HOME + '/.local/bin/paseo-daemon-start\npid = 4321\n', stderr:''};
  if (command === '/usr/sbin/lsof') return {status:0, stdout:'p' + args[2] + '\nn' + process.env.HOME + '\n', stderr:''};
  if (command === '/bin/ps' && args[0] === 'eww') return {status:0,
    stdout:'Paseo Daemon HOME=' + process.env.HOME + ' PASEO_SETUP_CLI=' + process.env.HOME + '/.bun/bin/paseo\n', stderr:''};
  return spawn(command, args, options);
};
'''

    def test_macos_verified_plist_and_process_origin_allow_cleanup(self):
        self.seed_macos_service()
        result = self.run_cleanup('mac.sh')
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertFalse(self.surplus.exists(), result.stdout)

    def test_macos_custom_loaded_owner_is_preserved(self):
        self.seed_macos_service()
        self.extra += "\nprocess.env.FIXTURE_BAD_PLIST = '1';\n"
        result = self.run_cleanup('mac.sh')
        self.assertIn('deferred', result.stdout)
        self.assertTrue(self.surplus.exists())

    def test_metadata_change_during_reference_probe_blocks_removal(self):
        self.extra = '''
const priorSpawn = cp.spawnSync;
let probes = 0;
cp.spawnSync = (command, args, options) => {
  if (command === '/bin/ps' && ++probes === 2) {
    fs.appendFileSync(process.env.HOME + '/.bun/install/global/node_modules/@getpaseo/cli/bin/paseo', '// concurrent edit');
  }
  return priorSpawn(command, args, options);
};
'''
        result = self.run_cleanup()
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn('metadata-changed', result.stdout)
        self.assertTrue(self.surplus.exists())
        self.assertFalse((self.home / 'npm-calls').exists())

    def test_unrelated_and_custom_installations_are_not_candidates(self):
        custom = self.package(self.home / 'custom-prefix/lib/node_modules', '0.4.0')
        project = self.package(self.home / 'Code/project/node_modules', '0.4.0')
        desktop = self.package(self.home / 'Applications/Paseo.app/Contents/Resources/node_modules', '0.4.0')
        result = self.run_cleanup()
        self.assertEqual(result.returncode, 0, result.stdout)
        for package in (custom, project, desktop):
            self.assertTrue(package.is_dir())
        self.assertFalse(self.surplus.exists())

    def test_string_bin_metadata_never_deletes_npm_normalized_cli_command(self):
        self.native_npm = True
        metadata = self.surplus / 'package.json'
        document = json.loads(metadata.read_text())
        document['bin'] = 'bin/paseo'
        metadata.write_text(json.dumps(document))
        self.command.unlink()
        unrelated = self.prefix / 'bin/cli'
        unrelated.write_text('unrelated command')
        result = self.run_cleanup()
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertEqual(unrelated.read_text(), 'unrelated command')
        self.assertTrue(self.surplus.exists())

    def test_bun_cache_hardlinks_do_not_reject_retained_package(self):
        for file in (self.retained / 'package.json', self.retained / 'bin/paseo'):
            os.link(file, self.home / (file.name + '-cache'))
        result = self.run_cleanup()
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertFalse(self.surplus.exists(), result.stdout)
        self.assertTrue((self.home / 'paseo-cache').is_file())

    def test_global_user_units_and_linked_dropin_directories_preserve_references(self):
        (self.services / 'old.service').write_text(f'[Service]\nExecStart={self.command}\n')
        self.extra = '''
const previous = fs.readdirSync;
fs.readdirSync = (p, ...args) => p === '/etc/systemd/user' ? previous(services, ...args) :
  systemDirs.includes(p) ? [] : previous(p, ...args);
const previousInfo = fs.lstatSync;
fs.lstatSync = (p, ...args) => p === '/etc/systemd/user' ? previousInfo(services, ...args) : previousInfo(p, ...args);
const previousRead = fs.readFileSync, previousStat = fs.statSync;
fs.readFileSync = (p, ...args) => typeof p === 'string' && p.startsWith('/etc/systemd/user/') ? previousRead(services + p.slice('/etc/systemd/user'.length), ...args) : previousRead(p, ...args);
fs.statSync = (p, ...args) => typeof p === 'string' && p.startsWith('/etc/systemd/user/') ? previousStat(services + p.slice('/etc/systemd/user'.length), ...args) : previousStat(p, ...args);
'''
        result = self.run_cleanup()
        self.assertTrue(self.surplus.exists(), result.stdout)
        self.assertIn('deferred', result.stdout)
        self.extra = ''
        (self.services / 'old.service').unlink()
        external = self.home / 'dropins'
        external.mkdir()
        (external / 'override.conf').write_text(f'[Service]\nExecStart={self.command}\n')
        folder = self.home / '.config/systemd/user'
        folder.mkdir(parents=True)
        (folder / 'example.service.d').symlink_to(external)
        result = self.run_cleanup()
        self.assertTrue(self.surplus.exists(), result.stdout)
        self.assertIn('deferred', result.stdout)

    def test_npm_failure_is_reported_without_output_or_false_success(self):
        self.npm_failure = True
        result = self.run_cleanup()
        self.assertEqual(result.returncode, 1)
        self.assertIn('paseo-cleanup:failed:npm-failed', result.stdout)
        self.assertTrue(self.surplus.exists())
        self.assertNotIn('removed:', result.stdout)

    def test_native_offline_npm_preserves_other_packages_and_ignores_scripts(self):
        self.native_npm = True
        metadata = self.surplus / 'package.json'
        data = json.loads(metadata.read_text())
        data['scripts'] = {'preuninstall': 'touch "$HOME/lifecycle-executed"', 'postuninstall': 'touch "$HOME/lifecycle-executed"'}
        metadata.write_text(json.dumps(data))
        other = self.prefix / 'lib/node_modules/unrelated'
        other.mkdir()
        (other / 'package.json').write_text('{"name":"unrelated","version":"1.0.0"}')
        before = (other / 'package.json').read_bytes()
        result = self.run_cleanup()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(self.surplus.exists())
        self.assertFalse((self.home / 'lifecycle-executed').exists())
        self.assertEqual((other / 'package.json').read_bytes(), before)
        args = json.loads((self.home / 'npm-calls').read_text().splitlines()[0])
        self.assertIn('--ignore-scripts', args)
        self.assertIn('--offline', args)

    def test_removes_old_mise_global_cli_and_preserves_retained_cli_and_data(self):
        data = self.home / '.paseo/config.json'
        data.parent.mkdir()
        data.write_text('{"private":"PRIVATE-SENTINEL"}')
        before = data.read_bytes()
        result = self.run_cleanup()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(self.surplus.exists())
        self.assertFalse(self.command.is_symlink())
        self.assertTrue(self.retained.is_dir())
        self.assertEqual(data.read_bytes(), before)
        self.assertIn('paseo-cleanup:removed:1', result.stdout)
        self.assertEqual(self.run_cleanup().returncode, 0)


if __name__ == '__main__':
    unittest.main()
