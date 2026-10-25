#!/usr/bin/env python3
import json
import os
import shutil
import subprocess
import unittest

import test_pi_visual_explainer as fixtures

assert fixtures.FAKE_PI.count("if args[0]=='update': sys.exit(0)") == 1
CLEANING_PI = fixtures.FAKE_PI.replace(
    "if args[0]=='update': sys.exit(0)", r'''
import subprocess
agent=pathlib.Path(os.environ.get('PI_CODING_AGENT_DIR') or str(pathlib.Path(os.environ['HOME'])/'.pi/agent'))
checkout=agent/'git/github.com/nicobailon/visual-explainer'
if checkout.exists():
    revision=os.environ.get('FIXTURE_REVISION')
    if revision: subprocess.run(['git','reset','--hard',revision],cwd=checkout,check=True,stdout=subprocess.DEVNULL)
    subprocess.run(['git','clean','-fdx'],cwd=checkout,check=True,stdout=subprocess.DEVNULL)
    with (root/'native-cleanups').open('a') as stream: stream.write('clean\n')
    modules=checkout/'node_modules/fixture-dependency'; modules.mkdir(parents=True,exist_ok=True)
    (modules/'package.json').write_text('{"name":"fixture-dependency","version":"1.0.0"}')
    (checkout/'package-lock.json').write_text('{"name":"visual-explainer","lockfileVersion":3}')
    if os.environ.get('FIXTURE_OPTIONAL_CONFLICT'):
        nested=checkout/'plugins/visual-explainer/node_modules'
        nested.mkdir(parents=True); (nested/'new-content').write_text('new conflict must survive')
    if os.environ.get('FIXTURE_HELD_TAMPER'):
        saved=agent/'.setup-visual-explainer-dependencies/node_modules/playwright-core/cli.js'
        if saved.exists(): saved.write_text('changed while held')
if os.environ.get('FIXTURE_NATIVE_SIGNAL'):
    import signal
    os.kill(os.getpid(),signal.SIGTERM)
if os.environ.get('FIXTURE_NATIVE_FAILURE'):
    print('SECRET-SENTINEL native failure',file=sys.stderr); sys.exit(1)
if args[0]=='update': sys.exit(0)
''')


