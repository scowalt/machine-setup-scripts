---
title: "feat: Install Pi goal and autoresearch extensions everywhere Pi is installed"
type: feat
status: completed
date: 2026-05-07
---

<!-- markdownlint-disable MD025 -->

# feat: Install Pi goal and autoresearch extensions everywhere Pi is installed

## Overview

Install the Pi packages that provide long-running goal loops and autoresearch workflows on every machine setup path that installs Pi:

- `npm:pi-goal`
- `npm:pi-autoresearch`

This should cover:

- `mac.sh`
- `ubuntu.sh`
- `wsl.sh`
- `pi.sh`
- `omarchy.sh`
- `bazzite.sh`
- `win.ps1`

## Research Findings

### Local repo patterns

- Existing setup scripts already install/update Pi with `@mariozechner/pi-coding-agent`.
- Existing tintinweb subagent setup provides the pattern to follow:
  - Bash function for package/settings maintenance and an idempotent setup function.
  - PowerShell equivalent using `ConvertFrom-Json` / `ConvertTo-Json`.
  - Optional package failures log warnings and do not abort full machine setup.
- Setup scripts use `~/.env.local` guard placeholders and source them early.
- Setup script version banners are bumped for meaningful script changes.
- `docs/solutions/` does not currently exist, so there are no local solution notes to carry forward.

### Pi package behavior

Pi package docs show global package installation with:

```bash
pi install npm:<package>
```

Global installs update `~/.pi/agent/settings.json` by default. The docs warn that packages and skills can execute or instruct arbitrary actions, so setup should keep failures non-fatal and provide an opt-out for autonomous extensions.

### Package details

`pi-goal`:

- Install: `pi install npm:pi-goal`
- Adds `/goal` plus goal state/tools so Pi can continue a long-running objective until complete, paused, cleared, or token-budget-limited.
- Stores goal state in Pi custom session entries.

`pi-autoresearch`:

- Install: `pi install npm:pi-autoresearch`
- Adds `/autoresearch`, experiment tools, dashboard UI, and skills:
  - `autoresearch-create`
  - `autoresearch-finalize`
  - `autoresearch-hooks`
- Persists progress in project files such as `autoresearch.md` and `autoresearch.jsonl` so loops can survive restarts and compaction.

## Proposed Solution

Add a dedicated Pi autonomous extensions setup step after Pi installation:

- Bash: `setup_pi_goal_autoresearch()`
- PowerShell: `Setup-PiGoalAutoresearch`

The setup step should:

1. Skip/remove package settings when `BAN_PI_GOAL_AUTORESEARCH=1` is set.
2. Verify `pi` is available.
3. Run `pi install npm:pi-goal`.
4. Run `pi install npm:pi-autoresearch`.
5. Validate `pi list` includes both package sources.
6. Log warnings instead of aborting if any optional extension install fails.

Also update the README and `~/.env.local` placeholders to document `BAN_PI_GOAL_AUTORESEARCH=1`.

## Technical Considerations

- Do not reintroduce Pi `npmCommand`; that setting is intentionally unmanaged.
- `pi.sh` and `omarchy.sh` currently run Pi package setup before dotfiles management. Re-run the package setup after dotfiles apply or move extension setup after dotfiles so the final script state keeps these packages active even when dotfiles manage Pi settings.
- Keep package names exact: `npm:pi-goal` and `npm:pi-autoresearch`.
- Treat these as optional agent enhancements; install failures should not break machine provisioning.

## Acceptance Criteria

