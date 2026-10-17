import functools
import hashlib
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

import extract_setup_fixture

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ('mac', 'ubuntu', 'bazzite', 'pi', 'wsl')


@functools.lru_cache(None)
def caller_fixture(entry):
    source = extract_setup_fixture.definitions((ROOT / (entry + '.sh')).read_text())
    names = set(re.findall(r'^([a-zA-Z_][a-zA-Z_0-9]*)\(\)\s*[({]', source, re.M))
    retained = ['run_setup_tasks', 'main', 'setup_bb_machine', 'setup_load_environment',
                'setup_environment_failure', 'setup_trim', 'setup_environment_value']
    if entry == 'ubuntu':
        retained += ['setup_bb_server', 'bb_server_selection', 'bb_server_restore_process_override']
    blocks = []
    for name in retained:
        start = source.index('\n' + name + '() {\n') + 1
        block = source[start:source.index('\n}\n', start) + 3]
        extract_setup_fixture.validate_function(block)
        blocks.append(block)
    stubs = '\n'.join(name + '() { :; }' for name in names if name not in retained)
    return stubs + '\n' + '\n'.join(blocks)


def snapshot(home):
    records = []
    for directory, dirs, files in os.walk(home, followlinks=False):
        for name in dirs + files:
            path = Path(directory) / name
            info = path.lstat()
            value = os.readlink(path) if path.is_symlink() else hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else None
            records.append((str(path.relative_to(home)), info.st_mode, info.st_uid, info.st_gid,
                            info.st_dev, info.st_ino, value))
    return sorted(records)


class HeadedBbPreservation(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='bb-headed-preservation-')
        self.addCleanup(temporary.cleanup)
        self.home = Path(temporary.name) / 'home'
        self.home.mkdir(mode=0o700)

    def seed_custom_installation(self):
        for relative in ('Applications/bb.app/Contents/MacOS/bb', '.local/opt/bb-desktop/bb.AppImage',
                         '.local/share/applications/dev.bb.desktop.desktop', '.local/bin/bb',
                         '.local/share/setup-bb-machine/npm/lib/node_modules/bb-app/package.json',
                         '.config/systemd/user/setup-bb-app.service', '.config/setup-bb-server/endpoint',
                         '.bb/config.json', '.bb/env.json', '.bb/auth.json', '.bb/bb.db'):
            path = self.home / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('custom-fork fixture; preserve exactly\n')
            path.chmod(0o640)
        (self.home / '.bb/custom-link').symlink_to(self.home / 'missing-custom-target')

    def run_entry(self, entry, headless, work='0', selection='0', failed=False, operation='main'):
        script = caller_fixture(entry) + r'''
check_dotfiles_access() { return 1; }
setup_dotfiles_deploy_key() { return 1; }
is_main_user() { return 0; }
whoami() { printf 'fixture-account\n'; }
brew() { :; }
print_message() { printf '%s\n' "$*"; }
print_error() { printf '%s\n' "$*"; }
install_bb_desktop() { echo FORBIDDEN-desktop; return 97; }
bb_machine_existing_role() { echo FORBIDDEN-role-inspection; return 97; }
bb_machine_platform_ready() { echo FORBIDDEN-platform-inspection; return 97; }
bb_setup_directory_preflight() { echo FORBIDDEN-server-preflight; return 97; }
ensure_shared_node_runtime() { echo FORBIDDEN-runtime; return 97; }
bb_machine_package_state() { echo FORBIDDEN-preparation; return 97; }
bb_install_package() { echo FORBIDDEN-server-install; return 97; }
install_opencode_cli() { return "$INDEPENDENT_FAILURE"; }
install_ntn_cli() { echo independent-work; }
check_pending_reboot() { echo reboot-reported; }
finish_setup_log() { printf 'final:%s\n' "$1"; return "$1"; }
'''
        env = {'PATH': '/usr/bin:/bin', 'HOME': str(self.home), 'SHELL': '/bin/bash',
               'WORK_MACHINE': work, 'BB_SERVER': selection, 'INDEPENDENT_FAILURE': str(int(failed))}
        if headless is not None:
            env['HEADLESS'] = headless
        before = snapshot(self.home)
        result = subprocess.run(['/bin/bash', '--noprofile', '--norc', '-c', script + '\n' + operation],
                                env=env, cwd=self.home, text=True, capture_output=True, timeout=20)
        self.assertEqual(result.returncode, int(failed), result.stdout + result.stderr)
        self.assertNotIn('FORBIDDEN', result.stdout + result.stderr)
        self.assertEqual(snapshot(self.home), before)
        return result.stdout

    def test_headed_callers_neither_install_nor_update_bb(self):
        for existing in (False, True):
            if existing:
                self.seed_custom_installation()
            for entry in SCRIPTS:
                for flag in (None, '', '0', 'true', 'false', '01'):
                    for work in ('0', '1'):
                        for selection in (('0', '1') if entry == 'ubuntu' else ('0',)):
                            with self.subTest(existing=existing, entry=entry, flag=flag, work=work, selection=selection):
                                out = self.run_entry(entry, flag, work, selection)
                                self.assertIn('independent-work', out)
                                self.assertIn('reboot-reported', out)
                                self.assertEqual(out.count('final:0'), 1)
        self.assertTrue((self.home / 'Applications/bb.app').exists())

    def test_headed_skip_preserves_unrelated_failure_and_finalization(self):
        self.seed_custom_installation()
        for entry in SCRIPTS:
            with self.subTest(entry=entry):
                out = self.run_entry(entry, '0', failed=True)
                self.assertIn('independent-work', out)
                self.assertIn('reboot-reported', out)
                self.assertEqual(out.count('final:1'), 1)

    def test_headed_installer_helpers_skip_before_preflight(self):
        self.seed_custom_installation()
        for entry in SCRIPTS:
            operations = [f'setup_bb_machine {entry}']
            if entry == 'ubuntu':
                operations.append('setup_bb_server')
            for operation in operations:
                for flag in (None, '', '0', 'true', 'false', '01'):
                    with self.subTest(entry=entry, operation=operation, flag=flag):
                        out = self.run_entry(entry, flag, operation=operation)
                        self.assertIn('HEADLESS=1', out)

    def test_environment_file_can_select_headed_preservation(self):
        (self.home / '.env.local').write_text('HEADLESS=0\n')
        for entry in ('mac', 'ubuntu', 'bazzite', 'pi'):
            with self.subTest(entry=entry):
                out = self.run_entry(entry, '1')
                self.assertIn('final:0', out)

    def test_desktop_install_is_absent_from_all_bash_callers(self):
        for entry in SCRIPTS:
            source = (ROOT / (entry + '.sh')).read_text()
            start = source.index('\nrun_setup_tasks() {')
            caller = source[start:source.index('\nmain() {', start)]
            self.assertNotIn('install_bb_desktop', caller)
            self.assertNotIn('bb_desktop_payload', caller)


if __name__ == '__main__':
    unittest.main()
