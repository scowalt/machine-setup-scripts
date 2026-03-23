---
title: "feat: Replace fnm and pyenv with mise across all setup scripts"
type: feat
status: completed
date: 2026-03-23
---

# Replace fnm and pyenv with mise across all setup scripts

## Overview

Replace fnm (Node.js) and pyenv (Python) with mise as the single runtime version manager across all 7 setup scripts (mac.sh, ubuntu.sh, wsl.sh, pi.sh, omarchy.sh, bazzite.sh, win.ps1) and the chezmoi-managed fish shell configuration. The setup scripts will only install the mise binary — each project's `.mise.toml` handles which runtimes and versions to install on first use.

## Problem Frame

The current setup scripts install and configure two separate version managers (fnm, pyenv) with platform-specific installation methods, complex initialization logic, and extensive Node.js version detection code. The mission control CLAUDE.md has already designated mise as the target runtime version manager. The fish config already has mise activation (lines 67-70 of `config.fish.tmpl`) but also retains fnm and pyenv initialization blocks. Consolidating to mise simplifies scripts, reduces maintenance surface, and aligns with the shared infrastructure standard.

## Requirements Trace

- R1. mise must be installed idempotently on all 7 platforms (macOS, Ubuntu, WSL, Raspberry Pi, Omarchy/Arch, Bazzite, Windows)
- R2. fnm and pyenv installation functions and references must be removed from all setup scripts
- R3. setup_nodejs() functions must be removed (mise + .mise.toml handles runtime installation per-project)
- R4. Fish shell config must activate mise and remove fnm/pyenv initialization blocks
- R5. The chezmoi `.chezmoiremove` file must be updated to clean up fnm/pyenv conf.d artifacts
- R6. Windows script must replace fnm WinGet package and pyenv-win git clone with mise WinGet package
- R7. Script version numbers must be incremented in all modified scripts
- R8. Shell configuration remains chezmoi-managed — setup scripts install tools only

## Scope Boundaries

- **Not in scope**: Installing any default runtimes via mise (no `mise install node@lts` etc.) — projects handle this via `.mise.toml`
- **Not in scope**: Creating `.mise.toml` files for any project
- **Not in scope**: Removing fnm/pyenv from machines that have already run the old scripts (users migrate manually)
- **Not in scope**: Bash/zsh shell configuration changes (only fish is actively used per dotfiles)
- **Not in scope**: Cleaning up CLAUDE.md sections about fnm/pyenv — separate documentation effort

## Context & Research

### Relevant Code and Patterns

**Current fnm installation methods by platform:**
| Script | Method | Location |
|--------|--------|----------|
| mac.sh | Homebrew (`brew install fnm`) | Line 342 in core packages array |
| ubuntu.sh | curl installer (`fnm.vercel.app/install --skip-shell`) | `install_fnm()` at line 1140 |
| wsl.sh | Homebrew (`brew install fnm`) | `install_fnm()` at line 782 |
| pi.sh | curl installer | `install_fnm()` at line 1088 |
| omarchy.sh | yay AUR (`fnm-bin`) | `install_dev_tools_aur()` at line 886 |
| bazzite.sh | curl installer | `install_fnm()` at line 733 |
| win.ps1 | WinGet (`Schniz.fnm`) | Line 7 in wingetPackages array |

**Current pyenv installation methods by platform:**
| Script | Method |
|--------|--------|
| mac.sh | Homebrew (`brew install pyenv`) in core packages array |
| ubuntu.sh | curl installer (`pyenv-installer`) at line 1555 |
| wsl.sh | Homebrew at line 1028 |
| pi.sh | curl installer at line 1566 |
| omarchy.sh | curl installer at line 1389 |
| bazzite.sh | curl installer at line 994 |
| win.ps1 | git clone pyenv-win at line 319 |

**Chezmoi fish config (`dot_config/private_fish/config.fish.tmpl`):**
- Lines 67-70: mise activation already present (`mise activate fish | source`)
- Lines 72-86: fnm initialization (PATH setup + `fnm env --shell fish | source`)
- Lines 88-92: pyenv PATH setup (`PYENV_ROOT`, `$PYENV_ROOT/bin` to PATH)
- Lines 106-109: pyenv interactive init (`pyenv init - | source`)

**`.chezmoiremove`:** Already removes `fnm.fish` and `pyenv.fish` from `conf.d/`

### mise Installation Methods (from research)

