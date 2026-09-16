---
id: TASK-35
title: Retire Paseo Plain on future machine setup runs
status: Done
assignee:
  - '@pi'
created_date: '2026-09-16 03:08'
updated_date: '2026-09-16 03:45'
labels: []
dependencies: []
references:
  - ubuntu.sh
  - mac.sh
  - wsl.sh
  - pi.sh
  - bazzite.sh
  - win.ps1
  - tests/test_paseo_plain_setup.py
  - README.md
  - CLAUDE.md
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Replace Paseo Plain installation and updates with idempotent removal across macOS, Ubuntu, WSL, Raspberry Pi, Bazzite, and Windows. Apply changes on each machine's next setup run, without a live fleet rollout.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 All six scripts stop installing, updating, or migrating Paseo Plain and instead remove the local paseo-plain registration, including disabled installations, when safe native removal is available.
- [x] #2 Removal is idempotent and scoped to the selected local Paseo home and exact plugin ID; preserve other plugins, global plugin enablement, credentials, projects, user-owned source directories, plugin-data, and existing recovery backups.
- [x] #3 Unavailable or unsafe removal is clearly reported with safe retry/manual instructions, never falsely reported as completed; failures propagate while unrelated setup continues. Do not start or restart daemons or contact remote machines for retirement.
- [x] #4 Keep shared retirement logic identical across all six scripts and cover absence, repeated runs, disabled/custom sources, custom home selection, unsafe metadata, command failures, and local-only targeting using isolated fixtures; remove obsolete installation expectations.
- [x] #5 Update documentation and agent guidance, increment all six script versions, and run ShellCheck and affected fixture suites; report unavailable platform coverage.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Confirm native removal semantics and retain verified CLI selection, selected-home validation, local-only endpoint checks, and secret-free diagnostics.
2. Replace the shared installer/migration blocks and call sites in all six scripts with an idempotent retirement helper. Remove the exact paseo-plain registration regardless of disabled state or source, preserve external sources/plugin-data/recovery backups, and explicitly defer unsafe or unavailable native removal without daemon lifecycle changes.
3. Replace installer-only fixtures with retirement coverage, adapt dependent extraction/wiring tests, and verify native removal in temporary fixtures where supported.
4. Update README and CLAUDE guidance, increment the six setup versions, and run ShellCheck plus affected Plain, CLI identity/cleanup, Muse, release-channel, and package-maintenance regressions. Record unavailable PowerShell/native Windows coverage.
5. Self-review for accidental reinstall paths, unintended deletion, and failure reporting; complete task checks only after verification.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Inspected existing shared installer and native removal fixture; Node, Python, and ShellCheck are available. PowerShell is not on PATH and PWSH_BIN is unset. Implementation awaits user approval of the plan.

User approved the plan. Native Paseo 0.8 removal deletes the managed checkout and plugin-settings, but preserves plugin-data and external directory sources. Retirement will preserve native settings in a private retirement backup before removal. Located a temporary PowerShell runtime and installed Paseo 0.8 module for isolated wrapper/native-manager validation.

Implemented identical retirement helpers in all six scripts, renamed call sites, and changed Bazzite retirement failure handling to continue unrelated work. Native settings receive exclusive private, verified backups; linked/malformed/shared deletion targets and incomplete migrations fail closed. Saved plugin-data/external sources/recovery backups remain intact.
Validation passed: 33 retirement tests with PowerShell wrappers; native Paseo 0.8 Git/disabled/directory removal and idempotency; poisoned-Git fixture isolation; ShellCheck; Markdownlint; CLI cleanup, Muse, release-channel (including explicit PowerShell suite), Pi package maintenance, headless, profile-permissions, Go, Go wiring, and shared-Node contracts (959 PowerShell assertions). Optional unrelated registry/dotfiles/native-lock probes and native Windows tests were skipped when unavailable. Native Windows ACL behavior remains unverified.
Self-review completed. Attempted read-only Claude second review was unavailable due to its expired OAuth token; no code was delegated or changed by that tool. No live setup, daemon, plugin, or fleet changes were performed.

Publishing follow-up: commit 1056f8a passed pre-commit checks. Full pre-push suite found stale exact version/banner expectations in the historical managed-skill contract; the push was blocked without changing remote main. Updated that contract to the six retirement versions and retained all skill behavior assertions.

The updated managed-skill version/banner contract and remaining Telegram/Windows-log contracts pass, including available PowerShell fixtures. All contracts preceding the stale-banner assertion passed in the full pre-push run. Publishing retains the original tests and hooks; no checks were bypassed.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Retire Paseo Plain on future setup runs across macOS, Ubuntu, WSL, Raspberry Pi, Bazzite, and Windows. All six scripts now remove the exact paseo-plain registration instead of installing/updating/migrating it, including disabled and custom-source installations.

Preserve unrelated plugins/configuration, external sources, plugin-data and existing backups. Back up native settings privately before native deletion. Reject unsafe or ambiguous metadata and clearly report blocked removal while continuing unrelated setup. Update README/agent guidance, increment all six versions, replace installation fixtures with retirement coverage, and adapt dependent extraction tests.

Verified with 33 isolated retirement tests, Bash/PowerShell wrappers, real Paseo 0.8 source/config managers with inert workers, Git-isolation checks, affected regression suites, ShellCheck, and Markdownlint. Native Windows ACL validation remains a platform follow-up; no live machines were changed.

Publishing follow-up: refreshed the managed-skill contract exact version/banner expectations to match the six retirement versions; its behavioral assertions remain unchanged.
<!-- SECTION:FINAL_SUMMARY:END -->
