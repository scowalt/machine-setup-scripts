---
id: TASK-26
title: Keep the Pi MCP adapter installed and enabled across setup and dotfiles
status: Done
assignee:
  - '@codex'
created_date: '2026-09-13 19:41'
updated_date: '2026-09-13 20:10'
labels:
  - pi
  - setup
  - dotfiles
dependencies: []
references:
  - ubuntu.sh
  - win.ps1
  - tests/test_pi_package_maintenance.py
  - >-
    /home/scowalt/.local/share/chezmoi/private_dot_pi/agent/private_settings.json.tmpl
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Ensure future setup runs and dotfiles application agree on the supported Pi MCP adapter package and its enabled resource state. The dotfiles settings template currently omits the adapter, and an isolated setup fixture reports success with all adapter extensions filtered out. The local installed version is also newer than the repo pin; live profiles remain outside this source-change task.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 All six setup scripts and the dotfiles settings template consistently request pi-mcp-adapter 2.32.1, enabled by default on personal and work machines, while honoring BAN_PI_MCP_ADAPTER=1.
- [x] #2 Setup verifies extension availability and enablement, not just package registration and version; preserved disabling source filters produce a clear non-success result instead of an enabled-success claim. Unrelated filters, packages, credentials, project overrides, and npm security policy remain unchanged.
- [x] #3 Isolated regression tests cover dotfiles rendering and subsequent setup, repeated runs, explicit opt-out, disabled or missing adapter resources, and Bash/PowerShell behavior; an isolated Pi resource-loading check verifies the pinned adapter loads without contacting real MCP servers or model providers.
- [x] #4 Script versions and relevant documentation are updated; applicable setup contracts, dotfiles tests, lint, and self-review pass without live setup, dotfiles application, fleet changes, or daemon restarts.
- [x] #5 Verified changes are committed with AI attribution and delivered to remote main in both the setup and dotfiles repositories, preserving concurrent upstream changes.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Confirm Pi package filtering/loading behavior and the 2.32.1 entry point using current Pi documentation and isolated package resources. Use Bash, Node, Python, chezmoi, ShellCheck, and the available isolated PowerShell binary at /tmp/pi-shared-runtime-pwsh.2SlAPL/pwsh. Do not run full setup or apply live dotfiles.
2. Add regression tests first for the two reproduced gaps: a rendered dotfiles configuration omitting the adapter and setup returning success for extensions: []. Add clean, opt-out, missing-resource, repeated-run, and custom-profile cases.
3. Update the dotfiles Pi settings template to retain the pinned, enabled adapter by default and honor the existing opt-out. Keep identical embedded setup policy across all six scripts; validate the installed resource and effective package enablement while preserving source filters and reporting explicit disablement rather than silently overriding it.
4. Verify the pinned adapter through an isolated Pi resource-loading check with no real MCP servers, credentials, or model requests. Run Bash/PowerShell package-maintenance, prose-retirement, shared-runtime, relevant dotfiles tests, and lint; update versions/docs and self-review both repositories.
Approval gate: share this plan and wait for user approval before code changes. Source changes only; do not alter live profiles, run fleet setup, or restart agents.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Read-only audit: the dotfiles source is /home/scowalt/.local/share/chezmoi (clean main); setup worktree was clean. Rendering private_settings.json.tmpl reports no adapter package. An extracted ubuntu.sh setup helper with an isolated fake Pi store returns exit 0 and installed/updated success while preserving extensions: []. Both checks fail the intended enabled-state assertion. The local live profile currently declares an unpinned adapter and contains 2.33.0; inspected only, no live mutations.

User approved implementation and requested delivery to remote main in both repositories. Preserve explicit opt-outs/source filters; verify actual pinned adapter loading with isolated fixtures before publishing.

Added failing regressions before the fix, then aligned all six setup scripts and the isolated dotfiles worktree. Setup validates the pinned package manifest and nonempty regular entry point, preserves disabled or ambiguous filters, and reports non-success with pi config recovery instructions. Explicit +index.ts selections are supported without guessing arbitrary glob semantics.
Dotfiles now retain the pinned enabled registration by default and honor environment/file opt-outs. Personal/work rendering and repeated render/setup pass on Bash and PowerShell fixtures. Real npm 12 restricted-store recovery plus Pi SDK loading passed with network blocked and no real MCP or model calls. Dotfiles changes are in /home/scowalt/.paseo/worktrees/02r3t7st/ignorant-mantis-dotfiles, not the live chezmoi source checkout.

Final validation: all 26 shell contract suites pass, including PowerShell wrappers, the real restricted npm/Pi registry probe, and cross-repository repeated render/setup. Updated the existing version-banner assertion after the required script version bumps. Dotfiles discovery ran 20 tests: 18 pass and 2 native-Windows-only fixtures skip on Linux. ShellCheck, Node syntax, Markdownlint, and git diff checks pass. Self-review confirms no credentials, live extension execution, npm-policy changes, or project overrides were introduced. Publishing to remote main remains pending.

Published and verified both remote main branches: machine-setup-scripts 3b45e95 and dotfiles 4b9f1cc. Setup pre-push hooks passed all contract suites and lint again. No force pushes, live provisioning, chezmoi application, or agent restarts.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Kept pi-mcp-adapter installed and enabled by default across machine setup and dotfiles.

Changes:

- Dotfiles retain npm:pi-mcp-adapter@2.32.1 on personal and work machines and honor explicit opt-outs.
- All six setup scripts verify the package manifest, regular nonempty index.ts, and enabled resource selection. Disabled, duplicate, and unverified filters return failure and stay unchanged.
- Added isolated Bash/PowerShell and cross-repository regressions. The real pinned package registers mcp, mcpScript, and /mcp with network calls blocked and no model requests.
- Updated versions, documentation, and the existing version-banner contract.

Validation: all 26 setup contract suites, the real restricted npm/Pi probe, repeated dotfiles/setup fixtures, 18 passing dotfiles tests, ShellCheck, Markdownlint, Node syntax, staged secret scans, and self-review. Two native Windows dotfiles tests skip on Linux.

Published to remote main: setup 3b45e95, dotfiles 4b9f1cc. Future setup runs apply the changes. Existing sessions need restart or /reload afterward; server connectivity and authentication remain separate.
<!-- SECTION:FINAL_SUMMARY:END -->
