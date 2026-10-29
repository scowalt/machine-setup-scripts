#!/usr/bin/env python3
import ast
import contextlib
import ctypes
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
    modules = {'ctypes', 'http.client', 'json', 'os', 'signal', 'subprocess', 'sys', 'time'}

    def check_function(node):
        args = node.args
        parameters = args.posonlyargs + args.args + args.kwonlyargs + [a for a in (args.vararg, args.kwarg) if a]
        if node.name == 'Exception' or node.decorator_list or node.returns is not None or any(a.annotation is not None for a in parameters):
            raise ValueError('Definition-time annotation/decorator refused')
        for default in args.defaults + [v for v in args.kw_defaults if v is not None]:
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


class Fixture:
    def __init__(self):
        self.temp = tempfile.TemporaryDirectory(prefix='bb-refresh-fixture-')
        self.root = Path(self.temp.name)
        self.home = self.root / 'home'
        self.home.mkdir()
        self.package = self.home / 'npm/lib/node_modules/bb-app'
        self.entry = self.package / 'server/dist/index.js'
        self.entry.parent.mkdir(parents=True)
        self.entry.write_text('throw Error("fixture must not execute BB");\n')
        self.cli = self.package / 'host-daemon/dist/bb'
        self.cli.parent.mkdir(parents=True)
        self.cli.write_text('throw Error("fixture must not execute BB");\n')
        self.node = self.root / 'node'
        self.node.write_text('inert; never execute')
        self.records = []
        self.requests = []
        self.commands = []
        self.health = {}
        self.safe = {}
        self.errors = {}
        self.http_error = None
        self.http_status = 200
        self.inventory_error = None
        self.native_inventory = False
        self.process_root = self.root / 'proc'
        self.closed = 0

    def close(self):
        self.temp.cleanup()

    def server(self, port=39001, data=None, flags=()):
        data = data or self.home / '.bb'
        data.mkdir(parents=True, exist_ok=True)
        (data / 'bb.db').write_bytes(b'inert database; not an identity proof')
        self.records.append(([str(self.node), *flags, str(self.entry)],
                             {'HOME': str(self.home), 'BB_DATA_DIR': str(data), 'BB_SERVER_PORT': str(port)}))
        return data

    def connection(self, host, port, **kwargs):
        assert host == '127.0.0.1' and 0 < kwargs['timeout'] <= 10
        path = None

        def request(method, url, **_kwargs):
            nonlocal path
            assert method == 'GET' and url in ('/health', '/api/v1/plugins/safe-mode')
            path = url
            self.requests.append((port, path))
            if self.http_error:
                raise self.http_error

        def response():
            value = self.health.get(port, {'ok': True}) if path == '/health' else self.safe.get(port, {'enabled': False})
            raw = value if isinstance(value, bytes) else json.dumps(value).encode()
            return types.SimpleNamespace(status=self.http_status, read=lambda: raw)

        def close():
            self.closed += 1

        return types.SimpleNamespace(request=request, getresponse=response, close=close)

    def execute(self, args, **kwargs):
        if args[0] == '/bin/ps':
            assert self.native_inventory and args == ['/bin/ps', '-U', str(os.getuid()), '-o', 'pid=']
            return types.SimpleNamespace(stdout='101\n102\n103\n')
        assert args[:2] == [str(self.node), str(self.cli)]
        assert args[2:] == ['plugin', 'update', '--all', '--yes']
        assert kwargs['stdin'] == kwargs['stdout'] == kwargs['stderr'] == subprocess.DEVNULL
        assert kwargs['check'] and 0 < kwargs['timeout'] <= 1800
        port = int(kwargs['env']['BB_SERVER_URL'].rsplit(':', 1)[1])
        assert kwargs['env']['BB_SERVER_URL'] == f'http://127.0.0.1:{port}'
        assert kwargs['env']['BB_CLI_REEXEC'] == '1'
        assert kwargs['env']['BB_DATA_DIR'] == str(kwargs['cwd'])
        self.commands.append((args, kwargs))
        if port in self.errors:
            raise self.errors[port]
        return types.SimpleNamespace(returncode=0)

    def run(self, policy='ready', environment=None):
        output = io.StringIO()
        with contextlib.ExitStack() as stack:
            stack.enter_context(patch.object(P.sys, 'argv', ['fixture', str(self.home), policy]))
            stack.enter_context(patch.dict(P.os.environ, environment or {}, clear=True))
            stack.enter_context(patch.object(P.signal, 'signal'))
            stack.enter_context(patch.object(P.signal, 'alarm'))
            stack.enter_context(patch.object(P.subprocess, 'run', side_effect=self.execute))
            stack.enter_context(patch.object(P.http.client, 'HTTPConnection', side_effect=self.connection))
            stack.enter_context(patch.object(P.os, 'kill', side_effect=AssertionError('process mutation forbidden')))
            if self.native_inventory:
                stack.enter_context(patch.object(P.sys, 'platform', 'linux'))
                stack.enter_context(patch.object(P, 'Path', side_effect=lambda value: self.process_root if value == '/proc' else Path(value)))
            else:
                stack.enter_context(patch.object(P, 'processes', side_effect=self.inventory_error or (lambda: iter(self.records))))
            stack.enter_context(contextlib.redirect_stdout(output))
            status = P.run()
        return status, output.getvalue()


