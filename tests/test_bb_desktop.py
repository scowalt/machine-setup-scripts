"""Inert extracted-helper fixtures: no desktop code, network or host lifecycle runs."""
import ast
import copy
import hashlib
import io
import json
import os
from pathlib import Path
import stat
import subprocess
import tempfile
import types
import unittest
from unittest.mock import Mock, patch
import zipfile
import plistlib
import re
import shutil

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ('mac', 'ubuntu', 'bazzite', 'wsl', 'pi')


def payload(name='mac'):
    return (ROOT / (name + '.sh')).read_text().split("<<'BB_DESKTOP_PY'\n", 1)[1].split('\nBB_DESKTOP_PY', 1)[0]


def wrapper(name):
    source = (ROOT / (name + '.sh')).read_text()
    return source.split('# BEGIN BB DESKTOP WRAPPER', 1)[1].split('# END BB DESKTOP WRAPPER', 1)[0].split('\n', 1)[1]


def appimage(number):
    data = bytearray(20)
    data[:6] = b'\x7fELF\x02\x01'
    data[8:11] = b'AI\x02'
    data[18:20] = b'\x3e\x00'
    return bytes(data) + b'INERT, NOT EXECUTABLE: ' + number.encode()


def release(number, data, platform='linux', tag='desktop-latest'):
    name = 'bb-' + number + ('-arm64.zip' if platform == 'macos' else '-x86_64.AppImage')
    return {'tag_name': tag, 'draft': False, 'prerelease': False,
            'html_url': 'https://github.com/get-bb/bb/releases/tag/' + tag,
            'assets': [{'id': 42, 'name': name, 'size': len(data), 'state': 'uploaded',
                        'digest': 'sha256:' + hashlib.sha256(data).hexdigest(),
                        'browser_download_url': 'https://github.com/get-bb/bb/releases/download/' + tag + '/' + name}]}


def mac_zip(number, identity='dev.bb.desktop'):
    stream = io.BytesIO()
    with zipfile.ZipFile(stream, 'w') as archive:
        archive.writestr('bb.app/Contents/Info.plist', plistlib.dumps({
            'CFBundleIdentifier': identity, 'CFBundleExecutable': 'bb',
            'CFBundleShortVersionString': number, 'LSMinimumSystemVersion': '13.0.0'}))
        archive.writestr('bb.app/Contents/MacOS/bb', 'INERT, NOT EXECUTABLE')
    return stream.getvalue()


def import_helper_definitions(source):
    """Do not rely on __name__ or entry-point text when importing an installer."""
    tree = ast.parse(source)
    selected = []
    for node in tree.body:
        if isinstance(node, (ast.Import, ast.ImportFrom)):
            selected.append(node)
        elif isinstance(node, (ast.FunctionDef, ast.ClassDef)):
            if node.decorator_list:
                raise AssertionError('Unexpected helper decorator')
            definitions = [node] if isinstance(node, ast.FunctionDef) else [n for n in node.body if isinstance(n, ast.FunctionDef)]
            if isinstance(node, ast.ClassDef):
                if node.keywords or any(ast.unparse(base) not in ('Exception', 'urllib.request.HTTPRedirectHandler') for base in node.bases):
                    raise AssertionError('Unexpected helper class construction')
                if any(not isinstance(n, (ast.FunctionDef, ast.Pass)) for n in node.body):
                    raise AssertionError('Unexpected class-body execution')
            for definition in definitions:
                arguments = [*definition.args.posonlyargs, *definition.args.args, *definition.args.kwonlyargs]
                if definition.decorator_list or definition.returns or any(arg.annotation for arg in arguments):
                    raise AssertionError('Unexpected definition-time annotation/decorator')
                for default in [*definition.args.defaults, *(v for v in definition.args.kw_defaults if v)]:
                    if any(not isinstance(value, (ast.Constant, ast.BinOp, ast.Mult)) for value in ast.walk(default)):
                        raise AssertionError('Unexpected definition-time execution')
            selected.append(node)
        elif isinstance(node, ast.Assign):
            if len(node.targets) == 1 and isinstance(node.targets[0], ast.Name) and node.targets[0].id == 'UID':
                node.value = ast.Constant(os.getuid())
            else:
                ast.literal_eval(node.value)
            selected.append(node)
        elif isinstance(node, ast.If) and ast.unparse(node.test) == "__name__ == '__main__'":
            continue  # never execute the production entry path while importing
        else:
            raise AssertionError('Unexpected helper top-level execution')
    namespace = {'__name__': 'fixture_only'}
    exec(compile(ast.fix_missing_locations(ast.Module(body=selected, type_ignores=[])),
                 'extracted-bb-desktop-definitions', 'exec'), namespace)
    return namespace


