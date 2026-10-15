#!/usr/bin/env python3
import functools
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from extract_setup_fixture import definitions

ROOT = Path(__file__).resolve().parents[1]
CORE = ROOT / 'lib/pi-visual-explainer.cjs'
SCRIPTS = ('mac.sh', 'ubuntu.sh', 'wsl.sh', 'pi.sh', 'bazzite.sh', 'win.ps1')
SOURCE = 'git:github.com/nicobailon/visual-explainer'
PAYLOAD = 'plugins/visual-explainer'
NODE = shutil.which('node')
PWSH = os.environ.get('PWSH_BIN') or shutil.which('pwsh')
COMMANDS = ('diff-review', 'fact-check', 'generate-slides', 'generate-video', 'generate-visual-plan',
            'generate-web-diagram', 'plan-review', 'project-recap')

FAKE_PI = r'''#!/usr/bin/python3
import json, os, pathlib, shutil, sys
args=sys.argv[1:]
root=pathlib.Path(os.environ['FIXTURE_ROOT'])
with (root/'calls').open('a') as stream: stream.write(json.dumps(args)+'\n')
if os.environ.get('NODE_OPTIONS') or os.environ.get('NODE_PATH'): sys.exit(99)
if args[0]=='update': sys.exit(0)
assert args[0]=='install' and args[2:]==['--no-approve']
failure=os.environ.get('FIXTURE_FAILURE','')
if failure=='command':
    print('SECRET-SENTINEL',file=sys.stderr); sys.exit(1)
agent=pathlib.Path(os.environ.get('PI_CODING_AGENT_DIR') or str(pathlib.Path(os.environ['HOME'])/'.pi/agent'))
checkout=agent/'git/github.com/nicobailon/visual-explainer'
if not checkout.exists(): shutil.copytree(root/'template',checkout)
settings=agent/'settings.json'
value=json.loads(settings.read_text()) if settings.exists() else {}
if failure!='registration':
    if not any((p if isinstance(p,str) else p['source'])==args[1] for p in value.get('packages',[])):
        value.setdefault('packages',[]).append(args[1]); settings.write_text(json.dumps(value))
modules=checkout/'node_modules/fixture-dependency'; modules.mkdir(parents=True,exist_ok=True)
(modules/'package.json').write_text('{"name":"fixture-dependency","version":"1.0.0"}')
(checkout/'package-lock.json').write_text('{"name":"visual-explainer","lockfileVersion":3}')
if failure=='dependency': (modules/'package.json').unlink()
if failure=='resource': (checkout/'plugins/visual-explainer/extension.ts').unlink()
if failure=='metadata': settings.write_text('{SECRET-SENTINEL')
'''


@functools.lru_cache(maxsize=None)
def bash_definitions(script):
    return definitions((ROOT / script).read_text())


class VisualExplainerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='pi-visual-explainer-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.home = self.root / 'account with spaces'
        self.agent = self.home / 'profiles/selected pi'
        self.agent.mkdir(parents=True, mode=0o700)
        self.settings = self.agent / 'settings.json'
        self.checkout = self.agent / 'git/github.com/nicobailon/visual-explainer'
        self.template = self.root / 'template'
        skill = self.template / PAYLOAD
        (skill / 'commands').mkdir(parents=True)
        (skill / 'templates').mkdir()
        (skill / 'SKILL.md').write_text('---\nname: visual-explainer\ndescription: inert fixture\n---\nNever execute this skill.\n')
        (skill / 'extension.ts').write_text('throw new Error("DO NOT EXECUTE FIXTURE EXTENSION");\n')
        (skill / 'templates/page.html').write_text('<!doctype html><title>Inert</title>')
        for name in COMMANDS:
            (skill / 'commands' / (name + '.md')).write_text('Inert ' + name + '\n')
        (self.template / '.gitignore').write_text('node_modules/\nignored-notes\n')
        manifest = {'name': 'visual-explainer', 'version': '0.12.0', 'dependencies': {'fixture-dependency': '1.0.0'},
                    'pi': {'extensions': ['./' + PAYLOAD + '/extension.ts'], 'skills': ['./' + PAYLOAD],
                           'prompts': ['./' + PAYLOAD + '/commands']}}
        (self.template / 'package.json').write_text(json.dumps(manifest))
        self.env = {**os.environ, 'HOME': str(self.home), 'USERPROFILE': str(self.home),
                    'PI_CODING_AGENT_DIR': str(self.agent), 'FIXTURE_ROOT': str(self.root)}
        self.env.pop('NODE_OPTIONS', None)
        self.env.pop('NODE_PATH', None)
        self.git('init', '-q', cwd=self.template)
        self.git('remote', 'add', 'origin', 'https://github.com/nicobailon/visual-explainer.git', cwd=self.template)
        self.git('add', '.', cwd=self.template)
        self.git('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid',
                 'commit', '-qm', 'inert fixture', cwd=self.template)
        self.git('tag', 'v0.12.0', cwd=self.template)
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        for name, content in [('pi', FAKE_PI), ('npm', '#!/bin/sh\nexit 0\n')]:
            file = self.bin / name
            file.write_text(content)
            file.chmod(0o700)
        self.env['PATH'] = str(self.bin) + os.pathsep + self.env['PATH']
        self.calls = self.root / 'calls'
        self.settings.write_text('{"sentinel":"preserved","packages":["npm:user-package@1.2.3"]}')
        self.sentinels = {}
        for file in (self.home / '.pi/agent/settings.json', self.root / '.pi/settings.json',
                     self.home / '.agent/diagrams/existing.html', self.agent / 'auth.json', self.agent / 'custom-prose.json'):
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_text('SECRET-SENTINEL existing unrelated bytes')
            self.sentinels[file] = file.read_bytes()

    def git(self, *args, cwd=None):
        return subprocess.run(['git', *args], env=self.env, cwd=cwd or self.checkout,
                              text=True, capture_output=True, check=True)

    def installed(self, source=SOURCE):
        if not self.checkout.exists():
            shutil.copytree(self.template, self.checkout)
        modules = self.checkout / 'node_modules/fixture-dependency'
        modules.mkdir(parents=True, exist_ok=True)
        (modules / 'package.json').write_text('{"name":"fixture-dependency","version":"1.0.0"}')
        (self.checkout / 'package-lock.json').write_text('{"name":"visual-explainer","lockfileVersion":3}')
        self.settings.write_text(json.dumps({'packages': [source], 'sentinel': 'preserved'}))

    def legacy(self):
        skill = self.agent / 'skills/visual-explainer'
        shutil.copytree(self.template / PAYLOAD, skill)
        prompts = self.agent / 'prompts'
        prompts.mkdir()
        for name in COMMANDS:
            shutil.copy2(self.template / PAYLOAD / 'commands' / (name + '.md'), prompts / (name + '.md'))
        (prompts / 'custom.md').write_text('SECRET-SENTINEL custom prompt')
        (prompts / 'share-unverified.md').write_text('SECRET-SENTINEL unknown legacy prompt')
        return skill, prompts

    def policy(self, mode='plan', source=SOURCE, prelude=''):
        program = self.root / 'policy.cjs'
        program.write_text(prelude + '\nprocess.exitCode=require(' + json.dumps(str(CORE)) + ').main(process.argv.slice(2));\n')
        return subprocess.run([NODE, str(program), mode, str(self.home), str(self.agent), source],
                              env=self.env, cwd=self.root, text=True, capture_output=True, timeout=30)

    def wrapper(self, script, refresh=False, overrides=None):
        env = {**self.env, **(overrides or {})}
        if script.endswith('.ps1'):
            if not PWSH:
                self.skipTest('Set PWSH_BIN for portable PowerShell wrapper coverage')
            code = r'''$ErrorActionPreference='Stop'
$tokens=$null; $errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile($env:FIXTURE_SOURCE,[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw 'Invalid fixture source' }
foreach ($definition in $ast.EndBlock.Statements) {
    if ($definition -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $definition.Name -in @('Invoke-PiVisualExplainerPolicy','Setup-PiVisualExplainer','Update-PiPackages')) {
        . ([scriptblock]::Create($definition.Extent.Text))
    }
}
function Write-Message { }
function Write-Success($Text) { Write-Host "SUCCESS: $Text" }
function Write-Warning($Text) { Write-Host "WARNING: $Text" }
$script:PiProfileMutationsBlocked=$env:FIXTURE_BLOCKED -eq '1'
'''
            code += '$result=' + ('Update-PiPackages' if refresh else 'Setup-PiVisualExplainer')
            code += '\nif ($result -isnot [bool]) { exit 99 }; if (-not $result) { exit 1 }\n'
            fixture = self.root / 'wrapper.ps1'
            fixture.write_text(code)
            env['FIXTURE_SOURCE'] = str(ROOT / script)
            command = [PWSH, '-NoProfile', '-NonInteractive', '-File', str(fixture)]
        else:
            code = bash_definitions(script) + r'''
print_message() { :; }
print_success() { printf 'SUCCESS: %s\n' "$*"; }
print_warning() { printf 'WARNING: %s\n' "$*"; }
'''
            code += '\n' + ('refresh_pi_packages' if refresh else 'setup_pi_visual_explainer') + '\n'
            command = ['bash', '--noprofile', '--norc']
        result = subprocess.run(command, input=code, env=env, cwd=self.root, text=True, capture_output=True, timeout=40)
        self.assertNotIn('SECRET-SENTINEL', result.stdout + result.stderr)
        self.assertNotIn(str(self.home), result.stdout + result.stderr)
        for file, data in self.sentinels.items():
            self.assertEqual(file.read_bytes(), data, str(file))
        return result

    def assert_ok(self, result):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_all_six_install_repeat_and_refresh_active_profile_on_work_and_headless(self):
        for script in SCRIPTS:
            with self.subTest(script=script):
                if self.checkout.exists(): shutil.rmtree(self.agent / 'git')
                self.settings.write_text('{"sentinel":"preserved","packages":["npm:user-package@1.2.3"]}')
                for _ in range(2):
                    self.assert_ok(self.wrapper(script, overrides={'WORK_MACHINE': '1', 'HEADLESS': '1'}))
                    self.assert_ok(self.wrapper(script, refresh=True))
                packages = json.loads(self.settings.read_text())['packages']
                self.assertEqual(packages, ['npm:user-package@1.2.3', SOURCE])
                self.assertTrue((self.checkout / PAYLOAD / 'extension.ts').is_file())
                self.assertFalse((self.agent / 'skills/visual-explainer').exists())
        calls = [json.loads(line) for line in self.calls.read_text().splitlines()]
        self.assertEqual(calls.count(['install', SOURCE, '--no-approve']), 12)
        self.assertEqual(calls.count(['update', '--extensions', '--no-approve']), 12)

    def test_default_profile_is_used_when_no_profile_is_selected(self):
        default = self.home / '.pi/agent'
        self.sentinels.pop(default / 'settings.json')
        (default / 'settings.json').write_text('{}')
        self.env.pop('PI_CODING_AGENT_DIR')
        selected = self.settings.read_bytes()
        for script in SCRIPTS:
            with self.subTest(script=script):
                self.assert_ok(self.wrapper(script))
                self.assertEqual(self.settings.read_bytes(), selected)
                self.assertEqual(json.loads((default / 'settings.json').read_text())['packages'], [SOURCE])

    def test_native_https_ssh_and_scp_origins_are_verified_without_rewriting_them(self):
        self.installed()
        for origin in ('https://github.com/nicobailon/visual-explainer.git',
                       'ssh://git@github.com/nicobailon/visual-explainer.git',
                       'git@github.com:nicobailon/visual-explainer.git'):
            self.git('remote', 'set-url', 'origin', origin)
            for script in SCRIPTS:
                with self.subTest(script=script, origin=origin):
                    self.assert_ok(self.wrapper(script))
                    self.assert_ok(self.wrapper(script, refresh=True))
                    self.assertEqual(self.git('remote', 'get-url', 'origin').stdout.strip(), origin)

    def test_windows_git_line_ending_conversion_is_exact_and_does_not_run_filters(self):
        program = 'const {matchesBlob}=require(' + json.dumps(str(CORE)) + '); const b=Buffer.from; console.log(JSON.stringify([' + \
            'matchesBlob(b("a\\r\\nb\\r\\n"),b("a\\nb\\n"),true),' + \
            'matchesBlob(b("a\\r\\nb\\r\\n"),b("a\\nb\\n"),false),' + \
            'matchesBlob(b("a\\r\\nEDIT\\r\\n"),b("a\\nb\\n"),true),' + \
            'matchesBlob(b([0,13,10]),b([0,10]),true)]));'
        result = subprocess.run([NODE, '-e', program], env=self.env, cwd=self.root, text=True, capture_output=True, timeout=15)
        self.assertEqual((result.returncode, result.stdout.strip()), (0, '[true,false,false,false]'))

    def test_existing_pins_aliases_and_resource_filters_are_preserved(self):
        for source in (SOURCE + '@v0.12.0', 'https://github.com/nicobailon/visual-explainer.git@v0.12.0',
                       'git:git@github.com:nicobailon/visual-explainer@v0.12.0',
                       'ssh://git@github.com/nicobailon/visual-explainer@v0.12.0'):
            self.installed(source)
            value = {'source': source, 'extensions': [], 'skills': ['!**'], 'prompts': ['+commands/diff-review.md']}
            self.settings.write_text(json.dumps({'packages': [value], 'npmCommand': ['npm', '--safe'], 'sentinel': 'preserved'}))
            before = self.settings.read_bytes()
            for script in SCRIPTS:
                with self.subTest(script=script, source=source):
                    self.assert_ok(self.wrapper(script))
                    self.assertEqual(self.settings.read_bytes(), before)
        self.assertNotIn(['install', SOURCE, '--no-approve'], [json.loads(line) for line in self.calls.read_text().splitlines()])

    def test_exact_legacy_duplicates_are_removed_without_touching_other_prompts(self):
        for script in SCRIPTS:
            with self.subTest(script=script):
                skill, prompts = self.legacy()
                self.assert_ok(self.wrapper(script))
                self.assertFalse(skill.exists())
                self.assertEqual(sorted(p.name for p in prompts.iterdir()), ['custom.md', 'share-unverified.md'])
                self.assertIn('SECRET-SENTINEL', (prompts / 'custom.md').read_text())
                self.assert_ok(self.wrapper(script))
                shutil.rmtree(prompts)

    def test_modified_uncertain_and_linked_legacy_resources_are_preserved_as_a_unit(self):
        self.installed()
        for condition in ('edited-skill', 'missing-skill-file', 'extra-file', 'extra-directory', 'linked-child',
                          'hardlinked-child', 'edited-prompt', 'linked-prompt', 'linked-skill'):
            with self.subTest(condition=condition):
                skill, prompts = self.legacy()
                target = skill / 'SKILL.md'
                outside = self.root / 'outside'
                outside.write_text('SECRET-SENTINEL')
                if condition == 'edited-skill': target.write_text('SECRET-SENTINEL edit')
                elif condition == 'missing-skill-file': target.unlink()
                elif condition == 'extra-file': (skill / 'custom.md').write_text('SECRET-SENTINEL')
                elif condition == 'extra-directory': (skill / 'empty-custom').mkdir()
                elif condition in ('linked-child', 'hardlinked-child'):
                    target.unlink()
                    if condition == 'linked-child': target.symlink_to(outside)
                    else: os.link(outside, target)
                elif condition == 'edited-prompt': (prompts / 'diff-review.md').write_text('SECRET-SENTINEL edit')
                elif condition == 'linked-prompt':
                    (prompts / 'diff-review.md').unlink(); (prompts / 'diff-review.md').symlink_to(outside)
                else:
                    shutil.rmtree(skill); skill.symlink_to(self.template / PAYLOAD, target_is_directory=True)
                result = self.policy('finish')
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertTrue(skill.exists())
                self.assertTrue((prompts / 'project-recap.md').exists(), 'No partial migration after a conflict')
                self.assertEqual(outside.read_text(), 'SECRET-SENTINEL')
                if skill.is_symlink(): skill.unlink()
                else: shutil.rmtree(skill)
                shutil.rmtree(prompts)

    def test_native_failure_and_zero_exit_unverified_results_fail_without_migration(self):
        for script in SCRIPTS:
            for failure in ('command', 'registration', 'dependency', 'resource', 'metadata'):
                with self.subTest(script=script, failure=failure):
                    if self.checkout.exists(): shutil.rmtree(self.agent / 'git')
                    self.settings.write_text('{}')
                    skill, prompts = self.legacy()
                    result = self.wrapper(script, overrides={'FIXTURE_FAILURE': failure})
                    self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                    self.assertNotIn('SUCCESS:', result.stdout)
                    self.assertTrue((skill / 'SKILL.md').exists())
                    self.assertTrue((prompts / 'diff-review.md').exists())
                    shutil.rmtree(skill); shutil.rmtree(prompts)

    def test_unsafe_metadata_and_duplicate_or_unsupported_sources_block_native_install(self):
        original = self.settings.read_bytes()
        for content in ('{SECRET-SENTINEL', '[]', '{"packages":{}}', '{"packages":[null]}',
                        json.dumps({'packages': [SOURCE, SOURCE + '@v0.12.0']}),
                        json.dumps({'packages': ['npm:visual-explainer@0.12.0']}),
                        json.dumps({'packages': [SOURCE + '#v0.12.0']}),
                        json.dumps({'packages': [SOURCE + '\n']})):
            self.settings.write_text(content)
            for script in SCRIPTS:
                with self.subTest(script=script, content=content):
                    result = self.wrapper(script)
                    self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                    self.assertFalse(self.calls.exists())
                    self.assertEqual(self.settings.read_text(), content)
        self.settings.unlink()
        outside = self.root / 'metadata.json'; outside.write_bytes(original)
        for kind in ('symlink', 'hardlink'):
            if kind == 'symlink': self.settings.symlink_to(outside)
            else: os.link(outside, self.settings)
            self.assertEqual(self.policy().returncode, 1)
            self.assertEqual(outside.read_bytes(), original)
            self.settings.unlink()

    def test_git_local_edits_unknown_ignored_files_and_wrong_identity_are_preserved(self):
        for condition in ('tracked', 'untracked', 'ignored', 'origin', 'linked-metadata', 'linked-lock', 'linked-modules'):
            with self.subTest(condition=condition):
                if self.checkout.exists(): shutil.rmtree(self.agent / 'git')
                self.installed()
                if condition == 'tracked': (self.checkout / PAYLOAD / 'SKILL.md').write_text('SECRET-SENTINEL edit')
                elif condition == 'untracked': (self.checkout / 'notes').write_text('SECRET-SENTINEL')
                elif condition == 'ignored': (self.checkout / 'ignored-notes').write_text('SECRET-SENTINEL')
                elif condition == 'origin': self.git('remote', 'set-url', 'origin', 'https://example.invalid/foreign')
                elif condition == 'linked-metadata':
                    metadata = self.root / 'saved-git'; (self.checkout / '.git').rename(metadata)
                    (self.checkout / '.git').symlink_to(metadata, target_is_directory=True)
                elif condition == 'linked-lock':
                    lock = self.checkout / 'package-lock.json'; lock.unlink(); lock.symlink_to(self.settings)
                else:
                    shutil.rmtree(self.checkout / 'node_modules'); (self.checkout / 'node_modules').symlink_to(self.template, target_is_directory=True)
                for script in SCRIPTS:
                    result = self.wrapper(script)
                    self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                    self.assertFalse(self.calls.exists())

    def test_generated_dependencies_are_a_narrow_refresh_exception(self):
        self.installed()
        for script in SCRIPTS:
            with self.subTest(script=script):
                self.assert_ok(self.wrapper(script, refresh=True))
                (self.checkout / 'ignored-notes').write_text('SECRET-SENTINEL custom data')
                result = self.wrapper(script, refresh=True)
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                (self.checkout / 'ignored-notes').unlink()
                lock = self.checkout / 'package-lock.json'; lock.unlink(); lock.symlink_to(self.settings)
                result = self.wrapper(script, refresh=True)
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                lock.unlink(); lock.write_text('{}')

    def test_blocked_offline_and_redirected_git_do_not_invoke_pi(self):
        for script in SCRIPTS:
            for overrides in ({'PI_PROFILE_MUTATIONS_BLOCKED': '1', 'FIXTURE_BLOCKED': '1'},
                              {'PI_OFFLINE': 'true'}, {'GIT_DIR': str(self.template / '.git')}):
                with self.subTest(script=script, overrides=overrides):
                    self.assertEqual(self.wrapper(script, overrides=overrides).returncode, 1)
                    self.assertFalse(self.calls.exists())

    def test_ordinary_group_access_is_not_normalized_and_changed_snapshots_stop_migration(self):
        self.installed()
        ordinary = (self.home, self.agent.parent, self.checkout, self.checkout.parent)
        for directory in ordinary: directory.chmod(0o2775)
        before = {file: file.stat().st_mode for file in ordinary}
        self.assert_ok(self.policy('finish'))
        self.assertEqual({file: file.stat().st_mode for file in ordinary}, before)
        skill, prompts = self.legacy()
        prelude = 'const fs=require("node:fs"),original=fs.readdirSync; fs.readdirSync=(...args)=>{const result=original(...args);fs.chmodSync(' + json.dumps(str(self.home)) + ',0o775);return result;};'
        result = self.policy('finish', prelude=prelude)
        self.assertEqual((result.returncode, result.stdout), (1, 'failed:changed-input\n'))
        self.assertTrue((skill / 'SKILL.md').exists())
        self.assertTrue((prompts / 'diff-review.md').exists())

    def test_embedding_and_caller_wiring_are_identical(self):
        result = subprocess.run(['/usr/bin/python3', '-I', str(ROOT / 'tools/embed-pi-visual-explainer.py'), '--check'],
                                env=self.env, cwd=self.root, text=True, capture_output=True, timeout=20)
        self.assert_ok(result)
        for script in SCRIPTS:
            text = (ROOT / script).read_text()
            call = 'if (-not (Setup-PiVisualExplainer))' if script.endswith('.ps1') else 'setup_pi_visual_explainer ||'
            self.assertEqual(text.count(call), 1)
            self.assertNotIn('install-pi.sh', text)
            self.assertIn(CORE.read_text().rstrip(), text)


if __name__ == '__main__':
    unittest.main(verbosity=2)
