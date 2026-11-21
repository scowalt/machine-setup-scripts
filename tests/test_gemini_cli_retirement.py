#!/usr/bin/env python3
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import tempfile
import unittest

from extract_setup_fixture import validate_function

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ('mac.sh', 'ubuntu.sh', 'wsl.sh', 'pi.sh', 'bazzite.sh')
POWERSHELL = 'win.ps1'
FUNCTION = 'retire_gemini_cli'
PACKAGE = '@google/gemini-cli'
SHIM_TARGET = '../install/global/node_modules/@google/gemini-cli/bundle/gemini.js'
TOOLS = ('grep', 'readlink', 'rm')
BUN = shutil.which('bun')

FAKE_BUN = (ROOT / 'tests/fixtures/fake-bun-global.py').read_text()
def function(script):
    source = (ROOT / script).read_text()
    start = source.index(f'\n{FUNCTION}() {{\n') + 1
    end = source.index('\n}\n', start) + 3
    block = source[start:end]
    validate_function(block)
    return block


def snapshot(base, skip=()):
    result = {}
    for path in sorted(base.rglob('*')):
        relative = path.relative_to(base)
        if relative.parts[0] in skip:
            continue
        info = path.lstat()
        kind = stat.S_IFMT(info.st_mode)
        if kind == stat.S_IFLNK:
            content = os.readlink(path)
        elif kind == stat.S_IFREG:
            content = path.read_bytes()
        else:
            content = None
        result[str(relative)] = (kind, stat.S_IMODE(info.st_mode), content)
    return result


