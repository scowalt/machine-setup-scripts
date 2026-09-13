---
id: TASK-24
title: Keep Linux Codex installation from modifying shell profiles
status: Done
assignee:
  - '@codex'
created_date: '2026-09-12 16:58'
updated_date: '2026-09-12 18:13'
labels:
  - bug
  - setup
  - codex
dependencies: []
references:
  - ubuntu.sh
  - wsl.sh
  - pi.sh
  - bazzite.sh
  - 'https://logs.scowalt.com/logs/arcane/2026-09-11-18-54-46-585.log'
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Eighteen audited Linux setup runs report that the native Codex installer adds PATH to .profile after Chezmoi applies dotfiles. Setup must install the native per-user CLI without taking ownership of shell configuration.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Ubuntu, WSL, Raspberry Pi, and Bazzite install or update the native per-user Codex CLI without creating or changing shell profiles or shell configuration.
- [x] #2 Codex remains available at the canonical per-user path and passes its existing Node-free smoke test; macOS and Windows installation behavior is preserved.
- [x] #3 Repeated-run and failure fixtures verify byte-identical existing profiles, absence of newly created profiles, and preserved installer failure reporting.
- [x] #4 Modified script versions, documentation, and applicable checks are updated.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Inspect the official Codex installer for a supported no-profile-modification option; prefer it if verifiable, otherwise use an authenticated/checksummed native release-binary installation path with the existing per-user and Node-free guarantees.
2. Add isolated clean-home, existing-profile, repeat-run, and failure fixtures that assert shell configuration remains untouched.
3. Fix the four Linux entry points without altering macOS/Windows installation behavior or adding shell-profile configuration.
4. Run Codex, shared-runtime, and reliability tests; update script versions/docs and self-review.
Approval gate: share this plan with the user and wait before code changes. Do not install or update the live Codex CLI; no delegation.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
User approved the implementation plan. Proceeding directly with isolated regression fixtures; no delegation or live fleet changes.

Red/green profile fixtures passed for all four Linux scripts. Upstream has no skip-profile flag: its only HOME uses are install defaults and shell profiles. Retained its checksum-verified standalone installer, but gave it a disposable HOME plus explicit real CODEX_INSTALL_DIR/CODEX_HOME. This is narrower than replacing release installation and preserves its trusted tool PATH.

Clean-home, existing profiles, repeated runs, custom CODEX_HOME, and failed installer fixtures pass across Ubuntu, WSL, Pi, and Bazzite. Existing Node-free Codex smoke-test contract also passes. No host shell profiles or installed CLIs were changed.

Final validation and self-review completed. All 26 shell contracts pass, including Codex profile isolation, Node-free smoke tests, and shared-runtime tests. Versions/docs updated. Retained upstream checksum verification and trusted execution PATH; no live Codex or profile changes.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Keep Linux native Codex installation separate from Chezmoi-owned shell configuration.

- Run the official installer with a disposable HOME and explicit real binary/data destinations.
- Preserve custom CODEX_HOME, the canonical ~/.local/bin/codex path, upstream verification, and the Node-free smoke test.
- Remove temporary installer files on success and failure. macOS and Windows Codex installers remain unchanged.

Validation: clean-home, existing-profile, repeat-run, custom-directory, and failure fixtures pass on all four Linux scripts. All 26 contract suites and lint pass. No live installation or rollout occurred.
<!-- SECTION:FINAL_SUMMARY:END -->
