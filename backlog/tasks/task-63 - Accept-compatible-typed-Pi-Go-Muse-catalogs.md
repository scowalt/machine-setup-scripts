---
id: TASK-63
title: Accept compatible typed Pi Go Muse catalogs
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
Implement section 1 of the user-approved upstream compatibility plan; preserve credential and catalog safety.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Legacy and typed catalogs succeed through extracted helpers and Bash/PowerShell wrappers; callers continue only on compatible catalogs.
- [x] #2 Missing, duplicate, wrong key/group/type/provider/API/endpoint/reasoning/xhigh catalogs fail before mutation; trust, locking, profiles and unrelated credentials/defaults remain protected.
- [ ] #3 All six helpers identical, versioned; permanent regressions and affected contained matrix/static checks recorded with skips and native limits.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Follow approved docs/plans/2026-10-01-001-fix-setup-upstream-compatibility.md, section 1: add permanent contained red regression at its approved seam, make minimal shared fix, record green evidence, then run audited affected matrix/static checks and review boundaries. User explicitly approved implementation; no additional checkpoint. No live setup, optional integrations, commits or branch changes.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Approval confirmed by implementation request. Required Node, PowerShell and ShellCheck exist. Read full plan, repository guidance, fixture audit and incident record. Existing diagnosis establishes one-variable root causes; adapting permanent regressions at the approved seams rather than repeating exploratory hypotheses.

Contained red: /tmp/setup-fixture-matrix-dr98hvd5 (setup-default and containment pass; Go 24 methods/2 skips, typed helper+all wrappers fail, explicit legacy non-chat rejection fails; wiring 5 methods/6 typed subcase failures). Negative subcases now reset fixture auth to avoid cascading red noise. Minimal identical helper accepts legacy or exact chat key and requires chat type when typed/present. Green: /tmp/setup-fixture-matrix-gq7flp2p, Go 24 methods/2 optional installed catalog+lock skips, wiring 5 methods/0 skips. Real wrappers now drive catalog gating in all extracted callers. Versions/docs/full matrix still pending.

Final affected matrix: /tmp/setup-fixture-matrix-x0r0i4o2, 21/21 entries status 0. Exact command, per-suite counts/skips, public fixture comparison and static evidence are in the attached validation report. All six Go/skills helpers identical; setup versions bumped once for this uncommitted delivery. ShellCheck, Bash/Node/Python syntax, full PowerShell AST parsing (136 functions), generator --check and diff whitespace checks pass. Self-review found no scope/policy drift. Automated Markdownlint unavailable; no fetch or untrusted cache fallback. AC3 remains unchecked and task remains In Progress pending parent disposition of that validation gap. No live/native rollout claim.

Publication integration: origin/main cf1ac23 already owns unrelated TASK-60 (README cleanup). Used CLI task demote 60 -> DRAFT-1 -> draft promote to allocate TASK-63 while preserving the Go task content. Updated plan/evidence references; upstream TASK-60 remains untouched.

User requested publication to remote main. Integrated cf1ac23 without changing its concise README or upstream behavioral/test intent; Go task collision resolved via CLI as TASK-63, leaving upstream TASK-60 untouched. Fresh integrated matrix /tmp/setup-fixture-matrix-q5f497vx passed 25/25 entries with the documented optional skips. Existing system ShellCheck, Bash/Node/Python/PowerShell parsing, generator consistency, whitespace, and supplemental CommonMark/closed-fence/local-link checks passed. Markdownlint remains unavailable (cached entry points are world-writable and were not executed); task remains In Progress for that gap. Publication will suppress unsafe automatic hooks only per command and perform staged secret scanning manually. No native rollout or BB changes.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Implemented exact legacy/chat-prefixed built-in Muse catalog compatibility across all six entry points. Typed/present type must be chat; semantic uniqueness and exact model compatibility remain mandatory before credentials change. Credential trust/locking and controlled errors are unchanged.

Added public Pi AI 0.99.2 fixture, positive/negative helper and wrapper regressions, and real-catalog caller gates. Contained red/green evidence and the passing 21-entry affected matrix are recorded in the validation report. Docs and versions updated; self-review complete.

Remaining validation gap: trusted Markdownlint unavailable. Optional installed/native integrations remain explicitly skipped; task not marked Done.
<!-- SECTION:FINAL_SUMMARY:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 Self-review and documentation complete; red/green evidence and final summary recorded
<!-- DOD:END -->
