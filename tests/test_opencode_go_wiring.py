"""Contract v4: independent Pi/Go/package orchestration and catalog safety gates."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

import test_pi_opencode_go_setup as go

ROOT = Path(__file__).resolve().parents[1]
BASH = ("mac.sh", "ubuntu.sh", "wsl.sh", "pi.sh", "bazzite.sh")
PWSH = os.environ.get("PWSH_BIN") or shutil.which("pwsh")


class WiringTests(unittest.TestCase):
    def bash_block(self, name):
        main = (ROOT / name).read_text().split("run_setup_tasks() {", 1)[1]
        begin = re.search(r'^    if ! [^\n]*prepare_pi_profile_permissions; then', main, re.M).start()
        end = re.search(r"^    (?:if ! )?remove_simple_english_skill", main, re.M).start()
        return main[begin:end]

    def run_bash(self, name, scenario, catalog_fixture=None):
        # Only the selected main block is executed, never a full setup script.
        inert = (
            "remove_rtk_resources", "remove_attention_span_resources", "setup_matt_pocock_skills",
            "configure_pi_defaults", "remove_pi_synthetic_models", "seed_pi_zai_models",
            "setup_pi_mcp_adapter", "remove_pi_subagents", "remove_pi_rpiv_packages",
            "setup_pi_claude_bridge", "setup_pi_companion_packages", "setup_pi_goal_autoresearch",
            "refresh_pi_packages",
        )
        code = "set -eu\n_setup_had_errors=0\n_pi_go_ready=0\nPI_RUNTIME_PREFLIGHT_PASSED=0\n"
        code += "PI_PROFILE_MUTATIONS_BLOCKED=0\n"
        if name == 'mac.sh' and scenario == 'developer-tools-unverified':
            code += 'MACOS_DEVELOPER_TOOLS_STATE=unverified\n'
        code += "record() { printf '%s\\n' \"$1\"; }\n"
        code += "print_warning() { :; }; print_section() { :; }\n"
        code += "\n".join(f"{fn}() {{ record {fn}; }}" for fn in inert)
        code += r'''
prepare_pi_profile_permissions() { record permissions; [[ "${SCENARIO}" != permissions-failure ]]; }
disable_pi_askclaude() { record askclaude; [[ "${SCENARIO}" != askclaude-failure ]]; }
remove_pi_prose() { record retirement; [[ "${SCENARIO}" != retirement-failure ]]; }
install_pi_cli() { record pi-install; [[ "${SCENARIO}" != pi-failure ]]; }
prepare_pi_mcp_adapter() { record packages; [[ "${SCENARIO}" != package-failure ]]; }
configure_pi_opencode_go() { record go; [[ "${SCENARIO}" != go-failure ]]; }
'''
        if catalog_fixture:
            code += '\n' + go.wrapper(name) + '\n'
            code += 'print_success() { :; }; print_debug() { :; }\n'
        code += 'exercise() {\n' + self.bash_block(name)
        code += '\n}\nexercise\nprintf "result:%s:%s\\n" "${_setup_had_errors}" "${_pi_go_ready}"\n'
        with tempfile.TemporaryDirectory() as tmp:
            fixture = Path(tmp) / "wiring.sh"
            fixture.write_text(code)
            result = subprocess.run(
                ["bash", str(fixture)], cwd=tmp,
                env={**(catalog_fixture.env if catalog_fixture else {"PATH": os.environ["PATH"], "HOME": tmp}),
                     "SCENARIO": scenario},
                text=True, capture_output=True, timeout=20,
            )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result.stdout.splitlines()

    def test_bash_success_and_order(self):
        for name in BASH:
            with self.subTest(script=name):
                calls = self.run_bash(name, "success")
                self.assertEqual(calls[-1], "result:0:1")
                self.assertLess(calls.index("permissions"), calls.index("askclaude"))
                self.assertLess(calls.index("askclaude"), calls.index("retirement"))
                self.assertLess(calls.index("pi-install"), calls.index("go"))
                self.assertLess(calls.index("go"), calls.index("packages"))
                self.assertLess(calls.index("packages"), calls.index("setup_pi_mcp_adapter"))
                self.assertLess(calls.index("setup_pi_goal_autoresearch"), calls.index("refresh_pi_packages"))

    def test_failures_are_aggregated_and_block_package_operations(self):
        for name in BASH:
            for scenario in ("permissions-failure", "askclaude-failure", "retirement-failure", "pi-failure", "go-failure",
                             "package-failure"):
                with self.subTest(script=name, scenario=scenario):
                    calls = self.run_bash(name, scenario)
                    ready = 0 if scenario in ("permissions-failure", "askclaude-failure", "retirement-failure", "pi-failure", "go-failure") else 1
                    self.assertEqual(calls[-1], f"result:1:{ready}")
                    self.assertNotIn("setup_pi_mcp_adapter", calls)
                    self.assertNotIn("refresh_pi_packages", calls)
                    if scenario in ("permissions-failure", "askclaude-failure", "retirement-failure", "pi-failure"):
                        self.assertNotIn("go", calls)
                    if scenario in ("permissions-failure", "askclaude-failure"):
                        self.assertNotIn("retirement", calls)
                        self.assertNotIn("pi-install", calls)
                        self.assertIn("setup_matt_pocock_skills", calls)
                    self.assertEqual("packages" in calls, bool(ready))

    def test_real_catalog_gate_controls_bash_package_work(self):
        fixture = go.GoSetupTests()
        fixture.setUp()
        self.addCleanup(fixture.doCleanups)
        for name in BASH:
            for compatible in (True, False):
                with self.subTest(script=name, compatible=compatible):
                    fixture.put(fixture.catalog, go.TYPED_CATALOG if compatible else {'openai-responses': {}})
                    calls = self.run_bash(name, 'success', fixture)
                    self.assertEqual(calls[-1], 'result:0:1' if compatible else 'result:1:0')
                    self.assertEqual('refresh_pi_packages' in calls, compatible)
                    self.assertEqual('packages' in calls, compatible)

    def test_macos_legacy_unverified_tools_do_not_block_packages(self):
        calls = self.run_bash('mac.sh', 'developer-tools-unverified')
        self.assertEqual(calls, self.run_bash('mac.sh', 'success'))

    @unittest.skipUnless(PWSH, "Set PWSH_BIN for PowerShell main-block fixtures")
    def test_powershell_wiring_and_failure_aggregation(self):
        main = (ROOT / "win.ps1").read_text().split("function Invoke-WindowsSetupTasks {", 1)[1]
        block = main[main.index("    if (-not (Prepare-PiProfilePermissions))"):
                     main.index("    if (-not (Remove-SimpleEnglishSkill))")]
        inert = ("Remove-RtkResources", "Remove-AttentionSpanResources", "Setup-MattPocockSkills",
                 "Set-PiDefaults", "Remove-PiSyntheticModels", "Seed-PiZaiModels",
                 "Setup-PiMcpAdapter", "Remove-PiSubagents", "Remove-PiRpivPackages",
                 "Setup-PiClaudeBridge", "Setup-PiCompanionPackages", "Setup-PiGoalAutoresearch", "Update-PiPackages")
        code = "$ErrorActionPreference = 'Stop'\n$script:calls = @()\n"
        code += "$piSetupFailed = $false\n$piOpenCodeGoReady = $false\n$script:PiRuntimePreflightPassed = $false\n"
        code += "function Write-Warning { param($Message) }\nfunction Test-EnvLocalFlag { $false }\n"
        code += "\n".join(f"function {fn} {{ $script:calls += '{fn}'; $true }}" for fn in inert)
        code += r'''
function Prepare-PiProfilePermissions { $script:calls += 'permissions'; $env:SCENARIO -ne 'permissions-failure' }
function Disable-PiAskClaude { $script:calls += 'askclaude'; $env:SCENARIO -ne 'askclaude-failure' }
function Remove-PiProse { $script:calls += 'retirement'; $env:SCENARIO -ne 'retirement-failure' }
function Install-PiCli { $script:calls += 'pi-install'; $env:SCENARIO -ne 'pi-failure' }
function Prepare-PiMcpAdapter { $script:calls += 'packages'; $env:SCENARIO -ne 'package-failure' }
function Set-PiOpenCodeGoProvider { $script:calls += 'go'; $env:SCENARIO -ne 'go-failure' }
'''
        # Real wrapper is installed only after all other effects are mocked.
        real_code = code + '\nfunction Write-Success {}\nfunction Write-Debug {}\n' + go.wrapper('win.ps1')
        finish = "\n@{failed=$piSetupFailed;ready=$piOpenCodeGoReady;calls=$script:calls} | ConvertTo-Json -Compress\n"
        real_code += '\n' + block + finish
        code += block + finish
        catalog_fixture = go.GoSetupTests()
        catalog_fixture.setUp()
        self.addCleanup(catalog_fixture.doCleanups)
        with tempfile.TemporaryDirectory() as tmp:
            fixture = Path(tmp) / "wiring.ps1"
            fixture.write_text(code)
            for scenario in ("success", "permissions-failure", "askclaude-failure", "retirement-failure", "pi-failure", "go-failure",
                             "package-failure", "typed-catalog", "incompatible-catalog"):
                with self.subTest(scenario=scenario):
                    real_catalog = scenario.endswith('-catalog')
                    fixture.write_text(real_code if real_catalog else code)
                    catalog_fixture.put(catalog_fixture.catalog, go.TYPED_CATALOG if scenario == 'typed-catalog' else {})
                    result = subprocess.run(
                        [PWSH, "-NoProfile", "-NonInteractive", "-File", str(fixture)], cwd=tmp,
                        env={**(catalog_fixture.env if real_catalog else {"PATH": os.environ["PATH"], "HOME": tmp}),
                             "SCENARIO": scenario},
                        text=True, capture_output=True, timeout=20,
                    )
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    state = json.loads(result.stdout.splitlines()[-1])
                    success = scenario in ('success', 'typed-catalog')
                    self.assertEqual(state["failed"], not success)
                    ready = scenario in ("success", "package-failure", "typed-catalog")
                    self.assertEqual(state["ready"], ready)
                    self.assertEqual('Update-PiPackages' in state['calls'], success)
                    if not success:
                        self.assertNotIn('Setup-PiMcpAdapter', state['calls'])
                        self.assertNotIn('Update-PiPackages', state['calls'])
                    self.assertEqual("packages" in state["calls"], ready)
                    if scenario in ("permissions-failure", "askclaude-failure"):
                        self.assertNotIn("retirement", state["calls"])
                        self.assertNotIn("pi-install", state["calls"])
                        self.assertIn("Setup-MattPocockSkills", state["calls"])
                    if scenario == "success":
                        self.assertLess(state["calls"].index("permissions"), state["calls"].index("askclaude"))
                        self.assertLess(state["calls"].index("askclaude"), state["calls"].index("retirement"))
                        self.assertLess(state["calls"].index("pi-install"), state["calls"].index("go"))
                        self.assertLess(state["calls"].index("go"), state["calls"].index("packages"))
                        self.assertLess(state["calls"].index("packages"), state["calls"].index("Setup-PiMcpAdapter"))


if __name__ == "__main__":
    unittest.main()
