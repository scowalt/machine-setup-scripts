---
id: TASK-27
title: Provision OpenCode Go for Pi and managed Muse Contributor profiles
status: Done
assignee:
  - '@pi'
created_date: '2026-09-13 18:37'
updated_date: '2026-09-13 23:12'
labels: []
dependencies: []
references:
  - CONTEXT.md
  - README.md
  - tests/ai-coding-agent-contract.sh
  - tests/headless-paseo-daemon-contract.sh
  - 'https://opencode.ai/docs/go/'
  - 'https://paseo.sh/docs/agent-profiles.md'
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Add OpenCode Go subscription access to Pi and a selectable Muse Spark 1.3 Contributor/xhigh Paseo profile on the next setup run for every supported platform, including work machines. Preserve existing GPT-6 Astra defaults and unrelated credentials/profiles. The user accepts the Contributor training policy and supplies OPENCODE_GO_API_KEY in ~/.env.local. Setup may restart an identified, setup-managed local daemon when needed. If setup cannot safely control the owning Desktop daemon, runs inside the daemon it would stop, or cannot establish ownership and a stopped interval, leave the profile unchanged and provide warning/manual rerun instructions.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 All six setup scripts support the addition on personal and work machines without changing Pi defaults, installing the OpenCode CLI, purchasing a subscription, or configuring paid Zen as a fallback.
- [x] #2 A nonempty OPENCODE_GO_API_KEY from the account environment file synchronizes only the active Pi profile opencode-go credential; absent input preserves existing credentials, and unrelated credentials and existing environment files remain unchanged.
- [x] #3 The managed Paseo profile selects Pi, opencode-go/muse-spark-1.3-contributor, and native xhigh; it is created even without a key, with a clear missing-authentication warning when needed.
- [x] #4 Repeated setup restores the managed provider/model/reasoning fields and recreates a deleted managed profile while preserving other profiles and optional user customizations without duplicate managed entries.
- [x] #5 Credential and profile mutations reject unsafe linked paths and malformed metadata, preserve concurrent unrelated changes, and never disclose keys in commands, logs, tests, or repository files.
- [x] #6 Profile changes respect local daemon ownership and platform restrictions; setup may restart the owning local daemon without affecting remote hosts or unrelated daemons.
- [x] #7 Documentation states the exact key name, Contributor training/retention implications, account-managed Go subscription and training consent, and the requirement to disable Use balance for subscription-only billing.
- [x] #8 Offline Bash, embedded-code, and PowerShell fixtures cover the managed additions and preservation/failure cases; relevant existing contracts and lint pass, modified setup versions increment, and development performs no live setup, model requests, or fleet rollout.
- [x] #9 Unsafe Desktop-owned, self-hosted setup, and unverified daemon-ownership cases defer profile synchronization with actionable manual rerun instructions rather than claiming success, killing Desktop, or creating a second daemon.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Implement identical embedded Go credential helpers and wrappers in all six scripts. Read the dedicated file key safely, validate the built-in Go/Muse/xhigh catalog offline, coordinate native auth locking, and preserve unrelated state with protected paths and private permissions.
2. Implement identical embedded managed Muse profile merging plus owner-aware local lifecycle handling. Preserve optional fields, restore required core/deletion, avoid needless restarts, restore a stopped service after errors, and defer unsafe Desktop/self-hosted/unknown-owner cases without changing the file.
3. Wire Go setup after successful Pi installation, profile synchronization before daemon setup and Plain, and preserve all existing platform/channel gates. Aggregate failures, increment setup versions, and add the commented key only to new environment templates.
4. Add extracted-function/embedded-code fixtures for auth rotation/absence, catalog gates, preservation, malformed/linked metadata, concurrent writes, custom homes, profile repair, lifecycle restoration and deferrals. Include PowerShell wrappers with the isolated PowerShell 7 runtime. Narrow the OpenCode CLI retirement assertion without restoring CLI installation.
5. Update README/CLAUDE/glossary, run focused and affected regression contracts plus shellcheck/Markdown lint, review the entire diff, then complete acceptance criteria and final summary only for verified outcomes. No live setup, live service operations, model requests, account changes, or remote rollout.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Design interview settled Q1-Q9: additive only; all personal/work machines; user supplies dedicated file key; Go Contributor only; missing key still gets profile; setup repairs managed core/deletion; nonempty key synchronizes Go-only native auth; controlled daemon restarts authorized; unsafe Desktop/self-hosted/unknown-owner cases may defer with manual instructions.
Read-only research confirmed native Pi Go/model/xhigh support, provider-specific auth storage, private dotfiles do not own auth.json or Paseo profiles, and existing lifecycle/platform constraints. Go endpoint selection alone cannot guarantee subscription-only billing: the user must keep the account Use balance option off. Research ran no setup, model calls, live service operations, or remote rollout. Only glossary/task metadata changed so far.

