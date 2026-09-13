---
id: TASK-23
title: Report managed Pi package failures in setup results
status: Done
assignee:
  - '@codex'
created_date: '2026-09-12 16:58'
updated_date: '2026-09-12 18:13'
labels:
  - bug
  - setup
  - pi
dependencies: []
references:
  - ubuntu.sh
  - bazzite.sh
  - win.ps1
  - 'https://logs.scowalt.com/logs/devinabox/2026-09-12-14-35-19-317.log'
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The weekly audit found setup success banners after failed Pi installs and removals. Extracted-function probes confirmed failure swallowing across all five Bash scripts; Windows has equivalent handlers. Distinguish existing registrations from successful updates and preserve best-effort continuation and log finalization.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Failed required managed Pi package installs, removals, or validation produce a nonzero final setup result on every supported platform, while unaffected work and log finalization still run.
- [x] #2 Success output does not imply successful updates solely because old package registrations exist; intentional opt-outs and absent legacy packages remain successful no-ops.
- [x] #3 Fixtures reproduce the audit failures, verify final status and log behavior, and cover Bash plus PowerShell without changing live agent state.
- [x] #4 Modified script versions, documentation, and applicable checks are updated.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Recreate the audit failing-function probes and review package maintenance plus final-result/log wiring on every platform.
2. Add failure fixtures for installs, removals, validation, stale registrations, opt-outs, and final status.
3. Return meaningful helper failures, aggregate them while continuing unaffected work, and remove misleading success claims without breaking log finalization.
4. Test across Bash and PowerShell, including existing setup-reliability regressions; update versions/docs and record any independent baseline failures separately.
Approval gate: share this plan with the user and wait before code changes. No live setup runs or delegation.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
User approved the implementation plan. Proceeding directly with isolated regression fixtures; no delegation or live fleet changes.

54 helper failure/validation cases reproduced before fixes. New orchestration fixtures exercise each real setup tail/entrypoint, proving failed final results, no success banner, continued unrelated work, and log finalization across all six scripts. Bazzite now has a final error accumulator. Failed retirement or unsafe metadata blocks Pi operations but does not skip unrelated work or final logs.

Final regression run passed all 26 shell contracts, including log finalization, shared Node PowerShell fixtures (959 assertions), and per-platform final-status fixtures. Self-review preserved the retirement safety gate: a failed retirement blocks Pi operations, not unrelated work or log finalization. The broad optional PowerShell PR Lens assertion fails identically on bcc7383 and remains TASK-19.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Make managed Pi package failures reach the final setup result on all six platforms.

- Return failures for required installs, removals, inconclusive validation, and shortcut setup.
- Do not print goal/autoresearch active after failed updates merely because registrations remain.
- Aggregate failures while continuing safe unrelated work and finalizing logs. Bazzite now checks its final error accumulator.
- Keep intentional opt-outs and absent legacy packages successful. Block unsafe package operations after retirement or metadata preflight failures.

Validation: all 26 contract suites, ShellCheck, Markdownlint, and isolated Bash/PowerShell failure and log fixtures pass. An unrelated pre-existing PowerShell PR Lens failure remains tracked in TASK-19.
<!-- SECTION:FINAL_SUMMARY:END -->
