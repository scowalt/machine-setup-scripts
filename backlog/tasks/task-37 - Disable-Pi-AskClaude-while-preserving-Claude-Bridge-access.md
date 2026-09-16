---
id: TASK-37
title: Disable Pi AskClaude while preserving Claude Bridge access
status: Done
assignee:
  - '@pi'
created_date: '2026-09-16 17:18'
updated_date: '2026-09-16 18:03'
labels: []
dependencies: []
references:
  - mac.sh
  - ubuntu.sh
  - wsl.sh
  - pi.sh
  - bazzite.sh
  - win.ps1
  - tests/test_pi_package_maintenance.py
  - README.md
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Disable the AskClaude delegation tool on future machine setup runs without uninstalling pi-claude-bridge or removing Claude/Fable model access. Apply the policy consistently on personal and work machines while preserving existing provider configuration and credentials. This is a managed global setting, not a ban on project-local overrides.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 All six setup scripts idempotently set askClaude.enabled=false in the default global Pi profile and the explicitly selected PI_CODING_AGENT_DIR profile; an existing true value is corrected on subsequent runs.
- [x] #2 Claude Bridge remains installed and registered; provider options, other bridge settings, Pi defaults, credentials, and unrelated packages remain unchanged.
- [x] #3 Configuration writes validate paths and JSON, preserve unrelated fields, reject unsafe links or malformed metadata without overwriting them, and report setup failure while allowing unrelated work to continue.
- [x] #4 Dotfiles preserve the bridge registration and maintain the disabled AskClaude global policy without discarding existing provider settings; repeated dotfiles/setup fixture runs retain the policy.
- [x] #5 Offline fixtures cover all six wrappers, idempotency, custom profiles, preservation, and unsafe/malformed input; affected package/model/agent contracts and lint pass, script versions are incremented, and documentation explains next-run rollout, reload requirements, and project overrides. No live setup, extension execution, model requests, or fleet changes occur.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Add offline failing fixtures for a shared, safe AskClaude configuration merge in all six setup scripts. Cover existing true, missing configuration, repeated runs, default/selected profiles, provider-field preservation, malformed JSON, and linked paths using temporary homes only.
2. Add identical embedded configuration logic and platform wrappers, ordered after dotfiles and Pi profile permission preparation and before bridge package operations. Set only askClaude.enabled=false, retain the bridge installer/registration, aggregate failures, and bump all six script versions.
3. Work in an isolated dotfiles worktree to manage the same disabled global setting through a preserving merge rather than replacing existing provider configuration. Keep npm:pi-claude-bridge registered and test repeated dotfiles/setup runs without applying live dotfiles.
4. Run focused AskClaude fixtures, Pi package-maintenance, AI-agent, model-default, and affected profile/runtime contracts, including extracted Windows wrappers using PWSH_BIN when available. Run ShellCheck, Markdown lint, and diff checks. Do not load live extensions, run setup, make model requests, change credentials, or update remote machines.
5. Document the next-setup-run rollout and reload/restart requirement. Explicitly document that project-local claude-bridge.json can override the global setting and is not modified. Review both repository diffs and record verification and any blocked native Windows coverage.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Confirmed AskClaude is bundled in pi-claude-bridge and can be disabled independently through askClaude.enabled=false. Upstream configuration merges project settings over global settings. All six scripts install the bridge; the current dotfiles template retains its registration but does not manage claude-bridge.json. Node, Python, ShellCheck, and Chezmoi are available; a temporary PowerShell binary candidate exists at /tmp/pi-shared-runtime-pwsh.2SlAPL/pwsh. Awaiting implementation-plan approval; no code or live settings changed.

User approved the plan. Beginning implementation in machine-setup and an isolated sibling dotfiles worktree (fix/disable-pi-askclaude); no live dotfiles will be applied.

Implemented identical embedded AskClaude-only configuration logic in all six scripts, with fail-closed main-loop gates after profile permission preparation and before package operations. Preserved bridge installation/registration and provider options; incremented all six setup versions. Added preserving dotfiles template and isolated apply/render fixtures in the sibling worktree.
Focused red/green fixtures cover default and custom profiles, all six wrappers, malformed/linked/hardlinked/FIFO/oversized inputs, idempotency, inherited Node controls, and repeated dotfiles/setup runs on personal/work machines. Self-review found that the bridge does not strip UTF-8 BOMs, so output is normalized to BOM-free JSON even if the existing setting was already false; added regression coverage. Also added occupied-staging-file and failed-write preservation fixtures.
Package-maintenance (22 tests, optional registry probe skipped), Pi profile permissions (21 tests, two native-Windows-only cases skipped), shared Node (16 tests plus 959 PowerShell assertions), prose retirement (22 tests), AI-agent, model-default (Bash/Python and PowerShell), Go wiring, and companion/RPIV/subagent contracts passed after teaching orchestration fixtures about the new gate. Final focused rerun, lint, and final review pending. No live setup, dotfiles apply, extension load, credential change, model request, or remote-machine update was performed.

