---
id: TASK-40
title: Report incomplete Homebrew updates in the macOS setup result
status: Done
assignee:
  - '@pi'
created_date: '2026-09-21 15:59'
updated_date: '2026-09-21 16:46'
labels: []
dependencies: []
documentation:
  - docs/plans/2026-09-19-001-fix-homebrew-results-and-paseo-inventory-plan.md
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Implement approved audit design fix 1: Homebrew command and verification failures must reach the final result without stopping unrelated work or log finalization.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Update, upgrade, required unpin, verification failures and unresolved unpinned or trust-skipped work return nonzero; intentional pins remain respected.
- [x] #2 macOS aggregates failures through final completion and logging while preserving earlier errors and tmux cleanup.
- [x] #3 Extracted helper and caller regression fixtures pass without live setup or package-manager mutations; modified script version and documentation are updated.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
User approved the implementation plan and helper/caller test seams.

1. Add a failing extracted macOS Homebrew caller fixture.
2. Propagate required phase and verification failures while retaining cleanup and log finalization.
3. Extend edge-case coverage, bump version, run reliability tests and ShellCheck.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Moved approved design onto current upstream on fix/setup-results-and-process-inventory. Red/green caller fixture reproduced final success after brew upgrade failure; implementation now propagates command and postcheck failures through the actual final caller/main seam. Six extracted helper/caller tests and setup-reliability-contract.sh pass. No live setup or package operations run.

Review added a red/green fixture for pre-existing tmux pins: setup now verifies the pin baseline and owns only its temporary pin. Seven Homebrew caller tests pass, including preflight/post-upgrade pin inventory failures. README and agent guidance now describe incomplete results. No live Homebrew operation was performed.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
## Summary

```text
Homebrew phase / required verification fails
  -> retain setup error
  -> finish unaffected work and log
  -> exit nonzero
Existing user pin -> preserved
```

## Evidence

- **Before:** the extracted upgrade-failure fixture printed Setup complete and finalized status 0. Existing tmux pins were unpinned.
- **After:** all 7 Homebrew helper/caller tests and the setup reliability contract pass, including pin preservation, failed postchecks and retained earlier errors. ShellCheck and Bash syntax checks pass; README and agent guidance updated.

## Merge Danger

**Door:** two-way.
**Blast Radius:** macOS setup now reports incomplete Homebrew work as failure while still finalizing logs. No automatic CLT, cask or trust remediation. Native macOS execution was not performed.
<!-- SECTION:FINAL_SUMMARY:END -->
