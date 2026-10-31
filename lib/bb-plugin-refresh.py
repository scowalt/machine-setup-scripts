import ctypes
import http.client
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time


class Refusal(Exception):
    pass


def need(value, reason):
    if not value:
        raise Refusal(reason)


def main_entry(argv):
    return next((Path(arg) for arg in argv[1:] if arg.endswith('/server/dist/index.js')), None)


def process_record(pid):
    if sys.platform == 'linux':
        root = Path('/proc') / str(pid)
        argv = [arg.decode() for arg in (root / 'cmdline').read_bytes().split(b'\0') if arg]
        raw_env = (root / 'environ').read_bytes() if main_entry(argv) else b''
    else:
        libc = ctypes.CDLL('/usr/lib/libSystem.B.dylib', use_errno=True)
        maximum = ctypes.c_int()
        size = ctypes.c_size_t(ctypes.sizeof(maximum))
        if libc.sysctlbyname(b'kern.argmax', ctypes.byref(maximum), ctypes.byref(size), None, 0):
            raise OSError(ctypes.get_errno(), 'process inventory unavailable')
        buffer = ctypes.create_string_buffer(maximum.value)
        size = ctypes.c_size_t(maximum.value)
        mib = (ctypes.c_int * 3)(1, 49, pid)
        if libc.sysctl(mib, 3, buffer, ctypes.byref(size), None, 0):
            raise OSError(ctypes.get_errno(), 'process arguments unavailable')
        raw = buffer.raw[:size.value]
        argc = int.from_bytes(raw[:4], sys.byteorder, signed=True)
        values = raw[4:].split(b'\0', 1)[1].lstrip(b'\0').split(b'\0')
        argv = [arg.decode() for arg in values[:argc]]
        raw_env = b'\0'.join(values[argc:])
    env = {}
    for item in raw_env.split(b'\0'):
        key, separator, value = item.partition(b'=')
        if separator and key in (b'HOME', b'BB_DATA_DIR', b'BB_SERVER_PORT'):
            env[key.decode()] = value.decode()
    return argv, env


def processes():
    need(sys.platform in ('linux', 'darwin'), 'unsupported-platform')
    darwin = sys.platform == 'darwin'
    command = ['/bin/ps', '-U', str(os.getuid()), '-o', 'pid=,args=' if darwin else 'pid=']
    if darwin:
        command.append('-ww')
    result = subprocess.run(command, stdin=subprocess.DEVNULL, capture_output=True, text=True,
                            timeout=10, check=True)
    for line in result.stdout.splitlines():
        fields = line.split(maxsplit=1)
        if not fields:
            continue
        if darwin and (len(fields) < 2 or '/server/dist/index.js' not in fields[1]):
            continue
        try:
            yield process_record(int(fields[0]))
        except (FileNotFoundError, ProcessLookupError):
            continue


def discover(home, block_default=False):
    default = (home / '.bb').resolve()
    data_dirs = {default}
    if os.environ.get('BB_DATA_DIR'):
        data_dirs.add(Path(os.environ['BB_DATA_DIR']).resolve())
    servers = {}
    for argv, env in processes():
        entry = main_entry(argv)
        if entry is None:
            continue
        package = entry.parents[2]
        cli = package / 'host-daemon/dist/bb'
        if package.name != 'bb-app' and not cli.is_file():
            continue
        data = Path(env.get('BB_DATA_DIR') or str(Path(env.get('HOME') or home) / '.bb')).resolve()
        if block_default and data == default:
            continue
        need(not (data / 'server-moved.json').exists() and not (data / 'server-import.json').exists(),
             'server-move-in-progress')
        port = int(env.get('BB_SERVER_PORT', '38886'))
        need(0 < port < 65536, 'invalid-port')
        servers.setdefault(data, {'node': argv[0], 'cli': cli, 'data': data, 'port': port})
    stopped = False
    for data in data_dirs - servers.keys():
        if block_default and data == default or (data / 'server-moved.json').exists():
            continue
        need(not (data / 'server-import.json').exists(), 'server-move-in-progress')
        stopped |= (data / 'bb.db').exists() or (data / 'bb-app-runtime.json').exists()
    return list(servers.values()), stopped


