---
id: TASK-10
title: Replace Synthetic Kimi K3 with GPT-6 Astra defaults
status: Done
assignee:
  - '@pi'
created_date: '2026-09-06 23:08'
updated_date: '2026-09-06 23:09'
labels: []
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Remove Synthetic Kimi K3 from machine setup scripts and dotfiles. Use GPT-6 Astra with xhigh thinking by default on all machines, including work machines. Retain z.ai as an optional provider and preserve unrelated configuration and local credentials.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 All six setup scripts stop seeding Synthetic and remove its managed provider configuration on rerun without changing unrelated providers or existing ~/.env.local files.
- [x] #2 Related documentation and script versions are updated, and regression tests cover removal, idempotency, preservation, and work-machine defaults.
- [x] #3 Pi and opencode dotfile templates no longer configure Synthetic or Kimi K3; z.ai remains an optional provider when configured.
- [x] #4 All six setup scripts and the Pi/opencode dotfiles default to GPT-6 Astra with xhigh on personal and work machines, regardless of z.ai key availability.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Verify installed GPT-6 Astra model IDs and supported Pi/opencode configuration fields.
2. Replace Synthetic seeding with safe, repeatable provider removal in all six scripts; force GPT-6 Astra xhigh defaults regardless of machine type while retaining optional z.ai seeding and preserving unrelated settings and local credentials.
3. Update Pi/opencode templates in /home/scowalt/Code/dotfiles, documentation, script versions, and regression tests.
4. Run lint, setup regression tests, and isolated dotfile template rendering tests. Review both diffs without running full setup, applying live dotfiles, editing credentials, or contacting other machines.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
User approved implementation and changed the replacement policy: GPT-6 Astra xhigh is the default on all machines, including work machines.

- Verified Pi uses openai-codex/gpt-6-astra with xhigh support in the installed model catalog; opencode uses openai/gpt-6-astra and model options.reasoningEffort.
- Replaced Synthetic seeding with provider-only cleanup on all six platforms, removed key placeholders, removed the work-machine default branch, and set the per-model Astra override to xhigh.
- Updated Pi/opencode templates, docs, script versions, and regression coverage. Initial Bash behavior tests, template rendering tests, z.ai contract, Telegram environment contract, and ShellCheck passed. PowerShell runtime verification is in progress using a temporary official portable runtime.

- Final verification passed: all 19 Bash contract scripts; the new Astra contract under official PowerShell 7.6.5 (portable download verified against the release SHA-256); all 16 dotfiles unit tests; ShellCheck; Markdown lint; and git diff --check in both repositories.
- Confirmed opencode loads the rendered openai/gpt-6-astra model with reasoningEffort=xhigh using an isolated home and fake credentials, without an inference request.
- Updated the existing skill contract version-banner expectations after the required setup version bumps. Existing Telegram tests need system jq first in PATH on this host because its mise jq shim cannot resolve inside their fake homes; all tests pass with that test-only PATH.
- Self-reviewed both diffs and confirmed the five Bash default/cleanup implementations are identical. Removed temporary PowerShell files and generated Python caches. No setup execution, live dotfile apply, credential changes, machine rollout, commits, or pushes.

User requested delivery to remote main in both repositories. Fetched origin/main for machine-setup-scripts and dotfiles; both local bases match their remote main heads. Preparing scoped commits and normal fast-forward pushes, with no force push or live dotfile apply.

During publication, remote main advanced to 7207293 and independently allocated task 9. Recreated this task with a new CLI-assigned ID, preserving upstream task 9. Rebased the implementation and incremented all six versions above the new remote versions. Dotfiles commit 95a6f84 is already on remote main.

Rebase verification passed: ShellCheck across all setup scripts, the upstream Claude Code installation contract, the Astra behavior contract, and version-banner/skill tests. Both functional changes remain intact; the full pre-push suite will run again during publication.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Replaced Synthetic Kimi K3 with GPT-6 Astra xhigh defaults on personal and work-machine configurations.

Changes:

- All six setup scripts use Pi openai-codex/gpt-6-astra, including its per-model xhigh override, and safely remove the old Synthetic provider on rerun.
- Removed Synthetic API-key placeholders and seeding code. Other providers, local environment files, and authentication remain unchanged. z.ai stays optional.
- Updated Pi and opencode templates in /home/scowalt/Code/dotfiles, script versions, docs, and version-banner expectations.
- Added isolated Bash, PowerShell, and template tests covering fresh installs, upgrades, machine/key combinations, repeat runs, symlinks, malformed files, and preservation.

Verification:

- All 19 setup shell contracts, PowerShell 7.6.5 Astra tests, and all 16 dotfiles tests pass.
- ShellCheck, Markdown lint, and diff whitespace checks pass.
- opencode loads the rendered Astra xhigh model without inference.

Rollout: Repository changes only, not applied to live machines. New Pi installations need their normal OpenAI Codex login.

Delivery target: remote main in both repositories. This publishes the configuration for future setup/chezmoi runs but does not apply it to live machines.
<!-- SECTION:FINAL_SUMMARY:END -->
