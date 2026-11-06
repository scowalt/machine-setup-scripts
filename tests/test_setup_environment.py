from dataclasses import dataclass
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from typing import Optional

ROOT = Path(__file__).resolve().parents[1]
BASH = ('mac.sh', 'ubuntu.sh', 'pi.sh', 'bazzite.sh', 'wsl.sh')
PWSH = os.environ.get('PWSH_BIN')
CONTENTS = '''BB_SERVER=1  # Opt in to a persistent bb server (Ubuntu only)
MACHINE_TYPE=physical  # Override VPS/physical detection when needed
GH_TOKEN='credential#literal' # trailing comment
ZAI_API_KEY="credential # spaced"  # another comment
OPENCODE_GO_API_KEY=credential#unquoted
WORK_MACHINE=1#not-a-comment
'''


@dataclass(frozen=True)
class EnvironmentCase:
    data: str
    expected: Optional[str]
    inherited: Optional[str] = None


INPUT_CASES = (
    EnvironmentCase('', None),
    EnvironmentCase('# {key}=1\n', None),
    EnvironmentCase('{key}=1 # intentional exclusion\n', '1'),
    EnvironmentCase('export {key}="0"\r\n', '0'),
    EnvironmentCase('{key}=\n', ''),
    EnvironmentCase('{key}=true\n', 'true'),
    EnvironmentCase('{key}=false\n', 'false'),
    EnvironmentCase('{key}=01\n', '01'),
    EnvironmentCase("{key}=' 1 '\n", ' 1 '),
    EnvironmentCase('{key}=1#literal\n', '1#literal'),
    EnvironmentCase("{key}='{command}'\n", '{command}'),
    EnvironmentCase('', '1', '1'),
    EnvironmentCase('# {key}=1\n', '0', '0'),
    EnvironmentCase('{key}=1\n', '1', '0'),
    EnvironmentCase('{key}=0\n', '0', '1'),
)


def input_cases(key, command='$(touch escaped)'):
    return tuple(EnvironmentCase(case.data.format(key=key, command=command),
                                 case.expected.format(command=command) if case.expected is not None else None,
                                 case.inherited) for case in INPUT_CASES)


def powershell_cases(key):
    cases = [{'Data': case.data, 'Expected': case.expected or '', 'Before': case.inherited}
             for case in input_cases(key, '$(New-Item escaped)')]
    return "$cases = ConvertFrom-Json @'\n" + json.dumps(cases) + "\n'@\n"


