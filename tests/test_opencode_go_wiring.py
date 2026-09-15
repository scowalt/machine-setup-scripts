"""Exercise only the setup entry-point's Pi/Go/profile block with inert functions."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
BASH = ("mac.sh", "ubuntu.sh", "wsl.sh", "pi.sh", "bazzite.sh")
PWSH = os.environ.get("PWSH_BIN") or shutil.which("pwsh")


class WiringTests(unittest.TestCase):
    def bash_block(self, name):
        main = (ROOT / name).read_text().split("run_setup_tasks() {", 1)[1]
        begin = main.index("    if ! prepare_pi_profile_permissions; then")
        end = re.search(r"^    (?:if ! )?remove_simple_english_skill", main, re.M).start()
        block = main[begin:end]
        if name == "pi.sh":
            # Pi configures its shell between these blocks; that work is not executed.
            gate = '    if [[ "${PASEO_MUSE_DEFER_DAEMON_SETUP:-0}" != "1" ]]; then'
            begin = main.index(gate)
            block += main[begin:main.index("    fi", begin) + len("    fi")]
        return block

    def run_bash(self, name, scenario):
        # Only the selected main block is executed, never a full setup script.
        inert = (
            "remove_rtk_resources", "remove_attention_span_resources", "setup_matt_pocock_skills",
            "configure_pi_defaults", "remove_pi_synthetic_models", "seed_pi_zai_models",
            "setup_pi_mcp_adapter", "remove_pi_subagents", "remove_pi_rpiv_packages",
            "setup_pi_claude_bridge", "setup_pi_companion_packages", "setup_pi_goal_autoresearch",
        )
        code = "set -eu\n_setup_had_errors=0\n_pi_go_ready=0\nPI_RUNTIME_PREFLIGHT_PASSED=0\n"
        code += "PI_PROFILE_MUTATIONS_BLOCKED=0\n"
        code += "record() { printf '%s\\n' \"$1\"; }\n"
        code += "print_warning() { :; }; print_section() { :; }\n"
        code += "\n".join(f"{fn}() {{ record {fn}; }}" for fn in inert)
        code += r'''
prepare_pi_profile_permissions() { record permissions; [[ "${SCENARIO}" != permissions-failure ]]; }
remove_pi_prose() { record retirement; [[ "${SCENARIO}" != retirement-failure ]]; }
install_pi_cli() { record pi-install; [[ "${SCENARIO}" != pi-failure ]]; }
prepare_pi_mcp_adapter() { record packages; [[ "${SCENARIO}" != package-failure ]]; }
configure_pi_opencode_go() { record go; [[ "${SCENARIO}" != go-failure ]]; }
configure_paseo_muse_profile() {
    record muse
    case "${SCENARIO}" in
        deferred) PASEO_MUSE_DEFER_DAEMON_SETUP=1 ;;
        profile-failure) PASEO_MUSE_DEFER_DAEMON_SETUP=1; return 1 ;;
    esac
}
setup_headless_paseo_daemon() { record daemon; }
exercise() {
'''
        code += self.bash_block(name)
        code += '\n}\nexercise\nprintf "result:%s:%s\\n" "${_setup_had_errors}" "${_pi_go_ready}"\n'
        with tempfile.TemporaryDirectory() as tmp:
            fixture = Path(tmp) / "wiring.sh"
            fixture.write_text(code)
            result = subprocess.run(
                ["bash", str(fixture)], cwd=tmp,
                env={"PATH": os.environ["PATH"], "HOME": tmp, "SCENARIO": scenario},
                text=True, capture_output=True, timeout=20,
            )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result.stdout.splitlines()

    def test_bash_success_and_order(self):
        for name in BASH:
            with self.subTest(script=name):
                calls = self.run_bash(name, "success")
                self.assertEqual(calls[-1], "result:0:1")
                self.assertLess(calls.index("permissions"), calls.index("retirement"))
                self.assertLess(calls.index("pi-install"), calls.index("go"))
                self.assertLess(calls.index("packages"), calls.index("muse"))
                if name != "wsl.sh":
                    self.assertLess(calls.index("muse"), calls.index("daemon"))
                else:
                    self.assertNotIn("daemon", calls)

    def test_failures_are_aggregated_and_deferred_updates_do_not_restart(self):
        for name in BASH:
            for scenario in ("permissions-failure", "retirement-failure", "pi-failure", "go-failure",
                             "package-failure", "profile-failure", "deferred"):
                with self.subTest(script=name, scenario=scenario):
                    calls = self.run_bash(name, scenario)
                    failed = 0 if scenario == "deferred" else 1
                    ready = 0 if scenario in ("permissions-failure", "retirement-failure", "pi-failure", "go-failure") else 1
                    self.assertEqual(calls[-1], f"result:{failed}:{ready}")
                    self.assertEqual("muse" in calls, bool(ready))
                    if not ready or scenario in ("deferred", "profile-failure"):
                        self.assertNotIn("daemon", calls)
                    if scenario in ("permissions-failure", "retirement-failure", "pi-failure"):
                        self.assertNotIn("go", calls)
                    if scenario == "permissions-failure":
                        self.assertNotIn("retirement", calls)
                        self.assertNotIn("pi-install", calls)
                        self.assertIn("setup_matt_pocock_skills", calls)
                    self.assertEqual("packages" in calls, bool(ready))

    @unittest.skipUnless(PWSH, "Set PWSH_BIN for PowerShell main-block fixtures")
    def test_powershell_wiring_and_failure_aggregation(self):
        main = (ROOT / "win.ps1").read_text().split("function Invoke-WindowsSetupTasks {", 1)[1]
        block = main[main.index("    if (-not (Prepare-PiProfilePermissions))"):
                     main.index("    if (-not (Remove-SimpleEnglishSkill))")]
        inert = ("Remove-RtkResources", "Remove-AttentionSpanResources", "Setup-MattPocockSkills",
                 "Set-PiDefaults", "Remove-PiSyntheticModels", "Seed-PiZaiModels",
                 "Setup-PiMcpAdapter", "Remove-PiSubagents", "Remove-PiRpivPackages",
                 "Setup-PiClaudeBridge", "Setup-PiCompanionPackages", "Setup-PiGoalAutoresearch")
        code = "$ErrorActionPreference = 'Stop'\n$script:calls = @()\n"
        code += "$piSetupFailed = $false\n$piOpenCodeGoReady = $false\n$script:PiRuntimePreflightPassed = $false\n"
        code += "function Write-Warning { param($Message) }\nfunction Test-EnvLocalFlag { $false }\n"
        code += "\n".join(f"function {fn} {{ $script:calls += '{fn}'; $true }}" for fn in inert)
        code += r'''
function Prepare-PiProfilePermissions { $script:calls += 'permissions'; $env:SCENARIO -ne 'permissions-failure' }
function Remove-PiProse { $script:calls += 'retirement'; $env:SCENARIO -ne 'retirement-failure' }
function Install-PiCli { $script:calls += 'pi-install'; $env:SCENARIO -ne 'pi-failure' }
function Prepare-PiMcpAdapter { $script:calls += 'packages'; $env:SCENARIO -ne 'package-failure' }
function Set-PiOpenCodeGoProvider { $script:calls += 'go'; $env:SCENARIO -ne 'go-failure' }
function Set-PaseoMuseProfile { $script:calls += 'muse'; $env:SCENARIO -ne 'profile-failure' }
'''
        code += block
        code += "\n@{failed=$piSetupFailed;ready=$piOpenCodeGoReady;calls=$script:calls} | ConvertTo-Json -Compress\n"
        with tempfile.TemporaryDirectory() as tmp:
            fixture = Path(tmp) / "wiring.ps1"
            fixture.write_text(code)
            for scenario in ("success", "permissions-failure", "retirement-failure", "pi-failure", "go-failure",
                             "package-failure", "profile-failure"):
                with self.subTest(scenario=scenario):
                    result = subprocess.run(
                        [PWSH, "-NoProfile", "-NonInteractive", "-File", str(fixture)], cwd=tmp,
                        env={"PATH": os.environ["PATH"], "HOME": tmp, "SCENARIO": scenario},
                        text=True, capture_output=True, timeout=20,
                    )
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    state = json.loads(result.stdout.splitlines()[-1])
                    self.assertEqual(state["failed"], scenario != "success")
                    ready = scenario in ("success", "package-failure", "profile-failure")
                    self.assertEqual(state["ready"], ready)
                    self.assertEqual("muse" in state["calls"], ready)
                    self.assertEqual("packages" in state["calls"], ready)
                    if scenario == "permissions-failure":
                        self.assertNotIn("retirement", state["calls"])
                        self.assertNotIn("pi-install", state["calls"])
                        self.assertIn("Setup-MattPocockSkills", state["calls"])
                    if scenario == "success":
                        self.assertLess(state["calls"].index("pi-install"), state["calls"].index("go"))
                        self.assertLess(state["calls"].index("packages"), state["calls"].index("muse"))


if __name__ == "__main__":
    unittest.main()
