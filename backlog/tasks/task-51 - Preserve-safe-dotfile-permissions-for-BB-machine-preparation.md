---
id: TASK-51
title: Preserve safe dotfile permissions for BB machine preparation
status: Done
assignee:
  - '@pi-task51'
created_date: '2026-09-28 17:32'
updated_date: '2026-09-28 20:37'
labels:
  - bb
  - setup
  - chezmoi
dependencies: []
references:
  - ubuntu.sh
  - mac.sh
  - pi.sh
  - bazzite.sh
  - wsl.sh
  - tests/test_bb_dotfiles_umask.py
  - tests/test_bb_machine_preparation.py
  - 'https://logs.scowalt.com/logs/devinabox/2026-09-28-17-14-14-644.log'
documentation:
  - docs/plans/2026-09-28-bb-preparation-permissions.md
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Repository implementation complete and independently reviewed. See docs/plans/2026-09-28-bb-preparation-permissions.md for the approved contract. Live rollout remains unverified and unauthorized.

All five Bash setup scripts now provide Chezmoi-only permission convergence and bounded secret-safe BB preflight diagnostics. Existing Ubuntu server protection is retained. The new command-scoped restriction applies only to eligible, non-deferred machine preparation; existing BB roles that defer preparation receive no additional preparation-driven restriction. Standalone/automatic Chezmoi operations and persistent dotfile policy remain outside scope. Explicit overrides and unmanaged unsafe paths remain preserved and blocked.

Confirmed reported run: devinabox, ScoBot, local log 2026-09-28-131312.log (Ubuntu v276). Read-only metadata found 0775 service directories and 0664 service files. Extracted inert fixtures reproduce the exact original generic preflight error independently for a writable ancestor and for a writable unrelated unit; equivalent safe-mode fixtures pass. These are established blockers, not proof that the real account has no others. The prior TASK-47 protection covered Ubuntu BB_SERVER=1 only.

No live repair, setup, live package changes, service lifecycle, enrollment or rollout was performed or authorized.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 All five Bash setup scripts cover the approved BB preparation scope; native Windows behavior and platform/headless gates remain unchanged.
- [x] #2 Permission convergence uses normal Chezmoi operations with an additive command-scoped umask, preserving stricter caller masks, the caller shell mask and explicit native configuration. BB preflight remains read-only; no recursive chmod or repair of unmanaged files.
- [x] #3 Unsafe or unverified BB preflight results stay fatal and preserve BB packages, roles and state. Safely inspectable blockers produce a bounded list of operation, HOME-relative path where safe, observed mode where known, and controlled reason; inspection stops beneath unsafe boundaries.
- [x] #4 Diagnostics never expose service contents, process arguments, credentials or raw exceptions. Unrelated work and log finalization retain existing failure aggregation.
- [x] #5 Isolated regression fixtures cover observed directory/file modes, repeated native Chezmoi convergence, preservation and diagnostics. No live setup, enrollment, service mutation or fleet changes are used for testing.
- [x] #6 Retain Ubuntu server dotfile protection and apply the new restriction only to eligible non-deferred preparation, using existing effective flag precedence and role/platform gates. Known existing BB roles defer without an additional preparation-driven restriction.
- [x] #7 Keep persistent dotfile policy, standalone/automatic Chezmoi operations, and the shared Node helper files-only repair unchanged. Document the standalone limitation and manual reconciliation for explicit overrides or unmanaged blockers.
- [x] #8 Native synthetic-source Chezmoi-to-preparation fixtures cover repeated directory and file convergence, existing/missing targets, stricter masks, explicit overrides, deferrals and actual call sites across all five scripts. Diagnostic tests cover bounded output, unsafe ancestors, secret sentinels and unrecognized helper output.
- [x] #9 Full enabled pre-push caller fixtures remain inert at unrelated BB Desktop setup calls; preserve their original failure/log-finalization assertions without changing production Windows behavior.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
User authorized implementation in one subagent after approving the complete design.

1. Reproduce directory and service-file permission failures with extracted fixtures; extend native synthetic-source Chezmoi coverage to the actual preparation seam.
2. Implement identical shared eligibility/command-scoped dotfile protection across the five Bash scripts while preserving server protection, existing-role deferrals, explicit overrides and platform gates.
3. Add bounded, fail-closed, secret-safe diagnostics without traversing unsafe boundaries or changing BB preflight ownership rules.
4. Update versions, documentation and contract wiring; run required regressions and lint using isolated fixtures only.
5. Subagent self-reviews and reports exact evidence/limitations. Parent independently reviews the diff and verifies key tests before marking the task Done.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
User explicitly requested implementation in a subagent. Earlier design-only/no-implementation wording is historical and superseded for repository implementation only. Live setup, real permission repair, package changes, enrollment, lifecycle changes, commits and pushes remain unauthorized. One implementation worker will share the current worktree; parent will avoid concurrent source edits and review afterward.

