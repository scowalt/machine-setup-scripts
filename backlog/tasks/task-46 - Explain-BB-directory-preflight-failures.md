---
id: TASK-46
title: Explain BB directory preflight failures
status: Done
assignee:
  - '@pi'
created_date: '2026-09-28 01:43'
updated_date: '2026-09-28 01:58'
labels:
  - setup
  - bb
  - diagnostics
dependencies: []
references:
  - ubuntu.sh
  - tests/bb-server-contract.sh
  - 'https://logs.scowalt.com/logs/devinabox/2026-09-27-23-06-20-855.log'
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The devinabox setup run 2026-09-27-190459.log failed before BB installation because account-owned ~/.config, ~/.config/systemd, and ~/.config/systemd/user were mode 775. The directory preflight returned silently, leaving only a generic incomplete-setup message. Report controlled actionable diagnostics without weakening safety checks or changing live permissions.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Each rejected directory in the BB HOME/config/systemd/state/data directory preflight produces a controlled diagnostic identifying the managed location and permission, ownership, or type problem without exposing credentials or raw command output.
- [x] #2 For the observed account-owned real directories with group-write permission, diagnostics explain the non-recursive permission correction; setup continues to fail before package, configuration, service, or ingress mutations.
- [x] #3 Isolated extracted-helper fixtures exercise the actual setup_bb_server call path for the observed 775 ancestor cases, safe directories, and unsafe ownership/type/link cases; fixtures never touch live services or permissions.
- [x] #4 Update the Ubuntu script version and last-change text, and pass Bash syntax, ShellCheck, the BB contract, setup reliability, and affected regression checks.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Approved scope: diagnostic-only fix with regression coverage; no live permission/service changes or automatic repairs.

1. Add temporary-HOME fixtures invoking extracted setup_bb_server through its real directory preflight, with inert mutation sentinels. Reproduce the observed silent 775 failures and verify safe paths reach the next gate.
2. Add controlled location/reason diagnostics and a non-recursive group-write correction hint. Preserve existing rejection conditions and return values, including unsafe types, ownership, and links; avoid arbitrary path/command/credential output. Bump Ubuntu version/last-change text.
3. Run Bash syntax, ShellCheck, BB fixtures, setup reliability and relevant shared-runtime/headless/Telegram regressions. Review preservation and output safety, update task evidence, and leave changes uncommitted unless requested.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Reproduced the silent 775 failure with a failing extracted-setup fixture before implementation. Added a diagnostic-only directory helper with fixed $HOME-relative labels, validated modes, controlled ownership/type/link/stat errors, and an explicitly non-recursive group-write hint. Existing ownership checks and writable-directory rejections remain; no repair or live mutation was introduced.
- The 10-test directory suite now passes, including all six managed directory locations, the exact three-directory 775 hierarchy, world-write, links, files, simulated foreign ownership/stat failures, missing optional directories, and HOME failures. Snapshot assertions verify no modes/content/links changed and mutation sentinels block side effects.
- Full BB fixtures initially exposed inherited mise Python shim lookup under temporary HOME. The test harness now resolves its interpreter before HOME changes and uses a disposable interpreter link, without changing native trust/configuration. Bash syntax, ShellCheck and the complete BB contract now pass.

- Final combined verification passed: Bash syntax, ShellCheck, BB contract (including the 10 new directory tests), setup reliability, shared Node runtime, headless Paseo, Go wiring, Telegram and git diff --check. Optional PowerShell/integration cases reported skips where prerequisites were unavailable.
- Headless regression execution required temporary PATH entries for the resolved Python interpreter and /usr/bin/jq: the account PATH contains mise shims that are unsuitable in these disposable-HOME fixtures (jq is currently inactive in that shim selection). No live config, tool installation, trust setting, permission or service change was made.
- Reviewed diff for unchanged rejection semantics, controlled output, metadata-error redaction, side-effect-free preflight, and fixture isolation. Ubuntu banner is version 271. No commit or push requested for this follow-up.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
BB setup now explains directory preflight failures instead of returning only a generic incomplete-setup error.

Changes:

- Report fixed HOME-relative locations and controlled permission, ownership, type, link or metadata reasons. For an account-owned group-writable directory, provide a non-recursive chmod g-w suggestion after asking the operator to confirm access requirements.
- Preserve all safety rejections; never change live permissions or invoke installation/services for these failures. Bump Ubuntu setup to version 271.
- Add 10 extracted-setup regression tests covering the reported 775 hierarchy and unsafe/missing directory variants, with mutation sentinels and state snapshots. Resolve the BB fixture Python interpreter before temporary HOME changes.

Verification:

- Bash syntax, ShellCheck, BB contract, setup reliability, shared-runtime, headless Paseo, Go wiring, Telegram and diff checks pass. Broader fixture checks used temporary resolved Python/system jq PATH entries rather than inherited mise shims; unavailable optional PowerShell/integration fixtures were skipped.
- No live setup, permission changes, service operations, deployment, commit or push.
<!-- SECTION:FINAL_SUMMARY:END -->
