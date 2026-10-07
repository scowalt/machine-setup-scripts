import ctypes
import http.client
import json
import os
from pathlib import Path
import re
import signal
import socket
import stat
import subprocess
import sys
import time

MAX_BYTES = 8388608
MAX_PROCESSES = 32768
MAX_PLUGINS = 1024


class Refusal(Exception):
    pass


class Diagnostics:
    def __init__(self):
        self.operation = 'preflight'
        self.first = None

    def record(self, error):
        if self.first is not None:
            return
        operations = ('preflight', 'discovery', 'identity', 'inventory', 'source-check',
                      'update-check', 'update', 'verification')
        reasons = ('activation-failed', 'activation-unverified', 'ambiguous-endpoint',
                   'ambiguous-main-server', 'ambiguous-process', 'changed-local-state',
                   'changed-plugin-intent', 'changed-plugin-inventory', 'changed-preserved-plugin',
                   'changed-process', 'changed-source-resolution', 'foreign-local-state',
                   'foreign-process', 'incomplete-results', 'malformed-result',
                   'native-request-failed', 'operation-timeout', 'process-proof-unavailable', 'rolled-back',
                   'server-move-in-progress', 'source-unavailable', 'unexpected-update-selection', 'unsupported-account',
                   'unsupported-native-contract', 'unsupported-platform', 'unverified-compatibility',
                   'unverified-home', 'unverified-local-state', 'unverified-main-server',
                   'unverified-peer', 'unverified-policy', 'unverified-result',
                   'unverified-source-intent', 'update-unverified', 'writable-local-state')
        reason = error.args[0] if type(error) is Refusal and len(error.args) == 1 else None
        if isinstance(error, (TimeoutError, subprocess.TimeoutExpired)):
            reason = 'operation-timeout'
        elif isinstance(error, (ConnectionError, http.client.HTTPException)):
            reason = 'native-request-failed'
        if type(reason) is not str or reason not in reasons:
            reason = 'unknown-failure'
        operation = self.operation if self.operation in operations else 'preflight'
        self.first = (operation, reason)

    def report(self):
        if self.first is not None:
            print('BB_PLUGIN_REFRESH failed ' + ' '.join(self.first))


def need(value, reason):
    if not value:
        raise Refusal(reason)


def object_json(raw):
    def pairs(items):
        result = {}
        for key, value in items:
            need(key not in result, 'malformed-result')
            result[key] = value
        return result
    try:
        return json.loads(raw, object_pairs_hook=pairs,
                          parse_constant=lambda _: (_ for _ in ()).throw(Refusal('malformed-result')))
    except (ValueError, UnicodeError):
        raise Refusal('malformed-result') from None


def bounded_read(path, limit=MAX_BYTES):
    with open(path, 'rb') as stream:
        raw = stream.read(limit + 1)
    need(len(raw) <= limit, 'unverified-local-state')
    return raw


def fingerprint(info):
    return (info.st_dev, info.st_ino, info.st_uid, info.st_gid, info.st_mode,
            info.st_size, info.st_mtime_ns, info.st_ctime_ns, info.st_nlink)