class DesktopTests(unittest.TestCase):
    def setUp(self):
        self.previous_umask = os.umask(0o077)
        self.temp = tempfile.TemporaryDirectory(prefix='bb-desktop-fixture-')
        self.base = Path(self.temp.name)
        self.home = self.base / 'home'
        self.home.mkdir(mode=0o700)
        self.ns = import_helper_definitions(payload())
        self.ns['UID'] = os.getuid()
        self.restriction = self.base / 'apparmor-restriction'
        self.restriction.write_text('0\n')
        self.ns['Path'] = lambda *args: self.restriction if args == ('/proc/sys/kernel/apparmor_restrict_unprivileged_userns',) else Path(*args)
        self.environment = patch.dict(os.environ, {'HOME': str(self.home)}, clear=True)
        self.environment.start()
        self.libc = patch.object(os, 'confstr', return_value='glibc 2.35')
        self.libc.start()
        self.account = patch.object(self.ns['pwd'], 'getpwuid', return_value=types.SimpleNamespace(pw_dir=str(self.home)))
        self.account.start()
        self.number = '1.2.3'
        self.data = appimage(self.number)
        self.latest = release(self.number, self.data)
        self.catalogue = []
        self.calls = []
        self.process_state = False
        self.real_fetch = self.ns['fetch']
        self.ns['fetch'] = self.fetch
        self.real_command = self.ns['command']
        self.ns['command'] = self.command
        self.real_running = self.ns['running']
        self.ns['running'] = lambda *_: self.process_state
        self.target = self.home / '.local/opt/bb-desktop/bb.AppImage'
        self.menu = self.home / '.local/share/applications/dev.bb.desktop.desktop'
        # Sentinel state must survive every installer test, including failures.
        self.sentinels = {}
        for name in ('.bb/config.json', '.bb/env.json', '.bb/auth.json', '.npmrc',
                     '.config/systemd/user/setup-bb-app.service', '.env.local',
                     '.config/fish/config.fish', 'Applications/bb Nightly.app/custom'):
            path = self.home / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b'unchanged fixture state\n')
            self.sentinels[path] = path.read_bytes()

    def tearDown(self):
        for path, value in self.sentinels.items():
            self.assertEqual(path.read_bytes(), value, str(path))
        self.account.stop()
        self.libc.stop()
        self.environment.stop()
        self.temp.cleanup()
        os.umask(self.previous_umask)

    def fetch(self, url, target=None, maximum=None):
        self.calls.append(('fetch', url))
        if target:
            self.assertEqual(url, self.latest['assets'][0]['browser_download_url'])
            target.write_bytes(self.data)
        elif url.endswith('/tags/desktop-latest'):
            return copy.deepcopy(self.latest)
        elif '?per_page=100&page=' in url:
            return copy.deepcopy(self.catalogue)
        else:
            self.fail('Unexpected network target: ' + url)

    def command(self, args):
        self.calls.append(('command', args))
        if args[0] == '/usr/bin/sw_vers':
            return '14.0\n'
        if args[0] == '/usr/bin/lipo':
            return 'arm64\n'
        if args[:2] == ['/usr/bin/codesign', '-dv']:
            return 'Identifier=dev.bb.desktop\nTeamIdentifier=ABCDEFGHIJ\n'
        if args[0] == '/usr/bin/codesign':
            return ''
        if args[0] == '/usr/sbin/spctl':
            return 'accepted\nsource=Notarized Developer ID\n'
        if args[0] == '/usr/bin/ditto':
            with zipfile.ZipFile(args[3]) as archive:
                archive.extractall(args[4])
            return ''
        self.fail('Forbidden native command: ' + repr(args))

    def install(self, platform='linux'):
        return self.ns['install'](platform)

    def old_install(self, number='1.0.0'):
        self.target.parent.mkdir(parents=True, exist_ok=True)
        data = appimage(number)
        self.target.write_bytes(data)
        self.target.chmod(0o700)
        self.catalogue = [release(number, data, tag='desktop-v' + number)]
        return data

    def mac(self):
        self.target = self.home / 'Applications/bb.app'
        self.data = mac_zip(self.number)
        self.latest = release(self.number, self.data, 'macos')

    def test_first_install_and_idempotency(self):
        self.assertEqual(self.install(), 'installed')
        self.assertEqual(self.target.read_bytes(), self.data)
        self.assertEqual(stat.S_IMODE(self.target.stat().st_mode), 0o700)
        menu = self.menu.read_text()
        self.assertIn(' --appimage-extract-and-run\n', menu)
        self.assertNotIn('--no-sandbox', menu)
        self.assertFalse((self.home / '.local/bin/bb').exists())
        before = (self.target.stat(), self.menu.stat())
        self.calls.clear()
        self.assertEqual(self.install(), 'current')
        self.assertEqual(before, (self.target.stat(), self.menu.stat()))
        self.assertEqual(len([c for c in self.calls if c[0] == 'fetch']), 1)
        self.assertFalse((self.target.parent / '.setup-bb-desktop.lock').exists())

    def test_update(self):
        self.old_install()
        self.assertEqual(self.install(), 'installed')
        self.assertEqual(self.target.read_bytes(), self.data)

    def test_newer_self_updated_bytes_not_stale_filename_or_receipt(self):
        original = self.old_install('9.0.0')
        (self.target.parent / 'receipt.json').write_text('{"version":"0.1.0"}')
        self.assertEqual(self.install(), 'newer-preserved')
        self.assertEqual(self.target.read_bytes(), original)
        self.assertTrue(self.menu.exists())

    def test_newer_major_minor_patch_numeric_order(self):
        self.old_install('1.20.0')
        self.assertEqual(self.install(), 'newer-preserved')

    def test_running_deferral_does_not_download_or_change_menu(self):
        original = self.old_install()
        self.process_state = True
        self.assertEqual(self.install(), 'deferred-running')
        self.assertEqual(self.target.read_bytes(), original)
        self.assertFalse(self.menu.exists())
        self.assertFalse(any(c[0] == 'command' for c in self.calls))

    def test_running_at_last_recheck_defers(self):
        original = self.old_install()
        results = iter([False, True])
        self.ns['running'] = lambda *_: next(results)
        self.assertEqual(self.install(), 'deferred-running')
        self.assertEqual(self.target.read_bytes(), original)
        self.assertFalse(self.menu.exists())

    def test_unknown_process_is_failure(self):
        original = self.old_install()
        def denied(*_):
            raise PermissionError('private fixture detail must not be logged')
        self.ns['running'] = denied
        with self.assertRaises(PermissionError):
            self.install()
        self.assertEqual(self.target.read_bytes(), original)

    def test_integrity_and_download_failure_preserve_old(self):
        for failure in ('digest', 'network'):
            with self.subTest(failure=failure):
                original = self.old_install()
                if failure == 'digest':
                    self.latest['assets'][0]['digest'] = 'sha256:' + '0' * 64
                else:
                    self.ns['fetch'] = lambda *_: (_ for _ in ()).throw(OSError('network failure'))
                with self.assertRaises(Exception):
                    self.install()
                self.assertEqual(self.target.read_bytes(), original)
                self.assertFalse(self.menu.exists())
                self.assertFalse((self.target.parent / '.setup-bb-desktop.lock').exists())

    def test_custom_copy_fails_without_overwrite(self):
        self.old_install()
        self.target.write_bytes(appimage('custom'))
        before = self.target.read_bytes()
        with self.assertRaisesRegex(self.ns['Refusal'], 'unverified-installed'):
            self.install()
        self.assertEqual(self.target.read_bytes(), before)

    def test_linked_target_and_parent_fail(self):
        outside = self.base / 'outside'
        outside.write_bytes(b'preserve')
        self.target.parent.mkdir(parents=True)
        self.target.symlink_to(outside)
        with self.assertRaisesRegex(self.ns['Refusal'], 'unsafe-file'):
            self.install()
        self.assertEqual(outside.read_bytes(), b'preserve')
        self.target.unlink()
        self.assertFalse((self.target.parent / '.setup-bb-desktop.lock').exists())
        self.target.parent.rmdir()
        self.target.parent.symlink_to(self.home / 'Applications')
        with self.assertRaisesRegex(self.ns['Refusal'], 'unsafe-directory'):
            self.install()

    def test_fifo_and_hardlinked_targets_fail_without_hang(self):
        self.target.parent.mkdir(parents=True)
        os.mkfifo(self.target)
        with self.assertRaisesRegex(self.ns['Refusal'], 'unsafe-file'):
            self.install()
        self.target.unlink()
        self.assertFalse((self.target.parent / '.setup-bb-desktop.lock').exists())
        outside = self.base / 'outside'
        outside.write_bytes(self.data)
        os.link(outside, self.target)
        with self.assertRaisesRegex(self.ns['Refusal'], 'unsafe-file'):
            self.install()

    def test_unmanaged_or_linked_menu_preserved(self):
        self.menu.parent.mkdir(parents=True, exist_ok=True)
        self.menu.write_text('[Desktop Entry]\ncustom=yes\n')
        with self.assertRaisesRegex(self.ns['Refusal'], 'unmanaged-menu'):
            self.install()
        self.assertIn('custom=yes', self.menu.read_text())
        self.assertFalse(self.target.exists())
        self.menu.unlink()
        self.menu.symlink_to(self.base / 'dangling')
        with self.assertRaisesRegex(self.ns['Refusal'], 'unsafe-file'):
            self.install()

    def test_unsafe_xdg_and_menu_paths(self):
        for data_home in ('relative', str(self.base), str(self.home), ''):
            with patch.dict(os.environ, XDG_DATA_HOME=data_home):
                with self.assertRaisesRegex(self.ns['Refusal'], 'unsafe-menu-directory'):
                    self.install()
        for path in ('/home/test/%F', '/home/test/$var', '/home/test/a\nb', '/home/test/a"b'):
            with self.assertRaisesRegex(self.ns['Refusal'], 'unsafe-menu-path'):
                self.ns['menu_text'](Path(path))
        self.assertIn('Exec="/home/test space/app"', self.ns['menu_text'](Path('/home/test space/app')))

    def test_writable_ancestors_and_foreign_home_rejected(self):
        self.home.chmod(0o777)
        with self.assertRaisesRegex(self.ns['Refusal'], 'unsafe-directory'):
            self.install()
        self.home.chmod(0o700)
        with patch.object(self.ns['pwd'], 'getpwuid', return_value=types.SimpleNamespace(pw_dir='/different')):
            with self.assertRaisesRegex(self.ns['Refusal'], 'wrong-account-home'):
                self.install()

    def test_stale_lock_fails_closed(self):
        self.target.parent.mkdir(parents=True)
        lock = self.target.parent / '.setup-bb-desktop.lock'
        lock.mkdir()
        (lock / 'previous-0').write_text('recovery')
        with self.assertRaises(FileExistsError):
            self.install()
        self.assertEqual((lock / 'previous-0').read_text(), 'recovery')

    def test_missing_or_failing_unshare_is_not_an_installation_requirement(self):
        for error in (FileNotFoundError('unshare absent'), self.ns['Refusal']('native-check-failed')):
            with self.subTest(error=type(error).__name__):
                self.old_install()
                probe = Mock(side_effect=error)
                self.ns['command'] = probe
                with patch.object(subprocess, 'run', side_effect=AssertionError('native launch/probe attempted')):
                    self.assertEqual(self.install(), 'installed')
                probe.assert_not_called()
                self.assertEqual(self.target.read_bytes(), self.data)
                self.assertTrue(self.menu.exists())

    def test_old_glibc_fails_without_installation(self):
        with patch.object(os, 'confstr', return_value='glibc 2.31'):
            with self.assertRaisesRegex(self.ns['Refusal'], 'glibc-too-old'):
                self.install()
        self.assertFalse(self.target.exists())

    def test_apparmor_flag_and_opaque_per_app_policy_are_not_inspected(self):
        self.restriction.write_text('1\n')
        policy = self.base / 'etc/apparmor.d/bb'
        policy.parent.mkdir(parents=True)
        policy.write_text('fixture application-specific policy; intentionally not interpreted\n')
        snapshot = {path: path.read_bytes() for path in (self.restriction, policy)}
        prior_path = self.ns['Path']
        def no_policy_path(*args):
            if args and ('apparmor' in str(args[0]) or str(args[0]) in ('/proc/sys/kernel/unprivileged_userns_clone', '/proc/sys/user/max_user_namespaces')):
                self.fail('installer inspected sandbox policy')
            return prior_path(*args)
        self.ns['Path'] = no_policy_path
        with patch.object(subprocess, 'run', side_effect=AssertionError('native launch/probe attempted')):
            self.assertEqual(self.install(), 'installed')
            self.assertEqual(self.install(), 'current')
            self.old_install('9.0.0')
            self.assertEqual(self.install(), 'newer-preserved')
        self.assertEqual(snapshot, {path: path.read_bytes() for path in snapshot})
        self.assertTrue(self.menu.exists())
        self.assertFalse(any(c[0] == 'command' for c in self.calls))

    def test_restricted_policy_does_not_hide_real_integrity_failure(self):
        self.restriction.write_text('1\n')
        original = self.old_install()
        self.latest['assets'][0]['digest'] = 'sha256:' + '0' * 64
        with self.assertRaisesRegex(self.ns['Refusal'], 'integrity-mismatch'):
            self.install()
        self.assertEqual(self.target.read_bytes(), original)
        self.assertFalse(self.menu.exists())
        self.assertEqual(self.restriction.read_text(), '1\n')

    def test_unknown_sandbox_state_does_not_block_verified_installation(self):
        # No policy state is available, and the installer must not ask for it.
        self.restriction.unlink()
        self.ns['command'] = Mock(side_effect=AssertionError('unexpected native probe'))
        with patch.object(subprocess, 'run', side_effect=AssertionError('native launch/probe attempted')):
            self.assertEqual(self.install(), 'installed')
        self.ns['command'].assert_not_called()
        self.assertEqual(self.target.read_bytes(), self.data)
        self.assertFalse(self.restriction.exists())

    def test_menu_promotion_failure_rolls_back_both_objects(self):
        original = self.old_install()
        self.menu.parent.mkdir(parents=True, exist_ok=True)
        self.menu.write_text(self.ns['menu_text'](self.target))
        menu_before = self.menu.read_bytes()
        rename = os.rename
        def fail_menu(source, dest):
            if str(source).endswith('/menu.desktop'):
                raise OSError('inert promotion failure')
            rename(source, dest)
        with patch.object(os, 'rename', side_effect=fail_menu):
            with self.assertRaises(OSError):
                self.install()
        self.assertEqual(self.target.read_bytes(), original)
        self.assertEqual(self.menu.read_bytes(), menu_before)

    def test_post_install_verification_failure_rolls_back(self):
        original = self.old_install()
        original_fingerprint = self.ns['fingerprint']
        def changed(path, macos=False):
            result = original_fingerprint(path, macos)
            if path == self.target and path.read_bytes() == self.data:
                return '0' * 64
            return result
        self.ns['fingerprint'] = changed
        with self.assertRaisesRegex(self.ns['Refusal'], 'integrity-mismatch'):
            self.install()
        self.assertEqual(self.target.read_bytes(), original)
        self.assertFalse(self.menu.exists())

    def test_mac_first_install_current_and_newer(self):
        self.mac()
        self.assertEqual(self.install('macos'), 'installed')
        before = (self.target / 'Contents/Info.plist').read_bytes()
        self.assertEqual(self.install('macos'), 'current')
        self.assertEqual((self.target / 'Contents/Info.plist').read_bytes(), before)
        self.number = '1.0.0'
        self.data = mac_zip(self.number)
        self.latest = release(self.number, self.data, 'macos')
        self.assertEqual(self.install('macos'), 'newer-preserved')
        self.assertEqual((self.target / 'Contents/Info.plist').read_bytes(), before)

    def test_mac_identity_signature_notarization_failure(self):
        self.mac()
        self.data = mac_zip(self.number, 'dev.bb.desktop.nightly')
        self.latest = release(self.number, self.data, 'macos')
        with self.assertRaisesRegex(self.ns['Refusal'], 'wrong-bundle-identity'):
            self.install('macos')
        self.assertFalse(self.target.exists())
        self.assertFalse((self.target.parent / '.setup-bb-desktop.lock').exists())
        self.mac()
        command = self.command
        self.ns['command'] = lambda args: 'source=Developer ID\n' if args[0] == '/usr/sbin/spctl' else command(args)
        with self.assertRaisesRegex(self.ns['Refusal'], 'not-notarized'):
            self.install('macos')
        self.assertFalse(self.target.exists())

    def test_mac_update_running_and_signer_mismatch(self):
        self.mac()
        self.assertEqual(self.install('macos'), 'installed')
        original = (self.target / 'Contents/Info.plist').read_bytes()
        self.number = '2.0.0'
        self.mac()
        self.process_state = True
        self.assertEqual(self.install('macos'), 'deferred-running')
        self.assertEqual((self.target / 'Contents/Info.plist').read_bytes(), original)
        self.process_state = False
        command = self.command
        def different_team(args):
            text = command(args)
            return text.replace('ABCDEFGHIJ', 'OTHERTEAM0') if 'stage-' in args[-1] else text
        self.ns['command'] = different_team
        with self.assertRaisesRegex(self.ns['Refusal'], 'different-signing-team'):
            self.install('macos')
        self.assertEqual((self.target / 'Contents/Info.plist').read_bytes(), original)

    def test_mac_native_rejections_preserve_installed_bundle(self):
        self.mac()
        self.assertEqual(self.install('macos'), 'installed')
        original = (self.target / 'Contents/Info.plist').read_bytes()
        for failure in ('signature', 'architecture', 'os-version'):
            def native(args):
                if failure == 'signature' and args[:2] == ['/usr/bin/codesign', '--verify']:
                    raise self.ns['Refusal']('native-check-failed')
                if failure == 'architecture' and args[0] == '/usr/bin/lipo':
                    return 'x86_64\n'
                if failure == 'os-version' and args[0] == '/usr/bin/sw_vers':
                    return '12.0\n'
                return self.command(args)
            self.ns['command'] = native
            with self.subTest(failure=failure), self.assertRaises(self.ns['Refusal']):
                self.install('macos')
            self.assertEqual((self.target / 'Contents/Info.plist').read_bytes(), original)

    def test_nonexecutable_appimage_is_not_reported_current(self):
        self.old_install(self.number)
        self.target.chmod(0o600)
        with self.assertRaisesRegex(self.ns['Refusal'], 'nonexecutable-appimage'):
            self.install()
        self.assertEqual(stat.S_IMODE(self.target.stat().st_mode), 0o600)

    def test_changed_installation_before_promotion_is_preserved(self):
        self.old_install()
        concurrent = appimage('9.0.0')
        self.catalogue.append(release('9.0.0', concurrent, tag='desktop-v9.0.0'))
        def fetch(url, target=None, maximum=None):
            result = self.fetch(url, target, maximum)
            if target:
                self.target.write_bytes(concurrent)
            return result
        self.ns['fetch'] = fetch
        with self.assertRaisesRegex(self.ns['Refusal'], 'installation-changed'):
            self.install()
        self.assertEqual(self.target.read_bytes(), concurrent)
        self.assertFalse(self.menu.exists())

    def test_bounded_transport_and_private_staging(self):
        class Response(io.BytesIO):
            status = 200
        class Opener:
            def open(inner, request, timeout):
                self.assertEqual(timeout, 30)
                self.assertNotIn('Authorization', request.headers)
                return Response(b'{"fixture":true}')
        with patch.object(self.ns['urllib'].request, 'build_opener', return_value=Opener()):
            self.assertEqual(self.real_fetch(self.ns['API']), {'fixture': True})
            target = self.base / 'download'
            self.real_fetch(self.ns['API'], target, 100)
            self.assertEqual(stat.S_IMODE(target.stat().st_mode), 0o600)
            with self.assertRaises(FileExistsError):
                self.real_fetch(self.ns['API'], target, 100)
            with self.assertRaisesRegex(self.ns['Refusal'], 'download-limit'):
                self.real_fetch(self.ns['API'], maximum=1)

    def test_zip_traversal_and_links_rejected_before_extraction(self):
        for name, content, mode in (
            ('bb.app/../../escape', b'x', 0),
            ('/bb.app/absolute', b'x', 0),
            ('bb.app/link', b'../../outside', stat.S_IFLNK | 0o777),
        ):
            archive = self.base / 'bad.zip'
            with zipfile.ZipFile(archive, 'w') as z:
                info = zipfile.ZipInfo(name)
                info.external_attr = mode << 16
                z.writestr(info, content)
            with self.assertRaises(self.ns['Refusal']):
                self.ns['unpack_mac'](archive, self.base / 'extract')
            self.assertFalse(any(c[0] == 'command' for c in self.calls))

    def test_release_metadata_matrix(self):
        valid = self.latest
        self.assertEqual(self.ns['release_asset'](valid, 'linux', 'desktop-latest')['version'], '1.2.3')
        changes = [({'draft': True}, None), ({'prerelease': True}, None),
                   ({'tag_name': 'desktop-nightly'}, None), ({'html_url': 'https://evil.test'}, None),
                   ({'assets': valid['assets'] * 2}, None),
                   (None, {'digest': None}), (None, {'digest': 'sha256:' + 'X' * 64}),
                   (None, {'size': -1}), (None, {'size': True}), (None, {'state': 'new'}),
                   (None, {'name': 'bb-1.2.3-nightly-x86_64.AppImage'}),
                   (None, {'browser_download_url': 'http://github.com/get-bb/bb/file'}),
                   (None, {'browser_download_url': 'https://evil.test/bb.AppImage'})]
        for top, asset in changes:
            bad = copy.deepcopy(valid)
            bad.update(top or {})
            bad['assets'][0].update(asset or {})
            with self.subTest(top=top, asset=asset), self.assertRaises(self.ns['Refusal']):
                self.ns['release_asset'](bad, 'linux', 'desktop-latest')
        with self.assertRaises(self.ns['Refusal']):
            json.loads('{"a":1,"a":2}', object_pairs_hook=self.ns['unique_json'])

    def test_redirect_rejects_untrusted_destinations(self):
        redirects = self.ns['Redirects']()
        for url in ('http://github.com/file', 'https://evil.test/file', 'https://github.com@evil.test/file',
                    'https://github.com:444/file', 'https://token@github.com/file'):
            with self.assertRaises(self.ns['Refusal']):
                redirects.redirect_request(None, None, 302, '', {}, url)

    def test_main_does_not_echo_exception_details(self):
        self.ns['install'] = lambda *_: (_ for _ in ()).throw(OSError('SECRET arbitrary exception'))
        output = io.StringIO()
        with patch.object(self.ns['sys'], 'argv', ['helper', 'linux']), patch('sys.stdout', output):
            self.assertEqual(self.ns['main'](), 1)
        self.assertEqual(output.getvalue(), 'failed:operation-error\n')

    def test_unrelated_inaccessible_environment_is_not_desktop_evidence(self):
        proc = self.base / 'proc'
        pid = proc / '123'
        pid.mkdir(parents=True)
        (pid / 'stat').write_text('123 (unrelated) ' + ' '.join(['S'] + ['0'] * 18 + ['456']))
        (pid / 'status').write_text('Name:\tunrelated\nState:\tS\nUid:\t' + '\t'.join([str(os.getuid())] * 4) + '\n')
        (pid / 'exe').symlink_to('/usr/bin/unrelated')
        (pid / 'environ').write_bytes(b'OTHER=1\0')
        self.ns['Path'] = lambda *args: proc if args == ('/proc',) else Path(*args)
        read_bytes = Path.read_bytes
        def denied(path):
            if path == pid / 'environ':
                raise PermissionError('unrelated private environment')
            return read_bytes(path)
        with patch.object(Path, 'read_bytes', denied):
            self.assertFalse(self.real_running(self.target, 'linux'))

    def proc_row(self, exe, name='bb', environment=None, owners=None):
        proc = self.base / 'candidate-proc'
        pid = proc / '123'
        pid.mkdir(parents=True, exist_ok=True)
        (pid / 'stat').write_text('123 (' + name + ') ' + ' '.join(['S'] + ['0'] * 18 + ['456']))
        owners = owners or [os.getuid()] * 4
        (pid / 'status').write_text('Name:\t' + name + '\nState:\tS\nUid:\t' + '\t'.join(map(str, owners)) + '\n')
        (pid / 'exe').symlink_to(exe)
        (pid / 'environ').write_bytes(environment if environment is not None else b'APPIMAGE=' + os.fsencode(self.target) + b'\0')
        prior_path = self.ns['Path']
        self.ns['Path'] = lambda *args: proc if args == ('/proc',) else prior_path(*args)
        return pid

    def test_real_inventory_allows_install_and_update_with_unrelated_private_environment(self):
        pid = self.proc_row('/usr/bin/node', name='node')
        self.ns['running'] = self.real_running
        read_bytes = Path.read_bytes
        def denied(path):
            if path == pid / 'environ':
                raise PermissionError('unrelated environment')
            return read_bytes(path)
        with patch.object(Path, 'read_bytes', denied):
            self.assertEqual(self.install(), 'installed')
            self.old_install('1.0.0')
            self.assertEqual(self.install(), 'installed')
            self.assertEqual(self.target.read_bytes(), self.data)

    def test_native_title_on_unrelated_executable_never_reads_environment(self):
        self.proc_row('/usr/bin/node', name='bb')
        with patch.object(Path, 'read_bytes', side_effect=AssertionError('unrelated environment read')):
            self.assertFalse(self.real_running(self.target, 'linux'))

    def test_inherited_appimage_on_unrelated_child_is_ignored(self):
        self.proc_row('/usr/bin/git', name='git')
        with patch.object(Path, 'read_bytes', side_effect=AssertionError('inherited environment read')):
            self.assertFalse(self.real_running(self.target, 'linux'))

    def test_custom_tmpdir_mounted_and_extracted_desktops(self):
        for directory in ('/run/user/1000/private temp/.mount_renamedABC', '/var/tmp/custom/appimage_extracted_abcd'):
            with self.subTest(directory=directory):
                pid = self.proc_row(directory + '/bb', name='renderer')
                self.assertTrue(self.real_running(self.target, 'linux'))
                (pid / 'exe').unlink()

    def test_relevant_inaccessible_environment_fails_closed(self):
        self.proc_row('/custom/temp/.mount_bbABC/bb')
        with patch.object(Path, 'read_bytes', side_effect=PermissionError('private')):
            with self.assertRaisesRegex(self.ns['Refusal'], 'process-environment-unverified'):
                self.real_running(self.target, 'linux')

    def test_exact_appimage_process_needs_no_environment_read(self):
        for suffix in ('', ' (deleted)'):
            pid = self.proc_row(str(self.target) + suffix, name='renamed')
            with patch.object(Path, 'read_bytes', side_effect=AssertionError('unneeded environment read')):
                self.assertTrue(self.real_running(self.target, 'linux'))
            (pid / 'exe').unlink()

    def test_unknown_same_user_executable_fails_closed(self):
        self.proc_row('/custom/temp/.mount_bbABC/bb')
        with patch.object(os, 'readlink', side_effect=PermissionError('private')):
            with self.assertRaisesRegex(self.ns['Refusal'], 'process-executable-unverified'):
                self.real_running(self.target, 'linux')

    def test_foreign_unrelated_executable_and_environment_not_read(self):
        foreign = os.getuid() + 10000
        self.proc_row('/usr/bin/node', name='bb', owners=[foreign] * 4)
        with patch.object(Path, 'read_bytes', side_effect=AssertionError('foreign environment read')):
            self.assertFalse(self.real_running(self.target, 'linux'))

    def test_foreign_relevant_executable_is_ownership_failure(self):
        foreign = os.getuid() + 10000
        self.proc_row('/custom/temp/.mount_bbABC/bb', owners=[foreign] * 4)
        with patch.object(Path, 'read_bytes', side_effect=AssertionError('foreign environment read')):
            with self.assertRaisesRegex(self.ns['Refusal'], 'process-owner'):
                self.real_running(self.target, 'linux')

    def test_inaccessible_foreign_executable_requires_title_screening(self):
        foreign = os.getuid() + 10000
        pid = self.proc_row('/usr/bin/unrelated', name='unrelated', owners=[foreign] * 4)
        with patch.object(os, 'readlink', side_effect=PermissionError('private')):
            self.assertFalse(self.real_running(self.target, 'linux'))
            (pid / 'status').write_text('Name:\tbb\nState:\tS\nUid:\t' + '\t'.join([str(foreign)] * 4) + '\n')
            with self.assertRaisesRegex(self.ns['Refusal'], 'process-executable-unverified'):
                self.real_running(self.target, 'linux')

    def test_unknown_desktop_location_cannot_be_safe_deferral(self):
        self.proc_row('/custom/non-runtime/bb')
        with self.assertRaisesRegex(self.ns['Refusal'], 'unverified-desktop-executable'):
            self.real_running(self.target, 'linux')

    def test_other_appimage_is_preserved_without_blocking_target(self):
        self.proc_row('/custom/temp/.mount_bbNightlyABC/bb', environment=b'APPIMAGE=/other/bb.AppImage\0')
        self.assertFalse(self.real_running(self.target, 'linux'))

    def test_process_identity_and_executable_swaps_fail_closed(self):
        pid = self.proc_row('/custom/temp/.mount_bbABC/bb')
        read_bytes = Path.read_bytes
        def replaced(path):
            data = read_bytes(path)
            (pid / 'stat').write_text((pid / 'stat').read_text().replace('456', '457'))
            return data
        with patch.object(Path, 'read_bytes', replaced):
            with self.assertRaisesRegex(self.ns['Refusal'], 'process-changed'):
                self.real_running(self.target, 'linux')
        with patch.object(os, 'readlink', side_effect=['/usr/bin/node', '/custom/temp/.mount_bbABC/bb']):
            with self.assertRaisesRegex(self.ns['Refusal'], 'process-changed'):
                self.real_running(self.target, 'linux')

    def test_scheduling_state_changes_are_not_identity_changes(self):
        pid = self.proc_row('/usr/bin/node', name='node')
        readlink = os.readlink
        def scheduled(path):
            value = readlink(path)
            (pid / 'status').write_text((pid / 'status').read_text().replace('State:\tS', 'State:\tR'))
            return value
        with patch.object(os, 'readlink', scheduled):
            self.assertFalse(self.real_running(self.target, 'linux'))

    def test_uid_changes_during_unrelated_exclusion_fail_closed(self):
        pid = self.proc_row('/usr/bin/node', name='node')
        readlink = os.readlink
        def changed(path):
            value = readlink(path)
            uid = str(os.getuid())
            (pid / 'status').write_text((pid / 'status').read_text().replace('Uid:\t' + uid, 'Uid:\t12345'))
            return value
        with patch.object(os, 'readlink', changed):
            with self.assertRaisesRegex(self.ns['Refusal'], 'process-changed'):
                self.real_running(self.target, 'linux')

    def test_ambiguous_appimage_environment_fails_closed(self):
        self.proc_row('/custom/temp/.mount_bbABC/bb', environment=b'APPIMAGE=/one\0APPIMAGE=/two\0')
        with self.assertRaisesRegex(self.ns['Refusal'], 'ambiguous-process'):
            self.real_running(self.target, 'linux')

    def test_foreign_exclusion_does_not_read_executable_or_environment(self):
        foreign = os.getuid() + 10000
        self.proc_row('/root/private/tool', name='unrelated', owners=[foreign] * 4)
        with patch.object(os, 'readlink', side_effect=AssertionError('foreign executable read')), \
                patch.object(Path, 'read_bytes', side_effect=AssertionError('foreign environment read')):
            self.assertFalse(self.real_running(self.target, 'linux'))

    def test_exited_candidate_is_not_reported_as_running(self):
        pid = self.proc_row(str(self.target))
        calls = []
        def exited(path):
            calls.append(path)
            if len(calls) == 1:
                return str(self.target)
            for child in pid.iterdir():
                child.unlink()
            pid.rmdir()
            raise FileNotFoundError('fixture exited')
        with patch.object(os, 'readlink', exited):
            self.assertFalse(self.real_running(self.target, 'linux'))

    def test_missing_executable_for_live_process_is_not_exit(self):
        pid = self.proc_row('/custom/temp/.mount_bbABC/bb')
        (pid / 'exe').unlink()
        with self.assertRaisesRegex(self.ns['Refusal'], 'process-inspection'):
            self.real_running(self.target, 'linux')

    def test_linux_process_inventory_and_ownership(self):
        proc = self.base / 'proc'
        proc.mkdir()
        pid = proc / '123'
        pid.mkdir()
        (pid / 'stat').write_text('123 (bb) ' + ' '.join(['S'] + ['0'] * 18 + ['456']))
        (pid / 'status').write_text('Name:\tbb\nState:\tS (sleeping)\nUid:\t' + '\t'.join([str(os.getuid())] * 4) + '\n')
        (pid / 'environ').write_bytes(b'APPIMAGE=' + os.fsencode(self.target) + b'\0SECRET=never print\0')
        (pid / 'exe').symlink_to('/tmp/.mount_bbABCD/bb')
        self.ns['Path'] = lambda *args: proc if args == ('/proc',) else Path(*args)
        self.assertTrue(self.real_running(self.target, 'linux'))
        (pid / 'exe').unlink()
        (pid / 'exe').symlink_to('/custom/bb')
        with self.assertRaisesRegex(self.ns['Refusal'], 'unverified-desktop-executable'):
            self.real_running(self.target, 'linux')
        (pid / 'status').write_text('Name:\tunrelated\nState:\tS\nUid:\t12345\t12345\t12345\t12345\n')
        (pid / 'environ').unlink()
        (pid / 'exe').unlink()
        (pid / 'exe').symlink_to('/usr/bin/unrelated')
        self.assertFalse(self.real_running(self.target, 'linux'))
        (pid / 'exe').unlink()
        (pid / 'exe').symlink_to('/custom/bb')
        (pid / 'status').write_text('Name:\tbb\nState:\tS\nUid:\t' + str(os.getuid()) + '\t12345\t12345\t12345\n')
        with self.assertRaisesRegex(self.ns['Refusal'], 'process-owner'):
            self.real_running(self.target, 'linux')

    def test_trusted_bazzite_alias_and_rejections(self):
        # Simulate root-owned system paths without touching /home or needing sudo.
        raw = '/home/bb-fixture'
        canonical = Path('/var/home/bb-fixture')
        target = ['var/home']
        owner = [0]
        parent_mode = [stat.S_IFDIR | 0o755]
        def lstat(path, **_):
            if str(path) == '/home':
                return types.SimpleNamespace(st_uid=owner[0], st_mode=stat.S_IFLNK | 0o777)
            if str(path) in ('/', '/var', '/var/home'):
                return types.SimpleNamespace(st_uid=0, st_mode=parent_mode[0])
            self.fail('Unexpected alias lstat')
        def path_stat(path, **_):
            if path == canonical:
                return types.SimpleNamespace(st_uid=os.getuid(), st_mode=stat.S_IFDIR | 0o700)
            return lstat(path)
        checked = []
        self.ns['directory'] = lambda p: checked.append(p)
        self.ns['Path'] = Path
        with patch.object(os, 'lstat', side_effect=lstat), patch.object(os, 'readlink', side_effect=lambda _: target[0]), \
                patch.object(Path, 'stat', autospec=True, side_effect=path_stat), \
                patch.object(self.ns['pwd'], 'getpwuid', return_value=types.SimpleNamespace(pw_dir=raw)):
            self.assertEqual(self.ns['trusted_home'](raw, 'linux'), canonical)
            self.assertEqual(checked, [canonical])
            target[0] = '/var/home'
            self.assertEqual(self.ns['trusted_home'](raw, 'linux'), canonical)
            for invalid in ('/tmp/elsewhere', '../var/home'):
                target[0] = invalid
                with self.assertRaisesRegex(self.ns['Refusal'], 'unsafe-home-alias'):
                    self.ns['trusted_home'](raw, 'linux')
            target[0] = 'var/home'
            owner[0] = 99999
            with self.assertRaisesRegex(self.ns['Refusal'], 'unsafe-home-alias'):
                self.ns['trusted_home'](raw, 'linux')
            owner[0] = 0
            parent_mode[0] = stat.S_IFDIR | 0o777
            with self.assertRaisesRegex(self.ns['Refusal'], 'unsafe-home-alias'):
                self.ns['trusted_home'](raw, 'linux')

    def test_bazzite_xdg_alias_uses_resolved_home_only(self):
        self.ns['trusted_home'] = lambda *_: self.home
        with patch.dict(os.environ, HOME='/home/fixture', XDG_DATA_HOME='/home/fixture/.local/share'):
            self.assertEqual(self.install(), 'installed')
        self.assertTrue(self.menu.exists())

    def test_mac_process_inspection(self):
        path = self.home / 'Applications/bb.app'
        self.ns['command'] = lambda _: f'{os.getuid()} 123 {path}/Contents/MacOS/bb\n'
        self.assertTrue(self.real_running(path, 'macos'))
        self.ns['command'] = lambda _: f'{os.getuid()} 123 bb\n'
        with self.assertRaisesRegex(self.ns['Refusal'], 'ambiguous-process'):
            self.real_running(path, 'macos')


