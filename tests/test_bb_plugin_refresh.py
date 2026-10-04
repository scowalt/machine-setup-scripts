#!/usr/bin/env python3
"""Definitions-only refresh policy/callers, synthetic files and inert native APIs.

No process inventory, socket, application, plugin, service or installed BB code
is used. Run only through run-fixture-matrix.py and its mandatory kernel filter.
"""
import ast
import copy
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import types
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ('ubuntu', 'mac', 'pi', 'bazzite', 'wsl')


def definitions_only(text=None):
    path = ROOT / 'lib/bb-plugin-refresh.py'
    tree = ast.parse(path.read_text() if text is None else text)
    modules = {'ctypes', 'http.client', 'json', 'os', 're', 'signal', 'socket',
               'stat', 'subprocess', 'sys', 'time'}
    constants = {'MAX_BYTES', 'MAX_PROCESSES', 'MAX_PLUGINS'}

    def check_function(node):
        args = node.args
        parameters = args.posonlyargs + args.args + args.kwonlyargs + [a for a in (args.vararg, args.kwarg) if a]
        if node.name == 'Exception' or node.decorator_list or node.returns is not None or any(a.annotation is not None for a in parameters):
            raise ValueError('Definition-time annotation/decorator refused')
        for default in args.defaults + [v for v in args.kw_defaults if v is not None]:
            if not (isinstance(default, ast.Name) and default.id in constants):
                ast.literal_eval(default)

    selected = []
    for node in tree.body:
        if isinstance(node, ast.Import):
            if any(a.name not in modules or a.asname is not None for a in node.names):
                raise ValueError('Only audited standard-library imports are permitted')
            selected.append(node)
        elif isinstance(node, ast.ImportFrom):
            if node.module != 'pathlib' or node.level or [(a.name, a.asname) for a in node.names] != [('Path', None)]:
                raise ValueError('Unaudited import refused')
            selected.append(node)
        elif isinstance(node, ast.FunctionDef):
            check_function(node)
            selected.append(node)
        elif isinstance(node, ast.ClassDef):
            if node.name == 'Exception' or node.decorator_list or node.keywords or any(not isinstance(b, ast.Name) or b.id != 'Exception' for b in node.bases):
                raise ValueError('Definition-time class expression refused')
            for member in node.body:
                if isinstance(member, ast.FunctionDef):
                    check_function(member)
                elif not (isinstance(member, ast.Pass) or isinstance(member, ast.Expr)
                          and isinstance(member.value, ast.Constant) and isinstance(member.value.value, str)):
                    raise ValueError('Executable class body refused')
            selected.append(node)
        elif isinstance(node, ast.Assign):
            if len(node.targets) != 1 or not isinstance(node.targets[0], ast.Name) or node.targets[0].id not in constants:
                raise ValueError('Unaudited initializer refused')
            ast.literal_eval(node.value)
            selected.append(node)
        elif isinstance(node, ast.Expr) and isinstance(node.value, ast.Constant) and isinstance(node.value.value, str):
            continue
        elif isinstance(node, ast.If) and ast.unparse(node.test) == "__name__ == '__main__'":
            continue
        else:
            raise ValueError('Unsupported policy import layout')
    module = types.ModuleType('refresh_fixture')
    exec(compile(ast.Module(body=selected, type_ignores=[]), str(path), 'exec'), module.__dict__)
    return module


P = definitions_only()
spec = importlib.util.spec_from_file_location('fixture_extractor', ROOT / 'tests/extract_setup_fixture.py')
EXTRACT = importlib.util.module_from_spec(spec)
spec.loader.exec_module(EXTRACT)


def plugin(identity='tracking', source='npm:fixture@^1', enabled=True):
    return {'id': identity, 'source': source, 'version': '1.0.0', 'provenance': 'direct',
            'enabled': enabled, 'status': 'running' if enabled else 'disabled', 'updateState': {}}


def resolved(version):
    return {'version': version, 'display': 'npm:fixture@' + version}


class FakeApi:
    def __init__(self, plugins=None, outcomes=None):
        self.plugins = {p['id']: copy.deepcopy(p) for p in (plugins or [plugin()])}
        self.outcomes = outcomes or {identity: 'update-available' for identity in self.plugins}
        self.calls = []
        self.safe = False
        self.results = {}
        self.verified = False
        self.after_update = lambda _: None

    def verify(self):
        self.verified = True

    def request(self, method, path, payload=None):
        assert self.verified
        self.calls.append((method, path, payload))
        if path == '/api/v1/plugins/safe-mode':
            return {'enabled': self.safe}
        if path == '/api/v1/plugins':
            return {'plugins': copy.deepcopy(list(self.plugins.values()))}
        if path.endswith('/source'):
            row = self.plugins[path.split('/')[-2]]
            return {'requested': row['source'], 'resolved': resolved(row['version'])['display'],
                    'subdirectory': 'nested/plugin', 'range': '^1', 'tagPrefix': 'fixture/',
                    'history': [], 'engines': {}}
        if path.endswith('/updates/check'):
            entries = []
            for identity, row in self.plugins.items():
                outcome = self.outcomes[identity]
                entry = {'id': identity, 'installed': resolved(row['version']), 'outcome': outcome}
                if outcome == 'update-available':
                    entry['candidate'] = resolved('1.1.0')
                if outcome == 'incompatible':
                    entry['blocked'] = {'version': '9.0.0', 'reasons': ['bb-engine']}
                entries.append(entry)
            return {'results': entries}
        assert method == 'POST' and path.endswith('/update'), (method, path)
        identity = path.split('/')[-2]
        result = self.results.get(identity, 'updated')
        if isinstance(result, Exception):
            raise result
        row = self.plugins[identity]
        answer = {'applied': result == 'updated', 'from': resolved(row['version']),
                  'to': resolved('1.1.0'), 'outcome': result}
        if result == 'updated':
            row['version'] = '1.1.0'
            self.outcomes[identity] = 'current'
        self.after_update(identity)
        return answer

    def mutations(self):
        return [call for call in self.calls if call[1].endswith('/update')]


class DarwinInputs:
    """Inert ps/sysctl/lsof bytes; the production parser and identity proof run."""
    def __init__(self, table, records, uids=None):
        self.table = table
        self.records = records
        self.uids = uids or {}
        self.private_reads = []
        self.queries = []
        self.peer = True
        self.on_query = lambda _: None

    def command(self, args, **kwargs):
        self.queries.append(args)
        self.on_query(args)
        assert kwargs['env'] == {'PATH': '/usr/bin:/bin:/usr/sbin:/sbin', 'LC_ALL': 'C'}
        status = 0
        if args == ['/bin/ps', '-axo', 'uid=,pid=']:
            raw = self.table
        elif args[:2] == ['/bin/ps', '-p'] and args[3:] == ['-o', 'uid=,lstart=']:
            pid = int(args[2])
            if pid not in self.records:
                raw, status = b'', 1
            else:
                stamp = self.records[pid][2].decode('ascii')
                raw = f'{self.uids.get(pid, os.getuid())} {stamp}\n'.encode('ascii')
        elif args[:4] == ['/usr/sbin/lsof', '-nP', '-a', '-p'] and args[5:] == ['-iTCP', '-FpnT']:
            pid = int(args[4])
            port = self.records[pid][1]['BB_SERVER_PORT']
            raw = f'p{pid}\nn127.0.0.1:{port}->127.0.0.1:49999\nTST=ESTABLISHED\n'.encode() if self.peer else b''
        elif len(args) == 5 and args[:4] == ['/usr/sbin/lsof', '-nP', '-Fpu', '--']:
            assert Path(args[-1]).name == 'bb.db'
            raw, status = b'', 1
        else:
            raise AssertionError('unexpected native command')
        return types.SimpleNamespace(returncode=status, stdout=raw, stderr=b'')

    def sysctl(self, mib, length, buffer, size, new, new_length):
        assert (mib[0], mib[1], length, new, new_length) == (1, 49, 3, None, 0)
        pid = mib[2]
        self.private_reads.append(pid)
        argv, env, _ = self.records[pid]
        values = [arg.encode() for arg in argv] + [f'{key}={value}'.encode() for key, value in env.items()]
        raw = len(argv).to_bytes(4, P.sys.byteorder) + argv[0].encode() + b'\0\0' + b'\0'.join(values) + b'\0'
        P.ctypes.memmove(buffer, raw, len(raw))
        size._obj.value = len(raw)
        return 0

    @contextlib.contextmanager
    def installed(self):
        with patch.object(P.subprocess, 'run', side_effect=self.command), \
                patch.object(P.ctypes, 'CDLL', return_value=types.SimpleNamespace(sysctl=self.sysctl)), \
                patch.object(P.os, 'kill', side_effect=AssertionError('process mutation forbidden')):
            yield self