class LocalFiles:
    def __init__(self, home, uid):
        self.original_home = Path(home)
        self.home = self.original_home.resolve(strict=True)
        self.uid = uid
        self.seen = {}
        need(self.home.is_absolute() and self.home != Path('/'), 'unverified-home')
        need(self.home.stat().st_uid == uid, 'unverified-home')

    def normalize(self, path):
        path = Path(path)
        try:
            return self.home / path.relative_to(self.original_home)
        except ValueError:
            return path

    def inspect(self, path, directory=False, optional=False, volatile=False):
        path = self.normalize(path)
        need(path.is_absolute() and '..' not in path.parts, 'unverified-local-state')
        chain = list(reversed(path.parents)) + [path]
        for current in chain:
            try:
                info = current.lstat()
            except FileNotFoundError:
                if optional:
                    return None
                raise Refusal('unverified-local-state') from None
            need(not stat.S_ISLNK(info.st_mode), 'unverified-local-state')
            is_dir = current != path or directory
            need(stat.S_ISDIR(info.st_mode) if is_dir else stat.S_ISREG(info.st_mode),
                 'unverified-local-state')
            need(info.st_uid in (0, self.uid), 'foreign-local-state')
            sticky_tmp = current == Path('/tmp') and info.st_uid == 0 and bool(info.st_mode & stat.S_ISVTX)
            mask = 0o002 if is_dir and info.st_uid == self.uid and info.st_uid != 0 else 0o022
            need(not info.st_mode & mask or sticky_tmp, 'writable-local-state')
            if not is_dir:
                need(info.st_nlink == 1, 'unverified-local-state')
            previous = self.seen.get(str(current))
            mark = fingerprint(info)[:5] if is_dir or volatile else fingerprint(info)
            need(previous is None or previous == mark, 'changed-local-state')
            self.seen[str(current)] = mark
        return info

    def main_evidence(self, path):
        path = self.normalize(path)
        need(path.is_absolute() and '..' not in path.parts, 'unverified-local-state')
        names = ('bb.db', 'bb.db-wal', 'bb.db-shm', 'bb.db-journal',
                 'bb-app-runtime.json', 'server-moved.json', 'server-import.json')
        handles = []
        completed = False
        missing = None
        try:
            for current in list(reversed(path.parents)) + [path]:
                parent = handles[-1][0] if handles else None
                name = current.name if parent is not None else '/'
                try:
                    info = os.stat(name, dir_fd=parent, follow_symlinks=False)
                except FileNotFoundError:
                    need(parent is not None, 'unverified-local-state')
                    missing = (parent, name)
                    break
                need(stat.S_ISDIR(info.st_mode), 'unverified-local-state')
                leaf = current == path
                need(info.st_uid == self.uid if leaf else info.st_uid in (0, self.uid),
                     'foreign-local-state')
                sticky_tmp = current == Path('/tmp') and info.st_uid == 0 and bool(info.st_mode & stat.S_ISVTX)
                mask = 0o002 if info.st_uid == self.uid and info.st_uid != 0 else 0o022
                need(not info.st_mode & mask or sticky_tmp, 'writable-local-state')
                previous = self.seen.get(str(current))
                need(previous is None or previous == fingerprint(info)[:5], 'changed-local-state')
                fd = os.open(name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=parent)
                handles.append((fd, parent, name, info, leaf))
                need(fingerprint(os.fstat(fd))[:5] == fingerprint(info)[:5], 'changed-local-state')
            def probe():
                evidence = []
                for name in names:
                    try:
                        info = os.stat(name, dir_fd=handles[-1][0], follow_symlinks=False)
                    except FileNotFoundError:
                        evidence.append(None)
                    else:
                        evidence.append(fingerprint(info)[:5] + (info.st_nlink,))
                return evidence
            before = probe() if missing is None else []
            present = any(item is not None for item in before)
            if missing is not None:
                try:
                    os.stat(missing[1], dir_fd=missing[0], follow_symlinks=False)
                except FileNotFoundError:
                    pass
                else:
                    raise Refusal('changed-local-state')
            else:
                need(probe() == before, 'changed-local-state')
            for fd, parent, name, info, leaf in handles:
                expected = fingerprint(info) if leaf and not present else fingerprint(info)[:5]
                for observed in (os.fstat(fd), os.stat(name, dir_fd=parent, follow_symlinks=False)):
                    mark = fingerprint(observed) if leaf and not present else fingerprint(observed)[:5]
                    need(mark == expected, 'changed-local-state')
            completed = True
            return present
        except (OSError, NotImplementedError):
            raise Refusal('unverified-local-state') from None
        finally:
            close_failed = False
            for fd, *_ in reversed(handles):
                try:
                    os.close(fd)
                except Exception:
                    close_failed = True
            if completed and close_failed:
                raise Refusal('unverified-local-state')

    def read(self, path, optional=False, header=False):
        path = self.normalize(path)
        info = self.inspect(path, optional=optional, volatile=header)
        if info is None:
            return None
        def stable(observed):
            if header:
                return fingerprint(observed)[:5] == fingerprint(info)[:5] and observed.st_nlink == 1
            return fingerprint(observed) == fingerprint(info)
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        completed = False
        try:
            need(stable(os.fstat(fd)), 'changed-local-state')
            with os.fdopen(fd, 'rb', closefd=False) as stream:
                raw = stream.read(16 if header else MAX_BYTES + 1)
            need(len(raw) <= MAX_BYTES, 'unverified-local-state')
            need(stable(os.fstat(fd)), 'changed-local-state')
            need(stable(os.lstat(path)), 'changed-local-state')
            completed = True
            return raw
        finally:
            if completed:
                os.close(fd)
            else:
                try:
                    os.close(fd)
                except Exception:
                    pass   

    def json(self, path, optional=False):
        raw = self.read(path, optional)
        return None if raw is None else object_json(raw)


