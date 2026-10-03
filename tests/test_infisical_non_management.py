"""TASK-69: real caller/logging seams, inert dependencies, private legacy state.

Run only through run-fixture-matrix.py. No whole setup file is evaluated.
"""
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

from extract_setup_fixture import validate_function

ROOT = Path(__file__).resolve().parents[1]
APT = ('ubuntu.sh', 'pi.sh', 'wsl.sh')
BREW = ('mac.sh', 'bazzite.sh')
PWSH = os.environ.get('PWSH_BIN')


def function(source, name):
    match = re.search(r'^' + re.escape(name) + r'\(\) \{\n.*?^\}\n', source, re.M | re.S)
    if not match:
        raise AssertionError('Missing fixture definition: ' + name)
    validate_function(match[0])
    return match[0]


def seed(home, residual):
    # Not live package-manager paths. Malformed/unreadable installation metadata
    # must not become a prerequisite; credentials and unrelated data also survive.
    files = {'.env.local': 'UNCHANGED=literal-fixture\n', 'project/data': 'keep',
             '.config/doppler/config.yaml': 'existing-doppler-state'}
    if residual:
        files.update({'.local/bin/infisical': 'custom binary sentinel',
                      '.infisical/config.json': '{malformed',
                      'apt/sources.list.d/infisical.list': 'stale source sentinel',
                      'homebrew/infisical/get-cli/INSTALL_RECEIPT.json': '{malformed',
                      'registry/infisical.infisical': 'unreadable registration sentinel'})
    for name, value in files.items():
        path = home / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(value)
        path.chmod(0o600)
    if residual:
        (home / '.infisical/link').symlink_to('../project/data')


def snapshot(home):
    return {str(p.relative_to(home)): (p.lstat().st_mode,
            os.readlink(p) if p.is_symlink() else p.read_bytes() if p.is_file() else None)
            for p in home.rglob('*')}


def bash_fixture(name):
    source = (ROOT / name).read_text()
    names = set(re.findall(r'^([A-Za-z_][A-Za-z_0-9]*)\(\) [\{(]', source, re.M))
    # Dependencies are inert before the real task dispatcher is invoked. Record
    # every request, including obsolete retirement requests on the red source.
    code = '\n'.join(f'{n}() {{ record request:{n}; }}' for n in sorted(names))
    retained = ['run_setup_tasks', 'main', 'install_secrets_manager']
    if name in APT:
        retained.append('install_doppler')
    if name == 'wsl.sh':
        retained.append('fail_unsupported_headless')
    elif name != 'mac.sh':
        retained.append('headless_platform_gate')
    code += '\n' + '\n'.join(function(source, n) for n in retained)
    code += r'''
record() { printf '%s\n' "$*" >> "$EVENTS"; }
check_dotfiles_access() { return 1; }
setup_dotfiles_deploy_key() { return 1; }
whoami() { printf 'fixture\n'; }
unzip() { :; }
is_main_user() { [[ "$PERSONA" == primary ]]; }
/opt/homebrew/bin/brew() { record shellenv; }
bb_server_selection() { return 1; }
print_warning() { record "warning:$*"; }
print_error() { record "error:$*"; }
command() {
    record "command:$*"
    case "$*" in
        '-v doppler') [[ "$DOPPLER_PRESENT" == 1 ]] ;;
        '-v infisical') [[ "$RESIDUAL" == 1 ]] ;;
        '-v brew') return 0 ;;
        *) return 1 ;;
    esac
}
curl() { record "curl:$*"; printf 'inert-signing-key\n'; }
sudo() { record "sudo:$*"; }
can_sudo() { return 0; }
env_local_flag_is_one() { [[ "${!1}" == 1 ]]; }
uname() { printf 'Linux\n'; }
is_wsl_environment() { return 1; }
is_container_environment() { [[ "$CONTAINER" == 1 ]]; }
ensure_brew_item_trusted() { record doppler-trust; [[ "$TRUST" == 1 ]]; }
ensure_brew_formula_trusted() { record doppler-trust; [[ "$TRUST" == 1 ]]; }
install_opencode_cli() { record opencode; [[ "$FAILURE" != opencode ]]; }
fix_dpkg_and_broken_dependencies() { record repair; }
update_dependencies() { record apt-update; [[ "$FAILURE" != update ]]; }
update_and_install_core() { record core; }
update_packages() { record final-update; [[ "$FAILURE" != update ]]; }
update_brew() { record brew-update; [[ "$FAILURE" != update ]]; }
remove_compound_engineering_resources() { record unrelated; }
check_pending_reboot() { record pending-reboot; }
start_setup_log() { record log-start; }
finish_setup_log() { record "final:$1"; return "$1"; }
'''
    # A retirement dependency may neither succeed as a hidden prerequisite nor
    # fail setup; do not execute its old native metadata/source helper.
    for n in names:
        if 'infisical' in n.lower():
            code += f'\n{n}() {{ record forbidden:{n}; return 1; }}'
    for cmd in ('apt-get', 'dpkg', 'dpkg-query', 'brew', 'infisical', 'systemctl',
                'launchctl', 'npm', 'bun', 'pi', 'bb', 'chezmoi', 'kill', 'pkill'):
        code += f'\n{cmd}() {{ record forbidden:{cmd}:"$*"; return 99; }}'
    code += r'''
brew() { record "brew:$*"; }
'''
    return code + '\nmain\n'


