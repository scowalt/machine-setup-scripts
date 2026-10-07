import errno
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

import test_bb_machine_preparation as preparation

NODE, snapshot = preparation.NODE, preparation.snapshot

ROOT = Path(__file__).resolve().parents[1]
PROGRAM = (ROOT / 'ubuntu.sh').read_text().split('const serviceGroupProgram = String.raw`\n', 1)[1].split('\n`;', 1)[0]
WRAPPER = r'''
import errno, os, stat, sys
from pathlib import Path
root = Path(sys.argv[1])
open_real, lstat_real, stat_real, fstat_real, listdir_real, getxattr_real = os.open, os.lstat, os.stat, os.fstat, os.listdir, os.getxattr
fds = {}
def mapped(file):
    file = str(file)
    if file == '/' or file == '/etc' or file.startswith('/etc/') or file == '/proc' or file.startswith('/proc/'):
        return root / 'system' / file.lstrip('/')
    assert Path(file).is_absolute() and Path(file).is_relative_to(root), 'live host path forbidden'
    return file
def root_owned(s):
    values = list(s); values[4] = 0
    return os.stat_result(values)
def open_fixture(file, flags, *args, **kwargs):
    assert not flags & (os.O_WRONLY | os.O_RDWR | os.O_CREAT | os.O_TRUNC), 'mutation forbidden'
    fd = open_real(mapped(file), flags, *args, **kwargs)
    fds[fd] = str(file)
    return fd
def lstat_fixture(file):
    s = lstat_real(mapped(file))
    return root_owned(s) if str(file) == '/' or str(file).startswith(('/etc', '/proc')) else s
def fstat_fixture(fd):
    s = fstat_real(fd)
    return root_owned(s) if fds[fd].startswith(('/etc', '/proc')) else s
def getxattr_fixture(fd, name):
    assert name == 'system.posix_acl_access'
    if (root / 'acl-present').exists(): return b'fixture-acl'
    if (root / 'acl-unavailable').exists(): raise OSError(errno.ENOTSUP, 'fixture')
    if (root / 'swap-path').exists():
        target = Path(fds[fd]); target.rename(target.with_name('old-target'))
        target.write_bytes(b'changed')
        (root / 'swap-path').unlink()
    return getxattr_real(fd, name)
def kill_fixture(pid, signal):
    assert signal == 0, 'signal forbidden'
    if (root / 'exited').exists(): raise ProcessLookupError(errno.ESRCH, 'fixture')
    return None
os.open, os.lstat, os.fstat = open_fixture, lstat_fixture, fstat_fixture
os.listdir = lambda file: listdir_real(mapped(file))
os.getxattr, os.kill = getxattr_fixture, kill_fixture
exec(compile(sys.argv[2], 'extracted-service-group-proof', 'exec'))
'''


def account_fixture(root):
    uid, gid = os.getuid(), os.getgid()
    for name in ['system', 'system/etc', 'system/proc', 'system/proc/self', 'system/proc/123']:
        p = root / name
        p.mkdir(exist_ok=True, parents=True)
        p.chmod(0o755)
    (root / 'system/etc/nsswitch.conf').write_text('passwd: files systemd\ngroup: files systemd\n')
    (root / 'system/etc/passwd').write_text(f'account:x:{uid}:{gid}:fixture:/fixture:/bin/false\nother:x:{uid+1}:{gid+1}:fixture:/other:/bin/false\n')
    (root / 'system/etc/group').write_text(f'account:x:{gid}:\nother:x:{gid+1}:\n')
    (root / 'system/proc/self/mountinfo').write_text('19 20 0:21 / /proc rw,nosuid,nodev,noexec - proc proc rw\n')
    (root / 'system/proc/123/status').write_text(f'Uid:\t{uid+1} {uid+1} {uid+1} {uid+1}\nGid:\t{gid+1} {gid+1} {gid+1} {gid+1}\nGroups:\t{gid+1}\n')
    for p in (root / 'system/etc').iterdir(): p.chmod(0o644)
    (root / 'group-wrapper.py').write_text(WRAPPER)


