import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ("mac.sh", "ubuntu.sh", "wsl.sh", "pi.sh", "bazzite.sh")
DOTFILES_SETTINGS = {
    "defaultProvider": "openai",
    "defaultModel": "gpt-6.1-sol",
    "defaultThinkingLevel": "xhigh",
    "enabledModels": ["openai/gpt-6.1-sol", "openai-codex/gpt-6.1-sol", "openai-codex/gpt-6-astra"],
    "modelThinkingLevels": {"openai/gpt-6.1-sol": "max", "openai-codex/gpt-6-astra": "xhigh"},
}


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value) + "\n")


class ModelDefaultsTests(unittest.TestCase):
    def run_function(self, script, home, agent, name, work="0"):
        source = (ROOT / script).read_text()
        functions = []
        for function in ("read_env_local_value", "remove_pi_synthetic_models", "seed_pi_zai_models"):
            match = re.search(rf"^{function}\(\) \{{\n.*?^\}}", source, re.M | re.S)
            self.assertIsNotNone(match, (script, function))
            functions.append(match[0])
        prelude = "set -euo pipefail\n"
        for logger in ("print_warning", "print_success", "print_debug"):
            prelude += f'{logger}() {{ printf "%s\\n" "$1"; }}\n'
        env = dict(os.environ, HOME=str(home), WORK_MACHINE=work)
        env.pop("PI_CODING_AGENT_DIR", None)
        if agent is not None:
            env["PI_CODING_AGENT_DIR"] = str(agent)
        return subprocess.run(
            ["bash", "-c", prelude + "\n".join(functions) + "\n" + name],
            env=env, capture_output=True, text=True, check=False,
        )

    def test_wiring_and_retired_integration_absent(self):
        for script in (*SCRIPTS, "win.ps1"):
            with self.subTest(script=script):
                source = (ROOT / script).read_text()
                self.assertNotRegex(source, r"Kimi-K3|Kimi K3|SYNTHETIC_API_KEY|api\.synthetic\.new")
                self.assertNotRegex(source, r"seed_pi_synthetic_models|Seed-PiSyntheticModels|pi_zai_key_available|Test-PiZaiKeyAvailable")
                self.assertNotRegex(source, r"configure_pi_defaults|Set-PiDefaults|defaultProvider|defaultModel|"
                                            r"defaultThinkingLevel|modelThinkingLevels")
                names = ("Remove-PiSyntheticModels", "Seed-PiZaiModels") if script == "win.ps1" else (
                    "remove_pi_synthetic_models", "seed_pi_zai_models")
                positions = []
                for name in names:
                    calls = list(re.finditer(rf"^ +{name}$", source, re.M))
                    self.assertEqual(len(calls), 1, name)
                    positions.append(calls[0].start())
                self.assertEqual(positions, sorted(positions))
                if script != "win.ps1":
                    subprocess.run(["bash", "-n", str(ROOT / script)], check=True)

    def test_dotfiles_defaults_preserved_on_all_machine_types(self):
        for script in SCRIPTS:
            for work in ("", "0", "1"):
                for custom in (False, True):
                    for key in (False, True):
                        with self.subTest(script=script, work=work, custom=custom, key=key), tempfile.TemporaryDirectory() as tmp:
                            home = Path(tmp)
                            agent = home / ("custom agent" if custom else ".pi/agent")
                            env_file = home / ".env.local"
                            env_file.write_text(f"WORK_MACHINE={work}\nSYNTHETIC_API_KEY=fixture-retired\n" +
                                                ("export ZAI_API_KEY='fixture-zai'\n" if key else ""))
                            initial_env = env_file.read_bytes()
                            settings = agent / "settings.json"
                            write_json(settings, DOTFILES_SETTINGS)
                            write_json(agent / "models.json", {"providers": {"synthetic": {"apiKey": "fixture-retired"}}})
                            write_json(agent / "auth.json", {"openai-codex": {"type": "oauth", "fixture": True}})
                            settings_before = settings.read_bytes()
                            auth_before = (agent / "auth.json").read_bytes()
                            for _ in range(2):
                                for name, status in (("remove_pi_synthetic_models", 0),
                                                     ("seed_pi_zai_models", int(work == "1" and not key))):
                                    result = self.run_function(script, home, agent if custom else None, name, work)
                                    self.assertEqual(result.returncode, status, result.stderr)
                                self.assertEqual(settings.read_bytes(), settings_before)
                            self.assertEqual(env_file.read_bytes(), initial_env)
                            self.assertEqual((agent / "auth.json").read_bytes(), auth_before)

    def test_provider_removal_and_optional_zai(self):
        for script in SCRIPTS:
            for custom in (False, True):
                with self.subTest(script=script, custom=custom), tempfile.TemporaryDirectory() as tmp:
                    home = Path(tmp)
                    agent = home / ("custom agent" if custom else ".pi/agent")
                    argument = agent if custom else None
                    models = agent / "models.json"
                    self.assertEqual(self.run_function(script, home, argument, "remove_pi_synthetic_models").returncode, 0)
                    self.assertFalse(models.exists())
                    initial = {"keep": [1, 2], "providers": {
                        "synthetic": {"apiKey": "fixture-retired", "models": [{"id": "hf:moonshotai/Kimi-K3"}]},
                        "custom": {"apiKey": "fixture-custom", "models": [{"id": "other"}]}}}
                    write_json(models, initial)
                    write_json(agent / "auth.json", {"synthetic": {"key": "fixture-auth"}})
                    auth_before = (agent / "auth.json").read_bytes()
                    env_file = home / ".env.local"
                    env_file.write_text("SYNTHETIC_API_KEY=fixture-retired\nZAI_API_KEY=fixture-zai\n")
                    env_before = env_file.read_bytes()
                    result = self.run_function(script, home, argument, "remove_pi_synthetic_models")
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertNotIn("fixture-", (result.stdout + result.stderr).replace(str(home), "<HOME>"))
                    del initial["providers"]["synthetic"]
                    self.assertEqual(json.loads(models.read_text()), initial)
                    before = models.read_bytes()
                    self.assertEqual(self.run_function(script, home, argument, "remove_pi_synthetic_models").returncode, 0)
                    self.assertEqual(models.read_bytes(), before)
                    self.assertEqual(models.stat().st_mode & 0o777, 0o600)
                    for work in ("0", "1"):
                        write_json(models, initial)
                        result = self.run_function(script, home, argument, "seed_pi_zai_models", work)
                        self.assertEqual(result.returncode, 0, result.stderr)
                        providers = json.loads(models.read_text())["providers"]
                        self.assertNotIn("synthetic", providers)
                        self.assertEqual(providers["custom"], initial["providers"]["custom"])
                        self.assertEqual(providers["zai"]["apiKey"], "fixture-zai")
                        self.assertEqual([m["id"] for m in providers["zai"]["models"]], ["glm-5.3", "glm-5-turbo", "glm-4.7"])
                    self.assertEqual(env_file.read_bytes(), env_before)
                    self.assertEqual((agent / "auth.json").read_bytes(), auth_before)
                    providers["zai"]["apiKey"] = "fixture-existing"
                    write_json(models, {"providers": providers})
                    self.assertEqual(self.run_function(script, home, argument, "seed_pi_zai_models").returncode, 0)
                    self.assertEqual(json.loads(models.read_text())["providers"]["zai"]["apiKey"], "fixture-existing")

    def test_symlinks_and_invalid_files(self):
        for script in SCRIPTS:
            with self.subTest(script=script), tempfile.TemporaryDirectory() as tmp:
                home = Path(tmp)
                agent = home / "agent"
                agent.mkdir()
                value = {"providers": {"synthetic": {}}}
                target = home / "models.json"
                path = agent / "models.json"
                write_json(target, value)
                path.symlink_to(target)
                self.assertEqual(self.run_function(script, home, agent, "remove_pi_synthetic_models").returncode, 0)
                self.assertTrue(path.is_symlink())
                self.assertNotEqual(json.loads(target.read_text()), value)
                for invalid in ("{not-json", '[{"providers":{"synthetic":{}}}]', "", "null",
                                '{"providers":[]}', '{"providers":"invalid"}'):
                    target.write_text(invalid)
                    self.assertNotEqual(self.run_function(script, home, agent, "remove_pi_synthetic_models").returncode, 0)
                    self.assertEqual(target.read_text(), invalid)
                path.unlink()
                for value in ({}, {"providers": None}, {"providers": {"custom": {}}}):
                    path = agent / "models.json"
                    write_json(path, value)
                    before = path.read_bytes()
                    self.assertEqual(self.run_function(script, home, agent, "remove_pi_synthetic_models").returncode, 0)
                    self.assertEqual(path.read_bytes(), before)


if __name__ == "__main__":
    unittest.main()
