---
id: TASK-28
title: Expose safe Pi OpenCode Go setup failure diagnostics
status: Done
assignee:
  - '@pi'
created_date: '2026-09-13 23:30'
updated_date: '2026-09-14 13:06'
labels:
  - bug
  - setup
  - diagnostics
dependencies: []
references:
  - ubuntu.sh
  - win.ps1
  - tests/test_pi_opencode_go_setup.py
  - 'https://logs.scowalt.com/logs/devinabox/2026-09-13-23-22-14-148.log'
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The devinabox Ubuntu v251 run 2026-09-13-192123.log failed Go setup but exposed only a generic warning. Make future setup logs identify the failed validation or operation without disclosing credentials or weakening safety checks. This task covers diagnostics, not an assumed repair of the unproven machine-specific cause.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 All six setup scripts report controlled operation or metadata labels and specific allowlisted validation reasons or bounded native error/exit codes for Go setup failures, with a safe fallback for unexpected helper failures.
- [x] #2 Diagnostics never print keys, credential contents, arbitrary exception messages, raw child output, or secret-bearing custom paths; existing credential, permissions, locking, and downstream failure gates remain intact.
- [x] #3 Extracted Bash and available PowerShell wrapper fixtures prove the specific reason reaches setup output, unexpected failures stay redacted, and failure status and credential preservation remain correct without live setup or model requests.
- [x] #4 Embedded Go helpers remain identical across all six scripts; modified setup versions, relevant documentation, and affected contract and lint checks are updated.
- [x] #5 Paseo Plain source-mismatch warnings distinguish directory/non-Git sources, other repositories, and custom or pinned refs with controlled labels and useful next steps, without printing source values or changing existing preservation behavior.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Add regression fixtures at extracted Go helper and Bash/PowerShell wrapper boundaries for permission, JSON, linked-path, catalog, lock/write, and unexpected helper failures. Assert safe detail, secret suppression, nonzero status, and preservation. Add Plain source-mismatch message fixtures without changing source/disabled preservation.
2. Carry controlled Go operation/metadata labels and allowlisted reason/native-error codes through a bounded result protocol, never raw stderr. Keep all six embedded helpers identical and preserve locking/validation/downstream gates. Give Plain directory/non-Git, repository, and ref mismatches controlled explanations and manual next steps without raw values.
3. Update all six setup versions, affected banner expectations, and documentation. Run Go/Muse/wiring, Plain/fixture-isolation, and affected package/runtime/headless/model/Telegram contracts, ShellCheck, Markdown/whitespace checks, with available isolated PowerShell wrappers.
4. Self-review and record verified outcomes. No live setup, daemon changes, model calls, actual-account permission repairs, or fleet rollout.
Approval: user approved this plan with Plain preservation retained.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Reproduced diagnostic loss with the actual extracted Ubuntu wrapper in a disposable fixture HOME: a 0644 fixture environment file yields exit 1 but only the generic warning, and an assertion for unsafe-file-permissions fails. This proves the logging gap, not the cause of the original live run. No real credentials, live setup, or repository code changed.
Reviewed completed TASK-16/TASK-25/TASK-27. Bash, Node, ShellCheck, Backlog, and the isolated /tmp/pi-shared-runtime-pwsh.2SlAPL/pwsh runtime are available. Waiting for approval.

User approved the plan with Plain preservation retained. Implementation now includes clearer Plain source-mismatch warnings, not takeover. Beginning regression fixtures and diagnostics changes; no live setup or daemon changes.

Added failing extracted-wrapper and Plain source-warning regressions, then implemented controlled Go operation/reason reporting in all six scripts. Unknown/native helper output remains suppressed unless it matches the exact allowed protocol. All 19 Go tests pass with portable PowerShell wrappers and native Pi lock/catalog probes; all 35 Plain tests pass. ShellCheck and whitespace checks pass. Wider contracts and documentation review are next.

Final verification passed: 22 Go tests with all six wrappers, portable PowerShell native-error-preference preservation, native Pi lock/catalog probes, safe fallback output, and operation preservation across cleanup/release. The original temporary permission fixture now reports environment-file: unsafe-file-permissions while returning failure.
All 35 Plain tests and the native manager/Git-hook isolation fixture pass; custom sources, disabled choices, native settings, recovery data, and cache remain untouched. Go/Muse/wiring, package maintenance, shared runtime, prose retirement, AI-agent, model-default, z.ai, headless, release-channel/system-home alias, Simple English, and Telegram contracts pass. Explicit PowerShell model/channel/Telegram suites also pass; package-maintenance optional registry/dotfiles probes were not enabled.
ShellCheck, Markdown lint, whitespace checks, and self-review passed. All six Go helpers and all six Plain installers remain identical. No live setup, actual-account cleanup, daemon operations, model requests, or fleet rollout occurred. Native Windows/macOS/ARM execution was not smoke-tested. Changes remain local and uncommitted.

User requested publication and merge into remote main. Fetched origin/main and confirmed it still matches the implementation base (25bfd72), with no incoming changes or existing PR for this branch. Preparing an attributed commit and normal hook-checked PR delivery; no live setup or daemon changes.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Expose safe Go setup failure details and clarify preserved Paseo Plain sources on future runs.

Changes:

- All six Go helpers identify a controlled operation and validation/native error code. Bash and PowerShell accept only the exact allowed failure protocol and keep arbitrary output, credentials, and custom paths out of logs. Unknown errors report an explicit fallback rather than an invented cause.
- Preserve failure status, existing validation and credential-lock behavior, and later Pi/Muse/daemon safety gates. Keep the original failing operation across cleanup.
- Plain warnings distinguish directory/non-Git sources, other repositories, and custom/pinned refs without taking over installations or changing disabled choices.
- Increment all six setup versions and update documentation and banner fixtures.

Validation:

- 22 Go tests and 35 Plain tests pass, including portable PowerShell wrappers, redaction cases, metadata preservation, native Pi lock/catalog probes, and native Paseo migration/Git-hook isolation.
- Affected Go/Muse/wiring, package/runtime/prose, AI-agent/model, headless/channel/system-home, skills, and Telegram contracts pass. Explicit PowerShell model/channel/Telegram suites pass.
- ShellCheck, Markdown lint, whitespace checks, and redacted diff secret scan pass.

Limits: Diagnostics do not assert the original machine-specific cause. No live setup, daemon change, model request, or rollout occurred. Native Windows/macOS/ARM smoke tests and optional package registry/dotfiles probes were not run. Changes are local and not published.
<!-- SECTION:FINAL_SUMMARY:END -->
