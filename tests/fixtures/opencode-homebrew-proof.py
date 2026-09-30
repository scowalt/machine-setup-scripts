"""Version 2: model transient procfs races without host inventory or application execution."""
import errno
import grp
import os
import pwd
from pathlib import Path
import posixpath
import stat
import sys
from types import SimpleNamespace

root = Path(sys.argv[1]).resolve()
program = sys.argv[2]
real_open, real_lstat, real_fstat = os.open, os.lstat, os.fstat
real_listdir, real_getxattr = os.listdir, os.getxattr
fds = {}
reads = 0
vanished = set()


def mapped(file):
    file = str(file)
    assert file.startswith('/'), 'absolute fixture path required'
    assert file == '/' or file.startswith(('/home/', '/etc/', '/proc/', '/usr/')) or file in ['/home', '/etc', '/proc', '/usr'], 'live path forbidden'
    return root / 'system' / file.lstrip('/')


def modeled(s, file):
    values = {key: getattr(s, key) for key in dir(s) if key.startswith('st_')}
    if file in ['/', '/home'] or file.startswith(('/etc', '/proc', '/usr')):
        values['st_uid'] = 0
    return SimpleNamespace(**values)


def opened(file, flags, mode=0o777, *, dir_fd=None):
    assert not flags & (os.O_WRONLY | os.O_RDWR | os.O_CREAT | os.O_TRUNC | os.O_APPEND), 'writes forbidden'
    logical = str(file) if dir_fd is None else posixpath.join(fds[dir_fd], str(file))
    if reads == 1 and logical in ['/proc/123/task/123/status', '/proc/123/task/123/stat']:
        leaf = logical.rsplit('/', 1)[1]
        if exists('proc-' + leaf + '-exit'):
            vanished.add('/proc/123/task/123')
            raise FileNotFoundError(errno.ENOENT, 'SECRET exited task')
    target = mapped(file) if dir_fd is None else file
    fd = real_open(target, flags, mode, dir_fd=dir_fd)
    fds[fd] = logical
    return fd


def lstat(file, *, dir_fd=None):
    logical = str(file) if dir_fd is None else posixpath.join(fds[dir_fd], str(file))
    if logical in vanished: raise FileNotFoundError(errno.ENOENT, 'SECRET exited task')
    return modeled(real_lstat(mapped(file) if dir_fd is None else file, dir_fd=dir_fd), logical)


def exists(name):
    try: real_lstat(root / name); return True
    except FileNotFoundError: return False


def xattr(fd, name):
    assert name in ['system.posix_acl_access', 'system.posix_acl_default']
    if exists('acl-present') or (name == 'system.posix_acl_default' and exists('acl-default')) or (reads >= 3 and exists('retry-acl')): return b'untrusted named ACL'
    if exists('acl-unavailable'): raise OSError(errno.ENOTSUP, 'SECRET acl error')
    if exists('swap-path'):
        target = mapped(fds[fd])
        directory = stat.S_ISDIR(real_lstat(target).st_mode)
        target.rename(target.with_name(target.name + '.saved'))
        target.mkdir() if directory else target.write_bytes(b'changed')
        (root / 'swap-path').unlink()
    return real_getxattr(fd, name)


def listing(file):
    global reads
    logical = fds[file] if isinstance(file, int) else str(file)
    result = real_listdir(file if isinstance(file, int) else mapped(file))
    result = [name for name in result if logical.rstrip('/') + '/' + name not in vanished]
    if logical == '/proc/123/task' and reads == 1 and exists('proc-task-exit'):
        result.append('999')
    if logical == '/proc':
        reads += 1
        (root / 'proc-scans').write_text(str(reads))
        if exists('proc-denied'): raise PermissionError(errno.EACCES, 'SECRET procfs')
        if exists('proc-io-error'): raise OSError(errno.EIO, 'SECRET procfs')
        if exists('proc-exit-always') or (reads <= 2 and exists('proc-exit-twice')) or (reads == 1 and exists('proc-exit-once')) or (reads == 2 and exists('proc-exit-second')):
            # Enumerated PID exits before its task directory can be opened.
            result.append('999')
        if (reads == 2 and exists('proc-churn-once')) or (reads % 2 == 0 and exists('proc-churn-always')):
            result.remove('123')
        if reads == 2 and exists('changed-task-credentials'):
            status = root / 'system/proc/123/task/123/status'
            status.write_text(status.read_text().replace(f'Groups:\t{os.getgid()+1}', f'Groups:\t{os.getgid()+2}'))
        if reads == 2 and exists('reused-task'):
            file = root / 'system/proc/123/task/123/stat'
            file.write_text(file.read_text().replace('12345', '12346'))
        if reads == 1 and exists('retry-config'):
            file = root / 'system/etc/group'
            file.write_text(file.read_text() + '# changed before retry\n')
        if reads == 1 and exists('retry-mount'):
            file = root / 'system/proc/self/mountinfo'
            file.write_text(file.read_text() + '\n')
        if reads == 2 and exists('retry-path'):
            os.chmod(root / 'system/home/linuxbrew/.linuxbrew', 0o750)
        if reads == 2 and exists('retry-foreign'):
            status = root / 'system/proc/123/task/123/status'
            status.write_text(status.read_text().replace('Groups:', f'Groups: {os.getgid()}'))
        if reads == 2 and exists('changed-membership'):
            status = root / 'system/proc/123/task/123/status'
            status.write_text(status.read_text().replace('Groups:', f'Groups: {os.getgid()}'))
        if reads == 2 and exists('changed-config'):
            file = root / 'system/etc/group'
            file.write_text(file.read_text() + '# changed snapshot\n')
        if reads == 2 and exists('changed-mount'):
            file = root / 'system/proc/self/mountinfo'
            file.write_text(file.read_text().replace('proc rw', 'proc rw,hidepid=2'))
    return result


# Patch the native NSS APIs before running the extracted code; never query host identities.
def users():
    rows = [line.split(':') for line in (root / 'system/etc/passwd').read_text().splitlines() if line and not line.startswith('#')]
    result = [SimpleNamespace(pw_name=r[0], pw_uid=int(r[2]), pw_gid=int(r[3])) for r in rows]
    if exists('native-primary'): result.append(SimpleNamespace(pw_name='extra', pw_uid=os.getuid()+2, pw_gid=os.getgid()))
    return result


def groups():
    rows = [line.split(':') for line in (root / 'system/etc/group').read_text().splitlines() if line and not line.startswith('#')]
    return [SimpleNamespace(gr_name=r[0], gr_gid=int(r[2]), gr_mem=[n for n in r[3].split(',') if n]) for r in rows]


def initgroups(name, gid):
    result = sorted({gid, *(entry.gr_gid for entry in groups() if name in entry.gr_mem)})
    if name == 'other' and exists('native-supplementary'): result.append(os.getgid())
    if name == 'account' and ((reads >= 2 and exists('changed-native-membership')) or (reads >= 1 and exists('retry-native-membership'))): result.append(os.getgid()+10)
    return result


pwd.getpwall, grp.getgrall, os.getgrouplist = users, groups, initgroups
os.open, os.lstat = opened, lstat
os.fstat = lambda fd: modeled(real_fstat(fd), fds[fd])
os.listdir, os.getxattr = listing, xattr
os.stat = lambda *args, **kwargs: (_ for _ in ()).throw(AssertionError('following paths forbidden'))
os.kill = lambda *args: (_ for _ in ()).throw(AssertionError('process signaling forbidden'))
exec(compile(program, 'extracted-opencode-homebrew-proof', 'exec'))