| Script | Recommended method | Package ID / URL |
|--------|-------------------|------------------|
| mac.sh | `brew install mise` | Homebrew formula |
| ubuntu.sh | `curl https://mise.run \| sh` | Installs to `~/.local/bin/mise` |
| wsl.sh | `curl https://mise.run \| sh` | Same as ubuntu |
| pi.sh | `curl https://mise.run \| sh` | ARM auto-detected |
| omarchy.sh | `sudo pacman -S mise` | Official Arch repos |
| bazzite.sh | `brew install mise` | Homebrew (not rpm-ostree) |
| win.ps1 | `winget install -e --id jdx.mise` | WinGet package `jdx.mise` |

**Key mise facts:**
- `curl https://mise.run | sh` does NOT modify shell config (no `--skip-shell` needed)
- Fish activation: `mise activate fish | source` (already in config.fish.tmpl)
- mise reads `.node-version`, `.python-version`, `.nvmrc` for backward compatibility
- The base installer auto-detects ARM architecture for Raspberry Pi

### Existing Patterns to Follow

- Idempotency: `if command -v mise &> /dev/null; then print_debug "already installed"; return; fi`
- curl|bash safety: scripts already handle stdin redirection patterns
- Homebrew scripts (mac.sh, wsl.sh, bazzite.sh): add to package arrays rather than separate install functions
- Non-Homebrew scripts: standalone `install_mise()` function following `install_fnm()` pattern

## Key Technical Decisions

- **Use platform-native package managers where available**: Homebrew on mac/wsl/bazzite, pacman on omarchy, WinGet on Windows. curl installer only for ubuntu/pi where no native package is available. This matches existing patterns in each script.
- **No default runtime installation**: Unlike current scripts which install Node.js LTS, mise will be installed without any `mise install` or `mise use --global` calls. Projects own their runtime versions via `.mise.toml`.
- **Remove setup_nodejs() entirely**: The complex fnm version detection, LTS installation, and default-setting logic all becomes unnecessary. Tools like `npm` used later in setup scripts (e.g., for Claude Code installation) need to be handled — either by installing Claude Code via a different method or by noting the dependency.
- **Keep mise activation in non-interactive section of fish config**: This matches the current fnm placement and ensures mise-managed tools are available in non-interactive shells.

## Open Questions

### Resolved During Planning

- **Q: Should we use the apt repo or curl installer for Ubuntu?** Resolution: Use curl installer (`mise.run`) for simplicity and consistency with pi.sh. The apt repo requires sudo and GPG key management, adding complexity for little benefit since mise self-updates.
- **Q: Does omarchy need AUR or is mise in official repos?** Resolution: mise is in the official Arch repositories (`pacman -S mise`), no AUR needed.
- **Q: What about tools that depend on npm during setup (e.g., Claude Code)?** Resolution: Claude Code now has a native installer (`~/.claude/bin`), and the fish config already adds it to PATH (line 62-65). The setup scripts should already be using the native installer. If any script still installs Claude Code via npm, that call should be updated to use the native installer or be left as a manual step.

### Deferred to Implementation

- **Claude Code installation method audit**: Verify which scripts still use `npm install -g @anthropic-ai/claude-code` vs the native installer. If any still use npm, they need to be updated since npm won't be available until a project's `.mise.toml` installs Node.js.
- **Bun installation dependency**: Check if `install_bun()` functions depend on npm/Node.js being available. If so, they may need adjustment.

## Implementation Units

- [x] **Unit 1: Add mise to Homebrew-based scripts (mac.sh, wsl.sh, bazzite.sh)**

**Goal:** Replace fnm and pyenv with mise in the Homebrew package arrays and remove the dedicated fnm/pyenv installation functions.

**Requirements:** R1, R2, R3, R7

**Dependencies:** None

**Files:**
- Modify: `mac.sh`
- Modify: `wsl.sh`
- Modify: `bazzite.sh`

**Approach:**
- In `mac.sh`: Replace `"fnm"` and `"pyenv"` with `"mise"` in the core packages array (line 342). Remove `setup_nodejs()` function and its call in main. No separate install function needed since Homebrew handles it.
- In `wsl.sh`: Replace `"fnm"` and `"pyenv"` in Homebrew install calls with `"mise"`. Remove `install_fnm()`, `setup_nodejs()`, `install_pyenv()` functions and their calls in main.
- In `bazzite.sh`: Replace the curl-based `install_fnm()` with adding `"mise"` to brew packages (bazzite uses Homebrew). Remove `install_fnm()`, `setup_nodejs()`, `install_pyenv()` functions and their calls in main.
- Increment version numbers in all three scripts.

**Patterns to follow:**
- Existing Homebrew package array pattern in `mac.sh` line 342
- Existing `print_debug "already installed"` pattern for idempotency

