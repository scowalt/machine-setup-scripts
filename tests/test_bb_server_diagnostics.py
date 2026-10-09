import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

from bb_managed_unit_fixture import managed_app_unit, managed_ingress_unit
from extract_setup_fixture import definitions, validate_function

ROOT = Path(__file__).resolve().parents[1]
SECRET = 'DO-NOT-LOG-FIXTURE-SECRET'

MOCKS = r'''
print_error() { printf 'ERROR: %s\n' "$1"; }
print_success() { printf 'SUCCESS: %s\n' "$1"; }
print_message() { printf 'INFO: %s\n' "$1"; }
print_warning() { printf 'WARNING: %s\n' "$1"; }
event() { printf '%s\n' "$*" >> "$EVENTS"; }
noisy_failure() { printf '%s\n' 'DO-NOT-LOG-FIXTURE-SECRET' >&2; return 1; }
installed=0
app_active=${ACTIVE:-0}
ingress_active=${ACTIVE:-0}
command() {
    case "$*" in
        '-v tailscale')
            if [[ ${FAIL_COMMAND:-} == tailscale || ${FAIL_COMMAND:-} == late-tailscale && $installed == 1 ]]; then noisy_failure; return 1; fi
            if [[ ${FAIL_COMMAND:-} == path || ${FAIL_COMMAND:-} == late-path && $installed == 1 ]]; then printf '/DO-NOT-LOG-FIXTURE-SECRET/tailscale\n'; else printf '/usr/bin/tailscale\n'; fi ;;
        '-v loginctl') [[ ${FAIL_COMMAND:-} != loginctl ]] || { noisy_failure; return 1; }; printf '/usr/bin/loginctl\n' ;;
        *) builtin command "$@" ;;
    esac
}
ensure_shared_node_runtime() { [[ ${FAIL_RUNTIME:-0} != 1 ]]; }
npm() {
    local key="$1:${3:-}:${4:-}"
    if [[ ${FAIL_NPM:-} == "$key" || ${FAIL_NPM:-} == late-prefix && $installed == 1 ]]; then noisy_failure; return 1; fi
    case "$1" in
        --version) printf '%s\n' "${NPM_VERSION:-11.19.0}" ;;
        config)
            case "$3" in
                ignore-scripts) printf '%s\n' "${NPM_IGNORE:-false}" ;;
                dangerously-allow-all-scripts) printf '%s\n' "${NPM_DANGER:-false}" ;;
                strict-allow-scripts) printf '%s\n' "${NPM_STRICT:-true}" ;;
                allow-scripts)
                    if [[ ${4:-} == --allow-scripts=* ]]; then printf '%s\n' "${NPM_SCOPED:-better-sqlite3,node-pty,@parcel/watcher}"; else printf '%s\n' "${NPM_ALLOW:-}"; fi ;;
                *) return 97 ;;
            esac ;;
        prefix)
            if [[ ${FAIL_NPM:-} == changed-prefix && $installed == 1 ]]; then printf '/DO-NOT-LOG-FIXTURE-SECRET\n'; else printf '%s\n' "${NPM_PREFIX:-$HOME/.local/share/mise/installs/node/24.20.0}"; fi ;;
        install) event npm-install; [[ ${FAIL_INSTALL:-0} != 1 ]] || noisy_failure ;;
        *) return 97 ;;
    esac
}
# Actual preflight remains intact. Installation alone is replaced with inert
# bookkeeping, never npm, an application, a service or an installed module.
bb_install_package() {
    if [[ ${READINESS_EVIDENCE:-0} == 1 ]]; then
        [[ $app_active == 0 && $ingress_active == 0 ]] || { event forbidden-running-install; return 97; }
    fi
    event install; installed=1
    [[ ${FAIL_INSTALL:-0} != 1 ]] || { bb_server_failure npm.install; return 1; }
    if [[ ${READINESS_EVIDENCE:-0} == 1 ]]; then
        printf 'updated inert package\n' > "$HOME/.config/setup-bb-server/fixture-package-revision"
    fi
    if [[ ! -f "$HOME/.config/setup-bb-server/package-owner" ]]; then
        printf '%s\n' "$BB_PACKAGE_PATH" > "$HOME/.config/setup-bb-server/package-owner.next"
    fi
}
bb_config_merge_native() { event config; return 0; }
bb_package_artifacts_ready() { [[ ${FAIL_RESTORE_ARTIFACTS:-0} != 1 ]]; }
bb_managed_app_process() { [[ ${FAIL_PROCESS:-0} != 1 ]]; }
bb_native_app_ready() { event native-ready; [[ ${FAIL_READY:-} != native || $installed == 0 ]]; }
bb_local_ports_free() { [[ ${FAIL_PORTS:-} != preflight && ! ( ${FAIL_PORTS:-} == update && $app_active == 0 && ${ACTIVE:-0} == 1 ) ]]; }
tailscale() {
    [[ ${FAIL_TAILSCALE:-} != "$1:$2" ]] || { noisy_failure; return 1; }
    case "$1 $2" in
        'version --daemon') printf '{"short":"1.102.4","daemonLong":"1.102.4"}\n' ;;
        'status --json') printf '{"BackendState":"Running","Self":{"DNSName":"fixture.example.ts.net."}}\n' ;;
        'serve status')
            if [[ ${READINESS_EVIDENCE:-0} == 1 ]]; then
                event route-inspection
                if [[ $ingress_active == 1 ]]; then
                    proxy=38886
                    if [[ ${FAIL_NATIVE:-} == route && $installed == 1 && ${restoring:-0} == 0 ]]; then proxy=39999; fi
                    printf '{"Foreground":{"fixture":{"TCP":{"38443":{"HTTPS":true}},"Web":{"fixture.example.ts.net:38443":{"Handlers":{"/":{"Proxy":"http://127.0.0.1:%s"}}}}}},"TCP":{"45454":{"HTTPS":true}},"Web":{"unrelated.example.ts.net:45454":{"Handlers":{"/":{"Proxy":"http://127.0.0.1:45555"}}}}}\n' "$proxy"
                else printf '{}\n'; fi
            elif [[ ${FAIL_ROUTE:-} == occupied ]]; then printf '{"TCP":{"443":{},"38443":{},"38444":{},"38445":{}}}\n'
            elif [[ $ingress_active == 1 && ! ( ${FAIL_READY:-} == route && $installed == 1 ) ]]; then
                printf '{"Foreground":{"fixture":{"TCP":{"443":{"HTTPS":true}},"Web":{"fixture.example.ts.net:443":{"Handlers":{"/":{"Proxy":"http://127.0.0.1:38886"}}}}}}}\n'
            else printf '{}\n'; fi ;;
        *) return 97 ;;
    esac
}
systemctl() {
    local args="$*"
    [[ ${FAIL_SYSTEMD:-} != "$args" ]] || { noisy_failure; return 1; }
    case "$args" in
        *' show '*)
            if [[ ${RACE_PARENT:-0} == 1 && ! -L "$HOME/.config/systemd/user" ]]; then
                mv "$HOME/.config/systemd/user" "$HOME/.config/systemd/renamed"
                ln -s "$HOME/.config/systemd/renamed" "$HOME/.config/systemd/user"
            fi
            if [[ -n ${REVIEWED_DROPINS:-} && $3 == setup-bb-app.service ]]; then
                printf 'FragmentPath=%s\nDropInPaths=%s\n' "$HOME/.config/systemd/user/$3" "$REVIEWED_DROPINS"
            elif [[ ${TMPDIR_CUSTOMIZATION:-0} == 1 && $3 == setup-bb-app.service ]]; then
                printf 'FragmentPath=%s\nDropInPaths=%s\n' "$HOME/.config/systemd/user/$3" "$HOME/.config/systemd/user/$3.d/10-tmpdir.conf"
            else
                printf '%s\n' "${UNIT_DETAILS:-FragmentPath=}" 'DropInPaths='
            fi ;;
        *' is-enabled '*) printf 'enabled\n' ;;
        *' is-active '*setup-bb-app.service)
            [[ ${FAIL_READY:-} != app-active || $installed == 0 ]] && [[ $app_active == 1 ]] ;;
        *' is-active '*setup-bb-ingress.service)
            [[ ${FAIL_READY:-} != ingress-active || $installed == 0 ]] && [[ $ingress_active == 1 ]] ;;
        *' stop setup-bb-ingress.service')
            event stop-ingress
            if [[ $installed == 1 ]]; then restoring=1; fi
            [[ ${STUCK:-} == ingress ]] || ingress_active=0 ;;
        *' stop setup-bb-app.service') event stop-app; [[ ${STUCK:-} == app ]] || app_active=0 ;;
        *' daemon-reload') event reload ;;
        *' enable setup-bb-app.service') event enable ;;
        *' disable setup-bb-app.service') event disable ;;
        *' start setup-bb-app.service')
            event start-app
            if [[ ${FAIL_NATIVE:-} == start && ${restoring:-0} == 0 ]]; then noisy_failure; return 1; fi
            app_active=1; ingress_active=1 ;;
        *' start setup-bb-ingress.service') event start-ingress; ingress_active=1 ;;
        *) event UNEXPECTED-systemctl; return 97 ;;
    esac
}
loginctl() {
    if [[ ${RACE_OVERRIDE:-0} == 1 ]]; then
        printf '[Service]\nEnvironment=TMPDIR=/unsupported-fixture\n' > "$HOME/.config/systemd/user/setup-bb-app.service.d/10-tmpdir.conf"
    fi
    if [[ -n ${RACE_DIRECTORY:-} ]]; then
        [[ "$RACE_DIRECTORY" == "$HOME/"* ]] || return 97
        chmod 2770 "$RACE_DIRECTORY"
    fi
    [[ ${FAIL_LINGER:-} != query ]] || { noisy_failure; return 1; }
    printf '%s\n' "${LINGER:-yes}"
}
can_sudo() { [[ ${CAN_SUDO:-0} == 1 ]]; }
sudo() { event sudo; noisy_failure; }
curl() { [[ ${FAIL_READY:-} != https ]] || noisy_failure; }
sleep() { event wait; }
'''