class GeminiCliRetirement(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='gemini-retire-test-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.home = self.root / 'account'
        self.home.mkdir()
        self.capture = self.root / 'capture'
        self.toolbox = self.root / 'toolbox'
        self.toolbox.mkdir()
        for tool in TOOLS:
            (self.toolbox / tool).symlink_to(shutil.which(tool))

    def reset(self):
        shutil.rmtree(self.home)
        self.home.mkdir()
        for stale in self.root.glob('capture.*'):
            stale.unlink()

    def write(self, relative, content, mode=0o644):
        path = self.home / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content if isinstance(content, bytes) else content.encode())
        path.chmod(mode)
        return path

    def install_package(self, name, bins, version='1.0.0'):
        package_dir = self.home / '.bun/install/global/node_modules' / name
        self.write(package_dir.relative_to(self.home) / 'package.json', json.dumps({'name': name, 'version': version, 'bin': bins}))
        for link, target in bins.items():
            self.write(package_dir.relative_to(self.home) / target, '#!/usr/bin/env node\n', 0o755)
            bin_dir = self.home / '.bun/bin'
            bin_dir.mkdir(parents=True, exist_ok=True)
            (bin_dir / link).symlink_to(f'../install/global/node_modules/{name}/{target}')
        manifest = self.home / '.bun/install/global/package.json'
        dependencies = json.loads(manifest.read_text())['dependencies'] if manifest.exists() else {}
        dependencies[name] = version
        manifest.write_text(json.dumps({'dependencies': dependencies}))

    def seed_bun(self, gemini=True):
        self.write('.bun/bin/bun', FAKE_BUN, 0o755)
        self.install_package('keep-tool', {'keep': 'keep.js'})
        if gemini:
            self.install_package(PACKAGE, {'gemini': 'bundle/gemini.js'}, '0.52.0')

    def seed_protected(self):
        self.write('.gemini/antigravity-cli/state.db', b'\x00agy state\xff')
        self.write('.gemini/config/skills.json', '{"skills": []}\n')
        self.write('.gemini/AGENTS.md', '# Agents\n')
        self.write('.gemini/settings.json', '{"mcpServers": {}}\n')
        self.write('.gemini/oauth_creds.json', '{"refresh_token": "fake-secret"}\n', 0o600)
        self.write('.gemini/gemini-credentials.json', '{"token": "fake-secret"}\n', 0o600)
        self.write('.gemini/skills/pr/SKILL.md', 'pr skill\n')
        (self.home / '.gemini/empty').mkdir()
        (self.home / '.gemini/link').symlink_to('settings.json')
        self.write('.agents/skills/pr/SKILL.md', 'canonical pr skill\n')
        self.write('.local/bin/agy', '#!/bin/sh\necho 1.5.14\n', 0o755)

    def invoke(self, script, path_extra=(), **flags):
        path = ':'.join([str(self.home / '.bun/bin'), *map(str, path_extra), str(self.toolbox)])
        env = {'HOME': str(self.home), 'PATH': path, 'LC_ALL': 'C', 'TMPDIR': str(self.root),
               'TEST_CAPTURE': str(self.capture), **{key: str(value) for key, value in flags.items()}}
        code = '''
print_message() { printf 'MESSAGE: %s\\n' "$*"; }
print_debug() { printf 'DEBUG: %s\\n' "$*"; }
print_success() { printf 'SUCCESS: %s\\n' "$*"; }
print_warning() { printf 'WARNING: %s\\n' "$*" >&2; }
print_error() { printf 'ERROR: %s\\n' "$*" >&2; }
''' + function(script) + f'\n{FUNCTION}\nexit $?\n'
        return subprocess.run(['/bin/bash', '--noprofile', '--norc', '-c', code], env=env, cwd=self.root,
                              capture_output=True, text=True, timeout=30, stdin=subprocess.DEVNULL)

    def calls(self):
        log = Path(str(self.capture) + '.calls')
        return log.read_text().splitlines() if log.exists() else []

    def managed_gone(self):
        return (not (self.home / '.bun/install/global/node_modules/@google/gemini-cli').exists()
                and PACKAGE not in json.loads((self.home / '.bun/install/global/package.json').read_text())['dependencies']
                and not os.path.lexists(self.home / '.bun/bin/gemini'))

    def assert_other_global_untouched(self):
        self.assertTrue((self.home / '.bun/install/global/node_modules/keep-tool/keep.js').is_file())
        self.assertEqual(os.readlink(self.home / '.bun/bin/keep'), '../install/global/node_modules/keep-tool/keep.js')
        self.assertIn('keep-tool', json.loads((self.home / '.bun/install/global/package.json').read_text())['dependencies'])

    def each_script(self):
        for script in SCRIPTS:
            with self.subTest(script=script):
                self.reset()
                yield script

    def test_removes_the_managed_install_and_nothing_else(self):
        for script in self.each_script():
            self.seed_bun()
            self.seed_protected()
            before = snapshot(self.home, skip=('.bun',))
            result = self.invoke(script)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertTrue(self.managed_gone())
            self.assert_other_global_untouched()
            self.assertIn('SUCCESS: Gemini CLI removed.', result.stdout)
            self.assertNotIn('WARNING', result.stderr)
            self.assertIn('remove -g @google/gemini-cli', self.calls())
            self.assertEqual(set(self.calls()), {'pm ls -g', 'remove -g @google/gemini-cli', 'pm bin -g'})
            self.assertEqual(snapshot(self.home, skip=('.bun',)), before)

    def test_a_bun_found_on_path_is_used_when_there_is_no_home_bun(self):
        for script in self.each_script():
            self.seed_bun()
            relocated = self.root / 'pathbin'
            relocated.mkdir(exist_ok=True)
            shutil.move(self.home / '.bun/bin/bun', relocated / 'bun')
            result = self.invoke(script, path_extra=[relocated])
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertTrue(self.managed_gone())
            self.assertIn('SUCCESS: Gemini CLI removed.', result.stdout)

    def test_second_run_changes_nothing(self):
        for script in self.each_script():
            self.seed_bun()
            self.seed_protected()
            self.assertEqual(self.invoke(script).returncode, 0)
            for stale in self.root.glob('capture.*'):
                stale.unlink()
            before = snapshot(self.home)
            result = self.invoke(script)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertNotIn('remove', ' '.join(self.calls()))
            self.assertEqual(snapshot(self.home), before)
            self.assertIn('DEBUG: Gemini CLI was not installed by setup.', result.stdout)
            self.assertNotIn('SUCCESS', result.stdout)

    def test_without_bun_nothing_is_called_and_nothing_changes(self):
        for script in self.each_script():
            self.seed_protected()
            before = snapshot(self.home)
            result = self.invoke(script)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(self.calls(), [])
            self.assertEqual(snapshot(self.home), before)
            self.assertIn('DEBUG: Gemini CLI was not installed by setup.', result.stdout)

    def test_each_bun_failure_fails_and_leaves_gemini_state_alone(self):
        cases = {
            'listing fails': ({'TEST_LS_FAILS': 1}, 'Could not list Bun', ['pm ls -g']),
            'removal fails': ({'TEST_REMOVE_FAILS': 1}, 'remove exploded', ['pm ls -g', 'remove -g @google/gemini-cli']),
            'package still listed': ({'TEST_REMOVE_NOOP': 1}, "Could not confirm", ['pm ls -g', 'remove -g @google/gemini-cli', 'pm ls -g']),
            'listing fails after removal': ({'TEST_LS_FAILS_AFTER_REMOVE': 1}, "Could not confirm", ['pm ls -g', 'remove -g @google/gemini-cli', 'pm ls -g']),
            'bin directory unknown': ({'TEST_BIN_FAILS': 1}, 'global bin directory', ['pm ls -g', 'remove -g @google/gemini-cli', 'pm ls -g', 'pm bin -g']),
        }
        for script in SCRIPTS:
            for name, (flags, message, calls) in cases.items():
                with self.subTest(script=script, case=name):
                    self.reset()
                    self.seed_bun()
                    self.seed_protected()
                    before = snapshot(self.home, skip=('.bun',))
                    result = self.invoke(script, **flags)
                    self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                    self.assertIn(message, result.stdout + result.stderr)
                    self.assertNotIn('SUCCESS', result.stdout)
                    self.assertEqual(self.calls(), calls)
                    self.assertEqual(snapshot(self.home, skip=('.bun',)), before)

    def test_a_dangling_link_an_older_bun_left_behind_is_unlinked(self):
        for script in self.each_script():
            self.seed_bun(gemini=False)
            self.seed_protected()
            (self.home / '.bun/bin/gemini').symlink_to(SHIM_TARGET)
            before = snapshot(self.home, skip=('.bun',))
            result = self.invoke(script)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertFalse(os.path.lexists(self.home / '.bun/bin/gemini'))
            self.assert_other_global_untouched()
            self.assertIn('SUCCESS: Gemini CLI removed.', result.stdout)
            self.assertNotIn('remove -g', ' '.join(self.calls()))
            self.assertEqual(snapshot(self.home, skip=('.bun',)), before)

    def test_a_link_left_by_removal_is_unlinked(self):
        for script in self.each_script():
            self.seed_bun()
            result = self.invoke(script, TEST_LEAVE_LINK=1)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertTrue(self.managed_gone())
            self.assertIn('SUCCESS: Gemini CLI removed.', result.stdout)

    def test_unrelated_gemini_in_the_bun_bin_directory_is_preserved_and_reported(self):
        outside = self.root / 'outside-target'
        outside.write_text('#!/bin/sh\necho other gemini\n')
        outside.chmod(0o755)
        cases = {
            'regular file': lambda link: link.write_bytes(b'#!/bin/sh\necho hand-installed\n') or link.chmod(0o755),
            'live link elsewhere': lambda link: link.symlink_to(outside),
            'dangling link elsewhere': lambda link: link.symlink_to('../../somewhere/gone'),
        }
        for script in SCRIPTS:
            for name, make in cases.items():
                with self.subTest(script=script, case=name):
                    self.reset()
                    self.seed_bun(gemini=False)
                    link = self.home / '.bun/bin/gemini'
                    make(link)
                    before = snapshot(self.home)
                    result = self.invoke(script)
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertEqual(snapshot(self.home), before)
                    if name != 'dangling link elsewhere':
                        self.assertIn(f'WARNING: Preserving a Gemini CLI that setup did not install: {link}.', result.stderr)

    def test_a_foreign_gemini_elsewhere_on_path_is_preserved_with_its_path(self):
        for script in SCRIPTS:
            for managed in (True, False):
                with self.subTest(script=script, managed=managed):
                    self.reset()
                    self.seed_bun(gemini=managed)
                    foreign = self.write('other/bin/gemini', '#!/bin/sh\necho foreign\n', 0o755)
                    before = foreign.read_bytes()
                    result = self.invoke(script, path_extra=[foreign.parent])
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertEqual(foreign.read_bytes(), before)
                    self.assertEqual(stat.S_IMODE(foreign.stat().st_mode), 0o755)
                    self.assertIn(f'WARNING: Preserving a Gemini CLI that setup did not install: {foreign}.', result.stderr)
                    self.assertEqual('SUCCESS: Gemini CLI removed.' in result.stdout, managed)
                    self.assertFalse(os.path.lexists(self.home / '.bun/bin/gemini'))

    def test_function_is_identical_and_called_once_right_before_agy(self):
        blocks = {script: function(script) for script in SCRIPTS}
        self.assertEqual(len(set(blocks.values())), 1)
        for script in SCRIPTS:
            with self.subTest(script=script):
                lines = (ROOT / script).read_text().splitlines()
                callers = [i for i, line in enumerate(lines) if re.fullmatch(r'\s*retire_gemini_cli\b.*', line)
                           and not line.startswith(f'{FUNCTION}()')]
                self.assertEqual(len(callers), 1)
                self.assertEqual(lines[callers[0]], '    retire_gemini_cli || _setup_had_errors=1')
                self.assertEqual(lines[callers[0] + 1], '    install_agy_cli || _setup_had_errors=1')

    def test_nothing_installs_gemini_cli_any_more(self):
        for script in (*SCRIPTS, POWERSHELL):
            with self.subTest(script=script):
                source = (ROOT / script).read_text()
                for needle in ('install_gemini_cli', 'Install-GeminiCli', 'install -g @google/gemini-cli',
                               'bun add -g @google/gemini-cli', 'add -g @google/gemini-cli'):
                    self.assertNotIn(needle, source)

    @unittest.skipUnless(BUN, 'Existing native Bun required; no runtime download')
    def test_real_bun_removes_its_own_install_and_keeps_the_rest(self):
        for script in SCRIPTS:
            with self.subTest(script=script):
                self.reset()
                bun = self.home / '.bun/bin/bun'
                bun.parent.mkdir(parents=True)
                shutil.copy2(Path(BUN).resolve(), bun)
                bun.chmod(0o775)
                packages = self.root / 'packages'
                shutil.rmtree(packages, ignore_errors=True)
                for name, binary, relative in ((PACKAGE, 'gemini', 'bundle/gemini.js'), ('keep-tool', 'keep', 'keep.js')):
                    folder = packages / name.replace('/', '-').lstrip('@')
                    (folder / relative).parent.mkdir(parents=True)
                    (folder / 'package.json').write_text(json.dumps({'name': name, 'version': '1.0.0', 'bin': {binary: relative}}))
                    (folder / relative).write_text('#!/usr/bin/env node\n')
                    (folder / relative).chmod(0o755)
                env = {'HOME': str(self.home), 'PATH': '/usr/bin:/bin', 'LC_ALL': 'C', 'TMPDIR': str(self.root)}
                added = subprocess.run([str(bun), 'add', '-g', str(packages / 'google-gemini-cli'), str(packages / 'keep-tool')],
                                       env=env, cwd=self.root, capture_output=True, text=True, timeout=60, stdin=subprocess.DEVNULL)
                self.assertEqual(added.returncode, 0, added.stdout + added.stderr)
                self.assertTrue(os.path.lexists(self.home / '.bun/bin/gemini'))
                self.seed_protected()
                before = snapshot(self.home, skip=('.bun',))
                result = self.invoke(script)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn('SUCCESS: Gemini CLI removed.', result.stdout)
                self.assertNotIn('WARNING', result.stderr)
                self.assertFalse(os.path.lexists(self.home / '.bun/bin/gemini'))
                self.assertFalse(os.path.lexists(self.home / '.bun/install/global/node_modules/@google/gemini-cli'))
                self.assertNotIn(PACKAGE, (self.home / '.bun/install/global/package.json').read_text())
                self.assertTrue(os.path.lexists(self.home / '.bun/bin/keep'))
                self.assertTrue((self.home / '.bun/install/global/node_modules/keep-tool/keep.js').exists())
                self.assertEqual(snapshot(self.home, skip=('.bun',)), before)
                listing = subprocess.run([str(bun), 'pm', 'ls', '-g'], env=env, cwd=self.root, capture_output=True,
                                         text=True, timeout=30, stdin=subprocess.DEVNULL)
                self.assertNotIn(PACKAGE, listing.stdout)
                self.assertIn('keep-tool', listing.stdout)


if __name__ == '__main__':
    unittest.main()