class Environment(unittest.TestCase):
    def bash(self, code, contents, environment=None):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            file = home / '.env.local'
            file.write_text(contents)
            source = (ROOT / 'lib/setup-policy.bash').read_text()
            result = subprocess.run(['/bin/bash', '-c', source + '\nprint_error() { echo "$*"; }\n' + code],
                                    cwd=tmp, env={'PATH': '/usr/bin:/bin', 'HOME': tmp, **(environment or {})},
                                    capture_output=True, text=True, timeout=10)
            self.assertEqual(file.read_bytes(), contents.encode())
            self.assertEqual(list(home.iterdir()), [file])
            return result

    def test_embedded_readers_match_and_no_scheduling_gate_remains(self):
        for name in (*BASH, 'win.ps1'):
            with self.subTest(script=name):
                source = (ROOT / name).read_text()
                policy = (ROOT / 'lib' / ('setup-policy.ps1' if name.endswith('.ps1') else 'setup-policy.bash')).read_text().rstrip()
                marker = "$null = '" if name.endswith('.ps1') else ": '"
                self.assertIn(marker + "BEGIN_SETUP_ENVIRONMENT_POLICY'\n" + policy + '\n' + marker + "END_SETUP_ENVIRONMENT_POLICY'", source)
                for obsolete in ('setup_require_maintenance', 'setup_safe_tasks', 'setup_safe_directory', 'setup_policy_init',
                                 'Assert-SetupMaintenance', 'Invoke-SetupSafeTasks', 'Initialize-SetupPolicy', 'Assert-SetupSafeDirectory'):
                    self.assertNotIn(obsolete, source)
                self.assertNotIn('source "${HOME}/.env.local"', source)

    def test_comments_preserve_template_flags_and_literal_credentials(self):
        result = self.bash('''setup_load_environment || exit 1
[[ "$BB_SERVER" == 1 && "$MACHINE_TYPE" == physical && "$GH_TOKEN" == 'credential#literal' && "$ZAI_API_KEY" == 'credential # spaced' && "$OPENCODE_GO_API_KEY" == 'credential#unquoted' && "$WORK_MACHINE" == '1#not-a-comment' ]]
''', CONTENTS)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn('credential', result.stdout + result.stderr)

    def test_bash_ignores_retired_engineering_skill_exclusions(self):
        saved = 'BAN_SCOWALT_ENGINEERING_SKILLS=two words\nBAN_MATT_POCOCK_SKILLS=1\nBAN_MATT_POCKOCK_SKILLS=1\n'
        result = self.bash('''setup_load_environment || exit 1
[[ -z "${BAN_SCOWALT_ENGINEERING_SKILLS+x}${BAN_MATT_POCOCK_SKILLS+x}${BAN_MATT_POCKOCK_SKILLS+x}" && "$GH_TOKEN" == 'credential#literal' ]]
''', CONTENTS + saved)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn('two words', result.stdout + result.stderr)

    def test_bash_impeccable_input_is_literal_and_independent_of_other_exclusions(self):
        policy = CONTENTS + 'BAN_PI_MCP_ADAPTER=0\nBAN_PI_GOAL_AUTORESEARCH=1\n'
        code = '''setup_load_environment || exit 1
[[ "$BAN_PI_MCP_ADAPTER" == 0 && "$BAN_PI_GOAL_AUTORESEARCH" == 1 ]] || exit 2
if [[ "$EXPECT_PRESENT" == 1 ]]; then
    [[ "${BAN_IMPECCABLE+x}" == x && "$BAN_IMPECCABLE" == "$EXPECTED" ]]
else
    [[ -z "${BAN_IMPECCABLE+x}" ]]
fi
'''
        for case in input_cases('BAN_IMPECCABLE'):
            with self.subTest(case=case):
                environment = {'EXPECTED': case.expected or '', 'EXPECT_PRESENT': str(int(case.expected is not None))}
                if case.inherited is not None:
                    environment['BAN_IMPECCABLE'] = case.inherited
                result = self.bash(code, policy + case.data, environment)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertNotIn('credential', result.stdout + result.stderr)
        result = self.bash('setup_load_environment', 'BAN_IMPECCABLE=two words\n')
        self.assertEqual(result.returncode, 1)
        self.assertIn('Failed:', result.stdout)
        self.assertNotIn('two words', result.stdout + result.stderr)

    def test_malformed_data_is_controlled_and_command_text_is_never_executed(self):
        for invalid in ('GH_TOKEN="unterminated', 'GH_TOKEN="one"two', 'GH_TOKEN="one"#two',
                        'GH_TOKEN=two words', '"GH_TOKEN"=value', 'touch escaped'):
            with self.subTest(invalid=invalid):
                result = self.bash('setup_load_environment', invalid)
                self.assertEqual(result.returncode, 1)
                self.assertIn('Failed:', result.stdout)
                self.assertNotIn(invalid, result.stdout + result.stderr)
        for value in ('$(touch escaped)', '`touch escaped`', r'literal\backslash$variable'):
            result = self.bash('setup_load_environment && [[ "$GH_TOKEN" == "$EXPECTED" ]]', f"GH_TOKEN='{value}'\n",
                               {'EXPECTED': value})
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_ubuntu_process_server_override_and_unknown_saved_flags(self):
        for override in ('0', '1'):
            result = self.bash('setup_load_environment && [[ "$BB_SERVER" == "$EXPECTED" && -z "${SETUP_MAINTENANCE_AUTHORIZED+x}" ]]',
                               'BB_SERVER=1\nSETUP_MAINTENANCE_AUTHORIZED=1\n',
                               {'BB_SERVER': override, 'EXPECTED': override, 'SETUP_ENTRY_PLATFORM': 'ubuntu'})
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    @unittest.skipUnless(PWSH, 'Set PWSH_BIN; native Windows is not claimed')
    def test_powershell_ignores_retired_engineering_skill_exclusions(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            script = root / 'fixture.ps1'
            script.write_text("$ErrorActionPreference='Stop'\n" + (ROOT / 'lib/setup-policy.ps1').read_text() + """
$file = Join-Path $env:USERPROFILE '.env.local'
[IO.File]::WriteAllText($file, "GH_TOKEN='credential#literal'`r`nBAN_SCOWALT_ENGINEERING_SKILLS=two words`r`nBAN_MATT_POCOCK_SKILLS=1`r`nBAN_MATT_POCKOCK_SKILLS=1`r`n")
Read-SetupEnvironment
foreach ($key in @('BAN_SCOWALT_ENGINEERING_SKILLS', 'BAN_MATT_POCOCK_SKILLS', 'BAN_MATT_POCKOCK_SKILLS')) {
    if ($null -ne [Environment]::GetEnvironmentVariable($key)) { throw "Retired input loaded: $key" }
}
if ($env:GH_TOKEN -cne 'credential#literal') { throw 'Independent input changed' }
Write-Output 'PASS: retired engineering-skill inputs'
""")
            result = subprocess.run([PWSH, '-NoLogo', '-NoProfile', '-NonInteractive', '-File', str(script)],
                                    cwd=tmp, env={k: v for k, v in dict(os.environ, HOME=tmp, USERPROFILE=tmp).items()
                                                  if not k.startswith('BAN_')},
                                    capture_output=True, text=True, timeout=20)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('PASS:', result.stdout)
            self.assertNotIn('credential', result.stdout + result.stderr)

    @unittest.skipUnless(PWSH, 'Set PWSH_BIN; native Windows is not claimed')
    def test_powershell_impeccable_input_is_literal_and_independent_of_other_exclusions(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            script = root / 'fixture.ps1'
            script.write_text("$ErrorActionPreference='Stop'\n" + (ROOT / 'lib/setup-policy.ps1').read_text() + """
$file = Join-Path $env:USERPROFILE '.env.local'
$policy = "BAN_PI_MCP_ADAPTER=0`nBAN_PI_GOAL_AUTORESEARCH=1`n"
""" + powershell_cases('BAN_IMPECCABLE') + """
foreach ($case in $cases) {
    [Environment]::SetEnvironmentVariable('BAN_IMPECCABLE', $case.Before, 'Process')
    [IO.File]::WriteAllText($file, $policy + $case.Data + "`n")
    $before = [Convert]::ToBase64String([IO.File]::ReadAllBytes($file))
    Read-SetupEnvironment
    if ([string]$env:BAN_IMPECCABLE -cne $case.Expected) { throw 'Impeccable input changed' }
    if ($env:BAN_PI_MCP_ADAPTER -cne '0' -or $env:BAN_PI_GOAL_AUTORESEARCH -cne '1') { throw 'Independent exclusion changed' }
    if ([Convert]::ToBase64String([IO.File]::ReadAllBytes($file)) -cne $before) { throw 'Environment file changed' }
}
[IO.File]::WriteAllText($file, "BAN_IMPECCABLE=two words`n")
$rejected = $false
try { Read-SetupEnvironment } catch {
    if ($_.Exception.Message -ne 'Unsupported environment-file value') { throw }
    $rejected = $true
}
if (-not $rejected) { throw 'Malformed Impeccable input accepted' }
Write-Output 'PASS: data-only Impeccable input'
""")
            result = subprocess.run([PWSH, '-NoLogo', '-NoProfile', '-NonInteractive', '-File', str(script)],
                                    cwd=tmp, env=dict(os.environ, HOME=tmp, USERPROFILE=tmp),
                                    capture_output=True, text=True, timeout=20)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('PASS:', result.stdout)
            self.assertFalse((root / 'escaped').exists())
            self.assertEqual((root / '.env.local').read_text(), 'BAN_IMPECCABLE=two words\n')

    @unittest.skipUnless(PWSH, 'Set PWSH_BIN; native Windows is not claimed')
    def test_powershell_literals_rejection_and_exact_headless_precedence(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            envfile = root / '.env.local'
            envfile.write_text(CONTENTS + "HEADLESS=0\nOP_SERVICE_ACCOUNT_TOKEN='$(New-Item escaped)'\n")
            before = envfile.read_bytes()
            script = root / 'fixture.ps1'
            script.write_text("$ErrorActionPreference='Stop'\n" + (ROOT / 'lib/setup-policy.ps1').read_text() + '''
$env:HEADLESS='1'
Read-SetupEnvironment
if ($env:BB_SERVER -ne '1' -or $env:MACHINE_TYPE -ne 'physical' -or $env:GH_TOKEN -ne 'credential#literal' -or
    $env:ZAI_API_KEY -ne 'credential # spaced' -or $env:OPENCODE_GO_API_KEY -ne 'credential#unquoted' -or
    $env:WORK_MACHINE -ne '1#not-a-comment' -or $env:HEADLESS -ne '1' -or
    $env:OP_SERVICE_ACCOUNT_TOKEN -ne '$(New-Item escaped)') { throw 'Literal data changed' }
foreach ($invalid in @('"unterminated','"one"two','"one"#two','two words')) {
    $rejected=$false
    try { ConvertFrom-SetupEnvironmentValue $invalid | Out-Null } catch {
        if ($_.Exception.Message -ne 'Unsupported environment-file value') { throw }
        $rejected=$true
    }
    if (-not $rejected) { throw 'Malformed value accepted' }
}
Write-Output 'PASS: data-only dotenv'
''')
            result = subprocess.run([PWSH, '-NoLogo', '-NoProfile', '-NonInteractive', '-File', str(script)],
                                    cwd=tmp, env=dict(os.environ, HOME=tmp, USERPROFILE=tmp),
                                    capture_output=True, text=True, timeout=20)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('PASS:', result.stdout)
            self.assertNotIn('credential', result.stdout + result.stderr)
            self.assertFalse((root / 'escaped').exists())
            self.assertEqual(envfile.read_bytes(), before)


if __name__ == '__main__':
    unittest.main(verbosity=2)
