import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from extract_setup_fixture import validate_function

ROOT = Path(__file__).resolve().parents[1]
REASONS = ('unsafe-path', 'unsafe-home', 'unsafe-profile', 'unsafe-boundary', 'unsafe-metadata',
           'malformed-metadata', 'duplicate-key', 'unsupported-json-number', 'malformed-toml',
           'unsupported-toml', 'toml-parser-failed', 'toml-parser-unavailable', 'unsafe-toml-edit',
           'metadata-changed', 'boundary-changed', 'native-wrapper-required', 'filesystem-error')


class BacklogDiagnostics(unittest.TestCase):
    def test_bash_wrappers_preserve_only_controlled_reason(self):
        for name in ('mac.sh', 'ubuntu.sh', 'wsl.sh', 'pi.sh', 'bazzite.sh'):
            text = (ROOT / name).read_text()
            helper = 'retire_global_backlog_mcp() {\n' + text.split('retire_global_backlog_mcp() {\n', 1)[1].split("\n: 'END_GLOBAL_BACKLOG_MCP_RETIREMENT'", 1)[0]
            validate_function(helper)
            with tempfile.TemporaryDirectory() as raw:
                home = Path(raw); binary = home / 'bin'; binary.mkdir()
                node = binary / 'node'
                node.write_text('#!/bin/sh\nprintf "%s\\n" "$FIXTURE_REASON"\nprintf "PRIVATE_STDERR\\n" >&2\nexit 1\n')
                node.chmod(0o700)
                script = helper + '\n' + '''
ensure_shared_node_runtime() { return 0; }
print_error() { printf '%s\\n' "$*"; }
print_debug() { :; }
print_success() { :; }
retire_global_backlog_mcp
'''
                for reason in (*REASONS, 'PRIVATE_UNKNOWN', 'unsafe-path\nPRIVATE_UNKNOWN'):
                    with self.subTest(script=name, reason=reason):
                        result = subprocess.run(['/bin/bash', '-u', '-c', script], input='', text=True, capture_output=True,
                                                env={'PATH': str(binary) + ':/usr/bin:/bin', 'HOME': raw,
                                                     'FIXTURE_REASON': reason}, timeout=10)
                        self.assertEqual(result.returncode, 1)
                        self.assertNotIn('PRIVATE_', result.stdout + result.stderr)
                        if reason in REASONS:
                            self.assertIn('preflight failed (' + reason + '); no changes were made.', result.stdout)
                        else:
                            self.assertIn('unknown controlled reason', result.stdout)

    @unittest.skipUnless(os.environ.get('PWSH_BIN'), 'existing PowerShell not supplied')
    def test_powershell_wrapper_preserves_only_controlled_reason(self):
        with tempfile.TemporaryDirectory() as raw:
            script = Path(raw) / 'wrapper.ps1'
            script.write_text(r'''
param([string]$Source)
$tokens = $null; $parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($Source, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw 'parse failure' }
$definition = $ast.EndBlock.Statements | Where-Object { $_ -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $_.Name -eq 'Remove-GlobalBacklogMcp' }
if (@($definition).Count -ne 1) { throw 'unexpected function selection' }
. ([scriptblock]::Create($definition.Extent.Text))
function Enable-SharedNodeRuntime { return $true }
function Write-Error { param($Message) Write-Output $Message }
function Write-Debug { param($Message) }
function Write-Success { param($Message) }
function node { $input | Out-Null; $global:LASTEXITCODE = 1; Write-Output $env:FIXTURE_REASON }
function Invoke-BacklogMcpWindowsRetirement { return @{ Status = $env:FIXTURE_REASON; Code = 1 } }
$results = @(Remove-GlobalBacklogMcp)
if ($results[-1] -ne $false) { throw 'failure swallowed' }
$results | Select-Object -SkipLast 1 | Write-Output
''')
            for reason in ('malformed-metadata', 'toml-parser-unavailable', 'native-preflight-failed',
                           'PRIVATE_UNKNOWN', 'unsafe-path\nPRIVATE_UNKNOWN'):
                with self.subTest(reason=reason):
                    result = subprocess.run([os.environ['PWSH_BIN'], '-NoProfile', '-File', str(script), str(ROOT / 'win.ps1')],
                                            text=True, capture_output=True, env={**os.environ, 'FIXTURE_REASON': reason}, timeout=20)
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertNotIn('PRIVATE_', result.stdout + result.stderr)
                    if reason.startswith('PRIVATE_') or '\n' in reason:
                        self.assertIn('unknown controlled reason', result.stdout)
                    else:
                        self.assertIn('preflight failed (' + reason + '); no changes were made.', result.stdout)


if __name__ == '__main__':
    unittest.main()
