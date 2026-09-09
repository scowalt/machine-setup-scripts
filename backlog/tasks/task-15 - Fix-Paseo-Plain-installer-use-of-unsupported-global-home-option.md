---
id: TASK-15
title: Fix Paseo Plain installer use of unsupported global home option
status: Done
assignee:
  - '@pi'
created_date: '2026-09-09 18:32'
updated_date: '2026-09-09 19:14'
labels: []
dependencies: []
references:
  - tests/test_paseo_plain_setup.py
  - ubuntu.sh
  - 'https://paseo.sh/docs/cli.md'
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
After plugins were enabled on scott-beelink-ubuntu, Ubuntu setup version 243 still failed to install Paseo Plain. The installer passes --home as a global Paseo CLI flag; Paseo 0.8.0-beta.1 rejects it before running daemon status. Pass the resolved PASEO_HOME through the child environment instead, without changing plugin trust, source ownership, or daemon state.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 All six installers use the resolved PASEO_HOME for child commands without the unsupported global --home flag, and preserve explicit verified local-host targeting.
- [x] #2 A regression reproduces the rejected argument and verifies successful installation/update under a CLI fixture that rejects unsupported global options; alternate-home isolation and failure redaction remain covered.
- [x] #3 Version banners, affected contract expectations, and necessary documentation are updated; installer tests, native read-only CLI verification, lint, secret checks, and pre-push contracts pass before publication.
- [x] #4 No remote daemon restart, configuration change, plugin activation, or real model call occurs during the source fix.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Add a regression at the existing temporary-home/fake-CLI boundary that rejects the unsupported global --home option and proves the current installer fails before installation.
2. Pass the resolved PASEO_HOME in each child command environment and remove --home from global arguments in all six identical installer copies. Preserve explicit verified local-host targeting and all existing trust/source/settings safeguards.
3. Validate argument compatibility with the real Paseo 0.8.0-beta.1 CLI using read-only reference commands. Update script versions and contract expectations, then run installer, shell, PowerShell, lint, whitespace, and secret checks.
4. After approval, publish the source correction to remote main without changing the affected machine or calling a model. Verify remote main and report the corrected script version for rerunning setup.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
The second Beelink log confirms Ubuntu version 243 and installed @getpaseo/cli@0.8.0-beta.1. It passed the trust gate but emitted the generic failure at line 518. On the same CLI release, the installer command paseo --home /home/scowalt/.paseo daemon status --json exits 1 with error: unknown option --home. Supplying PASEO_HOME via the child environment instead makes both daemon status and explicitly targeted plugin ls return valid JSON with exit 0. These checks were read-only against the local reference daemon, not the affected host. No machine settings changed.
Waiting for approval before source edits. Backlog allocated active ID 15 despite an archived historical task with that number; the excluded fleet-rollout task remains unchanged in backlog/archive/tasks.

Scott approved the source fix, regression coverage, and publication to main. Testing stays at the existing isolated setup/CLI boundary, plus read-only compatibility checks against the local reference CLI. The affected host will not be changed.

The stricter external CLI fixture reproduced the installer failure before the source fix (exit 1 and the same generic failure message). All six copies now remove the unsupported global option and supply the resolved PASEO_HOME in the child environment.

Validation completed:

- All 16 isolated installer tests pass, including the portable PowerShell wrapper.
- Default, empty, and relative custom-home cases pass. A mutation that removes the child environment override causes all three expected assertion failures. The custom-home install and update leave the default home unchanged and retain explicit loopback targeting despite an unrelated inherited PASEO_HOST.
- Real Paseo 0.8.0-beta.1 read-only reference commands confirm the old parser rejection and the corrected status/catalog JSON responses. Reference daemon and plugin configurations remain byte-identical.
- ShellCheck, Bash syntax, full win.ps1 parsing, the PowerShell channel fixtures, every tests/*.sh contract, Markdownlint, and whitespace checks pass. A manual lefthook pre-push invocation skipped because no commit existed yet, so the complete commands were run directly instead. Normal commit/push hooks will run again.
- Native Windows execution of the POSIX CLI fixtures is explicitly skipped to prevent fallback to real Windows tools. Portable PowerShell on Linux is not native Windows provisioning acceptance.

The source changes and docs were self-reviewed. No affected-host configuration, plugin activation, daemon restart, model call, or archived fleet task change occurred.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Fixed Paseo Plain setup failing before installation because Paseo 0.8 rejects --home as a global CLI option.

Changes:

- All six setup scripts now pass the resolved PASEO_HOME through each child environment. Explicit local-host targeting and existing trust, source, preference, and cache safeguards remain unchanged.
- Updated the six version banners and their contract expectations. Ubuntu is version 244. Added maintainer guidance and documented home selection.
- Tightened the simulated CLI argument contract and added default/empty and relative custom-home regressions. The existing fresh-install test failed before the fix and passes afterward.

Validation:

- All 16 installer tests, the portable PowerShell wrapper and channel fixtures, complete Windows script parsing, ShellCheck, Bash syntax, all shell contracts, Markdownlint, whitespace checks, and the staged secret scan passed.
- Read-only checks with the real Paseo 0.8.0-beta.1 CLI confirmed supported arguments and JSON responses without changing reference configuration. A mutation check confirmed the home tests catch a missing environment override.
- No remote rollout or model call occurred. The affected machine still needs a new setup run. Native Windows provisioning and client appearance were not tested.
<!-- SECTION:FINAL_SUMMARY:END -->
