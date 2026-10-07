import json
import os
import shutil
import unittest

import test_impeccable_convergence as convergence

BASH = ('mac.sh', 'ubuntu.sh', 'wsl.sh', 'pi.sh', 'bazzite.sh')
ENTRIES = (*BASH, 'win.ps1')


class ImpeccableCallers(unittest.TestCase):
    setUp = convergence.ImpeccableConvergence.setUp
    tearDown = convergence.ImpeccableConvergence.tearDown
    put = convergence.ImpeccableConvergence.put
    snapshot = convergence.ImpeccableConvergence.snapshot
    adapter = convergence.ImpeccableConvergence.adapter
    captured_directories = convergence.ImpeccableConvergence.captured_directories

    def run_entry(self, entry, success=True):
        self.put(self.root / 'events', '')
        result = self.adapter('powershell' if entry == 'win.ps1' else 'bash', entry=entry, success=success)
        events = (self.root / 'events').read_text().splitlines()
        expected = 'finalized' if entry == 'win.ps1' else 'final:' + str(int(not success))
        self.assertEqual(events[-1], expected)
        self.assertEqual(events.count(expected), 1)
        self.assertFalse(any(event.startswith('FORBIDDEN:') for event in events), events)
        return result, events

    def installer_calls(self):
        file = self.root / 'calls'
        return file.read_text().splitlines() if file.exists() else []

    def seed_preserved_state(self):
        files = [self.put(self.home / name, 'unchanged') for name in (
            '.env.local', '.pi/agent/auth.json', '.pi/agent/models.json', '.agents/skills/tdd/SKILL.md',
            '.agents/.setup-matt-pocock-skills.json', '.impeccable/bin/engine-cache',
            '.claude/settings.json', '.cursor/hooks.json', '.gemini/settings.json',
            '.cursor/agents/keep-me.md', 'unselected/skills/impeccable/SKILL.md',
            '.bashrc', '.config/fish/config.fish')]
        self.put(self.home / '.env.local', 'WORK_MACHINE=0\nBAN_IMPECCABLE=0\n')
        project_files = [self.put(self.root / name, 'unchanged') for name in (
            '.git/config', '.claude/settings.json', '.cursor/hooks.json', '.pi/settings.json',
            '.agents/skills/impeccable/SKILL.md', 'design/generated.html')]
        return {file: file.read_bytes() for file in files + project_files}

    def assert_preserved_state(self, state):
        for file, contents in state.items():
            self.assertEqual(file.read_bytes(), contents, str(file))

    def test_ubuntu_captured_group_writable_layout_converges_and_finalizes_without_permission_repair(self):
        state = self.seed_preserved_state()
        paths = self.captured_directories()
        before = convergence.directory_metadata(paths)
        result, events = self.run_entry('ubuntu.sh')
        self.assertIn('verified', result.stdout)
        for provider in convergence.PROVIDERS:
            self.assertEqual((self.home / provider / 'impeccable/SKILL.md').read_text(), convergence.descriptor(provider))
        self.assertEqual(convergence.directory_metadata(paths), before)
        self.assert_preserved_state(state)
        for operation in ('matt', 'independent', 'reboot', 'final:0'):
            self.assertIn(operation, events)

    def test_bash_required_installer_failure_survives_independent_work_reboot_and_finalization(self):
        self.captured_directories()
        self.env['IMPECCABLE_TEST_MODE'] = 'failed-command'
        for entry in BASH:
            with self.subTest(entry=entry):
                self.put(self.root / 'events', '')
                before = self.snapshot()
                result = self.adapter(entry=entry, success=False)
                self.assertIn('Impeccable: installer-failed.', result.stdout + result.stderr)
                self.assertEqual(self.snapshot(), before)
                events = (self.root / 'events').read_text().splitlines()
                for operation in ('matt', 'rtk', 'attention', 'simple-english', 'show-me', 'pr-lens', 'independent', 'reboot'):
                    self.assertIn(operation, events)
                self.assertEqual(events[-1], 'final:1')
                self.assertEqual(events.count('final:1'), 1)
                self.assertFalse(any(event.startswith('FORBIDDEN:') for event in events), events)

    def test_windows_boolean_failure_survives_independent_work_reboot_and_real_log_wrapper(self):
        self.captured_directories()
        self.env['IMPECCABLE_TEST_MODE'] = 'failed-command'
        before = self.snapshot()
        result = self.adapter('powershell', entry='win.ps1', success=False)
        self.assertIn('Required Impeccable skill convergence failed.', result.stderr)
        self.assertEqual(self.snapshot(), before)
        events = (self.root / 'events').read_text().splitlines()
        for operation in ('matt', 'rtk', 'attention', 'simple-english', 'show-me', 'pr-lens', 'independent', 'reboot'):
            self.assertIn(operation, events)
        self.assertEqual(events[-1], 'finalized')
        self.assertEqual(events.count('finalized'), 1)

    def test_six_real_callers_install_and_update_complete_default_pi_payload_preserving_independent_state(self):
        state = self.seed_preserved_state()
        paths = self.captured_directories()
        metadata = convergence.directory_metadata(paths)
        settings = self.put(self.home / '.pi/agent/settings.json', '{"skills":["custom"],"theme":"keep","packages":["npm:keep"]}')
        for entry in ENTRIES:
            with self.subTest(entry=entry):
                for revision in ('first snapshot', 'updated snapshot'):
                    self.env['IMPECCABLE_TEST_REVISION'] = revision
                    calls = len(self.installer_calls())
                    result, events = self.run_entry(entry)
                    self.assertIn('verified', result.stdout)
                    self.assertEqual(len(self.installer_calls()), calls + 1)
                    direct = self.home / '.pi/agent/skills/impeccable'
                    self.assertEqual((direct / 'SKILL.md').read_text(), convergence.descriptor('.pi/agent/skills') + revision)
                    self.assertEqual((direct / 'scripts/bin/linux-x64/impeccable').read_bytes(), convergence.native_engine())
                    for resource in convergence.SCRIPTS:
                        self.assertGreater((direct / 'scripts' / resource).stat().st_size, 0)
                    for provider in convergence.PROVIDERS:
                        self.assertTrue((self.home / provider / 'impeccable/reference/layout.md').is_file())
                    selected = json.loads(settings.read_text())
                    self.assertEqual(selected['skills'], ['custom', '!' + str(self.home / '.agents/skills/impeccable') + '/**'])
                    self.assertEqual(selected['theme'], 'keep')
                    self.assertEqual(selected['packages'], ['npm:keep'])
                    self.assertIn('matt', events)
                    self.assertIn('independent', events)
                    self.assertIn('reboot', events)
                    self.assert_preserved_state(state)
                    self.assertEqual(convergence.directory_metadata(paths), metadata)

    def test_selected_profiles_exact_data_only_exclusion_is_offline_idempotent_and_reversible_for_six_callers(self):
        state = self.seed_preserved_state()
        selected = self.home / 'selected pi'
        claude = self.home / 'selected claude'
        self.env.update(PI_CODING_AGENT_DIR=str(selected), CLAUDE_CONFIG_DIR=str(claude))
        paths = self.captured_directories()
        for directory in (selected / 'skills', claude, claude / 'skills', claude / 'agents'):
            directory.mkdir(parents=True, exist_ok=True)
            directory.chmod(0o775)
            paths.append(directory)
        selected.chmod(0o700)
        metadata = convergence.directory_metadata(paths + [selected])
        settings = self.put(selected / 'settings.json', '{"skills":["custom"],"theme":"keep"}')
        environment = self.home / '.env.local'
        outside = self.put(self.home / 'foreign/SKILL.md', 'keep leaf-link target')
        for entry in ENTRIES:
            with self.subTest(entry=entry):
                for flag in ('0', 'true', '01'):
                    environment.write_text('BAN_IMPECCABLE=' + flag + '\nWORK_MACHINE=1\n')
                    state[environment] = environment.read_bytes()
                    self.run_entry(entry)
                    self.assertEqual((selected / 'skills/impeccable/SKILL.md').read_text(), convergence.descriptor('.pi/agent/skills'))
                    self.assertTrue((claude / 'skills/impeccable/reference/layout.md').is_file())
                    self.assert_preserved_state(state)
                shared = self.home / '.agents/skills/impeccable'
                shutil.rmtree(shared)
                shared.symlink_to(outside.parent, target_is_directory=True)
                self.put(selected / 'skills/impeccable.md', 'flat legacy copy')
                calls = self.installer_calls()
                environment.write_text('BAN_IMPECCABLE=1\nWORK_MACHINE=1\n')
                state[environment] = environment.read_bytes()
                self.env['IMPECCABLE_TEST_MODE'] = 'bad-runtime'
                self.run_entry(entry)
                before = self.snapshot()
                self.run_entry(entry)
                self.assertEqual(self.snapshot(), before)
                self.assertEqual(self.installer_calls(), calls)
                for provider in convergence.PROVIDERS + ['selected pi/skills', 'selected claude/skills']:
                    self.assertFalse(os.path.lexists(self.home / provider / 'impeccable'))
                for profile in ('.claude', '.cursor', 'selected claude'):
                    for agent in convergence.AGENTS:
                        self.assertFalse((self.home / profile / 'agents' / ('impeccable-' + agent + '.md')).exists())
                self.assertFalse((selected / 'skills/impeccable.md').exists())
                self.assertEqual(outside.read_text(), 'keep leaf-link target')
                self.assertEqual(json.loads(settings.read_text()), {'skills': ['custom'], 'theme': 'keep'})
                self.assert_preserved_state(state)
                environment.write_text('WORK_MACHINE=1\n')
                state[environment] = environment.read_bytes()
                self.env.pop('BAN_IMPECCABLE', None)
                self.env.pop('IMPECCABLE_TEST_MODE')
                self.run_entry(entry)
                self.assertTrue((selected / 'skills/impeccable/scripts/live-browser.js').is_file())
                self.assert_preserved_state(state)
                self.assertEqual(convergence.directory_metadata(paths + [selected]), metadata)

    def test_incomplete_payload_failed_promotion_and_runtime_failure_remain_incomplete_without_losing_old_payload(self):
        self.captured_directories()
        for entry in ENTRIES:
            with self.subTest(entry=entry):
                self.run_entry(entry)
                before = self.snapshot()
                for mode in ('missing-engine', 'fail-skill-promotion', 'bad-runtime'):
                    self.env['IMPECCABLE_TEST_MODE'] = mode
                    result, events = self.run_entry(entry, success=False)
                    self.assertNotIn('verified', result.stdout)
                    self.assertEqual(self.snapshot(), before)
                    self.assertIn('independent', events)
                    self.assertIn('reboot', events)
                self.env.pop('IMPECCABLE_TEST_MODE')

    def test_earlier_independent_failure_is_not_erased_by_successful_impeccable_convergence(self):
        self.captured_directories()
        self.env['IMPECCABLE_TEST_EARLIER_FAILURE'] = '1'
        for entry in ENTRIES:
            with self.subTest(entry=entry):
                result, events = self.run_entry(entry, success=False)
                self.assertIn('verified', result.stdout)
                self.assertTrue((self.home / '.pi/agent/skills/impeccable/reference/layout.md').is_file())
                self.assertIn('matt', events)
                self.assertIn('independent', events)
                self.assertIn('reboot', events)

    def test_permission_and_later_pi_blocks_refuse_installation_and_exclusion_without_mutating_profiles(self):
        self.put(self.home / '.pi/agent/skills/impeccable/SKILL.md', 'custom native copy')
        self.put(self.home / '.agents/skills/impeccable/SKILL.md', 'custom shared copy')
        self.put(self.home / '.pi/agent/settings.json', 'malformed PRIVATE-SENTINEL')
        before = self.snapshot()
        for entry in ENTRIES:
            for gate in ('IMPECCABLE_TEST_BLOCKED', 'IMPECCABLE_TEST_LATE_BLOCK'):
                self.env[gate] = '1'
                for flag in ('0', '1'):
                    self.env['BAN_IMPECCABLE'] = flag
                    with self.subTest(entry=entry, gate=gate, flag=flag):
                        result, events = self.run_entry(entry, success=False)
                        self.assertNotIn('verified', result.stdout)
                        self.assertEqual(self.snapshot(), before)
                        self.assertEqual(self.installer_calls(), [])
                        self.assertIn('independent', events)
                        self.assertIn('reboot', events)
                self.env.pop(gate)

    def test_personal_work_and_native_headless_contexts_converge_without_bypassing_windows_wsl_early_rejection(self):
        for entry in ENTRIES:
            for work in ('0', '1'):
                for headless in ('0', 'true', '1'):
                    self.env.update(WORK_MACHINE=work, HEADLESS=headless)
                    rejected = headless == '1' and entry in ('wsl.sh', 'win.ps1')
                    with self.subTest(entry=entry, work=work, headless=headless):
                        before = self.snapshot()
                        calls = len(self.installer_calls())
                        result, events = self.run_entry(entry, success=not rejected)
                        if rejected:
                            self.assertEqual(self.snapshot(), before)
                            self.assertEqual(len(self.installer_calls()), calls)
                            self.assertNotIn('environment-template', events)
                            self.assertNotIn('permissions', events)
                            self.assertNotIn('matt', events)
                            self.assertNotIn('reboot', events)
                            self.assertNotIn('verified', result.stdout)
                        else:
                            self.assertIn('verified', result.stdout)
                            self.assertEqual(len(self.installer_calls()), calls + 1)
                            self.assertIn('permissions', events)
                            self.assertIn('matt', events)


if __name__ == '__main__':
    unittest.main(verbosity=2)