User approved the full plan and implementation. Work is split between independent credential and profile/lifecycle helpers; main agent owns integration, versions, documentation, and combined regression review. Main call order and all six setup versions updated. Dedicated key/profile runbook added. Located and verified isolated PowerShell 7.6.6 at /tmp/pi-shared-runtime-pwsh.2SlAPL/pwsh for wrapper fixtures.

Initial regression pass: model defaults (Bash/PowerShell), z.ai, shared Node (959 PowerShell assertions), Telegram templates, release channels/system-home alias, existing headless lifecycle, prose retirement, Plain installer, and Codex isolation pass. New extracted main-block tests also pass for all six scripts. Package-maintenance integration fixtures currently encounter not-yet-inserted Muse helper definitions and will rerun after helper work finishes.
The wider setup-reliability PowerShell suite fails at the known PR Lens ownership assertion (line453, existing TASK-19). Reproduced the identical failure with HEAD win.ps1 and HEAD fixtures in a disposable HOME; this is not a new Go/Muse regression. Baseline evidence is /tmp/task26-baseline-reliability.log. No unrelated production ownership fixes are included.

Credential worker aborted after saving its helper; main took over credential testing and review. Added 16 offline auth tests, including all six wrappers, literal file-only keys, rotation/absence, private paths, symlink/JSON rejection, model override refusal, and native proper-lockfile concurrency with Pi 0.85.1 catalog metadata. All pass with PowerShell 7.6.6. Fixed PowerShell Get-Command returning multiple node applications, symlink resolution before native dependency validation, and native lock interoperability under the account umask. Native installed Pi code retains normal npm group permissions; secret/profile paths remain strict, and world-writable installed metadata is rejected. No application session or model endpoint was invoked.

Go credential suite now passes 16 tests, including the explicitly selected native lock module/catalog probe and PowerShell wrappers. Main-block wiring tests pass. Re-ran package-maintenance (previous incomplete-helper failures now gone), AI-agent retirement/wiring, Telegram templates, and headless-daemon contracts: all pass. Shellcheck on all five setup scripts and modified shell tests, Markdown lint, and diff whitespace checks pass.
Remaining profile review points to resolve with the active profile worker after its completion: inherited NODE_OPTIONS/NODE_PATH in its wrapper, unsafe-number preservation in JSON, explicit empty/custom PASEO_HOME semantics, and conservative deferral for service drop-ins. No review changes have been made to that worker-owned helper while it is active.

Confirmed from Paseo 0.8 profile-picker/preference source that adding a profile does not itself change the saved create-agent selection. New Go key/profile wiring remains additive. Added a guard so failed/unavailable Go preflight also skips later managed-daemon setup instead of bypassing the profile safety check.
Full redacted gitleaks directory scan reports only an unchanged baseline false positive at bazzite.sh:26-27: two empty assignments (DOTFILES_ACCESS_METHOD and SUDO_KEEPALIVE_PID), verified identical to HEAD. No real credential or new finding was found. The profile worker is addressing consolidated review feedback (Node hook isolation, unsafe-number handling, validated in-HOME custom Paseo paths, and native PID-lock evidence).

