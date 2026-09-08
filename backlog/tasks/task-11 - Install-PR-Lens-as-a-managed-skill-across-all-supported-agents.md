---
id: TASK-11
title: Install PR Lens as a managed skill across all supported agents
status: Done
assignee:
  - '@pi'
created_date: '2026-09-08 17:23'
updated_date: '2026-09-08 17:49'
labels: []
dependencies: []
references:
  - 'https://github.com/coldteadotai/pr-lens'
  - >-
    https://github.com/coldteadotai/pr-lens/blob/b5309c353c79e536a3f6a69713b1b7eb276515a1/skills/pr-lens/SKILL.md
  - tests/simple-english-skill-contract.sh
  - tests/pi-skill-ownership-contract.sh
  - tests/setup-reliability-powershell.ps1
documentation:
  - CONTEXT.md
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Make PR Lens available beside show-me in every supported coding agent on personal and work machines. Each machine receives the skill on its next setup run. Scott approved the upstream default hosted uploads, including on work machines, instead of an approval-before-upload policy. This change does not require diagrams on every pull request.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Every macOS, Ubuntu, WSL, Raspberry Pi, Bazzite, and Windows setup run requests the latest coldteadotai/pr-lens skill globally for Claude Code, Codex, Gemini CLI, and Pi, on personal and work machines with no opt-out.
- [x] #2 Installation is noninteractive and reuses the managed shared copies for Codex, Gemini CLI, and Pi plus the Claude Code copy, including existing custom-path support. It does not add retired agents or redundant direct Pi copies.
- [x] #3 Both installed PR Lens copies contain SKILL.md, LICENSE, references/graph-document.md, references/config.md, and references/example.graph.json as real nonempty files. Missing files and linked files or directories cause a reported setup failure.
- [x] #4 Repeated setup runs update PR Lens safely. Pi ownership handles obsolete direct PR Lens copies consistently with existing managed skills and preserves user-modified content.
- [x] #5 The upstream skill remains unchanged, including default hosted uploads on personal and work machines. Setup adds no mandatory PR diagrams, runtime workflow, extra provider credentials, GitHub App, dotfiles policy override, or shell configuration.
- [x] #6 The rollout consists of setup script changes for the next setup run, not remote fleet installation. Setup and tests do not upload diagrams, post PR content, or alter project data.
- [x] #7 Relevant Bash and PowerShell regression coverage covers installation targets, repeat runs, complete artifacts, failure propagation, and Pi ownership. All six script versions and relevant expectations increase, and repository docs explain the approved scope and hosted-upload behavior.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Extend the existing managed skill installer interfaces only as needed to check the complete PR Lens footprint. Add thin PR Lens wrappers in all five Bash scripts and Windows, using coldteadotai/pr-lens and the pr-lens skill name. Keep the upstream files unchanged.
2. Wire the required installation after agent provisioning and before Pi ownership cleanup. Add pr-lens to all six canonical ownership lists and preserve current failure propagation and custom directory behavior.
3. Extend offline Bash and PowerShell fixtures for repeat runs, exact targets, all five files, empty/missing/linked artifacts, failures, and obsolete Pi copies. Do not install or execute PR Lens against a real repository.
4. Increment all six script versions and update pinned test expectations. Update README.md, CLAUDE.md, and the glossary to distinguish the skill from the GitHub App and describe next-run rollout, default hosted uploads, and remaining runtime limits. No dotfiles or shell-profile changes.
5. Run Bash syntax checks, ShellCheck, offline contract tests, and Markdown lint. PowerShell is not currently installed: run its suite if a suitable runtime becomes available without altering the host, otherwise record that gap. Review the final diff and update the task with evidence.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Scott approved all five rollout decisions, with Q4 changed to allow default hosted uploads, including on work machines. No local-only policy or approval gate will be added.
- Read-only research found no upstream publishing-off setting. Published CLI 0.4.0 uploads graph JSON and prints a secret edit link. Do not promise canvas deletion or keep credential-bearing output in test fixtures.
- Existing skill runtime minimum is higher than PR Lens Node >=20.11. Native Windows and Linux ARM64 viability is source-based, not tested. ARM32 runtime readiness and gh attachment compatibility remain environmental limits, not reasons to install another workflow.
- Bash, ShellCheck, Bun, Node, and npx are present. PowerShell is absent. No setup scripts or package installers have run.
- Implementation plan prepared. Awaiting the repository-required plan approval before code changes.

Scott approved the implementation plan and requested implementation in a subagent in this Paseo workspace. Proceed with code changes under the recorded scope. Hosted uploads remain allowed by default, including on work machines.

Implementation started in the approved shared workspace. Confirmed the existing shared installer, custom Claude path handling, and byte-identical Bash ownership pattern. Parent CONTEXT.md glossary change will remain untouched. No setup entry points or upstream CLI workflows will run.

