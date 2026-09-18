"""Native shared-runtime repair -> staged skills, using temporary homes and inert skills."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

from test_shared_node_runtime import extract, executable, SCRIPTS, NODE, MISE, FISH
from test_managed_skill_suite import functions, ROOT, KNOWN

DOTFILES = os.environ.get('PI_RUNTIME_DOTFILES_SOURCE')
CHEZMOI = shutil.which('chezmoi')


@unittest.skipUnless(DOTFILES and CHEZMOI and MISE and FISH and NODE,
                     'Set PI_RUNTIME_DOTFILES_SOURCE; requires chezmoi, mise, fish and Node')
class SharedNodeConvergence(unittest.TestCase):
    def test_real_setup_repairs_legacy_activation_and_installs_ask_matt_on_reruns(self):
        real_node = Path(NODE).resolve()
        version = subprocess.check_output([NODE, '-p', 'process.versions.node'], text=True).strip()
        if tuple(map(int, version.split('.')[:2])) < (22, 20):
            self.skipTest('Node >=22.20 required for native fixtures')
        template = (Path(DOTFILES) / 'dot_config/private_fish/config.fish.tmpl').read_text()
        for script in SCRIPTS:
            with self.subTest(script=script), tempfile.TemporaryDirectory(prefix='node-convergence-') as tmp:
                root = Path(tmp)
                home = root / 'home with spaces'
                home.mkdir()
                (home / '.test-owned').touch()
                config = home / '.config/mise/config.toml'
                config.parent.mkdir(parents=True)
                config.write_text(f'# Keep the global selection and other idiomatic tools.\n[tools]\nnode = "{version}"\n'
                                  '[settings]\nidiomatic_version_file_enable_tools = ["python"]\n')
                data = home / 'mise-data'
                install = data / 'installs/node' / version
                install.parent.mkdir(parents=True)
                install.symlink_to(real_node.parent.parent, target_is_directory=True)
                local = home / '.local/bin'
                local.mkdir(parents=True)
                (local / 'mise').symlink_to(MISE)
                legacy = home / 'legacy/bin'
                legacy.mkdir(parents=True)
                shutil.copy2(real_node, legacy / 'node')
                executable(legacy / 'npm', '#!/bin/sh\necho wrong-npm\n')
                fish = home / '.config/fish'
                (fish / 'conf.d').mkdir(parents=True)
                (fish / 'conf.d/vendor-mise.fish').write_text(
                    'set -gx PATH "$HOME/.local/bin" $PATH\nmise activate fish | source\n')
                stale = ('set -gx PATH "$HOME/legacy/bin" $PATH\n'
                         'mise activate fish | source\n')
                (fish / 'config.fish').write_text(stale)
                source = root / 'source'
                target = source / 'dot_config/private_fish/config.fish.tmpl'
                target.parent.mkdir(parents=True)
                # Native Homebrew remains outside the fixture. Relocate only its
                # hard-coded system prefix to an inert shellenv fixture.
                fixture_template = template
                for prefix in ('/opt/homebrew', '/home/linuxbrew/.linuxbrew'):
                    fixture_template = fixture_template.replace(prefix, str(root / 'fixture-brew'))
                target.write_text(fixture_template)
                executable(root / 'fixture-brew/bin/brew', '#!/bin/sh\n'
                           'printf \'set -gx PATH "$HOME/legacy/bin" $PATH\\n\'\n')
                unrelated = source / '.chezmoiscripts/run_before_unrelated.sh'
                unrelated.parent.mkdir()
                unrelated.write_text('#!/bin/sh\ntouch "$HOME/unrelated-script-ran"\n')
                (source / 'dot_unrelated').write_text('must not apply')
                chez_config = root / 'chezmoi.json'
                chez_config.write_text('{}')
                chez_args = [CHEZMOI, '--config', str(chez_config), '--source', str(source),
                             '--destination', str(home), '--cache', str(root / 'chez-cache'),
                             '--persistent-state', str(root / 'state.boltdb'), '--override-data',
                             json.dumps({'chezmoi': {'os': 'darwin' if script == 'mac.sh' else 'linux'}})]
                executable(local / 'chezmoi', f'#!{sys.executable}\n' +
                           'import json, pathlib, subprocess, sys\n' +
                           f'home=pathlib.Path({str(home)!r})\n' +
                           "assert sys.argv[1:]==['apply','--force','--include=files',str(home/'.config/fish/config.fish')]\n" +
                           "with (home/'repair-calls').open('a') as f: f.write('apply\\n')\n" +
                           f'sys.exit(subprocess.call({chez_args!r}+sys.argv[1:]))\n')
                env = {
                    'HOME': str(home), 'USERPROFILE': str(home), 'PATH': f'{local}:/usr/bin:/bin',
                    'XDG_CONFIG_HOME': str(home / '.config'), 'XDG_CACHE_HOME': str(home / '.cache'),
                    'XDG_DATA_HOME': str(home / '.local/share'), 'XDG_STATE_HOME': str(home / '.state'),
                    'MISE_DATA_DIR': str(data), 'MISE_CACHE_DIR': str(home / 'mise-cache'),
                    'MISE_STATE_DIR': str(home / 'mise-state'), 'MISE_OFFLINE': 'true',
                    'MISE_AUTO_INSTALL': 'false', 'MISE_NODE_COMPILE': 'false',
                    'MISE_TRUSTED_CONFIG_PATHS': str(home), 'TERM': 'dumb', 'TMPDIR': str(root),
                    'SKILL_TEST_HOME': str(home), 'SKILL_TEST_CALLS': str(home / 'skill-calls'),
                    'SKILL_TEST_STAGES': str(home / 'stages'), 'SKILL_TEST_PYTHON': sys.executable,
                    'SKILL_TEST_MOCK': str(ROOT / 'tests/mock_managed_skills.py'),
                }
                body = extract(script) + '\n' + functions(script) + r'''
print_debug() { :; }
print_message() { :; }
print_success() { :; }
print_warning() { printf '%s\n' "$*" >&2; }
PI_PROFILE_MUTATIONS_BLOCKED=0
npm() {
    if [[ "$1" == config ]]; then printf '%s/%s.npmrc\n' "$HOME" "$3"; else command npm "$@"; fi
}
npx() { "$SKILL_TEST_PYTHON" "$SKILL_TEST_MOCK" "$@"; }
'''
                def run(command):
                    return subprocess.run(['/bin/bash', '-c', body + '\n' + command], cwd=home,
                                          env=env, text=True, capture_output=True, timeout=30)
                # The production verifier must catch the exact legacy-binary symptom first.
                self.assertNotEqual(run('verify_shared_node_shell').returncode, 0)
                for _ in range(2):
                    result = run('setup_matt_pocock_skills')
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    for base in (home / '.agents/skills', home / '.claude/skills'):
                        for name in KNOWN:
                            self.assertGreater((base / name / 'SKILL.md').stat().st_size, 0)
                        self.assertIn('name: ask-matt', (base / 'ask-matt/SKILL.md').read_text())
                    self.assertEqual(run('verify_shared_node_shell').returncode, 0)
                self.assertEqual((home / 'repair-calls').read_text(), 'apply\n')
                other = data / 'installs/node/18.19.1/bin/node'
                executable(other, '#!/bin/sh\nif [ "$1" = --version ]; then echo v18.19.1; else exit 1; fi\n')
                for filename in ('.node-version', '.nvmrc'):
                    project = home / ('project' + filename)
                    project.mkdir()
                    pin = project / filename
                    pin.write_text('18.19.1\n')
                    selected = subprocess.run([FISH, '-lc', 'command -s node'], cwd=project,
                                              env=env, text=True, capture_output=True, timeout=20)
                    self.assertEqual(selected.stdout.strip(), str(other), selected.stderr)
                    changed = subprocess.run([FISH, '-lc', 'cd "$argv[1]"; command -s node', str(project)],
                                             cwd=home, env=env, text=True, capture_output=True, timeout=20)
                    self.assertEqual(changed.stdout.strip(), str(other), changed.stderr)
                    self.assertEqual(pin.read_text(), '18.19.1\n')
                # Native mise precedence remains authoritative: a HOME .mise.toml
                # overrides global tools, unlike idiomatic files directly at HOME.
                home_pin = home / '.mise.toml'
                home_pin.write_text('[tools]\nnode = "18.19.1"\n')
                before_calls = (home / 'skill-calls').read_bytes()
                result = run('setup_matt_pocock_skills')
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(home_pin.read_text(), '[tools]\nnode = "18.19.1"\n')
                self.assertEqual((home / 'skill-calls').read_bytes(), before_calls)
                home_pin.unlink()
                self.assertIn(f'node = "{version}"', config.read_text())
                self.assertIn('idiomatic_version_file_enable_tools = ["python", "node"]', config.read_text())
                self.assertIn('activate_aggressive = true', config.read_text())
                self.assertFalse((home / 'unrelated-script-ran').exists())
                self.assertFalse((home / '.unrelated').exists())
                self.assertTrue((legacy / 'node').is_file())
                for stage in (home / 'stages').read_text().splitlines():
                    self.assertFalse(os.path.lexists(stage))
                # Preserve an explicit conflicting override, but never accept a
                # cold-shell success that would regress on the next directory hook.
                calls = (home / 'skill-calls').read_bytes()
                for key, value in (('MISE_ACTIVATE_AGGRESSIVE', 'false'),
                                   ('MISE_IDIOMATIC_VERSION_FILE_ENABLE_TOOLS', 'python')):
                    env[key] = value
                    result = run('setup_matt_pocock_skills')
                    self.assertNotEqual(result.returncode, 0, 'Conflicting effective policy accepted: ' + key)
                    self.assertEqual((home / 'skill-calls').read_bytes(), calls)
                    self.assertEqual(env[key], value)
                    del env[key]
                # A stale source cannot turn a successful chezmoi exit into fake runtime readiness.
                target.write_text(stale)
                (fish / 'config.fish').write_text(stale)
                calls = (home / 'skill-calls').read_bytes()
                result = run('setup_matt_pocock_skills')
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('repair failed verification', result.stderr)
                self.assertEqual((home / 'skill-calls').read_bytes(), calls)
                # Legacy activation may coincidentally select mise correctly on a
                # clean startup. That is not evidence the durable migration ran.
                (fish / 'conf.d/vendor-mise.fish').unlink()
                healthy_legacy = ('set -gx PATH "$HOME/.local/bin" "$HOME/legacy/bin" $PATH\n'
                                  'mise activate fish | source\n')
                target.write_text(healthy_legacy)
                (fish / 'config.fish').write_text(healthy_legacy)
                env['__setup_shared_node_activation'] = '1'  # Cannot inherit evidence of this shell's migration.
                result = run('setup_matt_pocock_skills')
                self.assertNotEqual(result.returncode, 0, 'Healthy but unmigrated activation was accepted')
                self.assertIn('repair failed verification', result.stderr)
                self.assertEqual((home / 'skill-calls').read_bytes(), calls)


if __name__ == '__main__':
    unittest.main()
