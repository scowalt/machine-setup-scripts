#!/usr/bin/env python3
"""Contract version 1: extracted Bash channel functions, no setup or live Paseo.

Map only literal system paths into a temporary filesystem. Simulate root UIDs
because fixtures must not require sudo. Links, types, modes, and client writes
use the real filesystem and the production channel guard.
"""

import json
import os
from pathlib import Path
import shlex
import stat
import subprocess
import tempfile
import unittest


REPO = Path(__file__).resolve().parent.parent
SOURCE = (REPO / "bazzite.sh").read_text()
CHANNELS = SOURCE.split("# Paseo release channels.", 1)[1].split(
    "# End Paseo release channels.", 1
)[0]
CHANNELS = CHANNELS[CHANNELS.index("\npaseo_release_channel() {"):]

HARNESS = r'''
print_error() { printf '%s\n' "$*" >&2; }
print_warning() { :; }
print_success() { :; }
print_debug() { :; }
print_message() { :; }
paseo_desktop_is_running() { return "${PROCESS_STATUS:-1}"; }
uname() { printf 'x86_64\n'; }
stat() {
    [[ "${STAT_FAILURE:-0}" == 0 ]] || return 1
    if [[ "$#" == 3 && "$1" == -c && "$2" == %u ]]; then
        case "$3" in
            "${FIXTURE_ROOT}"|"${FIXTURE_ROOT}/home"|"${FIXTURE_ROOT}/var"|"${FIXTURE_ROOT}/var/home") ;;
            *) printf 'Unexpected ownership query\n' >&2; return 1 ;;
        esac
        if [[ "$3" == "${UNTRUSTED_OWNER:-}" ]]; then
            printf '1000\n'
        else
            printf '0\n'
        fi
    elif [[ "$#" == 3 && "$2" == %a && "$3" == "${BAD_MODE_PATH:-}" ]]; then
        printf 'invalid\n'
    else
        command stat "$@"
    fi
}
configure_paseo_desktop_channel "${PLATFORM:-linux}"
'''


class SystemHomeAliasTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="paseo-system-home-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.real_home = self.root / "var/home/scowalt"
        self.real_home.mkdir(parents=True)
        self.alias = self.root / "home"
        self.alias.symlink_to("var/home", target_is_directory=True)
        for path in (self.root, self.root / "var", self.root / "var/home"):
            path.chmod(0o755)
        self.profile = self.real_home / ".config/Paseo"
        self.file = self.profile / "desktop-settings.json"
        self.env = {
            # Exclude package-manager shims that can initialize a fixture HOME
            # or download tools. This Linux suite requires system Bash and jq.
            "PATH": os.defpath,
            "HOME": str(self.alias / "scowalt"),
            "PASEO_CHANNEL": "beta",
            "FIXTURE_ROOT": str(self.root),
            "LC_ALL": "C",
        }
        self.channels = CHANNELS
        # No test-only production flag or general path resolver is introduced.
        for literal in ('"/var/home"', '"/home"', '"/var"', '"/"'):
            mapped = self.root / literal.strip('"').lstrip("/")
            self.channels = self.channels.replace(literal, shlex.quote(str(mapped)))

    def run_channel(self, **environment):
        return subprocess.run(
            ["bash", "-c", self.channels + HARNESS],
            env={**self.env, **environment},
            capture_output=True,
            text=True,
            timeout=10,
            check=False,
        )

    def assert_success(self, **environment):
        result = self.run_channel(**environment)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result

    def snapshot(self):
        result = {}
        for path in self.root.rglob("*"):
            mode = path.lstat().st_mode
            if stat.S_ISLNK(mode):
                contents = os.readlink(path)
            elif stat.S_ISREG(mode):
                contents = path.read_bytes()
            else:
                contents = None
            result[str(path.relative_to(self.root))] = (mode, contents)
        return result

    def assert_rejected(self, message="Unsafe Paseo Desktop directory", **environment):
        before = self.snapshot()
        result = self.run_channel(**environment)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn(message, result.stderr)
        self.assertEqual(self.snapshot(), before, "Rejected setup changed fixture state")

    def test_relative_system_alias_creates_private_beta_settings(self):
        self.assert_success()
        document = json.loads(self.file.read_text())
        self.assertEqual(document["settings"]["releaseChannel"], "beta")
        self.assertTrue(document["migrations"]["legacyRendererSettingsImported"])
        self.assertEqual(stat.S_IMODE(self.file.stat().st_mode), 0o600)
        self.assertTrue(self.alias.is_symlink())

    def test_absolute_system_alias(self):
        self.alias.unlink()
        self.alias.symlink_to(self.root / "var/home", target_is_directory=True)
        self.assert_success()
        self.assertTrue(self.file.is_file())

    def test_existing_settings_preserved_and_repeat_is_noop(self):
        self.profile.mkdir(parents=True)
        document = {
            "version": 1,
            "settings": {"releaseChannel": "beta", "privatePreference": "keep"},
            "migrations": {"future": 42},
            "other": [1, 2],
        }
        self.file.write_text(json.dumps(document))
        self.assert_success(PASEO_CHANNEL="stable")
        expected = json.loads(json.dumps(document))
        expected["settings"]["releaseChannel"] = "stable"
        expected["migrations"]["legacyRendererSettingsImported"] = True
        self.assertEqual(json.loads(self.file.read_text()), expected)
        os.utime(self.file, (946684800, 946684800))
        before = self.snapshot()
        before_time = self.file.stat().st_mtime_ns
        self.assert_success(PASEO_CHANNEL="stable", PROCESS_STATUS="0")
        self.assertEqual(self.snapshot(), before)
        self.assertEqual(self.file.stat().st_mtime_ns, before_time)

    def test_explicit_config_and_desktop_paths(self):
        for variable, path in (
            ("XDG_CONFIG_HOME", self.alias / "scowalt/custom config"),
            ("PASEO_ELECTRON_USER_DATA_DIR", self.alias / "scowalt/custom desktop"),
        ):
            with self.subTest(variable=variable):
                self.assert_success(**{variable: str(path)})
                profile = path / "Paseo" if variable == "XDG_CONFIG_HOME" else path
                self.assertTrue((profile / "desktop-settings.json").is_file())

    def test_nonstandard_system_alias_rejected(self):
        other = self.root / "other"
        other.mkdir()
        for target in ("other", "var/../var/home", "missing"):
            with self.subTest(target=target):
                self.alias.unlink()
                self.alias.symlink_to(target, target_is_directory=True)
                self.assert_rejected()

    def test_untrusted_owners_rejected(self):
        for path in (self.root, self.alias, self.root / "var", self.root / "var/home"):
            with self.subTest(path=path):
                self.assert_rejected(UNTRUSTED_OWNER=str(path))

    def test_writable_system_directories_rejected(self):
        for path in (self.root, self.root / "var", self.root / "var/home"):
            for mode in (0o775, 0o757, 0o1777):
                with self.subTest(path=path, mode=oct(mode)):
                    path.chmod(mode)
                    self.assert_rejected()
                    path.chmod(0o755)

    def test_system_target_links_rejected(self):
        for path in (self.root / "var/home", self.root / "var"):
            with self.subTest(path=path):
                saved = self.root / "saved"
                path.rename(saved)
                path.symlink_to(saved, target_is_directory=True)
                self.assert_rejected()
                path.unlink()
                saved.rename(path)

    def test_system_target_nondirectory_rejected(self):
        self.real_home.rmdir()
        target = self.root / "var/home"
        target.rmdir()
        target.write_text("not a directory")
        self.assert_rejected()

    def test_user_and_profile_links_rejected(self):
        self.profile.mkdir(parents=True)
        for path in (self.real_home, self.real_home / ".config", self.profile):
            with self.subTest(path=path):
                saved = self.root / "saved"
                path.rename(saved)
                path.symlink_to(saved, target_is_directory=True)
                self.assert_rejected()
                path.unlink()
                saved.rename(path)

    def test_settings_link_rejected(self):
        self.profile.mkdir(parents=True)
        target = self.root / "private-settings"
        target.write_text('{"version":1,"settings":{}}')
        self.file.symlink_to(target)
        self.assert_rejected("Unsafe Paseo Desktop settings path")

    def test_malformed_settings_rejected(self):
        self.profile.mkdir(parents=True)
        self.file.write_text("{private malformed")
        self.assert_rejected("Invalid or unsupported Paseo Desktop settings")

    def test_running_app_and_failed_process_inspection_rejected(self):
        for status in ("0", "2"):
            with self.subTest(status=status):
                message = "Close Paseo Desktop" if status == "0" else "Cannot determine"
                self.assert_rejected(message, PROCESS_STATUS=status)

    def test_failed_or_malformed_stat_rejected(self):
        self.assert_rejected(STAT_FAILURE="1")
        self.assert_rejected(BAD_MODE_PATH=str(self.root / "var/home"))

    def test_macos_does_not_accept_system_alias(self):
        self.assert_rejected(PLATFORM="macos")

    def test_headless_without_profile_still_skips(self):
        before = self.snapshot()
        self.assert_success(HEADLESS="1")
        self.assertEqual(self.snapshot(), before)

    def test_regular_home_directory_still_works(self):
        self.alias.unlink()
        (self.root / "var/home").rename(self.alias)
        self.assert_success(STAT_FAILURE="1")
        self.assertTrue((self.alias / "scowalt/.config/Paseo/desktop-settings.json").is_file())

    def test_physical_home_path_still_works(self):
        self.assert_success(HOME=str(self.real_home))
        self.assertTrue(self.file.is_file())


if __name__ == "__main__":
    unittest.main()