def command(args, allow_missing=False):
    result = subprocess.run(args, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, timeout=10, close_fds=True,
                            env={'PATH': '/usr/bin:/bin:/usr/sbin:/sbin', 'LC_ALL': 'C'})
    if allow_missing and result.returncode == 1 and not result.stdout and not result.stderr:
        return b''
    need(result.returncode == 0 and not result.stderr and len(result.stdout) <= MAX_BYTES, 'process-proof-unavailable')
    return result.stdout


def parse_environment(raw):
    result = {}
    for item in raw.split(b'\0'):
        key, separator, value = item.partition(b'=')
        if separator and key in (b'HOME', b'BB_DATA_DIR', b'BB_SERVER_PORT', b'BB_SERVER_LAUNCH_ID'):
            name = key.decode('ascii')
            need(name not in result, 'ambiguous-process')
            result[name] = value.decode('utf-8', 'strict')
    return result


def darwin_uid(text):
    need(re.fullmatch(r'(?:[0-9]{1,10}|-[1-9][0-9]{0,9})', text) is not None,
         'process-proof-unavailable')
    value = int(text)
    need(-(1 << 31) <= value < (1 << 32) - 1 and value != -1,
         'process-proof-unavailable')
    return value if value >= 0 else value + (1 << 32)


class Processes:
    def __init__(self, uid):
        self.uid = uid
        self.system = sys.platform
        need(self.system in ('linux', 'darwin'), 'unsupported-platform')

    def table(self):
        raw = command(['/bin/ps', '-axo', 'uid=,pid='])
        if self.system == 'darwin':
            need(raw.isascii(), 'process-proof-unavailable')
        rows = raw.decode('ascii').splitlines()
        need(len(rows) <= MAX_PROCESSES, 'process-proof-unavailable')
        result = []
        for row in rows:
            parts = row.split()
            need(len(parts) == 2, 'process-proof-unavailable')
            if self.system == 'darwin':
                uid = darwin_uid(parts[0])
                need(re.fullmatch(r'[0-9]{1,10}', parts[1]) is not None
                     and int(parts[1]) <= (1 << 31) - 1, 'process-proof-unavailable')
            else:
                need(all(p.isdecimal() for p in parts), 'process-proof-unavailable')
                uid = int(parts[0])
            if uid == self.uid:
                result.append(int(parts[1]))
        return result

    def read(self, pid):
        if self.system == 'linux':
            root = Path('/proc') / str(pid)
            try:
                need(root.stat().st_uid == self.uid, 'foreign-process')
                stamp = bounded_read(root / 'stat', 65536).rsplit(b')', 1)[1].split()[19]
                argv = [x.decode('utf-8', 'strict') for x in bounded_read(root / 'cmdline', 2097152).split(b'\0') if x]
                env = bounded_read(root / 'environ', 2097152) if main_entry(argv) is not None else b''
                again = bounded_read(root / 'stat', 65536).rsplit(b')', 1)[1].split()[19]
            except (FileNotFoundError, ProcessLookupError):
                return None
            need(stamp == again, 'changed-process')
            return (argv, parse_environment(env), stamp)
        raw_rows = command(['/bin/ps', '-p', str(pid), '-o', 'uid=,lstart='], allow_missing=True)
        if not raw_rows:
            return None
        need(raw_rows.isascii(), 'process-proof-unavailable')
        row = re.fullmatch(
            r'[ \t]*(-?[0-9]{1,10})[ \t]+'
            r'((?:Mon|Tue|Wed|Thu|Fri|Sat|Sun)[ \t]+'
            r'(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[ \t]+'
            r'(?:0?[1-9]|[12][0-9]|3[01])[ \t]+'
            r'(?:[01][0-9]|2[0-3]):[0-5][0-9]:(?:[0-5][0-9]|60)[ \t]+[0-9]{4})[ \t]*\n?',
            raw_rows.decode('ascii'))
        need(row is not None, 'process-proof-unavailable')
        uid, stamp = row.groups()
        need(darwin_uid(uid) == self.uid, 'foreign-process')
        libc = ctypes.CDLL('/usr/lib/libSystem.B.dylib', use_errno=True)
        maximum = ctypes.c_int()
        maximum_size = ctypes.c_size_t(ctypes.sizeof(maximum))
        need(libc.sysctlbyname(b'kern.argmax', ctypes.byref(maximum), ctypes.byref(maximum_size), None, 0) == 0
             and maximum_size.value == ctypes.sizeof(maximum)
             and ctypes.sizeof(ctypes.c_int) < maximum.value <= MAX_BYTES, 'process-proof-unavailable')
        mib = (ctypes.c_int * 3)(1, 49, pid)
        size = ctypes.c_size_t(maximum.value)
        buffer = ctypes.create_string_buffer(size.value)
        need(libc.sysctl(mib, 3, buffer, ctypes.byref(size), None, 0) == 0
             and ctypes.sizeof(ctypes.c_int) <= size.value <= maximum.value, 'process-proof-unavailable')
        raw = buffer.raw[:size.value]
        argc = int.from_bytes(raw[:4], sys.byteorder, signed=True)
        need(0 < argc <= 4096, 'ambiguous-process')
        rest = raw[4:].split(b'\0', 1)
        need(len(rest) == 2, 'ambiguous-process')
        values = rest[1].lstrip(b'\0').split(b'\0')
        need(len(values) >= argc, 'ambiguous-process')
        argv = [value.decode('utf-8', 'strict') for value in values[:argc]]
        return argv, parse_environment(b'\0'.join(values[argc:])), stamp

    def database_open(self, path):
        if self.system == 'darwin':
            return bool(command(['/usr/sbin/lsof', '-nP', '-Fpu', '--', str(path)], allow_missing=True))
        expected = path.stat()
        for pid in self.table():
            try:
                entries = list((Path('/proc') / str(pid) / 'fd').iterdir())
            except FileNotFoundError:
                continue
            need(len(entries) <= 65536, 'process-proof-unavailable')
            for entry in entries:
                try:
                    observed = entry.stat()
                except FileNotFoundError:
                    continue
                if (observed.st_dev, observed.st_ino) == (expected.st_dev, expected.st_ino):
                    return True
        return False

    def peer_owned(self, pid, port, client_port):
        if self.system == 'darwin':
            raw = command(['/usr/sbin/lsof', '-nP', '-a', '-p', str(pid), '-iTCP', '-FpnT']).decode('utf-8')
            expected = f'n127.0.0.1:{port}->127.0.0.1:{client_port}'
            return f'p{pid}' in raw.splitlines() and expected + '\nTST=ESTABLISHED' in raw
        expected_local = f'0100007F:{port:04X}'
        expected_peer = f'0100007F:{client_port:04X}'
        matches = set()
        for name, local, peer in (('tcp', expected_local, expected_peer),
                                 ('tcp6', '0000000000000000FFFF0000' + expected_local,
                                  '0000000000000000FFFF0000' + expected_peer)):
            for line in bounded_read(Path('/proc/net') / name).decode('ascii').splitlines()[1:]:
                values = line.split()
                need(len(values) >= 10, 'process-proof-unavailable')
                if values[1:4] == [local, peer, '01'] and values[7] == str(self.uid):
                    matches.add(values[9])
        descriptors = list((Path('/proc') / str(pid) / 'fd').iterdir())
        need(len(descriptors) <= 65536, 'process-proof-unavailable')
        for descriptor in descriptors:
            try:
                target = os.readlink(descriptor)
            except FileNotFoundError:
                continue
            if target.startswith('socket:[') and target[8:-1] in matches:
                return True
        return False


