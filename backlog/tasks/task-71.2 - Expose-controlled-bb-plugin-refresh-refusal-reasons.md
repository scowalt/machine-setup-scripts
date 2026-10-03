---
id: TASK-71.2
title: Expose controlled bb plugin refresh refusal reasons
status: Done
assignee:
  - '@openai'
created_date: '2026-10-03 15:23'
updated_date: '2026-10-03 15:50'
labels: []
dependencies: []
parent_task_id: TASK-71
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Child of TASK-71; its approved specification and safety boundaries are authoritative. Make bb plugin refresh refusal diagnostics useful and secret-safe while leaving permission validation, native identity/update semantics and lifecycle behavior unchanged. Parent AC8–9, the bb portions of AC10/13, and applicable preservation/synchronization requirements apply. Reuse definitions-only policy fixtures with synthetic local evidence and inert native/API operations plus real extracted wrappers/callers. Surface existing controlled reasons without arbitrary exceptions, paths, process arguments, configuration or credential output. The historical first bb failure remains unknown; a current group-writable data directory is a blocker, not license to chmod it. This ticket is ready in the dependency graph; the user has approved execution.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Filesystem trust, discovery/identity, native-contract, operation, malformed-result and verification failures produce finite operation/reason diagnostics with controlled unknown fallback and no secret/path/raw-error leakage.
- [x] #2 Existing bb permission checks remain verification-only; fixture state demonstrates no chmod/chown, new group-write exception, lifecycle recovery, application execution or identity bypass.
- [x] #3 Native source/pin/disabled-state preservation, stopped/safe-mode/readiness deferrals and failed/unverified outcome semantics remain unchanged; independent failures survive later success and secondary diagnostic failures.
- [x] #4 Extracted real wrapper/caller fixtures retain nonzero failure aggregation, unrelated-work continuation and log finalization, rejecting unrecognized helper output.
- [x] #5 Shared policy/wrapper embeddings remain identical with incremented modified-script versions; focused contained red/green, BB regressions and static checks are recorded without live daemon inventory, plugin/API requests or installed-code imports.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implemented in 7b975c3 and integrated with current main d1a8bd0 at 23947aa. MERGE-BB-RESULT.md records 17/17 contained suites passing, 362 unittest executions including five optional skips, native Linux PowerShell wrappers, static/embedding/secret checks and preserved Infisical non-management/BB empty-drop-in behavior. Original red/green evidence is TASK-69.3-RESULT.md. Final combined-source standards/spec review remains on the parent/integration ticket.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
BB plugin refresh now reports finite operation/reason refusal labels while suppressing raw exceptions, paths, credentials and malformed helper output. Original failures survive independent success and cleanup; existing trust, permission, source/update and lifecycle boundaries remain unchanged.
Validation: 33 focused BB methods plus 17/17 integrated contained suites, static/embedding/ShellCheck and redacted secret scans. Five optional integration skips; native rollout remains unverified. See /tmp/task69-implementation.2W3se2/MERGE-BB-RESULT.md.
<!-- SECTION:FINAL_SUMMARY:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 Record contained regression/static evidence, review outcome and explicit skips without native rollout claims.
<!-- DOD:END -->