def remaining(deadline):
    seconds = deadline - time.monotonic()
    if seconds <= 0:
        raise TimeoutError()
    return seconds


def request(port, path, deadline):
    connection = http.client.HTTPConnection('127.0.0.1', port, timeout=min(10, remaining(deadline)))
    try:
        connection.request('GET', path, headers={'Accept-Encoding': 'identity'})
        response = connection.getresponse()
        need(response.status == 200, 'native-request-failed')
        value = json.loads(response.read())
        need(isinstance(value, dict), 'malformed-result')
        return value
    finally:
        connection.close()


def update(server, home, deadline):
    env = dict(os.environ, HOME=str(home), BB_DATA_DIR=str(server['data']),
               BB_SERVER_URL=f"http://127.0.0.1:{server['port']}", BB_CLI_REEXEC='1',
               ELECTRON_RUN_AS_NODE='1', NO_COLOR='1')
    subprocess.run([server['node'], str(server['cli']), 'plugin', 'update', '--all', '--yes'],
                   cwd=server['data'], env=env, stdin=subprocess.DEVNULL,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                   timeout=remaining(deadline), check=True)


def report(operation, error):
    reason = 'unknown-failure'
    if isinstance(error, (TimeoutError, subprocess.TimeoutExpired)):
        reason = 'operation-timeout'
    elif isinstance(error, subprocess.CalledProcessError):
        reason = 'native-command-failed'
    elif isinstance(error, (ConnectionError, http.client.HTTPException)):
        reason = 'native-request-failed'
    elif isinstance(error, PermissionError):
        reason = 'native-permission-denied'
    elif isinstance(error, OSError):
        reason = 'native-system-error'
    elif isinstance(error, (ValueError, UnicodeError)):
        reason = 'malformed-result'
    elif type(error) is Refusal:
        reason = error.args[0]
    print(f'BB_PLUGIN_REFRESH failed {operation} {reason}')


def run():
    operation = 'preflight'
    previous = signal.signal(signal.SIGALRM, lambda *_: (_ for _ in ()).throw(TimeoutError()))
    signal.alarm(1800)
    try:
        home = Path(sys.argv[1]).resolve()
        policy = sys.argv[2] if len(sys.argv) > 2 else 'ready'
        need(policy in ('ready', 'block-default'), 'invalid-policy')
        deadline = time.monotonic() + 1800
        operation = 'discovery'
        servers, stopped = discover(home, policy == 'block-default')
        if policy == 'block-default':
            print('BB_PLUGIN_REFRESH readiness-deferred')
        if stopped:
            print('BB_PLUGIN_REFRESH stopped')
        if not stopped and not servers:
            print('BB_PLUGIN_REFRESH absent')
        failed = False
        for server in servers:
            try:
                operation = 'readiness'
                health = request(server['port'], '/health', deadline)
                need(health.get('ok') is True and not health.get('serverMove'), 'server-not-ready')
                safe = request(server['port'], '/api/v1/plugins/safe-mode', deadline)
                need(type(safe.get('enabled')) is bool, 'malformed-result')
                if safe['enabled']:
                    print('BB_PLUGIN_REFRESH safe-mode')
                    continue
                operation = 'update'
                update(server, home, deadline)
                print('BB_PLUGIN_REFRESH completed')
            except Exception as error:
                failed = True
                report(operation, error)
        return int(failed)
    except Exception as error:
        report(operation, error)
        return 1
    finally:
        signal.alarm(0)
        signal.signal(signal.SIGALRM, previous)


if __name__ == '__main__':
    raise SystemExit(run())
