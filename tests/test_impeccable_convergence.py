import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

from extract_setup_fixture import definitions
from native_runtime_fixture import copy_node_runtime

ROOT = Path(__file__).resolve().parents[1]
NODE = shutil.which('node')
PWSH = os.environ.get('PWSH_BIN')
PROVIDERS = ['.claude/skills', '.agents/skills', '.cursor/skills', '.gemini/skills', '.pi/agent/skills']
REFERENCES = ['routing', 'init', 'craft', 'critique', 'layout', 'typeset', 'colorize', 'polish', 'audit',
              'audit.native', 'adapt', 'adapt.native', 'animate', 'bolder', 'clarify', 'delight', 'distill',
              'document', 'extract', 'generate', 'harden', 'onboard', 'optimize', 'quieter', 'shape',
              'visualize', 'overdrive', 'doctor', 'live', 'live-setup', 'operate', 'new-work', 'craft-floor',
              'component-review', 'region-map', 'mode-operate', 'mode-persuade', 'mode-read', 'ios', 'android', 'hooks']
SCRIPTS = ['impeccable', 'impeccable.cmd', 'VERSION', 'command-metadata.json', 'live-browser.js',
           'live-browser-session.js', 'live-browser-ignores.js', 'live-browser-dom.js', 'modern-screenshot.umd.js',
           'data/font-index.json', 'data/font-index-failures.json']
AGENTS = ['manual-edit-applier', 'asset-producer', 'documenter', 'finish-reviewer']


def native_engine():
    return b'\x7fELF\x02\x01\x01' + bytes(11) + b'\x02\x00\x3e\x00' + bytes(64)


