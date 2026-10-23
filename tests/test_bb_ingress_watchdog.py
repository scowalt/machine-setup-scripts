#!/usr/bin/env python3
import json
import os
from pathlib import Path
import signal
import shutil
import subprocess
import tempfile
import time
import unittest

from extract_setup_fixture import definitions

ROOT = Path(__file__).resolve().parents[1]
SECRET = 'DO-NOT-LOG-WATCHDOG-FIXTURE'
FIXTURE_TOOL = r'''#!/usr/bin/python3
import json, os, pathlib, signal, sys, time
root = pathlib.Path(os.environ['BB_GUARD_TEST_ROOT'])
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
config = json.loads((root / 'case.json').read_text())
cycle = int((root / 'cycle').read_text())

def event(kind, **extra):
    with (root / 'events.jsonl').open('a') as out:
        out.write(json.dumps({'kind': kind, 'cycle': cycle, **extra}) + '\n')

def scenario():
    plan = config['plan']
    return config['startup'] if cycle == 0 else plan[min(cycle - 1, len(plan) - 1)]

def has(value):
    return value in scenario().split('+')

if name == 'tailscale':
    if args == ['version', '--daemon', '--json']:
        print(json.dumps({'short': '1.104.1', 'daemonLong': '1.104.1'}))
    elif args == ['status', '--json']:
        print(json.dumps({'BackendState': 'Stopped' if has('tailnet-lost') else 'Running',
                          'Self': {'DNSName': 'bb-watchdog.example.ts.net.'}}))
    elif args == ['serve', '--https=38443', 'http://127.0.0.1:38886']:
        event('serve-start', args=args)
        def stop(*_):
            event('serve-stop')
            sys.exit(0)
        signal.signal(signal.SIGTERM, stop)
        signal.signal(signal.SIGINT, stop)
        while True:
            if (root / 'exit-serve').exists():
                event('serve-exit')
                (root / 'serve-exited').touch()
                sys.exit(config['serve_exit'])
            time.sleep(0.01)
    else:
        raise SystemExit('Unexpected tailscale fixture invocation')
elif name == 'systemctl':
    if args == ['--user', 'show', 'setup-bb-app.service', '--property=MainPID', '--value']:
        print(0 if has('ownership-lost') else os.environ['BB_GUARD_TEST_PID'])
    elif args == ['--user', 'is-active', '--quiet', 'setup-bb-app.service']:
        sys.exit(3 if has('app-inactive') else 0)
    elif args == ['--user', 'start', '--no-block', 'setup-bb-ingress.service']:
        event('ingress-queued')
    else:
        raise SystemExit('Unexpected systemctl fixture invocation')
elif name == 'sleep':
    if args not in (['5'], ['0']):
        raise SystemExit('Unexpected polling/readiness sleep')
    cycle += 1
    next_cycle = root / 'cycle.next'
    next_cycle.write_text(str(cycle))
    next_cycle.replace(root / 'cycle')
    if cycle > config['cycles']:
        event('observation-finished')
        while not (root / 'release-sleep').exists():
            time.sleep(0.01)
    else:
        event('check-start')
        data = pathlib.Path(os.environ['HOME']) / '.bb'
        host = data / 'host-id'
        if has('unsafe-host-mode'):
            host.chmod(0o644)
        if has('linked-host'):
            host.rename(data / 'host-target')
            host.symlink_to('host-target')
        if has('hardlinked-host'):
            os.link(host, data / 'host-copy')
        for state, file, content in [
            ('malformed-auth', 'auth.json', '{DO-NOT-LOG-WATCHDOG-FIXTURE'),
            ('auth-array', 'auth.json', '[]'),
            ('env-array', 'env.json', '[]'),
            ('env-layer-array', 'env.json', '{"env":[]}'),
            ('identity-conflict', 'auth.json', '{"hostId":"other-host"}'),
        ]:
            if has(state):
                target = data / file
                target.write_text(content)
                target.chmod(0o600)
        if has('serve-exit'):
            (root / 'exit-serve').touch()
            while not (root / 'serve-exited').exists():
                time.sleep(0.01)
elif name == 'curl':
    url = args[-1]
    if url not in ('http://127.0.0.1:38886/health', 'http://127.0.0.1:38887/status'):
        raise SystemExit('Unexpected curl fixture URL')
    timeout = float(args[args.index('--max-time') + 1])
    event('curl', url=url, timeout=timeout)
    health = url.endswith('/health')
    if has('two-second-stall' if health else 'two-second-status-stall') and timeout < 2:
        sys.exit(28)
    if has('timeout' if health else 'status-timeout'):
        print('DO-NOT-LOG-WATCHDOG-FIXTURE', file=sys.stderr)
        sys.exit(28)
    if has('http-failure' if health else 'status-http-failure'):
        sys.exit(22)
    if has('malformed-health' if health else 'malformed-status'):
        print('{DO-NOT-LOG-WATCHDOG-FIXTURE')
        sys.exit(0)
    if health:
        value = {'ok': not has('health-not-ok'), 'launchId': 'fixture-launch'}
        if has('empty-launch'):
            value['launchId'] = ''
        if has('launch-type'):
            value['launchId'] = 3
        if has('health-null'):
            value = None
        if has('health-array'):
            value = []
    else:
        value = {'connected': not has('daemon-disconnected'),
                 'hostId': 'wrong-host' if has('wrong-host') else 'fixture-host',
                 'serverUrl': 'http://wrong.example' if has('wrong-server') else 'http://127.0.0.1:38886'}
        if has('localhost-server'):
            value['serverUrl'] = 'http://localhost:38886/'
        for state, connected in [('connected-string', 'false'), ('connected-number', 0), ('connected-null', None)]:
            if has(state):
                value['connected'] = connected
        if has('connected-missing'):
            del value['connected']
        if has('status-null'):
            value = None
        if has('status-array'):
            value = []
    print(json.dumps(value))
else:
    raise SystemExit('Unexpected fixture tool')
'''


class BbIngressWatchdogTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        sandbox = os.environ.get('FIXTURE_NETWORK_SANDBOX')
        if not sandbox:
            raise RuntimeError('Use tests/run-fixture-matrix.py; no uncontained fallback')
        subprocess.run([sandbox, '--assert-inherited-denial'], check=True,
                       stdin=subprocess.DEVNULL, capture_output=True, timeout=10)
        cls.source = definitions((ROOT / 'ubuntu.sh').read_text())

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='bb-watchdog-test-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.home = self.root / 'home'
        state = self.home / '.config/setup-bb-server'
        state.mkdir(parents=True)
        endpoint = state / 'endpoint'
        endpoint.write_text('bb-watchdog.example.ts.net 38443 https://bb-watchdog.example.ts.net:38443\n')
        endpoint.chmod(0o600)
        data = self.home / '.bb'
        data.mkdir()
        host = data / 'host-id'
        host.write_text('fixture-host\n')
        host.chmod(0o600)
        self.helpers = self.root / 'definitions.sh'
        self.helpers.write_text(self.source)
        self.guard = state / 'bb-guard'
        tools = self.root / 'bin'
        tools.mkdir()
        entry = tools / 'fixture-tool'
        entry.write_text(FIXTURE_TOOL)
        entry.chmod(0o700)
        for name in ('curl', 'sleep', 'systemctl', 'tailscale'):
            (tools / name).symlink_to(entry.name)
        self.env = dict(os.environ, HOME=str(self.home),
                        PATH=str(tools) + os.pathsep + os.environ['PATH'],
                        BB_PACKAGE_BINARY='/bin/sleep', BB_TAILSCALE_BIN=str(tools / 'tailscale'),
                        BB_GUARD_TEST_ROOT=str(self.root), BB_READY_ATTEMPTS='2', BB_READY_INTERVAL='0')
        self.render_guard()

    def render_guard(self):
        result = subprocess.run(
            ['/bin/bash', '--noprofile', '--norc', '-euo', 'pipefail', '-c',
             'source "$1"; bb_write_bb_guard "$2"', '_', str(self.helpers), str(self.guard)],
            env=self.env, cwd=self.root, stdin=subprocess.DEVNULL, capture_output=True,
            text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)

    def events(self):
        path = self.root / 'events.jsonl'
        if not path.exists():
            return []
        return [json.loads(line) for line in path.read_text().splitlines(keepends=True)
                if line.endswith('\n')]

    def run_case(self, plan, cycles, expected_exit_cycle=None, *, startup='healthy',
                 mode='ingress-start', startup_failure=False, stop_signal=None, serve_exit=0):
        (self.root / 'case.json').write_text(json.dumps({
            'plan': plan, 'cycles': cycles, 'startup': startup, 'serve_exit': serve_exit}))
        (self.root / 'cycle').write_text('0')
        (self.root / 'events.jsonl').write_text('')
        (self.root / 'release-sleep').unlink(missing_ok=True)
        managed = subprocess.Popen(['/bin/sleep', '120'], stdin=subprocess.DEVNULL,
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        env = dict(self.env, BB_GUARD_TEST_PID=str(managed.pid))
        proc = None
        stderr_path = self.root / 'stderr'
        try:
            with stderr_path.open('w') as stderr:
                proc = subprocess.Popen(['/bin/bash', '--noprofile', '--norc', str(self.guard), mode],
                                        env=env, cwd=self.root, stdin=subprocess.DEVNULL,
                                        stdout=subprocess.DEVNULL, stderr=stderr, start_new_session=True)
                deadline = time.monotonic() + 15
                observed = False
                while time.monotonic() < deadline:
                    if proc.poll() is not None:
                        break
                    if any(e['kind'] == 'observation-finished' for e in self.events()):
                        observed = True
                        break
                    time.sleep(0.01)
                if stop_signal is not None:
                    self.assertTrue(observed, 'guard did not reach the signal checkpoint')
                    proc.send_signal(stop_signal)
                    (self.root / 'release-sleep').touch()
                    proc.wait(timeout=3)
                events = self.events()
                output = stderr_path.read_text()
                self.assertNotIn(SECRET, output)
                self.assertNotIn(str(self.home), output)
                starts = [e for e in events if e['kind'] == 'serve-start']
                stops = [e for e in events if e['kind'] == 'serve-stop']
                checks = [e['cycle'] for e in events if e['kind'] == 'check-start']
                if startup_failure:
                    self.assertEqual(proc.poll(), 1, output)
                    self.assertFalse(starts, 'startup exposed ingress before full readiness')
                    self.assertFalse(any(e['kind'] == 'ingress-queued' for e in events))
                    return output
                self.assertIsNone(managed.poll(), 'guard stopped the managed app fixture')
                self.assertEqual(len(starts), 1, output)
                self.assertEqual(starts[0]['args'], ['serve', '--https=38443', 'http://127.0.0.1:38886'])
                if stop_signal is not None:
                    self.assertEqual(proc.returncode, 0, output)
                    self.assertEqual(len(stops), 1, output)
                elif 'serve-exit' in plan:
                    self.assertEqual(proc.poll(), serve_exit, output)
                elif expected_exit_cycle is None:
                    self.assertIsNone(proc.poll(), output)
                    self.assertTrue(observed, 'watchdog did not finish the observation window')
                    self.assertFalse(stops, 'transient condition removed ingress')
                else:
                    self.assertEqual(proc.poll(), 1, output)
                    self.assertEqual(len(stops), 1, output)
                    self.assertEqual(max(checks, default=0), expected_exit_cycle, output)
                startup_http = [e for e in events if e['kind'] == 'curl' and e['cycle'] == 0]
                self.assertEqual(len(startup_http), 2)
                self.assertTrue(all(e['timeout'] == 1 for e in startup_http))
                runtime_http = [e for e in events if e['kind'] == 'curl' and e['cycle'] > 0]
                self.assertTrue(all(e['timeout'] == 5 for e in runtime_http), runtime_http)
                if expected_exit_cycle is not None:
                    self.assertIn('stopping ingress', output)
                return output
        finally:
            if proc is not None:
                try:
                    os.killpg(proc.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
                try:
                    proc.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    os.killpg(proc.pid, signal.SIGKILL)
                    proc.wait()
            managed.terminate()
            managed.wait(timeout=3)

    def test_two_second_stall_preserves_ingress(self):
        self.run_case(['two-second-stall', 'healthy'], 2)

    def test_one_timeout_recovers(self):
        output = self.run_case(['timeout', 'healthy'], 2)
        self.assertIn('transient health failure (1/3)', output)
        self.assertIn('health recovered after 1 transient failure(s)', output)

    def test_two_timeouts_recover(self):
        output = self.run_case(['timeout', 'timeout', 'healthy'], 3)
        self.assertIn('health recovered after 2 transient failure(s)', output)

    def test_success_resets_consecutive_failure_count(self):
        output = self.run_case(['timeout', 'timeout', 'healthy', 'timeout', 'timeout', 'healthy'], 6)
        self.assertEqual(output.count('transient health failure (1/3)'), 2)
        self.assertEqual(output.count('health recovered after 2 transient failure(s)'), 2)
        self.assertNotIn('(3/3)', output)

    def test_temporary_daemon_disconnect_recovers(self):
        self.run_case(['daemon-disconnected', 'healthy'], 2)

    def test_three_timeouts_fail_closed_on_third_check(self):
        output = self.run_case(['timeout'], 4, 3)
        self.assertIn('transient health failure (3/3)', output)
        self.assertIn('three consecutive transient HTTP/daemon failures', output)

    def test_three_daemon_disconnects_fail_closed_on_third_check(self):
        self.run_case(['daemon-disconnected'], 4, 3)

    def test_malformed_health_fails_closed_immediately(self):
        self.run_case(['malformed-health'], 2, 1)

    def test_wrong_daemon_identity_fails_closed_immediately(self):
        self.run_case(['wrong-host'], 2, 1)

    def test_wrong_daemon_server_fails_closed_immediately(self):
        self.run_case(['wrong-server'], 2, 1)

    def test_process_ownership_loss_fails_closed_immediately(self):
        output = self.run_case(['ownership-lost'], 2, 1)
        self.assertIn('app process/identity/security validation failed', output)

    def test_tailnet_loss_fails_closed_immediately(self):
        output = self.run_case(['tailnet-lost'], 2, 1)
        self.assertIn('tailnet validation failed', output)
        self.assertNotIn('transient health failure', output)

    def test_inactive_app_service_fails_closed_immediately(self):
        output = self.run_case(['app-inactive'], 2, 1)
        self.assertIn('app service inactive', output)
        self.assertNotIn('transient health failure', output)

    def test_both_endpoints_have_independent_runtime_timeouts(self):
        self.run_case(['two-second-status-stall', 'healthy'], 2)

    def test_http_status_failures_and_status_timeouts_are_transient(self):
        for state in ('http-failure', 'status-http-failure', 'status-timeout'):
            with self.subTest(state=state):
                self.run_case([state, 'healthy'], 2)
                self.run_case([state], 4, 3)

    def test_mixed_transient_failures_share_one_counter(self):
        self.run_case(['timeout', 'daemon-disconnected', 'status-timeout'], 4, 3)

    def test_disconnected_daemon_must_pass_all_identity_checks_first(self):
        for state in ('wrong-host', 'wrong-server', 'connected-string', 'connected-number',
                      'connected-null', 'connected-missing', 'malformed-status', 'status-null', 'status-array'):
            with self.subTest(state=state):
                output = self.run_case(['daemon-disconnected+' + state], 2, 1)
                self.assertNotIn('transient health failure', output)

    def test_invalid_health_schema_and_launch_identity_are_not_transient(self):
        for state in ('health-not-ok', 'empty-launch', 'launch-type', 'health-null', 'health-array'):
            with self.subTest(state=state):
                self.run_case([state], 2, 1)

    def test_unsafe_local_identity_metadata_is_not_transient(self):
        for state in ('unsafe-host-mode', 'linked-host', 'hardlinked-host', 'malformed-auth',
                      'auth-array', 'env-array', 'env-layer-array', 'identity-conflict'):
            with self.subTest(state=state):
                with tempfile.TemporaryDirectory(dir=self.root) as directory:
                    original = self.home
                    self.home = Path(directory) / 'home'
                    shutil.copytree(original, self.home, symlinks=True)
                    self.env['HOME'] = str(self.home)
                    try:
                        self.run_case([state], 2, 1)
                    finally:
                        self.home = original
                        self.env['HOME'] = str(original)

    def test_transport_failure_cannot_mask_a_known_identity_failure(self):
        for state in ('timeout+wrong-host', 'timeout+wrong-server',
                      'malformed-health+status-timeout', 'unsafe-host-mode+timeout'):
            with self.subTest(state=state):
                output = self.run_case([state], 2, 1)
                self.assertNotIn('transient health failure', output)

    def test_localhost_daemon_server_normalization_is_preserved(self):
        self.run_case(['localhost-server+daemon-disconnected', 'localhost-server'], 2)

    def test_startup_and_readiness_never_apply_runtime_grace(self):
        for mode in ('ingress-start', 'app-ready'):
            for state in ('two-second-stall', 'timeout', 'status-timeout', 'daemon-disconnected',
                          'wrong-host', 'wrong-server', 'malformed-health', 'connected-string'):
                with self.subTest(mode=mode, state=state):
                    self.run_case([state], 2, startup=state, mode=mode, startup_failure=True)
                    self.assertTrue(all(e['timeout'] == 1 for e in self.events() if e['kind'] == 'curl'))

    def test_group_write_alone_preserves_startup_runtime_and_endpoint_checks(self):
        data = self.home / '.bb'
        (data / 'auth.json').write_text('{"hostId":"fixture-host"}')
        (data / 'env.json').write_text('{"env":{"BB_HOST_ID":"fixture-host"}}')
        for target in (data / 'host-id', data / 'auth.json', data / 'env.json',
                       self.home / '.config/setup-bb-server/endpoint'):
            target.chmod(0o620)
        self.run_case(['healthy'], 1)

    def test_unsafe_endpoint_metadata_prevents_startup(self):
        endpoint = self.home / '.config/setup-bb-server/endpoint'
        endpoint.chmod(0o644)
        self.run_case(['healthy'], 1, startup_failure=True)
        self.assertEqual(self.events(), [])

    def test_term_and_int_clean_up_only_the_serve_child(self):
        for requested in (signal.SIGTERM, signal.SIGINT):
            with self.subTest(signal=requested):
                self.run_case(['healthy'], 1, stop_signal=requested)

    def test_serve_child_exit_status_is_preserved(self):
        for status in (0, 7):
            with self.subTest(status=status):
                (self.root / 'exit-serve').unlink(missing_ok=True)
                (self.root / 'serve-exited').unlink(missing_ok=True)
                self.run_case(['serve-exit'], 2, serve_exit=status)

    def test_regeneration_is_byte_and_metadata_idempotent(self):
        for mode in (0o700, 0o720):
            self.guard.chmod(mode)
            os.utime(self.guard, ns=(1_700_000_000_000_000_000, 1_700_000_000_000_000_000))
            before = self.guard.stat()
            content = self.guard.read_bytes()
            for _ in range(2):
                self.render_guard()
                after = self.guard.stat()
                for field in ('st_dev', 'st_ino', 'st_uid', 'st_gid', 'st_mode', 'st_nlink', 'st_mtime_ns', 'st_ctime_ns'):
                    self.assertEqual(getattr(after, field), getattr(before, field), field)
                self.assertEqual(self.guard.read_bytes(), content)
                self.assertEqual(after.st_mode & 0o7777, mode)
                self.assertEqual(list(self.guard.parent.glob('bb-guard.*')), [])

    def test_regeneration_replaces_old_guard_and_retains_private_mode(self):
        content = self.guard.read_bytes()
        self.guard.write_text('#!/usr/bin/env bash\n# setup-managed bb lifecycle guard v1\nexit 1\n')
        self.guard.chmod(0o600)
        self.render_guard()
        self.assertEqual(self.guard.read_bytes(), content)
        self.assertEqual(self.guard.stat().st_mode & 0o7777, 0o700)
        self.guard.chmod(0o755)
        self.render_guard()
        self.assertEqual(self.guard.stat().st_mode & 0o7777, 0o700)

    def test_generated_guard_syntax_and_shellcheck(self):
        for command in (['/bin/bash', '-n', str(self.guard)], ['shellcheck', str(self.guard)]):
            result = subprocess.run(command, env=self.env, cwd=ROOT, stdin=subprocess.DEVNULL,
                                    capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main(verbosity=2)
