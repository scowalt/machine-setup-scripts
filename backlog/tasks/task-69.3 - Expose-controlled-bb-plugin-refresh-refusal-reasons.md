---
id: TASK-69.3
title: Expose controlled bb plugin refresh refusal reasons
status: In Progress
assignee:
  - '@openai'
created_date: '2026-10-03 14:11'
updated_date: '2026-10-03 14:33'
labels: []
dependencies: []
references:
  - TASK-69
  - lib/bb-plugin-refresh.py
  - lib/bb-plugin-refresh.bash
  - tools/embed-bb-plugin-refresh.py
  - tests/test_bb_plugin_refresh.py
documentation:
  - docs/adr/0003-separate-bb-preparation-from-enrollment.md
  - docs/plans/2026-10-01-bb-plugin-refresh.md
  - docs/research/2026-10-01-bb-plugin-refresh-api.md
  - docs/research/2026-09-29-fixture-execution-audit.md
  - docs/research/2026-09-29-fixture-containment-incident.md
parent_task_id: TASK-69
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Child of TASK-69; its approved specification and safety boundaries are authoritative. Make bb plugin refresh refusal diagnostics useful and secret-safe while leaving permission validation, native identity/update semantics and lifecycle behavior unchanged. Parent AC8–9, the bb portions of AC10/13, and applicable preservation/synchronization requirements apply. Reuse definitions-only policy fixtures with synthetic local evidence and inert native/API operations plus real extracted wrappers/callers. Surface existing controlled reasons without arbitrary exceptions, paths, process arguments, configuration or credential output. The historical first bb failure remains unknown; a current group-writable data directory is a blocker, not license to chmod it. This ticket is initially ready in the dependency graph, but execution awaits the parent implementation-plan approval.
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
- [ ] #1 Attach contained regression/static evidence and explicit skips; do not claim native rollout.
<!-- DOD:END -->