@unittest.skipUnless(sys.platform == 'linux', 'Linux read-only group/ACL proof')
class ServiceGroupProof(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='bb-group-proof-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        account_fixture(self.root)
        self.target = self.root / 'fixture.service'
        self.target.write_text('unrelated fixture; no services are executed\n')
        self.target.chmod(0o664)
        self.request = {'uid': os.getuid(), 'paths': [self.entry(self.target)]}

    @staticmethod
    def entry(path):
        s = path.lstat()
        return {'path': str(path), **{key: getattr(s, 'st_' + key) for key in ['dev', 'ino', 'uid', 'gid', 'mode']}}

    def run_proof(self, expected='trusted\n'):
        result = subprocess.run([sys.executable, '-I', '-S', str(self.root / 'group-wrapper.py'), str(self.root), PROGRAM],
                                input=json.dumps(self.request), text=True, capture_output=True,
                                env={'PATH': '/usr/bin:/bin'}, timeout=5)
        self.assertEqual(result.stderr, '')
        self.assertEqual(result.stdout, expected)
        self.assertEqual(result.returncode, 0 if expected == 'trusted\n' else 1)
        return result

    def test_exclusive_group_proof_remains_file_only_and_preserves_modes(self):
        before = snapshot(self.root)
        self.run_proof(); self.run_proof()
        self.assertEqual(snapshot(self.root), before)
        directory = self.root / 'deploy'
        directory.mkdir(); directory.chmod(0o775)
        self.request['paths'].append(self.entry(directory))
        self.run_proof('unverified\n')

    def test_enumerable_initgroups_and_whitespace_are_supported(self):
        (self.root / 'system/etc/nsswitch.conf').write_text(' passwd : files\n group : files systemd\n initgroups : files systemd # fixture\n')
        self.run_proof()

    def test_shared_primary_supplementary_and_stale_live_groups_block(self):
        gid, uid = os.getgid(), os.getuid()
        for source in ['primary', 'supplementary', 'stale', 'system-group', 'not-primary']:
            with self.subTest(source=source):
                account_fixture(self.root)
                if source == 'primary':
                    p = self.root / 'system/etc/passwd'
                    p.write_text(p.read_text().replace(f'{uid+1}:{gid+1}', f'{uid+1}:{gid}'))
                elif source == 'supplementary':
                    (self.root / 'system/etc/group').write_text(f'account:x:{gid}:other\nother:x:{gid+1}:\n')
                elif source == 'system-group':
                    (self.root / 'system/etc/group').write_text(f'not-the-account:x:{gid}:\n')
                elif source == 'not-primary':
                    p = self.root / 'system/etc/passwd'
                    p.write_text(p.read_text().replace(f'{uid}:{gid}', f'{uid}:{gid+2}'))
                else:
                    (self.root / 'system/proc/123/status').write_text(f'Uid:\t{uid+1} {uid+1} {uid+1} {uid+1}\nGid:\t{gid+1} {gid+1} {gid+1} {gid+1}\nGroups:\t{gid+1} {gid}\n')
                self.run_proof('blocked:0\n')

    def test_acl_unknown_nss_hidden_processes_and_malformed_metadata_block(self):
        for cause in ['acl', 'acl-unavailable', 'nss', 'initgroups', 'hidepid', 'status', 'group']:
            with self.subTest(cause=cause):
                account_fixture(self.root)
                (self.root / 'acl-present').unlink(missing_ok=True)
                (self.root / 'acl-unavailable').unlink(missing_ok=True)
                if cause == 'acl': (self.root / 'acl-present').touch()
                elif cause == 'acl-unavailable': (self.root / 'acl-unavailable').touch()
                elif cause == 'nss': (self.root / 'system/etc/nsswitch.conf').write_text('passwd: files sss\ngroup: files\n')
                elif cause == 'initgroups':
                    (self.root / 'system/etc/nsswitch.conf').write_text('passwd: files\ngroup: files\n initgroups : files sss\n')
                elif cause == 'hidepid':
                    p = self.root / 'system/proc/self/mountinfo'; p.write_text(p.read_text().replace('proc rw', 'proc rw,hidepid=2'))
                elif cause == 'status': (self.root / 'system/proc/123/status').write_text('Uid: unknown\n')
                else: (self.root / 'system/etc/group').write_text('account:x:unknown:\n')
                self.run_proof('blocked:0\n' if cause == 'acl' else 'unverified\n')

    def test_links_hardlinks_fifos_and_identity_changes_are_not_adopted(self):
        original = self.target.read_bytes()
        backup = self.root / 'original'
        self.target.rename(backup)
        for kind in ['link', 'fifo', 'hardlink', 'changed']:
            with self.subTest(kind=kind):
                if kind == 'link': self.target.symlink_to(backup)
                elif kind == 'fifo': os.mkfifo(self.target)
                elif kind == 'hardlink': os.link(backup, self.target)
                else:
                    self.target.write_bytes(original); self.target.chmod(0o664)
                    self.request['paths'] = [self.entry(self.target)]
                    (self.root / 'swap-path').touch()
                self.run_proof('unverified\n')
                self.target.unlink()
                self.assertEqual(backup.read_bytes(), original)

    def test_missing_process_requires_positive_exit_evidence(self):
        (self.root / 'system/proc/123/status').unlink()
        self.run_proof('unverified\n')
        (self.root / 'exited').touch()
        self.run_proof()


@unittest.skipUnless(sys.platform == 'linux', 'Linux read-only group/ACL proof')
class PreparationReferenceIntegration(unittest.TestCase):
    def test_ordinary_service_directories_need_no_privacy_proof_on_either_unix_platform(self):
        for platform in ['linux', 'darwin']:
            for mode in [0o750, 0o755, 0o770, 0o775, 0o2775]:
                with self.subTest(platform=platform, mode=oct(mode)):
                    case = preparation.Preparation(); case.setUp(); self.addCleanup(case.doCleanups)
                    account_fixture(case.root)
                    (case.root / 'system/etc/group').write_text(f'account:x:{os.getgid()}:other\n')
                    (case.root / 'system/etc/nsswitch.conf').write_text('passwd: unavailable\ngroup: unavailable\n')
                    (case.root / 'system/proc/123/status').unlink()
                    (case.root / 'acl-unavailable').touch()
                    units = case.home / '.config/systemd/user'
                    agents = case.home / 'Library/LaunchAgents'
                    target = case.home / 'Code/project/deploy/systemd/unrelated.service'
                    cellar = case.home / 'brew/Cellar/example/1.0'
                    opt = case.home / 'brew/opt/example'
                    for directory in [units, agents, target.parent, cellar, opt.parent]:
                        directory.mkdir(parents=True, exist_ok=True)
                    target.write_text('[Service]\nExecStart=/usr/bin/true\n'); target.chmod(0o644)
                    (units / 'unrelated.service').symlink_to(target)
                    (units / 'masked.service').symlink_to('/dev/null')
                    (units / 'empty.service').write_text('')
                    (cellar / 'example.plist').write_text('<plist/>')
                    opt.symlink_to('../Cellar/example/1.0')
                    (agents / 'example.plist').symlink_to(opt / 'example.plist')
                    for directory in [case.home, *[p for p in case.home.rglob('*') if p.is_dir() and not p.is_symlink()]]:
                        directory.chmod(mode)
                    preload = case.root / 'no-directory-proof.cjs'
                    preload.write_text(r'''
const fs=require('node:fs'),cp=require('node:child_process'),path=require('node:path');
Object.defineProperty(process,'platform',{value:process.env.TEST_PLATFORM});
// Like the elevated entry point, helpers use the configured account's UID,
// not the caller's effective root identity.
process.geteuid=()=>0;
const outer=new Set();
for(let p=process.env.FIXTURE_ROOT;p!=='/';p=path.dirname(p)) outer.add(p);
const forbidden=()=>{ fs.appendFileSync(process.env.EVENTS,'FORBIDDEN directory privacy proof\n'); throw Error('forbidden'); };
for(const key of ['lstatSync','statSync']) {
  const original=fs[key];
  fs[key]=function(file,...args) {
    if(String(file)==='/usr/bin/python3') throw Object.assign(Error(),{code:'ENOENT'});
    if(String(file).startsWith('/etc/') || String(file).startsWith('/proc/')) return forbidden();
    const s=original.call(fs,file,...args);
    if(outer.has(String(file)) && s.uid===process.getuid()) s.mode=(s.mode & ~0o777)|0o755;
    return s;
  };
}
cp.spawnSync=forbidden; // no Python, NSS, ACL or process-membership proof
const exec=cp.execFileSync;
cp.execFileSync=function(command,args,...rest) {
  if(command!=='ps' || JSON.stringify(args)!==JSON.stringify(['-U',String(process.getuid()),'-o','command='])) return forbidden();
  return exec.call(cp,command,args,...rest); // independent BB operational identity remains required
};
''')
                    (case.tools / 'node').unlink()
                    case.write_exe('node', f'#!/bin/bash\nexec {NODE!r} --require {str(preload)!r} "$@"\n')
                    before = snapshot(case.home)
                    metadata = {p: (p.stat().st_uid, p.stat().st_gid, p.stat().st_mode)
                                for p in [case.home, *[p for p in case.home.rglob('*') if p.is_dir() and not p.is_symlink()]]}
                    for _ in range(2):
                        out = case.run_helper(TEST_PLATFORM=platform, PROCESSES='unrelated-workload-changing')
                        self.assertIn('not enrolled', out)
                        after = {row[0]: row for row in snapshot(case.home)}
                        for row in before:
                            self.assertEqual(after[row[0]], row)
                        self.assertEqual(metadata, {p: (p.stat().st_uid, p.stat().st_gid, p.stat().st_mode) for p in metadata})
                    self.assertNotIn('FORBIDDEN', case.log())
                    if platform == 'darwin':
                        target.chmod(0o664)
                        case.events.write_text('')
                        before = snapshot(case.home)
                        out = case.run_helper(expected=1, TEST_PLATFORM=platform)
                        self.assertIn('operation=service', out)
                        self.assertIn('mode=0664 reason=writable-boundary', out)
                        self.assertNotIn('npm ', case.log())
                        self.assertEqual(before, snapshot(case.home))

    def test_changed_service_link_listing_and_fifo_fail_before_package_work(self):
        for change in ['link', 'listing', 'fifo', 'mode', 'gid', 'uid', 'type', 'identity']:
            with self.subTest(change=change):
                case = preparation.Preparation(); case.setUp(); self.addCleanup(case.doCleanups)
                units = case.home / '.config/systemd/user'
                units.mkdir(parents=True)
                units.chmod(0o775)
                target = case.home / 'ordinary.unit'
                target.write_text('unrelated fixture-secret\n')
                unit = units / 'ordinary.service'
                unit.symlink_to(target)
                other = case.home / 'other.unit'
                other.write_text('ExecStart=' + str(case.prefix / 'bin/bb-host-daemon'))
                preload = case.root / 'race-preload.cjs'
                preload.write_text("""
const fs=require('node:fs'),path=require('node:path'),cp=require('node:child_process');
const read=fs.readSync,home=process.env.HOME,target=path.join(home,'ordinary.unit');
const units=path.join(home,'.config/systemd/user'),lstat=fs.lstatSync;
let changed=false;
fs.lstatSync=function(file,...args) {
  const s=lstat.call(fs,file,...args);
  if(changed && String(file)===units) {
    if(process.env.SERVICE_RACE==='gid') s.gid+=1;
    if(process.env.SERVICE_RACE==='uid') s.uid+=1;
    if(process.env.SERVICE_RACE==='identity') s.ino+=1;
    if(process.env.SERVICE_RACE==='type') s.mode=(s.mode & 0o7777)|0o100000;
  }
  return s;
};
fs.readSync=function(fd,...args) {
  const count=read.call(fs,fd,...args);
  if(!changed && fs.readlinkSync(`/proc/self/fd/${fd}`)===target) {
    changed=true;
    const unit=path.join(home,'.config/systemd/user/ordinary.service');
    if(process.env.SERVICE_RACE==='link') { fs.unlinkSync(unit);fs.symlinkSync(path.join(home,'other.unit'),unit); }
    else if(process.env.SERVICE_RACE==='listing') fs.writeFileSync(path.join(path.dirname(unit),'late.service'),'fixture-secret');
    else if(process.env.SERVICE_RACE==='fifo') { fs.unlinkSync(target);cp.execFileSync('/usr/bin/mkfifo',[target]); }
    else if(process.env.SERVICE_RACE==='mode') fs.chmodSync(units,0o2775); // both modes individually acceptable
  }
  return count;
};
""")
                (case.tools / 'node').unlink()
                case.write_exe('node', f'#!/bin/bash\nexec {NODE!r} --require {str(preload)!r} "$@"\n')
                out = case.run_helper(expected=1, SERVICE_RACE=change)
                self.assertIn('reason=unverified', out)
                self.assertNotIn('fixture-secret', out)
                self.assertNotIn('npm ', case.log())
                self.assertFalse(case.prefix.exists())
                if change == 'mode':
                    self.assertEqual(units.stat().st_mode & 0o7777, 0o2775)

    def test_directory_refusals_still_precede_descendant_inspection_and_package_work(self):
        for kind in ['foreign', 'root', 'world', 'link', 'dangling', 'type', 'inspection', 'system-group']:
            with self.subTest(kind=kind):
                case = preparation.Preparation(); case.setUp(); self.addCleanup(case.doCleanups)
                directory = case.home / '.config'
                (directory / 'systemd/user').mkdir(parents=True)
                directory.chmod(0o775)
                if kind == 'world': directory.chmod(0o777)
                elif kind in ['link', 'dangling', 'type']:
                    directory.rename(case.home / 'preserved')
                    if kind == 'type': directory.write_text('private-sentinel')
                    else: directory.symlink_to(case.home / ('preserved' if kind == 'link' else 'missing'))
                preload = case.root / 'unsafe-directory.cjs'
                preload.write_text(r'''
const fs=require('node:fs'),path=require('node:path');
const unsafe=process.env.REFUSAL==='system-group'?process.env.FIXTURE_ROOT:path.join(process.env.HOME,'.config');
for(const key of ['lstatSync','statSync','readdirSync','readlinkSync','openSync','readFileSync']) {
  const original=fs[key];
  fs[key]=function(file,...args) {
    // The helper may read its stdin, runtime files and trusted siblings, but
    // may not probe any child of the rejected directory.
    if(String(file).startsWith(unsafe+'/') && process.env.REFUSAL!=='system-group') {
      fs.appendFileSync(process.env.EVENTS,'FORBIDDEN unsafe descendant\n'); throw Error('private-sentinel');
    }
    if(key==='lstatSync' && String(file)===unsafe) {
      if(process.env.REFUSAL==='inspection') throw Error('private-sentinel');
      const s=original.call(fs,file,...args);
      if(process.env.REFUSAL==='foreign') s.uid=process.getuid()+1;
      if(process.env.REFUSAL==='root') s.uid=0;
      if(process.env.REFUSAL==='system-group') { s.uid=0; s.mode=(s.mode & ~0o7777)|0o775; }
      return s;
    }
    return original.call(fs,file,...args);
  };
}
''')
                (case.tools / 'node').unlink()
                case.write_exe('node', f'#!/bin/bash\nexec {NODE!r} --require {str(preload)!r} "$@"\n')
                before = snapshot(case.home)
                out = case.run_helper(expected=1, REFUSAL=kind)
                self.assertNotIn('private-sentinel', out)
                self.assertNotIn('npm ', case.log())
                self.assertEqual(before, snapshot(case.home))

    def test_shared_home_exclusive_group_preserves_all_arcane_shapes_twice(self):
        case = preparation.Preparation(); case.setUp(); self.addCleanup(case.doCleanups)
        account_fixture(case.root)
        case.root.chmod(0o755)
        case.home.chmod(0o750)
        target = case.home / 'Code/project/deploy/systemd'
        units = case.home / '.config/systemd/user'
        for directory in [target, units]:
            directory.mkdir(parents=True)
            current = directory
            while current != case.home:
                current.chmod(0o755); current = current.parent
        target.parent.chmod(0o775); target.chmod(0o775)
        service = target / 'unrelated.service'
        service.write_text('unrelated fixture\n'); service.chmod(0o664)
        (units / service.name).symlink_to(service)
        for name in ['training.service', 'sync.service', 'browser.service']:
            p = units / name; p.write_text('unrelated fixture\n'); p.chmod(0o664)
        preload = case.root / 'group-preload.cjs'
        preload.write_text("""
const cp=require('node:child_process'),fs=require('node:fs'),path=require('node:path');
const spawn=cp.spawnSync,root=process.env.FIXTURE_ROOT;
// Model a shared HOME without exposing the runner's genuinely private roots.
// Otherwise an outer 0700 directory legitimately supplies the alternate proof
// and this fixture never exercises the exclusive-group branch it asserts.
const outer=new Set();
for(let p=path.dirname(root);p!=='/';p=path.dirname(p)) outer.add(p);
for(const name of ['lstatSync','statSync']) {
  const original=fs[name];
  fs[name]=function(file,...args) {
    const metadata=original.call(fs,file,...args);
    if(outer.has(String(file)) && metadata.uid===process.getuid()) metadata.mode=(metadata.mode & ~0o777)|0o755;
    return metadata;
  };
}
cp.spawnSync=function(command,args,options) {
  if(command==='/usr/bin/python3') {
    if(JSON.parse(options.input).paths.some(p=>!fs.lstatSync(p.path).isFile())) {
      fs.appendFileSync(process.env.EVENTS,'FORBIDDEN directory proof\\n'); throw Error('file proof only');
    }
    if(JSON.stringify(args.slice(0,3))!==JSON.stringify(['-I','-S','-c']) || args.length!==4 ||
      options.shell!==false || options.cwd!=='/' || JSON.stringify(options.env)!==JSON.stringify({PATH:'/usr/bin:/bin',LANG:'C.UTF-8'})) throw Error('unsafe group proof');
    const override=path.join(root,'group-response.json');
    if(fs.existsSync(override)) return JSON.parse(fs.readFileSync(override,'utf8'));
    return spawn(command,['-I','-S',path.join(root,'group-wrapper.py'),root,args[3]],options);
  }
  return spawn(command,args,options);
};
""")
        (case.tools / 'node').unlink()
        case.write_exe('node', f'#!/bin/bash\nexec {NODE!r} --require {str(preload)!r} "$@"\n')
        before = (snapshot(case.home / 'Code'), snapshot(case.home / '.config'))
        for _ in range(2):
            case.run_helper()
            self.assertEqual(before, (snapshot(case.home / 'Code'), snapshot(case.home / '.config')))
        (case.root / 'system/etc/group').write_text(f'account:x:{os.getgid()}:other\n')
        case.events.unlink()
        output = case.run_helper(expected=1)
        self.assertIn('operation=service', output)
        self.assertNotIn('operation=directory', output)
        self.assertIn('reason=writable-boundary', output)
        self.assertNotIn('npm ', case.log())
        self.assertEqual(before, (snapshot(case.home / 'Code'), snapshot(case.home / '.config')))
        account_fixture(case.root)
        for status, output in [(1, 'trusted\n'), (0, 'trusted\nfixture-secret\n'), (0, 'fixture-secret'), (0, '')]:
            with self.subTest(status=status, output=output):
                (case.root / 'group-response.json').write_text(json.dumps({'status': status, 'stdout': output, 'stderr': 'fixture-secret'}))
                case.events.unlink()
                out = case.run_helper(expected=1)
                self.assertIn('reason=unverified', out)
                self.assertNotIn('fixture-secret', out)
                self.assertNotIn('npm ', case.log())
                self.assertEqual(before, (snapshot(case.home / 'Code'), snapshot(case.home / '.config')))


if __name__ == '__main__':
    unittest.main(verbosity=2)
