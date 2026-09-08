---
id: TASK-12
title: Default Paseo daemons and desktop clients to the beta channel
status: Done
assignee:
  - '@pi'
created_date: '2026-09-08 21:33'
updated_date: '2026-09-08 22:11'
labels: []
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Scott wants the Paseo v0.8 beta on all machines on their next setup run. Add a consistent beta default and stable override for setup-managed daemons and desktop clients, without remote fleet mutation or weakening headless platform safeguards.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Setup-managed daemon installation explicitly follows beta by default and stable when PASEO_CHANNEL=stable; invalid channel values fail before Paseo mutation.
- [x] #2 Desktop clients on supported desktop platforms use the selected release channel while preserving unrelated settings and existing app data; headless and WSL behavior remains safe and explicit.
- [x] #3 Documentation explains channel selection, next-run rollout, client/platform limits, and how to return to stable.
- [x] #4 Offline regression tests and lint pass; all modified setup script versions are incremented.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Add a shared-in-source PASEO_CHANNEL resolver (beta by default, stable -> npm latest, reject other values) to the setup scripts and use an explicit tag for each managed daemon install.
2. Configure the upstream Desktop settings document on macOS, native Linux, and Windows. Preserve unrelated fields, block legacy renderer channel overrides, refuse unsafe/malformed files, and require Desktop to be closed before a change. Seed future desktop installs on non-headless machines without adding a second installer or starting a bundled daemon. WSL directs users to win.ps1 for its host client.
3. Preserve current headless platform and service-restart rules. Add environment-template comments, update versions, and document app restart/update steps, platform/mobile limits, and stable rollback behavior.
4. Run offline Bash and PowerShell fixture tests, the existing regression suite, syntax checks, and lint. Do not run provisioning, install the beta locally, restart live daemons/clients, or update remote machines.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Scott approved beta as the default and requested daemon plus client coverage.
- npm registry currently reports latest=0.7.2 and beta=0.8.0-beta.1.
- Verified v0.7.2 and v0.8.0-beta.1 share the Desktop settings schema (upstream 4eab53e24e1b57c74b00945aa48a89d68ed755e3, packages/desktop/src/settings/desktop-settings.ts). It lives under Electron userData, uses settings.releaseChannel, caches in memory, and can import an older renderer channel unless migrations.legacyRendererSettingsImported is true.
- Desktop binaries exist for macOS x64/ARM64, Windows x64/ARM64, and Linux x64 only. There is no store beta for iOS; Android prerelease APKs are available manually.

- Implemented explicit daemon package tags and Desktop channel configuration across all six scripts. Preserved existing headless support gates and service restart detection. Bash caches the selected channel within the setup function so later environment-file loads cannot discard a process override.
- Added offline Bash and PowerShell fixtures for channel selection, process precedence, work/personal machines, repeat-run no-ops, unrelated settings, malformed/linked paths, running-client refusal, write failure cleanup, headless profiles, WSL, and Linux ARM limits.
- All 21 contract scripts pass in the normal machine environment. The new Paseo Windows fixtures and Telegram environment fixtures also pass with portable PowerShell 7.6.6 on Linux. Running the full suite with that PowerShell runtime reveals an existing setup-reliability-powershell.ps1:453 PR Lens direct-copy exclusion failure; reproduced identically from an unmodified HEAD archive. Left unrelated PR Lens code unchanged.
- ShellCheck passed for every modified Bash file; bash -n, Markdownlint, and git diff --check passed. Native Windows/macOS GUI updates and live beta runtimes were not exercised. No provisioning, live upgrades, daemon/client restarts, or remote-machine changes occurred.

Scott requested delivery to main. The branch starts at the current origin/main commit. Preparing a normal fast-forward push after re-running tests and lint.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Default setup-managed Paseo daemons and Desktop clients to the beta release channel so machines can adopt the v0.8 beta on their next setup run.

Changes:

- Add PASEO_CHANNEL=beta|stable with a beta default and process-environment precedence. Managed daemons use @getpaseo/cli@beta or @getpaseo/cli@latest.
- Select the Desktop updater channel on macOS, native Linux, and Windows. Preserve unrelated client data, prevent legacy renderer preferences from undoing the channel, write atomically, and refuse changes while Desktop runs. Desktop installation and launch remain manual.
- Preserve headless platform limits, WSL host boundaries, existing environment files, and service restart rules. Skip absent Linux ARM and headless Desktop profiles.
- Document client update steps, unsupported/mobile cases, stable rollback behavior, and custom user-data paths. Increment all six setup versions and update banner assertions.

Validation:

- All 21 normal-environment contract scripts pass.
- Paseo Windows and Telegram environment fixtures pass under portable PowerShell 7.6.6 on Linux.
- ShellCheck, Bash syntax checks, Markdownlint, and git diff --check pass.
- The full suite with portable PowerShell exposes an unrelated pre-existing PR Lens fixture failure at tests/setup-reliability-powershell.ps1:453, reproduced on unmodified HEAD.

Limits:

- No live or remote installations were updated. Native GUI/Windows runtime behavior still needs platform smoke tests. Desktop must be closed for a channel change and then reopened to check/install its update. Existing headless and mobile support limits remain.
<!-- SECTION:FINAL_SUMMARY:END -->
