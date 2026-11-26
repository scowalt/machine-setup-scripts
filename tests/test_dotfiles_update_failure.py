import functools
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

import extract_setup_fixture

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ('mac', 'ubuntu', 'wsl', 'pi', 'bazzite')
CHEZMOI = os.environ.get('CHEZMOI_BIN') or shutil.which('chezmoi')
GIT = shutil.which('git')
PWSH = os.environ.get('PWSH_BIN')
NO_UPSTREAM = 'There is no tracking information for the current branch.'
UPDATE_FAILED = 'Failed to update chezmoi dotfiles repository.'


@functools.lru_cache(None)
def caller_fixture(entry):
    source = extract_setup_fixture.definitions((ROOT / (entry + '.sh')).read_text())
    names = set(re.findall(r'^([a-zA-Z_][a-zA-Z_0-9]*)\(\)\s*[({]', source, re.M))
    retained = ['run_setup_tasks', 'main', 'update_chezmoi', 'with_bb_dotfiles_umask']
    if entry == 'pi':
        retained.append('apply_chezmoi_config')
    blocks = []
    for name in retained:
        start = source.index('\n' + name + '() {\n') + 1
        block = source[start:source.index('\n}\n', start) + 3]
        extract_setup_fixture.validate_function(block)
        blocks.append(block)
    stubs = '\n'.join(name + '() { :; }' for name in sorted(names - set(retained)))
    return stubs + '\n' + '\n'.join(blocks) + r'''
check_dotfiles_access() { return 0; }
is_main_user() { return 0; }
whoami() { printf 'scowalt\n'; }
brew() { :; }
print_section() { printf '== %s\n' "$1"; }
print_message() { printf 'INFO: %s\n' "$1"; }
print_success() { printf 'SUCCESS: %s\n' "$1"; }
print_warning() { printf 'WARNING: %s\n' "$1"; }
print_error() { printf 'ERROR: %s\n' "$1"; }
print_debug() { printf 'DEBUG: %s\n' "$1"; }
check_pending_reboot() { printf 'later-independent-work\n'; }
finish_setup_log() { printf 'final:%s\n' "$1"; return "$1"; }
main
'''


WINDOWS_FIXTURE = r'''param([string]$SourcePath)
$ErrorActionPreference = 'Stop'
$tokens = $null; $errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($SourcePath, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'Setup parse failed' }
$definitions = @($ast.EndBlock.Statements | Where-Object { $_ -is [System.Management.Automation.Language.FunctionDefinitionAst] })
$retained = @('Invoke-WindowsSetupTasks', 'Initialize-WindowsEnvironment', 'Update-Chezmoi', 'Complete-SetupLog',
    'Write-Section', 'Write-Message', 'Write-Success', 'Write-Warning', 'Write-Error', 'Write-Debug')
foreach ($definition in $definitions) {
    if ($definition.Name -notin $retained) { Set-Item -Path ('function:' + $definition.Name) -Value { $true } }
}
foreach ($name in $retained) {
    $selected = @($definitions | Where-Object Name -eq $name)
    if ($selected.Count -ne 1) { throw "Fixture selection failed: $name" }
    . ([scriptblock]::Create($selected[0].Extent.Text))
}
$arrow = '->'; $success = 'OK'; $warnIcon = 'WARN'; $failIcon = 'FAIL'; $sparkles = '*'
function Record { param($Message) Add-Content -LiteralPath (Join-Path $env:FIXTURE_ROOT 'events') -Value $Message }
function Get-SetupLogDirectory { Join-Path $env:FIXTURE_ROOT 'logs' }
function Assert-SetupLogPath { param($Path, [switch]$AllowMissing) }
function Invoke-PendingSetupLogUploads { }
function Upload-Log { Record 'uploaded' }
function Install-Chezmoi { Record 'install-chezmoi' }
function Test-PendingReboot { Record 'later-independent-work' }

New-Item -ItemType Directory -Force -Path (Join-Path $HOME 'AppData/Local/chezmoi/.git') | Out-Null
$direct = @(Update-Chezmoi)
if ($direct.Count -ne 1 -or $direct[0] -isnot [bool]) { throw 'Update-Chezmoi must return exactly one Boolean' }
Record "direct:$($direct[0])"
try { Initialize-WindowsEnvironment; Record 'completed' }
catch { Record "thrown:$($_.Exception.Message)"; exit 1 }
exit 0
'''