def main_entry(argv):
    entries = [arg for arg in argv[1:] if arg.endswith('/server/dist/index.js')]
    if not entries:
        return None
    need(len(entries) == 1 and Path(entries[0]).is_absolute(), 'ambiguous-process')
    return Path(entries[0])


def verify_package(files, entry):
    root = entry.parents[2]
    try:
        metadata = files.json(root / 'package.json', optional=True)
    except (Refusal, OSError):
        if root.name != 'bb-app':
            return False   
        raise
    if not isinstance(metadata, dict) or metadata.get('name') != 'bb-app':
        need(root.name != 'bb-app', 'unverified-main-server')
        workspace = files.json(entry.parents[1] / 'package.json', optional=True)
        need(not isinstance(workspace, dict) or workspace.get('name') != '@bb/server', 'unsupported-native-contract')
        return False
    version = metadata.get('version')
    need(version == '0.44.0', 'unsupported-native-contract')
    need(metadata.get('bin', {}).get('bb-server') == 'dist/bb-server.js', 'unverified-main-server')
    files.inspect(entry)
    files.inspect(root / 'server/dist/start-server.js')
    return True


def discover(files, processes, configured_data=None, block_default=False):
    servers = []
    data_dirs = {files.home / '.bb'}
    if configured_data:
        need(Path(configured_data).is_absolute(), 'unverified-local-state')
        data_dirs.add(files.normalize(configured_data))
    for pid in processes.table():
        record = processes.read(pid)
        if record is None:
            continue
        argv, env, stamp = record
        entry = main_entry(argv)
        if entry is None:
            continue
        if not verify_package(files, entry):
            continue
        need(len(argv) == 2, 'ambiguous-process')
        home = env.get('HOME') or str(files.home)
        need(Path(home).is_absolute(), 'unverified-home')
        data = files.normalize(env.get('BB_DATA_DIR') or str(Path(home) / '.bb'))
        if block_default and data == files.home / '.bb':
            continue   
        files.inspect(data, directory=True)
        need(data.stat().st_uid == files.uid, 'foreign-local-state')
        need(files.read(data / 'bb.db', header=True) == b'SQLite format 3\0'
             and (data / 'bb.db').stat().st_uid == files.uid, 'unverified-main-server')
        need(files.read(data / 'server-moved.json', optional=True) is None
             and files.read(data / 'server-import.json', optional=True) is None, 'server-move-in-progress')
        port_text = env.get('BB_SERVER_PORT', '38886')
        need(re.fullmatch(r'[0-9]{1,5}', port_text) is not None and 0 < int(port_text) < 65536,
             'ambiguous-endpoint')
        key = (data.stat().st_dev, data.stat().st_ino)
        need(not any(s['key'] == key or s['port'] == int(port_text) for s in servers), 'ambiguous-main-server')
        servers.append({'pid': pid, 'record': record, 'entry': entry, 'data': data,
                        'key': key, 'port': int(port_text), 'launch': env.get('BB_SERVER_LAUNCH_ID')})
        data_dirs.add(data)
    stopped = 0
    for data in data_dirs:
        if block_default and data == files.home / '.bb':
            continue
        if any(s['data'] == data for s in servers):
            files.inspect(data, directory=True)
            continue
        if not files.main_evidence(data):
            continue
        info = files.inspect(data, directory=True)
        if any(s['key'] == (info.st_dev, info.st_ino) for s in servers):
            continue
        db = files.read(data / 'bb.db', header=True)
        need(info.st_uid == files.uid and (data / 'bb.db').stat().st_uid == files.uid
             and db[:16] == b'SQLite format 3\0', 'unverified-main-server')
        moved = files.json(data / 'server-moved.json', optional=True)
        if moved is not None:
            need(isinstance(moved, dict) and moved.get('version') == 1
                 and moved.get('mode') in ('connect', 'direct')
                 and all(isinstance(moved.get(k), str) and moved[k]
                         for k in ('moveId', 'fromHostId', 'toHostId', 'toHostName', 'serverUrl'))
                 and type(moved.get('movedAt')) is int and moved['movedAt'] >= 0
                 and isinstance(moved.get('oldCopyEntries'), list), 'unverified-local-state')
            continue   
        need(files.read(data / 'server-import.json', optional=True) is None, 'server-move-in-progress')
        runtime = files.json(data / 'bb-app-runtime.json', optional=True)
        if runtime is not None:
            need(isinstance(runtime, dict) and type(runtime.get('pid')) is int, 'unverified-local-state')
            need(processes.read(runtime['pid']) is None, 'unverified-main-server')
        need(not processes.database_open(data / 'bb.db'), 'unverified-main-server')
        stopped += 1
    return servers, stopped


