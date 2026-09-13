"""Offline Muse profile/lifecycle contracts. No live Paseo, Pi or service commands.

Upstream evidence (installed @getpaseo 0.8.0, read-only):
protocol/dist/messages.js AgentProfileSchema.id is z.string(), so colons are valid.
server/dist/src/server/pid-lock.js uses paseo.pid with exclusive creation, a live
owner PID, and desktopManaged; supervisor-entrypoint acquires it before workers.
DaemonConfigStore owns the mutable profiles in memory and replaces whole arrays.
The fixture mocks OS inventory, signals and every child command before execution.
The optional PASEO_MUSE_PID_LOCK_MODULE proof imports only upstream 0.8.0's lock
module in temporary Node contenders; it never executes a daemon or worker.
"""
import json
import os
from pathlib import Path
import shutil
import shlex
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ('mac.sh', 'ubuntu.sh', 'wsl.sh', 'pi.sh', 'bazzite.sh', 'win.ps1')
NODE = shutil.which('node')
PWSH = os.environ.get('PWSH_BIN') or shutil.which('pwsh')
NATIVE_PID_LOCK = os.environ.get('PASEO_MUSE_PID_LOCK_MODULE')
ID = 'setup:pi:opencode-go:muse-spark-1.3-contributor'
CORE = {'provider': 'pi', 'model': 'opencode-go/muse-spark-1.3-contributor', 'thinkingOptionId': 'xhigh'}
PROFILE = {'id': ID, 'name': 'Muse 1.3 Contributor', **CORE}
SECRET = 'fixture-private-text-never-print'


def embedded(script):
    return (ROOT / script).read_text().split('// BEGIN PASEO MUSE PROFILE\n', 1)[1].split('// END PASEO MUSE PROFILE', 1)[0]


