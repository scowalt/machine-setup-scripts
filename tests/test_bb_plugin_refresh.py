#!/usr/bin/env python3
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
    constants = {'MAX_BYTES', 'MAX_PROCESSES'}

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
        assert self.verified and (method, path) == ('GET', '/api/v1/plugins/safe-mode')
        self.calls.append((method, path, payload))
        return {'enabled': self.safe}

    def update(self):
        for identity, row in self.plugins.items():
            if self.outcomes[identity] != 'update-available':
                continue
            self.calls.append(('POST', '/api/v1/plugins/' + identity + '/update', {}))
            result = self.results.get(identity, 'updated')
            if isinstance(result, Exception):
                raise result
            if result == 'updated':
                row['version'] = '1.1.0'
                self.outcomes[identity] = 'current'
            self.after_update(identity)

    def mutations(self):
        return [call for call in self.calls if call[1].endswith('/update')]


class DarwinInputs:
    def __init__(self, table, records, uids=None):
        self.table = table
        self.records = records
        self.uids = uids or {}
        self.identity_rows = {}
        self.private_reads = []
        self.argmax = 1048576
        self.argmax_status = 0
        self.argmax_width = P.ctypes.sizeof(P.ctypes.c_int)
        self.argmax_reads = 0
        self.procargs_capacities = []
        self.procargs_error = 0
        self.procargs_length = None
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
                raw = self.identity_rows.get(pid, f'{self.uids.get(pid, os.getuid())} {stamp}\n'.encode('ascii'))
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

    def sysctlbyname(self, name, value, size, new, new_length):
        assert (name, size._obj.value, new, new_length) == (b'kern.argmax', P.ctypes.sizeof(P.ctypes.c_int), None, 0)
        self.argmax_reads += 1
        value._obj.value = self.argmax
        size._obj.value = self.argmax_width
        return self.argmax_status

    def sysctl(self, mib, length, buffer, size, new, new_length):
        assert (mib[0], mib[1], length, new, new_length) == (1, 49, 3, None, 0)
        pid = mib[2]
        self.private_reads.append(pid)
        capacity = size._obj.value
        assert P.ctypes.sizeof(buffer) == capacity
        self.procargs_capacities.append(capacity)
        if capacity - P.ctypes.sizeof(P.ctypes.c_int) > self.argmax:
            P.ctypes.set_errno(22)
            return -1
        if self.procargs_error:
            P.ctypes.set_errno(self.procargs_error)
            return -1
        argv, env, _ = self.records[pid]
        values = [arg.encode() for arg in argv] + [f'{key}={value}'.encode() for key, value in env.items()]
        raw = len(argv).to_bytes(4, P.sys.byteorder) + argv[0].encode() + b'\0\0' + b'\0'.join(values) + b'\0'
        if len(raw) > capacity:
            P.ctypes.set_errno(12)
            return -1
        P.ctypes.memmove(buffer, raw, len(raw))
        size._obj.value = len(raw) if self.procargs_length is None else self.procargs_length
        return 0

    @contextlib.contextmanager
    def installed(self):
        with patch.object(P.subprocess, 'run', side_effect=self.command), \
                patch.object(P.ctypes, 'CDLL', return_value=types.SimpleNamespace(sysctl=self.sysctl, sysctlbyname=self.sysctlbyname)), \
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

    def test_native_cli_owns_plugin_selection_and_zero_exit_outcomes(self):
        for outcome in ('current', 'pinned', 'incompatible', 'unavailable', 'update-available'):
            api = FakeApi(outcomes={'tracking': outcome})
            api.results['tracking'] = 'rolled-back'
            with self.subTest(outcome=outcome), patch.object(api, 'update', wraps=api.update) as update:
                self.assertEqual(P.refresh(api), 'completed')
                update.assert_called_once_with()
                self.assertEqual([c for c in api.calls if c[0] == 'GET'],
                                 [('GET', '/api/v1/plugins/safe-mode', None)])

    def test_safe_mode_defers_without_executing_cli(self):
        api = FakeApi()
        api.safe = True
        with patch.object(api, 'update', side_effect=AssertionError('CLI forbidden')):
            self.assertEqual(P.refresh(api), 'safe-mode')
        self.assertEqual(len(api.calls), 1)

    def test_malformed_identity_json_and_safe_mode_fail_before_cli(self):
        for raw in ('{"ok":true,"ok":false}', '{', '{"x":NaN}'):
            with self.assertRaises(P.Refusal):
                P.object_json(raw)
        for shape in (None, {}, {'enabled': 'false'}):
            api = FakeApi()
            api.request = lambda *_: shape
            with patch.object(api, 'update', side_effect=AssertionError('CLI forbidden')), self.assertRaises(P.Refusal):
                P.refresh(api)


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
        (self.root / 'node').write_text('inert node fixture; never execute')
        cli = self.package / 'host-daemon/dist/bb'
        cli.parent.mkdir(parents=True)
        cli.write_text('throw Error("fixture must not execute BB");\n')
        (cli.parent / 'bb-chunks').mkdir()
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
                              'BB_SERVER_PORT': port, 'BB_SERVER_LAUNCH_ID': 'fixture-launch'}, b'Thu Oct  1 00:00:00 2026')
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
    def darwin_http(self, api, fault=None, data=None):
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
                    value = {'dataDir': str(self.home / 'wrong-data' if fault == 'data' else data or self.home / '.bb')}
                    api.verified = True
                else:
                    value = api.request(method, path, payload)
                raw = json.dumps(value).encode()
                return types.SimpleNamespace(status=200, getheader=lambda _: None, read=lambda _: raw)
            return types.SimpleNamespace(sock=types.SimpleNamespace(getsockname=lambda: ('127.0.0.1', 49999)),
                connect=lambda: None, request=request, getresponse=response, close=lambda: None)
        native_run = P.subprocess.run
        def execute(args, **kwargs):
            if args[2:] == ['plugin', 'update', '--all', '--yes']:
                self.assertEqual(args[:2], [str(self.root / 'node'), str(self.package / 'host-daemon/dist/bb')])
                self.assertEqual(kwargs['env']['BB_SERVER_URL'], 'http://127.0.0.1:39001')
                api.update()
                return types.SimpleNamespace(returncode=0)
            return native_run(args, **kwargs)
        with patch.object(P.http.client, 'HTTPConnection', side_effect=connection), \
                patch.object(P.subprocess, 'run', side_effect=execute):
            yield requests

    def run_policy(self, api=None, policy='ready', native_api=False, environment=None):
        output = io.StringIO()
        apis = iter(api) if isinstance(api, list) else None
        api_class = P.NativeApi
        with patch.object(P.sys, 'argv', ['fixture', str(self.home), policy]), \
                patch.dict(P.os.environ, environment or {}, clear=True), \
                patch.object(P, 'Processes', return_value=self.proc), \
                patch.object(P, 'NativeApi', side_effect=lambda *args: api_class(*args) if native_api else
                             next(apis) if apis is not None else api), \
                patch.object(P.signal, 'signal'), patch.object(P.signal, 'alarm'), \
                patch.object(P.os, 'chmod', side_effect=AssertionError('permission mutation forbidden')), \
                patch.object(P.os, 'chown', side_effect=AssertionError('ownership mutation forbidden')), \
                contextlib.redirect_stdout(output):
            status = P.run()
        return status, output.getvalue()

    def captured_non_server(self, daemon=True, enrolled=True, mode=0o775):
        self.home.chmod(0o750)
        data = self.home / '.bb'
        data.mkdir(mode=mode)
        data.chmod(mode)
        if enrolled:
            enrollment = self.home / '.bb-machines'
            enrollment.mkdir(mode=0o775)
            enrollment.chmod(0o775)
            (enrollment / 'fixture-enrollment').write_text('remote-selection-secret-sentinel')
        if daemon:
            self.records[32106] = (['node', str(self.home / '.bb-machines/host-daemon/dist/index.js')], {}, b'1')
        return data

    def test_native_cli_uses_verified_package_node_and_explicit_local_selection_for_any_version(self):
        self.server()
        manifest = self.package / 'package.json'
        for version in ('0.44.0', '0.45.0', '0.99.17'):
            metadata = json.loads(manifest.read_text())
            metadata['version'] = version
            manifest.write_text(json.dumps(metadata))
            files = self.files()
            server = P.discover(files, self.proc)[0][0]
            api = P.NativeApi(files, self.proc, server, P.time.monotonic() + 10)
            with self.subTest(version=version), \
                    patch.dict(P.os.environ, {'BB_CLI': '/forbidden/override', 'BB_SERVER_URL': 'https://remote.invalid',
                        'NODE_OPTIONS': '--import=/forbidden/module', 'HTTP_PROXY': 'http://proxy.invalid',
                        'BB_THREAD_ID': 'unrelated-thread'}, clear=True), \
                    patch.object(P.subprocess, 'run', return_value=types.SimpleNamespace(returncode=0,
                        stdout=b'rolled-back unavailable secret-sentinel', stderr=b'secret-sentinel')) as native:
                api.update()
            args, kwargs = native.call_args
            self.assertEqual(args[0], [str(self.root / 'node'), str(self.package / 'host-daemon/dist/bb'),
                                      'plugin', 'update', '--all', '--yes'])
            self.assertEqual(kwargs['env'], {'HOME': str(self.home), 'PATH': str(self.root) + ':/usr/bin:/bin',
                'BB_DATA_DIR': str(self.home / '.bb'), 'BB_SERVER_URL': 'http://127.0.0.1:39001',
                'BB_CLI_REEXEC': '1', 'ELECTRON_RUN_AS_NODE': '1', 'NO_COLOR': '1', 'NODE_ENV': 'production',
                'BB_APP_VERSION': version})
            self.assertEqual(kwargs['cwd'], self.home / '.bb')
            self.assertEqual((kwargs['stdin'], kwargs['stdout'], kwargs['stderr']), (subprocess.DEVNULL,) * 3)
            self.assertTrue(kwargs['close_fds'])
            self.assertGreater(kwargs['timeout'], 0)
            self.assertLessEqual(kwargs['timeout'], 10)
            native.assert_called_once()

    def test_native_cli_failures_and_timeouts_are_controlled_and_aggregate(self):
        self.server()
        for error, reason in ((None, 'native-command-failed'),
                              (subprocess.TimeoutExpired('inert-command', 1, output=b'secret-sentinel'), 'operation-timeout'),
                              (OSError('secret-sentinel'), 'unknown-failure')):
            files = self.files()
            server = P.discover(files, self.proc)[0][0]
            api = P.NativeApi(files, self.proc, server, P.time.monotonic() + 10)
            with self.subTest(reason=reason), patch.object(api, 'verify'), \
                    patch.object(api, 'request', return_value={'enabled': False}), \
                    patch.object(P.subprocess, 'run', side_effect=error,
                        return_value=types.SimpleNamespace(returncode=1, stdout=b'secret-sentinel', stderr=b'secret-sentinel')):
                status, output = self.run_policy(api)
            self.assertEqual((status, output), (1, f'BB_PLUGIN_REFRESH failed update {reason}\n'))

    def test_unsafe_or_changed_cli_and_process_never_execute_native_command(self):
        self.server()
        cli = self.package / 'host-daemon/dist/bb'
        for case in ('link', 'empty', 'writable', 'changed-process', 'changed-cli'):
            cli.unlink(missing_ok=True)
            cli.write_text('inert CLI')
            cli.chmod(0o600)
            files = self.files()
            server = P.discover(files, self.proc)[0][0]
            api = P.NativeApi(files, self.proc, server, P.time.monotonic() + 10)
            if case == 'link':
                cli.unlink()
                cli.symlink_to(self.entry)
            elif case == 'empty':
                cli.write_text('')
            elif case == 'writable':
                cli.chmod(0o660)
            elif case == 'changed-cli':
                files.inspect(cli)
                cli.write_text('changed inert CLI')
            with self.subTest(case=case), patch.object(P.subprocess, 'run', side_effect=AssertionError('CLI forbidden')):
                if case == 'changed-process':
                    with patch.object(self.proc, 'read', return_value=None), self.assertRaises(P.Refusal):
                        api.update()
                else:
                    with self.assertRaises(P.Refusal):
                        api.update()

    def test_account_owned_data_package_and_ancestors_refresh_without_permission_repairs(self):
        for selection in ('default', 'explicit-default', 'custom', 'custom-outside-home'):
            selected = self.root / 'manual/data' if selection == 'custom-outside-home' else (
                self.home / 'custom/data' if selection == 'custom' else None)
            data = self.server(data=selected)
            paths = [self.root, self.home, self.home / '.bb', data, *self.entry.parents[:6]]
            if selection.startswith('custom'):
                paths.append(data.parent)
            environment = {} if selection == 'default' else {'BB_DATA_DIR': str(data)}
            if selection.startswith('custom'):
                (self.home / '.bb/bb.db').unlink(missing_ok=True)
            for mode in (0o700, 0o755, 0o775, 0o2775):
                for path in paths:
                    path.chmod(mode)
                before = {path: path.stat() for path in paths}
                database = (data / 'bb.db').read_bytes()
                api = FakeApi([plugin(enabled=False)])
                with self.subTest(selection=selection, mode=oct(mode)), \
                        patch.object(P.subprocess, 'run', side_effect=AssertionError('external proof forbidden')), \
                        patch.object(P.os, 'getgroups', side_effect=AssertionError('group proof forbidden')), \
                        patch.object(P.os, 'getgrouplist', side_effect=AssertionError('initgroups proof forbidden')), \
                        patch.object(P.os, 'listxattr', side_effect=AssertionError('ACL proof forbidden')), \
                        self.darwin_http(api, data=data) as requests:
                    self.assertEqual(self.run_policy(native_api=True, environment=environment),
                                     (0, 'BB_PLUGIN_REFRESH completed\n'))
                    self.assertEqual(self.run_policy(native_api=True, environment=environment),
                                     (0, 'BB_PLUGIN_REFRESH completed\n'))
                    self.assertEqual(api.mutations(), [('POST', '/api/v1/plugins/tracking/update', {})])
                    self.assertTrue(set((method, path) for method, path, _ in requests) <= {
                        ('GET', '/health'), ('GET', '/api/v1/system/config'),
                        ('GET', '/api/v1/plugins/safe-mode'), ('GET', '/api/v1/plugins'),
                        ('GET', '/api/v1/plugins/tracking/source'),
                        ('POST', '/api/v1/plugins/updates/check'), ('POST', '/api/v1/plugins/tracking/update')})
                    self.assertFalse(api.plugins['tracking']['enabled'])
                    self.assertEqual(api.plugins['tracking']['source'], 'npm:fixture@^1')
                    self.assertEqual({path: path.stat() for path in paths}, before)
                    self.assertEqual((data / 'bb.db').read_bytes(), database)

    def test_group_writable_custom_and_default_absence_is_metadata_only_and_preserves_state(self):
        data = self.captured_non_server()
        custom = self.home / 'custom/data'
        custom.mkdir(parents=True)
        for path in (self.root, self.home, data, custom.parent, custom):
            path.chmod(0o2775)
        self.proc.table = lambda: [32106, 999]
        for selected in (None, str(data), str(custom)):
            before = {path: path.lstat() for path in (self.root, self.home, data, custom.parent, custom)}
            env = {'BB_CLI': '/must/not/execute', 'BB_SERVER_URL': 'https://remote.invalid'}
            if selected:
                env['BB_DATA_DIR'] = selected
            with self.subTest(selected=selected), \
                    patch.object(P.subprocess, 'run', side_effect=AssertionError('external proof forbidden')), \
                    patch.object(P.os, 'getgroups', side_effect=AssertionError('group proof forbidden')), \
                    patch.object(P.os, 'getgrouplist', side_effect=AssertionError('initgroups proof forbidden')), \
                    patch.object(P.os, 'listxattr', side_effect=AssertionError('ACL proof forbidden')), \
                    patch.object(P.http.client, 'HTTPConnection', side_effect=AssertionError('request forbidden')) as requests:
                self.assertEqual(self.run_policy(native_api=True, environment=env), (0, 'BB_PLUGIN_REFRESH absent\n'))
            self.assertFalse(requests.called)
            self.assertEqual({path: path.lstat() for path in before}, before)

    def test_captured_execution_machine_is_absent_without_requests_or_state_changes(self):
        self.captured_non_server()
        paths = [self.home, *sorted(self.home.rglob('*'))]
        before = [(path.read_bytes() if path.is_file() else None, path.lstat()) for path in paths]
        with patch.object(P.subprocess, 'run', side_effect=AssertionError('execution forbidden')), \
                patch.object(P.http.client, 'HTTPConnection', side_effect=AssertionError('request forbidden')) as requests:
            status, output = self.run_policy(native_api=True)
        self.assertEqual((status, output), (0, 'BB_PLUGIN_REFRESH absent\n'))
        self.assertEqual(requests.call_count, 0)
        self.assertEqual([(path.read_bytes() if path.is_file() else None, path.lstat()) for path in paths], before)
        result = run_wrapper(output, status)
        self.assertEqual(result.returncode, 0)
        self.assertIn('No verified local BB main server requires plugin refresh.', result.stdout)

    def test_prepared_unenrolled_private_and_explicit_default_controls(self):
        for daemon, enrolled, mode in ((False, True, 0o775), (True, False, 0o775),
                                      (False, False, 0o775), (True, True, 0o700)):
            with self.subTest(daemon=daemon, enrolled=enrolled, mode=oct(mode)):
                self.captured_non_server(daemon, enrolled, mode)
                for environment in ({}, {'BB_DATA_DIR': str(self.home / '.bb')},
                                    {'BB_CLI': 'secret-sentinel', 'BB_SERVER_URL': 'https://remote.invalid'}):
                    api = FakeApi()
                    self.assertEqual(self.run_policy(api, environment=environment), (0, 'BB_PLUGIN_REFRESH absent\n'))
                    self.assertFalse(api.verified)
                    self.assertFalse(api.calls)
                (self.home / '.bb').rmdir()
                if enrolled:
                    (self.home / '.bb-machines/fixture-enrollment').unlink()
                    (self.home / '.bb-machines').rmdir()
                self.records.clear()
        self.assertEqual(self.run_policy(), (0, 'BB_PLUGIN_REFRESH absent\n'))

    def test_unsafe_directories_links_and_types_still_refuse_negative_classification(self):
        data = self.captured_non_server()
        custom = self.home / 'custom'
        for path, mode in ((data, 0o777), (self.home, 0o772), (self.root, 0o772)):
            previous = path.stat().st_mode & 0o777
            path.chmod(mode)
            with self.subTest(path=path):
                self.assertEqual(self.run_policy(), (1, 'BB_PLUGIN_REFRESH failed discovery writable-local-state\n'))
            path.chmod(previous)
        data.rmdir()
        for target in (custom, self.package):
            data.symlink_to(target)
            self.assertEqual(self.run_policy(), (1, 'BB_PLUGIN_REFRESH failed discovery unverified-local-state\n'))
            data.unlink()
        data.write_text('not a directory')
        self.assertEqual(self.run_policy(), (1, 'BB_PLUGIN_REFRESH failed discovery unverified-local-state\n'))
        data.unlink()
        parent = self.home / 'linked'
        parent.symlink_to(self.package)
        self.assertEqual(self.run_policy(environment={'BB_DATA_DIR': str(parent / 'child')}),
                         (1, 'BB_PLUGIN_REFRESH failed discovery unverified-local-state\n'))
        parent.unlink()
        parent.write_text('not a directory')
        self.assertEqual(self.run_policy(environment={'BB_DATA_DIR': str(parent / 'child')}),
                         (1, 'BB_PLUGIN_REFRESH failed discovery unverified-local-state\n'))

    def test_metadata_probe_refuses_foreign_ownership_without_descending(self):
        data = self.captured_non_server()
        native_stat, native_open = os.stat, os.open
        for target, uid in ((data, 0), (data, os.getuid() + 1), (self.root, os.getuid() + 1)):
            expected = native_stat(target)
            def metadata(path, *args, **kwargs):
                info = native_stat(path, *args, **kwargs)
                actual = native_stat(target)
                if (info.st_dev, info.st_ino) == (actual.st_dev, actual.st_ino):
                    info = types.SimpleNamespace(st_mode=info.st_mode, st_uid=uid)
                return info
            def open_path(path, *args, **kwargs):
                info = native_stat(path, dir_fd=kwargs.get('dir_fd'), follow_symlinks=False)
                self.assertNotEqual((info.st_dev, info.st_ino), (expected.st_dev, expected.st_ino),
                                    'foreign directory must not be opened')
                return native_open(path, *args, **kwargs)
            with self.subTest(target=target, uid=uid), patch.object(P.os, 'stat', side_effect=metadata), \
                    patch.object(P.os, 'open', side_effect=open_path):
                self.assertEqual(self.run_policy(), (1, 'BB_PLUGIN_REFRESH failed discovery foreign-local-state\n'))

    def test_marker_probe_is_metadata_only_nofollow_and_never_interprets_missing_io_errors(self):
        data = self.captured_non_server()
        native_stat, native_open = os.stat, os.open
        names = ('bb.db', 'bb.db-wal', 'bb.db-shm', 'bb.db-journal',
                 'bb-app-runtime.json', 'server-moved.json', 'server-import.json')
        def open_directory(path, flags, *args, **kwargs):
            self.assertTrue(flags & os.O_DIRECTORY)
            self.assertTrue(flags & os.O_NOFOLLOW)
            return native_open(path, flags, *args, **kwargs)
        for name in names:
            for error in (PermissionError('secret-sentinel'), NotADirectoryError('secret-sentinel'),
                          OSError('secret-sentinel'), NotImplementedError('secret-sentinel')):
                def metadata(path, *args, **kwargs):
                    if str(path) in names:
                        self.assertIsNotNone(kwargs.get('dir_fd'))
                        self.assertIs(kwargs.get('follow_symlinks'), False)
                        if str(path) == name:
                            raise error
                    return native_stat(path, *args, **kwargs)
                with self.subTest(name=name, error=type(error).__name__), \
                        patch.object(P.os, 'stat', side_effect=metadata), \
                        patch.object(P.os, 'open', side_effect=open_directory):
                    self.assertEqual(self.run_policy(), (1, 'BB_PLUGIN_REFRESH failed discovery unverified-local-state\n'))
        for name in names:
            marker = data / name
            marker.symlink_to(self.package / 'package.json')
            with patch.object(P.os, 'open', side_effect=open_directory):
                self.assertEqual(self.run_policy(), (1, 'BB_PLUGIN_REFRESH failed discovery unverified-local-state\n'))
            marker.unlink()

    def test_mixed_execution_machine_and_verified_custom_server_refresh_only_local_main(self):
        default = self.captured_non_server()
        custom = self.server(data=self.home / 'manual')
        before = default.stat(), (custom / 'bb.db').read_bytes()
        for daemon in (False, True):
            if not daemon:
                record = self.records.pop(32106)
            else:
                self.records[32106] = record
            rows = [plugin('disabled', enabled=False), plugin('pin', 'npm:fixture@1.0.0'),
                    plugin('local', 'path:/inert/development')]
            api = FakeApi(rows, {'disabled': 'update-available', 'pin': 'pinned', 'local': 'pinned'})
            preserved = copy.deepcopy(api.plugins)
            with self.subTest(daemon=daemon), self.darwin_http(api, data=custom) as requests:
                self.assertEqual(self.run_policy(native_api=True, environment={'BB_DATA_DIR': str(custom)}),
                                 (0, 'BB_PLUGIN_REFRESH completed\n'))
            self.assertEqual(requests[:2], [('GET', '/health', None), ('GET', '/api/v1/system/config', None)])
            self.assertEqual(api.plugins['pin'], preserved['pin'])
            self.assertEqual(api.plugins['local'], preserved['local'])
            self.assertEqual(api.plugins['disabled']['status'], 'disabled')
            self.assertFalse(api.plugins['disabled']['enabled'])
            self.assertEqual(api.plugins['disabled']['source'], preserved['disabled']['source'])
            self.assertEqual(len(api.mutations()), 1)
        self.assertEqual((default.stat(), (custom / 'bb.db').read_bytes()), before)
        custom.chmod(0o775)
        with self.darwin_http(FakeApi(), data=custom):
            self.assertEqual(self.run_policy(native_api=True), (0, 'BB_PLUGIN_REFRESH completed\n'))

    @contextlib.contextmanager
    def database_activity(self, data, kind):
        database = data / 'bb.db'
        directory_activity = kind in ('directory', 'opening-directory')
        target = data / ('active-log' if directory_activity else kind)
        if kind != 'bb.db' and not directory_activity:
            target.write_bytes(b'inert sidecar')
        native_stat = os.stat
        identity = native_stat(data if kind == 'opening-directory' else database)
        writes = []
        def metadata(path, *args, **kwargs):
            info = native_stat(path, *args, **kwargs)
            if (info.st_dev, info.st_ino) == (identity.st_dev, identity.st_ino):
                with target.open('ab') as stream:
                    stream.write(b'inert activity')
                if directory_activity:
                    target.unlink()
                writes.append(kind)
            return info
        with patch.object(P.os, 'stat', side_effect=metadata):
            yield writes

    def test_verified_live_database_activity_does_not_require_negative_snapshot_stability(self):
        data = self.server()
        database = data / 'bb.db'
        original = database.stat()
        for kind in ('bb.db', 'bb.db-wal', 'bb.db-shm', 'directory'):
            with self.subTest(kind=kind):
                api = FakeApi([plugin(enabled=False)])
                with self.database_activity(data, kind) as writes, self.darwin_http(api) as requests:
                    result = self.run_policy(native_api=True)
                self.assertTrue(writes, 'synthetic database activity must occur in red and green')
                self.assertEqual(result, (0, 'BB_PLUGIN_REFRESH completed\n'))
                self.assertEqual(requests[:2], [('GET', '/health', None), ('GET', '/api/v1/system/config', None)])
                self.assertEqual(len(api.mutations()), 1)
                self.assertFalse(api.plugins['tracking']['enabled'])
                self.assertEqual(api.plugins['tracking']['source'], 'npm:fixture@^1')
                current = database.stat()
                self.assertEqual((current.st_dev, current.st_ino, current.st_uid, current.st_gid, current.st_mode),
                                 (original.st_dev, original.st_ino, original.st_uid, original.st_gid, original.st_mode))
                self.assertEqual(database.read_bytes()[:16], b'SQLite format 3\0')

    def test_verified_live_server_does_not_require_directory_read_access(self):
        data = self.server()
        native_open = os.open
        def open_path(path, flags, *args, **kwargs):
            if flags & os.O_DIRECTORY:
                raise PermissionError('directory-open-secret-sentinel')
            return native_open(path, flags, *args, **kwargs)
        api = FakeApi()
        with patch.object(P.os, 'open', side_effect=open_path), self.darwin_http(api) as requests:
            result = self.run_policy(native_api=True)
        self.assertEqual(result, (0, 'BB_PLUGIN_REFRESH completed\n'))
        self.assertEqual(len(api.mutations()), 1)
        self.assertEqual(requests[:2], [('GET', '/health', None), ('GET', '/api/v1/system/config', None)])
        self.assertEqual((data / 'bb.db').read_bytes()[:16], b'SQLite format 3\0')

    def test_positive_probe_retains_database_identity_ownership_permissions_links_and_header_guards(self):
        data = self.data()
        database = data / 'bb.db'
        native_stat = os.stat
        original = native_stat(database)
        fields = ('st_dev', 'st_ino', 'st_uid', 'st_gid', 'st_mode', 'st_size',
                  'st_mtime_ns', 'st_ctime_ns', 'st_nlink')
        for fault in ('st_ino', 'st_uid', 'st_gid', 'st_mode', 'st_nlink', 'header'):
            self.data(data)
            observed = False
            def metadata(path, *args, **kwargs):
                nonlocal observed
                info = native_stat(path, *args, **kwargs)
                if (info.st_dev, info.st_ino) == (original.st_dev, original.st_ino):
                    if fault == 'header':
                        database.write_bytes(b'invalid header')
                    elif observed:
                        info = types.SimpleNamespace(**{key: getattr(info, key) for key in fields})
                        setattr(info, fault, getattr(info, fault) + 1)
                    observed = True
                return info
            with self.subTest(fault=fault), patch.object(P.os, 'stat', side_effect=metadata):
                api = FakeApi()
                result = self.run_policy(api)
            self.assertTrue(observed)
            self.assertEqual(result, (1, 'BB_PLUGIN_REFRESH failed discovery ' +
                ('unverified-main-server' if fault == 'header' else 'changed-local-state') + '\n'))
            self.assertFalse(api.verified)
            self.assertFalse(api.calls)

    def test_root_owned_group_writable_ancestor_cannot_authorize_absence(self):
        self.captured_non_server()
        self.root.chmod(0o775)
        original, native_stat = self.root.stat(), os.stat
        def metadata(path, *args, **kwargs):
            info = native_stat(path, *args, **kwargs)
            if (info.st_dev, info.st_ino) == (original.st_dev, original.st_ino):
                return types.SimpleNamespace(st_mode=info.st_mode, st_uid=0)
            return info
        with patch.object(P.os, 'stat', side_effect=metadata):
            self.assertEqual(self.run_policy(), (1, 'BB_PLUGIN_REFRESH failed discovery writable-local-state\n'))

    def test_read_only_root_owned_package_directory_remains_supported(self):
        self.server()
        self.package.chmod(0o755)
        original, native_stat = self.package.stat(), os.stat
        def metadata(path, *args, **kwargs):
            info = native_stat(path, *args, **kwargs)
            if (info.st_dev, info.st_ino) == (original.st_dev, original.st_ino):
                fields = ('st_dev', 'st_ino', 'st_uid', 'st_gid', 'st_mode', 'st_size',
                          'st_mtime_ns', 'st_ctime_ns', 'st_nlink')
                info = types.SimpleNamespace(**{name: getattr(info, name) for name in fields})
                info.st_uid = 0
            return info
        with patch.object(P.os, 'stat', side_effect=metadata), self.darwin_http(FakeApi()):
            self.assertEqual(self.run_policy(native_api=True), (0, 'BB_PLUGIN_REFRESH completed\n'))

    def test_refresh_revalidates_accepted_directory_metadata_before_each_request(self):
        data = self.server()
        for path in (self.home, data, self.package):
            path.chmod(0o775)
        native_stat = os.stat
        fields = ('st_dev', 'st_ino', 'st_uid', 'st_gid', 'st_mode', 'st_size',
                  'st_mtime_ns', 'st_ctime_ns', 'st_nlink')
        for target in (self.home, data, self.package):
            original = native_stat(target)
            for field in ('st_dev', 'st_ino', 'st_uid', 'st_gid', 'st_mode'):
                requests = []
                def metadata(path, *args, **kwargs):
                    info = native_stat(path, *args, **kwargs)
                    if requests and (info.st_dev, info.st_ino) == (original.st_dev, original.st_ino):
                        info = types.SimpleNamespace(**{name: getattr(info, name) for name in fields})
                        setattr(info, field, (info.st_mode & ~0o005) if field == 'st_mode' else getattr(info, field) + 1)
                    return info
                with self.subTest(target=target, field=field), \
                        self.darwin_http(FakeApi()) as requests, patch.object(P.os, 'stat', side_effect=metadata):
                    status, output = self.run_policy(native_api=True)
                self.assertEqual(status, 1, output)
                self.assertIn('failed identity ', output)
                self.assertEqual(requests, [('GET', '/health', None)])

    def test_positive_directory_acceptance_keeps_system_file_and_type_refusals(self):
        data = self.server()
        for path in (self.home, data, self.package):
            path.chmod(0o775)
        native_stat = os.stat
        fields = ('st_dev', 'st_ino', 'st_uid', 'st_gid', 'st_mode', 'st_size',
                  'st_mtime_ns', 'st_ctime_ns', 'st_nlink')
        cases = [(self.package, field, value) for field, value in (
            ('st_uid', 0), ('st_uid', os.getuid() + 1), ('st_mode', P.stat.S_IFDIR | 0o777),
            ('st_mode', P.stat.S_IFLNK | 0o775), ('st_mode', P.stat.S_IFREG | 0o644))]
        cases += [(target, field, value) for target in (data / 'bb.db', self.package / 'package.json', self.entry)
                  for field, value in (('st_mode', P.stat.S_IFREG | 0o660), ('st_nlink', 2),
                                       ('st_mode', P.stat.S_IFLNK | 0o600))]
        for target, field, value in cases:
            original = native_stat(target)
            def metadata(path, *args, **kwargs):
                info = native_stat(path, *args, **kwargs)
                if (info.st_dev, info.st_ino) == (original.st_dev, original.st_ino):
                    info = types.SimpleNamespace(**{name: getattr(info, name) for name in fields})
                    setattr(info, field, value)
                return info
            with self.subTest(target=target, field=field, value=value), \
                    patch.object(P.os, 'stat', side_effect=metadata), self.darwin_http(FakeApi()) as requests:
                status, output = self.run_policy(native_api=True)
            self.assertEqual(status, 1, output)
            self.assertNotIn('absent', output)
            self.assertFalse(requests)

    def test_live_deduplication_retains_strict_directory_revalidation(self):
        data = self.server()
        native_stat = os.stat
        original = native_stat(data)
        fields = ('st_dev', 'st_ino', 'st_uid', 'st_gid', 'st_mode', 'st_size',
                  'st_mtime_ns', 'st_ctime_ns', 'st_nlink')
        for fault in ('st_ino', 'st_uid', 'st_gid', 'st_mode'):
            changed = False
            def metadata(path, *args, **kwargs):
                nonlocal changed
                try:
                    info = native_stat(path, *args, **kwargs)
                except FileNotFoundError:
                    if Path(path) == data / 'server-import.json':
                        changed = True
                    raise
                if changed and (info.st_dev, info.st_ino) == (original.st_dev, original.st_ino):
                    info = types.SimpleNamespace(**{key: getattr(info, key) for key in fields})
                    setattr(info, fault, getattr(info, fault) + (0o020 if fault == 'st_mode' else 1))
                return info
            with self.subTest(fault=fault), patch.object(P.os, 'stat', side_effect=metadata), \
                    self.darwin_http(FakeApi()) as requests:
                status, output = self.run_policy(native_api=True)
            self.assertTrue(changed)
            self.assertEqual(status, 1, output)
            self.assertIn('BB_PLUGIN_REFRESH failed discovery ', output)
            self.assertFalse(requests)

    def test_positive_database_activity_keeps_strict_stopped_classification_without_absence_claim(self):
        data = self.data()
        for kind in ('bb.db', 'bb.db-wal', 'bb.db-shm', 'directory', 'opening-directory'):
            with self.subTest(kind=kind):
                api = FakeApi()
                with self.database_activity(data, kind) as writes:
                    result = self.run_policy(api)
                self.assertTrue(writes)
                self.assertEqual(result, (0, 'BB_PLUGIN_REFRESH stopped\n'))
                self.assertFalse(api.verified)
                self.assertFalse(api.calls)

    def test_changed_negative_snapshot_is_refused_and_all_handles_close(self):
        original_home = self.home
        native_stat, native_fstat, native_open, native_close, native_chmod = os.stat, os.fstat, os.open, os.close, os.chmod
        cases = ('leaf-replace', 'ancestor-replace', 'link-substitute', 'leaf-mode', 'ancestor-mode',
                 'leaf-owner', 'leaf-group', 'ancestor-owner', 'ancestor-group', 'marker-appear',
                 'marker-remove', 'marker-appear-remove', 'failure-and-close', 'close-only')
        for case in cases:
            self.home = original_home / case
            self.home.mkdir()
            data = self.captured_non_server(False, False)
            marker = data / 'bb.db-journal'
            if case == 'marker-remove':
                marker.write_bytes(b'inert')
            target = native_stat(self.home if case.startswith('ancestor') else data)
            mutated = False
            descriptors = []
            def metadata(path, *args, **kwargs):
                nonlocal mutated
                try:
                    return native_stat(path, *args, **kwargs)
                finally:
                    if str(path) == 'server-import.json' and not mutated:
                        mutated = True
                        if case in ('leaf-replace', 'link-substitute'):
                            data.rename(self.home / 'old')
                            if case == 'leaf-replace':
                                data.mkdir()
                            else:
                                data.symlink_to(self.home / 'old')
                        elif case == 'ancestor-replace':
                            self.home.rename(self.home.with_name(case + '-old'))
                            self.home.mkdir()
                        elif case in ('leaf-mode', 'ancestor-mode'):
                            native_chmod(self.home if case == 'ancestor-mode' else data, 0o700)
                        elif case in ('marker-appear', 'marker-appear-remove'):
                            marker.write_bytes(b'inert')
                            if case == 'marker-appear-remove':
                                marker.unlink()
                        elif case == 'marker-remove':
                            marker.unlink()
            def descriptor_info(fd):
                info = native_fstat(fd)
                if mutated and (info.st_dev, info.st_ino) == (target.st_dev, target.st_ino) and case in (
                        'leaf-owner', 'ancestor-owner', 'leaf-group', 'ancestor-group', 'failure-and-close'):
                    fields = ('st_dev', 'st_ino', 'st_uid', 'st_gid', 'st_mode', 'st_size',
                              'st_mtime_ns', 'st_ctime_ns', 'st_nlink')
                    info = types.SimpleNamespace(**{key: getattr(info, key) for key in fields})
                    if case.endswith('group'):
                        info.st_gid += 1
                    else:
                        info.st_uid += 1
                return info
            def open_directory(*args, **kwargs):
                fd = native_open(*args, **kwargs)
                descriptors.append(fd)
                return fd
            def close(fd):
                native_close(fd)
                if case in ('failure-and-close', 'close-only'):
                    raise OSError('cleanup-secret-sentinel')
            api = FakeApi()
            with self.subTest(case=case), patch.object(P.os, 'stat', side_effect=metadata), \
                    patch.object(P.os, 'fstat', side_effect=descriptor_info), \
                    patch.object(P.os, 'open', side_effect=open_directory), patch.object(P.os, 'close', side_effect=close):
                status, output = self.run_policy(api)
                self.assertEqual((status, output), (1, 'BB_PLUGIN_REFRESH failed discovery ' +
                    ('unverified-local-state' if case == 'close-only' else 'changed-local-state') + '\n'))
                self.assertFalse(api.verified)
                self.assertFalse(api.calls)
            self.assertTrue(mutated)
            for fd in descriptors:
                with self.assertRaises(OSError):
                    native_fstat(fd)
        self.home = original_home

    def test_home_alias_normalizes_default_but_negative_result_never_trusts_later_server_state(self):
        data = self.captured_non_server()
        canonical = self.home
        alias = self.root / 'home-alias'
        alias.symlink_to(canonical)
        self.home = alias
        self.assertEqual(self.run_policy(environment={'BB_DATA_DIR': str(alias / '.bb')}),
                         (0, 'BB_PLUGIN_REFRESH absent\n'))
        self.assertEqual(self.run_policy(environment={'BB_DATA_DIR': str(canonical / '.bb')}),
                         (0, 'BB_PLUGIN_REFRESH absent\n'))
        (data / 'bb.db').write_bytes(b'SQLite format 3\0')
        self.assertEqual(self.run_policy(), (0, 'BB_PLUGIN_REFRESH stopped\n'))
        (data / 'bb.db').chmod(0o660)
        self.assertEqual(self.run_policy(), (1, 'BB_PLUGIN_REFRESH failed discovery writable-local-state\n'))
        self.home = canonical

    def test_missing_candidate_must_remain_missing_in_the_verified_parent(self):
        native_stat = os.stat
        created = False
        def metadata(path, *args, **kwargs):
            nonlocal created
            try:
                return native_stat(path, *args, **kwargs)
            except FileNotFoundError:
                if str(path) == '.bb' and not created:
                    created = True
                    (self.home / '.bb').mkdir()
                raise
        with patch.object(P.os, 'stat', side_effect=metadata):
            self.assertEqual(self.run_policy(), (1, 'BB_PLUGIN_REFRESH failed discovery changed-local-state\n'))
        self.assertTrue(created)

    def test_unverifiable_process_inventory_prevents_negative_classification(self):
        self.captured_non_server()
        with patch.object(self.proc, 'table', side_effect=P.Refusal('process-proof-unavailable')):
            self.assertEqual(self.run_policy(), (1, 'BB_PLUGIN_REFRESH failed discovery process-proof-unavailable\n'))
        with patch.object(self.proc, 'read', side_effect=P.Refusal('changed-process')):
            self.assertEqual(self.run_policy(), (1, 'BB_PLUGIN_REFRESH failed discovery changed-process\n'))

    def test_unresolved_main_process_claim_cannot_be_excluded_as_non_server(self):
        self.captured_non_server()
        for argv in (['node', str(self.entry)],
                     ['node', str(self.entry), str(self.entry)],
                     ['node', 'bb-app/server/dist/index.js']):
            with self.subTest(argv=argv):
                self.records[100] = (argv, {'HOME': str(self.home)}, b'1')
                api = FakeApi()
                status, output = self.run_policy(api)
                self.assertEqual(status, 1, output)
                self.assertNotIn('absent', output)
                self.assertFalse(api.calls)
                self.assertFalse(api.verified)

    def test_partial_main_evidence_is_never_absent_even_without_a_database(self):
        data = self.home / '.bb'
        data.mkdir()
        names = ('bb.db', 'bb.db-wal', 'bb.db-shm', 'bb.db-journal',
                 'bb-app-runtime.json', 'server-moved.json', 'server-import.json')
        for mode, database in ((0o700, False), (0o775, False), (0o700, True), (0o775, True)):
            data.chmod(mode)
            if database:
                (data / 'bb.db').write_bytes(b'SQLite format 3\0')
            for name in names:
                if database and name == 'bb.db':
                    continue
                for form in ('malformed', 'directory', 'dangling-link'):
                    marker = data / name
                    if form == 'malformed':
                        marker.write_text('secret-path-sentinel')
                    elif form == 'directory':
                        marker.mkdir()
                    else:
                        marker.symlink_to(self.root / 'missing-secret-sentinel')
                    with self.subTest(mode=oct(mode), database=database, name=name, form=form):
                        api = FakeApi()
                        status, output = self.run_policy(api)
                        stopped = database and name in ('bb.db-wal', 'bb.db-shm', 'bb.db-journal')
                        self.assertEqual(status, 0 if stopped else 1, output)
                        if stopped:
                            self.assertEqual(output, 'BB_PLUGIN_REFRESH stopped\n')
                        self.assertNotIn('BB_PLUGIN_REFRESH absent', output)
                        self.assertNotIn('sentinel', output)
                        self.assertFalse(api.calls)
                        self.assertFalse(api.verified)
                    if form == 'directory':
                        marker.rmdir()
                    else:
                        marker.unlink()
            if database:
                (data / 'bb.db').unlink()

    def test_writable_file_reports_controlled_refusal_without_permission_repair(self):
        data = self.data()
        data.chmod(0o775)
        (data / 'bb.db').chmod(0o660)
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

    def test_native_failures_identify_the_operation_without_exception_text(self):
        self.server()
        cases = (('identity', 'identity', 'unverified-main-server'),
                 ('inventory', 'inventory', 'malformed-result'),
                 ('timeout', 'update', 'operation-timeout'),
                 ('unknown-exception', 'update', 'unknown-failure'))
        for case, operation, reason in cases:
            api = FakeApi()
            if case == 'identity':
                api.verify = lambda: P.need(False, 'unverified-main-server')
            elif case == 'inventory':
                api.request = lambda *_: {'enabled': 'secret-sentinel'}
            else:
                api.results['tracking'] = P.Refusal('operation-timeout') if case == 'timeout' else RuntimeError('secret-sentinel')
            with self.subTest(case=case):
                status, output = self.run_policy(api)
                self.assertEqual(status, 1)
                self.assertIn(f'BB_PLUGIN_REFRESH failed {operation} {reason}\n', output)
                self.assertNotIn('sentinel', output)
                result = run_wrapper(output, status)
                self.assertEqual(result.returncode, 1)
                self.assertIn(f'{operation} / {reason}.', result.stdout)

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

    def test_darwin_native_argmax_reaches_verified_refresh_and_preserves_disabled_intent(self):
        self.server(613)
        api = FakeApi([plugin(enabled=False)])
        with self.darwin_inventory(f'{os.getuid()} 613\n'.encode()) as native, self.darwin_http(api):
            self.assertEqual(self.run_policy(native_api=True), (0, 'BB_PLUGIN_REFRESH completed\n'))
        self.assertGreater(native.argmax_reads, 1, 'native limit is honored during revalidation too')
        self.assertEqual(native.argmax_reads, len(native.private_reads))
        self.assertEqual(native.procargs_capacities, [1048576] * len(native.private_reads))
        self.assertEqual(set(native.private_reads), {613})
        self.assertFalse(api.plugins['tracking']['enabled'])
        self.assertEqual(api.plugins['tracking']['source'], 'npm:fixture@^1')

    def test_darwin_unverified_argmax_refuses_before_allocation_private_reads_or_requests(self):
        self.server()
        cases = [('status', -1), ('width', 0), ('width', 3), ('width', 8)]
        cases += [('limit', value) for value in (-1, 0, 4, P.MAX_BYTES + 1, (1 << 31) - 1)]
        for kind, value in cases:
            with self.subTest(kind=kind, value=value):
                api = FakeApi()
                with self.darwin_inventory(f'{os.getuid()} 100\n'.encode()) as native, self.darwin_http(api) as requests:
                    if kind == 'status':
                        native.argmax_status = value
                    elif kind == 'width':
                        native.argmax_width = value
                    else:
                        native.argmax = value
                    with patch.object(P.ctypes, 'create_string_buffer', side_effect=AssertionError('unverified allocation')):
                        result = self.run_policy(native_api=True)
                self.assertEqual(result, (1, 'BB_PLUGIN_REFRESH failed discovery process-proof-unavailable\n'))
                self.assertEqual(native.argmax_reads, 1)
                self.assertEqual(native.private_reads, [])
                self.assertEqual(requests, [])

    def test_darwin_argmax_revalidation_failure_cannot_reach_later_requests(self):
        self.server()
        for at_read in (2, 3, 4):
            with self.subTest(at_read=at_read):
                api = FakeApi()
                with self.darwin_inventory(f'{os.getuid()} 100\n'.encode()) as native, self.darwin_http(api) as requests:
                    def change(args):
                        if args[:2] == ['/bin/ps', '-p'] and native.argmax_reads == at_read - 1:
                            native.argmax_status = -1
                    native.on_query = change
                    result = self.run_policy(native_api=True)
                self.assertEqual(result, (1, 'BB_PLUGIN_REFRESH failed identity process-proof-unavailable\n'))
                self.assertEqual(native.private_reads, [100] * (at_read - 1))
                self.assertEqual(requests, [('GET', '/health', None)] if at_read == 4 else [])
                self.assertEqual(api.calls, [])

    def test_darwin_native_query_errors_and_invalid_return_sizes_remain_fatal(self):
        self.server()
        cases = [('errno', code) for code in (1, 3, 12, 22)]
        cases += [('length', count) for count in (0, 3, 1048577)]
        for kind, value in cases:
            with self.subTest(kind=kind, value=value):
                api = FakeApi()
                with self.darwin_inventory(f'{os.getuid()} 100\n'.encode()) as native, self.darwin_http(api) as requests:
                    if kind == 'errno':
                        native.procargs_error = value
                    else:
                        native.procargs_length = value
                    result = self.run_policy(native_api=True)
                self.assertEqual(result, (1, 'BB_PLUGIN_REFRESH failed discovery process-proof-unavailable\n'))
                self.assertEqual(native.argmax_reads, 1)
                self.assertEqual(native.private_reads, [100], 'no fallback or ignored native failure')
                self.assertEqual(requests, [])

    def test_darwin_observed_signed_uid_inventory_and_minimized_row_allow_discovery(self):
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

    def test_darwin_extra_identity_rows_refuse_discovery_before_private_reads_or_requests(self):
        self.server()
        account = str(os.getuid()).encode()
        row = account + b' Thu Oct  1 00:00:00 2026\n'
        for extra in (row, b'-2 Thu Oct  1 00:00:00 2026\n', b'\n'):
            for raw in (row + extra, extra + row):
                with self.subTest(raw=raw):
                    api = FakeApi()
                    with self.darwin_inventory(account + b' 100\n') as native, self.darwin_http(api) as requests:
                        native.identity_rows[100] = raw
                        result = self.run_policy(native_api=True)
                    self.assertEqual(native.private_reads, [])
                    self.assertEqual(requests, [])
                    self.assertEqual(result, (1, 'BB_PLUGIN_REFRESH failed discovery process-proof-unavailable\n'))

    def test_darwin_mixed_inventory_updates_only_verified_account_server_and_preserves_intent(self):
        data = self.server()
        for path in (self.home, data, self.package):
            path.chmod(0o775)
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
                        self.assertEqual(self.run_policy(native_api=True), (0, 'BB_PLUGIN_REFRESH completed\n'))
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
                    api.results['second'] = P.Refusal('native-command-failed')
                with self.darwin_inventory(table) as native, self.darwin_http(api) as requests:
                    status, output = self.run_policy(policy=policy, native_api=True)
                if case == 'failure-then-safe':
                    self.assertEqual((status, output), (1, 'BB_PLUGIN_REFRESH failed update native-command-failed\n'))
                else:
                    expected = 'readiness-deferred\nBB_PLUGIN_REFRESH absent' if case == 'readiness' else case
                    self.assertEqual((status, output), (0, f'BB_PLUGIN_REFRESH {expected}\n'))
                    self.assertFalse(api.mutations())
                if case in ('stopped', 'readiness'):
                    self.assertFalse(requests)
                self.assertTrue(set(native.private_reads) <= {100})

    def test_darwin_native_contract_socket_and_health_proof_still_gate_plugin_requests(self):
        data = self.server()
        for path in (self.home, data, self.package):
            path.chmod(0o775)
        table = b'-2 53750\n' + f'{os.getuid()} 100\n'.encode()
        manifest = self.package / 'package.json'
        original = manifest.read_bytes()
        for fault in ('contract', 'peer', 'health', 'data'):
            with self.subTest(fault=fault):
                api = FakeApi()
                manifest.write_bytes(original)
                if fault == 'contract':
                    metadata = json.loads(original)
                    metadata['bin']['bb-server'] = 'unexpected-entry'
                    manifest.write_text(json.dumps(metadata))
                with self.darwin_inventory(table) as native, self.darwin_http(api, fault) as requests, \
                        patch.object(P.time, 'monotonic', side_effect=range(1000)), patch.object(P.time, 'sleep'):
                    native.peer = fault != 'peer'
                    status, output = self.run_policy(native_api=True)
                expected = {'contract': 'discovery unverified-main-server', 'peer': 'identity unverified-peer',
                            'health': 'identity unverified-main-server', 'data': 'identity unverified-main-server'}[fault]
                self.assertEqual((status, output), (1, 'BB_PLUGIN_REFRESH failed ' + expected + '\n'))
                self.assertFalse(api.calls)
                self.assertFalse(any('/plugins' in path for _, path, _ in requests))
                self.assertTrue(set(native.private_reads) <= {100})
        manifest.write_bytes(original)

    def test_darwin_extra_identity_rows_refuse_revalidation_before_further_private_reads_or_requests(self):
        self.server()
        account = str(os.getuid()).encode()
        row = account + b' Thu Oct  1 00:00:00 2026\n'
        for raw in (row + row, row + b'-2 Thu Oct  1 00:00:00 2026\n', row + b'\n'):
            for at_read in (2, 3, 4):
                with self.subTest(raw=raw, at_read=at_read):
                    api = FakeApi()
                    count = 0
                    with self.darwin_inventory(account + b' 100\n') as native, self.darwin_http(api) as requests:
                        def change(args):
                            nonlocal count
                            if args[:2] == ['/bin/ps', '-p']:
                                count += 1
                                if count == at_read:
                                    native.identity_rows[100] = raw
                        native.on_query = change
                        result = self.run_policy(native_api=True)
                    self.assertEqual(native.private_reads, [100] * (at_read - 1))
                    self.assertEqual(requests, [('GET', '/health', None)] if at_read == 4 else [])
                    self.assertEqual(api.calls, [])
                    self.assertEqual(result, (1, 'BB_PLUGIN_REFRESH failed identity process-proof-unavailable\n'))

    def test_darwin_malformed_start_shape_refuses_before_further_private_reads_or_requests(self):
        self.server()
        account = str(os.getuid()).encode()
        stamp = b'Thu Oct  1 00:00:00 2026'
        malformed = (stamp + b' private-path-secret-sentinel', stamp + b'junk',
                     stamp + b'\0', stamp + b'\r', stamp + b'\v',
                     b'\v' + stamp, b'\r' + stamp, stamp.replace(b'Oct', b'Oct\0'),
                     stamp.replace(b'Oct  ', b'Oct\tsecret-sentinel '),
                     b'start', b'12345', b'Thu Oct 1 00:00:00', b'Oct 1 00:00:00 2026',
                     b'Bad Oct 1 00:00:00 2026', b'Thu Bad 1 00:00:00 2026',
                     b'Thu Oct 0 00:00:00 2026', b'Thu Oct 32 00:00:00 2026',
                     b'Thu Oct 1 24:00:00 2026', b'Thu Oct 1 00:60:00 2026',
                     b'Thu Oct 1 00:00:61 2026', b'Thu Oct 1 00:00:00 20260')
        for bad in malformed:
            for at_read in (1, 2, 3, 4):
                with self.subTest(stamp=bad, at_read=at_read):
                    api = FakeApi()
                    count = 0
                    with self.darwin_inventory(account + b' 100\n') as native, self.darwin_http(api) as requests:
                        def change(args):
                            nonlocal count
                            if args[:2] == ['/bin/ps', '-p']:
                                count += 1
                                if count == at_read:
                                    native.identity_rows[100] = account + b' ' + bad + b'\n'
                        native.on_query = change
                        result = self.run_policy(native_api=True)
                    self.assertEqual(native.private_reads, [100] * (at_read - 1))
                    self.assertEqual(requests, [('GET', '/health', None)] if at_read == 4 else [])
                    self.assertEqual(api.calls, [])
                    operation = 'discovery' if at_read == 1 else 'identity'
                    self.assertEqual(result, (1, f'BB_PLUGIN_REFRESH failed {operation} process-proof-unavailable\n'))

    def test_darwin_native_start_whitespace_allows_verified_refresh(self):
        self.server()
        account = str(os.getuid()).encode()
        for raw in (account + b' Thu Oct  1 00:00:00 2026\n',
                    b'  ' + account + b'   Wed Sep 30 23:59:59 2026   \n',
                    b'\t' + account + b'\tThu\tOct 1\t00:00:00 2026\t',
                    account + b' Sat Dec 31 23:59:60 2016\n'):
            with self.subTest(raw=raw):
                api = FakeApi()
                with self.darwin_inventory(account + b' 100\n') as native, self.darwin_http(api):
                    native.identity_rows[100] = raw
                    self.assertEqual(self.run_policy(native_api=True), (0, 'BB_PLUGIN_REFRESH completed\n'))
                self.assertTrue(native.private_reads)
                self.assertEqual(set(native.private_reads), {100})
                self.assertEqual(len(api.mutations()), 1)

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
                                stamp = b'Thu Oct  1 00:00:01 2026'
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
        self.records[100][1]['HOME'] = str(self.root)   
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

    def test_unrelated_server_entries_are_ignored_but_invalid_bb_identity_is_not(self):
        entry = self.home / 'unrelated/server/dist/index.js'
        entry.parent.mkdir(parents=True)
        entry.write_text('never execute')
        (entry.parents[2] / 'package.json').write_text('{"name":"unrelated"}')
        self.records[200] = (['node', '--some-node-option', str(entry)], {}, b'1')
        self.assertEqual(P.discover(self.files(), self.proc), ([], 0))
        self.server()
        manifest = self.package / 'package.json'
        metadata = json.loads(manifest.read_text())
        metadata['bin']['bb-server'] = 'unexpected-entry'
        manifest.write_text(json.dumps(metadata))
        with self.assertRaisesRegex(P.Refusal, 'unverified-main-server'):
            P.discover(self.files(), self.proc)
        self.assertEqual(self.run_policy(), (1, 'BB_PLUGIN_REFRESH failed discovery unverified-main-server\n'))

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
                api.request = native_api.request
                def close():
                    if close_fails:
                        raise RuntimeError('cleanup-secret-path-sentinel')
                response = types.SimpleNamespace(status=200, getheader=lambda _: None,
                    read=lambda _: b'{"enabled":true}')
                connection = types.SimpleNamespace(sock=types.SimpleNamespace(getsockname=lambda: ('127.0.0.1', 49999)),
                    connect=lambda: None, request=lambda *_: None, getresponse=lambda: response, close=close)
                with patch.object(P.http.client, 'HTTPConnection', return_value=connection):
                    status, output = self.run_policy(api)
                self.assertEqual(status, int(close_fails))
                self.assertEqual(output, 'BB_PLUGIN_REFRESH failed inventory unknown-failure\n' if close_fails
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
    def test_darwin_captured_and_other_native_argmax_values_determine_buffer_size(self):
        records = {613: (['/inert/other'], {}, b'Mon Oct 5 00:00:00 2026')}
        for maximum in (262144, 1048576, P.MAX_BYTES):
            with self.subTest(maximum=maximum), patch.object(P.sys, 'platform', 'darwin'):
                processes = P.Processes(501)
                native = DarwinInputs(b'501 613\n', records, {613: 501})
                native.argmax = maximum
                with native.installed():
                    self.assertEqual(processes.read(613), (records[613][0], {}, 'Mon Oct 5 00:00:00 2026'))
                self.assertEqual(native.argmax_reads, 1)
                self.assertEqual(native.procargs_capacities, [maximum])

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
        records = {99: (['/inert/node', '/inert/bb-app/server/dist/index.js'], {}, b'Thu Oct  1 00:00:00 2026')}
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
        for raw in [uid + b' Thu Oct  1 00:00:00 2026\n' for uid in malformed] + [b'1234\n', b'\n']:
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
                patch.object(P.ctypes, 'CDLL', return_value=types.SimpleNamespace(
                    sysctl=sysctl, sysctlbyname=DarwinInputs(b'', {}).sysctlbyname)):
            args, selected, _ = processes.read(99)
        self.assertEqual(args, [a.decode() for a in argv])
        self.assertEqual(selected, {'HOME': '/inert home', 'BB_DATA_DIR': '/inert home/custom data', 'BB_SERVER_PORT': '39001'})
        with patch.object(P, 'command', return_value=b''):
            self.assertIsNone(processes.read(99))
        with patch.object(P, 'command', return_value=b'p99\nn127.0.0.1:39001->127.0.0.1:49999\nTST=ESTABLISHED\n'):
            self.assertTrue(processes.peer_owned(99, 39001, 49999))
            self.assertFalse(processes.peer_owned(100, 39001, 49999))


class Callers(unittest.TestCase):
    def policy_outcomes(self):
        fixture = Discovery()
        fixture.setUp()
        self.addCleanup(fixture.doCleanups)
        data = fixture.captured_non_server()
        absent = fixture.run_policy()
        (data / 'bb.db').write_bytes(b'SQLite format 3\0')
        (data / 'bb.db').chmod(0o660)
        refusal = fixture.run_policy()
        (data / 'bb.db').unlink()
        fixture.server(data=fixture.home / 'manual')
        first = FakeApi()
        first.results['tracking'] = P.Refusal('operation-timeout')
        fixture.server(101, fixture.home / 'second', '39002')
        second = FakeApi()
        second.safe = True
        failure_then_deferral = fixture.run_policy([first, second])
        self.assertEqual(absent, (0, 'BB_PLUGIN_REFRESH absent\n'))
        self.assertEqual(refusal, (1, 'BB_PLUGIN_REFRESH failed discovery writable-local-state\n'))
        self.assertEqual(failure_then_deferral[0], 1)
        self.assertIn('BB_PLUGIN_REFRESH safe-mode', failure_then_deferral[1])
        self.assertIn('BB_PLUGIN_REFRESH failed update operation-timeout', failure_then_deferral[1])
        return absent, refusal, failure_then_deferral

    def test_real_refresh_runs_inside_ordinary_callers_with_group_writable_directories(self):
        driver = r'''
import importlib.util, json, os, sys, types
from pathlib import Path
from unittest.mock import patch
spec = importlib.util.spec_from_file_location('refresh_fixture_tests', sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
f = module.Discovery()
config = json.loads(Path(os.environ['FIXTURE_CONFIG']).read_text())
for name in ('root', 'home', 'package', 'entry'):
    setattr(f, name, Path(config[name]))
f.records = {int(pid): (argv, env, stamp.encode()) for pid, (argv, env, stamp) in config['records'].items()}
f.proc = types.SimpleNamespace(table=lambda: list(f.records), read=lambda pid: f.records.get(pid),
    peer_owned=lambda *_: True, database_open=lambda _: False)
api = module.FakeApi([module.plugin(enabled=False)])
api.safe = config['case'] == 'safe-mode'
if config['case'] == 'update-failed':
    api.results['tracking'] = module.P.Refusal('operation-timeout')
with patch.object(module.P.subprocess, 'run', side_effect=AssertionError('external execution forbidden')), \
        patch.object(module.P.os, 'getgroups', side_effect=AssertionError('group proof forbidden')), \
        patch.object(module.P.os, 'getgrouplist', side_effect=AssertionError('initgroups proof forbidden')), \
        patch.object(module.P.os, 'listxattr', side_effect=AssertionError('ACL proof forbidden')), \
        f.darwin_http(api, data=Path(config['data'])) as requests:
    status, output = f.run_policy(native_api=True, environment=config['environment'])
Path(os.environ['FIXTURE_RESULT']).write_text(json.dumps({'requests': requests, 'updates': api.mutations(), 'plugins': api.plugins}))
print(output, end='')
sys.exit(status)
'''
        for script in SCRIPTS:
            selected = EXTRACT.definitions((ROOT / (script + '.sh')).read_text())
            real = ('main', 'run_setup_tasks', 'refresh_bb_plugins')
            names = re.findall(r'^([A-Za-z_][A-Za-z_0-9]*)\(\) \{', selected, re.M)
            code = '\n'.join(f'{name}() {{ :; }}' for name in names if name not in real)
            for name in real:
                code += '\n' + re.search(rf'^{name}\(\) \{{\n.*?^\}}', selected, re.M | re.S).group()
            code += r'''
bb_plugin_refresh_payload() { /usr/bin/python3 -I -B "$FIXTURE_DRIVER" "$FIXTURE_TESTS"; }
setup_bb_machine() { return "$EARLIER"; }
print_error() { printf '%s\n' "$1"; }
print_warning() { printf '%s\n' "$1"; }
print_message() { printf '%s\n' "$1"; }
print_debug() { printf '%s\n' "$1"; }
prepare_pi_profile_permissions() { echo unrelated; }
refresh_pi_packages() { echo later-pi-success; }
check_pending_reboot() { echo reboot-reported; }
start_setup_log() { echo logging; }
finish_setup_log() { echo "finalized:$1"; return "$1"; }
check_dotfiles_access() { return 1; }
setup_dotfiles_deploy_key() { return 1; }
is_main_user() { return 0; }
bb_server_selection() { return 1; }
whoami() { echo fixture; }
brew() { :; }
unzip() { :; }
MACOS_DEVELOPER_TOOLS_STATE=ready
MACOS_CLT_OPERATION_FAILED=0
DOTFILES_ACCESS_METHOD=none
'''
            for command in ('systemctl', 'launchctl', 'loginctl', 'pgrep', 'ps', 'curl', 'npm',
                            'bun', 'pi', 'bb', 'chezmoi', 'sudo', 'kill', 'pkill', 'tailscale'):
                code += f'\n{command}() {{ echo FORBIDDEN:{command}; return 99; }}'
            code += '\nmain\n'
            for case in ('updated', 'absent', 'stopped', 'safe-mode', 'update-failed', 'file-failed'):
                for custom in (False, True):
                    fixture = Discovery()
                    fixture.setUp()
                    try:
                        data = fixture.home / ('custom/data' if custom else '.bb')
                        if case == 'absent':
                            data.mkdir(parents=True)
                        elif case == 'stopped':
                            fixture.data(data)
                        else:
                            fixture.server(data=data)
                        if case == 'file-failed':
                            (data / 'bb.db').chmod(0o660)
                        paths = [fixture.home, data, *fixture.entry.parents[:6]]
                        if custom:
                            paths.append(data.parent)
                        for path in paths:
                            path.chmod(0o2775)
                        before = {path: path.stat() for path in paths}
                        (fixture.root / 'driver.py').write_text(driver)
                        config = {name: str(getattr(fixture, name)) for name in ('root', 'home', 'package', 'entry')}
                        config.update(case=case, data=str(data), environment={'BB_DATA_DIR': str(data)},
                            records={pid: [argv, env, stamp.decode()] for pid, (argv, env, stamp) in fixture.records.items()})
                        (fixture.root / 'config.json').write_text(json.dumps(config))
                        for earlier in (0, 1):
                            expected = int(bool(earlier or case in ('update-failed', 'file-failed')))
                            env = {'HOME': str(fixture.home), 'PATH': '/usr/bin:/bin', 'EARLIER': str(earlier),
                                   'USER': 'fixture', 'LANG': 'C', 'TERM': 'dumb',
                                   'FIXTURE_CONFIG': str(fixture.root / 'config.json'),
                                   'FIXTURE_DRIVER': str(fixture.root / 'driver.py'),
                                   'FIXTURE_TESTS': str(Path(__file__).resolve()),
                                   'FIXTURE_RESULT': str(fixture.root / 'result.json')}
                            result = subprocess.run(['/bin/bash', '-c', code], cwd=fixture.home, env=env,
                                stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=15)
                            with self.subTest(script=script, case=case, custom=custom, earlier=earlier):
                                self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
                                for marker in ('logging', 'unrelated', 'later-pi-success', 'reboot-reported', f'finalized:{expected}'):
                                    self.assertIn(marker, result.stdout)
                                self.assertNotIn('FORBIDDEN:', result.stdout + result.stderr)
                                self.assertNotIn('sentinel', result.stdout + result.stderr)
                                report = json.loads((fixture.root / 'result.json').read_text())
                                updates = report['updates']
                                if case in ('updated', 'update-failed'):
                                    self.assertEqual(updates, [['POST', '/api/v1/plugins/tracking/update', {}]])
                                else:
                                    self.assertFalse(updates)
                                if case in ('absent', 'stopped', 'file-failed'):
                                    self.assertFalse(report['requests'])
                                self.assertFalse(report['plugins']['tracking']['enabled'])
                                self.assertEqual(report['plugins']['tracking']['version'], '1.1.0' if case == 'updated' else '1.0.0')
                                self.assertEqual({path: path.stat() for path in paths}, before)
                    finally:
                        fixture.doCleanups()

    def test_ubuntu_selection_readiness_and_preparation_failures_keep_boundaries(self):
        source = EXTRACT.definitions((ROOT / 'ubuntu.sh').read_text())
        caller = re.search(r'^run_setup_tasks\(\) \{\n.*?^\}', source, re.M | re.S).group()
        start = caller.index('    if [[ "${_bb_selection_status}" -eq 0 ]]; then')
        end = caller.index('    if ! prepare_pi_profile_permissions; then', start)
        seam = caller[start:end]
        cases = [
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
        outcomes = self.policy_outcomes()
        wrapper = (ROOT / 'lib/bb-plugin-refresh.bash').read_text().replace('@@PYTHON@@', (ROOT / 'lib/bb-plugin-refresh.py').read_text().rstrip()).rstrip()
        for script in SCRIPTS:
            source = (ROOT / (script + '.sh')).read_text()
            block = source.split(": 'BEGIN_BB_PLUGIN_REFRESH'\n", 1)[1].split("\n: 'END_BB_PLUGIN_REFRESH'", 1)[0]
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
install_opencode_cli() { return "$EARLIER"; }
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
bb_server_selection() { return "$SELECTION"; }
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
                cases = [('BB_PLUGIN_REFRESH completed', 0, 0, 0),
                         ('BB_PLUGIN_REFRESH stopped', 0, 0, 0),
                         ('BB_PLUGIN_REFRESH safe-mode', 0, 0, 0),
                         ('BB_PLUGIN_REFRESH failed discovery writable-local-state', 0, 0, 1),
                         ('BB_PLUGIN_REFRESH completed', 1, 0, 1),
                         ('secret-path-sentinel', 0, 0, 1),
                         ('BB_PLUGIN_REFRESH completed', 0, 1, 1),
                         ('BB_PLUGIN_REFRESH safe-mode', 0, 1, 1)]
                cases = [(*case, 1) for case in cases]
                cases += [(text, status, earlier, int(bool(status or earlier)), selection)
                          for status, text in outcomes for earlier in (0, 1)
                          for selection in ((0, 1) if script == 'ubuntu' else (1,))]
                for text, status, earlier, expected, selection in cases:
                    env = {'HOME': str(home), 'PATH': '/usr/bin:/bin', 'REFRESH_STATUS': str(status),
                           'EARLIER': str(earlier), 'FIXTURE_OUTPUT': text, 'SELECTION': str(selection),
                           'USER': 'fixture', 'LANG': 'C', 'TERM': 'dumb'}
                    result = subprocess.run(['/bin/bash', '-c', code], env=env, cwd=home,
                                            stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=15)
                    with self.subTest(script=script, text=text, earlier=earlier, status=status, selection=selection):
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

    def test_early_failure_survives_success_deferral_reboot_and_completed_log(self):
        outcomes = self.policy_outcomes()
        selected = EXTRACT.definitions((ROOT / 'mac.sh').read_text())
        real = ('run_setup_tasks', 'main', 'refresh_bb_plugins', 'start_setup_log', 'finish_setup_log')
        names = re.findall(r'^([A-Za-z_][A-Za-z_0-9]*)\(\) \{', selected, re.M)
        code = '\n'.join(f'{name}() {{ :; }}' for name in names if name not in real)
        for name in real:
            definition = re.search(rf'^{name}\(\) \{{\n.*?^\}}', selected, re.M | re.S).group()
            code += '\n' + definition
        code += r'''
print_error() { printf '%s\n' "$*"; }
print_warning() { printf '%s\n' "$*"; }
print_message() { printf '%s\n' "$*"; }
print_debug() { printf '%s\n' "$*"; }
install_bb_desktop() { echo desktop-operation; [[ "$FAIL_TASK" != desktop ]]; }
install_opencode_cli() { echo opencode-operation; [[ "$FAIL_TASK" != opencode ]]; }
install_gitea_client() { echo independent-success; return 0; }
bb_plugin_refresh_payload() { printf '%s\n' "$FIXTURE_OUTPUT"; return "$REFRESH_STATUS"; }
refresh_pi_packages() { echo later-pi-success; return 0; }
check_pending_reboot() { echo reboot-reported; }
check_dotfiles_access() { return 1; }
setup_dotfiles_deploy_key() { return 1; }
is_main_user() { return 0; }
whoami() { echo fixture; }
upload_log() { cp -- "$SETUP_LOG_FILE" "$HOME/completed-upload.log"; }
'''
        for command in ('curl', 'sudo', 'brew', 'chezmoi', 'bb', 'npm', 'ps', 'pgrep',
                        'launchctl', 'kill', 'pkill', 'tailscale'):
            code += f'\n{command}() {{ echo FORBIDDEN:{command}; return 99; }}'
        code += '\nmain\n'
        results = [(0, 'BB_PLUGIN_REFRESH safe-mode', 'BB plugin refresh deliberately deferred: native safe mode remains enabled.'),
                   (0, 'BB_PLUGIN_REFRESH stopped', 'Stopped local BB main-server plugin refresh deferred; no server was started.')]
        results += [(status, text, diagnostic) for (status, text), diagnostic in zip(outcomes, (
            'No verified local BB main server requires plugin refresh.',
            'BB plugin refresh failed: discovery / writable-local-state.',
            'BB plugin refresh failed: update / operation-timeout.'))]
        for failed in ('desktop', 'opencode', 'none'):
            for status, text, diagnostic in results:
                expected = int(failed != 'none' or status != 0)
                with self.subTest(failed=failed, outcome=text), tempfile.TemporaryDirectory(prefix='bb-refresh-final-log-') as home:
                    result = subprocess.run(['/bin/bash', '-c', code], cwd=home,
                                            env={'HOME': home, 'PATH': '/usr/bin:/bin', 'FAIL_TASK': failed,
                                                 'FIXTURE_OUTPUT': text, 'REFRESH_STATUS': str(status), 'TERM': 'dumb'},
                                            stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=15)
                    self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
                    logs = list((Path(home) / '.local/log/machine-setup').glob('*.log'))
                    self.assertEqual(len(logs), 1)
                    log = logs[0].read_text()
                    self.assertEqual((Path(home) / 'completed-upload.log').read_text(), log)
                    summary = 'Setup completed with errors' if expected else '✨ Setup complete!'
                    milestones = ['desktop-operation', 'opencode-operation', 'independent-success', diagnostic,
                                  'later-pi-success', 'reboot-reported', summary, 'Run log saved to:']
                    positions = [log.index(marker) for marker in milestones]
                    self.assertEqual(positions, sorted(positions), log)
                    self.assertEqual(log.count('Run log saved to:'), 1)
                    self.assertEqual('✨ Setup complete!' in log, not expected)
                    self.assertNotIn('FORBIDDEN:', result.stdout + result.stderr + log)
                    self.assertEqual(result.stderr, '')

    def test_wrapper_rejects_unknown_diagnostics_with_a_bounded_controlled_fallback(self):
        refused = ('', 'secret-path-sentinel',
                   'BB_PLUGIN_REFRESH failed secret-path-sentinel writable-local-state',
                   'BB_PLUGIN_REFRESH failed discovery secret-path-sentinel',
                   'BB_PLUGIN_REFRESH failed discovery writable-local-state /secret-path-sentinel',
                   'BB_PLUGIN_REFRESH failed discovery writable-local-state\rsecret-path-sentinel',
                   'BB_PLUGIN_REFRESH failed discovery writable-local-state\nsecret-path-sentinel',
                   'BB_PLUGIN_REFRESH completed\n' * 700)
        for text, status in [(text, 0) for text in refused] + [('BB_PLUGIN_REFRESH completed', 1)]:
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
        for text, status, expected in [('BB_PLUGIN_REFRESH completed', 0, 0),
                                       ('BB_PLUGIN_REFRESH completed', 1, 1),
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