Final verification passed: 15 AskClaude tests with PWSH_BIN and cross-repository rendering enabled; 22 package-maintenance tests (only optional network-isolated registry probe skipped); five dotfiles AskClaude tests including actual isolated apply; five dotfiles model/template tests. ShellCheck on all modified Bash scripts, Markdownlint on both README files, and diff checks passed. Reviewed the helper, wrappers, main-loop failure gates, and preserving template. Removed generated test bytecode. Live Chezmoi source remains clean.
Implementation remains uncommitted in machine-setup aquatic-buffalo and sibling aquatic-buffalo-dotfiles (branch fix/disable-pi-askclaude). No live machines have received the policy. Linux-hosted PowerShell 7.6.6 verified wrapper behavior/environment restoration; native Windows ACL behavior and Windows PowerShell 5.1 execution were not available.

User requested delivery to remote main in both repositories and asked about configuration ownership. Confirmed default configuration belongs in dotfiles; setup retains enforcement for selected custom profiles and existing installations. Both worktree bases matched freshly fetched remote main.
Dotfiles delivered as b7b6cdc5fd427483c3348d92dc35826450d6f16f via normal fast-forward push to scowalt/dotfiles main. Fresh fetch, ancestry, and ls-remote verified it. Dotfiles unittest discovery completed 29 tests with 16 unrelated PowerShell tests skipped; AskClaude/model template tests and Markdownlint passed. Re-ran all 15 AskClaude fixtures and the 22-test package-maintenance suite with the delivered dotfiles tree and PowerShell wrappers. ShellCheck/diff checks passed. Preparing the machine-setup commit and normal fast-forward push; the existing pre-push contract/lint hooks remain enabled.

The first machine-setup push was stopped by the enabled pre-push hook: tests/simple-english-skill-contract.sh still hardcoded the prior setup versions/banners. Updated only those expectations to the new AskClaude versions and incremented the contract version. The managed-skill, Telegram, weekly regression (29 tests; three optional/native cases skipped), and Windows upload contracts now pass, as does ShellCheck on the changed test. Amending the unpublished setup commit, then retrying the full hook without bypasses.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Disable only the Pi AskClaude delegation tool while retaining pi-claude-bridge and Claude/Fable model access.

Ownership and changes:

- Dotfiles owns the preserving default-global configuration template and keeps the bridge registered. Delivered to remote main in <https://github.com/scowalt/dotfiles/commit/b7b6cdc5fd427483c3348d92dc35826450d6f16f> .
- All six setup scripts enforce askClaude.enabled=false in default and explicitly selected global profiles. They preserve provider options, other configuration, authentication, and package registration. Script versions are incremented.
- Identical embedded logic preflights both profiles, rejects unsafe/malformed inputs, writes BOM-free JSON, preserves occupied temporary files, and reports failures without exposing configuration. Policy failure blocks later Pi package/dependent profile work while unrelated work and final logging continue.
- README documentation explains configuration ownership, rollout, reload/restart, and project-local overrides.

Validation:

- AskClaude fixtures: 15 passed, including all six wrappers and repeated dotfiles/setup runs. Dotfiles AskClaude and model/template suites: five tests each passed.
- Pi package-maintenance: 22 tests completed; optional registry probe skipped. Profile permissions, shared-runtime (including 959 PowerShell assertions), prose retirement, model defaults, AI-agent, Go wiring, and companion/RPIV/subagent regressions passed.
- ShellCheck, Markdownlint, and diff checks passed.

Rollout/limits:

- Each machine picks up the policy on its next setup run; existing Pi sessions require reload/restart. Project-local overrides remain untouched. No live setup, extension loads, model requests, credential changes, or fleet updates were performed.
- Native Windows ACL/PowerShell 5.1 verification remains a platform follow-up; PowerShell wrappers were exercised on Linux with 7.6.6.
- This machine-setup commit contains the enforcement, fixtures, documentation, and task record for the delivered dotfiles policy.

Delivery regression fix: aligned the managed-skill contract's hardcoded setup version/banner expectations with this change. The enabled full pre-push hook caught the stale expectations; managed-skill, Telegram, weekly, and Windows-upload checks passed after correction.
<!-- SECTION:FINAL_SUMMARY:END -->
