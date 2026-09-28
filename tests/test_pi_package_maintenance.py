#!/usr/bin/env python3
"""Contract v5: safely refresh active-global Pi packages after managed maintenance."""
import json
import os
from pathlib import Path
import re
import shutil
import shlex
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
BASH = ('mac.sh', 'ubuntu.sh', 'wsl.sh', 'pi.sh', 'bazzite.sh')
PWSH = os.environ.get('PWSH_BIN') or shutil.which('pwsh')
NODE = subprocess.check_output(['node', '-p', 'process.execPath'], text=True).strip()
PIN = 'npm:pi-mcp-adapter@2.32.1'
FUNCTIONS = {
    'adapter': ('setup_pi_mcp_adapter', 'Setup-PiMcpAdapter'),
    'bridge': ('setup_pi_claude_bridge', 'Setup-PiClaudeBridge'),
    'companions': ('setup_pi_companion_packages', 'Setup-PiCompanionPackages'),
    'goal': ('setup_pi_goal_autoresearch', 'Setup-PiGoalAutoresearch'),
    'subagents': ('remove_pi_subagents', 'Remove-PiSubagents'),
    'rpiv': ('remove_pi_rpiv_packages', 'Remove-PiRpivPackages'),
    'refresh': ('refresh_pi_packages', 'Update-PiPackages'),
}

FAKE_PI = r'''#!/usr/bin/python3
import json, os, pathlib, re, sys
statefile=pathlib.Path(os.environ['FIXTURE_STATE']); state=json.loads(statefile.read_text())
args=sys.argv[1:]; action=args[0]; package=args[1] if len(args)>1 else ''
with statefile.with_suffix('.calls').open('a') as f: f.write(json.dumps(args)+'\n')
def identity(value): return re.match(r'^npm:(?:@[^/]+/)?[^@]+',value).group()
if state.get('fail') in (action, package):
    print('npm error code EALLOWREMOTE'); sys.exit(1)
if action=='list':
    if state.get('bad_list'): sys.exit(0)
    print('\n'.join(state.get('packages',[]))); sys.exit(0)
if action=='update':
    if state.get('fail') == 'update': sys.exit(1)
    sys.exit(0)
if action=='remove':
    filtered=[p for p in state.get('packages',[]) if identity(p)!=identity(package)]
    if filtered==state.get('packages',[]): print('No matching package found'); sys.exit(1)
    state['packages']=filtered
elif action=='install':
    if state.get('restricted') and package=='npm:pi-mcp-adapter':
        print('npm error code EALLOWREMOTE'); sys.exit(1)
    state['packages']=[p for p in state.get('packages',[]) if identity(p)!=identity(package)]+[package]
    agent=pathlib.Path(os.environ['PI_CODING_AGENT_DIR'])
    if package.startswith('npm:pi-mcp-adapter'):
        store=agent/'npm'; store.mkdir(parents=True,exist_ok=True)
        manifest=store/'package.json'; value=json.loads(manifest.read_text()) if manifest.exists() else {}
        version='2.33.0' if state.get('wrong_version') else '2.32.1'
        value.setdefault('dependencies',{})['pi-mcp-adapter']=version if os.environ.get('npm_config_save_exact')=='true' else '^'+version
        manifest.write_text(json.dumps(value))
        installed=store/'node_modules/pi-mcp-adapter';installed.mkdir(parents=True,exist_ok=True)
        metadata={'name':'pi-mcp-adapter','version':version,'pi':{'extensions':['./index.ts']}}
        if state.get('bad_manifest'): metadata['pi']['extensions']=[]
        (installed/'package.json').write_text(json.dumps(metadata))
        entry=installed/'index.ts'
        if entry.exists() or entry.is_symlink(): entry.unlink()
        if state.get('bad_resource')=='empty': entry.write_text('')
        elif state.get('bad_resource')=='linked': entry.symlink_to(installed/'package.json')
        elif state.get('bad_resource')!='missing': entry.write_text('export default function(pi) {}\n')
    # pi install registers packages in the active global settings, not just npm.
    settings=agent/'settings.json';value=json.loads(settings.read_text()) if settings.exists() else {}
    entries=value.get('packages',[])
    if not any((p if isinstance(p,str) else p['source'])==package for p in entries): entries.append(package)
    value['packages']=entries;settings.write_text(json.dumps(value))
statefile.write_text(json.dumps(state))
'''


def extract(script, name):
    text = (ROOT / script).read_text()
    pattern = r'^function ' + name + r' \{\n.*?^\}' if script.endswith('.ps1') else r'^' + name + r'\(\) \{\n.*?^\}'
    match = re.search(pattern, text, re.M | re.S)
    return match.group() if match else ''


