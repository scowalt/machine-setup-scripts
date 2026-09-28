#!/usr/bin/env python3
"""Extracted preparation helpers only; no installed BB code or lifecycle is executed."""
import hashlib
import io
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]
SCRIPTS = ["ubuntu", "mac", "pi", "bazzite", "wsl"]
NODE = subprocess.check_output(["node", "-p", "process.execPath"], text=True).strip()
# mise's npm executable is a shell wrapper; use its native JS entry in offline fixtures.
NPM = str(Path(NODE).parent.parent / 'lib/node_modules/npm/bin/npm-cli.js')
if not Path(NPM).is_file():
    NPM = str(Path(shutil.which("npm")).resolve())
START = "# Installation only: keep this block identical in the five Bash scripts."
END = "# End shared BB machine preparation."
SOURCES = {n: (REPO / (n + ".sh")).read_text() for n in SCRIPTS}
BLOCK = SOURCES["ubuntu"].split(START, 1)[1].split(END, 1)[0]
BINS = {n: f"dist/{n}.js" for n in ("bb", "bb-app", "bb-server", "bb-host-daemon")}
FILES = list(BINS.values()) + ["server/dist/index.js", "app/dist/index.html", "host-daemon/dist/bb", "host-daemon/dist/daemon-bundle.mjs", "host-daemon/dist/bb-provider-bridge-worker.mjs", "host-daemon/dist/bb-parcel-watcher-child.mjs", "host-daemon/dist/bb-plugin-host-worker.mjs", "host-daemon/dist/bb-chunks/chunk.js"]
ADDONS = ["better-sqlite3", "node-pty", "@parcel/watcher", "fs-native-extensions"]


def fixture_package(version="0.44.0", native=False):
    files = {f: b"throw new Error('BB startup must never execute in this fixture');\n" for f in FILES}
    manifest = {"name": "bb-app", "version": version, "os": ["linux", "darwin"], "bin": BINS, "engines": {"node": "^22.19.0 || ^24.0.0 || ^26.0.0"}, "type": "module"}
    if native:
        manifest.update(dependencies={n: "1.0.0" for n in ADDONS}, bundledDependencies=ADDONS)
    files["package.json"] = json.dumps(manifest).encode()
    exports = ["module.exports=class { constructor(name) { if(name!==':memory:') throw Error('disk database'); } close(){} };", "module.exports={spawn(){throw Error('must not spawn')}};", "module.exports={subscribe(){throw Error('must not watch')}};", "module.exports={tryLock(){},unlock(){}};"]
    for name, code in zip(ADDONS, exports):
        base = f"node_modules/{name}/"
        meta = {"name": name, "version": "1.0.0", "main": "index.js"}
        if native and name != "fs-native-extensions":
            meta["scripts"] = {"install": "node build.cjs"}
            files[base + "build.cjs"] = b"require('fs').writeFileSync('built', process.env.FIXTURE_ABI || process.versions.modules);\n"
            code = "if(require('fs').readFileSync(__dirname+'/built','utf8') !== (process.env.FIXTURE_ABI || process.versions.modules)) throw Error('stale addon ABI');\n" + code
        code = f"if(process.env.FAIL_ADDON==={json.dumps(name)}) throw Error('fixture native load failure');\n" + code
        files[base + "package.json"] = json.dumps(meta).encode()
        files[base + "index.js"] = code.encode()
    return files


def snapshot(directory):
    records = []
    for p in sorted(directory.rglob("*")):
        s = p.lstat()
        records.append((str(p.relative_to(directory)), s.st_mode, os.readlink(p) if p.is_symlink() else hashlib.sha256(p.read_bytes()).hexdigest() if p.is_file() else None))
    return records