def run_wrapper(text, status=0):
    source = (ROOT / 'lib/bb-plugin-refresh.bash').read_text().split('\nbb_plugin_refresh_payload()', 1)[0]
    code = source + '\n' + '\n'.join(f'{name}() {{ printf "%s\\n" "$1"; }}' for name in
                                      ('print_section', 'print_message', 'print_error', 'print_warning', 'print_debug'))
    code += '\nbb_plugin_refresh_payload() { printf "%s\\n" "$FIXTURE_OUTPUT"; printf "%s\\n" "stderr-secret-sentinel" >&2; return "$FIXTURE_STATUS"; }\nrefresh_bb_plugins\n'
    with tempfile.TemporaryDirectory(prefix='bb-refresh-wrapper-') as home:
        return subprocess.run(['/bin/bash', '-c', code], cwd=home,
                              env={'HOME': home, 'PATH': '/usr/bin:/bin', 'FIXTURE_OUTPUT': text, 'FIXTURE_STATUS': str(status)},
                              stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=5)


class Policy(unittest.TestCase):
    def test_source_import_rejects_definition_time_effects_before_execution(self):
        candidates = ['import nonexistent_application', 'print("BEFORE_MOCKS")',
                      'class Unsafe:\n    print("BEFORE_MOCKS")',
                      'class Unsafe:\n    def method(self, value=print("BEFORE_MOCKS")):\n        pass',
                      '@print("BEFORE_MOCKS")\ndef unsafe():\n    pass',
                      'def unsafe(value: print("BEFORE_MOCKS")):\n    pass',
                      'class Unsafe(metaclass=print("BEFORE_MOCKS")):\n    pass',
                      'class Exception:\n    def __init_subclass__(cls):\n        print("BEFORE_MOCKS")\nclass Unsafe(Exception):\n    pass']
        for source in candidates:
            output = io.StringIO()
            with self.subTest(source=source), contextlib.redirect_stdout(output), self.assertRaises(ValueError):
                definitions_only(source)
            self.assertEqual(output.getvalue(), '')

    def test_entire_helper_deadline_precedes_discovery_and_raw_errors_are_suppressed(self):
        events = []
        def discover(*_args):
            self.assertEqual(events, ['signal', ('alarm', 1800)])
            raise RuntimeError('secret-sentinel-must-not-escape')
        output = io.StringIO()
        with patch.object(P.os, 'getuid', return_value=1234), \
                patch.object(P.sys, 'argv', ['fixture', '/inert-home', 'ready']), \
                patch.object(P, 'LocalFiles', return_value=object()), \
                patch.object(P, 'Processes', return_value=object()), \
                patch.object(P, 'discover', side_effect=discover), \
                patch.object(P.signal, 'signal', side_effect=lambda *_: events.append('signal')), \
                patch.object(P.signal, 'alarm', side_effect=lambda value: events.append(('alarm', value))), \
                contextlib.redirect_stdout(output):
            self.assertEqual(P.run(), 1)
        self.assertEqual(output.getvalue(), 'BB_PLUGIN_REFRESH failed discovery unknown-failure\n')

    def test_current_pinned_local_bundled_and_incompatible_are_preserved(self):
        rows = [plugin('current'), plugin('pin', 'npm:fixture@1.0.0'),
                plugin('local', 'path:/inert/development'), plugin('builtin', 'builtin:fixture'),
                plugin('incompatible')]
        rows[3]['provenance'] = 'builtin'
        api = FakeApi(rows, dict(zip([r['id'] for r in rows], ['current', 'pinned', 'pinned', 'pinned', 'incompatible'])))
        before = copy.deepcopy(api.plugins)
        self.assertEqual(P.refresh(api), ('checked', False))
        self.assertEqual(api.plugins, before)
        self.assertFalse(api.mutations())

    def test_update_preserves_disabled_status_and_source_intent(self):
        for enabled in (True, False):
            with self.subTest(enabled=enabled):
                api = FakeApi([plugin(enabled=enabled)])
                self.assertEqual(P.refresh(api), ('updated', False))
                row = api.plugins['tracking']
                self.assertEqual(row['enabled'], enabled)
                self.assertEqual(row['source'], 'npm:fixture@^1')
                self.assertEqual(row['status'], 'running' if enabled else 'disabled')
                self.assertEqual(len(api.mutations()), 1)

    def test_safe_mode_does_not_check_update_sources(self):
        api = FakeApi()
        api.safe = True
        self.assertEqual(P.refresh(api), ('safe-mode', False))
        self.assertEqual(len(api.calls), 1)

    def test_safe_mode_race_retains_prior_failures(self):
        for unavailable in (False, True):
            api = FakeApi([plugin('first'), plugin('second')],
                          {'first': 'unavailable' if unavailable else 'current', 'second': 'update-available'})
            api.results['second'] = P.Refusal('safe-mode')
            self.assertEqual(P.refresh(api), ('safe-mode', unavailable))

    def test_unavailable_rollback_and_partial_failure_are_not_success(self):
        for failure in ('rolled-back', P.Refusal('native-request-failed'), P.Refusal('operation-timeout')):
            api = FakeApi([plugin('first'), plugin('second')])
            api.results['first'] = failure
            self.assertEqual(P.refresh(api), ('updated', True))
            self.assertEqual(len(api.mutations()), 2)
        api = FakeApi(outcomes={'tracking': 'unavailable'})
        self.assertEqual(P.refresh(api), ('checked', True))
        self.assertFalse(api.mutations())

    def test_zero_exit_equivalent_false_success_and_intent_changes_are_refused(self):
        mutations = [lambda api: api.plugins['tracking'].update(enabled=False),
                     lambda api: api.plugins['tracking'].update(source='npm:other'),
                     lambda api: api.plugins['tracking'].update(status='degraded'),
                     lambda api: api.plugins['tracking']['updateState'].update(lastFailure={'at': 42}),
                     lambda api: api.plugins['tracking'].update(version='1.0.0')]
        for mutation in mutations:
            api = FakeApi()
            api.after_update = lambda _, api=api, mutation=mutation: mutation(api)
            with self.subTest(mutation=mutation), self.assertRaises(P.Refusal):
                P.refresh(api)
        api = FakeApi()
        api.results['tracking'] = 'current'
        self.assertEqual(P.refresh(api), ('checked', True))

    def test_malformed_results_and_dev_mode_fail_before_updates(self):
        for shape in (None, {}, {'results': []}, {'results': [None]},
                      {'results': [{'id': 'tracking', 'installed': resolved('1.0.0'), 'outcome': 'skipped'}]},
                      {'results': [{'id': 'tracking', 'installed': resolved('1.0.0'), 'outcome': 'current', 'devMode': True}]}):
            api = FakeApi()
            native = api.request
            api.request = lambda method, path, payload=None: shape if path.endswith('/updates/check') else native(method, path, payload)
            with self.subTest(shape=shape), self.assertRaises(P.Refusal):
                P.refresh(api)
            self.assertFalse(api.mutations())
        for raw in ('{"ok":true,"ok":false}', '{', '{"x":NaN}'):
            with self.assertRaises(P.Refusal):
                P.object_json(raw)

    def test_bundled_or_path_update_selection_is_not_applied(self):
        for source in ('path:/inert', 'builtin:fixture'):
            api = FakeApi([plugin(source=source)])
            with self.assertRaises(P.Refusal):
                P.refresh(api)
            self.assertFalse(api.mutations())


