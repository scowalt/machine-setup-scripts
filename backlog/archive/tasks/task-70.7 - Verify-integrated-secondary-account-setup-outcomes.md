---
id: TASK-70.7
title: Verify integrated secondary-account setup outcomes
status: To Do
assignee:
  - '@openai'
created_date: '2026-10-03 15:21'
updated_date: '2026-10-03 15:23'
labels: []
dependencies: []
references:
  - TASK-70
  - tests/run-fixture-matrix.py
  - tests/extract_setup_fixture.py
  - tests/setup-default-contract.sh
  - tests/setup-reliability-contract.sh
  - tests/test_opencode_cli_callers.py
  - tests/test_bb_plugin_refresh.py
parent_task_id: TASK-70
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Child of TASK-70, blocked by its two component tickets. Deliver evidence that the combined source preserves accurate setup outcomes and safety boundaries across standalone platforms, rather than merely passing each component's isolated tests. Parent AC10–14 and the complete parent specification are authoritative. Reuse the existing real caller/finalization acceptance seam and audited sequential fixture matrix; add only necessary cross-component regression coverage. Include synchronized generated source, version reconciliation and two-axis standards/spec review of the integration branch. Keep native rollout, machine repairs, skill cleanup, worker pushes and PRs out of scope (parent publication now explicitly authorized). This is a final-source behavioral/integration contract, not authorization to execute live setup or applications.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Actual extracted callers exercise corrected OpenCode behavior and preserved upstream Infisical non-management together with independent BB/other failures and prove that unaffected work and logging continue while the final status remains accurate.
- [ ] #2 The merged standalone scripts preserve every parent safety/platform/headless/readiness boundary, synchronized shared policies and accurate incremented versions; no skill-collision, shell ownership or unrelated policy changes enter the diff.
- [ ] #3 Mandatory containment/default/extraction checks and the audited affected matrix run sequentially on the final integration source with explicit existing tools, private roots/stdio and inert operations; missing coverage and native limitations are accurately recorded.
- [ ] #4 Standards and spec reviews compare against the pinned integration baseline; all actionable findings are fixed and affected checks rerun without expanding the approved scope.
- [ ] #5 Every parent/child acceptance criterion and DoD is backed by evidence before Backlog closure; local integration history is coherent and child worktrees are removed only after their work is merged and safe to retain. Parent publishes only after final-source verification; no native rollout occurs.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Canonical replacement is TASK-71.3. This intermediate renumbering is archived to avoid the already existing concurrent TASK-70 Beszel graph. No completion claimed.
<!-- SECTION:NOTES:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 Record contained regression/static evidence, review outcome and explicit skips without native rollout claims.
<!-- DOD:END -->
