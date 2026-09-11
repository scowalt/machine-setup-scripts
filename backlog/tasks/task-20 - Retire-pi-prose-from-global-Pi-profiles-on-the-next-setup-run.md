---
id: TASK-20
title: Retire pi-prose from global Pi profiles on the next setup run
status: Done
assignee:
  - '@pi'
created_date: '2026-09-11 19:26'
updated_date: '2026-09-11 20:05'
labels: []
dependencies: []
references:
  - >-
    https://github.com/scowalt/dotfiles/blob/main/private_dot_pi/agent/private_settings.json.tmpl
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Setup currently stops seeding pi-prose but preserves installed copies and package declarations. The user now requests mandatory removal on every machine that next runs a setup script, including copies previously retained as user-selected. Remove the package and declarations that cause automatic reinstallation without a remote rollout.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 All six setup scripts remove pi-prose from the default and explicitly configured global Pi agent profiles on the next run, including previously user-selected copies, and repeated runs keep it absent.
- [x] #2 Removal succeeds despite unrelated npm dependency-resolution failures such as the MCP adapter EALLOWREMOTE error, without relaxing npm security policy.
- [x] #3 Cleanup preserves unrelated packages, settings, credentials, custom prose files, and project data; unsafe or malformed state produces a clear failure rather than false success.
- [x] #4 Offline Bash and PowerShell fixtures cover package declarations, installed copies, missing state, repeated runs, preservation, and safety. Affected versions and documentation reflect mandatory retirement.
- [x] #5 The dotfiles template no longer declares pi-prose, so future chezmoi applies cannot restore the global package declaration. Do not apply dotfiles to live machines during development.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Update the setup and dotfiles retirement policy to require pi-prose removal, including previously user-selected global copies. Remove the published-template source declaration in a separate dotfiles worktree without applying live dotfiles.
2. Add isolated failing fixtures for the default and PI_CODING_AGENT_DIR profiles, pinned/object package declarations, installed package files, npm manifests/locks, missing state, preservation, unsafe paths, and repeated runs. Extract only tested functions or embedded cleanup logic.
3. Add cleanup to all six scripts after dotfiles application and before Pi package operations can restore pi-prose. Remove only verified pi-prose state without invoking dependency resolution, which currently fails on the unrelated MCP adapter URLs. Preserve custom prose files, unrelated packages, credentials, project files, and npm policy.
4. Increment affected versions and update existing no-restoration tests and documentation. Run Bash and PowerShell retirement fixtures, model/package preservation tests, relevant full contracts, ShellCheck, Markdownlint, and diff review.
5. Report the separate remaining MCP/npm 12 incompatibility. Do not contact or modify remote machines, run full setup, apply chezmoi, change npm security settings, or make model requests. Publish only when authorized.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Confirmed the earlier TASK-13 policy deliberately preserved user-selected installations. The current request changes that policy to mandatory retirement on future setup runs.
- GitHub main still lists npm:pi-prose at private_dot_pi/agent/private_settings.json.tmpl:10 in scowalt/dotfiles. Removing only the installed package would not prevent dotfiles from requesting it again.
- Existing Pi removal helpers call pi remove, which fails here because npm resolves the unrelated MCP adapter preview dependencies. The new cleanup must not depend on npm resolving the shared tree.
- Tooling is available: ShellCheck, Python, jq, Node, and temporary PowerShell 7.6.6. Setup branch fix/retire-pi-prose starts from origin/main c47b8b0. No implementation changes yet; waiting for plan approval.

User approved the plan. Beginning implementation in isolated setup and dotfiles worktrees; no live machine changes.

- Added the shared offline Node retirement engine to all six setup scripts, with Bash and PowerShell wrappers before Pi installation/package operations. It edits only Pi settings and npm manifest/lock records, then removes the verified package directory or unlinks a package source link.
- The initial retirement fixture failed before implementation. Seventeen engine/wrapper tests now pass, including PowerShell, npm/CLI independence, linked-path safety, malformed metadata, retries, both profiles, and custom-file preservation.
- In /home/scowalt/Code/dotfiles-retire-pi-prose (branch fix/retire-pi-prose), removed the package template entry and create-only prose seed, updated docs, and added a regression. Three dotfiles model/template tests pass. No live apply was run.
- The companion-package fixture now extracts only its tested function instead of sourcing an entire setup script. PowerShell runtime caches are isolated from the target snapshot to avoid false mutation reports.

