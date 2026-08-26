---
id: TASK-5
title: Stop markdownlint pre-push failures on vendored CLAUDE.md
status: In Progress
assignee:
  - '@pi-agent'
created_date: '2026-08-26 03:27'
updated_date: '2026-08-26 03:27'
labels: []
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Prevent markdownlint pre-push failures caused by vendored Backlog.md guidance inside CLAUDE.md without reformatting that file by excluding it from markdownlint checks.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Create a root .markdownlintignore that excludes CLAUDE.md with an explanatory comment.
- [ ] #2 From repo root,  must pass without extra flags.
- [ ] #3 ╭─────────────────────────────────────╮
│ 🥊 lefthook v1.13.6  hook: pre-push │
╰─────────────────────────────────────╯
│  contract-tests (skip) no matching push files
│  markdownlint-all (skip) no matching push files
│  shellcheck-all (skip) no matching push files

  ────────────────────────────────────
summary: (done in 0.01 seconds)
branch 'chore-markdownlint-ignore-vendored-claude-md' set up to track 'origin/chore-markdownlint-ignore-vendored-claude-md'. must pass with lefthook pre-push hooks enabled and no --no-verify.
- [ ] #4 Open a PR with the fix.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Add a root-level .markdownlintignore entry excluding CLAUDE.md with rationale.
2. Verify markdownlint and shellcheck/tests pass from root with default hook command usage.
3. Commit and push the change, then open PR and record evidence on the task.
<!-- SECTION:PLAN:END -->
