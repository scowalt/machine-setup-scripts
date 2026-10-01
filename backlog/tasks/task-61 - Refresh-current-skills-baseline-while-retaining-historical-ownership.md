---
id: TASK-61
title: Refresh current skills baseline while retaining historical ownership
status: In Progress
assignee:
  - '@implementation-worker'
created_date: '2026-10-01 14:35'
updated_date: '2026-10-01 15:32'
labels: []
dependencies: []
references:
  - docs/research/2026-10-01-upstream-compatibility-validation.md
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Implement section 2 of the user-approved upstream compatibility plan without weakening complete snapshot validation or deleting historical copies during ordinary installation.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Reviewed current 37-skill snapshot with pr and future names promotes from one verified snapshot without recreating resolving-merge-conflicts; missing required names fail regardless of count.
- [x] #2 Historical resolving-merge-conflicts survives inventory, offline opt-out and Pi exclusions without new ordinary deletion; identical/modified duplicate ownership and unrelated state preserved.
- [x] #3 Invalid reports, partial copies, unsafe links, metadata and source mismatches still fail; both opt-outs, personal/work and six identical policies covered.
- [ ] #4 Fixture provenance, README and guidance updated; versions, contained regressions/matrix and static checks recorded with skips and native limits.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Follow approved docs/plans/2026-10-01-001-fix-setup-upstream-compatibility.md, section 2: add permanent contained red regression at its approved seam, make minimal shared fix, record green evidence, then run audited affected matrix/static checks and review boundaries. User explicitly approved implementation; no additional checkpoint. No live setup, optional integrations, commits or branch changes.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Approval confirmed by implementation request. Required Node, PowerShell and ShellCheck exist. Read full plan, repository guidance, fixture audit and incident record. Existing diagnosis establishes one-variable root causes; adapting permanent regressions at the approved seams rather than repeating exploratory hypotheses.

Permanent reviewed-current fixture (d81f3a183412e71a5b1e84ca21bc1a35eea03a60) red at /tmp/setup-fixture-matrix-wt0ourfl: 32 methods, 69 expected-success failures, 3 optional skips; current promotion reports incomplete-suite. Minimal fix replaces required resolving-merge-conflicts with pr and adds historical ownership to inventory, not obsolete deletion. Green /tmp/setup-fixture-matrix-ev8fauxt: 32 methods/3 optional skips, ownership and managed-agent contracts pass. Added all 37 missing-name cases with extra future name, exact current promotion, historical preservation/inventory/no-inventory opt-outs and identical-vs-modified Pi duplicates. Docs/version/full matrix pending.

Final affected matrix /tmp/setup-fixture-matrix-x0r0i4o2: 21/21 entries pass. Skills 32 methods/3 optional skips, repeated by weekly; all ownership/agent contracts pass. Static comparison confirms all 37 fixture names exactly match retained public upstream tree d81f3a183412e71a5b1e84ca21bc1a35eea03a60. README/CLAUDE updated without stale experimental category counts; all six copies identical and versioned. Full per-suite results/skips/static checks and self-review in attached report. Trusted Markdownlint unavailable: AC4 unchecked and status In Progress pending parent disposition. No real dotfiles repository changes or native skill execution.

User requested publication to remote main. Integrated cf1ac23 without changing its concise README or upstream behavioral/test intent; Go task collision resolved via CLI as TASK-63, leaving upstream TASK-60 untouched. Fresh integrated matrix /tmp/setup-fixture-matrix-q5f497vx passed 25/25 entries with the documented optional skips. Existing system ShellCheck, Bash/Node/Python/PowerShell parsing, generator consistency, whitespace, and supplemental CommonMark/closed-fence/local-link checks passed. Markdownlint remains unavailable (cached entry points are world-writable and were not executed); task remains In Progress for that gap. Publication will suppress unsafe automatic hooks only per command and perform staged secret scanning manually. No native rollout or BB changes.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Refreshed the required current baseline to pr instead of upstream-retired resolving-merge-conflicts, preserving historical managed ownership separately for inventory, opt-outs and Pi exclusions. Ordinary installation preserves historical copies; existing identical-Pi-duplicate rules remain. Complete snapshot validation and single-snapshot promotion are unchanged.

Added exact-current snapshot, every-required-name omission despite constant cardinality, future-name and historical preservation/cleanup regressions. Updated fixture provenance and repository docs; contained red/green and passing 21-entry matrix are recorded in the validation report.

Self-review complete. Trusted Markdownlint remains unavailable; optional native CLI/dotfiles checks skipped. Task remains In Progress rather than claiming unverified validation complete.
<!-- SECTION:FINAL_SUMMARY:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 Self-review complete; red/green evidence and final summary recorded
<!-- DOD:END -->
