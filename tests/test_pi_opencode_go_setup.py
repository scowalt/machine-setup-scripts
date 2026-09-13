"""Offline Go credential fixtures. No Pi runtime, setup entry point, or network."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ("mac.sh", "ubuntu.sh", "wsl.sh", "pi.sh", "bazzite.sh", "win.ps1")
NODE = shutil.which("node")
PWSH = os.environ.get("PWSH_BIN") or shutil.which("pwsh")
NATIVE_LOCK = os.environ.get("PI_GO_LOCK_MODULE")
MODEL = "muse-spark-1.3-contributor"
KEY = "fixture-go-key-not-a-real-credential"
BEGIN = "// BEGIN PI_OPENCODE_GO_SETUP"
END = "// END PI_OPENCODE_GO_SETUP"


def embedded(script):
    text = (ROOT / script).read_text()
    return text[text.index(BEGIN):text.index(END) + len(END)]


def wrapper(script):
    text = (ROOT / script).read_text()
    signature = "function Set-PiOpenCodeGoProvider {" if script == "win.ps1" else "configure_pi_opencode_go() {"
    start = text.index(signature)
    return text[start:text.index("\n}\n", text.index(END, start)) + 2]


FAKE_LOCK = r'''
const fs = require('node:fs');
exports.lock = async (file, options) => {
    const action = process.env.GO_TEST_ACTION;
    if (options.realpath !== false || options.update > 1000 || !options.onCompromised) throw Error('bad-lock-options');
    if (action === 'lock-failure') throw Error('PRIVATE-FAILURE-SENTINEL');
    const lock = file + '.lock';
    fs.mkdirSync(lock, {mode: 0o700});
    if (action === 'refresh') {
        const data = JSON.parse(fs.readFileSync(file, 'utf8'));
        data.keep.access = 'renewed-fixture-token';
        fs.writeFileSync(file, JSON.stringify(data), {mode: 0o600});
    }
    if (action === 'compromised') options.onCompromised();
    if (action === 'rename-failure') {
        const rename = fs.renameSync;
        fs.renameSync = (from, to) => { if (to === file) throw Error('PRIVATE-FAILURE-SENTINEL'); return rename(from, to); };
    }
    return async () => fs.rmdirSync(lock);
};
'''


class GoSetupTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="pi-go-fixture-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.home = self.root / "home"
        self.home.mkdir(mode=0o700)
        self.profile = self.home / ".pi/agent"
        self.auth = self.profile / "auth.json"
        self.envfile = self.home / ".env.local"
        self.prefix = self.home / ".local" / ("node_modules" if os.name == "nt" else "lib/node_modules")
        self.package = self.prefix / "@earendil-works/pi-coding-agent"
        self.catalog = self.package / "node_modules/@earendil-works/pi-ai/dist/providers/data/opencode-go.json"
        self.lock = self.package / "node_modules/proper-lockfile"
        self.put(self.package / "package.json", {"name": "@earendil-works/pi-coding-agent", "version": "0.85.1"})
        self.put(self.catalog.parents[3] / "package.json", {"name": "@earendil-works/pi-ai", "version": "0.85.1"})
        self.model = {"id": MODEL, "provider": "opencode-go", "api": "openai-responses",
                      "baseUrl": "https://opencode.ai/zen/go/v1", "reasoning": True,
                      "thinkingLevelMap": {"xhigh": "xhigh"}}
        self.put(self.catalog, {"openai-responses": {MODEL: self.model}})
        self.put(self.lock / "package.json", {"name": "proper-lockfile", "version": "4.1.2", "main": "index.js"})
        self.put(self.lock / "index.js", FAKE_LOCK)
        self.env = {"PATH": os.environ["PATH"], "HOME": str(self.home), "USERPROFILE": str(self.home)}
        if os.name == "nt":
            for name in ("SystemRoot", "WINDIR", "TEMP", "TMP"):
                if name in os.environ:
                    self.env[name] = os.environ[name]
        self.active = ""
        self.put(self.envfile, "OPENCODE_GO_API_KEY=" + KEY + "\n")

    def put(self, file, value, mode=0o600):
        file.parent.mkdir(parents=True, exist_ok=True)
        for parent in file.parents:
            if parent.is_relative_to(self.root):
                parent.chmod(0o700)
        file.write_text(json.dumps(value) if not isinstance(value, str) else value)
        file.chmod(mode)

    def run_helper(self, script="ubuntu.sh", use_wrapper=False, mode="sync", code=None):
        if use_wrapper and script == "win.ps1":
            fixture = self.root / "wrapper.ps1"
            fixture.write_text("$ErrorActionPreference = 'Stop'\n"
                               "if ($env:GO_TEST_LEGACY_ARGS) { $PSNativeCommandArgumentPassing = 'Legacy' }\n"
                               "function Write-Warning($Message) { [Console]::WriteLine($Message) }\n"
                               "function Write-Success($Message) { [Console]::WriteLine($Message) }\n"
                               "function Write-Debug($Message) { [Console]::WriteLine($Message) }\n" + wrapper(script) +
                               "\n$ok = Set-PiOpenCodeGoProvider\n"
                               "[Console]::WriteLine('changed:' + $script:PiOpenCodeGoChanged)\n"
                               "if (-not $ok) { exit 1 }\n")
            args = [PWSH, "-NoProfile", "-NonInteractive", "-File", str(fixture)]
        elif use_wrapper:
            fixture = self.root / "wrapper.sh"
            fixture.write_text("set -eu\nprint_warning() { printf '%s\\n' \"$1\"; }\n"
                               "print_success() { printf '%s\\n' \"$1\"; }\n"
                               "print_debug() { printf '%s\\n' \"$1\"; }\n" + wrapper(script) +
                               "\nconfigure_pi_opencode_go\nprintf 'changed:%s\\n' \"${PI_OPENCODE_GO_CHANGED}\"\n")
            args = ["bash", str(fixture)]
        else:
            fixture = self.root / "helper.cjs"
            fixture.write_text(code or embedded(script))
            args = [NODE, str(fixture), str(self.home), self.active, mode]
        env = {**self.env, "PI_CODING_AGENT_DIR": self.active}
        before_env = self.envfile.read_bytes() if self.envfile.is_file() else None
        result = subprocess.run(args, input=None, env=env, cwd=self.root, text=True, capture_output=True, timeout=40)
        after_env = self.envfile.read_bytes() if self.envfile.is_file() else None
        self.assertEqual(after_env, before_env, 'Go setup must not rewrite the environment file')
        self.assertNotIn(KEY, result.stdout + result.stderr)
        self.assertNotIn("PRIVATE-FAILURE-SENTINEL", result.stdout + result.stderr)
        return result

    def test_embedded_helpers_are_identical_and_do_not_start_clients(self):
        bodies = [embedded(script) for script in SCRIPTS]
        self.assertTrue(all(body == bodies[0] for body in bodies))
        self.assertNotIn("ModelRuntime", bodies[0])
        self.assertNotIn("fetch(", bodies[0])
        self.assertNotIn("process.env.OPENCODE_API_KEY", bodies[0])

    def test_creation_rotation_idempotence_and_other_credentials(self):
        self.put(self.auth, {"keep": {"type": "oauth", "access": "old-fixture-token", "nested": [1, True]},
                             "opencode": {"type": "api_key", "key": "zen-untouched"}})
        for token in (KEY, "rotated-fixture-key", "fixture/key+with-padding=="):
            self.put(self.envfile, "OPENCODE_GO_API_KEY=" + token + "\n")
            result = self.run_helper()
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), "updated")
            data = json.loads(self.auth.read_text())
            self.assertEqual(data["opencode-go"], {"type": "api_key", "key": token})
            self.assertEqual(data["opencode"]["key"], "zen-untouched")
            self.assertEqual(data["keep"]["nested"], [1, True])
            before = self.auth.stat().st_mtime_ns
            result = self.run_helper()
            self.assertEqual(result.stdout.strip(), "unchanged")
            self.assertEqual(self.auth.stat().st_mtime_ns, before)
        if os.name != "nt":
            self.assertEqual(self.auth.stat().st_mode & 0o777, 0o600)
        self.assertFalse(self.auth.with_suffix(".json.lock").exists())

    def test_missing_or_empty_input_never_opens_or_erases_existing_auth(self):
        self.put(self.auth, "malformed existing auth is preserved")
        before = self.auth.read_bytes()
        for content in (None, "# no key\n", "OPENCODE_GO_API_KEY=\n", "OPENCODE_GO_API_KEY=''\n"):
            with self.subTest(content=content):
                if content is None:
                    self.envfile.unlink()
                else:
                    self.put(self.envfile, content)
                result = self.run_helper()
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.strip(), "missing-key")
                self.assertEqual(self.auth.read_bytes(), before)
        shutil.rmtree(self.profile)
        self.assertEqual(self.run_helper().returncode, 0)
        self.assertFalse(self.profile.exists())

    def test_input_parser_is_file_only_and_never_executes_content(self):
        self.env["OPENCODE_GO_API_KEY"] = "process-value-must-not-win"
        self.env["OPENCODE_API_KEY"] = "shared-value-must-not-win"
        self.put(self.envfile, "# retained\nOPENCODE_GO_API_KEY=earlier\nexport OPENCODE_GO_API_KEY = '" + KEY + "'\n")
        self.assertEqual(self.run_helper().returncode, 0)
        self.assertEqual(json.loads(self.auth.read_text())["opencode-go"]["key"], KEY)
        for value in ("!touch sentinel", "$OPENCODE_API_KEY", "$(touch sentinel)", "bad key", '"unterminated', "value # comment"):
            with self.subTest(value=value):
                before = self.auth.read_bytes()
                self.put(self.envfile, "OPENCODE_GO_API_KEY=" + value + "\n")
                result = self.run_helper()
                self.assertEqual(result.returncode, 1)
                self.assertIn("invalid-key-format", result.stderr)
                self.assertEqual(self.auth.read_bytes(), before)
                self.assertFalse((self.root / "sentinel").exists())

    def test_custom_active_profile_does_not_change_default(self):
        self.put(self.auth, {"default": {"type": "api_key", "key": "keep"}})
        original = self.auth.read_bytes()
        self.active = str(self.root / "custom profile")
        result = self.run_helper()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.auth.read_bytes(), original)
        self.assertEqual(json.loads((Path(self.active) / "auth.json").read_text())["opencode-go"]["key"], KEY)
        for bad in ("relative", str(self.home), str(self.home / ".pi/../other")):
            self.active = bad
            self.assertEqual(self.run_helper().returncode, 1)

    def test_malformed_metadata_is_not_replaced(self):
        for text in ("", "{bad", "[]", "null", '{"keep":{"type":"api_key","key":12}}',
                     '{"keep":{"type":"api_key"},"keep":{"type":"api_key"}}',
                     '{"keep":{"type":"oauth","expires":9007199254740993}}'):
            with self.subTest(text=text):
                self.put(self.auth, text)
                result = self.run_helper()
                self.assertEqual(result.returncode, 1)
                self.assertEqual(self.auth.read_text(), text)
                self.assertFalse(self.auth.with_suffix(".json.lock").exists())

    def test_go_model_overrides_are_preserved_and_block_sync(self):
        models = self.profile / "models.json"
        for provider in ({"baseUrl": "https://example.invalid"}, {"modelOverrides": {MODEL: {"thinkingLevelMap": {"xhigh": "high"}}}}, {}):
            self.put(models, {"providers": {"opencode-go": provider, "keep": {"apiKey": "!never-execute"}}})
            before = models.read_bytes()
            result = self.run_helper()
            self.assertEqual(result.returncode, 1)
            self.assertIn("go-provider-overridden", result.stderr)
            self.assertEqual(models.read_bytes(), before)
            self.assertFalse(self.auth.exists())
        self.put(models, {"providers": {"keep": {"apiKey": "!never-execute"}}})
        before = models.read_bytes()
        self.assertEqual(self.run_helper().returncode, 0)
        self.assertEqual(models.read_bytes(), before)

    def test_incompatible_catalog_prevents_credential_mutation(self):
        for field, value in (("baseUrl", "https://opencode.ai/zen/v1"), ("provider", "opencode"),
                             ("api", "openai-completions"), ("reasoning", False),
                             ("thinkingLevelMap", {"xhigh": "high"})):
            with self.subTest(field=field):
                model = {**self.model, field: value}
                self.put(self.catalog, {"openai-responses": {MODEL: model}})
                result = self.run_helper()
                self.assertEqual(result.returncode, 1)
                self.assertIn("catalog-incompatible", result.stderr)
                self.assertFalse(self.auth.exists())

    @unittest.skipIf(os.name == "nt", "POSIX link/permission fixture")
    def test_linked_and_public_metadata_are_rejected(self):
        self.put(self.auth, {"keep": {"type": "api_key", "key": "keep"}})
        for file in (self.auth, self.envfile, self.catalog, self.lock / "index.js"):
            with self.subTest(file=file):
                outside = file.with_name(file.name + ".outside")
                file.rename(outside)
                before = outside.read_bytes()
                file.symlink_to(outside)
                self.assertEqual(self.run_helper().returncode, 1)
                self.assertEqual(outside.read_bytes(), before)
                file.unlink()
                outside.rename(file)
        for folder in (self.profile, self.lock, self.catalog.parents[3]):
            with self.subTest(folder=folder):
                outside = folder.with_name(folder.name + ".outside")
                folder.rename(outside)
                folder.symlink_to(outside, target_is_directory=True)
                self.assertEqual(self.run_helper().returncode, 1)
                folder.unlink()
                outside.rename(folder)
        for file in (self.auth, self.envfile):
            before = file.read_bytes()
            file.chmod(0o644)
            self.assertEqual(self.run_helper().returncode, 1)
            self.assertEqual(file.read_bytes(), before)
            self.assertEqual(file.stat().st_mode & 0o777, 0o644)
            file.chmod(0o600)
        lock = self.auth.with_suffix(".json.lock")
        outside = self.root / "outside-lock"
        outside.mkdir()
        lock.symlink_to(outside, target_is_directory=True)
        self.assertEqual(self.run_helper().returncode, 1)
        self.assertTrue(outside.is_dir())

    @unittest.skipIf(os.name == "nt", "POSIX npm umask fixture")
    def test_installed_npm_umask_does_not_relax_credential_permissions(self):
        for item in (self.home / ".local").rglob("*"):
            item.chmod(0o775 if item.is_dir() else 0o664)
        self.assertEqual(self.run_helper().returncode, 0)
        self.assertEqual(self.auth.stat().st_mode & 0o777, 0o600)
        self.profile.chmod(0o775)
        self.assertEqual(self.run_helper().returncode, 1)
        self.profile.chmod(0o700)
        self.catalog.chmod(0o666)
        self.assertEqual(self.run_helper().returncode, 1)

    def test_linux_system_home_alias_policy_without_real_home_access(self):
        text = embedded("ubuntu.sh")
        function = "function systemHomeAlias" + text.split("function systemHomeAlias", 1)[1].split("function directoryChain", 1)[0]
        code = r'''
const fs = {readlinkSync: () => target};
const fake = () => ({uid: 0, mode: 0o755, isDirectory: () => true, isSymbolicLink: () => false});
let entries, target;
const info = dir => entries[dir];
const assert = require('node:assert/strict');
''' + function + r'''
for (const value of ['var/home', '/var/home']) {
    target = value;
    entries = Object.fromEntries(['/', '/var', '/var/home'].map(dir => [dir, fake()]));
    assert.equal(systemHomeAlias('/home', {uid: 0}), process.platform === 'linux');
    assert.equal(systemHomeAlias('/home', {uid: 1}), false);
    assert.equal(systemHomeAlias('/home/user', {uid: 0}), false);
    for (const dir of Object.keys(entries)) {
        entries[dir].mode = 0o777;
        assert.equal(systemHomeAlias('/home', {uid: 0}), false);
        entries[dir] = fake();
        entries[dir].isSymbolicLink = () => true;
        assert.equal(systemHomeAlias('/home', {uid: 0}), false);
        entries[dir] = fake();
    }
}
target = '/elsewhere';
assert.equal(systemHomeAlias('/home', {uid: 0}), false);
console.log('alias-fixtures-passed');
'''
        fixture = self.root / "alias.cjs"
        fixture.write_text(code)
        result = subprocess.run([NODE, str(fixture)], env=self.env, cwd=self.root, text=True, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_refresh_inside_native_lock_is_preserved(self):
        self.put(self.auth, {"keep": {"type": "oauth", "access": "old-fixture-token"}})
        self.env["GO_TEST_ACTION"] = "refresh"
        result = self.run_helper()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(self.auth.read_text())["keep"]["access"], "renewed-fixture-token")

    def test_lock_and_write_failures_preserve_auth_and_clean_temporary_files(self):
        self.put(self.auth, {"keep": {"type": "api_key", "key": "keep"}})
        before = self.auth.read_bytes()
        for action in ("lock-failure", "compromised", "rename-failure"):
            with self.subTest(action=action):
                self.env["GO_TEST_ACTION"] = action
                self.assertEqual(self.run_helper().returncode, 1)
                self.assertEqual(self.auth.read_bytes(), before)
                self.assertEqual(list(self.profile.glob(".opencode-go-*")), [])
                self.assertFalse(self.auth.with_suffix(".json.lock").exists())

    def test_every_bash_wrapper_and_windows_wrapper_when_available(self):
        for script in SCRIPTS:
            if script == "win.ps1" and not PWSH:
                continue
            with self.subTest(script=script):
                if self.auth.exists():
                    self.auth.unlink()
                self.env["NODE_OPTIONS"] = "--require=/does-not-exist"
                self.env["NODE_PATH"] = "/does-not-exist"
                result = self.run_helper(script, use_wrapper=True)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("changed:True" if script == "win.ps1" else "changed:1", result.stdout)
                result = self.run_helper(script, use_wrapper=True)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("changed:False" if script == "win.ps1" else "changed:0", result.stdout)
                self.put(self.envfile, "OPENCODE_GO_API_KEY=$UNSAFE\n")
                self.assertEqual(self.run_helper(script, use_wrapper=True).returncode, 1)
                self.put(self.envfile, "OPENCODE_GO_API_KEY=" + KEY + "\n")

    @unittest.skipUnless(PWSH, "Set PWSH_BIN for legacy PowerShell argument coverage")
    def test_powershell_legacy_native_argument_passing(self):
        self.env["GO_TEST_LEGACY_ARGS"] = "1"
        for active in ("", str(self.root / "legacy custom profile")):
            with self.subTest(active=active):
                self.active = active
                result = self.run_helper("win.ps1", use_wrapper=True)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                target = Path(active) / "auth.json" if active else self.auth
                self.assertEqual(json.loads(target.read_text())["opencode-go"]["key"], KEY)

    @unittest.skipUnless(NATIVE_LOCK, "Set PI_GO_LOCK_MODULE for the installed catalog metadata probe")
    def test_published_catalog_matches_the_checked_contract(self):
        modules = Path(NATIVE_LOCK).resolve(strict=True).parents[1]
        catalog = modules / "@earendil-works/pi-ai/dist/providers/data/opencode-go.json"
        if not catalog.is_file():
            self.skipTest("No Pi catalog beside the explicitly supplied native lock module")
        self.put(self.catalog, catalog.read_text())
        result = self.run_helper(mode="check-catalog")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "catalog-ready")
        self.assertFalse(self.profile.exists())

    @unittest.skipUnless(NATIVE_LOCK, "Set PI_GO_LOCK_MODULE for native proper-lockfile interoperability")
    def test_real_pi_lock_serializes_concurrent_refresh(self):
        module = Path(NATIVE_LOCK).resolve(strict=True)
        self.put(self.lock / "index.js", "module.exports = require(" + json.dumps(str(module)) + ");\n")
        self.put(self.auth, {"keep": {"type": "oauth", "access": "old-fixture-token"}})
        ready = self.root / "ready"
        worker = self.root / "refresh.cjs"
        worker.write_text("const lock = require(" + json.dumps(str(module)) + ");\n" + r'''
const fs = require('node:fs');
const file = process.argv[2];
const release = lock.lockSync(file, {realpath: false});
fs.writeFileSync(process.argv[3], 'ready');
setTimeout(() => {
    const data = JSON.parse(fs.readFileSync(file, 'utf8'));
    data.keep.access = 'native-renewed-fixture';
    fs.writeFileSync(file, JSON.stringify(data));
    release();
}, 600);
''')
        process = subprocess.Popen([NODE, str(worker), str(self.auth), str(ready)], cwd=self.root,
                                   env=self.env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            deadline = time.monotonic() + 10
            while not ready.exists() and process.poll() is None and time.monotonic() < deadline:
                time.sleep(0.01)
            self.assertTrue(ready.exists())
            result = self.run_helper()
            self.assertEqual(result.returncode, 0, result.stderr)
            stdout, stderr = process.communicate(timeout=5)
            self.assertEqual(process.returncode, 0, stdout + stderr)
            data = json.loads(self.auth.read_text())
            self.assertEqual(data["keep"]["access"], "native-renewed-fixture")
            self.assertEqual(data["opencode-go"]["key"], KEY)
        finally:
            if process.poll() is None:
                process.kill()
            process.communicate(timeout=5)


if __name__ == "__main__":
    unittest.main()
