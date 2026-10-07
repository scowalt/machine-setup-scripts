import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

from extract_setup_fixture import definitions
import test_impeccable_convergence as convergence

ROOT = Path(__file__).resolve().parents[1]


class CompletionDirectories(unittest.TestCase):
    def test_real_macos_caller_preserves_completion_directory_group_access(self):
        source = definitions((ROOT / 'mac.sh').read_text())
        cases = [(mode, '') for mode in (0o700, 0o755, 0o775, 0o2775, 0o777, 0o2777)]
        cases += [(0o775, name) for name in ('root-owner', 'foreign-owner', 'stat-failure', 'chmod-failure', 'prior-failure', 'link')]
        for mode, scenario in cases:
            with self.subTest(mode=oct(mode), scenario=scenario), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                paths = []
                for name in ('apple/zsh', 'apple/zsh-completions', 'intel/zsh', 'audited completion'):
                    directory = root / name
                    directory.mkdir(parents=True)
                    directory.chmod(mode)
                    paths.append(directory)
                    child = directory / 'nested'
                    child.mkdir(mode=0o700)
                    child.chmod(mode)
                    paths.append(child)
                expected = {p: (p.stat().st_uid, p.stat().st_gid, p.stat().st_mode & ~0o002) for p in paths}
                audited = root / 'audited completion'
                nested = audited / 'nested'
                expected[nested] = (nested.stat().st_uid, nested.stat().st_gid, nested.stat().st_mode)
                if scenario in ('root-owner', 'foreign-owner'):
                    uid, gid, bits = expected[audited]
                    expected[audited] = (uid, gid, bits & ~0o020)
                if scenario == 'link':
                    (audited / 'nested').rmdir()
                    paths.remove(audited / 'nested')
                    expected.pop(audited / 'nested')
                    audited.rmdir()
                    audited.symlink_to(root / 'apple/zsh', target_is_directory=True)
                files = []
                for directory in paths[:3]:
                    file = directory / '_fixture'
                    file.write_text('inert completion')
                    file.chmod(0o664)
                    files.append(file)
                fixture = source
                for logical, physical in zip(('/opt/homebrew/share/zsh-completions', '/opt/homebrew/share/zsh', '/usr/local/share/zsh'),
                                             (root / 'apple/zsh-completions', root / 'apple/zsh', root / 'intel/zsh')):
                    fixture = fixture.replace(logical, str(physical))
                retained = {'fix_zsh_compaudit', 'main', 'run_setup_tasks'}
                names = set(re.findall(r'^(\w+)\(\)', fixture, re.M))
                mocks = '\n'.join(f'{name}() {{ :; }}' for name in names - retained)
                tools = root / 'tools'
                tools.mkdir()
                stat = tools / 'stat'
                stat.write_text('#!/usr/bin/python3\n' + r'''
import os, sys
p = sys.argv[-1]
s = os.lstat(p)
fmt = sys.argv[2]
scenario = os.environ.get('TRUST_SCENARIO')
owner = s.st_uid
if p.endswith('/audited completion'):
    if scenario == 'root-owner': owner = 0
    if scenario == 'foreign-owner': owner = 1234567
if scenario == 'stat-failure' and fmt != '%Su': sys.exit(1)
values = {'%Su': 'fixture', '%u': str(owner), '%Lp': format(s.st_mode & 0o7777, 'o')}
for key, value in values.items():
    fmt = fmt.replace(key, value)
print(fmt)
''')
                stat.chmod(0o700)
                fixture += '\n' + mocks + r'''
whoami() { printf 'fixture\n'; }
check_dotfiles_access() { return 1; }
setup_dotfiles_deploy_key() { return 1; }
can_sudo() { return 1; }
print_warning() { printf '%s\n' "$*"; }
zsh() {
    case "$*" in
        *xargs*) chmod go-w "$HOME/audited completion" ;;
        *) printf '%s\n' "$HOME/audited completion" ;;
    esac
}
chmod() {
    printf 'chmod:%s\n' "$*" >> "$HOME/events"
    [[ "${TRUST_SCENARIO:-}" != chmod-failure ]] || return 1
    case "${!#}" in "$HOME"/*) /bin/chmod "$@" ;; *) return 99 ;; esac
}
chown() { printf 'FORBIDDEN:chown\n' >> "$HOME/events"; return 99; }
sudo() { printf 'FORBIDDEN:sudo\n' >> "$HOME/events"; return 99; }
start_setup_log() { :; }
install_core_packages() { [[ "${TRUST_SCENARIO:-}" != prior-failure ]]; }
check_pending_reboot() { printf 'reboot\n' >> "$HOME/events"; }
finish_setup_log() { printf 'final:%s\n' "$1" >> "$HOME/events"; return "$1"; }
main
'''
                script = root / 'fixture.sh'
                script.write_text(fixture)
                result = subprocess.run(['/bin/bash', str(script)], cwd=root,
                                        env=dict(os.environ, HOME=tmp, PATH=str(tools) + ':/usr/bin:/bin', TRUST_SCENARIO=scenario),
                                        capture_output=True, text=True, timeout=20)
                status = int(scenario in ('stat-failure', 'chmod-failure', 'prior-failure'))
                self.assertEqual(result.returncode, status, result.stdout + result.stderr)
                self.assertEqual({p: (p.stat().st_uid, p.stat().st_gid, p.stat().st_mode) for p in paths}, expected)
                file_mask = 0o020 if scenario in ('stat-failure', 'chmod-failure') else 0
                self.assertTrue(all(p.stat().st_mode & 0o022 == file_mask for p in files))
                events = (root / 'events').read_text().splitlines()
                self.assertFalse(any('FORBIDDEN:' in e for e in events), events)
                self.assertEqual(events[-2:], ['reboot', 'final:' + str(status)])
                if mode & 0o020 and not mode & 0o002 and scenario not in ('root-owner', 'foreign-owner'):
                    self.assertFalse(any(str(p) == e.partition(' ')[2] for e in events if e.startswith('chmod:') for p in paths))