**Test scenarios:**
- Running each script on a fresh machine installs mise via Homebrew
- Running each script on a machine with mise already installed skips installation
- fnm and pyenv are no longer installed on new machines
- Version numbers are incremented

**Verification:**
- `command -v mise` succeeds after script runs
- `command -v fnm` is not installed by the script (may still be present from prior runs)
- No references to fnm or pyenv remain in modified scripts (except removal/migration comments if needed)

---

- [x] **Unit 2: Add mise to curl-installer scripts (ubuntu.sh, pi.sh)**

**Goal:** Replace fnm and pyenv installation with mise using the curl installer for platforms without a native package manager option.

**Requirements:** R1, R2, R3, R7

**Dependencies:** None (parallel with Unit 1)

**Files:**
- Modify: `ubuntu.sh`
- Modify: `pi.sh`

**Approach:**
- Add `install_mise()` function following existing idempotent pattern: check `command -v mise`, if not found install via `curl https://mise.run | sh`. The installer places the binary at `~/.local/bin/mise` which is already on PATH via the fish config.
- Remove `install_fnm()`, `setup_nodejs()`, `install_pyenv()` functions.
- Update main() to call `install_mise` instead of the removed functions.
- For pi.sh: note that ARM architecture is auto-detected by the mise installer. No special handling needed (unlike fnm which required platform-specific path).
- Increment version numbers.

**Patterns to follow:**
- Existing curl installer pattern used by fnm: download script to variable, pipe to bash
- stdin safety: the mise installer (`curl https://mise.run | sh`) doesn't read stdin, but follow the established pattern of `< /dev/null` if piping

**Test scenarios:**
- Fresh Ubuntu/Pi machine gets mise installed to `~/.local/bin/mise`
- ARM detection works correctly on Raspberry Pi
- Idempotent re-run skips installation
- No fnm/pyenv artifacts created

**Verification:**
- `~/.local/bin/mise` binary exists after script runs
- `mise --version` succeeds
- No `~/.local/share/fnm` or `~/.pyenv` directories created by the script

---

- [x] **Unit 3: Add mise to Arch/Omarchy script (omarchy.sh)**

**Goal:** Replace fnm (AUR) and pyenv (curl installer) with mise from official Arch repositories.

**Requirements:** R1, R2, R3, R7

**Dependencies:** None (parallel with Units 1-2)

**Files:**
- Modify: `omarchy.sh`

**Approach:**
- Add `"mise"` to the core pacman packages array in `install_core_packages()` (line ~705). mise is in the official Arch repos.
- Remove `"fnm-bin"` from the AUR packages array in `install_dev_tools_aur()` (line 886) and its special-case check (lines 892-897).
- Remove `setup_nodejs()` function (line 1069) and `install_pyenv()` function (line 1389).
- Remove their calls in main() (lines 1628, 1636).
- Increment version number.

**Patterns to follow:**
- Existing pacman package array in `install_core_packages()`
- Existing AUR package removal pattern

**Test scenarios:**
- mise installed via pacman on fresh Arch system
- fnm-bin no longer in AUR install list
- No pyenv curl installer runs

**Verification:**
- `pacman -Qi mise` shows mise as installed
- No fnm or pyenv references remain in the script

---

- [x] **Unit 4: Add mise to Windows script (win.ps1)**

**Goal:** Replace fnm (WinGet) and pyenv-win (git clone) with mise (WinGet) in the Windows setup script.

**Requirements:** R1, R2, R3, R6, R7

**Dependencies:** None (parallel with Units 1-3)

**Files:**
- Modify: `win.ps1`

**Approach:**
- Replace `"Schniz.fnm"` with `"jdx.mise"` in the `$wingetPackages` array (line 7).
- Remove the `Install-PyenvWin` function (line ~319) and its call.
- Remove the Node.js setup function that uses fnm (line ~462) and its call.
- Increment version number.

**Patterns to follow:**
- Existing WinGet package array pattern
- Existing `Write-Debug` idempotency pattern

**Test scenarios:**
- WinGet installs mise instead of fnm
- pyenv-win git clone no longer runs
- Node.js setup function no longer called

**Verification:**
- `winget list --id jdx.mise` shows mise installed
- No `Schniz.fnm` in WinGet package list
- No `$env:USERPROFILE\.pyenv` directory creation by script

---

- [x] **Unit 5: Update chezmoi fish config and .chezmoiremove**

**Goal:** Remove fnm and pyenv initialization from fish shell config, keeping only the existing mise activation. Update `.chezmoiremove` if needed.

**Requirements:** R4, R5, R8

