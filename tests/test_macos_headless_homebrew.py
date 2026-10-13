import os
from pathlib import Path
import re
import signal
import subprocess
import tempfile
import time
import unittest

from extract_setup_fixture import validate_function

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'mac.sh').read_text()
TOKEN = 'gho_inert_fixture_credential'


def function(name):
    match = re.search(rf'^{name}\(\) ([{{(])\n.*?^[}})]$', SOURCE, re.M | re.S)
    if not match:
        raise AssertionError(f'Missing function: {name}')
    block = match[0]
    validate_function(block)
    return block


class HeadlessHomebrew(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        sandbox = os.environ.get('FIXTURE_NETWORK_SANDBOX')
        if not sandbox:
            raise AssertionError('Use tests/run-fixture-matrix.py; uncontained fixtures are not permitted')
        result = subprocess.run([sandbox, '--assert-inherited-denial'], capture_output=True, text=True, timeout=2)
        if result.returncode:
            raise AssertionError('Inherited fixture network containment unavailable')

    def fixture(self, root, mode='failed'):
        home = root / 'home'
        home.mkdir()
        commands = root / 'bin'
        commands.mkdir()
        gh = commands / 'gh'
        gh.write_text('''#!/bin/bash
printf 'gh:%s\\n' "$*" >> "$HOME/calls"
case "$FIXTURE_GH_MODE" in
    success) printf '%s\\n' "$FIXTURE_TOKEN" ;;
    failed) printf '%s\\n' "$FIXTURE_TOKEN"; printf 'private diagnostic: %s\\n' "$FIXTURE_TOKEN" >&2; exit 1 ;;
    empty) exit 0 ;;
    malformed) printf '%s\\nextra output\\n' "$FIXTURE_TOKEN" ;;
    oversized) printf '%09000d' 0; exec /bin/sleep 60 ;;
    hang|closed-output-hang)
        printf '%s\\n' "$$" > "$HOME/probe-pid"
        trap '' TERM
        if [[ "$FIXTURE_GH_MODE" == closed-output-hang ]]; then
            printf '%s\\n' "$FIXTURE_TOKEN"
            exec 1>&-
        fi
        /bin/sleep 60 &
        printf '%s\\n' "$!" > "$HOME/probe-child-pid"
        wait ;;
    descendant)
        printf '%s\\n' "$$" > "$HOME/probe-pid"
        printf '%s\\n' "$FIXTURE_TOKEN"
        /bin/sleep 60 &
        printf '%s\\n' "$!" > "$HOME/probe-child-pid"
        exit 0 ;;
    *) exit 90 ;;
esac
''')
        brew = commands / 'brew'
        brew.write_text('''#!/bin/bash
printf 'brew:%s\\n' "$*" >> "$HOME/calls"
if [[ "$*" == upgrade ]]; then
    if [[ "${HEADLESS:-}" == 1 ]]; then
        if [[ -z "${HOMEBREW_GITHUB_API_TOKEN:-}" ]]; then
            exec "$FIXTURE_BIN/git" credential-osxkeychain get
        fi
        [[ "$HOMEBREW_GITHUB_API_TOKEN" == "$FIXTURE_TOKEN" ]] || exit 91
    fi
    [[ "${FIXTURE_BREW_FAILURE:-0}" != 1 ]] || exit 7
fi
''')
        git = commands / 'git'
        git.write_text('''#!/bin/bash
printf 'git:%s\\n' "$*" >> "$HOME/calls"
exec "$FIXTURE_BIN/git-credential-osxkeychain" get
''')
        keychain = commands / 'git-credential-osxkeychain'
        keychain.write_text('''#!/bin/bash
printf 'unbounded-keychain-wait\\n' >> "$HOME/calls"
exec /bin/sleep 60
''')
        for command in commands.iterdir():
            command.chmod(0o700)
        env = {'PATH': f'{commands}:/usr/bin:/bin', 'HOME': str(home), 'TMPDIR': str(root),
               'SHELL': '/bin/bash', 'HEADLESS': '1', 'FIXTURE_BIN': str(commands),
               'FIXTURE_GH_MODE': mode, 'FIXTURE_TOKEN': TOKEN}
        return home, commands, env

    def caller(self):
        names = re.findall(r'^([A-Za-z_][A-Za-z_0-9]*)\(\)', SOURCE, re.M)
        code = '\n'.join(f'{name}() {{ :; }}' for name in names) + '''
GREEN= BOLD= NC= GRAY= CYAN=
SETUP_TMUX_PINNED=0
SETUP_BREW_TRUST_FAILURES=0
print_message() { printf '%s\\n' "$*"; }
print_warning() { printf '%s\\n' "$*"; }
print_error() { printf '%s\\n' "$*"; }
print_success() { printf '%s\\n' "$*"; }
whoami() { printf 'fixture-user\\n'; }
is_main_user() { return "${FIXTURE_SECONDARY:-0}"; }
check_dotfiles_access() { return 1; }
setup_dotfiles_deploy_key() { return 1; }
install_xcode_cli_tools() { printf 'provisioning-started\\n' >> "$HOME/calls"; }
start_setup_log() { printf 'log-started\\n'; }
finish_setup_log() { printf 'log-finalized=%s\\n' "$1"; return "$1"; }
tmux() { :; }
/opt/homebrew/bin/brew() { :; }
'''
        selected = ('setup_trim', 'setup_environment_value', 'setup_load_environment',
                    'headless_homebrew_gh_token', 'prepare_headless_homebrew_auth',
                    'list_unresolved_brew_outdated_items', 'opencode_guarded_brew_upgrade',
                    'update_brew', 'run_setup_tasks', 'main')
        for name in selected:
            if name in names:
                code += '\n' + function(name)
        return code + '\nmain\n'

    def run_bash(self, code, env, timeout=3):
        started = time.monotonic()
        child = subprocess.Popen(['/bin/bash', '--noprofile', '--norc', '-c', code],
                                 env=env, cwd=env['HOME'], stdin=subprocess.DEVNULL,
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                 start_new_session=True, text=True, close_fds=True)
        try:
            stdout, stderr = child.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            os.killpg(child.pid, signal.SIGKILL)
            stdout, stderr = child.communicate()
            calls = (Path(env['HOME']) / 'calls').read_text()
            raise AssertionError('Setup stalled instead of refusing before provisioning. Fixture calls: ' + calls) from None
        self.assertNotIn(TOKEN, stdout + stderr, 'Credential leaked into diagnostics')
        return subprocess.CompletedProcess(child.args, child.returncode, stdout, stderr), time.monotonic() - started

    def test_failed_login_blocks_before_brew_keychain_wait_and_finalizes_log(self):
        with tempfile.TemporaryDirectory() as tmp:
            home, _, env = self.fixture(Path(tmp))
            result, _ = self.run_bash(self.caller(), env)
            calls = (home / 'calls').read_text().splitlines() if (home / 'calls').exists() else []
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            self.assertEqual(calls, ['gh:auth token --hostname github.com'])
            self.assertIn('log-finalized=1', result.stdout)
            self.assertIn('headless Homebrew', result.stdout)
            self.assertNotIn('provisioning-started', calls)
            self.assertNotIn('unbounded-keychain-wait', calls)

    def assert_no_live_probe(self, home):
        for name in ('probe-pid', 'probe-child-pid'):
            file = home / name
            if not file.exists():
                continue
            pid = int(file.read_text())
            state = subprocess.run(['/bin/ps', '-o', 'stat=', '-p', str(pid)],
                                   capture_output=True, text=True, timeout=2).stdout.strip()
            self.assertTrue(not state or state.startswith('Z'), f'Fixture probe left running: {pid} ({state})')

    def test_success_exports_once_before_provisioning_and_preserves_credentials(self):
        with tempfile.TemporaryDirectory() as tmp:
            home, _, env = self.fixture(Path(tmp), 'success')
            config = home / '.config/gh'
            config.mkdir(parents=True)
            login = config / 'hosts.yml'
            login.write_text('github.com:\n    user: fixture-active-account\n')
            envfile = home / '.env.local'
            envfile.write_text('HEADLESS=1\n# Existing account configuration remains untouched.\n')
            env.update({'GH_CONFIG_DIR': str(config), 'GH_HOST': 'other.invalid', 'GH_DEBUG': 'api'})
            before = {p: (p.read_bytes(), p.stat().st_mode) for p in (login, envfile)}
            result, _ = self.run_bash(self.caller(), env)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            calls = (home / 'calls').read_text().splitlines()
            self.assertEqual(calls.count('gh:auth token --hostname github.com'), 1)
            self.assertLess(calls.index('gh:auth token --hostname github.com'), calls.index('provisioning-started'))
            self.assertIn('brew:upgrade', calls)
            self.assertNotIn('unbounded-keychain-wait', calls)
            self.assertIn('log-finalized=0', result.stdout)
            self.assertEqual(before, {p: (p.read_bytes(), p.stat().st_mode) for p in before})
            for p in home.rglob('*'):
                if p.is_file():
                    self.assertNotIn(TOKEN.encode(), p.read_bytes(), f'Credential written to fixture file: {p.name}')

    def test_real_ten_second_timeout_stops_before_provisioning_and_cleans_children(self):
        with tempfile.TemporaryDirectory() as tmp:
            home, _, env = self.fixture(Path(tmp), 'hang')
            result, elapsed = self.run_bash(self.caller(), env, timeout=14)
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            self.assertGreaterEqual(elapsed, 10)
            self.assertLess(elapsed, 12)
            self.assertIn('timed out after 10 seconds', result.stdout)
            self.assertIn('log-finalized=1', result.stdout)
            self.assertEqual((home / 'calls').read_text().splitlines(), ['gh:auth token --hostname github.com'])
            self.assert_no_live_probe(home)

    def test_missing_gh_fails_early_without_fallback(self):
        with tempfile.TemporaryDirectory() as tmp:
            home, commands, env = self.fixture(Path(tmp))
            (commands / 'gh').unlink()
            env['PATH'] = str(commands)
            result, _ = self.run_bash(self.caller(), env)
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            self.assertIn('gh CLI unavailable', result.stdout)
            self.assertIn('gh auth login --hostname github.com', result.stdout)
            self.assertIn('log-finalized=1', result.stdout)
            self.assertFalse((home / 'calls').exists())

    def test_exact_headless_mode_and_dotenv_selection(self):
        for value in ('', '0', 'true', 'false', '01'):
            with self.subTest(value=value), tempfile.TemporaryDirectory() as tmp:
                home, _, env = self.fixture(Path(tmp))
                env['HEADLESS'] = value
                result, _ = self.run_bash(self.caller(), env)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                calls = (home / 'calls').read_text().splitlines()
                self.assertIn('provisioning-started', calls)
                self.assertIn('brew:upgrade', calls)
                self.assertFalse(any(c.startswith('gh:') for c in calls))
        with tempfile.TemporaryDirectory() as tmp:
            home, _, env = self.fixture(Path(tmp))
            env['HEADLESS'] = '0'
            (home / '.env.local').write_text('HEADLESS=1\n')
            result, _ = self.run_bash(self.caller(), env)
            self.assertEqual(result.returncode, 1)
            self.assertEqual((home / 'calls').read_text().splitlines(), ['gh:auth token --hostname github.com'])

    def test_secondary_account_is_also_guarded_before_any_work(self):
        with tempfile.TemporaryDirectory() as tmp:
            home, _, env = self.fixture(Path(tmp))
            env['FIXTURE_SECONDARY'] = '1'
            result, _ = self.run_bash(self.caller(), env)
            self.assertEqual(result.returncode, 1)
            self.assertEqual((home / 'calls').read_text().splitlines(), ['gh:auth token --hostname github.com'])
            self.assertIn('log-finalized=1', result.stdout)

    def test_explicit_homebrew_override_is_preserved_without_gh_lookup(self):
        with tempfile.TemporaryDirectory() as tmp:
            home, _, env = self.fixture(Path(tmp))
            env['HOMEBREW_GITHUB_API_TOKEN'] = TOKEN
            result, _ = self.run_bash(self.caller(), env)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            calls = (home / 'calls').read_text().splitlines()
            self.assertFalse(any(c.startswith('gh:') for c in calls))
            self.assertNotIn('unbounded-keychain-wait', calls)

    def test_unusable_output_or_override_is_controlled_and_never_exposed(self):
        for mode in ('empty', 'malformed', 'oversized'):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory() as tmp:
                home, _, env = self.fixture(Path(tmp), mode)
                result, _ = self.run_bash(self.caller(), env)
                self.assertEqual(result.returncode, 1)
                self.assertIn('empty or malformed', result.stdout)
                self.assertIn('log-finalized=1', result.stdout)
                self.assertEqual((home / 'calls').read_text().splitlines(), ['gh:auth token --hostname github.com'])
        for value in (' ', TOKEN + '\nextra', TOKEN + '\r', 'x' * 9000):
            with self.subTest(override_shape=len(value)), tempfile.TemporaryDirectory() as tmp:
                home, _, env = self.fixture(Path(tmp), 'success')
                env['HOMEBREW_GITHUB_API_TOKEN'] = value
                result, _ = self.run_bash(self.caller(), env)
                self.assertEqual(result.returncode, 1)
                self.assertIn('empty or malformed', result.stdout)
                self.assertFalse((home / 'calls').exists())
                if value.strip():
                    self.assertNotIn(value, result.stdout + result.stderr)

    def test_xtrace_is_restored_without_exposing_credentials(self):
        with tempfile.TemporaryDirectory() as tmp:
            _, _, env = self.fixture(Path(tmp), 'success')
            code = function('headless_homebrew_gh_token') + '\n' + function('prepare_headless_homebrew_auth') + '''
print_debug() { :; }; print_error() { printf '%s\\n' "$*"; }
set -x
prepare_headless_homebrew_auth || exit 1
case "$-" in *x*) printf 'tracing-restored\\n' ;; *) exit 99 ;; esac
'''
            result, _ = self.run_bash(code, env)
            self.assertEqual(result.returncode, 0)
            self.assertIn('tracing-restored', result.stdout)

    def test_internal_supervisor_bounds_open_or_closed_stdout_and_descendants(self):
        for mode in ('hang', 'closed-output-hang', 'descendant'):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory() as tmp:
                home, commands, env = self.fixture(Path(tmp), mode)
                env['FIXTURE_GH'] = str(commands / 'gh')
                code = function('headless_homebrew_gh_token') + '''
if token=$(headless_homebrew_gh_token "$FIXTURE_GH" 0.3); then exit 99; else exit $?; fi
'''
                result, elapsed = self.run_bash(code, env)
                self.assertEqual(result.returncode, 124, result.stdout + result.stderr)
                self.assertGreaterEqual(elapsed, 0.3)
                self.assertLess(elapsed, 2)
                self.assert_no_live_probe(home)

    def test_internal_supervisor_failures_and_child_environment(self):
        with tempfile.TemporaryDirectory() as tmp:
            _, commands, env = self.fixture(Path(tmp), 'success')
            gh = commands / 'gh'
            gh.write_text('''#!/bin/bash
[[ "$*" == 'auth token --hostname github.com' ]] || exit 90
[[ "$GH_CONFIG_DIR" == "$FIXTURE_CONFIG" && "$GH_HOST" == 'other.invalid' ]] || exit 91
[[ "$GH_PROMPT_DISABLED" == 1 && "$GH_NO_UPDATE_NOTIFIER" == 1 && "$GH_NO_EXTENSION_UPDATE_NOTIFIER" == 1 && -z "${GH_DEBUG+x}" ]] || exit 92
if read -r input; then exit 93; fi
printf '%s\\n' "$FIXTURE_TOKEN"
''')
            env.update({'FIXTURE_GH': str(gh), 'GH_CONFIG_DIR': tmp + '/selected gh',
                        'FIXTURE_CONFIG': tmp + '/selected gh', 'GH_HOST': 'other.invalid',
                        'GH_DEBUG': 'api', 'PERL5OPT': '-Mnot_a_real_module', 'PERL5LIB': tmp + '/foreign'})
            code = function('headless_homebrew_gh_token') + '''
if token=$(headless_homebrew_gh_token "$FIXTURE_GH" 1); then
    [[ "$token" == "$FIXTURE_TOKEN" ]]
else exit $?; fi
'''
            result, _ = self.run_bash(code, env)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            for argument in ('0', '11', 'invalid'):
                result, _ = self.run_bash(function('headless_homebrew_gh_token') +
                                          f'\nheadless_homebrew_gh_token "$FIXTURE_GH" {argument}\n', env)
                self.assertEqual(result.returncode, 70)

    def test_native_probe_launch_failure_is_controlled(self):
        with tempfile.TemporaryDirectory() as tmp:
            home, commands, env = self.fixture(Path(tmp))
            (commands / 'gh').write_text('#!/missing-fixture-interpreter\n')
            result, _ = self.run_bash(self.caller(), env)
            self.assertEqual(result.returncode, 1)
            self.assertIn('gh could not retrieve', result.stdout)
            self.assertIn('log-finalized=1', result.stdout)
            self.assertFalse((home / 'calls').exists())
            self.assertEqual(result.stderr, '')

    def test_ignored_sigchld_does_not_release_owned_probe_identity(self):
        for mode, expected in (('success', 0), ('hang', 124)):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory() as tmp:
                home, commands, env = self.fixture(Path(tmp), mode)
                env['FIXTURE_GH'] = str(commands / 'gh')
                code = function('headless_homebrew_gh_token') + '''
trap '' CHLD
if token=$(headless_homebrew_gh_token "$FIXTURE_GH" 0.3); then
    [[ "$token" == "$FIXTURE_TOKEN" ]]
else exit $?; fi
'''
                result, _ = self.run_bash(code, env)
                self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
                self.assert_no_live_probe(home)

    def test_missing_supervisor_refuses_without_credential_lookup(self):
        with tempfile.TemporaryDirectory() as tmp:
            home, _, env = self.fixture(Path(tmp), 'success')
            guard = function('prepare_headless_homebrew_auth').replace('/usr/bin/perl', tmp + '/absent-perl')
            validate_function(guard)
            code = guard + '''
print_error() { printf '%s\\n' "$*"; }
prepare_headless_homebrew_auth
'''
            result, _ = self.run_bash(code, env)
            self.assertEqual(result.returncode, 1)
            self.assertIn('native credential supervision failed', result.stdout)
            self.assertFalse((home / 'calls').exists())

    def test_interrupted_supervisor_cleans_only_its_probe(self):
        with tempfile.TemporaryDirectory() as tmp:
            home, commands, env = self.fixture(Path(tmp))
            (commands / 'gh').write_text('''#!/bin/bash
printf '%s\\n' "$$" > "$HOME/probe-pid"
/bin/sleep 60 &
printf '%s\\n' "$!" > "$HOME/probe-child-pid"
kill -TERM "$PPID"
wait
''')
            env['FIXTURE_GH'] = str(commands / 'gh')
            code = function('headless_homebrew_gh_token') + '''
if token=$(headless_homebrew_gh_token "$FIXTURE_GH" 1); then exit 99; else exit $?; fi
'''
            result, _ = self.run_bash(code, env)
            self.assertEqual(result.returncode, 143, result.stdout + result.stderr)
            self.assert_no_live_probe(home)

    def test_preflight_success_does_not_erase_real_homebrew_failure(self):
        with tempfile.TemporaryDirectory() as tmp:
            home, _, env = self.fixture(Path(tmp), 'success')
            env['FIXTURE_BREW_FAILURE'] = '1'
            result, _ = self.run_bash(self.caller(), env)
            self.assertEqual(result.returncode, 1)
            self.assertIn('brew:upgrade', (home / 'calls').read_text().splitlines())
            self.assertIn('upgrade=7', result.stdout)
            self.assertIn('log-finalized=1', result.stdout)


if __name__ == '__main__':
    unittest.main(verbosity=2)
