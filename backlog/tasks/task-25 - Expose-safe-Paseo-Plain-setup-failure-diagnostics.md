---
id: TASK-25
title: Expose safe Paseo Plain setup failure diagnostics
status: Done
assignee:
  - '@codex'
created_date: '2026-09-12 16:58'
updated_date: '2026-09-12 18:13'
labels:
  - bug
  - setup
  - diagnostics
dependencies: []
references:
  - ubuntu.sh
  - tests/test_paseo_plain_setup.py
  - 'https://logs.scowalt.com/logs/arcane/2026-09-11-18-54-46-585.log'
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Arcane reports that Paseo Plain setup could not finish, but the embedded installer discards the failed operation and reason. Improve diagnostics rather than guessing or resetting live plugin state.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 All six identical embedded installers identify the failed operation and a safe reason or exit status for command, timeout, validation, and migration failures.
- [x] #2 Diagnostics never print credentials, raw sensitive command output, or plugin preferences, and preserve current local-daemon targeting and migration recovery safeguards.
- [x] #3 Isolated failure fixtures verify diagnostic usefulness and secret redaction without starting or modifying live Paseo daemons.
- [x] #4 Modified script versions, documentation, and applicable checks are updated.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Review the existing embedded installer failure paths and tests; do not assume the cause of Arcane's failure.
2. Add isolated command, timeout, validation, and migration failure fixtures with sensitive-output sentinels.
3. Emit bounded operation labels and allowlisted reason/exit codes while preserving recovery behavior and excluding raw command output or secret-bearing values. Keep all six embedded installers identical.
4. Run Paseo Plain and fixture-isolation suites, plus available Windows wrapper tests; update versions/docs and self-review.
Approval gate: share this plan with the user and wait before code changes. No live Paseo calls, fleet rollout, or delegation.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
User approved the implementation plan. Proceeding directly with isolated regression fixtures; no delegation or live fleet changes.

Added a failing diagnostic regression, then safe operation/reason reporting in all six embedded installers. Command failures, timeouts, invalid responses, malformed local JSON, and migration validation are covered; raw sensitive output stays suppressed.

Final validation: 35 embedded-installer tests plus native source/config manager migration and poisoned-Git fixture isolation passed. Unknown errors report unexpected-error rather than inventing a filesystem cause. All six embedded engines remain identical. No daemon listener, plugin execution, model request, or live migration occurred. All 26 shell contracts and lint pass.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Expose safe Paseo Plain failure diagnostics without resetting plugin state or guessing the cause of Arcane failures.

- Identify controlled operation labels with exit codes, timeouts, invalid JSON, migration validation reasons, and bounded filesystem codes.
- Suppress arbitrary exception text, raw command output, preferences, and credentials.
- Preserve local-daemon targeting, migration journals, private backups, and manual recovery requirements.

Validation: 35 installer tests and native source-manager migration/fixture-isolation tests pass. All six embedded installers match; script versions/docs are updated. All 26 shell contracts and lint pass. Native Windows provisioning remains untested.
<!-- SECTION:FINAL_SUMMARY:END -->
