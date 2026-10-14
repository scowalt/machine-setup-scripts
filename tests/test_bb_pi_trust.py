#!/usr/bin/env python3
import functools
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

from extract_setup_fixture import definitions

ROOT = Path(__file__).resolve().parents[1]
CORE = ROOT / 'lib/bb-pi-trust.cjs'
SCRIPTS = ('mac.sh', 'ubuntu.sh', 'wsl.sh', 'pi.sh', 'bazzite.sh', 'win.ps1')
NODE = shutil.which('node')
PWSH = os.environ.get('PWSH_BIN') or shutil.which('pwsh')
FIXTURES = ROOT / 'tests/fixtures/bb-pi-trust'


def identity(file):
    info = file.lstat()
    return info.st_dev, info.st_ino, info.st_uid, info.st_gid, info.st_mode


@functools.lru_cache(maxsize=None)
def bash_definitions(script):
    return definitions((ROOT / script).read_text())


class BbPiTrustTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='bb-pi-trust-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.home = self.root / 'account with spaces'
        self.agent = self.home / '.pi/agent'
        self.agent.mkdir(parents=True, mode=0o700)
        self.data = self.home / '.bb'
        self.worktrees = self.data / 'plugins/environment-git-worktree/host-data/worktrees'
        self.trust = self.agent / 'trust.json'
        self.env = {**os.environ, 'HOME': str(self.home), 'USERPROFILE': str(self.home),
                    'PI_CODING_AGENT_DIR': str(self.agent), 'BB_DATA_DIR': str(self.data)}
        self.env.pop('NODE_OPTIONS', None)
        self.env.pop('NODE_PATH', None)

    def policy(self, mode='merge', *extra, prelude=''):
        if prelude:
            program = self.root / 'injected.cjs'
            program.write_text(prelude + '\nprocess.exitCode = require(' + json.dumps(str(CORE)) + ').main(process.argv.slice(2));\n')
        else:
            program = CORE
        result = subprocess.run([NODE, str(program), mode, str(self.home), str(self.data), str(self.agent), *map(str, extra)],
                                env=self.env, cwd=self.root, text=True, capture_output=True, timeout=40)
        self.assertNotIn('SECRET-SENTINEL', result.stdout + result.stderr)
        self.assertNotIn(str(self.home), result.stdout + result.stderr)
        return result

    def expect_ok(self, result):
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, 'ok\n', ''))

    def seed(self, data):
        self.trust.write_text(json.dumps(data))
        self.trust.chmod(0o600)

    def roots(self):
        return [self.worktrees, self.data / 'thread-storage', self.home / 'Code']

    def test_future_roots_and_repeat_preserve_decisions_files_and_directories(self):
        prior = {str(self.worktrees / 'thr_old/repo'): True,
                 str(self.worktrees / 'thr_denied/repo'): False,
                 str(self.home / '.paseo/worktrees/legacy'): True,
                 str(self.home / 'unrelated'): None}
        self.seed(prior)
        sentinels = ['mcp-project-approvals.json', 'settings.json', 'auth.json', 'mcp-adapter.json']
        for name in sentinels:
            (self.agent / name).write_text('malformed SECRET-SENTINEL is not setup-owned')
        before = {name: ((self.agent / name).read_bytes(), identity(self.agent / name)) for name in sentinels}
        self.expect_ok(self.policy())
        expected = {**prior, **{str(root): True for root in self.roots()}}
        self.assertEqual(json.loads(self.trust.read_text()), expected)
        self.assertFalse(self.data.exists(), 'Do not provision or enumerate BB data while merging trust')
        self.assertFalse((self.home / 'Code').exists())
        original = (self.trust.read_bytes(), identity(self.trust))
        self.expect_ok(self.policy())
        self.assertEqual((self.trust.read_bytes(), identity(self.trust)), original)
        self.assertEqual({name: ((self.agent / name).read_bytes(), identity(self.agent / name)) for name in sentinels}, before)
        self.assertNotIn(str(self.home), expected)
        self.assertNotIn(str(self.data), expected)
        self.assertEqual(list(self.agent.glob('trust.json.*')), [])

    def test_selected_profile_and_bb_data_do_not_trust_default_data_or_other_profiles(self):
        inactive = self.agent / 'trust.json'
        inactive.write_text('SECRET-SENTINEL')
        self.agent = self.home / 'profiles/selected'
        self.agent.mkdir(parents=True, mode=0o700)
        self.trust = self.agent / 'trust.json'
        self.data = self.root / 'custom BB data'
        self.worktrees = self.data / 'plugins/environment-git-worktree/host-data/worktrees'
        self.expect_ok(self.policy())
        self.assertEqual(json.loads(self.trust.read_text()), {str(root): True for root in self.roots()})
        self.assertEqual(inactive.read_text(), 'SECRET-SENTINEL')
        self.assertFalse(self.data.exists())

    def test_explicit_and_inherited_denials_are_never_overridden(self):
        for denied in (self.worktrees, self.data, self.home, self.home / 'Code'):
            with self.subTest(denied=denied):
                prior = {str(denied): False, str(self.worktrees / 'thr_denied'): False,
                         str(self.worktrees / 'thr_allowed'): True}
                self.seed(prior)
                self.expect_ok(self.policy())
                actual = json.loads(self.trust.read_text())
                for name, decision in prior.items():
                    self.assertIs(actual[name], decision)
                if denied in (self.data, self.home):
                    self.assertNotIn(str(self.worktrees), actual)
                self.assertFalse(actual[str(denied)])

    def test_bom_null_and_existing_positive_decisions(self):
        self.trust.write_text('\ufeff' + json.dumps({str(self.worktrees): None, str(self.home / 'unrelated'): None}))
        self.expect_ok(self.policy())
        self.assertTrue(json.loads(self.trust.read_text())[str(self.worktrees)])
        self.assertIsNone(json.loads(self.trust.read_text())[str(self.home / 'unrelated')])

    def test_malformed_or_duplicate_decisions_fail_without_partial_writes(self):
        for text in ('{SECRET-SENTINEL', 'null', '[]', '{"/x":1}', '{"/x":{}}', '{"/x":false,"/x":true}'):
            with self.subTest(text=text):
                self.trust.write_text(text)
                before = (self.trust.read_bytes(), identity(self.trust))
                result = self.policy()
                self.assertEqual((result.returncode, result.stdout), (1, 'failed:invalid-trust\n'))
                self.assertEqual((self.trust.read_bytes(), identity(self.trust)), before)
                self.assertEqual(list(self.agent.glob('trust.json.*')), [])

    @unittest.skipIf(os.name == 'nt', 'POSIX filesystem safeguards')
    def test_file_link_hardlink_and_writable_metadata_are_refused(self):
        target = self.root / 'outside.json'
        target.write_text('SECRET-SENTINEL')
        for kind in ('symlink', 'hardlink', 'group-write', 'world-write', 'directory'):
            with self.subTest(kind=kind):
                if kind == 'symlink': self.trust.symlink_to(target)
                elif kind == 'hardlink': os.link(target, self.trust)
                elif kind == 'directory': self.trust.mkdir()
                else:
                    self.seed({})
                    self.trust.chmod(0o620 if kind == 'group-write' else 0o602)
                result = self.policy()
                self.assertEqual((result.returncode, result.stdout), (1, 'failed:unsafe-metadata\n'))
                self.assertEqual(target.read_text(), 'SECRET-SENTINEL')
                self.trust.rmdir() if kind == 'directory' else self.trust.unlink()

    @unittest.skipIf(os.name == 'nt', 'POSIX directory mode and link policy')
    def test_ordinary_group_access_is_preserved_but_links_and_private_profile_fail(self):
        self.worktrees.mkdir(parents=True)
        ordinary = (self.home, self.data, self.worktrees.parent, self.worktrees)
        for directory in ordinary: directory.chmod(0o2775)
        before = {p: identity(p) for p in ordinary}
        self.expect_ok(self.policy())
        self.assertEqual({p: identity(p) for p in ordinary}, before)
        self.agent.chmod(0o775)
        self.assertIn('failed:unsafe-profile', self.policy().stdout)
        self.agent.chmod(0o700)
        self.data.chmod(0o2777)
        self.assertIn('failed:unsafe-directory', self.policy().stdout)
        self.data.chmod(0o2775)
        linked = self.home / 'linked'
        linked.symlink_to(self.data, target_is_directory=True)
        self.data = linked
        self.assertIn('failed:unsafe-directory', self.policy().stdout)

    def test_invalid_paths_and_target_profiles_fail_closed(self):
        for data in ('relative', str(self.home / '../escape'), '~/../escape', '~/.bb/../escape', str(self.home), '/'):
            with self.subTest(data=data):
                self.data = data
                self.assertNotEqual(self.policy().returncode, 0)
                self.assertFalse(self.trust.exists())
        self.data = self.home / '.bb'
        for agent in (self.home, self.root, self.home / 'missing/leaf'):
            self.agent = agent
            self.assertNotEqual(self.policy().returncode, 0)
        self.assertFalse(self.trust.exists())

    def test_native_lock_path_is_respected_even_if_old_or_linked(self):
        lock = self.agent / 'trust.json.lock'
        for kind in ('directory', 'file', 'link'):
            with self.subTest(kind=kind):
                if kind == 'directory': lock.mkdir()
                elif kind == 'file': lock.write_text('SECRET-SENTINEL')
                else: lock.symlink_to(self.root, target_is_directory=True)
                os.utime(lock, (1, 1), follow_symlinks=False)
                before = identity(lock)
                result = self.policy()
                self.assertEqual((result.returncode, result.stdout), (1, 'failed:trust-locked\n'))
                self.assertEqual(identity(lock), before)
                self.assertFalse(self.trust.exists())
                lock.rmdir() if kind == 'directory' else lock.unlink()

    def test_concurrent_writer_is_preserved_and_accepted_mode_changes_invalidate_snapshots(self):
        self.seed({str(self.home / 'old'): True})
        trust_name = json.dumps(str(self.trust))
        prelude = '''const fs = require('node:fs'), original = fs.writeFileSync;
fs.writeFileSync = (file, ...args) => {
    const result = original(file, ...args);
    if (String(file).includes('.setup-')) original(''' + trust_name + ''', '{"/concurrent":false}');
    return result;
};'''
        result = self.policy(prelude=prelude)
        self.assertIn('failed:changed-input', result.stdout)
        self.assertEqual(json.loads(self.trust.read_text()), {'/concurrent': False})
        self.assertEqual(list(self.agent.glob('trust.json.*')), [])
        prelude = '''const fs = require('node:fs'), original = fs.writeFileSync;
fs.writeFileSync = (file, ...args) => {
    const result = original(file, ...args);
    if (String(file).includes('.setup-')) fs.chmodSync(''' + json.dumps(str(self.home)) + ''', 0o2775);
    return result;
};'''
        result = self.policy(prelude=prelude)
        self.assertIn('failed:changed-input', result.stdout)
        self.assertEqual(json.loads(self.trust.read_text()), {'/concurrent': False})
        self.assertTrue((self.agent / 'trust.json.lock').exists(), 'Retain uncertain recovery state')

    @unittest.skipIf(os.name == 'nt', 'POSIX accepted-mode race')
    def test_repeated_ancestor_inspection_cannot_replace_an_earlier_snapshot(self):
        prelude = '''const fs = require('node:fs'), original = fs.lstatSync;
let visits = 0;
fs.lstatSync = (file, ...args) => {
    if (file === ''' + json.dumps(str(self.home)) + ''' && ++visits === 2) fs.chmodSync(file, 0o2775);
    return original(file, ...args);
};'''
        result = self.policy(prelude=prelude)
        self.assertEqual((result.returncode, result.stdout), (1, 'failed:changed-input\n'))
        self.assertFalse(self.trust.exists())
        self.assertFalse((self.agent / 'trust.json.lock').exists())

    def wrapper(self, script, action='merge', extra=(), overrides=None):
        env = {**self.env, **(overrides or {})}
        if script.endswith('.ps1'):
            if not PWSH: self.skipTest('Set PWSH_BIN for portable wrapper coverage')
            code = r'''$ErrorActionPreference='Stop'
$tokens=$null; $errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile($env:FIXTURE_SOURCE,[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw 'Invalid fixture AST' }
foreach ($node in $ast.EndBlock.Statements) {
    if ($node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -in @('Invoke-BbPiTrustPolicy','Configure-BbPiTrust','Test-BbPiMcpHealth')) {
        . ([scriptblock]::Create($node.Extent.Text))
    }
}
function Write-Debug { }
function Write-Warning($Text) { Write-Host $Text }
$script:PiProfileMutationsBlocked=$env:FIXTURE_BLOCKED -eq '1'
'''
            code += '$result=' + ('Configure-BbPiTrust' if action == 'merge' else 'Test-BbPiMcpHealth -WorkingDirectory $args[0] -RequiredServers @($args | Select-Object -Skip 1)')
            code += '\nif (-not $result) { exit 1 }\n'
            fixture = self.root / 'wrapper.ps1'
            fixture.write_text(code)
            command = [PWSH, '-NoProfile', '-NonInteractive', '-File', str(fixture), *map(str, extra)]
        else:
            code = bash_definitions(script)
            code += '\nprint_debug() { :; }; print_warning() { printf "%s\\n" "$*"; };\n'
            code += '\n' + ('configure_bb_pi_trust' if action == 'merge' else 'check_bb_pi_mcp_health "$@"') + '\n'
            fixture = self.root / 'wrapper.sh'
            fixture.write_text(code)
            command = ['/bin/bash', '--noprofile', '--norc', str(fixture), *map(str, extra)]
        return subprocess.run(command, env={**env, 'FIXTURE_SOURCE': str(ROOT / script)}, cwd=self.root,
                              capture_output=True, text=True, timeout=40)

    def test_six_embedded_wrappers_converge_and_honor_blocked_and_optout_profiles(self):
        subprocess.run(['/usr/bin/python3', '-I', str(ROOT / 'tools/embed-bb-pi-trust.py'), '--check'], check=True)
        for script in SCRIPTS:
            with self.subTest(script=script):
                result = self.wrapper(script)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(json.loads(self.trust.read_text()), {str(p): True for p in self.roots()})
                original = (self.trust.read_bytes(), identity(self.trust))
                self.assertEqual(self.wrapper(script).returncode, 0)
                self.assertEqual((self.trust.read_bytes(), identity(self.trust)), original)
                self.trust.unlink()
                self.assertEqual(self.wrapper(script, overrides={'BAN_PI_MCP_ADAPTER': '1'}).returncode, 0)
                self.assertFalse(self.trust.exists())
                blocked = self.wrapper(script, overrides={'PI_PROFILE_MUTATIONS_BLOCKED': '1', 'FIXTURE_BLOCKED': '1'})
                self.assertEqual(blocked.returncode, 1)
                self.assertFalse(self.trust.exists())
                marker = self.root / 'injected'
                loader = self.root / 'inject.cjs'
                loader.write_text('require("node:fs").writeFileSync(' + json.dumps(str(marker)) + ', "forbidden");')
                result = self.wrapper(script, overrides={'NODE_OPTIONS': '--require=' + str(loader), 'NODE_PATH': str(self.root)})
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertFalse(marker.exists())
                self.trust.unlink()

    def fake_doctor(self, report, status=0):
        target = self.worktrees / 'thr_fresh/repo'
        target.mkdir(parents=True, exist_ok=True)
        cli = self.agent / 'npm/node_modules/pi-mcp-adapter/cli.js'
        cli.parent.mkdir(parents=True, exist_ok=True)
        cli.write_text('''const fs = require('node:fs');
if (JSON.stringify(process.argv.slice(2)) !== '["doctor","--json"]') process.exit(99);
fs.writeFileSync(process.env.FIXTURE_DOCTOR_CALL, JSON.stringify({cwd:process.cwd(), agent:process.env.PI_CODING_AGENT_DIR}));
console.error('SECRET-SENTINEL must never escape');
console.log(''' + json.dumps(report if isinstance(report, str) else json.dumps(report)) + ''');
process.exitCode = ''' + str(status) + ';\n')
        self.env['FIXTURE_DOCTOR_CALL'] = str(self.root / 'doctor-call.json')
        return target

    def test_health_checks_json_not_zero_exit_and_requires_expected_servers(self):
        cases = [([{'name': 'reviewed', 'state': 'ok', 'tools': 1}], 0, 'ok'),
                 ([{'name': 'reviewed', 'state': 'blocked', 'message': 'SECRET-SENTINEL'}], 0, 'failed:doctor-blocked'),
                 ([{'name': 'reviewed', 'state': 'disabled'}], 0, 'failed:doctor-missing-server'),
                 ([{'name': 'other', 'state': 'ok', 'tools': 1}], 0, 'failed:doctor-missing-server'),
                 ([{'name': 'reviewed', 'state': 'needs-auth'}], 0, 'failed:doctor-unhealthy'),
                 ([{'name': 'reviewed', 'state': 'failed'}], 1, 'failed:doctor-failed'),
                 ([{'name': 'reviewed', 'state': 'ok', 'tools': None}], 0, 'failed:invalid-doctor-report'),
                 ('[]', 0, 'failed:invalid-doctor-report'), ('{}', 0, 'failed:invalid-doctor-report'),
                 ('garbage SECRET-SENTINEL', 0, 'failed:invalid-doctor-report')]
        for report, status, expected in cases:
            with self.subTest(report=report):
                target = self.fake_doctor(report, status)
                result = self.policy('health', target, 'reviewed')
                self.assertEqual((result.returncode, result.stdout), (0 if expected == 'ok' else 1, expected + '\n'))
                self.assertEqual(json.loads((self.root / 'doctor-call.json').read_text()), {'cwd': str(target), 'agent': str(self.agent)})
        for script in ('ubuntu.sh', 'win.ps1'):
            if script.endswith('.ps1') and not PWSH: continue
            self.fake_doctor([{'name': 'reviewed', 'state': 'blocked'}])
            result = self.wrapper(script, 'health', (target, 'reviewed'))
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            self.assertIn('failed:doctor-blocked', result.stdout)
            self.assertNotIn('SECRET-SENTINEL', result.stdout + result.stderr)

    @unittest.skipUnless(PWSH, 'Set PWSH_BIN to parse the native ACL payload')
    def test_windows_acl_payload_parses_without_executing_native_operations(self):
        source = CORE.read_text()
        program = re.search(r'const program = String.raw`(.*?)`;', source, re.S)[1]
        native = self.root / 'native-acl.ps1'
        native.write_text(program)
        parser = self.root / 'parse.ps1'
        parser.write_text("$tokens=$null; $errors=$null\n"
                          "$null=[System.Management.Automation.Language.Parser]::ParseFile($args[0],[ref]$tokens,[ref]$errors)\n"
                          "if ($errors.Count) { exit 1 }\n")
        result = subprocess.run([PWSH, '-NoProfile', '-NonInteractive', '-File', str(parser), str(native)],
                                env=self.env, cwd=self.root, capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    @unittest.skipUnless(PWSH, 'Set PWSH_BIN for inert ACL-policy fixtures')
    def test_native_acl_policy_preserves_system_ancestor_rules_and_rejects_effective_writers(self):
        program = re.search(r'const program = String.raw`(.*?)`;', CORE.read_text(), re.S)[1]
        identity_expression = '[Security.Principal.WindowsIdentity]::GetCurrent().User.Value'
        self.assertEqual(program.count(identity_expression), 1)
        program = program.replace(identity_expression, "'S-1-5-21-fixture'")
        prelude = r'''
function Test-Path { param($LiteralPath) return $true }
function Get-Item {
    param($LiteralPath, [switch]$Force)
    $attributes=[IO.FileAttributes]::Directory
    if ($env:ACL_CASE -eq 'reparse' -and $LiteralPath -like '*profile') { $attributes=$attributes -bor [IO.FileAttributes]::ReparsePoint }
    return [pscustomobject]@{Attributes=$attributes}
}
$script:aclReads=0
function Get-Acl {
    param($LiteralPath)
    $script:aclReads++
    $account=$LiteralPath -like '*profile'
    $owner=if ($account) { 'S-1-5-21-fixture' } else { 'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464' }
    if ($account -and $env:ACL_CASE -eq 'foreign-owner') { $owner='S-1-5-21-foreign' }
    $rights=if (-not $account -or $env:ACL_CASE -in @('writer','inherit-only')) { [Security.AccessControl.FileSystemRights]::Write } else { 0 }
    $propagation=if ($env:ACL_CASE -eq 'inherit-only') { [Security.AccessControl.PropagationFlags]::InheritOnly } else { 0 }
    $sddl=if ($env:ACL_CASE -eq 'changed' -and $script:aclReads -eq 2) { 'changed' } else { 'stable' }
    $acl=[pscustomobject]@{OwnerValue=$owner;Sddl=$sddl;Rules=@([pscustomobject]@{
        AccessControlType='Allow';IdentityReference=[pscustomobject]@{Value='S-1-5-21-other'};
        FileSystemRights=$rights;PropagationFlags=$propagation})}
    $acl | Add-Member -MemberType ScriptMethod -Name GetOwner -Value { param($Type) return [pscustomobject]@{Value=$this.OwnerValue} }
    $acl | Add-Member -MemberType ScriptMethod -Name GetAccessRules -Value { param($Explicit,$Inherited,$Type) return $this.Rules }
    return $acl
}
'''
        fixture = self.root / 'inert-acls.ps1'
        fixture.write_text(prelude + program)
        request = json.dumps({'files': ['C:\\', 'C:\\profile'], 'accountPaths': ['C:\\profile']})
        for case in ('system-ancestor', 'inherit-only', 'writer', 'foreign-owner', 'reparse', 'changed'):
            with self.subTest(case=case):
                result = subprocess.run([PWSH, '-NoProfile', '-NonInteractive', '-File', str(fixture)],
                                        input=request, env={**self.env, 'ACL_CASE': case}, cwd=self.root,
                                        capture_output=True, text=True, timeout=20)
                self.assertEqual(result.returncode, 0 if case in ('system-ancestor', 'inherit-only') else 1,
                                 result.stdout + result.stderr)
                if result.returncode == 0:
                    self.assertEqual(len(json.loads(result.stdout)), 2)

    def materialize_native_admission(self):
        destination = self.root / 'native-fixtures'
        destination.mkdir()
        for name, expected in [('adapter-project-server-trust.js', '5a7b9b6ad3152bcff260af21c14e70ddc312849ecf4a1bc393c3e1d946376ec0'),
                               ('pi-trust-manager.js', 'ce8644574983b5f8a04059545305b63463557cdf8d09049c35590cb937a70c76')]:
            source = (FIXTURES / 'vendor' / name).read_bytes()
            self.assertEqual(hashlib.sha256(source).hexdigest(), expected)
            text = source.decode()
            replacements = {
                'import { getAgentPath } from "./agent-dir.js";': 'const getAgentPath = (...parts) => join(process.env.PI_CODING_AGENT_DIR, ...parts);',
                'import { isServerDisabled } from "./types.js";': 'const isServerDisabled = definition => definition?.disabled === true;',
                'import { CONFIG_DIR_NAME } from "../config.js";': 'const CONFIG_DIR_NAME = ".pi";',
                'import { canonicalizePath, resolvePath } from "../utils/paths.js";':
                    'import { realpathSync } from "node:fs"; import { resolve as resolvePath } from "node:path"; const canonicalizePath = file => { try { return realpathSync(file); } catch { return file; } };',
                'import { stripBom } from "../utils/text.js";': 'const stripBom = text => text.replace(/^\\uFEFF/, "");',
                'import lockfile from "proper-lockfile";': 'import { mkdirSync as lockMkdir, rmdirSync as lockRmdir } from "node:fs"; const lockfile = { lockSync: (dir, options) => { if (options.lockfilePath !== process.env.PI_CODING_AGENT_DIR + "/trust.json.lock") throw Error("wrong native lock path"); lockMkdir(options.lockfilePath); return () => lockRmdir(options.lockfilePath); } };',
            }
            for original, replacement in replacements.items():
                if original in text:
                    self.assertEqual(text.count(original), 1)
                    text = text.replace(original, replacement)
            (destination / name.replace('.js', '.mjs')).write_text(text)
        harness = destination / 'session.mjs'
        harness.write_text('''import fs from 'node:fs';
import path from 'node:path';
import { ProjectTrustStore, hasTrustRequiringProjectResources } from './pi-trust-manager.mjs';
import { approveProjectServer, applyProjectServerTrust, excludeProjectServersAtLoadTime } from './adapter-project-server-trust.mjs';
const [action, cwd, mode='rpc'] = process.argv.slice(2);
const loaded = { config: JSON.parse(fs.readFileSync(path.join(cwd, '.mcp.json'), 'utf8')), projectServers: new Map([['reviewed', {path:path.join(cwd,'.mcp.json')}]]), projectServerPolicy:'ask' };
if (action === 'approve') { approveProjectServer(cwd, 'reviewed', loaded.config.mcpServers.reviewed); }
else {
    if (Object.keys(excludeProjectServersAtLoadTime(loaded).mcpServers).length) throw Error('load-time server escaped');
    if (!hasTrustRequiringProjectResources(cwd)) throw Error('fixture must require Pi trust');
    const trusted = new ProjectTrustStore(process.env.PI_CODING_AGENT_DIR).get(cwd) === true;
    const result = await applyProjectServerTrust(loaded, {cwd, hasUI:mode==='rpc', mode, isProjectTrusted:()=>trusted, ui:{select:()=>{throw Error('headless prompt forbidden')}}});
    console.log(JSON.stringify({trusted, blocks:[...result.blockedServers].map(([name, block])=>[name,block.reason])}));
}
''')
        return harness

    def test_fresh_headless_native_admission_and_repository_worktree_approval_inheritance(self):
        harness = self.materialize_native_admission()
        repo = self.home / 'Code/reviewed-repo'
        repo.mkdir(parents=True)
        (repo / '.pi').mkdir()
        (repo / '.pi/settings.json').write_text('{}')
        definition = {'command': 'inert-never-executed', 'args': ['reviewed'], 'env': {'TOKEN': '${INERT_TEST_TOKEN}'}}
        config = {'mcpServers': {'reviewed': definition}}
        (repo / '.mcp.json').write_text(json.dumps(config))
        def git(*args):
            subprocess.run(['/usr/bin/git', '-c', 'core.hooksPath=/dev/null', '-c', 'commit.gpgsign=false',
                            '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', *map(str, args)],
                           cwd=repo, env=self.env, capture_output=True, text=True, check=True, timeout=15)
        git('init', '-q')
        git('add', '.')
        git('commit', '-qm', 'inert trust fixture')
        first = self.worktrees / 'thr_first/reviewed-repo'
        second = self.worktrees / 'thr_second/reviewed-repo'
        first.parent.mkdir(parents=True)
        second.parent.mkdir(parents=True)
        git('worktree', 'add', '--detach', first, 'HEAD')
        git('worktree', 'add', '--detach', second, 'HEAD')
        def session(action, cwd, mode='rpc'):
            result = subprocess.run([NODE, str(harness), action, str(cwd), mode], env=self.env,
                                    cwd=self.root, capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            return json.loads(result.stdout) if result.stdout else None
        self.assertEqual(session('session', first), {'trusted': False, 'blocks': [['reviewed', 'untrusted']]})
        self.expect_ok(self.policy())
        self.assertEqual(session('session', first), {'trusted': True, 'blocks': [['reviewed', 'approval-required']]})
        self.assertFalse((self.agent / 'mcp-project-approvals.json').exists(), 'Folder trust must not seed arbitrary definitions')
        session('approve', first)
        approvals = self.agent / 'mcp-project-approvals.json'
        approved = (approvals.read_bytes(), identity(approvals))
        for mode in ('print', 'json', 'rpc'):
            for cwd in (repo, first, second):
                self.assertEqual(session('session', cwd, mode), {'trusted': True, 'blocks': []})
        for field, value in [('args', ['changed']), ('command', 'changed'), ('env', {'TOKEN': 'changed'})]:
            changed = {'mcpServers': {'reviewed': {**definition, field: value}}}
            (second / '.mcp.json').write_text(json.dumps(changed))
            self.expect_ok(self.policy())
            self.assertEqual(session('session', second), {'trusted': True, 'blocks': [['reviewed', 'approval-required']]})
            self.assertEqual((approvals.read_bytes(), identity(approvals)), approved)
        (second / '.mcp.json').write_text(json.dumps(config))
        data = json.loads(self.trust.read_text())
        data[str(second)] = False
        self.seed(data)
        self.expect_ok(self.policy())
        self.assertEqual(session('session', second), {'trusted': False, 'blocks': [['reviewed', 'untrusted']]})
        impostor = self.worktrees / 'thr_impostor/repo'
        (impostor / '.pi').mkdir(parents=True)
        (impostor / '.pi/settings.json').write_text('{}')
        (impostor / '.mcp.json').write_text(json.dumps(config))
        (impostor / '.git').write_text((first / '.git').read_text())
        self.assertEqual(session('session', impostor), {'trusted': True, 'blocks': [['reviewed', 'approval-required']]})
        self.assertEqual((approvals.read_bytes(), identity(approvals)), approved)


if __name__ == '__main__':
    unittest.main()