PRELOAD = r'''
const fs = require('node:fs'), path = require('node:path'), os = require('node:os');
const cp = require('node:child_process');
const root = process.env.MUSE_FIXTURE_ROOT;
const stateFile = path.join(root, 'state.json');
const state = JSON.parse(fs.readFileSync(stateFile));
const original = Object.fromEntries(['readFileSync','writeFileSync','statSync','lstatSync','readdirSync','openSync','renameSync','unlinkSync','realpathSync','readlinkSync','mkdirSync','existsSync'].map(k => [k,fs[k].bind(fs)]));
const diskHome = path.join(root, 'home');
const home = state.aliasHome ? '/var/home/fixture' : diskHome;
const logicalHome = state.aliasHome ? (state.physicalHome ? home : '/home/fixture') : state.logicalHome || home;
const paseo = state.selectedHome || path.join(home, '.paseo');
const pidFile = path.join(paseo, 'paseo.pid');
const config = path.join(paseo, 'config.json');
const uid = process.getuid();
const platform = state.platform || 'linux';
Object.defineProperty(process, 'platform', {value:platform});
os.homedir = () => logicalHome;
os.userInfo = () => ({homedir:state.accountHome || logicalHome, uid, username:'fixture'});
os.hostname = () => 'fixture-machine';
os.release = () => state.wsl ? 'microsoft-standard-WSL2' : 'fixture';
state.calls = [];
state.nodeOptions = process.env.NODE_OPTIONS ?? null;
state.nodePath = process.env.NODE_PATH ?? null;
state.forbiddenRead = false;
state.running = !!state.running;
const saved = () => original.writeFileSync(stateFile, JSON.stringify(state));
process.on('exit', saved);
function error(code) { const e = new Error('fixture-private-text-never-print'); e.code=code; throw e; }
function procRows() {
  const rows = [{pid:process.pid,parent:state.unknownAncestor ? 4999 : state.selfHosted ? 4202 : 4100,command:'node fixture.js',env:{HOME:home},cgroup:state.selfGroup ? '0:'+group() : '0::/session.scope'},
    {pid:4100,parent:state.foreignAncestor ? 4202 : 1,uid:state.foreignAncestor ? uid+1 : uid,command:'bash setup.sh',env:{HOME:home},cgroup:'0::/session.scope'}];
  if (state.running) {
    rows.push({pid:4200,parent:1,command:'node managed-entrypoint.js',env:{HOME:home},cgroup:'0:'+group()});
    rows.push({pid:4202,parent:4200,command:state.renamed ? 'nonstandard-binary' : 'node /pkg/@getpaseo/server/supervisor-entrypoint.js',
      env:{HOME:state.ownerHome || home, ...(Object.hasOwn(state, 'ownerPaseoHome') ? {PASEO_HOME:state.ownerPaseoHome} : {})},cgroup:'0:'+group()});
  }
  if (state.otherWriter || state.leftover) rows.push({pid:4300,parent:1,command:state.otherWriter || 'renamed-worker',
    env:{HOME:home,PASEO_HOME:paseo},cgroup:state.leftover ? '0:'+group() : '0::/other.scope'});
  return rows;
}
function group() { return `:/user.slice/user-${uid}.slice/user@${uid}.service/app.slice/paseo.service`; }
function procFile(file) {
  const m = String(file).match(/^\/proc\/(\d+)\/(stat|cmdline|environ|cgroup)$/);
  if (!m) return null;
  if (state.inventoryDenied) error('EACCES');
  const row = procRows().find(p=>p.pid===Number(m[1]));
  if (!row) error('ENOENT');
  if(m[2]==='stat') return `${row.pid} (fixture) S ${row.parent} 0 0 0`;
  if(m[2]==='cmdline') return row.command.replaceAll(' ','\0');
  if(m[2]==='environ') return Object.entries(row.env).map(([k,v])=>`${k}=${v}`).join('\0');
  return row.cgroup;
}
const plist = '/Library/LaunchDaemons/com.scowalt.paseo-daemon.plist';
function mapped(file) {
  if(file===plist) return path.join(root,'managed.plist');
  if(state.aliasHome && typeof file==='string') {
    for(const prefix of ['/home/fixture','/var/home/fixture']) {
      if(file===prefix || file.startsWith(prefix+'/')) return path.join(diskHome,path.relative(prefix,file));
    }
  }
  return file;
}
fs.existsSync = file => original.existsSync(mapped(file));
fs.mkdirSync = (file,...args) => original.mkdirSync(mapped(file),...args);
fs.unlinkSync = file => original.unlinkSync(mapped(file));
fs.realpathSync = function(file,...args) {
  if(state.aliasHome && ['/home/fixture','/var/home/fixture'].includes(file)) return '/var/home/fixture';
  return original.realpathSync(file,...args);
};
fs.readFileSync = function(file,...args) { const p=procFile(file); if(p!==null) return p; return original.readFileSync(mapped(file),...args); };
fs.statSync = function(file,...args) { if(/^\/proc\/\d+$/.test(String(file))) return {uid:procRows().find(p=>p.pid===Number(String(file).split('/').pop()))?.uid ?? uid}; return original.statSync(mapped(file),...args); };
fs.lstatSync = function(file,...args) {
  if((state.alias || state.aliasHome) && ['/home','/var','/var/home'].includes(file)) {
    return {uid:state.aliasBadOwner ? 99 : 0,mode:state.aliasWritable ? 0o777 : 0o755,
      isSymbolicLink:()=>file==='/home',isDirectory:()=>file!=='/home',isFile:()=>false};
  }
  if(file==='/Library'||file==='/Library/LaunchDaemons') return {uid:0,mode:0o755,isDirectory:()=>true,isSymbolicLink:()=>false};
  const s=original.lstatSync(mapped(file),...args); if(file===plist) {s.uid=state.plistBadOwner ? 99 : 0;} return s;
};
fs.readlinkSync = function(file,...args) {if((state.alias || state.aliasHome) && file==='/home') return state.aliasTarget || '/var/home'; return original.readlinkSync(file,...args);};
fs.readdirSync = function(file,...args) { if(file==='/proc') return procRows().map(p=>String(p.pid)); return original.readdirSync(file,...args); };
process.kill = function(pid, signal) {
  if(signal!==0) throw new Error('FORBIDDEN real signal');
  if(state.killDenied) error('EPERM');
  if(procRows().some(p=>p.pid===pid)) return true;
  error('ESRCH');
};
const aclSelf = 'S-1-5-21-fixture';
const aclTrusted = [aclSelf, 'S-1-5-18', 'S-1-5-32-544'];
const aclWrites = 278 | 64 | 65536 | 262144 | 524288;
function fixtureAcl(file) { return state.windowsAcls?.[file] || {owner:aclSelf,rules:[]}; }
function checkAcl(file, privateHome=false) {
  const acl=fixtureAcl(file);
  if(acl.nullDacl || (privateHome ? acl.owner!==aclSelf : !aclTrusted.includes(acl.owner))) return false;
  return !acl.rules.some(rule => rule.type!=='Deny' && !(rule.inheritOnly && !privateHome) && !aclTrusted.includes(rule.sid) &&
    ((privateHome && file===paseo) || (rule.rights & aclWrites)));
}
const opened = new Map();
fs.openSync = function(file,...args) {
  if((state.forbiddenReadPaths || []).includes(String(file))) { state.forbiddenRead=true; error('EACCES'); }
  if(file===pidFile && args[0]==='wx' && state.nativeContender) {
    state.otherWriter='new-native-owner';
    original.writeFileSync(mapped(pidFile), JSON.stringify({pid:4300,uid,hostname:'fixture-machine',startedAt:'2026-01-01T00:00:00Z',listen:null}));
  }
  if(String(file).includes('.config.setup-muse-') && state.concurrentEdit) {
    original.writeFileSync(mapped(config),JSON.stringify({concurrent:state.concurrentEdit}));
  }
  if(String(file).includes('.config.setup-muse-') && state.writeFailure) error('EIO');
  const fd=original.openSync(mapped(file),...args); opened.set(fd,file); return fd;
};
fs.writeFileSync = function(file,...args) {
  if(typeof file==='number' && opened.get(file)===pidFile && state.pidWriteFailure) error('EIO');
  return original.writeFileSync(mapped(file),...args);
};
fs.renameSync = function(from,to,...args) {
  if(to===config) {
    const lock=JSON.parse(original.readFileSync(mapped(pidFile),'utf8'));
    if(lock.pid!==process.pid || state.running) throw new Error('MUTATION WITHOUT NATIVE STOPPED LOCK');
    state.calls.push(['atomic-merge']);
    if(state.renameFailure) error('EIO');
  }
  const result=original.renameSync(mapped(from),mapped(to),...args);
  if(state.windowsAcls && Object.hasOwn(state.windowsAcls,from)) { state.windowsAcls[to]=state.windowsAcls[from]; delete state.windowsAcls[from]; }
  return result;
};
function nativePid() {
  original.writeFileSync(mapped(pidFile),JSON.stringify({pid:4202,uid,hostname:'fixture-machine',startedAt:'2026-01-01T00:00:00Z',listen:'127.0.0.1:6767'}));
}
function stop() {
  if(!state.stopLeavesRunning) {
    state.running=false;
    if(fs.existsSync(pidFile)) original.unlinkSync(mapped(pidFile));
    if(state.shutdownConfig) original.writeFileSync(mapped(config),JSON.stringify(state.shutdownConfig));
  }
  if(state.interruptAfterStop) process.emit('SIGTERM');
  if(state.newWriterAfterStop) state.otherWriter='new-nonstandard-writer';
  if(Object.hasOwn(state,'managerEnvAfterStop')) state.managerEnv=state.managerEnvAfterStop;
  if(Object.hasOwn(state,'macManagerEnvAfterStop')) state.macManagerEnv=state.macManagerEnvAfterStop;
  saved();
  return !state.stopFailure;
}
function start() { if(state.startFailure) return false; state.running=true; nativePid(); saved(); return true; }
function show() {
  const wrapper=path.join(home,'.local/bin/paseo-daemon-start');
  const values={Id:'paseo.service',LoadState:'loaded',ActiveState:state.running?'active':'inactive',SubState:state.running?'running':'dead',MainPID:state.running?'4200':'0',
    FragmentPath:path.join(home,'.config/systemd/user/paseo.service'),DropInPaths:'',NeedDaemonReload:'no',ControlGroup:group().slice(1),User:'',
    ExecStart:`{ path=${wrapper} ; argv[]=${wrapper} ; }`,Environment:`HOME=${home} PATH=/fixture/bin`,EnvironmentFiles:'',KillMode:'control-group',...state.serviceOverrides};
  return Object.entries(values).map(([k,v])=>`${k}=${v}`).join('\n')+'\n';
}
cp.spawnSync = function(command,args,options) {
  state.calls.push([command,...args]); saved();
  if(!options || options.shell!==false || options.env.PASEO_HOME!==paseo || options.env.HOME!==logicalHome) throw new Error('UNPINNED CHILD');
  const result=(stdout='',ok=true)=>({status:ok?0:1,stdout,stderr:'fixture-private-text-never-print'});
  if(command==='powershell.exe' && !args[3].startsWith('$env:PSModulePath = "$PSHOME\\Modules"; ')) throw new Error('UNPINNED POWERSHELL MODULE PATH');
  if(state.commandDenied) return result('',false);
  if(command==='systemctl') {
    if(state.directBusFailure && args[0]==='--user') return result('',false);
    const a=args.slice(args.indexOf('--user')+1);
    if(a[0]==='show') return result(show());
    if(a[0]==='show-environment') return result(state.managerEnv || 'PATH=/fixture/bin\n');
    if(a[0]==='stop'&&a[1]==='paseo.service') return result('',stop());
    if(a[0]==='start'&&a[1]==='paseo.service') return result('',start());
  }
  if(command==='ps') {
    if(args[0]==='-axww') return result(procRows().map(p=>`${p.pid} ${p.parent} ${p.uid ?? uid} ${p.command}`).join('\n'));
    if(args[0]==='eww') return result(`nonstandard-binary HOME=${state.ownerHome||home}${Object.hasOwn(state,'ownerPaseoHome') ? ' PASEO_HOME='+state.ownerPaseoHome : ''}\n`);
  }
  if(command==='powershell.exe' && args[3].includes('Get-CimInstance Win32_Process')) return result(JSON.stringify(procRows().map(p=>({ProcessId:p.pid,ParentProcessId:p.parent,Name:p.command,CommandLine:p.command,ExecutablePath:'C:\\fixture'}))));
  if(command==='powershell.exe' && args[3].includes('PASEO_MUSE_ACL_PATHS')) {
    const paths=JSON.parse(options.env.PASEO_MUSE_ACL_PATHS);
    if(paths.at(-1)!==home || paths.some(file => (file!==home && !file.startsWith(home+'/')) || !original.existsSync(mapped(file)))) throw new Error('ACL BOUNDARY NOT VERIFIED');
    (state.aclChecks ||= []).push(paths);
    if(state.windowsAclCommandFailure || !paths.every(file => checkAcl(file))) return result('',false);
    return result(state.windowsAclMissingReceipt ? '' : 'ok');
  }
  if(command==='powershell.exe' && args[3].includes('PASEO_MUSE_ACCOUNT_HOME')) {
    for(let current=paseo;;current=path.dirname(current)) {
      if(state.customAclFailure || !checkAcl(current,true)) return result('',false);
      if(current===home) return result('');
    }
  }
  if(command==='powershell.exe' && args[3].includes('Set-Acl -LiteralPath')) {
    const target=options.env.PASEO_MUSE_TEMP;
    if(!target.startsWith(paseo+'/.config.setup-muse-')) throw new Error('ACL WRITE OUTSIDE STAGED CONFIG');
    if(original.readFileSync(mapped(target),'utf8')!=='') throw new Error('ACL MUST PRECEDE DATA WRITE');
    if(state.aclFailure) return result('',false);
    state.windowsAcls ||= {};
    state.windowsAcls[target]=options.env.PASEO_MUSE_EXISTING==='1' ? structuredClone(fixtureAcl(config)) : {owner:aclSelf,rules:[]};
    return result('');
  }
  if(command==='plutil') return result(JSON.stringify({Label:'com.scowalt.paseo-daemon',UserName:'fixture',WorkingDirectory:home,
    ProgramArguments:[path.join(home,'.local/bin/paseo-daemon-start')],EnvironmentVariables:{HOME:home,PATH:'/fixture/bin'},RunAtLoad:true,KeepAlive:true,...state.plistOverrides}));
  if(command==='sudo'&&args[0]==='-n'&&args[1]==='launchctl') {
    if(args[2]==='list') return result('PID\tStatus\tLabel\n'+(state.running?'4200\t0\tcom.scowalt.paseo-daemon\n':''));
    if(args[2]==='print' && args[3]==='system') return result(`system = {\nenvironment = {\n${state.macManagerEnv || ''}\n}\n}`);
    if(args[2]==='print') return result(`path = ${plist}\nprogram = ${home}/.local/bin/paseo-daemon-start\n`);
    if(args[2]==='bootout') return result('',stop());
    if(args[2]==='bootstrap') return result('',start());
  }
  throw new Error('FORBIDDEN child command');
};
'''