class NativeApi:
    def __init__(self, files, processes, server, deadline):
        self.files, self.processes, self.server, self.deadline = files, processes, server, deadline

    def request(self, method, path, payload=None):
        need(time.monotonic() < self.deadline, 'operation-timeout')
        s = self.server
        need(self.processes.read(s['pid']) == s['record'], 'changed-process')
        need(verify_package(self.files, s['entry']), 'unverified-main-server')
        self.files.inspect(s['data'], directory=True)
        connection = http.client.HTTPConnection('127.0.0.1', s['port'],
                                               timeout=min(180, self.deadline - time.monotonic()))
        failed = True
        try:
            connection.connect()
            connection.auto_open = 0   
            client_port = connection.sock.getsockname()[1]
            until = min(self.deadline, time.monotonic() + 2)
            while not self.processes.peer_owned(s['pid'], s['port'], client_port):
                need(time.monotonic() < until, 'unverified-peer')
                time.sleep(0.025)
            need(self.processes.read(s['pid']) == s['record'], 'changed-process')
            body = None if payload is None else json.dumps(payload).encode('ascii')
            connection.request(method, path, body, {'Content-Type': 'application/json', 'Accept-Encoding': 'identity'})
            response = connection.getresponse()
            need(response.getheader('Content-Encoding') in (None, 'identity'), 'malformed-result')
            raw = response.read(MAX_BYTES + 1)
            need(len(raw) <= MAX_BYTES, 'malformed-result')
            need(self.processes.read(s['pid']) == s['record'], 'changed-process')
            result = object_json(raw)
            if response.status == 422 and method == 'POST' and path.endswith('/update'):
                identity = path.split('/')[-2]
                refusal = ('plugin safe mode is on; turn it off with `bb plugin safe-mode off` '
                           'before you update "' + identity + '"')
                if isinstance(result, dict) and result.get('error') == refusal:
                    failed = False   
                    raise Refusal('safe-mode')
            need(response.status == 200, 'native-request-failed')   
            failed = False
            return result
        except (TimeoutError, socket.timeout):
            raise Refusal('operation-timeout') from None
        finally:
            if not failed:
                connection.close()
            else:
                try:
                    connection.close()
                except Exception:
                    pass

    def verify(self):
        health = self.request('GET', '/health')
        need(isinstance(health, dict) and health.get('ok') is True and not health.get('serverMove'),
             'unverified-main-server')
        if self.server['launch']:
            need(health.get('launchId') == self.server['launch'], 'unverified-main-server')
        config = self.request('GET', '/api/v1/system/config')
        need(isinstance(config, dict) and isinstance(config.get('dataDir'), str)
             and self.files.normalize(config['dataDir']) == self.server['data'], 'unverified-main-server')


