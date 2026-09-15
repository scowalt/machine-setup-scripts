"""Extracted headless preflight and wrapper fixtures; no real CLI/services/setup."""
import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ('mac.sh', 'ubuntu.sh', 'pi.sh', 'bazzite.sh')
MARKER = 'Managed by scowalt machine setup: headless-paseo-daemon'


def extract(script, function):
    text = (ROOT / script).read_text()
    start = text.index(function + '() {')
    return text[start:text.index('\n}\n', start) + 2]


class HeadlessProvenanceTests(unittest.TestCase):
    def test_wrapper_overrides_inherited_provenance_with_its_validated_exec_path(self):
        for script in SCRIPTS:
            with self.subTest(script=script), tempfile.TemporaryDirectory(prefix='paseo-provenance-') as temp:
                root = Path(temp)
                home = root / 'home'
                home.mkdir(mode=0o700)
                cli = root / 'retained cli'
                cli.write_text('#!/bin/bash\nprintf "provenance:%s\\nargs:%s\\n" "$PASEO_SETUP_CLI" "$*"\n')
                cli.chmod(0o700)
                wrapper = home / '.local/bin/paseo-daemon-start'
                wrapper.parent.mkdir(parents=True)
                # A valid old eight-line owner migrates once, then becomes idempotent.
                quote = lambda value: "'" + str(value).replace("'", "'\\''") + "'"
                wrapper.write_text(f'#!/bin/bash\n# {MARKER}\nset -euo pipefail\nexport HOME={quote(home)}\n'
                                   f"export PATH='/usr/bin:/bin'\n[[ -x '/bin/true' ]] || exit 127\n"
                                   f"[[ -x {quote(cli)} ]] || exit 127\nexec {quote(cli)} daemon start --foreground --listen '127.0.0.1:6767'\n")
                wrapper.chmod(0o700)
                fixture = root / 'writer.sh'
                fixture.write_text('set -eu\nprint_error() { return 1; }; print_success() { :; }; print_debug() { :; }\n'
                                   'paseo_effective_service_path() { printf /usr/bin:/bin; }\n'
                                   "paseo_resolve_listen_target() { PASEO_LISTEN_TARGET='127.0.0.1:6767'; }\n" +
                                   extract(script, 'paseo_shell_quote') + '\n' + extract(script, 'write_paseo_daemon_wrapper') + '\n' +
                                   'write_paseo_daemon_wrapper\n[[ "$PASEO_DAEMON_WRAPPER_CHANGED" == 1 ]]\n'
                                   'write_paseo_daemon_wrapper\n[[ "$PASEO_DAEMON_WRAPPER_CHANGED" == 0 ]]\n')
                env = {'PATH': os.environ['PATH'], 'HOME': str(home), 'PASEO_MANAGED_MARKER': MARKER,
                       'PASEO_VALIDATED_CMD': str(cli), 'PASEO_VALIDATED_NODE': '/bin/true',
                       'PASEO_SETUP_CLI': '/untrusted/inherited-cli'}
                result = subprocess.run(['bash', str(fixture)], env=env, cwd=root, capture_output=True, text=True, timeout=15)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                lines = wrapper.read_text().splitlines()
                self.assertEqual(len(lines), 9)
                self.assertEqual(shlex.split(lines[7]), ['export', 'PASEO_SETUP_CLI=' + str(cli)])
                self.assertEqual(shlex.split(lines[8])[1], str(cli))
                # Execute only the generated wrapper's inert, test-owned CLI.
                result = subprocess.run(['bash', str(wrapper)], env=env, cwd=root, capture_output=True, text=True, timeout=15)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.splitlines(), ['provenance:' + str(cli),
                    'args:daemon start --foreground --listen 127.0.0.1:6767'])

    def test_headless_checks_ownership_before_any_install_cleanup_or_restart(self):
        for script in SCRIPTS:
            for scenario in ('healthy', 'deferred', 'failed', 'not-headless', 'native-gate', 'wrong-platform', 'no-canary'):
                if scenario == 'no-canary' and script != 'mac.sh':
                    continue
                with self.subTest(script=script, scenario=scenario), tempfile.TemporaryDirectory(prefix='paseo-owner-gate-') as temp:
                    root = Path(temp)
                    fixture = root / 'gate.sh'
                    code = '''set -eu
record() { printf '%s\\n' "$*" >> "$CALLS"; }
print_error() { :; }; print_success() { :; }; print_warning() { :; }
uname() { printf '%s\\n' "$PLATFORM"; }
paseo_native_linux_preflight() { record native; [[ "$SCENARIO" != native-gate ]]; }
paseo_macos_preflight() { record native; [[ "$SCENARIO" != native-gate ]]; }
paseo_existing_managed_service_check() { record existing; }
configure_paseo_muse_profile() {
    [[ "$#" == 1 && "$1" == verify-owner ]] || return 99
    record "owner:$1"
    PASEO_MUSE_DEFER_DAEMON_SETUP=0
    case "$SCENARIO" in
        deferred) PASEO_MUSE_DEFER_DAEMON_SETUP=1 ;;
        failed) PASEO_MUSE_DEFER_DAEMON_SETUP=1; return 1 ;;
    esac
}
'''
                    inert = ('install_paseo_cli', 'paseo_resolve_listen_target', 'stop_existing_paseo_daemon',
                             'paseo_listener_target_available', 'write_paseo_daemon_wrapper',
                             'install_paseo_systemd_user_service', 'install_paseo_launchdaemon',
                             'paseo_service_owner_check', 'wait_for_paseo_health', 'paseo_listener_audit',
                             'cleanup_paseo_managed_service', 'cleanup_surplus_paseo_clis')
                    code += '\n'.join(name + '() { record ' + name + '; }' for name in inert)
                    code += '\npaseo_linux_service_pid() { printf 4200; }; paseo_macos_service_pid() { printf 4200; }\n'
                    code += extract(script, 'setup_headless_paseo_daemon') + '\nsetup_headless_paseo_daemon\n'
                    fixture.write_text(code)
                    calls = root / 'calls'
                    env = {'PATH': os.environ['PATH'], 'HOME': temp, 'CALLS': str(calls), 'SCENARIO': scenario,
                           'PLATFORM': 'other' if scenario == 'wrong-platform' else ('Darwin' if script == 'mac.sh' else 'Linux'),
                           'HEADLESS': '0' if scenario == 'not-headless' else '1',
                           'PASEO_MACOS_HEADLESS_CANARY': '0' if scenario == 'no-canary' else '1'}
                    result = subprocess.run(['bash', str(fixture)], env=env, cwd=root, capture_output=True, text=True, timeout=15)
                    events = calls.read_text().splitlines() if calls.exists() else []
                    self.assertEqual(result.returncode, 1 if scenario in ('failed', 'native-gate', 'wrong-platform') else 0,
                                     result.stdout + result.stderr)
                    if scenario == 'healthy':
                        self.assertEqual(events[:3], ['native', 'existing', 'owner:verify-owner'])
                        self.assertLess(events.index('owner:verify-owner'), events.index('install_paseo_cli'))
                        self.assertIn('stop_existing_paseo_daemon', events)
                        self.assertIn('write_paseo_daemon_wrapper', events)
                        self.assertIn('cleanup_surplus_paseo_clis', events)
                    else:
                        self.assertFalse(any(event in inert for event in events), events)
                        if scenario in ('deferred', 'failed'):
                            self.assertIn('owner:verify-owner', events)
                        else:
                            self.assertNotIn('owner:verify-owner', events)


if __name__ == '__main__':
    unittest.main()
