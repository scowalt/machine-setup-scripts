import hashlib
import os
from pathlib import Path
import re
import stat
import subprocess
import tempfile
import unittest

from bb_managed_unit_fixture import managed_app_unit, managed_ingress_unit
from extract_setup_fixture import validate_function

ROOT = Path(__file__).resolve().parents[1]
UNITS = ('setup-bb-app.service', 'setup-bb-ingress.service')
REAL = ('bb_server_failure', 'bb_setup_directory_preflight', 'bb_owned_metadata_file', 'bb_owned_file',
        'bb_owned_script', 'bb_owned_safe_directory', 'bb_unit_preflight', 'setup_bb_server',
        'bb_server_selection', 'bb_server_restore_process_override',
        'run_setup_tasks', 'main')
HARNESS = r'''
set -uo pipefail
# Keep fixture events on the private captured stderr even when the real helper
# suppresses systemctl stderr. No inherited nonstandard descriptor is used.
exec 3>&2
source "$1"
print_error() { printf 'ERROR: %s\n' "$1"; }
print_message() { printf 'INFO: %s\n' "$1"; }
print_warning() { printf 'WARNING: %s\n' "$1"; }
for name in loginctl tailscale npm sudo curl wget mkdir chmod node python3 /usr/bin/python3 mv rm cp mktemp sleep kill find cat; do
    eval "$name() { printf 'FORBIDDEN_COMMAND: $name\n' >&2; exit 97; }"
done
command_not_found_handle() { printf 'FORBIDDEN_UNDEFINED_COMMAND\n' >&2; exit 97; }
command() {
    if [[ "$#" == 2 && "$1" == -v && "$2" == tailscale ]]; then
        printf '/usr/bin/tailscale\n'; return 0
    fi
    printf 'FORBIDDEN_COMMAND_DISCOVERY\n' >&2; exit 97
}
id() {
    [[ "$#" == 1 && "$1" == -u ]] || { printf 'FORBIDDEN_ID\n' >&2; exit 97; }
    printf '%s\n' "$FIXTURE_UID"
}
stat() {
    [[ "$#" == 4 && "$1" == -c && "$3" == -- ]] || { printf 'FORBIDDEN_STAT\n' >&2; exit 97; }
    case "$2" in '%u %a'|'%u %h %a') ;; *) printf 'FORBIDDEN_STAT\n' >&2; exit 97 ;; esac
    case "$4" in "$HOME/.config/systemd/user/"*.d|"$HOME/.config/systemd/user/"*.d/*) printf 'FORBIDDEN_DROPIN_INSPECTION\n' >&2; exit 97 ;; esac
    case "$4" in "$HOME"|"$HOME/"*) ;; *) exit 97 ;; esac
    /usr/bin/stat "$@"
}
systemctl() {
    if [[ "$FIXTURE_MODE" == checkpoint ]]; then
        case "$*" in
            '--user is-active --quiet setup-bb-app.service'|'--user is-active --quiet setup-bb-ingress.service') return 1 ;;
            '--user is-enabled setup-bb-app.service') printf 'enabled\n'; return 0 ;;
        esac
    fi
    if [[ "$*" == '--user is-active --quiet setup-bb-app.service' ]]; then
        # Positive control reaches this boundary; NEVER inspect real services.
        printf 'NEXT_INERT_GATE\n' >&3; exit 73
    fi
    [[ "$#" -ge 4 && "$1" == --user && "$2" == show && "$4" == --property=FragmentPath ]] || {
        printf 'FORBIDDEN_SYSTEMCTL\n' >&2; exit 97;
    }
    case "$3" in setup-bb-app.service|setup-bb-ingress.service) ;; *) exit 97 ;; esac
    printf 'SYSTEMD_SHOW: %s\n' "$3" >&3
    local fragment="$HOME/.config/systemd/user/$3" dropins="${FIXTURE_DROPINS:-}"
    if [[ "$3" == "$FIXTURE_UNIT" ]]; then
        case "$FIXTURE_SYSTEMD" in
            clean) ;;
            absent) fragment='' ;;
            foreign) fragment='/fixture-secret/foreign.service' ;;
            duplicate) printf 'FragmentPath=/fixture-secret/foreign.service\n' ;;
            missing) return 0 ;;
            malformed) printf 'fixture-secret-invalid-property\n'; return 0 ;;
            failed) printf 'fixture-secret-systemd-error\n' >&2; return 1 ;;
            *) exit 97 ;;
        esac
    fi
    printf 'FragmentPath=%s\n' "$fragment"
    # Answer every requested property so an inspection of loaded drop-ins sees them.
    if [[ "${5:-}" == --property=DropInPaths ]]; then printf 'DropInPaths=%s\n' "$dropins"; fi
}
# Continue to the final pre-mutation checkpoint only with inert dependencies.
if [[ "$FIXTURE_MODE" == checkpoint ]]; then
    id() {
        case "$*" in -u) printf '%s\n' "$FIXTURE_UID" ;; -un) printf 'fixture\n' ;; *) exit 97 ;; esac
    }
    command() {
        case "$*" in
            '-v tailscale'|'-v systemctl'|'-v loginctl') printf '/usr/bin/%s\n' "$2" ;;
            *) printf 'FORBIDDEN_COMMAND_DISCOVERY\n' >&2; exit 97 ;;
        esac
    }
    bb_tailnet_identity() { printf 'fixture.example.ts.net\n'; }
    loginctl() { [[ "$*" == 'show-user fixture --property=Linger --value' ]] || exit 97; printf 'yes\n'; }
    node() { [[ "$#" == 3 && "$1" == -e && "$3" == "$HOME" ]] || exit 97; }
    mkdir() {
        [[ "$*" == "-p -- $HOME/.config/setup-bb-server $HOME/.config/systemd/user $HOME/.bb" ]] || exit 97
        printf 'NEXT_INERT_GATE\n' >&3; exit 73
    }
fi
# The real ordinary caller runs only after all non-BB helpers are inert.
check_dotfiles_access() { return 1; }
setup_dotfiles_deploy_key() { return 1; }
refresh_bb_plugins() { printf 'PLUGIN_REFRESH: %s\n' "$1"; }
setup_matt_pocock_skills() { printf 'UNAFFECTED_SKILLS\n'; }
refresh_pi_packages() { printf 'UNAFFECTED_PI_REFRESH\n'; }
check_pending_reboot() { printf 'REBOOT_CHECK\n'; }
start_setup_log() { printf 'LOG_STARTED\n'; }
finish_setup_log() { printf 'FINAL_STATUS=%s\n' "$1"; return "$1"; }
BOLD='' NC='' GRAY='' GREEN='' BB_SERVER=1
case "$FIXTURE_MODE" in
    setup) setup_bb_server ;;
    unit) bb_unit_preflight "$FIXTURE_UNIT" "$HOME/.config/systemd/user/$FIXTURE_UNIT" ;;
    caller|checkpoint) main ;;
    *) exit 97 ;;
esac
'''


