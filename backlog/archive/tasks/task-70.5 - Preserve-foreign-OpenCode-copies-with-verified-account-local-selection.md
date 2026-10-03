---
id: TASK-70.5
title: Preserve foreign OpenCode copies with verified account-local selection
status: In Progress
assignee:
  - '@openai'
created_date: '2026-10-03 15:21'
updated_date: '2026-10-03 15:23'
labels: []
dependencies: []
references:
  - TASK-70
  - lib/opencode-cli.cjs
  - lib/opencode-cli.bash
  - lib/opencode-cli.ps1
  - tools/embed-opencode-cli.py
  - tests/opencode-cli.test.cjs
  - tests/test_opencode_cli_callers.py
  - tests/opencode-cli-contract.sh
documentation:
  - docs/adr/0002-let-chezmoi-own-shell-configuration.md
  - docs/adr/0004-keep-opencode-migration-command-only.md
  - docs/adr/0005-accept-opencode-linux-homebrew-group-write.md
parent_task_id: TASK-70
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Child of TASK-70; its approved specification and safety boundaries are authoritative. Deliver account-local OpenCode CLI ownership with coexistence of lower-priority foreign commands, verified effective resolution in setup and a fresh native shell, and controlled refusal diagnostics. Parent AC4–7, the OpenCode portions of AC8/10/13, and applicable preservation/synchronization requirements apply. Exercise the actual shared installer with injected artifacts, synthetic ownership and inert probes plus extracted native caller/wrapper seams. A discovered foreign command is not a migration target and must not be executed or changed. Keep Chezmoi shell ownership, official-byte identity, pins/newer/custom-copy policy and rollback. Do not redesign Homebrew ownership or introduce profile edits, lifecycle changes, new architectures or live application probes. This ticket is ready in the dependency graph; the user has approved execution.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The account-owned verified installation succeeds when a foreign command is lower priority, and every foreign command/store/receipt/permission/recovery artifact remains untouched and unexecuted.
- [ ] #2 Success requires actual effective account-local selection in setup and a fresh native shell. Higher-priority foreign/custom shadowing, aliases/functions and unverified or conflicting resolution fail without shell/profile repair.
- [ ] #3 New installation, current/newer official copies, upgrades and eligible account-owned migration retain verified bytes before probes, supported exact version output, pins, custom-copy refusal, safe promotion and recoverable rollback.
- [ ] #4 Finite operation/reason diagnostics distinguish the approved ownership/resolution cases; unrecognized results and arbitrary exception/path/secret sentinels fail closed without leakage or loss of the original failure.
- [ ] #5 Shared native policy and applicable Bash/PowerShell embeddings remain synchronized with incremented modified-script versions; deterministic red/green, contained installer/caller regressions and static checks are recorded, including native-platform and optional-skip limitations.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Canonical replacement is TASK-71.1. This intermediate renumbering is archived to avoid the already existing concurrent TASK-70 Beszel graph. No completion claimed.
<!-- SECTION:NOTES:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 Record contained regression/static evidence, review outcome and explicit skips without native rollout claims.
<!-- DOD:END -->
