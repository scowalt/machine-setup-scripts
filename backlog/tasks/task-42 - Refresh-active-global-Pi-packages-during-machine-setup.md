---
id: TASK-42
title: Refresh active global Pi packages during machine setup
status: Done
assignee:
  - '@pi-implementor'
created_date: '2026-09-22 22:20'
updated_date: '2026-09-22 23:36'
labels: []
dependencies: []
references:
  - tests/test_pi_package_maintenance.py
  - tests/pi-package-maintenance-contract.sh
  - CONTEXT.md
  - README.md
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Every setup run should refresh Pi packages as well as maintaining the existing managed package set. Include user-added packages in the active global profile without touching projects or other profiles, losing local Git edits, relaxing npm policy, or concealing incomplete work.

Design interview decisions: all six platforms, personal and work machines; keep existing managed installs; preserve pins and resource exclusions; update packages even when their resources are disabled; apply package opt-outs/retirements before refresh; protect locally modified managed Git checkouts; respect offline mode but report the required refresh as incomplete.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 All six setup scripts perform a guarded pi update --extensions --no-approve refresh on eligible setup runs, supplementing rather than replacing existing managed installs.
- [x] #2 Refresh covers setup-managed and user-added packages only in the active global Pi profile; project packages, other profiles, local-path packages, declared pins/refs, resource filters, and unrelated settings remain unchanged.
- [x] #3 Disabled-resource packages remain eligible, while supported package opt-outs and retirements are applied first; any failed prerequisite or package maintenance step blocks the bulk refresh rather than refreshing an unsafe or retired registration.
- [x] #4 A read-only preflight blocks the bulk refresh and reports incomplete setup if a managed Git checkout has local changes that the native updater could discard, or if the relevant safety state cannot be verified.
- [x] #5 Offline mode is honored without forcing network access, but an offline refresh is explicitly reported as incomplete rather than successful.
- [x] #6 Refresh/preflight failures reach the final nonzero setup result while unrelated work and log finalization continue; unsafe or malformed metadata cannot produce false success.
- [x] #7 Existing npm security policy and custom npm commands are preserved; setup adds no extension loading, model requests, Pi self-update, model catalog update, or live/fleet mutation during development.
- [x] #8 Temporary extracted-helper and mocked-native fixtures cover scope isolation, pins/filters, Git edit protection, exclusions, offline/failure reporting, and all-six orchestration; relevant regressions and shellcheck pass, script versions and user documentation are updated, and unavailable platform coverage is disclosed.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Extend the existing package-maintenance fixtures with temporary profiles and inert Pi/npm/Git commands covering active-global scope, trusted-project exclusion, custom profiles/npm commands, pins/resource filters, retirements, offline mode, modified Git checkouts, malformed/linked metadata, and failures. Never invoke live setup or installed extensions.
2. Add identical shared package-refresh preflight logic across the six standalone scripts, with Bash and PowerShell wrappers. Inspect only the active profile and registered managed Git checkouts; fail closed on unsafe/unverified state and protect local edits without changing npm policy.
3. Invoke pi update --extensions --no-approve once after successful existing guarded package maintenance. Track package-block success separately from unrelated setup errors, block refresh after failed maintenance, and aggregate refresh failures without bypassing unrelated work or log finalization.
4. Update README guidance and all six script version/change headers. Preserve the glossary distinctions already recorded in CONTEXT.md.
5. Run package-maintenance and affected permission/runtime/retirement/Go/companion/AskClaude regressions plus shellcheck. Use PWSH_BIN if available; otherwise disclose the PowerShell/native Windows coverage gap. Review the diff and verify every acceptance criterion before marking complete.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Design interview complete: user approved active-global/all-six scope, incomplete result on failure, updating disabled-resource packages without enabling them, protection of edited Git checkouts, and incomplete reporting for offline refreshes. No script implementation has begun; awaiting confirmation of the consolidated plan.
Read-only investigation verified installed Pi 0.85.1 semantics. --no-approve excludes trusted project settings; Git ref reconciliation can reset/clean clones; failures propagate but malformed settings/offline no-ops need independent handling. Existing managed installs and adapter pin recovery must remain.
Available: backlog, shellcheck, python3, Node, Bun. pwsh was not found on PATH; alternate PWSH_BIN availability has not yet been established.

User approved implementation with: "implement this in the current workspace" and requested a Paseo handoff. The consolidated plan is approved; the receiving Implementor agent should proceed without another plan-approval round. Preserve the existing CONTEXT.md changes and continue on branch add-pi-update-extensions-to-setup-scripts in the same workspace. No setup code or tests have been changed/run yet.

- Implemented an identical active-profile refresh preflight across five Bash scripts and an aligned PowerShell wrapper. The helper rejects offline mode, malformed/linked metadata, and tracked, untracked, ignored, or unverifiable registered Git checkouts before invoking `pi update --extensions --no-approve`.
- Added a package-maintenance success gate so every managed install/retirement failure blocks bulk refresh while unrelated setup and log finalization continue.
- Added isolated scope, declaration-preservation, offline/error, Git safety, command, and all-six orchestration fixtures; updated dependent wiring/removal contracts.
- Updated README and bumped all six script versions.