**Dependencies:** None (parallel with Units 1-4, but should be applied in coordination)

**Files:**
- Modify: `../dotfiles/dot_config/private_fish/config.fish.tmpl` (chezmoi-managed, separate repo)
- Modify: `../dotfiles/.chezmoiremove`

**Approach:**
- Remove lines 72-86 (fnm initialization block: FNM_PATH setup, manual install locations, Homebrew fallback, `fnm env` source).
- Remove lines 88-92 (pyenv non-interactive setup: PYENV_ROOT, PATH addition).
- Remove lines 106-109 (pyenv interactive init: `pyenv init - | source`).
- Keep lines 67-70 (existing mise activation) unchanged.
- `.chezmoiremove` already has `fnm.fish` and `pyenv.fish` entries — verify no additional cleanup needed.

**Patterns to follow:**
- Existing mise activation block (lines 67-70) serves as the template
- Keep the comment style consistent with surrounding blocks

**Test scenarios:**
- `chezmoi diff` shows only removal of fnm/pyenv blocks
- `chezmoi apply` removes fnm/pyenv init from deployed config
- mise activation remains functional
- Fish shell starts without errors after applying

**Verification:**
- `config.fish.tmpl` contains no references to fnm or pyenv
- mise activation block is intact
- Fish shell starts cleanly and `mise` command is available

---

- [x] **Unit 6: Audit and update npm-dependent installations**

**Goal:** Ensure no setup script functions depend on npm/Node.js being available at install time, since mise won't provide a global Node.js by default.

**Requirements:** R3

**Dependencies:** Units 1-4 (need to know what's been removed)

**Files:**
- Audit: all setup scripts for `npm install`, `npx`, `node ` commands
- Potentially modify: any scripts still using npm for Claude Code installation

**Approach:**
- Grep all scripts for `npm`, `npx`, `node ` to find dependencies.
- Claude Code should be using the native installer (already in most scripts). Verify and update any that still use `npm install -g @anthropic-ai/claude-code`.
- Check `install_bun()` functions — Bun has its own installer and doesn't depend on Node.js.
- For any remaining npm dependencies, either find alternative installation methods or document them as requiring `mise install node` first.

**Test scenarios:**
- No script function fails due to missing `npm` or `node` commands
- Claude Code installation works via native installer

**Verification:**
- `grep -r "npm install\|npx " *.sh *.ps1` returns no results in critical installation paths (non-commented, non-documentation lines)

## System-Wide Impact

- **Interaction graph:** Chezmoi dotfiles and setup scripts are tightly coupled — the scripts install mise, chezmoi deploys the shell config that activates it. Both changes should land together or in quick succession to avoid a window where mise is installed but not activated (or vice versa).
- **Error propagation:** If mise installation fails, no runtime version managers will be available. This is the same risk as the current fnm/pyenv approach but now consolidated into a single failure point.
- **State lifecycle risks:** Existing machines with fnm/pyenv installed will retain those tools. The fish config change removes their activation, so they'll become inert but present on disk. Users should manually clean up `~/.local/share/fnm`, `~/.pyenv`, etc.
- **API surface parity:** All 7 scripts must be updated together to maintain consistency across platforms.
- **Integration coverage:** Each platform should be tested end-to-end on a fresh machine (or VM) to verify mise installation and that no npm-dependent steps break.

## Risks & Dependencies

- **Risk: npm-dependent install steps break silently.** Some scripts may use npm for tool installation (e.g., Claude Code). Without a global Node.js, these will fail. Mitigation: Unit 6 audits for this explicitly.
- **Risk: Existing machines lose fnm/pyenv activation.** When chezmoi applies the updated fish config, fnm and pyenv stop being initialized. If a user hasn't yet set up `.mise.toml` in their projects, they temporarily lose Node.js/Python access. Mitigation: Document in commit message; mise reads `.node-version` and `.python-version` files for backward compatibility.
- **Risk: Raspberry Pi ARM compatibility.** The mise curl installer claims ARM auto-detection, but this should be verified on actual Pi hardware. Mitigation: Test on Pi before merging, or add a fallback error message.
- **Dependency: Chezmoi dotfiles repo.** The fish config changes are in a separate repository. Both repos should be updated in coordination.

## Sources & References

- Related code: `dot_config/private_fish/config.fish.tmpl` (chezmoi dotfiles repo)
- Related code: `.chezmoiremove` (chezmoi dotfiles repo)
- External docs: https://mise.jdx.dev/installing-mise.html
- External docs: https://mise.jdx.dev/getting-started.html
- Mission control standard: `~/Code/CLAUDE.md` — "Runtime version management: mise"
