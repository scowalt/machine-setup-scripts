---
id: TASK-14
title: Install and maintain Paseo Plain from machine setup
status: Done
assignee:
  - '@pi'
created_date: '2026-09-09 13:40'
updated_date: '2026-09-09 18:07'
labels: []
dependencies: []
references:
  - 'https://github.com/scowalt/paseo-plain/blob/v0.2.0/paseo-plugin.json'
  - 'https://github.com/scowalt/paseo-plain/releases/tag/v0.2.0'
  - tests/headless-paseo-daemon-contract.sh
  - 'https://paseo.sh/docs/plugins/v0.8/reference.md'
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Add Paseo Plain installation and update logic to the six standalone machine setup scripts so future setup runs get the plugin. Scott explicitly excluded inventorying existing machines and any one-time fleet rollout. Do not run setup on existing machines as part of implementation. Preserve existing behavior, settings, authentication, agent sessions, and manual-only rewriting.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 All six platform scripts install or update only the managed paseo-plain plugin for the correct local daemon user after required runtimes are available, without creating duplicate installations.
- [x] #2 Reruns preserve voice, model, display, cache files, deliberate disabled states, unrelated plugins, existing environment/authentication files, and existing shell/service configuration.
- [x] #3 Global plugin enablement requires explicit informed permission; first-install manual controls can be initialized once, while existing configuration is not reset.
- [x] #4 Missing or incompatible daemons, runtimes, credentials, unsupported platforms, and conflicting source IDs produce accurate actionable status, never a false installation-success claim or silent Paseo downgrade.
- [x] #5 Offline contract tests cover first install, no-op rerun, update, disabled/malformed settings, offline failures, alternate homes, source conflicts, and zero automatic model calls; all changed setup versions and docs are updated.
- [x] #6 Future setup runs use the tested release branch, update only a matching Git-managed paseo-plain installation, retain the previous working version on failed updates, and leave conflicting or directory-based installations unchanged with an actionable warning.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Revised scope: future setup runs only. No fleet inventory, SSH inspection, remote installation, canary rollout, or migration of the existing devinabox plugin. Confirm the fresh-install compatibility/enablement policy with Scott before coding.

1. Consume the public Git-installable release prepared in paseo-plain TASK-3. Use native Git install for an absent ID and native update only for an existing matching managed source. Never update all plugins or replace an unrelated/local-directory installation.
2. Add standalone Bash/PowerShell installation functions to mac.sh, ubuntu.sh, wsl.sh, pi.sh, bazzite.sh, and win.ps1 after the required user runtimes and an available local Paseo daemon. Resolve only the local setup user's daemon/home/endpoint during that setup run. Do not inventory or contact other machines.
3. Apply the approved fresh-install policy for compatible Paseo and global plugin enablement. Paseo Plain currently requires the 0.8 API and a fresh daemon has plugins disabled by default. Until Scott approves otherwise, do not silently install beta versions or enable the global switch. Preserve deliberate disabled states and the existing HEADLESS restrictions. Missing/inactive daemons must produce a clear deferred status, not a second daemon or a false success claim.
4. Initialize manual controls only on a fresh installation after trust approval. Preserve saved voice/model/display/timeout values, cache files, malformed existing settings, environment/authentication files, unrelated plugins, and shell/service configuration on reruns. Model calls remain explicit user actions only.
5. Test first installation, no-op reruns, managed updates, update failure recovery, missing/incompatible prerequisites, disabled/malformed configuration, source conflicts, and alternate homes with temporary fixtures and fake Paseo/Pi boundaries. Do not run full setup or make real model requests.
6. Run available platform tests, headless and Pi default regressions, pi-prose non-restoration checks, syntax validation, ShellCheck, Markdownlint, whitespace checks, and secret scans. Increment changed setup-script versions and update installation/maintenance documentation. Keep earlier unrelated cleanup identifiable.
7. Deliver reviewed source changes for future setup runs only. Do not deploy or reload the plugin on current daemons. Dotfiles do not manage live plugin settings, credentials, or code.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Current setup provisions Paseo daemons only for the established HEADLESS paths; WSL and Windows deliberately reject strict HEADLESS=1, and macOS requires its existing canary opt-in. The plugin can still target already-running desktop/WSL daemons without changing that policy. Source currently lacks a Git dependency build step and defaults manual controls to disabled, so installation alone would not make the answer button appear. The plan explicitly handles dependency preparation and one-time control initialization.

Scope correction from Scott: remove fleet inventory and one-time rollout entirely. TASK-15 was archived as out of scope, not completed. This task is only future machine-setup-script integration; local-to-Git migration and per-host rollout reporting are removed. The fresh-install beta/global-enable policy remains unanswered.

