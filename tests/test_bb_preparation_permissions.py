"""Arcane regression: real dotfiles callers + native apply + inert preparation.

No real source, lifecycle, network, user config or installed BB is executed.
"""
import json
import re
import subprocess
import sys
import unittest
from setup_policy_fixture import bash_maintenance

from test_bb_dotfiles_umask import CHEZMOI, CHEZMOI_FIXTURE, GIT_FIXTURE, function
import test_bb_machine_preparation as preparation
from test_bb_machine_preparation import SCRIPTS, SOURCES, snapshot


class PreparationPermissions(unittest.TestCase):
    def fixture(self, platform):
        case = preparation.Preparation()
        case.setUp()
        self.addCleanup(case.doCleanups)
        source = SOURCES[platform]
        helpers = [preparation.BLOCK, function(SOURCES['ubuntu'], 'bb_server_selection')]
        helpers += [function(source, n) for n in ['initialize_chezmoi', 'update_chezmoi']]
        if platform == 'pi':
            helpers.append(function(source, 'apply_chezmoi_config'))
            apply = 'apply_chezmoi_config; result=$?'
        else:
            main = source[source.index('\nrun_setup_tasks() {'):]
            apply = re.search(r'^        if ! [^\n]*chezmoi apply --force; then\n.*?^        fi$', main, re.M | re.S).group()
            apply = '_setup_had_errors=0\n' + apply + '\nresult=$_setup_had_errors'
        (case.root / 'dotfiles.sh').write_text(bash_maintenance() + '\n'.join(helpers))
        # Reuse the shared argv-checking fixture, including Pi's verbose apply.
        # This suite uses native mode only for full apply, never init/update.
        for name, body in [('chezmoi', CHEZMOI_FIXTURE), ('git', GIT_FIXTURE)]:
            case.write_exe(name, '#!/usr/bin/python3\n' + body)
        case.write_exe('tmux', '#!/bin/bash\nexit 0\n')
        case.env['FIXTURE_CALLS'] = str(case.root / 'calls')
        # Explicit temporary destinations and no source scripts, templates,
        # includes, credentials or inherited Git controls.
        (case.root / 'chezmoi.toml').write_text('[git]\nautoCommit=false\nautoPush=false\nautoPull=false\n')
        for relative, text in [('dot_config/systemd/user/fixture.service', '[Service]\nExecStart=/usr/bin/true\n'),
                               ('Library/LaunchAgents/fixture.plist', '<plist/>\n')]:
            p = case.root / 'source' / relative
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(text)
        return case, apply

    def run_stage(self, case, apply, stage='apply', mask='0002', native=False, failure='', selection=None, method='ssh'):
        checkout = case.home / '.local/share/chezmoi'
        if stage == 'update':
            (checkout / '.git').mkdir(parents=True, exist_ok=True)
        if stage == 'init' and checkout.exists():
            (checkout / '.git').rmdir()
            checkout.rmdir()
        (case.root / 'calls').unlink(missing_ok=True)
        env = case.env | {'DOTFILES_ACCESS_METHOD': method, 'FIXTURE_FAIL': failure}
        if selection is not None:
            env['BB_SERVER'] = selection
        if native:
            if not CHEZMOI:
                self.skipTest('Native Chezmoi unavailable; set CHEZMOI_BIN')
            env.update(FIXTURE_NATIVE='1', FIXTURE_NATIVE_BIN=CHEZMOI)
        operation = apply if stage == 'apply' else stage.replace('init', 'initialize') + '_chezmoi; result=$?'
        script = '''source "$FIXTURE_ROOT/dotfiles.sh"
print_message() { :; }
print_success() { printf 'SUCCESS: %s\\n' "$*"; }
print_error() { printf 'ERROR: %s\\n' "$*"; }
print_warning() { printf 'WARNING: %s\\n' "$*"; }
print_debug() { :; }
umask "$1"
''' + operation + '\nprintf "CALLER_MASK=%s\\n" "$(umask)"\nexit "$result"\n'
        out = subprocess.run(['/bin/bash', '-c', script, '_', mask], env=env, cwd=case.home, capture_output=True, text=True, timeout=20)
        self.assertEqual(out.stderr, '', out)
        self.assertIn('CALLER_MASK=' + mask, out.stdout)
        self.assertNotIn('FORBIDDEN', case.log())
        return out

    def test_all_five_real_callers_apply_additive_mask_and_preserve_failures(self):
        for platform in SCRIPTS:
            case, apply = self.fixture(platform)
            self.assertEqual(function(SOURCES[platform], 'with_bb_dotfiles_umask'),
                             function(SOURCES['ubuntu'], 'with_bb_dotfiles_umask'))
            for selection in [None, '0', '1']:
                for mask, expected in [('0002', '0022'), ('0027', '0027'), ('0077', '0077')]:
                    for stage, method in [('init', 'ssh'), ('init', 'token'), ('init', 'deploy'), ('update', ''), ('apply', '')]:
                        with self.subTest(platform=platform, stage=stage, mask=mask, selection=selection):
                            out = self.run_stage(case, apply, stage, mask, selection=selection, method=method)
                            self.assertEqual(out.returncode, 0, out)
                            calls = [json.loads(s) for s in (case.root / 'calls').read_text().splitlines()]
                            args = ['apply', '--force'] + (['--verbose'] if platform == 'pi' else [])
                            if stage == 'update':
                                args = ['update'] + ([] if platform == 'pi' else ['--force'])
                            elif stage == 'init':
                                repo = {'ssh': 'scowalt/dotfiles', 'token': 'https://github.com/scowalt/dotfiles.git',
                                        'deploy': 'git@github-dotfiles:scowalt/dotfiles.git'}[method]
                                args = ['init', '--apply', '--force', repo] + (['--ssh'] if method == 'ssh' else [])
                            self.assertEqual([c for c in calls if c['command'] == 'chezmoi'],
                                             [{'command': 'chezmoi', 'args': args, 'umask': expected}])
            for stage in ['init', 'update', 'apply']:
                out = self.run_stage(case, apply, stage, failure='17')
                self.assertNotIn('SUCCESS:', out.stdout)
                self.assertTrue('ERROR:' in out.stdout or 'WARNING:' in out.stdout, out)
                if stage != 'update':
                    self.assertEqual(out.returncode, 1, out)

    def test_native_managed_arcane_modes_converge_then_preparation_succeeds_twice(self):
        for platform in SCRIPTS:
            with self.subTest(platform=platform):
                case, apply = self.fixture(platform)
                for name in ['.config', '.config/systemd', '.config/systemd/user', 'Library', 'Library/LaunchAgents']:
                    p = case.home / name
                    p.mkdir(exist_ok=True)
                    p.chmod(0o775)
                managed = case.home / '.config/systemd/user/fixture.service'
                managed.write_text('[Service]\nExecStart=/usr/bin/true\n')
                managed.chmod(0o664)
                # Private Linux ancestry excludes other account writers already;
                # native dotfiles must still converge their managed modes.
                out = case.run_helper(expected=0 if sys.platform == 'linux' else 1)
                self.assertIn('not enrolled' if sys.platform == 'linux' else 'preflight failed', out)
                for attempt in range(2):
                    self.assertEqual(self.run_stage(case, apply, native=True).returncode, 0)
                    self.assertEqual(managed.stat().st_mode & 0o777, 0o644)
                    self.assertIn('not enrolled', case.run_helper(platform))
                # Unmanaged files remain unchanged, not silently chmodded/adopted.
                unit = managed.with_name('unmanaged.service')
                unit.write_text('fixture-secret: unrelated service\n')
                unit.chmod(0o664)
                unit_before = (unit.lstat().st_mode, unit.read_bytes())
                self.run_stage(case, apply, native=True)
                self.assertEqual((unit.lstat().st_mode, unit.read_bytes()), unit_before)
                before = snapshot(case.home)
                case.events.unlink()
                out = case.run_helper(expected=0 if sys.platform == 'linux' else 1)
                self.assertIn('not enrolled' if sys.platform == 'linux' else 'preflight failed', out)
                self.assertNotIn('fixture-secret', out)
                self.assertEqual(snapshot(case.home), before)
                unit.chmod(0o666)
                before = snapshot(case.home)
                case.events.unlink()
                out = case.run_helper(expected=1)
                self.assertIn('operation=service path=~/.config/systemd/user/unmanaged.service mode=0666 reason=writable-boundary', out)
                self.assertEqual(snapshot(case.home), before)
                self.assertNotIn('npm', case.log())

    def test_explicit_chezmoi_umask_is_preserved_and_world_write_fails_closed(self):
        case, apply = self.fixture('ubuntu')
        config = case.root / 'chezmoi.toml'
        config.write_text('umask=0o002\n' + config.read_text())
        before = config.read_bytes()
        # Existing managed directories reproduce chmod convergence, not only
        # mkdir's extra inherited process-mask restriction on first creation.
        (case.home / '.config/systemd/user').mkdir(parents=True)
        self.run_stage(case, apply, native=True)
        out = case.run_helper(expected=0 if sys.platform == 'linux' else 1)
        self.assertIn('not enrolled' if sys.platform == 'linux' else 'preflight failed', out)
        self.assertEqual(config.read_bytes(), before)
        config.write_text(config.read_text().replace('umask=0o002', 'umask=0o000'))
        before = config.read_bytes()
        self.run_stage(case, apply, native=True)
        case.events.unlink()
        out = case.run_helper(expected=1)
        self.assertIn('operation=directory path=~/.config mode=0777 reason=writable-boundary', out)
        self.assertEqual(config.read_bytes(), before)
        self.assertNotIn('npm', case.log())


if __name__ == '__main__':
    unittest.main(verbosity=2)
