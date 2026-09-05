---
id: TASK-8
title: Document direct Telegram alerts for coding agents
status: Done
assignee:
  - '@pi'
created_date: '2026-09-05 22:20'
updated_date: '2026-09-05 23:15'
labels: []
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Implement the approved cross-repository plan: direct Telegram requests from agents, local credentials, and setup placeholders without a notification helper or daemon.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 All six setup scripts include commented Telegram alert credentials in new environment files and preserve existing files.
- [x] #2 Dotfiles provide one shared direct-request reference and notification policy for Claude Code, Codex, and Pi.
- [x] #3 Offline tests cover configuration loading, request encoding, API errors, and credential-safe output; document any live-test blocker.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
The user approved this plan before implementation.

1. Add a shared direct Telegram request guide and short global policies in dotfiles.
2. Add commented credentials to all six setup environment templates and increment script versions.
3. Test examples offline with fake credentials and setup functions in temporary homes.
4. Review diffs, scan for secrets, and report activation and live-test requirements.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implemented direct-request docs and matching global policies in /home/scowalt/Code/dotfiles. Added only commented credential placeholders and version increments to the six setup scripts. Existing ~/.env.local files remain untouched.
Verification: 14 offline tests execute the documented Bash blocks with a fake curl; five Bash setup functions pass creation, mode-600, rerun, and existing-file preservation tests; Windows template contract passes. ShellCheck, Markdownlint, git diff --check, and an isolated chezmoi apply-twice test pass. Gitleaks finds no secrets in changed content or new files; a whole-file scan flags unchanged empty initializers in bazzite.sh (also present in HEAD).
The native PowerShell test is included but could not run because pwsh is unavailable. Both alert credentials are absent on this machine, so no live Telegram request was made. Scott must configure the dedicated bot and verify desktop/iOS deletion. No real dotfiles apply, setup run, commit, or push was performed.

Scott approved publishing both repositories to remote main. Release preparation includes rebasing dotfiles onto current remote main and running repository commit/push hooks.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Added direct Telegram alert documentation, global agent guidance, and setup credential placeholders without a helper, MCP integration, or daemon.

Dotfiles: shared request guide, matching Claude Code/Codex/Pi policies, local-secret and test exclusions, README activation steps, and 14 offline example tests.
Machine setup: optional placeholders on all six platforms, version increments, documentation, and isolated environment-file contract tests.

Verified: offline examples, Bash setup preservation, Windows template contract, isolated chezmoi deployment twice, ShellCheck, Markdownlint, clean diffs, and secret scanning of changes.
Pending operator verification: native PowerShell execution and one live desktop/iOS alert/deletion test after local credential setup. Machine activation remains a separate step.
<!-- SECTION:FINAL_SUMMARY:END -->
