---
id: TASK-29
title: Keep Claude Bridge registered in Pi after dotfiles updates
status: Done
assignee:
  - '@pi'
created_date: '2026-09-14 19:52'
updated_date: '2026-09-14 22:17'
labels: []
dependencies: []
references:
  - README.md
  - tests/test_pi_package_maintenance.py
  - >-
    https://github.com/scowalt/dotfiles/commit/f609d6b874ad9edc03ba3cc523c604464222c94c
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Claude Bridge can remain installed but unavailable as provider claude-bridge because the Chezmoi Pi settings template omits npm:pi-claude-bridge. All six setup scripts already use pi install for this package. Keep the dotfiles desired package list aligned with setup so later applies do not remove registration.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The dotfiles Pi settings template includes npm:pi-claude-bridge with extensions enabled on personal and work machines across Linux, macOS, and Windows, including when the MCP adapter is opted out.
- [x] #2 Offline regression coverage proves that repeated dotfiles rendering after setup registration retains Claude Bridge; tests use temporary homes and do not load live extensions or make model requests.
- [x] #3 Existing Pi provider/model/thinking defaults, adapter pin and opt-out behavior, and other managed packages remain unchanged; relevant dotfiles and setup contract tests pass.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Work in an isolated dotfiles Git worktree; add a failing rendered-settings regression for Claude Bridge across platforms, personal/work settings, and MCP-adapter opt-out. Keep tests offline with temporary homes.
2. Add npm:pi-claude-bridge to the managed Pi package template and document why the registration must survive Chezmoi applies. Preserve existing defaults and other packages.
3. Add or extend offline setup/dotfiles regression coverage for install followed by repeated template rendering. Change setup helpers only if this reveals a separate registration defect; bump versions and run ShellCheck if any setup script changes.
4. Run the relevant dotfiles and machine-setup package/AI-agent/model-default contracts. Use an available isolated PowerShell binary for Windows fixtures, or report unavailable coverage. Do not apply live dotfiles, run live setup, invoke live extensions, or make model requests.
5. Review changes in both repositories and record test results and final summary.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Diagnosis: user already verified explicit extension loading and authentication with BRIDGE_OK. All six setup helpers call pi install npm:pi-claude-bridge; the dotfiles template omits it. An isolated render using the existing ModelTemplateTests.render helper produced bridge in rendered packages=False for linux, darwin, and windows even with a preexisting fixture registration and package directory. No live settings or authentication were changed.
Awaiting user approval of the implementation plan before code changes.

User approved the plan. Created an isolated dotfiles worktree for fix/pi-claude-bridge-registration; live Chezmoi source and destination stay unchanged. Located PowerShell 7 for extracted Windows wrapper fixtures.

Added regression tests before the fix. Dotfiles rendering failed all 12 platform/work/adapter-opt-out cases; the cross-repository extracted setup test failed all 24 cases, including PowerShell. Both failures were the missing plain npm:pi-claude-bridge source after rendering.
Added the single package entry in the isolated dotfiles template, expanded repeated-rendering coverage, and documented registration/reload behavior. Setup installers remain unchanged. The setup Pi mock now reflects native global registration for every package install.

Green: all five dotfiles model/template tests passed; the repeated setup/render regression passed all six wrappers with PowerShell 7.6.6. Full package-maintenance suite passed (22 tests, only the optional live registry probe skipped). AI-agent contract and model-default contracts passed, including extracted PowerShell model-default fixtures. No setup script changes or live package/model operations were needed.
Markdown lint initially lacked a cached executable; installing the standard lint tool through the existing bunx hook command, without changing npm policy. Reviewing both repository diffs before completion.

Final review: both diffs are limited to the package-list entry, tests, and documentation. Markdown lint passed in both repositories after fetching the standard lint tool. git diff --check passed in both worktrees. The original isolated reproduction now reports bridge in rendered packages=True for Linux, macOS, and Windows. The live Chezmoi source remains clean; no live settings were applied.
Implementation is uncommitted in two worktrees: machine-setup tests/docs in tame-horse, and dotfiles template/tests/docs in sibling tame-horse-dotfiles on fix/pi-claude-bridge-registration. PowerShell coverage is Linux-hosted extracted wrappers, not native Windows provisioning. The optional live npm registry/adapter-load probe was intentionally skipped.

User requested delivery to remote main for dotfiles. Re-ran dotfiles tests, Markdown lint, and the cross-repository repeated-render/setup regression including PowerShell wrappers. Committed the three dotfiles files as f609d6b874ad9edc03ba3cc523c604464222c94c and fast-forward pushed HEAD to origin/main without force. A fresh fetch, ancestry check, and git ls-remote verified remote main at that exact commit. Dotfiles worktree is clean. Machine-setup tests/docs remain uncommitted and were not pushed.

User requested delivery of the remaining machine-setup changes to remote main. Fetched main and confirmed the worktree base matches it. Re-ran the complete package-maintenance suite with the delivered dotfiles template and PowerShell wrappers: 22 tests completed, one optional live registry probe skipped. Preparing a normal fast-forward push of README.md, the regression fixtures, and this completed task record. Setup installers remain unchanged.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Keep Claude Bridge enabled through later dotfiles updates. The setup scripts already register npm:pi-claude-bridge, but the Chezmoi template omitted it and could remove that registration while leaving the package installed.

Changes:

- Dotfiles adds the plain npm:pi-claude-bridge source for personal and work machines. The fix is verified on remote main in [dotfiles commit f609d6b](https://github.com/scowalt/dotfiles/commit/f609d6b874ad9edc03ba3cc523c604464222c94c).
- Machine setup adds cross-repository regression coverage for all six extracted setup wrappers and repeated template rendering. The fixture asserts that dotfiles retain registration before any later repair install.
- The mock Pi installer now records global package registration. Both repositories document the cause and repair command. Setup installers need no code changes.

Validation:

- Dotfiles model/template tests passed, including repeated rendering, work-machine cases, and MCP adapter opt-outs.
- Package-maintenance suite passed with PWSH_BIN and PI_ADAPTER_DOTFILES_SOURCE: 22 tests completed, one optional live registry probe skipped.
- AI-agent and model-default contracts passed, including PowerShell model-default fixtures.
- Markdown lint and git diff --check passed.
- No live setup, dotfiles apply, extension loads, model requests, or credential changes were made. PowerShell fixtures run on Linux and do not prove native Windows provisioning.

This machine-setup commit contains the regression tests, documentation, and completed task record for the delivered dotfiles fix.
<!-- SECTION:FINAL_SUMMARY:END -->