class OptionalDependencies(unittest.TestCase):
    def setUp(self):
        self.f = fixtures.VisualExplainerTests()
        self.f.setUp()
        self.addCleanup(self.f.doCleanups)
        self.f.installed()
        (self.f.bin / 'pi').write_text(CLEANING_PI)
        self.nested = self.f.checkout / fixtures.PAYLOAD / 'node_modules'
        self.saved = self.f.agent / '.setup-visual-explainer-dependencies'

    def optional(self):
        package = self.nested / 'playwright-core'
        package.mkdir(parents=True)
        (package / 'package.json').write_text(json.dumps({
            'name': 'playwright-core', 'version': '1.64.1', 'bin': {'playwright-core': 'cli.js'}}))
        (package / 'cli.js').write_text('throw Error("NEVER EXECUTE OPTIONAL FIXTURE");\n')
        (package / 'cli.js').chmod(0o775)
        (self.nested / '.package-lock.json').write_text(json.dumps({
            'lockfileVersion': 3, 'packages': {'node_modules/playwright-core': {'version': '1.64.1'}}}))
        (self.nested / '.bin').mkdir()
        (self.nested / '.bin/playwright-core').symlink_to('../playwright-core/cli.js')
        for file in self.nested.rglob('*'):
            if not file.is_symlink(): file.chmod(0o775 if file.is_dir() else file.stat().st_mode & 0o777 | 0o020)
        self.nested.chmod(0o775)

    def snapshot(self, root=None):
        root = root or self.nested
        return {str(p.relative_to(root)): (os.readlink(p) if p.is_symlink() else p.read_bytes() if p.is_file() else None,
                                          p.lstat().st_mode, p.lstat().st_ino)
                for p in (root, *sorted(root.rglob('*')))}

    def advance(self):
        old = self.f.git('rev-parse', 'HEAD').stdout.strip()
        (self.f.checkout / 'new-upstream-file').write_text('inert upstream revision\n')
        self.f.git('add', 'new-upstream-file')
        self.f.git('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-qm', 'next fixture')
        new = self.f.git('rev-parse', 'HEAD').stdout.strip()
        self.f.git('reset', '--hard', old)
        return new

    def test_original_checkout_shape_passes_plan_and_finish_without_mutation(self):
        self.optional()
        before = self.snapshot()
        status = self.f.git('status', '--porcelain=v1', '-z', '--untracked-files=normal', '--ignored=matching').stdout
        self.assertIn('!! plugins/visual-explainer/node_modules/\0', status)
        for _ in range(2):
            plan = self.f.policy()
            self.assertEqual((plan.returncode, plan.stdout), (0, 'source:' + fixtures.SOURCE + '\n'))
            finish = self.f.policy('finish')
            self.assertEqual((finish.returncode, finish.stdout), (0, 'ok\n'))
            self.assertEqual(self.snapshot(), before)
            self.assertFalse(self.saved.exists())
            self.assertFalse(self.f.calls.exists())

    def test_all_six_install_register_repeat_and_refresh_preserve_exact_optional_copy(self):
        self.optional()
        before = self.snapshot()
        revision = self.advance()
        for script in fixtures.SCRIPTS:
            with self.subTest(script=script):
                self.f.settings.write_text('{"packages":["npm:user-package@1.2.3"],"sentinel":"keep"}')
                self.f.assert_ok(self.f.wrapper(script, overrides={'FIXTURE_REVISION': revision}))
                self.assertEqual(self.snapshot(), before)
                self.assertFalse(self.saved.exists())
                self.assertIn('clean', (self.f.root / 'native-cleanups').read_text())
                self.assertEqual(self.f.git('rev-parse', 'HEAD').stdout.strip(), revision)
                self.assertTrue((self.f.checkout / 'new-upstream-file').is_file())
                self.assertEqual(json.loads(self.f.settings.read_text())['packages'], ['npm:user-package@1.2.3', fixtures.SOURCE])
                self.f.assert_ok(self.f.wrapper(script))
                self.f.assert_ok(self.f.wrapper(script, refresh=True, overrides={'FIXTURE_REVISION': revision}))
                self.assertEqual(self.snapshot(), before)
                self.assertFalse(self.saved.exists())

    def test_refresh_does_not_inspect_or_modify_an_unregistered_visual_checkout(self):
        self.f.settings.write_text('{"packages":["npm:user-package@1.2.3"]}')
        (self.f.bin / 'pi').write_text(fixtures.FAKE_PI)
        outside = self.f.root / 'unregistered-checkout'
        self.f.checkout.rename(outside)
        self.f.checkout.symlink_to(outside, target_is_directory=True)
        before = (outside / 'package.json').read_bytes()
        for script in ('ubuntu.sh', 'win.ps1'):
            result = self.f.wrapper(script, refresh=True, overrides={'GIT_DIR': str(self.f.root / 'unrelated-git-control')})
            self.f.assert_ok(result)
            self.assertTrue(self.f.checkout.is_symlink())
            self.assertEqual((outside / 'package.json').read_bytes(), before)
            self.assertFalse(self.saved.exists())

    def test_absent_optional_dependency_does_not_create_recovery_state_or_install_a_replacement(self):
        for script in fixtures.SCRIPTS:
            self.f.assert_ok(self.f.wrapper(script))
            self.f.assert_ok(self.f.wrapper(script, refresh=True))
            self.assertFalse(self.nested.exists())
            self.assertFalse(self.saved.exists())
        calls = [json.loads(line) for line in self.f.calls.read_text().splitlines()]
        self.assertTrue(all(call in (['install', fixtures.SOURCE, '--no-approve'],
                                     ['update', '--extensions', '--no-approve']) for call in calls))

    def test_default_profile_and_user_pins_and_resource_filters_are_preserved(self):
        self.optional()
        before = self.snapshot()
        source = fixtures.SOURCE + '@v0.12.0'
        settings = {'packages': [{'source': source, 'extensions': [], 'skills': ['!**'], 'prompts': ['+commands/diff-review.md']}],
                    'npmCommand': ['npm', '--safe'], 'sentinel': 'keep'}
        self.f.settings.write_text(json.dumps(settings))
        original = self.f.settings.read_bytes()
        for script in fixtures.SCRIPTS:
            self.f.assert_ok(self.f.wrapper(script))
            self.f.assert_ok(self.f.wrapper(script, refresh=True))
            self.assertEqual(self.f.settings.read_bytes(), original)
            self.assertEqual(self.snapshot(), before)
        default = self.f.home / '.pi/agent'
        self.f.sentinels.pop(default / 'settings.json')
        shutil.rmtree(default)
        old_agent = self.f.agent
        old_agent.rename(default)
        self.f.sentinels = {(default / p.relative_to(old_agent) if p.is_relative_to(old_agent) else p): data
                            for p, data in self.f.sentinels.items()}
        self.f.env.pop('PI_CODING_AGENT_DIR')
        self.f.agent = default
        self.f.settings = default / 'settings.json'
        self.f.checkout = default / 'git/github.com/nicobailon/visual-explainer'
        self.nested = self.f.checkout / fixtures.PAYLOAD / 'node_modules'
        for script in fixtures.SCRIPTS:
            self.f.assert_ok(self.f.wrapper(script))
            self.f.assert_ok(self.f.wrapper(script, refresh=True))
            self.assertEqual(self.snapshot(), before)

    def test_native_install_and_refresh_failures_restore_without_reporting_success(self):
        self.optional()
        before = self.snapshot()
        for script in fixtures.SCRIPTS:
            for refresh in (False, True):
                with self.subTest(script=script, refresh=refresh):
                    result = self.f.wrapper(script, refresh=refresh, overrides={'FIXTURE_NATIVE_FAILURE': '1'})
                    self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                    self.assertNotIn('SUCCESS:', result.stdout)
                    self.assertIn('failed:native-command', result.stdout + result.stderr)
                    self.assertTrue(self.f.calls.exists(), 'The native command must actually fail after cleanup')
                    self.assertEqual(self.snapshot(), before)
                    self.assertFalse(self.saved.exists())

    @unittest.skipUnless(fixtures.PWSH, 'Set PWSH_BIN; native Windows remains separately unverified')
    def test_native_windows_delegation_uses_data_arguments_and_strips_node_controls(self):
        program = self.f.root / 'windows-delegation.cjs'
        program.write_text(r'''
const child=require('node:child_process'); let captured;
child.spawnSync=(command,args,options)=>{captured={command,args,input:options.input,
    nodeOptions:!!options.env.NODE_OPTIONS,nodePath:!!options.env.NODE_PATH};return {status:0};};
Object.defineProperty(process,'platform',{value:'win32'});
process.env.SystemRoot='C:\\Windows';
process.env.NODE_OPTIONS='SECRET-SENTINEL';process.env.NODE_PATH='SECRET-SENTINEL';
const core=require(''' + json.dumps(str(fixtures.CORE)) + r''');
const ok=core.nativePi(['install','git:github.com/nicobailon/visual-explainer@v0.12.0','--no-approve']);
console.log(JSON.stringify({ok,...captured}));
''')
        result = subprocess.run([fixtures.NODE, str(program)], env=self.f.env, cwd=self.f.root,
                                text=True, capture_output=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        data = json.loads(result.stdout)
        self.assertTrue(data['ok'])
        self.assertFalse(data['nodeOptions'])
        self.assertFalse(data['nodePath'])
        self.assertIn('System32/WindowsPowerShell/v1.0/powershell.exe', data['command'])
        self.assertEqual(data['args'][:3], ['-NoProfile', '-NonInteractive', '-EncodedCommand'])
        result = subprocess.run([fixtures.PWSH, *data['args']], input=data['input'],
                                env=self.f.env, cwd=self.f.root, text=True, capture_output=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(json.loads(self.f.calls.read_text().splitlines()[-1]),
                         ['install', fixtures.SOURCE + '@v0.12.0', '--no-approve'])

    def test_optional_lock_can_be_absent_and_native_windows_bin_files_are_preserved(self):
        self.optional()
        (self.nested / '.package-lock.json').unlink()
        (self.nested / '.bin/playwright-core').unlink()
        for name in ('playwright-core', 'playwright-core.cmd', 'playwright-core.ps1'):
            (self.nested / '.bin' / name).write_text('inert native npm command shim\n')
        before = self.snapshot()
        self.f.assert_ok(self.f.wrapper('ubuntu.sh'))
        self.f.assert_ok(self.f.wrapper('win.ps1', refresh=True))
        self.assertEqual(self.snapshot(), before)

    def test_interrupted_native_child_restores_and_propagates_failure(self):
        self.optional()
        before = self.snapshot()
        result = self.f.wrapper('ubuntu.sh', overrides={'FIXTURE_NATIVE_SIGNAL': '1'})
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn('failed:native-command', result.stdout + result.stderr)
        self.assertEqual(self.snapshot(), before)
        self.assertFalse(self.saved.exists())

    def test_prior_recovery_state_is_never_followed_consumed_or_overwritten(self):
        self.optional()
        before = self.snapshot()
        for kind in ('directory', 'file', 'link'):
            with self.subTest(kind=kind):
                if kind == 'directory':
                    self.saved.mkdir(); (self.saved / 'custom').write_text('old recovery data')
                elif kind == 'file': self.saved.write_text('old recovery metadata')
                else: self.saved.symlink_to(self.f.home, target_is_directory=True)
                for script in ('ubuntu.sh', 'win.ps1'):
                    result = self.f.wrapper(script)
                    self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                    self.assertIn('dependency-recovery', result.stdout + result.stderr)
                    self.assertFalse(self.f.calls.exists())
                    self.assertEqual(self.snapshot(), before)
                if kind == 'directory':
                    self.assertEqual((self.saved / 'custom').read_text(), 'old recovery data')
                    (self.saved / 'custom').unlink(); self.saved.rmdir()
                else: self.saved.unlink()

    def test_restoration_does_not_depend_on_successful_metadata_or_payload_validation(self):
        self.optional()
        before = self.snapshot()
        for failure in ('metadata', 'registration', 'dependency', 'resource'):
            with self.subTest(failure=failure):
                self.f.settings.write_text('{}')
                result = self.f.wrapper('ubuntu.sh', overrides={'FIXTURE_FAILURE': failure})
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertTrue(self.f.calls.exists(), 'Post-command validation must be reached')
                self.assertEqual(self.snapshot(), before)
                self.assertFalse(self.saved.exists())
                self.f.settings.write_text('{}')
                shutil.copy2(self.f.template / fixtures.PAYLOAD / 'extension.ts', self.f.checkout / fixtures.PAYLOAD / 'extension.ts')

    def test_unsafe_or_unknown_nested_artifacts_block_before_native_execution(self):
        for condition in ('unknown-package', 'extra-file', 'linked-root', 'linked-package', 'linked-file',
                          'hardlinked-file', 'world-write', 'bad-lock', 'wrong-lock-version', 'wrong-name',
                          'escaping-bin', 'linked-lock', 'other-nested-modules', 'bin-is-file'):
            with self.subTest(condition=condition):
                if self.nested.exists(): shutil.rmtree(self.nested)
                self.optional()
                package = self.nested / 'playwright-core'
                if condition == 'unknown-package': (self.nested / 'other-package').mkdir()
                elif condition == 'extra-file': (self.nested / 'custom-notes').write_text('preserve me')
                elif condition == 'linked-root':
                    outside = self.f.root / 'outside-modules'; self.nested.rename(outside); self.nested.symlink_to(outside, target_is_directory=True)
                elif condition == 'linked-package':
                    outside = self.f.root / 'outside-package'; package.rename(outside); package.symlink_to(outside, target_is_directory=True)
                elif condition in ('linked-file', 'hardlinked-file'):
                    file = package / 'cli.js'; file.unlink()
                    if condition == 'linked-file': file.symlink_to(self.f.settings)
                    else: os.link(self.f.settings, file)
                elif condition == 'world-write': (package / 'cli.js').chmod(0o777)
                elif condition == 'bad-lock': (self.nested / '.package-lock.json').write_text('{malformed')
                elif condition == 'wrong-lock-version': (self.nested / '.package-lock.json').write_text('{"lockfileVersion":3,"packages":{"node_modules/playwright-core":{"version":"9.0.0"}}}')
                elif condition == 'wrong-name': (package / 'package.json').write_text('{"name":"foreign","version":"1.64.1"}')
                elif condition == 'escaping-bin':
                    link = self.nested / '.bin/playwright-core'; link.unlink(); link.symlink_to(self.f.settings)
                elif condition == 'linked-lock':
                    lock = self.nested / '.package-lock.json'; lock.unlink(); lock.symlink_to(self.f.settings)
                elif condition == 'bin-is-file':
                    shutil.rmtree(self.nested / '.bin'); (self.nested / '.bin').write_text('not a directory')
                else:
                    extra = self.f.checkout / fixtures.PAYLOAD / 'other/node_modules'; extra.mkdir(parents=True)
                    (extra / 'custom').write_text('not an allowed location')
                for refresh in (False, True):
                    result = self.f.wrapper('ubuntu.sh', refresh=refresh)
                    self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                    self.assertFalse(self.f.calls.exists())
                    self.assertFalse(self.saved.exists())
                if self.nested.is_symlink(): self.nested.unlink()
                if condition == 'other-nested-modules': shutil.rmtree(self.f.checkout / fixtures.PAYLOAD / 'other')

    def test_restore_conflict_keeps_both_copies_and_blocks_subsequent_mutations(self):
        self.optional()
        original = self.snapshot()
        result = self.f.wrapper('ubuntu.sh', overrides={'FIXTURE_OPTIONAL_CONFLICT': '1'})
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn('dependency-recovery', result.stdout + result.stderr)
        self.assertEqual((self.nested / 'new-content').read_text(), 'new conflict must survive')
        self.assertEqual(self.snapshot(self.saved / 'node_modules'), original)
        calls = self.f.calls.read_bytes()
        self.assertEqual(self.f.wrapper('ubuntu.sh').returncode, 1)
        self.assertEqual(self.f.calls.read_bytes(), calls)

    def test_changed_held_snapshot_stops_restoration_without_deleting_recovery_copy(self):
        self.optional()
        result = self.f.wrapper('ubuntu.sh', overrides={'FIXTURE_HELD_TAMPER': '1'})
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn('dependency-recovery', result.stdout + result.stderr)
        self.assertTrue((self.saved / 'node_modules/playwright-core/cli.js').is_file())
        self.assertFalse(self.nested.exists())


if __name__ == '__main__':
    unittest.main(verbosity=2)
