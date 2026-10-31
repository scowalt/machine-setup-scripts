import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
PROGRAM = (ROOT / 'mac.sh').read_text().split('// BEGIN BACKLOG_MCP_RETIREMENT\n', 1)[1].split('\n// END BACKLOG_MCP_RETIREMENT', 1)[0]
BUN = shutil.which('bun')


@unittest.skipUnless(BUN, 'Existing native Bun required; no runtime download')
class BunFallback(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='backlog-bun-')
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.bun = self.home / '.bun/bin/bun'
        self.bun.parent.mkdir(parents=True)
        shutil.copy2(Path(BUN).resolve(), self.bun)
        self.bun.chmod(0o775)
        self.shared = self.home / '.config/mcp/mcp.json'
        self.shared.parent.mkdir(parents=True)
        self.original = '{"mcpServers":{"backlog":{},"keep":{}},"credential":"fake-secret"}\n'
        self.shared.write_text(self.original)
        self.toml = self.home / '.codex/config.toml'
        self.toml.parent.mkdir()
        self.toml.write_text('[mcp_servers.backlog]\ncommand="backlog"\n[other]\nkeep=true\n')
        self.marker = self.home / 'startup-executed'
        poison = self.home / 'poison.cjs'
        poison.write_text(f'require("node:fs").writeFileSync({json.dumps(str(self.marker))}, "bad")')
        (self.home / '.bunfig.toml').write_text('preload = [' + json.dumps(str(poison)) + ']\n')
        (self.home / '.env').write_text('NODE_OPTIONS=--require=' + str(poison) + '\n')
        self.prelude = r'''
const fixtureFs = require('node:fs'), fixtureCp = require('node:child_process');
const fixtureStat = fixtureFs.lstatSync.bind(fixtureFs), fixtureSpawn = fixtureCp.spawnSync.bind(fixtureCp);
fixtureFs.lstatSync = (file, ...args) => {
    if (['/usr/bin/python3', '/opt/homebrew/bin/python3', '/usr/local/bin/python3',
         '/opt/homebrew/bin/bun', '/usr/local/bin/bun'].includes(file)) {
        const error = new Error(); error.code = 'ENOENT'; throw error;
    }
    return fixtureStat(file, ...args);
};
fixtureCp.spawnSync = (command, args, options) => {
    if (command !== process.argv[2] + '/.bun/bin/bun') throw Error('unmocked external command');
    if (!args.includes('--no-env-file') || !args.includes('--no-install') || !args.includes('--config=/dev/null')) throw Error('missing isolation');
    if (options.cwd !== '/' || !options.timeout || options.env.NODE_OPTIONS || options.env.BUN_OPTIONS) throw Error('inherited controls');
    return fixtureSpawn(command, args, options);
};
// Poison only after Node has started: the native parser child must not inherit it.
process.env.NODE_OPTIONS = '--require=' + process.argv[2] + '/poison.cjs';
process.env.BUN_OPTIONS = '--preload=' + process.argv[2] + '/poison.cjs';
'''

    def run_helper(self, expected='removed'):
        result = subprocess.run(['node', '--input-type=commonjs', '-', str(self.home), '', '', '', ''],
                                input=self.prelude + PROGRAM, text=True, capture_output=True,
                                cwd=self.home, env={**os.environ, 'HOME': str(self.home)}, timeout=20)
        self.assertEqual(result.stdout.strip(), expected, result.stderr)
        self.assertEqual(result.returncode, int(expected not in ('removed', 'absent')))
        self.assertEqual(result.stderr, '')
        self.assertFalse(self.marker.exists())

    def test_existing_bun_retirement_without_python_is_repeatable_and_isolated(self):
        self.run_helper()
        self.assertEqual(self.toml.read_text(), '[other]\nkeep=true\n')
        self.assertEqual(self.shared.read_text(), self.original.replace('"backlog":{},', ''))
        self.assertEqual(self.bun.stat().st_mode & 0o777, 0o775)
        self.run_helper('absent')

    def test_incompatible_system_python_uses_existing_bun(self):
        self.prelude += r'''
const filteredStat = fixtureFs.lstatSync, filteredSpawn = fixtureCp.spawnSync;
fixtureFs.lstatSync = (file, ...args) => file === '/usr/bin/python3' ? fixtureStat(file, ...args) : filteredStat(file, ...args);
fixtureCp.spawnSync = (command, args, options) => args.includes('import tomllib; print("ready")')
    ? {status: 1, stdout: '', stderr: 'fixture: no tomllib'} : filteredSpawn(command, args, options);
'''
        self.run_helper()
        self.assertEqual(self.toml.read_text(), '[other]\nkeep=true\n')

    def test_failed_native_parser_preserves_files_and_redacts_output(self):
        original = self.toml.read_text()
        self.prelude += "\nfixtureCp.spawnSync = () => ({status: 1, stdout: 'fake-secret', stderr: 'fake-secret'});\n"
        self.run_helper('toml-parser-failed')
        self.assertEqual(self.shared.read_text(), self.original)
        self.assertEqual(self.toml.read_text(), original)

    def test_malformed_or_unsupported_toml_preserves_all_metadata(self):
        for text, reason in (('[mcp_servers.backlog]\ninvalid=[', 'malformed-toml'),
                             ('mcp_servers.backlog.command="backlog"\n', 'unsupported-toml')):
            with self.subTest(reason=reason):
                self.toml.write_text(text)
                self.run_helper(reason)
                self.assertEqual(self.toml.read_text(), text)
                self.assertEqual(self.shared.read_text(), self.original)

    def test_missing_or_unsafe_bun_does_not_bypass_parser_safety(self):
        self.bun.chmod(0o777)
        self.run_helper('toml-parser-unavailable')
        self.assertEqual(self.shared.read_text(), self.original)
        self.bun.unlink()
        self.run_helper('toml-parser-unavailable')
        self.assertEqual(self.shared.read_text(), self.original)

    def test_linked_runtime_parent_is_not_followed(self):
        moved = self.home / 'outside'
        self.bun.parent.rename(moved)
        self.bun.parent.symlink_to(moved, target_is_directory=True)
        self.run_helper('unsafe-path')
        self.assertEqual(self.shared.read_text(), self.original)


if __name__ == '__main__':
    unittest.main(verbosity=2)
