#!/usr/bin/env python3
"""Offline shared-Node setup fixtures; never source a complete setup script."""

import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ("mac.sh", "ubuntu.sh", "wsl.sh", "pi.sh", "bazzite.sh")
NODE = shutil.which("node")
FISH = shutil.which("fish")
MISE = shutil.which("mise")
FUNCTIONS = (
    "pi_node_runtime_ready", "shared_node_runtime_ready", "shared_node_fallback",
    "verify_shared_node_shell", "ensure_shared_node_runtime", "ensure_pi_node_runtime",
    "skills_cli_node_runtime_ready", "ensure_skills_cli_node_runtime", "install_pi_cli",
)


def extract(script):
    text = (ROOT / script).read_text()
    return "\n\n".join(
        match.group() for name in FUNCTIONS
        if (match := re.search(r"^" + name + r"\(\) \{\n.*?^\}", text, re.M | re.S))
    )


def executable(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    path.chmod(0o755)


class RuntimeFixture:
    def __init__(self, root, version=None, inherited="24.20.0", **options):
        self.home = root / "home with spaces"
        self.home.mkdir()
        self.state = self.home / "state.json"
        self.state.write_text(json.dumps({"global": version, **options}))
        self.log = self.home / "calls.jsonl"
        self.env = {
            "HOME": str(self.home), "XDG_CONFIG_HOME": str(self.home / ".config"),
            "PATH": f"{self.home}/inherited:{self.home}/.local/bin:/usr/bin:/bin",
            "TERM": "dumb", "SHELL": FISH or "/bin/false", "LC_ALL": "C",
            "FIXTURE_HOME": str(self.home), "REAL_NODE": NODE,
            "REAL_PYTHON": sys.executable,
        }
        for v in ("18.19.1", "20.19.0", "22.18.0", "22.19.0", "22.20.0", "22.23.2", "24.20.0", "26.0.0"):
            directory = self.home / "runtimes" / v / "bin"
            executable(directory / "node", f"#!{sys.executable}\n" + f"VERSION = {v!r}\n" + r'''
import json, os, pathlib, subprocess, sys
state = json.loads(pathlib.Path(os.environ['FIXTURE_HOME'], 'state.json').read_text())
if sys.argv[1:] == ['--version']:
    print('v' + VERSION)
    sys.exit(0)
if len(sys.argv) >= 3 and sys.argv[1] == '-e':
    code = 'Object.defineProperty(process.versions,"node",{value:' + json.dumps(VERSION) + '});'
    code += 'Object.defineProperty(process,"execPath",{value:' + json.dumps(str(pathlib.Path(sys.argv[0]).resolve())) + '});'
    if state.get('no_glob') or int(VERSION.split('.')[0]) < 22:
        code += 'require("node:fs").globSync=undefined;'
    sys.exit(subprocess.call([os.environ['REAL_NODE'], '-e', code + sys.argv[2], *sys.argv[3:]]))
os.execv(os.environ['REAL_NODE'], [os.environ['REAL_NODE'], *sys.argv[1:]])
''')
            executable(directory / "npm", f"#!{sys.executable}\n" + r'''
import json, os, pathlib, sys
home = pathlib.Path(os.environ['FIXTURE_HOME'])
state = json.loads((home / 'state.json').read_text())
with (home / 'calls.jsonl').open('a') as f:
    f.write(json.dumps(['npm', *sys.argv[1:]]) + '\n')
if sys.argv[1:] == ['--version']:
    print('11.0.0')
    sys.exit(1 if state.get('npm_failure') else 0)
# An unexpected package operation must never reach a real registry.
sys.exit(99)
''')
        inherited_bin = self.home / "inherited"
        inherited_bin.mkdir()
        for name in ("node", "npm"):
            (inherited_bin / name).symlink_to(self.home / "runtimes" / inherited / "bin" / name)
        executable(self.home / ".local/bin/mise", f"#!{sys.executable}\n" + r'''
import json, os, pathlib, shlex, sys
home = pathlib.Path(os.environ['FIXTURE_HOME'])
state_path = home / 'state.json'
state = json.loads(state_path.read_text())
args = sys.argv[1:]
with (home / 'calls.jsonl').open('a') as f:
    f.write(json.dumps(['mise', *args]) + '\n')
if args[0] == 'ls':
    assert '--global' in args and '--json' in args and args[-1] == 'node', args
    if state.get('inventory_failure'): sys.exit(1)
    version = state.get('global')
    if state.get('home_override') and args[args.index('-C') + 1] == str(home):
        version = None  # Real mise --global filters the effective active source.
    if 'inventory' in state:
        print(json.dumps(state['inventory']))
        sys.exit(0)
    print(json.dumps([] if not version else [{
        'version': version, 'requested_version': version, 'installed': True,
        'install_path': str(home / ('missing' if state.get('missing_global') else 'runtimes') / version), 'active': True,
        'source': {'type': 'mise.toml', 'path': str(home / '.config/mise/config.toml')}
    }]))
elif args[0] in ('use', 'install'):
    assert os.environ.get('MISE_NODE_COMPILE') == 'false', 'must prohibit compilation'
    if state.get('install_failure'): sys.exit(1)
    assert args[-1] in ('node@24', 'node@22', 'node@22.23.2', 'node@26.0.0'), args
    if args[0] == 'use':
        state['global'] = '22.23.2' if args[-1] == 'node@22' else '24.20.0'
    elif state.get('global') == '22':
        state['global'] = '22.23.2'
    state.pop('missing_global', None)
    state_path.write_text(json.dumps(state))
elif args[0] == 'which':
    assert args[-1] == 'node', args
    version = state.get('home_override') or state.get('global')
    if not version: sys.exit(1)
    print(home / 'runtimes' / version / 'bin/node')
elif args[0] in ('env', 'activate'):
    assert not any(a.startswith('node@') for a in args), 'forced runtime masks HOME conflicts'
    if state.get('env_failure'): sys.exit(1)
    version = state.get('home_override') or state.get('global')
    paths = [str(home / '.local/bin'), '/usr/bin', '/bin']
    if version: paths.insert(0, str(home / 'runtimes' / version / 'bin'))
    if 'fish' in args:
        if not state.get('no_activation'):
            print('set -gx PATH ' + ' '.join(shlex.quote(p) for p in paths))
    else:
        print('export PATH=' + shlex.quote(':'.join(paths)))
else:
    raise AssertionError(args)
''')
        executable(self.home / ".local/bin/uname", f"#!{sys.executable}\n" + r'''
import json, os, pathlib, sys
state = json.loads(pathlib.Path(os.environ['FIXTURE_HOME'], 'state.json').read_text())
print(state.get('arch', 'x86_64') if sys.argv[1:] == ['-m'] else 'Linux')
''')
        config = self.home / ".config/fish/config.fish"
        config.parent.mkdir(parents=True)
        config.write_text('set -gx PATH "$HOME/.local/bin" $PATH\n'
                          'if type -q mise\n    mise activate fish | source\nend\n')

    def run(self, script="ubuntu.sh", command="ensure_pi_node_runtime"):
        prelude = "\n".join(f'{name}() {{ printf "%s\\n" "$*"; }}' for name in
                            ("print_debug", "print_message", "print_success", "print_warning", "print_error"))
        # Real extracted installer, with unrelated package configuration isolated.
        prelude += '\nensure_npm_configuration() { return 0; }\n'
        return subprocess.run(
            ["/bin/bash", "--noprofile", "--norc", "-c", prelude + "\n" + extract(script) + "\n" + command],
            cwd=self.home, env=self.env, text=True, capture_output=True, timeout=20,
        )

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def selected(self):
        return json.loads(self.state.read_text()).get("global")


@unittest.skipUnless(NODE and FISH, "Node and fish are required for offline runtime fixtures")
class SharedNodeTests(unittest.TestCase):
    def fixture(self, **kwargs):
        tmp = tempfile.TemporaryDirectory(prefix="shared-node-")
        self.addCleanup(tmp.cleanup)
        return RuntimeFixture(Path(tmp.name), **kwargs)

    def test_inherited_modern_node_does_not_skip_durable_default(self):
        for script in SCRIPTS:
            with self.subTest(script=script):
                f = self.fixture()
                result = f.run(script)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(f.selected(), "24.20.0")

    def test_supported_global_is_preserved_and_reruns_do_not_install(self):
        for version in ("22.23.2", "26.0.0"):
            f = self.fixture(version=version, inherited="18.19.1")
            for _ in range(2):
                result = f.run()
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(f.selected(), version)
            self.assertFalse(any(c[:2] in (["mise", "use"], ["mise", "install"]) for c in f.calls()))

    def test_old_global_is_repaired_despite_modern_inherited_node(self):
        f = self.fixture(version="18.19.1")
        result = f.run()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(f.selected(), "24.20.0")

    def test_shared_bash_functions_do_not_drift(self):
        for name in FUNCTIONS:
            if name == "install_pi_cli":
                continue
            pattern = r'^' + name + r'\(\) \{\n.*?^\}'
            canonical = re.search(pattern, (ROOT / 'ubuntu.sh').read_text(), re.M | re.S).group()
            for script in SCRIPTS:
                self.assertEqual(re.search(pattern, (ROOT / script).read_text(), re.M | re.S).group(), canonical,
                                 f'{script}: {name}')

    def test_multiple_global_selections_require_review(self):
        f = self.fixture(inventory=[{'version': '22.23.2'}, {'version': '24.20.0'}])
        self.assertNotEqual(f.run().returncode, 0)
        self.assertFalse(any(c[:2] in (["mise", "use"], ["mise", "install"]) for c in f.calls()))

    def test_pi_failure_branch_defers_cleanup_only_for_failed_runtime(self):
        for script in SCRIPTS:
            block = re.search(r'^    if install_pi_cli; then\n.*?^    fi$',
                              (ROOT / script).read_text(), re.M | re.S).group()
            for healthy in (False, True):
                with self.subTest(script=script, healthy=healthy):
                    f = self.fixture(version='24.20.0' if healthy else None, install_failure=not healthy)
                    command = ('remove_pi_subagents() { touch "$HOME/cleanup-ran"; }; '
                               'remove_pi_rpiv_packages() { touch "$HOME/cleanup-ran"; };\n' + block)
                    f.run(script, command)
                    self.assertEqual((f.home / 'cleanup-ran').exists(), healthy)

    def test_pi_runtime_boundaries(self):
        for version, ready in (("18.19.1", False), ("20.19.0", False), ("22.18.0", False),
                               ("22.19.0", True), ("22.20.0", True), ("24.20.0", True)):
            with self.subTest(version=version):
                f = self.fixture(inherited=version)
                self.assertEqual(f.run(command="pi_node_runtime_ready").returncode == 0, ready)
        f = self.fixture(no_glob=True)
        self.assertNotEqual(f.run(command="pi_node_runtime_ready").returncode, 0)

    def test_armv7_fallback_includes_earlier_skills_helper(self):
        for command in ("ensure_pi_node_runtime", "ensure_skills_cli_node_runtime"):
            f = self.fixture(arch="armv7l")
            result = f.run(command=command)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(f.selected(), "22.23.2")

    def test_absent_supported_selection_is_installed_without_reselection(self):
        for version in ('22.23.2', '26.0.0', '22'):
            f = self.fixture(version=version, missing_global=True, inherited='18.19.1')
            result = f.run()
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertFalse(any(c[:2] == ['mise', 'use'] for c in f.calls()))
            self.assertTrue(any(c[:2] == ['mise', 'install'] for c in f.calls()))

    def test_installed_but_incompatible_runtime_uses_fallback_not_absent_repair(self):
        f = self.fixture(version='22.23.2', no_glob=True)
        self.assertNotEqual(f.run().returncode, 0)
        self.assertTrue(any(c[:2] == ['mise', 'use'] for c in f.calls()))
        self.assertFalse(any(c[:2] == ['mise', 'install'] for c in f.calls()))

    def test_absent_armv7_node24_selection_switches_to_official_node22(self):
        f = self.fixture(version='24.20.0', missing_global=True, arch='armv7l')
        result = f.run()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(f.selected(), '22.23.2')
        self.assertFalse(any(c[:2] == ['mise', 'install'] for c in f.calls()))

    def test_home_conflict_is_reported_without_overwriting_pin(self):
        f = self.fixture(version="24.20.0", home_override="18.19.1")
        pin = f.home / ".mise.toml"
        pin.write_text('[tools]\nnode = "18.19.1"\n')
        before = pin.read_bytes()
        result = f.run()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(pin.read_bytes(), before)
        self.assertEqual(f.selected(), "24.20.0")
        self.assertFalse(any(c[:2] == ["mise", "use"] for c in f.calls()))

    def test_project_pin_is_not_changed(self):
        f = self.fixture(version="24.20.0")
        project = f.home / "project"
        project.mkdir()
        pin = project / ".mise.toml"
        pin.write_text('[tools]\nnode = "18"\n')
        result = f.run(command='cd "$HOME/project"; ensure_pi_node_runtime')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(pin.read_text(), '[tools]\nnode = "18"\n')

    def test_runtime_failures_do_not_mutate_pi(self):
        cases = (
            {"install_failure": True}, {"version": "24.20.0", "env_failure": True},
            {"version": "24.20.0", "npm_failure": True},
            {"version": "24.20.0", "no_activation": True}, {"arch": "armv6l"},
            {"inventory_failure": True},
        )
        for options in cases:
            with self.subTest(options=options):
                f = self.fixture(**options)
                package = f.home / ".local/lib/node_modules/@earendil-works/pi-coding-agent"
                package.mkdir(parents=True)
                sentinel = package / "keep"
                sentinel.write_text("existing package")
                executable(f.home / ".local/bin/pi", "#!/bin/sh\nexit 1\n")
                result = f.run(command="install_pi_cli")
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(sentinel.read_text(), "existing package")
                self.assertFalse(any(c[0] == "npm" and c[1:] != ["--version"] for c in f.calls()), f.calls())

    @unittest.skipUnless(MISE, "mise is required for the real activation fixture")
    def test_real_mise_and_fish_activate_shared_node_after_setup_exits(self):
        # Only expose the already installed runtime read-only; never install a tool.
        version = subprocess.check_output([NODE, "-p", "process.versions.node"], text=True).strip()
        real_node = Path(subprocess.check_output([NODE, "-p", "process.execPath"], text=True).strip()).resolve()
        if tuple(map(int, version.split(".")[:2])) < (22, 20):
            self.skipTest("a Node >=22.20 installation is needed")
        with tempfile.TemporaryDirectory(prefix="real-shared-node-") as tmp:
            home = Path(tmp) / "home"
            config = home / ".config/mise/config.toml"
            config.parent.mkdir(parents=True)
            config.write_text(f'[tools]\nnode = "{version}"\n')
            data = home / "mise-data"
            install = data / "installs/node" / version
            install.parent.mkdir(parents=True)
            install.symlink_to(real_node.parent.parent, target_is_directory=True)
            local_bin = home / ".local/bin"
            local_bin.mkdir(parents=True)
            (local_bin / "mise").symlink_to(MISE)
            fish_config = home / ".config/fish/config.fish"
            fish_config.parent.mkdir(parents=True)
            fish_config.write_text('set -gx PATH "$HOME/.local/bin" $PATH\nmise activate fish | source\n')
            env = {
                "HOME": str(home), "XDG_CONFIG_HOME": str(home / ".config"),
                "MISE_DATA_DIR": str(data), "MISE_CACHE_DIR": str(home / "mise-cache"),
                "MISE_STATE_DIR": str(home / "mise-state"), "MISE_OFFLINE": "true",
                "MISE_AUTO_INSTALL": "false", "MISE_NODE_COMPILE": "false",
                "MISE_TRUSTED_CONFIG_PATHS": str(home), "PATH": "/usr/bin:/bin",
                "TERM": "dumb", "PI_OFFLINE": "1", "PI_TELEMETRY": "0",
                "PI_CODING_AGENT_DIR": str(home / ".pi/agent"),
            }
            prelude = '\n'.join(f'{name}() {{ printf "%s\\n" "$*"; }}' for name in
                                ("print_debug", "print_message", "print_warning"))
            result = subprocess.run(["/bin/bash", "-c", prelude + '\n' + extract("ubuntu.sh") +
                                     '\nensure_pi_node_runtime'], cwd=home, env=env,
                                    capture_output=True, text=True, timeout=20)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(config.read_text(), f'[tools]\nnode = "{version}"\n')
            # The parent PATH still has no managed Node. A separate fish must activate it.
            fresh = subprocess.run([FISH, "-l", "-c", 'node -p process.execPath'], cwd=home, env=env,
                                   capture_output=True, text=True, timeout=20)
            self.assertEqual(fresh.returncode, 0, fresh.stdout + fresh.stderr)
            self.assertEqual(Path(fresh.stdout.strip()).resolve(), real_node)
            # A minimal Pi-like module exercises the exact missing-export startup failure.
            cli = home / 'pi-fixture.mjs'
            cli.write_text('#!/usr/bin/env node\nimport { globSync } from "node:fs"; console.log(typeof globSync);\n')
            cli.chmod(0o755)
            (local_bin / 'pi').symlink_to(cli)
            check = subprocess.run(["/bin/bash", "-c", extract("ubuntu.sh") +
                                    '\nverify_shared_node_shell "$HOME/.local/bin/pi"'],
                                   cwd=home, env=env, capture_output=True, text=True, timeout=20)
            self.assertEqual(check.returncode, 0, check.stdout + check.stderr)
            # Optional read-only smoke of an explicitly supplied installed Pi CLI.
            real_pi = os.environ.get('PI_RUNTIME_TEST_CLI')
            if real_pi:
                supplied = Path(real_pi)
                self.assertTrue(supplied.is_absolute() and supplied.is_file())
                (local_bin / 'pi').unlink()
                (local_bin / 'pi').symlink_to(supplied)
                actual = subprocess.run([FISH, '-l', '-c', 'pi --version'], cwd=home, env=env,
                                        capture_output=True, text=True, timeout=20)
                self.assertEqual(actual.returncode, 0, actual.stdout + actual.stderr)
                self.assertTrue(actual.stdout.strip())
            # Ordinary HOME pin precedence must not be masked by explicit mise env arguments.
            (home / '.mise.toml').write_text('[tools]\nnode = "18.19.1"\n')
            conflict = subprocess.run(["/bin/bash", "-c", prelude + '\n' + extract("ubuntu.sh") +
                                      '\nensure_pi_node_runtime'], cwd=home, env=env,
                                     capture_output=True, text=True, timeout=20)
            self.assertNotEqual(conflict.returncode, 0)
            self.assertEqual(config.read_text(), f'[tools]\nnode = "{version}"\n')
            self.assertEqual((home / '.mise.toml').read_text(), '[tools]\nnode = "18.19.1"\n')

    def test_global_22_19_is_upgraded_for_skills_requirement(self):
        f = self.fixture(version="22.19.0")
        result = f.run(command="ensure_skills_cli_node_runtime; ensure_pi_node_runtime")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(f.selected(), "24.20.0")


if __name__ == "__main__":
    unittest.main()
