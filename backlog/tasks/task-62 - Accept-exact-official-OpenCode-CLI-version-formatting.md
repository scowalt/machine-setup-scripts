---
id: TASK-62
title: Accept exact official OpenCode CLI version formatting
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
Implement section 3 of the user-approved upstream compatibility plan with unchanged verified-artifact probe and recovery boundaries.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Exact bare and opencode v expected versions pass including LF/CRLF; wrong versions, names, suffixes, empty/multiline/extra text fail.
- [x] #2 Nonzero, timeout, signal and output-limit probe failures remain failures; isolated environment and artifact verification before probes preserved.
- [x] #3 Staged/current/promoted installation paths covered; staged failure preserves prior command and post-promotion failure restores command/receipt; existing preservation policies unchanged.
- [ ] #4 Generator and all standalone copies versioned/consistent; Bash/PowerShell callers, affected contained matrix/static checks, docs and explicit skips/native limits recorded.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Follow approved docs/plans/2026-10-01-001-fix-setup-upstream-compatibility.md, section 3: add permanent contained red regression at its approved seam, make minimal shared fix, record green evidence, then run audited affected matrix/static checks and review boundaries. User explicitly approved implementation; no additional checkpoint. No live setup, optional integrations, commits or branch changes.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Approval confirmed by implementation request. Required Node, PowerShell and ShellCheck exist. Read full plan, repository guidance, fixture audit and incident record. Existing diagnosis establishes one-variable root causes; adapting permanent regressions at the approved seams rather than repeating exploratory hypotheses.

Contained red /tmp/setup-fixture-matrix-o_ko0wsy: 130 Node tests, 125 pass, 4 fail, 1 optional shim skip. Exact named probe/staged-current cases fail and promotion regressions stop at stage (1 vs 2 calls). Minimal exact equality fix in lib/opencode-cli.cjs v3 regenerated all six scripts. Green /tmp/setup-fixture-matrix-9rehg_xh: contract passes (130 Node tests, 129 pass, 1 optional shim skip; 7 caller tests pass). Native output is injected at execFileSync boundary; no application runs. Wrong content and native error simulations preserve controlled diagnostics/recovery. Docs and six setup version increments now updated; full matrix/static checks pending.

Final affected matrix /tmp/setup-fixture-matrix-x0r0i4o2: 21/21 entries pass, including 130 OpenCode Node tests (129 pass/1 optional installed shim skip) and 7 Bash/PowerShell caller methods. Generated policy and versioned scripts consistent; ShellCheck and syntax/parser/static checks pass. Exact invocation, all skips, native limitations and self-review are attached. Trusted installed Markdownlint unavailable, so AC4 stays unchecked and task stays In Progress pending parent disposition. No OpenCode application executed; process results/errors injected before intentional real probe/install execution.

User requested publication to remote main. Integrated cf1ac23 without changing its concise README or upstream behavioral/test intent; Go task collision resolved via CLI as TASK-63, leaving upstream TASK-60 untouched. Fresh integrated matrix /tmp/setup-fixture-matrix-q5f497vx passed 25/25 entries with the documented optional skips. Existing system ShellCheck, Bash/Node/Python/PowerShell parsing, generator consistency, whitespace, and supplemental CommonMark/closed-fence/local-link checks passed. Markdownlint remains unavailable (cached entry points are world-writable and were not executed); task remains In Progress for that gap. Publication will suppress unsafe automatic hooks only per command and perform staged secret scanning manually. No native rollout or BB changes.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
OpenCode version probes now accept exactly the expected bare version or official opencode v<version> line after existing whitespace normalization. Byte verification before probing, isolated environment, native success requirement and restoration behavior remain unchanged.

Added exact/malformed output, process error, staged/promoted/current path and command/receipt recovery regressions. Regenerated all six standalone entry points and updated versions/docs. Contained red/green and passing 21-entry matrix are recorded in the validation report.

Self-review complete; automated Markdownlint unavailable and native rollout/optional installed npm shim unverified. Task remains In Progress.
<!-- SECTION:FINAL_SUMMARY:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 Self-review complete; red/green evidence and final summary recorded
<!-- DOD:END -->