class Refresh(unittest.TestCase):
    def setUp(self):
        self.f = Fixture()
        self.addCleanup(self.f.close)

    def test_source_import_rejects_definition_time_effects(self):
        for source in ('import nonexistent_application', 'print("BEFORE_MOCKS")',
                       'class Unsafe:\n    print("BEFORE_MOCKS")',
                       'class Unsafe:\n    def method(self, value=print("BEFORE_MOCKS")):\n        pass',
                       '@print("BEFORE_MOCKS")\ndef unsafe():\n    pass',
                       'def unsafe(value: print("BEFORE_MOCKS")):\n    pass',
                       'class Unsafe(metaclass=print("BEFORE_MOCKS")):\n    pass',
                       'class Exception:\n    pass\nclass Unsafe(Exception):\n    pass'):
            with self.subTest(source=source), self.assertRaises(ValueError):
                definitions_only(source)

    def test_native_launch_options_are_not_a_compatibility_gate(self):
        for flags in ((), ('--use-system-ca',), ('--use-env-proxy',),
                      ('--use-system-ca', '--use-env-proxy'), ('--enable-source-maps',)):
            with self.subTest(flags=flags):
                self.f.records.clear()
                self.f.commands.clear()
                self.f.server(flags=flags)
                self.assertEqual(self.f.run(), (0, 'BB_PLUGIN_REFRESH completed\n'))
                self.assertEqual(len(self.f.commands), 1)

    def test_linux_process_inventory_replays_observed_launch_through_native_cli(self):
        self.f.server(flags=('--use-system-ca', '--use-env-proxy'))
        argv, env = self.f.records[0]
        proc = self.f.process_root / '101'
        proc.mkdir(parents=True)
        (proc / 'cmdline').write_bytes(b'\0'.join(arg.encode() for arg in argv) + b'\0')
        (proc / 'environ').write_bytes(b'\0'.join(f'{key}={value}'.encode() for key, value in env.items()) + b'\0SECRET=never-output\0')
        unrelated = self.f.process_root / '102'
        unrelated.mkdir()
        (unrelated / 'cmdline').write_bytes(b'node\0/unrelated/daemon-bundle.mjs\0')
        self.f.native_inventory = True
        self.assertEqual(self.f.run(), (0, 'BB_PLUGIN_REFRESH completed\n'))
        self.assertEqual(len(self.f.commands), 1)
        self.assertEqual(self.f.requests, [(39001, '/health'), (39001, '/api/v1/plugins/safe-mode')])

    def test_darwin_process_arguments_keep_flags_and_spaces_without_identity_proofs(self):
        self.f.server(data=self.f.home / 'custom data', flags=('--use-system-ca', '--use-env-proxy'))
        argv, env = self.f.records[0]
        raw = len(argv).to_bytes(4, P.sys.byteorder) + argv[0].encode() + b'\0\0'
        raw += b'\0'.join(arg.encode() for arg in argv) + b'\0'
        raw += b'\0'.join(f'{key}={value}'.encode() for key, value in env.items()) + b'\0SECRET=never-output\0'

        def maximum(_name, value, _size, _new, _length):
            value._obj.value = 1048576
            return 0

        def arguments(mib, length, buffer, size, new, new_length):
            self.assertEqual((list(mib), length, new, new_length), ([1, 49, 101], 3, None, 0))
            ctypes.memmove(buffer, raw, len(raw))
            size._obj.value = len(raw)
            return 0

        libc = types.SimpleNamespace(sysctlbyname=maximum, sysctl=arguments)
        with patch.object(P.sys, 'platform', 'darwin'), patch.object(P.ctypes, 'CDLL', return_value=libc):
            self.assertEqual(P.process_record(101), (argv, env))
            libc.sysctl = lambda *_: -1
            with patch.object(P.ctypes, 'get_errno', return_value=3), self.assertRaises(ProcessLookupError):
                P.process_record(101)
            with patch.object(P.ctypes, 'get_errno', return_value=13), self.assertRaises(PermissionError):
                P.process_record(101)

    def test_absent_prepared_enrolled_and_unrelated_servers_do_not_update(self):
        data = self.f.home / '.bb'
        data.mkdir()
        (data / 'host-auth.json').write_text('preserve-enrollment')
        self.f.records.extend([(['node', '/other/server/dist/index.js'], {}),
                               (['node', '/other/host-daemon/dist/daemon-bundle.mjs'], {})])
        self.assertEqual(self.f.run(environment={'BB_SERVER_URL': 'https://remote.example.invalid'}),
                         (0, 'BB_PLUGIN_REFRESH absent\n'))
        self.assertFalse(self.f.commands or self.f.requests)
        self.assertEqual((data / 'host-auth.json').read_text(), 'preserve-enrollment')

    def test_stopped_and_moved_servers_never_start_or_update(self):
        data = self.f.server()
        self.f.records.clear()
        self.assertEqual(self.f.run(), (0, 'BB_PLUGIN_REFRESH stopped\n'))
        (data / 'server-moved.json').write_text('{}')
        self.assertEqual(self.f.run(), (0, 'BB_PLUGIN_REFRESH absent\n'))
        self.assertFalse(self.f.requests or self.f.commands)

    def test_custom_data_aliases_are_deduplicated_and_default_readiness_is_scoped(self):
        self.f.server()
        custom = self.f.server(39002, self.f.home / 'custom')
        alias = self.f.home / 'alias'
        alias.symlink_to(custom, target_is_directory=True)
        argv, env = self.f.records[-1]
        self.f.records.append((argv, dict(env, BB_DATA_DIR=str(alias))))
        self.assertEqual(self.f.run('block-default', {'BB_DATA_DIR': str(alias)}),
                         (0, 'BB_PLUGIN_REFRESH readiness-deferred\nBB_PLUGIN_REFRESH completed\n'))
        self.assertEqual(len(self.f.commands), 1)
        self.assertEqual(self.f.commands[0][1]['cwd'], custom)
        self.assertTrue(all(port == 39002 for port, _ in self.f.requests))
        self.f.records.clear()
        self.assertEqual(self.f.run('block-default', {'BB_DATA_DIR': str(custom)}),
                         (0, 'BB_PLUGIN_REFRESH readiness-deferred\nBB_PLUGIN_REFRESH stopped\n'))

    def test_files_are_not_subject_to_setup_trust_or_permission_repairs(self):
        data = self.f.server()
        credential = data / 'credential.json'
        credential.write_text('secret-sentinel')
        for path in (self.f.entry, self.f.cli, self.f.node, data / 'bb.db'):
            path.chmod(0o777)
        link = self.f.cli.with_name('native-cli')
        self.f.cli.rename(link)
        self.f.cli.symlink_to(link)
        before = {path: (path.lstat(), path.read_bytes()) for path in (self.f.entry, self.f.cli, self.f.node, credential, data / 'bb.db')}
        with patch.object(P.os, 'chmod', side_effect=AssertionError('permission repair forbidden')), \
                patch.object(P.os, 'chown', side_effect=AssertionError('ownership repair forbidden')):
            self.assertEqual(self.f.run(), (0, 'BB_PLUGIN_REFRESH completed\n'))
        self.assertEqual(before, {path: (path.lstat(), path.read_bytes()) for path in before})

    def test_local_selection_overrides_remote_context_without_environment_hardening(self):
        self.f.server()
        env = {'BB_SERVER_URL': 'https://remote.example.invalid', 'BB_CLI_REEXEC': '0',
               'BB_CLI': '/inert/other-cli', 'HTTP_PROXY': 'http://proxy.example.invalid',
               'NODE_OPTIONS': '--enable-source-maps', 'CUSTOM_NATIVE_SETTING': 'preserve'}
        self.assertEqual(self.f.run(environment=env), (0, 'BB_PLUGIN_REFRESH completed\n'))
        child = self.f.commands[0][1]['env']
        self.assertEqual(child['BB_SERVER_URL'], 'http://127.0.0.1:39001')
        self.assertEqual(child['BB_CLI_REEXEC'], '1')
        for key in ('HTTP_PROXY', 'NODE_OPTIONS', 'CUSTOM_NATIVE_SETTING'):
            self.assertEqual(child[key], env[key])

    def test_safe_mode_and_success_do_not_erase_an_earlier_failure(self):
        self.f.server()
        self.f.server(39002, self.f.home / 'second')
        self.f.server(39003, self.f.home / 'third')
        self.f.errors[39001] = subprocess.CalledProcessError(1, ['inert'], stderr=b'secret-sentinel')
        self.f.safe[39002] = {'enabled': True}
        status, text = self.f.run()
        self.assertEqual(status, 1)
        self.assertIn('failed update native-command-failed', text)
        self.assertIn('BB_PLUGIN_REFRESH safe-mode', text)
        self.assertIn('BB_PLUGIN_REFRESH completed', text)
        self.assertEqual(len(self.f.commands), 2)
        self.assertNotIn('sentinel', text)

    def test_unhealthy_malformed_safe_mode_and_http_failures_remain_failures(self):
        self.f.server()
        for health, safe, status, expected in (({'ok': False}, {}, 200, 'server-not-ready'),
                                               ({'ok': True, 'serverMove': {}}, {'enabled': False}, 503, 'native-request-failed'),
                                               ({'ok': True}, {'enabled': 'false'}, 200, 'malformed-result'),
                                               (b'not-json-secret-sentinel', {}, 200, 'malformed-result'),
                                               ([], {}, 200, 'malformed-result')):
            with self.subTest(expected=expected):
                self.f.health[39001], self.f.safe[39001], self.f.http_status = health, safe, status
                result, output = self.f.run()
                self.assertEqual(result, 1)
                self.assertIn('failed readiness ' + expected, output)
                self.assertNotIn('sentinel', output)
        self.assertFalse(self.f.commands)
        self.assertGreater(self.f.closed, 0)

    def test_timeouts_native_errors_and_inventory_errors_have_controlled_diagnostics(self):
        self.f.server()
        for error, reason in ((TimeoutError('secret-sentinel'), 'operation-timeout'),
                              (subprocess.TimeoutExpired('secret-sentinel', 1), 'operation-timeout'),
                              (RuntimeError('secret-sentinel'), 'unknown-failure')):
            with self.subTest(reason=reason):
                self.f.errors[39001] = error
                self.assertEqual(self.f.run(), (1, f'BB_PLUGIN_REFRESH failed update {reason}\n'))
        self.f.errors.clear()
        self.f.http_error = ConnectionRefusedError('secret-sentinel')
        self.assertEqual(self.f.run(), (1, 'BB_PLUGIN_REFRESH failed readiness native-request-failed\n'))
        self.f.inventory_error = subprocess.CalledProcessError(1, ['ps'], stderr=b'secret-sentinel')
        self.assertEqual(self.f.run(), (1, 'BB_PLUGIN_REFRESH failed discovery native-command-failed\n'))

    def test_import_move_invalid_policy_and_ports_do_not_run_updates(self):
        data = self.f.server()
        self.assertEqual(self.f.run('wrong-policy'), (1, 'BB_PLUGIN_REFRESH failed preflight invalid-policy\n'))
        for name in ('server-import.json', 'server-moved.json'):
            marker = data / name
            marker.write_text('{}')
            self.assertEqual(self.f.run(), (1, 'BB_PLUGIN_REFRESH failed discovery server-move-in-progress\n'))
            marker.unlink()
        for port in ('0', '65536', 'invalid-secret-sentinel'):
            self.f.records[0][1]['BB_SERVER_PORT'] = port
            status, text = self.f.run()
            self.assertEqual(status, 1)
            self.assertNotIn('sentinel', text)
        self.assertFalse(self.f.commands or self.f.requests)

    def test_whole_operation_deadline_and_expired_request_budget(self):
        with patch.object(P.time, 'monotonic', return_value=10), self.assertRaises(TimeoutError):
            P.remaining(10)
        events = []
        with patch.object(P.sys, 'argv', ['fixture', str(self.f.home)]), \
                patch.object(P.signal, 'signal', side_effect=lambda *_: events.append('signal')), \
                patch.object(P.signal, 'alarm', side_effect=lambda seconds: events.append(seconds)), \
                patch.object(P, 'discover', side_effect=TimeoutError()), contextlib.redirect_stdout(io.StringIO()) as output:
            self.assertEqual(P.run(), 1)
        self.assertEqual(events, ['signal', 1800, 0, 'signal'])
        self.assertEqual(output.getvalue(), 'BB_PLUGIN_REFRESH failed discovery operation-timeout\n')