class MacApplicationsTests(unittest.TestCase):
    """Real installer, inert native checks, reported macOS metadata on private files.

    No chown, host /Applications access or desktop execution. The path adapter
    maps native absolute paths before any installer I/O; stat/fstat agree on the
    simulated account. HOME's native deny-delete ACL is not a POSIX mode bit and
    is deliberately not invented as additional write authority by this fixture.
    """
    setUp = DesktopTests.setUp
    tearDown = DesktopTests.tearDown
    fetch = DesktopTests.fetch
    install = DesktopTests.install

    def command(self, args):
        if args[0] != '/bin/ps':
            return DesktopTests.command(self, args)
        self.assertEqual(args, ['/bin/ps', '-ww', '-axo', 'uid=,pid=,comm='])
        self.calls.append(('command', args))
        # Exercise the real command decoder and parser with successful native
        # query bytes, not a precomputed process list. All other native execution
        # remains forbidden by native_layout's subprocess guard.
        result = subprocess.CompletedProcess(args, 0, self.process_rows.encode(), b'')
        with patch.object(subprocess, 'run', return_value=result):
            return self.real_command(args)

    def native_layout(self, number='1.0.0', uid=501):
        self.process_rows = '0 1 /usr/bin/unrelated\n'
        self.ns['running'] = self.real_running
        native = self.base / 'native'
        users = native / 'Users'
        users.mkdir(parents=True)
        home = users / 'scowalt'
        self.home.rename(home)
        self.sentinels = {home / p.relative_to(self.home): data for p, data in self.sentinels.items()}
        self.home = home
        os.environ['HOME'] = str(home)
        # getpwuid was installed by the base fixture as a Mock.
        self.ns['pwd'].getpwuid.return_value = types.SimpleNamespace(pw_dir=str(home))
        self.target = native / 'Applications/bb.app'
        self.target.parent.mkdir()
        with zipfile.ZipFile(io.BytesIO(mac_zip(number))) as archive:
            archive.extractall(self.target.parent)
        self.data = mac_zip(self.number)
        self.latest = release(self.number, self.data, 'macos')
        self.ns['UID'] = uid
        self.ns['Path'] = lambda *args: native / Path(*args).relative_to('/') if args and str(args[0]) in (
            '/', '/Applications', '/Applications/bb.app') else Path(*args)
        self.metadata = {
            native: dict(st_uid=0, st_gid=0, st_mode=stat.S_IFDIR | 0o755),
            users: dict(st_uid=0, st_gid=80, st_mode=stat.S_IFDIR | 0o755),
            home: dict(st_uid=uid, st_gid=20, st_mode=stat.S_IFDIR | 0o755),
            home / 'Applications': dict(st_uid=uid, st_gid=20, st_mode=stat.S_IFDIR | 0o700),
            self.target.parent: dict(st_uid=0, st_gid=80, st_mode=stat.S_IFDIR | 0o775),
            self.target: dict(st_uid=uid, st_gid=80, st_mode=stat.S_IFDIR | 0o755),
        }
        real_stat, real_fstat = Path.stat, os.fstat
        def metadata(s, overrides=None):
            fields = {key: getattr(s, key) for key in dir(s) if key.startswith('st_')}
            if s.st_uid == os.getuid():
                fields.update(st_uid=uid, st_gid=20)
            fields.update(overrides or {})
            return types.SimpleNamespace(**fields)
        def path_stat(path, **kwargs):
            return metadata(real_stat(path, **kwargs), self.metadata.get(path))
        self.addCleanup(patch.stopall)
        patch.object(Path, 'stat', path_stat).start()
        patch.object(os, 'fstat', lambda fd: metadata(real_fstat(fd))).start()
        patch.object(self.ns['sys'], 'platform', 'darwin').start()
        patch.object(subprocess, 'run', side_effect=AssertionError('native execution forbidden')).start()

    def assert_unrelated_uid_allows_update(self, owner, pids):
        self.native_layout()
        self.process_rows = ''.join(f'{owner} {pid} /usr/bin/unrelated\n' for pid in pids)
        self.assertEqual(self.install('macos'), 'installed')
        self.assertEqual(plistlib.loads(self.installed_bytes())['CFBundleShortVersionString'], self.number)
        self.assertFalse((self.target.parent / '.setup-bb-desktop.lock').exists())
        self.assertFalse((self.home / 'Applications/bb.app').exists())

    def test_observed_two_signed_uid_rows_allow_update(self):
        self.assert_unrelated_uid_allows_update('-2', (53750, 53752))

    def test_minimized_one_signed_uid_row_allows_update(self):
        self.assert_unrelated_uid_allows_update('-2', (53750,))

    def test_observed_two_unsigned_uid_rows_allow_update(self):
        self.assert_unrelated_uid_allows_update('4294967294', (53750, 53752))

    def test_minimized_one_unsigned_uid_row_allows_update(self):
        self.assert_unrelated_uid_allows_update('4294967294', (53750,))

    def installed_snapshot(self):
        paths = [self.target, *self.target.rglob('*')]
        return {str(p.relative_to(self.target)): (
            self.ns['stable'](p.lstat()), p.lstat().st_gid, p.read_bytes() if p.is_file() else None
        ) for p in paths}

    def test_invalid_uids_refuse_even_on_unrelated_rows(self):
        self.native_layout()
        original = self.installed_snapshot()
        for owner in ('-1', '4294967295', '-2147483649', '4294967296', '-9999999999',
                      'unknown', '+2', '--2', '+-2', '-+2', '2-', '2+', '−2', '２', '²',
                      '1e3', '1.0', '0x1', '1_0', 'NaN', '9' * 100, '', ' '):
            with self.subTest(owner=owner):
                self.process_rows = f'{owner} 53750 /usr/bin/unrelated\n'
                with self.assertRaisesRegex(self.ns['Refusal'], '^process-inspection$'):
                    self.install('macos')
                self.assertEqual(self.installed_snapshot(), original)
                self.assertFalse((self.target.parent / '.setup-bb-desktop.lock').exists())

    def test_valid_uid_and_pid_edges_keep_current_bundle(self):
        self.native_layout(self.number)
        original = self.installed_snapshot()
        for owner in ('0', '501', '999', '2147483647', '2147483648', '4294967294',
                      '-2147483648', '-2147483647', '-2', '0000000501'):
            with self.subTest(owner=owner):
                self.process_rows = (f'0 0 kernel_task\n{owner} 2147483647 /usr/bin/unrelated\n'
                                     '501 123 /Applications/Unrelated App.app/Contents/MacOS/tool\n')
                self.assertEqual(self.install('macos'), 'current')
                self.assertEqual(self.installed_snapshot(), original)

    def test_malformed_rows_refuse_before_relevance_or_running_deferral(self):
        self.native_layout()
        original = self.installed_snapshot()
        for row in ('', '\n', '501', '501 123', '501 123   ', 'extra 501 123 /usr/bin/unrelated',
                    '501 extra 123 /usr/bin/unrelated', 'uid pid comm'):
            with self.subTest(row=row):
                # A valid relevant row must not hide a malformed later row.
                self.process_rows = f'501 123 {self.target}/Contents/MacOS/bb\n' + row + '\n'
                with self.assertRaisesRegex(self.ns['Refusal'], '^process-inspection$'):
                    self.install('macos')
                self.assertEqual(self.installed_snapshot(), original)

    def test_empty_inventory_refuses_without_changing_bundle(self):
        self.native_layout()
        original = self.installed_snapshot()
        self.process_rows = ''
        with self.assertRaisesRegex(self.ns['Refusal'], '^process-inspection$'):
            self.install('macos')
        self.assertEqual(self.installed_snapshot(), original)

    def test_foreign_relevant_signed_and_unsigned_uids_still_refuse(self):
        self.native_layout()
        original = self.installed_snapshot()
        for owner in ('-2', '4294967294', '-2147483648', '2147483648', '0', '999'):
            with self.subTest(owner=owner):
                self.process_rows = f'{owner} 53750 {self.target}/Contents/MacOS/bb\n'
                with self.assertRaisesRegex(self.ns['Refusal'], '^process-owner$'):
                    self.install('macos')
                self.assertEqual(self.installed_snapshot(), original)

    def test_negative_uid_is_not_absolute_value_owner(self):
        self.native_layout(uid=2)
        original = self.installed_snapshot()
        self.process_rows = f'-2 53750 {self.target}/Contents/MacOS/bb\n'
        with self.assertRaisesRegex(self.ns['Refusal'], '^process-owner$'):
            self.install('macos')
        self.assertEqual(self.installed_snapshot(), original)

    def assert_equivalent_owner_defers(self, uid, signed):
        self.native_layout(uid=uid)
        original = self.installed_snapshot()
        for owner in (signed, str(uid)):
            with self.subTest(owner=owner):
                self.process_rows = f'{owner} 53750 {self.target}/Contents/MacOS/bb\n'
                with patch.object(os, 'rename', side_effect=AssertionError('running app renamed')):
                    self.assertEqual(self.install('macos'), 'deferred-running')
                self.assertEqual(self.installed_snapshot(), original)

    def test_signed_and_unsigned_high_account_uid_both_defer(self):
        self.assert_equivalent_owner_defers(4294967294, '-2')

    def test_signed_lower_bound_and_unsigned_account_uid_both_defer(self):
        self.assert_equivalent_owner_defers(2147483648, '-2147483648')

    def test_mixed_inventory_defers_account_candidate_in_either_order(self):
        self.native_layout()
        original = self.installed_snapshot()
        rows = ['-2 53750 /usr/bin/unrelated', '0 0 kernel_task',
                f'501 123 {self.target}/Contents/MacOS/bb Helper (Renderer)',
                '999 321 /usr/bin/unrelated', '-2147483648 53752 /usr/bin/unrelated']
        for inventory in (rows, list(reversed(rows))):
            with self.subTest(inventory=inventory):
                self.process_rows = '\n'.join(inventory) + '\n'
                with patch.object(os, 'rename', side_effect=AssertionError('running app renamed')), \
                        patch.object(os, 'chmod', side_effect=AssertionError('permission repair forbidden')), \
                        patch.object(os, 'chown', side_effect=AssertionError('ownership repair forbidden')), \
                        patch.object(os, 'kill', side_effect=AssertionError('process termination forbidden')):
                    self.assertEqual(self.install('macos'), 'deferred-running')
                self.assertEqual(self.installed_snapshot(), original)

    def test_signed_rows_preserve_current_and_newer_copies(self):
        self.native_layout(self.number)
        original = self.installed_snapshot()
        self.process_rows = '-2 53750 /usr/bin/unrelated\n'
        self.assertEqual(self.install('macos'), 'current')
        self.data = mac_zip('1.0.0')
        self.latest = release('1.0.0', self.data, 'macos')
        self.assertEqual(self.install('macos'), 'newer-preserved')
        self.assertEqual(self.installed_snapshot(), original)

    def test_ambiguous_titles_with_signed_uids_still_refuse(self):
        self.native_layout()
        original = self.installed_snapshot()
        for owner in ('-2', '4294967294', '501'):
            with self.subTest(owner=owner):
                self.process_rows = f'{owner} 53750 bb Helper (Renderer)\n'
                with self.assertRaisesRegex(self.ns['Refusal'], '^ambiguous-process$'):
                    self.install('macos')
                self.assertEqual(self.installed_snapshot(), original)

    def test_invalid_pids_refuse_without_changing_bundle(self):
        self.native_layout()
        original = self.installed_bytes()
        for pid in ('-2', '+123', '12x', '1.5', '１２３', '²', '2147483648', '9' * 100):
            with self.subTest(pid=pid):
                self.process_rows = f'501 {pid} /usr/bin/unrelated\n'
                with self.assertRaisesRegex(self.ns['Refusal'], '^process-inspection$'):
                    self.install('macos')
                self.assertEqual(self.installed_bytes(), original)
                self.assertFalse((self.target.parent / '.setup-bb-desktop.lock').exists())

    def test_root_admin_parent_without_group_write_also_updates(self):
        self.native_layout()
        self.metadata[self.target.parent]['st_mode'] = stat.S_IFDIR | 0o755
        self.assertEqual(self.install('macos'), 'installed')

    def test_reported_root_admin_applications_updates_in_place(self):
        self.native_layout()
        parent_before = self.target.parent.stat()
        with patch.object(os, 'chmod', side_effect=AssertionError('permission repair forbidden')), \
                patch.object(os, 'chown', side_effect=AssertionError('ownership repair forbidden')):
            self.assertEqual(self.install('macos'), 'installed')
        self.assertEqual(plistlib.loads((self.target / 'Contents/Info.plist').read_bytes())[
            'CFBundleShortVersionString'], self.number)
        parent_after = self.target.parent.stat()
        self.assertEqual((parent_after.st_uid, parent_after.st_gid, parent_after.st_mode),
                         (parent_before.st_uid, parent_before.st_gid, parent_before.st_mode))
        self.assertFalse((self.home / 'Applications/bb.app').exists())
        self.assertFalse((self.target.parent / '.setup-bb-desktop.lock').exists())

    def installed_bytes(self):
        return (self.target / 'Contents/Info.plist').read_bytes()

    def test_current_newer_and_real_running_deferral_preserve_system_copy(self):
        self.native_layout(self.number)
        original = self.installed_bytes()
        self.assertEqual(self.install('macos'), 'current')
        self.data = mac_zip('1.0.0')
        self.latest = release('1.0.0', self.data, 'macos')
        self.assertEqual(self.install('macos'), 'newer-preserved')
        self.data = mac_zip('2.0.0')
        self.latest = release('2.0.0', self.data, 'macos')
        self.ns['command'] = lambda args: (f'501 123 {self.target}/Contents/MacOS/bb\n'
                                           if args[0] == '/bin/ps' else self.command(args))
        self.ns['running'] = self.real_running
        self.assertEqual(self.install('macos'), 'deferred-running')
        self.assertEqual(self.installed_bytes(), original)
        self.assertFalse((self.home / 'Applications/bb.app').exists())
        self.assertFalse((self.target.parent / '.setup-bb-desktop.lock').exists())

    def test_running_at_promotion_defers_without_renaming(self):
        self.native_layout(uid=4294967294)
        original = self.installed_snapshot()
        inventories = iter(['4294967294 53750 /usr/bin/unrelated\n',
                            f'-2 53750 {self.target}/Contents/MacOS/bb\n'])
        def command(args):
            if args[0] == '/bin/ps':
                self.process_rows = next(inventories)
            return self.command(args)
        self.ns['command'] = command
        with patch.object(os, 'rename', side_effect=AssertionError('running app renamed')):
            self.assertEqual(self.install('macos'), 'deferred-running')
        self.assertEqual(self.installed_snapshot(), original)
        self.assertIsNone(next(inventories, None))

    def test_foreign_signed_uid_at_promotion_still_refuses(self):
        self.native_layout()
        original = self.installed_snapshot()
        inventories = iter(['-2 53750 /usr/bin/unrelated\n',
                            f'-2 53750 {self.target}/Contents/MacOS/bb\n'])
        def command(args):
            if args[0] == '/bin/ps':
                self.process_rows = next(inventories)
            return self.command(args)
        self.ns['command'] = command
        with patch.object(os, 'rename', side_effect=AssertionError('foreign app renamed')):
            with self.assertRaisesRegex(self.ns['Refusal'], '^process-owner$'):
                self.install('macos')
        self.assertEqual(self.installed_snapshot(), original)
        self.assertIsNone(next(inventories, None))

    def test_nonstandard_applications_metadata_rejected_before_fetch(self):
        self.native_layout()
        original = self.installed_bytes()
        accepted = self.metadata[self.target.parent].copy()
        for change in ({'st_uid': 501}, {'st_uid': 999}, {'st_gid': 20},
                       {'st_gid': 0, 'st_mode': stat.S_IFDIR | 0o755},
                       {'st_mode': stat.S_IFDIR | 0o777}, {'st_mode': stat.S_IFDIR | 0o1775},
                       {'st_mode': stat.S_IFLNK | 0o775}, {'st_mode': stat.S_IFREG | 0o775}):
            with self.subTest(change=change):
                self.metadata[self.target.parent] = {**accepted, **change}
                with self.assertRaisesRegex(self.ns['Refusal'], 'unsafe-directory'):
                    self.install('macos')
                self.assertFalse(any(c[0] == 'fetch' for c in self.calls))
                self.assertEqual(self.installed_bytes(), original)
                self.assertFalse((self.target.parent / '.setup-bb-desktop.lock').exists())

    def test_exception_requires_native_macos_and_explicit_mac_caller(self):
        self.native_layout()
        with self.assertRaisesRegex(self.ns['Refusal'], 'unsafe-directory'):
            self.ns['directory'](self.target.parent)
        with patch.object(self.ns['sys'], 'platform', 'linux'):
            with self.assertRaisesRegex(self.ns['Refusal'], 'unsafe-directory'):
                self.install('macos')
        nested = self.target / 'Contents'
        self.metadata[nested] = dict(st_uid=501, st_gid=80, st_mode=stat.S_IFDIR | 0o775)
        with self.assertRaisesRegex(self.ns['Refusal'], 'unsafe-bundle-file'):
            self.install('macos')
        del self.metadata[nested]
        self.metadata[self.home / 'Applications']['st_mode'] = stat.S_IFDIR | 0o775
        with self.assertRaisesRegex(self.ns['Refusal'], 'unsafe-directory'):
            self.ns['directory'](self.home / 'Applications', macos=True)

    def test_root_foreign_and_writable_bundles_still_refused(self):
        self.native_layout()
        original = self.installed_bytes()
        accepted = self.metadata[self.target].copy()
        for change, reason in (({'st_uid': 0}, 'foreign-bundle'),
                               ({'st_uid': 999}, 'unsafe-directory'),
                               ({'st_mode': stat.S_IFDIR | 0o775}, 'unsafe-directory')):
            with self.subTest(change=change):
                self.metadata[self.target] = {**accepted, **change}
                with self.assertRaisesRegex(self.ns['Refusal'], reason):
                    self.install('macos')
                self.assertEqual(self.installed_bytes(), original)
                self.assertFalse((self.target.parent / '.setup-bb-desktop.lock').exists())

    def test_linked_parent_and_target_are_not_followed(self):
        self.native_layout()
        parent = self.target.parent
        real_parent = parent.with_name('saved-applications')
        parent.rename(real_parent)
        parent.symlink_to(real_parent)
        del self.metadata[parent]
        with self.assertRaisesRegex(self.ns['Refusal'], 'unsafe-directory'):
            self.install('macos')
        parent.unlink()
        real_parent.rename(parent)
        self.metadata[parent] = dict(st_uid=0, st_gid=80, st_mode=stat.S_IFDIR | 0o775)
        saved = self.target.with_name('saved.app')
        self.target.rename(saved)
        self.target.symlink_to(saved)
        del self.metadata[self.target]
        with self.assertRaisesRegex(self.ns['Refusal'], 'unsafe-directory'):
            self.install('macos')
        self.assertTrue((saved / 'Contents/Info.plist').is_file())
        self.assertFalse((parent / '.setup-bb-desktop.lock').exists())

    def test_system_nightly_custom_signature_and_signer_rejections_preserve_copy(self):
        self.native_layout()
        self.process_rows = '-2 53750 /usr/bin/unrelated\n'
        original = self.installed_bytes()
        plist = self.target / 'Contents/Info.plist'
        bad = plistlib.loads(original)
        bad['CFBundleIdentifier'] = 'dev.bb.desktop.nightly'
        plist.write_bytes(plistlib.dumps(bad))
        with self.assertRaisesRegex(self.ns['Refusal'], 'wrong-bundle-identity'):
            self.install('macos')
        self.assertEqual(plistlib.loads(self.installed_bytes()), bad)
        plist.write_bytes(original)
        for failure, reason in (('signature', 'native-check-failed'), ('signer', 'different-signing-team'),
                                ('notarization', 'not-notarized')):
            def command(args):
                if failure == 'signature' and args[:2] == ['/usr/bin/codesign', '--verify']:
                    raise self.ns['Refusal']('native-check-failed')
                if failure == 'notarization' and args[0] == '/usr/sbin/spctl':
                    return 'source=Developer ID\n'
                result = self.command(args)
                return result.replace('ABCDEFGHIJ', 'OTHERTEAM0') if failure == 'signer' and 'stage-' in args[-1] else result
            self.ns['command'] = command
            with self.subTest(failure=failure), self.assertRaisesRegex(self.ns['Refusal'], reason):
                self.install('macos')
            self.assertEqual(self.installed_bytes(), original)

    def test_ambiguous_copies_and_stale_linked_locks_are_preserved(self):
        self.native_layout()
        duplicate = self.home / 'Applications/bb.app'
        duplicate.mkdir()
        with self.assertRaisesRegex(self.ns['Refusal'], 'ambiguous-applications'):
            self.install('macos')
        duplicate.rmdir()
        lock = self.target.parent / '.setup-bb-desktop.lock'
        lock.mkdir()
        (lock / 'recovery').write_text('preserve')
        with self.assertRaises(FileExistsError):
            self.install('macos')
        self.assertEqual((lock / 'recovery').read_text(), 'preserve')
        saved = lock.with_name('saved-lock')
        lock.rename(saved)
        lock.symlink_to(saved)
        with self.assertRaises(FileExistsError):
            self.install('macos')
        self.assertEqual((saved / 'recovery').read_text(), 'preserve')

    def test_parent_identity_owner_group_mode_changes_fail_closed(self):
        self.native_layout()
        original = self.installed_bytes()
        parent = self.target.parent
        accepted = self.metadata[parent].copy()
        initial = parent.stat()
        for change in ({'st_ino': initial.st_ino + 1}, {'st_dev': initial.st_dev + 1},
                       {'st_uid': 501}, {'st_gid': 20}, {'st_mode': stat.S_IFDIR | 0o755}):
            def fetch(url, target=None, maximum=None):
                result = self.fetch(url, target, maximum)
                if target:
                    self.metadata[parent].update(change)
                return result
            self.ns['fetch'] = fetch
            with self.subTest(change=change), self.assertRaisesRegex(self.ns['Refusal'], 'transaction-changed'):
                self.install('macos')
            self.assertEqual(self.installed_bytes(), original)
            lock = parent / '.setup-bb-desktop.lock'
            self.assertTrue(lock.exists())  # uncertainty is not authority to clean up
            self.metadata[parent] = accepted.copy()
            shutil.rmtree(lock)  # only this fixture's synthetic recovery tree

    def test_changed_target_cannot_be_current_or_deferred(self):
        self.native_layout(self.number)
        original = self.installed_bytes()
        def running(*_):
            self.metadata[self.target]['st_gid'] = 20
            return True
        self.ns['running'] = running
        with self.assertRaisesRegex(self.ns['Refusal'], 'installation-changed'):
            self.install('macos')
        self.assertEqual(self.installed_bytes(), original)

    def test_changed_lock_and_stage_are_retained_not_cleaned(self):
        self.native_layout()
        original = self.installed_bytes()
        for part in ('lock', 'stage'):
            def fetch(url, target=None, maximum=None):
                result = self.fetch(url, target, maximum)
                if target:
                    path = target.parent if part == 'stage' else target.parent.parent
                    self.metadata[path] = dict(st_mode=stat.S_IFDIR | 0o750)
                return result
            self.ns['fetch'] = fetch
            with self.subTest(part=part), self.assertRaisesRegex(self.ns['Refusal'], 'transaction-changed'):
                self.install('macos')
            self.assertEqual(self.installed_bytes(), original)
            lock = self.target.parent / '.setup-bb-desktop.lock'
            self.assertTrue(lock.exists())
            self.metadata = {p: s for p, s in self.metadata.items() if not p.is_relative_to(lock)}
            shutil.rmtree(lock)

    def test_failed_verification_rolls_back_in_system_parent(self):
        self.native_layout()
        original = self.installed_bytes()
        def command(args):
            if args[:2] == ['/usr/bin/codesign', '--verify'] and args[-1] == str(self.target) and self.installed_bytes() != original:
                raise self.ns['Refusal']('native-check-failed')
            return self.command(args)
        self.ns['command'] = command
        with self.assertRaisesRegex(self.ns['Refusal'], 'native-check-failed'):
            self.install('macos')
        self.assertEqual(self.installed_bytes(), original)
        self.assertFalse((self.target.parent / '.setup-bb-desktop.lock').exists())

    def test_parent_change_before_rollback_retains_backup(self):
        self.native_layout()
        original = self.installed_bytes()
        def command(args):
            if args[:2] == ['/usr/bin/codesign', '--verify'] and args[-1] == str(self.target) and self.installed_bytes() != original:
                self.metadata[self.target.parent]['st_gid'] = 20
                raise self.ns['Refusal']('native-check-failed')
            return self.command(args)
        self.ns['command'] = command
        with self.assertRaisesRegex(self.ns['Refusal'], 'transaction-changed'):
            self.install('macos')
        backups = list(self.target.parent.glob('.setup-bb-desktop.lock/stage-*/previous-0'))
        self.assertEqual(len(backups), 1)
        self.assertEqual((backups[0] / 'Contents/Info.plist').read_bytes(), original)
        self.assertFalse((self.home / 'Applications/bb.app').exists())

    def test_unverified_new_stage_is_retained_without_traversal_or_cleanup(self):
        self.native_layout()
        original = self.installed_bytes()
        mkdtemp = tempfile.mkdtemp
        made = []
        def unsafe_stage(*args, **kwargs):
            path = Path(mkdtemp(*args, **kwargs))
            (path / 'unverified').write_text('preserve')
            self.metadata[path] = dict(st_uid=999)
            made.append(path)
            return str(path)
        with patch.object(tempfile, 'mkdtemp', unsafe_stage):
            with self.assertRaisesRegex(self.ns['Refusal'], 'unsafe-directory'):
                self.install('macos')
        self.assertEqual(len(made), 1)
        self.assertEqual((made[0] / 'unverified').read_text(), 'preserve')
        self.assertEqual(self.installed_bytes(), original)
        self.assertFalse(any(c[0] == 'fetch' for c in self.calls))

    def test_link_substituted_for_stage_is_not_followed_or_cleaned(self):
        self.native_layout()
        outside = self.base / 'outside-stage'
        outside.mkdir()
        marker = outside / 'preserve'
        marker.write_text('unrelated')
        def fetch(url, target=None, maximum=None):
            result = self.fetch(url, target, maximum)
            if target:
                stage = target.parent
                stage.rename(stage.with_name('saved-stage'))
                stage.symlink_to(outside)
            return result
        self.ns['fetch'] = fetch
        with self.assertRaisesRegex(self.ns['Refusal'], 'transaction-changed'):
            self.install('macos')
        self.assertEqual(marker.read_text(), 'unrelated')
        self.assertTrue((self.target.parent / '.setup-bb-desktop.lock').exists())

    def test_parent_replaced_after_backup_preserves_recovery_without_promotion(self):
        self.native_layout()
        original = self.installed_bytes()
        rename = os.rename
        calls = []
        def replaced(source, dest):
            calls.append((source, dest))
            rename(source, dest)
            if source == self.target:
                self.metadata[self.target.parent]['st_ino'] = self.target.parent.stat().st_ino + 1
        with patch.object(os, 'rename', replaced):
            with self.assertRaisesRegex(self.ns['Refusal'], 'transaction-changed'):
                self.install('macos')
        self.assertEqual(len(calls), 1)
        self.assertFalse(self.target.exists())
        self.assertEqual((calls[0][1] / 'Contents/Info.plist').read_bytes(), original)
        self.assertFalse((self.home / 'Applications/bb.app').exists())

    def test_insufficient_parent_access_does_not_elevate_or_fall_back(self):
        self.native_layout()
        original = self.installed_bytes()
        mkdir = Path.mkdir
        def denied(path, *args, **kwargs):
            if path == self.target.parent / '.setup-bb-desktop.lock':
                raise PermissionError('inert native denial')
            return mkdir(path, *args, **kwargs)
        with patch.object(Path, 'mkdir', denied):
            with self.assertRaises(PermissionError):
                self.install('macos')
        self.assertEqual(self.installed_bytes(), original)
        self.assertFalse(any(c[0] == 'fetch' for c in self.calls))
        self.assertFalse((self.home / 'Applications/bb.app').exists())

    def test_system_app_absent_uses_user_directory_without_duplicate(self):
        self.native_layout()
        shutil.rmtree(self.target)
        self.assertEqual(self.install('macos'), 'installed')
        self.assertTrue((self.home / 'Applications/bb.app/Contents/Info.plist').is_file())
        self.assertFalse(self.target.exists())
        self.assertFalse((self.target.parent / '.setup-bb-desktop.lock').exists())