class MuseProfileTests(unittest.TestCase):
    def setUp(self):
        previous_umask = os.umask(0o077)
        self.addCleanup(os.umask, previous_umask)
        self.temp = tempfile.TemporaryDirectory(prefix='muse-fixture-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.home = self.root / 'home'
        self.home.mkdir()
        self.paseo = self.home / '.paseo'
        self.paseo.mkdir()
        self.config = self.paseo / 'config.json'
        self.state = {}
        self.preload = self.root / 'preload.cjs'
        self.preload.write_text(PRELOAD)
        self.env = {'PATH': os.environ['PATH'], 'HOME': str(self.home), 'MUSE_FIXTURE_ROOT': str(self.root)}

    def run_helper(self, script='ubuntu.sh', suffix=''):
        (self.root / 'state.json').write_text(json.dumps(self.state))
        code = self.root / 'profile.cjs'
        code.write_text(embedded(script) + suffix)
        result = subprocess.run([NODE, '--require', str(self.preload), str(code)], env=self.env,
                                text=True, capture_output=True, timeout=15)
        self.state = json.loads((self.root / 'state.json').read_text())
        self.assertNotIn(SECRET, result.stdout + result.stderr)
        self.assertEqual(result.stderr, '', result.stderr)
        return result

    def select_home(self, directory):
        directory.mkdir(parents=True, mode=0o700, exist_ok=True)
        self.paseo = directory
        self.config = directory / 'config.json'
        self.state['selectedHome'] = str(directory)
        self.env['PASEO_HOME'] = str(directory)

    def save(self, config):
        self.config.write_text(json.dumps(config))

    def read_config(self):
        return json.loads(self.config.read_text())

    def managed(self):
        return next(p for p in self.read_config()['daemon']['agentProfiles'] if p['id'] == ID)

    def seed_service(self, platform='linux'):
        self.state.update(running=True, platform=platform)
        self.env['HEADLESS'] = '1'
        self.env['PASEO_MACOS_HEADLESS_CANARY'] = '1'
        uid = os.getuid()
        (self.paseo / 'paseo.pid').write_text(json.dumps({'pid': 4202, 'uid': uid, 'hostname': 'fixture-machine',
            'startedAt': '2026-01-01T00:00:00Z', 'listen': '127.0.0.1:6767'}))
        wrapper = self.home / '.local/bin/paseo-daemon-start'
        wrapper.parent.mkdir(parents=True, exist_ok=True)
        wrapper.write_text(f"#!/bin/bash\n# Managed by scowalt machine setup: headless-paseo-daemon\nset -euo pipefail\nexport HOME='{self.home}'\nexport PATH='/fixture/bin'\n[[ -x '/fixture/node' ]] || exit 127\n[[ -x '/fixture/paseo' ]] || exit 127\nexec '/fixture/paseo' daemon start --foreground --listen '127.0.0.1:6767'\n")
        service = self.home / '.config/systemd/user/paseo.service'
        service.parent.mkdir(parents=True, exist_ok=True)
        service.write_text(f'# Managed by scowalt machine setup: headless-paseo-daemon\n[Unit]\nDescription=Paseo headless daemon\nDocumentation=https://www.getpaseo.com/\n\n[Service]\nType=simple\nExecStart={self.home}/.local/bin/paseo-daemon-start\nWorkingDirectory={self.home}\nEnvironment=HOME={self.home}\nEnvironment=PATH=/fixture/bin\nRestart=on-failure\nRestartSec=5\n\n[Install]\nWantedBy=default.target\n')
        (self.root / 'managed.plist').write_text('<!-- Managed by scowalt machine setup: headless-paseo-daemon -->')

    def mutations(self):
        return [c for c in self.state.get('calls', []) if c == ['atomic-merge'] or any(a in c for a in ('stop', 'start', 'bootout', 'bootstrap'))]

    def assert_deferred(self, reason):
        before = self.config.read_bytes() if self.config.exists() else None
        result = self.run_helper()
        self.assertIn(reason, result.stdout)
        self.assertIn('PASEO_MUSE_DEFER_DAEMON_SETUP=1', result.stdout)
        self.assertIn('outside Paseo', result.stdout)
        self.assertEqual(self.config.read_bytes() if self.config.exists() else None, before)
        self.assertEqual(self.mutations(), [])
        return result

    def test_embedded_code_identical(self):
        for script in SCRIPTS:
            self.assertEqual(embedded(script), embedded('ubuntu.sh'), script)

    def test_fresh_seed_all_platforms_without_key_or_paseo(self):
        for platform in ('linux', 'darwin', 'win32'):
            with self.subTest(platform=platform):
                self.state = {'platform': platform}
                if self.config.exists():
                    self.config.unlink()
                result = self.run_helper()
                self.assertEqual(result.returncode, 0, result.stdout)
                self.assertEqual(self.managed(), PROFILE)
                self.assertFalse((self.paseo / 'paseo.pid').exists())
                self.assertEqual(self.mutations(), [['atomic-merge']])
                self.assertEqual(self.config.stat().st_mode & 0o777, 0o600)

    def test_missing_home_directory_created(self):
        self.paseo.rmdir()
        self.assertEqual(self.run_helper().returncode, 0)
        self.assertEqual(self.managed(), PROFILE)

    def test_optional_fields_and_all_other_data_preserved_core_repaired(self):
        optional = {'name': 'Custom name', 'modeId': 'auto', 'icon': 'custom', 'color': 'violet',
                    'notes': 'review', 'featureValues': {'test': True}, 'future': {'x': 9}}
        other = {'id': 'user-profile', 'name': 'Muse 1.3 Contributor', 'provider': 'codex', 'unknown': True}
        self.save({'unknown': [1, 2], 'daemon': {'listen': 'custom', 'agentProfiles': [other, {'id': ID, 'provider': 'wrong', 'model': 'wrong', 'thinkingOptionId': 'low', **optional}]}})
        result = self.run_helper()
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(self.managed(), {'id': ID, **optional, **CORE})
        self.assertEqual(self.read_config()['daemon']['agentProfiles'][0], other)
        self.assertEqual(self.read_config()['unknown'], [1, 2])
        self.assertEqual(self.read_config()['daemon']['listen'], 'custom')

    def test_idempotence_has_no_inventory_restart_or_file_write_even_live(self):
        self.seed_service()
        self.save({'daemon': {'agentProfiles': [PROFILE]}})
        before = self.config.stat()
        result = self.run_helper()
        self.assertEqual(result.returncode, 0)
        self.assertIn('UNCHANGED', result.stdout)
        self.assertEqual(self.state['calls'], [])
        self.assertEqual(self.config.stat().st_mtime_ns, before.st_mtime_ns)
        self.assertEqual(self.config.stat().st_ino, before.st_ino)

    def test_deleted_profile_recreated_without_duplicate(self):
        self.save({'daemon': {'agentProfiles': []}})
        self.run_helper()
        self.run_helper()
        self.assertEqual(self.read_config()['daemon']['agentProfiles'], [PROFILE])

    def test_invalid_config_profiles_and_duplicate_keys_never_overwritten(self):
        invalid = ['{'+SECRET, '[]', 'null', '{"daemon":null}', '{"daemon":{"agentProfiles":{}}}',
                   '{"daemon":{},"daemon":{}}', '{"daemon":{"agentProfiles":[null]}}',
                   json.dumps({'daemon': {'agentProfiles': [PROFILE, PROFILE]}}),
                   json.dumps({'daemon': {'agentProfiles': [{**PROFILE, 'featureValues': []}]}}),
                   json.dumps({'daemon': {'agentProfiles': [{**PROFILE, 'notes': None}]}})]
        for text in invalid:
            with self.subTest(text=text[:20]):
                self.config.write_text(text)
                self.state = {}
                self.assertNotEqual(self.assert_deferred('Paseo Muse failed:').returncode, 0)

    def test_unsafe_numbers_and_duplicate_keys_never_stop_or_mutate(self):
        self.seed_service()
        cases = [(f'{{"other":{number}}}', 'unsafe-json-number') for number in
                 ('9007199254740993', '-9007199254740993', '9007199254740992.0', '1e309', '-1e309')]
        cases += [(f'{{"other":{number}}}', 'invalid-json') for number in
                  ('NaN', 'Infinity', '-Infinity', '01', '+1', '.5', '1.', '1e+')]
        cases += [(' {"other":{"key":1,"key":2}}', 'duplicate-json-key'),
                  ('{"keep":1,"\\u006beep":2}', 'duplicate-json-key')]
        for text, reason in cases:
            with self.subTest(text=text):
                self.config.write_text(text)
                self.assertNotEqual(self.assert_deferred(reason).returncode, 0)
                self.assertTrue(self.state['running'])
        self.save({'other': [9007199254740991, -9007199254740991, 0.125, 1e5, '9007199254740993']})
        expected = self.read_config()['other']
        self.assertEqual(self.run_helper().returncode, 0)
        self.assertEqual(self.read_config()['other'], expected)

    def test_snapshot_size_bounds_prevent_reading_oversized_config_or_pid(self):
        for file, limit in ((self.config, 4 * 1024 * 1024), (self.paseo / 'paseo.pid', 64 * 1024)):
            with self.subTest(file=file.name):
                with file.open('wb') as stream:
                    stream.truncate(limit + 1)
                self.state['forbiddenReadPaths'] = [str(file)]
                result = self.run_helper()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('metadata-too-large', result.stdout)
                self.assertFalse(self.state['forbiddenRead'])
                self.assertEqual(file.stat().st_size, limit + 1)
                self.assertEqual(self.mutations(), [])
                file.unlink()

    def test_symlink_config_directory_home_and_hardlink_rejected(self):
        outside = self.root / 'outside.json'
        outside.write_text('{}')
        self.config.symlink_to(outside)
        self.assert_deferred('linked-path')
        self.config.unlink()
        os.link(outside, self.config)
        self.assert_deferred('unsafe-file-type')
        self.config.unlink()
        self.paseo.rmdir()
        self.paseo.symlink_to(self.root, target_is_directory=True)
        self.assert_deferred('linked-path')
        self.paseo.unlink()
        self.paseo.mkdir()
        alias = self.root / 'home-link'
        alias.symlink_to(self.home, target_is_directory=True)
        self.state['logicalHome'] = str(alias)
        self.assert_deferred('linked-path')

    def test_home_mismatch_and_unverified_custom_home_defer(self):
        other = self.root / 'other'
        other.mkdir()
        self.state['accountHome'] = str(other)
        self.assert_deferred('account-home-mismatch')
        self.state = {}
        for value in (str(other), str(self.home), str(self.home / 'missing-custom')):
            self.env['PASEO_HOME'] = value
            self.assert_deferred('custom-home-unverified')
        self.env['PASEO_HOME'] = str(self.paseo)
        self.assertEqual(self.run_helper().returncode, 0)
        self.assertEqual(self.managed(), PROFILE)

    def test_empty_relative_tilde_overrides_are_not_unset_even_on_noop(self):
        self.save({'daemon': {'agentProfiles': [PROFILE]}})
        for value in ('', '.paseo', 'profiles/muse', '~/.paseo'):
            with self.subTest(value=value):
                self.env['PASEO_HOME'] = value
                self.assertEqual(self.assert_deferred('invalid-home-override').returncode, 0)

    def test_safe_offline_custom_home_changes_only_selected_profile(self):
        self.save({'defaultUnchanged': True})
        default = self.config
        before = default.read_bytes()
        self.select_home(self.home / 'profiles/muse')
        for platform in ('linux', 'darwin', 'win32'):
            self.state['platform'] = platform
            self.save({'other': 'preserved'})
            result = self.run_helper()
            self.assertEqual(result.returncode, 0, result.stdout)
            self.assertEqual(self.managed(), PROFILE)
            self.assertIn('PASEO_MUSE_DEFER_DAEMON_SETUP=1', result.stdout)
            self.assertEqual(self.read_config()['other'], 'preserved')
            self.assertEqual(default.read_bytes(), before)
            self.assertFalse((default.parent / 'paseo.pid').exists())
            self.assertFalse((self.paseo / 'paseo.pid').exists())
            self.assertEqual(self.mutations(), [['atomic-merge']])

    def test_custom_home_links_nonprivate_and_wrong_owner_rejected(self):
        self.select_home(self.home / 'profiles/muse')
        self.paseo.chmod(0o755)
        self.assert_deferred('custom-home-permissions-unverified')
        self.paseo.chmod(0o700)
        alias = self.home / 'profile-link'
        alias.symlink_to(self.paseo, target_is_directory=True)
        self.env['PASEO_HOME'] = str(alias)
        self.assert_deferred('linked-path')
        self.env['PASEO_HOME'] = str(self.paseo)
        self.state.update(platform='win32', customAclFailure=True)
        self.assert_deferred('custom-home-permissions-unverified')

    def test_active_custom_home_requires_selected_owner_and_manager_home(self):
        self.select_home(self.home / 'profiles/muse')
        self.seed_service()
        correct_manager = f'PASEO_HOME={self.paseo}\n'
        self.state['managerEnv'] = correct_manager
        for value in (None, '', str(self.home / '.paseo'), str(self.home / 'another')):
            with self.subTest(owner=value):
                if value is None:
                    self.state.pop('ownerPaseoHome', None)
                else:
                    self.state['ownerPaseoHome'] = value
                self.assert_deferred('service-home-mismatch')
        self.state['ownerPaseoHome'] = str(self.paseo)
        for value in ('PATH=/fixture/bin\n', 'PASEO_HOME=\n', f'PASEO_HOME={self.home}/.paseo\n'):
            self.state['managerEnv'] = value
            self.assert_deferred('service-home-mismatch')
        self.state['managerEnv'] = correct_manager
        self.assertEqual(self.run_helper().returncode, 0)
        self.assertEqual(self.managed(), PROFILE)
        self.assertFalse((self.home / '.paseo/config.json').exists())
        self.assertEqual(self.mutations(), [['systemctl', '--user', 'stop', 'paseo.service'], ['atomic-merge'], ['systemctl', '--user', 'start', 'paseo.service']])

    def test_custom_home_noop_and_changed_key_use_existing_lifecycle_guards(self):
        self.select_home(self.home / 'profiles/muse')
        self.seed_service()
        self.save({'daemon': {'agentProfiles': [PROFILE]}})
        self.state['ownerPaseoHome'] = str(self.paseo)
        self.state['managerEnv'] = f'PASEO_HOME={self.paseo}\n'
        before = self.config.stat()
        result = self.run_helper()
        self.assertEqual(result.returncode, 0)
        self.assertIn('PASEO_MUSE_DEFER_DAEMON_SETUP=1', result.stdout)
        self.assertEqual(self.state['calls'], [])
        self.env['PASEO_MUSE_GO_CHANGED'] = '1'
        self.assertEqual(self.run_helper().returncode, 0)
        self.assertEqual(self.config.stat().st_ino, before.st_ino)
        self.assertEqual(self.config.stat().st_mtime_ns, before.st_mtime_ns)
        self.assertEqual(self.mutations(), [['systemctl', '--user', 'stop', 'paseo.service'], ['systemctl', '--user', 'start', 'paseo.service']])

    def test_custom_home_manager_change_prevents_wrong_home_restore(self):
        self.select_home(self.home / 'profiles/muse')
        self.seed_service()
        self.state['ownerPaseoHome'] = str(self.paseo)
        self.state['managerEnv'] = f'PASEO_HOME={self.paseo}\n'
        self.state['managerEnvAfterStop'] = f'PASEO_HOME={self.home}/.paseo\n'
        result = self.run_helper()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('service-restore-failed', result.stdout)
        self.assertFalse(self.state['running'])
        self.assertNotIn(['systemctl', '--user', 'start', 'paseo.service'], self.mutations())
        self.assertFalse((self.home / '.paseo/config.json').exists())

    def test_explicit_empty_owner_and_manager_home_rejected_for_default_too(self):
        self.seed_service()
        self.state['ownerPaseoHome'] = ''
        self.assert_deferred('service-home-mismatch')
        self.state.pop('ownerPaseoHome')
        self.state['managerEnv'] = 'PASEO_HOME=\n'
        self.assert_deferred('service-home-mismatch')

    def test_mac_custom_home_requires_actual_owner_and_launchd_environment(self):
        self.select_home(self.home / 'profiles/muse')
        self.seed_service('darwin')
        self.state['macManagerEnv'] = f'PASEO_HOME => {self.paseo}'
        for value in (None, '', str(self.home / '.paseo')):
            if value is None:
                self.state.pop('ownerPaseoHome', None)
            else:
                self.state['ownerPaseoHome'] = value
            self.assert_deferred('service-home-mismatch')
        self.state['ownerPaseoHome'] = str(self.paseo)
        for value in ('', 'PASEO_HOME =>', f'PASEO_HOME => {self.home}/.paseo'):
            self.state['macManagerEnv'] = value
            self.assert_deferred('service-home-mismatch')
        self.state['macManagerEnv'] = f'PASEO_HOME => {self.paseo}'
        self.assertEqual(self.run_helper().returncode, 0)
        self.assertEqual(self.managed(), PROFILE)

    def test_existing_file_mode_is_preserved(self):
        self.save({})
        self.config.chmod(0o640)
        self.assertEqual(self.run_helper().returncode, 0)
        self.assertEqual(self.config.stat().st_mode & 0o777, 0o640)

    def test_native_startup_contender_wins_without_config_clobber(self):
        self.state['nativeContender'] = True
        result = self.run_helper()
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.config.exists())
        self.assertEqual(json.loads((self.paseo / 'paseo.pid').read_text())['pid'], 4300)
        self.assertEqual(self.mutations(), [])

    def test_partial_native_lock_write_failure_releases_only_own_lock(self):
        self.state['pidWriteFailure'] = True
        result = self.run_helper()
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.config.exists())
        self.assertFalse((self.paseo / 'paseo.pid').exists())

    def test_writable_profile_paths_rejected(self):
        self.save({})
        self.config.chmod(0o666)
        self.assert_deferred('unsafe-owner-or-mode')

    def test_native_pid_link_malformed_remote_stale_desktop_and_unknown_owner(self):
        file = self.paseo / 'paseo.pid'
        file.write_text(SECRET)
        self.assert_deferred('invalid-json')
        self.seed_service()
        original = json.loads(file.read_text())
        for change, reason in [({'hostname': 'remote'}, 'pid-metadata-unverified'),
                               ({'uid': 99999}, 'pid-metadata-unverified'),
                               ({'pid': 99999}, 'stale-pid-lock'),
                               ({'desktopManaged': True}, 'desktop-owned')]:
            file.write_text(json.dumps({**original, **change}))
            self.assert_deferred(reason)
        file.unlink()
        file.symlink_to(self.root / 'missing')
        self.assert_deferred('linked-path')

    def test_inventory_catches_desktop_and_renamed_writer_without_pid(self):
        for command in ('/Applications/Paseo.app/Contents/MacOS/Paseo', 'nonstandard-binary'):
            self.state = {'otherWriter': command}
            self.assert_deferred('unknown-writer')

    def test_inventory_or_command_failure_not_proof_of_stopped(self):
        self.state['inventoryDenied'] = True
        self.assert_deferred('process-inventory-unverified')
        self.state = {}
        self.seed_service()
        self.state['commandDenied'] = True
        self.assert_deferred('command-unverified')

    def test_service_stop_merge_start_order_and_latest_shutdown_data(self):
        self.seed_service()
        self.state['renamed'] = True
        self.state['shutdownConfig'] = {'fromShutdown': 123, 'daemon': {'agentProfiles': [{'id': 'custom', 'name': 'custom', 'provider': 'pi'}]}}
        result = self.run_helper()
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(self.mutations(), [['systemctl', '--user', 'stop', 'paseo.service'], ['atomic-merge'], ['systemctl', '--user', 'start', 'paseo.service']])
        self.assertTrue(self.state['running'])
        self.assertEqual(self.read_config()['fromShutdown'], 123)
        self.assertEqual(len(self.read_config()['daemon']['agentProfiles']), 2)
        self.assertEqual(json.loads((self.paseo / 'paseo.pid').read_text())['pid'], 4202)

    def test_service_control_bus_fallback_preserves_local_user(self):
        self.seed_service()
        self.state['directBusFailure'] = True
        self.assertEqual(self.run_helper().returncode, 0)
        self.assertIn(['systemctl', '--machine=fixture@', '--user', 'stop', 'paseo.service'], self.state['calls'])

    def test_core_noop_key_rotation_refreshes_service_without_config_write(self):
        self.seed_service()
        self.save({'daemon': {'agentProfiles': [PROFILE]}})
        before = self.config.read_bytes()
        self.env['PASEO_MUSE_GO_CHANGED'] = '1'
        self.assertEqual(self.run_helper().returncode, 0)
        self.assertEqual(self.config.read_bytes(), before)
        self.assertEqual(self.mutations(), [['systemctl', '--user', 'stop', 'paseo.service'], ['systemctl', '--user', 'start', 'paseo.service']])

    def test_unset_zero_true_headless_wsl_windows_and_mac_gate_defer(self):
        self.seed_service()
        for headless in ('', '0', 'true'):
            self.env['HEADLESS'] = headless
            self.assert_deferred('headless-control-not-authorized')
        self.env['HEADLESS'] = '1'
        self.state['wsl'] = True
        self.assert_deferred('headless-control-not-authorized')
        self.state['wsl'] = False
        self.state['platform'] = 'win32'
        self.assert_deferred('unknown-owner')
        self.state['platform'] = 'darwin'
        self.env['PASEO_MACOS_HEADLESS_CANARY'] = '0'
        self.assert_deferred('headless-control-not-authorized')

    def test_self_hosted_by_ancestry_cgroup_or_environment_defer(self):
        self.seed_service()
        self.state['selfHosted'] = True
        self.assert_deferred('self-hosted-setup')
        self.state['selfHosted'] = False
        self.state['selfGroup'] = True
        self.assert_deferred('self-hosted-setup')
        self.state['selfGroup'] = False
        self.state['foreignAncestor'] = True
        self.assert_deferred('self-hosted-setup')
        self.state['foreignAncestor'] = False
        self.state['unknownAncestor'] = True
        self.assert_deferred('ancestry-unverified')
        self.state['unknownAncestor'] = False
        self.env['PASEO_AGENT_ID'] = 'fixture-agent'
        self.assert_deferred('self-hosted-setup')

    def test_home_service_pid_dropin_and_wrapper_mismatch_defer(self):
        self.seed_service()
        for changes, reason in [({'ownerHome': '/other'}, 'service-home-mismatch'),
                                ({'ownerPaseoHome': '/other'}, 'service-home-mismatch'),
                                ({'managerEnv': 'PASEO_HOME=/other\n'}, 'service-home-mismatch'),
                                ({'serviceOverrides': {'MainPID': '4300'}}, 'service-pid-mismatch'),
                                ({'serviceOverrides': {'DropInPaths': '/custom'}}, 'service-state-unverified'),
                                ({'serviceOverrides': {'NeedDaemonReload': 'yes'}}, 'service-state-unverified')]:
            self.state = {'running': True, **changes}
            self.assert_deferred(reason)
        self.state = {'running': True}
        wrapper = self.home / '.local/bin/paseo-daemon-start'
        wrapper.write_text(wrapper.read_text().replace("export PATH='/fixture/bin'", "export PATH='/fixture'$(untrusted)'/bin'"))
        self.assert_deferred('unmanaged-wrapper')
        (self.home / '.local/bin/paseo-daemon-start').write_text('# user-owned wrapper\n')
        self.assert_deferred('unmanaged-wrapper')

    def test_github_token_dropin_defers_without_reading_token_then_offline_seed_works(self):
        self.seed_service()
        dropin = self.home / '.config/systemd/user/paseo.service.d/github-token.conf'
        token_file = self.home / '.config/paseo/github-token.env'
        token_file.parent.mkdir(parents=True)
        token_file.write_text(SECRET)
        self.state['forbiddenReadPaths'] = [str(token_file), str(dropin)]
        self.state['serviceOverrides'] = {'DropInPaths': str(dropin), 'EnvironmentFiles': f'{token_file} (ignore_errors=no)'}
        self.assert_deferred('service-state-unverified')
        self.assertFalse(self.state['forbiddenRead'])
        self.assertEqual(token_file.read_text(), SECRET)
        self.state['running'] = False
        (self.paseo / 'paseo.pid').unlink()
        self.assertEqual(self.run_helper().returncode, 0)
        self.assertEqual(self.managed(), PROFILE)
        self.assertFalse(self.state['forbiddenRead'])
        self.assertEqual(self.mutations(), [['atomic-merge']])

    def test_restore_after_merge_failure_and_concurrent_changes(self):
        for failure in ('writeFailure', 'renameFailure', 'concurrentEdit'):
            with self.subTest(failure=failure):
                self.seed_service()
                self.save({'existing': True})
                self.state[failure] = SECRET if failure == 'concurrentEdit' else True
                result = self.run_helper()
                self.assertNotEqual(result.returncode, 0)
                self.assertTrue(self.state['running'])
                self.assertIn(['systemctl', '--user', 'start', 'paseo.service'], self.mutations())
                self.assertNotIn('agentProfiles', self.read_config().get('daemon', {}))
                if failure == 'concurrentEdit':
                    self.assertEqual(self.read_config(), {'concurrent': SECRET})
                del self.state[failure]

    def test_failed_stop_and_remaining_writer_restore_without_merge(self):
        for flag in ('stopFailure', 'stopLeavesRunning', 'leftover'):
            self.seed_service()
            self.save({'existing': True})
            self.state[flag] = True
            result = self.run_helper()
            self.assertIn('PASEO_MUSE_DEFER_DAEMON_SETUP=1', result.stdout)
            self.assertTrue(self.state['running'])
            self.assertNotIn(['atomic-merge'], self.mutations())
            # A pre-existing extra writer defers before stopping at all.
            if flag == 'stopFailure':
                self.assertIn(['systemctl', '--user', 'start', 'paseo.service'], self.mutations())
            if flag == 'stopLeavesRunning':
                self.assertNotIn(['systemctl', '--user', 'start', 'paseo.service'], self.mutations())
            del self.state[flag]

    def test_interrupt_after_stop_restores_before_return(self):
        self.seed_service()
        self.state['interruptAfterStop'] = True
        result = self.run_helper()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('interrupted', result.stdout)
        self.assertTrue(self.state['running'])
        self.assertNotIn(['atomic-merge'], self.mutations())
        self.assertIn(['systemctl', '--user', 'start', 'paseo.service'], self.mutations())

    def test_new_writer_after_stop_blocks_second_daemon_and_reports_restore_failure(self):
        self.seed_service()
        self.state['newWriterAfterStop'] = True
        result = self.run_helper()
        self.assertIn('service-restore-failed', result.stdout)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.state['running'])
        self.assertNotIn(['atomic-merge'], self.mutations())
        self.assertNotIn(['systemctl', '--user', 'start', 'paseo.service'], self.mutations())

    def test_windows_default_config_and_ancestor_unsafe_acls_fail_before_read_or_mutation(self):
        self.save({'preserve': SECRET})
        for target in (self.config, self.paseo, self.home):
            cases = [{'owner': 'S-1-1-0', 'rules': []}, {'owner': 'S-1-5-21-fixture', 'rules': [], 'nullDacl': True}]
            cases += [{'owner': 'S-1-5-21-fixture', 'rules': [{'sid': 'S-1-1-0', 'rights': rights, 'inherited': True}]} for rights in
                      (278, 64, 65536, 262144, 524288)]
            for acl in cases:
                with self.subTest(target=target.name, acl=acl):
                    self.state = {'platform': 'win32', 'windowsAcls': {str(target): acl}, 'forbiddenReadPaths': [str(self.config)]}
                    self.assertNotEqual(self.assert_deferred('windows-acl-unverified').returncode, 0)
                    self.assertFalse(self.state['forbiddenRead'])
                    self.assertEqual(self.state['aclChecks'][-1], [str(self.config), str(self.paseo), str(self.home)])
                    self.assertFalse((self.paseo / 'paseo.pid').exists())

    def test_windows_missing_default_directory_checks_home_acl_before_creation(self):
        self.paseo.rmdir()
        for acl in ({'owner': 'S-1-1-0', 'rules': []},
                    {'owner': 'S-1-5-21-fixture', 'rules': [{'sid': 'S-1-1-0', 'rights': 278}]}):
            self.state = {'platform': 'win32', 'windowsAcls': {str(self.home): acl}}
            self.assertNotEqual(self.assert_deferred('windows-acl-unverified').returncode, 0)
            self.assertEqual(self.state['aclChecks'][-1], [str(self.home)])
            self.assertFalse(self.paseo.exists())

    def test_windows_existing_pid_metadata_acl_is_checked_without_replacement(self):
        self.save({})
        pid = self.paseo / 'paseo.pid'
        pid.write_text(json.dumps({'pid': 4999, 'uid': os.getuid(), 'hostname': 'fixture-machine',
                                   'startedAt': '2026-01-01T00:00:00Z', 'listen': None}))
        before = pid.read_bytes()
        self.state = {'platform': 'win32', 'windowsAcls': {str(pid): {'owner': 'S-1-1-0', 'rules': []}},
                      'forbiddenReadPaths': [str(pid)]}
        self.assertNotEqual(self.assert_deferred('windows-acl-unverified').returncode, 0)
        self.assertFalse(self.state['forbiddenRead'])
        self.assertEqual(pid.read_bytes(), before)

    def test_windows_trusted_acls_are_preserved_and_inherit_only_is_not_applied(self):
        unrelated = self.home / 'unrelated.json'
        unrelated.write_text(SECRET)
        for owner in ('S-1-5-21-fixture', 'S-1-5-18', 'S-1-5-32-544'):
            self.save({})
            original_acls = {
                str(self.home): {'owner': 'S-1-5-32-544', 'rules': [{'sid': 'S-1-1-0', 'rights': 278, 'inheritOnly': True}]},
                str(self.paseo): {'owner': 'S-1-5-18', 'rules': [{'sid': 'S-1-1-0', 'rights': 1}]},
                str(self.config): {'owner': owner, 'rules': [{'sid': 'S-1-1-0', 'rights': 1},
                    {'sid': 'S-1-1-0', 'rights': 278, 'inheritOnly': True}, {'sid': 'S-1-5-18', 'rights': 2032127}]},
                str(unrelated): {'owner': 'S-1-1-0', 'rules': [{'sid': 'S-1-1-0', 'rights': 2032127}]},
            }
            self.state = {'platform': 'win32', 'windowsAcls': original_acls}
            result = self.run_helper()
            self.assertEqual(result.returncode, 0, result.stdout)
            self.assertEqual(self.managed(), PROFILE)
            self.assertEqual(self.state['windowsAcls'], original_acls)
            self.assertEqual(unrelated.read_text(), SECRET)
            self.assertTrue(all(str(unrelated) not in paths for paths in self.state['aclChecks']))
            before = self.config.stat().st_mtime_ns
            self.assertEqual(self.run_helper().returncode, 0)
            self.assertEqual(self.mutations(), [])
            self.assertEqual(self.config.stat().st_mtime_ns, before)

    def test_windows_acl_failure_or_missing_positive_receipt_blocks_mutation(self):
        self.save({})
        for flag in ('windowsAclCommandFailure', 'windowsAclMissingReceipt'):
            self.state = {'platform': 'win32', flag: True}
            self.assertNotEqual(self.assert_deferred('windows-acl-unverified').returncode, 0)
            self.assertFalse((self.paseo / 'paseo.pid').exists())

    def test_windows_custom_home_private_boundary_is_not_relaxed(self):
        self.select_home(self.home / 'profiles/muse')
        cases = [{'owner': 'S-1-5-18', 'rules': []},
                 {'owner': 'S-1-5-21-fixture', 'rules': [{'sid': 'S-1-1-0', 'rights': 1}]},
                 {'owner': 'S-1-5-21-fixture', 'rules': [{'sid': 'S-1-1-0', 'rights': 1, 'inheritOnly': True}]}]
        for acl in cases:
            self.state = {'platform': 'win32', 'selectedHome': str(self.paseo), 'windowsAcls': {str(self.paseo): acl}}
            self.assert_deferred('custom-home-permissions-unverified')
            self.assertFalse(self.config.exists())
        self.state = {'platform': 'win32', 'selectedHome': str(self.paseo)}
        self.assertEqual(self.run_helper().returncode, 0)
        self.assertEqual(self.managed(), PROFILE)

    def test_windows_acl_failure_does_not_write_config(self):
        self.state.update(platform='win32', aclFailure=True)
        result = self.run_helper()
        self.assertIn('command-unverified', result.stdout)
        self.assertFalse(self.config.exists())
        self.assertFalse((self.paseo / 'paseo.pid').exists())

    def test_restore_failure_is_hard_failure(self):
        self.seed_service()
        self.state['startFailure'] = True
        result = self.run_helper()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('service-restore-failed', result.stdout)

    def test_mac_verified_canary_bootout_merge_bootstrap(self):
        self.seed_service('darwin')
        result = self.run_helper('mac.sh')
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(self.mutations(), [['sudo', '-n', 'launchctl', 'bootout', 'system/com.scowalt.paseo-daemon'], ['atomic-merge'], ['sudo', '-n', 'launchctl', 'bootstrap', 'system', '/Library/LaunchDaemons/com.scowalt.paseo-daemon.plist']])

    def test_mac_merge_failure_restores_and_wrong_user_does_not_stop(self):
        self.seed_service('darwin')
        self.state['plistOverrides'] = {'UserName': 'other'}
        self.assert_deferred('service-state-unverified')
        self.state['plistOverrides'] = {}
        self.state['macManagerEnv'] = 'PASEO_HOME => /unknown'
        self.assert_deferred('service-home-mismatch')
        self.state['macManagerEnv'] = ''
        self.state['writeFailure'] = True
        self.assertNotEqual(self.run_helper('mac.sh').returncode, 0)
        self.assertTrue(self.state['running'])
        self.assertTrue(any('bootstrap' in c for c in self.mutations()))

    def test_stopped_desktop_and_key_refresh_seed_offline_no_service_creation(self):
        for platform in ('darwin', 'win32'):
            self.state = {'platform': platform}
            self.env['PASEO_MUSE_GO_CHANGED'] = '1'
            self.save({})
            self.assertEqual(self.run_helper().returncode, 0)
            self.assertEqual(self.mutations(), [['atomic-merge']])

    def test_trusted_linux_root_home_alias_validation_without_real_home(self):
        # Call only the path validator against synthetic root-owned stats. The
        # asynchronous helper runs independently against this fixture HOME.
        self.state['alias'] = True
        suffix = "\ntry { checkedPath('/home', true); console.log('ALIAS_ACCEPTED'); } catch { console.log('ALIAS_REJECTED'); }\n"
        self.assertIn('ALIAS_ACCEPTED', self.run_helper(suffix=suffix).stdout)
        for change in ({'aliasBadOwner': True}, {'aliasWritable': True}, {'aliasTarget': '/untrusted'}):
            self.state = {'alias': True, **change}
            self.assertIn('ALIAS_REJECTED', self.run_helper(suffix=suffix).stdout)

    def test_bazzite_aliases_map_only_selected_custom_home(self):
        default = self.config
        default.write_text(SECRET)
        self.select_home(self.home / 'profiles/muse')
        for physical in (False, True):
            for requested in ('/home/fixture/profiles/muse', '/var/home/fixture/profiles/muse'):
                with self.subTest(physical_home=physical, requested=requested):
                    self.state.update(aliasHome=True, physicalHome=physical, selectedHome='/var/home/fixture/profiles/muse')
                    self.env['PASEO_HOME'] = requested
                    self.save({'custom': 'preserved'})
                    suffix = "\nif (samePaseoHome('/home/fixture/.paseo')) throw new Error('default alias accepted for custom home');\n"
                    suffix += "if (!sameHome('/home/fixture') || !sameHome('/var/home/fixture')) throw new Error('trusted account alias rejected');\n"
                    result = self.run_helper('bazzite.sh', suffix=suffix)
                    self.assertEqual(result.returncode, 0, result.stdout)
                    self.assertEqual(self.managed(), PROFILE)
                    self.assertEqual(default.read_text(), SECRET)
                    self.assertFalse((default.parent / 'paseo.pid').exists())
                    self.assertFalse((self.paseo / 'paseo.pid').exists())
        self.state['aliasBadOwner'] = True
        self.state['physicalHome'] = False
        self.assert_deferred('linked-path')

    def prepare_poisoned_wrapper(self):
        # The test-owned --require is explicit argv, never NODE_OPTIONS. Every
        # process/OS call from the embedded helper remains mocked by PRELOAD.
        bin_dir = self.root / 'bin'
        bin_dir.mkdir()
        launcher = bin_dir / 'node'
        launcher.write_text(f'#!/bin/bash\nexec {shlex.quote(NODE)} --require {shlex.quote(str(self.preload))} "$@"\n')
        launcher.chmod(0o700)
        modules = self.root / 'poison-modules'
        hook = modules / 'poison-fixture/index.js'
        hook.parent.mkdir(parents=True)
        hook.write_text("require('node:fs').writeFileSync(process.env.MUSE_POISON_MARKER, 'hook executed'); throw new Error('poison-hook-executed');\n")
        marker = self.root / 'poison-executed'
        env = {**self.env, 'PATH': f'{bin_dir}:{os.environ["PATH"]}', 'NODE_OPTIONS': '--require=poison-fixture',
               'NODE_PATH': str(modules), 'MUSE_POISON_MARKER': str(marker)}
        # Positive control is only this benign fixture hook, not installed code.
        control = subprocess.run([NODE, '-e', ''], env=env, capture_output=True, text=True, timeout=10)
        self.assertNotEqual(control.returncode, 0)
        self.assertTrue(marker.exists())
        marker.unlink()
        return env, marker

    def test_bash_wrappers_clear_poisoned_node_hook_and_preserve_caller_values(self):
        env, marker = self.prepare_poisoned_wrapper()
        for name in SCRIPTS[:-1]:
            with self.subTest(script=name):
                text = (ROOT / name).read_text()
                function = 'configure_paseo_muse_profile() {' + text.split('configure_paseo_muse_profile() {', 1)[1].split('\ninstall_paseo_plain() {', 1)[0]
                script = self.root / 'wrapper.sh'
                script.write_text('set -eu\nprint_warning() { :; }; print_success() { :; }; print_debug() { :; }\n' + function +
                    '\nexpected_options=${NODE_OPTIONS}\nexpected_path=${NODE_PATH}\nconfigure_paseo_muse_profile\n' +
                    '[[ "${PASEO_MUSE_DEFER_DAEMON_SETUP}" == 0 && "${NODE_OPTIONS}" == "${expected_options}" && "${NODE_PATH}" == "${expected_path}" ]]\n')
                self.save({})
                (self.root / 'state.json').write_text(json.dumps(self.state))
                result = subprocess.run(['bash', str(script)], env=env, capture_output=True, text=True, timeout=15)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertFalse(marker.exists())
                state = json.loads((self.root / 'state.json').read_text())
                self.assertIsNone(state['nodeOptions'])
                self.assertIsNone(state['nodePath'])
                self.assertEqual(self.managed(), PROFILE)

    def test_empty_override_guidance_and_skip_flag_reach_bash_caller(self):
        env, marker = self.prepare_poisoned_wrapper()
        env['PASEO_HOME'] = ''
        text = (ROOT / 'ubuntu.sh').read_text()
        function = 'configure_paseo_muse_profile() {' + text.split('configure_paseo_muse_profile() {', 1)[1].split('\ninstall_paseo_plain() {', 1)[0]
        script = self.root / 'wrapper.sh'
        script.write_text('set -eu\nprint_warning() { printf "%s\\n" "$1"; }; print_success() { :; }; print_debug() { :; }\n' + function +
            '\nconfigure_paseo_muse_profile\n[[ "${PASEO_MUSE_DEFER_DAEMON_SETUP}" == 1 ]]\n')
        (self.root / 'state.json').write_text(json.dumps(self.state))
        result = subprocess.run(['bash', str(script)], env=env, capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('PASEO_HOME must be unset or an absolute directory below the account HOME', result.stdout)
        self.assertIn('outside Paseo', result.stdout)
        self.assertFalse(marker.exists())
        self.assertFalse(self.config.exists())

    @unittest.skipUnless(PWSH, 'Set PWSH_BIN for the real Node/PowerShell poison-hook fixture')
    def test_powershell_wrapper_clears_poisoned_node_hook_and_restores_values(self):
        env, marker = self.prepare_poisoned_wrapper()
        text = (ROOT / 'win.ps1').read_text()
        function = 'function Set-PaseoMuseProfile {' + text.split('function Set-PaseoMuseProfile {', 1)[1].split('\nfunction Install-PaseoPlain {', 1)[0]
        script = self.root / 'wrapper.ps1'
        script.write_text("$ErrorActionPreference='Stop'\nfunction Write-Success { param($Message) }\nfunction Write-Debug { param($Message) }\n" + function + "\n" +
            "$script:PiOpenCodeGoChanged=$false\n$expectedOptions=$env:NODE_OPTIONS\n$expectedPath=$env:NODE_PATH\n" +
            "if (-not (Set-PaseoMuseProfile)) { throw 'profile failed' }\n" +
            "if ($env:NODE_OPTIONS -cne $expectedOptions -or $env:NODE_PATH -cne $expectedPath) { throw 'Node environment not restored' }\n")
        self.state['platform'] = 'win32'
        (self.root / 'state.json').write_text(json.dumps(self.state))
        result = subprocess.run([PWSH, '-NoLogo', '-NoProfile', '-NonInteractive', '-File', str(script)],
                                env=env, capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(marker.exists())
        state = json.loads((self.root / 'state.json').read_text())
        self.assertIsNone(state['nodeOptions'])
        self.assertIsNone(state['nodePath'])
        self.assertEqual(self.managed(), PROFILE)

    @unittest.skipUnless(NATIVE_PID_LOCK, 'Set PASEO_MUSE_PID_LOCK_MODULE for the isolated upstream 0.8.0 lock proof')
    def test_native_080_pid_lock_rejects_the_actual_setup_reservation(self):
        module = Path(NATIVE_PID_LOCK).resolve()
        package = module.parents[3]
        metadata = json.loads((package / 'package.json').read_text())
        self.assertEqual((metadata['name'], metadata['version']), ('@getpaseo/server', '0.8.0'))
        self.assertEqual(module.relative_to(package).as_posix(), 'dist/src/server/pid-lock.js')
        source = (package / 'dist/scripts/supervisor-entrypoint.js').read_text()
        self.assertLess(source.index('await acquirePidLock('), source.index('const supervisor = runSupervisor('))
        self.assertIn('if (error instanceof PidLockError)', source)
        self.assertIn('process.exit(1);\n            return;', source)
        # Only pid-lock.js (node built-ins + zod) is imported. No supervisor,
        # worker, provider SDK, installed CLI, or model process is executed.
        imports = [line for line in module.read_text().splitlines() if line.startswith('import ')]
        self.assertEqual(len(imports), 5)
        for line, dependency in zip(imports, ('node:fs/promises', 'node:fs', 'node:path', 'node:os', 'zod')):
            self.assertIn(f'from "{dependency}";', line)
        common = f'''import * as native from {json.dumps(module.as_uri())};
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
const home=process.argv[1], file=path.join(home,'paseo.pid');
'''
        blocked = common + '''const before=fs.readFileSync(file,'utf8');
assert.equal(JSON.parse(before).pid,process.ppid);
for (const options of [{}, {reclaimStaleDesktopLock:true}]) {
  await assert.rejects(native.acquirePidLock(home,null,options), error=>error instanceof native.PidLockError);
  assert.equal(fs.readFileSync(file,'utf8'),before);
}
console.log('NATIVE_REJECTED');
'''
        released = common + '''await native.acquirePidLock(home,null);
assert.equal(JSON.parse(fs.readFileSync(file,'utf8')).pid,process.pid);
await native.releasePidLock(home);
assert.equal(fs.existsSync(file),false);
console.log('NATIVE_ACQUIRED_AFTER_RELEASE');
'''
        # Extract definitions only, initialize temporary fixture paths, then call
        # the real setup reserve/release functions. The Node children above are
        # short-lived lock contenders, never daemons or service managers.
        definitions = embedded('ubuntu.sh').rsplit('(async () => {', 1)[0]
        program = definitions + f'''
const assert = require('node:assert/strict');
home=logicalHome=process.env.HOME;
paseoHome=path.join(home,'.paseo'); pidPath=path.join(paseoHome,'paseo.pid');
reservePid();
try {{
  const child=spawnSync(process.execPath,['--input-type=module','-e',{json.dumps(blocked)},paseoHome],{{encoding:'utf8',env:process.env,timeout:10000}});
  assert.equal(child.status,0); assert.equal(child.stdout.trim(),'NATIVE_REJECTED');
  lockUnchanged();
}} finally {{ releasePid(); }}
const child=spawnSync(process.execPath,['--input-type=module','-e',{json.dumps(released)},paseoHome],{{encoding:'utf8',env:process.env,timeout:10000}});
assert.equal(child.status,0); assert.equal(child.stdout.trim(),'NATIVE_ACQUIRED_AFTER_RELEASE');
console.log('Native 0.8.0 PID-lock exclusion verified.');
'''
        file = self.root / 'native-lock-proof.cjs'
        file.write_text(program)
        result = subprocess.run([NODE, str(file)], env=self.env, capture_output=True, text=True, timeout=25)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('PID-lock exclusion verified', result.stdout)
        self.assertFalse((self.paseo / 'paseo.pid').exists())
        self.assertFalse(self.config.exists())

    def test_extracted_bash_wrapper_flags_and_changed_input(self):
        text = (ROOT / 'ubuntu.sh').read_text()
        function = 'configure_paseo_muse_profile() {' + text.split('configure_paseo_muse_profile() {', 1)[1].split('\ninstall_paseo_plain() {', 1)[0]
        bin_dir = self.root / 'bin'
        bin_dir.mkdir()
        node = bin_dir / 'node'
        node.write_text('#!/bin/bash\n[[ "${PASEO_MUSE_GO_CHANGED}" == 1 ]] || exit 99\nprintf "%s\\n" PASEO_MUSE_DEFER_DAEMON_SETUP=1 "Paseo Muse deferred: fixture."\n')
        node.chmod(0o700)
        script = self.root / 'wrapper.sh'
        script.write_text('set -eu\nprint_warning() { :; }; print_success() { :; }; print_debug() { :; }\n' + function + '\nPI_OPENCODE_GO_CHANGED=1\nconfigure_paseo_muse_profile\n[[ "${PASEO_MUSE_DEFER_DAEMON_SETUP}" == 1 ]]\n')
        result = subprocess.run(['bash', str(script)], env={**self.env, 'PATH': f'{bin_dir}:{os.environ["PATH"]}'}, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == '__main__':
    unittest.main()