class ImpeccableConvergence(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='impeccable-convergence-')
        self.root = Path(self.tmp.name)
        self.home = self.root / 'home'
        self.home.mkdir(mode=0o700)
        self.env = dict(os.environ)
        self.env.update(HOME=str(self.home), USERPROFILE=str(self.home), TMPDIR=str(self.root),
                        TMP=str(self.root), TEMP=str(self.root),
                        IMPECCABLE_TEST_HOME=str(self.home), IMPECCABLE_TEST_ROOT=str(self.root),
                        IMPECCABLE_TEST_MOCK=str(Path(__file__).resolve()),
                        IMPECCABLE_TEST_PYTHON=sys.executable,
                        XDG_STATE_HOME=str(self.home / 'state'), XDG_CONFIG_HOME=str(self.home / 'config'),
                        XDG_DATA_HOME=str(self.home / 'data'), XDG_CACHE_HOME=str(self.root / 'runtime-cache'))
        for key in ('CLAUDE_CONFIG_DIR', 'CODEX_HOME', 'PI_CODING_AGENT_DIR', 'BAN_IMPECCABLE',
                    'NODE_OPTIONS', 'NODE_PATH'):
            self.env.pop(key, None)
        self.put(self.home / 'user.npmrc', 'ignore-scripts=true\n')
        self.put(self.home / 'global.npmrc', 'allow-remote=false\n')
        self.env['NPM_CONFIG_USERCONFIG'] = str(self.home / 'user.npmrc')
        self.env['NPM_CONFIG_GLOBALCONFIG'] = str(self.home / 'global.npmrc')
        native = copy_node_runtime(NODE, self.root / 'native')
        commands = self.root / 'commands'
        commands.mkdir()
        boundary = self.put(self.root / 'external-boundary.cjs', r'''
const fs = require('node:fs');
const path = require('node:path');
if (process.env.IMPECCABLE_TEST_ALIAS_ROOT) {
    const root = process.env.IMPECCABLE_TEST_ALIAS_ROOT;
    const mapped = file => typeof file === 'string' && (file === '/' || file === '/home' || file.startsWith('/home/') || file === '/var' || file.startsWith('/var/')) ? path.join(root, file.slice(1)) : file;
    for (const name of ['lstatSync','readlinkSync','mkdirSync','writeFileSync','readFileSync','openSync','unlinkSync','readdirSync','rmdirSync','realpathSync']) {
        const original = fs[name];
        fs[name] = (file, ...args) => {
            const result = original(mapped(file), ...args);
            if (name === 'lstatSync' && ['/', '/home', '/var', '/var/home'].includes(file)) result.uid = process.env.IMPECCABLE_TEST_UNTRUSTED_ALIAS === file ? 1234567 : 0;
            return result;
        };
    }
    const rename = fs.renameSync;
    fs.renameSync = (from, to) => rename(mapped(from), mapped(to));
}
const {EventEmitter} = require('node:events');
const {Readable} = require('node:stream');
const crypto = require('node:crypto');
const bytes = Buffer.concat([Buffer.from([127,69,76,70,2,1,1]), Buffer.alloc(11), Buffer.from([2,0,62,0]), Buffer.alloc(64)]);
const expected = crypto.createHash('sha256').update(bytes).digest('hex');
require('node:path');
if (process.env.IMPECCABLE_TEST_ARCH) Object.defineProperty(process, 'arch', {value: process.env.IMPECCABLE_TEST_ARCH});
if (process.env.IMPECCABLE_TEST_PLATFORM === 'win32') {
    Object.defineProperty(process, 'platform', {value: 'win32'});
    require('node:child_process').spawnSync = () => ({status: 1, stdout: '', stderr: 'PRIVATE-SENTINEL native permission uncertainty'});
}
const originalRename = fs.renameSync;
let refusedRename = false;
fs.renameSync = (from, to) => {
    const mode = process.env.IMPECCABLE_TEST_MODE;
    const home = process.env.IMPECCABLE_TEST_HOME;
    const failures = {'fail-skill-promotion': home + '/.gemini/skills/impeccable',
        'fail-settings-promotion': home + '/.pi/agent/settings.json',
        'fail-inventory-promotion': home + '/.agents/.setup-impeccable.json'};
    if (!refusedRename && failures[mode] === to) {
        refusedRename = true;
        const error = new Error('PRIVATE-SENTINEL native failure'); error.code = 'EIO'; throw error;
    }
    return originalRename(from, to);
};
const originalUnlink = fs.unlinkSync;
fs.unlinkSync = file => {
    if (process.env.IMPECCABLE_TEST_MODE === 'fail-backup-cleanup' && /\.setup-impeccable-[a-f0-9-]+\.old$/.test(String(file))) {
        const error = new Error('PRIVATE-SENTINEL cleanup failure'); error.code = 'EACCES'; throw error;
    }
    return originalUnlink(file);
};
require('node:https').get = (url, options, callback) => {
    if (typeof options === 'function') callback = options;
    if (!/^https:\/\/github\.com\/pbakaus\/impeccable\/releases\/download\/engine-v0\.1\.11\/impeccable-linux-x64\.sha256$/.test(String(url))) throw new Error('UNEXPECTED_FIXTURE_FETCH');
    const request = new EventEmitter();
    request.setTimeout = () => request;
    request.destroy = error => { request.emit('error', error || new Error('fixture')); request.emit('close'); };
    process.nextTick(() => {
        const mode = process.env.IMPECCABLE_TEST_MODE;
        if (mode === 'change-live-settings') {
            fs.writeFileSync(process.env.IMPECCABLE_TEST_HOME + '/.pi/agent/settings.json', '{"skills":["concurrent-user-selection"],"theme":"concurrent"}');
        }
        if (mode === 'change-stage-after-verification') {
            const stages = fs.readFileSync(process.env.IMPECCABLE_TEST_ROOT + '/stages', 'utf8').trim().split('\n');
            fs.writeFileSync(stages.at(-1) + '/.pi/agent/skills/impeccable/scripts/bin/linux-x64/impeccable', Buffer.concat([bytes, Buffer.from('corrupt')]));
        }
        const response = Readable.from([expected + '  impeccable-linux-x64\n']);
        response.statusCode = process.env.IMPECCABLE_TEST_MODE === 'unavailable-checksum' ? 503 : 200;
        response.headers = {};
        callback(response);
        response.on('end', () => request.emit('close'));
    });
    return request;
};
''')
        shim = self.put(commands / 'node', '#!/bin/bash\nexec ' + str(native) + ' --require ' + str(boundary) + ' "$@"\n')
        shim.chmod(0o700)
        self.env['PATH'] = str(commands) + os.pathsep + self.env['PATH']

    def tearDown(self):
        self.tmp.cleanup()

    def put(self, file, data='preserved'):
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_text(data)
        return file

    def snapshot(self, directory=None):
        directory = directory or self.home
        state = {}
        def visit(file):
            info = file.lstat()
            state[str(file.relative_to(directory))] = (info.st_mode,
                os.readlink(file) if file.is_symlink() else
                hashlib.sha256(file.read_bytes()).hexdigest() if file.is_file() else None)
            if file.is_dir() and not file.is_symlink():
                for child in file.iterdir():
                    visit(child)
        visit(directory)
        return state

    def adapter(self, shell='bash', success=True, blocked=False):
        suffix = 'ps1' if shell == 'powershell' else 'bash'
        core = (ROOT / 'lib/impeccable-skill.cjs').read_text()
        wrapper = (ROOT / ('lib/impeccable-skill.' + suffix)).read_text().replace('@IMPECCABLE_CORE@', core)
        fixture = self.root / ('adapter.' + suffix)
        if shell == 'bash':
            extracted = definitions(wrapper + '\nmain() {\n    :\n}\nrun_setup_tasks() {\n    :\n}\nsetup_load_environment() {\n    :\n}\n')
            fixture.write_text('set -eu\n' + extracted + r'''
print_message() { :; }
print_success() { printf '%s\n' "$1"; }
print_warning() { printf '%s\n' "$1" >&2; }
ensure_skills_cli_node_runtime() { [[ "${IMPECCABLE_TEST_MODE:-}" != bad-runtime ]]; }
npm() {
    [[ "$1 $2" == 'config get' ]] || return 91
    [[ "${IMPECCABLE_TEST_MODE:-}" != failed-npm-config ]] || return 1
    case "$3" in
        userconfig) printf '%s\n' "${NPM_CONFIG_USERCONFIG}" ;;
        globalconfig) printf '%s\n' "${NPM_CONFIG_GLOBALCONFIG}" ;;
        *) return 91 ;;
    esac
}
npx() { "${IMPECCABLE_TEST_PYTHON}" "${IMPECCABLE_TEST_MOCK}" --installer "$@"; }
''' + f'\nPI_PROFILE_MUTATIONS_BLOCKED={int(blocked)}\nconverge_impeccable_skill\n')
            command = ['/bin/bash', '--noprofile', '--norc', str(fixture)]
        else:
            if not PWSH:
                self.skipTest('PowerShell unavailable; native Windows remains rollout work')
            source = self.root / 'source.ps1'
            source.write_text(wrapper)
            fixture.write_text("$ErrorActionPreference='Stop'\n" + r'''
$tokens=$null; $errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile($env:IMPECCABLE_TEST_SOURCE,[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw 'invalid adapter source' }
foreach ($statement in $ast.EndBlock.Statements) {
    if ($statement -isnot [System.Management.Automation.Language.FunctionDefinitionAst]) { throw 'non-definition adapter source' }
    Invoke-Expression $statement.Extent.Text
}
function Write-Message($Message) { }
function Write-Success($Message) { [Console]::WriteLine($Message) }
function Write-Warning($Message) { [Console]::Error.WriteLine($Message) }
function Enable-SkillsCliNodeRuntime { return $env:IMPECCABLE_TEST_MODE -ne 'bad-runtime' }
function npm {
    param([string]$Command, [string]$Action, [string]$Key)
    if ($Command -ne 'config' -or $Action -ne 'get' -or $Key -notin @('userconfig','globalconfig')) { throw 'unexpected npm' }
    $global:LASTEXITCODE = 0
    if ($env:IMPECCABLE_TEST_MODE -eq 'failed-npm-config') { $global:LASTEXITCODE = 1; return }
    if ($Key -eq 'userconfig') { return $env:NPM_CONFIG_USERCONFIG }
    return $env:NPM_CONFIG_GLOBALCONFIG
}
function npx {
    param([Parameter(ValueFromRemainingArguments=$true)][object[]]$Arguments)
    $env:IMPECCABLE_TEST_ARGS = ConvertTo-Json -InputObject @($Arguments) -Compress
    try { & $env:IMPECCABLE_TEST_PYTHON $env:IMPECCABLE_TEST_MOCK --installer 2> (Join-Path $env:IMPECCABLE_TEST_ROOT 'installer-errors') }
    finally { $env:IMPECCABLE_TEST_ARGS = $null }
}
''' + f'\n$script:PiProfileMutationsBlocked=${str(blocked).lower()}\n'
                                + r'''
$saved=[System.Collections.Generic.Dictionary[string,object]]::new([System.StringComparer]::Ordinal)
foreach ($key in @('HOME','USERPROFILE','CLAUDE_CONFIG_DIR','CODEX_HOME','PI_CODING_AGENT_DIR','APPDATA','LOCALAPPDATA',
    'XDG_STATE_HOME','XDG_CONFIG_HOME','XDG_DATA_HOME','XDG_CACHE_HOME','TMPDIR','TMP','TEMP',
    'NPM_CONFIG_USERCONFIG','NPM_CONFIG_GLOBALCONFIG','npm_config_userconfig','npm_config_globalconfig',
    'IMPECCABLE_HOME','IMPECCABLE_BIN','IMPECCABLE_DOWNLOAD_BASE','IMPECCABLE_BUNDLE_PATH','NODE_OPTIONS','NODE_PATH')) {
    $saved[$key]=[Environment]::GetEnvironmentVariable($key)
}
$location=(Get-Location).Path
$result=Invoke-ImpeccableConvergence
foreach ($key in $saved.Keys) {
    if ([Environment]::GetEnvironmentVariable($key) -cne $saved[$key]) { throw "Environment restoration failed: $key" }
}
if ((Get-Location).Path -cne $location) { throw 'Location restoration failed' }
if (-not $result) { exit 1 }
''')
            command = [PWSH, '-NoProfile', '-NonInteractive', '-File', str(fixture)]
            self.env['IMPECCABLE_TEST_SOURCE'] = str(source)
        result = subprocess.run(command, env=self.env, cwd=self.root, stdin=subprocess.DEVNULL,
                                text=True, capture_output=True, timeout=45)
        mock_errors = (self.root / 'installer-errors').read_text() if (self.root / 'installer-errors').exists() else ''
        self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr + mock_errors)
        self.assertNotIn('PRIVATE-SENTINEL', result.stdout + result.stderr)
        if (self.root / 'stages').exists():
            for stage in (self.root / 'stages').read_text().splitlines():
                self.assertFalse(os.path.lexists(stage), 'stage was not safely disposed')
        return result

    def test_fresh_convergence_installs_complete_pi_payload_without_hooks_or_user_state_changes(self):
        settings = self.put(self.home / '.pi/agent/settings.json', '{"theme":"keep","packages":["npm:keep"],"skills":["custom"]}')
        sentinels = [self.put(self.home / file, 'PRIVATE-SENTINEL') for file in (
            '.env.local', '.pi/agent/auth.json', '.pi/agent/models.json', '.impeccable/bin/keep',
            'project/.claude/settings.json', 'project/.agents/skills/impeccable/SKILL.md',
            '.claude/settings.json', '.cursor/hooks.json', '.codex/hooks.json', '.gemini/settings.json',
            '.agents/skills/tdd/SKILL.md')]
        result = self.adapter()
        self.assertIn('verified', result.stdout)
        for provider in PROVIDERS:
            skill = self.home / provider / 'impeccable'
            self.assertEqual((skill / 'SKILL.md').read_text(), descriptor(provider))
            for reference in REFERENCES:
                self.assertEqual((skill / ('reference/' + reference + '.md')).read_text(), 'Inert upstream reference.\n')
            for resource in SCRIPTS:
                self.assertGreater((skill / 'scripts' / resource).stat().st_size, 0)
            self.assertEqual((skill / 'scripts/bin/linux-x64/impeccable').read_bytes(), native_engine())
        self.assertEqual(json.loads(settings.read_text())['theme'], 'keep')
        self.assertEqual(json.loads(settings.read_text())['packages'], ['npm:keep'])
        self.assertIn('custom', json.loads(settings.read_text())['skills'])
        for sentinel in sentinels:
            self.assertEqual(sentinel.read_text(), 'PRIVATE-SENTINEL')
        self.assertEqual((self.home / 'user.npmrc').read_text(), 'ignore-scripts=true\n')
        self.assertEqual((self.home / 'global.npmrc').read_text(), 'allow-remote=false\n')

    def test_powershell_public_adapter_restores_user_environment_and_location_on_repeated_install(self):
        for _ in range(2):
            self.adapter('powershell')
        self.assertEqual((self.home / '.pi/agent/skills/impeccable/SKILL.md').read_text(), descriptor('.pi/agent/skills'))
        settings = json.loads((self.home / '.pi/agent/settings.json').read_text())
        self.assertEqual(settings['skills'].count('!' + str(self.home / '.agents/skills/impeccable') + '/**'), 1)

    def test_exclusion_is_offline_exact_idempotent_and_reversible_with_bounded_cleanup(self):
        selected = self.home / 'selected pi'
        self.env['PI_CODING_AGENT_DIR'] = str(selected)
        self.env['CLAUDE_CONFIG_DIR'] = str(self.home / 'selected claude')
        self.env['CODEX_HOME'] = str(self.home / 'selected codex')
        for shell in ('bash', 'powershell'):
            with self.subTest(shell=shell):
                self.env.pop('BAN_IMPECCABLE', None)
                self.env.pop('IMPECCABLE_TEST_MODE', None)
                for value in ('0', 'true', '01'):
                    self.env['BAN_IMPECCABLE'] = value
                    self.adapter(shell)
                copies = [self.home / (directory + '/impeccable') for directory in PROVIDERS]
                copies += [selected / 'skills/impeccable', self.home / 'selected claude/skills/impeccable',
                           self.home / 'selected codex/skills/impeccable', self.home / '.codex/skills/impeccable']
                for skill in copies:
                    self.put(skill / 'SKILL.md', 'previous managed copy')
                helpers = [self.put(self.home / profile / 'agents' / ('impeccable-' + agent + '.md'))
                           for profile in ('.cursor', '.claude', 'selected claude') for agent in AGENTS]
                preserved = [self.put(self.home / file, 'PRIVATE-SENTINEL') for file in (
                    '.impeccable/bin/engine-cache', 'project/.cursor/skills/impeccable/SKILL.md',
                    'project/.cursor/agents/impeccable-documenter.md', '.cursor/hooks.json',
                    '.claude/settings.json', '.pi/agent/auth.json', '.env.local', '.agents/skills/tdd/SKILL.md',
                    '.cursor/agents/unrelated.md', 'unselected-pi/skills/impeccable/SKILL.md')]
                linked_target = self.put(self.home / 'foreign/SKILL.md', 'PRIVATE-SENTINEL')
                shutil.rmtree(copies[1])
                copies[1].symlink_to(linked_target.parent, target_is_directory=True)
                self.put(selected / 'skills/impeccable.md', 'old flat copy')
                calls = (self.root / 'calls').read_bytes()
                self.env.update(BAN_IMPECCABLE='1', IMPECCABLE_TEST_MODE='bad-runtime')
                self.adapter(shell)
                before = self.snapshot()
                self.adapter(shell)
                after = self.snapshot()
                self.assertEqual(after, before, 'Changed after repeated exclusion: ' + ', '.join(key for key in set(after) | set(before) if after.get(key) != before.get(key)))
                self.assertEqual((self.root / 'calls').read_bytes(), calls)
                for skill in copies:
                    self.assertFalse(os.path.lexists(skill))
                for helper in helpers:
                    self.assertFalse(helper.exists())
                self.assertFalse((selected / 'skills/impeccable.md').exists())
                for file in preserved + [linked_target]:
                    self.assertEqual(file.read_text(), 'PRIVATE-SENTINEL')
                settings = json.loads((selected / 'settings.json').read_text())
                self.assertNotIn('!' + str(self.home / '.agents/skills/impeccable') + '/**', settings.get('skills', []))
                self.env.pop('BAN_IMPECCABLE')
                self.env.pop('IMPECCABLE_TEST_MODE')
                self.adapter(shell)
                self.assertEqual((selected / 'skills/impeccable/SKILL.md').read_text(), descriptor('.pi/agent/skills'))

    def test_intentionally_modified_native_pi_copy_is_preserved_and_never_replaced_by_an_upstream_update(self):
        self.adapter()
        copy = self.home / '.pi/agent/skills/impeccable'
        file = copy / 'reference/layout.md'
        file.write_text('Intentional user customization.\n')
        before = self.snapshot()
        calls = (self.root / 'calls').read_bytes()
        for shell in ('bash', 'powershell'):
            self.adapter(shell, success=False)
            self.assertEqual(self.snapshot(), before)
            self.assertEqual((self.root / 'calls').read_bytes(), calls)
        (self.home / '.agents/.setup-impeccable.json').unlink()
        before = self.snapshot()
        self.adapter(success=False)
        self.assertEqual(self.snapshot(), before)

    def test_runtime_installer_blocked_profile_and_payload_failures_never_accept_an_old_install(self):
        self.adapter()
        target = self.put(self.home / 'foreign/keep', 'PRIVATE-SENTINEL')
        for shell in ('bash', 'powershell'):
            for mode in ('bad-runtime', 'failed-npm-config', 'failed-command', 'missing-provider',
                         'missing-descriptor', 'empty-descriptor', 'directory-descriptor', 'linked-reference'):
                with self.subTest(shell=shell, mode=mode):
                    self.env['IMPECCABLE_TEST_MODE'] = mode
                    before = self.snapshot()
                    result = self.adapter(shell, success=False)
                    self.assertNotIn('verified', result.stdout)
                    self.assertEqual(self.snapshot(), before)
                    self.assertEqual(target.read_text(), 'PRIVATE-SENTINEL')
            self.env.pop('IMPECCABLE_TEST_MODE')
            before = self.snapshot()
            for ban in ('0', '1'):
                self.env['BAN_IMPECCABLE'] = ban
                self.adapter(shell, success=False, blocked=True)
                self.assertEqual(self.snapshot(), before)
            self.env.pop('BAN_IMPECCABLE')
            calls = (self.root / 'calls').read_bytes()
            self.env['IMPECCABLE_TEST_ARCH'] = 'arm'
            self.adapter(shell, success=False)
            self.assertEqual(self.snapshot(), before)
            self.assertEqual((self.root / 'calls').read_bytes(), calls)
            self.env.pop('IMPECCABLE_TEST_ARCH')
        self.env['IMPECCABLE_TEST_MODE'] = 'stage-leaf-link'
        self.adapter()
        self.assertEqual(target.read_text(), 'PRIVATE-SENTINEL')

    def test_work_and_native_headless_contexts_preserve_the_full_independent_managed_suite(self):
        names = json.loads((ROOT / 'tests/fixtures/matt-pocock-skills.json').read_text())['skills']
        files = [self.put(self.home / '.agents/skills' / name / 'SKILL.md', 'Matt suite sentinel') for name in names]
        files += [self.put(self.home / '.agents/.setup-matt-pocock-skills.json', json.dumps({'version': 1, 'skills': names})),
                  self.put(self.home / '.agents/.skill-lock.json', '{"version":3,"skills":{"tdd":{"source":"mattpocock/skills"}}}')]
        before = {file: file.read_bytes() for file in files}
        for work, headless in [('0', '0'), ('1', '0'), ('0', '1'), ('1', '1')]:
            self.env.update(WORK_MACHINE=work, HEADLESS=headless)
            self.adapter()
            self.assertEqual({file: file.read_bytes() for file in files}, before)
        self.env['BAN_IMPECCABLE'] = '1'
        self.adapter()
        self.assertEqual({file: file.read_bytes() for file in files}, before)

    def test_cleanup_failure_keeps_recovery_evidence_and_blocks_subsequent_installer_calls(self):
        self.adapter()
        self.env.update(IMPECCABLE_TEST_MODE='fail-backup-cleanup', IMPECCABLE_TEST_REVISION='updated snapshot')
        result = self.adapter(success=False)
        self.assertNotIn('verified', result.stdout)
        self.assertTrue((self.home / '.agents/.setup-impeccable.lock').exists())
        self.assertTrue(list((self.home / '.claude/agents').glob('.setup-impeccable-*.old')))
        calls = (self.root / 'calls').read_bytes()
        before = self.snapshot()
        self.env.pop('IMPECCABLE_TEST_MODE')
        self.adapter(success=False)
        self.assertEqual((self.root / 'calls').read_bytes(), calls)
        self.assertEqual(self.snapshot(), before)

    def test_profile_collisions_and_linked_ancestors_fail_before_installer_without_following_foreign_data(self):
        self.adapter()
        self.env['CLAUDE_CONFIG_DIR'] = str(self.home / '.cursor')
        calls = (self.root / 'calls').read_bytes()
        before = self.snapshot()
        self.adapter(success=False)
        self.assertEqual(self.snapshot(), before)
        self.assertEqual((self.root / 'calls').read_bytes(), calls)
        self.env.pop('CLAUDE_CONFIG_DIR')
        foreign = self.put(self.root / 'foreign/SKILL.md', 'PRIVATE-SENTINEL').parent
        pi = self.home / '.pi/agent'
        saved = self.home / 'preserved-pi'
        pi.rename(saved)
        pi.symlink_to(foreign, target_is_directory=True)
        before = self.snapshot()
        self.adapter(success=False)
        self.env['BAN_IMPECCABLE'] = '1'
        self.adapter(success=False)
        self.assertEqual(self.snapshot(), before)
        self.assertEqual((foreign / 'SKILL.md').read_text(), 'PRIVATE-SENTINEL')
        self.assertEqual((self.root / 'calls').read_bytes(), calls)

    def test_trusted_bazzite_home_alias_converges_without_relaxing_foreign_or_writable_system_aliases(self):
        system = self.root / 'system'
        real = system / 'var/home/account'
        real.mkdir(parents=True)
        for directory in (system, system / 'var', system / 'var/home'):
            directory.chmod(0o755)
        (system / 'home').symlink_to('var/home', target_is_directory=True)
        self.env.update(HOME='/home/account', USERPROFILE='/home/account', IMPECCABLE_TEST_HOME='/home/account',
                        IMPECCABLE_TEST_ALIAS_ROOT=str(system), NPM_CONFIG_USERCONFIG='/home/account/user.npmrc',
                        NPM_CONFIG_GLOBALCONFIG='/home/account/global.npmrc')
        self.home = real
        self.put(real / 'user.npmrc', 'ignore-scripts=true\n')
        self.put(real / 'global.npmrc', 'allow-remote=false\n')
        self.adapter()
        self.assertEqual((real / '.pi/agent/skills/impeccable/SKILL.md').read_text(), descriptor('.pi/agent/skills'))
        for logical in ('/', '/home', '/var', '/var/home'):
            self.env['IMPECCABLE_TEST_UNTRUSTED_ALIAS'] = logical
            before = self.snapshot()
            self.adapter(success=False)
            self.assertEqual(self.snapshot(), before)
        self.env.pop('IMPECCABLE_TEST_UNTRUSTED_ALIAS')
        (system / 'var/home').chmod(0o775)
        before = self.snapshot()
        self.adapter(success=False)
        self.assertEqual(self.snapshot(), before)

    def test_malformed_identity_and_ignored_pi_descriptor_cannot_establish_availability(self):
        self.adapter()
        for mode in ('duplicate-name', 'empty-description', 'oversize-description'):
            self.env['IMPECCABLE_TEST_MODE'] = mode
            before = self.snapshot()
            self.adapter(success=False)
            self.assertEqual(self.snapshot(), before)
        self.env.pop('IMPECCABLE_TEST_MODE')
        ignore = self.put(self.home / '.pi/agent/skills/.ignore', 'impeccable/\n')
        before = self.snapshot()
        calls = (self.root / 'calls').read_bytes()
        self.adapter(success=False)
        self.assertEqual(self.snapshot(), before)
        self.assertEqual((self.root / 'calls').read_bytes(), calls)
        self.assertEqual(ignore.read_text(), 'impeccable/\n')

    def test_changed_source_or_user_selection_after_verification_is_not_promoted_or_overwritten(self):
        self.adapter()
        for mode in ('change-stage-after-verification', 'change-live-settings'):
            with self.subTest(mode=mode):
                before = self.snapshot()
                self.env['IMPECCABLE_TEST_MODE'] = mode
                self.adapter(success=False)
                if mode == 'change-live-settings':
                    settings = self.home / '.pi/agent/settings.json'
                    self.assertEqual(json.loads(settings.read_text()), {'skills': ['concurrent-user-selection'], 'theme': 'concurrent'})
                    del before['.pi/agent/settings.json']
                    after = self.snapshot()
                    del after['.pi/agent/settings.json']
                    self.assertEqual(after, before)
                else:
                    self.assertEqual(self.snapshot(), before)

    def test_staging_ignores_inherited_engine_selectors_and_cannot_find_a_real_project_from_its_cwd(self):
        for key in ('IMPECCABLE_BIN', 'IMPECCABLE_BUNDLE_PATH', 'IMPECCABLE_DOWNLOAD_BASE',
                    'IMPECCABLE_SKILL_DIR', 'IMPECCABLE_SELF', 'IMPECCABLE_LAUNCHER_PROBE', 'NODE_OPTIONS', 'NODE_PATH'):
            self.env[key] = 'PRIVATE-SENTINEL'
        self.env['IMPECCABLE_TEST_REQUIRE_ISOLATION'] = '1'
        for shell in ('bash', 'powershell'):
            self.adapter(shell)

    def test_native_windows_permission_uncertainty_refuses_before_installer_and_preserves_profiles(self):
        self.put(self.home / '.pi/agent/settings.json', '{"skills":["custom"]}')
        self.env['IMPECCABLE_TEST_PLATFORM'] = 'win32'
        before = self.snapshot()
        for shell in ('bash', 'powershell'):
            self.adapter(shell, success=False)
            self.assertEqual(self.snapshot(), before)
            self.assertFalse((self.root / 'calls').exists())

    def test_unsafe_ancestors_outside_pi_profiles_and_forged_owned_metadata_refuse_before_installer(self):
        self.adapter()
        for shell in ('bash', 'powershell'):
            with self.subTest(shell=shell):
                foreign = self.root / 'outside-pi'
                self.put(foreign / 'settings.json', '{}')
                self.env['PI_CODING_AGENT_DIR'] = str(foreign)
                before = self.snapshot()
                calls = (self.root / 'calls').read_bytes()
                self.adapter(shell, success=False)
                self.assertEqual(self.snapshot(), before)
                self.assertEqual((self.root / 'calls').read_bytes(), calls)
                self.assertEqual((foreign / 'settings.json').read_text(), '{}')
                self.env.pop('PI_CODING_AGENT_DIR')
                ancestor = self.home / '.agents'
                ancestor.chmod(0o775)
                before = self.snapshot()
                self.adapter(shell, success=False)
                self.assertEqual(self.snapshot(), before)
                self.assertEqual((self.root / 'calls').read_bytes(), calls)
                ancestor.chmod(0o700)
                manifest = self.home / '.agents/.setup-impeccable.json'
                prior = manifest.read_bytes()
                self.put(manifest, json.dumps({'version': 1, 'source': 'pbakaus/impeccable',
                    'ownedExclusions': {str(self.home / '.pi/agent'): ['custom']}}))
                self.env['BAN_IMPECCABLE'] = '1'
                before = self.snapshot()
                self.adapter(shell, success=False)
                self.assertEqual(self.snapshot(), before)
                self.env.pop('BAN_IMPECCABLE')
                manifest.write_bytes(prior)

    def test_official_helper_resources_promote_with_the_same_snapshot_and_incomplete_helpers_do_not_replace_it(self):
        self.env['CLAUDE_CONFIG_DIR'] = str(self.home / 'selected claude')
        for shell in ('bash', 'powershell'):
            self.env.pop('IMPECCABLE_TEST_MODE', None)
            self.adapter(shell)
            for profile in ('selected claude', '.cursor'):
                for agent in AGENTS:
                    self.assertEqual((self.home / profile / 'agents' / ('impeccable-' + agent + '.md')).read_text(), 'Inert official helper.\n')
            before = self.snapshot()
            self.env['IMPECCABLE_TEST_MODE'] = 'missing-helper'
            self.adapter(shell, success=False)
            self.assertEqual(self.snapshot(), before)

    def test_replacement_rolls_back_every_provider_and_owned_metadata_when_any_promotion_fails(self):
        self.adapter()
        self.env['IMPECCABLE_TEST_REVISION'] = 'updated snapshot'
        for shell in ('bash', 'powershell'):
            for mode in ('fail-skill-promotion', 'fail-settings-promotion', 'fail-inventory-promotion'):
                with self.subTest(shell=shell, mode=mode):
                    if mode == 'fail-settings-promotion':
                        self.put(self.home / '.pi/agent/settings.json', '{"skills":["custom"],"theme":"keep"}')
                    self.env['IMPECCABLE_TEST_MODE'] = mode
                    before = self.snapshot()
                    result = self.adapter(shell, success=False)
                    self.assertNotIn('verified', result.stdout)
                    self.assertEqual(self.snapshot(), before)
        self.env.pop('IMPECCABLE_TEST_MODE')
        self.adapter()
        self.assertIn('updated snapshot', (self.home / '.pi/agent/skills/impeccable/SKILL.md').read_text())
        before = self.snapshot()
        self.adapter()
        self.assertEqual(self.snapshot(), before)

    def test_zero_exit_with_an_unverified_native_engine_or_malformed_required_resource_preserves_previous_payload(self):
        self.adapter()
        for shell in ('bash', 'powershell'):
            for mode in ('corrupt-engine', 'unavailable-checksum', 'invalid-resource-json', 'missing-engine', 'missing-codex-agent'):
                with self.subTest(shell=shell, mode=mode):
                    self.env['IMPECCABLE_TEST_MODE'] = mode
                    before = self.snapshot()
                    result = self.adapter(shell, success=False)
                    self.assertNotIn('verified', result.stdout)
                    self.assertEqual(self.snapshot(), before)
        self.env.pop('IMPECCABLE_TEST_MODE')

    def test_intentional_pi_overrides_are_preserved_and_never_report_disabled_or_duplicate_availability(self):
        shared = self.home / '.agents/skills/impeccable'
        direct = self.home / '.pi/agent/skills/impeccable'
        settings = self.home / '.pi/agent/settings.json'
        self.adapter()
        for shell in ('bash', 'powershell'):
            for entry in ('+' + str(shared), '-' + str(direct), '!' + str(direct) + '/**', '!impeccable'):
                with self.subTest(shell=shell, entry=entry):
                    self.put(settings, json.dumps({'skills': [entry, 'custom'], 'theme': 'keep'}))
                    before = self.snapshot()
                    calls = (self.root / 'calls').read_bytes()
                    result = self.adapter(shell, success=False)
                    self.assertNotIn('verified', result.stdout)
                    self.assertEqual(self.snapshot(), before)
                    self.assertEqual((self.root / 'calls').read_bytes(), calls)
        self.put(settings, json.dumps({'skills': ['+' + str(shared), '-' + str(shared), '+' + str(direct), 'custom']}))
        self.adapter()
        self.assertIn('-' + str(shared), json.loads(settings.read_text())['skills'])

    def test_selected_pi_profile_has_one_discovery_input_and_preserves_other_resource_selections(self):
        selected = self.home / 'selected pi'
        self.env['PI_CODING_AGENT_DIR'] = str(selected)
        self.env['CLAUDE_CONFIG_DIR'] = str(self.home / 'selected claude')
        default_copy = self.put(self.home / '.pi/agent/skills/impeccable/SKILL.md', 'customized default copy')
        custom = self.put(selected / 'settings.json', json.dumps({'skills': ['custom', '!user-exclusion/**'], 'theme': 'keep'}))
        self.adapter()
        self.assertEqual((selected / 'skills/impeccable/SKILL.md').read_text(), descriptor('.pi/agent/skills'))
        settings = json.loads(custom.read_text())
        self.assertEqual(settings['theme'], 'keep')
        self.assertEqual(settings['skills'], ['custom', '!user-exclusion/**',
            '!' + str(self.home / '.agents/skills/impeccable') + '/**'])
        self.assertEqual(default_copy.read_text(), 'customized default copy')
        self.assertTrue((self.home / 'selected claude/skills/impeccable/SKILL.md').is_file())


