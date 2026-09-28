---
id: TASK-51
title: Preserve BB preparation permissions and explain preflight failures
status: Done
assignee:
  - '@pi-task51'
created_date: '2026-09-28 19:17'
updated_date: '2026-09-28 21:03'
labels: []
dependencies: []
references:
  - ubuntu.sh
  - tests/test_bb_dotfiles_umask.py
  - tests/test_bb_machine_preparation.py
documentation:
  - docs/plans/2026-09-28-bb-preparation-permissions.md
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Arcane setup failed before BB package changes because service directories were 0775 and several service files were 0664. The existing Chezmoi permission guard only covered BB_SERVER=1; native temporary fixtures reproduce those unsafe managed modes without the guard. Extend the command-scoped protection to preparation and surface controlled preflight diagnostics without weakening ownership checks or modifying unmanaged services. User approved this repository-only fix; no live rollout is authorized.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 All five Bash setup scripts restrict group/world write bits for full Chezmoi init/update/apply operations, including BB preparation with BB_SERVER unset/0, while preserving stricter caller masks, native explicit config precedence and command failures.
- [x] #2 Identical preparation helpers report controlled operation/location/reason diagnostics for directory, service-reference, process, runtime and artifact failures without leaking credentials, raw errors or arbitrary process/service contents; unknown output fails closed.
- [x] #3 Unsafe or unmanaged paths and services remain untouched and blocked; existing role deferrals, npm policy, manual enrollment ownership, headless gates and failure aggregation are preserved.
- [x] #4 Isolated native Chezmoi and extracted-caller fixtures reproduce Arcane writable modes, verify convergence of managed paths and repeated preparation, preserve unmanaged paths, and cover unsafe metadata plus diagnostic secrecy.
- [x] #5 README explains managed-mode convergence and manual recovery for remaining unsafe locations; modified setup-script versions are incremented.
- [x] #6 The full pre-push PowerShell retirement fixture isolates the existing BB Desktop caller with an inert success stub, without changing Windows setup or bypassing retirement/finalization assertions.
- [x] #7 Consolidated approved policy: retain server protection, but add preparation-driven Chezmoi restrictions only for eligible non-deferred roles. Diagnostics collect bounded independent safe blockers, stop below unsafe ancestors and validate the entire secret-safe result protocol.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Lock down the approved Arcane regression with native Chezmoi fixtures and extracted preparation callers in temporary homes, including unmanaged writable service files.
2. Share an additive command-scoped umask wrapper across all five Bash full-apply callers; preserve native config precedence, existing failures, targeted runtime repairs and caller umask.
3. Add controlled stage/location/reason diagnostics to the identical preparation helper and strict Bash result validation, without relaxing safety checks or invoking BB.
4. Update README and script versions; run affected contracts/lint, review preservation and log aggregation, and document manual-only recovery plus native rollout limits.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
User approved the proposed repository fix in this thread. Diagnosis used authenticated collector log arcane/2026-09-28-18-49-16-056.log, read-only remote metadata/preflight (first failure: systemd directory chain), and isolated real-helper replays. Temporary fixtures prove either 0775 directory or 0664 unrelated unit independently blocks preparation; no Arcane mutation occurred. Implementation plan shared; proceeding under that approval.

- Reproduced the managed 0664/0775 convergence failure before patching through native Chezmoi and all five extracted callers. Identical unconditional command-scoped go-w wrappers now cover full init/update/apply; stricter masks, caller mask and explicit native config remain intact. Targeted runtime repair callers are unchanged.
- Added strict allowlisted preparation terminal diagnostics with stage/location/reason. Unknown or status-inconsistent output fails closed without echoing raw output; no safety check was weakened. Existing-role deferrals remain before runtime/npm.
- Preparation contract passed (20 helper groups, 3 cross-platform caller/native-Chezmoi groups, PowerShell guidance). BB server, setup reliability, Homebrew results and macOS CLT fixtures passed. Bash syntax/ShellCheck passed before final review.
- Native fixtures preserve unmanaged 0664 service files and block them with service-inventory diagnostics. Explicit Chezmoi umask 002 is not overridden. Remaining unmanaged/explicit-policy blockers require manual review; no Arcane setup, permissions or lifecycle changes were made.

- Final verification passed: preparation contract (20 helper groups + 3 cross-platform/native-Chezmoi groups + PowerShell guidance), BB server contract, setup reliability, Homebrew results, macOS CLT, shared Node runtime (18 Python cases and both 1409-assertion PowerShell modes), headless Paseo, AI-agent, PowerShell setup reliability, weekly regressions, pending reboot, Bash syntax, ShellCheck, README markdownlint and git diff --check.
- Tightened final fixtures to require exactly one native command with unchanged argv per call, identical wrappers, and unchanged unmanaged file bytes/modes across apply. Reran all three permission integration groups successfully.
- Optional integrations skipped: PI_RUNTIME_DOTFILES_SOURCE; managed-skills native discovery/snapshot and render/setup without MANAGED_SKILLS_CLI/PI_SKILLS_DOTFILES_SOURCE. Native macOS/WSL/ARM installation and actual Arcane rerun remain rollout checks, not fixture claims. PowerShell used /tmp/pi-shared-runtime-pwsh.2SlAPL/pwsh.
- Self-review confirmed shared preparation payload/wrapper equality, no relaxed safety predicates, no automatic chmod/chown, no changed npm policy or server/enrollment lifecycle, preserved caller masks and explicit native config. Version bumps are +1 in all five Bash setup scripts. Only repository files and temporary fixtures changed during implementation; no commit, push or deployment.

