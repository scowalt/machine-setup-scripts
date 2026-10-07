import os
import pathlib
import subprocess
import tempfile
import unittest

from extract_setup_fixture import definitions


ROOT = pathlib.Path(__file__).resolve().parents[1]
DIRECTORIES = ("", ".config", ".config/systemd", ".config/systemd/user",
               ".config/setup-bb-server", ".bb")
RUN_PREFLIGHT = r'''
source "$1"
export HOME="$2"
stat_case="$3" stat_target="$4"
print_error() { printf 'ERROR: %s\n' "$1"; }
print_message() { printf 'INFO: %s\n' "$1"; }
print_warning() { printf 'WARNING: %s\n' "$1"; }
command() {
    if [[ "$*" == '-v tailscale' ]]; then printf '/usr/bin/tailscale\n'; return 0; fi
    builtin command "$@"
}
stat() {
    if [[ "${*: -1}" == "$stat_target" ]]; then
        case "$stat_case" in
            foreign) printf '%s 755\n' "$(( $(id -u) + 1 ))"; return 0 ;;
            failed) printf 'fixture-secret: raw stat failure\n' >&2; return 1 ;;
            malformed) printf 'fixture-secret invalid-mode\n'; return 0 ;;
        esac
    fi
    builtin command stat "$@"
}
# The first gate after directory validation deliberately stops the fixture.
bb_owned_file() { printf 'DIRECTORY_PREFLIGHT_PASSED\n'; exit 1; }
# A regression must not run package/service/configuration mutations.
for name in systemctl loginctl tailscale npm sudo curl mkdir chmod node python3 mv; do
    eval "$name() { printf 'UNEXPECTED_COMMAND: $name\\n' >&2; return 97; }"
done
setup_bb_server
'''


class BbDirectoryPreflightTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.definitions = definitions((ROOT / 'ubuntu.sh').read_text())

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="bb-directory-preflight-")
        self.addCleanup(self.temporary.cleanup)
        self.root = pathlib.Path(self.temporary.name)
        self.home = self.root / "home"
        for relative in DIRECTORIES:
            directory = self.home / relative
            directory.mkdir(parents=True, exist_ok=True)
            directory.chmod(0o755 if relative else 0o750)
        self.helpers = self.root / "helpers.sh"
        self.helpers.write_text(self.definitions)

    def snapshot(self):
        paths = [self.root]
        for directory, dirs, files in os.walk(self.root, followlinks=False):
            paths.extend(pathlib.Path(directory) / name for name in dirs + files)
        return {str(path.relative_to(self.root)): (path.lstat().st_mode,
                path.lstat().st_uid, os.readlink(path) if path.is_symlink()
                else path.read_bytes() if path.is_file() else None) for path in paths}

    def run_preflight(self, stat_case="", target="", home=None):
        before = self.snapshot()
        result = subprocess.run(
            ["bash", "--noprofile", "--norc", "-c", RUN_PREFLIGHT, "_",
             str(self.helpers), str(home or self.home), stat_case, str(target)],
            env={"PATH": "/usr/bin:/bin", "HOME": str(self.home), "LC_ALL": "C"},
            text=True, capture_output=True, timeout=10,
        )
        self.assertEqual(result.returncode, 1, result)
        self.assertEqual(result.stderr, "", result)
        self.assertNotIn("UNEXPECTED_COMMAND", result.stdout + result.stderr)
        self.assertNotIn("fixture-secret", result.stdout + result.stderr)
        self.assertNotIn(str(self.home), result.stdout + result.stderr)
        self.assertEqual(self.snapshot(), before, "Preflight changed fixture state")
        return result.stdout

    def assert_blocked(self, output, relative, reason):
        label = "$HOME" + ("/" + relative if relative else "")
        self.assertIn("BB directory preflight", output)
        self.assertIn(label, output)
        self.assertIn(reason, output)
        self.assertNotIn("DIRECTORY_PREFLIGHT_PASSED", output)

    def test_safe_directories_reach_next_gate(self):
        self.assertEqual(self.run_preflight(), "DIRECTORY_PREFLIGHT_PASSED\n")

    def test_observed_group_writable_directories_keep_modes_without_correction(self):
        for relative in DIRECTORIES:
            with self.subTest(directory=relative):
                directory = self.home / relative
                previous = directory.stat().st_mode & 0o7777
                directory.chmod(0o775)
                try:
                    output = self.run_preflight()
                    self.assertEqual(output, "DIRECTORY_PREFLIGHT_PASSED\n")
                finally:
                    directory.chmod(previous)

    def test_observed_775_config_hierarchy_passes_without_correction(self):
        for relative in (".config", ".config/systemd", ".config/systemd/user"):
            (self.home / relative).chmod(0o775)
        output = self.run_preflight()
        self.assertEqual(output, "DIRECTORY_PREFLIGHT_PASSED\n")

    def test_world_writable_directory_does_not_suggest_group_only_correction(self):
        (self.home / ".config").chmod(0o757)
        output = self.run_preflight()
        self.assert_blocked(output, ".config", "world-writable (mode 757)")
        self.assertNotIn("chmod g-w", output)

    def test_linked_directories_and_external_contents_are_preserved(self):
        for relative in DIRECTORIES:
            with self.subTest(directory=relative):
                directory = self.home / relative
                target = self.root / "link-target"
                directory.rename(target)
                directory.symlink_to(target, target_is_directory=True)
                try:
                    output = self.run_preflight()
                    self.assert_blocked(output, relative, "symbolic link")
                    self.assertNotIn("chmod", output)
                finally:
                    directory.unlink()
                    target.rename(directory)

    def test_non_directory_paths_are_preserved(self):
        for relative in DIRECTORIES:
            with self.subTest(directory=relative):
                directory = self.home / relative
                backup = self.root / "directory-backup"
                directory.rename(backup)
                directory.write_text("fixture-secret: preserve this file\n")
                try:
                    output = self.run_preflight()
                    self.assert_blocked(output, relative, "not a directory")
                    self.assertNotIn("chmod", output)
                finally:
                    directory.unlink()
                    backup.rename(directory)

    def test_ownership_and_metadata_failures_use_controlled_diagnostics(self):
        reasons = {"foreign": "not owned by the setup account",
                   "failed": "could not inspect permissions",
                   "malformed": "invalid ownership or mode metadata"}
        for case, reason in reasons.items():
            for relative in DIRECTORIES:
                with self.subTest(case=case, directory=relative):
                    output = self.run_preflight(case, self.home / relative)
                    self.assert_blocked(output, relative, reason)
                    self.assertNotIn("chmod", output)

    def test_missing_optional_directories_remain_valid(self):
        for relative in sorted((item for item in DIRECTORIES if item),
                               key=lambda item: item.count("/"), reverse=True):
            (self.home / relative).rmdir()
        self.assertEqual(self.run_preflight(), "DIRECTORY_PREFLIGHT_PASSED\n")

    def test_unsupported_home_path_does_not_echo_its_contents(self):
        home = self.root / "fixture-secret home"
        home.mkdir()
        output = self.run_preflight(home=home)
        self.assert_blocked(output, "", "must be an absolute supported path")

    def test_missing_home_fails_with_a_controlled_diagnostic(self):
        output = self.run_preflight(home=self.root / "missing-home")
        self.assert_blocked(output, "", "is missing")


if __name__ == "__main__":
    unittest.main()
