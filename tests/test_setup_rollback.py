import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

from extract_setup_fixture import validate_function

ROOT = Path(__file__).resolve().parents[1]
BASH = ('mac.sh', 'ubuntu.sh', 'pi.sh', 'bazzite.sh', 'wsl.sh')
PWSH = os.environ.get('PWSH_BIN')


def function(source, name):
    start = source.index(f'\n{name}() {{\n') + 1
    end = source.index('\n}\n', start) + 3
    block = source[start:end]
    validate_function(block)   
    return block


class Rollback(unittest.TestCase):
    def test_default_bash_wrappers_dispatch_normal_tasks_and_finalize_original_result(self):
        for name in BASH:
            source = (ROOT / name).read_text()
            for task_status, log_status in ((0, 0), (23, 0), (0, 1)):
                with self.subTest(script=name, task_status=task_status, log_status=log_status), tempfile.TemporaryDirectory() as tmp:
                    names = re.findall(r'^([A-Za-z_][A-Za-z_0-9]*)\(\) \{', source, re.M)
                    code = '\n'.join(f'{n}() {{ echo unexpected:{n}; return 99; }}' for n in names)
                    code += '''
start_setup_log() { echo log-start; return "$LOG_STATUS"; }
run_setup_tasks() { echo normal-tasks; return "$TASK_STATUS"; }
finish_setup_log() { echo "finalized:$1"; return "$1"; }
'''
                    code += function(source, 'main') + '\nmain\n'
                    result = subprocess.run(['/bin/bash', '-c', code], cwd=tmp, capture_output=True, text=True,
                                            env={'PATH': '/usr/bin:/bin', 'HOME': tmp, 'TASK_STATUS': str(task_status),
                                                 'LOG_STATUS': str(log_status), 'BB_THREAD_ID': 'inert-fixture'}, timeout=10)
                    self.assertEqual(result.returncode, task_status, result.stdout + result.stderr)
                    self.assertEqual(result.stdout.splitlines(), ['log-start', 'normal-tasks', f'finalized:{task_status}'])

    def test_group_writable_home_code_and_log_ancestors_keep_previous_behavior(self):
        for name in BASH:
            with self.subTest(script=name), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                home = root / 'home'
                home.mkdir(mode=0o775)
                home.chmod(0o775)   
                code_dir = home / 'Code'
                code_dir.mkdir()
                code_dir.chmod(0o775)
                (code_dir / 'preserve').write_text('unchanged')
                logs = home / '.local/log/machine-setup'
                logs.mkdir(parents=True)
                for path in (home / '.local', home / '.local/log', logs):
                    path.chmod(0o775)
                source = (ROOT / name).read_text()
                policy = (ROOT / 'lib/setup-policy.bash').read_text()
                helpers = '\n'.join(function(source, n) for n in ('setup_code_directory', 'start_setup_log', 'finish_setup_log'))
                code = policy + '\n' + helpers + '''
print_message() { :; }; print_debug() { :; }; print_success() { :; }; print_warning() { echo "$*"; }
upload_log() { echo fixture-upload >> "$HOME/transport"; }
SETUP_LOGGING_ACTIVE=0; SETUP_LOG_FILE=''; SETUP_LOG_TEE_PID=''
setup_code_directory || exit 21
start_setup_log || exit 22
printf 'fixture log body\n'
finish_setup_log 23
[[ $? == 23 ]] || exit 24
[[ -f "$SETUP_LOG_FILE" ]] && grep -q 'fixture log body' "$SETUP_LOG_FILE"
'''
                result = subprocess.run(['/bin/bash', '-c', code], cwd=tmp, capture_output=True, text=True,
                                        env={'PATH': '/usr/bin:/bin', 'HOME': str(home)}, timeout=10)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual((code_dir / 'preserve').read_text(), 'unchanged')
                self.assertEqual(home.stat().st_mode & 0o777, 0o775)
                self.assertEqual(code_dir.stat().st_mode & 0o777, 0o775)
                self.assertEqual((home / 'transport').read_text().splitlines(), ['fixture-upload'])

    @unittest.skipUnless(PWSH, 'Set PWSH_BIN; native Windows is not claimed')
    def test_default_windows_wrapper_dispatches_normal_tasks_and_preserves_failures(self):
        for task_failure in ('0', '1'):
            with self.subTest(task_failure=task_failure), tempfile.TemporaryDirectory() as tmp:
                script = Path(tmp) / 'fixture.ps1'
                script.write_text('''param([string]$SourcePath, [string]$TaskFailure)
$ErrorActionPreference='Stop'
$tokens=$null; $errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile($SourcePath,[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw 'Parse failure' }
$selected=@($ast.EndBlock.Statements | Where-Object { $_ -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $_.Name -eq 'Initialize-WindowsEnvironment' })
if ($selected.Count -ne 1) { throw 'Wrapper selection failed' }
. ([scriptblock]::Create($selected[0].Extent.Text))
function Initialize-SetupPolicy { throw 'Unexpected scheduling policy' }
function Get-SetupLogDirectory { Join-Path $env:USERPROFILE 'logs' }
function Assert-SetupLogPath { param($Path,[switch]$AllowMissing) }
function Invoke-PendingSetupLogUploads { }
function Start-Transcript { param($Path,[switch]$NoClobber,$ErrorAction) }
function Write-Debug { param($Message) }
function Invoke-WindowsSetupTasks { Write-Output 'normal-tasks'; if ($TaskFailure -eq '1') { throw 'original-task-error' } }
function Complete-SetupLog { Write-Output 'finalized' }
try { Initialize-WindowsEnvironment; if ($TaskFailure -eq '1') { throw 'failure swallowed' } }
catch { if ($TaskFailure -ne '1' -or $_.Exception.Message -ne 'original-task-error') { throw } }
''')
                result = subprocess.run([PWSH, '-NoLogo', '-NoProfile', '-NonInteractive', '-File', str(script),
                                         str(ROOT / 'win.ps1'), task_failure], cwd=tmp,
                                        env=dict(os.environ, HOME=tmp, USERPROFILE=tmp, BB_THREAD_ID='inert-fixture'),
                                        capture_output=True, text=True, timeout=20)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(result.stdout.splitlines(), ['normal-tasks', 'finalized'])


if __name__ == '__main__':
    unittest.main(verbosity=2)