def plugin_map(result):
    need(isinstance(result, dict) and isinstance(result.get('plugins'), list), 'malformed-result')
    need(len(result['plugins']) <= MAX_PLUGINS, 'malformed-result')
    plugins = {}
    for plugin in result['plugins']:
        need(isinstance(plugin, dict), 'malformed-result')
        identity = plugin.get('id')
        need(isinstance(identity, str) and re.fullmatch(r'[a-zA-Z0-9][a-zA-Z0-9._-]{0,199}', identity),
             'malformed-result')
        need(identity not in plugins and type(plugin.get('enabled')) is bool, 'malformed-result')
        need(plugin.get('provenance') in ('builtin', 'direct', 'catalog'), 'malformed-result')
        need(all(isinstance(plugin.get(key), str) and plugin[key] for key in ('source', 'version', 'status')),
             'malformed-result')
        need(isinstance(plugin.get('updateState'), dict), 'malformed-result')
        plugins[identity] = plugin
    return plugins


def safe_mode(api):
    state = api.request('GET', '/api/v1/plugins/safe-mode')
    need(isinstance(state, dict) and type(state.get('enabled')) is bool, 'malformed-result')
    return state['enabled']


def resolution(value):
    return (isinstance(value, dict) and isinstance(value.get('version'), str)
            and bool(value['version']) and isinstance(value.get('display'), str))