- Started authorized implementation; read CLAUDE.md, CONTEXT.md, approved design and task. Preserving parent edits and live-rollout prohibition.
- Added actual native-Chezmoi-to-preparation regression: BB_SERVER=0 under 0002 fails real preparation preflight (red). Added writable-directory diagnostic regression; existing generic-only output cannot identify the blocker. All fixtures are disposable/inert.

- Implemented one shared preparation platform gate and subprocess-only Chezmoi mask wrapper across all five scripts; Ubuntu uses its existing server selection after actual flag resolution. Known role deferrals reuse the existing role helper; no Node/npm or lifecycle work at the dotfile boundary. Shared Node files-only repair unchanged.
- Implemented eight-record/4096-byte fail-closed diagnostic protocol, safe relative paths/categories/modes/reasons, independent safe-branch collection, ancestor-first inspection (including service-link targets), and binary/unknown-output rejection. No preflight permission repair.
- Native synthetic Chezmoi init (all three authentication call sites), update and apply now converge both directories and service files across all five scripts; repeated ordinary 0002 baseline fails then protected operation passes. Stricter/explicit masks, fallback selection, actual-runner flags, deferrals, unmanaged blockers, sentinels and malformed protocol regressions added. Initial full fixture runs passed; final contracts/lint underway.

- BB preparation/server, setup reliability, shared Node runtime and weekly regressions passed. Discovered existing PowerShell 7.6.6 under /tmp and used it for BB Windows guidance, shared runtime (1409 assertions in each argument mode) and direct setup-reliability fixtures; no tooling installed.
- Headless contract initially failed at the unchanged configured-listener fixture because inherited mise jq shim could not resolve under its disposable HOME. Rerunning with native /usr/bin:/bin first passed; no production/headless code changed.
- Final self-review added binary/unterminated-output regressions, ancestor-first service-link traversal tests, and explicit proof the earlier dotfile boundary never calls Node/npm/process inventory. Baseline HEAD helper fails both directory and unrelated 0664 service diagnostic regressions; current helper passes both with no mutation. Parent CONTEXT.md and design content preserved; only obsolete design authorization sentences updated.

- Final BB preparation contract: 24 preparation tests + 15 dotfile tests + PowerShell Windows guidance passed. BB server contract: 10 directory checks + 15 dotfile tests + generated-command/lifecycle/npm/native-lock fixtures passed. Final Bash syntax, ShellCheck, markdownlint and git diff --check passed.
- Self-review caught POSIX symlink/.. ordering while adding ancestor-first service resolution. Added a red test with a Homebrew-style opt link and benign lexical-path decoy; fixed resolution to process .. only after links, and reran it green. Trusted links, empty registrations and /dev/null masks still pass without mutation. Shared five-script blocks are identical; shared Node files-only helper and win.ps1 are byte-for-byte unchanged.
- Remaining coverage limitations: native macOS/WSL2/ARM installation and enrollment, native Windows ACL/platform behavior and live rollout remain unverified/forbidden. Optional real-dotfiles shared-runtime convergence skipped without PI_RUNTIME_DOTFILES_SOURCE; weekly suite skipped two optional MANAGED_SKILLS_CLI cases and one PI_SKILLS_DOTFILES_SOURCE case. The new synthetic native-Chezmoi coverage had no skips.
- All AC/DoD checkboxes now have fixture/lint/self-review evidence. Leaving TASK-51 In Progress for parent independent review; no commit, push, PR, worktree switch, live setup, permission repair, package/service mutation, BB/Paseo startup, enrollment, authentication or Tailscale operation performed.

Final coverage addition: native Chezmoi deferrals now run init/update/apply for existing BB roles across all five scripts and native applies for both data/prefix overrides; ordinary 0775/0664 behavior and preserved state are verified, and preparation defers before runtime. Final reruns passed: preparation 24 tests + dotfiles 16 tests + PowerShell; server 10 directory tests + dotfiles 16 tests + lifecycle/native-lock fixtures. No production changes after the final lint/headless run.

