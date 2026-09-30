"""Benign boundary-drift and socket-construction regressions; no destinations.

Run only through run-fixture-matrix.py. No production setup entry point is run.
"""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from extract_setup_fixture import definitions, materialize, SCRIPTS

ROOT = Path(__file__).resolve().parents[1]
PWSH = os.environ.get('PWSH_BIN') or shutil.which('pwsh')
REQUIRED = '''setup_policy_init() {
    :
}
run_setup_tasks() {
    :
}
main() {
    printf 'explicit caller only\\n'
}
'''


class ExtractionBoundary(unittest.TestCase):
    def test_changed_entry_invocation_and_top_level_code_are_not_emitted(self):
        for invocation in ('main', 'main --changed-signature', 'main "$@" --new-argument'):
            source = 'printf BAD > "$HOME/before-mocks"\n' + REQUIRED + invocation + '\n'
            selected = definitions(source)
            with self.subTest(invocation=invocation), tempfile.TemporaryDirectory() as tmp:
                run = subprocess.run(['/bin/bash', '-c', selected + '\nprintf imported\\n\n'],
                                     env={'PATH': '/usr/bin:/bin', 'HOME': tmp}, capture_output=True, text=True)
                self.assertEqual(run.returncode, 0, run.stderr)
                self.assertFalse((Path(tmp) / 'before-mocks').exists())
                self.assertNotIn('explicit caller only', run.stdout)

    def test_unsupported_early_closing_brace_cannot_smuggle_top_level_code(self):
        # All three required functions precede the drift; swallowing a following
        # NON-required function must not evade the required-name check.
        for close in ('}; printf BAD > "$HOME/before-mocks"',
                      '    }; printf BAD > "$HOME/before-mocks"',
                      ':; }; printf BAD > "$HOME/before-mocks"',
                      '} \\\n; printf BAD > "$HOME/before-mocks"'):
            source = REQUIRED + 'extra() {\n    :\n' + close + '\nfollowing() {\n    :\n}\n'
            with self.subTest(close=close), self.assertRaises(ValueError):
                definitions(source)
        source = REQUIRED + 'extra() {\n:; }; printf BAD > "$HOME/before-mocks"\n{\n:\n}\n'
        with self.assertRaises(ValueError):
            definitions(source)

    def test_audited_subshell_function_form_keeps_the_same_boundary_checks(self):
        safe = REQUIRED + 'extra() (\n    :\n)\n'
        self.assertIn('extra() (', definitions(safe))
        for close in ('); printf BAD > "$HOME/before-mocks"', ':; ); printf BAD > "$HOME/before-mocks"'):
            with self.subTest(close=close), self.assertRaises(ValueError):
                definitions(REQUIRED + 'extra() (\n    :\n' + close + '\n{\n:\n}\n)\n')

    def test_quote_and_heredoc_boundaries_fail_closed_or_stay_inside_function(self):
        quoted = REQUIRED + "extra() {\nprintf '%s' '\n}\n'; printf BAD > \"$HOME/before-mocks\"\n}\n"
        with self.assertRaises(ValueError):
            definitions(quoted)
        heredoc = REQUIRED + "extra() {\n    printf '%s' \"$(< /dev/null)\"\n    read -r ignored <<'END'\n}; printf BAD > \"$HOME/before-mocks\"\nEND\n}\n"
        selected = definitions(heredoc)
        with tempfile.TemporaryDirectory() as tmp:
            run = subprocess.run(['/bin/bash', '-c', selected], env={'PATH': '/usr/bin:/bin', 'HOME': tmp},
                                 capture_output=True, text=True)
            self.assertEqual(run.returncode, 0, run.stderr)
            self.assertFalse((Path(tmp) / 'before-mocks').exists())
        with self.assertRaises(ValueError):
            definitions(heredoc.replace('\nEND\n', '\nMISSING\n'))

    @unittest.skipUnless(PWSH, 'PowerShell is unavailable; native Windows is not claimed')
    def test_actual_powershell_fixture_importers_ignore_changed_entry_signature(self):
        for name in ('attention-span-removal-powershell.ps1', 'setup-reliability-powershell.ps1'):
            importer = (ROOT / 'tests' / name).read_text().split('$script:Messages =', 1)[0]
            with self.subTest(importer=name), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                (root / 'tests').mkdir()
                # This is a synthetic script, not the actual setup implementation.
                (root / 'win.ps1').write_text('''param([switch]$Maintenance)
function Initialize-SetupPolicy { param([switch]$Maintenance) }
function Initialize-WindowsEnvironment {
    if (-not $script:MocksReady) { [IO.File]::WriteAllText((Join-Path $env:USERPROFILE 'before-mocks'), 'BAD'); throw 'before mocks' }
    Write-Output 'explicit fixture call after mocks'
}
Initialize-WindowsEnvironment -Maintenance:$Maintenance -ChangedSignature
''')
                fixture = root / 'tests/import.ps1'
                fixture.write_text(importer + '''
$script:MocksReady=$true
Initialize-WindowsEnvironment
''')
                env = {'PATH': os.environ['PATH'], 'HOME': tmp, 'USERPROFILE': tmp,
                       'POWERSHELL_TELEMETRY_OPTOUT': '1', 'DOTNET_CLI_TELEMETRY_OPTOUT': '1'}
                result = subprocess.run([PWSH, '-NoLogo', '-NoProfile', '-NonInteractive', '-File', str(fixture)],
                                        env=env, cwd=tmp, capture_output=True, text=True, timeout=20)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertFalse((root / 'before-mocks').exists())
                self.assertEqual(result.stdout.count('explicit fixture call after mocks'), 1)