WINDOWS_CHEZMOI = '''#!/bin/sh
printf '%s\\n' "$*" >> "$FIXTURE_ROOT/chezmoi-calls"
if [ "$1" = update ] && [ "$FIXTURE_UPDATE" = fail ]; then
    printf '%s\\n' 'There is no tracking information for the current branch.' 'chezmoi: exit status 1' >&2
    exit 1
fi
exit 0
'''


class DotfilesUpdateFailure(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='dotfiles-update-failure-')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.home = self.root / 'home'
        self.home.mkdir(mode=0o700)
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        for name in ('curl', 'wget', 'ssh', 'sudo', 'systemctl', 'loginctl', 'tailscale', 'npm', 'apt-get', 'brew'):
            guard = self.bin / name
            guard.write_text('#!/bin/sh\nprintf "%s\\n" "$0" >> "$FIXTURE_ROOT/unexpected"\nexit 97\n')
            guard.chmod(0o700)
        hooks = self.root / 'no-hooks'
        hooks.mkdir()
        self.env = {'PATH': f'{self.bin}:/usr/bin:/bin', 'HOME': str(self.home), 'USERPROFILE': str(self.home),
                    'USERNAME': 'scowalt', 'SHELL': '/bin/bash', 'LANG': 'C.UTF-8', 'LC_ALL': 'C.UTF-8',
                    'XDG_CONFIG_HOME': str(self.home / '.config'), 'XDG_DATA_HOME': str(self.home / '.local/share'),
                    'XDG_CACHE_HOME': str(self.home / '.cache'), 'XDG_STATE_HOME': str(self.home / '.local/state'),
                    'GIT_CONFIG_NOSYSTEM': '1', 'GIT_CONFIG_GLOBAL': '/dev/null', 'GIT_TERMINAL_PROMPT': '0',
                    'GIT_CONFIG_COUNT': '2', 'GIT_CONFIG_KEY_0': 'core.hooksPath', 'GIT_CONFIG_VALUE_0': str(hooks),
                    'GIT_CONFIG_KEY_1': 'init.templateDir', 'GIT_CONFIG_VALUE_1': str(hooks),
                    'FIXTURE_ROOT': str(self.root), 'BB_SERVER': '0', 'HEADLESS': '0', 'WORK_MACHINE': '0'}

    def git(self, *args):
        return subprocess.run([GIT, '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', *args],
                              env=self.env, check=True, capture_output=True, text=True, timeout=20)

    def dotfiles_checkout(self, upstream):
        seed = self.root / 'seed'
        origin = self.root / 'origin.git'
        checkout = self.home / '.local/share/chezmoi'
        seed.mkdir()
        (seed / 'dot_fixture-dotfile').write_text('origin main\n')
        self.git('init', '-b', 'main', str(seed))
        self.git('-C', str(seed), 'add', '.')
        self.git('-C', str(seed), 'commit', '-m', 'seed')
        self.git('clone', '--bare', str(seed), str(origin))
        self.git('clone', str(origin), str(checkout))
        if upstream:
            (seed / 'dot_fixture-dotfile').write_text('origin update\n')
            self.git('-C', str(seed), 'commit', '-am', 'remote update')
            self.git('-C', str(seed), 'push', str(origin), 'main')
            return 'origin update\n'
        self.git('-C', str(checkout), 'checkout', '-b', 'pr-guard-sleep-poll')
        (checkout / 'dot_fixture-dotfile').write_text('local branch\n')
        self.git('-C', str(checkout), 'commit', '-am', 'local work')
        return 'local branch\n'

    def run_entry(self, entry):
        self.assertTrue(CHEZMOI and GIT, 'native chezmoi and git are required; set CHEZMOI_BIN')
        chezmoi = self.bin / 'chezmoi'
        chezmoi.unlink(missing_ok=True)
        chezmoi.symlink_to(Path(CHEZMOI).resolve(strict=True))
        result = subprocess.run(['/bin/bash', '--noprofile', '--norc', '-c', caller_fixture(entry)],
                                env=self.env, cwd=self.home, stdin=subprocess.DEVNULL, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60)
        self.assertFalse((self.root / 'unexpected').exists(), result.stdout)
        return result

    def test_update_failure_applies_local_copy_and_fails_the_run(self):
        for entry in SCRIPTS:
            with self.subTest(entry=entry):
                self.setUp()
                applied = self.dotfiles_checkout(upstream=False)
                result = self.run_entry(entry)
                log = result.stdout
                self.assertEqual(result.returncode, 1, log)
                self.assertEqual(log.count('final:1'), 1, log)
                self.assertIn(NO_UPSTREAM, log)
                self.assertIn('ERROR: ' + UPDATE_FAILED, log)
                self.assertLess(log.index(NO_UPSTREAM), log.index(UPDATE_FAILED))
                self.assertLess(log.index(UPDATE_FAILED), log.index('later-independent-work'))
                self.assertEqual((self.home / '.fixture-dotfile').read_text(), applied)

    def test_successful_update_still_passes(self):
        for entry in SCRIPTS:
            with self.subTest(entry=entry):
                self.setUp()
                applied = self.dotfiles_checkout(upstream=True)
                result = self.run_entry(entry)
                self.assertEqual(result.returncode, 0, result.stdout)
                self.assertIn('final:0', result.stdout)
                self.assertIn('SUCCESS: chezmoi dotfiles repository updated.', result.stdout)
                self.assertNotIn('ERROR:', result.stdout)
                self.assertEqual((self.home / '.fixture-dotfile').read_text(), applied)

    def run_windows(self, outcome):
        if not PWSH:
            self.skipTest('PowerShell unavailable; set PWSH_BIN')
        chezmoi = self.bin / 'chezmoi'
        chezmoi.write_text(WINDOWS_CHEZMOI)
        chezmoi.chmod(0o700)
        git = self.bin / 'git'
        git.write_text('#!/bin/sh\nexit 0\n')
        git.chmod(0o700)
        fixture = self.root / 'windows.ps1'
        fixture.write_text(WINDOWS_FIXTURE)
        result = subprocess.run([PWSH, '-NoProfile', '-NonInteractive', '-File', str(fixture), str(ROOT / 'win.ps1')],
                                env=dict(self.env, FIXTURE_UPDATE=outcome), cwd=self.home, stdin=subprocess.DEVNULL,
                                text=True, capture_output=True, timeout=120)
        self.assertFalse((self.root / 'unexpected').exists(), result.stdout + result.stderr)
        events = (self.root / 'events').read_text().splitlines()
        logs = list((self.root / 'logs').iterdir())
        self.assertEqual(len(logs), 1, logs)
        return result, events, logs[0].read_text()

    def test_windows_update_failure_fails_the_run_after_unrelated_work(self):
        result, events, log = self.run_windows('fail')
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertEqual(events[0], 'direct:False')
        self.assertEqual(events[-1], 'thrown:Dotfiles update failed.')
        self.assertLess(events.index('later-independent-work'), events.index('uploaded'))
        self.assertIn(NO_UPSTREAM, log)
        self.assertIn('FAIL ' + UPDATE_FAILED, log)

    def test_windows_successful_update_still_passes(self):
        result, events, log = self.run_windows('ok')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(events[0], 'direct:True')
        self.assertEqual(events[-1], 'completed')
        self.assertIn('OK chezmoi dotfiles repository updated.', log)
        self.assertNotIn('FAIL ', log)


if __name__ == '__main__':
    unittest.main(verbosity=2)
