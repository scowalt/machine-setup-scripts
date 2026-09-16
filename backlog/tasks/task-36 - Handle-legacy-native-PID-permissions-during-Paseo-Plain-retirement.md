---
id: TASK-36
title: Handle legacy native PID permissions during Paseo Plain retirement
status: Done
assignee:
  - '@pi'
created_date: '2026-09-16 13:22'
updated_date: '2026-09-16 13:46'
labels: []
dependencies: []
references:
  - ubuntu.sh
  - tests/test_paseo_plain_setup.py
  - 'https://logs.scowalt.com/logs/devinabox/2026-09-16-13-10-00-625.log'
  - >-
    https://logs.scowalt.com/logs/scott-beelink-ubuntu/2026-09-16-13-09-37-164.log
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Post-rollout diagnosis: devinabox and scott-beelink-ubuntu September 16 setup uploads both ran Ubuntu version 258 and reported "Paseo Plain removal failure: preflight: unsafe-path." On devinabox, read-only probes identify the account-owned regular ~/.paseo/paseo.pid (0664 inside a 0700 Paseo home) as the exact rejected path; verified Paseo 0.8 CLI/daemon are reachable and paseo-plain remains enabled/running. A minimal temporary fixture reproduces retained registration with PID mode 0664 and succeeds when only the fixture PID changes to 0600. Existing fixtures use umask 077 and missed this integration state.

The earlier Muse ownership/permission-recovery step reports process-inventory-unverified: a read-only local probe finds EACCES reading several same-UID /proc/PID/environ files. This service also has a drop-in, and its legacy wrapper lacks umask 077; existing safety rules intentionally block automatic service/permission takeover. No live files, permissions, plugin state, or daemon lifecycle were changed during diagnosis.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Retirement safely handles the observed account-owned legacy native PID state across all six scripts without weakening linked-path, ownership, private-home, endpoint, or unrelated-metadata protections.
- [x] #2 Regression fixtures reproduce an active directory-installed plugin with no managed store or plugin-settings and a 0664 native PID; verify the intended safe removal or actionable, precise blocker instead of a generic unsafe-path message.
- [x] #3 Preserve saved data, unrelated plugins, service drop-ins, launch environments, and daemon lifecycle; use temporary extracted-helper fixtures only, without live cleanup or blanket permission changes.
- [x] #4 Keep shared helpers identical, update affected versions/banner contracts/documentation, and pass relevant retirement/native/PowerShell and full pre-push regressions.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Add a failing regression matching the observed directory registration: no managed plugin store or native settings, a native-style 0664 PID inside an account-owned 0700 Paseo home, and unrelated service drop-ins/legacy permissions that must remain unchanged.
2. Add a PID-only read path that permits the exact legacy 0664 mode on POSIX only behind a verified private, non-writable directory boundary. Keep ordinary metadata checks unchanged; reject foreign ownership, links/hardlinks, special files, world-write and nonlocal endpoints. Use bounded nonblocking/no-follow reads with identity checks and revalidate PID/home state before CLI commands. Do not chmod, stop/restart daemons, inspect all processes, or mutate services.
3. Verify success and failure through all extracted wrappers, negative boundary/race fixtures, and actual Paseo native PID/source managers in temporary homes with inert workers. Keep the six helpers identical.
4. Update documentation, setup versions and exact-banner tests; run lint and the full pre-push suite, commit with attribution, and fast-forward remote main without force. If safeguards cannot establish a safe read, retain a precise failed result and manual instructions.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
User approved implementation and publication. This fix separates read-only PID consumption for plugin retirement from the stricter service/permission-repair owner policy; it will not bypass service drop-in or process-inventory restrictions for daemon mutations.

Added the deployed directory-plugin/no-store/no-settings regression and observed the original unsafe-path failure before implementation. The PID-only reader now permits exact POSIX 0664 only inside a private owned home with trusted ancestors, rejects unsafe identity/type/link/mode changes, and rechecks before every CLI command. It never changes permissions or services and ignores only heartbeat timestamps.
The original temporary repro now passes without changing its 0664 PID. All 44 retirement tests pass with every Bash/PowerShell wrapper, negative ownership/link/endpoint/permission/FIFO-swap cases, and main-flow continuation after Go or Muse failures. Native tests create PID locks with the real Paseo 0.8 writer under umask 002 and verify unchanged PID contents/mode/inode after removal. Native source-manager and poisoned-Git isolation fixtures, banner/managed-skill contract, ShellCheck, Markdownlint and diff checks pass. No live daemon, plugin, permissions or service changes were made.

Full validation passed: all 31 tests/*.sh contracts, all setup-script ShellCheck checks, and Markdownlint. PowerShell was available via PWSH_BIN and PATH, and the explicit Paseo 0.8 service module enabled real native PID/source/config and Git-isolation coverage. Optional environment-dependent/native Windows cases retained their documented skips. Self-review confirmed that only the PID reader receives the mode exception; generic metadata validation, shared CLI identity, service ownership/recovery logic, and daemon lifecycle code are unchanged.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Fix Paseo Plain retirement failing before removal on legacy native 0664 PID files. The former generic metadata check rejected the deployed state even inside a private Paseo home; test fixtures previously hid it under umask 077.

All six scripts now use a read-only PID-specific validation path for exact POSIX 0664 behind private, account-owned directory boundaries. Preserve permissions and service/drop-in state, reject untrusted ownership/links/modes/ancestors/endpoints, bound nonblocking no-follow reads, and recheck PID/home identity and contents before CLI calls while allowing heartbeat timestamp changes. Keep other metadata and daemon-repair policies unchanged.

Add deployed-state regressions, all-wrapper preservation tests, negative permission/ownership/link/FIFO/race coverage, and real native PID creation under umask 002. Update all six versions, exact-banner contracts, README, and agent guidance.

Validation: 44 retirement tests, native Paseo and poisoned-Git fixtures, all 31 shell contracts with available PowerShell coverage, ShellCheck, Markdownlint, and diff checks pass. Native Windows ACL behavior still requires Windows verification. No live cleanup, chmod, service change, or daemon restart was performed.
<!-- SECTION:FINAL_SUMMARY:END -->
