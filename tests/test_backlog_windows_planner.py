"""Isolated Windows planner/pipe tests; no native handles, live configs, or MCPs."""
import base64
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'win.ps1').read_text()
PROGRAM = SOURCE.split('// BEGIN BACKLOG_MCP_RETIREMENT\n', 1)[1].split('// END BACKLOG_PURE_PLANNER', 1)[0]
PROGRAM += '\ntry { process.stdout.write(JSON.stringify(planRetirement(records))); } catch { process.exitCode=1; }'
NATIVE = SOURCE.split('// BEGIN BACKLOG_WINDOWS_NATIVE\n', 1)[1].split('// END BACKLOG_WINDOWS_NATIVE', 1)[0]
LAUNCHER = "const q=JSON.parse(require('node:fs').readFileSync(0,'utf8'));const records=q.records;eval(q.program);"
BUN = shutil.which('bun')
PWSH = os.environ.get('PWSH_BIN') or shutil.which('pwsh')


@unittest.skipUnless(BUN, 'Bun is required for the Windows built-in TOML planner')
class WindowsPlannerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='backlog-windows-planner-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.system = self.root / 'System32'
        self.system.mkdir()
        # Linux equivalent of the Windows null device used as an empty bunfig.
        if os.name != 'nt':
            (self.system / 'NUL').write_text('')
        self.env = {'HOME': str(self.system), 'USERPROFILE': str(self.system),
                    'XDG_CONFIG_HOME': str(self.system), 'APPDATA': str(self.system),
                    'LOCALAPPDATA': str(self.system)}
        for name in ('SystemRoot', 'WINDIR'):
            if name in os.environ:
                self.env[name] = os.environ[name]

    def request(self, entries):
        return json.dumps({'program': PROGRAM, 'records': [
            {'format': fmt, 'input': base64.b64encode(text.encode()).decode()}
            for fmt, text in entries]}, ensure_ascii=True)

    def plan(self, entries, ok=True):
        result = subprocess.run([BUN, '--no-env-file', '--no-install', '--config=NUL', '--eval', LAUNCHER],
                                input=self.request(entries), text=True, capture_output=True,
                                env=self.env, cwd=self.system, timeout=20)
        if not ok:
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(result.stdout, '')
            self.assertEqual(result.stderr, '')
            return
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, '')
        return [None if item is None else base64.b64decode(item).decode() for item in json.loads(result.stdout)]

    def test_json_preserves_exact_unrelated_numbers_bom_unicode_and_records(self):
        text = '\ufeff{"counter":9007199254740993,"exponent":1e400,"decimal":1.0000000000000001,"fraction":0.25,"negative":-0,"mcpServers":{"Backlog":{},"keep":{"token":"fake-雪-secret"}},"projects":{"repo":{"mcpServers":{"backlog":{}}}}}'
        output = self.plan([('json', text)])[0]
        self.assertEqual(output, text.replace('"Backlog":{},', ''))
        self.assertIsNone(self.plan([('json', output)])[0])

    def test_all_member_positions_alias_and_nested_objects(self):
        for members in [
            '"backlog":{},"keep":{}', '"keep":{},"backlog":{}',
            '"backlog":{}', '"Backlog":{},"backlog":{},"keep":{}',
            '"tasks":{"command":"C:\\\\bin\\\\backlog.exe","args":["mcp","start"],"env":{"token":"fake-secret"}},"keep":{"args":[{"nested":{"backlog":{}}}]}'
        ]:
            with self.subTest(members=members):
                result = self.plan([('json', '{"mcpServers":{' + members + '}}')])[0]
                self.assertIsNotNone(result)
                servers = json.loads(result)['mcpServers']
                self.assertFalse(any(key.lower() == 'backlog' or key == 'tasks' for key in servers))

    def test_native_json_map_spellings_are_scoped(self):
        for fmt, key in [('codex-json', 'mcp_servers'), ('editor-json', 'mcp-servers')]:
            text = json.dumps({key: {'backlog': {}, 'keep': {}}, 'projects': {'backlog': {}}})
            self.assertEqual(set(json.loads(self.plan([(fmt, text)])[0])[key]), {'keep'})
            self.assertIsNone(self.plan([('json', text)])[0])

    def test_toml_syntax_and_semantic_preservation(self):
        suffix = '[[unrelated]]\nkeep="雪"\n[other]\nvalue=0.25\n'
        for header in ['[mcp_servers.backlog]', '[mcp_servers."backlog"]', "[mcp_servers.'backlog']"]:
            self.assertEqual(self.plan([('toml', header + '\ncommand="backlog"\n' + suffix)])[0], suffix)
        alias = '[mcp_servers.tasks]\ncommand="C:\\\\bin\\\\backlog.exe"\nargs=["mcp","start"]\n[mcp_servers.tasks.env]\nTOKEN="fake-secret"\n'
        self.assertEqual(self.plan([('toml', alias + suffix)])[0], suffix)
        absent = 'custom="""\n[mcp_servers.backlog]\nnot a server\n"""\n' + suffix
        self.assertIsNone(self.plan([('toml', absent)])[0])

    def test_malformed_and_unsupported_input_never_returns_partial_plan(self):
        valid = ('json', '{"mcpServers":{"backlog":{}}}')
        for invalid in [
            ('json', '{"mcpServers":{"backlog":{},"backlog":{}}}'),
            ('json', '{"mcpServers":[]}'), ('json', '{fake-secret'),
            ('toml', '[mcp_servers.backlog]\ninvalid=['),
            ('toml', '[mcp_servers.backlog]\ncommand="a"\ncommand="b"\n'),
            ('toml', 'mcp_servers={backlog={command="backlog"}}'),
            ('toml', 'mcp_servers.backlog.command="backlog"'),
        ]:
            with self.subTest(invalid=invalid):
                self.plan([valid, invalid], ok=False)

    @unittest.skipUnless(PWSH and os.name != 'nt', 'Linux PowerShell needed for isolated production pipe probe')
    def test_actual_native_backend_pipe_code_and_environment_isolation(self):
        # Calls the production managed Plan method, not its Win32 methods. The
        # exact C# process runner executes Bun; all input/output stays in pipes.
        native_file = self.root / 'native.cs'; native_file.write_text(NATIVE)
        runner = self.root / 'runner.ps1'
        runner.write_text('param($Native,$Bun,$Root)\n$ErrorActionPreference="Stop"\n'
                          'Add-Type -TypeDefinition ([IO.File]::ReadAllText($Native))\n'
                          '[Console]::InputEncoding=[Text.UTF8Encoding]::new($false)\n'
                          '$request=[Console]::In.ReadToEnd()\n'
                          '[Console]::Out.Write([BacklogNativeFiles]::Plan($Bun,$request,$Root))\n')
        poison = self.root / 'poison'; poison.mkdir()
        sentinel = self.root / 'executed'
        preload = poison / 'preload.cjs'
        preload.write_text('require("node:fs").writeFileSync(' + json.dumps(str(sentinel)) + ',"executed")')
        (poison / 'bunfig.toml').write_text('preload = [' + json.dumps(str(preload)) + ']\n')
        (poison / '.bunfig.toml').write_text((poison / 'bunfig.toml').read_text())
        (poison / '.env').write_text('NODE_OPTIONS=--require=' + str(preload) + '\n')
        env = dict(os.environ, HOME=str(poison), USERPROFILE=str(poison),
                   XDG_CONFIG_HOME=str(poison), NODE_OPTIONS='--require=' + str(preload),
                   BUN_OPTIONS='--preload=' + str(preload))
        entries = [('json', '{"mcpServers":{"keep":{}}}'),
                   ('json', '{"mcpServers":{"backlog":{},"keep":{"token":"fake-雪-secret"}}}'),
                   ('toml', '[mcp_servers.backlog]\ncommand="backlog"\n[other]\nkeep=true\n')]
        result = subprocess.run([PWSH, '-NoProfile', '-File', str(runner), str(native_file), BUN, str(self.root)],
                                input=self.request(entries), text=True, capture_output=True,
                                env=env, cwd=poison, timeout=45)
        self.assertEqual(result.returncode, 0, result.stderr)
        decoded = [None if item is None else base64.b64decode(item).decode() for item in json.loads(result.stdout)]
        self.assertEqual(decoded, self.plan(entries))
        self.assertFalse(sentinel.exists(), 'a parent/project startup file executed')
        self.assertEqual(result.stderr, '')


if __name__ == '__main__':
    unittest.main()