def function(source, name):
    start = source.index('\n' + name + '() {\n') + 1
    end = source.index('\n}\n', start) + 3
    block = source[start:end]
    validate_function(block)
    return block


def snapshot(root):
    paths = [root]
    for directory, dirs, files in os.walk(root, followlinks=False):
        paths.extend(Path(directory) / name for name in dirs + files)
    result = {}
    for path in paths:
        info = path.lstat()
        value = None
        if stat.S_ISLNK(info.st_mode):
            value = os.readlink(path)
        elif stat.S_ISREG(info.st_mode):
            try:
                value = hashlib.sha256(path.read_bytes()).hexdigest()
            except PermissionError:
                value = 'unreadable'
        result[str(path.relative_to(root))] = (info.st_dev, info.st_ino, info.st_size,
                                             info.st_mode, info.st_uid, info.st_gid,
                                             info.st_nlink, info.st_mtime_ns,
                                             info.st_ctime_ns, value)
    return result


class BbServicePreflightTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        sandbox = os.environ.get('FIXTURE_NETWORK_SANDBOX')
        if not sandbox:
            raise SystemExit(125)
        result = subprocess.run([sandbox, '--assert-inherited-denial'],
                                stdin=subprocess.DEVNULL, capture_output=True,
                                close_fds=True, timeout=10)
        if result.returncode:
            raise SystemExit(125)
        source = (ROOT / 'ubuntu.sh').read_text()
        names = re.findall(r'^([A-Za-z_][A-Za-z_0-9]*)\(\) [({]', source, re.M)
        stubs = '\n'.join(name + '() { :; }' for name in names if name not in REAL)
        cls.definitions = stubs + '\n' + '\n'.join(function(source, name) for name in REAL)

    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='bb-service-preflight-')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.home = self.root / 'home'
        for relative in ('', '.config', '.config/systemd', '.config/systemd/user',
                         '.config/setup-bb-server', '.bb'):
            directory = self.home / relative
            directory.mkdir(parents=True, exist_ok=True)
            directory.chmod(0o700)
        self.units = self.home / '.config/systemd/user'
        for unit, content in zip(UNITS, (managed_app_unit(self.home), managed_ingress_unit(self.home))):
            (self.units / unit).write_text(content)
            (self.units / unit).chmod(0o600)
        for relative in ('.env.local', '.bb/auth.json'):
            (self.home / relative).write_text('fixture-secret: preserve without reading\n')
            (self.home / relative).chmod(0o600)
        self.helpers = self.root / 'definitions.sh'
        self.helpers.write_text(self.definitions)
        self.helpers.chmod(0o600)
        self.empty_path = self.root / 'empty-bin'
        self.empty_path.mkdir()

    def dropin(self, relative, content, directory_mode=0o700, file_mode=0o600):
        path = self.home / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.parent.chmod(directory_mode)
        path.write_text(content)
        path.chmod(file_mode)
        return path

    def run_preflight(self, unit=UNITS[0], mode='setup', systemd='clean', status=73, dropins=''):
        before = snapshot(self.root)
        result = subprocess.run(
            ['/bin/bash', '--noprofile', '--norc', '-c', HARNESS, '_', str(self.helpers)],
            env={'PATH': str(self.empty_path), 'HOME': str(self.home), 'LANG': 'C', 'HEADLESS': '1',
                 'FIXTURE_UID': str(os.getuid()), 'FIXTURE_UNIT': unit,
                 'FIXTURE_MODE': mode, 'FIXTURE_SYSTEMD': systemd, 'FIXTURE_DROPINS': dropins},
            cwd=self.home, stdin=subprocess.DEVNULL, capture_output=True,
            text=True, close_fds=True, timeout=5,
        )
        self.assertEqual(result.returncode, status, result.stdout + result.stderr)
        self.assertNotIn('FORBIDDEN_', result.stdout + result.stderr)
        self.assertNotIn('fixture-secret', result.stdout + result.stderr)
        self.assertNotIn(str(self.home), result.stdout)
        self.assertEqual(snapshot(self.root), before, 'Preflight/caller changed fixture state')
        return result

    def assert_reaches_next_gate(self, result):
        self.assertIn('NEXT_INERT_GATE', result.stderr)
        for unit in UNITS:
            self.assertIn('SYSTEMD_SHOW: ' + unit, result.stderr)
        self.assertNotIn('BB server setup incomplete', result.stdout)
        self.assertNotIn('ERROR:', result.stdout)

    def test_captured_devinabox_dropins_reach_final_checkpoint_unchanged(self):
        tasks = self.dropin('.config/systemd/user.control/setup-bb-app.service.d/50-TasksMax.conf',
                            '# This is a drop-in unit file extension, created via "systemctl set-property"\n'
                            '# or an equivalent operation. Do not edit.\n[Service]\nTasksMax=2500\n',
                            directory_mode=0o755, file_mode=0o644)
        env = self.dropin('.config/systemd/user/setup-bb-app.service.d/env.conf',
                          '[Service]\nEnvironmentFile=%h/.env.local\n',
                          directory_mode=0o775, file_mode=0o664)
        for attempt in range(2):
            for mode in ('setup', 'caller'):
                with self.subTest(mode=mode, attempt=attempt):
                    self.assert_reaches_next_gate(self.run_preflight(mode=mode, dropins=f'{tasks} {env}'))
            with self.subTest(mode='checkpoint', attempt=attempt):
                result = self.run_preflight(mode='checkpoint', status=1, dropins=f'{tasks} {env}')
                self.assertIn('NEXT_INERT_GATE', result.stderr)
                self.assertIn('[update.directories]', result.stdout + result.stderr)
                self.assertNotIn('[preflight.', result.stdout + result.stderr)

    def test_local_dropins_of_any_shape_are_left_to_systemd(self):
        target = self.root / 'linked-target'
        target.mkdir()
        (target / 'keep.conf').write_text('[Service]\nEnvironment=SECRET=fixture-secret\n')
        for unit in UNITS:
            directory = self.units / (unit + '.d')
            shapes = {
                'override': lambda: self.dropin(f'.config/systemd/user/{unit}.d/override.conf',
                                                '[Service]\nEnvironment=SECRET=fixture-secret\n'),
                'several': lambda: [self.dropin(f'.config/systemd/user/{unit}.d/{name}', '[Service]\n')
                                    for name in ('10-a.conf', '20-b.conf', '.hidden')],
                'nested': lambda: (directory / 'nested').mkdir(parents=True),
                'group-world-writable': lambda: self.dropin(f'.config/systemd/user/{unit}.d/x.conf',
                                                            '[Service]\n', 0o777, 0o666),
                'file': lambda: directory.write_text('fixture-secret: not a directory\n'),
                'link': lambda: directory.symlink_to(target, target_is_directory=True),
                'dangling': lambda: directory.symlink_to(self.root / 'missing-target'),
            }
            for shape, create in shapes.items():
                with self.subTest(unit=unit, shape=shape):
                    create()
                    try:
                        self.assert_reaches_next_gate(self.run_preflight(unit))
                    finally:
                        if directory.is_symlink() or directory.is_file():
                            directory.unlink()
                        else:
                            for child in directory.iterdir():
                                child.rmdir() if child.is_dir() else child.unlink()
                            directory.rmdir()

    def test_loaded_dropins_from_any_systemd_source_reach_next_gate(self):
        for unit in UNITS:
            for dropins in ('/etc/systemd/user/' + unit + '.d/override.conf',
                            '/run/user/1000/systemd/user.control/' + unit + '.d/50-MemoryMax.conf',
                            str(self.home / '.config/systemd/user.control' / (unit + '.d') / '50-TasksMax.conf')):
                with self.subTest(unit=unit, dropins=dropins):
                    self.assert_reaches_next_gate(self.run_preflight(unit, dropins=dropins))

    def test_unit_fragment_identity_checks_remain_fail_closed(self):
        for unit in UNITS:
            for metadata in ('clean', 'absent', 'foreign', 'duplicate', 'missing', 'malformed', 'failed'):
                with self.subTest(unit=unit, metadata=metadata):
                    status = 0 if metadata in ('clean', 'absent') else 1
                    result = self.run_preflight(unit, mode='unit', systemd=metadata, status=status,
                                                dropins='/etc/systemd/user/' + unit + '.d/override.conf')
                    self.assertEqual(result.stdout, '')

    def test_real_caller_reports_unit_failure_continues_and_finishes_log(self):
        for unit, check in zip(UNITS, ('[preflight.app-unit]', '[preflight.ingress-unit]')):
            with self.subTest(unit=unit):
                result = self.run_preflight(unit, mode='caller', systemd='foreign', status=1)
                self.assertIn(check, result.stdout + result.stderr)
                self.assertNotIn('NEXT_INERT_GATE', result.stderr)
                for expected in ('BB server setup incomplete; review the BB server diagnostics above.',
                                 'PLUGIN_REFRESH: block-default', 'UNAFFECTED_SKILLS',
                                 'UNAFFECTED_PI_REFRESH', 'REBOOT_CHECK',
                                 'Setup completed with errors', 'FINAL_STATUS=1'):
                    self.assertIn(expected, result.stdout)
                self.assertNotIn('Setup complete!', result.stdout)
                self.assertTrue(result.stdout.endswith('FINAL_STATUS=1\n'))


if __name__ == '__main__':
    unittest.main(verbosity=2)
