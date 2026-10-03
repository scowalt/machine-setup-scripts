---
id: TASK-71.2
title: Expose controlled bb plugin refresh refusal reasons
status: In Progress
assignee:
  - '@openai'
created_date: '2026-10-03 15:23'
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
- [ ] #1 Filesystem trust, discovery/identity, native-contract, operation, malformed-result and verification failures produce finite operation/reason diagnostics with controlled unknown fallback and no secret/path/raw-error leakage.
- [ ] #2 Existing bb permission checks remain verification-only; fixture state demonstrates no chmod/chown, new group-write exception, lifecycle recovery, application execution or identity bypass.
- [ ] #3 Native source/pin/disabled-state preservation, stopped/safe-mode/readiness deferrals and failed/unverified outcome semantics remain unchanged; independent failures survive later success and secondary diagnostic failures.
- [ ] #4 Extracted real wrapper/caller fixtures retain nonzero failure aggregation, unrelated-work continuation and log finalization, rejecting unrecognized helper output.
- [ ] #5 Shared policy/wrapper embeddings remain identical with incremented modified-script versions; focused contained red/green, BB regressions and static checks are recorded without live daemon inventory, plugin/API requests or installed-code imports.
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 Record contained regression/static evidence, review outcome and explicit skips without native rollout claims.
<!-- DOD:END -->
