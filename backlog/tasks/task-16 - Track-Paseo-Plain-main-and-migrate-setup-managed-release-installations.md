---
id: TASK-16
title: Track Paseo Plain main and migrate setup-managed release installations
status: Done
assignee:
  - '@pi'
created_date: '2026-09-09 19:52'
updated_date: '2026-09-09 20:43'
labels: []
dependencies: []
references:
  - tests/test_paseo_plain_setup.py
  - ubuntu.sh
  - 'https://paseo.sh/docs/plugins/v0.8/reference.md'
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Use the latest main branch commit for Paseo Plain on future machine setup runs, without a separate release-branch promotion step. Existing setup-managed release installations must move to main without losing user preferences, cached rewrites, credentials, or unrelated plugin state. Confirm a supported migration method before implementation.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 All six standalone scripts install and update matching Git-managed paseo-plain installations from the canonical repository main branch, retaining resolved PASEO_HOME and verified explicit local-host targeting.
- [x] #2 Future setup runs migrate matching setup-managed release installations to main using a reviewed and tested migration method; unsuccessful migration does not silently discard the existing installation or its user data.
- [x] #3 Disabled installations, directory installs, other remotes, custom refs and pinned revisions, global plugin trust, user preferences, cache, credentials, release-channel choices, and unrelated plugins remain unchanged.
- [x] #4 Isolated regression tests exercise fresh installs, release-to-main migration, main reruns, conflict/disabled preservation, and migration failures against the actual supported Paseo command contract; all lint and shell/PowerShell checks pass with updated versions and docs.
- [x] #5 No fleet inventory, remote execution, existing-daemon migration during development, daemon restart, model call, old-branch deletion, or unrelated GitHub policy change occurs.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Add tests at the isolated setup/CLI seam for fresh main installs, owned release migration, main reruns, preservation, and failures. Also exercise the actual Paseo 0.8 plugin-manager lifecycle with temporary homes, local fixture repositories, and fake runtime/model boundaries. Never source full provisioning scripts.
2. Change all six identical installers to install/update main. Permit migration only for the canonical paseo-plain Git source with verified release-branch metadata, an enabled installation, an already-enabled global switch, and the verified local daemon/home. Preserve directory installs, other remotes, custom refs, pinned revisions, and disabled choices.
3. Because Paseo 0.8 has no in-place ref change, use one explicitly approved, guarded remove/add migration under the same plugin ID. First make and verify a private recovery copy of the existing checkout and plugin-specific state. Do not touch live plugin-data. Preserve and restore any Paseo-owned plugin-settings removed by the native remove command before adding main. Do not edit cached sources.json or restart the daemon.
4. Persist migration progress so interrupted work is not mistaken for a fresh install. On command failure or timeout, retain recovery material, preserve user data, and stop with precise recovery instructions. Do not blindly retry or remove a possibly completed new installation. Verify the final canonical main source, enabled/running status, and preserved state before declaring success.
5. Update setup and plugin installation documentation, script versions, and contract expectations. Run isolated regressions, ShellCheck, Bash/PowerShell checks, Markdownlint, whitespace/secret checks, and normal commit/push hooks. Publish the reviewed setup correction and relevant plugin docs after approval.
6. Apply changes only on future setup runs. Do not inventory or contact the fleet, restart a daemon, change plugin/model behavior or GitHub branch policy, or delete the historical release branch or tags.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Inspected Paseo 0.8.0-beta.1 CLI help and source. plugin update accepts only an ID/--all, not --ref. plugin add --ref main rejects an occupied runtime ID. The plugin manager caches sources.json in memory, and config reload does not reload manual source-entry changes.

Native remove deletes the managed checkout and `plugin-settings/<id>`, not just its registration. Paseo Plain stores its own preferences and cache separately in plugin-data/paseo-plain, which must remain untouched. This makes remove/add a deliberate migration exception, not a generic failed-update recovery policy. Source evidence: packages/cli/src/commands/plugin/index.ts, packages/server/src/server/plugins/index.ts, managed-source.ts, bootstrap.ts, and the versioned plugin reference.

No setup/plugin code or live daemon was changed. Awaiting approval of the guarded remove/add migration and its brief plugin interruption before implementation.

Scott approved the guarded one-time remove/add migration, including the brief plugin interruption. Implementation is limited to future setup runs and the agreed isolated test seams.

Implemented main tracking and the approved one-time migration in all six identical embedded installers. Ubuntu is version 245; the other five banners and their contract expectations are updated. Matching release installs require a running/enabled catalog entry plus the exact canonical native source record. No cached source metadata is edited.

Migration creates a private, verified and flushed recovery copy of the checkout and plugin-specific state before native removal. Relative links confined to the checkout survive; external links and linked state paths fail before removal. Windows permission preparation fails closed before copying data. Native settings are restored before adding main. Live plugin-data is never rewritten by the migration. A persistent journal prevents incomplete attempts from being treated as fresh installs. Backups remain after success, and their cached rewrite copies do not expire automatically.

