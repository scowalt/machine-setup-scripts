---
id: TASK-34
title: Repair verified Paseo setup permissions and prevent writable PID locks
status: Done
assignee:
  - '@pi'
created_date: '2026-09-15 16:23'
updated_date: '2026-09-15 19:19'
labels:
  - setup
  - paseo
  - bug
dependencies: []
references:
  - ubuntu.sh
  - tests/test_paseo_muse_profile.py
  - tests/test_paseo_headless_provenance.py
  - tests/headless-paseo-daemon-contract.sh
  - tests/test_paseo_cli_cleanup.py
documentation:
  - README.md
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The v256 Muse helper rejects the setup-managed daemon PID file at mode 0664 and systemd parent directories at mode 0775. The native Paseo 0.8 PID writer inherits the running daemon umask 0002, so an isolated chmod is not durable. Add bounded permission recovery and restrictive managed launch permissions while preserving ownership, private profiles and daemon lifecycle safeguards. Future setup runs only; no live service changes during development.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Future setup can recover the reproduced account-owned PID 0664 and approved systemd directory 0775 conditions, then complete Muse and eligible managed-daemon setup without weakening required final permission checks.
- [x] #2 Recovery is preflighted, limited to explicit verified account-owned paths and stable file identities, does not recurse or follow links, and preserves HOME, unrelated paths, file contents, credentials, and custom service configuration; unsafe or unverified cases fail closed.
- [x] #3 Setup-managed daemon launches use a restrictive umask so the native PID writer cannot recreate a group/world-writable lock after restart; recognized old/new wrappers and provenance validation remain compatible and exact.
- [x] #4 Desktop, self-hosted, custom-home, service-ownership, stopped-interval, platform/canary, failure-restoration, private Windows ACL, and trusted Bazzite HOME-alias protections remain intact.
- [x] #5 Extracted-helper and mocked-lifecycle fixtures reproduce the observed permissions, prove next-start PID safety and idempotence, cover rejection/failure cases and available PowerShell wrappers, and never operate a live daemon.
- [x] #6 Shared helper copies remain identical across all six scripts; affected contracts and lint pass; documentation and modified setup versions are updated with controlled secret-free diagnostics.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Add red-capable fixtures for the exact observed account-owned PID 0664 plus .config, .config/systemd and .config/systemd/user directories at 0775; verify the native PID creation behavior under umask 0002 without starting Paseo.
2. Add a bounded, preflighted recovery path for those approved setup boundaries, using verified ownership, non-linked paths and stable identities. Preserve HOME, unrelated paths and all file contents; keep unverified owners and unsupported/custom arrangements blocked. Keep the final Muse safety checks strict.
3. Set a restrictive umask in managed daemon launches and update exact old/new wrapper recognition and provenance fixtures so subsequent native PID creation stays safe. Preserve existing lifecycle, platform, Desktop/self-hosted and restoration protections.
4. Extend temporary-home permission, race/failure, native PID and mocked lifecycle tests, plus available PowerShell coverage. Keep shared helper copies identical, update documentation and setup versions, then run Muse/headless/provenance/cleanup/Plain/Go/channel/runtime regressions and lint. No live setup, daemon commands, restarts, remote mutations or model requests during development.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Read-only diagnosis on scott-beelink-ubuntu confirmed correct uid 1000 on all relevant paths, PID mode 0664, three systemd ancestor directories at 0775, and an owning paseo.service process with umask 0002. Installed Paseo 0.8 uses open(pidPath, "wx") without an explicit mode. Isolated fixtures fail until the PID and all three directory write bits are corrected, then perform only a mocked stop/merge/start successfully. Awaiting implementation-plan approval.

User approved the recorded implementation plan, including bounded permission recovery. Beginning regression-first implementation; no live host or daemon changes.

Added red regression tests for PID0664/systemd0775 recovery and generated launch umask, then implemented the bounded Linux recovery and umask077 wrapper migration. Initial focused suite passed 72 cases with native PID lock and PowerShell wrappers. Safety cases cover wrong ownership, world-write, links, malformed metadata, private HOME boundaries, path swaps, failed chmod, custom/Desktop/self-hosted/platform gates, and unchanged profiles.
Independent read-only review found two extra races: Type=simple may return before PID creation, and blocking read-only open could hang on a FIFO replacement. Added nonblocking descriptor opens plus bounded post-restart native-PID readiness/owner checks, with delayed/partial/absent PID and FIFO-swap fixtures. No live setup or remote changes.

After independent review, the full Muse suite now covers 76 cases with available PowerShell/native-lock checks, including nonblocking FIFO rejection and retry-scoped safety for linked, foreign-owned and world-writable replacement PIDs. Native Paseo 0.8 PID acquisition fixtures verify umask002 produces0664 and umask077 produces0600 without a daemon. No further concrete blockers were found on rereview.
All 27 non-skills shell contracts pass with PWSH_BIN, including headless, cleanup, Muse, Plain, channel, Go, shared-runtime and package maintenance. System-home alias tests pass. ShellCheck, Markdownlint, whitespace checks and redacted diff secret scan pass. The remaining four skill/reliability contracts will run after integrating TASK-33. No live setup, remote mutations or service commands were used in implementation/testing.

Added and passed recovery fixtures for both spellings of the trusted Bazzite /home to /var/home account alias, using descriptor-relative handles against temporary paths. Acceptance criteria 1–5 are verified; final shared integration/version/documentation/lint criterion remains pending TASK-33 integration.

Final combined verification passed all 31 shell contracts. The Muse suite passes 77 tests, including PowerShell wrappers and native 0.8 PID-lock/umask fixtures; cleanup passes30 tests, provenance passes2, and trusted system-home alias passes18. Added safe restart retry cases and trusted-alias recovery for both account HOME spellings. All six embedded copies match, four generated managed launchers use umask077, and exact legacy/new provenance validation remains covered. ShellCheck, Bash syntax, Markdownlint, whitespace and redacted diff secret checks pass. No live machine configuration, daemon restart, model call or remote rollout occurred.

User requested delivery to remote main. Confirmed origin/main is unchanged at 17c64dc and permits a direct fast-forward push. Publishing with TASK-33 through normal commit/push hooks; no service changes or fleet rollout.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Fixed Muse permission failures and recurring writable PID files on future setup runs.

- Native Linux default-home recovery verifies the running setup-managed owner, preflights the approved PID/systemd paths, then removes write bits through pinned descriptor-relative handles. Preserve file contents, ownership, HOME, unrelated paths and lifecycle/platform/custom-home safeguards; read-only owner checks remain nonmutating.
- Managed launch wrappers now set umask077. After a Muse restart through an older wrapper, bounded readiness checks verify and secure the replacement PID before claiming restoration. Nonblocking leaf opens prevent FIFO replacement hangs.
- Updated exact wrapper/provenance recognition, documentation and all six setup versions.

Validation: 77 Muse tests, 30 cleanup tests, two provenance tests and 18 system-home alias tests pass; all31 shell contracts and lint/secret checks pass, including available PowerShell and isolated native PID coverage. Native Windows/macOS/ARM lifecycle smoke tests remain outside scope. No live setup, service changes or remote rollout.
<!-- SECTION:FINAL_SUMMARY:END -->