Pre-release verification found that the refresh preflight approximated native hosted-Git normalization and could inspect a nonexistent path for valid aliases, allowing a dirty real checkout to reach update. Reopened to fix the AC #4 safety gap; no live update was run.

- Fixed the release-check AC #4 gap by replacing approximate hosted-Git normalization with a documented fail-closed canonical source subset. Valid but ambiguous hosted aliases/web URLs now defer refresh instead of mapping to a guessed nonexistent checkout.
- Strengthened repository inspection: reject inherited Git repository/object redirection, require real local `.git` metadata, verify top-level/git/common-directory identity, disable optional locks/fsmonitor, and reject parent-repository resolution.
- Added table-driven alias, trailing slash, encoded path, linked metadata, parent repository, inherited redirection, and canonical URL/SSH fixtures. Updated the stale AI-agent orchestration contract without weakening failure semantics.
- Re-ran every `tests/*.sh` pre-push contract successfully, plus ShellCheck and `git diff --check`. PowerShell execution remains unavailable.

Final cross-check found three remaining AC #4 gaps: native `www.github.com` and repeated `.git` normalization could diverge from the conservative parser, and linked checkout ancestors were checked only after a leaf existed. Reopened for narrow fail-closed parser and path-walk hardening.

- Closed final AC #4 bypasses: generic `www.` hosted-domain aliases and repeated `.git` suffixes now fail closed before checkout derivation. Regression cases use dirty canonical clones and prove update is never called.
- Checkout preflight now walks every existing component below the profile Git root before accepting a missing leaf, rejecting linked host/owner components and dangling links. Git redirection variables are rejected before the missing-checkout return.
- Added focused missing-leaf linked-host, linked-owner, dangling-host/owner, and missing-checkout redirection fixtures. Package maintenance contract, ShellCheck, and `git diff --check` pass; helpers remain identical and version bumps remain single increments.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Added guarded active-global Pi package refreshes to all six machine setup entrypoints.

Changes:

- Runs `pi update --extensions --no-approve` only after managed Pi installs, opt-outs, and retirements all succeed.
- Preflights only the selected global profile, preserving package declarations, filters, pins, custom npm commands, project settings, and other profiles.
- Blocks refresh for offline mode, unsafe metadata, and tracked, untracked, ignored, linked, malformed, or unverifiable Git checkout state.
- Aggregates refresh failures into the final nonzero setup result without stopping unrelated work or log finalization.
- Adds inert temporary-profile fixtures and updates dependent orchestration contracts, README guidance, and all six script versions.

Tests:

- `bash tests/pi-package-maintenance-contract.sh`
- `bash tests/pi-profile-permissions-contract.sh`
- `bash tests/pi-prose-contract.sh`
- `bash tests/pi-subagents-removal-contract.sh`
- `bash tests/pi-rpiv-removal-contract.sh`
- `bash tests/pi-companion-packages-contract.sh`
- `bash tests/pi-askclaude-contract.sh`
- `bash tests/pi-opencode-go-contract.sh`
- `bash tests/opencode-go-wiring-contract.sh`
- `bash tests/shared-node-runtime-contract.sh`
- `shellcheck mac.sh ubuntu.sh wsl.sh pi.sh bazzite.sh tests/pi-subagents-removal-contract.sh tests/pi-rpiv-removal-contract.sh`
- `git diff --check`

Coverage gap: PowerShell fixtures were skipped because neither `pwsh` nor `PWSH_BIN` was available; native Windows ACL behavior remains unverified on this Linux host.

Release-check hardening:

- Conservatively rejects noncanonical hosted-Git aliases, web-view URLs, fragments, queries, encoded paths, trailing slashes, and ambiguous repository paths rather than approximating native checkout identity.
- Verifies the exact repository/worktree/common-directory and blocks linked `.git`, parent-repository fallback, and inherited Git redirection before update. Inspection uses `GIT_OPTIONAL_LOCKS=0` and disables fsmonitor.
- Added focused regressions for the reported native alias reproductions and related identity boundaries.

Final verification: every `tests/*.sh` contract passed; ShellCheck and `git diff --check` passed. PowerShell/native Windows execution was unavailable.

Final AC #4 cross-check fix:

- Rejects `www.` hosted-domain aliases and repeated `.git` suffixes instead of inspecting an approximated path.
- Walks existing checkout path components before treating a missing clone as safe, blocking linked/dangling host or owner ancestors.
- Applies Git redirection checks before the missing-checkout path.
- Added dirty-canonical-clone and missing-leaf regression fixtures.

Focused verification: `bash tests/pi-package-maintenance-contract.sh`, ShellCheck on modified shell contracts, and `git diff --check` all pass. PowerShell execution remains unavailable.
<!-- SECTION:FINAL_SUMMARY:END -->
