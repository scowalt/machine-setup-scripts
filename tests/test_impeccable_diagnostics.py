import unittest

import test_impeccable_convergence as convergence

DNS = "Download failed: Could not verify skill bundle: https://private.invalid/PRIVATE-SENTINEL: Dns Failed: resolve dns name 'private.invalid:443': failed to lookup address information: Try again.\n"
SECRET = 'Authorization: Bearer PRIVATE-SENTINEL\npassword=PRIVATE-SENTINEL\n'


class ImpeccableDiagnostics(unittest.TestCase):
    setUp = convergence.ImpeccableConvergence.setUp
    tearDown = convergence.ImpeccableConvergence.tearDown
    put = convergence.ImpeccableConvergence.put
    snapshot = convergence.ImpeccableConvergence.snapshot
    adapter = convergence.ImpeccableConvergence.adapter

    def test_installer_reason_and_actual_exit_are_safe_and_survive_cleanup(self):
        for shell in ('bash', 'powershell'):
            for output, reason in ((DNS, 'dns-resolution-failed'),
                                   ('npm error code EAI_AGAIN\n', 'dns-resolution-failed'),
                                   ('npm error code E403\n', 'download-http-failed'),
                                   (DNS + 'npm error code E403\n', 'unknown'),
                                   (SECRET, 'unknown')):
                with self.subTest(shell=shell, reason=reason):
                    self.env.update(IMPECCABLE_TEST_INSTALLER_EXIT='37', IMPECCABLE_TEST_STDOUT=SECRET,
                                    IMPECCABLE_TEST_STDERR=output, DEBUG='1')
                    before = self.snapshot()
                    result = self.adapter(shell, success=False)
                    self.assertIn(f'Impeccable: phase=installer reason={reason} exit=37', result.stderr)
                    self.assertNotIn('private.invalid', result.stdout + result.stderr)
                    self.assertEqual(self.snapshot(), before)
                    self.assertEqual((self.root / 'output-drained').read_text(), 'completed')

    def test_oversized_unterminated_output_is_drained_and_unknown_without_archives(self):
        for shell in ('bash', 'powershell'):
            self.env.update(IMPECCABLE_TEST_INSTALLER_EXIT='43', IMPECCABLE_TEST_STDERR=DNS,
                            IMPECCABLE_TEST_OVERSIZED='1')
            result = self.adapter(shell, success=False)
            self.assertIn('phase=installer reason=unknown exit=43', result.stderr)
            self.assertEqual((self.root / 'output-drained').read_text(), 'completed')

    def test_policy_reasons_and_exit_codes_survive_both_wrappers(self):
        for shell in ('bash', 'powershell'):
            settings = self.put(self.home / '.pi/agent/settings.json', 'PRIVATE-SENTINEL malformed JSON')
            before = self.snapshot()
            result = self.adapter(shell, success=False)
            self.assertIn('phase=preflight reason=malformed-metadata exit=1', result.stderr)
            self.assertEqual(self.snapshot(), before)
            self.env['BAN_IMPECCABLE'] = '1'
            result = self.adapter(shell, success=False)
            self.assertIn('phase=removal reason=malformed-metadata exit=1', result.stderr)
            self.assertEqual(self.snapshot(), before)
            self.env.pop('BAN_IMPECCABLE')
            settings.unlink()
            self.env['IMPECCABLE_TEST_MODE'] = 'missing-engine'
            result = self.adapter(shell, success=False)
            self.assertIn('phase=promotion reason=incomplete-payload exit=1', result.stderr)
            self.env.pop('IMPECCABLE_TEST_MODE')

    def test_successful_verified_install_is_not_reclassified_by_error_like_output(self):
        for shell in ('bash', 'powershell'):
            self.env['IMPECCABLE_TEST_SUCCESS_NOISE'] = DNS + SECRET
            result = self.adapter(shell)
            self.assertIn('verified', result.stdout)
            self.assertNotIn('phase=installer', result.stderr)

    def test_bash_pipefail_and_inherited_errexit_keep_native_failure_and_cleanup(self):
        self.env.update(IMPECCABLE_TEST_STRICT_PIPELINE='1', IMPECCABLE_TEST_INSTALLER_EXIT='59',
                        IMPECCABLE_TEST_STDERR=DNS)
        result = self.adapter(success=False)
        self.assertIn('phase=installer reason=dns-resolution-failed exit=59', result.stderr)
        self.assertFalse(list(self.root.glob('setup-impeccable-*')))

    def test_powershell_legacy_native_arguments_keep_the_collector_program_intact(self):
        self.env['IMPECCABLE_TEST_LEGACY_ARGUMENTS'] = '1'
        self.adapter('powershell')
        before = self.snapshot()
        self.env.update(IMPECCABLE_TEST_INSTALLER_EXIT='53', IMPECCABLE_TEST_STDERR=DNS)
        result = self.adapter('powershell', success=False)
        self.assertIn('phase=installer reason=dns-resolution-failed exit=53', result.stderr)
        self.assertEqual(self.snapshot(), before)

    def test_failed_collector_drains_without_replacing_the_installer_exit(self):
        for shell in ('bash', 'powershell'):
            self.env.update(IMPECCABLE_TEST_INSTALLER_EXIT='57', IMPECCABLE_TEST_STDOUT=SECRET,
                            IMPECCABLE_TEST_STDERR=DNS, IMPECCABLE_TEST_BAD_COLLECTOR='1',
                            IMPECCABLE_TEST_OVERSIZED='1')
            result = self.adapter(shell, success=False)
            self.assertIn('phase=installer reason=unknown exit=57', result.stderr)
            self.assertEqual((self.root / 'output-drained').read_text(), 'completed')

    def test_unknown_helper_output_does_not_hide_its_exit_or_leak_text(self):
        for shell in ('bash', 'powershell'):
            self.env['IMPECCABLE_TEST_POLICY_OUTPUT'] = '1'
            before = self.snapshot()
            result = self.adapter(shell, success=False)
            self.assertIn('phase=preflight reason=unknown exit=73', result.stderr)
            self.assertEqual(self.snapshot(), before)
            self.assertFalse((self.root / 'calls').exists())

    def test_prerequisite_npm_staging_and_launch_failures_have_distinct_phases(self):
        for shell in ('bash', 'powershell'):
            for variable, value, expected in (
                    ('IMPECCABLE_TEST_MODE', 'bad-runtime', 'phase=prerequisites reason=installer-runtime-unavailable exit=unavailable'),
                    ('IMPECCABLE_TEST_MODE', 'failed-npm-config', 'phase=npm-configuration reason=npm-configuration-unverified exit=1'),
                    ('IMPECCABLE_TEST_STAGE_FAILURE', '1', 'phase=staging reason=ENOSPC exit=1'),
                    ('IMPECCABLE_TEST_LAUNCH_FAILURE', '1', 'phase=installer reason=launch-failed exit=unavailable' if shell == 'powershell' else 'phase=installer reason=unknown exit=127')):
                with self.subTest(shell=shell, variable=variable, value=value):
                    self.env[variable] = value
                    before = self.snapshot()
                    result = self.adapter(shell, success=False)
                    self.assertIn(expected, result.stderr)
                    self.assertEqual(self.snapshot(), before)
                    self.env.pop(variable)

    def test_six_callers_preserve_diagnostics_independent_work_and_final_failure(self):
        self.env.update(IMPECCABLE_TEST_INSTALLER_EXIT='61', IMPECCABLE_TEST_STDERR=DNS)
        for entry in ('mac.sh', 'ubuntu.sh', 'wsl.sh', 'pi.sh', 'bazzite.sh', 'win.ps1'):
            self.put(self.root / 'events', '')
            shell = 'powershell' if entry == 'win.ps1' else 'bash'
            result = self.adapter(shell, entry=entry, success=False)
            self.assertIn('phase=installer reason=dns-resolution-failed exit=61', result.stderr)
            events = (self.root / 'events').read_text().splitlines()
            self.assertIn('independent', events)
            self.assertIn('reboot', events)
            self.assertEqual(events[-1], 'finalized' if shell == 'powershell' else 'final:1')

    def test_installer_and_cleanup_failures_are_both_reported_in_order(self):
        for shell in ('bash', 'powershell'):
            self.env.update(IMPECCABLE_TEST_INSTALLER_EXIT='49', IMPECCABLE_TEST_STDERR=DNS,
                            IMPECCABLE_TEST_DISPOSE_FAILURE='1')
            before = self.snapshot()
            result = self.adapter(shell, success=False, stage_retained=True)
            first = 'phase=installer reason=dns-resolution-failed exit=49'
            second = 'phase=cleanup reason=EACCES exit=1'
            self.assertIn(first, result.stderr)
            self.assertIn(second, result.stderr)
            self.assertLess(result.stderr.index(first), result.stderr.index(second))
            self.assertEqual(self.snapshot(), before)
            for stage in self.root.glob('setup-impeccable-*'):
                self.assertFalse(any(file.is_file() for file in stage.rglob('*')), 'raw output was archived')


if __name__ == '__main__':
    unittest.main(verbosity=2)
