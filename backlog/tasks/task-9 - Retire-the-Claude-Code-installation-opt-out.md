---
id: TASK-9
title: Retire the Claude Code installation opt-out
status: Done
assignee:
  - '@pi'
created_date: '2026-09-06 22:47'
updated_date: '2026-09-06 22:56'
labels: []
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Always manage the native Claude Code CLI on supported machines, even when an existing environment contains BAN_CLAUDE_CODE=1. Keep the normal login command available alongside the Pi Claude bridge without implying that the bridge requires a separately installed executable.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 All six setup scripts install or update Claude Code on supported platforms regardless of BAN_CLAUDE_CODE=1, preserving platform and installer safety checks.
- [x] #2 New environment templates no longer advertise BAN_CLAUDE_CODE; existing environment files remain unchanged and active documentation states that the flag is ignored.
- [x] #3 All six setup script versions are incremented and regression tests cover the retired opt-out; relevant contract tests and lint checks pass.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Approved by Scott in conversation.

1. Remove the Claude Code opt-out checks and template entries from all six scripts while preserving platform checks, installer safety, and existing environment files.
2. Update current documentation, annotate the original plan as superseded, and increment each setup script version.
3. Add regression coverage for BAN_CLAUDE_CODE=1, run relevant contracts and lint, review the diff, and record results.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Removed the opt-out guards and template entries from all six setup scripts. Preserved platform guards and native installer safety logic, and incremented all six setup versions.
- Updated current docs and annotated the historical plan as superseded. Existing environment files remain untouched.
- New offline regression failed before the change (BAN_CLAUDE_CODE blocked fresh install), then passed for installs, updates, unsupported platforms, and environment-file preservation across all five Bash scripts. Windows static contracts and existing template contracts pass; pwsh is not installed here.

- Updated the existing version-banner assertions after the full suite exposed their stale expectations.
- Final verification: all 20 tests/*.sh suites pass. ShellCheck passes for the five modified Bash setup scripts and both affected shell tests. Markdownlint and git diff --check pass. Reviewed the complete diff; no authentication, real installation, shell-profile changes, or existing user-file edits occurred.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Removed the Claude Code setup opt-out across macOS, Ubuntu, WSL, Raspberry Pi, Bazzite, and Windows. Setup installs or updates the native CLI on supported platforms even when BAN_CLAUDE_CODE=1 remains set.

Changes:

- Removed the flag from installer guards and new environment templates without changing existing environment files or installer safety checks.
- Incremented all six setup versions, updated current guidance, and annotated the original plan as superseded.
- Added offline regression coverage for installs, updates, platform rejection, and environment-file preservation, and refreshed existing version-banner assertions.

Validation:

- All 20 Bash contract/regression suites pass.
- ShellCheck, Markdownlint, and git diff --check pass.
- Windows received static coverage only because PowerShell is unavailable on this machine. No live installation or authentication was performed.
<!-- SECTION:FINAL_SUMMARY:END -->