class ActualSourceSelection(unittest.TestCase):
    def test_actual_bash_sources_materialize_without_entry_execution(self):
        destination = materialize(ROOT)
        self.assertEqual({p.name for p in destination.iterdir()}, set(SCRIPTS))
        for name in SCRIPTS:
            selected = (destination / name).read_text()
            self.assertIn('\nrun_setup_tasks() {\n', selected)
            self.assertIn('\nmain() {\n', selected)
            self.assertNotIn('\n    main "$@"\n', selected)
            self.assertNotIn('\nmain "$@"\n', selected)
        print('Actual Bash definitions materialized (parse only): ' + str(destination))

    @unittest.skipUnless(PWSH, 'PowerShell unavailable; no native Windows claim')
    def test_actual_powershell_source_ast_selection_without_execution(self):
        with tempfile.TemporaryDirectory() as tmp:
            fixture = Path(tmp) / 'parse-only.ps1'
            fixture.write_text('''param([string]$SourcePath)
$ErrorActionPreference='Stop'
$tokens=$null; $errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile($SourcePath,[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw 'Actual PowerShell source parse failed' }
$definitions=@($ast.EndBlock.Statements | Where-Object { $_ -is [System.Management.Automation.Language.FunctionDefinitionAst] })
foreach ($name in @('Initialize-WindowsEnvironment','Invoke-WindowsSetupTasks','Initialize-SetupPolicy','Invoke-SetupSafeTasks')) {
    if (@($definitions | Where-Object Name -eq $name).Count -ne 1) { throw 'Required function selection failed' }
}
foreach ($definition in $definitions) {
    $part=[System.Management.Automation.Language.Parser]::ParseInput($definition.Extent.Text,[ref]$tokens,[ref]$errors)
    if ($errors.Count -or $part.EndBlock.Statements.Count -ne 1 -or $part.EndBlock.Statements[0] -isnot [System.Management.Automation.Language.FunctionDefinitionAst]) { throw 'Selected non-definition code' }
}
Write-Output ('PASS: actual PowerShell AST selected ' + $definitions.Count + ' functions; no definitions or entry point executed')
''')
            env = dict(os.environ, HOME=tmp, USERPROFILE=tmp, POWERSHELL_TELEMETRY_OPTOUT='1', DOTNET_CLI_TELEMETRY_OPTOUT='1')
            result = subprocess.run([PWSH, '-NoLogo', '-NoProfile', '-NonInteractive', '-File', str(fixture), str(ROOT / 'win.ps1')],
                                    env=env, cwd=tmp, capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('no definitions or entry point executed', result.stdout)
            print(result.stdout.strip())


class OutboundContainment(unittest.TestCase):
    def test_runner_supplied_filter_is_inherited_not_reinstalled(self):
        sandbox = os.environ.get('FIXTURE_NETWORK_SANDBOX')
        self.assertTrue(sandbox, 'Use tests/run-fixture-matrix.py; uncontained execution is not permitted')
        result = subprocess.run([sandbox, '--assert-inherited-denial'], capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('AF_INET and AF_INET6 socket creation denied', result.stdout)


if __name__ == '__main__':
    unittest.main(verbosity=2)