class CombinedOrdinaryCaller(unittest.TestCase):
    setUp = convergence.ImpeccableConvergence.setUp
    tearDown = convergence.ImpeccableConvergence.tearDown
    put = convergence.ImpeccableConvergence.put
    adapter = convergence.ImpeccableConvergence.adapter
    captured_directories = convergence.ImpeccableConvergence.captured_directories

    def test_real_retirement_private_profiles_and_impeccable_share_ordinary_ancestors(self):
        for entry in ('ubuntu.sh', 'mac.sh'):
            for scenario in ('success', 'backlog-file-failure', 'installer-failure'):
                with self.subTest(entry=entry, scenario=scenario):
                    paths = self.captured_directories()
                    self.home.chmod(0o2775)
                    selected_parent = self.home / 'selected'
                    selected = selected_parent / 'pi'
                    selected.mkdir(parents=True, exist_ok=True)
                    selected.chmod(0o700)
                    selected_parent.chmod(0o2775)
                    self.env['PI_CODING_AGENT_DIR'] = str(selected)
                    paths.extend((selected_parent, selected))
                    for profile in (self.home / '.pi/agent', selected):
                        self.put(profile / 'settings.json', json.dumps({'theme': 'keep', 'packages': ['npm:pi-prose', 'npm:keep']}))
                        self.put(profile / 'auth.json', 'inert credential sentinel')
                        self.put(profile / 'prose/custom.md', 'preserve custom style')
                        self.put(profile / 'npm/package.json', '{"dependencies":{"pi-prose":"1","keep":"1"}}')
                        (profile / 'npm').chmod(0o2775)
                        paths.append(profile / 'npm')
                    registration = self.put(self.home / '.claude.json', '{"mcpServers":{"backlog":{"command":"backlog","args":["mcp","start"]},"keep":{"command":"keep"}}}')
                    registration.chmod(0o664 if scenario == 'backlog-file-failure' else 0o600)
                    self.env['IMPECCABLE_TEST_MODE'] = 'failed-command' if scenario == 'installer-failure' else ''
                    self.put(self.root / 'events', '')
                    before = convergence.directory_metadata(paths)
                    result = self.adapter(entry=entry, combined=True, success=scenario == 'success')
                    if scenario == 'backlog-file-failure':
                        self.assertIn('backlog', json.loads(registration.read_text())['mcpServers'])
                    else:
                        self.assertEqual(json.loads(registration.read_text())['mcpServers'], {'keep': {'command': 'keep'}})
                    for profile in (self.home / '.pi/agent', selected):
                        self.assertEqual(json.loads((profile / 'settings.json').read_text())['packages'], ['npm:keep'])
                        self.assertEqual(json.loads((profile / 'npm/package.json').read_text())['dependencies'], {'keep': '1'})
                        self.assertEqual((profile / 'auth.json').read_text(), 'inert credential sentinel')
                        self.assertEqual((profile / 'prose/custom.md').read_text(), 'preserve custom style')
                    if scenario != 'installer-failure':
                        self.assertIn('verified', result.stdout)
                        self.assertTrue((selected / 'skills/impeccable/SKILL.md').is_file())
                    else:
                        self.assertIn('installer-failed', result.stdout + result.stderr)
                    self.assertEqual(convergence.directory_metadata(paths), before)
                    events = (self.root / 'events').read_text().splitlines()
                    self.assertIn('independent', events)
                    self.assertEqual(events[-2:], ['reboot', 'final:' + str(int(scenario != 'success'))])
                    self.assertFalse(any(event.startswith('FORBIDDEN:') for event in events), events)


if __name__ == '__main__':
    unittest.main(verbosity=2)