class PackageMaintenance(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='pi-maintenance-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.home = self.root / 'home'; self.home.mkdir()
        self.agent = self.home / '.pi/agent'; self.agent.mkdir(parents=True)
        self.bin = self.root / 'bin'; self.bin.mkdir()
        for name, text in [('pi', FAKE_PI), ('npm', '#!/bin/sh\nexit 0\n')]:
            file = self.bin / name; file.write_text(text); file.chmod(0o700)
        self.statefile = self.root / 'state.json'
        self.state = {'packages': ['npm:pi-goal', 'npm:pi-autoresearch', 'npm:pi-web-access']}
        self.env = {'HOME': str(self.home), 'USERPROFILE': str(self.home), 'PI_CODING_AGENT_DIR': str(self.agent),
                    'PATH': os.pathsep.join([str(self.bin), str(Path(NODE).parent), os.defpath]),
                    'FIXTURE_STATE': str(self.statefile), 'LC_ALL': 'C', 'PI_OFFLINE': '1'}

    def run_helper(self, script, helper):
        self.statefile.write_text(json.dumps(self.state))
        names = [pair[1 if script.endswith('.ps1') else 0] for pair in FUNCTIONS.values()]
        if script.endswith('.ps1'):
            names += ['Prepare-PiMcpAdapter', 'Remove-PiMcpAdapterSettings', 'Remove-PiGoalAutoresearchSettings',
                      'Set-PiAutoresearchShortcut', 'Set-JsonProperty', 'Remove-JsonProperty']
            code = '''$ErrorActionPreference='Stop'
function Write-Message { param($Text) }
function Write-Debug { param($Text) }
function Write-Success { param($Text) Write-Host "SUCCESS: $Text" }
function Write-Warning { param($Text) Write-Host "WARNING: $Text" }
function Write-Error { param($Text) Write-Host "ERROR: $Text" }
function Test-EnvLocalFlag { param($Name) return [Environment]::GetEnvironmentVariable($Name) -eq '1' }
''' + '\n'.join(extract(script, name) for name in names)
            code += '\n$result=' + FUNCTIONS[helper][1] + '\nif ($result -isnot [bool]) { Write-Host "INVALID-RESULT"; exit 99 }; if (-not $result) { exit 1 }\n'
            fixture = self.root / 'fixture.ps1'
            fixture.write_text(code)
            command = [PWSH, '-NoProfile', '-NonInteractive', '-File', str(fixture)]
        else:
            names += ['prepare_pi_mcp_adapter', 'remove_pi_mcp_adapter_settings', 'remove_pi_goal_autoresearch_settings',
                      'configure_pi_autoresearch_shortcut']
            code = '''print_message() { :; }
print_debug() { :; }
print_success() { printf 'SUCCESS: %s\\n' "$*"; }
print_warning() { printf 'WARNING: %s\\n' "$*"; }
print_error() { printf 'ERROR: %s\\n' "$*"; }
''' + '\n'.join(extract(script, name) for name in names) + '\n' + FUNCTIONS[helper][0] + '\n'
            command = ['bash', '--noprofile', '--norc']
        result = subprocess.run(command, input=code, env=self.env, cwd=self.root,
                                text=True, capture_output=True, timeout=15)
        self.state = json.loads(self.statefile.read_text())
        return result

    def test_setup_final_status_and_log_finalization(self):
        # Execute each real orchestration tail and entry point. All unrelated
        # provisioning is replaced at function boundaries; no setup script is sourced.
        for script in (*BASH, *(['win.ps1'] if PWSH else [])):
            for failure in ('adapter', 'bridge', 'companions', 'goal', 'subagents', 'rpiv', 'refresh', 'prose', 'prepare', 'permissions', 'askclaude-policy', 'none'):
                with self.subTest(script=script, failure=failure):
                    text = (ROOT / script).read_text()
                    windows = script.endswith('.ps1')
                    names = re.findall(r'^function ([\w-]+)(?:\s|\()', text, re.M) if windows else re.findall(r'^(\w+)\(\) \{', text, re.M)
                    if windows:
                        code = "$ErrorActionPreference='Stop'\n" + '\n'.join('function ' + n + ' { return $true }' for n in names)
                        for key, pair in FUNCTIONS.items():
                            code += '\nfunction ' + pair[1] + ' { Write-Host "PACKAGE-STEP:' + key + '"; return $' + ('false' if key == failure else 'true') + ' }'
                        code += '\nfunction Prepare-PiMcpAdapter { return $' + ('false' if failure == 'prepare' else 'true') + ' }'
                        code += '\nfunction Prepare-PiProfilePermissions { return $' + ('false' if failure == 'permissions' else 'true') + ' }'
                        code += '\nfunction Remove-PiProse { return $' + ('false' if failure == 'prose' else 'true') + ' }'
                        code += '\nfunction Disable-PiAskClaude { return $' + ('false' if failure == 'askclaude-policy' else 'true') + ' }'
                        code += '\nfunction Update-PiPackages { Write-Host "PACKAGE-STEP:refresh"; return $' + ('false' if failure == 'refresh' else 'true') + ' }'
                        code += '''
function Test-EnvLocalFlag { return $false }
function Remove-CompoundEngineeringResources { Write-Host 'UNRELATED-CONTINUED'; return $true }
function Get-SetupLogDirectory { return (Join-Path $env:HOME 'logs') }
function Start-Transcript { }
function Complete-SetupLog { Write-Host 'LOG-FINALIZED' }
'''
                        code += extract(script, 'Invoke-WindowsSetupTasks') + '\n' + extract(script, 'Initialize-WindowsEnvironment')
                        code += '\ntry { Initialize-WindowsEnvironment } catch { Write-Host "EXPECTED-SETUP-ERROR"; exit 1 }\n'
                        fixture = self.root / 'main.ps1'; fixture.write_text(code)
                        command = [PWSH, '-NoProfile', '-NonInteractive', '-File', str(fixture)]
                    else:
                        code = '\n'.join(n + '() { return 0; }' for n in names)
                        for key, pair in FUNCTIONS.items():
                            code += '\n' + pair[0] + '() { echo "PACKAGE-STEP:' + key + '"; return ' + ('1' if key == failure else '0') + '; }'
                        code += '\nprepare_pi_mcp_adapter() { return ' + ('1' if failure == 'prepare' else '0') + '; }'
                        code += '\nprepare_pi_profile_permissions() { return ' + ('1' if failure == 'permissions' else '0') + '; }'
                        code += '\nremove_pi_prose() { return ' + ('1' if failure == 'prose' else '0') + '; }'
                        code += '\ndisable_pi_askclaude() { return ' + ('1' if failure == 'askclaude-policy' else '0') + '; }'
                        code += '\nrefresh_pi_packages() { echo "PACKAGE-STEP:refresh"; return ' + ('1' if failure == 'refresh' else '0') + '; }'
                        code += '''
print_warning() { printf '%s\\n' "$*"; }
remove_compound_engineering_resources() { printf 'UNRELATED-CONTINUED\\n'; }
start_setup_log() { :; }
finish_setup_log() { printf 'LOG-FINALIZED:%s\\n' "$1"; return "$1"; }
'''
                        tail = extract(script, 'run_setup_tasks')
                        tail = tail[re.search(r'^    if ! [^\n]*prepare_pi_profile_permissions', tail, re.M).start():]
                        if script == 'mac.sh':
                            # CLT verification precedes this slice. Preserve the
                            # actual gate with explicitly verified readiness.
                            code += '\nMACOS_DEVELOPER_TOOLS_STATE=ready\n'
                            for gate in ('macos_developer_tools_ready_for', 'macos_existing_prerequisites', 'macos_clt_summary'):
                                code += '\n' + extract(script, gate)
                        code += '\nrun_setup_tasks() {\nlocal _setup_had_errors=0 _pi_go_ready=0 PI_PROFILE_MUTATIONS_BLOCKED=0\n' + tail
                        code += '\n' + extract(script, 'main') + '\nmain\n'
                        command = ['bash', '--noprofile', '--norc']
                    result = subprocess.run(command, input=code, env=self.env, cwd=self.root, capture_output=True, text=True, timeout=15)
                    self.assertEqual(result.returncode, 0 if failure == 'none' else 1, result.stdout + result.stderr)
                    self.assertIn('UNRELATED-CONTINUED', result.stdout)
                    self.assertIn('LOG-FINALIZED', result.stdout)
                    if failure != 'none': self.assertNotIn('Setup complete!', result.stdout)
                    if failure in ('prose', 'prepare', 'permissions', 'askclaude-policy'):
                        self.assertNotIn('PACKAGE-STEP:', result.stdout)
                    else:
                        self.assertIn('PACKAGE-STEP:goal', result.stdout)
                        self.assertLess(result.stdout.index('PACKAGE-STEP:adapter'), result.stdout.index('PACKAGE-STEP:subagents'))
                    if failure in FUNCTIONS and failure != 'refresh':
                        self.assertNotIn('PACKAGE-STEP:refresh', result.stdout)
                    elif failure not in ('prose', 'prepare', 'permissions', 'askclaude-policy'):
                        self.assertIn('PACKAGE-STEP:refresh', result.stdout)

    def seed_affected_store(self):
        store = self.agent / 'npm'; store.mkdir(exist_ok=True)
        settings = {'packages': [{'source': 'npm:pi-mcp-adapter@2.33.0', 'extensions': ['index.ts'], 'skills': []},
                                 'npm:unrelated'], 'privateSentinel': 'DO-NOT-LOG-FIXTURE'}
        manifest = {'dependencies': {'pi-mcp-adapter': '^2.33.0', 'unrelated': '1.0.0'}, 'private': True}
        (self.agent / 'settings.json').write_text(json.dumps(settings))
        (store / 'package.json').write_text(json.dumps(manifest))
        (store / 'package-lock.json').write_text('{"lockfileVersion":3,"fixture":"npm owns this"}')
        (self.home / '.npmrc').write_text('allow-remote=none\n//registry.example/:_authToken=DO-NOT-LOG-FIXTURE\n')
        return settings, manifest

    def test_affected_custom_profile_recovers_idempotently(self):
        default = self.agent / 'settings.json'; default.write_text('{"untouched":"default profile"}')
        self.agent = self.home / 'custom agent'; self.agent.mkdir()
        self.env['PI_CODING_AGENT_DIR'] = str(self.agent)
        for script in (*BASH, *(['win.ps1'] if PWSH else [])):
            with self.subTest(script=script):
                settings, manifest = self.seed_affected_store()
                settings['packages'][0]['source'] = PIN
                manifest['dependencies']['pi-mcp-adapter'] = '2.32.1'
                for _ in range(2):
                    result = self.run_helper(script, 'adapter')
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertEqual(json.loads((self.agent / 'settings.json').read_text()), settings)
                    self.assertEqual(json.loads((self.agent / 'npm/package.json').read_text()), manifest)
                    self.assertNotIn('DO-NOT-LOG-FIXTURE', result.stdout + result.stderr)
                self.assertEqual(default.read_text(), '{"untouched":"default profile"}')
                self.assertIn('allow-remote=none', (self.home / '.npmrc').read_text())
                self.assertEqual((self.agent / 'npm/package-lock.json').read_text(), '{"lockfileVersion":3,"fixture":"npm owns this"}')

    def test_banned_adapter_removes_only_its_managed_records(self):
        self.env['BAN_PI_MCP_ADAPTER'] = '1'
        for script in (*BASH, *(['win.ps1'] if PWSH else [])):
            with self.subTest(script=script):
                settings, manifest = self.seed_affected_store()
                settings['packages'].pop(0)
                del manifest['dependencies']['pi-mcp-adapter']
                result = self.run_helper(script, 'adapter')
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(json.loads((self.agent / 'settings.json').read_text()), settings)
                self.assertEqual(json.loads((self.agent / 'npm/package.json').read_text()), manifest)
                self.assertFalse(self.statefile.with_suffix('.calls').exists(), 'Opt-out must not install adapter')

    def test_disabled_or_unverified_extension_filters_do_not_report_success(self):
        for entry in ({'extensions': []}, {'extensions': ['-index.ts']},
                      {'extensions': ['!index.ts']}, {'autoload': False},
                      {'extensions': ['./index.ts']}, {'extensions': ['other.ts']},
                      {'extensions': ['*.ts']}, {'extensions': 'index.ts'},
                      {'extensions': [42]}, {'extensions': ['+index.ts', '-index.ts']}):
            for script in (*BASH, *(['win.ps1'] if PWSH else [])):
                with self.subTest(script=script, entry=entry):
                    settings, _ = self.seed_affected_store()
                    settings['packages'][0] = dict(source=PIN, skills=[], **entry)
                    target = self.agent / 'settings.json'
                    target.write_text(json.dumps(settings))
                    result = self.run_helper(script, 'adapter')
                    self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                    self.assertNotIn('SUCCESS:', result.stdout)
                    self.assertIn('pi config', result.stdout + result.stderr)
                    self.assertEqual(json.loads(target.read_text()), settings)

    def test_explicit_enabled_filters_are_preserved(self):
        for entry in ({}, {'skills': []}, {'extensions': ['index.ts']},
                      {'extensions': ['+./index.ts']},
                      {'extensions': ['*.ts', '+index.ts']},
                      {'extensions': ['!*', '+./index.ts']},
                      {'autoload': False, 'extensions': ['!index.ts', '+index.ts']}):
            for script in (*BASH, *(['win.ps1'] if PWSH else [])):
                with self.subTest(script=script, entry=entry):
                    settings, _ = self.seed_affected_store()
                    settings['packages'][0] = dict(source=PIN, **entry)
                    target = self.agent / 'settings.json'
                    target.write_text(json.dumps(settings))
                    result = self.run_helper(script, 'adapter')
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertIn('enabled in the active global profile', result.stdout)
                    self.assertEqual(json.loads(target.read_text()), settings)

    def test_missing_empty_or_linked_entry_point_fails_validation(self):
        for resource in ('missing', 'empty', 'linked'):
            self.state['bad_resource'] = resource
            for script in (*BASH, *(['win.ps1'] if PWSH else [])):
                with self.subTest(script=script, resource=resource):
                    result = self.run_helper(script, 'adapter')
                    self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                    self.assertNotIn('SUCCESS:', result.stdout)

    def test_missing_manifest_extension_fails_validation(self):
        self.state['bad_manifest'] = True
        for script in (*BASH, *(['win.ps1'] if PWSH else [])):
            with self.subTest(script=script):
                result = self.run_helper(script, 'adapter')
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertNotIn('SUCCESS:', result.stdout)

    def test_duplicate_adapter_entries_are_not_assumed_enabled(self):
        for script in (*BASH, *(['win.ps1'] if PWSH else [])):
            with self.subTest(script=script):
                settings, _ = self.seed_affected_store()
                settings['packages'].insert(0, {'source': PIN, 'extensions': []})
                (self.agent / 'settings.json').write_text(json.dumps(settings))
                result = self.run_helper(script, 'adapter')
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertNotIn('SUCCESS:', result.stdout)

    def test_wrong_installed_version_fails_validation(self):
        self.state['wrong_version'] = True
        for script in (*BASH, *(['win.ps1'] if PWSH else [])):
            with self.subTest(script=script):
                result = self.run_helper(script, 'adapter')
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertNotIn('SUCCESS:', result.stdout)

    def test_malformed_metadata_is_preserved_without_running_pi(self):
        for relative in ('settings.json', 'npm/package.json', 'npm/package-lock.json'):
            for script in (*BASH, *(['win.ps1'] if PWSH else [])):
                with self.subTest(script=script, relative=relative):
                    self.seed_affected_store()
                    target = self.agent / relative
                    original = target.read_bytes()
                    target.write_text('{DO-NOT-LOG-FIXTURE invalid JSON')
                    before = {p: p.read_bytes() for p in self.agent.rglob('*') if p.is_file()}
                    result = self.run_helper(script, 'adapter')
                    self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                    self.assertEqual({p: p.read_bytes() for p in before}, before)
                    self.assertFalse(self.statefile.with_suffix('.calls').exists())
                    self.assertNotIn('DO-NOT-LOG-FIXTURE', result.stdout + result.stderr)
                    target.write_bytes(original)

    def test_linked_metadata_is_not_followed(self):
        for script in (*BASH, *(['win.ps1'] if PWSH else [])):
            for hardlink in (False, True):
                with self.subTest(script=script, hardlink=hardlink):
                    self.seed_affected_store()
                    target = self.agent / 'npm/package.json'
                    outside = self.root / 'outside.json'
                    original = target.read_bytes(); outside.write_bytes(original)
                    target.unlink()
                    if hardlink: os.link(outside, target)
                    else: target.symlink_to(outside)
                    result = self.run_helper(script, 'adapter')
                    self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                    self.assertEqual(outside.read_bytes(), original)
                    self.assertFalse(self.statefile.with_suffix('.calls').exists())
                    target.unlink()

    def test_linked_store_is_not_followed(self):
        for script in (*BASH, *(['win.ps1'] if PWSH else [])):
            with self.subTest(script=script):
                self.seed_affected_store()
                store = self.agent / 'npm'
                outside = self.root / ('outside-store-' + script)
                store.rename(outside)
                before = (outside / 'package.json').read_bytes()
                store.symlink_to(outside, target_is_directory=True)
                result = self.run_helper(script, 'adapter')
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertEqual((outside / 'package.json').read_bytes(), before)
                self.assertFalse(self.statefile.with_suffix('.calls').exists())
                store.unlink()

    def test_legacy_cleanup_failure_survives_successful_companion_update(self):
        self.state['packages'].append('npm:pi-ask-user')
        self.state['fail'] = 'remove'
        for script in (*BASH, *(['win.ps1'] if PWSH else [])):
            with self.subTest(script=script):
                result = self.run_helper(script, 'companions')
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertIn('npm:pi-web-access installed/updated', result.stdout)
                self.assertIn('Failed to remove legacy Pi Ask User', result.stdout)

    def test_absent_legacy_packages_and_goal_opt_out_are_successful(self):
        self.env['BAN_PI_GOAL_AUTORESEARCH'] = '1'
        for script in (*BASH, *(['win.ps1'] if PWSH else [])):
            for helper in ('subagents', 'rpiv', 'goal'):
                with self.subTest(script=script, helper=helper):
                    result = self.run_helper(script, helper)
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertNotIn('WARNING:', result.stdout)

    @unittest.skipUnless(os.environ.get('PI_ADAPTER_DOTFILES_SOURCE'),
                         'Set PI_ADAPTER_DOTFILES_SOURCE for the cross-repository render/setup fixture')
    def test_dotfiles_and_setup_keep_adapter_and_bridge_enabled_across_repeated_runs(self):
        template = Path(os.environ['PI_ADAPTER_DOTFILES_SOURCE']) / 'private_dot_pi/agent/private_settings.json.tmpl'
        config = self.root / 'chezmoi.json'; config.write_text('{}')
        source = self.root / 'empty-source'; source.mkdir()
        for script in (*BASH, *(['win.ps1'] if PWSH else [])):
            for work in ('0', '1'):
                for disabled in ('0', '1'):
                    with self.subTest(script=script, work=work, disabled=disabled):
                        self.env.update(WORK_MACHINE=work, BAN_PI_MCP_ADAPTER=disabled)
                        envfile = self.home / '.env.local'
                        envfile.write_text(f'WORK_MACHINE={work}\nBAN_PI_MCP_ADAPTER={disabled}\n')
                        before = envfile.read_bytes()
                        target = self.agent / 'settings.json'
                        target.write_text('{"packages":[]}')
                        # Start with setup registering the bridge before a later
                        # dotfiles update. Never run real Pi or load extensions.
                        result = self.run_helper(script, 'bridge')
                        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                        self.assertEqual(json.loads(target.read_text())['packages'], ['npm:pi-claude-bridge'])
                        self.assertIn(['install', 'npm:pi-claude-bridge'], [
                            json.loads(line) for line in self.statefile.with_suffix('.calls').read_text().splitlines()
                        ])
                        for _ in range(2):
                            rendered = subprocess.run([
                                shutil.which('chezmoi'), '--config', str(config), '--source', str(source),
                                '--destination', str(self.home), '--cache', str(self.root / 'chezmoi-cache'),
                                '--persistent-state', str(self.root / 'chezmoi-state'),
                                '--override-data', json.dumps({'chezmoi': {'homeDir': str(self.home),
                                    'os': 'windows' if script.endswith('.ps1') else 'darwin' if script == 'mac.sh' else 'linux'}}),
                                'execute-template', '--file', str(template),
                            ], env=self.env, cwd=self.root, capture_output=True, text=True, check=True)
                            settings = json.loads(rendered.stdout)
                            self.assertEqual(PIN in settings['packages'], disabled != '1')
                            self.assertEqual(settings['packages'].count('npm:pi-claude-bridge'), 1,
                                             'Dotfiles must retain the enabled bridge registration without another install')
                            target.write_text(rendered.stdout)
                            for helper in ('adapter', 'bridge'):
                                result = self.run_helper(script, helper)
                                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                                self.assertEqual(json.loads(target.read_text()), settings)
                        self.assertEqual(envfile.read_bytes(), before)

    def run_git(self, *args, cwd=None):
        env = dict(self.env)
        for key in list(env):
            if key.startswith('GIT_'):
                del env[key]
        return subprocess.run(['git', *args], cwd=cwd or self.root, env=env, text=True,
                              capture_output=True, check=True)

    def seed_git_checkout(self, source='git:github.com/example/fixture@v1'):
        checkout = self.agent / 'git/github.com/example/fixture'
        checkout.mkdir(parents=True)
        self.run_git('init', '-q', cwd=checkout)
        (checkout / 'tracked.txt').write_text('clean\n')
        self.run_git('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid',
                     'add', 'tracked.txt', cwd=checkout)
        self.run_git('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid',
                     'commit', '-qm', 'fixture', cwd=checkout)
        (self.agent / 'settings.json').write_text(json.dumps({'packages': [source]}))
        return checkout

    def test_refresh_targets_only_active_global_profile_and_preserves_declarations(self):
        self.env.pop('PI_OFFLINE')
        project = self.root / '.pi'; project.mkdir()
        project_settings = project / 'settings.json'
        project_settings.write_text(json.dumps({'packages': ['npm:project-only']}))
        other = self.home / '.pi/other'; other.mkdir()
        other_settings = other / 'settings.json'; other_settings.write_text('{"packages":["npm:other"]}')
        settings = {'npmCommand': ['fixture-npm', '--safe'], 'packages': [
            'npm:exact@1.2.3', 'npm:range@^2.0.0', '/local/package',
            {'source': 'npm:disabled', 'extensions': [], 'skills': ['!legacy/**']},
        ], 'sentinel': 'preserved'}
        target = self.agent / 'settings.json'; target.write_text(json.dumps(settings))
        for script in (*BASH, *(['win.ps1'] if PWSH else [])):
            with self.subTest(script=script):
                if self.statefile.with_suffix('.calls').exists(): self.statefile.with_suffix('.calls').unlink()
                result = self.run_helper(script, 'refresh')
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                calls = [json.loads(line) for line in self.statefile.with_suffix('.calls').read_text().splitlines()]
                self.assertEqual(calls, [['update', '--extensions', '--no-approve']])
                self.assertEqual(json.loads(target.read_text()), settings)
                self.assertEqual(project_settings.read_text(), '{"packages": ["npm:project-only"]}')
                self.assertEqual(other_settings.read_text(), '{"packages":["npm:other"]}')

    def test_refresh_offline_malformed_or_linked_settings_and_command_failure_are_incomplete(self):
        cases = ('offline', 'malformed', 'linked', 'command')
        for script in (*BASH, *(['win.ps1'] if PWSH else [])):
            for case in cases:
                with self.subTest(script=script, case=case):
                    self.env.pop('PI_OFFLINE', None); self.state.pop('fail', None)
                    target = self.agent / 'settings.json'
                    if target.exists() or target.is_symlink(): target.unlink()
                    outside = self.root / ('outside-' + script + '-' + case)
                    if case == 'offline': self.env['PI_OFFLINE'] = 'yes'; target.write_text('{}')
                    elif case == 'malformed': target.write_text('{invalid')
                    elif case == 'linked': outside.write_text('{}'); target.symlink_to(outside)
                    else: target.write_text('{}'); self.state['fail'] = 'update'
                    calls = self.statefile.with_suffix('.calls')
                    if calls.exists(): calls.unlink()
                    result = self.run_helper(script, 'refresh')
                    self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                    self.assertNotIn('SUCCESS:', result.stdout)
                    if case != 'command': self.assertFalse(calls.exists())
                    else: self.assertEqual(json.loads(calls.read_text().strip()), ['update', '--extensions', '--no-approve'])
                    if target.is_symlink(): target.unlink()

    def test_refresh_noncanonical_git_aliases_fail_closed_before_update(self):
        self.env.pop('PI_OFFLINE')
        sources = (
            'https://github.com/example/fixture/tree/v1',
            'git:github.com/example/fixture#v1',
            'https://github.com/example/fixture/',
            'https://github.com/example/fixture.git/',
            'https://github.com/example/%66ixture@v1',
            'git:github:example/fixture@v1',
            'git:github:example/fixture#v1',
            'https://www.github.com/example/fixture',
            'https://www.gitlab.com/example/fixture',
            'https://www.bitbucket.org/example/fixture',
            'https://www.gist.github.com/example/fixture',
            'https://github.com/example/fixture.git.git',
            'https://gitlab.com/example/fixture.git.git@v1',
        )
        for source in sources:
            for script in (*BASH, *(['win.ps1'] if PWSH else [])):
                with self.subTest(script=script, source=source):
                    git_root = self.agent / 'git'
                    if git_root.exists(): shutil.rmtree(git_root)
                    checkout = self.seed_git_checkout(source)
                    (checkout / 'tracked.txt').write_text('edited\n')
                    calls = self.statefile.with_suffix('.calls')
                    if calls.exists(): calls.unlink()
                    result = self.run_helper(script, 'refresh')
                    self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                    self.assertFalse(calls.exists())

    def test_refresh_git_preflight_blocks_tracked_untracked_ignored_and_unverified_checkouts(self):
        self.env.pop('PI_OFFLINE')
        for condition in ('tracked', 'untracked', 'ignored', 'not-repository', 'linked-metadata', 'parent-repository'):
            for script in (*BASH, *(['win.ps1'] if PWSH else [])):
                with self.subTest(script=script, condition=condition):
                    git_root = self.agent / 'git'
                    if git_root.exists(): shutil.rmtree(git_root)
                    checkout = self.seed_git_checkout()
                    if condition == 'tracked': (checkout / 'tracked.txt').write_text('edited\n')
                    elif condition == 'untracked': (checkout / 'new.txt').write_text('new\n')
                    elif condition == 'ignored':
                        (checkout / '.gitignore').write_text('ignored.txt\n')
                        self.run_git('add', '.gitignore', cwd=checkout)
                        self.run_git('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-qm', 'ignore', cwd=checkout)
                        (checkout / 'ignored.txt').write_text('ignored\n')
                    elif condition == 'not-repository': shutil.rmtree(checkout / '.git')
                    elif condition == 'linked-metadata':
                        metadata = self.root / ('git-metadata-' + script)
                        if metadata.exists(): shutil.rmtree(metadata)
                        (checkout / '.git').rename(metadata)
                        (checkout / '.git').symlink_to(metadata, target_is_directory=True)
                    elif condition == 'parent-repository':
                        shutil.rmtree(checkout / '.git')
                        self.run_git('init', '-q', cwd=git_root)
                    calls = self.statefile.with_suffix('.calls')
                    if calls.exists(): calls.unlink()
                    result = self.run_helper(script, 'refresh')
                    self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                    self.assertFalse(calls.exists())

    def test_missing_checkout_rejects_linked_or_dangling_ancestors(self):
        self.env.pop('PI_OFFLINE')
        for condition in ('linked-host', 'linked-owner', 'dangling-host', 'dangling-owner'):
            for script in (*BASH, *(['win.ps1'] if PWSH else [])):
                with self.subTest(script=script, condition=condition):
                    git_root = self.agent / 'git'
                    if git_root.exists(): shutil.rmtree(git_root)
                    git_root.mkdir()
                    outside = self.root / ('outside-' + script + '-' + condition)
                    if outside.exists(): shutil.rmtree(outside)
                    target = self.root / ('missing-' + script + '-' + condition)
                    if target.exists(): shutil.rmtree(target)
                    host = git_root / 'github.com'
                    if condition == 'linked-host':
                        outside.mkdir(); host.symlink_to(outside, target_is_directory=True)
                    elif condition == 'dangling-host': host.symlink_to(target, target_is_directory=True)
                    else:
                        host.mkdir()
                        owner = host / 'example'
                        if condition == 'linked-owner': outside.mkdir(); owner.symlink_to(outside, target_is_directory=True)
                        else: owner.symlink_to(target, target_is_directory=True)
                    (self.agent / 'settings.json').write_text(json.dumps({'packages': ['git:github.com/example/fixture']}))
                    calls = self.statefile.with_suffix('.calls')
                    if calls.exists(): calls.unlink()
                    result = self.run_helper(script, 'refresh')
                    self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                    self.assertFalse(calls.exists())

    def test_refresh_rejects_inherited_git_repository_redirection(self):
        self.env.pop('PI_OFFLINE')
        for variable in ('GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE', 'GIT_COMMON_DIR',
                         'GIT_OBJECT_DIRECTORY', 'GIT_ALTERNATE_OBJECT_DIRECTORIES'):
            for script in (*BASH, *(['win.ps1'] if PWSH else [])):
                with self.subTest(script=script, variable=variable):
                    git_root = self.agent / 'git'
                    if git_root.exists(): shutil.rmtree(git_root)
                    git_root.mkdir()
                    (self.agent / 'settings.json').write_text(json.dumps({'packages': ['git:github.com/example/fixture']}))
                    self.env[variable] = str(self.root / 'redirected')
                    calls = self.statefile.with_suffix('.calls')
                    if calls.exists(): calls.unlink()
                    try:
                        result = self.run_helper(script, 'refresh')
                    finally:
                        self.env.pop(variable, None)
                    self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                    self.assertFalse(calls.exists())

    def test_clean_canonical_git_checkouts_refresh_without_modification(self):
        self.env.pop('PI_OFFLINE')
        sources = ('git:github.com/example/fixture@v1',
                   'git:git@github.com:example/fixture@v1',
                   'https://github.com/example/fixture.git@v1',
                   'ssh://git@github.com/example/fixture@v1')
        for source in sources:
            for script in (*BASH, *(['win.ps1'] if PWSH else [])):
                with self.subTest(script=script, source=source):
                    git_root = self.agent / 'git'
                    if git_root.exists(): shutil.rmtree(git_root)
                    checkout = self.seed_git_checkout(source)
                    before = (checkout / 'tracked.txt').read_bytes()
                    result = self.run_helper(script, 'refresh')
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertEqual((checkout / 'tracked.txt').read_bytes(), before)

    def test_embedded_refresh_policy_is_identical(self):
        policies = []
        for script in (*BASH, 'win.ps1'):
            body = extract(script, 'Update-PiPackages' if script.endswith('.ps1') else 'refresh_pi_packages')
            if script.endswith('.ps1'):
                policy = body.split("$code = @'\n", 1)[1].split("\n'@", 1)[0]
            else:
                policy = body.split("<<'PI_PACKAGE_REFRESH_JS'\n", 1)[1].split('\nPI_PACKAGE_REFRESH_JS', 1)[0]
            policies.append(policy)
        self.assertTrue(all(policy == policies[0] for policy in policies))

    def test_embedded_recovery_policy_is_identical(self):
        policies = []
        for script in (*BASH, 'win.ps1'):
            body = extract(script, 'Prepare-PiMcpAdapter' if script.endswith('.ps1') else 'prepare_pi_mcp_adapter')
            if script.endswith('.ps1'):
                policy = body.split("$code = @'\n", 1)[1].split("\n'@", 1)[0]
            else:
                policy = body.split("<<'PI_ADAPTER_POLICY_JS'\n", 1)[1].split('\nPI_ADAPTER_POLICY_JS', 1)[0]
            policies.append(policy)
        self.assertTrue(all(policy == policies[0] for policy in policies))

    @unittest.skipUnless(os.environ.get('PI_PACKAGE_NPM_CLI') and os.environ.get('PI_PACKAGE_CLI'),
                         'Optional registry probe requires PI_PACKAGE_NPM_CLI (npm 12+) and PI_PACKAGE_CLI')
    def test_real_restricted_npm_clean_affected_and_banned_stores(self):
        # Explicit opt-in. Run real package CLIs only in this temporary HOME,
        # with lifecycle scripts disabled and remote dependencies prohibited.
        for name, variable in [('npm', 'PI_PACKAGE_NPM_CLI'), ('pi', 'PI_PACKAGE_CLI')]:
            command = shlex.join([NODE, str(Path(os.environ[variable]).resolve())])
            (self.bin / name).write_text('#!/bin/sh\nexec ' + command + ' "$@"\n')
        userconfig = self.root / 'npm-userconfig'; userconfig.write_text('')
        globalconfig = self.root / 'npm-globalconfig'; globalconfig.write_text('')
        self.env.update({'npm_config_allow_remote': 'none', 'npm_config_ignore_scripts': 'true',
                         'npm_config_userconfig': str(userconfig), 'npm_config_globalconfig': str(globalconfig),
                         'npm_config_cache': str(self.root / 'npm-cache'), 'npm_config_audit': 'false',
                         'npm_config_fund': 'false'})

        def cli(*args, success=True):
            result = subprocess.run(args, env=self.env, cwd=self.root, capture_output=True, text=True, timeout=120)
            if success: self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            return result

        broken = cli('pi', 'install', 'npm:pi-mcp-adapter@2.33.0', success=False)
        self.assertNotEqual(broken.returncode, 0)
        self.assertIn('EALLOWREMOTE', broken.stdout + broken.stderr)
        # run_helper normally has a short offline timeout, so invoke its two
        # production functions directly for this explicitly networked probe.
        code = '''print_message() { :; }; print_success() { :; }; print_debug() { :; }
print_warning() { printf '%s\\n' "$*" >&2; }
''' + extract('ubuntu.sh', 'prepare_pi_mcp_adapter') + '\n' + extract('ubuntu.sh', 'setup_pi_mcp_adapter') + '\nsetup_pi_mcp_adapter\n'
        fixture = self.root / 'real-adapter.sh'; fixture.write_text(code)
        cli('bash', str(fixture))
        sdk = Path(os.environ['PI_PACKAGE_CLI']).resolve().with_name('index.js')
        loaded = cli(NODE, str(ROOT / 'tests/pi-mcp-adapter-load.mjs'), str(sdk), str(self.agent), str(self.root))
        self.assertIn('PASS: pinned adapter loads MCP tools', loaded.stdout)
        cli('pi', 'install', 'npm:is-number@7.0.0')
        store = self.agent / 'npm'
        metadata = json.loads(cli('npm', 'view', 'pi-mcp-adapter@2.33.0', '--json').stdout)
        if isinstance(metadata, list):
            self.assertEqual(len(metadata), 1)
            metadata = metadata[0]
        self.assertEqual(metadata['version'], '2.33.0')
        manifest = json.loads((store / 'package.json').read_text())
        manifest['dependencies']['pi-mcp-adapter'] = '^2.33.0'
        (store / 'package.json').write_text(json.dumps(manifest))
        settings = json.loads((self.agent / 'settings.json').read_text())
        settings['packages'] = [{'source': 'npm:pi-mcp-adapter@2.33.0', 'skills': []}, 'npm:is-number@7.0.0']
        (self.agent / 'settings.json').write_text(json.dumps(settings))
        # Simulate a previous affected installation without ever allowing remote
        # downloads, including the visible and hidden npm lockfiles.
        for lockpath in [store / 'package-lock.json', store / 'node_modules/.package-lock.json']:
            lock = json.loads(lockpath.read_text())
            if '' in lock['packages']: lock['packages']['']['dependencies']['pi-mcp-adapter'] = '^2.33.0'
            entry = lock['packages']['node_modules/pi-mcp-adapter']
            entry.update(version='2.33.0', dependencies=metadata['dependencies'],
                         resolved=metadata['dist']['tarball'], integrity=metadata['dist']['integrity'])
            lockpath.write_text(json.dumps(lock))
        installed = store / 'node_modules/pi-mcp-adapter/package.json'
        installed.write_text(json.dumps({'name': 'pi-mcp-adapter', 'version': '2.33.0', 'dependencies': metadata['dependencies']}))
        for _ in range(2): cli('bash', str(fixture))
        self.assertEqual(json.loads(installed.read_text())['version'], '2.32.1')
        self.assertEqual(json.loads((self.agent / 'settings.json').read_text())['packages'],
                         [{'source': PIN, 'skills': []}, 'npm:is-number@7.0.0'])
        self.env['BAN_PI_MCP_ADAPTER'] = '1'
        cli('bash', str(fixture))
        cli('pi', 'install', 'npm:is-number@7.0.0')
        cli('bash', str(fixture))
        self.assertNotIn('pi-mcp-adapter', json.loads((store / 'package.json').read_text())['dependencies'])
        self.assertEqual(json.loads((store / 'node_modules/is-number/package.json').read_text())['version'], '7.0.0')
        self.assertEqual(userconfig.read_text(), '')
        self.assertEqual(globalconfig.read_text(), '')

    def test_adapter_uses_compatible_exact_pin(self):
        for script in (*BASH, *(['win.ps1'] if PWSH else [])):
            with self.subTest(script=script):
                self.state['restricted'] = True
                result = self.run_helper(script, 'adapter')
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn(PIN, self.state['packages'])
                manifest = json.loads((self.agent / 'npm/package.json').read_text())
                self.assertEqual(manifest['dependencies']['pi-mcp-adapter'], '2.32.1')

    def test_other_managed_failures_are_not_hidden_by_stale_registrations(self):
        for script in (*BASH, *(['win.ps1'] if PWSH else [])):
            for helper in ('bridge', 'companions', 'goal', 'subagents', 'rpiv'):
                with self.subTest(script=script, helper=helper):
                    self.state['fail'] = 'remove' if helper in ('subagents', 'rpiv') else 'install'
                    result = self.run_helper(script, helper)
                    self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                    self.assertNotIn('extensions are active', result.stdout)

    def test_inconclusive_package_validation_is_failure(self):
        self.state['bad_list'] = True
        for script in (*BASH, *(['win.ps1'] if PWSH else [])):
            for helper in ('adapter', 'bridge', 'companions', 'goal'):
                with self.subTest(script=script, helper=helper):
                    result = self.run_helper(script, helper)
                    self.assertEqual(result.returncode, 1, result.stdout + result.stderr)

    def test_failed_adapter_install_is_a_failure(self):
        for script in BASH:
            with self.subTest(script=script):
                self.state['fail'] = 'install'
                result = self.run_helper(script, 'adapter')
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertIn('EALLOWREMOTE', result.stdout)

    @unittest.skipUnless(PWSH, 'Set PWSH_BIN to run PowerShell wrappers')
    def test_windows_failed_adapter_install_returns_false(self):
        self.state['fail'] = 'install'
        result = self.run_helper('win.ps1', 'adapter')
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn('EALLOWREMOTE', result.stdout)


if __name__ == '__main__':
    unittest.main()
