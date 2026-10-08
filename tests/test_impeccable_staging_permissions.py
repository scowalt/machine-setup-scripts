import json
import os
from pathlib import Path
import unittest

import test_impeccable_convergence as convergence
import test_impeccable_callers as callers


class ImpeccableStagingPermissions(unittest.TestCase):
    tearDown = convergence.ImpeccableConvergence.tearDown
    put = convergence.ImpeccableConvergence.put
    adapter = convergence.ImpeccableConvergence.adapter
    snapshot = convergence.ImpeccableConvergence.snapshot
    captured_directories = convergence.ImpeccableConvergence.captured_directories
    seed_preserved_state = callers.ImpeccableCallers.seed_preserved_state
    assert_preserved_state = callers.ImpeccableCallers.assert_preserved_state

    def setUp(self):
        convergence.ImpeccableConvergence.setUp(self)
        self.env['IMPECCABLE_TEST_NATIVE_MODES'] = '1'
        self.preserved = self.seed_preserved_state()
        self.directories = self.captured_directories()
        self.metadata = convergence.directory_metadata(self.directories)
        self.npm = {file: file.read_bytes() for file in (self.home / 'user.npmrc', self.home / 'global.npmrc')}

    def run_adapter(self, entry=None, success=True, mask=0o002, stage_retained=False):
        self.put(self.root / 'events', '')
        self.put(self.root / 'stages', '')
        result = self.adapter(entry=entry, success=success, creation_mask=mask, stage_retained=stage_retained)
        self.assertEqual(convergence.directory_metadata(self.directories), self.metadata)
        self.assert_preserved_state(self.preserved)
        self.assert_preserved_state(self.npm)
        self.assertEqual(int((self.root / 'installer-umask').read_text(), 8), 0o077)
        if entry:
            events = (self.root / 'events').read_text().splitlines()
            self.assertEqual(events[-1], 'final:' + str(int(not success)))
            self.assertEqual(events.count(events[-1]), 1)
            self.assertIn('independent', events)
            self.assertIn('reboot', events)
            self.assertFalse(any(event.startswith('FORBIDDEN:') for event in events), events)
        return result

    def assert_safe_created_files(self, caller_mask=0o002):
        self.assertEqual(json.loads((self.root / 'installer-modes.json').read_text()), {
            '.claude/skills/impeccable/scripts/bin/linux-x64/impeccable': 0o755,
            '.claude/agents/impeccable-documenter.md': 0o600,
            '.npm/_cacache/content/blob': 0o600,
        })
        for provider in convergence.PROVIDERS:
            skill = self.home / provider / 'impeccable'
            self.assertEqual((skill / 'scripts/bin/linux-x64/impeccable').stat().st_mode & 0o777,
                             0o755 & ~caller_mask)
            self.assertEqual((skill / 'SKILL.md').stat().st_mode & 0o777, 0o600)
        for profile in ('.claude', '.cursor'):
            for name in convergence.AGENTS:
                helper = self.home / profile / 'agents' / ('impeccable-' + name + '.md')
                self.assertEqual(helper.stat().st_mode & 0o777, 0o600)

    def test_canonical_adapter_scopes_private_mask_without_changing_caller_mask(self):
        for mask in (0o002, 0o022, 0o077):
            with self.subTest(mask=oct(mask)):
                result = self.run_adapter(mask=mask)
                self.assertIn('verified', result.stdout)
                self.assert_safe_created_files(caller_mask=mask)

    def test_five_real_callers_install_update_and_repeat_with_permissive_mask(self):
        for entry in callers.BASH:
            for revision in ('initial', 'updated', 'updated'):
                with self.subTest(entry=entry, revision=revision):
                    self.env['IMPECCABLE_TEST_REVISION'] = revision
                    result = self.run_adapter(entry)
                    self.assertIn('verified', result.stdout)
                    self.assert_safe_created_files()
                    self.assertTrue((self.home / '.claude/skills/impeccable/SKILL.md').read_text().endswith(revision))

    def test_installer_and_promotion_failures_dispose_stage_preserve_prior_payload_and_caller_mask(self):
        self.run_adapter('ubuntu.sh')
        for mode in ('failed-command', 'fail-skill-promotion'):
            with self.subTest(mode=mode):
                before = self.snapshot()
                self.env.update(IMPECCABLE_TEST_MODE=mode, IMPECCABLE_TEST_REVISION='new payload')
                result = self.run_adapter('ubuntu.sh', success=False)
                self.assertNotIn('verified', result.stdout)
                self.assertEqual(self.snapshot(), before)
        self.env.pop('IMPECCABLE_TEST_MODE')
        self.env['IMPECCABLE_TEST_EARLIER_FAILURE'] = '1'
        result = self.run_adapter('ubuntu.sh', success=False)
        self.assertIn('verified', result.stdout)
        self.assert_safe_created_files()

    def test_explicitly_restored_unsafe_engine_still_refuses_without_permission_repair(self):
        before = self.snapshot()
        self.env['IMPECCABLE_TEST_MODE'] = 'unsafe-bundled-engine'
        result = self.run_adapter('ubuntu.sh', success=False, stage_retained=True)
        self.assertEqual(result.stderr.count('Impeccable: unsafe-owner-or-mode.'), 2)
        self.assertEqual(self.snapshot(), before)
        stage = Path((self.root / 'stages').read_text().strip())
        binary = stage / '.claude/skills/impeccable/scripts/bin/linux-x64/impeccable'
        self.assertEqual(binary.stat().st_mode & 0o777, 0o775)
        self.assertNotIn('verified', result.stdout)

    def test_explicitly_unsafe_cache_keeps_cleanup_failure_fatal(self):
        self.env['IMPECCABLE_TEST_MODE'] = 'unsafe-npm-cache'
        result = self.run_adapter('ubuntu.sh', success=False, stage_retained=True)
        self.assertEqual(result.stderr.count('Impeccable: unsafe-owner-or-mode.'), 1)
        self.assertNotIn('verified', result.stdout)
        stage = Path((self.root / 'stages').read_text().strip())
        self.assertTrue(os.path.isdir(stage))
        self.assertEqual((stage / '.npm/_cacache/content/blob').stat().st_mode & 0o777, 0o664)
        self.assertTrue((self.home / '.agents/.setup-impeccable.json').is_file())


if __name__ == '__main__':
    unittest.main(verbosity=2)
