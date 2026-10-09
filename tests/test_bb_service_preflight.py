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
        'bb_owned_script', 'bb_owned_safe_directory', 'bb_unit_dropins_empty', 'bb_tmpdir_snapshot',
        'bb_dropins_selection', 'bb_unit_dropins_snapshot', 'bb_unit_preflight', 'setup_bb_server',
        'bb_server_selection', 'bb_server_restore_process_override',
        'run_setup_tasks', 'main')
PYTHON_ADAPTER = r'''
import os
from pathlib import Path
import sys
from types import SimpleNamespace

assert sys.argv[1:4] == ['-I', '-S', '-']
home = sys.argv[4]
assert home == os.environ['HOME']
program = sys.stdin.read()
assert sys.argv[5] in ('dropins', 'fragment')
sys.argv = ['-', home, sys.argv[5]]
inspection = os.environ.get('FIXTURE_INSPECTION', '')
real_open, real_stat, real_fstat = os.open, os.stat, os.fstat
real_listdir, real_read = os.listdir, os.read
paths = {}
reads = 0
stats = {}

def checked(name, parent=None):
    path = str(Path(paths[parent]) / name) if parent is not None else str(name)
    assert path == home or path.startswith(home + '/'), 'outside fixture HOME'
    return path

def metadata(value, path):
    selected = home + '/.config/systemd/user/setup-bb-app.service.d/10-tmpdir.conf'
    if inspection == 'tmpdir-foreign-target':
        selected = home + '/.cache/bb/tmp'
    elif inspection == 'tmpdir-foreign-ancestor' or inspection.startswith('tmpdir-directory-'):
        selected = home + '/.cache'
    if inspection.startswith('env-'):
        selected = home + '/.config/systemd/user/setup-bb-app.service.d/env.conf'
        if '-source-' in inspection:
            selected = home + '/.env.local'
        elif '-parent-' in inspection:
            selected = home + '/.config/systemd/user'
        elif '-fragment-' in inspection:
            selected = home + '/.config/systemd/user/setup-bb-app.service'
    if path != selected:
        return value
    if inspection == 'tmpdir-inspection-failed':
        raise OSError('fixture-secret')
    fields = {key: getattr(value, key) for key in dir(value) if key.startswith('st_')}
    if inspection in ('tmpdir-foreign', 'tmpdir-foreign-target', 'tmpdir-foreign-ancestor'):
        fields['st_uid'] += 1
    if inspection == 'tmpdir-identity-race':
        fields['st_ino'] += stats.get(path, 0)
        stats[path] = stats.get(path, 0) + 1
    if inspection.startswith('tmpdir-directory-'):
        call = stats.get(path, 0)
        stats[path] = call + 1
        if call:
            field = inspection.removeprefix('tmpdir-directory-').removesuffix('-race')
            if field == 'mode':
                fields['st_mode'] ^= 0o020
            elif field == 'type':
                fields['st_mode'] = 0o100775
            else:
                fields['st_' + field] += 1
    if inspection.startswith('env-'):
        if inspection.endswith('-failed') and ('-late-' not in inspection or os.environ.get('FIXTURE_PHASE') == 'late'):
            raise OSError('fixture-secret')
        if inspection.endswith('-foreign'):
            fields['st_uid'] += 1
        call = stats.get(path, 0)
        stats[path] = call + 1
        if inspection.endswith('-race') and (os.environ.get('FIXTURE_PHASE') == 'late' or
                                              ('-late-' not in inspection and call)):
            field = inspection.split('-')[-2]
            if field == 'mode':
                fields['st_mode'] ^= (0o200 if '-source-' in inspection else
                                      0o044 if '-fragment-' in inspection else 0o020)
            elif field == 'type':
                fields['st_mode'] = 0o120777
            else:
                fields['st_' + field] += 1
    return SimpleNamespace(**fields)

def open_fixture(name, flags, *, dir_fd=None):
    path = checked(name, dir_fd)
    assert flags & os.O_NOFOLLOW and not flags & (os.O_CREAT | os.O_TRUNC | os.O_RDWR | os.O_WRONLY)
    if path == home + '/.env.local':
        assert flags & os.O_PATH, 'credential source opened for content access'
    fd = real_open(name, flags, dir_fd=dir_fd)
    paths[fd] = path
    return fd

def stat_fixture(name, *, dir_fd=None, follow_symlinks=True):
    assert follow_symlinks is False
    path = checked(name, dir_fd)
    return metadata(real_stat(name, dir_fd=dir_fd, follow_symlinks=False), path)

def listdir_fixture(fd):
    assert paths[fd] == home + '/.config/systemd/user/setup-bb-app.service.d', 'unexpected directory enumeration'
    if inspection == 'tmpdir-enumeration-failed':
        raise OSError('fixture-secret')
    return real_listdir(fd)

def read_fixture(fd, size):
    global reads
    assert paths[fd] in [home + '/.config/systemd/user/setup-bb-app.service'] + [
        home + '/.config/systemd/user/setup-bb-app.service.d/' + name
        for name in ('10-tmpdir.conf', 'env.conf', '20-env-local.conf')], 'unrelated content read'
    assert size <= (65537 if paths[fd].endswith('.service') else 4097), 'unbounded content read'
    result = real_read(fd, size)
    reads += 1
    if inspection == 'tmpdir-content-race' and reads > 1:
        return result + b'changed'
    if inspection in ('tmpdir-short-read', 'env-short-read') and not paths[fd].endswith('.service'):
        return b'\n'.join(result.split(b'\n')[:2]) + b'\n'
    if inspection in ('env-content-race', 'env-late-content-race', 'env-late-fragment-content-race'):
        selected = home + '/.config/systemd/user/setup-bb-app.service'
        if '-fragment-' not in inspection:
            selected += '.d/env.conf'
        if paths[fd] == selected and (os.environ.get('FIXTURE_PHASE') == 'late' or
                                     ('-late-' not in inspection and reads > 2)):
            return result.replace(b'\n', b'\r', 1)
    return result

os.open = open_fixture
os.stat = stat_fixture
os.fstat = lambda fd: metadata(real_fstat(fd), paths[fd])
os.listdir = listdir_fixture
os.read = read_fixture
try:
    exec(compile(program, 'extracted-tmpdir-policy', 'exec'))
except AssertionError:
    os.write(3, b'FORBIDDEN_PYTHON_BOUNDARY\n')
    raise SystemExit(97)
'''
HARNESS = r'''
set -uo pipefail
# Keep fixture events on the private captured stderr even when the real helper
# suppresses systemctl stderr. No inherited nonstandard descriptor is used.
exec 3>&2
source "$1"
/usr/bin/python3() {
    if [[ -n "${FIXTURE_SNAPSHOT_OUTPUT:-}" ]]; then
        printf '%s\n' "$FIXTURE_SNAPSHOT_OUTPUT"
    else
        builtin command /usr/bin/python3 -I -S "$FIXTURE_PYTHON_ADAPTER" "$@"
    fi
}
print_error() { printf 'ERROR: %s\n' "$1"; }
print_message() { printf 'INFO: %s\n' "$1"; }
print_warning() { printf 'WARNING: %s\n' "$1"; }
for name in loginctl tailscale npm sudo curl wget mkdir chmod node python3 mv rm cp mktemp sleep kill; do
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
    case "$2" in '%u %a'|'%u %h %a'|'%d:%i:%u:%g:%f:%y:%z') ;; *) exit 97 ;; esac
    case "$4" in "$HOME"|"$HOME/"*) ;; *) exit 97 ;; esac
    if [[ "$4" == "$HOME/.config/systemd/user/$FIXTURE_UNIT.d" ]]; then
        case "$FIXTURE_INSPECTION" in
            foreign)
                if [[ "$2" == '%u %a' ]]; then printf '%s 700\n' "$((FIXTURE_UID + 1))"; return 0; fi ;;
            failed) printf 'fixture-secret-stat-error\n' >&2; return 1 ;;
            malformed)
                if [[ "$2" == '%u %a' ]]; then printf 'fixture-secret-invalid-mode\n'; return 0; fi ;;
            changed)
                # Each command substitution gets a distinct PID: deterministic
                # changed snapshots without touching a real directory or account.
                if [[ "$2" == '%d:%i:%u:%g:%f:%y:%z' ]]; then printf '%s\n' "$BASHPID"; return 0; fi ;;
        esac
    fi
    /usr/bin/stat "$@"
}
find() {
    [[ "$#" == 8 && "$2 $3 $4 $5 $6 $7 $8" == '-mindepth 1 -maxdepth 1 -printf x -quit' ]] || exit 97
    case "$1" in
        "$HOME/.config/systemd/user/setup-bb-app.service.d"|"$HOME/.config/systemd/user/setup-bb-ingress.service.d") ;;
        *) printf 'FORBIDDEN_FIND\n' >&2; exit 97 ;;
    esac
    case "$FIXTURE_INSPECTION" in
        enumeration-failed) printf 'fixture-secret-enumeration-error\n' >&2; return 1 ;;
        enumeration-missing) return 127 ;;
    esac
    /usr/bin/find "$@"
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
    [[ "$#" == 5 && "$1" == --user && "$2" == show &&
       "$4" == --property=FragmentPath && "$5" == --property=DropInPaths ]] || {
        printf 'FORBIDDEN_SYSTEMCTL\n' >&2; exit 97;
    }
    case "$3" in setup-bb-app.service|setup-bb-ingress.service) ;; *) exit 97 ;; esac
    printf 'SYSTEMD_SHOW: %s\n' "$3" >&3
    local fragment="$HOME/.config/systemd/user/$3" dropins=''
    if [[ "$3" == "$FIXTURE_UNIT" ]]; then
        case "$FIXTURE_SYSTEMD" in
            loaded) dropins='/fixture-secret/external/override.conf /fixture-secret/second.conf' ;;
            foreign) fragment='/fixture-secret/foreign.service' ;;
            absent) fragment='' ;;
            duplicate-fragment)
                printf 'FragmentPath=/fixture-secret/foreign.service\n' ;;
            duplicate-dropins)
                printf 'DropInPaths=/fixture-secret/unknown.conf\n' ;;
            reviewed-duplicate)
                printf 'DropInPaths=/fixture-secret/unknown.conf\n'
                dropins="$HOME/.config/systemd/user/setup-bb-app.service.d/10-tmpdir.conf" ;;
            missing) printf 'FragmentPath=%s\n' "$fragment"; return 0 ;;
            malformed) printf 'fixture-secret-invalid-property\n'; return 0 ;;
            failed) printf 'fixture-secret-systemd-error\n' >&2; return 1 ;;
            reviewed) dropins="$FIXTURE_SELECTED" ;;
            reviewed-extra) dropins="$FIXTURE_SELECTED /fixture-secret/extra.conf" ;;
            reviewed-reversed)
                local -a names=()
                read -r -a names <<< "$FIXTURE_SELECTED"
                dropins="${names[1]} ${names[0]}" ;;
            reviewed-twice) dropins="$FIXTURE_SELECTED $FIXTURE_SELECTED" ;;
            reviewed-late-missing)
                [[ "${FIXTURE_PHASE:-}" == late ]] || dropins="$FIXTURE_SELECTED" ;;
            clean) ;;
            *) exit 97 ;;
        esac
    fi
    printf 'FragmentPath=%s\nDropInPaths=%s\n' "$fragment" "$dropins"
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
    bb_package_preflight() {
        export FIXTURE_PHASE=late
        if [[ "$FIXTURE_INSPECTION" == env-late-selection-race ]]; then
            /usr/bin/mv -- "$HOME/.config/systemd/user/setup-bb-app.service.d/env.conf" \
                "$HOME/.config/systemd/user/setup-bb-app.service.d/20-env-local.conf"
        fi
    }
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
    unit) bb_unit_preflight "$FIXTURE_UNIT" "$HOME/.config/systemd/user/$FIXTURE_UNIT" "${FIXTURE_EXPECTED:-}" ;;
    caller) main ;;
    checkpoint) main ;;
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
        self.python_adapter = self.root / 'python-adapter.py'
        self.python_adapter.write_text(PYTHON_ADAPTER)
        self.empty_path = self.root / 'empty-bin'
        self.empty_path.mkdir()

    def add_dropin(self, unit, kind):
        path = self.units / (unit + '.d')
        if kind in ('empty', 'populated'):
            path.mkdir(mode=0o700)
            if kind == 'populated':
                (path / '10-env.conf').write_text('[Service]\nEnvironment=SECRET=fixture-secret\n')
                (path / '20-env-file.conf').write_text('[Service]\nEnvironmentFile=/fixture-secret/env\n')
        elif kind == 'file':
            path.write_text('fixture-secret: not a directory\n')
        elif kind == 'link':
            target = self.root / 'fixture-secret-linked-target'
            target.mkdir()
            (target / 'keep').write_text('fixture-secret: leave target unchanged\n')
            path.symlink_to(target, target_is_directory=True)
        elif kind == 'dangling':
            path.symlink_to(self.root / 'fixture-secret-missing-target')
        else:
            raise AssertionError('unknown fixture kind')
        return path

    def run_preflight(self, unit=UNITS[0], mode='setup', systemd='clean', status=1, inspection='',
                      selection=('10-tmpdir.conf',), snapshot_output='', expected_snapshot=''):
        before = snapshot(self.root)
        result = subprocess.run(
            ['/bin/bash', '--noprofile', '--norc', '-c', HARNESS, '_', str(self.helpers)],
            env={'PATH': str(self.empty_path), 'HOME': str(self.home), 'LANG': 'C',
                 'FIXTURE_UID': str(os.getuid()), 'FIXTURE_UNIT': unit,
                 'FIXTURE_MODE': mode, 'FIXTURE_SYSTEMD': systemd, 'FIXTURE_INSPECTION': inspection,
                 'FIXTURE_PYTHON_ADAPTER': str(self.python_adapter),
                 'FIXTURE_SNAPSHOT_OUTPUT': snapshot_output, 'FIXTURE_EXPECTED': expected_snapshot,
                 'FIXTURE_SELECTED': ' '.join(str(self.units / (UNITS[0] + '.d') / name)
                                              for name in selection)},
            cwd=self.home, stdin=subprocess.DEVNULL, capture_output=True,
            text=True, close_fds=True, timeout=5,
        )
        self.assertEqual(result.returncode, status, result.stdout + result.stderr)
        self.assertNotIn('FORBIDDEN_', result.stdout + result.stderr)
        self.assertNotIn('fixture-secret', result.stdout + result.stderr)
        self.assertNotIn(str(self.home), result.stdout)
        after = snapshot(self.root)
        if inspection == 'env-late-selection-race':
            directory = str((self.units / (UNITS[0] + '.d')).relative_to(self.root))
            original = list(before.pop(directory + '/env.conf'))
            original[8] = after[directory + '/20-env-local.conf'][8]
            before[directory + '/20-env-local.conf'] = tuple(original)
            original = list(before[directory])
            original[7:9] = after[directory][7:9]
            before[directory] = tuple(original)
        self.assertEqual(after, before, 'Preflight/caller changed fixture state')
        return result

    def assert_diagnostic(self, result, unit):
        self.assertIn('BB service preflight', result.stdout)
        self.assertIn(unit, result.stdout)
        self.assertRegex(result.stdout, r'drop-in|override')
        self.assertIn('Review', result.stdout)
        self.assertIn('unchanged', result.stdout)
        self.assertNotIn('NEXT_INERT_GATE', result.stderr)
        self.assertNotIn('chmod', result.stdout)
        self.assertNotIn('rm ', result.stdout)

    def test_reviewed_tmpdir_reaches_next_boundary_through_ordinary_caller_unchanged(self):
        _, _, target = self.reviewed()
        (target / 'existing-work').write_text('preserve temporary work\n')
        for ingress_empty in (False, True):
            if ingress_empty:
                self.add_dropin(UNITS[1], 'empty')
            for attempt in range(2):
                with self.subTest(ingress_empty=ingress_empty, attempt=attempt):
                    result = self.run_preflight(mode='caller', systemd='reviewed', status=73)
                    self.assertIn('NEXT_INERT_GATE', result.stderr)
                    self.assertNotIn('BB server setup incomplete', result.stdout)

    def test_legacy_environment_reference_reaches_next_caller_boundary_unchanged(self):
        dropins = self.add_dropin(UNITS[0], 'empty')
        dropins.chmod(0o775)
        override = dropins / '20-env-local.conf'
        override.write_bytes(b'[Service]\nEnvironmentFile=%h/.env.local\n')
        override.chmod(0o664)
        for _ in range(2):
            result = self.run_preflight(mode='caller', systemd='reviewed', status=73,
                                        selection=(override.name,))
            self.assertIn('NEXT_INERT_GATE', result.stderr)
            self.assertNotIn('BB server setup incomplete', result.stdout)

    def test_captured_devinabox_override_differential_through_ordinary_caller(self):
        for relative, content in (
            ('.bb/config.json', '{"config":{"BB_APP_URL":"https://fixture.example.ts.net:38443"},"providers":{"keep":"fixture-secret"}}\n'),
            ('.bb/env.json', '{"env":{"KEEP_API_KEY":"fixture-secret"}}\n'),
            ('.config/setup-bb-server/endpoint', 'fixture.example.ts.net 38443 https://fixture.example.ts.net:38443\n'),
        ):
            protected = self.home / relative
            protected.write_text(content)
            protected.chmod(0o600)
        dropins = self.add_dropin(UNITS[0], 'empty')
        broad = dropins / 'env.conf'
        cases = (
            ('captured-775-env-664', 0o775, 0o664, 73),
            ('same-775-directory-empty', 0o775, None, 73),
            ('private-700-env-600', 0o700, 0o600, 73),
            ('safe-755-directory-empty', 0o755, None, 73),
            ('absent-directory', None, None, 73),
        )
        for state, directory_mode, file_mode, status in cases:
            with self.subTest(state=state):
                if file_mode is None:
                    broad.unlink(missing_ok=True)
                else:
                    broad.write_bytes(b'[Service]\nEnvironmentFile=%h/.env.local\n')
                    broad.chmod(file_mode)
                    metadata = broad.lstat()
                    self.assertTrue(stat.S_ISREG(metadata.st_mode))
                    self.assertEqual((metadata.st_uid, metadata.st_nlink, metadata.st_size,
                                      stat.S_IMODE(metadata.st_mode)),
                                     (os.getuid(), 1, 40, file_mode))
                if directory_mode is None:
                    dropins.rmdir()
                else:
                    dropins.chmod(directory_mode)
                    metadata = dropins.lstat()
                    self.assertTrue(stat.S_ISDIR(metadata.st_mode))
                    self.assertEqual((metadata.st_uid, stat.S_IMODE(metadata.st_mode)),
                                     (os.getuid(), directory_mode))
                kwargs = dict(mode='caller', status=status, selection=(broad.name,),
                              systemd='reviewed' if file_mode is not None else 'clean')
                first = self.run_preflight(**kwargs)
                second = self.run_preflight(**kwargs)
                self.assertEqual((first.stdout, first.stderr), (second.stdout, second.stderr))
                for result in (first, second):
                    self.assertIn('LOG_STARTED', result.stdout)
                    self.assertNotIn('Setup complete!', result.stdout)
                    self.assertIn('NEXT_INERT_GATE', result.stderr)
                    for unit in UNITS:
                        self.assertIn('SYSTEMD_SHOW: ' + unit, result.stderr)
                    self.assertNotIn('BB server setup incomplete', result.stdout)
                    self.assertNotIn('PLUGIN_REFRESH:', result.stdout)
                    self.assertNotIn('FINAL_STATUS=', result.stdout)

    def environment_reference(self, name='env.conf'):
        dropins = self.add_dropin(UNITS[0], 'empty')
        dropins.chmod(0o775)
        override = dropins / name
        override.write_bytes(b'[Service]\nEnvironmentFile=%h/.env.local\n')
        override.chmod(0o664)
        return override

    def test_environment_reference_requires_present_managed_fragment(self):
        self.environment_reference()
        (self.units / UNITS[0]).unlink()
        result = self.run_preflight(mode='caller', systemd='reviewed', selection=('env.conf',))
        self.assert_caller_refusal(result)

    def test_snapshot_and_loaded_selection_both_refuse_invalid_selection_grammar(self):
        self.environment_reference()
        digest = 'a' * 64
        invalid = [f'dropins:{names}:{digest}' for names in
                   ('', 'other.conf', 'env.conf,20-env-local.conf', 'env.conf,10-tmpdir.conf',
                    '10-tmpdir.conf,10-tmpdir.conf', 'env.conf,env.conf', '../env.conf')]
        invalid += ['dropins:env.conf:' + 'A' * 64, 'dropins:env.conf:' + 'a' * 63,
                    'dropins:env.conf:' + digest + ':extra', 'dropins:env.conf:' + digest + '\nextra']
        for value in invalid:
            with self.subTest(snapshot=value):
                result = self.run_preflight(mode='caller', systemd='reviewed', selection=('env.conf',),
                                            snapshot_output=value)
                self.assert_caller_refusal(result)
                self.assertNotIn('SYSTEMD_SHOW', result.stderr)
                self.run_preflight(mode='unit', systemd='reviewed', selection=('env.conf',),
                                   expected_snapshot=value)

    def test_prior_generated_fragment_variants_retain_compatibility(self):
        self.environment_reference()
        fragment = self.units / UNITS[0]
        for version, origin, tailscale in (
            ('22.20.0', 'https://prior.example.ts.net', '/usr/local/bin/tailscale'),
            ('24.20.0', 'https://fixture.example.ts.net:38443', '/usr/bin/tailscale'),
            ('24.20.0+local', 'https://other.example.ts.net:65535', '/usr/local/bin/tailscale'),
        ):
            with self.subTest(version=version, origin=origin, tailscale=tailscale):
                fragment.write_text(managed_app_unit(self.home, version=version, origin=origin, tailscale=tailscale))
                self.run_preflight(mode='caller', systemd='reviewed', selection=('env.conf',), status=73)

    def test_managed_fragment_requires_complete_exact_body(self):
        self.environment_reference()
        fragment = self.units / UNITS[0]
        original = fragment.read_text()
        for content in ('# setup-managed bb app v1\n', original + '\n',
                        original.replace('\n', '\r\n'), original.rstrip(),
                        original + '[Service]\nExecStop=/unsupported/hook\n',
                        original.replace('Type=simple\n', 'Type=simple\nExecStop=/unsupported/hook\n'),
                        original.replace('Type=simple\n', 'Type=simple\nEnvironmentFile=/other\n'),
                        original.replace('Restart=always', 'Restart=no'),
                        original.replace(' app-start\n', ' app-ready\n'),
                        original.replace('TimeoutStartSec=180\n', ''),
                        original.replace('Type=simple\n', 'Type=simple\nType=simple\n'),
                        original.replace('/24.20.0/bin/bb-app', '/../bin/bb-app'),
                        original.replace('/bin/bb-app', '/bin/bb-app;other'),
                        original.replace('Environment=PATH=', 'Environment=PATH=/other:'),
                        original.replace('/usr/bin/tailscale\n', '/other/tailscale\n'),
                        original.replace('https://fixture.example.ts.net', 'http://fixture.example.ts.net'),
                        original.replace('https://fixture.example.ts.net', 'https://fixture.example.ts.net:65536'),
                        original.replace('https://fixture.example.ts.net', 'https://fixture.example.ts.net/other'),
                        original + '\x00', original + '\u00ff', original + 'x' * 65536):
            with self.subTest(content=content):
                fragment.write_text(content)
                result = self.run_preflight(mode='caller', systemd='reviewed', selection=('env.conf',))
                self.assert_caller_refusal(result)
                self.assertNotIn('SYSTEMD_SHOW', result.stderr)

    def test_no_reference_fragment_snapshots_reject_late_changes(self):
        for selection in ('absent', 'empty'):
            if selection == 'empty':
                self.add_dropin(UNITS[0], 'empty')
            for field in ('ino', 'uid', 'gid', 'mode', 'size', 'mtime_ns', 'ctime_ns', 'content'):
                with self.subTest(selection=selection, field=field):
                    result = self.run_preflight(mode='checkpoint',
                                                inspection='env-late-fragment-' + field + '-race')
                    self.assert_caller_refusal(result)
                    self.assertIn('[preflight.app-unit]', result.stderr)

    def test_environment_fragment_snapshot_invalidates_late_identity_changes(self):
        self.environment_reference()
        for field in ('ino', 'uid', 'gid', 'mode', 'size', 'mtime_ns', 'ctime_ns'):
            with self.subTest(field=field):
                result = self.run_preflight(mode='checkpoint', systemd='reviewed',
                                            selection=('env.conf',),
                                            inspection='env-late-fragment-' + field + '-race')
                self.assert_caller_refusal(result)
                self.assertIn('[preflight.app-unit]', result.stderr)

    def test_environment_and_private_tmpdir_keep_both_ordered_inputs(self):
        dropins, _, target = self.reviewed()
        (target / 'existing-work').write_text('untouched\n')
        for path in (self.home, self.home / '.config', self.home / '.config/systemd',
                     self.units, dropins, self.home / '.cache', target.parent):
            path.chmod(0o2775)
        self.add_dropin(UNITS[1], 'empty').chmod(0o775)
        for name in ('env.conf', '20-env-local.conf'):
            override = dropins / name
            override.write_bytes(b'[Service]\nEnvironmentFile=%h/.env.local\n')
            for mode in (0o400, 0o600, 0o640, 0o644, 0o660, 0o664):
                override.chmod(mode)
                for _ in range(2):
                    result = self.run_preflight(mode='caller', systemd='reviewed', status=73,
                                                selection=('10-tmpdir.conf', name))
                    self.assertIn('NEXT_INERT_GATE', result.stderr)
            override.unlink()

    def test_environment_content_is_exact_required_reference_only(self):
        override = self.environment_reference()
        original = override.read_bytes()
        cases = (
            b'', b'[Service]\n', original.rstrip(), original + b'\n',
            original.replace(b'\n', b'\r\n'), original + b'# comment\n',
            original.replace(b'EnvironmentFile=', b'EnvironmentFile=-'),
            original.replace(b'%h/.env.local', str(self.home / '.env.local').encode()),
            original.replace(b'%h/.env.local', b'$HOME/.env.local'),
            original.replace(b'%h/.env.local', b'/fixture-secret/foreign'),
            original.replace(b'%h/.env.local', b'"%h/.env.local"'),
            original.replace(b'%h/.env.local', b'%h/.env.local %h/other'),
            original.replace(b'%h/.env.local', b'%h/./.env.local'),
            original + original, original + b'Environment=OTHER=fixture-secret\n',
            original + b'ExecStart=/fixture-secret\n', original + b'\x00',
            original + b'\xff', original + b'\\\n', b'x' * 8192,
            original.replace(b'[Service]', b'[Unit]'),
        )
        for content in cases:
            with self.subTest(content=content[:80]):
                override.write_bytes(content)
                result = self.run_preflight(mode='caller', systemd='reviewed', selection=(override.name,))
                self.assert_caller_refusal(result)
                self.assert_diagnostic(result, UNITS[0])
                self.assertNotIn('SYSTEMD_SHOW', result.stderr)
        override.write_bytes(original + b'Environment=EXTRA=fixture-secret\n')
        self.assert_caller_refusal(self.run_preflight(mode='caller', systemd='reviewed',
                                  selection=(override.name,), inspection='env-short-read'))

    def test_environment_reference_does_not_authorize_other_entries_or_ingress(self):
        override = self.environment_reference()
        for name in ('20-env-local.conf', '.hidden', 'extra.conf'):
            extra = override.with_name(name)
            extra.write_bytes(override.read_bytes())
            extra.chmod(0o600)
            self.assert_caller_refusal(self.run_preflight(mode='caller', systemd='reviewed',
                                                          selection=('env.conf',)))
            extra.unlink()
        renamed = override.with_name('other.conf')
        override.rename(renamed)
        self.assert_caller_refusal(self.run_preflight(mode='caller', systemd='reviewed',
                                                      selection=('other.conf',)))
        ingress = self.add_dropin(UNITS[1], 'empty')
        renamed.rename(ingress / 'env.conf')
        self.assert_caller_refusal(self.run_preflight(mode='caller', unit=UNITS[1],
                                                      systemd='reviewed', selection=('env.conf',)))

    def test_environment_artifacts_and_credential_source_keep_distinct_permissions(self):
        override = self.environment_reference()
        for path, modes in ((override, (0o000, 0o200, 0o666, 0o704, 0o674, 0o665,
                                       0o1664, 0o2664, 0o4664)),
                            (self.home / '.env.local', (0o000, 0o200, 0o640, 0o644, 0o660,
                                                       0o664, 0o666, 0o700, 0o1600, 0o2600, 0o4600))):
            content = path.read_bytes()
            for mode in modes:
                with self.subTest(path=path.name, mode=oct(mode)):
                    path.chmod(mode)
                    self.assert_caller_refusal(self.run_preflight(mode='caller', systemd='reviewed',
                                                                  selection=(override.name,)))
            path.chmod(0o600)
            saved = path.with_name(path.name + '-saved') if path.name == '.env.local' else self.root / 'saved-reference'
            path.rename(saved)
            for kind in ('missing', 'link', 'dangling', 'directory', 'fifo', 'hardlink'):
                with self.subTest(path=path.name, kind=kind):
                    if kind == 'link':
                        path.symlink_to(saved)
                    elif kind == 'dangling':
                        path.symlink_to(self.root / 'missing')
                    elif kind == 'directory':
                        path.mkdir()
                    elif kind == 'fifo':
                        os.mkfifo(path)
                    elif kind == 'hardlink':
                        os.link(saved, path)
                    self.assert_caller_refusal(self.run_preflight(mode='caller', systemd='reviewed',
                                                                  selection=(override.name,)))
                    if kind == 'directory':
                        path.rmdir()
                    elif kind != 'missing':
                        path.unlink()
                    self.assertEqual(saved.read_bytes(), content)
            saved.rename(path)
        for mode in (0o400, 0o600):
            (self.home / '.env.local').chmod(mode)
            self.run_preflight(mode='caller', systemd='reviewed', status=73, selection=('env.conf',))
        (self.units / UNITS[0]).chmod(0o664)
        result = self.run_preflight(mode='caller', systemd='reviewed', selection=('env.conf',))
        self.assert_caller_refusal(result)
        self.assertIn('[preflight.app-unit-file]', result.stderr)

    def test_environment_selection_must_match_complete_ordered_loaded_state(self):
        dropins, _, _ = self.reviewed()
        override = dropins / 'env.conf'
        override.write_bytes(b'[Service]\nEnvironmentFile=%h/.env.local\n')
        override.chmod(0o664)
        for metadata in ('clean', 'loaded', 'foreign', 'absent', 'missing', 'malformed', 'failed',
                         'duplicate-fragment', 'duplicate-dropins', 'reviewed-duplicate',
                         'reviewed-extra', 'reviewed-reversed', 'reviewed-twice'):
            with self.subTest(metadata=metadata):
                result = self.run_preflight(mode='caller', systemd=metadata,
                                            selection=('10-tmpdir.conf', 'env.conf'))
                self.assert_caller_refusal(result)
                self.assertIn('[preflight.app-unit]', result.stderr)
        self.assert_caller_refusal(self.run_preflight(mode='checkpoint', systemd='reviewed-late-missing',
                                                      selection=('10-tmpdir.conf', 'env.conf')))

    def test_environment_snapshots_reject_metadata_content_and_parent_races(self):
        self.environment_reference()
        for target in ('reference', 'source', 'parent'):
            for boundary in ('', 'late-'):
                for field in ('dev', 'ino', 'uid', 'gid', 'mode', 'type', 'nlink', 'size', 'mtime_ns', 'ctime_ns'):
                    with self.subTest(target=target, boundary=boundary, field=field):
                        inspection = 'env-' + boundary + target + '-' + field + '-race'
                        result = self.run_preflight(mode='checkpoint' if boundary else 'caller',
                                                    systemd='reviewed', selection=('env.conf',),
                                                    inspection=inspection)
                        self.assert_caller_refusal(result)
        for inspection in ('env-reference-foreign', 'env-source-foreign', 'env-parent-foreign',
                           'env-reference-failed', 'env-source-failed', 'env-parent-failed',
                           'env-late-source-failed',
                           'env-content-race', 'env-late-content-race', 'env-late-fragment-content-race'):
            with self.subTest(inspection=inspection):
                result = self.run_preflight(mode='checkpoint' if '-late-' in inspection else 'caller',
                                            systemd='reviewed', selection=('env.conf',), inspection=inspection)
                self.assert_caller_refusal(result)
        unchanged = self.run_preflight(mode='checkpoint', systemd='reviewed', selection=('env.conf',))
        self.assertIn('NEXT_INERT_GATE', unchanged.stderr)
        self.assertIn('[update.directories]', unchanged.stderr)

    def test_changed_between_reviewed_legacy_names_invalidates_local_selection(self):
        override = self.environment_reference()
        result = self.run_preflight(mode='checkpoint', systemd='reviewed', selection=(override.name,),
                                    inspection='env-late-selection-race')
        self.assert_caller_refusal(result)
        self.assertIn('[preflight.app-unit]', result.stderr)
        self.run_preflight(mode='caller', systemd='reviewed', selection=('20-env-local.conf',), status=73)

    def reviewed(self):
        dropins = self.add_dropin(UNITS[0], 'empty')
        target = self.home / '.cache/bb/tmp'
        target.mkdir(parents=True, mode=0o700)
        override = dropins / '10-tmpdir.conf'
        override.write_text('[Service]\nEnvironment=TMPDIR=' + str(target) + '\n')
        override.chmod(0o600)
        return dropins, override, target

    def assert_caller_refusal(self, result):
        self.assertNotIn('NEXT_INERT_GATE', result.stderr)
        self.assertIn('BB server setup incomplete', result.stdout)
        self.assertIn('PLUGIN_REFRESH: block-default', result.stdout)
        self.assertIn('UNAFFECTED_SKILLS', result.stdout)
        self.assertIn('UNAFFECTED_PI_REFRESH', result.stdout)
        self.assertTrue(result.stdout.endswith('FINAL_STATUS=1\n'))

    def test_tmpdir_content_is_a_narrow_literal_contract(self):
        _, override, target = self.reviewed()
        original = override.read_bytes()
        cases = (
            b'', b'[Service]\n', original + b'Environment=OTHER=fixture-secret\n',
            original + b'Environment=TMPDIR=/other\n', original + original,
            original.replace(b'[Service]', b'[Unit]'),
            original.replace(str(target).encode(), b'%h/.cache/bb/tmp'),
            original.replace(str(target).encode(), b'$HOME/.cache/bb/tmp'),
            original.replace(str(target).encode(), b'/tmp'),
            original.replace(b'Environment=', b'EnvironmentFile='),
            original + b'ExecStart=/fixture-secret\n', original + b'\x00',
            original + b'\xff', original + b'\\\n', b'x' * 8192,
            original.replace(b'Environment=', b'Environment="').rstrip() + b' OTHER=fixture-secret"\n',
        )
        for content in cases:
            with self.subTest(content=content[:80]):
                override.write_bytes(content)
                result = self.run_preflight(mode='caller', systemd='reviewed')
                self.assert_caller_refusal(result)
                self.assert_diagnostic(result, UNITS[0])
                self.assertNotIn('SYSTEMD_SHOW', result.stderr)
        override.write_bytes(original.replace(b'Environment=TMPDIR=', b'Environment="TMPDIR=').rstrip() + b'"\n')
        self.run_preflight(mode='caller', systemd='reviewed', status=73)

    def test_tmpdir_selection_cannot_extend_to_ingress_or_extra_entries(self):
        dropins, override, _ = self.reviewed()
        for name in ('unknown.conf', '.hidden', '20-extra.conf'):
            with self.subTest(name=name):
                extra = dropins / name
                extra.write_text('fixture-secret\n')
                self.assert_caller_refusal(self.run_preflight(mode='caller', systemd='reviewed'))
                extra.unlink()
        renamed = dropins / 'other.conf'
        override.rename(renamed)
        self.assert_caller_refusal(self.run_preflight(mode='caller', systemd='reviewed'))
        renamed.rename(override)
        ingress = self.add_dropin(UNITS[1], 'empty')
        override.rename(ingress / override.name)
        self.assert_caller_refusal(self.run_preflight(unit=UNITS[1], mode='caller'))

    def test_tmpdir_artifact_types_and_permissions_never_trigger_repair(self):
        _, override, target = self.reviewed()
        content = override.read_bytes()
        for mode in (0o644, 0o664, 0o620, 0o666, 0o000, 0o1600):
            with self.subTest(mode=oct(mode)):
                override.chmod(mode)
                self.assert_caller_refusal(self.run_preflight(mode='caller', systemd='reviewed'))
        override.chmod(0o600)
        self.assertEqual(override.read_bytes(), content)
        saved = self.root / 'saved-override'
        override.rename(saved)
        for kind in ('link', 'dangling', 'directory', 'fifo', 'hardlink'):
            with self.subTest(kind=kind):
                if kind == 'link':
                    override.symlink_to(saved)
                elif kind == 'dangling':
                    override.symlink_to(self.root / 'missing')
                elif kind == 'directory':
                    override.mkdir()
                elif kind == 'fifo':
                    os.mkfifo(override)
                else:
                    os.link(saved, override)
                self.assert_caller_refusal(self.run_preflight(mode='caller', systemd='reviewed'))
                if kind == 'directory':
                    override.rmdir()
                else:
                    override.unlink()
                self.assertEqual(saved.read_bytes(), content)
        saved.rename(override)
        for path in (override.parent, self.home / '.cache', target.parent):
            with self.subTest(path=path.name):
                path.chmod(0o770)
                self.run_preflight(mode='caller', systemd='reviewed', status=73)
                path.chmod(0o700)
        for mode in (0o770, 0o775, 0o755, 0o2700):
            target.chmod(mode)
            self.assert_caller_refusal(self.run_preflight(mode='caller', systemd='reviewed'))
        target.chmod(0o700)
        target.rmdir()
        self.assert_caller_refusal(self.run_preflight(mode='caller', systemd='reviewed'))
        self.assertFalse(target.exists())

    def test_tmpdir_ancestors_and_target_are_not_followed_or_scanned(self):
        _, _, target = self.reviewed()
        (target / 'private-data').write_text('fixture-secret\n')
        (target / 'unrelated-link').symlink_to(self.root / 'missing')
        os.mkfifo(target / 'unrelated-fifo')
        self.run_preflight(mode='caller', systemd='reviewed', status=73)
        for path in (self.home / '.cache', target.parent, target,
                     self.home / '.config/systemd/user/setup-bb-app.service.d',
                     self.home / '.config/systemd/user', self.home / '.config/systemd',
                     self.home / '.config'):
            with self.subTest(path=str(path.relative_to(self.home))):
                saved = path.with_name(path.name + '-saved')
                path.rename(saved)
                path.symlink_to(saved, target_is_directory=True)
                self.assert_caller_refusal(self.run_preflight(mode='caller', systemd='reviewed'))
                path.unlink()
                saved.rename(path)

    def test_tmpdir_inspection_uncertainty_and_changes_refuse_without_effects(self):
        self.reviewed()
        (self.home / '.cache').chmod(0o775)
        for inspection in ('tmpdir-foreign', 'tmpdir-foreign-target', 'tmpdir-foreign-ancestor',
                           'tmpdir-inspection-failed', 'tmpdir-enumeration-failed',
                           'tmpdir-identity-race', 'tmpdir-content-race',
                           'tmpdir-directory-uid-race', 'tmpdir-directory-gid-race',
                           'tmpdir-directory-mode-race', 'tmpdir-directory-type-race',
                           'tmpdir-directory-ino-race'):
            with self.subTest(inspection=inspection):
                self.assert_caller_refusal(self.run_preflight(mode='caller', systemd='reviewed', inspection=inspection))

    def test_reviewed_tmpdir_shell_inspection_failures_keep_ordinary_caller_incomplete(self):
        self.reviewed()
        for ingress_empty in (False, True):
            if ingress_empty:
                self.add_dropin(UNITS[1], 'empty')
            for inspection in ('foreign', 'failed', 'malformed', 'changed',
                               'enumeration-failed', 'enumeration-missing'):
                with self.subTest(ingress_empty=ingress_empty, inspection=inspection):
                    first = self.run_preflight(mode='caller', systemd='reviewed', inspection=inspection)
                    second = self.run_preflight(mode='caller', systemd='reviewed', inspection=inspection)
                    self.assertEqual((first.stdout, first.stderr), (second.stdout, second.stderr))
                    self.assert_caller_refusal(first)
                    self.assert_diagnostic(first, UNITS[0])
                    self.assertIn('[preflight.unit-dropins]', first.stderr)
                    self.assertNotIn('SYSTEMD_SHOW', first.stderr)

    def test_short_file_reads_cannot_hide_extra_directives(self):
        _, override, _ = self.reviewed()
        override.write_bytes(override.read_bytes() + b'EnvironmentFile=/fixture-secret\n')
        self.assert_caller_refusal(self.run_preflight(mode='caller', systemd='reviewed',
                                                     inspection='tmpdir-short-read'))

    def test_tmpdir_local_evidence_does_not_override_loaded_selection(self):
        self.reviewed()
        for metadata in ('clean', 'loaded', 'foreign', 'absent', 'missing', 'malformed', 'failed',
                         'duplicate-fragment', 'duplicate-dropins', 'reviewed-duplicate'):
            with self.subTest(metadata=metadata):
                self.assert_caller_refusal(self.run_preflight(mode='caller', systemd=metadata))

    def test_local_dropin_paths_refuse_explain_and_preserve_without_systemd(self):
        for unit in UNITS:
            for kind in ('populated', 'file', 'link', 'dangling'):
                with self.subTest(unit=unit, kind=kind):
                    path = self.add_dropin(unit, kind)
                    try:
                        first = self.run_preflight(unit)
                        second = self.run_preflight(unit)
                        self.assertEqual((first.stdout, first.stderr), (second.stdout, second.stderr))
                        self.assert_diagnostic(first, unit)
                        self.assertIn('[preflight.unit-dropins]', first.stderr)
                        self.assertIn('$HOME/.config/systemd/user/' + unit + '.d', first.stdout)
                        self.assertNotIn('SYSTEMD_SHOW', first.stderr)
                    finally:
                        if path.is_symlink() or path.is_file():
                            path.unlink()
                        else:
                            for child in path.iterdir():
                                child.unlink()
                            path.rmdir()
                        target = self.root / 'fixture-secret-linked-target'
                        if target.exists():
                            (target / 'keep').unlink()
                            target.rmdir()

    def test_verified_empty_dropin_directories_reach_next_inert_gate_unchanged(self):
        for selected in ((UNITS[0],), (UNITS[1],), UNITS):
            paths = [self.add_dropin(unit, 'empty') for unit in selected]
            try:
                for mode in ('setup', 'caller'):
                    with self.subTest(empty_units=selected, mode=mode):
                        result = self.run_preflight(mode=mode, status=73)
                        self.assertIn('NEXT_INERT_GATE', result.stderr)
                        for checked in UNITS:
                            self.assertIn('SYSTEMD_SHOW: ' + checked, result.stderr)
                        self.assertNotIn('[preflight.unit-dropins]', result.stderr)
                        self.assertNotIn('BB server setup incomplete', result.stdout)
            finally:
                for path in paths:
                    path.rmdir()

    def test_any_dropin_entry_including_hidden_or_dangling_blocks_unchanged(self):
        for unit in UNITS:
            for kind in ('hidden', 'directory', 'dangling'):
                with self.subTest(unit=unit, kind=kind):
                    path = self.add_dropin(unit, 'empty')
                    entry = path / '.fixture-secret'
                    if kind == 'hidden':
                        entry.write_text('fixture-secret: never read contents\n')
                    elif kind == 'directory':
                        entry.mkdir()
                    else:
                        entry.symlink_to(self.root / 'fixture-secret-missing')
                    try:
                        result = self.run_preflight(unit)
                        self.assert_diagnostic(result, unit)
                        self.assertIn('[preflight.unit-dropins]', result.stderr)
                        self.assertNotIn('SYSTEMD_SHOW', result.stderr)
                    finally:
                        if kind == 'directory':
                            entry.rmdir()
                        else:
                            entry.unlink()
                        path.rmdir()

    def test_empty_dropins_with_unsafe_or_unreadable_modes_stay_blocked(self):
        for unit in UNITS:
            for permissions in (0o707, 0o100, 0o400, 0o000):
                with self.subTest(unit=unit, permissions=oct(permissions)):
                    path = self.add_dropin(unit, 'empty')
                    path.chmod(permissions)
                    try:
                        result = self.run_preflight(unit)
                        self.assert_diagnostic(result, unit)
                        self.assertNotIn('SYSTEMD_SHOW', result.stderr)
                    finally:
                        path.chmod(0o700)
                        path.rmdir()

    def test_empty_dropin_inspection_failures_preserve_failure_through_real_caller(self):
        for unit in UNITS:
            for inspection in ('foreign', 'failed', 'malformed', 'changed',
                               'enumeration-failed', 'enumeration-missing'):
                with self.subTest(unit=unit, inspection=inspection):
                    path = self.add_dropin(unit, 'empty')
                    try:
                        result = self.run_preflight(unit, mode='caller', inspection=inspection)
                        self.assert_diagnostic(result, unit)
                        self.assertIn('[preflight.unit-dropins]', result.stderr)
                        self.assertNotIn('SYSTEMD_SHOW', result.stderr)
                        self.assertIn('PLUGIN_REFRESH: block-default', result.stdout)
                        self.assertTrue(result.stdout.endswith('FINAL_STATUS=1\n'))
                    finally:
                        path.rmdir()

    def test_empty_local_directory_does_not_bypass_loaded_override_or_identity_checks(self):
        for unit in UNITS:
            for metadata in ('loaded', 'foreign', 'missing', 'malformed', 'failed'):
                with self.subTest(unit=unit, metadata=metadata):
                    path = self.add_dropin(unit, 'empty')
                    path.chmod(0o775)
                    try:
                        result = self.run_preflight(unit, mode='caller', systemd=metadata)
                        self.assertIn('SYSTEMD_SHOW: ' + unit, result.stderr)
                        self.assertNotIn('[preflight.unit-dropins]', result.stderr)
                        self.assertNotIn('NEXT_INERT_GATE', result.stderr)
                        self.assertIn('PLUGIN_REFRESH: block-default', result.stdout)
                        self.assertTrue(result.stdout.endswith('FINAL_STATUS=1\n'))
                        if metadata == 'loaded':
                            self.assert_diagnostic(result, unit)
                            self.assertIn('loaded systemd drop-ins', result.stdout)
                    finally:
                        path.rmdir()

    def test_loaded_dropins_refuse_without_disclosing_systemd_paths(self):
        for unit in UNITS:
            with self.subTest(unit=unit):
                result = self.run_preflight(unit, systemd='loaded')
                self.assert_diagnostic(result, unit)
                self.assertIn('loaded systemd drop-ins', result.stdout)
                kind = 'app' if unit == UNITS[0] else 'ingress'
                self.assertIn('[preflight.' + kind + '-unit]', result.stderr)
                self.assertIn('SYSTEMD_SHOW: ' + unit, result.stderr)

    def test_no_dropins_reach_next_inert_gate(self):
        for mode in ('setup', 'caller'):
            with self.subTest(mode=mode):
                result = self.run_preflight(mode=mode, status=73)
                if mode == 'setup':
                    self.assertEqual(result.stdout, '')
                self.assertNotIn('BB server setup incomplete', result.stdout)
                self.assertIn('NEXT_INERT_GATE', result.stderr)
                for unit in UNITS:
                    self.assertIn('SYSTEMD_SHOW: ' + unit, result.stderr)

    def test_duplicate_systemd_properties_cannot_hide_loaded_overrides(self):
        for metadata in ('duplicate-fragment', 'duplicate-dropins'):
            with self.subTest(metadata=metadata):
                result = self.run_preflight(mode='caller', systemd=metadata)
                self.assertNotIn('NEXT_INERT_GATE', result.stderr)
                self.assertIn('PLUGIN_REFRESH: block-default', result.stdout)
                self.assertTrue(result.stdout.endswith('FINAL_STATUS=1\n'))

    def test_unit_identity_checks_remain_fail_closed(self):
        for unit in UNITS:
            for metadata in ('clean', 'absent', 'foreign', 'missing', 'malformed', 'failed'):
                with self.subTest(unit=unit, metadata=metadata):
                    status = 0 if metadata in ('clean', 'absent') else 1
                    result = self.run_preflight(unit, mode='unit', systemd=metadata, status=status)
                    self.assertEqual(result.stdout, '')

    def test_real_caller_keeps_failure_continues_independent_work_and_finishes_log(self):
        for unit in UNITS:
            for boundary in ('local', 'loaded'):
                with self.subTest(unit=unit, boundary=boundary):
                    path = self.add_dropin(unit, 'populated') if boundary == 'local' else None
                    try:
                        result = self.run_preflight(unit, mode='caller',
                                                    systemd='loaded' if boundary == 'loaded' else 'clean')
                        self.assert_diagnostic(result, unit)
                        for expected in ('BB server setup incomplete; review the BB server diagnostics above.',
                                         'PLUGIN_REFRESH: block-default', 'UNAFFECTED_SKILLS',
                                         'UNAFFECTED_PI_REFRESH', 'REBOOT_CHECK',
                                         'Setup completed with errors', 'FINAL_STATUS=1'):
                            self.assertIn(expected, result.stdout)
                        self.assertNotIn('Setup complete!', result.stdout)
                        self.assertTrue(result.stdout.endswith('FINAL_STATUS=1\n'))
                    finally:
                        if path is not None:
                            for child in path.iterdir():
                                child.unlink()
                            path.rmdir()


if __name__ == '__main__':
    unittest.main(verbosity=2)
