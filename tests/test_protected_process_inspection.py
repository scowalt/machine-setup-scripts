"""Extract the privileged reader into fake procfs; never run sudo or live inventory."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'ubuntu.sh').read_text()
PROGRAM = SOURCE.split('const linuxProtectedProcessProgram = String.raw`\n', 1)[1].split('\n`;', 1)[0]
SECRET = 'fixture-private-environment-never-return'
WRAPPER = r'''
import json, os, stat, sys
from pathlib import Path
root = Path(sys.argv[1])
original_open, original_fstat, original_read = os.open, os.fstat, os.read
proc_fd = None
opens = {}
def open_fixture(file, flags, *args, **kwargs):
    global proc_fd
    assert not flags & (os.O_WRONLY | os.O_RDWR | os.O_CREAT | os.O_TRUNC), 'write forbidden'
    if file == '/proc':
        proc_fd = original_open(root / 'proc', flags, *args, **kwargs)
        return proc_fd
    assert not os.path.isabs(file), 'absolute host path forbidden'
    opens[file] = opens.get(file, 0) + 1
    if file == 'environ' and opens[file] == 2:
        mutation = os.environ.get('FIXTURE_MUTATION')
        if mutation == 'environment': (root / 'proc/123/environ').write_bytes(b'HOME=/changed\0')
        if mutation == 'command': (root / 'proc/123/cmdline').write_bytes(b'node\0different.js\0')
        if mutation == 'identity':
            p = root / 'proc/123/stat'
            p.write_text(p.read_text().replace('9876', '9877'))
        if mutation == 'group': (root / 'proc/123/cgroup').write_text('0::/changed\n')
        if mutation == 'directory':
            (root / 'proc/123').rename(root / 'proc/old')
            (root / 'proc/123').mkdir()
    return original_open(file, flags, *args, **kwargs)
def fstat_fixture(fd):
    info = original_fstat(fd)
    if fd == proc_fd:
        fields = list(info); fields[4] = 0
        return os.stat_result(fields)
    return info
os.open, os.fstat = open_fixture, fstat_fixture
os.geteuid = lambda: int(os.environ.get('FIXTURE_EUID', '0'))
# Assertions above make it impossible for this execution to inspect live procfs.
try:
    exec(compile((root / 'reader.py').read_text(), 'extracted-protected-reader', 'exec'))
finally:
    (root / 'opened-fields.json').write_text(json.dumps(opens))
'''


class ProtectedProcessInspection(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='protected-process-contract-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.proc = self.root / 'proc/123'
        self.proc.mkdir(parents=True)
        self.proc.parent.chmod(0o755)  # Simulated procfs root has no untrusted writers.
        uid = os.getuid()
        self.request = {'schema': 1, 'uid': uid, 'pid': 123,
                        'identity': {'parent': 1, 'start': '9876', 'uids': [uid]*4, 'dead': False},
                        'cgroup': '0::/user.slice/other.service\n'}
        (self.root / 'reader.py').write_text(PROGRAM)
        (self.root / 'wrapper.py').write_text(WRAPPER)
        (self.proc / 'stat').write_text('123 (protected ) process) S 1 ' + '0 '*17 + '9876\n')
        (self.proc / 'status').write_text(f'Pid:\t123\nPPid:\t1\nUid:\t{uid} {uid} {uid} {uid}\nGid:\t1000 1000 1000 1000\n')
        (self.proc / 'cgroup').write_text(self.request['cgroup'])
        (self.proc / 'cmdline').write_bytes(b'/usr/bin/protected-process\0--flag\0')
        (self.proc / 'environ').write_bytes(('HOME=/fixture/home\0PASEO_HOME=/fixture/home/.paseo\0'
                                           'PASEO_DESKTOP_MANAGED=1\0API_TOKEN=' + SECRET + '\0').encode())
        self.env = {'PATH': '/usr/bin:/bin', 'SUDO_UID': str(uid)}

    def run_reader(self, expected=0, **env):
        result = subprocess.run([sys.executable, '-I', '-S', str(self.root / 'wrapper.py'), str(self.root)],
                                input=json.dumps(self.request), env=self.env | env,
                                capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
        self.assertEqual(result.stderr, '')
        self.assertNotIn(SECRET, result.stdout)
        return json.loads(result.stdout)

    def test_bounded_read_only_receipt_contains_only_ownership_fields(self):
        before = {p.name: p.read_bytes() for p in self.proc.iterdir()}
        for _ in range(2):
            receipt = self.run_reader()
            self.assertEqual(receipt, {'schema': 1, 'identity': self.request['identity'],
                'cgroup': self.request['cgroup'], 'command': '/usr/bin/protected-process\0--flag\0',
                'env': {'HOME': '/fixture/home', 'PASEO_HOME': '/fixture/home/.paseo', 'PASEO_DESKTOP_MANAGED': '1'}})
            self.assertEqual(before, {p.name: p.read_bytes() for p in self.proc.iterdir()})

    def test_privilege_account_and_request_boundaries(self):
        self.run_reader(expected=1, FIXTURE_EUID='1000')
        self.run_reader(expected=1, SUDO_UID=str(os.getuid()+1))
        for key, value in [('uid', os.getuid()+1), ('pid', '../123'), ('schema', 2)]:
            original = self.request[key]
            self.request[key] = value
            self.run_reader(expected=1)
            self.request[key] = original
        self.request['unexpected'] = SECRET
        self.run_reader(expected=1)

    def test_credential_and_pid_identity_must_match_before_sensitive_reads(self):
        for key, value in [('uids', [os.getuid()+1]*4), ('start', '9877'), ('parent', 2), ('dead', True)]:
            original = self.request['identity'][key]
            self.request['identity'][key] = value
            self.run_reader(expected=1)
            self.request['identity'][key] = original
        # The kernel owns all four credential values. Mixed IDs stay associated
        # with the setup account, rather than being ignored as foreign.
        uid = os.getuid()
        self.request['identity']['uids'] = [uid, 0, 0, 0]
        (self.proc / 'status').write_text(f'Pid:\t123\nPPid:\t1\nUid:\t{uid} 0 0 0\nGid:\t1000 1000 1000 1000\n')
        self.run_reader()
        self.request['identity']['uids'] = [uid+1, uid+1, uid, uid+1]
        (self.proc / 'status').write_text(f'Pid:\t123\nPPid:\t1\nUid:\t{uid+1} {uid+1} {uid} {uid+1}\nGid:\t1000 1000 1000 1000\n')
        self.run_reader(expected=1)
        self.assertNotIn('environ', json.loads((self.root / 'opened-fields.json').read_text()))
        self.assertNotIn('cmdline', json.loads((self.root / 'opened-fields.json').read_text()))

    def test_changed_image_environment_group_and_directory_are_rejected(self):
        original = {p.name: p.read_bytes() for p in self.proc.iterdir()}
        for mutation in ['environment', 'command', 'identity', 'group', 'directory']:
            with self.subTest(mutation=mutation):
                result = self.run_reader(expected=1, FIXTURE_MUTATION=mutation)
                self.assertEqual(result['error'], 'changed')
                for name, content in original.items(): (self.proc / name).write_bytes(content)

    def test_links_fifos_duplicates_and_oversized_fields_fail_promptly(self):
        env = self.proc / 'environ'
        original = env.read_bytes()
        target = self.root / 'private-target'
        target.write_text(SECRET)
        env.unlink(); env.symlink_to(target)
        self.run_reader(expected=1)
        self.assertEqual(target.read_text(), SECRET)
        env.unlink(); os.mkfifo(env)
        self.run_reader(expected=1)
        env.unlink()
        for contents in [b'HOME=a\0HOME=b\0', b'HOME=' + b'x'*16385, b'x'*4194305, b'HOME=\xff']:
            env.write_bytes(contents)
            self.run_reader(expected=1)
        env.write_bytes(original)

    @unittest.skipUnless(sys.platform == 'linux', 'native Linux protected-process proof')
    def test_native_non_dumpable_child_denies_environment_read_without_policy_changes(self):
        # Only this disposable test-owned child changes its own dumpability.
        # No agent, service, sudo command or live process inventory is used.
        code = "import ctypes,sys; assert ctypes.CDLL(None).prctl(4,0,0,0,0)==0; print('ready',flush=True); sys.stdin.read(1)"
        child = subprocess.Popen([sys.executable, '-I', '-S', '-c', code], stdin=subprocess.PIPE,
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                                 env={'PATH': '/usr/bin:/bin', 'FIXTURE_PRIVATE': SECRET})
        try:
            self.assertEqual(child.stdout.readline().strip(), 'ready')
            if os.geteuid() == 0: self.skipTest('root can inspect its test child')
            with self.assertRaises(PermissionError):
                fd = os.open(f'/proc/{child.pid}/environ', os.O_RDONLY | os.O_NOFOLLOW)
                os.close(fd)
        finally:
            child.communicate('x', timeout=5)
        self.assertEqual(child.returncode, 0)


if __name__ == '__main__':
    unittest.main(verbosity=2)
