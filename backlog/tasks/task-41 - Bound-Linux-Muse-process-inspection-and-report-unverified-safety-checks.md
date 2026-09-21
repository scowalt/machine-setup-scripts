---
id: TASK-41
title: Bound Linux Muse process inspection and report unverified safety checks
status: Done
assignee:
  - '@pi'
created_date: '2026-09-21 15:59'
updated_date: '2026-09-21 17:07'
labels: []
dependencies: []
documentation:
  - docs/plans/2026-09-19-001-fix-homebrew-results-and-paseo-inventory-plan.md
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Implement approved audit design fix 2: exclude verified foreign processes without sensitive reads, preserve owner and ancestry safeguards, and report blocked verification as incomplete setup rather than successful deferral.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Linux inventory validates UID tuple and process identity independently of procfs directory ownership, avoids foreign sensitive reads, and rejects ambiguous identities, relevant unreadable metadata and unsafe process races.
- [x] #2 Owner, service, ancestry, native-lock, custom-home and platform protections remain enforced; Desktop/self-hosted expected deferrals remain warning-only and failure recovery preserves safe restoration.
- [x] #3 Allowlisted operation/reason diagnostics and nonzero safety outcomes survive every Bash and PowerShell wrapper; unknown output fails closed without leaking secrets and dependent daemon/cleanup is blocked.
- [x] #4 Shared helper copies stay identical across all six version-bumped scripts; isolated helper/wrapper/final-result and affected regression suites pass with native platform limitations documented.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
User approved the implementation plan and shared helper/wrapper/final-result seams.

1. Reproduce foreign-process denial with the actual helper fixture.
2. Implement validated UID/instance inventory and owner-aware fail-closed checks.
3. Add controlled diagnostics and strict outcome parsing to all wrappers.
4. Extend race, ownership, secret-redaction and final-result fixtures; synchronize six copies and versions; run affected suites.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Reproduced and fixed foreign cmdline EACCES, foreign service-owner exclusion, unknown wrapper output acceptance, and lost primary diagnostics after failed restoration. UID tuples and start identities now bound Linux inventory; ancestry and service-group evidence remain mandatory. Expected Desktop/self-hosted/platform deferrals retain zero status; unverified safety results fail.

93 Muse tests pass with PowerShell 7.6.6 and native Paseo 0.8 PID-lock fixtures. Actual Bash wrapper/caller/final-log tests cover all five Bash scripts. PowerShell fixtures cover strict output, operation diagnostics and simulated ACL policy. Shared helper and Bash wrapper equality plus cross-platform diagnostic policy equality are checked. No live setup, inventory, model request or daemon lifecycle operation was performed.

Regression verification passed: headless daemon, CLI cleanup, release channel (including explicit PowerShell fixtures), Pi profile permissions, Go with the installed native proper-lockfile module, Go wiring, Plain retirement, shared Node runtime, setup reliability, pending reboot, Windows log upload, model defaults, Telegram alerts, AI agents and weekly log-audit suites. Explicit PowerShell reliability/model/Telegram suites also pass.

ShellCheck and Bash syntax checks pass. Markdownlint uses an existing cached CLI without installation and respects the repository exclusion of vendored CLAUDE.md. Optional fixtures requiring extra modules/platforms remain skipped where unavailable; native Windows ACL and native macOS execution are not claimed. Self-review confirmed six identical embedded helpers and preserved platform, lock, custom-home and restoration gates.

Remote-main publication was blocked by the full pre-push suite: tests/backlog-mcp-retirement-contract.sh incorrectly freezes every setup script header to the previous feature description. Reproduced with the isolated contract (exit 1); its native/simulated retirement fixtures pass before the obsolete grep assertion. Adjusting only that header assertion while retaining all retirement behavior checks.

The Backlog retirement contract now checks version-header structure instead of freezing the prior feature description. Its Bash, planner and PowerShell fixtures pass with PWSH_BIN; ShellCheck passes. Full pre-push hooks remain enabled for publication.

The next full pre-push run passed the preceding contracts and found the same obsolete header snapshot in simple-english-skill-contract.sh. Reproduced independently. Replacing its duplicated fixed version/description map with the version-header format contract already used by the Gitea suite; managed-skill runtime, ownership, retirement and artifact checks remain unchanged.

The managed-skills contract now passes after removing only the frozen release snapshot. Its functional checks and ShellCheck pass. Repository-wide inspection found no other remaining exact setup version/Last changed assertions. Pre-push hooks remain mandatory.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
## Summary

```text
Linux process metadata -> stable identity + UID tuple + ancestry/group evidence
  foreign/unrelated -> no command/environment reads
  relevant or uncertain -> verify or block
Unverified safety -> nonzero result + dependent daemon/cleanup block
Established Desktop/self-hosted ownership -> expected deferral
```

Controlled diagnostics survive Bash/PowerShell wrappers and recovery; unknown output fails closed without echoing it. All six script versions and documentation updated.

## Evidence

- **Before:** an unrelated foreign process with unreadable cmdline blocked profile sync; uncertain ownership returned success; wrappers echoed unrecognized message prefixes and restoration could hide the failing inventory operation.
- **After:** 93 Muse tests pass, including native Paseo 0.8 PID-lock contenders, PowerShell wrappers/simulated ACL policy, UID and PID races, preservation gates, and actual Bash caller/final-log failure propagation. Affected regression suites, ShellCheck, syntax and documentation lint pass.

## Merge Danger

**Door:** two-way.
**Blast Radius:** future setup runs on all six platforms; Linux inventory changes and cross-platform safety-result reporting. Conservative checks can still block uncertain processes. No live setup, daemon restart, fleet change or model request was made. Native Windows ACLs/macOS execution need platform verification; audited host failures are not all proven to share one cause.

Publication follow-up: fixed the pre-existing Backlog contract assertion that froze Last changed text to the previous feature. Header structure is still verified, and all retirement behavior fixtures remain enabled.

The same header-format correction also applies to the managed-skills contract; its runtime and safety assertions remain unchanged.
<!-- SECTION:FINAL_SUMMARY:END -->
