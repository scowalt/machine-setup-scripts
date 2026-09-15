---
id: TASK-33
title: Allow unrelated linked skills during full-suite installation
status: Done
assignee:
  - '@pi'
created_date: '2026-09-15 16:23'
updated_date: '2026-09-15 19:19'
labels:
  - setup
  - skills
  - bug
dependencies: []
references:
  - ubuntu.sh
  - tests/test_managed_skill_suite.py
  - tests/mock_managed_skills.py
  - tests/pi-skill-ownership-contract.sh
documentation:
  - README.md
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Ubuntu setup v256 aborts Matt Pocock installation when unrelated dangling omarchy links exist in the shared and Claude skill directories. Scope installation safety checks to the exact upstream skill selection without weakening protection for managed or newly discovered targets. Future setup runs only; no live or remote skill changes.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 An unrelated real or dangling skill link does not block a full Matt Pocock suite installation and remains unchanged with its target untouched.
- [x] #2 The complete upstream selection, including future names, is verified before destination mutation; links or unsafe artifacts at an actual installation target still fail safely.
- [x] #3 All six scripts preserve identical shared policy, full-depth copied installation, complete result and copy validation, existing opt-outs, custom profiles, inventory, retirements, runtime gates, and failure aggregation.
- [x] #4 Extracted-helper fixtures cover the observed two omarchy links, actual-target and future-name collisions, repeated runs, unsafe metadata, and available PowerShell wrappers without executing skills or changing live profiles.
- [x] #5 Affected contracts and lint pass; documentation and every modified setup version are updated.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Turn the observed shared/Claude dangling omarchy-link fixtures into regression tests and verify safe exact-selection discovery with the native skills CLI in a disposable HOME. Never execute installed skill content.
2. Validate the full upstream selection before checking only its installation destinations; bind discovery and installation to the same verified source so future upstream names cannot bypass link protection. Preserve unrelated links and existing metadata/runtime/opt-out/inventory behavior across all six scripts.
3. Extend inert Bash/PowerShell and optional native CLI fixtures for linked real targets, newly discovered name collisions, incomplete discovery, failures, custom profiles and repeated runs.
4. Update docs and script versions; run managed-skill, ownership, reliability and affected contracts plus lint and review. No live setup, remote mutations or dotfiles application.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Diagnosis reproduced both unrelated dangling links against v256: either link independently aborts preflight; removing both only in fixtures passes. Read-only host metadata confirms the links are omarchy, not Matt Pocock skills. Worktree fast-forwarded to origin/main 17c64dc. ShellCheck, Node and Python are available; isolated PowerShell runtime exists at /tmp/pi-shared-runtime-pwsh.2SlAPL/pwsh. Awaiting implementation-plan approval.

User approved the recorded implementation plan. Starting regression-first implementation with an isolated skills worker; parent agent retains task metadata, integration, versions, documentation and combined verification.

Integrated the isolated worker diff. One native skills CLI install in a disposable HOME supplies the complete selection and immutable promotion source, avoiding a second fetch/discovery step. Native --list plus --json is unsupported, so validating this staged installation and copying its exact files is the selected approach. All selected destinations, including future names, are checked before promotion; unrelated links remain untouched. Native source records are merged into the selected lock without changing unrelated entries.
Parent review added bounded Node staging disposal (unlink links instead of legacy PowerShell recursive junction traversal), cleanup independent of malformed global metadata, and PowerShell 5.1-compatible OS detection/environment restoration. The initial unrelated-link regression failed 12 cases before the worker fix. The integrated suite passes 29 tests with PowerShell and the offline native CLI, with only optional dotfiles rendering skipped so far. The remaining four skills/reliability shell contracts now pass. Docs and six version banners are updated; final combined validation is underway.

Final combined verification passed all 31 shell contracts with PowerShell coverage. The managed-skill suite passes all 29 tests with the offline native CLI and isolated dotfiles rendering enabled (no skips). Native source advancement after staging cannot change promoted names or bytes; external staging links are unlinked without modifying targets. All six helper copies match. ShellCheck, Bash syntax, Markdownlint, whitespace checks and the redacted diff secret scan pass. Native Windows filesystem execution remains unverified; no live setup or remote changes were performed.

User requested delivery to remote main. Confirmed origin/main is unchanged at 17c64dc, main is unprotected, and push permission is available. Preparing one ordinary fast-forward publication with TASK-34, hooks enabled; no force push or live setup.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Fixed unrelated skill links blocking the full Matt Pocock suite on future setup runs.

- All six scripts validate one disposable native installation, preflight the complete selected destinations, and promote that exact snapshot without another fetch. Existing and future-name target links remain blocked; unrelated live/dangling links and targets stay unchanged.
- Preserve effective npm configuration, selected profiles, native update records, opt-outs and unrelated metadata. Added bounded link-safe staging cleanup and Windows PowerShell 5.1-compatible environment handling.
- Updated documentation and setup versions alongside the Paseo fix.

Validation: all 29 managed-skill tests pass with PowerShell, offline native CLI and isolated dotfiles rendering; all 31 shell contracts, lint and secret review pass. No live setup, remote rollout, skill execution or native Windows filesystem smoke test.
<!-- SECTION:FINAL_SUMMARY:END -->