Validation:

- The fresh-install test first failed with release instead of main. The migration test first failed because the old installer deferred release sources. Both now pass.
- All 30 isolated installer tests pass, including safe reruns, source/disabled preservation, failed removal/activation/addition, lost success responses, timeout, concurrent trust changes, reappearing settings, internal/external links, and recovery records. The portable PowerShell wrapper exercises both fresh install and migration.
- A new reproducible native test uses the real Paseo 0.8.0-beta.1 PluginService, ManagedPluginSources, and DaemonConfigStore with local Git fixtures and fake plugin execution/CLI transport. It verified native checkout/settings deletion, release-to-main migration, updating to a later main commit, and a failed build with blocked retry. This test caught the native root pluginPath representation (a dot rather than an empty string), which the implementation and smaller fixture now use. There is no listener, authenticated session, or model; Git transport is file-only.
- Pre-push contracts now include the isolated installer suite automatically. Supplying PASEO_TEST_PLUGIN_SERVICE_MODULE includes the native manager test too.
- ShellCheck, Bash and Node syntax, full win.ps1 parsing, PowerShell channel fixtures, all existing shell contracts, Markdownlint, and whitespace checks pass. Plugin documentation is linted with the setup repository Markdown rules, which allow long lines.
- The separate plugin repository changed only README.md; all 43 plugin tests and TypeScript checks pass. No version tag, release-branch promotion, or package version bump is needed.

Self-review documented non-atomic migration and manual recovery, including the rule never to move/delete a recovery checkout that is an installed directory source. Native Windows migration and successful Windows backup ACLs remain unverified; the negative permission path is simulated. No live daemon or fleet was changed, and the historical release branch and archived rollout task remain untouched.

Publication validation found and contained a native-fixture isolation incident. The first real pre-push hook exported Git repository variables. The fixture inherited them, created synthetic local commit edc6f8a above unpublished 90449f2 in this worktree, and changed the shared Git configuration (fixture identity and core.bare). The hook rejected the push; setup remote main remained 65f652c.

Recovery verified all 82 tracked working files against the pre-test commit blob IDs. The branch was restored with a conditional update-ref and the index with read-tree; working files were not rewritten. Repository non-bare mode and the effective Scott Walters / `me@scowalt.com` identity were restored from the verified prior commit and global identity. The prior Git config layout was not snapshotted, so byte-for-byte metadata restoration is not claimed; identity is now set explicitly locally. No test commit was published.

The new hook-isolation regression reproduces the failure inside a disposable caller repository, not this project. It failed before the correction and now passes for GIT_DIR alone and combined worktree/index/common-directory/object-directory variables, comparing all caller file and metadata hashes. The native fixture strips inherited GIT_* values, supplies isolated config/hooks, asserts the fixture repository path, and uses per-command identity instead of writing identity config. Pre-push now runs this guard whenever the native module is supplied.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Paseo Plain now follows main without release-branch promotion. Existing matching release installations migrate on each machine's next setup run under the same plugin ID.

Changes:

- Updated all six installers, version banners, and documentation. Ubuntu is version 245. Main installations receive normal native updates; directory sources, other repositories/refs, pinned revisions, and disabled choices remain preserved.
- Added the approved one-time native remove/add migration with verified private recovery copies, source-record checks, restored Paseo-owned settings, and untouched live rewrite preferences/cache. The migration does not restart the daemon.
- Added a durable progress journal and conservative failure handling. Failures, timeouts, lost responses, and incomplete attempts stop for manual review rather than retrying destructively. Recovery guidance covers retained private cached data and directory-source fallback.
- Added automatic pre-push installer tests and a reproducible native-manager fixture.

Validation:

- All 30 isolated installer tests passed, including the portable PowerShell migration wrapper and the simulated Windows permission-failure path.
- Actual Paseo 0.8 source/configuration managers passed local-fixture migration, subsequent main-commit update, and failed-build recovery tests. No listener, real plugin execution, authentication, or model was used.
- ShellCheck, Bash/Node syntax, complete PowerShell parsing, PowerShell channel fixtures, shell contracts, Markdownlint, whitespace, and staged secret checks passed.
- Plugin README documentation was published at 77d32ec; all 43 plugin tests and TypeScript checks passed locally.

Limits: No fleet or live daemon was changed. Native Windows migration and successful Windows backup ACLs remain unverified. The historical release branch and tags remain available for recovery; no new release or package version was cut.

Publication check follow-up:

- The first pre-push attempt exposed inherited Git variables redirecting the native test into this worktree. The push was blocked. All working files were verified unchanged; the branch/index and effective repository settings were restored before retrying.
- Added a caller-repository isolation regression and removed inherited Git state from fixture subprocesses. The optional native suite now includes this guard. No synthetic test commit was published.
<!-- SECTION:FINAL_SUMMARY:END -->
