---
id: TASK-32
title: Install the full Matt Pocock skill suite and retire legacy global skills
status: Done
assignee:
  - '@pi'
created_date: '2026-09-15 13:59'
updated_date: '2026-09-15 15:41'
labels: []
dependencies: []
references:
  - 'https://github.com/mattpocock/skills'
  - mac.sh
  - ubuntu.sh
  - wsl.sh
  - pi.sh
  - bazzite.sh
  - win.ps1
  - tests/simple-english-skill-contract.sh
  - tests/pi-skill-ownership-contract.sh
  - tests/setup-reliability-powershell.ps1
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Install the full upstream Matt Pocock suite, including experimental skills, for all four supported agents on personal and work machines. Preserve both Matt Pocock opt-outs. Retire PR Lens, Simple English, and HumanLayer show-me on each machine’s next setup run. Coordinate dotfiles exclusions without applying live profiles or changing remote machines.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 All six setup scripts install and update the approved full Matt Pocock suite for Claude Code, Codex, Gemini CLI, and Pi, including newly added upstream skills without retaining the current eight-skill limit.
- [x] #2 Existing explicit Matt Pocock opt-outs remain effective unless the user approves their retirement; personal and work machines otherwise receive the same suite.
- [x] #3 Setup no longer installs PR Lens and safely removes its shared and default/explicitly configured global agent copies on the next setup run, without following linked targets or altering unrelated skills, credentials, project files, or hooks.
- [x] #4 Pi skill ownership and any necessary dotfiles rules cover the expanded suite without duplicate discovery, and later dotfiles application does not restore PR Lens.
- [x] #5 Failed installs, unsafe cleanup, and invalid installed skill files are reported as setup failures while unrelated setup work continues; existing runtime and profile-safety gates remain intact.
- [x] #6 Offline Bash and available PowerShell fixtures cover repeated runs, full-suite discovery and validation, personal/work parity, opt-outs, PR Lens retirement, custom locations, symlink safety, and failure propagation; affected regression suites and lint pass.
- [x] #7 README.md and repository guidance describe the approved behavior, and every changed setup script has an incremented version and matching change description.
- [x] #8 Simple English and show-me are no longer installed or treated as active shared skills; all six scripts safely remove existing global copies and update records using the same safeguards as PR Lens, while preserving the Matt Pocock suite and unrelated data.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Preserve the approved full Matt Pocock suite, experimental/future skills, four-agent targets, and both opt-outs.
2. Apply the same approved retirement approach to show-me: replace its installers/main calls with failure-aggregating cleanup, extend the shared policy, and remove it from active ownership and isolated dotfiles rules.
3. Update temporary-home Bash/PowerShell fixtures for all three retired skills, custom profiles, lock metadata, symlink safety, repeated runs, and preservation of Matt skills and unrelated data. Preserve generic copied-file validation coverage using inert fixtures.
4. Increment all six versions, update documentation, run affected contracts and lint, and review both worktrees. No live setup, dotfiles application, skill execution, remote changes, or uploads.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Initial read-only investigation: upstream commit 3cca18b368ae95cdbdebbff572ccafa662551015 contains 37 SKILL.md files: 18 engineering, seven productivity, four misc, and eight in-progress. The official Claude plugin includes only the 25 engineering/productivity skills, so plugin installation alone does not satisfy literal full-repository coverage. Current scripts explicitly select eight skills for Codex/Pi and install PR Lens separately for all four harnesses.
Local chezmoi source is clean but behind remote main (local 4b9f1cc, remote f609d6b). Remote Pi settings contain fixed direct-copy exclusions for the existing Matt suite and no PR Lens entry. Avoid editing or applying the stale live source. Bash, shellcheck, Node, Python, gh, and Backlog CLI are available; pwsh was not on PATH. TASK-19 records a pre-existing Linux PowerShell PR Lens ownership fixture failure. No setup scripts, dotfiles, or live agent profiles have been changed; awaiting plan approval.

User approved the plan, including experimental skills and preservation of both existing Matt Pocock opt-outs. Implementation started.

Implementation complete in all six setup scripts. Full selection uses --skill * --full-depth with explicit Claude Code/Codex/Gemini CLI targets and native JSON results; Pi uses the shared copy. A shared embedded Node policy validates every reported copy, tracks future names, preserves both opt-outs, retires PR Lens copies/update records, and manages duplicate exclusions for both default and selected Pi profiles. Bazzite now aggregates these skill failures instead of stopping unrelated work.
Matching dotfiles changes are isolated at /home/scowalt/.paseo/worktrees/02r3t7st/eloquent-meerkat-dotfiles on branch setup-full-matt-skills, based on remote main f609d6b. The template includes all baseline names and validated local inventory names. No live chezmoi application, agent installation, remote host mutation, skill execution, model request, or diagram upload occurred.
Verification: 17 managed-skill tests pass with PowerShell wrappers, repeated setup/template rendering, temporary Bazzite system-alias fixtures, and an offline native skills 1.5.26 discovery/copy/JSON fixture. The native fixture uses inert local skills and blocks network/child processes. The CLI and dependencies were prepared only in /tmp with lifecycle scripts disabled and npm policy unchanged.
Passed: shellcheck for all modified Bash files; markdownlint in both repositories; git diff --check; Simple English, Pi ownership, weekly log audit, setup reliability (including PowerShell), AI-agent, model-default, shared-runtime, profile-permissions, package-maintenance, Go, Go wiring, Muse, surplus-CLI, prose-retirement, headless, release-channel, Plain, and system-home-alias contracts. Dotfiles skill and model-template suites pass. Optional native Go lock/catalog, Paseo PID-lock, adapter registry, and native Windows ACL cases remain environment-gated skips. No claims of native Windows/macOS/ARM workflow execution.
The old PR Lens five-file and modified-reference ownership fixtures now use an inert generic code-review fixture, retaining those checks without installing the retired skill. The PowerShell reliability suite passes with the shared ownership implementation. Removed its two obsolete unused PowerShell helper implementations.