- Parent independent review accepted the five-script diff and shared helper identity, role/flag/platform selection, scoped Chezmoi authority, explicit overrides and bounded fail-closed diagnostics. No blocking findings.
- Parent independently passed BB preparation (24 preparation + 16 dotfile tests and PowerShell guidance), BB server (10 directory + 16 dotfile tests and lifecycle/native-lock fixtures), setup reliability, shared Node runtime (18 tests plus both 1409-assertion PowerShell modes), headless fixtures with native tool PATH, Homebrew results (8 tests), Bash syntax, ShellCheck, Markdown lint and whitespace checks. Optional shared-runtime real-dotfiles integration remains skipped; native-platform/live rollout remains unverified.
- Updated design completion status and moved the orchestration-only workflow source out of the repository into parent thread storage. No production edits after worker completion; only documentation/task wrap-up. No commits, pushes or live changes.

User authorized merging the reviewed change into remote main. Fetched origin/main at a8ab2b5; three newer macOS CLT commits overlap mac.sh and preparation test runner fixtures. Will commit the reviewed task, integrate remote main normally, resolve overlaps preserving both features and increment macOS version, then verify and non-force push with repository hooks enabled. No live deployment is included.

- Integrated origin/main a8ab2b5, preserving its macOS CLT readiness/repair and dependent-work gating. Only textual conflict was the macOS banner; resolved to v250 with both changes represented. Remote preparation runner fixtures merged cleanly.
- Combined-tree verification passed: BB preparation (24 tests), dotfile convergence (16 tests), PowerShell guidance, macOS CLT (22 tests), Homebrew results (9 tests), ShellCheck and whitespace checks. Finishing an attributed merge commit with hooks enabled, then the full pre-push contracts before publishing.

- First authenticated push was blocked by the full pre-push suite, not remote permissions. Enabling available PowerShell exposed a pre-existing missing Install-BbDesktop stub in tests/infisical-retirement-windows.ps1 (win.ps1 is unchanged by this task). Standalone fixture reproduces the failure; providing only an inert successful Install-BbDesktop function makes all original assertions pass. Adding that fixture-only isolation shim rather than skipping PowerShell or bypassing hooks.
- Git had no active HTTPS/gh login; verified the existing account GH_TOKEN for scowalt and used it through a command-scoped gh credential helper. No credential output, persisted login or global Git configuration changes.

Fixture-only Install-BbDesktop stub added; standalone full Infisical contract now passes with PowerShell enabled, retaining failure aggregation and log-finalization assertions. No production Windows changes.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Implemented BB preparation permission convergence across Ubuntu v277, macOS v249, Pi v228, Bazzite v129 and WSL v211. Normal Chezmoi initialization, update-and-apply and full apply now receive additive subprocess-only protection for eligible non-deferred preparation. Existing Ubuntu server protection, effective flags, role/platform gates, stricter masks, explicit native configuration and Pi fallback selection are preserved. Shared Node files-only repair and native Windows behavior remain unchanged.

Preflight remains read-only and reports up to eight controlled blockers within a 4096-byte helper protocol. It stops beneath unsafe ancestors, preserves trusted service links/masks, suppresses unsafe paths/raw errors, and rejects malformed output without echoing it. Explicit overrides and unmanaged blockers remain fatal and untouched. Updated README, design documentation and version banners.

Verification: original native preparation-only apply under 0002 reproduced the failure; synthetic native Chezmoi-to-preparation fixtures now repeatedly converge directories and files across all five scripts. Parent independently reviewed the complete diff and passed preparation/server contracts, setup reliability, shared Node/PowerShell, headless, Homebrew, Bash syntax, ShellCheck, Markdown lint and whitespace checks. Worker additionally passed weekly and direct PowerShell reliability regressions.

Limitations: optional real-dotfiles/skills integration cases were skipped when their inputs were unavailable. Native macOS/WSL2/ARM installation, Windows ACL behavior and live rollout remain unverified. No live setup, permission/package/service changes, enrollment, authentication, Tailscale changes, commits or pushes.

Remote-main integration: preserved the newer macOS CLT readiness changes and advanced mac.sh to v250. Combined BB preparation/dotfile, CLT and Homebrew tests pass; no feature changes were discarded.
<!-- SECTION:FINAL_SUMMARY:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 Update versions of modified setup scripts, README scope/recovery guidance and relevant tests; preserve identical shared helper blocks.
- [x] #2 Pass BB preparation/server, setup reliability, shared Node, headless and affected dotfile contracts, Bash syntax, ShellCheck and documentation/whitespace checks. Report unavailable PowerShell/native-platform verification explicitly.
- [x] #3 Self-review scope, idempotency, ownership, role deferrals, secret-safe diagnostics and preservation; no live setup or rollout during development.
<!-- DOD:END -->
