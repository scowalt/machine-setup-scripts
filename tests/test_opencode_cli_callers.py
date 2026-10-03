"""Contract v8: real installer/wrappers/callers preserve foreign copies and controlled selection failures."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
BASH = ('mac.sh', 'ubuntu.sh', 'wsl.sh', 'pi.sh', 'bazzite.sh')
PWSH = os.environ.get('PWSH_BIN') or shutil.which('pwsh')

DIAGNOSTICS = [(f'opencode-cli:download-failed:{operation}:http-{status}', 1,
                f'OpenCode CLI download failed (operation={operation}, HTTP={status}).')
               for operation in ('latest-release', 'package-index', 'package-version', 'artifact-download', 'download')
               for status in ('406', 'unknown')]
DIAGNOSTICS += [(result, status, None) for result, status in [
    ('opencode-cli:download-failed:package-version:http-406', 0),
    ('opencode-cli:download-failed:SECRET:http-406', 1),
    ('opencode-cli:download-failed:package-version:http-099', 1),
    ('opencode-cli:download-failed:package-version:http-600', 1),
    ('opencode-cli:download-failed:package-version:http-0406', 1),
    ('opencode-cli:download-failed:package-version:http-406 SECRET', 1),
    ('opencode-cli:download-failed:package-version:http-406\r', 1),
    ('opencode-cli:download-failed:package-version:http-406\nSECRET', 1),
    ('SECRET\nopencode-cli:download-failed:package-version:http-406', 1),
    ('OPENCODE-CLI:download-failed:package-version:http-406', 1),
    ('opencode-cli:recovery-required', 1),
]]

DIAGNOSTICS += [(f'opencode-cli:policy-failed:{operation}:{reason}', 1,
                 f'OpenCode CLI blocked (operation={operation}, reason={reason}).')
                for operation, reason in [('homebrew-preflight', 'brew-path'), ('homebrew-preflight', 'brew-snapshot-changed'),
                                          ('homebrew-preflight', 'brew-command'), ('homebrew-preflight', 'brew-origin'),
                                          ('homebrew-preflight', 'brew-readiness'), ('homebrew-preflight', 'native-EACCES'),
                                          ('installation', 'pinned'), ('installation', 'unverified-copy'), ('installation', 'native-ENOENT'),
                                          ('setup-selection', 'foreign-command'), ('setup-selection', 'command-conflict'),
                                          ('fresh-shell-selection', 'command-conflict'), ('fresh-shell-selection', 'selection-unverified')]]
DIAGNOSTICS += [(result, status, None) for result, status in [
    ('opencode-cli:policy-failed:homebrew-preflight:brew-path', 0),
    ('opencode-cli:policy-failed:homebrew-preflight:brew-process-churn', 0),
    ('opencode-cli:policy-failed:homebrew-preflight:brew-process-churn\nSECRET', 1),
    ('opencode-cli:policy-failed:SECRET:brew-path', 1),
    ('opencode-cli:policy-failed:homebrew-preflight:SECRET', 1),
    ('opencode-cli:policy-failed:homebrew-preflight:native-SECRET', 1),
    ('opencode-cli:policy-failed:homebrew-preflight:brew-path\nSECRET', 1),
    ('opencode-cli:policy-failed:homebrew-preflight:brew-path\r', 1),
    ('opencode-cli:policy-failed:homebrew-preflight:brew-path SECRET', 1),
    ('opencode-cli:policy-failed:homebrew-preflight:BREW-PATH', 1),
]]

RECOVERY_RESULTS = {'opencode-cli:recovery-required', 'opencode-cli:recovery-required:failed',
                    'opencode-cli:recovery-required:policy-failed:fresh-shell-selection:command-conflict'}
DIAGNOSTICS += [
    ('opencode-cli:recovery-required:policy-failed:fresh-shell-selection:command-conflict', 1,
     'OpenCode CLI blocked (operation=fresh-shell-selection, reason=command-conflict).'),
    ('opencode-cli:recovery-required:failed', 1, None),
    ('opencode-cli:recovery-required:policy-failed:fresh-shell-selection:SECRET', 1, None),
    ('opencode-cli:recovery-required:policy-failed:fresh-shell-selection:command-conflict\nSECRET', 1, None),
]

# Obsolete helper replies are unrecognized failures, even with a nonzero status.
DIAGNOSTICS += [(f'opencode-cli:policy-failed:homebrew-preflight:{reason}', status, None)
                for reason in ('brew-group-shared', 'brew-identity-source', 'brew-acl-present', 'brew-acl-unverified',
                               'brew-proof-unverified', 'brew-proof-tool', 'brew-process-churn')
                for status in (0, 1)]


def function(source, name):
    return re.search(rf'^{name}\(\) \{{\n.*?^\}}', source, re.M | re.S)[0]


class Callers(unittest.TestCase):
    def exercise(self, source, code, env=None):
        with tempfile.TemporaryDirectory() as temp:
            home = Path(temp)
            node = home / 'node'
            node.write_text('''#!/bin/bash
[[ -z "${NODE_OPTIONS:-}" && -z "${NODE_PATH:-}" ]] || exit 90
if [[ "$1" == -e ]]; then exit "${MOCK_NODE_PREREQUISITE:-0}"; fi
if [[ "${MOCK_SELECTION_INPUTS:-0}" == 1 ]]; then
    [[ "${SETUP_OPENCODE_SHELL:-}" == "${HOME}/fish" && "${SETUP_OPENCODE_HASHED:-}" == "${HOME}/foreign/opencode" ]] || exit 91
fi
while IFS= read -r line; do :; done
printf '%s\\n' "${MOCK_RESULT:-opencode-cli:installed}"
printf 'SECRET stderr\\n' >&2
exit "${MOCK_STATUS:-0}"
''')
            node.chmod(0o700)
            script = ('set -eu\nprint_success() { echo "success:$*"; }\n'
                      'print_warning() { echo "warning:$*"; }\nprint_error() { echo "error:$*"; }\n'
                      + source + '\n' + code)
            return subprocess.run(['bash', '-c', script], cwd=temp, text=True, capture_output=True, timeout=20,
                                  env={'PATH': temp + ':/usr/bin:/bin', 'HOME': temp, **(env or {})})

    def test_wrappers_and_shared_policy(self):
        blocks = []
        for name in BASH:
            text = (ROOT / name).read_text()
            blocks.append(text.split('# BEGIN GENERATED OPENCODE CLI\n')[1].split('# END GENERATED OPENCODE CLI')[0])
            helper = blocks[-1].split('# Keep retained legacy Homebrew')[0]
            for result, status in [('opencode-cli:installed', 0), ('opencode-cli:migrated', 0),
                                   ('opencode-cli:current', 0), ('opencode-cli:newer', 0),
                                   ('opencode-cli:unsupported', 0), ('unexpected-secret-output', 0),
                                   ('opencode-cli:failed', 1)]:
                with self.subTest(script=name, result=result):
                    run = self.exercise(helper, 'install_opencode_cli', {'MOCK_RESULT': result, 'MOCK_STATUS': str(status),
                                                                        'NODE_OPTIONS': '--invalid', 'NODE_PATH': '/invalid'})
                    self.assertEqual(run.returncode, int(bool(status or result.startswith('unexpected'))), run.stdout + run.stderr)
                    self.assertNotIn('unexpected-secret-output', run.stdout)
            for result, status, diagnostic in DIAGNOSTICS:
                with self.subTest(script=name, diagnostic=result):
                    run = self.exercise(helper, 'install_opencode_cli', {'MOCK_RESULT': result, 'MOCK_STATUS': str(status)})
                    self.assertEqual(run.returncode, 1, run.stdout + run.stderr)
                    self.assertNotIn('SECRET', run.stdout + run.stderr)
                    if diagnostic:
                        self.assertIn(diagnostic, run.stdout)
                    else:
                        self.assertNotIn('OpenCode CLI download failed (', run.stdout)
                        self.assertNotIn('OpenCode CLI blocked (', run.stdout)
                    self.assertEqual('rollback needs manual recovery' in run.stdout, result in RECOVERY_RESULTS)
            for extra in [{'MOCK_NODE_PREREQUISITE': '1'}, {}]:
                setup = 'macos_existing_prerequisites() { return 1; }\n' if not extra else ''
                run = self.exercise(setup + helper, 'install_opencode_cli', extra)
                self.assertEqual(run.returncode, 1, run.stdout)
        self.assertTrue(all(block == blocks[0] for block in blocks))

    def test_setup_wrapper_supplies_native_shell_and_actual_cached_selection(self):
        helper = (ROOT / 'lib/opencode-cli.bash').read_text().split('# Keep retained legacy Homebrew')[0]
        before = '''
mkdir -p "${HOME}/foreign"
printf '#!/bin/sh\\nexit 99\\n' > "${HOME}/fish"
chmod 700 "${HOME}/fish"
hash -p "${HOME}/foreign/opencode" opencode
'''
        run = self.exercise(helper, before + 'install_opencode_cli', {
            'MOCK_SELECTION_INPUTS': '1', 'SETUP_OPENCODE_SHELL': 'SECRET', 'SETUP_OPENCODE_HASHED': 'SECRET'})
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
        self.assertNotIn('SECRET', run.stdout + run.stderr)

    def test_setup_alias_or_function_is_a_controlled_unexecuted_conflict(self):
        helper = (ROOT / 'lib/opencode-cli.bash').read_text().split('# Keep retained legacy Homebrew')[0]
        for conflict in ['opencode() { echo SECRET; }', "shopt -s expand_aliases; alias opencode='echo SECRET'"]:
            run = self.exercise(helper, conflict + '\ninstall_opencode_cli')
            self.assertEqual(run.returncode, 1, run.stdout + run.stderr)
            self.assertIn('OpenCode CLI blocked (operation=setup-selection, reason=command-conflict).', run.stdout)
            self.assertNotIn('SECRET', run.stdout + run.stderr)

    def test_real_caller_aggregation_independent_tail_and_log_finalization(self):
        for name in BASH:
            source = (ROOT / name).read_text()
            main = function(source, 'run_setup_tasks')
            call = re.search(r'^    install_opencode_cli \|\| _setup_had_errors=1$', main, re.M)[0]
            self.assertLess(main.index(call), main.index('elif install_pi_cli; then'))
            tail = main[main.index('    check_pending_reboot'):]
            if name == 'mac.sh':
                tail = tail.replace('    macos_clt_summary', '    :')
            # Preserve the real final aggregation and main log-finalization seams.
            fixture = ('install_opencode_cli() { return 1; }\ncheck_pending_reboot() { echo independent-reboot; }\n'
                       'print_message() { :; }; print_debug() { :; }; print_section() { :; }\n'
                       'start_setup_log() { echo log-started; }; finish_setup_log() { echo "log-finalized:$1"; return "$1"; }\n'
                       'run_setup_tasks() { local _setup_had_errors=0;\n' + call + '\n' + tail + '\n' + function(source, 'main'))
            run = self.exercise(fixture, 'main', {'GREEN': '', 'BOLD': '', 'NC': '', 'GRAY': ''})
            self.assertEqual(run.returncode, 1, run.stdout + run.stderr)
            self.assertIn('independent-reboot', run.stdout)
            self.assertIn('log-finalized:1', run.stdout)

    def test_real_installer_wrapper_caller_and_finalization_with_two_accounts(self):
        native_node = shutil.which('node')
        self.assertTrue(native_node, 'existing native Node required')
        driver = ROOT / 'tests/fixtures/opencode-cli-driver.cjs'
        for name in BASH:
            source = (ROOT / name).read_text()
            wrapper = source.split('# BEGIN GENERATED OPENCODE CLI\n')[1].split('# Keep retained legacy Homebrew')[0]
            main = function(source, 'run_setup_tasks')
            call = re.search(r'^    install_opencode_cli \|\| _setup_had_errors=1$', main, re.M)[0]
            tail = main[main.index('    check_pending_reboot'):]
            if name == 'mac.sh':
                tail = tail.replace('    macos_clt_summary', '    :')
            fixture = ('print_success() { echo "success:$*"; }; print_warning() { echo "warning:$*"; }; print_error() { echo "error:$*"; }\n'
                       'print_message() { :; }; print_debug() { :; }; print_section() { :; }\n'
                       'check_pending_reboot() { echo independent-reboot; }; later_success() { echo later-success; return 0; }\n'
                       'start_setup_log() { echo log-started; }; finish_setup_log() { echo "log-finalized:$1"; return "$1"; }\n'
                       + wrapper + '\nrun_setup_tasks() { local _setup_had_errors=0;\n' + call + '\nlater_success\n' + tail + '\n' + function(source, 'main') + '\nmain\n')
            for outcome in ('lower', 'shadowed', 'fresh', 'cleanup'):
                with self.subTest(script=name, outcome=outcome), tempfile.TemporaryDirectory() as temp:
                    root = Path(temp); home = root / 'account'; foreign = root / 'foreign'; tools = root / 'tools'
                    for directory in (home, foreign, tools):
                        directory.mkdir(mode=0o700)
                    foreign_command = foreign / 'opencode'
                    foreign_command.write_text('INERT foreign command SECRET')
                    foreign_command.chmod(0o700)
                    before = foreign_command.stat()
                    node = tools / 'node'
                    node.write_text('#!/bin/sh\nexec "$FIXTURE_NODE" "$FIXTURE_DRIVER" "$@"\n')
                    node.chmod(0o700)
                    local_bin = str(home / '.local/bin')
                    paths = [str(foreign), local_bin] if outcome == 'shadowed' else [local_bin, str(foreign)]
                    run = subprocess.run(['bash', '-c', fixture], cwd=home, text=True, capture_output=True, timeout=30,
                                         env={'PATH': ':'.join([str(tools), *paths, '/usr/bin', '/bin']), 'HOME': str(home),
                                              'FIXTURE_NODE': native_node, 'FIXTURE_DRIVER': str(driver), 'FIXTURE_FOREIGN': str(foreign),
                                              'FIXTURE_OUTCOME': outcome, 'BOLD': '', 'GREEN': '', 'GRAY': '', 'NC': ''})
                    self.assertEqual(run.returncode, 0 if outcome == 'lower' else 1, run.stdout + run.stderr)
                    self.assertIn('later-success', run.stdout)
                    self.assertIn('independent-reboot', run.stdout)
                    self.assertIn('log-finalized:' + ('0' if outcome == 'lower' else '1'), run.stdout)
                    if outcome != 'lower':
                        operation, reason = ('setup-selection', 'foreign-command') if outcome == 'shadowed' else ('fresh-shell-selection', 'command-conflict')
                        self.assertIn(f'operation={operation}, reason={reason}', run.stdout)
                    self.assertEqual('rollback needs manual recovery' in run.stdout, outcome == 'cleanup')
                    self.assertNotIn('SECRET', run.stdout + run.stderr)
                    after = foreign_command.stat()
                    self.assertEqual((after.st_ino, after.st_mode, after.st_mtime_ns), (before.st_ino, before.st_mode, before.st_mtime_ns))
                    self.assertEqual(foreign_command.read_text(), 'INERT foreign command SECRET')
                    self.assertEqual((home / '.local/bin/opencode').exists(), outcome == 'lower')

    def test_brew_upgrade_protects_legacy_records_and_preserves_pins(self):
        text = (ROOT / 'mac.sh').read_text()
        helper = re.search(r'^opencode_guarded_brew_upgrade\(\) \(\n.*?^\)', text, re.M | re.S)[0]
        stub = '''
brew() {
  echo "$*" >> "${HOME}/calls"
  case "$*" in
    'list --formula -1') echo opencode ;;
    'list --pinned') echo "${MOCK_PIN:-}" ;;
    upgrade) return "${MOCK_UPGRADE:-0}" ;;
  esac
}
'''
        for pinned in ('', 'opencode'):
            for status in ('0', '1'):
                run = self.exercise(stub + helper,
                                    'result=0; opencode_guarded_brew_upgrade || result=$?; /bin/cat "${HOME}/calls"; exit "$result"',
                                    {'MOCK_PIN': pinned, 'MOCK_UPGRADE': status})
                self.assertEqual(run.returncode, int(status), run.stderr)
                self.assertEqual('\npin opencode\n' in run.stdout, not bool(pinned))
                self.assertEqual('\nunpin opencode\n' in run.stdout, not bool(pinned))

    def test_apt_upgrade_guard_preserves_distro_owned_and_uncertain_commands(self):
        helper = function((ROOT / 'ubuntu.sh').read_text(), 'opencode_apt_upgrade_safe')
        stub = '''
type() { if [[ "$*" == '-ap opencode' ]]; then echo /fixture/opencode; else builtin type "$@"; fi; }
readlink() { echo /fixture/native-opencode; }
dpkg-query() { return "${MOCK_OWNER}"; }
'''
        for status in ('0', '1', '2'):
            run = self.exercise(stub + helper, 'opencode_apt_upgrade_safe', {'MOCK_OWNER': status})
            self.assertEqual(run.returncode, 0 if status == '1' else 1, run.stdout + run.stderr)
        for name in ('ubuntu.sh', 'pi.sh', 'wsl.sh'):
            text = (ROOT / name).read_text()
            caller = function(text, 'update_packages' if name == 'wsl.sh' else 'update_dependencies')
            self.assertRegex(caller, r'if opencode_apt_upgrade_safe; then\n[^\n]+upgrade --with-new-pkgs')
            with self.subTest(script=name):
                before = '''
print_message() { :; }; print_warning() { :; }; print_error() { :; }
can_sudo() { return 0; }; dpkg() { return 1; }; apt-mark() { return 0; }
brew() { return 0; }; opencode_guarded_brew_upgrade() { return 0; }
sudo() { if [[ "$*" == *upgrade* ]]; then echo unexpected-upgrade; return 90; fi; return 0; }
opencode_apt_upgrade_safe() { return 1; }
'''
                run = self.exercise(before + caller, 'update_packages' if name == 'wsl.sh' else 'update_dependencies')
                self.assertEqual(run.returncode, 1, run.stdout + run.stderr)
                self.assertNotIn('unexpected-upgrade', run.stdout)

    def test_headless_guards_remain_before_any_provisioning(self):
        wsl = (ROOT / 'wsl.sh').read_text()
        main = function(wsl, 'run_setup_tasks')
        self.assertLess(main.index('fail_unsupported_headless'), main.index('install_opencode_cli'))
        gate = function(wsl, 'env_local_flag_is_one') + '\n' + function(wsl, 'fail_unsupported_headless')
        run = self.exercise(gate, 'fail_unsupported_headless || exit $?; echo unexpected-provisioning', {'HEADLESS': '1'})
        self.assertNotEqual(run.returncode, 0)
        self.assertNotIn('unexpected-provisioning', run.stdout)
        win = (ROOT / 'win.ps1').read_text().split('function Invoke-WindowsSetupTasks {')[1]
        self.assertLess(win.index('Assert-HeadlessUnsupported'), win.index('New-TokenPlaceholders'))
        self.assertLess(win.index('New-TokenPlaceholders'), win.index('Install-OpenCodeCli'))

    @unittest.skipUnless(PWSH, 'No existing PWSH_BIN/pwsh: PowerShell wrapper execution not claimed')
    def test_powershell_wrapper_result_validation_and_environment_restoration(self):
        block = (ROOT / 'win.ps1').read_text().split('# BEGIN GENERATED OPENCODE CLI\n')[1].split('# END GENERATED OPENCODE CLI')[0]
        wrapper = 'function Install-OpenCodeCli {' + block.split('function Install-OpenCodeCli {', 1)[1]
        with tempfile.TemporaryDirectory() as home:
            fake = Path(home) / 'node-fixture.ps1'
            fake.write_text('if ($args[0] -eq "-e") { $global:LASTEXITCODE=0; return }\n'
                            'if ($env:MOCK_SELECTION_INPUTS -eq "1" -and ($env:SETUP_OPENCODE_SHELL -notmatch "[\\\\/]pwsh.exe$" -or $env:SETUP_OPENCODE_HASHED -or $env:SETUP_OPENCODE_FRESH_PATH -eq "SECRET")) { $global:LASTEXITCODE=91; return }\n'
                            '$global:OpenCodeCompleted=$true\n$input | Out-Null\nWrite-Output ([regex]::Split($env:MOCK_RESULT, "`n"))\n'
                            'Write-Error "SECRET stderr" -ErrorAction Continue\n$global:LASTEXITCODE=[int]$env:MOCK_STATUS\n')
            harness = Path(home) / 'wrapper.ps1'
            harness.write_text('''$ErrorActionPreference='Stop'
function Write-Success { param($Message) Write-Host $Message }
function Write-Warning { param($Message) Write-Host $Message }
function Get-Command { param($Name, $CommandType, $ErrorAction)
    if ($Name -eq 'node') { [pscustomobject]@{Source=$env:MOCK_NODE} }
    if ($Name -eq 'opencode' -and $global:OpenCodeCompleted) {
        $selected = Join-Path $env:USERPROFILE '.local/bin/opencode.exe'
        if ($env:MOCK_SELECTED -eq 'foreign') { $selected = 'C:/SECRET/other/opencode.exe' }
        [pscustomobject]@{Source=$selected; CommandType=$(if ($env:MOCK_SELECTED -eq 'function') { 'Function' } else { 'Application' })}
    }
}
function Test-OpenCodeCliAcl { param($HomePath) $true }
$env:PROCESSOR_ARCHITECTURE='AMD64'
$env:PROCESSOR_ARCHITEW6432=$null
$env:NODE_OPTIONS='fixture-original'
$env:SETUP_OPENCODE_SHELL='SECRET'
$env:SETUP_OPENCODE_HASHED='SECRET'
$env:SETUP_OPENCODE_FRESH_PATH='SECRET'
''' + wrapper + '''
$result=Install-OpenCodeCli
if ($env:NODE_OPTIONS -ne 'fixture-original' -or $env:SETUP_OPENCODE_SHELL -ne 'SECRET' -or
    $env:SETUP_OPENCODE_HASHED -ne 'SECRET' -or $env:SETUP_OPENCODE_FRESH_PATH -ne 'SECRET') { throw 'environment not restored' }
if ($result) { exit 0 } else { exit 1 }
''')
            cases = [('opencode-cli:installed', '0', 0, None), ('opencode-cli:newer', '0', 0, None),
                     ('opencode-cli:failed', '1', 1, None), ('unexpected-secret-output', '0', 1, None)]
            cases += [(result, str(status), 1, diagnostic) for result, status, diagnostic in DIAGNOSTICS]
            for result, status, expected, diagnostic in cases:
                run = subprocess.run([PWSH, '-NoProfile', '-NonInteractive', '-File', str(harness)], cwd=home,
                                     env={'PATH': os.environ['PATH'], 'HOME': home, 'USERPROFILE': home, 'MOCK_NODE': str(fake),
                                          'MOCK_RESULT': result, 'MOCK_STATUS': status,
                                          'MOCK_SELECTION_INPUTS': '1' if result == 'opencode-cli:installed' else '0'}, capture_output=True, text=True, timeout=20)
                self.assertEqual(run.returncode, expected, run.stdout + run.stderr)
                self.assertNotIn('unexpected-secret-output', run.stdout + run.stderr)
                self.assertNotIn('SECRET', run.stdout + run.stderr)
                if diagnostic:
                    self.assertIn(diagnostic, run.stdout)
                else:
                    self.assertNotIn('OpenCode CLI download failed (', run.stdout)
                    self.assertNotIn('OpenCode CLI blocked (', run.stdout)
                self.assertEqual('rollback needs manual recovery' in run.stdout, result in RECOVERY_RESULTS)
            for selected in ('foreign', 'function'):
                run = subprocess.run([PWSH, '-NoProfile', '-NonInteractive', '-File', str(harness)], cwd=home,
                                     env={'PATH': os.environ['PATH'], 'HOME': home, 'USERPROFILE': home, 'MOCK_NODE': str(fake),
                                          'MOCK_RESULT': 'opencode-cli:installed', 'MOCK_STATUS': '0', 'MOCK_SELECTED': selected},
                                     capture_output=True, text=True, timeout=20)
                self.assertEqual(run.returncode, 1, run.stdout + run.stderr)
                self.assertIn('OpenCode CLI blocked (operation=setup-selection, reason=command-conflict).', run.stdout)
                self.assertNotIn('SECRET', run.stdout + run.stderr)

    @unittest.skipUnless(PWSH, 'No existing PWSH_BIN/pwsh: native Windows/PowerShell execution not claimed')
    def test_real_powershell_installer_caller_and_finalization(self):
        native_node = shutil.which('node')
        self.assertTrue(native_node, 'existing native Node required')
        script = '''param([string]$SourcePath)
$ErrorActionPreference='Stop'
$tokens=$null; $errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile($SourcePath,[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw 'Fixture source parse failed' }
$definitions=@($ast.EndBlock.Statements | Where-Object { $_ -is [System.Management.Automation.Language.FunctionDefinitionAst] })
$selectedNames=@('Invoke-WindowsSetupTasks','Initialize-WindowsEnvironment','Install-OpenCodeCli')
foreach ($definition in $definitions) {
    if ($definition.Name -notin $selectedNames) { Set-Item -Path ('function:' + $definition.Name) -Value { $true } }
}
foreach ($name in $selectedNames) {
    $selected=@($definitions | Where-Object Name -eq $name)
    if ($selected.Count -ne 1) { throw 'Fixture selection failed' }
    . ([scriptblock]::Create($selected[0].Extent.Text))
}
function Write-Host { }
function Write-Warning { param($Message) [Console]::WriteLine($Message) }
function Write-Success { param($Message) [Console]::WriteLine($Message) }
function Write-Debug { }
function Get-SetupLogDirectory { Join-Path $env:USERPROFILE 'logs' }
function Assert-SetupLogPath { param($Path,[switch]$AllowMissing) }
function Invoke-PendingSetupLogUploads { }
function Start-Transcript { param($Path,[switch]$NoClobber,$ErrorAction) }
function Complete-SetupLog { [Console]::WriteLine('finalized') }
function Install-GiteaClient { [Console]::WriteLine('later-success'); $true }
function Test-PendingReboot { [Console]::WriteLine('reboot') }
function Get-Command { param($Name, $CommandType, $ErrorAction)
    if ($Name -eq 'node') { return [pscustomobject]@{Source=$env:FIXTURE_WRAPPER} }
    if ($Name -eq 'opencode') {
        $file=Join-Path $env:USERPROFILE '.local/bin/opencode.exe'
        if (Test-Path -LiteralPath $file) { [pscustomobject]@{Source=$file; CommandType='Application'} }
    }
}
$env:PROCESSOR_ARCHITECTURE='AMD64'; $env:PROCESSOR_ARCHITEW6432=$null
try { Initialize-WindowsEnvironment; exit 0 } catch {
    if ($_.Exception.Message -ne 'OpenCode CLI setup or upgrade preservation was incomplete.') { throw }
    [Console]::WriteLine('original-opencode-failure'); exit 1
}
'''
        for outcome in ('lower', 'shadowed', 'fresh', 'cleanup'):
            with self.subTest(outcome=outcome), tempfile.TemporaryDirectory() as temp:
                root = Path(temp); home = root / 'account'; foreign = root / 'foreign'
                home.mkdir(mode=0o700); foreign.mkdir(mode=0o700)
                foreign_command = foreign / 'opencode.exe'; foreign_command.write_text('INERT foreign SECRET'); foreign_command.chmod(0o700)
                before = foreign_command.stat()
                wrapper = root / 'node.ps1'
                wrapper.write_text('$input | & $env:FIXTURE_NODE $env:FIXTURE_DRIVER @args\n')
                harness = root / 'caller.ps1'; harness.write_text(script)
                paths = [str(foreign), str(home / '.local/bin')] if outcome == 'shadowed' else [str(home / '.local/bin'), str(foreign)]
                run = subprocess.run([PWSH, '-NoProfile', '-NonInteractive', '-File', str(harness), str(ROOT / 'win.ps1')], cwd=home,
                                     env={'PATH': ':'.join([*paths, '/usr/bin', '/bin']), 'HOME': str(home), 'USERPROFILE': str(home),
                                          'FIXTURE_NODE': native_node, 'FIXTURE_DRIVER': str(ROOT / 'tests/fixtures/opencode-cli-driver.cjs'),
                                          'FIXTURE_FOREIGN': str(foreign), 'FIXTURE_PLATFORM': 'win32', 'FIXTURE_OUTCOME': outcome,
                                          'FIXTURE_WRAPPER': str(wrapper), 'POWERSHELL_TELEMETRY_OPTOUT': '1'},
                                     capture_output=True, text=True, timeout=30)
                self.assertEqual(run.returncode, 0 if outcome == 'lower' else 1, run.stdout + run.stderr)
                self.assertIn('later-success', run.stdout); self.assertIn('reboot', run.stdout)
                self.assertEqual(run.stdout.splitlines().count('finalized'), 1)
                self.assertNotIn('SECRET', run.stdout + run.stderr)
                if outcome != 'lower':
                    self.assertIn('original-opencode-failure', run.stdout)
                    operation, reason = ('setup-selection', 'foreign-command') if outcome == 'shadowed' else ('fresh-shell-selection', 'command-conflict')
                    self.assertIn(f'operation={operation}, reason={reason}', run.stdout)
                self.assertEqual('rollback needs manual recovery' in run.stdout, outcome == 'cleanup')
                after = foreign_command.stat()
                self.assertEqual((after.st_ino, after.st_mode, after.st_mtime_ns), (before.st_ino, before.st_mode, before.st_mtime_ns))
                self.assertEqual(foreign_command.read_text(), 'INERT foreign SECRET')
                self.assertEqual((home / '.local/bin/opencode.exe').exists(), outcome == 'lower')

    @unittest.skipUnless(PWSH, 'No existing PWSH_BIN/pwsh: native Windows/PowerShell execution not claimed')
    def test_powershell_caller_aggregation(self):
        # Select the real task caller and logging wrapper by AST, replacing all
        # other setup definitions before either caller can run. No whole-file eval.
        script = '''param([string]$SourcePath)
$ErrorActionPreference='Stop'
$tokens=$null; $errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile($SourcePath,[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw 'Fixture source parse failed' }
$definitions=@($ast.EndBlock.Statements | Where-Object { $_ -is [System.Management.Automation.Language.FunctionDefinitionAst] })
$callers=@('Invoke-WindowsSetupTasks','Initialize-WindowsEnvironment')
foreach ($definition in $definitions) {
    if ($definition.Name -notin $callers) {
        Set-Item -Path ('function:' + $definition.Name) -Value { $true }
    }
}
foreach ($name in $callers) {
    $selected=@($definitions | Where-Object Name -eq $name)
    if ($selected.Count -ne 1) { throw 'Fixture caller selection failed' }
    . ([scriptblock]::Create($selected[0].Extent.Text))
}
function Write-Host { }
function Write-Warning { }
function Write-Debug { }
function Get-SetupLogDirectory { Join-Path $env:USERPROFILE 'logs' }
function Assert-SetupLogPath { param($Path,[switch]$AllowMissing) }
function Invoke-PendingSetupLogUploads { }
function Start-Transcript { param($Path,[switch]$NoClobber,$ErrorAction) }
function Complete-SetupLog { Write-Output finalized }
function Install-OpenCodeCli { $false }
function Install-GiteaClient { Write-Output independent }
function Test-PendingReboot { Write-Output reboot }
function Install-WingetUpdates { throw 'Blanket upgrade was not deferred' }
try { Initialize-WindowsEnvironment } catch {
    if ($_.Exception.Message -ne 'OpenCode CLI setup or upgrade preservation was incomplete.') { throw }
    Write-Output original-opencode-failure
    exit 1
}
'''
        with tempfile.TemporaryDirectory() as home:
            file = Path(home) / 'caller.ps1'
            file.write_text(script)
            run = subprocess.run([PWSH, '-NoProfile', '-NonInteractive', '-File', str(file), str(ROOT / 'win.ps1')], cwd=home,
                                 env={'PATH': os.environ['PATH'], 'HOME': home, 'USERPROFILE': home,
                                      'POWERSHELL_TELEMETRY_OPTOUT': '1'}, capture_output=True, text=True, timeout=20)
        self.assertEqual(run.returncode, 1, run.stdout + run.stderr)
        self.assertIn('independent', run.stdout)
        self.assertIn('reboot', run.stdout)
        self.assertEqual(run.stdout.splitlines().count('finalized'), 1)
        self.assertIn('original-opencode-failure', run.stdout)


if __name__ == '__main__':
    unittest.main()
