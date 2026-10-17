import os
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ('mac', 'ubuntu', 'bazzite', 'pi', 'wsl')


def seed(home, layout):
    if layout == 'absent':
        return
    paths = ('Applications/bb.app/Contents/Info.plist',
             'system/Applications/bb.app/Contents/Info.plist',
             '.local/opt/bb-desktop/bb.AppImage',
             '.local/share/applications/dev.bb.desktop.desktop',
             'Applications/.setup-bb-desktop.lock/recovery',
             '.bb/config.json', '.bb/auth.json', '.bb/bb.db',
             '.bb/plugins/custom/settings.json',
             '.bb-machines/owner-state',
             '.config/systemd/user/setup-bb-app.service',
             '.local/bin/bb', '.env.local')
    for name in paths:
        path = home / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(b'custom fork or malformed owner state: ' + name.encode())
        path.chmod(0o664)
    for path in home.rglob('*'):
        if path.is_dir():
            path.chmod(0o775)
    if layout == 'links':
        app = home / 'Applications/bb.app'
        app.rename(app.with_name('owner-fork.app'))
        app.symlink_to('owner-fork.app', target_is_directory=True)
        launcher = home / '.local/opt/bb-desktop/bb.AppImage'
        launcher.unlink()
        launcher.symlink_to('missing-owner-fork.AppImage')
    home.chmod(0o777)


def snapshot(home):
    result = {}
    for path in (home, *home.rglob('*')):
        info = path.lstat()
        identity = tuple(getattr(info, field) for field in (
            'st_dev', 'st_ino', 'st_uid', 'st_gid', 'st_mode', 'st_size',
            'st_mtime_ns', 'st_ctime_ns', 'st_nlink'))
        content = os.readlink(path) if path.is_symlink() else path.read_bytes() if path.is_file() else None
        result[str(path.relative_to(home))] = (identity, content)
    return result


class NonManagement(unittest.TestCase):
    def test_all_entry_points_retire_desktop_installers_without_retiring_other_bb_roles(self):
        for entry in (*SCRIPTS, 'win'):
            source = (ROOT / (entry + ('.ps1' if entry == 'win' else '.sh'))).read_text()
            with self.subTest(entry=entry):
                for token in ('BEGIN_BB_DESKTOP', 'BB_DESKTOP_PY', 'bb_desktop_payload',
                              'install_bb_desktop', 'Install-BbDesktop', 'bbDesktopSetupFailed',
                              'desktop-latest', '.setup-bb-desktop.lock', 'dev.bb.desktop.desktop'):
                    self.assertNotIn(token, source)
                if entry != 'win':
                    self.assertIn('setup_bb_machine ', source)
                    self.assertIn('refresh_bb_plugins ready', source)
                if entry == 'ubuntu':
                    self.assertIn('setup_bb_server', source)
                    self.assertIn('bb_server_selection', source)


if __name__ == '__main__':
    unittest.main(verbosity=2)
