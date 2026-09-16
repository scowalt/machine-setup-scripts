#!/usr/bin/env python3
"""Contract v1: disable only AskClaude using extracted helpers and temporary profiles."""
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
BASH = ('mac.sh', 'ubuntu.sh', 'wsl.sh', 'pi.sh', 'bazzite.sh')
SCRIPTS = (*BASH, 'win.ps1')
PWSH = os.environ.get('PWSH_BIN') or shutil.which('pwsh')
NODE = subprocess.check_output(['node', '-p', 'process.execPath'], text=True).strip()
BEGIN = '// BEGIN PI_ASKCLAUDE_POLICY'
END = '// END PI_ASKCLAUDE_POLICY'


def embedded(script):
    text = (ROOT / script).read_text()
    if BEGIN not in text or END not in text:
        raise AssertionError(f'{script}: AskClaude policy missing')
    return text.split(BEGIN, 1)[1].split(END, 1)[0]


def extract(script, name):
    prefix = 'function ' + name + r' \{' if script.endswith('.ps1') else name + r'\(\) \{'
    text = (ROOT / script).read_text()
    if name in ('disable_pi_askclaude', 'Disable-PiAskClaude'):
        start = re.search('^' + prefix + r'\n', text, re.M)
        if not start:
            raise AssertionError(f'{script}: {name} missing')
        return text[start.start():].split('# End Pi AskClaude policy.', 1)[0].rstrip()
    match = re.search('^' + prefix + r'\n.*?^\}', text, re.M | re.S)
    if not match:
        raise AssertionError(f'{script}: {name} missing')
    return match.group()


class AskClaudeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='pi-askclaude-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.home = self.root / 'home'; self.home.mkdir(mode=0o700)
        self.agent = self.home / '.pi/agent'; self.agent.mkdir(parents=True, mode=0o700)
        self.custom = self.home / 'custom agent'; self.custom.mkdir(mode=0o700)
        self.env = {'HOME': str(self.home), 'USERPROFILE': str(self.home),
                    'PI_CODING_AGENT_DIR': str(self.custom), 'LC_ALL': 'C',
                    'PATH': str(Path(NODE).parent) + os.pathsep + os.defpath}
        self.engine = embedded('mac.sh')

    def run_engine(self, active=None, engine=None, home=None):
        return subprocess.run([NODE, '--input-type=commonjs', '-', str(home or self.home),
                               str(self.custom if active is None else active)],
                              input=engine or self.engine, env=self.env, cwd=self.root,
                              text=True, capture_output=True, timeout=10)

    def seed(self, profile):
        config = {'provider': {'plan': 'max', 'pathToClaudeCodeExecutable': '/keep/claude',
                               'strictMcpConfig': False},
                  'askClaude': {'enabled': True, 'name': 'MyClaude', 'allowFullMode': False},
                  'unknown': {'secret': 'fixture-private'}}
        (profile / 'claude-bridge.json').write_text(json.dumps(config))
        (profile / 'claude-bridge.json').chmod(0o600)
        (profile / 'settings.json').write_text('{"packages":["npm:pi-claude-bridge"],"defaultModel":"keep"}')
        (profile / 'auth.json').write_text('fixture-auth-keep')
        return config

    def snapshot(self):
        return {str(p.relative_to(self.root)): (p.lstat().st_mode,
                os.readlink(p) if p.is_symlink() else p.read_bytes() if p.is_file() else None)
                for p in self.root.rglob('*')}

    def assert_rejected(self, **kwargs):
        before = self.snapshot()
        result = self.run_engine(**kwargs)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertEqual(self.snapshot(), before)
        self.assertNotIn('fixture-private', result.stdout + result.stderr)
        self.assertNotIn(str(self.root), result.stdout + result.stderr)

    def test_identical_helper_and_orchestration(self):
        for script in SCRIPTS:
            with self.subTest(script=script):
                self.assertEqual(embedded(script), self.engine)
                text = (ROOT / script).read_text()
                name = 'Disable-PiAskClaude' if script.endswith('.ps1') else 'disable_pi_askclaude'
                self.assertIn('npm:pi-claude-bridge', text)
                main = extract(script, 'Invoke-WindowsSetupTasks' if script.endswith('.ps1') else 'run_setup_tasks')
                prepare = 'Prepare-PiProfilePermissions' if script.endswith('.ps1') else 'prepare_pi_profile_permissions'
                retirement = 'Remove-PiProse' if script.endswith('.ps1') else 'remove_pi_prose'
                self.assertLess(main.index(prepare), main.index(name))
                self.assertLess(main.index(name), main.index(retirement))

    def test_preserves_bridge_and_idempotency(self):
        expected = {}
        for profile in (self.agent, self.custom):
            expected[profile] = self.seed(profile)
            expected[profile]['askClaude']['enabled'] = False
        before = self.snapshot()
        result = self.run_engine()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        for profile, config in expected.items():
            file = profile / 'claude-bridge.json'
            self.assertEqual(json.loads(file.read_text()), config)
            self.assertEqual(stat.S_IMODE(file.stat().st_mode), 0o600)
        after = self.snapshot()
        changed = [p for p in before if before[p] != after[p]]
        self.assertEqual(sorted(changed), sorted(str((p / 'claude-bridge.json').relative_to(self.root)) for p in expected))
        times = {p: p.stat().st_mtime_ns for p in self.root.rglob('*') if p.is_file()}
        self.assertEqual(self.run_engine().returncode, 0)
        self.assertEqual(self.snapshot(), after)
        self.assertEqual({p: p.stat().st_mtime_ns for p in times}, times)

    def test_missing_config_and_missing_askclaude(self):
        (self.custom / 'claude-bridge.json').write_text('{"provider":{"plan":"max"}}')
        result = self.run_engine()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(json.loads((self.agent / 'claude-bridge.json').read_text()), {'askClaude': {'enabled': False}})
        self.assertEqual(stat.S_IMODE((self.agent / 'claude-bridge.json').stat().st_mode), 0o600)
        self.assertEqual(json.loads((self.custom / 'claude-bridge.json').read_text()),
                         {'provider': {'plan': 'max'}, 'askClaude': {'enabled': False}})

    def test_bom_and_deduplicated_default_profile(self):
        file = self.agent / 'claude-bridge.json'
        for enabled in (True, False):
            file.write_text('\ufeff' + json.dumps({'askClaude': {'enabled': enabled}}))
            result = self.run_engine(active=self.agent)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            # Match the bridge's plain JSON.parse: a retained BOM makes it ignore
            # the whole configuration and default AskClaude back to enabled.
            self.assertFalse(file.read_text().startswith('\ufeff'))
            self.assertFalse(json.loads(file.read_text())['askClaude']['enabled'])
            self.assertFalse((self.custom / 'claude-bridge.json').exists())

    def test_all_profiles_preflighted_before_writes(self):
        self.seed(self.agent)
        file = self.custom / 'claude-bridge.json'
        for payload in ('', '{fixture-private', 'null', '[]', '42', '{"askClaude":null}',
                        '{"askClaude":[]}', '{"askClaude":true}', '{"askClaude":{"enabled":"false"}}'):
            with self.subTest(payload=payload):
                file.write_text(payload)
                self.assert_rejected()

    def test_linked_paths_and_files_rejected(self):
        self.seed(self.agent); self.seed(self.custom)
        for file in (self.custom / 'claude-bridge.json', self.custom, self.home / '.pi'):
            with self.subTest(file=file):
                saved = self.root / 'saved'; file.rename(saved)
                file.symlink_to(saved, target_is_directory=saved.is_dir())
                self.assert_rejected()
                file.unlink(); saved.rename(file)
        file = self.custom / 'claude-bridge.json'
        file.unlink(); file.symlink_to(self.root / 'absent')
        self.assert_rejected()

    def test_hardlinks_fifo_and_oversize_rejected(self):
        self.seed(self.agent); self.seed(self.custom)
        file = self.custom / 'claude-bridge.json'
        linked = self.root / 'shared'; os.link(file, linked)
        self.assert_rejected(); linked.unlink(); file.unlink()
        os.mkfifo(file); self.assert_rejected(); file.unlink()
        file.write_text(' ' * (1024 * 1024 + 1)); self.assert_rejected()

    def test_occupied_staging_file_preserved(self):
        self.seed(self.agent)
        occupied = self.agent / ('claude-bridge.json.setup-' + '00' * 12)
        occupied.write_text('fixture-private existing file')
        engine = self.engine.replace("const crypto = require('node:crypto');",
                                     "const crypto = require('node:crypto'); crypto.randomBytes = n => Buffer.alloc(n);")
        self.assert_rejected(engine=engine)

    def test_failed_write_leaves_config_and_no_temporary_file(self):
        self.seed(self.agent)
        engine = self.engine.replace("const fs = require('node:fs');",
            "const fs = require('node:fs'); fs.writeFileSync = () => { throw new Error('fixture-private'); };")
        self.assert_rejected(engine=engine)

    def test_invalid_profile_paths_rejected(self):
        self.seed(self.agent)
        outside = self.root / 'outside'; outside.mkdir()
        for active in ('relative', self.home, outside, str(self.home) + '/custom agent/../.pi/agent', ''):
            with self.subTest(active=active):
                self.assert_rejected(active=active)

    def test_missing_profile_not_silently_skipped(self):
        self.seed(self.agent)
        self.assert_rejected(active=self.home / 'missing')

    def test_home_alias_preserved(self):
        self.seed(self.agent); self.seed(self.custom)
        alias = self.root / 'home-alias'; alias.symlink_to(self.home, target_is_directory=True)
        result = self.run_engine(home=alias, active=alias / 'custom agent')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(json.loads((self.custom / 'claude-bridge.json').read_text())['askClaude']['enabled'])

    def run_wrapper(self, script):
        if script.endswith('.ps1'):
            if not PWSH:
                self.skipTest('PWSH_BIN unavailable')
            code = '''$ErrorActionPreference = 'Stop'
function Write-Debug { param($Text) }
function Write-Warning { param($Text) Write-Host $Text }
function Write-Success { param($Text) Write-Host $Text }
''' + extract(script, 'Disable-PiAskClaude')
            code += '\n$beforeOptions = $env:NODE_OPTIONS; $beforePath = $env:NODE_PATH; $beforeEncoding = $OutputEncoding\n'
            code += '$result = Disable-PiAskClaude\n'
            code += 'if ($env:NODE_OPTIONS -ne $beforeOptions -or $env:NODE_PATH -ne $beforePath -or $OutputEncoding -ne $beforeEncoding) { exit 98 }\n'
            code += 'if ($result -isnot [bool]) { exit 99 }; if (-not $result) { exit 1 }\n'
            file = self.root / 'wrapper.ps1'; file.write_text(code)
            command = [PWSH, '-NoProfile', '-NonInteractive', '-File', str(file)]
        else:
            code = '''print_debug() { :; }
print_warning() { printf '%s\\n' "$*"; }
print_success() { printf '%s\\n' "$*"; }
''' + extract(script, 'disable_pi_askclaude') + '\ndisable_pi_askclaude\n'
            command = ['bash', '--noprofile', '--norc']
        return subprocess.run(command, input=code, cwd=self.root, env=self.env,
                              text=True, capture_output=True, timeout=15)

    def test_dotfiles_setup_and_rerender_preserve_access(self):
        source = os.environ.get('PI_ADAPTER_DOTFILES_SOURCE')
        if not source or not shutil.which('chezmoi'):
            self.skipTest('Set PI_ADAPTER_DOTFILES_SOURCE with chezmoi for cross-repository coverage')
        template = Path(source) / 'private_dot_pi/agent/private_claude-bridge.json.tmpl'
        self.assertTrue(template.is_file())
        config = self.root / 'chezmoi.json'; config.write_text('{}')
        empty = self.root / 'source'; empty.mkdir()
        for script in (*BASH, *(['win.ps1'] if PWSH else [])):
            for work in ('0', '1'):
                with self.subTest(script=script, work=work):
                    self.env['WORK_MACHINE'] = work
                    default_expected = self.seed(self.agent); default_expected['askClaude']['enabled'] = False
                    custom_expected = self.seed(self.custom); custom_expected['askClaude']['enabled'] = False
                    untouched = {p: p.read_bytes() for profile in (self.agent, self.custom)
                                 for p in (profile / 'auth.json', profile / 'settings.json')}
                    project = self.home / 'project/.pi'; project.mkdir(parents=True, exist_ok=True)
                    (project / 'claude-bridge.json').write_text('{"askClaude":{"enabled":true}}')
                    untouched[project / 'claude-bridge.json'] = (project / 'claude-bridge.json').read_bytes()
                    for _ in range(2):
                        rendered = subprocess.run([shutil.which('chezmoi'), '--config', str(config), '--source', str(empty),
                            '--destination', str(self.home), '--cache', str(self.root / 'cache'),
                            '--persistent-state', str(self.root / 'state.boltdb'), '--override-data',
                            json.dumps({'chezmoi': {'homeDir': str(self.home)}}), 'execute-template', '--file', str(template)],
                            env=self.env, capture_output=True, text=True, timeout=10)
                        self.assertEqual(rendered.returncode, 0, rendered.stderr)
                        (self.agent / 'claude-bridge.json').write_text(rendered.stdout)
                        result = self.run_wrapper(script)
                        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                        self.assertEqual(json.loads((self.agent / 'claude-bridge.json').read_text()), default_expected)
                        self.assertEqual(json.loads((self.custom / 'claude-bridge.json').read_text()), custom_expected)
                    self.assertEqual({p: p.read_bytes() for p in untouched}, untouched)

    def test_default_profile_without_override(self):
        self.env.pop('PI_CODING_AGENT_DIR')
        for script in (*BASH, *(['win.ps1'] if PWSH else [])):
            with self.subTest(script=script):
                self.seed(self.agent)
                result = self.run_wrapper(script)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertFalse(json.loads((self.agent / 'claude-bridge.json').read_text())['askClaude']['enabled'])
                self.assertFalse((self.custom / 'claude-bridge.json').exists())

    def test_wrappers_success_and_failure_with_inherited_node_controls(self):
        self.env['NODE_OPTIONS'] = '--require /nonexistent-fixture'
        self.env['NODE_PATH'] = '/nonexistent-fixture'
        for script in (*BASH, *(['win.ps1'] if PWSH else [])):
            with self.subTest(script=script):
                self.seed(self.agent); self.seed(self.custom)
                result = self.run_wrapper(script)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                for profile in (self.agent, self.custom):
                    self.assertFalse(json.loads((profile / 'claude-bridge.json').read_text())['askClaude']['enabled'])
                (self.custom / 'claude-bridge.json').write_text('{fixture-private')
                result = self.run_wrapper(script)
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertNotIn('fixture-private', result.stdout + result.stderr)
                self.assertNotIn(str(self.home), result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
