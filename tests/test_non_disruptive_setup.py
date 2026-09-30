"""Real standalone callers and shared mutation boundaries; never execute setup live."""
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest
import shutil
import ast
import json
from itertools import product
from types import SimpleNamespace
from unittest.mock import patch

PWSH = os.environ.get('PWSH_BIN') or shutil.which('pwsh')

ROOT = Path(__file__).resolve().parents[1]
BASH = ('ubuntu.sh', 'mac.sh', 'pi.sh', 'bazzite.sh', 'wsl.sh')


def function(source, name):
    start = source.index(f'\n{name}() {{\n') + 1
    lines = []
    heredoc = None
    for line in source[start:].splitlines(keepends=True):
        lines.append(line)
        if heredoc:
            if line.strip() == heredoc: heredoc = None
            continue
        match = re.search(r'''(?<!<)<<-?\s*['"]?([A-Za-z_]\w*)''', line)
        if match: heredoc = match[1]
        elif line.rstrip() == '}': return ''.join(lines)
    raise AssertionError(f'unterminated helper {name}')


class NonDisruptive(unittest.TestCase):
    def test_default_real_caller_does_not_reach_mutating_stages(self):
        for name, health_status in product(BASH, (0, 1)):
            with self.subTest(script=name, health_status=health_status), tempfile.TemporaryDirectory() as tmp:
                source = (ROOT / name).read_text()
                # Fail closed: every legacy operation is inert but forbidden, except
                # the named safe observations. Retain the REAL caller and policy.
                names = re.findall(r'^([A-Za-z_][A-Za-z_0-9]*)\(\) \{', source, re.M)
                policy = (ROOT / 'lib/setup-policy.bash').read_text() if (ROOT / 'lib/setup-policy.bash').exists() else ''
                code = '\n'.join(f'{n}() {{ echo forbidden:{n} >> "$HOME/calls"; return 99; }}' for n in names)
                code += '\n' + policy + '\n'
                code += '''
print_section() { :; }; print_debug() { :; }
print_message() { echo "$*"; }; print_success() { echo "$*"; }
print_warning() { echo "$*"; }; print_error() { echo "$*"; }
whoami() { echo fixture; }; is_main_user() { return 1; }
ensure_not_root() { return 0; }; verify_bazzite_system() { return 0; }
headless_platform_gate() { return 0; }; fail_unsupported_headless() { return 0; }
check_pending_reboot() { echo reboot >> "$HOME/calls"; }
setup_observe_services() { echo health >> "$HOME/calls"; return "$HEALTH_STATUS"; }
acquire_setup_lock() { echo lock >> "$HOME/calls"; }
start_setup_log() { echo log-start >> "$HOME/calls"; }
finish_setup_log() { echo "log-finish:$1" >> "$HOME/calls"; return "$1"; }
'''
                for fn in ('run_setup_tasks', 'main'):
                    code += '\n' + function(source, fn)
                code += '\nmain\n'
                result = subprocess.run(['bash', '-c', code], cwd=tmp,
                                        env={'PATH': '/usr/bin:/bin', 'HOME': tmp, 'USER': 'fixture', 'HEALTH_STATUS': str(health_status)},
                                        capture_output=True, text=True, timeout=10)
                calls = (Path(tmp) / 'calls').read_text()
                self.assertNotIn('forbidden:', calls, (result.stdout, result.stderr, calls))
                self.assertEqual(result.returncode, health_status, result.stdout + result.stderr)
                self.assertIn('health', calls)
                self.assertIn('reboot', calls)
                self.assertIn(f'log-finish:{health_status}', calls)
                self.assertIn('maintenance pending', result.stdout.lower())

    def bash(self, code, files=None, environment=None):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            for name, content in (files or {}).items():
                path = home / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(content)
            before = {str(p.relative_to(home)): p.read_bytes() for p in home.rglob('*') if p.is_file()}
            policy = (ROOT / 'lib/setup-policy.bash').read_text()
            prelude = '''
print_message() { echo "$*"; }; print_debug() { echo "$*"; }
print_warning() { echo "$*"; }; print_error() { echo "$*"; }
print_success() { echo "$*"; }; print_section() { :; }
'''
            result = subprocess.run(['bash', '-c', policy + '\n' + prelude + '\n' + code], cwd=tmp,
                                    env={'PATH': '/usr/bin:/bin', 'HOME': tmp, **(environment or {})},
                                    capture_output=True, text=True, timeout=10)
            after = {str(p.relative_to(home)): p.read_bytes() for p in home.rglob('*') if p.is_file()}
            return result, before, after

    def test_indirect_real_mutation_boundaries_defer_before_any_effect(self):
        functions = ('setup_bb_server', 'bb_package_preflight', 'setup_bb_machine',
                     'ensure_shared_node_runtime', 'prepare_pi_profile_permissions',
                     'retire_global_backlog_mcp', 'setup_matt_pocock_skills',
                     'with_bb_dotfiles_umask', 'setup_dns64_for_ipv6_only',
                     'setup_tailscale_ssh', 'setup_unattended_upgrades', 'create_env_local')
        fixtures = {'.bb/config.json': '{"preserve":"idle sessions"}',
                    '.config/setup-bb-server/endpoint': 'fixture.ts.net 443 https://fixture.ts.net',
                    '.pi/agent/auth.json': '{"key":"synthetic-secret"}',
                    '.config/fish/config.fish': 'synthetic shared runtime activation',
                    '.config/chezmoi/chezmoi.toml': 'existing updater setting',
                    '.agents/skills/fixture/SKILL.md': 'never execute'}
        for name in BASH:
            source = (ROOT / name).read_text()
            for fn in functions:
                if f'\n{fn}() {{' not in source:
                    continue
                for consumer in ('busy', 'idle', 'unrecognized', 'appears-later'):
                    with self.subTest(script=name, helper=fn, consumer=consumer):
                        code = function(source, fn) + '\nsetup_policy_init\n' + fn + ' ubuntu\n'
                        result, before, after = self.bash(code, fixtures, {'CONSUMER': consumer})
                        self.assertEqual(result.returncode, 75, result.stdout + result.stderr)
                        self.assertEqual(before, after)
                        self.assertIn('Deferred:', result.stdout)
                        self.assertNotIn('synthetic-secret', result.stdout + result.stderr)
                        self.assertNotIn('command not found', result.stderr)

    def test_authorization_is_not_environment_or_saved_state(self):
        for saved in ('SETUP_MAINTENANCE_AUTHORIZED=1\nSETUP_POLICY_READY=1\n',
                      'MAINTENANCE=1\nWORK_MACHINE="1"\n',
                      'OPENCODE_GO_API_KEY="$(touch escaped)"\n'):
            result, before, after = self.bash('setup_policy_init; setup_load_environment; setup_require_maintenance fixture',
                                           {'.env.local': saved},
                                           {'SETUP_MAINTENANCE_AUTHORIZED': '1', 'SETUP_POLICY_READY': '1'})
            self.assertEqual(result.returncode, 75, result.stdout + result.stderr)
            self.assertEqual(before, after)
        result, before, after = self.bash('setup_policy_init; setup_load_environment',
                                       {'.env.local': 'touch escaped\n'})
        self.assertEqual(result.returncode, 1)
        self.assertEqual(before, after)
        self.assertIn('Failed:', result.stdout)

    def test_dotenv_comments_preserve_template_flags_and_literal_credentials(self):
        contents = '''BB_SERVER=1  # Opt in to a persistent bb server (Ubuntu only)
MACHINE_TYPE=physical  # Override VPS/physical detection when needed
GH_TOKEN='credential#literal' # trailing comment
ZAI_API_KEY="credential # spaced"  # another comment
OPENCODE_GO_API_KEY=credential#unquoted
WORK_MACHINE=1#not-a-comment
'''
        source = (ROOT / 'ubuntu.sh').read_text()
        for template in contents.splitlines()[:2]:
            self.assertIn('# ' + template, source)
        code = '''setup_load_environment || exit 1
[[ "$BB_SERVER" == 1 && "$MACHINE_TYPE" == physical && "$GH_TOKEN" == 'credential#literal' && "$ZAI_API_KEY" == 'credential # spaced' && "$OPENCODE_GO_API_KEY" == 'credential#unquoted' && "$WORK_MACHINE" == '1#not-a-comment' ]]
'''
        result, before, after = self.bash(code, {'.env.local': contents})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(before, after)
        self.assertNotIn('credential', result.stdout + result.stderr)
        for invalid in ('GH_TOKEN="unterminated', 'GH_TOKEN="one"two', 'GH_TOKEN="one"#two', 'GH_TOKEN=two words', '"GH_TOKEN"=value'):
            with self.subTest(invalid=invalid):
                result, before, after = self.bash('setup_load_environment', {'.env.local': invalid})
                self.assertEqual(result.returncode, 1)
                self.assertEqual(before, after)
                self.assertNotIn(invalid, result.stdout + result.stderr)

    def test_bb_default_never_executes_node_resolver_even_when_health_is_required(self):
        code = '''node() { echo mutation > "$HOME/resolver-ran"; return 99; }
mise() { node; }
bb_native_app_ready() { node -e 'legacy probe'; }
setup_systemd_available() { return 0; }
setup_observe_systemd_service() { SETUP_SERVICE_EXPECTED_ACTIVE=1; }
setup_readonly_python() { local ignored; while IFS= read -r ignored; do :; done; return 1; }
setup_observe_services ubuntu
'''
        result, before, after = self.bash(code, {'.config/setup-bb-server/preserved': 'existing deployment'})
        self.assertEqual(result.returncode, 1)
        self.assertEqual(before, after)
        self.assertIn('Failed: existing BB app/local execution health', result.stdout)
        native = function((ROOT / 'lib/setup-policy.bash').read_text(), 'setup_readonly_python')
        self.assertIn('"${python}" -I -S "$@"', native)
        self.assertNotIn('command -v', native)

    def test_fixed_native_python_ignores_account_startup_and_node_resolvers(self):
        code = '''node() { echo mutation > "$HOME/resolver-ran"; return 99; }
mise() { node; }
export PYTHONPATH="$HOME" PYTHONHOME="$HOME/missing-runtime"
setup_readonly_python - <<'ISOLATED_FIXTURE'
import sys
assert sys.flags.isolated and sys.flags.ignore_environment and sys.flags.no_site
ISOLATED_FIXTURE
'''
        result, before, after = self.bash(code, {'sitecustomize.py': 'open("startup-ran", "w").write("forbidden")\n'})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(before, after)

    def test_bb_readiness_python_with_inert_process_and_http_observations(self):
        policy = (ROOT / 'lib/setup-policy.bash').read_text()
        payload = policy.split("<<'SETUP_READONLY_BB_PY'\n", 1)[1].split('\nSETUP_READONLY_BB_PY', 1)[0]
        tree = ast.parse(payload)
        selected = [node for node in tree.body if isinstance(node, (ast.Import, ast.ImportFrom, ast.FunctionDef))]
        for node in selected:
            if isinstance(node, ast.FunctionDef):
                self.assertFalse(node.decorator_list or node.args.defaults or node.returns)
        namespace = {}
        exec(compile(ast.Module(body=selected, type_ignores=[]), '<readiness definitions>', 'exec'), namespace)
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            package = home / '.local/share/mise/installs/node/24.20.0/lib/node_modules/bb-app'
            binary = package.parents[2] / 'bin/bb-app'
            binary.parent.mkdir(parents=True)
            binary.write_text('inert identity; never execute')
            for relative, value in {'.config/setup-bb-server/package-owner': str(package), '.bb/host-id': 'fixture-host'}.items():
                path = home / relative; path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(value); path.chmod(0o600)
            process = Path('/proc/43210')
            real_stat, real_read = Path.stat, Path.read_bytes
            def metadata(path, *args, **kwargs):
                if str(path).startswith('/proc/'):
                    self.assertEqual(path, process)
                    return SimpleNamespace(st_uid=os.getuid())
                return real_stat(path, *args, **kwargs)
            def read(path):
                if str(path).startswith('/proc/'):
                    self.assertEqual(path, process / 'cmdline')
                    return (str(binary) + '\0').encode()
                return real_read(path)
            def systemctl(command, **kwargs):
                self.assertEqual(command, ['/usr/bin/systemctl', '--user', 'show', 'setup-bb-app.service', '--property=MainPID', '--value'])
                return SimpleNamespace(stdout='43210\n')
            requests = []
            responses = {38886: {'ok': True, 'launchId': 'fixture-launch'}, 38887: {'connected': True, 'hostId': 'fixture-host', 'serverUrl': 'http://127.0.0.1:38886'}}
            case = self
            class Connection:
                def __init__(self, host, port, timeout):
                    case.assertEqual(host, '127.0.0.1'); case.assertEqual(timeout, 2)
                    self.port = port
                def request(self, method, endpoint):
                    requests.append((self.port, method, endpoint))
                def getresponse(self):
                    return SimpleNamespace(status=200, read=lambda limit: json.dumps(responses[self.port]).encode())
                def close(self): pass
            with patch.object(namespace['subprocess'], 'run', systemctl), patch.object(Path, 'stat', metadata), patch.object(Path, 'read_bytes', read), patch.object(namespace['http'].client, 'HTTPConnection', Connection):
                namespace['readiness'](home)
                self.assertEqual(requests, [(38886, 'GET', '/health'), (38887, 'GET', '/status')])
                responses[38887]['connected'] = False
                with self.assertRaises(ValueError): namespace['readiness'](home)
                requests.clear()
                credential = home / '.bb/host-id'
                credential.unlink(); credential.symlink_to(home / 'outside')
                with self.assertRaises(OSError): namespace['readiness'](home)
                self.assertFalse(requests)

    @unittest.skipUnless(PWSH, 'Set PWSH_BIN for actual PowerShell fixtures')
    def test_powershell_dotenv_and_native_platform_gate(self):
        policy = (ROOT / 'lib/setup-policy.ps1').read_text()
        self.assertNotIn('$env:OS', policy)
        # Model a native Windows platform; Get-Acl throws before WindowsIdentity
        # is needed. This proves the branch, not native ACL implementation behavior.
        self.assertEqual(policy.count('[Environment]::OSVersion.Platform'), 1)
        windows_policy = policy.replace('[Environment]::OSVersion.Platform', '[PlatformID]::Win32NT')
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            (home / '.env.local').write_text('BB_SERVER=1  # Opt in to a persistent bb server (Ubuntu only)\nMACHINE_TYPE=physical  # Override VPS/physical detection when needed\nGH_TOKEN="credential # quoted" # comment\nZAI_API_KEY=credential#unquoted\n')
            script = home / 'fixture.ps1'
            script.write_text("$ErrorActionPreference='Stop'\n" + windows_policy + '''
Read-SetupEnvironment
if ($env:BB_SERVER -ne '1' -or $env:MACHINE_TYPE -ne 'physical' -or $env:GH_TOKEN -ne 'credential # quoted' -or $env:ZAI_API_KEY -ne 'credential#unquoted') { throw 'Incorrect dotenv value' }
foreach ($invalid in @('GH_TOKEN="unterminated','GH_TOKEN="one"two','GH_TOKEN="one"#two','GH_TOKEN=two words','"GH_TOKEN"=value')) {
    [IO.File]::WriteAllText((Join-Path $env:USERPROFILE '.env.local'),$invalid)
    $rejected=$false
    try { Read-SetupEnvironment } catch { $rejected=$true }
    if (-not $rejected) { throw 'Malformed value accepted' }
}
function Get-Acl { param($LiteralPath,$ErrorAction) $script:Checks++; throw 'synthetic-acl-check' }
foreach ($spoof in @($null,'Linux','Windows_NT')) {
    $env:OS=$spoof; $script:Checks=0; $rejected=$false
    try { Assert-SetupSafeDirectory (Join-Path $env:USERPROFILE 'Code') }
    catch { if ($_.Exception.Message -ne 'synthetic-acl-check') { throw }; $rejected=$true }
    if (-not $rejected -or $script:Checks -ne 1) { throw 'Native ACL gate bypassed' }
}
Write-Output 'PASS: dotenv data and platform gate'
''')
            result = subprocess.run([PWSH, '-NoLogo', '-NoProfile', '-NonInteractive', '-File', str(script)],
                                    env=dict(os.environ, HOME=tmp, USERPROFILE=tmp), cwd=tmp, text=True, capture_output=True, timeout=20)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('PASS: dotenv', result.stdout)
            self.assertNotIn('credential', result.stdout + result.stderr)
            self.assertFalse((home / 'Code').exists())

    def test_maintenance_requires_argument_and_refuses_known_bb_context(self):
        result, _, _ = self.bash('setup_policy_init --maintenance && setup_require_maintenance fixture')
        self.assertEqual(result.returncode, 0, result.stderr)
        for key in ('BB_THREAD_ID', 'BB_ENVIRONMENT_ID', 'BB_TERMINAL_ID'):
            result, _, _ = self.bash('setup_policy_init --maintenance', environment={key: 'fixture'})
            self.assertEqual(result.returncode, 1)
            self.assertIn('refused', result.stdout)
        result, _, _ = self.bash('setup_policy_init --maintenance; setup_policy_init; setup_require_maintenance fixture')
        self.assertEqual(result.returncode, 75)
        result, _, _ = self.bash('setup_policy_init --not-a-flag')
        self.assertEqual(result.returncode, 1)

    def test_safe_creation_repeat_and_failed_inspection(self):
        result, before, after = self.bash('setup_policy_init; setup_safe_code_directory; setup_safe_code_directory')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('Applied:', result.stdout)
        self.assertIn('Verified current:', result.stdout)
        self.assertEqual(before, after)  # only an empty directory is added
        for code in ('printf keep > "$HOME/Code"', 'ln -s "$HOME/target" "$HOME/Code"',
                     'mkdir "$HOME/Code"; chmod 777 "$HOME/Code"'):
            result, _, after = self.bash(code + '\nsetup_safe_code_directory', {'target': 'preserve'})
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            self.assertEqual(after['target'], b'preserve')
            self.assertIn('Failed:', result.stdout)

    def test_health_reports_failure_without_recovery_or_false_current(self):
        for state, status in (('active', 0), ('failed', 1), ('inactive', 1)):
            code = '''systemctl() {
    [[ "$*" == '--user show setup-bb-app.service --property=LoadState,ActiveState,UnitFileState,Result' ]] || exit 99
    printf 'LoadState=loaded\\nActiveState=%s\\nUnitFileState=enabled\\nResult=success\\n' "$STATE"
}
setup_observe_systemd_service user setup-bb-app.service
'''
            result, before, after = self.bash(code, {'.bb/config.json': 'preserve'}, {'STATE': state})
            self.assertEqual(result.returncode, status, result.stdout + result.stderr)
            self.assertEqual(before, after)
            if status: self.assertNotIn('Verified current:', result.stdout)
        for response in ('return 1', "printf 'LoadState=unknown\\n'", "printf 'raw-secret\\n'"):
            result, _, _ = self.bash('systemctl() { ' + response + '; }; setup_observe_systemd_service user setup-bb-app.service')
            self.assertEqual(result.returncode, 1)
            self.assertNotIn('raw-secret', result.stdout + result.stderr)
        result, _, _ = self.bash('''systemctl() { printf 'LoadState=loaded\\nActiveState=inactive\\nUnitFileState=disabled\\nResult=success\\n'; }
setup_observe_systemd_service user setup-bb-app.service''')
        self.assertEqual(result.returncode, 0)
        self.assertNotIn('Verified current:', result.stdout)

    def test_macos_log_reservation_accepts_strict_bsd_template_and_preserves_transport(self):
        source = (ROOT / 'mac.sh').read_text()
        for name in BASH:
            self.assertEqual(function((ROOT / name).read_text(), 'start_setup_log'), function(source, 'start_setup_log'))
        helpers = '\n'.join(function(source, name) for name in ('start_setup_log', 'finish_setup_log', 'upload_log'))
        code = helpers + '''
SETUP_LOGGING_ACTIVE=0; SETUP_LOG_FILE=''; SETUP_LOG_TEE_PID=''
date() { printf '2026-09-29-123456\\n'; }
hostname() { printf 'offline-fixture\\n'; }
mktemp() {
    # Model BSD's trailing-X interface, not GNU's suffix extension.
    local template="${!#}"
    [[ "${template}" == *XXXXXX ]] || { echo 'BSD fixture: trailing Xs required' >&2; return 1; }
    /usr/bin/mktemp "$@"
}
curl() { printf '%s\\n' "$@" >> "$HOME/transport"; }
start_setup_log || exit 31
first="$SETUP_LOG_FILE"
printf 'first-log-body\\n'
finish_setup_log 0 || exit 32
start_setup_log || exit 33
second="$SETUP_LOG_FILE"
printf 'second-log-body\\n'
finish_setup_log 23
[[ $? == 23 ]] || exit 34
[[ "$first" != "$second" && "$first" == *.log && "$second" == *.log ]] || exit 35
[[ ! -L "$first" && ! -L "$second" && "$(stat -c '%h %a' "$first")" == '1 600' && "$(stat -c '%h %a' "$second")" == '1 600' ]] || exit 36
[[ "$(stat -c '%a' "${first%/*}")" == 700 && "$(stat -c '%a' "${second%/*}")" == 700 ]] || exit 40
grep -q first-log-body "$first" && ! grep -q second-log-body "$first" || exit 37
grep -q second-log-body "$second" || exit 38
[[ "$(grep -c 'https://logs.scowalt.com/upload?hostname=offline-fixture' "$HOME/transport")" == 2 ]] || exit 39
grep -Fxq -- "file=@$first" "$HOME/transport" && grep -Fxq -- "file=@$second" "$HOME/transport"
'''
        result, _, _ = self.bash(code)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_bash_log_reservation_refuses_existing_linked_and_hardlinked_candidates(self):
        source = (ROOT / 'mac.sh').read_text()
        helpers = '\n'.join(function(source, name) for name in ('start_setup_log', 'finish_setup_log'))
        for collision in ('regular', 'symlink', 'hardlink'):
            with self.subTest(collision=collision):
                code = helpers + '''
SETUP_LOGGING_ACTIVE=0; SETUP_LOG_FILE=''; SETUP_LOG_TEE_PID=''
upload_log() { echo forbidden > "$HOME/upload-ran"; }
mktemp() {
    local directory candidate
    [[ "$1" == -d && "${!#}" == *XXXXXX ]] || return 91
    directory=$(/usr/bin/mktemp "$@") || return 92
    candidate="${directory}/${directory##*/}.log"
    case "$COLLISION" in
        regular) cp "$HOME/protected" "$candidate" ;;
        symlink) ln -s "$HOME/protected" "$candidate" ;;
        hardlink) ln "$HOME/protected" "$candidate" ;;
    esac
    printf '%s\\n' "$directory"
}
if start_setup_log; then exit 93; fi
[[ -z "$SETUP_LOG_FILE" && "$SETUP_LOGGING_ACTIVE" == 0 ]] || exit 94
finish_setup_log 0
'''
                result, _, after = self.bash(code, {'protected': 'preserve-marker'}, {'COLLISION': collision})
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(after['protected'], b'preserve-marker')
                self.assertNotIn('upload-ran', after)
                candidates = [value for name, value in after.items() if name.endswith('.log')]
                self.assertEqual(candidates, [b'preserve-marker'])

    @unittest.skipUnless(PWSH, 'Set PWSH_BIN for real PowerShell wrapper fixtures')
    def test_powershell_logger_failure_continues_safe_work_without_unsafe_transport(self):
        for failure, maintenance in (('linked-directory', False), ('transcript', False), ('linked-directory', True), ('transcript', True), ('maintenance-task', True)):
            with self.subTest(failure=failure, maintenance=maintenance), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp); home = root / 'home'; home.mkdir()
                outside = root / 'protected'; outside.mkdir(); (outside / 'sentinel').write_text('preserve-marker')
                if failure == 'linked-directory':
                    logs = home / '.local/log/machine-setup'; logs.parent.mkdir(parents=True)
                    logs.symlink_to(outside, target_is_directory=True)
                script = root / 'fixture.ps1'
                script.write_text('''param([string]$SourcePath, [string]$Failure, [string]$MaintenanceCase)
$ErrorActionPreference='Stop'
$tokens=$null; $errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile($SourcePath,[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw 'Source parse failure' }
$required=@('Initialize-SetupPolicy','Write-SetupDeferred','Assert-SetupMaintenance','Read-SetupEnvironment','ConvertFrom-SetupEnvironmentValue','Assert-SetupSafeDirectory','Invoke-SetupSafeTasks','Complete-SetupPolicy','Test-EnvLocalFlag','Assert-HeadlessUnsupported','Get-SetupLogDirectory','Assert-SetupLogPath','Initialize-WindowsEnvironment','Complete-SetupLog')
$selected=@($ast.EndBlock.Statements | Where-Object { $_ -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $_.Name -in $required })
if ($selected.Count -ne $required.Count) { throw 'Incomplete function selection' }
foreach ($definition in $selected) {
    $text=$definition.Extent.Text.Replace('function Complete-SetupLog {','function Complete-SetupLogFixtureCore {')
    . ([scriptblock]::Create($text))
}
$script:Services=0; $script:Reboots=0; $script:Finalized=0; $script:Starts=0; $script:Stops=0; $script:Uploads=0; $script:Pending=0; $script:MaintenanceCalls=0
function Write-Message { param($Message) Write-Host $Message }
function Write-Success { param($Message) Write-Host $Message }
function Write-Warning { param($Message) Write-Host $Message }
function Write-Error { param($Message) Write-Host $Message }
function Write-Debug { param($Message) }
function Write-Section { param($Message) }
function Get-Service { [CmdletBinding()]param($Name) $script:Services++; @() }
function Test-PendingReboot { $script:Reboots++ }
function Invoke-PendingSetupLogUploads { $script:Pending++ }
function Start-Transcript {
    param($Path,[switch]$NoClobber,$ErrorAction)
    $script:Starts++
    if (-not $NoClobber) { throw 'Missing no-clobber safeguard' }
    $file=[IO.File]::Open($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try { $bytes=[Text.Encoding]::UTF8.GetBytes('partial-fixture-transcript'); $file.Write($bytes,0,$bytes.Length) } finally { $file.Dispose() }
    if ($Failure -eq 'transcript') { throw 'synthetic-transcript-failure' }
}
function Stop-Transcript { param($ErrorAction) $script:Stops++ }
function Upload-Log { if (-not $script:SetupLogClosed) { throw 'Attempted active-log upload' }; $script:Uploads++ }
function Complete-SetupLog { $script:Finalized++; Complete-SetupLogFixtureCore }
function Invoke-WindowsSetupTasks { Assert-SetupMaintenance 'fixture caller'; $script:MaintenanceCalls++; throw 'synthetic-maintenance-task-failure' }
$maintenance=$MaintenanceCase -eq '1'
$caught=$null
try { Initialize-WindowsEnvironment -Maintenance:$maintenance } catch { $caught=$_ }
if (-not $caught) { throw 'Logger/task failure was swallowed' }
if ($script:Finalized -ne 1) { throw 'Finalization was not exactly once' }
if ($script:SetupMaintenanceAuthorized -or $script:SetupPolicyReady) { throw 'Authorization escaped invocation' }
if ($Failure -eq 'maintenance-task') {
    if ($caught.Exception.Message -ne 'synthetic-maintenance-task-failure' -or $script:MaintenanceCalls -ne 1 -or $script:Stops -ne 1 -or $script:Uploads -ne 1) { throw 'Maintenance failure or finalization changed' }
} else {
    if ($script:MaintenanceCalls -or $script:Stops -or $script:Uploads) { throw 'Failed logger reached forbidden work/transport' }
    if ($script:SetupLogFile -or $script:SetupTranscriptStarted -or $script:SetupLogClosed) { throw 'Failed logger retained uploadable state' }
    if ($Failure -eq 'linked-directory') {
        if ($caught.Exception.Message -ne 'Linked setup log path' -or $script:Starts -or $script:Pending) { throw 'Unsafe directory reached logger' }
    } elseif ($caught.Exception.Message -ne 'synthetic-transcript-failure' -or $script:Starts -ne 1 -or $script:Pending -ne 1) { throw 'Transcript failure was replaced' }
}
if ($maintenance) {
    if ($script:Services -or $script:Reboots -or [IO.Directory]::Exists((Join-Path $env:USERPROFILE 'Code'))) { throw 'Maintenance path changed after failure' }
} else {
    if ($script:Services -ne 2 -or $script:Reboots -ne 1 -or -not [IO.Directory]::Exists((Join-Path $env:USERPROFILE 'Code')) -or -not $script:SetupPolicyDeferred -or -not $script:SetupPolicyFailed) { throw 'Independent safe work or failure summary was skipped' }
}
Write-Output 'PASS: original error preserved; finalization exactly once'
exit 23
''')
                result = subprocess.run([PWSH, '-NoLogo', '-NoProfile', '-NonInteractive', '-File', str(script), str(ROOT / 'win.ps1'), failure, str(int(maintenance))],
                                        env=dict(os.environ, HOME=str(home), USERPROFILE=str(home), USERNAME='scowalt'), cwd=tmp,
                                        capture_output=True, text=True, timeout=25)
                self.assertEqual(result.returncode, 23, result.stdout + result.stderr)
                self.assertEqual({p.name: p.read_bytes() for p in outside.iterdir()}, {'sentinel': b'preserve-marker'})
                if not maintenance:
                    self.assertIn('Maintenance pending', result.stdout)
                    self.assertNotIn('Safe work completed;', result.stdout)
                if failure == 'transcript':
                    self.assertEqual([p.read_bytes() for p in home.rglob('*.log')], [b'partial-fixture-transcript'])

    def test_mixed_results_and_failure_are_not_erased_by_defer(self):
        for failure in (False, True):
            code = 'setup_policy_init; setup_policy_defer tools\n'
            if failure: code += "setup_policy_failure 'synthetic inspection' || true\n"
            code += 'setup_policy_summary 0'
            result, _, _ = self.bash(code)
            self.assertEqual(result.returncode, int(failure))
            self.assertIn('pending', result.stdout)
            self.assertIn('Update availability was not checked', result.stdout)
            if failure: self.assertNotIn('Safe work completed;', result.stdout)

    @unittest.skipUnless(PWSH, 'Set PWSH_BIN for actual PowerShell fixtures')
    def test_powershell_policy_and_real_default_caller(self):
        source = (ROOT / 'win.ps1').read_text()
        policy = (ROOT / 'lib/setup-policy.ps1').read_text()
        fn = lambda name: re.search(rf'^function {name} .*?^}}', source, re.M | re.S)[0]
        with tempfile.TemporaryDirectory() as tmp:
            script = Path(tmp) / 'fixture.ps1'
            script.write_text("$ErrorActionPreference='Stop'\n" + policy + '''
function Write-Message { param($Message) Write-Host $Message }
function Write-Success { param($Message) Write-Host $Message }
function Write-Warning { param($Message) Write-Host $Message }
function Write-Error { param($Message) Write-Host $Message }
function Write-Debug { param($Message) }
function Write-Section { param($Message) }
function Get-Service { @() }
function Test-PendingReboot { Write-Host 'reboot' }
function Get-SetupLogDirectory { return (Join-Path $env:USERPROFILE 'log') }
function Assert-SetupLogPath { param($Path, [switch]$AllowMissing) }
function Invoke-PendingSetupLogUploads { }
function Start-Transcript { param($Path, [switch]$NoClobber, $ErrorAction) }
function Complete-SetupLog { Write-Host 'finalized' }
function Invoke-WindowsSetupTasks { throw 'FORBIDDEN maintenance caller' }
''' + fn('Test-EnvLocalFlag') + '\n' + fn('Assert-HeadlessUnsupported') + '\n' + fn('Initialize-WindowsEnvironment') + '''
Initialize-WindowsEnvironment
if ($script:SetupMaintenanceAuthorized) { throw 'authorization escaped invocation' }
''')
            result = subprocess.run([PWSH, '-NoLogo', '-NoProfile', '-File', str(script)], cwd=tmp,
                                    env={'PATH': os.environ['PATH'], 'HOME': tmp, 'USERPROFILE': tmp,
                                         'USERNAME': 'fixture', 'SETUP_MAINTENANCE_AUTHORIZED': '1'},
                                    capture_output=True, text=True, timeout=20)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('maintenance pending', result.stdout)
            self.assertIn('reboot', result.stdout)
            self.assertEqual(result.stdout.count('finalized'), 1)
            self.assertNotIn('FORBIDDEN', result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main(verbosity=2)