class Callers(unittest.TestCase):
    def policy_outcomes(self):
        f = Fixture()
        self.addCleanup(f.close)
        absent = f.run()
        f.server()
        f.health[39001] = {'ok': False}
        refusal = f.run()
        f.health.clear()
        f.errors[39001] = TimeoutError()
        f.server(39002, f.home / 'second')
        f.safe[39002] = {'enabled': True}
        failure_then_deferral = f.run()
        self.assertEqual(absent, (0, 'BB_PLUGIN_REFRESH absent\n'))
        self.assertEqual(refusal, (1, 'BB_PLUGIN_REFRESH failed readiness server-not-ready\n'))
        self.assertEqual(failure_then_deferral[0], 1)
        self.assertIn('BB_PLUGIN_REFRESH safe-mode', failure_then_deferral[1])
        self.assertIn('BB_PLUGIN_REFRESH failed update operation-timeout', failure_then_deferral[1])
        return absent, refusal, failure_then_deferral

    def test_ubuntu_selection_readiness_and_preparation_failures_keep_boundaries(self):
        source = EXTRACT.definitions((ROOT / 'ubuntu.sh').read_text())
        caller = re.search(r'^run_setup_tasks\(\) \{\n.*?^\}', source, re.M | re.S).group()
        start = caller.index('    if [[ "${_bb_selection_status}" -eq 0 ]]; then')
        end = caller.index('    if ! prepare_pi_profile_permissions; then', start)
        seam = caller[start:end]
        cases = [(0, 0, 0, 0, 0, 'ready'), (0, 0, 1, 0, 0, 'block-default'),
                 (0, 1, 0, 0, 0, None), (1, 0, 0, 0, 0, 'ready'),
                 (1, 0, 0, 1, 0, 'ready'), (1, 0, 0, 0, 1, 'ready'), (2, 0, 0, 0, 1, None)]
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
                       'PLATFORM_FAIL': str(platform), 'SERVER_FAIL': str(server), 'PREP_FAIL': str(prep), 'EARLIER': str(earlier)}
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
            real = ('run_setup_tasks', 'main', 'refresh_bb_plugins')
            names = re.findall(r'^([A-Za-z_][A-Za-z_0-9]*)\(\) \{', selected, re.M)
            code = '\n'.join(f'{name}() {{ :; }}' for name in names if name not in real)
            for name in real:
                code += '\n' + re.search(rf'^{name}\(\) \{{\n.*?^\}}', selected, re.M | re.S).group()
            code += '''
bb_plugin_refresh_payload() { printf '%s\\n' "$FIXTURE_OUTPUT"; echo stderr-secret-sentinel >&2; return "$REFRESH_STATUS"; }
setup_bb_machine() { return "$EARLIER"; }
install_opencode_cli() { return "$EARLIER"; }
print_error() { printf '%s\\n' "$1"; }
print_warning() { printf '%s\\n' "$1"; }
print_message() { printf '%s\\n' "$1"; }
print_debug() { printf '%s\\n' "$1"; }
prepare_pi_profile_permissions() { echo unrelated; }
refresh_pi_packages() { echo later-pi-success; }
check_pending_reboot() { echo reboot-reported; }
start_setup_log() { echo logging; }
finish_setup_log() { echo "finalized:$1"; return "$1"; }
check_dotfiles_access() { return 1; }
setup_dotfiles_deploy_key() { return 1; }
is_main_user() { return 0; }
bb_server_selection() { return "$SELECTION"; }
whoami() { echo fixture; }
brew() { :; }
unzip() { :; }
MACOS_DEVELOPER_TOOLS_STATE=ready
MACOS_CLT_OPERATION_FAILED=0
DOTFILES_ACCESS_METHOD=none
'''
            for cmd in ('systemctl', 'launchctl', 'loginctl', 'pgrep', 'ps', 'curl', 'npm',
                        'bun', 'pi', 'bb', 'chezmoi', 'sudo', 'kill', 'pkill', 'tailscale'):
                code += f'\n{cmd}() {{ echo FORBIDDEN:{cmd}; return 99; }}'
            code += '\nmain\n'
            cases = [(0, 'BB_PLUGIN_REFRESH completed'), (0, 'BB_PLUGIN_REFRESH stopped'),
                     (0, 'BB_PLUGIN_REFRESH safe-mode'), (1, 'BB_PLUGIN_REFRESH completed'),
                     (0, 'secret-sentinel'), *outcomes]
            for status, text in cases:
                for earlier in (0, 1):
                    for selection in ((0, 1) if script == 'ubuntu' else (1,)):
                        expected = int(bool(status or earlier or text == 'secret-sentinel'))
                        with tempfile.TemporaryDirectory(prefix='bb-refresh-caller-') as home:
                            env = {'HOME': home, 'PATH': '/usr/bin:/bin', 'REFRESH_STATUS': str(status),
                                   'EARLIER': str(earlier), 'FIXTURE_OUTPUT': text, 'SELECTION': str(selection),
                                   'USER': 'fixture', 'LANG': 'C', 'TERM': 'dumb'}
                            result = subprocess.run(['/bin/bash', '-c', code], env=env, cwd=home,
                                                    stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=15)
                        with self.subTest(script=script, text=text, earlier=earlier, selection=selection):
                            self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
                            for marker in ('logging', 'unrelated', 'later-pi-success', 'reboot-reported', f'finalized:{expected}'):
                                self.assertIn(marker, result.stdout)
                            self.assertNotIn('FORBIDDEN:', result.stdout + result.stderr)
                            self.assertNotIn('sentinel', result.stdout + result.stderr)
        self.assertNotIn('refresh_bb_plugins', (ROOT / 'win.ps1').read_text())

    def test_real_log_finalization_preserves_failure_and_deferral(self):
        selected = EXTRACT.definitions((ROOT / 'mac.sh').read_text())
        real = ('run_setup_tasks', 'main', 'refresh_bb_plugins', 'start_setup_log', 'finish_setup_log')
        names = re.findall(r'^([A-Za-z_][A-Za-z_0-9]*)\(\) \{', selected, re.M)
        code = '\n'.join(f'{name}() {{ :; }}' for name in names if name not in real)
        for name in real:
            code += '\n' + re.search(rf'^{name}\(\) \{{\n.*?^\}}', selected, re.M | re.S).group()
        code += r'''
print_error() { printf '%s\n' "$*"; }
print_warning() { printf '%s\n' "$*"; }
print_message() { printf '%s\n' "$*"; }
print_debug() { printf '%s\n' "$*"; }
install_xcode_cli_tools() { echo early-operation; return "$EARLIER"; }
install_gitea_client() { echo independent-success; }
bb_plugin_refresh_payload() { printf '%s\n' "$FIXTURE_OUTPUT"; return "$REFRESH_STATUS"; }
refresh_pi_packages() { echo later-pi-success; }
check_pending_reboot() { echo reboot-reported; }
check_dotfiles_access() { return 1; }
setup_dotfiles_deploy_key() { return 1; }
is_main_user() { return 0; }
whoami() { echo fixture; }
upload_log() { cp -- "$SETUP_LOG_FILE" "$HOME/completed-upload.log"; }
'''
        for command in ('curl', 'sudo', 'brew', 'chezmoi', 'bb', 'npm', 'ps', 'pgrep', 'launchctl', 'kill', 'pkill', 'tailscale'):
            code += f'\n{command}() {{ echo FORBIDDEN:{command}; return 99; }}'
        code += '\nmain\n'
        for earlier in (0, 1):
            for status, text in [(0, 'BB_PLUGIN_REFRESH safe-mode'), (0, 'BB_PLUGIN_REFRESH stopped'), *self.policy_outcomes()]:
                expected = int(bool(earlier or status))
                with tempfile.TemporaryDirectory(prefix='bb-refresh-final-log-') as home:
                    result = subprocess.run(['/bin/bash', '-c', code], cwd=home,
                                            env={'HOME': home, 'PATH': '/usr/bin:/bin', 'EARLIER': str(earlier),
                                                 'FIXTURE_OUTPUT': text, 'REFRESH_STATUS': str(status), 'TERM': 'dumb'},
                                            stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=15)
                    self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
                    logs = list((Path(home) / '.local/log/machine-setup').glob('*.log'))
                    self.assertEqual(len(logs), 1)
                    log = logs[0].read_text()
                    self.assertEqual((Path(home) / 'completed-upload.log').read_text(), log)
                    summary = 'Setup completed with errors' if expected else '✨ Setup complete!'
                    milestones = ['early-operation', 'independent-success', 'later-pi-success', 'reboot-reported', summary, 'Run log saved to:']
                    self.assertEqual([log.index(marker) for marker in milestones], sorted(log.index(marker) for marker in milestones))
                    self.assertEqual(log.count('Run log saved to:'), 1)
                    self.assertNotIn('FORBIDDEN:', result.stdout + result.stderr + log)
                    self.assertEqual(result.stderr, '')

    def test_wrapper_rejects_uncontrolled_diagnostics_and_retains_failure_status(self):
        source = (ROOT / 'lib/bb-plugin-refresh.bash').read_text().split('\nbb_plugin_refresh_payload()', 1)[0]
        code = source + '\n' + '\n'.join(f'{name}() {{ printf "%s\\n" "$1"; }}' for name in
                                         ('print_section', 'print_message', 'print_error', 'print_warning', 'print_debug'))
        code += '\nbb_plugin_refresh_payload() { printf "%s\\n" "$FIXTURE_OUTPUT"; echo stderr-secret-sentinel >&2; return "$FIXTURE_STATUS"; }\nrefresh_bb_plugins\n'
        refused = ('', 'secret-sentinel', 'BB_PLUGIN_REFRESH failed secret-sentinel operation-timeout',
                   'BB_PLUGIN_REFRESH failed discovery secret-sentinel',
                   'BB_PLUGIN_REFRESH failed readiness server-not-ready /secret-sentinel',
                   'BB_PLUGIN_REFRESH failed readiness server-not-ready\rsecret-sentinel',
                   'BB_PLUGIN_REFRESH failed readiness server-not-ready\nsecret-sentinel',
                   'BB_PLUGIN_REFRESH completed\n' * 700)
        cases = [(text, 0, 1) for text in refused]
        cases += [('BB_PLUGIN_REFRESH completed', 1, 1), ('BB_PLUGIN_REFRESH completed', 0, 0),
                  ('BB_PLUGIN_REFRESH failed', 0, 1), ('BB_PLUGIN_REFRESH safe-mode', 0, 0),
                  ('BB_PLUGIN_REFRESH failed update operation-timeout', 0, 1)]
        for text, status, expected in cases:
            with tempfile.TemporaryDirectory(prefix='bb-refresh-wrapper-') as home:
                result = subprocess.run(['/bin/bash', '-c', code], cwd=home,
                                        env={'HOME': home, 'PATH': '/usr/bin:/bin', 'FIXTURE_OUTPUT': text, 'FIXTURE_STATUS': str(status)},
                                        stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=5)
            self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
            self.assertNotIn('sentinel', result.stdout + result.stderr)
            self.assertLess(len(result.stdout + result.stderr), 500)


if __name__ == '__main__':
    unittest.main(verbosity=2)