User approved retiring Simple English as part of this same change, while keeping HumanLayer show-me. Reopened the task and added acceptance criterion 8 before implementation.

Simple English retirement is complete. All six installers were replaced with removal wrappers that use the same bounded path, metadata, symlink, and blocked-profile checks as PR Lens. Removal covers shared/default/custom global locations, flat Pi skill files, and both skills CLI lockfile locations. Active Pi ownership and the isolated dotfiles baseline no longer list Simple English. HumanLayer show-me and the full Matt Pocock suite remain unchanged.
Expanded fixtures prove Simple English removal on personal and work machines through every Bash/PowerShell wrapper, repeated runs, preservation of show-me/Matt skills/project copies/environment files, linked-target safety, malformed or linked metadata rejection, and partial cleanup with blocked Pi profiles. Corrected stale function names in Go/Plain main-block fixtures so they mock the current cleanup entry points.
Final validation: 19 managed-skill tests pass, including optional offline native skills CLI and repeated dotfiles rendering. Managed-agent, ownership, PowerShell reliability, profile-permissions, Go wiring, Plain, weekly regression, package-maintenance, AI-agent, and shared-runtime contracts pass. Dotfiles skill/model suites, shellcheck, markdownlint in both worktrees, and git diff --check pass. Native Windows ACL coverage remains a separate platform verification requirement. No live profiles or remote machines were changed.

User approved extending the same next-run retirement to show-me. Reopened the task, updated the scope and acceptance criterion 8, and retained all existing safety and rollout boundaries.

Show-me retirement is complete in all six scripts. Its installer and main calls now use the shared bounded cleanup policy, including global/default/custom copies, flat Pi Markdown files, and skills CLI update records. It is no longer added to active Pi ownership or the isolated dotfiles template. Bazzite aggregates removal failure instead of aborting unrelated setup work.
Expanded fixtures cover all three retirements in sequence on personal and work machines through every wrapper, repeated cleanup, dangling Markdown links, copied or modified skills, both lock locations, full Matt suite preservation, unrelated project/environment data, and blocked Pi profiles. Generic copied-file and modified-reference validation remains covered with inert tdd/code-review fixtures rather than show-me installation.
Final validation: all 21 managed-skill tests pass with PowerShell, optional offline native CLI, and dotfiles rendering enabled. Managed-agent, ownership, PowerShell reliability, profile-permissions, Go wiring, Plain, weekly regressions, package-maintenance, AI-agent, shared-runtime, and both dotfiles suites pass. ShellCheck, Markdownlint in both repositories, and whitespace checks pass. The combined regression command hit its wall-clock limit during shared-runtime testing; rerunning that contract separately passed. No live profiles, remote machines, or hosted content were changed.

User requested publication to remote main for both repositories. Confirmed both worktrees are based on their current origin/main commits and neither branch requires a pull request. Delivery will use ordinary fast-forward pushes with hooks enabled, without force pushes or live setup.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
All six setup scripts install the full Matt Pocock suite and retire PR Lens, Simple English, and HumanLayer show-me on each machine’s next setup run. Experimental skills and future additions are included, and both Matt Pocock opt-outs remain supported.

Changes:

- Added identical shared validation, inventory, cleanup, and Pi ownership policy across the six scripts.
- Replaced all three retired skill installers with safe removal of global copies and skills CLI update records, including selected custom profiles and direct Pi Markdown skills.
- Preserved linked targets, the Matt suite, unrelated skills, project files, credentials, existing environment files, runtime policy, and Pi profile-safety gates.
- Updated the matching dotfiles template so later applies retain the full Matt suite exclusions without listing retired skills as active.
- Updated documentation, six version banners, and regression fixtures.

Validation:

- 21 managed-skill tests pass with Bash/PowerShell wrappers, offline native skills 1.5.26 discovery, and repeated dotfiles rendering.
- Affected setup/runtime/Pi/Paseo contracts, dotfiles skill/model tests, ShellCheck, Markdownlint, and whitespace checks pass.
- Native Windows ACLs and optional integration environments retain their documented coverage limits.

Changes span scowalt/machine-setup-scripts and scowalt/dotfiles. No live or remote setup was run; each machine receives the changes on its next setup run.
<!-- SECTION:FINAL_SUMMARY:END -->