class Discovery(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='bb-refresh-fixture-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.home = self.root / 'home'
        self.home.mkdir(mode=0o700)
        self.package = self.home / 'npm/lib/node_modules/bb-app'
        self.entry = self.package / 'server/dist/index.js'
        self.entry.parent.mkdir(parents=True)
        self.entry.write_text('throw Error("fixture must not execute BB");\n')
        (self.entry.parent / 'start-server.js').write_text('throw Error("fixture must not execute BB");\n')
        (self.package / 'package.json').write_text(json.dumps({'name': 'bb-app', 'version': '0.44.0', 'bin': {'bb-server': 'dist/bb-server.js'}}))
        self.records = {}
        self.proc = types.SimpleNamespace(table=lambda: list(self.records), read=lambda pid: self.records.get(pid),
                                          peer_owned=lambda *_: True, database_open=lambda _: False)

    def files(self):
        return P.LocalFiles(self.home, os.getuid())

    def data(self, path=None):
        data = path or self.home / '.bb'
        data.mkdir(parents=True, exist_ok=True)
        (data / 'bb.db').write_bytes(b'SQLite format 3\0' + b'inert database placeholder')
        return data

    def server(self, pid=100, data=None, port='39001'):
        data = self.data(data)
        self.records[pid] = ([str(self.root / 'node'), str(self.entry)],
                             {'HOME': str(self.home), 'BB_DATA_DIR': str(data),
                              'BB_SERVER_PORT': port, 'BB_SERVER_LAUNCH_ID': 'fixture-launch'}, b'12345')
        return data

    @contextlib.contextmanager
    def darwin_inventory(self, table, uids=None):
        previous = self.proc
        with patch.object(P.sys, 'platform', 'darwin'):
            self.proc = P.Processes(os.getuid())
        native = DarwinInputs(table, self.records, uids)
        try:
            with native.installed():
                yield native
        finally:
            self.proc = previous

    @contextlib.contextmanager
    def darwin_http(self, api, fault=None):
        # Only the transport is replaced: NativeApi still revalidates process,
        # package, data, accepted-socket, health and native configuration proof.
        requests = []
        def connection(host, port, **_kwargs):
            self.assertEqual((host, port), ('127.0.0.1', 39001))
            def request(method, path, body, _headers):
                requests.append((method, path, None if body is None else json.loads(body)))
            def response():
                method, path, payload = requests[-1]
                if path == '/health':
                    value = {'ok': fault != 'health', 'launchId': 'fixture-launch'}
                elif path == '/api/v1/system/config':
                    value = {'dataDir': str(self.home / ('wrong-data' if fault == 'data' else '.bb'))}
                    api.verified = True
                else:
                    value = api.request(method, path, payload)
                raw = json.dumps(value).encode()
                return types.SimpleNamespace(status=200, getheader=lambda _: None, read=lambda _: raw)
            return types.SimpleNamespace(sock=types.SimpleNamespace(getsockname=lambda: ('127.0.0.1', 49999)),
                connect=lambda: None, request=request, getresponse=response, close=lambda: None)
        with patch.object(P.http.client, 'HTTPConnection', side_effect=connection):
            yield requests

    def run_policy(self, api=None, policy='ready', native_api=False):
        output = io.StringIO()
        apis = iter(api) if isinstance(api, list) else None
        api_class = P.NativeApi
        with patch.object(P.sys, 'argv', ['fixture', str(self.home), policy]), \
                patch.dict(P.os.environ, {}, clear=True), \
                patch.object(P, 'Processes', return_value=self.proc), \
                patch.object(P, 'NativeApi', side_effect=lambda *args: api_class(*args) if native_api else
                             next(apis) if apis is not None else api), \
                patch.object(P.signal, 'signal'), patch.object(P.signal, 'alarm'), \
                patch.object(P.os, 'chmod', side_effect=AssertionError('permission mutation forbidden')), \
                patch.object(P.os, 'chown', side_effect=AssertionError('ownership mutation forbidden')), \
                contextlib.redirect_stdout(output):
            status = P.run()
        return status, output.getvalue()

    def test_writable_state_reports_controlled_refusal_without_permission_repair(self):
        data = self.data()
        data.chmod(0o775)
        before = data.stat(), (data / 'bb.db').read_bytes()
        status, output = self.run_policy()
        self.assertEqual(status, 1)
        self.assertEqual(output, 'BB_PLUGIN_REFRESH failed discovery writable-local-state\n')
        self.assertEqual((data.stat(), (data / 'bb.db').read_bytes()), before)
        result = run_wrapper(output, status)
        self.assertEqual(result.returncode, 1)
        self.assertIn('BB plugin refresh failed: discovery / writable-local-state.', result.stdout)
        self.assertNotIn(str(self.home), result.stdout + result.stderr)
        self.assertNotIn('secret-sentinel', result.stdout + result.stderr)

    def test_changed_local_evidence_survives_file_close_failure(self):
        data = self.data()
        original = (data / 'bb.db').read_bytes()
        native_stat, native_close = os.fstat, os.close
        def changed(fd):
            fields = ('st_dev', 'st_ino', 'st_uid', 'st_gid', 'st_mode', 'st_size',
                      'st_mtime_ns', 'st_ctime_ns', 'st_nlink')
            info = native_stat(fd)
            result = types.SimpleNamespace(**{key: getattr(info, key) for key in fields})
            result.st_ino += 1
            return result
        def close(fd):
            native_close(fd)
            raise RuntimeError('close-secret-path-sentinel')
        with patch.object(P.os, 'fstat', side_effect=changed), patch.object(P.os, 'close', side_effect=close):
            status, output = self.run_policy()
        self.assertEqual(status, 1)
        self.assertEqual(output, 'BB_PLUGIN_REFRESH failed discovery changed-local-state\n')
        self.assertEqual((data / 'bb.db').read_bytes(), original)

    def test_source_failure_survives_later_update_success_safe_mode_and_verification_failure(self):
        self.server()
        for later in ('updated', 'safe-mode', 'verification-failure'):
            with self.subTest(later=later):
                api = FakeApi([plugin('first'), plugin('second')],
                              {'first': 'unavailable', 'second': 'update-available'})
                if later == 'safe-mode':
                    api.results['second'] = P.Refusal('safe-mode')
                if later == 'verification-failure':
                    api.after_update = lambda _: api.plugins['second'].update(source='npm:secret-path-sentinel')
                status, output = self.run_policy(api)
                self.assertEqual(status, 1)
                self.assertIn('BB_PLUGIN_REFRESH failed update-check source-unavailable\n', output)
                self.assertEqual(output.count('BB_PLUGIN_REFRESH failed'), 1)
                if later != 'verification-failure':
                    self.assertIn('BB_PLUGIN_REFRESH ' + later, output)
                self.assertNotIn('sentinel', output)
                self.assertEqual(len(api.mutations()), 1)
                result = run_wrapper(output, status)
                self.assertEqual(result.returncode, 1)
                self.assertIn('update-check / source-unavailable', result.stdout)
                self.assertNotIn('sentinel', result.stdout + result.stderr)

    def test_native_failures_identify_the_operation_without_response_or_exception_text(self):
        self.server()
        cases = (
            ('identity', 'identity', 'unverified-main-server'),
            ('inventory', 'inventory', 'malformed-result'),
            ('source', 'source-check', 'unverified-source-intent'),
            ('check', 'update-check', 'malformed-result'),
            ('rolled-back', 'update', 'rolled-back'),
            ('timeout', 'update', 'operation-timeout'),
            ('unknown-refusal', 'update', 'unknown-failure'),
            ('unknown-exception', 'update', 'unknown-failure'),
            ('current', 'verification', 'update-unverified'),
            ('activation', 'verification', 'activation-unverified'),
            ('final-unavailable', 'verification', 'source-unavailable'),
        )
        for case, operation, reason in cases:
            with self.subTest(case=case):
                api = FakeApi()
                native = api.request
                def request(method, path, payload=None):
                    if case == 'inventory' and path == '/api/v1/plugins':
                        return {'plugins': 'secret-path-sentinel'}
                    if case == 'source' and path.endswith('/source'):
                        return {'requested': '/secret-path-sentinel'}
                    if case == 'check' and path.endswith('/updates/check'):
                        return {'results': [{'secret': 'secret-path-sentinel'}]}
                    return native(method, path, payload)
                api.request = request
                if case == 'identity':
                    api.verify = lambda: P.need(False, 'unverified-main-server')
                if case in ('rolled-back', 'current'):
                    api.results['tracking'] = case
                if case == 'timeout':
                    api.results['tracking'] = P.Refusal('operation-timeout')
                if case == 'unknown-refusal':
                    api.results['tracking'] = P.Refusal('safe-mode\n/secret-path-sentinel')
                if case == 'unknown-exception':
                    api.results['tracking'] = RuntimeError('/secret-path-sentinel')
                if case == 'activation':
                    api.after_update = lambda _: api.plugins['tracking'].update(status='secret-path-sentinel')
                if case == 'final-unavailable':
                    api.after_update = lambda _: api.outcomes.update(tracking='unavailable')
                status, output = self.run_policy(api)
                self.assertEqual(status, 1)
                self.assertIn(f'BB_PLUGIN_REFRESH failed {operation} {reason}\n', output)
                self.assertNotIn('sentinel', output)
                self.assertLess(len(output), 200)
                result = run_wrapper(output, status)
                self.assertEqual(result.returncode, 1)
                self.assertIn(f'{operation} / {reason}.', result.stdout)
                self.assertNotIn('sentinel', result.stdout + result.stderr)

    def test_later_server_deferral_cannot_erase_an_earlier_server_failure(self):
        self.server()
        self.server(101, self.home / 'second', '39002')
        first, second = FakeApi(), FakeApi()
        first.results['tracking'] = P.Refusal('operation-timeout')
        second.safe = True
        status, output = self.run_policy([first, second])
        self.assertEqual(status, 1)
        self.assertIn('BB_PLUGIN_REFRESH failed update operation-timeout\n', output)
        self.assertIn('BB_PLUGIN_REFRESH safe-mode\n', output)
        self.assertFalse(second.mutations())

    def test_darwin_observed_signed_uid_inventory_and_minimized_row_allow_discovery(self):
        # Observed PID/UID bytes, with successful native status and no stderr.
        # Keep the real command validator, table parser, discovery and policy.
        for uid in ('-2', '4294967294'):
            for pids in ((53750, 53752), (53750,)):
                with self.subTest(uid=uid, pids=pids):
                    with patch.object(P.sys, 'platform', 'darwin'):
                        self.proc = P.Processes(os.getuid())
                    def native(args, **_kwargs):
                        self.assertEqual(args, ['/bin/ps', '-axo', 'uid=,pid='])
                        return types.SimpleNamespace(returncode=0, stderr=b'',
                            stdout=''.join(f'{uid} {pid}\n' for pid in pids).encode('ascii'))
                    with patch.object(P.subprocess, 'run', side_effect=native), \
                            patch.object(P.ctypes, 'CDLL', side_effect=AssertionError('foreign environment read')):
                        self.assertEqual(self.run_policy(), (0, 'BB_PLUGIN_REFRESH absent\n'))

    def test_darwin_malformed_uid_pid_or_row_is_refused_before_account_selection(self):
        bad_uids = (b'-2147483649', b'4294967296', b'-1', b'4294967295', b'unknown',
                    b'--2', b'+2', b'2-', b'-0', b'1.0', b'1e3', b'0x2', b'1_000',
                    b'999999999999999999999', '٢'.encode(), '−2'.encode(), b'\xff')
        bad_pids = (b'-2', b'-1', b'2147483648', b'4294967294', b'--2', b'+2',
                    b'2-', b'1.0', b'1e3', b'0x2', b'999999999999999999999', '٢'.encode())
        rows = [uid + b' 53750\n' for uid in bad_uids]
        rows += [b'4294967294 ' + pid + b'\n' for pid in bad_pids]
        rows += [b'\n', b'4294967294\n', b'4294967294 53750 extra\n']
        self.server()
        for row in rows:
            for tail in (b'', f'{os.getuid()} 100\n'.encode()):
                with self.subTest(row=row, account_candidate=bool(tail)):
                    with self.darwin_inventory(row + tail) as native:
                        self.assertEqual(self.run_policy(FakeApi()),
                            (1, 'BB_PLUGIN_REFRESH failed discovery process-proof-unavailable\n'))
                    self.assertEqual(native.private_reads, [])

    def test_darwin_mixed_inventory_updates_only_verified_account_server_and_preserves_intent(self):
        data = self.server()
        # A foreign row may even name the same BB entry; it is not a candidate
        # and its environment must never be inspected to decide that.
        self.records[53750] = self.records[100]
        self.records[53752] = self.records[100]
        before = (data / 'bb.db').read_bytes(), (self.package / 'package.json').read_bytes()
        account = f'{os.getuid()} 100\n'.encode()
        for foreign in (b'-2', b'4294967294'):
            unrelated = (b'0 0\n0 1\n' + foreign + b' 53750\n' + foreign + b' 53752\n'
                         b'-2147483648 123\n2147483647 2147483647\n4294967293 234\n')
            for table in (unrelated + account, account + unrelated, unrelated[:8] + account + unrelated[8:]):
                with self.subTest(foreign=foreign, table=table):
                    rows = [plugin('disabled', enabled=False), plugin('pin', 'npm:fixture@1.0.0'),
                            plugin('local', 'path:/inert/development')]
                    api = FakeApi(rows, {'disabled': 'update-available', 'pin': 'pinned', 'local': 'pinned'})
                    preserved = copy.deepcopy(api.plugins)
                    with self.darwin_inventory(table) as native, self.darwin_http(api) as requests:
                        self.assertEqual(self.run_policy(native_api=True), (0, 'BB_PLUGIN_REFRESH updated\n'))
                    self.assertTrue(native.private_reads)
                    self.assertEqual(set(native.private_reads), {100})
                    self.assertEqual(api.plugins['pin'], preserved['pin'])
                    self.assertEqual(api.plugins['local'], preserved['local'])
                    self.assertEqual(api.plugins['disabled']['status'], 'disabled')
                    self.assertFalse(api.plugins['disabled']['enabled'])
                    self.assertEqual(api.plugins['disabled']['source'], preserved['disabled']['source'])
                    self.assertEqual(len(api.mutations()), 1)
                    self.assertEqual(requests[:2], [('GET', '/health', None), ('GET', '/api/v1/system/config', None)])
                    self.assertEqual(((data / 'bb.db').read_bytes(), (self.package / 'package.json').read_bytes()), before)

    def test_darwin_signed_inventory_retains_stopped_safe_mode_readiness_and_prior_failure(self):
        self.server()
        foreign = b'-2 53750\n-2 53752\n'
        account = f'{os.getuid()} 100\n'.encode()
        cases = (('stopped', foreign, 'ready'), ('safe-mode', foreign + account, 'ready'),
                 ('readiness', foreign + account, 'block-default'), ('failure-then-safe', foreign + account, 'ready'))
        for case, table, policy in cases:
            with self.subTest(case=case):
                api = FakeApi([plugin('first'), plugin('second')],
                              {'first': 'unavailable', 'second': 'update-available'})
                api.safe = case == 'safe-mode'
                if case == 'failure-then-safe':
                    api.results['second'] = P.Refusal('safe-mode')
                with self.darwin_inventory(table) as native, self.darwin_http(api) as requests:
                    status, output = self.run_policy(policy=policy, native_api=True)
                if case == 'failure-then-safe':
                    self.assertEqual((status, output), (1, 'BB_PLUGIN_REFRESH safe-mode\n'
                                     'BB_PLUGIN_REFRESH failed update-check source-unavailable\n'))
                else:
                    expected = 'readiness-deferred\nBB_PLUGIN_REFRESH absent' if case == 'readiness' else case
                    self.assertEqual((status, output), (0, f'BB_PLUGIN_REFRESH {expected}\n'))
                    self.assertFalse(api.mutations())
                if case in ('stopped', 'readiness'):
                    self.assertFalse(requests)
                self.assertTrue(set(native.private_reads) <= {100})

    def test_darwin_native_contract_socket_and_health_proof_still_gate_plugin_requests(self):
        self.server()
        table = b'-2 53750\n' + f'{os.getuid()} 100\n'.encode()
        manifest = self.package / 'package.json'
        original = manifest.read_bytes()
        for fault in ('contract', 'peer', 'health', 'data'):
            with self.subTest(fault=fault):
                api = FakeApi()
                manifest.write_bytes(original)
                if fault == 'contract':
                    metadata = json.loads(original)
                    metadata['version'] = '0.45.0'
                    manifest.write_text(json.dumps(metadata))
                with self.darwin_inventory(table) as native, self.darwin_http(api, fault) as requests, \
                        patch.object(P.time, 'monotonic', side_effect=range(1000)), patch.object(P.time, 'sleep'):
                    native.peer = fault != 'peer'
                    status, output = self.run_policy(native_api=True)
                expected = {'contract': 'discovery unsupported-native-contract', 'peer': 'identity unverified-peer',
                            'health': 'identity unverified-main-server', 'data': 'identity unverified-main-server'}[fault]
                self.assertEqual((status, output), (1, 'BB_PLUGIN_REFRESH failed ' + expected + '\n'))
                self.assertFalse(api.calls)
                self.assertFalse(any('/plugins' in path for _, path, _ in requests))
                self.assertTrue(set(native.private_reads) <= {100})
        manifest.write_bytes(original)

    def test_darwin_pid_reuse_and_changed_evidence_refuse_before_plugin_operations(self):
        self.server()
        table = b'-2 53750\n' + f'{os.getuid()} 100\n'.encode()
        original = copy.deepcopy(self.records[100])
        for changed in ('stamp', 'argv', 'environment', 'uid', 'package'):
            for at_read in (2, 3, 4):
                with self.subTest(changed=changed, at_read=at_read):
                    self.records[100] = copy.deepcopy(original)
                    manifest = self.package / 'package.json'
                    package_before = manifest.read_bytes()
                    api = FakeApi()
                    count = 0
                    with self.darwin_inventory(table) as native, self.darwin_http(api) as requests:
                        def change(args):
                            nonlocal count
                            if args[:2] != ['/bin/ps', '-p']:
                                return
                            count += 1
                            if count != at_read:
                                return
                            argv, env, stamp = self.records[100]
                            if changed == 'stamp':
                                stamp = b'reused-pid'
                            elif changed == 'argv':
                                argv = ['/inert/different-node', argv[1]]
                            elif changed == 'environment':
                                env['BB_SERVER_LAUNCH_ID'] = 'changed-launch'
                            elif changed == 'uid':
                                native.uids[100] = '-2'
                            else:
                                manifest.write_text('{}')
                            self.records[100] = argv, env, stamp
                        native.on_query = change
                        status, output = self.run_policy(native_api=True)
                    expected = 'foreign-process' if changed == 'uid' else (
                        'changed-local-state' if changed == 'package' else 'changed-process')
                    self.assertEqual((status, output), (1, f'BB_PLUGIN_REFRESH failed identity {expected}\n'))
                    self.assertFalse(api.calls)
                    self.assertFalse(any('/plugins' in path for _, path, _ in requests))
                    self.assertTrue(set(native.private_reads) <= {100})
                    manifest.write_bytes(package_before)

    def test_native_process_failures_do_not_disclose_subprocess_output(self):
        self.proc.table = lambda: P.command(['/bin/ps', '-axo', 'uid=,pid='])
        with patch.object(P.subprocess, 'run', return_value=types.SimpleNamespace(
                returncode=1, stdout=b'secret-path-sentinel', stderr=b'secret-path-sentinel')):
            status, output = self.run_policy()
        self.assertEqual((status, output), (1, 'BB_PLUGIN_REFRESH failed discovery process-proof-unavailable\n'))
        with patch.object(P.subprocess, 'run', side_effect=subprocess.TimeoutExpired(
                '/secret-path-sentinel', 10, output=b'secret-path-sentinel')):
            status, output = self.run_policy()
        self.assertEqual((status, output), (1, 'BB_PLUGIN_REFRESH failed discovery operation-timeout\n'))

    def test_absent_prepared_and_enrolled_only_have_no_main_server(self):
        for marker in ('.local/share/setup-bb-machine', '.bb-machines/remote', '.bb'):
            (self.home / marker).mkdir(parents=True, exist_ok=True)
        with patch.dict(os.environ, {'BB_CLI': '/must/not/execute', 'BB_SERVER_URL': 'https://remote.invalid'}):
            self.assertEqual(P.discover(self.files(), self.proc), ([], 0))
        self.records[100] = (['node', '/inert/host-daemon/dist/daemon-bundle.mjs'], {}, b'1')
        self.assertEqual(P.discover(self.files(), self.proc), ([], 0))

    def test_stopped_and_moved_server_data_never_become_live_targets(self):
        data = self.data()
        self.assertEqual(P.discover(self.files(), self.proc), ([], 1))
        self.assertEqual(self.run_policy(), (0, 'BB_PLUGIN_REFRESH stopped\n'))
        self.assertEqual(self.run_policy(policy='block-default'),
                         (0, 'BB_PLUGIN_REFRESH readiness-deferred\nBB_PLUGIN_REFRESH absent\n'))
        self.proc.database_open = lambda _: True
        with self.assertRaises(P.Refusal):
            P.discover(self.files(), self.proc)
        self.proc.database_open = lambda _: False
        moved = data / 'server-moved.json'
        moved.write_text('{}')
        with self.assertRaises(P.Refusal):
            P.discover(self.files(), self.proc)
        moved.write_text(json.dumps({'version': 1, 'moveId': 'fixture', 'movedAt': 1,
                                     'fromHostId': 'old', 'toHostId': 'new', 'toHostName': 'remote',
                                     'serverUrl': 'https://remote.invalid', 'mode': 'direct',
                                     'connectHandle': None, 'oldCopyEntries': []}))
        self.assertEqual(P.discover(self.files(), self.proc), ([], 0))

    def test_manual_desktop_alias_and_custom_data_are_deduplicated(self):
        data = self.server(data=self.home / 'custom/data')
        servers, stopped = P.discover(self.files(), self.proc, str(data))
        self.assertEqual((len(servers), stopped), (1, 0))
        self.assertEqual(servers[0]['data'], data)
        self.assertEqual(servers[0]['port'], 39001)
        self.server(101, self.home / '.bb', '39002')
        self.assertEqual(len(P.discover(self.files(), self.proc, str(data))[0]), 2)

    def test_readiness_failure_excludes_only_managed_default_data(self):
        self.server()
        self.server(101, self.home / 'manual', '39002')
        servers, stopped = P.discover(self.files(), self.proc, block_default=True)
        self.assertEqual(([s['pid'] for s in servers], stopped), ([101], 0))

    def test_ambiguous_foreign_changed_and_linked_evidence_fails_closed(self):
        data = self.server()
        self.records[101] = self.records[100]
        with self.assertRaises(P.Refusal):
            P.discover(self.files(), self.proc)
        del self.records[101]
        with patch.object(self.proc, 'read', side_effect=P.Refusal('foreign-process')):
            with self.assertRaises(P.Refusal):
                P.discover(self.files(), self.proc)
        self.records[100][1]['HOME'] = str(self.root)  # same UID, custom HOME is not foreign
        self.assertEqual(len(P.discover(self.files(), self.proc)[0]), 1)
        (data / 'bb.db').unlink()
        (data / 'bb.db').symlink_to(self.entry)
        with self.assertRaises(P.Refusal):
            P.discover(self.files(), self.proc)
        (data / 'bb.db').unlink()
        self.data(data)
        files = self.files()
        P.discover(files, self.proc)
        (self.package / 'package.json').write_text('{}')
        with self.assertRaises(P.Refusal):
            P.discover(files, self.proc)

    def test_unrelated_server_entries_are_ignored_but_unknown_bb_contract_is_not(self):
        entry = self.home / 'unrelated/server/dist/index.js'
        entry.parent.mkdir(parents=True)
        entry.write_text('never execute')
        (entry.parents[2] / 'package.json').write_text('{"name":"unrelated"}')
        self.records[200] = (['node', '--some-node-option', str(entry)], {}, b'1')
        self.assertEqual(P.discover(self.files(), self.proc), ([], 0))
        self.server()
        manifest = self.package / 'package.json'
        metadata = json.loads(manifest.read_text())
        metadata['version'] = '0.45.0'
        manifest.write_text(json.dumps(metadata))
        with self.assertRaisesRegex(P.Refusal, 'unsupported-native-contract'):
            P.discover(self.files(), self.proc)
        self.assertEqual(self.run_policy(), (1, 'BB_PLUGIN_REFRESH failed discovery unsupported-native-contract\n'))

    def test_live_launcher_without_verified_main_is_not_called_stopped(self):
        data = self.data()
        self.records[100] = (['node', str(self.package / 'dist/bb-app.js')], {}, b'12345')
        (data / 'bb-app-runtime.json').write_text('{"pid":100}')
        with self.assertRaises(P.Refusal):
            P.discover(self.files(), self.proc)

    def test_transport_and_cleanup_failures_keep_the_original_diagnostic(self):
        self.server()
        for failure, expected in (('http', 'native-request-failed'),
                                  ('json', 'malformed-result'),
                                  ('timeout', 'operation-timeout'),
                                  ('connection', 'native-request-failed'),
                                  ('close-only', 'unknown-failure')):
            with self.subTest(failure=failure):
                files = self.files()
                server = P.discover(files, self.proc)[0][0]
                api = P.NativeApi(files, self.proc, server, P.time.monotonic() + 10)
                def close():
                    raise RuntimeError('cleanup-secret-path-sentinel')
                def connect():
                    if failure == 'timeout':
                        raise TimeoutError('timeout-secret-path-sentinel')
                    if failure == 'connection':
                        raise ConnectionRefusedError('connection-secret-path-sentinel')
                response = types.SimpleNamespace(status=503 if failure == 'http' else 200,
                    getheader=lambda _: None, read=lambda _: b'secret-path-sentinel' if failure == 'json' else b'{"error":"secret-path-sentinel"}')
                connection = types.SimpleNamespace(sock=types.SimpleNamespace(getsockname=lambda: ('127.0.0.1', 49999)),
                    connect=connect, request=lambda *_: None, getresponse=lambda: response, close=close)
                with patch.object(P.http.client, 'HTTPConnection', return_value=connection):
                    status, output = self.run_policy(api)
                self.assertEqual(status, 1)
                self.assertEqual(output, f'BB_PLUGIN_REFRESH failed identity {expected}\n')
                self.assertNotIn('sentinel', output)

    def test_safe_mode_is_not_an_original_failure_that_can_hide_a_close_error(self):
        self.server()
        for close_fails in (False, True):
            with self.subTest(close_fails=close_fails):
                files = self.files()
                server = P.discover(files, self.proc)[0][0]
                native_api = P.NativeApi(files, self.proc, server, P.time.monotonic() + 10)
                api = FakeApi()
                fake_request = api.request
                api.request = lambda method, path, payload=None: (
                    native_api.request(method, path, payload) if path.endswith('/update')
                    else fake_request(method, path, payload))
                def close():
                    if close_fails:
                        raise RuntimeError('cleanup-secret-path-sentinel')
                response = types.SimpleNamespace(status=422, getheader=lambda _: None,
                    read=lambda _: json.dumps({'error': 'plugin safe mode is on; turn it off with `bb plugin safe-mode off` before you update "tracking"'}).encode())
                connection = types.SimpleNamespace(sock=types.SimpleNamespace(getsockname=lambda: ('127.0.0.1', 49999)),
                    connect=lambda: None, request=lambda *_: None, getresponse=lambda: response, close=close)
                with patch.object(P.http.client, 'HTTPConnection', return_value=connection):
                    status, output = self.run_policy(api)
                self.assertEqual(status, int(close_fails))
                self.assertEqual(output, 'BB_PLUGIN_REFRESH failed update unknown-failure\n' if close_fails
                                 else 'BB_PLUGIN_REFRESH safe-mode\n')

    def test_peer_proof_precedes_every_request_no_cli_proxy_redirect_or_reconnect(self):
        self.server()
        files = self.files()
        server = P.discover(files, self.proc)[0][0]
        events = []
        response = types.SimpleNamespace(status=200, getheader=lambda _: None, read=lambda _: b'{"ok":true}')
        connection = types.SimpleNamespace(sock=types.SimpleNamespace(getsockname=lambda: ('127.0.0.1', 49999)),
                                            connect=lambda: events.append('connect'),
                                            request=lambda *args: events.append(('request', args)),
                                            getresponse=lambda: response, close=lambda: events.append('close'))
        def proof(*args):
            events.append(('proof', args))
            return True
        self.proc.peer_owned = proof
        with patch.object(P.http.client, 'HTTPConnection', return_value=connection) as create:
            api = P.NativeApi(files, self.proc, server, P.time.monotonic() + 10)
            self.assertEqual(api.request('GET', '/health'), {'ok': True})
            self.assertEqual(connection.auto_open, 0)
            self.assertEqual(create.call_args.args, ('127.0.0.1', 39001))
            self.assertEqual(events[0], 'connect')
            self.assertEqual(events[1][0], 'proof')
            self.assertEqual(events[2][0], 'request')
            events.clear()
            self.proc.peer_owned = lambda *_: False
            with patch.object(P.time, 'monotonic', side_effect=range(50)), patch.object(P.time, 'sleep'):
                with self.assertRaisesRegex(P.Refusal, 'unverified-peer'):
                    P.NativeApi(files, self.proc, server, 100).request('POST', '/api/v1/plugins/id/update', {})
            self.assertFalse(any(isinstance(e, tuple) and e[0] == 'request' for e in events))
            self.proc.peer_owned = proof
            response.status = 302
            with self.assertRaisesRegex(P.Refusal, 'native-request-failed'):
                api.request('GET', '/health')


class NativeEvidence(unittest.TestCase):
    def test_darwin_account_signed_and_unsigned_identity_is_equivalent_at_both_queries(self):
        records = {99: (['/inert/node', '/inert/bb-app/server/dist/index.js'],
                        {'HOME': '/inert', 'SECRET': 'must-not-escape'}, b'Thu Oct 1 00:00:00 2026')}
        cases = ((1234, ('1234',)), (2147483647, ('2147483647',)),
                 (2147483648, ('-2147483648', '2147483648')),
                 (4294967294, ('-2', '4294967294')))
        for account, forms in cases:
            for inventory in forms:
                for identity in forms:
                    with self.subTest(account=account, inventory=inventory, identity=identity):
                        with patch.object(P.sys, 'platform', 'darwin'):
                            processes = P.Processes(account)
                        native = DarwinInputs(f'{inventory} 99\n'.encode(), records, {99: identity})
                        with native.installed():
                            self.assertEqual(processes.table(), [99])
                            self.assertEqual(processes.read(99),
                                (records[99][0], {'HOME': '/inert'}, 'Thu Oct 1 00:00:00 2026'))
                        self.assertEqual(native.private_reads, [99])

    def test_darwin_foreign_and_malformed_per_process_uids_never_read_private_environment(self):
        records = {99: (['/inert/node', '/inert/bb-app/server/dist/index.js'], {}, b'start')}
        foreign = ((2, '-2'), (2, '4294967294'), (4294967294, '-2147483648'),
                   (1234, '0'), (1234, '-2'), (1234, '4294967294'))
        for account, uid in foreign:
            with self.subTest(account=account, uid=uid):
                with patch.object(P.sys, 'platform', 'darwin'):
                    processes = P.Processes(account)
                native = DarwinInputs(f'{uid} 99\n'.encode(), records, {99: uid})
                with native.installed():
                    self.assertEqual(processes.table(), [])
                    with self.assertRaisesRegex(P.Refusal, '^foreign-process$'):
                        processes.read(99)
                self.assertEqual(native.private_reads, [])
        malformed = (b'-1', b'4294967295', b'-2147483649', b'4294967296', b'unknown',
                     b'--2', b'+2', b'2-', b'-0', b'1.0', b'1e3', b'0x2', b'1_000',
                     b'999999999999999999999', '٢'.encode(), '−2'.encode(), b'\xff')
        with patch.object(P.sys, 'platform', 'darwin'):
            processes = P.Processes(1234)
        for raw in [uid + b' start\n' for uid in malformed] + [b'1234\n', b'\n']:
            with self.subTest(raw=raw), patch.object(P.subprocess, 'run', return_value=types.SimpleNamespace(
                    returncode=0, stdout=raw, stderr=b'')), \
                    patch.object(P.ctypes, 'CDLL', side_effect=AssertionError('private environment read')):
                with self.assertRaisesRegex(P.Refusal, '^process-proof-unavailable$'):
                    processes.read(99)

    def test_linux_inventory_keeps_unsigned_interpretation_and_darwin_pid_edges_are_distinct(self):
        for account in (0, 1234, 2147483648, 4294967294, 4294967295):
            with self.subTest(account=account), patch.object(P.sys, 'platform', 'linux'):
                processes = P.Processes(account)
                for text in (f'{account} 99\n', '-2 99\n'):
                    with DarwinInputs(text.encode(), {}).installed():
                        if text.startswith('-'):
                            with self.assertRaisesRegex(P.Refusal, '^process-proof-unavailable$'):
                                processes.table()
                        else:
                            self.assertEqual(processes.table(), [99])
        with patch.object(P.sys, 'platform', 'darwin'):
            processes = P.Processes(1234)
        with DarwinInputs(b'0 0\n1234 1\n1234 2147483647\n', {}).installed():
            self.assertEqual(processes.table(), [1, 2147483647])

    def test_linux_foreign_uid_and_reused_pid_are_rejected_before_requests(self):
        with patch.object(P.sys, 'platform', 'linux'):
            processes = P.Processes(1234)
        with patch.object(P.Path, 'stat', return_value=types.SimpleNamespace(st_uid=999)), \
                patch.object(P, 'bounded_read', side_effect=AssertionError('must reject UID before reading')):
            with self.assertRaisesRegex(P.Refusal, 'foreign-process'):
                processes.read(99)
        stamps = iter((b'old', b'new'))
        def read(path, _limit):
            if str(path).endswith('/stat'):
                return b'99 (node) ' + b' '.join([b'S'] + [b'0'] * 18 + [next(stamps)])
            if str(path).endswith('/cmdline'):
                return b'/inert/node\0/inert/bb-app/server/dist/index.js\0'
            if str(path).endswith('/environ'):
                return b'HOME=/inert\0'
            raise AssertionError('unexpected native read')
        with patch.object(P.Path, 'stat', return_value=types.SimpleNamespace(st_uid=1234)), \
                patch.object(P, 'bounded_read', side_effect=read):
            with self.assertRaisesRegex(P.Refusal, 'changed-process'):
                processes.read(99)

    def test_linux_accepted_socket_is_matched_to_the_server_fd(self):
        with patch.object(P.sys, 'platform', 'linux'):
            processes = P.Processes(1234)
        table = b'header\n 0: 0100007F:9859 0100007F:C34F 01 0:0 0:0 0 1234 0 777\n'
        reads = lambda path, *args: table if str(path).endswith('/tcp') else b'header\n'
        with patch.object(P, 'bounded_read', side_effect=reads), \
                patch.object(P.Path, 'iterdir', return_value=iter([Path('/inert/fd/1')])), \
                patch.object(P.os, 'readlink', return_value='socket:[777]'):
            self.assertTrue(processes.peer_owned(999, 39001, 49999))
        with patch.object(P, 'bounded_read', side_effect=reads), \
                patch.object(P.Path, 'iterdir', return_value=iter([Path('/inert/fd/1')])), \
                patch.object(P.os, 'readlink', return_value='socket:[888]'):
            self.assertFalse(processes.peer_owned(999, 39001, 49999))

    def test_macos_procargs_preserves_spaces_and_filters_secrets_without_execution(self):
        argv = [b'/Applications/bb.app/Contents/MacOS/bb', b'/inert space/server/dist/index.js']
        env = [b'HOME=/inert home', b'BB_DATA_DIR=/inert home/custom data', b'BB_SERVER_PORT=39001', b'SECRET=must-not-escape']
        raw = (2).to_bytes(4, P.sys.byteorder) + argv[0] + b'\0\0' + b'\0'.join(argv + env) + b'\0'
        def sysctl(_mib, _length, buffer, size, _new, _new_length):
            P.ctypes.memmove(buffer, raw, len(raw))
            size._obj.value = len(raw)
            return 0
        with patch.object(P.sys, 'platform', 'darwin'):
            processes = P.Processes(1234)
        with patch.object(P, 'command', return_value=b'1234 Thu Oct 1 00:00:00 2026'), \
                patch.object(P.ctypes, 'CDLL', return_value=types.SimpleNamespace(sysctl=sysctl)):
            args, selected, _ = processes.read(99)
        self.assertEqual(args, [a.decode() for a in argv])
        self.assertEqual(selected, {'HOME': '/inert home', 'BB_DATA_DIR': '/inert home/custom data', 'BB_SERVER_PORT': '39001'})
        with patch.object(P, 'command', return_value=b''):
            self.assertIsNone(processes.read(99))
        with patch.object(P, 'command', return_value=b'p99\nn127.0.0.1:39001->127.0.0.1:49999\nTST=ESTABLISHED\n'):
            self.assertTrue(processes.peer_owned(99, 39001, 49999))
            self.assertFalse(processes.peer_owned(100, 39001, 49999))


class Callers(unittest.TestCase):
    def test_ubuntu_selection_readiness_and_preparation_failures_keep_boundaries(self):
        source = EXTRACT.definitions((ROOT / 'ubuntu.sh').read_text())
        caller = re.search(r'^run_setup_tasks\(\) \{\n.*?^\}', source, re.M | re.S).group()
        start = caller.index('    if [[ "${_bb_selection_status}" -eq 0 ]]; then')
        end = caller.index('    if ! prepare_pi_profile_permissions; then', start)
        seam = caller[start:end]
        cases = [
            # selection, platform failure, server failure, prep failure, earlier, expected refresh
            (0, 0, 0, 0, 0, 'ready'), (0, 0, 1, 0, 0, 'block-default'),
            (0, 1, 0, 0, 0, None), (1, 0, 0, 0, 0, 'ready'),
            (1, 0, 0, 1, 0, 'ready'), (1, 0, 0, 0, 1, 'ready'),
            (2, 0, 0, 0, 1, None),
        ]
        for selection, platform, server, prep, earlier, refresh in cases:
            code = '''
print_error() { :; }
bb_server_platform_ready() { return "$PLATFORM_FAIL"; }
setup_bb_server() { echo normal-startup; return "$SERVER_FAIL"; }
setup_bb_machine() { echo preparation; return "$PREP_FAIL"; }
refresh_bb_plugins() { echo "refresh:$1"; }
run_fixture() {
local _bb_selection_status=$SELECTION _setup_had_errors=$EARLIER
''' + seam + '''
echo unrelated-and-finalization
return "$_setup_had_errors"
}
run_fixture
'''
            with tempfile.TemporaryDirectory(prefix='bb-refresh-ubuntu-seam-') as home:
                env = {'HOME': home, 'PATH': '/usr/bin:/bin', 'SELECTION': str(selection),
                       'PLATFORM_FAIL': str(platform), 'SERVER_FAIL': str(server),
                       'PREP_FAIL': str(prep), 'EARLIER': str(earlier)}
                result = subprocess.run(['/bin/bash', '-c', code], env=env, cwd=home,
                                        stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=5)
            self.assertEqual(result.returncode, int(bool(platform or server or prep or earlier)), result.stderr)
            self.assertIn('unrelated-and-finalization', result.stdout)
            self.assertEqual('refresh:' in result.stdout, refresh is not None)
            if refresh is not None:
                self.assertIn('refresh:' + refresh, result.stdout)
            if selection == 0 and platform == 0:
                self.assertLess(result.stdout.index('normal-startup'), result.stdout.index('refresh:'))

    def test_shared_embedding_windows_boundary_and_real_failure_aggregation(self):
        wrapper = (ROOT / 'lib/bb-plugin-refresh.bash').read_text().replace('@@PYTHON@@', (ROOT / 'lib/bb-plugin-refresh.py').read_text().rstrip()).rstrip()
        for script in SCRIPTS:
            source = (ROOT / (script + '.sh')).read_text()
            block = source.split('# BEGIN BB PLUGIN REFRESH\n', 1)[1].split('\n# END BB PLUGIN REFRESH', 1)[0]
            self.assertEqual(block, wrapper)
            selected = EXTRACT.definitions(source)
            main = re.search(r'^run_setup_tasks\(\) \{\n.*?^\}', selected, re.M | re.S).group()
            outer = re.search(r'^main\(\) \{\n.*?^\}', selected, re.M | re.S).group()
            names = re.findall(r'^([A-Za-z_][A-Za-z_0-9]*)\(\) \{', selected, re.M)
            refresh = re.search(r'^refresh_bb_plugins\(\) \{\n.*?^\}', selected, re.M | re.S).group()
            stubs = '\n'.join(f'{name}() {{ :; }}' for name in names if name not in ('main', 'run_setup_tasks', 'refresh_bb_plugins'))
            with tempfile.TemporaryDirectory(prefix='bb-refresh-caller-') as temp:
                home = Path(temp) / 'home'
                home.mkdir()
                code = stubs + '\n' + main + '\n' + outer + '\n' + refresh + '''
bb_plugin_refresh_payload() { printf '%s\\n' "$FIXTURE_OUTPUT"; echo stderr-secret-path-sentinel >&2; return "$REFRESH_STATUS"; }
setup_bb_machine() { return "$EARLIER"; }
print_error() { printf '%s\\n' "$1"; }
print_warning() { printf '%s\\n' "$1"; }
print_message() { printf '%s\\n' "$1"; }
prepare_pi_profile_permissions() { echo unrelated; return 0; }
refresh_pi_packages() { echo later-pi-success; }
start_setup_log() { echo logging; }
finish_setup_log() { echo "finalized:$1"; return "$1"; }
setup_load_environment() { :; }
setup_dotfiles_access() { :; }
determine_dotfiles_access() { :; }
check_dotfiles_access() { return 1; }
setup_dotfiles_deploy_key() { return 1; }
is_main_user() { return 0; }
bb_server_selection() { return 1; }
whoami() { echo fixture; }
brew() { :; }
unzip() { :; }
macos_developer_tools_ready_for() { return 0; }
macos_existing_prerequisites() { return 0; }
MACOS_DEVELOPER_TOOLS_STATE=ready
MACOS_CLT_OPERATION_FAILED=0
DOTFILES_ACCESS_METHOD=none
'''
                for cmd in ('systemctl', 'launchctl', 'loginctl', 'pgrep', 'ps', 'curl', 'npm',
                            'bun', 'pi', 'bb', 'chezmoi', 'sudo', 'kill', 'pkill', 'tailscale'):
                    code += f'\n{cmd}() {{ echo FORBIDDEN:{cmd}; return 99; }}'
                code += '\nmain\n'
                # Only real caller + refresh wrapper execute. The payload and
                # every unrelated helper are inert before intentional invocation.
                cases = [('BB_PLUGIN_REFRESH checked', 0, 0, 0),
                         ('BB_PLUGIN_REFRESH stopped', 0, 0, 0),
                         ('BB_PLUGIN_REFRESH safe-mode', 0, 0, 0),
                         ('BB_PLUGIN_REFRESH failed discovery writable-local-state', 0, 0, 1),
                         ('BB_PLUGIN_REFRESH checked', 1, 0, 1),
                         ('secret-path-sentinel', 0, 0, 1),
                         ('BB_PLUGIN_REFRESH checked', 0, 1, 1),
                         ('BB_PLUGIN_REFRESH safe-mode', 0, 1, 1)]
                for text, status, earlier, expected in cases:
                    env = {'HOME': str(home), 'PATH': '/usr/bin:/bin', 'REFRESH_STATUS': str(status),
                           'EARLIER': str(earlier), 'FIXTURE_OUTPUT': text,
                           'USER': 'fixture', 'LANG': 'C', 'TERM': 'dumb'}
                    result = subprocess.run(['/bin/bash', '-c', code], env=env, cwd=home,
                                            stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=15)
                    with self.subTest(script=script, text=text, earlier=earlier, status=status):
                        self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
                        self.assertIn('logging', result.stdout)
                        self.assertIn('unrelated', result.stdout)
                        self.assertIn('later-pi-success', result.stdout)
                        self.assertIn(f'finalized:{expected}', result.stdout)
                        self.assertLess(result.stdout.index('unrelated'), result.stdout.index('finalized:'))
                        if text.startswith('BB_PLUGIN_REFRESH failed discovery'):
                            self.assertIn('discovery / writable-local-state.', result.stdout)
                        if text == 'secret-path-sentinel':
                            self.assertIn('helper-result / unverified-result.', result.stdout)
                        self.assertNotIn('FORBIDDEN:', result.stdout + result.stderr)
                        self.assertNotIn('sentinel', result.stdout + result.stderr)
        self.assertNotIn('refresh_bb_plugins', (ROOT / 'win.ps1').read_text())

    def test_wrapper_rejects_unknown_diagnostics_with_a_bounded_controlled_fallback(self):
        refused = ('', 'secret-path-sentinel',
                   'BB_PLUGIN_REFRESH failed secret-path-sentinel writable-local-state',
                   'BB_PLUGIN_REFRESH failed discovery secret-path-sentinel',
                   'BB_PLUGIN_REFRESH failed discovery writable-local-state /secret-path-sentinel',
                   'BB_PLUGIN_REFRESH failed discovery writable-local-state\rsecret-path-sentinel',
                   'BB_PLUGIN_REFRESH failed discovery writable-local-state\nsecret-path-sentinel',
                   'BB_PLUGIN_REFRESH checked\n' * 700)
        for text, status in [(text, 0) for text in refused] + [('BB_PLUGIN_REFRESH checked', 1)]:
            with self.subTest(text=text[:90], status=status):
                result = run_wrapper(text, status)
                self.assertEqual(result.returncode, 1)
                self.assertIn('helper-result / unverified-result.', result.stdout)
                self.assertNotIn('sentinel', result.stdout + result.stderr)
                self.assertLess(len(result.stdout + result.stderr), 500)
                if text.startswith('BB_PLUGIN_REFRESH failed discovery writable-local-state\n'):
                    self.assertIn('discovery / writable-local-state.', result.stdout)

    def test_wrapper_suppresses_uncontrolled_output_and_retains_status(self):
        source = (ROOT / 'lib/bb-plugin-refresh.bash').read_text().split('\nbb_plugin_refresh_payload()', 1)[0]
        for text, status, expected in [('BB_PLUGIN_REFRESH checked', 0, 0),
                                       ('BB_PLUGIN_REFRESH updated', 1, 1),
                                       ('BB_PLUGIN_REFRESH safe-mode', 0, 0),
                                       ('BB_PLUGIN_REFRESH stopped', 0, 0),
                                       ('BB_PLUGIN_REFRESH failed', 0, 1),
                                       ('raw-secret-sentinel', 0, 1)]:
            code = source + '\n' + '\n'.join(f'{name}() {{ printf "%s\\n" "$1"; }}' for name in
                                              ('print_section', 'print_message', 'print_error', 'print_warning', 'print_debug'))
            code += '\nbb_plugin_refresh_payload() { printf "%s\\n" "$FIXTURE_OUTPUT"; return "$FIXTURE_STATUS"; }\nrefresh_bb_plugins\n'
            with tempfile.TemporaryDirectory(prefix='bb-refresh-wrapper-') as home:
                result = subprocess.run(['/bin/bash', '-c', code], cwd=home,
                                        env={'HOME': home, 'PATH': '/usr/bin:/bin', 'FIXTURE_OUTPUT': text, 'FIXTURE_STATUS': str(status)},
                                        stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=5)
            self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
            self.assertNotIn('raw-secret-sentinel', result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main(verbosity=2)
