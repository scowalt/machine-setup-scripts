"""Version 1: real BB override refusals and caller propagation, with inert effects."""
import hashlib
import os
from pathlib import Path
import re
import stat
import subprocess
import tempfile
import unittest

from extract_setup_fixture import validate_function

ROOT = Path(__file__).resolve().parents[1]
UNITS = ('setup-bb-app.service', 'setup-bb-ingress.service')
REAL = ('bb_server_failure', 'bb_setup_directory_preflight', 'bb_owned_metadata_file', 'bb_owned_file',
        'bb_owned_script', 'bb_unit_preflight', 'setup_bb_server',
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
    case "$2" in '%u %a'|'%u %h %a') ;; *) exit 97 ;; esac
    case "$4" in "$HOME"|"$HOME/"*) ;; *) exit 97 ;; esac
    /usr/bin/stat "$@"
}
systemctl() {
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
            missing) printf 'FragmentPath=%s\n' "$fragment"; return 0 ;;
            malformed) printf 'fixture-secret-invalid-property\n'; return 0 ;;
            failed) printf 'fixture-secret-systemd-error\n' >&2; return 1 ;;
            clean) ;;
            *) exit 97 ;;
        esac
    fi
    printf 'FragmentPath=%s\nDropInPaths=%s\n' "$fragment" "$dropins"
}
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
    caller) main ;;
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
    """Compare fixture data/metadata without following linked artifacts."""
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
            value = hashlib.sha256(path.read_bytes()).hexdigest()
        result[str(path.relative_to(root))] = (info.st_mode, info.st_uid, info.st_gid,
                                             info.st_nlink, info.st_mtime_ns,
                                             info.st_ctime_ns, value)
    return result


class BbServicePreflightTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Refuse standalone execution without inherited mandatory containment.
        sandbox = os.environ.get('FIXTURE_NETWORK_SANDBOX')
        if not sandbox:
            raise SystemExit(125)
        result = subprocess.run([sandbox, '--assert-inherited-denial'],
                                stdin=subprocess.DEVNULL, capture_output=True,
                                close_fds=True, timeout=10)
        if result.returncode:
            raise SystemExit(125)
        source = (ROOT / 'ubuntu.sh').read_text()
        # Independently validate only the selected real definitions. All other
        # named setup helpers are inert before caller execution; no whole-source
        # evaluation or top-level setup invocation is emitted.
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
        for unit, marker in zip(UNITS, ('# setup-managed bb app v1',
                                       '# setup-managed bb ingress v1')):
            (self.units / unit).write_text(marker + '\n')
            (self.units / unit).chmod(0o600)
        # Neither diagnostics nor caller may read environment/credential content.
        for relative in ('.env.local', '.bb/auth.json'):
            (self.home / relative).write_text('fixture-secret: preserve without reading\n')
            (self.home / relative).chmod(0o600)
        self.helpers = self.root / 'definitions.sh'
        self.helpers.write_text(self.definitions)
        self.helpers.chmod(0o600)
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

    def run_preflight(self, unit=UNITS[0], mode='setup', systemd='clean', status=1):
        before = snapshot(self.root)
        result = subprocess.run(
            ['/bin/bash', '--noprofile', '--norc', '-c', HARNESS, '_', str(self.helpers)],
            env={'PATH': str(self.empty_path), 'HOME': str(self.home), 'LANG': 'C',
                 'FIXTURE_UID': str(os.getuid()), 'FIXTURE_UNIT': unit,
                 'FIXTURE_MODE': mode, 'FIXTURE_SYSTEMD': systemd},
            cwd=self.home, stdin=subprocess.DEVNULL, capture_output=True,
            text=True, close_fds=True, timeout=5,
        )
        self.assertEqual(result.returncode, status, result.stdout + result.stderr)
        self.assertNotIn('FORBIDDEN_', result.stdout + result.stderr)
        self.assertNotIn('fixture-secret', result.stdout + result.stderr)
        self.assertNotIn(str(self.home), result.stdout)
        self.assertEqual(snapshot(self.root), before, 'Preflight/caller changed fixture state')
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

    def test_local_dropin_paths_refuse_explain_and_preserve_without_systemd(self):
        for unit in UNITS:
            for kind in ('populated', 'empty', 'file', 'link', 'dangling'):
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
        result = self.run_preflight(status=73)
        self.assertEqual(result.stdout, '')
        self.assertIn('NEXT_INERT_GATE', result.stderr)
        for unit in UNITS:
            self.assertIn('SYSTEMD_SHOW: ' + unit, result.stderr)

    def test_unit_identity_checks_remain_fail_closed(self):
        for unit in UNITS:
            for metadata in ('clean', 'absent', 'foreign', 'missing', 'malformed', 'failed'):
                with self.subTest(unit=unit, metadata=metadata):
                    status = 0 if metadata in ('clean', 'absent') else 1
                    result = self.run_preflight(unit, mode='unit', systemd=metadata, status=status)
                    # Do not misdiagnose an identity/transport failure as overrides.
                    self.assertEqual(result.stdout, '')

    def test_real_caller_keeps_failure_continues_independent_work_and_finishes_log(self):
        for unit in UNITS:
            for boundary in ('local', 'loaded'):
                with self.subTest(unit=unit, boundary=boundary):
                    path = self.add_dropin(unit, 'empty') if boundary == 'local' else None
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
                            path.rmdir()


if __name__ == '__main__':
    unittest.main(verbosity=2)
