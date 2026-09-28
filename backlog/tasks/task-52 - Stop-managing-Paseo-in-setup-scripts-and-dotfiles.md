---
id: TASK-52
title: Stop managing Paseo in setup scripts and dotfiles
status: Done
assignee:
  - '@pi'
created_date: '2026-09-28 20:33'
updated_date: '2026-09-28 21:29'
labels: []
dependencies: []
references:
  - mac.sh
  - ubuntu.sh
  - wsl.sh
  - pi.sh
  - bazzite.sh
  - win.ps1
  - /home/scowalt/Code/dotfiles
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Relinquish all Paseo management as machines migrate to BB. Remove future installation, configuration, lifecycle, validation, and cleanup operations, without uninstalling or mutating existing Paseo state. Remove Paseo source artifacts from the dotfiles repository without applying dotfiles or adding deletion rules. Preserve independent Pi/OpenCode Go support and existing BB provisioning.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 All six setup scripts contain no active Paseo installation, configuration, health-check, lifecycle, plugin retirement, or surplus-CLI cleanup operations; existing Paseo state and existing environment files are left untouched.
- [x] #2 Dotfiles no longer distributes the Paseo GitHub-token helper or systemd drop-in, and current instructions no longer prescribe them; no live apply, service change, credential access, or managed deletion is performed.
- [x] #3 Independent Pi/OpenCode Go, BB preparation/server/Desktop, shared runtime, and unrelated setup behavior remain intact; no automatic BB enrollment or session migration is added.
- [x] #4 Current documentation and script versions are updated; obsolete Paseo-only tests are replaced by non-management coverage and affected contract tests and lint checks pass using temporary inert fixtures.
- [x] #5 Windows and WSL retain their existing early exact HEADLESS=1 rejection with Paseo-independent diagnostics; existing BB support limits remain unchanged.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Confirm the remaining HEADLESS compatibility boundary with the user before code changes. Windows/WSL currently reject exact HEADLESS=1 early for Paseo, and BB preparation independently rejects WSL HEADLESS=1; recommend preserving that existing support boundary with Paseo-independent diagnostics.
2. Remove Paseo-only helpers, callers, environment examples, result flags, and safety/lifecycle gates from all six scripts. Preserve independent Pi/Go and existing BB policies, failure aggregation, shared helpers, and log finalization. Increment each script version.
3. Remove only the Paseo token helper and service drop-in source files in /home/scowalt/Code/dotfiles and update its README. Do not apply dotfiles, add removal rules, read credentials, or change any live service/state.
4. Refresh current setup README/agent guidance and glossary; preserve historical plans and completed tasks as history. Replace Paseo-only tests with non-management regressions and adapt shared orchestration tests to prove Pi/Go/BB remain independent.
5. Run shell syntax/ShellCheck, inert temporary-home non-management tests, affected BB/Pi/Go/runtime/headless/CLT/reliability/weekly/environment-template suites and available PowerShell fixtures. Review both repository diffs and report unavailable native checks. No live setup, fleet changes, app execution, or enrollment.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- User approved removal of all Paseo management, dotfiles source cleanup, and preservation of independent Pi/OpenCode Go and existing BB behavior.
- Read-only inventory found the dotfiles token helper, systemd drop-in and README instructions. Both repositories were initially clean.
- Remaining decision: retain the current exact HEADLESS=1 unsupported boundary on Windows/WSL with generic diagnostics. No runtime code changes made. ShellCheck is available; pwsh is not on PATH.

User approved the complete plan and Q4 recommendation: retain Windows/WSL early HEADLESS=1 rejection with neutral messaging. User explicitly requested implementation in a subagent.

Implementation inventory complete. Ubuntu tmux uses the former Paseo systemctl helper; retain it under a generic name. Preserve native headless platform limits plus early Windows/WSL exact-1 rejection. Dotfiles has only the two approved artifacts and README references; source-only removal, no apply.

Removed duplicated Paseo management and callers from all six scripts, preserving independent Pi/Go and BB paths; renamed Ubuntu tmux user-bus helper and retained generic headless platform gates. Removed dotfiles source helper/drop-in only and refreshed current docs/glossary/versions. Replaced deleted management tests with inert legacy-state/source-absence and generic headless coverage; focused fixtures pass (PowerShell runtime unavailable). Broad regressions underway.

