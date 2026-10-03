---
id: TASK-69.1
title: Verify Infisical absence without sudo
status: In Progress
assignee:
  - '@openai'
created_date: '2026-10-03 14:11'
updated_date: '2026-10-03 14:33'
labels: []
dependencies: []
references:
  - TASK-69
  - ubuntu.sh
  - wsl.sh
  - pi.sh
  - tests/test_infisical_apt_retirement.py
  - tests/test_infisical_native_retirement.py
  - tests/test_infisical_callers.py
  - tests/infisical-retirement-contract.sh
documentation:
  - docs/adr/0001-keep-cleanup-for-retired-managed-tools.md
  - docs/research/2026-09-29-fixture-execution-audit.md
  - docs/research/2026-09-29-fixture-containment-incident.md
parent_task_id: TASK-69
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Child of TASK-69; its approved specification and safety boundaries are authoritative. Deliver privilege-independent positive verification of an already-absent native Infisical package and official APT sources, while retaining privileged, narrowly scoped retirement when needed. Cover all existing APT retirement callers and controlled diagnostics. Parent AC1–3, the Infisical portions of AC8/10/13, and applicable preservation/synchronization requirements apply. Reuse the existing extracted actual retirement helper, structured source inspection, native inventory, and real caller/finalization fixture seams. No live setup, system metadata mutation, privilege grants, or broad source-parser redesign. This ticket is initially ready in the dependency graph, but execution awaits the parent implementation-plan approval.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Verified supported absent/not-installed package state plus verified clean official APT source state succeeds without sudo or mutation; the regression is red on the prior code and green with the actual observation flow.
- [ ] #2 Trusted root-owned system metadata remains verifiable without relaxing ownership/link/ambiguity/change checks; unavailable inventory or unsafe/unverified evidence fails closed.
- [ ] #3 Required retirement without privilege fails with a finite operation/reason diagnostic. Existing authorized removal, all-candidate preflight, independent postchecks, unrelated-state preservation and APT update gates remain intact.
- [ ] #4 Contained real caller tests prove correct failure aggregation, continued unrelated work and log finalization; sentinel secrets/paths and arbitrary native errors never escape diagnostics.
- [ ] #5 Applicable helper copies remain identical; modified script versions are incremented; focused contained contracts and static checks have recorded evidence without live operations or weakened containment.
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 Attach contained regression/static evidence and explicit skips; do not claim native rollout.
<!-- DOD:END -->