class NonManagement(unittest.TestCase):
    def run_bash(self, name, work, residual, failure='none', present='0', persona='primary',
                 headless='0', container='0', readiness='ready', trust='1'):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            home = root / 'home'; home.mkdir()
            seed(home, residual)
            before = snapshot(home)
            events = root / 'events'
            env = {'PATH': '/usr/bin:/bin', 'HOME': str(home), 'EVENTS': str(events),
                   'WORK_MACHINE': work, 'RESIDUAL': str(int(residual)),
                   'DOPPLER_PRESENT': present, 'FAILURE': failure,
                   'PERSONA': persona, 'SHELL': '/bin/bash', 'HEADLESS': headless,
                   'CONTAINER': container, 'MACOS_DEVELOPER_TOOLS_STATE': readiness, 'TRUST': trust}
            gated = headless == '1' and (name == 'wsl.sh' or container == '1')
            failed = (failure != 'none' or gated
                      or (name == 'bazzite.sh' and work == '0' and trust == '0'))
            # Repeat against the same preserved state; absence must stay a no-op.
            for repeat in range(2):
                events.write_text('')
                result = subprocess.run(['/bin/bash', '--noprofile', '--norc', '-c', bash_fixture(name)],
                                        cwd=root, env=env, capture_output=True, text=True, timeout=20)
                calls = events.read_text().splitlines()
                with self.subTest(repeat=repeat):
                    self.assertEqual(snapshot(home), before)
                    self.assertNotIn('infisical', '\n'.join(calls).lower())
                    self.assertNotIn('infisical', (result.stdout + result.stderr).lower())
                    self.assertFalse(any(c.startswith('forbidden:') for c in calls), calls)
                    self.assertEqual(result.returncode, int(failed), result.stdout + result.stderr)
                    self.assertEqual(result.stderr, '')
                    self.assertEqual(calls[0], 'log-start')
                    self.assertEqual(calls[-1], f'final:{int(failed)}')
                    if not gated:
                        self.assertLess(calls.index('unrelated'), calls.index('pending-reboot'))
            return calls

    def test_apt_callers_leave_legacy_state_unmanaged_and_keep_eligible_updates(self):
        for name in APT:
            for work in ('0', '1'):
                for residual in (False, True):
                    with self.subTest(platform=name, work=work, residual=residual):
                        calls = self.run_bash(name, work, residual)
                        self.assertIn('core', calls)
                        if name != 'wsl.sh':
                            self.assertLess(calls.index('apt-update'), calls.index('core'))
                        if name == 'ubuntu.sh':
                            self.assertLess(calls.index('repair'), calls.index('apt-update'))
                        self.assertEqual('sudo:apt-get install -y doppler' in calls, work == '0')

    def test_homebrew_callers_leave_legacy_state_unmanaged_without_expanding_account_scope(self):
        for name in BREW:
            for persona in (('primary', 'secondary') if name == 'mac.sh' else ('primary',)):
                for work in ('0', '1'):
                    for residual in (False, True):
                        with self.subTest(platform=name, persona=persona, work=work, residual=residual):
                            calls = self.run_bash(name, work, residual, persona=persona)
                            self.assertEqual('brew-update' in calls, persona == 'primary')
                            installs = [c for c in calls if c.startswith('brew:install dopplerhq/')]
                            self.assertEqual(len(installs), int(work == '0' and persona == 'primary'))
                            if persona == 'secondary':
                                self.assertNotIn('request:install_homebrew', calls)
                                self.assertNotIn('request:install_core_packages', calls)

    def test_bash_required_failures_survive_later_work_reboot_reporting_and_finalization(self):
        for name in (*APT, *BREW):
            for failure in ('opencode', 'update'):
                with self.subTest(platform=name, failure=failure):
                    calls = self.run_bash(name, '1', True, failure=failure)
                    update = 'brew-update' if name in BREW else 'final-update' if name == 'wsl.sh' else 'apt-update'
                    self.assertLess(calls.index(update), calls.index('pending-reboot'))

    def run_windows(self, work, residual, failure='none', present='0', headless='0'):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            home = root / 'home'; home.mkdir()
            seed(home, residual)
            before = snapshot(home)
            events = root / 'events'
            env = dict(os.environ, HOME=str(home), USERPROFILE=str(home),
                       XDG_CONFIG_HOME=str(root / 'config'), XDG_DATA_HOME=str(root / 'data'),
                       XDG_CACHE_HOME=str(root / 'cache'), EVENTS=str(events),
                       FIXTURE_LOG_DIR=str(root / 'logs'), WORK_MACHINE=work,
                       DOPPLER_PRESENT=present, FAILURE=failure, HEADLESS=headless)
            for repeat in range(2):
                events.write_text('')
                result = subprocess.run([PWSH, '-NoLogo', '-NoProfile', '-NonInteractive', '-File',
                                         str(ROOT / 'tests/infisical-non-management-windows.ps1'),
                                         str(ROOT / 'win.ps1')], cwd=root, env=env,
                                        capture_output=True, text=True, timeout=20)
                calls = events.read_text().splitlines()
                with self.subTest(repeat=repeat):
                    self.assertEqual(snapshot(home), before)
                    self.assertNotIn('infisical', '\n'.join(calls).lower())
                    self.assertNotIn('infisical', (result.stdout + result.stderr).lower())
                    self.assertEqual(result.returncode, int(failure != 'none' or headless == '1'),
                                     result.stdout + result.stderr)
                    self.assertEqual(calls[0], 'log-start')
                    self.assertEqual(calls.count('finalized'), 1)
            return calls

    @unittest.skipUnless(PWSH, 'Set PWSH_BIN; Linux PowerShell is not native Windows evidence')
    def test_windows_leaves_legacy_state_unmanaged_and_reaches_updates(self):
        for work in ('0', '1'):
            for residual in (False, True):
                with self.subTest(work=work, residual=residual):
                    calls = self.run_windows(work, residual)
                    self.assertIn('unrelated', calls)
                    self.assertLess(calls.index('winget-update'), calls.index('windows-update'))
                    self.assertLess(calls.index('windows-update'), calls.index('pending-reboot'))
                    self.assertEqual(calls[-1], 'finalized')
                    installs = [c for c in calls if c.startswith('winget:install -e --id doppler.doppler ')]
                    self.assertEqual(len(installs), int(work == '0'))

    @unittest.skipUnless(PWSH, 'Set PWSH_BIN; Linux PowerShell is not native Windows evidence')
    def test_windows_independent_failure_and_opencode_deferral_survive_finalization(self):
        for failure in ('permissions', 'opencode'):
            with self.subTest(failure=failure):
                calls = self.run_windows('1', True, failure=failure)
                self.assertEqual('winget-update' in calls, failure != 'opencode')
                self.assertLess(calls.index('unrelated'), calls.index('windows-update'))
                self.assertLess(calls.index('windows-update'), calls.index('pending-reboot'))
                self.assertEqual(calls[-2:], ['finalized', 'failed'])

    def test_mac_work_ignores_legacy_readiness_but_exact_headless_gates_remain(self):
        calls = self.run_bash('mac.sh', '0', True, readiness='unverified')
        self.assertIn('brew-update', calls)
        self.assertTrue(any(c.startswith('brew:install') for c in calls))
        for name in (*APT, 'bazzite.sh'):
            for headless in ('1', 'true'):
                with self.subTest(platform=name, headless=headless):
                    calls = self.run_bash(name, '1', True, headless=headless, container='1')
                    self.assertEqual('unrelated' in calls, headless != '1')
                    if headless == '1':
                        for event in ('apt-update', 'core', 'brew-update', 'final-update', 'pending-reboot'):
                            self.assertNotIn(event, calls)

    def test_bash_personal_doppler_presence_and_trust_are_not_bypassed(self):
        for name in (*APT, *BREW):
            for work in ('0', '1'):
                with self.subTest(platform=name, work=work):
                    calls = self.run_bash(name, work, True, present='1')
                    self.assertFalse(any('install' in c and 'doppler' in c for c in calls))
                    self.assertEqual('command:-v doppler' in calls, work == '0')
            if name in BREW:
                calls = self.run_bash(name, '0', True, trust='0')
                self.assertIn('doppler-trust', calls)
                self.assertFalse(any(c.startswith('brew:install') for c in calls))

    @unittest.skipUnless(PWSH, 'Set PWSH_BIN; Linux PowerShell is not native Windows evidence')
    def test_windows_doppler_presence_and_exact_headless_boundary_remain(self):
        for work in ('0', '1'):
            calls = self.run_windows(work, True, present='1')
            self.assertFalse(any(c.startswith('winget:install') for c in calls))
            self.assertEqual('command:doppler' in calls, work == '0')
        for headless in ('1', 'true'):
            calls = self.run_windows('1', True, headless=headless)
            self.assertEqual('unrelated' in calls, headless != '1')
            if headless == '1':
                for event in ('winget-update', 'windows-update', 'pending-reboot'):
                    self.assertNotIn(event, calls)
            self.assertEqual(calls[-2:] if headless == '1' else calls[-1:],
                             ['finalized', 'failed'] if headless == '1' else ['finalized'])

    def test_entry_points_have_no_infisical_specific_operations(self):
        for name in (*APT, *BREW, 'win.ps1'):
            with self.subTest(platform=name):
                self.assertNotIn('infisical', (ROOT / name).read_text().lower())


if __name__ == '__main__':
    unittest.main(verbosity=2)