Scott said continue after narrowing scope to future setup only. Proceeding with the documented conservative policy: do not upgrade to beta or enable a disabled global switch automatically; report unmet prerequisites. Tests use the agreed temporary-home and fake CLI/process boundaries. No inventory, existing-daemon change, or real model call.

Corrected a test-harness isolation error: sourcing mac.sh invoked its unconditional main entry point. The test ran with a temporary HOME and fake package-management commands, but attempted macOS setup before its timeout. No headless daemon was started (HEADLESS was not enabled); dotfiles access failed, and the live Paseo Plain configuration fingerprint is unchanged. Temporary fixture downloads/files were removed and no fixture processes remain. The replacement harness extracts only the target function. Auditing the zsh permission step separately because it references /usr/local/share/zsh outside HOME.

The side-effect audit found /opt/homebrew zsh paths absent and /usr/local/share/zsh root-owned with unchanged July timestamps, predating the test. The temporary CLT marker is absent, and the fixture home was removed. The corrected package-version test now extracts only install_paseo_cli, never a script entry point. It reproduced an unqualified stable-tag install replacing a 0.8 beta request; the fix preserves the installed 0.8 version. All 12 installer tests and ShellCheck now pass.

Implemented the same embedded installer in all six standalone scripts. It requires an already enabled compatible local daemon, preserves directory/conflicting sources and disabled settings, seeds only absent first-install configuration, and uses native Git add/update on release. Four headless CLI installers preserve an existing 0.8.x version instead of reinstalling a potentially older stable tag.
Validation: 13 installer tests pass, including the isolated PowerShell wrapper under a checksum-verified portable PowerShell 7.6.6. Full win.ps1 parsing exposed and fixed a trailing comma from the earlier pi-prose removal. Headless, pi-prose, companion-package, four Pi-default tests, ShellCheck, Bash syntax, Markdownlint, and whitespace checks passed. PowerShell testing here is on Linux, not a full native Windows provisioning run. No full provisioning entry point was invoked after correcting the earlier harness incident.

Final review added a preflight for paseo.pid because native daemon status prefers its saved endpoint over config.json and probes it. The regression first installed instead of deferring for a nonlocal PID endpoint; all six copies now reject it before any CLI call. All 14 installer tests pass, including the portable PowerShell wrapper. Repeated ShellCheck, syntax, headless/prose/companion contracts, Markdownlint, whitespace, and changed-code secret scanning passed. The earlier four Pi-default tests also passed.
Paseo Plain v0.2.0 is published on the tested release branch at 3f1d281. Setup changes remain local and uncommitted with the earlier pi-prose cleanup preserved. No existing-daemon reload or actual model call was performed; the live configuration fingerprint remains unchanged. Native Windows provisioning, ARM/WSL runtime acceptance, and broader real-client acceptance are not established by these fixtures.

Scott requested publication to remote main. Integrated remote 53d14d5, which independently adds the beta-default and explicit stable PASEO_CHANNEL policy. Kept that upstream channel implementation unchanged and removed the obsolete exact-version pin. Updated the integration regression to cover default beta, explicit beta, and explicit stable while an old beta is installed. All 14 installer tests and full win.ps1 syntax pass with portable PowerShell; ShellCheck, Markdownlint, whitespace, and staged secret scans pass. Operational Backlog notes remain local rather than being added to the source commit.

Published setup source to origin/main at 44534cd6d0c90f3669796cea891ca79492390e67 and verified the remote ref matches. The first pre-push run stopped at stale exact-version expectations in the managed-skill contract; updated those expectations and reran all pre-push checks successfully without bypassing hooks. All 14 isolated installer tests and the PowerShell syntax/channel fixtures also passed. No GitHub Actions runs are configured for this commit. Private operational notes stay local.

Scott explicitly requested publication of these task records to remote main, including the archived out-of-scope rollout task. Updated active references to public plugin sources. TASK-15 remains archived, not completed.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Published Paseo Plain install/update support across all six setup scripts to remote main in [44534cd](https://github.com/scowalt/machine-setup-scripts/commit/44534cd6d0c90f3669796cea891ca79492390e67).

Preserves settings, cache, disabled choices, and conflicting sources. Uses the public release branch and keeps the upstream beta-default/explicit-stable PASEO_CHANNEL policy. Missing plugin prerequisites defer installation. The same commit includes the separately approved pi-prose package/default removal without deleting custom prose files.

Validation: all 14 isolated installer tests, portable PowerShell syntax and channel fixtures, staged secret scanning, ShellCheck, Markdownlint, and the full pre-push shell contract suite passed. Remote main matches the tested commit. No machine rollout, daemon reload, or real model call was performed. Native Windows/ARM/WSL provisioning acceptance remains separate.
<!-- SECTION:FINAL_SUMMARY:END -->
