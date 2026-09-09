---
id: TASK-13
title: Stop restoring the removed pi-prose package and defaults
status: Done
assignee:
  - '@pi'
created_date: '2026-09-09 00:04'
updated_date: '2026-09-09 18:07'
labels: []
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Remove setup and dotfiles automation that reinstalls pi-prose or seeds matter-of-fact. Preserve all existing custom prose files and unrelated Pi settings. The approved Paseo rewriter is a separate local plugin project.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 All platform setup scripts stop installing pi-prose and stop seeding prose configuration; affected versions are incremented.
- [x] #2 Dotfiles stop listing pi-prose and no longer manage a prose seed file, without deleting any deployed custom prose files.
- [x] #3 Relevant documentation and offline tests reflect removal; shellcheck, contract tests, and available model-default tests pass.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Cleanup was approved in the preceding conversation.

1. Remove pi-prose package entries, seed functions, and seed calls from all six setup scripts; increment each version.
2. Remove only the dotfiles source seed and package entry; never run chezmoi apply or delete deployed prose files.
3. Replace the old installation contract with a no-restoration contract and update model-default fixtures/docs.
4. Run targeted tests, shellcheck, syntax checks, and diff review. Keep changes local and separate from the plugin repository.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Removed pi-prose entries and seed functions/calls from all six setup scripts; incremented each version. Removed only the dotfiles source seed, not deployed prose files. Both shell contracts, ShellCheck on modified shell files, four setup model-default tests, three dotfiles template tests, Markdownlint, and diff checks pass. PowerShell runtime is unavailable, so Windows has static coverage only. Changed-code secret scans pass. The complete setup-tree scan reports one pre-existing generic-api-key finding at bazzite.sh:26, the DOTFILES_ACCESS_METHOD assignment; that line is byte-identical to HEAD and is not part of this change.

Final live-state verification found pi-prose restored before this task began: settings.json mtime 23:18 UTC, before source work began at 23:36. Removed that package again with pi remove npm:pi-prose. Verified all other settings were identical and every existing prose file remained unchanged. The stock live prose configuration is intentionally preserved, but the package is inactive.

Follow-up TASK-14 validation with portable PowerShell found and fixed a trailing comma in the remaining one-item companion-package array. Full win.ps1 syntax now passes; this is not a native Windows provisioning test.

The setup-script portion is now published to origin/main in 44534cd6d0c90f3669796cea891ca79492390e67 together with Paseo Plain integration. Existing custom prose files remain untouched. This publication did not push or apply the separate dotfiles checkout.

Scott explicitly requested publication of the task records to remote main after the setup source was published.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Published the setup-script cleanup in [44534cd](https://github.com/scowalt/machine-setup-scripts/commit/44534cd6d0c90f3669796cea891ca79492390e67).

- Removed package/default automation from all six platforms and incremented script versions.
- Removed the dotfiles package entry and source seed locally, without changing deployed custom prose files. The setup publication did not push or apply the separate dotfiles checkout.
- Added no-restoration and preservation checks, while retaining package-preservation model tests.

Validation: shell contracts, ShellCheck, setup and dotfiles Python tests, Markdownlint, and secret scans passed. Follow-up portable PowerShell validation fixed a trailing comma and confirmed win.ps1 syntax. Native Windows provisioning remains unverified.

Live cleanup: pi-prose reappeared before this task started. Removed its package with the Pi CLI and confirmed that all other Pi settings and existing prose files remained unchanged.
<!-- SECTION:FINAL_SUMMARY:END -->