def descriptor(provider):
    version = 'metadata:\n  version: 4.5.0' if provider == '.agents/skills' else 'version: 4.5.0'
    return '---\nname: impeccable\ndescription: Inert official-shape fixture; never execute.\n' + version + '\n---\nProvider ' + provider + '\n'


def installer_fixture():
    args = json.loads(os.environ['IMPECCABLE_TEST_ARGS']) if os.environ.get('IMPECCABLE_TEST_ARGS') else sys.argv[2:]
    assert args == ['--yes', 'impeccable@latest', 'install', '--yes', '--scope=global',
                    '--providers=claude,codex,cursor,gemini,pi', '--no-hooks'], 'wrong-install-arguments'
    home, real = Path(os.environ['HOME']), Path(os.environ['IMPECCABLE_TEST_HOME'])
    root = Path(os.environ['IMPECCABLE_TEST_ROOT'])
    assert home != real and home.parent == root
    assert Path.cwd() == home, 'wrong-working-directory'
    assert os.environ['USERPROFILE'] == str(home)
    for key, suffix in [('CLAUDE_CONFIG_DIR', '.claude'), ('CODEX_HOME', '.codex'), ('PI_CODING_AGENT_DIR', '.pi/agent'),
                        ('XDG_STATE_HOME', '.state'), ('XDG_CONFIG_HOME', '.config'), ('XDG_CACHE_HOME', '.cache'),
                        ('XDG_DATA_HOME', '.local/share'), ('APPDATA', '.appdata'), ('LOCALAPPDATA', '.localappdata'),
                        ('IMPECCABLE_HOME', '.impeccable'), ('TMPDIR', '.tmp'), ('TMP', '.tmp'), ('TEMP', '.tmp')]:
        assert os.environ[key] == str(home / suffix), key
    for key, filename in [('userconfig', 'user.npmrc'), ('globalconfig', 'global.npmrc')]:
        assert os.environ['npm_config_' + key] == str(real / filename)
    for key in ('IMPECCABLE_BIN', 'IMPECCABLE_BUNDLE_PATH', 'IMPECCABLE_DOWNLOAD_BASE', 'IMPECCABLE_SKILL_DIR',
                'IMPECCABLE_SELF', 'IMPECCABLE_LAUNCHER_PROBE', 'NODE_OPTIONS', 'NODE_PATH'):
        assert not os.environ.get(key), key
    if os.environ.get('IMPECCABLE_TEST_REQUIRE_ISOLATION'):
        assert (home / '.git').is_dir(), 'stage-project-root-marker-missing'
    with (root / 'calls').open('a') as file:
        file.write(json.dumps(args) + '\n')
    with (root / 'stages').open('a') as file:
        file.write(str(home) + '\n')
    if os.environ.get('IMPECCABLE_TEST_MODE') == 'failed-command':
        print('PRIVATE-SENTINEL arbitrary failure output', file=sys.stderr)
        raise SystemExit(1)
    for provider in PROVIDERS:
        skill = home / provider / 'impeccable'
        skill.mkdir(parents=True)
        (skill / 'SKILL.md').write_text(descriptor(provider) + os.environ.get('IMPECCABLE_TEST_REVISION', ''))
        for reference in REFERENCES + ['degraded/manual-edit-applier', 'degraded/asset-producer', 'degraded/documenter', 'degraded/finish-reviewer']:
            file = skill / ('reference/' + reference + '.md')
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_text('Inert upstream reference.\n')
        for resource in SCRIPTS:
            file = skill / 'scripts' / resource
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_text('0.1.11\n' if resource == 'VERSION' else '{}\n' if resource.endswith('.json') else 'Inert bundled resource; never execute.\n')
        binary = skill / 'scripts/bin/linux-x64/impeccable'
        binary.parent.mkdir(parents=True)
        binary.write_bytes(native_engine())
        binary.chmod(0o700)
        (skill / 'scripts/impeccable').chmod(0o700)
        if provider == '.agents/skills':
            for name in ['openai.yaml'] + ['impeccable_' + agent.replace('-', '_') + '.toml' for agent in AGENTS]:
                file = skill / 'agents' / name
                file.parent.mkdir(exist_ok=True)
                file.write_text('Inert native agent metadata.\n')
    pi = home / '.pi/agent/skills/impeccable'
    mode = os.environ.get('IMPECCABLE_TEST_MODE', '')
    if mode == 'stage-leaf-link':
        (home / 'external-directory').symlink_to(real / 'foreign', target_is_directory=True)
    elif mode == 'missing-provider':
        shutil.rmtree(home / '.gemini/skills/impeccable')
    elif mode in ('missing-descriptor', 'empty-descriptor', 'directory-descriptor'):
        (pi / 'SKILL.md').unlink()
        if mode == 'empty-descriptor':
            (pi / 'SKILL.md').touch()
        elif mode == 'directory-descriptor':
            (pi / 'SKILL.md').mkdir()
    elif mode == 'linked-reference':
        file = pi / 'reference/layout.md'
        file.unlink()
        file.symlink_to(real / 'foreign/keep')
    elif mode == 'duplicate-name':
        (pi / 'SKILL.md').write_text(descriptor('.pi/agent/skills').replace('name: impeccable', 'name: impeccable\nname: wrong'))
    elif mode == 'empty-description':
        (pi / 'SKILL.md').write_text('---\nname: impeccable\ndescription: null\nversion: 4.5.0\n---\nInert.\n')
    elif mode == 'oversize-description':
        (pi / 'SKILL.md').write_text('---\nname: impeccable\ndescription: ' + 'x' * 1025 + '\nversion: 4.5.0\n---\nInert.\n')
    elif mode == 'corrupt-engine':
        (pi / 'scripts/bin/linux-x64/impeccable').write_bytes(native_engine() + b'corrupt')
    elif mode == 'missing-engine':
        (pi / 'scripts/bin/linux-x64/impeccable').unlink()
    elif mode == 'invalid-resource-json':
        (pi / 'scripts/command-metadata.json').write_text('PRIVATE-SENTINEL malformed JSON')
    elif mode == 'missing-codex-agent':
        (home / '.agents/skills/impeccable/agents/openai.yaml').unlink()
    for provider in ('.claude', '.cursor'):
        directory = home / provider / 'agents'
        directory.mkdir()
        for agent in AGENTS:
            (directory / ('impeccable-' + agent + '.md')).write_text('Inert official helper.\n')
    if mode == 'missing-helper':
        (home / '.cursor/agents/impeccable-documenter.md').unlink()
    print('PRIVATE-SENTINEL arbitrary installer output must not reach setup logs')


if __name__ == '__main__':
    if sys.argv[1:2] == ['--installer']:
        installer_fixture()
    else:
        unittest.main()
