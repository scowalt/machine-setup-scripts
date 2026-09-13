---
id: TASK-22
title: Recover Pi package maintenance under restricted npm policy
status: Done
assignee:
  - '@codex'
created_date: '2026-09-12 16:58'
updated_date: '2026-09-12 18:13'
labels:
  - bug
  - setup
  - pi
dependencies: []
references:
  - ubuntu.sh
  - bazzite.sh
  - win.ps1
  - 'https://logs.scowalt.com/logs/bazzite/2026-09-11-22-13-19-559.log'
  - 'https://registry.npmjs.org/pi-mcp-adapter'
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The September 12 audit found EALLOWREMOTE on four hosts after unpinned pi-mcp-adapter 2.33.0 introduced pkg.pr.new dependencies. Bazzite repeatedly fails both managed installs and legacy removals. Future setup runs must recover without weakening npm policy or changing unrelated user data.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 All six supported setup scripts select a verified compatible Pi MCP adapter dependency graph under the existing remote-package restrictions.
- [x] #2 Existing affected managed package stores converge safely and repeated runs remain idempotent; unrelated packages, credentials, project data, custom profiles, and security settings are preserved.
- [x] #3 Regression fixtures cover clean and affected stores, failed recovery, explicit adapter opt-out, and Bash/PowerShell behavior without live machine installs.
- [x] #4 Modified script versions, documentation, and applicable checks are updated.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Work directly from synchronized main bcc7383; review Pi package documentation, current installer helpers, and restricted-store fixtures. Reconfirm that the 2.32.1 candidate and its dependency graph work without relaxing npm policy.
2. Add isolated failing tests for clean and affected stores before implementing a narrowly scoped, validated adapter selection and managed-store recovery. Preserve opt-outs, custom profiles, unrelated data, and malformed/symlink safeguards.
3. Apply consistent behavior to all six supported scripts; do not touch live machine or agent profiles.
4. Run targeted package, retirement, runtime, and Bash/PowerShell fixtures; update versions and docs, self-review, and record results. Obtain an isolated PowerShell runtime if needed: pwsh is not currently on PATH.
Approval gate: share this plan with the user and wait before code changes. No delegation.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
User approved the implementation plan. Proceeding directly with isolated regression fixtures; no delegation or live fleet changes.

Real npm 12.0.2 + installed Pi CLI probe passed in an isolated HOME: clean 2.33.0 fails with EALLOWREMOTE; extracted setup selects 2.32.1; affected manifest plus visible/hidden locks recover; repeated runs and opt-out preserve an unrelated registry package. Remote URLs stayed prohibited and lifecycle scripts stayed disabled. Offline Bash/PowerShell fixtures also cover filters, custom profiles, malformed files, links/hardlinks, validation failures, and absent legacy packages.

Final validation: all 26 shell contract suites passed with isolated PowerShell, real npm/Pi registry probe, and native Paseo source-manager fixtures enabled. ShellCheck, Markdownlint, git diff checks, and secret scans of the patch/tests passed. Full-directory Gitleaks flags an unchanged pair of empty Bazzite shell variables at lines 26-27; reproduced on HEAD, no credential present. Broad PowerShell reliability still fails at the existing PR Lens assertion, independently reproduced on unmodified bcc7383 (TASK-19). Self-review completed; no live provisioning or rollout.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Pinned pi-mcp-adapter to verified registry-compatible 2.32.1 across all six setup scripts without weakening npm policy.

- Repair only active-profile adapter declarations before shared-store operations; preserve source filters, unrelated packages, custom profiles, and security configuration.
- Support opt-out and reject malformed or linked metadata. npm owns lockfile reconciliation.
- Add offline cross-platform fixtures and an opt-in real npm 12/Pi probe covering EALLOWREMOTE, recovery, repeated runs, and removal.
- Update versions and documentation. All 26 contract suites and lint pass. Existing broad PowerShell PR Lens failure remains TASK-19.

Future setup runs only. Changes remain local; native Windows provisioning was not performed.
<!-- SECTION:FINAL_SUMMARY:END -->
