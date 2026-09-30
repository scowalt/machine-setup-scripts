"""Contract v5: ordinary extracted callers validate controlled Homebrew/policy diagnostics."""
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
                for operation, reason in [('homebrew-preflight', 'brew-group-shared'), ('homebrew-preflight', 'brew-identity-source'),
                                          ('homebrew-preflight', 'brew-acl-unverified'), ('homebrew-preflight', 'native-EACCES'),
                                          ('installation', 'pinned'), ('installation', 'unverified-copy'), ('installation', 'native-ENOENT')]]
DIAGNOSTICS += [(result, status, None) for result, status in [
    ('opencode-cli:policy-failed:homebrew-preflight:brew-path', 0),
    ('opencode-cli:policy-failed:SECRET:brew-path', 1),
    ('opencode-cli:policy-failed:homebrew-preflight:SECRET', 1),
    ('opencode-cli:policy-failed:homebrew-preflight:native-SECRET', 1),
    ('opencode-cli:policy-failed:homebrew-preflight:brew-path\nSECRET', 1),
    ('opencode-cli:policy-failed:homebrew-preflight:brew-path\r', 1),
    ('opencode-cli:policy-failed:homebrew-preflight:brew-path SECRET', 1),
    ('opencode-cli:policy-failed:homebrew-preflight:BREW-PATH', 1),
]]


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
                    self.assertEqual('rollback needs manual recovery' in run.stdout, result == 'opencode-cli:recovery-required')
            for extra in [{'MOCK_NODE_PREREQUISITE': '1'}, {}]:
                setup = 'macos_existing_prerequisites() { return 1; }\n' if not extra else ''
                run = self.exercise(setup + helper, 'install_opencode_cli', extra)
                self.assertEqual(run.returncode, 1, run.stdout)
        self.assertTrue(all(block == blocks[0] for block in blocks))

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
                            '$input | Out-Null\nWrite-Output ([regex]::Split($env:MOCK_RESULT, "`n"))\n'
                            'Write-Error "SECRET stderr" -ErrorAction Continue\n$global:LASTEXITCODE=[int]$env:MOCK_STATUS\n')
            harness = Path(home) / 'wrapper.ps1'
            harness.write_text('''$ErrorActionPreference='Stop'
function Write-Success { param($Message) Write-Host $Message }
function Write-Warning { param($Message) Write-Host $Message }
function Get-Command { param($Name, $CommandType, $ErrorAction)
    if ($Name -eq 'node') { [pscustomobject]@{Source=$env:MOCK_NODE} }
}
function Test-OpenCodeCliAcl { param($HomePath) $true }
$env:PROCESSOR_ARCHITECTURE='AMD64'
$env:PROCESSOR_ARCHITEW6432=$null
$env:NODE_OPTIONS='fixture-original'
''' + wrapper + '''
$result=Install-OpenCodeCli
if ($env:NODE_OPTIONS -ne 'fixture-original') { throw 'environment not restored' }
if ($result) { exit 0 } else { exit 1 }
''')
            cases = [('opencode-cli:installed', '0', 0, None), ('opencode-cli:newer', '0', 0, None),
                     ('opencode-cli:failed', '1', 1, None), ('unexpected-secret-output', '0', 1, None)]
            cases += [(result, str(status), 1, diagnostic) for result, status, diagnostic in DIAGNOSTICS]
            for result, status, expected, diagnostic in cases:
                run = subprocess.run([PWSH, '-NoProfile', '-NonInteractive', '-File', str(harness)], cwd=home,
                                     env={'PATH': os.environ['PATH'], 'HOME': home, 'USERPROFILE': home, 'MOCK_NODE': str(fake),
                                          'MOCK_RESULT': result, 'MOCK_STATUS': status}, capture_output=True, text=True, timeout=20)
                self.assertEqual(run.returncode, expected, run.stdout + run.stderr)
                self.assertNotIn('unexpected-secret-output', run.stdout + run.stderr)
                self.assertNotIn('SECRET', run.stdout + run.stderr)
                if diagnostic:
                    self.assertIn(diagnostic, run.stdout)
                else:
                    self.assertNotIn('OpenCode CLI download failed (', run.stdout)
                    self.assertNotIn('OpenCode CLI blocked (', run.stdout)
                self.assertEqual('rollback needs manual recovery' in run.stdout, result == 'opencode-cli:recovery-required')

    @unittest.skipUnless(PWSH, 'No existing PWSH_BIN/pwsh: native Windows/PowerShell execution not claimed')
    def test_powershell_caller_aggregation(self):
        source = (ROOT / 'win.ps1').read_text()
        main = source.split('function Invoke-WindowsSetupTasks {')[1]
        call = re.search(r'^    if \(-not \(Install-OpenCodeCli\)\).*$', main, re.M)[0]
        check = re.search(r'^    if \(\$openCodeSetupFailed -or \$script:OpenCodeWingetConflict\) \{.*?^    \}', main, re.M | re.S)[0]
        script = ('$ErrorActionPreference="Stop"\nfunction Install-OpenCodeCli { $false }\n'
                  '$openCodeSetupFailed=$false; $script:OpenCodeWingetConflict=$false\n' + call +
                  '\nWrite-Output independent\ntry {\n' + check + '\n} catch { Write-Output finalized; exit 1 }\n')
        with tempfile.TemporaryDirectory() as home:
            file = Path(home) / 'caller.ps1'
            file.write_text(script)
            run = subprocess.run([PWSH, '-NoProfile', '-NonInteractive', '-File', str(file)], cwd=home,
                                 env={'PATH': os.environ['PATH'], 'HOME': home}, capture_output=True, text=True, timeout=20)
        self.assertEqual(run.returncode, 1)
        self.assertIn('independent', run.stdout)
        self.assertIn('finalized', run.stdout)


if __name__ == '__main__':
    unittest.main()