def refresh(api, diagnostics=None):
    diagnostics = diagnostics if diagnostics is not None else Diagnostics()
    diagnostics.operation = 'identity'
    api.verify()
    diagnostics.operation = 'inventory'
    if safe_mode(api):
        return 'safe-mode', False
    before = plugin_map(api.request('GET', '/api/v1/plugins'))
    sources = {}
    diagnostics.operation = 'source-check'
    for identity, plugin in before.items():
        source = api.request('GET', '/api/v1/plugins/' + identity + '/source')
        need(isinstance(source, dict) and source.get('requested') == plugin['source']
             and isinstance(source.get('resolved'), str), 'unverified-source-intent')
        sources[identity] = source
    targets = {}
    diagnostics.operation = 'update-check'
    checks = api.request('POST', '/api/v1/plugins/updates/check', {})
    need(isinstance(checks, dict) and isinstance(checks.get('results'), list), 'malformed-result')
    need(len(checks['results']) == len(before), 'incomplete-results')
    checked = {}
    failed = False
    updated = False
    for entry in checks['results']:
        need(isinstance(entry, dict) and entry.get('id') in before and entry['id'] not in checked,
             'malformed-result')
        need(resolution(entry.get('installed')), 'malformed-result')
        need(entry.get('outcome') in ('current', 'update-available', 'pinned', 'incompatible', 'unavailable'),
             'malformed-result')
        need(not entry.get('devMode'), 'unverified-compatibility')
        if entry['outcome'] == 'incompatible':
            blocked = entry.get('blocked')
            need(isinstance(blocked, dict) and isinstance(blocked.get('version'), str)
                 and isinstance(blocked.get('reasons'), list) and bool(blocked['reasons'])
                 and all(isinstance(r, str) and r for r in blocked['reasons']), 'malformed-result')
        need(sources[entry['id']]['resolved'] == entry['installed']['display'], 'changed-source-resolution')
        checked[entry['id']] = entry
    for identity, entry in checked.items():
        diagnostics.operation = 'update-check'
        plugin = before[identity]
        outcome = entry['outcome']
        if outcome == 'unavailable':
            diagnostics.record(Refusal('source-unavailable'))
            failed = True
            continue
        if outcome != 'update-available':
            continue
        need(plugin['provenance'] != 'builtin' and not plugin['source'].startswith(('path:', 'builtin:')),
             'unexpected-update-selection')
        need(resolution(entry.get('candidate')), 'malformed-result')
        diagnostics.operation = 'update'
        if safe_mode(api):
            return 'safe-mode', failed
        try:
            result = api.request('POST', '/api/v1/plugins/' + identity + '/update', {})
            need(isinstance(result, dict) and type(result.get('applied')) is bool
                 and resolution(result.get('from')), 'malformed-result')
            need(result.get('outcome') in ('current', 'updated', 'rolled-back'), 'malformed-result')
            if result['outcome'] == 'rolled-back':
                diagnostics.record(Refusal('rolled-back'))
                failed = True
            elif result['outcome'] == 'updated':
                need(result['applied'] is True and resolution(result.get('to')), 'malformed-result')
                updated = True
                targets[identity] = result['to']
            else:
                need(result['applied'] is False, 'malformed-result')
                targets[identity] = result['from']
        except Refusal as error:
            if type(error) is Refusal and error.args == ('safe-mode',):
                return 'safe-mode', failed
            diagnostics.record(error)
            failed = True
    diagnostics.operation = 'verification'
    after = plugin_map(api.request('GET', '/api/v1/plugins'))
    need(before.keys() == after.keys(), 'changed-plugin-inventory')
    for identity, old in before.items():
        new = after[identity]
        source = api.request('GET', '/api/v1/plugins/' + identity + '/source')
        need(isinstance(source, dict) and all(source.get(key) == sources[identity].get(key)
             for key in ('requested', 'subdirectory', 'range', 'tagPrefix', 'registry')), 'changed-plugin-intent')
        if identity in targets:
            need(source.get('resolved') == targets[identity]['display'], 'update-unverified')
        need(all(new[key] == old[key] for key in ('source', 'provenance', 'enabled')), 'changed-plugin-intent')
        if checked[identity]['outcome'] in ('pinned', 'incompatible'):
            need(new['version'] == old['version'], 'changed-preserved-plugin')
        if checked[identity]['outcome'] == 'update-available':
            need(new['status'] in (('running',) if new['enabled'] else ('disabled',)), 'activation-unverified')
        failure = new['updateState'].get('lastFailure')
        need(failure is None or failure == old['updateState'].get('lastFailure'), 'activation-failed')
    final = api.request('POST', '/api/v1/plugins/updates/check', {})
    need(isinstance(final, dict) and isinstance(final.get('results'), list), 'malformed-result')
    remaining = final['results']
    need(len(remaining) == len(before) and {e.get('id') for e in remaining if isinstance(e, dict)} == set(before),
         'incomplete-results')
    for entry in remaining:
        need(resolution(entry.get('installed')) and not entry.get('devMode'), 'malformed-result')
        if entry['id'] in targets:
            need(entry['installed'] == targets[entry['id']], 'update-unverified')
        if entry.get('outcome') not in ('current', 'pinned', 'incompatible'):
            diagnostics.record(Refusal('source-unavailable' if entry.get('outcome') == 'unavailable'
                                      else 'update-unverified'))
            failed = True
    return ('updated' if updated else 'checked'), failed


