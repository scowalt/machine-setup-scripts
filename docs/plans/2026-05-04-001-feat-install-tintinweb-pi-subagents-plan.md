---
title: "feat: Install tintinweb Pi subagents everywhere Pi is installed"
type: feat
status: completed
date: 2026-05-04
---

<!-- markdownlint-disable MD025 -->

# feat: Install tintinweb Pi subagents everywhere Pi is installed

## Overview

Install [`@tintinweb/pi-subagents`](https://github.com/tintinweb/pi-subagents) on every machine setup path that installs Pi, so fresh and rerun setups get Claude Code-style Pi subagents immediately after Pi is installed.

This should cover all current setup targets:

- `mac.sh`
- `ubuntu.sh`
- `wsl.sh`
- `pi.sh`
- `omarchy.sh`
- `bazzite.sh`
- `win.ps1`

## Research Findings

### Local repo patterns

- All seven setup scripts already install/update Pi with `@mariozechner/pi-coding-agent`.
- Bash scripts share the same rough pattern:
  - `install_pi_cli()` installs Pi with `bun install -g @mariozechner/pi-coding-agent`.
  - `setup_pi_compound_engineering()` runs after Pi installation.
  - Main flow calls Pi setup in the development-tools section.
- Windows mirrors the pattern with:
  - `Install-PiCli`
  - `Setup-PiCompoundEngineering`
- Setup scripts must remain idempotent, log warnings rather than aborting for optional agent setup failures, and increment script version numbers when modified.
- `README.md` documents AI agent setup and existing opt-out flags.
- `docs/solutions/` does not currently exist, so there are no local solution notes to carry forward.

### Pi package behavior

Pi packages are installed with:

```bash
pi install npm:@tintinweb/pi-subagents
```

Pi writes package sources to global settings by default at `~/.pi/agent/settings.json`. NPM package operations use the Pi `npmCommand` setting when present; otherwise Pi shells out to `npm`. Because these setup scripts install Pi with Bun and do not guarantee global `npm` availability, the implementation should ensure Pi package installs use Bun via:

```json
"npmCommand": ["bun"]
```

Pi package docs also warn that extensions execute arbitrary code with full system access. This is acceptable for this requested install, but the plan includes a dedicated opt-out flag.

### External package details

- GitHub repo: <https://github.com/tintinweb/pi-subagents>
- NPM package: `@tintinweb/pi-subagents`
- Latest observed version: `0.7.0`
- Install command from README: `pi install npm:@tintinweb/pi-subagents`
- Peer dependency requirement: Pi packages `>=0.70.5`
- Registers Claude Code-style tools: `Agent`, `get_subagent_result`, `steer_subagent`
- Adds `/agents` command and default agent types like `general-purpose`, `Explore`, and `Plan`.

### Existing package conflict to handle

Current dotfiles-managed Pi settings already include:

```json
"packages": [
  "npm:pi-subagents",
  "npm:pi-web-access"
]
```

That unscoped `npm:pi-subagents` package is a different NPM package from a different repository. It likely overlaps tool names with `@tintinweb/pi-subagents`, so the implementation should replace it rather than installing both.

## Proposed Solution

Add a dedicated Pi subagents setup step immediately after Pi installation in every script:

- Bash: `setup_pi_subagents()`
- PowerShell: `Setup-PiSubagents`

The setup step should:

1. Ensure Bun is on `PATH`.
2. Skip or remove when `BAN_PI_SUBAGENTS=1` is set.
3. Verify `pi` is available.
4. Ensure Pi settings use `"npmCommand": ["bun"]` so package installation does not depend on `npm`.
5. Remove legacy `npm:pi-subagents` from Pi settings/package install if present.
6. Install/update `npm:@tintinweb/pi-subagents` through Pi's package manager.
7. Validate `pi list` or settings show `npm:@tintinweb/pi-subagents`.
8. Log success/warnings without making the whole setup fail if optional Pi extension setup fails.

Also make the companion dotfiles change so future `chezmoi apply` does not revert the package list back to the legacy unscoped package.

## Technical Approach

### 1. Bash setup scripts

Modify:

- `mac.sh`
- `ubuntu.sh`
- `wsl.sh`
- `pi.sh`
- `omarchy.sh`
- `bazzite.sh`

Add a function near `install_pi_cli()` / `setup_pi_compound_engineering()`:

```bash
setup_pi_subagents() {
    # Ensure bun is on PATH
    # If BAN_PI_SUBAGENTS=1: remove package from settings and return
    # If pi missing: warn and return
    # Ensure ~/.pi/agent/settings.json has npmCommand ["bun"]
    # Remove legacy npm:pi-subagents source
    # Run: pi install npm:@tintinweb/pi-subagents
    # Validate: pi list contains npm:@tintinweb/pi-subagents
}
```

Call it after `install_pi_cli` and before `setup_pi_compound_engineering`:

```bash
install_pi_cli
setup_pi_subagents
setup_pi_compound_engineering
```

### 2. Windows setup script

Modify `win.ps1` with a PowerShell equivalent:

```powershell
function Setup-PiSubagents {
    # Ensure Bun path
    # Honor BAN_PI_SUBAGENTS
    # Check pi command
    # Update ~/.pi/agent/settings.json npmCommand/packages safely with ConvertFrom-Json/ConvertTo-Json
    # Run: pi install npm:@tintinweb/pi-subagents
    # Validate: pi list contains npm:@tintinweb/pi-subagents
}
```

Call it after `Install-PiCli` and before `Setup-PiCompoundEngineering`.

### 3. Dotfiles companion change

Modify the Pi settings template in the dotfiles repo:

- `/home/scowalt/Code/dotfiles/private_dot_pi/agent/private_settings.json.tmpl`

Change:

```json
"packages": [
  "npm:pi-subagents",
  "npm:pi-web-access"
]
```

to:

```json
"npmCommand": ["bun"],
"packages": [
  "npm:@tintinweb/pi-subagents",
  "npm:pi-web-access"
]
```

This prevents future `chezmoi apply` runs from reintroducing the legacy unscoped package.

### 4. README update

Update `README.md` AI agent section to mention:

- Pi subagents are installed alongside Pi.
- `BAN_PI_SUBAGENTS=1` skips/removes the Pi subagents extension.
- `BAN_COMPOUND_PLUGIN=1` remains scoped to Compound Engineering.

### 5. Version bumps

Increment each modified setup script version and update the last-changed text:

- `mac.sh`: `156` → `157`
- `ubuntu.sh`: `170` → `171`
- `wsl.sh`: `126` → `127`
- `pi.sh`: `135` → `136`
- `omarchy.sh`: `140` → `141`
- `bazzite.sh`: `34` → `35`
- `win.ps1`: `87` → `88`

## Acceptance Criteria

- [x] `mac.sh` installs/updates `npm:@tintinweb/pi-subagents` after Pi installation.
- [x] `ubuntu.sh` installs/updates `npm:@tintinweb/pi-subagents` after Pi installation.
- [x] `wsl.sh` installs/updates `npm:@tintinweb/pi-subagents` after Pi installation.
- [x] `pi.sh` installs/updates `npm:@tintinweb/pi-subagents` after Pi installation.
- [x] `omarchy.sh` installs/updates `npm:@tintinweb/pi-subagents` after Pi installation.
- [x] `bazzite.sh` installs/updates `npm:@tintinweb/pi-subagents` after Pi installation.
- [x] `win.ps1` installs/updates `npm:@tintinweb/pi-subagents` after Pi installation.
- [x] Setup is idempotent on reruns and does not duplicate package entries.
- [x] Legacy `npm:pi-subagents` is removed/replaced so both subagents packages are not loaded together.
- [x] Pi package installs use Bun via `npmCommand: ["bun"]` rather than assuming `npm` exists.
- [x] `BAN_PI_SUBAGENTS=1` prevents the tintinweb subagents package from being active.
- [x] Setup failures for Pi subagents log warnings but do not abort the whole machine setup.
- [x] `README.md` documents Pi subagents and the opt-out flag.
- [x] Dotfiles Pi settings template is updated so chezmoi preserves the tintinweb package source.
- [x] Version headers are incremented in every modified setup script.
- [x] ShellCheck has no new findings in the modified Bash sections; `shellcheck --severity=error` and the run excluding pre-existing SC2312/SC2250/SC2024/SC2154 findings pass.
- [ ] PowerShell syntax parsing passes for `win.ps1`. (Not run locally: `pwsh`/`powershell` unavailable in this Linux environment.)
- [x] Markdownlint passes for updated docs.

## System-Wide Impact

### Interaction Graph

1. User runs a platform setup script.
2. Script installs/updates Bun and Pi.
3. New Pi subagents setup function updates Pi package settings and installs the package.
4. Future Pi startup loads `@tintinweb/pi-subagents` and registers `Agent`, `get_subagent_result`, `steer_subagent`, and `/agents`.
5. Chezmoi later reapplies dotfiles; the dotfiles template must keep the same package source or the setup-script install will be reverted.

### Error & Failure Propagation

- Missing Bun: warn and skip Pi subagents.
- Missing Pi: warn and skip Pi subagents.
- Package install failure: warn and continue.
- Settings JSON parse failure: warn and continue rather than corrupting settings.
- Legacy package removal failure: warn, then avoid installing the scoped package if both would remain active.

### State Lifecycle Risks

- Partial settings edits could corrupt `~/.pi/agent/settings.json`; use temp-file writes for Bash and PowerShell JSON serialization for Windows.
- Installing both unscoped and scoped subagents packages could create duplicate tool registrations; remove/replace the unscoped package first.
- Dotfiles can overwrite setup-script changes; update dotfiles template as part of the same change set.

### API Surface Parity

All scripts that currently install Pi should get the same behavior. There should be no platform-specific omissions unless a command is unavailable and logs a warning.

## Risks & Mitigations

- **Risk: third-party extension runs arbitrary code.** Mitigate with explicit package source, README documentation, and `BAN_PI_SUBAGENTS=1` opt-out.
- **Risk: package manager mismatch (`npm` missing).** Mitigate by setting Pi `npmCommand` to Bun.
- **Risk: duplicate subagent extensions.** Mitigate by migrating away from existing `npm:pi-subagents`.
- **Risk: dotfiles fight setup scripts.** Mitigate with companion dotfiles template update.
- **Risk: PowerShell JSON formatting changes settings unexpectedly.** Mitigate by preserving known fields and validating `ConvertFrom-Json`/`ConvertTo-Json` output.

## Validation Plan

Run from `/home/scowalt/Code/machine-setup-scripts` after implementation:

```bash
git diff --check
bunx shellcheck mac.sh ubuntu.sh wsl.sh pi.sh omarchy.sh bazzite.sh
bunx markdownlint-cli README.md docs/plans/2026-05-04-001-feat-install-tintinweb-pi-subagents-plan.md
```

PowerShell parse validation:

```powershell
pwsh -NoProfile -Command "$tokens = $null; $errors = $null; [System.Management.Automation.Language.Parser]::ParseFile('win.ps1', [ref]$tokens, [ref]$errors) | Out-Null; if ($errors.Count) { $errors; exit 1 }"
```

Manual/current-machine validation after applying dotfiles and running the relevant setup path:

```bash
pi list
# expect npm:@tintinweb/pi-subagents
# expect no npm:pi-subagents
```

## Validation Results

- `git diff --check` passed for machine-setup-scripts and dotfiles.
- `bash -n mac.sh ubuntu.sh wsl.sh pi.sh omarchy.sh bazzite.sh` passed.
- `bunx shellcheck --severity=error mac.sh ubuntu.sh wsl.sh pi.sh omarchy.sh bazzite.sh` passed.
- `bunx shellcheck --exclude=SC2312,SC2250,SC2024,SC2154 mac.sh ubuntu.sh wsl.sh pi.sh omarchy.sh bazzite.sh` passed; a full configured shellcheck run still reports pre-existing findings in those excluded categories.
- `bunx markdownlint-cli README.md docs/plans/2026-05-04-001-feat-install-tintinweb-pi-subagents-plan.md` passed.
- PowerShell parser validation was not run because neither `pwsh` nor `powershell` is installed in this environment.
- Current machine validation: `pi install npm:@tintinweb/pi-subagents` succeeded and `pi list` now shows `npm:@tintinweb/pi-subagents` without legacy `npm:pi-subagents`. Backup: `/home/scowalt/.pi/agent/settings.json.bak-20260504-165458-pre-tintinweb-pi-subagents`.

## Sources & References

- Package repo: <https://github.com/tintinweb/pi-subagents>
- Package README install command: `pi install npm:@tintinweb/pi-subagents`
- NPM package: <https://www.npmjs.com/package/@tintinweb/pi-subagents>
- Pi package docs: `/home/scowalt/.bun/install/global/node_modules/@mariozechner/pi-coding-agent/docs/packages.md`
- Pi settings docs: `/home/scowalt/.bun/install/global/node_modules/@mariozechner/pi-coding-agent/docs/settings.md`
- Existing Pi setup functions: `mac.sh`, `ubuntu.sh`, `wsl.sh`, `pi.sh`, `omarchy.sh`, `bazzite.sh`, `win.ps1`
- Dotfiles Pi settings template: `/home/scowalt/Code/dotfiles/private_dot_pi/agent/private_settings.json.tmpl`