- Verification: all 34 remaining tests/*.sh suites passed; full Python discovery passed 346 tests (13 skips). Includes BB preparation/server/Desktop, Pi/Go auth/wiring/permissions/packages/defaults, native Go credential-lock/catalog probe, shared Node repair with dotfiles integration, managed skills/render integration, reliability, CLT/Homebrew, weekly, generic headless and Telegram contracts. New state fixtures preserve legacy configuration/services/plugins/credentials/recovery sentinels and obsolete invalid inputs while proving Pi failure aggregation and independent BB/finalization.
- Initial five suite failures were inherited mise jq-shim trust errors; reran using the existing jq 1.8.2 binary, without changing trust/security config. Concurrent Backlog fixtures hit boundary-changed on shared temporary-directory metadata; serial reruns and full serial Python discovery passed.
- Bash syntax and ShellCheck passed for every modified shell file; Markdownlint passed in both repositories; git diff --check passed. Function comparison against HEAD confirms unrelated helper bodies remain unchanged. Remaining Paseo references outside historical records are intentional non-management docs, version descriptions and fixtures.
- Unavailable checks: pwsh/PowerShell wrappers and native Windows ACLs; native Apple/ARM/GUI/boot rollout; optional native skills CLI and npm registry/adapter probes without supplied CLI paths. No live setup, Paseo/BB lifecycle/inventory, credential access, app/skill execution, model request, dotfiles apply to real HOME, enrollment, commit, push or branch change. Dotfiles changes are exactly README plus removal of the two approved source artifacts; .chezmoiremove is unchanged.

Origin review completed: compared retained function bodies and renamed platform/tmux helpers against HEAD; only approved Paseo removal, generic headless diagnostics, template/version changes and Go notification decoupling alter runtime behavior. Confirmed dotfiles diff is exactly the two source removals plus README, with no deletion rules. Independently reran Bash syntax, ShellCheck, cross-repository Paseo non-management, generic headless, Pi/Go wiring and both whitespace checks successfully (PowerShell cases explicitly skipped). Inspected successful isolated Python and Backlog rerun logs to reconcile the earlier concurrent-fixture failure in the initial final logs. No implementation blockers found; changes remain uncommitted.

Publication integration: merged current origin/main into the approved change, preserving newer BB preparation permission safeguards, controlled diagnostics and Windows fixture isolation. Resolved glossary additions by keeping both terms; advanced five Bash versions beyond remote main. Adapted the headless fixture to the newly extracted BB platform gate without changing its policy. Merged-state non-management, headless, BB preparation/permissions/server/Desktop, Pi/Go wiring, reliability, CLT/Homebrew and ShellCheck validation passed; PowerShell remains unavailable.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Relinquished all future Paseo management in all six setup entry points without adding uninstall or migration behavior. Existing installations, services, settings, credentials, plugins, recovery data and environment files remain owner-managed. Removed channel/profile/daemon/Plain/surplus-CLI helpers, callers and dependent flags; retained independent Pi OpenCode Go, model defaults, package safety, the full skill suite and existing BB preparation/server/Desktop behavior. Ubuntu tmux keeps the shared user-systemd control helper under a generic name. Exact Windows/WSL headless rejection and other platform limits remain intact.

Removed the Paseo token-helper and service-drop-in sources from /home/scowalt/Code/dotfiles and replaced its instructions with preservation guidance. No target-deletion rules or live apply were added. Updated setup README/CLAUDE/glossary and incremented each setup version once; historical plans and tasks remain intact. Replaced obsolete management tests with inert non-management/state-preservation and generic headless contracts and adapted shared fixtures without weakening Pi/BB gates.

Validation: all 34 remaining shell suites pass; Python discovery reports 346 tests, 13 explicit skips. Bash syntax, ShellCheck, Markdownlint and whitespace checks pass in scope. Existing native Go lock/catalog and temporary dotfiles/runtime/skills integrations passed. Environmental jq-shim and concurrent temporary-directory failures passed on isolated reruns without policy changes. PowerShell/native platform rollout and optional native skills/npm registry probes remain unverified as documented. No live lifecycle, enrollment, provider/model request, real-HOME dotfiles apply or Git publication occurred.
<!-- SECTION:FINAL_SUMMARY:END -->