- Added required PR Lens wrappers and main wiring to all six scripts, plus canonical Pi ownership entries. All six version banners increased by one. The shared installer now validates required nonempty regular files and every path component inside each skill copy without changing file contents.
- Extended offline Bash and PowerShell fixtures for exact targets, repeated personal/work runs, custom/default Claude paths, missing/empty/directory/linked artifacts, linked references directories, failure propagation, and obsolete Pi copies with user-modified references. Targeted Bash contracts pass.
- ShellCheck and Bash syntax checks pass on all seven modified shell files. No pwsh/powershell runtime found on PATH or in searched temporary/cache/opt locations. Windows runtime tests remain pending/unverified. Markdown lint tool was not cached; the no-install attempt stopped without running lint.

- Final verification passed: `for file in mac.sh ubuntu.sh wsl.sh pi.sh bazzite.sh tests/simple-english-skill-contract.sh tests/pi-skill-ownership-contract.sh; do bash -n "${file}"; done` and `shellcheck mac.sh ubuntu.sh wsl.sh pi.sh bazzite.sh tests/simple-english-skill-contract.sh tests/pi-skill-ownership-contract.sh`.
- Final verification passed: `for test in tests/*.sh; do bash "${test}" || exit 1; done` (all 20 offline Bash suites, including the four Python model-default cases). Full final output is at /tmp/task-11-contracts.3S52Q9.log. `bunx markdownlint-cli *.md` and `git diff --check` also pass. Markdownlint required a temporary Bun cache download; no repository dependency files changed.
- Windows gap: `command -v pwsh || command -v powershell` found neither runtime. `tests/setup-reliability-powershell.ps1` was extended and self-reviewed but not executed or parsed by PowerShell. Static Windows target/artifact/wiring contracts pass in the Bash suite. Native Windows symlinks/junctions and runtime behavior remain unverified; file-symlink tests require Windows symlink privileges. No host setup changes were made to obtain a runtime.
- Self-review found only intended installer, ownership-list, version, documentation, and test changes. Added drift checks prove the helper, PR Lens wrapper, and ownership function remain byte-identical across the five Bash scripts. Failure-wiring checks cover each required setup call. Default hosted uploads remain unchanged. No PR Lens CLI was installed/executed, no live skill installation or remote rollout ran, and no diagrams or PR content were uploaded/posted.
- Parent CONTEXT.md glossary edit remains unchanged. All implementation changes remain uncommitted for parent review. Versions: macOS 219, Ubuntu 241, WSL 183, Raspberry Pi 200, Bazzite 100, Windows 136.

- Parent review found no implementation blockers. Independently reran Bash syntax checks, ShellCheck, both targeted skill suites, and all 20 Bash suites successfully. Full parent suite log: /tmp/task-11-parent-review.7R6DH3.log.
- Reviewed the entire diff and upstream skills installer copy behavior. LICENSE and bundled references are not excluded from ordinary skill copies. Hosted behavior remains unchanged.
- Broader Markdown lint found missing blank lines in this task final summary. Corrected them through Backlog CLI. The Windows runtime gap remains as documented.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Install the latest upstream PR Lens skill on the next setup run across all six platforms and all four supported agents, on personal and work machines. Hosted uploads retain the upstream defaults with no added gate or opt-out.

Changes:

- Reuse the copied Claude/shared skill installation paths and required setup failure handling. Validate all five nonempty regular PR Lens files, including nested directory-link rejection. Upstream contents remain unchanged.
- Add PR Lens to canonical Pi ownership, preserving modified obsolete copies while excluding them and removing identical duplicates. Increment all six setup banners.
- Expand offline Bash/PowerShell contracts and document next-run rollout, hosted canvas visibility, secret edit-link handling, Node/gh requirements, and unverified native runtime limits.

Verification:

- Bash syntax and ShellCheck passed on all seven modified shell files.
- All 20 offline Bash suites passed, including managed-skill validation, ownership, and static Windows contracts. Root Markdown lint and git diff --check passed.
- PowerShell is unavailable, so the extended Windows runtime suite remains unexecuted. Native Windows, ARM64, and ARM32 PR Lens runtime workflows were not smoke-tested.

No live setup, skill installation, PR Lens execution, upload, PR post, push, or commit ran. Changes are uncommitted.
<!-- SECTION:FINAL_SUMMARY:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 Run ShellCheck and Bash syntax checks on changed shell scripts.
- [x] #2 Run offline Bash contract tests and Markdown lint. Run PowerShell tests when a PowerShell runtime is available, and record any platform verification gaps.
- [x] #3 Review the diff for unintended file, credential, policy, or platform changes.
<!-- DOD:END -->