- [x] `mac.sh` installs/updates `npm:pi-goal` and `npm:pi-autoresearch` after Pi installation.
- [x] `ubuntu.sh` installs/updates `npm:pi-goal` and `npm:pi-autoresearch` after Pi installation.
- [x] `wsl.sh` installs/updates `npm:pi-goal` and `npm:pi-autoresearch` after Pi installation.
- [x] `pi.sh` installs/updates `npm:pi-goal` and `npm:pi-autoresearch` and leaves them active after dotfiles apply.
- [x] `omarchy.sh` installs/updates `npm:pi-goal` and `npm:pi-autoresearch` and leaves them active after dotfiles apply.
- [x] `bazzite.sh` installs/updates `npm:pi-goal` and `npm:pi-autoresearch` after Pi installation.
- [x] `win.ps1` installs/updates `npm:pi-goal` and `npm:pi-autoresearch` after Pi installation.
- [x] `BAN_PI_GOAL_AUTORESEARCH=1` removes these package sources from Pi settings and skips installation.
- [x] Setup is idempotent on reruns and does not intentionally duplicate package entries.
- [x] README documents the new Pi packages and opt-out flag.
- [x] Version banners are incremented in every modified setup script.
- [x] Bash syntax checks pass.
- [x] ShellCheck error-level validation passes.
- [x] Markdownlint passes for updated docs.

## Validation Plan

```bash
git diff --check
bash -n mac.sh ubuntu.sh wsl.sh pi.sh omarchy.sh bazzite.sh
bunx shellcheck --severity=error mac.sh ubuntu.sh wsl.sh pi.sh omarchy.sh bazzite.sh
bunx shellcheck --exclude=SC2312,SC2250,SC2024,SC2154 mac.sh ubuntu.sh wsl.sh pi.sh omarchy.sh bazzite.sh
bunx markdownlint-cli README.md docs/plans/2026-05-07-001-feat-install-pi-goal-autoresearch-plan.md
```

PowerShell parse validation when PowerShell is available:

```powershell
pwsh -NoProfile -Command "$tokens = $null; $errors = $null; [System.Management.Automation.Language.Parser]::ParseFile('win.ps1', [ref]$tokens, [ref]$errors) | Out-Null; if ($errors.Count) { $errors; exit 1 }"
```

Manual/current-machine validation:

```bash
pi install npm:pi-goal
pi install npm:pi-autoresearch
pi list
# expect npm:pi-goal and npm:pi-autoresearch
```

## Validation Results

- `bash -n mac.sh ubuntu.sh wsl.sh pi.sh omarchy.sh bazzite.sh` passed.
- `bunx shellcheck --severity=error mac.sh ubuntu.sh wsl.sh pi.sh omarchy.sh bazzite.sh` passed.
- `bunx shellcheck --exclude=SC2312,SC2250,SC2024,SC2154 mac.sh ubuntu.sh wsl.sh pi.sh omarchy.sh bazzite.sh` passed.
- `bunx markdownlint-cli README.md docs/plans/2026-05-07-001-feat-install-pi-goal-autoresearch-plan.md` passed.
- `git diff --check` passed.
- PowerShell parser validation was not run because neither `pwsh` nor `powershell` is installed in this environment.
- Current machine validation: `pi install npm:pi-goal` and `pi install npm:pi-autoresearch` succeeded; `pi list` now shows both packages. Backup: `/home/scowalt/.pi/agent/settings.json.bak-20260507-121021-pre-pi-goal-autoresearch`.
- Companion dotfiles template update keeps `npm:pi-goal` and `npm:pi-autoresearch` in managed Pi settings so future `chezmoi apply` runs do not remove them.

## Sources & References

- Pi packages docs: `/home/scowalt/.bun/install/global/node_modules/@mariozechner/pi-coding-agent/docs/packages.md`
- Pi skills docs: `/home/scowalt/.bun/install/global/node_modules/@mariozechner/pi-coding-agent/docs/skills.md`
- `pi-goal` NPM metadata and README: `npm view pi-goal`
- `pi-autoresearch` NPM metadata and README: `npm view pi-autoresearch`
- Existing Pi subagent plan: `docs/plans/2026-05-04-001-feat-install-tintinweb-pi-subagents-plan.md`
- Existing setup functions: `setup_pi_subagents`, `Setup-PiSubagents`
