---
id: TASK-56
title: >-
  Safely validate private-group Homebrew OpenCode installs and expose preflight
  failures
status: Done
assignee:
  - '@openai-codex'
created_date: '2026-09-29 19:46'
updated_date: '2026-09-29 20:29'
labels: []
dependencies: []
references:
  - lib/opencode-cli.cjs
  - lib/opencode-cli.bash
  - lib/opencode-cli.ps1
  - tests/test_bb_service_trust.py
  - tests/opencode-cli.test.cjs
  - tests/test_opencode_cli_callers.py
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Ubuntu v282 still fails OpenCode migration on scott-beelink-ubuntu. Read-only execution of the actual Homebrew preflight rejects account-owned 0775 Cellar directories as brew-path, and the wrapper suppresses the reason. Support only positively verified private Linux group-writable Homebrew layouts without changing their permissions, while preserving fail-closed behavior and making controlled preflight diagnostics actionable.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A fixture matching the observed Homebrew v1.18.33 layout with 0775 directories and a 0664 receipt is accepted only after a native, bounded, stable exclusive-primary-group and ACL trust proof, without chmod or mutation of the Homebrew tree.
- [x] #2 Shared, foreign, stale or unverified group membership; unsupported NSS/initgroups policy; unsafe ACLs; world write; unsafe links; changed identities; and missing proof prerequisites fail closed before command promotion. Existing macOS and Windows trust boundaries remain intact.
- [x] #3 Allowlisted preflight operation/reason diagnostics reach Bash and PowerShell without exposing arbitrary exceptions, raw command output, paths or credentials; unknown output stays suppressed and existing HTTP/recovery protocols remain compatible.
- [x] #4 Official artifact identity, migration/pins, command-only changes, rollback, version verification, Homebrew readiness and failure aggregation are preserved; extracted fixture tests cover acceptance and rejection without running OpenCode or live setup.
- [x] #5 Shared source and all six generated entry points remain synchronized, version headers and documentation are updated, required contracts/lint pass with limitations recorded, and changes remain uncommitted for parent review.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Add an observed-layout Homebrew fixture (v1.18.33, 0775 directories/0664 receipt) at the exported preflight and real inert migration seams; demonstrate rejection before changes.
2. Add a separate Linux Homebrew-only native Python proof, inspired by but not modifying BB: isolated/root-trusted executable, enumerable NSS including initgroups, exclusive primary group, bounded full task-membership/identity snapshots, descriptor-relative link-rejecting traversal and absent access/default ACLs. Unknown/missing/changed evidence fails closed; no permission repairs.
3. Inspect Homebrew paths parent-first; retain snapshots and revalidate trust/identity before migration and publication, preserving command-only backups and rollback. Add typed allowlisted policy/native diagnostics with strict Bash/PowerShell validation; keep HTTP and recovery protocols intact.
4. Regenerate/version all six entry points and document prerequisites/recovery. Run offline native-proof, orchestration, safety, required regression and lint checks; record optional skips and native/remote limits. User approval covers this scope; stop rather than weakening proof if blocked.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Read the parent read-only reproduction (not executed), current OpenCode policy and BB service trust reference. Confirmed HEAD 4ece5ef; only new TASK-56 was untracked. No remote, live Homebrew/proc inventory or application validation will be performed.

- Red evidence: node --test --test-name-pattern "observed 0775" tests/opencode-cli.test.cjs rejected the modeled v1.18.33 Homebrew layout with brew-path before implementation. New wrapper fixtures also failed before policy diagnostics were added (36 failed subcases).
- Added Linux Homebrew-only proof using root-trusted isolated native Python, known NSS/initgroups configuration plus effective pwd/grp/getgrouplist verification, bounded per-thread procfs membership/start-time snapshots, absent access/default ACLs and descriptor-relative no-follow ancestry checks. Account/group and path snapshots are rechecked; shared/unknown/changed evidence blocks. BB helpers remain untouched.
- Homebrew traversal is now parent-first. Original command/receipt/native path snapshots are retained through byte identity checks, rechecked before command quarantine and publication, and required for rollback; failed rollback retains recovery artifacts. No permissions or package stores are changed.
- Typed allowlisted policy/native-code diagnostics now survive core and strict Bash/PowerShell wrappers; original HTTP and recovery protocols remain unchanged.
- Initial full OpenCode contract green: 96 Node tests and all 7 caller tests, with existing PWSH and installed cmd-shim enabled. Native proof fixtures redirect every account/procfs/filesystem read; no host inventory or OpenCode execution. Full required regressions and final self-review pending.

