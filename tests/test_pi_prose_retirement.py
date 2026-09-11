#!/usr/bin/env python3
"""Contract version 1: retire only Pi-managed prose state in temporary homes."""
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ("mac.sh", "ubuntu.sh", "wsl.sh", "pi.sh", "bazzite.sh", "win.ps1")
BEGIN = "// BEGIN PI_PROSE_RETIREMENT"
END = "// END PI_PROSE_RETIREMENT"


def embedded(script):
    source = (ROOT / script).read_text()
    if BEGIN not in source or END not in source:
        raise AssertionError(f"{script}: mandatory pi-prose retirement is missing")
    return source.split(BEGIN, 1)[1].split(END, 1)[0]


class RetirementTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="pi-prose-retirement-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.home = self.root / "home"
        self.home.mkdir()
        self.agent = self.home / ".pi/agent"
        self.custom = self.home / "custom agent"
        self.node = subprocess.run(["node", "-p", "process.execPath"], check=True,
                                   capture_output=True, text=True).stdout.strip()
        self.env = {"HOME": str(self.home), "PATH": str(Path(self.node).parent) + os.pathsep + os.defpath,
                    "LC_ALL": "C"}
        self.engine = embedded("bazzite.sh")

    def seed(self, agent):
        npm = agent / "npm"
        package = npm / "node_modules/pi-prose"
        package.mkdir(parents=True)
        (package / "package.json").write_text(json.dumps({"name": "pi-prose", "version": "0.2.0",
                                                         "scripts": {"uninstall": "exit 99"}}))
        (package / "extension.js").write_text("throw new Error('must never load this extension')")
        settings = {"packages": ["npm:pi-prose", "npm:pi-prose@0.2.0",
                                  {"source": "npm:pi-prose@latest", "extensions": []},
                                  "npm:pi-prose-extra", {"source": "npm:other", "skills": []}],
                    "theme": "keep", "private": "fixture-private"}
        self.write_json(agent / "settings.json", settings)
        (agent / "settings.json").chmod(0o600)
        manifest = {"name": "pi-packages", "dependencies": {"pi-prose": "^0.2.0", "pi-mcp-adapter": "2.33.0"},
                    "devDependencies": {"pi-prose": "0.2.0", "keep": "1"},
                    "optionalDependencies": {"pi-prose": "0.2.0"},
                    "peerDependencies": {"pi-prose": "*", "keep": "*"},
                    "peerDependenciesMeta": {"pi-prose": {"optional": True}, "keep": {"optional": True}},
                    "overrides": {"pi-prose": "0.2.0", "pi-prose@0.1.0": "0.2.0", "other": {"keep": "1"}},
                    "scripts": {"postinstall": "exit 99"}, "other": {"keep": True}}
        self.write_json(npm / "package.json", manifest)
        lock = {"lockfileVersion": 3, "packages": {
            "": {"dependencies": manifest["dependencies"]},
            "node_modules/pi-prose": {"version": "0.2.0"},
            "node_modules/pi-prose/node_modules/private-dependency": {"version": "1"},
            "node_modules/pi-prose-extra": {"version": "1"},
            "node_modules/pi-mcp-adapter": {"version": "2.33.0", "dependencies": {
                "@modelcontextprotocol/client": "https://pkg.pr.new/fixture-blocked-by-npm12"}},
        }, "other": "keep"}
        for file in (npm / "package-lock.json", npm / "npm-shrinkwrap.json", npm / "node_modules/.package-lock.json"):
            self.write_json(file, lock)
        sibling = npm / "node_modules/pi-mcp-adapter/package.json"
        sibling.parent.mkdir()
        sibling.write_text('{"name":"pi-mcp-adapter","keep":true}')
        (npm / ".npmrc").write_text("allow-remote=none\nignore-scripts=true\n")
        (agent / "auth.json").write_text("fixture-secret-auth")
        (agent / "prose").mkdir()
        (agent / "prose/custom.md").write_text("user style")
        (agent / "prose/config.json").write_text("{malformed user prose configuration")
        return settings, manifest, lock

    @staticmethod
    def write_json(file, document):
        file.write_text(json.dumps(document, indent=2) + "\n")

    def run_cleanup(self, custom=None, engine=None):
        return subprocess.run([self.node, "--input-type=commonjs", "-", str(self.home),
                               str(custom) if custom else ""], input=engine or self.engine,
                              env=self.env, cwd=self.root, capture_output=True, text=True, timeout=10)

    def snapshot(self):
        result = {}
        for file in self.root.rglob("*"):
            mode = file.lstat().st_mode
            contents = os.readlink(file) if stat.S_ISLNK(mode) else file.read_bytes() if stat.S_ISREG(mode) else None
            result[str(file.relative_to(self.root))] = (mode, contents)
        return result

    def assert_retired(self, agent):
        self.assertFalse(os.path.lexists(agent / "npm/node_modules/pi-prose"))
        settings = json.loads((agent / "settings.json").read_text())
        self.assertEqual(settings["packages"], ["npm:pi-prose-extra", {"source": "npm:other", "skills": []}])
        self.assertEqual(settings["theme"], "keep")
        self.assertEqual(settings["private"], "fixture-private")
        self.assertEqual(stat.S_IMODE((agent / "settings.json").stat().st_mode), 0o600)
        manifest = json.loads((agent / "npm/package.json").read_text())
        for field in ("dependencies", "devDependencies", "optionalDependencies", "peerDependencies", "peerDependenciesMeta", "overrides"):
            self.assertNotIn("pi-prose", manifest[field])
        self.assertEqual(manifest["dependencies"], {"pi-mcp-adapter": "2.33.0"})
        self.assertEqual(manifest["overrides"], {"other": {"keep": "1"}})
        self.assertEqual(manifest["scripts"], {"postinstall": "exit 99"})
        for relative in ("package-lock.json", "npm-shrinkwrap.json", "node_modules/.package-lock.json"):
            lock = json.loads((agent / "npm" / relative).read_text())
            self.assertNotIn("node_modules/pi-prose", lock["packages"])
            self.assertNotIn("node_modules/pi-prose/node_modules/private-dependency", lock["packages"])
            self.assertIn("node_modules/pi-prose-extra", lock["packages"])
            self.assertEqual(lock["packages"]["node_modules/pi-mcp-adapter"]["dependencies"], {
                "@modelcontextprotocol/client": "https://pkg.pr.new/fixture-blocked-by-npm12"})
        self.assertEqual((agent / "npm/.npmrc").read_text(), "allow-remote=none\nignore-scripts=true\n")
        self.assertEqual((agent / "auth.json").read_text(), "fixture-secret-auth")
        self.assertEqual((agent / "prose/custom.md").read_text(), "user style")
        self.assertEqual((agent / "prose/config.json").read_text(), "{malformed user prose configuration")

    def assert_rejected(self, custom=None):
        before = self.snapshot()
        result = self.run_cleanup(custom)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertNotIn("fixture-private", result.stdout + result.stderr)
        self.assertNotIn("fixture-secret", result.stdout + result.stderr)
        self.assertEqual(self.snapshot(), before, "Preflight failure changed state")

    def test_retirement_and_repeat_preserve_unrelated_state(self):
        self.seed(self.agent)
        self.seed(self.custom)
        result = self.run_cleanup(self.custom)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_retired(self.agent)
        self.assert_retired(self.custom)
        before = self.snapshot()
        times = {p: p.stat().st_mtime_ns for p in self.root.rglob("*") if p.is_file()}
        result = self.run_cleanup(self.custom)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.snapshot(), before)
        self.assertEqual({p: p.stat().st_mtime_ns for p in times}, times)

    def test_identical_profile_paths_are_deduplicated(self):
        self.seed(self.agent)
        result = self.run_cleanup(self.agent)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_retired(self.agent)

    def test_profile_inside_retired_package_is_not_deleted(self):
        self.seed(self.agent)
        nested = self.agent / "npm/node_modules/pi-prose/profile"
        nested.mkdir()
        (nested / "auth.json").write_text("fixture-secret nested-profile")
        self.assert_rejected(nested)

    def test_missing_profiles_are_not_created(self):
        before = self.snapshot()
        result = self.run_cleanup(self.custom)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.snapshot(), before)

    def test_empty_valid_and_malformed_custom_prose_files_are_preserved(self):
        self.seed(self.agent)
        file = self.agent / "prose/config.json"
        for payload in ("", "{}", '{"default":"custom"}', "{malformed"):
            with self.subTest(payload=payload):
                file.write_text(payload)
                result = self.run_cleanup()
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(file.read_text(), payload)
                self.assertFalse((self.agent / "npm/node_modules/pi-prose").exists())

    def test_legacy_lockfile_versions(self):
        self.seed(self.agent)
        for version in (1, 2):
            document = {"lockfileVersion": version, "dependencies": {
                "pi-prose": {"version": "0.2.0", "dependencies": {"owned": {"version": "1"}}},
                "keep": {"version": "1"}}}
            self.write_json(self.agent / "npm/package-lock.json", document)
            result = self.run_cleanup()
            self.assertEqual(result.returncode, 0, result.stderr)
            document["dependencies"].pop("pi-prose")
            self.assertEqual(json.loads((self.agent / "npm/package-lock.json").read_text()), document)

    def test_settings_only_and_orphan_package(self):
        self.agent.mkdir(parents=True)
        self.write_json(self.agent / "settings.json", {"packages": ["npm:pi-prose"]})
        result = self.run_cleanup()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads((self.agent / "settings.json").read_text())["packages"], [])
        (self.agent / "settings.json").unlink()
        package = self.agent / "npm/node_modules/pi-prose"
        package.mkdir(parents=True)
        self.write_json(package / "package.json", {"name": "pi-prose"})
        self.assertEqual(self.run_cleanup().returncode, 0)
        self.assertFalse(package.exists())
        self.assertFalse((self.agent / "settings.json").exists())

    def test_all_json_preflighted_before_either_profile_changes(self):
        self.seed(self.agent)
        self.seed(self.custom)
        for relative, payload in (("settings.json", "{fixture-private malformed"),
                                  ("settings.json", '{"packages":{}}'),
                                  ("settings.json", '{"packages":[null]}'),
                                  ("settings.json", '{"packages":[{"source":42}]}'),
                                  ("npm/package.json", '{"dependencies":[]}'),
                                  ("npm/package-lock.json", '{"lockfileVersion":99}'),
                                  ("npm/node_modules/.package-lock.json", "null")):
            with self.subTest(relative=relative, payload=payload):
                file = self.custom / relative
                original = file.read_bytes()
                file.write_text(payload)
                self.assert_rejected(self.custom)
                file.write_bytes(original)

    def test_linked_metadata_or_profile_ancestors_rejected(self):
        self.seed(self.agent)
        for relative in ("settings.json", "npm/package.json", "npm/package-lock.json", "npm/node_modules/.package-lock.json", "npm/node_modules", "npm", "."):
            with self.subTest(relative=relative):
                file = self.agent / relative
                saved = self.root / "saved"
                file.rename(saved)
                file.symlink_to(saved, target_is_directory=saved.is_dir())
                self.assert_rejected()
                file.unlink()
                saved.rename(file)

    def test_hardlinked_metadata_is_not_replaced(self):
        self.seed(self.agent)
        for relative in ("settings.json", "npm/package.json", "npm/package-lock.json", "npm/node_modules/pi-prose/package.json"):
            with self.subTest(relative=relative):
                other = self.root / "shared-metadata"
                os.link(self.agent / relative, other)
                self.assert_rejected()
                other.unlink()

    def test_explicit_agent_link_and_relative_path_rejected(self):
        self.seed(self.agent)
        target = self.root / "foreign-profile"
        target.mkdir()
        self.custom.symlink_to(target, target_is_directory=True)
        self.assert_rejected(self.custom)
        self.assert_rejected(Path("relative-profile"))

    def test_home_alias_does_not_hide_linked_pi_directories(self):
        self.seed(self.agent)
        logical = self.root / "logical-home"
        logical.symlink_to(self.home, target_is_directory=True)
        self.home = logical
        self.assertEqual(self.run_cleanup().returncode, 0)
        self.assert_retired(self.agent)
        pi_dir = self.agent.parent
        saved = self.root / "linked-pi-source"
        pi_dir.rename(saved)
        pi_dir.symlink_to(saved, target_is_directory=True)
        self.assert_rejected()

    def test_linked_package_is_unlinked_without_touching_its_target(self):
        self.seed(self.agent)
        package = self.agent / "npm/node_modules/pi-prose"
        saved = self.root / "local-source"
        package.rename(saved)
        package.symlink_to(saved, target_is_directory=True)
        original = (saved / "extension.js").read_bytes()
        self.assertEqual(self.run_cleanup().returncode, 0)
        self.assertFalse(os.path.lexists(package))
        self.assertEqual((saved / "extension.js").read_bytes(), original)

    def test_package_child_links_do_not_delete_external_files(self):
        self.seed(self.agent)
        target = self.root / "external"
        target.mkdir()
        (target / "keep").write_text("keep")
        (self.agent / "npm/node_modules/pi-prose/external").symlink_to(target, target_is_directory=True)
        self.assertEqual(self.run_cleanup().returncode, 0)
        self.assertEqual((target / "keep").read_text(), "keep")

    def test_unverified_package_preserved(self):
        self.seed(self.agent)
        file = self.agent / "npm/node_modules/pi-prose/package.json"
        for payload in ('{"name":"user-project"}', '{broken', ''):
            file.write_text(payload)
            self.assert_rejected()
        file.unlink()
        self.assert_rejected()

    def test_no_npm_pi_or_lifecycle_execution(self):
        self.seed(self.agent)
        commands = self.root / "bin"
        commands.mkdir()
        for name in ("npm", "pi"):
            file = commands / name
            file.write_text('#!/bin/sh\nprintf "unexpected package command" >&2\nexit 99\n')
            file.chmod(0o755)
        self.env["PATH"] = str(commands) + os.pathsep + self.env["PATH"]
        result = self.run_cleanup()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_retired(self.agent)

    def test_write_failure_reports_failure_and_preserves_package(self):
        self.seed(self.agent)
        # Replace the filesystem rename function, not the retirement algorithm.
        injected = self.engine.replace("const fs = require('node:fs');", "const fs = require('node:fs'); fs.renameSync = () => { throw new Error('fixture-private'); };")
        self.assertNotEqual(injected, self.engine)
        before = self.snapshot()
        result = self.run_cleanup(engine=injected)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("fixture-private", result.stderr)
        self.assertEqual(self.snapshot(), before)

    def test_failed_package_removal_is_reported_and_retry_finishes(self):
        self.seed(self.agent)
        injected = self.engine.replace("const fs = require('node:fs');", "const fs = require('node:fs'); fs.rmSync = () => { throw new Error('fixture-private'); };")
        package = self.agent / "npm/node_modules/pi-prose"
        original = (package / "extension.js").read_bytes()
        result = self.run_cleanup(engine=injected)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("removed", result.stdout)
        self.assertNotIn("fixture-private", result.stderr)
        self.assertEqual((package / "extension.js").read_bytes(), original)
        self.assertEqual(json.loads((self.agent / "settings.json").read_text())["packages"],
                         ["npm:pi-prose-extra", {"source": "npm:other", "skills": []}])
        result = self.run_cleanup()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_retired(self.agent)

    def test_bash_wrappers_use_both_profiles_and_are_repeatable(self):
        for script in SCRIPTS[:-1]:
            with self.subTest(script=script):
                home = self.home / script
                agent = home / ".pi/agent"
                custom = home / "custom profile"
                self.seed(agent)
                self.seed(custom)
                source = (ROOT / script).read_text()
                block = source.split("# Pi prose retirement.", 1)[1].split("# End Pi prose retirement.", 1)[0]
                block = block[block.index("\nremove_pi_prose() {"):]
                harness = 'set -eu\nprint_error() { printf "%s\\n" "$*" >&2; }; print_debug() { :; }; print_success() { :; }\n'
                harness += 'pi() { return 99; }; npm() { return 99; }\n' + block + '\nremove_pi_prose\n'
                env = {**self.env, "HOME": str(home), "PI_CODING_AGENT_DIR": str(custom)}
                result = subprocess.run(["bash", "-c", harness], env=env, capture_output=True, text=True, timeout=10)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assert_retired(agent)
                self.assert_retired(custom)
                before = self.snapshot()
                result = subprocess.run(["bash", "-c", harness], env=env, capture_output=True, text=True, timeout=10)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(self.snapshot(), before)
                (custom / "settings.json").write_text("{fixture-private malformed")
                before = self.snapshot()
                result = subprocess.run(["bash", "-c", harness], env=env, capture_output=True, text=True, timeout=10)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn("fixture-private", result.stdout + result.stderr)
                self.assertEqual(self.snapshot(), before)

    def test_powershell_wrapper(self):
        pwsh = os.environ.get("PWSH_BIN") or shutil.which("pwsh")
        if not pwsh:
            self.skipTest("Set PWSH_BIN or provide pwsh for the Windows wrapper fixtures")
        self.seed(self.agent)
        self.seed(self.custom)
        harness = r'''
$ErrorActionPreference = 'Stop'
$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($env:SETUP_SCRIPT, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'Invalid Windows setup syntax' }
$definition = $ast.Find({ param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Remove-PiProse'
}, $false)
. ([scriptblock]::Create($definition.Extent.Text))
function Write-Debug($Message) {}
function Write-Success($Message) {}
function Write-Warning($Message) {}
function pi { throw 'Pi must not run' }
function npm { throw 'npm must not run' }
if (-not (Remove-PiProse)) { exit 42 }
'''
        # PowerShell maintains its own caches even with -NoProfile. Keep them
        # outside the target snapshots so they cannot look like cleanup writes.
        runtime = tempfile.TemporaryDirectory(prefix="pi-prose-powershell-runtime-")
        self.addCleanup(runtime.cleanup)
        env = {**self.env, "HOME": runtime.name, "XDG_CACHE_HOME": runtime.name + "/cache",
               "LOCALAPPDATA": runtime.name + "/local", "APPDATA": runtime.name + "/roaming",
               "POWERSHELL_TELEMETRY_OPTOUT": "1", "USERPROFILE": str(self.home),
               "PI_CODING_AGENT_DIR": str(self.custom), "SETUP_SCRIPT": str(ROOT / "win.ps1")}
        result = subprocess.run([pwsh, "-NoProfile", "-Command", harness], env=env, capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_retired(self.agent)
        self.assert_retired(self.custom)
        before = self.snapshot()
        result = subprocess.run([pwsh, "-NoProfile", "-Command", harness], env=env, capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.snapshot(), before)
        (self.custom / "settings.json").write_text("{fixture-private malformed")
        before = self.snapshot()
        result = subprocess.run([pwsh, "-NoProfile", "-Command", harness], env=env, capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 42, result.stderr)
        self.assertEqual(self.snapshot(), before)

    def test_bash_wrapper_handles_missing_node(self):
        source = (ROOT / "bazzite.sh").read_text()
        block = source.split("# Pi prose retirement.", 1)[1].split("# End Pi prose retirement.", 1)[0]
        block = block[block.index("\nremove_pi_prose() {"):]
        harness = 'print_error() { :; }; print_debug() { :; }; print_success() { :; }\n' + block + '\nremove_pi_prose\n'
        command = [shutil.which("bash"), "-c", harness]
        env = {**self.env, "PATH": str(self.root / "missing-bin")}
        self.assertEqual(subprocess.run(command, env=env, capture_output=True).returncode, 0)
        self.seed(self.agent)
        before = self.snapshot()
        self.assertNotEqual(subprocess.run(command, env=env, capture_output=True).returncode, 0)
        self.assertEqual(self.snapshot(), before)

    def test_shared_engines_and_setup_wiring(self):
        canonical = embedded("bazzite.sh")
        for script in SCRIPTS:
            with self.subTest(script=script):
                self.assertEqual(embedded(script), canonical)
                source = (ROOT / script).read_text()
                call = 'if (-not (Remove-PiProse)) { throw "Pi prose retirement failed." }' if script == "win.ps1" else 'remove_pi_prose || return 1'
                install = 'if (Install-PiCli)' if script == "win.ps1" else 'if install_pi_cli; then'
                entry = 'function Invoke-WindowsSetupTasks {' if script == 'win.ps1' else 'run_setup_tasks() {'
                body = source.split(entry, 1)[1]
                self.assertIn(call, body)
                self.assertLess(body.index(call), body.index(install))
                dotfiles = max(body.rfind(command) for command in ('Update-Chezmoi', 'update_chezmoi', 'chezmoi apply --force'))
                self.assertGreater(dotfiles, -1)
                self.assertLess(dotfiles, body.index(call))


if __name__ == "__main__":
    unittest.main()
