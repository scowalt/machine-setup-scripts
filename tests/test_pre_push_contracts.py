#!/usr/bin/env python3
import importlib.util
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
PREFIX = 'env -i PATH=/usr/bin:/bin /usr/bin/python3 -I tools/run-pre-push-contracts.py'


def hook_command():
    config = (ROOT / 'lefthook.yml').read_text()
    return re.search(r'    contract-tests:\n      run: (.*)', config).group(1)


class HookWiringTests(unittest.TestCase):
    def test_contract_hook_uses_sanitized_dispatcher(self):
        command = hook_command()
        self.assertTrue(command.startswith(PREFIX), command)
        self.assertNotIn('for test', command)
        self.assertNotIn('bash "$test"', command)


class DispatchTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='hook-dispatch-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'tools').mkdir()
        (self.root / 'tests').mkdir()
        shutil.copyfile(ROOT / 'tools/run-pre-push-contracts.py', self.root / 'tools/run-pre-push-contracts.py')
        spec = importlib.util.spec_from_file_location('hook_dispatch', self.root / 'tools/run-pre-push-contracts.py')
        self.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.module)
        self.shell_names = sorted(p.name for p in (ROOT / 'tests').glob('*.sh')) + ['future-contract.sh']
        for name in self.shell_names + list(self.module.DIRECT_SUITES):
            (self.root / 'tests' / name).write_text('raise RuntimeError("suite must never execute in dispatch test")\n')
        self.env = {'PATH': '/usr/bin:/bin', 'HOME': str(self.root),
                    'SECRET_SENTINEL': 'must-not-propagate', 'NODE_OPTIONS': '--invalid-sentinel',
                    'PYTHONPATH': str(self.root / 'untrusted'), 'BASH_ENV': str(self.root / 'startup'),
                    'GIT_CONFIG_COUNT': '1', 'GIT_CONFIG_KEY_0': 'core.hooksPath',
                    'GIT_CONFIG_VALUE_0': '/untrusted', 'PI_CODING_AGENT_DIR': '/untrusted',
                    'MANAGED_SKILLS_CLI': '/untrusted', 'PI_GO_LOCK_MODULE': '/untrusted'}
        (self.root / 'startup').write_text('exit 99\n')
        for name, variable in self.module.TOOLS.items():
            tool = self.root / ('native ' + name)
            tool.write_bytes(b'\x7fELFinert-not-executable-code')
            tool.chmod(0o700)
            self.env[variable] = str(tool)
        self.record = self.root / 'record.json'
        self.runner(0)

    def runner(self, status):
        (self.root / 'tests/run-fixture-matrix.py').write_text(
            'import json, os, sys\nfrom pathlib import Path\n'
            'root = Path(__file__).resolve().parents[1]\n'
            'tools = Path(sys.argv[sys.argv.index("--tool-path") + 1].split(":")[-1])\n'
            'record = {"argv": sys.argv[1:], "env": dict(os.environ), '
            '"mode": tools.stat().st_mode & 0o777, '
            '"tools": {p.name: str(p.resolve()) for p in tools.iterdir()}}\n'
            '(root / "record.json").write_text(json.dumps(record))\n'
            f'sys.exit({status})\n')

    def dispatch(self):
        command = hook_command()
        self.assertTrue(command.startswith(PREFIX), command)
        return subprocess.run(['/bin/sh', '-c', command], cwd=self.root, env=self.env,
                              stdin=subprocess.DEVNULL, capture_output=True, text=True)

    def test_actual_hook_dispatch_sanitizes_and_selects_full_suite(self):
        result = self.dispatch()
        self.assertEqual(result.returncode, 0, result.stderr)
        record = json.loads(self.record.read_text())
        self.assertEqual(set(record['env']) - {'LC_CTYPE'}, {'PATH'})
        self.assertEqual(record['env']['PATH'], '/usr/bin:/bin')
        argv = record['argv']
        self.assertEqual(argv[:4], ['--node', self.env['SETUP_TEST_NODE'], '--pwsh', self.env['PWSH_BIN']])
        self.assertEqual(argv[4], '--tool-path')
        self.assertTrue(argv[5].startswith('/usr/bin:/bin:/tmp/setup-hook-tools-'))
        expected = ['tests/' + name for name in self.module.DIRECT_SUITES] + ['tests/' + name for name in sorted(self.shell_names)]
        self.assertEqual(argv[6:8], ['--timeout', '900'])
        self.assertEqual(argv[8:], expected)
        self.assertEqual(record['mode'], 0o700)
        self.assertEqual(record['tools'], {name: self.env[self.module.TOOLS[name]] for name in ('mise', 'chezmoi', 'bun')})
        self.assertFalse(Path(argv[5].split(':')[-1]).exists(), 'private dispatch tool links must be cleaned')

    def test_simulated_runner_failures_propagate_without_retry(self):
        for status in (1, 2, 125):
            with self.subTest(simulated_status=status):
                self.runner(status)
                result = self.dispatch()
                self.assertEqual(result.returncode, status, result.stderr)

    def test_missing_relative_and_shim_tools_fail_before_runner(self):
        for variable in self.module.TOOLS.values():
            original = self.env[variable]
            for value in (str(self.root / 'missing'), 'relative/path'):
                with self.subTest(variable=variable, value=value):
                    self.env[variable] = value
                    result = self.dispatch()
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn(variable, result.stderr)
                    self.assertFalse(self.record.exists())
            shim = self.root / 'shim'
            shim.write_text('#!/bin/sh\nexit 99\n')
            shim.chmod(0o700)
            self.env[variable] = str(shim)
            result = self.dispatch()
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('not a shim', result.stderr)
            self.assertFalse(self.record.exists())
            self.env[variable] = original

    def test_system_discovery_is_bounded_and_missing_tool_fails(self):
        with patch.object(self.module.shutil, 'which', return_value=None) as which:
            with self.assertRaisesRegex(ValueError, 'SETUP_TEST_NODE'):
                self.module.native_tool('node', '')
            which.assert_called_once_with('node', path='/usr/bin:/bin')

    def test_unsupported_platform_and_launch_failure_are_fatal(self):
        arguments = [part for name, variable in self.module.TOOLS.items() for part in ('--' + name, self.env[variable])]
        with patch.object(self.module.os, 'uname') as uname, patch.object(self.module.subprocess, 'call') as call:
            uname.return_value.sysname = 'Darwin'
            with self.assertRaises(SystemExit) as result:
                self.module.main(arguments)
            self.assertEqual(result.exception.code, 2)
            call.assert_not_called()
        with patch.object(self.module.subprocess, 'call', side_effect=OSError) as call:
            self.assertEqual(self.module.main(arguments), 125)
            self.assertEqual(call.call_count, 1)
            self.assertEqual(call.call_args.kwargs['env'], {'PATH': '/usr/bin:/bin'})
            self.assertTrue(call.call_args.kwargs['close_fds'])

    def test_linked_or_empty_inventory_is_rejected(self):
        contract = self.root / 'tests' / self.shell_names[0]
        contract.unlink()
        contract.symlink_to(self.root / 'missing')
        self.assertNotEqual(self.dispatch().returncode, 0)
        self.assertFalse(self.record.exists())
        for path in (self.root / 'tests').glob('*.sh'):
            path.unlink()
        result = self.dispatch()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('empty hook run', result.stderr)
        self.assertFalse(self.record.exists())


if __name__ == '__main__':
    unittest.main(verbosity=2)