Full shell-contract sweep found only the pre-existing TASK-19 PowerShell failure plus stale hard-coded version expectations in the Simple English contract. Updated those expectations for the required six version increments; that contract now passes. Re-ran package maintenance, prose, shared Node, and headless contracts after adding Go-failure guards: all pass. Go failure now blocks later Pi package operations as well as profile/daemon setup.
Credential fixtures now total 17 passing tests: added legacy PowerShell native-argument coverage and fixed the empty default-profile argument that Windows PowerShell 5.1 would drop. Environment-file byte preservation and ordinary padded bearer-key characters are covered.
Profile follow-up passed 49 tests, including explicit native Paseo 0.8.0 PID-lock exclusion, with custom-home and Node-hook fixes. Final review requested only default Windows profile/file ACL validation, which was previously limited to custom homes. Native macOS/Windows/ARM lifecycle smoke tests remain outside this development run.

Final review complete. Added Windows ACL checks for default/custom profile metadata and ancestor directories, pinned native PowerShell module loading, and ensured verified custom homes skip the later legacy default-home daemon installer. Both embedded helpers remain identical across all six scripts. Reviewed wrapper/main diffs and preservation boundaries.
Final focused validation: 17 Go credential tests, 55 Muse profile/lifecycle tests, and 3 main-wiring tests pass, plus PowerShell wrapper and ACL-policy fixtures. Explicit native Pi proper-lockfile/catalog and Paseo 0.8.0 PID-lock probes passed using temporary fixtures only. All 29 shell contracts were run: 28 pass; the sole failure is the independently reproduced baseline TASK-19 PR Lens assertion. The 18 system-home alias tests pass. The optional native Git fixture-isolation test was invoked but skipped because no plugin-service module was supplied; it is unrelated to this change.
ShellCheck, Markdown lint, whitespace checks, and final self-review pass. Redacted secret scan found no new findings; its sole finding is the previously verified unchanged empty-assignment false positive. No native platform lifecycle smoke tests, live setup/service changes, model requests, or remote rollout occurred. Changes remain uncommitted.

Delivery preparation: remote main advanced with the Pi MCP adapter fix (3b45e95) and delivery record (f2e7f4e). Rebased this change without overwriting either commit. Moved the local task through Backlog draft/promote to TASK-27 because remote main already owns TASK-26. All task content and completed criteria were preserved. Incremented versions again to macOS 229, Ubuntu 251, WSL 193, Raspberry Pi 210, Bazzite 110, and Windows 146; updated banner fixtures accordingly.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Added OpenCode Go access and a selectable Muse 1.3 Contributor/xhigh Paseo profile to all six setup scripts, including work machines, without changing GPT-6 Astra defaults.

Changes:

- Synchronize the dedicated OPENCODE_GO_API_KEY file value into only the active Pi Go credential, using native credential locking and private filesystem/ACL checks. Preserve existing environment files and unrelated credentials/providers.
- Validate the installed native Go catalog and exact Contributor/xhigh model. Add and repair one stable-ID profile while preserving optional fields and other profiles.
- Coordinate offline profile writes with native PID exclusion and verified local service ownership. Defer Desktop, self-hosted, customized/unverified service, and unsafe-path cases. Restore stopped services after failure where safe. Protect custom-home selection from the legacy default-home daemon installer.
- Aggregate failures, block unsafe subsequent operations, increment all six setup versions, and document training/retention, subscription consent, and the account-level Use balance requirement.

Validation:

- 75 new Python contract tests pass, plus PowerShell wrapper/ACL-policy fixtures and native Pi/Paseo lock probes.
- 28 of 29 shell contracts pass; the remaining setup-reliability PowerShell failure is unchanged baseline TASK-19, reproduced on HEAD.
- System-home alias tests, ShellCheck, Markdown lint, whitespace checks, and secret review pass with no new findings.

Limits:

- Future setup runs only; no live rollout or model requests were performed.
- Native Windows/macOS/ARM lifecycle behavior was not smoke-tested. Custom homes and service drop-ins can require manual owner updates. Arbitrary external editors can ignore native PID exclusion, so do not edit configuration during setup.
<!-- SECTION:FINAL_SUMMARY:END -->
