"""Exercise all five real dotfile call sites; native Chezmoi uses inert fixtures.

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
from test_bb_machine_preparation import BLOCK, NODE, SCRIPTS


ROOT = pathlib.Path(__file__).resolve().parents[1]
PYTHON = str(pathlib.Path(sys.executable).resolve())
CHEZMOI = os.environ.get("CHEZMOI_BIN") or shutil.which("chezmoi")
if CHEZMOI:
    CHEZMOI = str(pathlib.Path(CHEZMOI).resolve())
DIRECTORIES = (".config", ".config/systemd", ".config/systemd/user")

# Record the process boundary, not a test-only reimplementation of umask policy.
# Native mode uses only an inert local repository, config, state and destination.
# Authentication URLs are recorded, then removed for offline native init.
CHEZMOI_FIXTURE = r'''
import json, os, pathlib, sys
mask = os.umask(0)
os.umask(mask)
with open(os.environ["FIXTURE_CALLS"], "a") as log:
    log.write(json.dumps({"command": "chezmoi", "args": sys.argv[1:], "umask": f"{mask:04o}"}) + "\n")
if os.environ.get("FIXTURE_FAIL"):
    sys.exit(int(os.environ["FIXTURE_FAIL"]))
if os.environ.get("FIXTURE_NATIVE") == "1":
    root = pathlib.Path(os.environ["FIXTURE_ROOT"])
    native = os.environ["FIXTURE_NATIVE_BIN"]
    args = sys.argv[1:]
    if args[0] == 'init':
        assert args in [['init', '--apply', '--force', 'scowalt/dotfiles', '--ssh'],
                        ['init', '--apply', '--force', 'https://github.com/scowalt/dotfiles.git'],
                        ['init', '--apply', '--force', 'git@github-dotfiles:scowalt/dotfiles.git']]
        args = ['init', '--apply', '--force']
    else:
        assert args in [['update'], ['update', '--force'], ['apply', '--force'], ['apply', '--force', '--verbose']]
    os.execv(native, [native, "--source", str(root / "source"),
        "--destination", os.environ["HOME"], "--config", str(root / "chezmoi.toml"),
        "--cache", str(root / "cache"), "--persistent-state", str(root / "state.boltdb"),
        "--working-tree", str(root / "source"), "--no-tty", "--no-pager", *args])
'''
GIT_FIXTURE = r'''
import json, os, pathlib, sys
if os.environ.get('FIXTURE_NATIVE') == '1' and pathlib.Path.cwd() == pathlib.Path(os.environ['FIXTURE_ROOT']) / 'source':
    os.execv(os.environ['FIXTURE_GIT'], [os.environ['FIXTURE_GIT'], *sys.argv[1:]])
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
        (self.bin / 'node').symlink_to(NODE)
        for name, body in [('ps', 'exit 0'), ('tmux', 'exit 0'),
                           ('uname', 'if [[ "$1" == -s ]]; then echo "${KERNEL:-Linux}"; else echo "${RELEASE:-6.6-microsoft-standard-WSL2}"; fi')]:
            binary = self.bin / name
            binary.write_text('#!/bin/bash\n' + body + '\n')
            binary.chmod(0o700)
        self.configure_script('ubuntu')

    def configure_script(self, platform):
        self.platform = platform
        source = (ROOT / (platform + '.sh')).read_text()
        helpers = [BLOCK] + [function(source, name) for name in ("initialize_chezmoi", "update_chezmoi")]
        # Allow the pre-fix version to reach the actual native regression, not
        # fail on a missing new symbol before it can reproduce the user's bug.
        if "with_bb_dotfiles_umask() {" in source:
            helpers.insert(0, function(source, "with_bb_dotfiles_umask"))
        server = (ROOT / 'ubuntu.sh').read_text()
        start = server.index("bb_server_platform_ready() {")
        helpers.append(server[start:server.index("\nrun_setup_tasks() {", start)])
        self.helpers = self.root / "helpers.sh"
        self.helpers.write_text("\n".join(helpers))
        main = source[source.index("\nrun_setup_tasks() {"):]
        apply = re.search(r"^        if ! [^\n]*chezmoi apply --force; then\n.*?^        fi$", main, re.M | re.S)
        if platform == 'pi':
            with self.helpers.open('a') as helper:
                helper.write(function(source, 'apply_chezmoi_config'))
            self.full_apply = 'apply_chezmoi_config || _setup_had_errors=1'
        else:
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
            if stage in ('init', 'update'):
                self.native_git(env)
        checkout = self.home / ".local/share/chezmoi"
        if stage == "init" and checkout.exists():
            # Only empty fixture directories; never discard a real checkout.
            (checkout / ".git").rmdir()
            checkout.rmdir()
        if stage == "update":
            for relative in ('.local', '.local/share', '.local/share/chezmoi', '.local/share/chezmoi/.git'):
                directory = self.home / relative
                if not directory.exists():
                    directory.mkdir(mode=0o755)
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

    def native_git(self, env):
        git = shutil.which('git')
        if not git:
            self.skipTest('Native Git unavailable for isolated Chezmoi init/update')
        hooks = self.root / 'empty-hooks'
        hooks.mkdir(exist_ok=True)
        env.update(FIXTURE_GIT=git, GIT_ALLOW_PROTOCOL='file', GIT_CONFIG_COUNT='2',
                   GIT_CONFIG_KEY_0='core.hooksPath', GIT_CONFIG_VALUE_0=str(hooks),
                   GIT_CONFIG_KEY_1='init.templateDir', GIT_CONFIG_VALUE_1=str(hooks))
        if (self.source / '.git').exists():
            return
        commands = [ ['init', '-b', 'main'], ['add', '.'],
                     ['-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-m', 'inert'],
                     ['clone', '--bare', str(self.source), str(self.root / 'origin.git')],
                     ['remote', 'add', 'origin', str(self.root / 'origin.git')],
                     ['fetch', 'origin'], ['branch', '--set-upstream-to=origin/main'] ]
        for args in commands:
            result = subprocess.run([git, *args], cwd=self.source, env=env, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result)
        path = subprocess.check_output([git, 'rev-parse', '--show-toplevel'], cwd=self.source, env=env, text=True).strip()
        self.assertEqual(path, str(self.source))

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

    def test_native_preparation_only_apply_keeps_directories_and_files_safe(self):
        # Remove the server fixture role: this is an ordinary preparation account.
        shutil.rmtree(self.home / '.bb')
        self.protected = [p for p in self.protected if '.bb' not in p.parts]
        (self.source / 'dot_config/systemd/user/tmux.service').write_text('inert service\n')
        for attempt in range(2):
            result = self.run_stage(selection='0', native=True)
            self.assertEqual(result.returncode, 0, result)
            result = subprocess.run(['bash', '-c', 'source "$1"; print_error() { echo "$*"; }; bb_machine_package_state preflight',
                                     '_', str(self.helpers)], env=self.env, text=True,
                                    capture_output=True, timeout=10)
            self.assertEqual(result.returncode, 0, result)
            self.assertEqual((self.home / '.config/systemd/user/tmux.service').stat().st_mode & 0o777, 0o644)

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


class BbPreparationDotfilesTests(unittest.TestCase):
    configure_script = BbDotfilesUmaskTests.configure_script
    run_stage = BbDotfilesUmaskTests.run_stage
    native_git = BbDotfilesUmaskTests.native_git
    snapshot = BbDotfilesUmaskTests.snapshot
    calls = BbDotfilesUmaskTests.calls

    def setUp(self):
        BbDotfilesUmaskTests.setUp(self)
        shutil.rmtree(self.home / '.bb')
        self.protected = [p for p in self.protected if '.bb' not in p.parts]
        (self.source / 'dot_config/systemd/user/tmux.service').write_text('inert service\n')
        self.env['BB_SERVER'] = '0'

    def preparation(self, expected=0):
        result = subprocess.run(['bash', '-c', '''source "$1"
print_error() { echo "$*"; }
bb_machine_package_state preflight
''', '_', str(self.helpers)], env=self.env, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, expected, result)
        self.assertEqual(result.stderr, '', result)
        return result.stdout

    def test_native_all_five_call_sites_converge_files_and_directories_repeatedly(self):
        for platform in SCRIPTS:
            self.configure_script(platform)
            for stage, method in [('init', 'ssh'), ('init', 'token'), ('init', 'deploy'),
                                  ('update', ''), ('apply', '')]:
                for attempt in range(2):
                    with self.subTest(platform=platform, stage=stage, method=method, attempt=attempt):
                        if not CHEZMOI:
                            self.skipTest('Native Chezmoi unavailable')
                        # Establish the ordinary inherited-0002 state natively.
                        # This avoids fabricating an external edit conflict that
                        # Pi's intentionally non-force update would prompt about.
                        baseline = subprocess.run(['bash', '-c', 'umask 0002; "$1" apply --force',
                                                   '_', str(self.bin / 'chezmoi')],
                                                  env=self.env | {'FIXTURE_NATIVE': '1', 'FIXTURE_NATIVE_BIN': CHEZMOI},
                                                  capture_output=True, text=True, timeout=10)
                        self.assertEqual(baseline.returncode, 0, baseline)
                        unit = self.home / '.config/systemd/user/tmux.service'
                        self.assertEqual(unit.stat().st_mode & 0o777, 0o664)
                        self.assertIn('mode=0775 reason=writable-boundary', self.preparation(expected=1))
                        result = self.run_stage(stage, selection='0', method=method, native=True)
                        self.assertEqual(result.returncode, 0, result)
                        self.assertNotIn('WARNING:', result.stdout)
                        self.preparation()
                        self.assertEqual([((self.home / p).stat().st_mode & 0o777) for p in DIRECTORIES], [0o755] * 3)
                        self.assertEqual(unit.stat().st_mode & 0o777, 0o644)
            new_dir = self.source / f'dot_config/systemd/user/new-{platform}'
            new_dir.mkdir()
            (self.source / f'dot_config/systemd/user/new-{platform}.service').write_text('inert new file\n')
            result = self.run_stage(selection='0', native=True)
            self.assertEqual(result.returncode, 0, result)
            self.preparation()
            self.assertEqual((self.home / f'.config/systemd/user/new-{platform}').stat().st_mode & 0o777, 0o755)
            self.assertEqual((self.home / f'.config/systemd/user/new-{platform}.service').stat().st_mode & 0o777, 0o644)

    def test_call_site_arguments_masks_errors_and_pi_fallback(self):
        for platform in SCRIPTS:
            self.configure_script(platform)
            fallback = self.home / 'bin/chezmoi'
            if platform == 'pi':
                fallback.parent.mkdir(exist_ok=True)
                (self.bin / 'chezmoi').rename(fallback)
            for mask, expected in [('0000', '0022'), ('0002', '0022'), ('0027', '0027'), ('0077', '0077')]:
                for stage, method in [('init', 'ssh'), ('init', 'token'), ('init', 'deploy'), ('update', ''), ('apply', '')]:
                    with self.subTest(platform=platform, mask=mask, stage=stage, method=method):
                        result = self.run_stage(stage, mask, '0', method)
                        self.assertEqual(result.returncode, 0, result)
                        command = self.calls()[0]
                        self.assertEqual(command['umask'], expected)
                        args = {'init': ['init', '--apply', '--force', {'ssh': 'scowalt/dotfiles', 'token': 'https://github.com/scowalt/dotfiles.git', 'deploy': 'git@github-dotfiles:scowalt/dotfiles.git'}.get(method, '')] + (['--ssh'] if method == 'ssh' else []),
                                'update': ['update'] + ([] if platform == 'pi' else ['--force']),
                                'apply': ['apply', '--force'] + (['--verbose'] if platform == 'pi' else [])}[stage]
                        self.assertEqual(command['args'], args)
                        failure = self.run_stage(stage, mask, '0', method, fail='17')
                        self.assertNotIn('SUCCESS:', failure.stdout)
                        self.assertEqual(failure.returncode, 0 if stage == 'update' else 1, failure)
            if platform == 'pi':
                fallback.rename(self.bin / 'chezmoi')

    def test_native_deferred_roles_keep_ordinary_apply_behavior(self):
        role = self.home / '.bb/project.txt'
        role.parent.mkdir()
        role.write_text('preserve existing BB state\n')
        self.protected.append(role)
        for platform in SCRIPTS:
            self.configure_script(platform)
            for stage in ['init', 'update', 'apply']:
                result = self.run_stage(stage, selection='0', native=True)
                self.assertEqual(result.returncode, 0, result)
                self.assertEqual((self.home / '.config').stat().st_mode & 0o777, 0o775)
                self.assertEqual((self.home / '.config/systemd/user/tmux.service').stat().st_mode & 0o777, 0o664)
                result = subprocess.run(['bash', '-c', '''source "$1"
print_message() { echo "$*"; }
ensure_shared_node_runtime() { echo FORBIDDEN; return 97; }
setup_bb_machine "$2"
''', '_', str(self.helpers), platform], env=self.env, capture_output=True, text=True, timeout=10)
                self.assertEqual(result.returncode, 0, result)
                self.assertIn('readiness was not checked', result.stdout)
                self.assertNotIn('FORBIDDEN', result.stdout)
        self.protected.remove(role)
        role.unlink()
        role.parent.rmdir()
        for platform in SCRIPTS:
            self.configure_script(platform)
            for key in ['BB_DATA_DIR', 'BB_APP_NPM_PREFIX']:
                self.env[key] = '/not-inspected'
                self.run_stage(selection='0', native=True)
                self.assertEqual((self.home / '.config').stat().st_mode & 0o777, 0o775)
                del self.env[key]

    def test_early_boundary_needs_no_node_npm_or_process_inventory(self):
        (self.bin / 'node').unlink()  # Unlink the fixture link, never its native target.
        for name in ['node', 'ps']:
            binary = self.bin / name
            binary.write_text('#!/bin/bash\necho forbidden >> "$FIXTURE_ROOT/unexpected"\nexit 97\n')
            binary.chmod(0o700)
        for platform in SCRIPTS:
            self.configure_script(platform)
            for stage in ['init', 'update', 'apply']:
                result = self.run_stage(stage, selection='0')
                self.assertEqual(result.returncode, 0, result)
                self.assertEqual(self.calls()[0]['umask'], '0022')

    def test_roles_overrides_platforms_and_exact_headless_scope(self):
        for platform in SCRIPTS:
            self.configure_script(platform)
            for name in ['.bb', '.bb-machines', '.config/setup-bb-server',
                         '.config/systemd/user/bb-existing.service', 'Library/LaunchAgents/app.bb.plist']:
                role = self.home / name
                role.parent.mkdir(parents=True, exist_ok=True)
                role.write_text('preserve role state')
                self.protected.append(role)
                for stage in ['init', 'update', 'apply']:
                    self.run_stage(stage, selection='0')
                    self.assertEqual(self.calls()[0]['umask'], '0002', (platform, name, stage))
                self.protected.remove(role)
                role.unlink()
            for key in ['BB_DATA_DIR', 'BB_APP_NPM_PREFIX']:
                self.env[key] = '/not-inspected'
                self.run_stage(selection='0')
                self.assertEqual(self.calls()[0]['umask'], '0002')
                del self.env[key]
            role = pathlib.Path(self.env['XDG_CONFIG_HOME']) / 'setup-bb-server'
            role.parent.mkdir(exist_ok=True)
            role.symlink_to(self.root / 'missing-role')
            self.run_stage(selection='0')
            self.assertEqual(self.calls()[0]['umask'], '0002')
            role.unlink()
            for flag in ['', '0', 'true', 'false', '1']:
                self.env['HEADLESS'] = flag
                self.run_stage(selection='0')
                self.assertEqual(self.calls()[0]['umask'], '0002' if platform == 'wsl' and flag == '1' else '0022')
            del self.env['HEADLESS']
            self.env['KERNEL'] = 'MINGW64_NT'
            self.run_stage(selection='0')
            self.assertEqual(self.calls()[0]['umask'], '0002')
            del self.env['KERNEL']
            if platform == 'wsl':
                self.env['RELEASE'] = '4.4-Microsoft'
                self.run_stage(selection='0')
                self.assertEqual(self.calls()[0]['umask'], '0002')
                del self.env['RELEASE']
            self.run_stage(selection='invalid')
            self.assertEqual(self.calls()[0]['umask'], '0002' if platform == 'ubuntu' else '0022')
            self.run_stage(selection='1')
            self.assertEqual(self.calls()[0]['umask'], '0022')

    def test_actual_runners_resolve_effective_flags_before_dotfile_boundary(self):
        for platform in SCRIPTS:
            source = (ROOT / (platform + '.sh')).read_text()
            main = function(source, 'run_setup_tasks')
            names = set(re.findall(r'^(\w+)\(\)\s*\{', source, re.M))
            stubs = '\n'.join(f'{n}() {{ :; }}' for n in names if n != 'run_setup_tasks')
            script = stubs + '\n' + main + '\n'
            for name in ['with_bb_dotfiles_umask', 'bb_machine_existing_role', 'bb_machine_platform_ready']:
                script += function(source, name)
            if platform == 'ubuntu':
                for name in ['bb_server_selection', 'bb_server_restore_process_override']:
                    script += function(source, name)
            if platform == 'pi':
                script += function(source, 'apply_chezmoi_config')
            script += '\numask 0002\nrun_setup_tasks\nprintf "CALLER_MASK=%s\\n" "$(umask)"\n'
            for process, saved, expected in [({'BB_SERVER': '0'}, 'BB_SERVER=1', '0022'),
                                             ({'BB_SERVER': '1'}, 'BB_SERVER=0\nBB_DATA_DIR=/custom', '0022' if platform == 'ubuntu' else '0002'),
                                             ({'BB_SERVER': 'invalid'}, 'BB_SERVER=0', '0002' if platform == 'ubuntu' else '0022'),
                                             ({'BB_DATA_DIR': '/custom'}, 'BB_DATA_DIR=', '0022'),
                                             ({'HEADLESS': '0'}, 'HEADLESS=1', '0002' if platform == 'wsl' else '0022'),
                                             ({'HEADLESS': '1'}, 'HEADLESS=0', '0022')]:
                with self.subTest(platform=platform, process=process, saved=saved):
                    (self.home / '.env.local').write_text(saved + '\n')
                    (self.root / 'calls').unlink(missing_ok=True)
                    # All setup functions are inert except the real full-apply
                    # call site, policy and the runner's own flag resolution.
                    result = subprocess.run(['bash', '-c', script], env=self.env | process,
                                            cwd=self.home, capture_output=True, text=True, timeout=10)
                    self.assertEqual(result.stderr, '', result)
                    self.assertIn('CALLER_MASK=0002', result.stdout)
                    self.assertEqual(self.calls()[0]['umask'], expected)
                    self.assertFalse((self.root / 'unexpected').exists())

    def test_native_stricter_and_explicit_masks_and_unmanaged_blockers(self):
        config = self.config.read_text()
        for platform in SCRIPTS:
            self.configure_script(platform)
            for mask, directory, file in [('0027', 0o750, 0o640), ('0077', 0o700, 0o600)]:
                self.run_stage(mask=mask, selection='0', native=True)
                self.preparation()
                self.assertEqual((self.home / '.config').stat().st_mode & 0o777, directory)
                self.assertEqual((self.home / '.config/systemd/user/tmux.service').stat().st_mode & 0o777, file)
            self.config.write_text('umask = 0o002\n' + config)
            self.run_stage(selection='0', native=True)
            self.assertIn('path=~/.config mode=0775', self.preparation(expected=1))
            self.config.write_text(config)
            unmanaged = self.home / '.config/systemd/user/unmanaged.service'
            unmanaged.write_text('SECRET_UNMANAGED')
            unmanaged.chmod(0o664)
            self.protected.append(unmanaged)
            self.run_stage(selection='0', native=True)
            out = self.preparation(expected=1)
            self.assertIn('path=~/.config/systemd/user/unmanaged.service mode=0664', out)
            self.assertNotIn('SECRET', out)
            self.protected.remove(unmanaged)
            unmanaged.unlink()


if __name__ == "__main__":
    unittest.main()
