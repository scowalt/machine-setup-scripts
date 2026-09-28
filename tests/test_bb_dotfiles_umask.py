"""Exercise Ubuntu's real dotfile call sites; native apply uses only inert fixtures.

Set CHEZMOI_BIN to a native binary to override discovery. No real dotfiles source,
Git configuration, source scripts, network, services, or setup entry point run.
"""
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

from test_bb_directory_preflight import RUN_PREFLIGHT


ROOT = pathlib.Path(__file__).resolve().parents[1]
PYTHON = str(pathlib.Path(sys.executable).resolve())
CHEZMOI = os.environ.get("CHEZMOI_BIN") or shutil.which("chezmoi")
if CHEZMOI:
    CHEZMOI = str(pathlib.Path(CHEZMOI).resolve())
DIRECTORIES = (".config", ".config/systemd", ".config/systemd/user")

# Record the process boundary, not a test-only reimplementation of umask policy.
# Native mode permits exactly the full-apply operation, with explicit disposable
# destinations. Init/update network and Git operations remain inert recordings.
CHEZMOI_FIXTURE = r'''
import json, os, pathlib, sys
mask = os.umask(0)
os.umask(mask)
with open(os.environ["FIXTURE_CALLS"], "a") as log:
    log.write(json.dumps({"command": "chezmoi", "args": sys.argv[1:], "umask": f"{mask:04o}"}) + "\n")
if os.environ.get("FIXTURE_FAIL"):
    sys.exit(int(os.environ["FIXTURE_FAIL"]))
if os.environ.get("FIXTURE_NATIVE") == "1":
    assert sys.argv[1:] == ["apply", "--force"], "Only isolated native apply is allowed"
    root = pathlib.Path(os.environ["FIXTURE_ROOT"])
    native = os.environ["FIXTURE_NATIVE_BIN"]
    os.execv(native, [native, "--source", str(root / "source"),
        "--destination", os.environ["HOME"], "--config", str(root / "chezmoi.toml"),
        "--cache", str(root / "cache"), "--persistent-state", str(root / "state.boltdb"),
        "--working-tree", str(root / "source"), "--no-tty", "--no-pager", *sys.argv[1:]])
'''
GIT_FIXTURE = r'''
import json, os, sys
with open(os.environ["FIXTURE_CALLS"], "a") as log:
    log.write(json.dumps({"command": "git", "args": sys.argv[1:]}) + "\n")
assert sys.argv[1:3] == ["-C", os.environ["HOME"] + "/.local/share/chezmoi"]
assert sys.argv[3:] in (["reset", "--hard", "HEAD"], ["merge", "--abort"], ["clean", "-fd"])
'''


def function(source, name):
    start = source.index(name + "() {")
    return source[start:source.index("\n}\n", start) + 3]


class BbDotfilesUmaskTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="bb-dotfiles-umask-")
        self.addCleanup(temporary.cleanup)
        self.root = pathlib.Path(temporary.name)
        self.home = self.root / "home"
        self.home.mkdir(mode=0o750)
        self.home.chmod(0o750)
        self.source = self.root / "source"
        for relative in DIRECTORIES:
            target = self.home / relative
            target.mkdir(parents=True, exist_ok=True)
            target.chmod(0o755)
            source_dir = self.source / relative.replace(".config", "dot_config", 1)
            source_dir.mkdir(parents=True, exist_ok=True)
            source_dir.chmod(0o775)
        (self.source / "dot_config/systemd/user/fixture.txt").write_text("inert fixture\n")
        self.config = self.root / "chezmoi.toml"
        self.config.write_text("[git]\nautoCommit = false\nautoPush = false\nautoPull = false\n")
        self.protected = [self.config, self.home]
        for relative in (".env.local", ".bashrc", ".bb/project.txt", ".pi/agent/auth.json",
                         ".config/systemd/user/unrelated.service"):
            path = self.home / relative
            path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
            path.write_text("inert preservation sentinel\n")
            path.chmod(0o600)
            self.protected.append(path)
        unrelated = self.home / ".config/unrelated"
        unrelated.mkdir()
        unrelated.chmod(0o775)
        self.protected.append(unrelated)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        for name, content in (("chezmoi", CHEZMOI_FIXTURE), ("git", GIT_FIXTURE)):
            binary = self.bin / name
            binary.write_text(f"#!{PYTHON}\n" + content)
            binary.chmod(0o700)
        for name in ("curl", "wget", "ssh", "sudo", "systemctl", "loginctl", "tailscale", "npm"):
            binary = self.bin / name
            binary.write_text('#!/bin/bash\nprintf "%s\\n" "$0" >> "$FIXTURE_ROOT/unexpected"\nexit 97\n')
            binary.chmod(0o700)
        # No inherited GIT_*, BASH_ENV, credentials, hooks, XDG paths or tool controls.
        self.env = {"PATH": f"{self.bin}:/usr/bin:/bin", "HOME": str(self.home), "LC_ALL": "C",
                    "XDG_CONFIG_HOME": str(self.root / "xdg-config"),
                    "XDG_CACHE_HOME": str(self.root / "xdg-cache"),
                    "XDG_DATA_HOME": str(self.root / "xdg-data"),
                    "XDG_STATE_HOME": str(self.root / "xdg-state"),
                    "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_SYSTEM": "/dev/null",
                    "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_TERMINAL_PROMPT": "0",
                    "FIXTURE_ROOT": str(self.root), "FIXTURE_CALLS": str(self.root / "calls"),
                    "BB_SERVER": "1"}
        source = (ROOT / "ubuntu.sh").read_text()
        helpers = [function(source, name) for name in ("initialize_chezmoi", "update_chezmoi")]
        # Allow the pre-fix version to reach the actual native regression, not
        # fail on a missing new symbol before it can reproduce the user's bug.
        if "with_bb_dotfiles_umask() {" in source:
            helpers.insert(0, function(source, "with_bb_dotfiles_umask"))
        start = source.index("bb_server_platform_ready() {")
        helpers.append(source[start:source.index("\nrun_setup_tasks() {", start)])
        self.helpers = self.root / "helpers.sh"
        self.helpers.write_text("\n".join(helpers))
        main = source[source.index("\nrun_setup_tasks() {"):]
        apply = re.search(r"^        if ! [^\n]*chezmoi apply --force; then\n.*?^        fi$", main, re.M | re.S)
        self.assertIsNotNone(apply, "Full-apply call site not found")
        self.full_apply = apply.group()

    def run_stage(self, stage="apply", mask="0002", selection="1", method="ssh", native=False, fail=""):
        env = dict(self.env, DOTFILES_ACCESS_METHOD=method, FIXTURE_FAIL=fail)
        if selection is None:
            env.pop("BB_SERVER")
        else:
            env["BB_SERVER"] = selection
        if native:
            if not CHEZMOI:
                self.skipTest("Native Chezmoi unavailable; set CHEZMOI_BIN for integration coverage")
            env.update(FIXTURE_NATIVE="1", FIXTURE_NATIVE_BIN=CHEZMOI)
        checkout = self.home / ".local/share/chezmoi"
        if stage == "init" and checkout.exists():
            # Only empty fixture directories; never discard a real checkout.
            (checkout / ".git").rmdir()
            checkout.rmdir()
        if stage == "update":
            (checkout / ".git").mkdir(parents=True, exist_ok=True)
        (self.root / "calls").unlink(missing_ok=True)
        before = self.snapshot()
        operation = {"apply": f"_setup_had_errors=0\n{self.full_apply}\nresult=$_setup_had_errors",
                     "init": "initialize_chezmoi; result=$?",
                     "update": "update_chezmoi; result=$?"}[stage]
        result = subprocess.run(["bash", "--noprofile", "--norc", "-c", r'''
source "$1"
print_message() { printf 'INFO: %s\n' "$1"; }
print_success() { printf 'SUCCESS: %s\n' "$1"; }
print_error() { printf 'ERROR: %s\n' "$1"; }
print_warning() { printf 'WARNING: %s\n' "$1"; }
print_debug() { printf 'DEBUG: %s\n' "$1"; }
umask "$2"
''' + operation + '\nprintf "CALLER_MASK=%s\\n" "$(umask)"\nexit "$result"\n',
            "_", str(self.helpers), mask], env=env, text=True, capture_output=True, timeout=20)
        self.assertFalse((self.root / "unexpected").exists(), "Unexpected external command")
        self.assertEqual(result.stderr, "", result)
        self.assertIn(f"CALLER_MASK={mask}\n", result.stdout, "Subprocess changed caller umask")
        self.assertEqual(self.snapshot(), before, "Changed unrelated content/modes or native config")
        return result

    def snapshot(self):
        return [(path.lstat().st_mode, path.lstat().st_uid,
                 path.read_bytes() if path.is_file() else None) for path in self.protected]

    def calls(self, command="chezmoi"):
        return [entry for line in (self.root / "calls").read_text().splitlines()
                if (entry := json.loads(line))["command"] == command]

    def preflight(self):
        result = subprocess.run(["bash", "--noprofile", "--norc", "-c", RUN_PREFLIGHT,
                                 "_", str(self.helpers), str(self.home), "", ""],
                                env=self.env, text=True, capture_output=True, timeout=10)
        # The fixture stops at the next gate after the *real* directory checks.
        self.assertEqual(result.returncode, 1, result)
        self.assertEqual(result.stderr, "", result)
        self.assertNotIn("UNEXPECTED_COMMAND", result.stdout)
        return result.stdout

    def test_native_apply_does_not_undo_manual_correction_before_bb(self):
        for attempt in range(2):
            with self.subTest(attempt=attempt):
                for relative in DIRECTORIES:
                    (self.home / relative).chmod(0o755)
                result = self.run_stage(native=True)
                self.assertEqual(result.returncode, 0, result)
                # Assert the user's symptom through the actual setup preflight.
                self.assertEqual(self.preflight(), "DIRECTORY_PREFLIGHT_PASSED\n")
                self.assertEqual([((self.home / p).stat().st_mode & 0o777) for p in DIRECTORIES],
                                 [0o755, 0o755, 0o755])

    def test_every_directory_applying_call_site_scopes_the_opt_in_mask(self):
        stages = (
            ("init", "ssh", ["init", "--apply", "--force", "scowalt/dotfiles", "--ssh"]),
            ("init", "token", ["init", "--apply", "--force", "https://github.com/scowalt/dotfiles.git"]),
            ("init", "deploy", ["init", "--apply", "--force", "git@github-dotfiles:scowalt/dotfiles.git"]),
            ("update", "", ["update", "--force"]),
            ("apply", "", ["apply", "--force"]),
        )
        for selection in (None, "", "0", "invalid", "1"):
            for mask, restricted in (("0000", "0022"), ("0002", "0022"), ("0022", "0022"),
                                     ("0027", "0027"), ("0077", "0077")):
                for stage, method, args in stages:
                    with self.subTest(selection=selection, mask=mask, stage=stage, method=method):
                        result = self.run_stage(stage, mask, selection, method)
                        self.assertEqual(result.returncode, 0, result)
                        self.assertEqual(self.calls(), [{"command": "chezmoi", "args": args,
                            "umask": restricted if selection == "1" else mask}])
                        git_args = [["-C", str(self.home / ".local/share/chezmoi"), *args]
                                    for args in (("reset", "--hard", "HEAD"),
                                                 ("merge", "--abort"), ("clean", "-fd"))]
                        self.assertEqual([call["args"] for call in self.calls("git")],
                                         git_args if stage == "update" else [])

    def test_command_failure_still_reaches_existing_caller_error_handling(self):
        for selection in ("0", "1"):
            for stage, method in (("init", "ssh"), ("init", "token"), ("init", "deploy"),
                                  ("update", ""), ("apply", "")):
                with self.subTest(selection=selection, stage=stage, method=method):
                    result = self.run_stage(stage, selection=selection, method=method, fail="17")
                    self.assertIn("Failed to", result.stdout)
                    if stage != "update":
                        self.assertEqual(result.returncode, 1, result)
                    # Update historically warns and continues. Do not hide the
                    # failure by reporting a successful update after the wrapper.
                    self.assertNotIn("SUCCESS:", result.stdout)

    def test_native_apply_converges_existing_writable_and_missing_managed_directories(self):
        for relative in DIRECTORIES:
            (self.home / relative).chmod(0o775)
        for attempt in range(2):
            result = self.run_stage(native=True)
            self.assertEqual(result.returncode, 0, result)
            self.assertEqual(self.preflight(), "DIRECTORY_PREFLIGHT_PASSED\n")
        # A new source-only directory models first provisioning, not just repair.
        (self.source / "dot_config/new-managed-dir").mkdir()
        result = self.run_stage(native=True)
        self.assertEqual(result.returncode, 0, result)
        self.assertEqual((self.home / ".config/new-managed-dir").stat().st_mode & 0o777, 0o755)

    def test_native_source_directory_modes_do_not_determine_target_permissions(self):
        for mode in (0o755, 0o775):
            with self.subTest(source_mode=oct(mode)):
                for relative in DIRECTORIES:
                    (self.source / relative.replace(".config", "dot_config", 1)).chmod(mode)
                result = self.run_stage(native=True)
                self.assertEqual(result.returncode, 0, result)
                self.assertEqual(self.preflight(), "DIRECTORY_PREFLIGHT_PASSED\n")
                self.assertEqual([((self.home / p).stat().st_mode & 0o777) for p in DIRECTORIES],
                                 [0o755, 0o755, 0o755])

    def test_native_stricter_caller_masks_remain_restrictive(self):
        for mask, expected in (("0027", 0o750), ("0077", 0o700)):
            with self.subTest(mask=mask):
                result = self.run_stage(mask=mask, native=True)
                self.assertEqual(result.returncode, 0, result)
                self.assertEqual(self.preflight(), "DIRECTORY_PREFLIGHT_PASSED\n")
                self.assertEqual([((self.home / p).stat().st_mode & 0o777) for p in DIRECTORIES],
                                 [expected, expected, expected])

    def test_native_without_opt_in_retains_inherited_umask_behavior(self):
        for selection in (None, "", "0", "invalid"):
            with self.subTest(selection=selection):
                result = self.run_stage(selection=selection, native=True)
                self.assertEqual(result.returncode, 0, result)
                self.assertEqual([((self.home / p).stat().st_mode & 0o777) for p in DIRECTORIES],
                                 [0o775, 0o775, 0o775])
                self.assertIn("group- or world-writable (mode 775)", self.preflight())

    def test_native_explicit_config_umask_wins_without_being_rewritten(self):
        config = self.config.read_text()
        for mask, expected in (("002", 0o775), ("077", 0o700)):
            with self.subTest(config_umask=mask):
                self.config.write_text(f"umask = 0o{mask}\n" + config)
                result = self.run_stage(native=True)
                self.assertEqual(result.returncode, 0, result)
                self.assertEqual([((self.home / p).stat().st_mode & 0o777) for p in DIRECTORIES],
                                 [expected, expected, expected])
                output = self.preflight()
                if mask == "002":
                    self.assertIn("group- or world-writable (mode 775)", output)
                    self.assertIn("review its explicit umask setting", output)
                    self.assertNotIn("DIRECTORY_PREFLIGHT_PASSED", output)
                else:
                    self.assertEqual(output, "DIRECTORY_PREFLIGHT_PASSED\n")


if __name__ == "__main__":
    unittest.main()