class Preparation(unittest.TestCase):
    def setUp(self):
        previous_umask = os.umask(0o077)
        self.addCleanup(os.umask, previous_umask)
        self.temp = tempfile.TemporaryDirectory(prefix="bb-prep-contract-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.home = self.root / "home"
        self.home.mkdir(mode=0o700)
        self.tools = self.root / "tools"
        self.tools.mkdir()
        (self.tools / "node").symlink_to(NODE)
        (self.root / "helpers.sh").write_text(BLOCK)
        self.prefix = self.home / ".local/share/setup-bb-machine/npm"
        self.pkg = self.prefix / "lib/node_modules/bb-app"
        self.events = self.root / "events"
        self.original_prefix = self.root / 'original-prefix'
        self.globalconfig = self.original_prefix / 'etc/npmrc'
        self.globalconfig.parent.mkdir(parents=True)
        self.globalconfig.write_text('')
        self.userconfig = self.home / '.npmrc'
        self.userconfig.write_text('')
        self.env = {"HOME": str(self.home), "PATH": f"{self.tools}:/usr/bin:/bin", "EVENTS": str(self.events), "FIXTURE_ROOT": str(self.root), "FIXTURE_NODE": NODE, "FIXTURE_NPM": NPM, "LANG": "C.UTF-8", "npm_config_prefix": str(self.original_prefix), "npm_config_cache": str(self.root / 'cache'), "npm_config_offline": "true"}
        (self.root / 'native-config.cjs').write_text(r'''
const path = require('node:path');
const npmPath = path.dirname(path.dirname(process.env.FIXTURE_NPM));
const Config = require(path.join(npmPath, 'node_modules/@npmcli/config'));
const definitions = require(path.join(npmPath, 'node_modules/@npmcli/config/lib/definitions'));
(async () => {
  const config = new Config({...definitions, npmPath, argv: [process.execPath, process.env.FIXTURE_NPM, ...JSON.parse(process.argv[2])]});
  await config.load();
  const result = Object.fromEntries(['registry', 'allow-git', 'allow-remote', 'ignore-scripts', 'globalconfig', 'userconfig'].map(k => [k, config.get(k)]));
  if (process.env.ASSERT_FIXTURE_AUTH === '1') {
    if (config.get('//fixture.invalid/:_authToken') !== 'inert-fixture-token') throw Error('fixture auth source not preserved');
    result.authPreserved = true; // Never emit credential values, even inert ones.
  }
  process.stdout.write(JSON.stringify(result));
})().catch(() => { process.exitCode = 1; });
''')
        self.write_exe("ps", '#!/bin/bash\nprintf "%s\\n" "${PROCESSES:-}"; exit "${PS_FAIL:-0}"\n')
        self.write_exe("uname", '#!/bin/bash\nif [[ "$1" == -s ]]; then echo "${KERNEL:-Linux}"; else echo "${RELEASE:-6.6.0-microsoft-standard-WSL2}"; fi\n')
        for tool in ["systemctl", "launchctl", "tailscale", "curl", "wget", "bun", "sudo", "ssh", "nohup"]:
            self.write_exe(tool, '#!/bin/bash\necho "FORBIDDEN $0 $*" >> "$EVENTS"; exit 97\n')
        # This is an inert native-npm command fixture, not a success-only stub.
        # It validates every argv, destination and scoped policy before writing artifacts.
        self.write_exe("npm", f"#!{sys.executable}\n" + '''import json, os, pathlib, subprocess, sys
root=pathlib.Path(os.environ['FIXTURE_ROOT']); actual=sys.argv[1:]
with open(os.environ['EVENTS'],'a') as f: f.write('npm '+json.dumps(actual)+'\\n')
# Only production may pin config paths. The fixture preserves ordinary native
# default resolution from npm_config_prefix and HOME, with no injected paths.
context=[a for a in actual if a.startswith(('--userconfig=', '--globalconfig='))]
args=[a for a in actual if a not in context]
if args==['--version']: print(os.environ.get('NPM_VERSION','11.19.0')); sys.exit(0)
if args in [['--global','config','get','userconfig'], ['--global','config','get','globalconfig']]:
    if os.environ.get('NATIVE')=='1':
        sys.exit(subprocess.call([os.environ['FIXTURE_NODE'],os.environ['FIXTURE_NPM']]+actual))
    if os.environ.get('CONFIG_PATH_FAIL')=='1': sys.exit(1)
    print(str(pathlib.Path(os.environ['HOME'])/'.npmrc') if args[-1]=='userconfig' else str(root/'original-prefix/etc/npmrc')); sys.exit(0)
prefix=str(pathlib.Path(os.environ['HOME'])/'.local/share/setup-bb-machine/npm')
base=['--global','--prefix',prefix]
allow='--allow-scripts=better-sqlite3,node-pty,@parcel/watcher'
if args[:5]==base+['config','get']:
    if os.environ.get('NATIVE')=='1':
        sys.exit(subprocess.call([os.environ['FIXTURE_NODE'],os.environ['FIXTURE_NPM']]+actual))
    key=args[5]; rest=args[6:]
    values={'ignore-scripts':os.environ.get('IGNORE','false'),'dangerously-allow-all-scripts':os.environ.get('DANGEROUS','false'),'allow-scripts':os.environ.get('ALLOW',''),'strict-allow-scripts':'true'}
    if rest:
        assert rest==[allow] or rest==['--strict-allow-scripts']
        value='better-sqlite3,node-pty,@parcel/watcher' if rest==[allow] else os.environ.get('STRICT','true')
    else: value=values[key]
    print(value); sys.exit(0)
install=['install']+base+['--engine-strict','--strict-allow-scripts',allow,'bb-app@latest']
rebuild=['rebuild']+base+['--strict-allow-scripts',allow,'better-sqlite3','node-pty','@parcel/watcher']
assert args in [install,rebuild], args
if os.environ.get('NATIVE')=='1':
    # Load native npm config for the EXACT production argv at BOTH operations.
    # Only nonsecret fixture settings and an auth-preserved boolean are emitted.
    observed=json.loads(subprocess.check_output([os.environ['FIXTURE_NODE'],str(root/'native-config.cjs'),json.dumps(actual)],text=True))
    observed['operation']=args[0]
    with open(root/'native-config.jsonl','a') as f: f.write(json.dumps(observed)+'\\n')
    actual=[str(root/'fixture.tgz') if a=='bb-app@latest' else a for a in actual]
    actual+=['--offline','--audit=false','--fund=false']
    sys.exit(subprocess.call([os.environ['FIXTURE_NODE'],os.environ['FIXTURE_NPM']]+actual))
if args==rebuild: sys.exit(int(os.environ.get('FAIL_REBUILD','0')))
files=json.loads((root/'package.json').read_text()); pkg=pathlib.Path(prefix)/'lib/node_modules/bb-app'
for name, contents in files.items():
    dest=pkg/name; dest.parent.mkdir(parents=True,exist_ok=True); dest.write_text(contents); dest.chmod(0o700 if name.startswith('dist/') else 0o600)
for name, dest in json.loads(files['package.json'])['bin'].items():
    link=pathlib.Path(prefix)/'bin'/name; link.parent.mkdir(parents=True,exist_ok=True)
    if not link.is_symlink(): link.symlink_to('../lib/node_modules/bb-app/'+dest)
if os.environ.get('MISSING'): (pkg/os.environ['MISSING']).unlink()
if os.environ.get('EMPTY'): (pkg/os.environ['EMPTY']).write_text('')
sys.exit(int(os.environ.get('FAIL_INSTALL','0')))
''')
        self.package()

    def write_exe(self, name, content):
        f = self.tools / name
        f.write_text(content)
        f.chmod(0o700)

    def package(self, version="0.44.0", native=False):
        files = fixture_package(version, native)
        (self.root / "package.json").write_text(json.dumps({k: v.decode() for k, v in files.items()}))
        if native:
            with tarfile.open(self.root / "fixture.tgz", "w:gz") as tar:
                for name, content in files.items():
                    entry = tarfile.TarInfo("package/" + name)
                    entry.size = len(content)
                    entry.mode = 0o755 if name.startswith("dist/") else 0o644
                    tar.addfile(entry, io.BytesIO(content))

    def run_helper(self, platform="ubuntu", expected=0, **env):
        script = '''source "$FIXTURE_ROOT/helpers.sh"
print_message() { printf 'message: %s\\n' "$*"; }
print_success() { printf 'success: %s\\n' "$*"; }
print_error() { printf 'error: %s\\n' "$*"; }
ensure_shared_node_runtime() { echo runtime >> "$EVENTS"; return "${RUNTIME_FAIL:-0}"; }
setup_bb_machine "$1"
'''
        result = subprocess.run(["/bin/bash", "-c", script, "fixture", platform], env=self.env | env, cwd=self.home, text=True, capture_output=True, timeout=40)
        self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
        self.assertNotIn("FORBIDDEN", self.log())
        self.assertNotIn("success:", result.stdout if expected else "")
        return result.stdout

    def log(self):
        return self.events.read_text() if self.events.exists() else ""

    def test_identical_helpers(self):
        for source in SOURCES.values():
            self.assertEqual(BLOCK, source.split(START, 1)[1].split(END, 1)[0])

    def test_system_home_alias_and_runtime_boundaries(self):
        # Virtual filesystem only: never touch the host /home or simulate with sudo.
        code = BLOCK.split("<<'BB_MACHINE_STATE'\n", 1)[1].split('\nBB_MACHINE_STATE', 1)[0]
        driver = r'''
const vm = require('node:vm');
const fixture = JSON.parse(process.argv[1]), code = process.argv[2];
const fakeProcess = {argv: ['node', '-', 'preflight', '/home/fixture'], getuid: () => 1000, platform: fixture.platform || 'linux', versions: {node: fixture.node || '24.20.0'}, exitCode: 0};
const fs = {
  lstatSync(p) {
    if (!['/', '/var', '/var/home', '/home', '/home/fixture'].includes(p)) throw Object.assign(Error(), {code: 'ENOENT'});
    const link = (p === '/home') || (p === '/home/fixture' && fixture.userLink);
    return {uid: p === '/home/fixture' ? 1000 : (p === '/home' && fixture.foreignAlias ? 1000 : 0), mode: p === '/var/home' && fixture.writable ? 0o775 : 0o755, isSymbolicLink: () => link, isDirectory: () => !link};
  },
  readlinkSync() { return fixture.target || '/var/home'; }
};
vm.runInNewContext(code, {process: fakeProcess, require: n => n === 'node:fs' ? fs : n === 'node:child_process' ? {execFileSync: () => ''} : require(n)});
process.exit(fakeProcess.exitCode);
'''
        for fixture, expected in [({}, 0), ({'target': 'var/home'}, 0), ({'target': '/other'}, 1), ({'foreignAlias': True}, 1), ({'writable': True}, 1), ({'userLink': True}, 1), ({'platform': 'darwin'}, 1), ({'node': '23.0.0'}, 1), ({'node': '22.18.0'}, 1)]:
            with self.subTest(fixture=fixture):
                result = subprocess.run([NODE, '-e', driver, json.dumps(fixture), code], env=self.env, capture_output=True, text=True, timeout=10)
                self.assertEqual(result.returncode, expected, result.stderr)

    def test_first_install_update_and_unrelated_preservation(self):
        for name in [".env.local", ".npmrc", ".bashrc", "project/file", ".pi/agent/auth.json", ".local/lib/node_modules/other/data"]:
            p = self.home / name
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text("fixture-preserve\n")
        before = {name: (self.home / name).read_bytes() for name in [".env.local", ".npmrc", ".bashrc", "project/file", ".pi/agent/auth.json", ".local/lib/node_modules/other/data"]}
        for version in ["0.44.0", "0.44.0", "0.45.0"]:
            self.package(version)
            out = self.run_helper(WORK_MACHINE="1", HEADLESS="0")
            self.assertIn("not enrolled", out)
            self.assertIn("ONE chosen BB server", out)
            self.assertEqual(json.loads((self.pkg / "package.json").read_text())["version"], version)
        for name, data in before.items():
            self.assertEqual((self.home / name).read_bytes(), data)
        self.assertFalse((self.home / ".bb").exists())
        self.assertFalse((self.home / ".bb-machines").exists())
        self.assertFalse((self.home / ".local/bin").exists())
        self.assertFalse((self.home / ".config/systemd").exists())

    def test_role_deferrals_do_not_even_call_runtime_or_npm(self):
        for name in [".bb", ".bb-machines/server/npm", ".config/setup-bb-server", ".config/systemd/user/setup-bb-app.service", ".config/systemd/user/bb-host-daemon-test.service", "Library/LaunchAgents/app.getbb.host-daemon.test.plist"]:
            with self.subTest(name=name):
                p = self.home / name
                p.parent.mkdir(parents=True, exist_ok=True)
                p.write_text("preserve including malformed metadata")
                before = snapshot(self.home)
                for flag in ["", "0", "1"]:
                    out = self.run_helper(BB_SERVER=flag, RUNTIME_FAIL="1")
                    self.assertIn("readiness was not checked", out)
                    self.assertEqual(snapshot(self.home), before)
                    self.assertEqual(self.log(), "")
                p.unlink()
                # Remove the test's empty enrollment root as it too is a deferral.
                if (self.home / ".bb-machines").exists():
                    shutil.rmtree(self.home / ".bb-machines")
                if (self.home / ".config/setup-bb-server").exists():
                    (self.home / ".config/setup-bb-server").unlink()
        for setting in ["BB_DATA_DIR", "BB_APP_NPM_PREFIX"]:
            self.run_helper(**{setting: "/custom/location"})
            self.assertEqual(self.log(), "")

    def test_pairing_freezes_already_prepared_software_and_fallback(self):
        self.run_helper()
        paired = self.home / ".bb-machines/server"
        paired.mkdir(parents=True)
        (paired / "host-identity.json").write_text('{"token":"fixture-only"}')
        (paired / "npm").mkdir()
        (paired / "config.json").write_text('{"serverUrl":"https://fixture.ts.net"}')
        unit = self.home / ".config/systemd/user/bb-host-daemon-fixture.service"
        unit.parent.mkdir(parents=True)
        unit.write_text(f"ExecStart={self.prefix}/bin/bb-app host-daemon --auto-update\n")
        before = snapshot(self.home)
        self.events.unlink()
        self.package("0.45.0")
        self.run_helper(BB_SERVER="0")
        self.assertEqual(snapshot(self.home), before)
        self.assertEqual(self.log(), "")

    def test_unmanaged_bins_and_owned_tree_conflicts(self):
        self.write_exe("bb", '#!/bin/bash\necho FORBIDDEN >> "$EVENTS"; exit 97\n')
        before = snapshot(self.home)
        self.run_helper(expected=1)
        self.assertEqual(before, snapshot(self.home))
        self.assertEqual(self.log(), "")
        (self.tools / "bb").unlink()
        self.prefix.mkdir(parents=True)
        self.run_helper(expected=1)
        self.assertNotIn("npm", self.log())

    def test_stopped_custom_service_references_and_unrelated_services(self):
        self.run_helper()
        for name in ['.config/systemd/user/my-agent.service', 'Library/LaunchAgents/com.example.agent.plist']:
            with self.subTest(name=name):
                unit = self.home / name
                unit.parent.mkdir(parents=True, exist_ok=True)
                unit.write_text(f'ExecStart={self.prefix}/bin/bb-app --data-dir /custom/state\n')
                before = snapshot(self.home)
                self.events.unlink()
                self.run_helper(expected=1)
                self.assertEqual(snapshot(self.home), before)
                self.assertNotIn('npm', self.log())
                unit.write_text('unrelated service preserved\n')
                self.run_helper()
                self.assertEqual(unit.read_text(), 'unrelated service preserved\n')
                unit.unlink()

    def test_linked_empty_masked_and_actual_service_references(self):
        unit = self.home / '.config/systemd/user/other.service'
        agent = self.home / 'Library/LaunchAgents/homebrew.mxcl.example.plist'
        for registration in [unit, agent]:
            registration.parent.mkdir(parents=True)
        target = self.home / 'other.service'
        target.write_text('[Service]\nExecStart=/usr/bin/true\n')
        unit.symlink_to(target)
        # Homebrew-style LaunchAgent: a relative leaf link through an opt link.
        cellar = self.home / 'homebrew/Cellar/example/1.0'
        cellar.mkdir(parents=True)
        brew_target = cellar / 'example.plist'
        brew_target.write_text('<plist><dict><key>Program</key><string>/usr/bin/true</string></dict></plist>')
        opt = self.home / 'homebrew/opt/example'
        opt.parent.mkdir(parents=True)
        opt.symlink_to('../Cellar/example/1.0')
        agent.symlink_to(os.path.relpath(opt / 'example.plist', agent.parent))
        masked = unit.with_name('masked.service')
        masked.symlink_to('/dev/null')
        empty = unit.with_name('empty.service')
        empty.write_text('')
        before = snapshot(self.home)
        self.run_helper()  # Fresh install, followed by safe rerun, leaves all links/targets alone.
        self.run_helper()
        after = {row[0]: row for row in snapshot(self.home)}
        for row in before:
            self.assertEqual(after[row[0]], row)
        target.write_text(f'[Service]\nExecStart={self.prefix}/bin/bb-app --data-dir /custom\n')
        before = snapshot(self.home)
        self.events.unlink()
        self.run_helper(expected=1)
        self.assertNotIn('npm', self.log())
        self.assertEqual(snapshot(self.home), before)
        target.write_text('[Service]\nExecStart=/usr/bin/true\n')
        brew_target.write_text(f'<plist><dict><key>Program</key><string>{self.prefix}/bin/bb-app</string></dict></plist>')
        before = snapshot(self.home)
        self.run_helper(expected=1)
        self.assertNotIn('npm', self.log())
        self.assertEqual(snapshot(self.home), before)
        brew_target.write_text('<plist/>')
        # Unknown or unsafe read targets cannot be treated as proven unrelated.
        target.unlink()
        self.run_helper(expected=1)  # Dangling reference.
        os.mkfifo(target)
        self.run_helper(expected=1)  # No blocking read of the FIFO.
        target.unlink()
        target.write_text('unrelated')
        target.chmod(0o666)
        self.run_helper(expected=1)

    def test_wsl_exact_headless_semantics(self):
        for flags in [{}, {'HEADLESS': ''}, {'HEADLESS': '0'}, {'HEADLESS': 'true'}, {'HEADLESS': 'false'}]:
            with self.subTest(flags=flags):
                self.run_helper('wsl', **flags)
        self.run_helper('wsl', expected=1, HEADLESS='1')

    def test_native_original_prefix_policy_and_precedence(self):
        self.package(native=True)
        self.globalconfig.write_text('ignore-scripts=true\nregistry=https://fixture.invalid/\nallow-git=none\nallow-remote=none\n')
        self.run_helper(NATIVE='1', expected=1)
        self.assertFalse(self.prefix.parent.exists())
        self.assertFalse((self.root / 'native-config.jsonl').exists())
        self.globalconfig.write_text('ignore-scripts=false\nregistry=https://fixture.invalid/\nallow-git=none\nallow-remote=none\n')
        self.globalconfig.write_text(self.globalconfig.read_text() + '//fixture.invalid/:_authToken=inert-fixture-token\n')
        self.run_helper(NATIVE='1', ASSERT_FIXTURE_AUTH='1')
        # Native user and environment value precedence must survive the path pin.
        self.globalconfig.write_text(self.globalconfig.read_text().replace('ignore-scripts=false', 'ignore-scripts=true'))
        self.userconfig.write_text('ignore-scripts=false\nregistry=https://user.fixture.invalid/\n')
        self.run_helper(NATIVE='1', ASSERT_FIXTURE_AUTH='1')
        selected_user = self.root / 'selected user.npmrc'
        selected_user.write_text('ignore-scripts=true\nregistry=https://selected-user.fixture.invalid/\n')
        self.run_helper(NATIVE='1', ASSERT_FIXTURE_AUTH='1', npm_config_userconfig=str(selected_user), npm_config_ignore_scripts='false', npm_config_registry='https://env.fixture.invalid/')
        observed = [json.loads(line) for line in (self.root / 'native-config.jsonl').read_text().splitlines()]
        self.assertEqual([item['operation'] for item in observed], ['install', 'rebuild'] * 3)
        for index, item in enumerate(observed):
            self.assertEqual(item['registry'], ['https://fixture.invalid/', 'https://user.fixture.invalid/', 'https://env.fixture.invalid/'][index // 2])
            self.assertEqual(item['globalconfig'], str(self.globalconfig))
            self.assertEqual(item['userconfig'], str(selected_user if index >= 4 else self.userconfig))
            self.assertIs(item['ignore-scripts'], False)
            self.assertEqual(item['allow-git'], 'none')
            self.assertEqual(item['allow-remote'], 'none')
            self.assertTrue(item['authPreserved'])
        self.assertNotIn('inert-fixture-token', self.log())
        selected_global = self.root / 'selected global.npmrc'
        selected_global.write_text(self.globalconfig.read_text().replace('fixture.invalid/', 'selected.fixture.invalid/'))
        # Explicit config-path overrides are captured, not replaced by defaults.
        self.run_helper(NATIVE='1', NPM_CONFIG_GLOBALCONFIG=str(selected_global), NPM_CONFIG_USERCONFIG=str(self.root / 'absent-user.npmrc'), npm_config_ignore_scripts='false')
        last = [json.loads(line) for line in (self.root / 'native-config.jsonl').read_text().splitlines()][-2:]
        for item in last:
            self.assertEqual(item['globalconfig'], str(selected_global))
            self.assertEqual(item['registry'], 'https://selected.fixture.invalid/')
            self.assertEqual(item['userconfig'], str(self.root / 'absent-user.npmrc'))

    def test_custom_process_and_unsafe_metadata_fail_before_npm(self):
        for command in ['node /custom/bb-app/dist/bb-app.js --data-dir /other', 'bb-host-daemon', '/custom/bin/bb-server --data-dir /private', 'node /custom/bin/bb-host-daemon.js']:
            self.run_helper(expected=1, PROCESSES=command)
            self.assertNotIn('npm', self.log())
            self.assertFalse(self.prefix.parent.exists())
        self.run_helper(expected=1, PS_FAIL='1')
        self.assertNotIn('npm', self.log())
        self.run_helper(PROCESSES='node unrelated-program.js\n/usr/bin/bash')
        manifest = self.pkg / 'package.json'
        original = manifest.read_bytes()
        for data in ['{', '{"name":"custom-package"}']:
            manifest.write_text(data)
            self.events.unlink()
            self.run_helper(expected=1)
            self.assertNotIn('npm', self.log())
            self.assertEqual(manifest.read_text(), data)
        manifest.write_bytes(original)
        manifest.unlink()
        os.mkfifo(manifest)
        self.run_helper(expected=1)  # Must fail promptly rather than open the FIFO.

    def test_policy_failures_leave_no_owned_record(self):
        for settings in [{"NPM_VERSION": "11.18.0"}, {"IGNORE": "true"}, {"DANGEROUS": "true"}, {"ALLOW": "none"}, {"STRICT": "false"}, {"RUNTIME_FAIL": "1"}, {"CONFIG_PATH_FAIL": "1"}]:
            with self.subTest(settings=settings):
                self.run_helper(expected=1, **settings)
                self.assertFalse(self.prefix.parent.exists())
                self.assertNotIn('npm ["install"', self.log())
        self.run_helper(ALLOW="better-sqlite3,node-pty,@parcel/watcher")
        self.run_helper(ALLOW="@parcel/watcher, better-sqlite3, node-pty")

    def test_partial_install_retry_and_verification_failures(self):
        self.run_helper(expected=1, FAIL_INSTALL="1", MISSING="dist/bb.js")
        self.assertTrue((self.prefix.parent / "owner.json").is_file())
        self.run_helper()
        for failure in [{"FAIL_REBUILD": "1"}, {"MISSING": "host-daemon/dist/daemon-bundle.mjs"}, {"MISSING": "dist/bb.js"}, {"EMPTY": "host-daemon/dist/bb-provider-bridge-worker.mjs"}] + [{"FAIL_ADDON": name} for name in ADDONS]:
            with self.subTest(failure=failure):
                self.run_helper(expected=1, **failure)
                self.run_helper()
        self.package("0.45.0-nightly.1")
        self.run_helper(expected=1)

    def test_links_metadata_and_permissions(self):
        self.run_helper()
        marker = self.prefix.parent / "owner.json"
        original = marker.read_bytes()
        marker.write_text("not JSON")
        self.events.unlink()
        self.run_helper(expected=1)
        self.assertNotIn("npm", self.log())
        marker.write_bytes(original)
        for p in [marker, self.pkg / "package.json", self.pkg / "node_modules/node-pty/index.js"]:
            with self.subTest(path=str(p)):
                backup = p.read_bytes()
                target = self.root / "outside"
                target.write_bytes(backup)
                p.unlink()
                p.symlink_to(target)
                self.events.unlink()
                self.run_helper(expected=1)
                self.assertNotIn("npm", self.log())
                self.assertEqual(target.read_bytes(), backup)
                p.unlink()
                p.write_bytes(backup)
                p.chmod(0o600)
        self.prefix.chmod(0o770)
        self.run_helper(expected=1)
        self.prefix.chmod(0o700)
        extra = self.prefix / "lib/node_modules/unrelated"
        extra.mkdir()
        self.run_helper(expected=1)
        self.assertTrue(extra.is_dir())

    def test_work_headless_platform_and_wsl2(self):
        for platform, kernel, headless in [("mac", "Darwin", "0"), ("mac", "Darwin", "1"), ("ubuntu", "Linux", "0"), ("pi", "Linux", "1"), ("bazzite", "Linux", "0"), ("wsl", "Linux", "0")]:
            with self.subTest(platform=platform, headless=headless):
                self.run_helper(platform, KERNEL=kernel, HEADLESS=headless, WORK_MACHINE="1")
        self.run_helper("wsl", expected=1, RELEASE="4.4.0-Microsoft")
        self.run_helper("wsl", expected=1, HEADLESS="1")
        self.run_helper(expected=1, KERNEL="MINGW64_NT")

    def test_native_npm_tarball_and_prefix_abi_transition(self):
        # Actual native npm, entirely offline, with bundled inert addon fixtures.
        # No BB code, real native build, network, live package tree or user npmrc.
        self.package(native=True)
        self.userconfig.write_text("ignore-scripts=true\n")
        self.run_helper(NATIVE="1", expected=1)
        self.assertFalse(self.prefix.parent.exists())
        self.userconfig.write_text("ignore-scripts=false\ndangerously-allow-all-scripts=false\n")
        self.run_helper(NATIVE="1", FIXTURE_ABI="first")
        old = self.home / ".local/share/mise/installs/node/old"
        new = self.home / ".local/share/mise/installs/node/new"
        for d in [old, new]:
            (d / "bin").mkdir(parents=True)
            (d / "bin/node").symlink_to(NODE)
            (d / "unrelated").write_text("preserve")
        before = snapshot(old)
        self.run_helper(NATIVE="1", FIXTURE_ABI="second", PATH=f"{new}/bin:{self.env['PATH']}")
        self.assertEqual(snapshot(old), before)
        self.assertEqual((new / "unrelated").read_text(), "preserve")
        self.assertEqual((self.pkg / "node_modules/better-sqlite3/built").read_text(), "second")
        self.package("0.45.0", native=True)
        self.run_helper(NATIVE="1", FIXTURE_ABI="second")
        self.assertEqual(json.loads((self.pkg / "package.json").read_text())["version"], "0.45.0")

    def test_extracted_call_sites_aggregate_and_ignore_pi_gates(self):
        for platform, source in SOURCES.items():
            with self.subTest(platform=platform):
                main = re.search(r"^run_setup_tasks\(\) \{\n.*?^\}", source, re.M | re.S).group()
                names = set(re.findall(r"^(\w+)\(\)\s*\{", source, re.M))
                stubs = "\n".join(f"{n}() {{ :; }}" for n in names if n != "run_setup_tasks")
                # Every setup operation is inert. Only the real runner control flow
                # and Ubuntu selection / WSL rejection are evaluated.
                setup = stubs + "\n" + main + '''
check_dotfiles_access() { return 1; }
setup_dotfiles_deploy_key() { return 1; }
setup_bb_machine() { echo prep >> "$EVENTS"; return "${PREP_FAIL:-0}"; }
setup_bb_server() { echo server >> "$EVENTS"; }
prepare_pi_profile_permissions() { return "${PI_FAIL:-0}"; }
env_local_flag_is_one() { [[ "${!1:-0}" == 1 ]]; }
remove_compound_engineering_resources() { echo unrelated >> "$EVENTS"; }
print_warning() { echo "$*"; }
'''
                if platform == "mac":
                    # This caller fixture begins with an inert installed brew.
                    # Keep real readiness gates; the CLT test suite supplies the
                    # actual verifier, while this suite controls its result.
                    for name in ["macos_developer_tools_ready_for", "macos_existing_prerequisites"]:
                        setup += re.search(rf"^{name}\(\) \{{\n.*?^\}}", source, re.M | re.S).group() + "\n"
                    setup += '''
ensure_macos_developer_tools_ready() { MACOS_DEVELOPER_TOOLS_STATE=${CLT_READY:-ready}; [[ "$MACOS_DEVELOPER_TOOLS_STATE" == ready ]]; }
brew() { :; }
command() {
    if [[ "$*" == '-v brew' ]]; then printf 'brew\\n'
    elif [[ "$1" == -v ]]; then return 1
    else builtin command "$@"; fi
}
'''
                if platform == "ubuntu":
                    for name in ["bb_server_selection", "bb_server_restore_process_override"]:
                        setup += re.search(rf"^{name}\(\) \{{\n.*?^\}}", source, re.M | re.S).group() + "\n"
                if platform == "wsl":
                    setup += re.search(r"^fail_unsupported_headless_paseo_daemon\(\) \{\n.*?^\}", source, re.M | re.S).group() + "\n"
                setup += 'run_setup_tasks; result=$?; echo finalized >> "$EVENTS"; exit "$result"\n'
                cases = [({}, 0, True), ({"PREP_FAIL": "1"}, 1, True), ({"PI_FAIL": "1"}, 1, True)]
                if platform == 'mac':
                    cases.append(({"CLT_READY": "unverified"}, 1, False))
                for flags, expected, prep in cases:
                    self.events.write_text("")
                    out = subprocess.run(["/bin/bash", "-c", setup], env=self.env | {"WORK_MACHINE": "1"} | flags, cwd=self.home, capture_output=True, text=True, timeout=15)
                    self.assertEqual(out.returncode, expected, out.stdout + out.stderr)
                    self.assertEqual("prep\n" in self.log(), prep)
                    self.assertIn("unrelated\n", self.log())
                    self.assertIn("finalized\n", self.log())
                    self.assertNotIn("FORBIDDEN", self.log())
                if platform == 'ubuntu':
                    for flag in ['', '0', 'invalid']:
                        self.events.write_text('')
                        out = subprocess.run(['/bin/bash', '-c', setup], env=self.env | {'BB_SERVER': flag}, cwd=self.home, capture_output=True, text=True, timeout=15)
                        self.assertEqual(out.returncode, 1 if flag == 'invalid' else 0)
                        self.assertEqual('prep\n' in self.log(), flag != 'invalid')
                        self.assertNotIn('server\n', self.log())
                if platform == 'wsl':
                    for flag in ['', '0', 'true', 'false']:
                        self.events.write_text('')
                        out = subprocess.run(['/bin/bash', '-c', setup], env=self.env | {'HEADLESS': flag}, cwd=self.home, capture_output=True, text=True, timeout=15)
                        self.assertEqual(out.returncode, 0, out.stdout + out.stderr)
                        self.assertIn('prep\n', self.log())
                if platform in ["ubuntu", "wsl"]:
                    flags = {"BB_SERVER": "1"} if platform == "ubuntu" else {"HEADLESS": "1"}
                    self.events.write_text("")
                    out = subprocess.run(["/bin/bash", "-c", setup], env=self.env | flags, cwd=self.home, capture_output=True, text=True, timeout=15)
                    self.assertEqual(out.returncode, 0 if platform == "ubuntu" else 1)
                    self.assertNotIn("prep\n", self.log())
                    if platform == "ubuntu":
                        self.assertIn("server\n", self.log())


if __name__ == "__main__":
    unittest.main(verbosity=2)
