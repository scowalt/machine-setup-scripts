---
id: TASK-18
title: Allow the Bazzite system home alias during Paseo Desktop setup
status: Done
assignee:
  - '@pi'
created_date: '2026-09-11 18:44'
updated_date: '2026-09-11 19:01'
labels: []
dependencies: []
references:
  - bazzite.sh
  - tests/paseo-release-channel-contract.sh
  - tests/paseo-release-channel-powershell.ps1
  - CLAUDE.md
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Bazzite setup version 104 aborts during Paseo Desktop channel setup with an unsafe-directory error. An offline fixture reproduces the error with the normal /home -> /var/home system alias. Handle this alias without weakening checks on client profiles or settings.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Bazzite Desktop channel setup accepts the trusted system /home alias and succeeds in an offline fixture.
- [x] #2 Untrusted home aliases, linked user/profile/settings paths, malformed settings, and running-app protections remain enforced.
- [x] #3 Regression tests cover the alias, preserved settings, and repeated setup without running full setup scripts or live Paseo.
- [x] #4 Affected script versions and documentation are updated, and relevant Bash, PowerShell, and lint validation passes.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Review the shared channel guard and Bazzite call site, keeping this exception limited to the trusted OS home alias. The user approved this plan by asking to make the previously described setup fix.
2. Add an offline regression fixture, reproduce the failure, and implement the smallest safe alias exception without resolving client-owned symlinks.
3. Update affected versions and documentation, run the Bash and PowerShell channel fixtures plus ShellCheck, and review the diff.
4. Record verification and limitations. Do not access or modify the remote machine, source whole setup scripts, or run live Paseo.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Confirmed the fatal error is raised by the shared Bash ancestor-directory guard. Bazzite calls this guard before the remaining development tools.
- Chosen narrow exception: on Linux only, accept /home pointing exactly to var/home or /var/home when the link and real system directories are root-owned and the directories are not group/world-writable. Continue rejecting every user/profile/settings symlink. Keep the shared block identical in all five Bash scripts.
- Use temporary filesystem fixtures with explicit test-only root path substitution and simulated root ownership. All link/type/permission and settings behavior still uses the extracted production functions. Existing PowerShell runtime is available in /tmp for offline fixtures.

- Red/green verified: the new relative-home regression failed with the exact logged unsafe-directory message before the fix, then passed after the narrow alias exception. All 17 alias fixtures now pass.
- The shared five-script Bash channel suite and Windows PowerShell fixture suite pass. ShellCheck passes for all five modified setup scripts and the modified Bash contract. Versions incremented and README/agent guidance updated.
- Fixture isolation excludes package-manager shims to prevent them from initializing temporary HOME directories. A first extra Paseo Plain test run selected system Node 18; rerunning with the installed Node 24 binary, not changing production code for that test-environment issue.

- Final verification: 18 system-home alias tests pass, including regular /home directories and physical home paths. The full Bash channel suite, Windows PowerShell channel suite, 30 Paseo Plain setup tests on Node 24, ShellCheck, Bash syntax checks, Markdownlint, and git diff --check pass.
- Native migration isolation suite was invoked but skipped because PASEO_TEST_PLUGIN_SERVICE_MODULE was not supplied. Native migration code is unchanged.
- Self-review confirms the exception is Linux-only, limited to the exact system alias, and requires trusted ownership/permissions on both sides. User/profile/settings links remain rejected. All five Bash channel blocks remain identical and versions increased by one. No remote machine, live Paseo daemon, shell profile, environment file, or credentials were changed.

- Publication requested. Synced onto remote main at 6477413, preserving the newer shared-Node runtime fix. Resolved only version-header conflicts and incremented Bazzite to 106 (macOS 225, Ubuntu 247, Pi 206, WSL 189).
- Resolved the concurrent TASK-17 collision through Backlog CLI demote/promote; this task is now TASK-18 and the upstream Node-runtime task remains TASK-17. Running validation again on the combined changes before publication.

- Combined-branch validation passes all 23 standard Bash contract entry points. Explicit PowerShell channel fixtures pass; shared-Node PowerShell fixtures pass 959 assertions. ShellCheck, Markdownlint, and whitespace checks pass. Updated the upstream version-banner expectations to match this change.
- The optional broad PowerShell reliability suite fails at its PR Lens ownership assertion on both this branch and an isolated copy of unmodified main 6477413. Recorded this pre-existing failure as TASK-19, without changing the Windows implementation or that fixture. The standard hooks do not discover the temporary PowerShell runtime automatically. Native migration isolation remains skipped without its explicit module.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Fix Bazzite setup aborting at Paseo Desktop channel selection when /home is the normal system alias for /var/home.

Changes:

- Accept only the exact Linux system alias when the link and real system ancestors are root-owned and the directories are not group/world-writable. Keep client-path, malformed-settings, and running-app protections.
- Keep the five shared Bash channel blocks identical. Bump Bazzite to 106, macOS to 225, Ubuntu to 247, Pi to 206, and WSL to 189 after preserving the newer shared-Node runtime fix on main. Update banner-test expectations.
- Add 18 isolated filesystem regression tests and include them in the channel contract. Update README and agent guidance, including authenticated retrieval from the canonical log collector.

Verification:

- Reproduced the logged error before the fix; all 18 regression cases now pass.
- All 23 standard Bash contract entry points pass on the combined branch, including 30 Paseo Plain setup tests and shared-Node tests. Explicit PowerShell channel tests and shared-Node PowerShell tests (959 assertions) pass. ShellCheck, Markdownlint, syntax/version checks, and whitespace checks pass.
- The optional broad PowerShell reliability suite has a PR Lens ownership failure reproduced on unmodified main 6477413; tracked separately as TASK-19. Native migration isolation is skipped without its explicit native module.

Scope: publish the code fix at the user request. No live setup, Bazzite changes, Paseo operations, or credential changes. Filesystem fixtures simulate the system alias without sudo.
<!-- SECTION:FINAL_SUMMARY:END -->