- Final self-review added revalidation of quarantined Homebrew link identity/content before publication and rollback, plus procfs mount-view snapshot checking. Changed backups or post-quarantine trust failures retain backups/journal/lock and report recovery-required rather than publish or restore an uncertain reference.
- Final OpenCode contract: 98 Node tests passed, 0 skipped; all 7 Bash/PowerShell caller tests passed. Replayed the final observed-layout fixture against committed HEAD core: still fails with brew-path, establishing red/green at the real preflight seam. Saved HTTP metadata replay returns 200; REPLAY=1 cached artifact/integrity/unpack replay reaches the deliberately throwing inert probe (zero OpenCode execution). Neither replay demonstrates existing-machine migration.
- Final required contracts all pass: AI coding agents, setup reliability (including PowerShell), weekly, headless, shared runtime (18 Python tests plus both 1409-assertion PowerShell modes), Pi Go (22 tests including installed native lock/catalog), Go wiring, Paseo, reboot, CLT (22) and Homebrew results (9). Additional BB service-trust (8) and full BB preparation contracts pass; BB source policy remains unchanged.
- Final embedding --check, ShellCheck (shared Bash source and all five generated Bash entry points) and git diff --check pass. Verified six entry points differ from HEAD only in generated OpenCode blocks and version banners. Versions: mac 256, Ubuntu 283, WSL 217, Pi 234, Bazzite 135, Windows 166; shared wrappers v3, Node test v3, caller contract v4.
- Optional skips: weekly has 3 (two MANAGED_SKILLS_CLI native fixtures, one PI_SKILLS_DOTFILES_SOURCE); shared runtime has 1 PI_RUNTIME_DOTFILES_SOURCE; Paseo has 1 PASEO_UNMANAGED_DOTFILES_SOURCE. Existing PowerShell, installed npm cmd-shim and Pi lock/catalog fixtures were enabled. Temporary jq -> /usr/bin/jq PATH shim was used for inherited fixture trust and removed afterward; no dependencies or persistent environment configuration changed.
- Logs: /tmp/opencode-task56-tests/final-opencode.log, final-original-red.log, red-callers.log, final-*.log, bb-service-trust.log, bb-preparation.log and offline replay logs. No remote checks, live process/daemon inventories, live setup, application/skill execution, permissions/credentials/fleet changes, or commits. The target machine still needs separately authorized read-only native proof and rollout; process churn, NSS disagreement and unavailable ACL evidence intentionally fail closed.

Parent review: no blocking code findings against the approved scope/trust boundaries. Independently reproduced brew-path with the final observed-layout fixture against committed HEAD, then reran the changed contract (97 Node pass/1 optional shim skip; 5 caller pass/2 optional PowerShell skips in parent environment). Reviewed child evidence for 98 Node and all 7 callers passing with prerequisites enabled. Embedding check, ShellCheck, whitespace check, Homebrew-result (9) and CLT (22) tests passed; all six setup versions increment and unrelated generated-entry-point code is unchanged. Corrected task final-summary Markdown spacing through the CLI. Native target-machine group privacy/artifact identity remain unverified; no remote or live-setup verification was performed during review.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Safely support positively proved private Linux Homebrew groups and expose controlled OpenCode preflight failures.

Changes:

- Added a Linux Homebrew-only isolated native proof: trusted Python, recognized NSS/initgroups configuration and effective enumeration, exclusive primary group, stable bounded per-thread membership/identity snapshots, descriptor-relative no-follow ancestry and absent access/default ACLs. No chmod/chown, private-ancestor shortcuts or BB policy changes.
- Reworked Homebrew preflight to inspect parents before descendants. Retained path/receipt/link snapshots and rechecked trust before quarantine/publication/rollback, including quarantined link identity. Official byte identity, pins, staged verification, no-clobber publication and command-only recovery remain mandatory.
- Added typed allowlisted policy/native-code diagnostics through strict Bash and PowerShell validation, preserving HTTP diagnostics, recovery-required, unrelated work and final failure aggregation.
- Updated README guidance; regenerated and versioned all six standalone entry points.

Validation:

- Observed 0775/0664 v1.18.33 fixture fails with brew-path against committed core and passes repeated inert migrations with the new native proof. Final OpenCode suite: 98 Node tests and all 7 caller tests pass, including PowerShell and installed npm shim coverage.
- Required AI-agent/reliability/weekly/headless/runtime/Pi Go/wiring/Paseo/reboot/CLT/Homebrew suites and additional BB service-trust/preparation regressions pass. Embedding check, ShellCheck and whitespace checks pass. Optional cross-repository/native-skill skips are documented in notes. Cached metadata/artifact replays preserve TASK-55 behavior without network or application execution.

Limitations:

- Fixtures do not prove the remote account/group is private or that its old binary matches an official artifact. Native Windows/macOS/ARM and complete machine installation remain rollout checks. No remote work, live setup, app execution, credential/fleet changes, commits or pushes were performed. All changes remain uncommitted for parent review.
<!-- SECTION:FINAL_SUMMARY:END -->
