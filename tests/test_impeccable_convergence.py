from functools import lru_cache
import hashlib
import json
import os
from pathlib import Path
import re
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
CAPTURED_DIRECTORIES = ['.agents', '.claude/skills', '.agents/skills', '.cursor', '.cursor/skills',
                        '.gemini', '.gemini/skills', '.pi/agent/skills', '.cursor/agents']


def directory_metadata(paths):
    return {str(file): (file.stat().st_uid, file.stat().st_gid, file.stat().st_mode) for file in paths}


@lru_cache(maxsize=6)
def fixture_definitions(source):
    return definitions(source)


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
for (const name of ['spawnSync', 'spawn', 'execSync', 'exec', 'execFileSync', 'execFile', 'fork']) {
    if (process.platform !== 'win32') require('node:child_process')[name] = () => { throw new Error('FORBIDDEN_PRIVACY_PROCESS'); };
}
process.getgroups = () => { throw new Error('FORBIDDEN_GROUP_ENUMERATION'); };
require('node:os').userInfo = () => { throw new Error('FORBIDDEN_ACCOUNT_ENUMERATION'); };
for (const name of ['readFileSync', 'openSync', 'readdirSync']) {
    const original = fs[name];
    fs[name] = (file, ...args) => {
        if (typeof file === 'string' && (/^\/etc\/(?:passwd|group|nsswitch\.conf)$/.test(file) || /^\/proc(?:\/|$)/.test(file))) throw new Error('FORBIDDEN_PRIVACY_INSPECTION');
        return original(file, ...args);
    };
}
for (const name of ['chmodSync', 'chownSync', 'lchownSync', 'fchmodSync', 'fchownSync']) {
    fs[name] = () => { throw new Error('FORBIDDEN_PERMISSION_REPAIR'); };
}
let changedMetadata = false;
const originalStat = fs.lstatSync;
fs.lstatSync = (file, ...args) => {
    const st = originalStat(file, ...args);
    if (file === process.env.IMPECCABLE_TEST_STAT_PATH) {
        Object.assign(st, JSON.parse(process.env.IMPECCABLE_TEST_STAT || '{}'));
    }
    if (changedMetadata && file === process.env.IMPECCABLE_TEST_RACE_PATH) {
        const field = process.env.IMPECCABLE_TEST_RACE_FIELD || 'gid';
        if (field === 'mode') st.mode ^= 0o005;
        else st[field] += 1;
    }
    if (process.env.IMPECCABLE_TEST_MODE === 'unsafe-stage' && process.argv[5] === 'promote' && file === process.argv[6]) st.mode |= 0o070;
    return st;
};
const originalRename = fs.renameSync;
let refusedRename = false;
fs.renameSync = (from, to) => {
    const mode = process.env.IMPECCABLE_TEST_MODE;
    const home = process.env.IMPECCABLE_TEST_HOME;
    const failures = {'fail-skill-promotion': home + '/.gemini/skills/impeccable',
        'fail-settings-promotion': home + '/.pi/agent/settings.json',
        'fail-inventory-promotion': home + '/.agents/.setup-impeccable.json'};
    if (!refusedRename && mode === 'change-parent-during-promotion' && to === home + '/.gemini/skills/impeccable') {
        refusedRename = true;
        changedMetadata = true;
        const error = new Error('PRIVATE-SENTINEL promotion failure'); error.code = 'EIO'; throw error;
    }
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
        if (mode === 'change-directory-group') changedMetadata = true;
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

    def captured_directories(self, writable=CAPTURED_DIRECTORIES):
        self.home.chmod(0o750)
        paths = [self.home, self.home / '.pi', self.home / '.pi/agent']
        for name in CAPTURED_DIRECTORIES:
            directory = self.home / name
            directory.mkdir(parents=True, exist_ok=True)
            directory.chmod(0o775 if name in writable else 0o755)
            paths.append(directory)
        for directory in paths[1:3]:
            directory.chmod(0o700)
        return paths

    def snapshot(self, directory=None):
        directory = directory or self.home
        state = {}
        def visit(file):
            info = file.lstat()
            state[str(file.relative_to(directory))] = (info.st_uid, info.st_gid, info.st_mode,
                os.readlink(file) if file.is_symlink() else
                hashlib.sha256(file.read_bytes()).hexdigest() if file.is_file() else None)
            if file.is_dir() and not file.is_symlink():
                for child in file.iterdir():
                    visit(child)
        visit(directory)
        return state

    def adapter(self, shell='bash', success=True, blocked=False, entry=None, combined=False,
                creation_mask=None, stage_retained=False):
        suffix = 'ps1' if shell == 'powershell' else 'bash'
        core = (ROOT / 'lib/impeccable-skill.cjs').read_text()
        wrapper = (ROOT / entry).read_text() if entry else (ROOT / ('lib/impeccable-skill.' + suffix)).read_text().replace('@IMPECCABLE_CORE@', core)
        fixture = self.root / ('adapter.' + suffix)
        if shell == 'bash':
            extracted = fixture_definitions(wrapper if entry else wrapper + '\nmain() {\n    :\n}\nrun_setup_tasks() {\n    :\n}\nsetup_load_environment() {\n    :\n}\n')
            mocks = ''
            if entry:
                retained = {'impeccable_skill_policy', 'converge_impeccable_skill', 'main', 'run_setup_tasks',
                            'setup_load_environment', 'setup_environment_failure', 'setup_trim', 'setup_environment_value',
                            'fail_unsupported_headless', 'env_local_flag_is_one'}
                if combined:
                    retained.update(('retire_global_backlog_mcp', 'prepare_pi_profile_permissions', 'remove_pi_prose'))
                names = set(re.findall(r'^(\w+)\(\)', extracted, re.M))
                mocks = '\n'.join(f'{name}() {{ :; }}' for name in names - retained) + r'''
record() { printf '%s\n' "$1" >> "$IMPECCABLE_TEST_ROOT/events"; }
whoami() { printf 'fixture\n'; }
create_env_local() { record environment-template; }
brew() { :; }
is_main_user() { return 0; }
check_dotfiles_access() { return 1; }
setup_dotfiles_deploy_key() { return 1; }
bb_server_selection() { return 1; }
prepare_pi_profile_permissions() { record permissions; [[ "${IMPECCABLE_TEST_BLOCKED:-0}" != 1 ]]; }
setup_matt_pocock_skills() { record matt; [[ "${IMPECCABLE_TEST_EARLIER_FAILURE:-0}" != 1 ]]; }
remove_rtk_resources() { record rtk; }
remove_attention_span_resources() { record attention; }
remove_simple_english_skill() { record simple-english; }
remove_show_me_skill() { record show-me; }
remove_pr_lens_skill() { record pr-lens; }
configure_pi_opencode_go() { [[ "${IMPECCABLE_TEST_LATE_BLOCK:-0}" != 1 ]]; }
remove_compound_engineering_resources() { record independent; }
check_pending_reboot() { record reboot; }
start_setup_log() { record log-start; }
finish_setup_log() { record "final:$1"; return "$1"; }
'''
                if combined:
                    mocks = re.sub(r'^prepare_pi_profile_permissions\(\).*\n', '', mocks, flags=re.M)
                for command_name in ('curl', 'npm', 'npx', 'pi', 'bb', 'chezmoi', 'sudo', 'systemctl', 'launchctl', 'kill', 'pkill', 'tmux'):
                    mocks += f'\n{command_name}() {{ record FORBIDDEN:{command_name}; return 99; }}'
            invocation = '\nmain\n' if entry else f'\nPI_PROFILE_MUTATIONS_BLOCKED={int(blocked)}\nconverge_impeccable_skill\n'
            if creation_mask is not None:
                invocation = f'\numask {creation_mask:03o}\n_fixture_mask=$(umask)\n_fixture_status=0\n' + invocation.rstrip() + r''' || _fixture_status=$?
if [[ "$(umask)" != "${_fixture_mask}" ]]; then
    printf 'Fixture caller creation mask changed\n' >&2
    exit 98
fi
exit "${_fixture_status}"
'''
            fixture.write_text(('set -e\n' if entry else 'set -eu\n') + extracted + '\n' + mocks + '\n' + r'''
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
''' + invocation)
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
$retained=@('Invoke-ImpeccableSkillPolicy','Invoke-ImpeccableConvergence','Read-SetupEnvironment',
    'ConvertFrom-SetupEnvironmentValue','Assert-HeadlessUnsupported','Test-EnvLocalFlag',
    'Invoke-WindowsSetupTasks','Initialize-WindowsEnvironment')
foreach ($statement in $ast.EndBlock.Statements) {
    if ($statement -is [System.Management.Automation.Language.FunctionDefinitionAst]) {
        if ($env:IMPECCABLE_TEST_ENTRY -and $statement.Name -notin $retained) {
            Set-Item -Path ('function:' + $statement.Name) -Value { $true }
        } else { . ([scriptblock]::Create($statement.Extent.Text)) }
    } elseif (-not $env:IMPECCABLE_TEST_ENTRY) { throw 'non-definition adapter source' }
}
if ($env:IMPECCABLE_TEST_ENTRY) {
    function Record($Message) { Add-Content (Join-Path $env:IMPECCABLE_TEST_ROOT events) $Message }
    function Write-Host { }
    function Write-Debug { }
    function Write-Section { }
    function Get-SetupLogDirectory { Join-Path $env:IMPECCABLE_TEST_ROOT logs }
    function Assert-SetupLogPath { param($Path,[switch]$AllowMissing) }
    function Invoke-PendingSetupLogUploads { }
    function Start-Transcript { param($Path,[switch]$NoClobber,$ErrorAction) }
    function Complete-SetupLog { Record finalized }
    function New-TokenPlaceholders { Record environment-template }
    function Prepare-PiProfilePermissions { Record permissions; return $env:IMPECCABLE_TEST_BLOCKED -ne '1' }
    function Setup-MattPocockSkills { Record matt; return $env:IMPECCABLE_TEST_EARLIER_FAILURE -ne '1' }
    function Remove-RtkResources { Record rtk }
    function Remove-AttentionSpanResources { Record attention }
    function Remove-SimpleEnglishSkill { Record simple-english; return $true }
    function Remove-ShowMeSkill { Record show-me; return $true }
    function Remove-PrLensSkill { Record pr-lens; return $true }
    function Set-PiOpenCodeGoProvider { return $env:IMPECCABLE_TEST_LATE_BLOCK -ne '1' }
    function Remove-CompoundEngineeringResources { Record independent }
    function Test-PendingReboot { Record reboot }
    foreach ($name in @('curl','pi','bb','chezmoi','sudo','systemctl','launchctl','Stop-Process','Invoke-RestMethod','Invoke-WebRequest')) {
        Set-Item -Path ('function:' + $name) -Value { throw 'unexpected external operation' }
    }
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
$result=$false
if ($env:IMPECCABLE_TEST_ENTRY) {
    try { Initialize-WindowsEnvironment; $result=$true }
    catch { [Console]::Error.WriteLine($_.Exception.Message) }
} else {
    $result=Invoke-ImpeccableConvergence
    if ($result -isnot [bool]) { throw 'Convergence success stream is not one Boolean' }
}
foreach ($key in $saved.Keys) {
    if ([Environment]::GetEnvironmentVariable($key) -cne $saved[$key]) { throw "Environment restoration failed: $key" }
}
if ((Get-Location).Path -cne $location) { throw 'Location restoration failed' }
if (-not $result) { exit 1 }
''')
            command = [PWSH, '-NoProfile', '-NonInteractive', '-File', str(fixture)]
            self.env['IMPECCABLE_TEST_SOURCE'] = str(source)
            self.env['IMPECCABLE_TEST_ENTRY'] = entry or ''
        result = subprocess.run(command, env=self.env, cwd=self.root, stdin=subprocess.DEVNULL,
                                text=True, capture_output=True, timeout=45)
        mock_errors = (self.root / 'installer-errors').read_text() if (self.root / 'installer-errors').exists() else ''
        if creation_mask is not None:
            self.assertNotIn('Fixture caller creation mask changed', result.stderr)
        self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr + mock_errors)
        self.assertNotIn('PRIVATE-SENTINEL', result.stdout + result.stderr)
        if (self.root / 'stages').exists():
            for stage in (self.root / 'stages').read_text().splitlines():
                self.assertEqual(os.path.lexists(stage), stage_retained, 'unexpected stage disposition')
        return result

    def test_inherited_002_mask_converges_without_changing_caller_or_existing_directories(self):
        paths = self.captured_directories()
        before = directory_metadata(paths)
        sentinel = self.put(self.home / '.agents/skills/tdd/SKILL.md', 'independent managed skill')
        result = self.adapter(creation_mask=0o002)
        self.assertIn('verified', result.stdout)
        self.assertNotIn('unsafe-owner-or-mode', result.stderr)
        for provider in PROVIDERS:
            skill = self.home / provider / 'impeccable'
            self.assertEqual((skill / 'SKILL.md').read_text(), descriptor(provider))
            self.assertEqual((skill / 'SKILL.md').stat().st_mode & 0o777, 0o600)
            self.assertEqual((skill / 'reference').stat().st_mode & 0o777, 0o700)
        self.assertEqual(directory_metadata(paths), before)
        self.assertEqual(sentinel.read_text(), 'independent managed skill')

    def test_inherited_002_mask_still_refuses_unsafe_existing_files_without_repair(self):
        self.captured_directories()
        settings = self.put(self.home / '.pi/agent/settings.json', '{}')
        settings.chmod(0o664)
        before = self.snapshot()
        result = self.adapter(creation_mask=0o002, success=False)
        self.assertIn('Impeccable: unsafe-owner-or-mode.', result.stderr)
        self.assertEqual(self.snapshot(), before)
        self.assertFalse((self.root / 'calls').exists())

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

    def test_each_captured_directory_and_combined_layout_install_update_repeat_exclude_and_reinstall(self):
        for writable in [[name] for name in CAPTURED_DIRECTORIES] + [CAPTURED_DIRECTORIES]:
            with self.subTest(writable=writable):
                paths = self.captured_directories(writable)
                before = directory_metadata(paths)
                unrelated = self.put(self.home / '.agents/skills/tdd/SKILL.md', 'independent Matt suite')
                for revision in ('initial', 'updated', 'updated'):
                    self.env['IMPECCABLE_TEST_REVISION'] = revision
                    result = self.adapter()
                    self.assertIn('verified', result.stdout)
                    for provider in PROVIDERS:
                        self.assertEqual((self.home / provider / 'impeccable/SKILL.md').read_text(), descriptor(provider) + revision)
                    self.assertEqual(directory_metadata(paths), before)
                calls = (self.root / 'calls').read_bytes()
                self.env.update(BAN_IMPECCABLE='1', IMPECCABLE_TEST_MODE='bad-runtime')
                for _ in range(2):
                    self.adapter()
                    self.assertEqual(directory_metadata(paths), before)
                    self.assertEqual((self.root / 'calls').read_bytes(), calls)
                    for provider in PROVIDERS:
                        self.assertFalse((self.home / provider / 'impeccable').exists())
                self.env.pop('BAN_IMPECCABLE')
                self.env.pop('IMPECCABLE_TEST_MODE')
                self.adapter()
                self.assertEqual(directory_metadata(paths), before)
                self.assertEqual(unrelated.read_text(), 'independent Matt suite')
                self.env['BAN_IMPECCABLE'] = '1'
                self.adapter()
                self.env.pop('BAN_IMPECCABLE')

    def test_readable_private_group_writable_and_setgid_containers_keep_metadata_at_selected_destinations(self):
        paths = self.captured_directories()
        selected = self.home / 'profiles/shared/pi'
        claude = self.root / 'selected claude'
        codex = self.home / 'profiles/codex'
        self.env.update(PI_CODING_AGENT_DIR=str(selected), CLAUDE_CONFIG_DIR=str(claude), CODEX_HOME=str(codex))
        containers = [self.home, self.home / 'profiles', selected.parent, selected / 'skills',
                      claude, claude / 'skills', claude / 'agents', codex, codex / 'skills',
                      self.home / '.codex', self.home / '.codex/skills']
        for directory in containers:
            directory.mkdir(parents=True, exist_ok=True)
        selected.chmod(0o700)
        settings = self.put(selected / 'settings.json', '{"skills":["custom"],"theme":"keep"}')
        for permissions in (0o700, 0o755, 0o775, 0o2775):
            with self.subTest(mode=oct(permissions)):
                for directory in containers:
                    directory.chmod(permissions)
                before = directory_metadata(paths + containers + [selected])
                for shell in ('bash', 'powershell'):
                    self.adapter(shell)
                    self.assertEqual((selected / 'skills/impeccable/SKILL.md').read_text(), descriptor('.pi/agent/skills'))
                    self.assertEqual((claude / 'skills/impeccable/SKILL.md').read_text(), descriptor('.claude/skills'))
                    self.assertEqual(json.loads(settings.read_text())['skills'], ['custom', '!' + str(self.home / '.agents/skills/impeccable') + '/**'])
                    self.assertEqual(directory_metadata(paths + containers + [selected]), before)
                    for tree in (selected / 'skills/impeccable', claude / 'skills/impeccable',
                                 codex / 'skills/impeccable', self.home / '.codex/skills/impeccable'):
                        tree.mkdir(exist_ok=True)
                        tree.chmod(permissions)
                    self.env['BAN_IMPECCABLE'] = '1'
                    calls = (self.root / 'calls').read_bytes()
                    self.adapter(shell)
                    self.assertEqual((self.root / 'calls').read_bytes(), calls)
                    self.assertEqual(directory_metadata(paths + containers + [selected]), before)
                    self.assertEqual(json.loads(settings.read_text()), {'skills': ['custom'], 'theme': 'keep'})
                    self.env.pop('BAN_IMPECCABLE')

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

    def test_malformed_metadata_in_an_otherwise_complete_snapshot_never_replaces_working_artifacts(self):
        self.adapter()
        self.env.update(IMPECCABLE_TEST_MODE='malformed-frontmatter', IMPECCABLE_TEST_REVISION='replacement must not be promoted')
        before = self.snapshot()
        for shell in ('bash', 'powershell'):
            with self.subTest(shell=shell):
                result = self.adapter(shell, success=False)
                self.assertNotIn('verified', result.stdout)
                self.assertEqual(self.snapshot(), before)

    def test_official_five_provider_frontmatter_is_verified_and_preserved_byte_for_byte(self):
        frontmatter = json.loads((ROOT / 'tests/fixtures/impeccable-frontmatter.json').read_text())['frontmatter']
        descriptors = {provider: header + '\nInert official-shape payload; never execute.\n' for provider, header in frontmatter.items()}
        self.env['IMPECCABLE_TEST_DESCRIPTORS'] = json.dumps(descriptors)
        for shell in ('bash', 'powershell'):
            self.adapter(shell)
            for provider, text in descriptors.items():
                self.assertEqual((self.home / provider / 'impeccable/SKILL.md').read_bytes(), text.encode())

    def test_malformed_unknown_fields_and_unsupported_yaml_never_establish_verified_availability(self):
        self.adapter()
        cases = [
            ('.agents/skills', '  broken: [\n'),
            ('.claude/skills', 'future: [unfinished\n'),
            ('.cursor/skills', 'future: "unfinished\n'),
            ('.gemini/skills', 'future: a: b\n'),
            ('.gemini/skills', 'future: value:\n'),
            ('.agents/skills', '  broken: value:\n'),
            ('.pi/agent/skills', 'metadata:\n  build: first\n  build: second\n'),
            ('.pi/agent/skills', 'future:\n  broken: [\n'),
            ('.pi/agent/skills', 'allowed-tools:\n  - [unfinished\n'),
            ('.claude/skills', "future: 'one'junk'\n"),
            ('.pi/agent/skills', 'future: [valid, but, unsupported]\n'),
            ('.pi/agent/skills', 'future: |\n  valid but unsupported\n'),
            ('.pi/agent/skills', 'future: &anchor value\nnext: *anchor\n'),
        ]
        for provider, extra in cases:
            with self.subTest(provider=provider, extra=extra):
                text = descriptor(provider).replace('\n---\n', '\n' + extra + '---\n')
                self.env['IMPECCABLE_TEST_DESCRIPTORS'] = json.dumps({provider: text})
                before = self.snapshot()
                result = self.adapter(success=False)
                self.assertNotIn('verified', result.stdout)
                self.assertEqual(self.snapshot(), before)
        for value in ('.5', '+.inf', '0xdead', 'true'):
            with self.subTest(description=value):
                self.env['IMPECCABLE_TEST_DESCRIPTORS'] = json.dumps({'.pi/agent/skills':
                    '---\nname: impeccable\ndescription: ' + value + '\nversion: 4.5.0\n---\nInert.\n'})
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

    def test_file_negation_cannot_reopen_an_ignored_pi_skill_directory_or_replace_prior_payload(self):
        for profile in (self.home / '.pi/agent', self.home / 'selected pi'):
            self.env['PI_CODING_AGENT_DIR'] = str(profile)
            self.adapter()
            ignore = self.put(profile / 'skills/.ignore', 'impeccable/\n!impeccable/SKILL.md\n')
            before = self.snapshot()
            calls = (self.root / 'calls').read_bytes()
            for shell in ('bash', 'powershell'):
                with self.subTest(profile=profile.name, shell=shell):
                    result = self.adapter(shell, success=False)
                    self.assertNotIn('verified', result.stdout)
                    self.assertEqual(self.snapshot(), before)
                    self.assertEqual((self.root / 'calls').read_bytes(), calls)
                    self.assertEqual(ignore.read_text(), 'impeccable/\n!impeccable/SKILL.md\n')

    def test_native_ignore_trailing_tabs_remain_literal_while_trailing_spaces_are_ignored(self):
        cases = [
            ('impeccable/\n!impeccable/\t\n', False),
            ('impeccable/\n!impeccable/ \t\n', False),
            ('impeccable/\n!impeccable/\t \n', False),
            ('impeccable/\n!impeccable/   \n', True),
            ('impeccable/\t\n', True),
            ('impeccable/SKILL.md\t\n', True),
            ('impeccable/   \n', False),
        ]
        for profile in (self.home / '.pi/agent', self.home / 'selected pi'):
            self.env['PI_CODING_AGENT_DIR'] = str(profile)
            self.adapter()
            for text, success in cases:
                ignore = self.put(profile / 'skills/.ignore', text)
                for shell in ('bash', 'powershell'):
                    with self.subTest(profile=profile.name, text=text, shell=shell):
                        before = self.snapshot()
                        calls = (self.root / 'calls').read_bytes()
                        result = self.adapter(shell, success=success)
                        self.assertEqual(ignore.read_bytes(), text.encode())
                        if success:
                            self.assertIn('verified', result.stdout)
                            self.assertEqual((profile / 'skills/impeccable/SKILL.md').read_text(), descriptor('.pi/agent/skills'))
                        else:
                            self.assertNotIn('verified', result.stdout)
                            self.assertEqual(self.snapshot(), before)
                            self.assertEqual((self.root / 'calls').read_bytes(), calls)

    def test_pi_ignore_rules_respect_native_scoping_directory_types_globs_and_ordered_parent_negation(self):
        cases = [
            ({'.ignore': 'impeccable/\n!impeccable/\n'}, True),
            ({'.gitignore': 'impeccable/\n', '.ignore': '!impeccable/\n'}, True),
            ({'.ignore': 'impeccable/\n!impeccable/\n', '.fdignore': 'impeccable/SKILL.md\n'}, False),
            ({'.ignore': '/impeccable/\n!/impeccable/SKILL.md\n'}, False),
            ({'.ignore': '*\n!impeccable/\n!impeccable/SKILL.md\n'}, True),
            ({'.ignore': '**/impeccable/\n!**/SKILL.md\n'}, False),
            ({'.ignore': 'impeccable/**\n!impeccable/SKILL.md\n'}, True),
            ({'.ignore': 'impeccable/SKILL.md\n!impeccable/\n'}, False),
            ({'.ignore': '/SKILL.md\n'}, False),
            ({'.ignore': 'SKILL.md/\n'}, True),
            ({'.fdignore': 'IMPECCABLE/\n'}, False),
            ({'.gitignore': '*/SKILL.md\n'}, False),
        ]
        for profile in (self.home / '.pi/agent', self.home / 'selected pi'):
            self.env['PI_CODING_AGENT_DIR'] = str(profile)
            self.adapter()
            for policies, success in cases:
                with self.subTest(profile=profile.name, policies=policies):
                    for name in ('.gitignore', '.ignore', '.fdignore'):
                        (profile / 'skills' / name).unlink(missing_ok=True)
                    files = [self.put(profile / 'skills' / name, text) for name, text in policies.items()]
                    before = self.snapshot()
                    calls = (self.root / 'calls').read_bytes()
                    result = self.adapter(success=success)
                    if success:
                        self.assertIn('verified', result.stdout)
                        self.assertEqual((profile / 'skills/impeccable/SKILL.md').read_text(), descriptor('.pi/agent/skills'))
                    else:
                        self.assertNotIn('verified', result.stdout)
                        self.assertEqual(self.snapshot(), before)
                        self.assertEqual((self.root / 'calls').read_bytes(), calls)
                    self.assertEqual({file.name: file.read_text() for file in files}, policies)

    def test_nested_pi_ignore_files_use_native_root_relative_prefixes_and_cannot_reopen_parents(self):
        self.adapter()
        cases = [
            ({'.ignore': 'SKILL.md\n!SKILL.md\n'}, '', True),
            ({'.gitignore': 'SKILL.md\n', '.ignore': '!SKILL.md\n'}, '', True),
            ({'.ignore': '!/SKILL.md\n'}, 'impeccable/SKILL.md\n', True),
            ({'.ignore': '/SKILL.md\n'}, '', False),
            ({'.fdignore': '*.md\n'}, '', False),
            ({'.ignore': 'impeccable/\n'}, '', True),
            ({'.ignore': '!SKILL.md\n'}, 'impeccable/\n', False),
        ]
        root_ignore = self.home / '.pi/agent/skills/.ignore'
        for policies, ancestor, success in cases:
            with self.subTest(policies=policies, ancestor=ancestor):
                self.put(root_ignore, ancestor)
                self.env['IMPECCABLE_TEST_PI_IGNORES'] = json.dumps(policies)
                before = self.snapshot()
                result = self.adapter(success=success)
                if success:
                    self.assertIn('verified', result.stdout)
                    skill = self.home / '.pi/agent/skills/impeccable'
                    self.assertEqual({name: (skill / name).read_text() for name in policies}, policies)
                else:
                    self.assertNotIn('verified', result.stdout)
                    self.assertEqual(self.snapshot(), before)
                self.assertEqual(root_ignore.read_text(), ancestor)

    def test_native_pi_root_descriptor_prevents_traversal_until_that_descriptor_is_ignored(self):
        self.adapter()
        root_descriptor = self.put(self.home / '.pi/agent/skills/SKILL.md', 'Unrelated root descriptor; never execute.\n')
        before = self.snapshot()
        calls = (self.root / 'calls').read_bytes()
        result = self.adapter(success=False)
        self.assertNotIn('verified', result.stdout)
        self.assertEqual(self.snapshot(), before)
        self.assertEqual((self.root / 'calls').read_bytes(), calls)
        ignore = self.put(root_descriptor.parent / '.ignore', '/SKILL.md\n!impeccable/SKILL.md\n')
        self.adapter()
        self.assertEqual(root_descriptor.read_text(), 'Unrelated root descriptor; never execute.\n')
        self.assertEqual(ignore.read_text(), '/SKILL.md\n!impeccable/SKILL.md\n')

    def test_accepted_metadata_changes_in_destinations_and_ancestors_invalidate_snapshots_before_promotion(self):
        self.captured_directories()
        self.adapter()
        nested = self.home / '.pi/agent/skills/impeccable/reference'
        nested.chmod(0o775)
        for target, reason in ((nested, 'changed-copy'), (self.home / '.agents', 'changed-directory')):
            for field in ('gid', 'mode', 'ino', 'uid'):
                with self.subTest(target=target.name, field=field):
                    self.env.update(IMPECCABLE_TEST_MODE='change-directory-group', IMPECCABLE_TEST_RACE_PATH=str(target),
                                    IMPECCABLE_TEST_RACE_FIELD=field)
                    before = self.snapshot()
                    result = self.adapter(success=False)
                    self.assertIn('Impeccable: ' + ('unsafe-owner-or-mode' if field == 'uid' else reason) + '.', result.stderr)
                    self.assertEqual(self.snapshot(), before)
                    self.assertFalse((self.home / '.agents/.setup-impeccable.lock').exists())

    def test_accepted_parent_changes_during_failed_promotion_retain_private_recovery_evidence(self):
        self.captured_directories()
        self.adapter()
        prior = (self.home / '.claude/skills/impeccable/SKILL.md').read_bytes()
        self.env.update(IMPECCABLE_TEST_MODE='change-parent-during-promotion',
                        IMPECCABLE_TEST_REVISION='new payload', IMPECCABLE_TEST_RACE_PATH=str(self.home / '.agents'),
                        IMPECCABLE_TEST_RACE_FIELD='mode')
        result = self.adapter(success=False)
        self.assertIn('Impeccable: recovery-required.', result.stderr)
        lock = self.home / '.agents/.setup-impeccable.lock'
        self.assertEqual(lock.stat().st_mode & 0o777, 0o600)
        backups = list((self.home / '.claude/skills').glob('.setup-impeccable-*.old'))
        self.assertEqual(len(backups), 1)
        self.assertEqual((backups[0] / 'SKILL.md').read_bytes(), prior)
        self.assertEqual(backups[0].stat().st_mode & 0o777, 0o700)
        self.assertFalse(list(self.home.rglob('.setup-impeccable-*.new')))
        self.env.pop('IMPECCABLE_TEST_MODE')
        before = self.snapshot()
        calls = (self.root / 'calls').read_bytes()
        self.adapter(success=False)
        self.assertEqual(self.snapshot(), before)
        self.assertEqual((self.root / 'calls').read_bytes(), calls)

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

    def test_private_pi_boundaries_still_refuse_group_write_with_ordinary_ancestors_accepted(self):
        self.captured_directories()
        selected = self.home / 'shared profiles/selected pi'
        selected.mkdir(parents=True)
        selected.parent.chmod(0o775)
        self.env['PI_CODING_AGENT_DIR'] = str(selected)
        self.adapter()
        for boundary in (self.home / '.pi', self.home / '.pi/agent', selected):
            boundary.chmod(0o775)
            for flag in ('0', '1'):
                with self.subTest(boundary=boundary.name, excluded=flag):
                    self.env['BAN_IMPECCABLE'] = flag
                    before = self.snapshot()
                    calls = (self.root / 'calls').read_bytes()
                    result = self.adapter(success=False)
                    self.assertIn('Impeccable: unsafe-owner-or-mode.', result.stderr)
                    self.assertEqual(self.snapshot(), before)
                    self.assertEqual((self.root / 'calls').read_bytes(), calls)
            boundary.chmod(0o700)
        self.env.pop('BAN_IMPECCABLE')

    def test_ordinary_group_access_does_not_weaken_files_world_write_ownership_or_stage_privacy(self):
        self.captured_directories()
        self.adapter()
        for relative, permissions in (('.agents', 0o777), ('.pi/agent/skills/impeccable/reference', 0o777),
                                      ('.pi/agent/settings.json', 0o660), ('.agents/.setup-impeccable.json', 0o660),
                                      ('.pi/agent/skills/impeccable/SKILL.md', 0o660)):
            file = self.home / relative
            original = file.stat().st_mode & 0o7777
            file.chmod(permissions)
            for flag in ('0', '1'):
                with self.subTest(path=relative, excluded=flag):
                    self.env['BAN_IMPECCABLE'] = flag
                    before = self.snapshot()
                    calls = (self.root / 'calls').read_bytes()
                    result = self.adapter(success=False)
                    self.assertIn('Impeccable: unsafe-owner-or-mode.', result.stderr)
                    self.assertEqual(self.snapshot(), before)
                    self.assertEqual((self.root / 'calls').read_bytes(), calls)
            file.chmod(original)
        self.env.pop('BAN_IMPECCABLE')
        for owner in (0, os.getuid() + 12345):
            self.env.update(IMPECCABLE_TEST_STAT_PATH=str(self.home / '.agents'), IMPECCABLE_TEST_STAT=json.dumps({'uid': owner}))
            before = self.snapshot()
            calls = (self.root / 'calls').read_bytes()
            self.adapter(success=False)
            self.assertEqual(self.snapshot(), before)
            self.assertEqual((self.root / 'calls').read_bytes(), calls)
        self.env.pop('IMPECCABLE_TEST_STAT_PATH')
        self.env.pop('IMPECCABLE_TEST_STAT')
        self.env['IMPECCABLE_TEST_MODE'] = 'unsafe-stage'
        before = self.snapshot()
        result = self.adapter(success=False)
        self.assertIn('Impeccable: unsafe-stage.', result.stderr)
        self.assertEqual(self.snapshot(), before)

    def test_root_system_boundary_stays_strict_but_account_ancestors_need_no_private_ancestor(self):
        self.captured_directories()
        selected = self.root / 'system-parent/selected claude'
        selected.mkdir(parents=True)
        self.env.update(CLAUDE_CONFIG_DIR=str(selected), IMPECCABLE_TEST_STAT_PATH=str(selected.parent),
                        IMPECCABLE_TEST_STAT=json.dumps({'uid': 0, 'mode': 0o40755}))
        self.adapter()
        self.env['IMPECCABLE_TEST_STAT'] = json.dumps({'uid': 0, 'mode': 0o40775})
        before = self.snapshot()
        calls = (self.root / 'calls').read_bytes()
        result = self.adapter(success=False)
        self.assertIn('Impeccable: unsafe-owner-or-mode.', result.stderr)
        self.assertEqual(self.snapshot(), before)
        self.assertEqual((self.root / 'calls').read_bytes(), calls)
        self.home.chmod(0o775)
        self.env.update(IMPECCABLE_TEST_STAT_PATH=str(self.root),
                        IMPECCABLE_TEST_STAT=json.dumps({'mode': 0o40775, 'gid': os.getgid() + 1}))
        self.adapter()
        self.assertEqual(self.home.stat().st_mode & 0o777, 0o775)

    def test_wrong_type_dangling_ancestor_and_hardlinked_metadata_refuse_without_installer_or_cleanup(self):
        self.captured_directories()
        self.adapter()
        directory = self.home / '.cursor/skills'
        saved = self.root / 'saved-skills'
        directory.rename(saved)
        calls = (self.root / 'calls').read_bytes()
        for linked in (False, True):
            if linked:
                directory.symlink_to(self.root / 'missing', target_is_directory=True)
            else:
                directory.write_text('not a directory')
            for flag in ('0', '1'):
                self.env['BAN_IMPECCABLE'] = flag
                before = self.snapshot()
                self.adapter(success=False)
                self.assertEqual(self.snapshot(), before)
                self.assertEqual((self.root / 'calls').read_bytes(), calls)
            directory.unlink()
        saved.rename(directory)
        settings = self.home / '.pi/agent/settings.json'
        os.link(settings, self.root / 'hardlinked-settings')
        for flag in ('0', '1'):
            self.env['BAN_IMPECCABLE'] = flag
            before = self.snapshot()
            result = self.adapter(success=False)
            self.assertIn('Impeccable: unsafe-metadata.', result.stderr)
            self.assertEqual(self.snapshot(), before)
            self.assertEqual((self.root / 'calls').read_bytes(), calls)

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
                ancestor.chmod(0o777)
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

    def test_source_relative_force_includes_preserve_user_choices_and_refuse_duplicate_pi_discovery(self):
        self.adapter()
        for profile in (self.home / '.pi/agent', self.home / 'selected pi'):
            self.env['PI_CODING_AGENT_DIR'] = str(profile)
            settings = profile / 'settings.json'
            for entry in ('+skills/impeccable', '+./skills/impeccable', '+skills/impeccable/SKILL.md'):
                for shell in ('bash', 'powershell'):
                    with self.subTest(profile=profile.name, entry=entry, shell=shell):
                        self.put(settings, json.dumps({'skills': [entry, 'custom'], 'theme': 'keep'}))
                        before = self.snapshot()
                        calls = (self.root / 'calls').read_bytes()
                        result = self.adapter(shell, success=False)
                        self.assertNotIn('verified', result.stdout)
                        self.assertEqual(self.snapshot(), before)
                        self.assertEqual((self.root / 'calls').read_bytes(), calls)

    def test_native_pi_terminal_globstar_requires_a_suffix_but_middle_globstar_can_match_zero_directories(self):
        cases = [
            ('!impeccable/**', True),
            ('!impeccable/**/**', True),
            ('!impeccable/**/SKILL.md', True),
            ('!skills/**/impeccable', False),
            ('!**/impeccable', False),
            ('!skills/impeccable/**', False),
            ('!skills/**/impeccable/**', False),
        ]
        self.adapter()
        for profile in (self.home / '.pi/agent', self.home / 'selected pi'):
            self.env['PI_CODING_AGENT_DIR'] = str(profile)
            settings = profile / 'settings.json'
            for entry, success in cases:
                self.put(settings, json.dumps({'skills': [entry, 'custom'], 'theme': 'keep'}))
                for shell in ('bash', 'powershell'):
                    with self.subTest(profile=profile.name, entry=entry, shell=shell):
                        before = self.snapshot()
                        calls = (self.root / 'calls').read_bytes()
                        result = self.adapter(shell, success=success)
                        if success:
                            self.assertIn('verified', result.stdout)
                            self.assertEqual(json.loads(settings.read_text()), {'skills': [entry, 'custom',
                                '!' + str(self.home / '.agents/skills/impeccable') + '/**'], 'theme': 'keep'})
                            self.assertEqual((profile / 'skills/impeccable/SKILL.md').read_text(), descriptor('.pi/agent/skills'))
                        else:
                            self.assertNotIn('verified', result.stdout)
                            self.assertEqual(self.snapshot(), before)
                            self.assertEqual((self.root / 'calls').read_bytes(), calls)

    def test_native_pi_resource_paths_and_override_precedence_use_each_discovery_source(self):
        self.adapter()
        shared = self.home / '.agents/skills/impeccable'
        for profile in (self.home / '.pi/agent', self.home / 'selected pi'):
            self.env['PI_CODING_AGENT_DIR'] = str(profile)
            direct = profile / 'skills/impeccable'
            settings = profile / 'settings.json'
            cases = [
                (['+skills/impeccable', '-' + str(shared)], True),
                (['!impeccable', '+' + str(direct)], True),
                (['+~/.agents/skills/impeccable'], True),
                (['+SKILL.md', '+impeccable'], True),
                (['+skills/impeccable', '-skills/impeccable'], False),
                (['+skills/impeccable', '-./skills/impeccable/SKILL.md'], False),
                (['+.\\skills/impeccable'], False),
                (['!skills/**/impeccable'], False),
            ]
            for entries, success in cases:
                with self.subTest(profile=profile.name, entries=entries):
                    self.put(settings, json.dumps({'skills': entries + ['custom'], 'theme': 'keep'}))
                    before = self.snapshot()
                    calls = (self.root / 'calls').read_bytes()
                    result = self.adapter(success=success)
                    if success:
                        self.assertIn('verified', result.stdout)
                        self.assertEqual(json.loads(settings.read_text())['skills'][:-1], entries + ['custom'])
                        self.assertEqual((direct / 'SKILL.md').read_text(), descriptor('.pi/agent/skills'))
                    else:
                        self.assertNotIn('verified', result.stdout)
                        self.assertEqual(self.snapshot(), before)
                        self.assertEqual((self.root / 'calls').read_bytes(), calls)

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
    native_modes = os.environ.get('IMPECCABLE_TEST_NATIVE_MODES') == '1'
    if native_modes:
        mask = os.umask(0)
        os.umask(mask)
        (root / 'installer-umask').write_text(oct(mask))
        for name in ('.npm/_logs/install.log', '.npm/_cacache/content/blob'):
            cache = home / name
            cache.parent.mkdir(parents=True, exist_ok=True)
            cache.write_text('Inert npm cache created with inherited permissions.\n')
    if os.environ.get('IMPECCABLE_TEST_MODE') == 'failed-command':
        print('PRIVATE-SENTINEL arbitrary failure output', file=sys.stderr)
        raise SystemExit(1)
    descriptors = json.loads(os.environ.get('IMPECCABLE_TEST_DESCRIPTORS', '{}'))
    assert set(descriptors).issubset(PROVIDERS) and all(isinstance(text, str) for text in descriptors.values())
    for provider in PROVIDERS:
        skill = home / provider / 'impeccable'
        skill.mkdir(parents=True)
        (skill / 'SKILL.md').write_text(descriptors.get(provider, descriptor(provider)) + os.environ.get('IMPECCABLE_TEST_REVISION', ''))
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
        binary.chmod((binary.stat().st_mode & 0o777) | 0o755 if native_modes else 0o700)
        (skill / 'scripts/impeccable').chmod(0o755 if native_modes else 0o700)
        if provider == '.agents/skills':
            for name in ['openai.yaml'] + ['impeccable_' + agent.replace('-', '_') + '.toml' for agent in AGENTS]:
                file = skill / 'agents' / name
                file.parent.mkdir(exist_ok=True)
                file.write_text('Inert native agent metadata.\n')
        if native_modes:
            for file in skill.rglob('*'):
                if file.is_file() and file not in (binary, skill / 'scripts/impeccable'):
                    file.chmod(0o600)
    pi = home / '.pi/agent/skills/impeccable'
    ignores = json.loads(os.environ.get('IMPECCABLE_TEST_PI_IGNORES', '{}'))
    assert set(ignores).issubset(('.gitignore', '.ignore', '.fdignore')) and all(isinstance(text, str) for text in ignores.values())
    for name, text in ignores.items():
        (pi / name).write_text(text)
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
    elif mode == 'malformed-frontmatter':
        (pi / 'SKILL.md').write_text(descriptor('.pi/agent/skills').replace('\n---\n', '\nmetadata:\n  broken: [\n---\n'))
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
    if mode == 'failed-after-write':
        raise SystemExit(1)
    if mode == 'unsafe-bundled-engine':
        (home / '.claude/skills/impeccable/scripts/bin/linux-x64/impeccable').chmod(0o775)
    if mode == 'unsafe-npm-cache':
        (home / '.npm/_cacache/content/blob').chmod(0o664)
    if native_modes:
        paths = ['.claude/skills/impeccable/scripts/bin/linux-x64/impeccable',
                 '.claude/agents/impeccable-documenter.md', '.npm/_cacache/content/blob']
        (root / 'installer-modes.json').write_text(json.dumps({name: (home / name).stat().st_mode & 0o777 for name in paths}))
    print('PRIVATE-SENTINEL arbitrary installer output must not reach setup logs')


if __name__ == '__main__':
    if sys.argv[1:2] == ['--installer']:
        installer_fixture()
    else:
        unittest.main()
