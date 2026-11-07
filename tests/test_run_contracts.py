#!/usr/bin/env python3
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import contract_shard

ROOT = Path(__file__).resolve().parents[1]
PREFIX = 'env -i PATH=/usr/bin:/bin /usr/bin/python3 -I tools/run-contracts.py'
SUITE = 'tests/test_macos_clt.py'


def workflow_command():
    workflow = (ROOT / '.github/workflows/contracts.yml').read_text()
    return re.search(r'      - name: Run contract\n        env:\n          SUITE: \$\{\{ matrix.suite \}\}\n        run: (.*)', workflow).group(1)


class WorkflowWiringTests(unittest.TestCase):
    def test_contract_job_uses_sanitized_dispatcher(self):
        command = workflow_command()
        self.assertTrue(command.startswith(PREFIX), command)
        self.assertNotIn('for test', command)
        self.assertNotIn('bash "$test"', command)
        self.assertNotIn('pre-push', (ROOT / 'lefthook.yml').read_text())


class DispatchTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='contract-dispatch-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'tools').mkdir()
        (self.root / 'tests').mkdir()
        shutil.copyfile(ROOT / 'tools/run-contracts.py', self.root / 'tools/run-contracts.py')
        spec = importlib.util.spec_from_file_location('contract_dispatch', self.root / 'tools/run-contracts.py')
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
                    'MANAGED_SKILLS_CLI': '/untrusted', 'PI_GO_LOCK_MODULE': '/untrusted',
                    'SUITE': SUITE}
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

    def dispatch(self, command=None):
        command = command or workflow_command()
        self.assertTrue(command.startswith(PREFIX), command)
        return subprocess.run(['/bin/sh', '-c', command], cwd=self.root, env=self.env,
                              stdin=subprocess.DEVNULL, capture_output=True, text=True)

    def inventory(self):
        return ['tests/' + name for name in self.module.DIRECT_SUITES] + ['tests/' + name for name in sorted(self.shell_names)]

    def test_actual_workflow_dispatch_sanitizes_and_selects_matrix_suite(self):
        result = self.dispatch()
        self.assertEqual(result.returncode, 0, result.stderr)
        record = json.loads(self.record.read_text())
        self.assertEqual(set(record['env']) - {'LC_CTYPE'}, {'PATH'})
        self.assertEqual(record['env']['PATH'], '/usr/bin:/bin')
        argv = record['argv']
        self.assertEqual(argv[:4], ['--node', self.env['SETUP_TEST_NODE'], '--pwsh', self.env['PWSH_BIN']])
        self.assertEqual(argv[4], '--tool-path')
        self.assertTrue(argv[5].startswith('/usr/bin:/bin:/tmp/setup-contract-tools-'))
        self.assertEqual(argv[6:8], ['--timeout', '900'])
        self.assertEqual(argv[8:], [SUITE])
        self.assertEqual(record['mode'], 0o700)
        self.assertEqual(record['tools'], {name: self.env[self.module.TOOLS[name]] for name in ('mise', 'chezmoi', 'bun')})
        self.assertFalse(Path(argv[5].split(':')[-1]).exists(), 'private dispatch tool links must be cleaned')

    def test_no_selection_runs_full_inventory(self):
        result = self.dispatch(workflow_command().replace(' "${SUITE}"', ''))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(self.record.read_text())['argv'][8:], self.inventory())

    def test_list_covers_every_suite_once_within_the_concurrency_limit(self):
        result = self.dispatch(PREFIX + ' --list')
        self.assertEqual(result.returncode, 0, result.stderr)
        listed = json.loads(result.stdout)
        self.assertLessEqual(len(listed), 32, 'GitHub queues jobs beyond the 40 concurrent jobs shared by every workflow on the account')
        covered = []
        for entry in listed:
            if entry.startswith('batch:'):
                self.env['SUITE'] = entry
                self.assertEqual(self.dispatch().returncode, 0)
                covered += json.loads(self.record.read_text())['argv'][8:]
                self.record.unlink()
            else:
                suite, _, shard = entry.partition(':')
                if shard.split('/')[0] in ('', '1'):
                    covered.append(suite)
        self.assertEqual(sorted(covered), sorted(self.inventory()))
        self.assertFalse(self.record.exists())

    def test_listed_shard_reaches_runner_and_invalid_shards_are_rejected(self):
        suite, count = next(iter(self.module.DEDICATED_JOBS.items()))
        self.env['SUITE'] = f'{suite}:{count}/{count}'
        result = self.dispatch()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(self.record.read_text())['argv'][8:], [self.env['SUITE']])
        self.record.unlink()
        for entry in (f'{suite}:0/{count}', f'{suite}:{count + 1}/{count}', f'{suite}:1/{count + 1}',
                      f'{suite}:1', SUITE + ':1/2', '../ubuntu.sh:1/1', 'batch:0/4', f'batch:1/{self.module.BATCHES + 1}',
                      f'batch:{self.module.BATCHES + 1}/{self.module.BATCHES}'):
            with self.subTest(entry=entry):
                self.env['SUITE'] = entry
                result = self.dispatch()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('not in the contract inventory', result.stderr)
                self.assertFalse(self.record.exists())

    def test_unknown_suite_is_rejected_before_runner(self):
        for suite in ('tests/run-fixture-matrix.py', 'tests/missing-contract.sh', '../ubuntu.sh'):
            with self.subTest(suite=suite):
                self.env['SUITE'] = suite
                result = self.dispatch()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('not in the contract inventory', result.stderr)
                self.assertFalse(self.record.exists())

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
        self.assertIn('empty contract run', result.stderr)
        self.assertFalse(self.record.exists())


class ShardTests(unittest.TestCase):
    def test_shards_partition_every_test_exactly_once(self):
        case = type('Case', (unittest.TestCase,), {f'test_{n}': lambda self: None for n in range(7)})
        tests = unittest.defaultTestLoader.loadTestsFromTestCase(case)
        selected = []
        for index in (1, 2, 3):
            with patch.dict(os.environ, {'SETUP_TEST_SHARD': f'{index}/3'}):
                shard = [test.id() for test in contract_shard.load_tests(None, tests, None)]
            self.assertTrue(shard)
            selected += shard
        self.assertEqual(sorted(selected), sorted(test.id() for test in tests))
        with patch.dict(os.environ, {}, clear=True):
            self.assertEqual(contract_shard.load_tests(None, tests, None).countTestCases(), 7)

    def test_invalid_shard_selection_fails(self):
        for value in ('0/3', '4/3', '1', 'a/b', '1/3 ', ''):
            with self.subTest(value=value), patch.dict(os.environ, {'SETUP_TEST_SHARD': value}):
                with self.assertRaises(ValueError):
                    contract_shard.selected_shard()

    def test_every_sharded_contract_runs_a_sharded_module(self):
        spec = importlib.util.spec_from_file_location('contract_inventory', ROOT / 'tools/run-contracts.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        for suite in [suite for suite, count in module.DEDICATED_JOBS.items() if count > 1]:
            with self.subTest(suite=suite):
                modules = re.findall(r'tests/(test_\w+\.py)', (ROOT / suite).read_text())
                self.assertTrue(any('from contract_shard import load_tests' in (ROOT / 'tests' / name).read_text()
                                    for name in modules))


if __name__ == '__main__':
    unittest.main(verbosity=2)
