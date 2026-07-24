---
id: TASK-1
title: Remove Compound Engineering setup
status: Done
assignee:
  - '@scowalt'
created_date: '2026-07-23 22:59'
updated_date: '2026-07-23 23:24'
labels: []
dependencies: []
references:
  - docs/plans/2026-07-23-001-refactor-remove-compound-engineering-setup-plan.md
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Execute docs/plans/2026-07-23-001-refactor-remove-compound-engineering-setup-plan.md: replace active Compound setup with safe cleanup across all platform scripts and align active documentation.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 All setup scripts remove active Compound install, sanitize, link, and skip-flag flows while retaining safe cleanup.
- [x] #2 Legacy Compound cleanup is idempotent and preserves unrelated Pi, Codex, and user-owned resources.
- [x] #3 README, CLAUDE, and generated env templates remove Compound setup and skip-flag guidance; all script version banners are updated.
- [x] #4 Shell, PowerShell, Markdown, and active-content validation pass; historical plans remain unchanged.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Compare the existing Bash and PowerShell Compound flows with the safe Matt Pocock cleanup patterns.
2. Add narrowly guarded cleanup helpers, then remove Compound installation/sanitization/call paths across all platform scripts.
3. Remove active documentation and generated-template references; update every modified script version banner.
4. Run static validation and active-surface scans, self-review path guards, then record completion.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Started implementation from the approved plan on branch remove-compound-engineering-plugins.

- Replaced Compound installation/sanitization flows with non-fatal, path-guarded legacy cleanup across six Bash scripts and Windows PowerShell.
- Removed Compound skip flags and setup claims from generated templates and active documentation; incremented all setup-script banners.
- Validated Bash syntax, ShellCheck, cleanup behavior in temporary filesystem sandboxes, active-flow scans, README markdownlint, and git diff --check.
- PowerShell parser validation was not run because neither pwsh nor Windows PowerShell is installed in this environment.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Removed setup-managed Compound Engineering across all platform scripts.

Changes:
- Replaced installer, sanitizer, and Codex-link flows with idempotent cleanup that only targets known legacy artifacts and preserves unrelated resources.
- Removed Compound skip flags and active documentation claims; bumped every modified setup-script version banner.
- Updated the execution plan status to completed.

Validation:
- Bash syntax and ShellCheck across all Bash setup scripts
- Temporary-filesystem cleanup behavior and safety checks
- Active-flow content scans, README markdownlint, and git diff --check
- PowerShell parser unavailable in this Linux environment
<!-- SECTION:FINAL_SUMMARY:END -->