- Hardened retirement against hardlinked JSON metadata and an active Pi profile nested inside the directory scheduled for removal. Added explicit retry/failure and duplicate-profile tests; 21 retirement tests now pass, including the Windows wrapper.
- All 23 standard Bash contract entry points pass, including the unchanged Paseo Plain installer tests and the shared-Node suite (959 PowerShell assertions). The explicit PowerShell release-channel fixtures also pass. ShellCheck, syntax/version checks, Markdownlint, whitespace checks, and changed-content secret scans pass.
- All 19 dotfiles tests pass with 2 expected native-Windows skips when run on Linux. No live dotfiles were applied.
- Requested a read-only independent review, but the Claude reviewer could not authenticate. Completed self-review instead. Adjusted the new helper location to keep the existing headless Paseo test boundary intact, without weakening that test.
- Broad PowerShell reliability has the known unrelated TASK-19 failure; native migration isolation still needs its explicit module. Neither unrelated implementation changed.

- Final retirement suite: 22 passing tests, including actual Bash wrappers for all five platforms and the extracted PowerShell wrapper. Explicit tests cover valid/empty/malformed custom prose files and cleanup placement after dotfiles work but before Pi installation.
- Self-review confirmed the six embedded programs are identical, only the trusted HOME boundary is resolved, no npm/Pi/lifecycle command runs during retirement, and the package identity is checked before deleting a regular installation. Unrelated JSON values, credentials, custom prose files, npm policy, and shared dependencies are preserved. Temporary test artifacts were removed.
- Final changes remain uncommitted and unpublished in both fix/retire-pi-prose branches. The setup repository is this worktree; the dotfiles worktree is /home/scowalt/Code/dotfiles-retire-pi-prose. Both repositories must be published for future setup and chezmoi runs to keep the package inactive. No live machines, dotfiles, or Pi sessions were modified.

- User authorized publication to remote main in both repositories. Dotfiles PR <https://github.com/scowalt/dotfiles/pull/19> merged first as d85d29b1a8cb27fa2281265ec17f7d7a9d8b2dc2, removing the restoring package declaration and seed. Its 19 tests passed with two native-Windows skips; lint and secret scans passed.
- Rechecked setup ShellCheck and the 22 retirement tests, including the PowerShell wrapper. Publishing the setup branch with normal pre-commit/pre-push hooks enabled. No live setup or dotfiles apply is part of publication.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Retire pi-prose on each machine’s next setup run, including installations previously retained as user-selected.

Setup changes:

- Add identical offline Node cleanup to all six scripts, after dotfiles work and before Pi package operations. Clean both the default global profile and PI_CODING_AGENT_DIR.
- Remove prose package declarations, direct npm dependencies/overrides, matching lock records, and the verified installed package directory. Unlink package-source links without deleting their targets.
- Avoid npm dependency resolution and lifecycle scripts, so the unrelated npm 12 MCP dependency failure cannot block prose removal. Preserve npm security policy, custom prose files, unrelated packages/settings/credentials, and project data.
- Preflight both profiles, reject unsafe or malformed state, and report failed writes or deletions. Keep retries idempotent and avoid reporting false success.
- Bump macOS to 226, Ubuntu to 248, WSL to 190, Pi to 207, Bazzite to 107, and Windows to 142. Update policies and isolated fixtures.

Dotfiles counterpart:

- Merged first via <https://github.com/scowalt/dotfiles/pull/19> (d85d29b), removing npm:pi-prose from the template and deleting only the source create_config.json seed. Existing deployed custom files remain untouched.

Verification:

- Red/green retirement and dotfiles regressions. All 22 retirement tests pass, including Bash and PowerShell wrappers.
- All 23 standard setup contract entry points pass, including 30 Paseo Plain tests and shared-Node PowerShell coverage (959 assertions). Explicit PowerShell release-channel tests pass.
- All 19 dotfiles tests pass with 2 expected native-Windows skips on Linux. ShellCheck, Markdownlint, syntax/version checks, whitespace checks, and changed-content secret scans pass.
- Native migration isolation still needs its supplied module. The unrelated broad PowerShell reliability failure remains tracked in TASK-19. Independent Claude review was unavailable because its authentication failed; self-review completed.

Scope: repository publication only, without a live setup run, remote rollout, chezmoi apply, Pi restart, or npm security change. Existing Pi sessions must restart to unload an already-loaded extension. The separate MCP adapter/npm 12 issue remains unchanged.
<!-- SECTION:FINAL_SUMMARY:END -->