def simple_function(source, name):
    start = source.index('\n' + name + '() {\n') + 1
    end = source.index('\n}\n', start) + 3
    block = source[start:end]
    validate_function(block)
    return block


class BbServerDiagnostics(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not os.environ.get('FIXTURE_NETWORK_SANDBOX'):
            raise RuntimeError('Use tests/run-fixture-matrix.py; no uncontained fallback')
        cls.source = (ROOT / 'ubuntu.sh').read_text()
        cls.definitions = definitions(cls.source)

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='bb-server-diagnostics-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.home = self.root / 'home'
        self.prefix = self.home / '.local/share/mise/installs/node/24.20.0'
        self.package = self.prefix / 'lib/node_modules/bb-app'
        for path in (self.home / '.bb', self.home / '.config/systemd/user',
                     self.home / '.config/setup-bb-server', self.prefix / 'bin',
                     self.prefix / 'lib/node_modules'):
            path.mkdir(parents=True, exist_ok=True)
        self.helpers = self.root / 'helpers.sh'
        self.helpers.write_text(self.definitions)
        self.events = self.root / 'events'
        self.events.touch()
        self.env = dict(os.environ, HOME=str(self.home), EVENTS=str(self.events),
                        HELPERS=str(self.helpers))
        for path in self.home.rglob('*'):
            if path.is_dir():
                path.chmod(0o700)
        self.home.chmod(0o700)
        self.seed('.env.local', '')

    def seed(self, name, value):
        target = self.home / name
        target.write_text(value)
        target.chmod(0o600)
        return target

    def active(self):
        self.env['ACTIVE'] = '1'
        self.seed('.config/systemd/user/setup-bb-app.service', managed_app_unit(self.home))
        self.seed('.config/systemd/user/setup-bb-ingress.service', managed_ingress_unit(self.home))
        self.seed('.config/setup-bb-server/endpoint', 'fixture.example.ts.net 443 https://fixture.example.ts.net\n')
        self.seed('.config/setup-bb-server/package-owner', str(self.package) + '\n')

    def snapshot(self):
        return {str(p.relative_to(self.home)): (p.lstat().st_mode,
                os.readlink(p) if p.is_symlink() else p.read_bytes() if p.is_file() else None)
                for p in self.home.rglob('*')}

    def run_code(self, code='setup_bb_server', extra='', env=None, log_paths=False, native_config=False):
        mocks = MOCKS
        if native_config:
            mocks = mocks.replace('bb_config_merge_native() { event config; return 0; }', '')
        result = subprocess.run(['/bin/bash', '--noprofile', '--norc'],
                                input='source "$HELPERS"\n' + mocks + '\n' + extra + '\n' + code,
                                env=dict(self.env, **(env or {})), cwd=self.root,
                                text=True, capture_output=True, timeout=20)
        output = result.stdout + result.stderr
        self.assertNotIn(SECRET, output)
        if not log_paths:
            self.assertNotIn(str(self.home), output)
        self.assertNotIn('command not found', output)
        self.assertNotIn('UNEXPECTED', output)
        return result

    def failure(self, label, *, extra='', env=None, unchanged=False):
        before = self.snapshot()
        result = self.run_code(extra=extra, env=env)
        self.assertEqual(result.returncode, 1, result)
        self.assertIn(f'BB server [{label}]:', result.stderr, result)
        self.assertNotIn('[diagnostic.unknown]', result.stderr)
        self.assertNotIn('SUCCESS:', result.stdout)
        if unchanged:
            self.assertEqual(self.snapshot(), before)
            self.assertNotRegex(self.events.read_text(), r'(?m)^(install|config|stop-|start-|sudo)')
        return result

    def customize(self):
        self.active()
        self.env['TMPDIR_CUSTOMIZATION'] = '1'
        directory = self.home / '.config/systemd/user/setup-bb-app.service.d'
        directory.mkdir(mode=0o700)
        target = self.home / '.cache/bb/tmp'
        target.mkdir(parents=True, mode=0o700)
        self.seed('.cache/bb/tmp/keep', 'existing temporary data\n')
        return self.seed('.config/systemd/user/setup-bb-app.service.d/10-tmpdir.conf',
                         '[Service]\nEnvironment=TMPDIR=' + str(target) + '\n')

    def ordinary_caller(self):
        names = re.findall(r'^(\w+)\(\) [({]', self.source, re.M)
        retained = {'setup_bb_server', 'run_setup_tasks', 'main',
                    'create_env_local', 'migrate_token_files', 'setup_load_environment',
                    'setup_environment_failure', 'setup_trim', 'setup_environment_value',
                    'print_error', 'print_warning', 'print_message', 'print_success'}
        stubs = '\n'.join(name + '() { :; }' for name in names
                          if not name.startswith('bb_') and name not in retained)
        return stubs + r'''
BB_SERVER=1 BOLD='' NC='' GRAY='' GREEN=''
check_dotfiles_access() { return 1; }
setup_dotfiles_deploy_key() { return 1; }
refresh_bb_plugins() { printf 'PLUGIN_REFRESH:%s\n' "$1"; }
setup_matt_pocock_skills() { printf 'INDEPENDENT_WORK\n'; }
start_setup_log() { printf 'LOG_STARTED\n'; }
finish_setup_log() { printf 'FINAL_STATUS=%s\n' "$1"; return "$1"; }
'''

    def test_ordinary_directory_modes_survive_complete_maintenance_and_caller(self):
        self.active()
        sentinel = self.seed('.bb/auth.json', '{"private":"' + SECRET + '"}')
        directories = [self.home / p for p in ('', '.config', '.config/systemd',
                       '.config/systemd/user', '.config/setup-bb-server', '.bb')]
        extra = self.ordinary_caller() + r'''
chmod() {
    [[ ! -d "${*: -1}" ]] || { event forbidden-directory-chmod; return 97; }
    builtin command chmod "$@"
}
chown() { event forbidden-chown; return 97; }
for name in getent groups getfacl setfacl ps pgrep; do
    eval "$name() { event forbidden-privacy-proof; return 97; }"
done
id() {
    [[ "$*" == -u || "$*" == -un ]] || { event forbidden-membership-proof; return 97; }
    builtin command id "$@"
}
check_pending_reboot() { printf 'REBOOT_CHECK\n'; }
'''
        for mode in (0o700, 0o755, 0o770, 0o775, 0o2775):
            for directory in directories:
                directory.chmod(mode)
            before = {p: (p.stat().st_dev, p.stat().st_ino, p.stat().st_uid,
                          p.stat().st_gid, p.stat().st_mode) for p in directories}
            for attempt in range(2):
                with self.subTest(mode=oct(mode), attempt=attempt):
                    self.events.write_text('')
                    result = self.run_code('main', extra=extra)
                    self.assertEqual(result.returncode, 0, result)
                    self.assertEqual(result.stderr, '')
                    for expected in ('PLUGIN_REFRESH:ready', 'INDEPENDENT_WORK',
                                     'REBOOT_CHECK', 'FINAL_STATUS=0'):
                        self.assertIn(expected, result.stdout)
                    events = self.events.read_text().splitlines()
                    self.assertNotIn('forbidden', '\n'.join(events))
                    order = [events.index(e) for e in ('stop-ingress', 'stop-app', 'install', 'config', 'start-app')]
                    self.assertEqual(order, sorted(order))
                    self.assertEqual({p: (p.stat().st_dev, p.stat().st_ino, p.stat().st_uid,
                                         p.stat().st_gid, p.stat().st_mode) for p in directories}, before)
                    self.assertEqual(sentinel.read_text(), '{"private":"' + SECRET + '"}')
                    self.assertEqual(sentinel.stat().st_mode & 0o7777, 0o600)
                    self.assertIn('bb-guard app-start', (self.home / '.config/systemd/user/setup-bb-app.service').read_text())

    def inherited_environment(self):
        self.active()
        directory = self.home / '.config/systemd/user/setup-bb-app.service.d'
        directory.mkdir(mode=0o775)
        directory.chmod(0o775)
        reference = self.seed(str(directory.relative_to(self.home)) + '/env.conf',
                              '[Service]\nEnvironmentFile=%h/.env.local\n')
        reference.chmod(0o664)
        self.seed('.config/systemd/user/setup-bb-app.service',
                  managed_app_unit(self.home, origin='https://fixture.example.ts.net:38443'))
        self.env.update(REVIEWED_DROPINS=str(reference), READINESS_EVIDENCE='1')
        self.seed('.env.local', 'UNRELATED=' + SECRET + '\n')
        self.seed('.bb/host-id', 'fixture-host\n')
        self.seed('.bb/auth.json', '{"hostId":"fixture-host","private":"' + SECRET + '"}')
        self.seed('.bb/env.json', '{"env":{"KEY":"' + SECRET + '"}}')
        self.seed('.bb/config.json', '{"config":{"BB_APP_URL":"https://fixture.example.ts.net:38443"},"providers":{"keep":"native"}}')
        self.seed('.config/setup-bb-server/endpoint', 'fixture.example.ts.net 38443 https://fixture.example.ts.net:38443\n')
        self.seed('.config/setup-bb-server/fixture-package-revision', 'prior inert package\n')
        self.seed('.bb/project-data', 'unrelated projects and sessions\n')
        self.seed('.config/systemd/user/unrelated.service', 'unrelated service\n')
        self.package.mkdir()
        self.seed(str(self.package.relative_to(self.home)) + '/package.json', '{"name":"bb-app"}')
        native = self.package / 'node_modules/fs-native-extensions'
        native.mkdir(parents=True)
        (native / 'index.js').write_text('''const fs=require('fs');
exports.tryLock=()=>{
  fs.appendFileSync(process.env.EVENTS, 'native-lock\\n');
  if(process.env.FAIL_NATIVE==='lock') throw new Error('DO-NOT-LOG-FIXTURE-SECRET');
  return true;
};
exports.unlock=()=>{fs.appendFileSync(process.env.EVENTS, 'native-unlock\\n')};
''')
        return reference

    def preserved_inputs(self, reference):
        paths = [self.home / name for name in ('.env.local', '.bb/host-id', '.bb/auth.json',
                 '.bb/env.json', '.bb/config.json', '.bb/project-data',
                 '.config/systemd/user/unrelated.service', '.config/setup-bb-server/endpoint',
                 '.config/setup-bb-server/package-owner')]
        if reference.parent.exists():
            paths += [reference.parent, *reference.parent.iterdir()]
        if (self.home / '.cache/bb/tmp').exists():
            paths += [self.home / '.cache/bb/tmp', self.home / '.cache/bb/tmp/keep']
        return {p: (p.lstat().st_dev, p.lstat().st_ino, p.lstat().st_uid, p.lstat().st_gid,
                    p.lstat().st_mode, p.lstat().st_nlink,
                    p.read_bytes() if p.is_file() else None) for p in paths if p.exists()}

    def logged_maintenance(self, *, env=None, extra=''):
        logging = '\n'.join(simple_function(self.source, name) for name in
                            ('start_setup_log', 'finish_setup_log', 'bb_native_app_ready'))
        logging += r'''
upload_log() { cp -- "$SETUP_LOG_FILE" "$EVENTS.uploaded"; }
date() { printf '%s\n' "$FIXTURE_RUN"; }
check_pending_reboot() { printf 'REBOOT_CHECK\n'; }
bb_managed_app_process() {
    event managed-process
    [[ ${FAIL_NATIVE:-} != process || $installed == 0 || ${restoring:-0} == 1 ]]
}
curl() {
    local phase=${FAIL_NATIVE:-} late=0
    if [[ $installed == 1 && ${restoring:-0} == 0 ]]; then late=1; fi
    case "${*: -1}" in
        http://127.0.0.1:38886/health)
            event native-health
            if [[ $phase == health && $late == 1 ]]; then noisy_failure; return 1; fi
            if [[ $phase == malformed && $late == 1 ]]; then printf 'DO-NOT-LOG-FIXTURE-SECRET'; return; fi
            printf '{"ok":true,"launchId":"fixture-launch"}\n' ;;
        http://127.0.0.1:38887/status)
            event native-host-status
            if [[ $phase == host-status && $late == 1 ]]; then noisy_failure; return 1; fi
            local host=fixture-host connected=true url=http://127.0.0.1:38886
            if [[ $late == 1 ]]; then
                case "$phase" in host-id) host=foreign-host;; disconnected) connected=false;; host-url) url=http://foreign.invalid;; esac
            fi
            printf '{"connected":%s,"hostId":"%s","serverUrl":"%s"}\n' "$connected" "$host" "$url" ;;
        *)
            [[ "$*" == *'https://fixture.example.ts.net:38443/ -o /dev/null' ]] || { event UNEXPECTED-https; return 97; }
            event private-https
            [[ $phase != https || $late == 0 ]] || noisy_failure ;;
    esac
}
'''
        self.events.write_text('')
        self.log_attempt = getattr(self, 'log_attempt', 0) + 1
        result = self.run_code('main', extra=self.ordinary_caller() + '\n' + logging + '\n' + extra,
                               env=dict(env or {}, FIXTURE_RUN='run-' + str(self.log_attempt)),
                               log_paths=True, native_config=True)
        uploaded = Path(str(self.events) + '.uploaded').read_text()
        self.assertNotIn(SECRET, uploaded)
        self.assertNotIn('[diagnostic.unknown]', uploaded)
        self.assertNotIn('forbidden', self.events.read_text())
        for expected in ('INDEPENDENT_WORK', 'REBOOT_CHECK', 'Run log saved to:'):
            self.assertIn(expected, uploaded)
        return result, uploaded, self.events.read_text().splitlines()

    def test_captured_environment_reference_completes_logged_ordinary_maintenance(self):
        reference = self.inherited_environment()
        for name, mode, combined in (('env.conf', 0o664, False), ('20-env-local.conf', 0o664, False),
                                     ('env.conf', 0o600, False), ('env.conf', 0o664, True),
                                     ('20-env-local.conf', 0o600, True)):
            reference = reference.rename(reference.with_name(name))
            reference.chmod(mode)
            if combined and not (reference.parent / '10-tmpdir.conf').exists():
                target = self.home / '.cache/bb/tmp'
                target.mkdir(parents=True, mode=0o700)
                self.seed('.cache/bb/tmp/keep', 'existing temporary data\n')
                self.seed(str(reference.parent.relative_to(self.home)) + '/10-tmpdir.conf',
                          '[Service]\nEnvironment=TMPDIR=' + str(target) + '\n')
            self.env['REVIEWED_DROPINS'] = ' '.join(str(p) for p in sorted(reference.parent.iterdir()))
            before = self.preserved_inputs(reference)
            for attempt in range(2):
                with self.subTest(name=name, mode=oct(mode), combined=combined, attempt=attempt):
                    result, uploaded, events = self.logged_maintenance()
                    self.assertEqual(result.returncode, 0, result)
                    self.assertIn('PLUGIN_REFRESH:ready', uploaded)
                    self.assertIn('BB available privately at https://fixture.example.ts.net:38443', uploaded)
                    self.assertNotIn('Setup completed with errors', uploaded)
                    order = [events.index(e) for e in ('stop-ingress', 'stop-app', 'install', 'native-lock',
                                                       'native-unlock', 'start-app')]
                    self.assertEqual(order, sorted(order))
                    after_start = events[events.index('start-app') + 1:]
                    self.assertEqual(after_start, ['managed-process', 'native-health', 'native-host-status',
                                                  'route-inspection', 'private-https'])
                    self.assertEqual(self.preserved_inputs(reference), before)
                    self.assertEqual(sorted(p.name for p in reference.parent.iterdir()),
                                     (['10-tmpdir.conf'] if combined else []) + [name])

    def test_ordinary_maintenance_does_not_seed_environment_inheritance(self):
        reference = self.inherited_environment()
        reference.unlink()
        (self.home / '.env.local').unlink()
        reference.parent.rmdir()
        del self.env['REVIEWED_DROPINS']
        for selection in ('absent', 'empty', 'tmpdir-only'):
            with self.subTest(selection=selection):
                if selection == 'empty':
                    reference.parent.mkdir(mode=0o775)
                    reference.parent.chmod(0o775)
                if selection == 'tmpdir-only':
                    target = self.home / '.cache/bb/tmp'
                    target.mkdir(parents=True, mode=0o700)
                    self.seed('.cache/bb/tmp/keep', 'existing temporary data\n')
                    self.seed(str(reference.parent.relative_to(self.home)) + '/10-tmpdir.conf',
                              '[Service]\nEnvironment=TMPDIR=' + str(target) + '\n')
                    self.env['TMPDIR_CUSTOMIZATION'] = '1'
                source = self.home / '.env.local'
                source.unlink(missing_ok=True)
                before = self.preserved_inputs(reference)
                result, uploaded, events = self.logged_maintenance()
                self.assertEqual(result.returncode, 0, result)
                self.assertIn('PLUGIN_REFRESH:ready', uploaded)
                self.assertEqual(events[-1], 'private-https')
                self.assertTrue(source.is_file())
                self.assertEqual(source.stat().st_mode & 0o777, 0o600)
                self.assertIn('# Machine-specific environment variables', source.read_text())
                after = self.preserved_inputs(reference)
                after.pop(source)
                self.assertEqual(after, before)
                self.assertFalse(reference.exists())
                self.assertFalse(reference.with_name('20-env-local.conf').exists())
                if selection == 'absent':
                    self.assertFalse(reference.parent.exists())

    def test_reference_source_and_legacy_tokens_survive_real_initialization(self):
        reference = self.inherited_environment()
        source = self.home / '.env.local'
        for state, mode, status in (('existing', 0o400, 0), ('missing', None, 1),
                                    ('unsafe', 0o640, 1)):
            with self.subTest(state=state):
                source.unlink(missing_ok=True)
                if mode is not None:
                    self.seed('.env.local', 'UNRELATED=' + SECRET + '\n').chmod(mode)
                tokens = [self.seed(name, key + '=' + SECRET + '\n') for name, key in
                          (('.gh_token', 'GH_TOKEN'), ('.op_token', 'OP_SERVICE_ACCOUNT_TOKEN'))]
                before = self.preserved_inputs(reference)
                token_state = {p: (p.read_bytes(), p.stat().st_mode, p.stat().st_ino,
                                   p.stat().st_mtime_ns, p.stat().st_ctime_ns) for p in tokens}
                result, uploaded, events = self.logged_maintenance()
                self.assertEqual(result.returncode, status, result)
                self.assertEqual(self.preserved_inputs(reference), before)
                self.assertEqual({p: (p.read_bytes(), p.stat().st_mode, p.stat().st_ino,
                                      p.stat().st_mtime_ns, p.stat().st_ctime_ns) for p in tokens}, token_state)
                if status:
                    self.assertIn('[preflight.unit-dropins]', uploaded)
                    self.assertIn('PLUGIN_REFRESH:block-default', uploaded)
                    self.assertFalse(set(events) & {'stop-ingress', 'stop-app', 'install', 'start-app'})
                else:
                    self.assertIn('PLUGIN_REFRESH:ready', uploaded)
                    self.assertIn('private-https', events)

    def test_no_reference_keeps_legacy_migration_and_data_only_loading(self):
        reference = self.inherited_environment()
        reference.unlink()
        reference.parent.rmdir()
        self.env.pop('REVIEWED_DROPINS')
        source = self.seed('.env.local', 'BB_SERVER=1\nUNRELATED=' + SECRET + '\n')
        source.chmod(0o400)
        token = self.seed('.gh_token', "export GH_TOKEN='literal-$(never-run);value'\n")
        result, uploaded, events = self.logged_maintenance(extra='''
unset BB_SERVER
setup_matt_pocock_skills() {
    [[ "$GH_TOKEN" == 'literal-$(never-run);value' ]] || return 97
    printf 'INDEPENDENT_WORK\\n'
}
''')
        self.assertEqual(result.returncode, 0, result)
        self.assertFalse(token.exists())
        self.assertIn("GH_TOKEN='literal-$(never-run);value'", source.read_text())
        self.assertIn('UNRELATED=' + SECRET, source.read_text())
        self.assertEqual(source.stat().st_mode & 0o777, 0o600)
        self.assertIn('PLUGIN_REFRESH:ready', uploaded)
        self.assertIn('private-https', events)

    def test_unsafe_reference_paths_do_not_recreate_source_or_migrate_tokens(self):
        reference = self.inherited_environment()
        source = self.home / '.env.local'
        source.unlink()
        token = self.seed('.gh_token', 'GH_TOKEN=' + SECRET + '\n')
        for state in ('legacy-name', 'dangling-reference', 'linked-directory', 'wrong-type-directory'):
            with self.subTest(state=state):
                selected = reference
                if state == 'legacy-name':
                    selected = reference.rename(reference.with_name('20-env-local.conf'))
                elif state == 'dangling-reference':
                    reference.unlink()
                    reference.symlink_to(self.root / 'missing-reference')
                elif state == 'linked-directory':
                    reference.parent.rename(self.home / 'saved-dropins')
                    reference.parent.symlink_to(self.home / 'saved-dropins', target_is_directory=True)
                elif state == 'wrong-type-directory':
                    reference.parent.rename(self.home / 'saved-dropins')
                    reference.parent.write_text('not a directory\n')
                self.env['REVIEWED_DROPINS'] = str(selected)
                result, uploaded, events = self.logged_maintenance()
                self.assertEqual(result.returncode, 1, result)
                self.assertFalse(source.exists())
                self.assertEqual(token.read_text(), 'GH_TOKEN=' + SECRET + '\n')
                self.assertIn('[preflight.unit-dropins]', uploaded)
                self.assertIn('PLUGIN_REFRESH:block-default', uploaded)
                self.assertFalse(set(events) & {'stop-ingress', 'stop-app', 'install', 'start-app'})
                if state == 'legacy-name':
                    selected.rename(reference)
                elif state == 'dangling-reference':
                    reference.unlink()
                    reference.write_text('[Service]\nEnvironmentFile=%h/.env.local\n')
                    reference.chmod(0o664)
                else:
                    reference.parent.unlink()
                    (self.home / 'saved-dropins').rename(reference.parent)

    def test_inherited_environment_failures_restore_services_not_original_success(self):
        reference = self.inherited_environment()
        before = self.preserved_inputs(reference)
        units = [self.home / ('.config/systemd/user/setup-bb-' + kind + '.service')
                 for kind in ('app', 'ingress')]
        prior_units = {p: p.read_bytes() for p in units}
        for failure, label in (('install', 'npm.install'), ('lock', 'config.locks'),
                               ('start', 'update.start-app'), ('process', 'readiness.process'),
                               ('health', 'readiness.health'), ('host-status', 'readiness.host-status'),
                               ('host-id', 'readiness.native'), ('host-url', 'readiness.native'),
                               ('disconnected', 'readiness.native'), ('malformed', 'readiness.native'),
                               ('route', 'readiness.route'), ('https', 'readiness.https')):
            with self.subTest(failure=failure):
                revision = self.seed('.config/setup-bb-server/fixture-package-revision', 'prior inert package\n')
                env = {'FAIL_INSTALL': '1'} if failure == 'install' else {'FAIL_NATIVE': failure}
                result, uploaded, events = self.logged_maintenance(env=env)
                self.assertEqual(result.returncode, 1, result)
                self.assertIn('[' + label + ']', uploaded)
                self.assertIn('PLUGIN_REFRESH:block-default', uploaded)
                self.assertIn('Setup completed with errors', uploaded)
                self.assertNotIn('BB available privately', uploaded)
                self.assertNotIn('restoration incomplete', uploaded)
                self.assertNotIn('[restore.', uploaded)
                self.assertEqual(events.count('install'), 1)
                self.assertLess(events.index('stop-ingress'), events.index('stop-app'))
                self.assertLess(events.index('stop-app'), events.index('install'))
                self.assertLess(events.index('install'), events.index('start-app'))
                self.assertEqual(events[-4:], ['managed-process', 'native-health', 'native-host-status', 'start-ingress'])
                self.assertEqual(self.preserved_inputs(reference), before)
                self.assertEqual({p: p.read_bytes() for p in units}, prior_units)
                self.assertEqual(revision.read_text(), 'prior inert package\n' if failure == 'install'
                                 else 'updated inert package\n')

        result, uploaded, events = self.logged_maintenance(env={'FAIL_INSTALL': '1', 'FAIL_RESTORE_ARTIFACTS': '1'})
        self.assertEqual(result.returncode, 1, result)
        self.assertLess(uploaded.index('[npm.install]'), uploaded.index('[restore.artifacts]'))
        self.assertIn('restoration incomplete', uploaded)
        self.assertIn('PLUGIN_REFRESH:block-default', uploaded)
        self.assertNotIn('start-app', events)
        self.assertEqual(self.preserved_inputs(reference), before)

    def test_inherited_environment_success_does_not_clear_unrelated_failure(self):
        reference = self.inherited_environment()
        before = self.preserved_inputs(reference)
        result, uploaded, events = self.logged_maintenance(extra='update_dependencies() { return 1; }')
        self.assertEqual(result.returncode, 1, result)
        self.assertIn('PLUGIN_REFRESH:ready', uploaded)
        self.assertIn('BB available privately at https://fixture.example.ts.net:38443', uploaded)
        self.assertIn('Setup completed with errors', uploaded)
        self.assertNotIn('BB server setup incomplete', uploaded)
        self.assertEqual(events[-1], 'private-https')
        self.assertEqual(self.preserved_inputs(reference), before)

    def test_inherited_environment_unsafe_neighbors_fail_before_stop_and_finalize(self):
        reference = self.inherited_environment()
        source = self.home / '.env.local'
        for case in ('extra-entry', 'duplicate', 'optional', 'source-missing', 'source-public',
                     'reference-world-write', 'reference-executable', 'reference-link',
                     'loaded-selection', 'loaded-fragment', 'late-mode'):
            with self.subTest(case=case):
                env, extra, added = {}, '', None
                if case in ('extra-entry', 'duplicate'):
                    added = self.seed(str(reference.parent.relative_to(self.home)) +
                                      ('/.hidden' if case == 'extra-entry' else '/20-env-local.conf'), reference.read_text())
                elif case == 'optional':
                    reference.write_text('[Service]\nEnvironmentFile=-%h/.env.local\n')
                elif case == 'source-missing':
                    source.unlink()
                elif case == 'source-public':
                    source.chmod(0o640)
                elif case == 'reference-world-write':
                    reference.chmod(0o666)
                elif case == 'reference-executable':
                    reference.chmod(0o764)
                elif case == 'reference-link':
                    added = self.seed('reference-target', reference.read_text())
                    reference.unlink()
                    reference.symlink_to(added)
                elif case == 'loaded-selection':
                    env['REVIEWED_DROPINS'] = str(reference) + ' /unverified/extra.conf'
                elif case == 'loaded-fragment':
                    extra = 'systemctl() { printf "FragmentPath=/unverified/app.service\\nDropInPaths=%s\\n" "$REVIEWED_DROPINS"; }'
                elif case == 'late-mode':
                    extra = 'loginctl() { chmod 600 "$HOME/.config/systemd/user/setup-bb-app.service.d/env.conf"; printf "yes\\n"; }'
                before = self.preserved_inputs(reference)
                if case == 'late-mode':
                    item = list(before[reference]); item[4] = 0o100600
                    before[reference] = tuple(item)
                result, uploaded, events = self.logged_maintenance(env=env, extra=extra)
                self.assertEqual(result.returncode, 1, result)
                self.assertRegex(uploaded, r'\[preflight\.(unit-dropins|app-unit)\]')
                self.assertIn('PLUGIN_REFRESH:block-default', uploaded)
                self.assertIn('Setup completed with errors', uploaded)
                self.assertNotIn('BB available privately', uploaded)
                self.assertFalse(set(events) & {'stop-ingress', 'stop-app', 'install', 'native-lock', 'start-app'})
                self.assertEqual(self.preserved_inputs(reference), before)
                if reference.is_symlink():
                    reference.unlink()
                reference.write_text('[Service]\nEnvironmentFile=%h/.env.local\n')
                reference.chmod(0o664)
                self.seed('.env.local', 'UNRELATED=' + SECRET + '\n')
                if added:
                    added.unlink()

    def test_marked_custom_app_fragments_refuse_before_stop_and_finalize(self):
        reference = self.inherited_environment()
        fragment = self.home / '.config/systemd/user/setup-bb-app.service'
        original = fragment.read_text()
        for selection in ('environment', 'empty', 'absent'):
            if selection == 'empty':
                reference.unlink()
                self.env.pop('REVIEWED_DROPINS')
            elif selection == 'absent':
                reference.parent.rmdir()
            for content in (original.replace('[Service]\n', '[Service]\nExecStop=/unsupported/hook\n'),
                            original.replace('Type=simple\n', 'Type=simple\nEnvironmentFile=/other\n'),
                            original.replace('Restart=always', 'Restart=no'),
                            original.replace(' app-ready\n', ' ingress-start\n'),
                            original.replace('Environment=HOME=', 'Environment=EXTRA='),
                            original.replace('/bin/bb-app\n', '/bin/other\n')):
                with self.subTest(selection=selection, content=content):
                    fragment.write_text(content)
                    before = self.preserved_inputs(reference)
                    result, uploaded, events = self.logged_maintenance()
                    self.assertEqual(result.returncode, 1, result)
                    self.assertIn('[preflight.unit-dropins]', uploaded)
                    self.assertIn('PLUGIN_REFRESH:block-default', uploaded)
                    self.assertIn('Setup completed with errors', uploaded)
                    self.assertFalse(set(events) & {'stop-ingress', 'stop-app', 'install', 'native-lock', 'start-app'})
                    self.assertEqual(fragment.read_text(), content)
                    self.assertEqual(self.preserved_inputs(reference), before)
        fragment.write_text(original)

    def test_existing_selection_gates_do_not_activate_inherited_environment(self):
        reference = self.inherited_environment()
        before = self.preserved_inputs(reference)
        for extra, status in (('BB_SERVER=0', 0), ('unset BB_SERVER', 0),
                              ('bb_native_ubuntu_id() { printf "debian\\n"; }', 1)):
            with self.subTest(gate=extra):
                result, uploaded, events = self.logged_maintenance(extra=extra)
                self.assertEqual(result.returncode, status, result)
                self.assertEqual(events, [])
                self.assertNotIn('BB available privately', uploaded)
                self.assertEqual(self.preserved_inputs(reference), before)

    def test_changed_customization_before_mutation_keeps_caller_incomplete(self):
        override = self.customize()
        before = self.snapshot()
        expected_content = b'[Service]\nEnvironment=TMPDIR=/unsupported-fixture\n'
        before[str(override.relative_to(self.home))] = (override.stat().st_mode, expected_content)
        result = self.run_code('main', extra=self.ordinary_caller(), env={'RACE_OVERRIDE': '1'})
        self.assertEqual(result.returncode, 1, result)
        self.assertNotRegex(self.events.read_text(), r'(?m)^(install|config|stop-|start-|sudo)')
        self.assertEqual(self.snapshot(), before)
        self.assertIn('PLUGIN_REFRESH:block-default', result.stdout)
        self.assertIn('INDEPENDENT_WORK', result.stdout)
        self.assertTrue(result.stdout.endswith('FINAL_STATUS=1\n'))

    def test_accepted_directory_mode_change_invalidates_pre_mutation_snapshot(self):
        override = self.customize()
        ingress = self.home / '.config/systemd/user/setup-bb-ingress.service.d'
        ingress.mkdir(mode=0o775)
        for directory in (override.parent, self.home / '.cache', ingress):
            with self.subTest(directory=directory.name):
                directory.chmod(0o775)
                before = self.snapshot()
                before[str(directory.relative_to(self.home))] = (0o42770, None)
                self.events.write_text('')
                result = self.run_code('main', extra=self.ordinary_caller(),
                                       env={'RACE_DIRECTORY': str(directory)})
                self.assertEqual(result.returncode, 1, result)
                self.assertRegex(result.stderr, r'\[preflight\.(app|ingress)-unit\]')
                self.assertEqual(self.snapshot(), before)
                self.assertNotRegex(self.events.read_text(), r'(?m)^(install|config|stop-|start-|sudo)')
                self.assertIn('PLUGIN_REFRESH:block-default', result.stdout)
                self.assertTrue(result.stdout.endswith('FINAL_STATUS=1\n'))

    def test_replaced_parent_refuses_before_dropin_enumeration(self):
        override = self.customize()
        content = override.read_bytes()
        extra = self.ordinary_caller() + r'''
find() {
    if [[ -L "$HOME/.config/systemd/user" ]]; then
        event forbidden-parent-traversal
        return 97
    fi
    builtin command find "$@"
}
'''
        result = self.run_code('main', extra=extra, env={'RACE_PARENT': '1'})
        self.assertEqual(result.returncode, 1, result)
        self.assertNotIn('forbidden-parent-traversal', self.events.read_text())
        self.assertNotRegex(self.events.read_text(), r'(?m)^(install|config|stop-|start-|sudo)')
        parent = self.home / '.config/systemd/user'
        self.assertTrue(parent.is_symlink())
        self.assertEqual((parent.with_name('renamed') / 'setup-bb-app.service.d/10-tmpdir.conf').read_bytes(), content)
        self.assertIn('PLUGIN_REFRESH:block-default', result.stdout)
        self.assertTrue(result.stdout.endswith('FINAL_STATUS=1\n'))

    def test_reviewed_customization_completes_caller_with_native_config_preserved(self):
        override = self.customize()
        (self.home / '.config/systemd/user/setup-bb-ingress.service.d').mkdir()
        ordinary = [self.home / p for p in ('', '.config', '.config/systemd', '.config/systemd/user',
                    '.config/setup-bb-server', '.bb', '.cache', '.cache/bb',
                    '.config/systemd/user/setup-bb-app.service.d',
                    '.config/systemd/user/setup-bb-ingress.service.d')]
        for directory in ordinary:
            directory.chmod(0o2775)
        modes = {p: (p.stat().st_ino, p.stat().st_uid, p.stat().st_gid, p.stat().st_mode) for p in ordinary}
        self.package.mkdir()
        self.seed(str(self.package.relative_to(self.home)) + '/package.json', '{"name":"bb-app"}')
        native = self.package / 'node_modules/fs-native-extensions'
        native.mkdir(parents=True)
        (native / 'index.js').write_text('exports.tryLock=()=>true;exports.unlock=()=>{};')
        self.seed('.bb/config.json', '{"config":{"BB_APP_URL":"https://fixture.example.ts.net"},"providers":{"keep":"native"}}')
        self.seed('.bb/env.json', '{"env":{"KEY":"' + SECRET + '"}}')
        self.seed('.bb/auth.json', '{"private":"' + SECRET + '"}')
        self.seed('.env.local', 'UNRELATED=' + SECRET + '\n')
        protected = [override, self.home / '.cache/bb/tmp/keep', self.home / '.env.local',
                     self.home / '.bb/auth.json', self.home / '.bb/config.json',
                     self.home / '.bb/env.json', self.home / '.config/setup-bb-server/endpoint']
        before = {p: (p.stat().st_mode, p.read_bytes()) for p in protected}
        extra = self.ordinary_caller()
        for _ in range(2):
            self.events.write_text('')
            result = self.run_code('main', extra=extra, native_config=True)
            self.assertEqual(result.returncode, 0, result)
            self.assertEqual(result.stderr, '')
            self.assertIn('private TMPDIR override verified', result.stdout)
            self.assertIn('PLUGIN_REFRESH:ready', result.stdout)
            self.assertIn('INDEPENDENT_WORK', result.stdout)
            self.assertTrue(result.stdout.endswith('FINAL_STATUS=0\n'))
            self.assertEqual({p: (p.stat().st_mode, p.read_bytes()) for p in protected}, before)
            self.assertEqual({p: (p.stat().st_ino, p.stat().st_uid, p.stat().st_gid, p.stat().st_mode) for p in ordinary}, modes)
            self.assertEqual((self.home / '.cache/bb/tmp').stat().st_mode & 0o7777, 0o700)
            events = self.events.read_text().splitlines()
            order = [events.index(e) for e in ('stop-ingress', 'stop-app', 'install', 'start-app')]
            self.assertEqual(order, sorted(order))
        self.events.write_text('')
        result = self.run_code('main', extra=extra, env={'FAIL_INSTALL': '1'}, native_config=True)
        self.assertEqual(result.returncode, 1, result)
        self.assertIn('[npm.install]', result.stderr)
        self.assertIn('start-ingress', self.events.read_text())
        self.assertIn('PLUGIN_REFRESH:block-default', result.stdout)
        self.assertTrue(result.stdout.endswith('FINAL_STATUS=1\n'))
        self.assertEqual({p: (p.stat().st_mode, p.read_bytes()) for p in protected}, before)

    def test_group_writable_package_tree_completes_real_install_config_and_caller(self):
        self.active()
        files = {
            'package.json': '{"name":"bb-app","version":"0.44.0"}',
            'node_modules/fs-native-extensions/index.js': 'exports.tryLock=()=>true;exports.unlock=()=>{};',
            'node_modules/better-sqlite3/index.js': 'module.exports=class {close(){}};',
            'node_modules/node-pty/index.js': 'module.exports={};',
            'node_modules/@parcel/watcher/index.js': 'module.exports={};',
            'node_modules/fs-native-extensions/prebuilds/linux-x64/nested/fixture.node': 'inert-not-loaded',
        }
        for artifact in ('dist/bb-app.js', 'dist/bb-server.js', 'dist/bb-host-daemon.js',
                         'server/dist/index.js', 'app/dist/index.html',
                         'host-daemon/dist/daemon-bundle.mjs', 'host-daemon/dist/bb',
                         'host-daemon/dist/bb-provider-bridge-worker.mjs',
                         'host-daemon/dist/bb-parcel-watcher-child.mjs',
                         'host-daemon/dist/bb-plugin-host-worker.mjs', 'host-daemon/dist/bb-chunks/a.js'):
            files[artifact] = 'throw new Error("fixture application must never execute");'
        for relative, content in files.items():
            path = self.package / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content)
            path.chmod(0o600)
        (self.prefix / 'bin/bb-app').symlink_to('../lib/node_modules/bb-app/dist/bb-app.js')
        config = self.seed('.bb/config.json', '{"config":{"BB_APP_URL":"https://old.invalid"},"providers":{"keep":"native"}}')
        env = self.seed('.bb/env.json', '{"env":{"BB_APP_URL":"https://old.invalid","KEY":"' + SECRET + '"}}')
        auth = self.seed('.bb/auth.json', '{"private":"' + SECRET + '"}')
        for unit in ('app', 'ingress'):
            (self.home / ('.config/systemd/user/setup-bb-' + unit + '.service.d')).mkdir()
        directories = [self.home] + [p for p in self.home.rglob('*') if p.is_dir()]
        for path in directories:
            path.chmod(0o2775)
        before = {p: (p.stat().st_dev, p.stat().st_ino, p.stat().st_uid,
                      p.stat().st_gid, p.stat().st_mode) for p in directories}
        protected = {p: p.read_bytes() for p in (auth, self.home / '.config/setup-bb-server/endpoint')}
        extra = self.ordinary_caller() + '\n' + '\n'.join(simple_function(self.source, name) for name in
                 ('bb_install_package', 'bb_package_artifacts_ready')) + r'''
chmod() {
    [[ ! -d "${*: -1}" ]] || { event forbidden-directory-chmod; return 97; }
    builtin command chmod "$@"
}
for name in chown getent groups getfacl setfacl ps pgrep; do
    eval "$name() { event forbidden-privacy-or-repair; return 97; }"
done
id() {
    [[ "$*" == -u || "$*" == -un ]] || { event forbidden-membership-proof; return 97; }
    builtin command id "$@"
}
check_pending_reboot() { printf 'REBOOT_CHECK\n'; }
'''
        for attempt in range(2):
            with self.subTest(attempt=attempt):
                self.events.write_text('')
                result = self.run_code('main', extra=extra, native_config=True)
                self.assertEqual(result.returncode, 0, result)
                self.assertEqual(result.stderr, '')
                events = self.events.read_text().splitlines()
                self.assertNotIn('forbidden', '\n'.join(events))
                order = [events.index(e) for e in ('stop-ingress', 'stop-app', 'npm-install', 'start-app')]
                self.assertEqual(order, sorted(order))
                for expected in ('PLUGIN_REFRESH:ready', 'REBOOT_CHECK', 'FINAL_STATUS=0'):
                    self.assertIn(expected, result.stdout)
                self.assertEqual(json.loads(config.read_text()), {'config': {'BB_APP_URL': 'https://fixture.example.ts.net'},
                                                                 'providers': {'keep': 'native'}})
                self.assertEqual(json.loads(env.read_text()), {'env': {'KEY': SECRET}})
                self.assertEqual({p: (p.stat().st_dev, p.stat().st_ino, p.stat().st_uid,
                                     p.stat().st_gid, p.stat().st_mode) for p in directories}, before)
                self.assertEqual({p: p.read_bytes() for p in protected}, protected)
                for name in ('config.json', 'env.json', '.config.json.lock', '.env.json.lock'):
                    self.assertEqual((self.home / '.bb' / name).stat().st_mode & 0o7777, 0o600)

        for relative, mode, label in (
            ('.bb/auth.json', 0o640, 'preflight.host-identity'),
            ('.bb/config.json', 0o620, 'preflight.config-file'),
            ('.bb/.config.json.lock', 0o620, 'config.locks'),
            ('.config/setup-bb-server/endpoint', 0o640, 'preflight.endpoint-file'),
            ('.config/systemd/user/setup-bb-app.service', 0o664, 'preflight.app-unit-file'),
            (str(self.package.relative_to(self.home)) + '/package.json', 0o660, 'npm.previous-target'),
            (str(self.package.relative_to(self.home)) + '/node_modules/fs-native-extensions/prebuilds/linux-x64/nested/fixture.node',
             0o660, 'npm.previous-target'),
        ):
            with self.subTest(unsafe_file=relative):
                target = self.home / relative
                old_mode, content = target.stat().st_mode & 0o7777, target.read_bytes()
                target.chmod(mode)
                result = self.run_code('main', extra=extra, native_config=True)
                self.assertEqual(result.returncode, 1, result)
                self.assertIn('[' + label + ']', result.stderr)
                self.assertIn('PLUGIN_REFRESH:block-default', result.stdout)
                self.assertIn('REBOOT_CHECK', result.stdout)
                self.assertTrue(result.stdout.endswith('FINAL_STATUS=1\n'))
                self.assertEqual(target.read_bytes(), content)
                self.assertEqual(target.stat().st_mode & 0o7777, mode)
                target.chmod(old_mode)
        for target, label in ((self.home / '.local', 'npm.prefix-directory'),
                              (self.package, 'npm.previous-target'),
                              (self.package / 'node_modules/fs-native-extensions/prebuilds/linux-x64/nested', 'npm.previous-target')):
            with self.subTest(unsafe_directory=str(target.relative_to(self.home))):
                target.chmod(0o2777)
                result = self.run_code('main', extra=extra, native_config=True)
                self.assertEqual(result.returncode, 1, result)
                self.assertIn('[' + label + ']', result.stderr)
                self.assertEqual(target.stat().st_mode & 0o7777, 0o2777)
                target.chmod(0o2775)
                saved = self.root / 'saved-directory'
                target.rename(saved)
                target.symlink_to(saved, target_is_directory=True)
                result = self.run_code('main', extra=extra, native_config=True)
                self.assertEqual(result.returncode, 1, result)
                self.assertIn('[' + label + ']', result.stderr)
                self.assertTrue(target.is_symlink())
                target.unlink()
                saved.rename(target)
        for label, failure in (('npm.install', {'FAIL_INSTALL': '1'}),
                               ('readiness.https', {'FAIL_READY': 'https'})):
            with self.subTest(downstream=label):
                self.events.write_text('')
                result = self.run_code('main', extra=extra, native_config=True, env=failure)
                self.assertEqual(result.returncode, 1, result)
                self.assertIn('[' + label + ']', result.stderr)
                self.assertIn('PLUGIN_REFRESH:block-default', result.stdout)
                self.assertIn('start-ingress', self.events.read_text())
                self.assertTrue(result.stdout.endswith('FINAL_STATUS=1\n'))
        result = self.run_code('main', extra=extra + '\nupdate_dependencies() { return 1; }', native_config=True)
        self.assertEqual(result.returncode, 1, result)
        self.assertIn('PLUGIN_REFRESH:ready', result.stdout)
        self.assertNotIn('BB server setup incomplete', result.stdout)
        self.assertTrue(result.stdout.endswith('FINAL_STATUS=1\n'))
        self.assertEqual({p: (p.stat().st_dev, p.stat().st_ino, p.stat().st_uid,
                             p.stat().st_gid, p.stat().st_mode) for p in directories}, before)
        self.assertEqual({p: p.read_bytes() for p in protected}, protected)

    def test_optional_environment_reference_refusal_survives_real_log_finalization(self):
        override = self.customize()
        for directory in (self.home, self.home / '.config', self.home / '.config/systemd',
                          override.parent.parent, override.parent):
            directory.chmod(0o775)
        broad = self.seed('.config/systemd/user/setup-bb-app.service.d/20-env-local.conf',
                          '[Service]\nEnvironmentFile=-%h/.env.local\n')
        broad.chmod(0o664)
        auth = self.seed('.bb/auth.json', '{"private":"' + SECRET + '"}')
        environment = self.seed('.env.local', 'UNRELATED=' + SECRET + '\n')
        protected = [override, broad, auth, environment, self.home / '.cache/bb/tmp/keep']
        before = {p: (p.stat().st_mode, p.read_bytes()) for p in protected}
        logging = '\n'.join(simple_function(self.source, name) for name in ('start_setup_log', 'finish_setup_log'))
        logging += '\nupload_log() { cp -- "$SETUP_LOG_FILE" "$EVENTS.uploaded"; }\n'
        result = self.run_code('main', extra=self.ordinary_caller() + '\n' + logging, log_paths=True)
        self.assertEqual(result.returncode, 1, result)
        self.assertEqual({p: (p.stat().st_mode, p.read_bytes()) for p in protected}, before)
        self.assertEqual(self.events.read_text(), '')
        uploaded = Path(str(self.events) + '.uploaded').read_text()
        for expected in ('[preflight.unit-dropins]', 'unsupported or unverified drop-in path',
                         'PLUGIN_REFRESH:block-default', 'INDEPENDENT_WORK',
                         'Setup completed with errors', 'Run log saved to:'):
            self.assertIn(expected, uploaded)
        self.assertNotIn(SECRET, uploaded)

    def test_early_command_and_unit_failures_are_identified_without_mutation(self):
        cases = [
            ('preflight.tailscale-command', {'FAIL_COMMAND': 'tailscale'}),
            ('preflight.tailscale-path', {'FAIL_COMMAND': 'path'}),
            ('preflight.required-commands', {'FAIL_COMMAND': 'loginctl'}),
            ('preflight.app-unit', {'FAIL_SYSTEMD': '--user show setup-bb-app.service --property=FragmentPath --property=DropInPaths'}),
            ('preflight.ingress-unit', {'FAIL_SYSTEMD': '--user show setup-bb-ingress.service --property=FragmentPath --property=DropInPaths'}),
            ('preflight.app-unit', {'UNIT_DETAILS': 'FragmentPath=/DO-NOT-LOG-FIXTURE-SECRET'}),
            ('preflight.local-ports', {'FAIL_PORTS': 'preflight'}),
            ('preflight.tailnet-version', {'FAIL_TAILSCALE': 'version:--daemon'}),
            ('preflight.tailnet-identity', {'FAIL_TAILSCALE': 'status:--json'}),
            ('preflight.https-port-selection', {'FAIL_ROUTE': 'occupied'}),
            ('preflight.linger-query', {'FAIL_LINGER': 'query'}),
            ('preflight.linger-enable', {'LINGER': 'no'}),
        ]
        for label, env in cases:
            with self.subTest(label=label, env=env):
                self.failure(label, env=env, unchanged=True)

    def test_file_and_endpoint_failures_are_identified_without_values(self):
        cases = [
            ('.bb/server-import.json', '{}', 'preflight.migration-state'),
            ('.config/systemd/user/setup-bb-app.service', SECRET, 'preflight.app-unit-file'),
            ('.config/systemd/user/setup-bb-ingress.service', SECRET, 'preflight.ingress-unit-file'),
            ('.config/setup-bb-server/bb-guard', SECRET, 'preflight.guard-file'),
            ('.config/setup-bb-server/endpoint', '', 'preflight.endpoint-read'),
            ('.config/setup-bb-server/endpoint', 'fixture.example.ts.net 08 ignored\n', 'preflight.endpoint-port'),
            ('.config/setup-bb-server/endpoint', f'fixture.example.ts.net {SECRET} https://fixture.example.ts.net\n', 'preflight.endpoint-port'),
            ('.config/setup-bb-server/endpoint', f'fixture.example.ts.net 443 {SECRET}\n', 'preflight.endpoint-origin'),
            ('.bb/config.json', '{' + SECRET, 'preflight.config-json'),
            ('.bb/config.json', '{"duplicate":1,"duplicate":2}', 'preflight.config-json'),
        ]
        for name, value, label in cases:
            with self.subTest(label=label):
                target = self.seed(name, value)
                try:
                    self.failure(label, unchanged=True)
                finally:
                    target.unlink()
        target = self.home / '.bb/auth.json'
        target.symlink_to(self.root / SECRET)
        self.failure('preflight.metadata-link', unchanged=True)

    def test_metadata_permissions_are_reported_at_the_actual_boundary(self):
        self.seed('.bb/config.json', '{"private":"' + SECRET + '"}').chmod(0o620)
        self.failure('preflight.config-file', unchanged=True)

    def test_native_npm_preflight_reports_each_query_and_policy_failure(self):
        cases = [
            ('npm.shared-runtime', {'FAIL_RUNTIME': '1'}),
            ('npm.version-query', {'FAIL_NPM': '--version::'}),
            ('npm.version-format', {'NPM_VERSION': SECRET}),
            ('npm.version-floor', {'NPM_VERSION': '11.18.0'}),
            ('npm.ignore-scripts-query', {'FAIL_NPM': 'config:ignore-scripts:'}),
            ('npm.dangerous-scripts-query', {'FAIL_NPM': 'config:dangerously-allow-all-scripts:'}),
            ('npm.lifecycle-policy', {'NPM_IGNORE': 'true'}),
            ('npm.lifecycle-policy', {'NPM_DANGER': SECRET}),
            ('npm.allow-scripts-query', {'FAIL_NPM': 'config:allow-scripts:'}),
            ('npm.allow-scripts-policy', {'NPM_ALLOW': SECRET}),
            ('npm.strict-policy-query', {'FAIL_NPM': 'config:strict-allow-scripts:--strict-allow-scripts'}),
            ('npm.strict-policy', {'NPM_STRICT': SECRET}),
            ('npm.scoped-policy-query', {'FAIL_NPM': 'config:allow-scripts:--allow-scripts=better-sqlite3,node-pty,@parcel/watcher'}),
            ('npm.scoped-policy', {'NPM_SCOPED': SECRET}),
            ('npm.prefix-query', {'FAIL_NPM': 'prefix::'}),
            ('npm.prefix', {'NPM_PREFIX': '/' + SECRET}),
        ]
        for label, env in cases:
            with self.subTest(label=label):
                self.failure(label, env=env, unchanged=True)

    def test_owned_and_unowned_package_boundaries_remain_distinct(self):
        self.package.mkdir()
        self.failure('npm.unowned-package', unchanged=True)
        self.seed('.config/setup-bb-server/package-owner', str(self.package) + '\n')
        self.package.chmod(0o777)
        self.failure('npm.previous-target', unchanged=True)

    def test_actual_installer_distinguishes_install_and_verification_failure(self):
        helper = simple_function(self.source, 'bb_install_package')
        for label, env, extra in (
            ('npm.install', {'FAIL_INSTALL': '1'}, ''),
            ('npm.artifacts', {}, 'bb_package_artifacts_ready() { return 1; }'),
        ):
            with self.subTest(label=label):
                result = self.run_code('bb_install_package', extra=helper + '\n' + extra, env=env)
                self.assertEqual(result.returncode, 1, result)
                self.assertIn('[' + label + ']', result.stderr)
                self.assertTrue((self.home / '.config/setup-bb-server/package-owner.next').is_file())
                self.assertFalse((self.home / '.config/setup-bb-server/package-owner').exists())

    def test_restoration_failures_keep_existing_status_and_attempt_order(self):
        call = '''bb_restore_bb_services "$HOME/app-unit" "$HOME/ingress-unit" "$HOME/guard" 'old-app' 'old-ingress' 'old-guard' 1 1 "$HOME/.local/share/mise/installs/node/24.20.0/lib/node_modules/bb-app" 0'''
        cases = [
            ('restore.app-unit', {}, 'bb_write_owned_unit() { [[ "$1" != */app-unit ]]; }'),
            ('restore.ingress-unit', {}, 'bb_write_owned_unit() { [[ "$1" != */ingress-unit ]]; }'),
            ('restore.guard', {}, 'bb_write_owned_content() { [[ "$1" != */guard ]]; }'),
            ('restore.daemon-reload', {'FAIL_SYSTEMD': '--user daemon-reload'}, ''),
            ('restore.disable-app', {'FAIL_SYSTEMD': '--user disable setup-bb-app.service'}, ''),
            ('restore.artifacts', {'FAIL_RESTORE_ARTIFACTS': '1'}, ''),
            ('restore.start-app', {'FAIL_SYSTEMD': '--user start setup-bb-app.service'}, ''),
            ('restore.start-ingress', {'FAIL_SYSTEMD': '--user start setup-bb-ingress.service'}, ''),
            ('restore.readiness', {}, 'bb_native_app_ready() { BB_SERVER_READY_CHECK=readiness.health; return 1; }'),
        ]
        for label, env, extra in cases:
            with self.subTest(label=label):
                self.events.write_text('')
                result = self.run_code(call, extra=extra, env=env)
                self.assertEqual(result.returncode, 1, result)
                self.assertIn('[' + label + ']', result.stderr)
                events = self.events.read_text().splitlines()
                self.assertEqual(events[:2], ['stop-ingress', 'stop-app'])
                if label == 'restore.readiness':
                    self.assertEqual(events.count('wait'), 30)
                    self.assertEqual(result.stderr.count('[readiness.health]'), 1)
        for service in ('ingress', 'app'):
            with self.subTest(best_effort=service):
                result = self.run_code(call, env={'FAIL_SYSTEMD': '--user stop setup-bb-' + service + '.service'})
                self.assertEqual(result.returncode, 0, result)
                self.assertIn('[restore.stop-' + service + ']', result.stderr)

    def test_stopped_update_and_late_command_failures(self):
        self.active()
        cases = [
            ('update.stop-ingress', {'FAIL_SYSTEMD': '--user stop setup-bb-ingress.service'}),
            ('update.stop-app', {'FAIL_SYSTEMD': '--user stop setup-bb-app.service'}),
            ('update.ingress-stopped', {'STUCK': 'ingress'}),
            ('update.app-stopped', {'STUCK': 'app'}),
            ('update.local-ports', {'FAIL_PORTS': 'update'}),
            ('update.prefix-query', {'FAIL_NPM': 'late-prefix'}),
            ('update.prefix-changed', {'FAIL_NPM': 'changed-prefix'}),
            ('update.tailscale-command', {'FAIL_COMMAND': 'late-tailscale'}),
            ('update.tailscale-path', {'FAIL_COMMAND': 'late-path'}),
            ('update.daemon-reload', {'FAIL_SYSTEMD': '--user daemon-reload'}),
            ('update.enable-app', {'FAIL_SYSTEMD': '--user enable setup-bb-app.service'}),
            ('update.start-app', {'FAIL_SYSTEMD': '--user start setup-bb-app.service'}),
        ]
        for label, env in cases:
            with self.subTest(label=label):
                self.events.write_text('')
                result = self.failure(label, env=env)
                self.assertNotIn('remains stopped', result.stdout + result.stderr)

    def test_success_and_restoration_keep_event_order_and_original_status(self):
        self.active()
        result = self.run_code()
        self.assertEqual(result.returncode, 0, result)
        self.assertEqual(result.stderr, '')
        events = self.events.read_text().splitlines()
        indices = [events.index(e) for e in ('stop-ingress', 'stop-app', 'install', 'config', 'start-app')]
        self.assertEqual(indices, sorted(indices))
        self.events.write_text('')
        result = self.failure('npm.install', env={'FAIL_INSTALL': '1'})
        events = self.events.read_text().splitlines()
        self.assertLess(events.index('install'), events.index('start-app'))
        self.assertIn('start-ingress', events)
        self.assertNotIn('[restore.', result.stderr)
        result = self.failure('npm.install', env={'FAIL_INSTALL': '1', 'FAIL_RESTORE_ARTIFACTS': '1'})
        self.assertLess(result.stderr.index('[npm.install]'), result.stderr.index('[restore.artifacts]'))
        self.assertNotIn('remains stopped', result.stdout + result.stderr)

    def test_terminal_readiness_reports_one_failed_check_without_poll_spam(self):
        for check in ('app-active', 'ingress-active', 'native', 'route', 'https'):
            with self.subTest(check=check):
                self.events.write_text('')
                result = self.failure('readiness.' + check, env={'FAIL_READY': check})
                self.assertEqual(result.stderr.count('BB server ['), 1, result)
                self.assertEqual(self.events.read_text().splitlines().count('wait'), 30)

    def test_write_errors_suppress_native_paths(self):
        self.failure('update.directories', extra='mkdir() { noisy_failure; }')
        self.failure('update.guard-write', extra='mktemp() { noisy_failure; }')
        for kind in ('app', 'ingress'):
            extra = 'bb_write_bb_guard() { return 0; }\n' + '''
mv() {
    if [[ "${*: -1}" == *setup-bb-''' + kind + '''.service ]]; then noisy_failure; else builtin command mv "$@"; fi
}
'''
            self.failure('update.' + kind + '-unit-write', extra=extra)
        self.failure('update.owner-promotion', extra='mv() { if [[ "${*: -1}" == */package-owner ]]; then noisy_failure; else builtin command mv "$@"; fi; }')

    def test_diagnostic_boundary_rejects_arbitrary_labels_and_keeps_stdout_clean(self):
        result = self.run_code('captured=$(bb_server_failure "$UNTRUSTED"); [[ -z "$captured" ]]',
                               env={'UNTRUSTED': SECRET + '\nconfig.locks'})
        self.assertEqual(result.returncode, 0, result)
        self.assertEqual(result.stdout, '')
        self.assertIn('[diagnostic.unknown]', result.stderr)

    def test_real_native_readiness_remembers_failure_without_printing_probe_data(self):
        helper = simple_function(self.source, 'bb_native_app_ready')
        for phase, mock in (
            ('process', 'bb_managed_app_process() { return 1; }'),
            ('health', 'curl() { noisy_failure; }'),
            ('host-status', 'curl() { if [[ "${*: -1}" == */status ]]; then noisy_failure; else printf "{}"; fi; }'),
            ('native', 'curl() { printf "%s" "DO-NOT-LOG-FIXTURE-SECRET"; }'),
        ):
            with self.subTest(phase=phase):
                result = self.run_code('if bb_native_app_ready; then exit 99; fi; bb_server_failure "$BB_SERVER_READY_CHECK"', extra=helper + '\n' + mock)
                self.assertEqual(result.returncode, 0, result)
                self.assertEqual(result.stdout, '')
                self.assertIn('[readiness.' + phase + ']', result.stderr)

    def native_config(self, module):
        self.package.mkdir(exist_ok=True)
        self.seed(str(self.package.relative_to(self.home)) + '/package.json', '{"name":"bb-app"}')
        native = self.package / 'node_modules/fs-native-extensions'
        native.mkdir(parents=True, exist_ok=True)
        (native / 'index.js').write_text(module)
        extra = 'source "$HELPERS"\nprint_error() { printf "ERROR: %s\\n" "$1"; }\nBB_PACKAGE_PATH="$HOME/.local/share/mise/installs/node/24.20.0/lib/node_modules/bb-app"\n'
        return self.run_code('bb_config_merge_native https://fixture.example.ts.net', extra=extra)

    def test_native_config_failure_protocol_and_partial_changes(self):
        good = 'exports.tryLock=()=>true;exports.unlock=()=>{};'
        self.seed('.bb/config.json', '{broken-' + SECRET)
        result = self.native_config(good)
        self.assertEqual(result.returncode, 1)
        self.assertIn('[config.read]', result.stderr)
        result = self.native_config('exports.tryLock=()=>{throw new Error("' + SECRET + '")};exports.unlock=()=>{};')
        self.assertEqual(result.returncode, 1, result)
        self.assertIn('[config.locks]', result.stderr)
        result = self.native_config('exports.tryLock=()=>true;exports.unlock=()=>{throw new Error("' + SECRET + '")};')
        self.assertEqual(result.returncode, 1, result)
        self.assertIn('[config.read]', result.stderr)
        self.assertNotIn('[config.unlock]', result.stderr)
        self.seed('.bb/config.json', '{"config":{"BB_SERVER_PORT":"9999"}}')
        result = self.native_config(good)
        self.assertEqual(result.returncode, 1, result)
        self.assertIn('[config.validate]', result.stderr)
        self.seed('.bb/config.json', '{"config":{}}')
        self.seed('.bb/env.json', '{"env":{"BB_APP_URL":"old","KEY":"' + SECRET + '"}}')
        (self.home / '.bb/.env.json.tmp').mkdir()
        result = self.native_config(good)
        self.assertEqual(result.returncode, 1, result)
        self.assertIn('[config.write]', result.stderr)
        self.assertIn('partial changes may have occurred', result.stderr)
        config = json.loads((self.home / '.bb/config.json').read_text())
        self.assertEqual(config['config']['BB_APP_URL'], 'https://fixture.example.ts.net')
        self.assertEqual(json.loads((self.home / '.bb/env.json').read_text())['env']['KEY'], SECRET)
        (self.home / '.bb/.env.json.tmp').rmdir()
        result = self.native_config('exports.tryLock=()=>true;exports.unlock=()=>{throw new Error("' + SECRET + '")};')
        self.assertEqual(result.returncode, 1, result)
        self.assertIn('[config.unlock]', result.stderr)
        result = self.native_config('console.log("' + SECRET + '");throw new Error("' + SECRET + '");')
        self.assertEqual(result.returncode, 1, result)
        self.assertIn('[config.native-helper]', result.stderr)

    def test_config_wrapper_preserves_exit_status_and_rejects_unknown_output(self):
        extra = r'''
source "$HELPERS"
print_error() { printf 'ERROR: %s\n' "$1"; }
node() {
    printf 'config.locks\nDO-NOT-LOG-FIXTURE-SECRET\n'
    printf 'DO-NOT-LOG-FIXTURE-SECRET\n' >&2
    return 17
}
'''
        result = self.run_code('bb_config_merge_native https://fixture.example.ts.net', extra=extra)
        self.assertEqual(result.returncode, 17, result)
        self.assertEqual(result.stdout, '')
        self.assertIn('[config.native-helper]', result.stderr)

    def test_real_caller_aggregates_failure_and_finishes_logging(self):
        names = re.findall(r'^(\w+)\(\) \{', self.source, re.M)
        stubs = '\n'.join(n + '() { return 0; }' for n in names)
        tail = simple_function(self.source, 'run_setup_tasks')
        start = tail.index("    : 'BEGIN_BB_SERVER_CALLER'")
        caller = 'run_setup_tasks() {\nlocal _bb_selection_status=0 _setup_had_errors=0 _pi_go_ready=0 PI_PROFILE_MUTATIONS_BLOCKED=0\n' + tail[start:]
        validate_function(caller)
        main = simple_function(self.source, 'main')
        extra = stubs + r'''
print_error() { printf 'ERROR: %s\n' "$1"; }
print_warning() { printf '%s\n' "$1"; }
setup_bb_server() { bb_server_failure preflight.tailscale-path; return 1; }
remove_compound_engineering_resources() { printf 'UNRELATED-CONTINUED\n'; }
start_setup_log() { printf 'LOG-START\n'; }
finish_setup_log() { printf 'LOG-FINAL:%s\n' "$1"; return "$1"; }
''' + simple_function(self.source, 'bb_server_failure') + '\n' + caller + '\n' + main
        result = self.run_code('main', extra=extra)
        self.assertEqual(result.returncode, 1, result)
        self.assertIn('[preflight.tailscale-path]', result.stderr)
        self.assertIn('BB server setup incomplete', result.stdout)
        self.assertIn('UNRELATED-CONTINUED', result.stdout)
        self.assertIn('LOG-FINAL:1', result.stdout)
        self.assertNotIn('was preserved', result.stdout)
        logging = '\n'.join(simple_function(self.source, name) for name in ('start_setup_log', 'finish_setup_log'))
        logging += '\nprint_debug() { :; }\nupload_log() { cp -- "$SETUP_LOG_FILE" "$EVENTS.uploaded"; }\n'
        result = self.run_code('main', extra=extra + '\n' + logging, log_paths=True)
        self.assertEqual(result.returncode, 1, result)
        uploaded = Path(str(self.events) + '.uploaded').read_text()
        self.assertIn('[preflight.tailscale-path]', uploaded)
        self.assertIn('BB server setup incomplete', uploaded)
        self.assertIn('UNRELATED-CONTINUED', uploaded)
        self.assertIn('Run log saved to:', uploaded)
        self.assertNotIn(SECRET, uploaded)


if __name__ == '__main__':
    unittest.main()
