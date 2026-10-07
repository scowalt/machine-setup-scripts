import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

from functools import lru_cache
from extract_setup_fixture import definitions

fixture_definitions = lru_cache(maxsize=5)(definitions)

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ('mac.sh', 'ubuntu.sh', 'wsl.sh', 'pi.sh', 'bazzite.sh')


def program():
    return (ROOT / 'mac.sh').read_text().split('// BEGIN BACKLOG_MCP_RETIREMENT\n', 1)[1].split('\n// END BACKLOG_MCP_RETIREMENT', 1)[0]


class BacklogDirectoryTrust(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='backlog-directory-')
        self.root = Path(self.tmp.name)
        self.home = self.root / 'home'
        self.home.mkdir()
        self.env = {**os.environ, 'HOME': str(self.home), 'BACKLOG_TEST_ROOT': str(self.root)}
        for name in ('NODE_OPTIONS', 'NODE_PATH', 'PI_CODING_AGENT_DIR', 'CLAUDE_CONFIG_DIR', 'CODEX_HOME', 'GEMINI_CLI_HOME'):
            self.env.pop(name, None)
        self.text = '{"mcpServers":{"backlog":{},"keep":{}},"custom":"keep"}\n'
        self.files = []
        for name in ('.config/mcp/mcp.json', '.agents/mcp.json', '.claude/mcp.json', '.cursor/mcp.json',
                     '.gemini/settings.json', '.pi/agent/mcp.json', 'profiles/claude/mcp.json',
                     'profiles/pi/mcp.json', 'profiles/gemini/settings.json'):
            file = self.home / name
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_text(self.text)
            self.files.append(file)
        self.codex = self.home / 'profiles/codex/config.toml'
        self.codex.parent.mkdir(parents=True)
        self.codex.write_text('[mcp_servers.backlog]\ncommand="backlog"\n[other]\nkeep=true\n')
        self.env.update(CLAUDE_CONFIG_DIR=str(self.home / 'profiles/claude'), CODEX_HOME=str(self.codex.parent),
                        PI_CODING_AGENT_DIR=str(self.home / 'profiles/pi'), GEMINI_CLI_HOME=str(self.home / 'profiles/gemini'))
        self.sentinel = self.home / 'project/.mcp.json'
        self.sentinel.parent.mkdir()
        self.sentinel.write_text(self.text)

    def tearDown(self):
        self.tmp.cleanup()

    def directories(self, mode):
        private = {self.home / '.pi/agent', self.home / 'profiles/pi'}
        dirs = [self.home] + [p for p in self.home.rglob('*') if p.is_dir()]
        for directory in dirs:
            directory.chmod(0o700 if directory in private else mode)
        return {p: (p.stat().st_uid, p.stat().st_gid, p.stat().st_mode, p.stat().st_ino) for p in dirs}

    def assert_directories(self, before):
        self.assertEqual({p: (p.stat().st_uid, p.stat().st_gid, p.stat().st_mode, p.stat().st_ino) for p in before}, before)

    def helper(self, success=True, prelude=''):
        proc = subprocess.run(['node', '--input-type=commonjs', '-', str(self.home),
                               self.env['PI_CODING_AGENT_DIR'], self.env['CLAUDE_CONFIG_DIR'],
                               self.env['CODEX_HOME'], self.env['GEMINI_CLI_HOME']],
                              input=prelude + program(), env=self.env, capture_output=True, text=True, timeout=30)
        self.assertEqual(proc.returncode == 0, success, proc.stdout + proc.stderr)
        return proc

    def assert_removed(self):
        for file in self.files:
            self.assertEqual(json.loads(file.read_text()), {'mcpServers': {'keep': {}}, 'custom': 'keep'})
        self.assertEqual(self.codex.read_text(), '[other]\nkeep=true\n')
        self.assertEqual(self.sentinel.read_text(), self.text)

    def caller(self, script, success=True, earlier=False):
        extracted = fixture_definitions((ROOT / script).read_text())
        retained = {'main', 'run_setup_tasks', 'retire_global_backlog_mcp', 'setup_load_environment',
                    'setup_environment_failure', 'setup_trim', 'setup_environment_value', 'fail_unsupported_headless',
                    'env_local_flag_is_one'}
        names = set(re.findall(r'^(\w+)\(\)', extracted, re.M))
        mocks = '\n'.join(f'{name}() {{ :; }}' for name in names - retained) + r'''
record() { printf '%s\n' "$1" >> "$BACKLOG_TEST_ROOT/events"; }
whoami() { printf 'fixture\n'; }
brew() { :; }
is_main_user() { return 0; }
check_dotfiles_access() { return 1; }
setup_dotfiles_deploy_key() { return 1; }
bb_server_selection() { return 1; }
install_bb_desktop() { [[ "${BACKLOG_TEST_EARLIER:-0}" != 1 ]]; }
remove_compound_engineering_resources() { record independent; }
check_pending_reboot() { record reboot; }
start_setup_log() { record log-start; }
finish_setup_log() { record "final:$1"; return "$1"; }
print_success() { printf '%s\n' "$1"; }
print_error() { printf '%s\n' "$1" >&2; }
'''
        for name in ('curl', 'npm', 'npx', 'pi', 'bb', 'chezmoi', 'sudo', 'systemctl', 'launchctl', 'kill', 'pkill', 'tmux', 'getent', 'id', 'getfacl', 'ps'):
            mocks += f'\n{name}() {{ record FORBIDDEN:{name}; return 99; }}'
        fixture = self.root / 'caller.sh'
        fixture.write_text('set -e\n' + extracted + '\n' + mocks + '\nmain\n')
        (self.root / 'events').write_text('')
        proc = subprocess.run(['/bin/bash', '--noprofile', '--norc', str(fixture)],
                              env={**self.env, 'BACKLOG_TEST_EARLIER': str(int(earlier))}, capture_output=True, text=True, timeout=60)
        events = (self.root / 'events').read_text().splitlines()
        self.assertEqual(proc.returncode == 0, success, script + ': ' + proc.stdout + proc.stderr)
        self.assertEqual(events[-1], 'final:' + str(int(not success)))
        self.assertIn('independent', events)
        self.assertIn('reboot', events)
        self.assertFalse(any(e.startswith('FORBIDDEN:') for e in events), events)
        return proc

    def test_real_callers_retire_and_repeat_with_group_writable_home_ancestors_and_selected_profiles(self):
        before = self.directories(0o2775)
        for script in SCRIPTS:
            with self.subTest(script=script):
                for file in self.files:
                    file.write_text(self.text)
                self.caller(script)
                self.assert_removed()
                self.caller(script)
                self.assert_directories(before)

    def test_permission_controls_preserve_original_directory_and_file_metadata(self):
        for mode in (0o700, 0o755, 0o770, 0o775, 0o2775):
            with self.subTest(mode=oct(mode)):
                before = self.directories(mode)
                for file in self.files:
                    file.write_text(self.text)
                files_before = {p: (p.stat().st_uid, p.stat().st_gid, p.stat().st_mode, p.stat().st_ino) for p in self.files}
                self.helper()
                self.assert_removed()
                self.assert_directories(before)
                self.assertEqual({p: (p.stat().st_uid, p.stat().st_gid, p.stat().st_mode, p.stat().st_ino) for p in self.files}, files_before)

    def test_managed_toml_parser_prefixes_accept_directories_but_not_group_writable_executables(self):
        for prefix in ('.pyenv/versions/3.12.77', '.local/share/mise/installs/python/3.12.77'):
            with self.subTest(prefix=prefix):
                runtime = self.home / prefix / 'bin/python3'
                runtime.parent.mkdir(parents=True)
                shutil.copy2('/usr/bin/python3', runtime)
                for file in self.files:
                    file.write_text(self.text)
                self.codex.write_text('[mcp_servers.backlog]\ncommand="backlog"\n[other]\nkeep=true\n')
                before = self.directories(0o2775)
                prelude = f'''const testFs=require('node:fs'), originalStat=testFs.lstatSync;
const testCp=require('node:child_process'), originalSpawn=testCp.spawnSync;
testFs.lstatSync=(file,...args)=>{{if(['/usr/bin/python3','/opt/homebrew/bin/python3','/usr/local/bin/python3'].includes(file)) {{const e=new Error();e.code='ENOENT';throw e;}} return originalStat(file,...args);}};
testCp.spawnSync=(command,args,options)=>{{if(command!=={json.dumps(str(runtime))} || !args.includes('-I') || !args.includes('-S')) throw new Error('forbidden external operation'); return originalSpawn(command,args,options);}};
'''
                self.helper(prelude=prelude)
                self.assert_removed()
                self.assert_directories(before)
                runtime.chmod(0o775)
                self.codex.write_text('[mcp_servers.backlog]\ncommand="backlog"\n')
                self.assertEqual(self.helper(False, prelude).stdout.strip(), 'toml-parser-unavailable')
                self.assertIn('[mcp_servers.backlog]', self.codex.read_text())
                runtime.unlink()
                self.codex.write_text('[other]\nkeep=true\n')

    def test_downstream_metadata_and_prior_failures_remain_incomplete(self):
        self.directories(0o775)
        self.caller('mac.sh', success=False, earlier=True)
        self.assert_removed()
        self.files[0].write_text(self.text)
        self.files[0].chmod(0o660)
        self.caller('ubuntu.sh', success=False)
        self.assertEqual(self.files[0].read_text(), self.text)

    def test_world_write_foreign_and_root_owned_group_write_remain_refusals(self):
        self.directories(0o775)
        boundary = self.home / '.config'
        boundary.chmod(0o777)
        self.assertEqual(self.helper(False).stdout.strip(), 'unsafe-boundary')
        boundary.chmod(0o775)
        for uid in (0, os.getuid() + 12345):
            prelude = f'''const testFs=require('node:fs'), originalStat=testFs.lstatSync;
testFs.lstatSync=(file,...args)=>{{const s=originalStat(file,...args); if(file==={json.dumps(str(boundary))}) s.uid={uid}; return s;}};
'''
            self.assertEqual(self.helper(False, prelude).stdout.strip(), 'unsafe-boundary')
        self.assertTrue(all(file.read_text() == self.text for file in self.files))

    def test_linked_ancestor_wrong_type_and_failed_inspection_still_preserve_metadata(self):
        self.directories(0o775)
        directory = self.home / '.config'
        target = self.root / 'link-target'
        directory.rename(target)
        directory.symlink_to(target, target_is_directory=True)
        self.assertEqual(self.helper(False).stdout.strip(), 'unsafe-path')
        self.assertTrue(all(file.read_text() == self.text for file in self.files))
        directory.unlink()
        target.rename(directory)
        first = self.files[0]
        first.unlink()
        first.mkdir()
        self.assertEqual(self.helper(False).stdout.strip(), 'unsafe-metadata')
        first.rmdir()
        first.write_text(self.text)
        prelude = f'''const testFs=require('node:fs'), originalStat=testFs.lstatSync;
testFs.lstatSync=(file,...args)=>{{if(file==={json.dumps(str(directory))}) {{const e=new Error('PRIVATE-SENTINEL');e.code='EACCES';throw e;}} return originalStat(file,...args);}};
'''
        result = self.helper(False, prelude)
        self.assertEqual(result.stdout.strip(), 'filesystem-error')
        self.assertNotIn('PRIVATE-SENTINEL', result.stdout + result.stderr)
        self.assertTrue(all(file.read_text() == self.text for file in self.files))

    def test_accepted_mode_group_owner_type_and_inode_changes_invalidate_retirement_snapshot(self):
        self.directories(0o775)
        for field, value in (('mode', 's.mode ^ 0o020'), ('gid', 's.gid + 1'), ('uid', 's.uid + 1'),
                             ('mode', '0o100775'), ('ino', 's.ino + 1')):
            prelude = f'''const testFs=require('node:fs'), originalStat=testFs.lstatSync, originalRead=testFs.readSync;
let reads=0, raced=false;
testFs.readSync=(...args)=>{{if(++reads==={len(self.files) + 1}) raced=true; return originalRead(...args);}};
testFs.lstatSync=(file,...args)=>{{const s=originalStat(file,...args); if(raced && file==={json.dumps(str(self.home))}) s.{field}={value}; return s;}};
'''
            with self.subTest(field=field, value=value):
                self.assertEqual(self.helper(False, prelude).stdout.strip(), 'boundary-changed')
                self.assertTrue(all(file.read_text() == self.text for file in self.files))


if __name__ == '__main__':
    unittest.main(verbosity=2)