class WiringTests(unittest.TestCase):
    def test_shared_copies_and_callers(self):
        self.assertEqual(payload('mac'), payload('ubuntu'))
        self.assertEqual(payload('mac'), payload('bazzite'))
        for name in SCRIPTS:
            self.assertEqual(wrapper(name), wrapper('mac'))
            source = (ROOT / (name + '.sh')).read_text()
            entry = 'macos' if name == 'mac' else name
            self.assertIn('install_bb_desktop ' + entry + ' || _setup_had_errors=1', source)
            self.assertIn('return "${_setup_had_errors}"', source)
            self.assertIn('finish_setup_log "${setup_status}"', source)
        windows = (ROOT / 'win.ps1').read_text()
        self.assertIn('if (-not (Install-BbDesktop)) { $bbDesktopSetupFailed = $true }', windows)
        self.assertIn('if ($bbDesktopSetupFailed)', windows)
        self.assertLess(windows.index('    Assert-HeadlessUnsupported'), windows.index('    if (-not (Install-BbDesktop))'))

    def run_wrapper(self, entry, headless='', system='Linux', arch='x86_64', kernel='native', result='installed', status=0, arm_capable='0'):
        script = wrapper('mac') + '''
print_debug() { printf 'debug:%s\\n' "$*"; }
print_success() { printf 'success:%s\\n' "$*"; }
print_warning() { printf 'warning:%s\\n' "$*"; }
print_error() { printf 'error:%s\\n' "$*"; }
uname() { case "$1" in -s) printf '%s\\n' "$SYSTEM";; -m) printf '%s\\n' "$ARCH";; -r) printf '%s\\n' "$KERNEL";; esac; }
sysctl() { printf '%s\\n' "$ARM_CAPABLE"; }
bb_desktop_payload() { printf '%s\\n' "$RESULT"; return "$STATUS"; }
_setup_had_errors=0
install_bb_desktop "$ENTRY" || _setup_had_errors=1
printf 'unrelated-work-and-log-finalization\\n'
exit "$_setup_had_errors"
'''
        env = {'PATH': '/usr/bin:/bin', 'HOME': '/nonexistent-bb-fixture', 'HEADLESS': headless,
               'ENTRY': entry, 'SYSTEM': system, 'ARCH': arch, 'KERNEL': kernel, 'RESULT': result, 'STATUS': str(status),
               'ARM_CAPABLE': arm_capable}
        results = []
        for work in ('', '0', '1'):
            env['WORK_MACHINE'] = work
            results.append(subprocess.run(['bash', '-c', script], env=env, capture_output=True, text=True))
        self.assertEqual(len({(r.returncode, r.stdout) for r in results}), 1)
        return results[0]

    def test_all_headless_and_supported_architecture_work_gates(self):
        for entry in ('macos', 'ubuntu', 'bazzite', 'wsl', 'pi'):
            for headless in ('', '0', 'true', '1'):
                system, arch = ('Darwin', 'arm64') if entry == 'macos' else ('Linux', 'x86_64')
                result = self.run_wrapper(entry, headless, system, arch)
                self.assertEqual(result.returncode, 0)
                should_install = headless != '1' and entry in ('macos', 'ubuntu', 'bazzite')
                self.assertEqual('success:' in result.stdout, should_install)
        for entry, system, arch, kernel in (
            ('macos', 'Darwin', 'x86_64', 'native'), ('ubuntu', 'Linux', 'aarch64', 'native'),
            ('bazzite', 'Linux', 'armv7l', 'native'), ('ubuntu', 'Linux', 'x86_64', '5.15-microsoft-WSL2'),
            ('ubuntu', 'Darwin', 'arm64', 'native')):
            result = self.run_wrapper(entry, system=system, arch=arch, kernel=kernel)
            self.assertEqual(result.returncode, 0)
            self.assertNotIn('success:', result.stdout)

    def test_apple_silicon_under_rosetta(self):
        result = self.run_wrapper('macos', system='Darwin', arch='x86_64', arm_capable='1')
        self.assertEqual(result.returncode, 0)
        self.assertIn('success:', result.stdout)

    def test_real_bash_callers_aggregate_and_finalize(self):
        # Execute only extracted callers with every setup/lifecycle function inert.
        # No sourcing complete scripts, and no live HOME/network/package operations.
        for name in SCRIPTS:
            source = (ROOT / (name + '.sh')).read_text()
            start = source.index('\nrun_setup_tasks() {')
            caller = source[start:source.index('\nmain() {', start)]
            names = set(re.findall(r'^([a-zA-Z_][a-zA-Z_0-9]*)\(\)\s*\{', source, re.M))
            stubs = '\n'.join(n + '() { :; }' for n in names if n not in ('run_setup_tasks', 'main'))
            with tempfile.TemporaryDirectory(prefix='bb-desktop-caller-') as tmp:
                script = stubs + '\n' + caller + '''
check_dotfiles_access() { return 1; }
setup_dotfiles_deploy_key() { return 1; }
is_main_user() { return 0; }
install_bb_desktop() { printf 'desktop-called\\n'; return 1; }
check_pending_reboot() { printf 'unrelated-work-finished\\n'; }
finish_setup_log() { printf 'log-result=%s\\n' "$1"; }
'''
                main = source[source.index('\nmain() {', start):].split('\n}\n', 1)[0] + '\n}\nmain\n'
                result = subprocess.run(['bash', '-c', script + main], env={
                    'PATH': '/usr/bin:/bin', 'HOME': tmp, 'SHELL': '/bin/bash',
                    'BB_SERVER': '0', 'HEADLESS': '0'}, text=True, capture_output=True)
                with self.subTest(script=name):
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertIn('desktop-called', result.stdout)
                    self.assertIn('unrelated-work-finished', result.stdout)
                    self.assertIn('log-result=1', result.stdout)

    def test_linux_compatibility_warning_only_follows_verified_success(self):
        warning = 'warning:bb desktop installation is verified; GUI/sandbox launch compatibility remains unverified. No launch or security-policy changes were performed.'
        for entry in ('ubuntu', 'bazzite'):
            for outcome in ('installed', 'current', 'newer-preserved'):
                result = self.run_wrapper(entry, result=outcome)
                self.assertEqual(result.returncode, 0)
                self.assertEqual(result.stdout.count(warning), 1)
        for outcome in ('installed', 'current', 'newer-preserved'):
            result = self.run_wrapper('macos', system='Darwin', arch='arm64', result=outcome)
            self.assertEqual(result.returncode, 0)
            self.assertNotIn('warning:', result.stdout)
        for entry, headless in (('ubuntu', '1'), ('bazzite', '1'), ('wsl', ''), ('pi', '')):
            result = self.run_wrapper(entry, headless=headless)
            self.assertEqual(result.returncode, 0)
            self.assertNotIn(warning, result.stdout)
        result = self.run_wrapper('ubuntu', result='deferred-running')
        self.assertEqual(result.returncode, 0)
        self.assertIn('update deferred:', result.stdout)
        self.assertNotIn(warning, result.stdout)

    def test_installer_and_wrapper_have_no_sandbox_policy_probe(self):
        for name in ('mac', 'ubuntu', 'bazzite'):
            source = payload(name) + wrapper(name)
            for forbidden in ('/proc/sys/kernel/', '/proc/sys/user/', '/sys/kernel/security/', '/etc/apparmor', 'unshare', '--no-sandbox'):
                self.assertNotIn(forbidden, source)

    def test_outcomes_and_failures_aggregate_without_early_return(self):
        for outcome in ('installed', 'current', 'newer-preserved', 'deferred-running'):
            result = self.run_wrapper('ubuntu', result=outcome)
            self.assertEqual(result.returncode, 0)
            self.assertIn('warning:', result.stdout)
        for outcome, status in (('failed:integrity-mismatch', 1), ('installed', 1),
                                ('garbage SECRET', 0), ('failed:bad/path SECRET', 1),
                                ('failed:integrity-mismatch', 0),
                                ('installed\nSECRET extra warning', 0), ('current\nnewer-preserved', 0)):
            result = self.run_wrapper('ubuntu', result=outcome, status=status)
            self.assertEqual(result.returncode, 1)
            self.assertIn('unrelated-work-and-log-finalization', result.stdout)
            self.assertNotIn('SECRET', result.stdout)
            self.assertNotIn('GUI/sandbox launch compatibility', result.stdout)


if __name__ == '__main__':
    unittest.main()