User authorized merging this change into remote main. Fetched origin/main and confirmed it exactly matches the implementation base; preparing an attributed commit and normal fast-forward push with repository hooks enabled. This does not authorize running setup on Arcane.

Merge-time hook verification found a pre-existing Windows Infisical fixture failure: its extracted caller now invokes Install-BbDesktop but the fixture lacks that stub. Reproduced exit 1 from unchanged origin/main using three files in a temporary directory; adding only an in-memory success stub produced exit 0. Adding that test-only isolation correction under the existing regression-verification plan before retrying all hooks. Initial HTTPS push also lacked shell credentials; read-only API verification confirmed the existing account owner token permits this repo, used only in process environment with command-scoped git credential helper (no persisted credentials). No force or hook bypass.

The corrected Infisical contract now passes with PWSH_BIN enabled, retaining real retirement failure aggregation and log-finalization assertions. Only the unrelated Desktop action is stubbed. Removed only the three Python cache files produced by the initial hook run; subsequent hook tests disable bytecode output.

Consolidating concurrent implementations after remote main advanced during a fully passing pre-push run. The separate devinabox design/implementation record used the same TASK-51 ID; it is preserved under backlog/archive/tasks/task-51 - Preserve-safe-dotfile-permissions-for-BB-machine-preparation.md through the CLI. This active main record retains the Arcane history. The explicit approved design in docs/plans/2026-09-28-bb-preparation-permissions.md governs integration: scoped eligibility rather than unconditional masking, and bounded HOME-relative diagnostics rather than a single label-only result. Preserve and adapt main extra native preparation and secrecy regression cases to that contract. Earlier unconditional/single-result notes describe historical implementation, not the integrated result. No live changes or force push.

- Consolidated-tree targeted verification passed: 27 preparation helper groups, 16 native/caller dotfile groups, all 3 additional main permission-to-installation groups, PowerShell guidance, Bash syntax, ShellCheck and whitespace checks. Preserved main unsupported-platform/runtime/process diagnostic distinctions inside the bounded protocol.
- Kept both histories without duplicate active tasks: main TASK-51 remains active; the earlier devinabox record is CLI-archived. The two identical Windows isolation stubs are consolidated into one. All five setup versions advance past both branches: Ubuntu 278, macOS 251, Pi 229, Bazzite 130, WSL 212.
- Full enabled pre-push contracts/lint previously passed on the pre-consolidation tree; publishing was rejected only because main advanced mid-suite. Re-running all hooks for the final integrated tree, with private /var/tmp fixtures to avoid shared /tmp ancestor-stat races. No force, hook bypass or production-machine changes.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Consolidated the independently diagnosed devinabox and Arcane BB permission fixes across all five Bash setup scripts. The approved scoped policy protects eligible non-deferred preparation and retains Ubuntu server protection; existing BB-role deferrals receive no additional permission restriction. Native explicit overrides, stricter masks, caller masks, platform/headless gates, runtime ownership and ordinary unmanaged files remain preserved.

Preflight remains read-only. Bounded whole-output-validated diagnostics identify safe HOME-relative boundaries, modes and controlled reasons, including main unsupported-platform/runtime/process distinctions. Inspection stops beneath unsafe ancestors. Shared helpers remain identical; native Windows and shared Node files-only repair remain unchanged.

Preserved and adapted both regression sets: 27 preparation helper groups, 16 native/caller dotfile groups, and 3 additional native Chezmoi-to-installation groups pass, plus PowerShell guidance and syntax/ShellCheck. The existing Windows retirement fixture uses one inert Desktop stub and preserves its failure/finalization assertions. Full pre-push verification runs before publishing. Earlier parent/worker validation passed BB server, reliability/PowerShell, runtime, headless, Homebrew/CLT, weekly and lint checks; optional external-source integrations were skipped as documented.

Versions: Ubuntu 278, macOS 251, Pi 229, Bazzite 130 and WSL 212. The main TASK-51 history remains active; the duplicate devinabox planning record is preserved in the CLI archive. No live setup, permission/service/package changes or enrollment; native rollout remains unverified.
<!-- SECTION:FINAL_SUMMARY:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 Run affected preparation/server, reliability, shared runtime and headless contracts, available PowerShell fixtures, Bash syntax, ShellCheck and diff checks.
- [x] #2 Review scope, preservation and fixture-versus-live evidence; record limitations and final summary.
<!-- DOD:END -->