def run():
    labels = {'safe-mode', 'checked', 'updated', 'stopped', 'absent', 'failed'}
    diagnostics = Diagnostics()
    try:
        need(os.getuid() != 0, 'unsupported-account')
        deadline = time.monotonic() + 1800
        signal.signal(signal.SIGALRM, lambda *_: (_ for _ in ()).throw(Refusal('operation-timeout')))
        signal.alarm(1800)   
        files = LocalFiles(sys.argv[1], os.getuid())
        processes = Processes(os.getuid())
        policy = sys.argv[2] if len(sys.argv) > 2 else 'ready'
        need(policy in ('ready', 'block-default'), 'unverified-policy')
        diagnostics.operation = 'discovery'
        servers, stopped = discover(files, processes, os.environ.get('BB_DATA_DIR'), policy == 'block-default')
        failed = False
        if policy == 'block-default':
            print('BB_PLUGIN_REFRESH readiness-deferred')
        if stopped:
            print('BB_PLUGIN_REFRESH stopped')
        if not stopped and not servers:
            print('BB_PLUGIN_REFRESH absent')
        for server in servers:
            try:
                diagnostics.operation = 'verification'
                state, error = refresh(NativeApi(files, processes, server, deadline), diagnostics)
                need(state in labels, 'unverified-result')
                print('BB_PLUGIN_REFRESH ' + state)
                failed = failed or error
                if error:
                    diagnostics.record(Refusal('unverified-result'))
            except Exception as error:
                failed = True
                diagnostics.record(error)
        diagnostics.report()
        return int(failed)
    except Exception as error:
        diagnostics.record(error)
        diagnostics.report()
        return 1


if __name__ == '__main__':
    raise SystemExit(run())
