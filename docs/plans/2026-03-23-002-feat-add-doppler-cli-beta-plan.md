---
title: "feat: Add Doppler CLI to all machine setup scripts"
type: feat
status: completed
date: 2026-03-23
---

# feat: Add Doppler CLI to all machine setup scripts

## Overview

Add Doppler CLI installation to all seven setup scripts (mac.sh, ubuntu.sh, wsl.sh, pi.sh, omarchy.sh, bazzite.sh, win.ps1) so every machine in the fleet has access to Doppler for secrets management. Doppler is the project-wide standard for secrets (per the Mission Control CLAUDE.md).

## Problem Frame

Doppler is the designated secrets management tool across all projects, but none of the setup scripts install it. Developers must install it manually on each new machine, breaking the "run one script and you're ready" promise.

## Requirements Trace

- R1. Doppler CLI (`doppler` binary) is installed on every supported platform after running the respective setup script
- R2. Installation is idempotent — re-running the script does not reinstall or error
- R3. Follows existing installation patterns per platform (Homebrew array, apt custom repo function, AUR array, WinGet array)
- R4. Placed in the Security Tools section alongside 1Password CLI and Tailscale
- R5. Version numbers incremented on all modified scripts

## Scope Boundaries

- No shell configuration or Doppler project setup — scripts install the binary only
- No `doppler login` or token setup — that's a user-specific action done post-install
- No chezmoi changes needed

## Context & Research

### Relevant Code and Patterns

**Homebrew scripts (mac.sh, bazzite.sh):** Add `dopplerhq/cli/doppler` to the `packages` array in `install_core_packages()`. The Doppler Homebrew formula lives in a custom tap (`dopplerhq/cli`).

- `mac.sh:342` — packages array
- `bazzite.sh:249` — packages array

**apt-based scripts (ubuntu.sh, wsl.sh, pi.sh):** Create a dedicated `install_doppler()` function following the same pattern as `install_1password_cli()` — add GPG key, configure apt source, install package. Doppler provides an official apt repo with GPG signing.

- `ubuntu.sh:1156` — `install_1password_cli()` reference pattern
- `ubuntu.sh:1703-1705` — Security Tools section call site
- `wsl.sh:1223-1225` — Security Tools section call site
- `pi.sh:1629` — Development Tools section (pi.sh has no Security Tools section; 1Password and Tailscale live in Development Tools and Network & SSH respectively)

**pacman/AUR script (omarchy.sh):** Add `doppler-cli-bin` to the `aur_packages` array in `install_dev_tools_aur()`.

- `omarchy.sh:886` — AUR packages array

**WinGet script (win.ps1):** Add `Doppler.doppler` to the `$wingetPackages` array.

- `win.ps1:3` — WinGet packages array

### Institutional Learnings

- No `docs/solutions/` directory exists; CLAUDE.md documents all relevant patterns
- Tools with custom apt repos require dedicated install functions (not the core packages array)
- Homebrew tools with taps use `tap/formula` syntax in the packages array

## Key Technical Decisions

- **Homebrew tap syntax**: Use `dopplerhq/cli/doppler` which auto-taps `dopplerhq/cli` — no separate `brew tap` needed
- **apt installation method**: Use Doppler's official install script (`curl -sLf --retry 3 --tlsv1.2 --proto "=https" 'https://packages.doppler.com/public/cli/gpg.DE2A7741A397C129.key'` + apt source) following the GPG key + sources.list pattern used for 1Password
- **pi.sh placement**: Add `install_doppler` call in the "Development Tools" section alongside `install_1password_cli` since pi.sh doesn't have a dedicated Security Tools section
- **WinGet package ID**: `Doppler.doppler` (the official WinGet ID)
- **AUR package**: `doppler-cli-bin` (prebuilt binary from AUR)

## Open Questions

### Resolved During Planning

- **Where to place in script sections?** Security Tools, per user decision. Exception: pi.sh uses Development Tools (where 1Password already lives).
- **Which Homebrew formula?** `dopplerhq/cli/doppler` — the official tap-qualified name.

### Deferred to Implementation

- **Exact GPG key URL validity**: The Doppler apt repo key URL should be verified at implementation time. If it has changed, check Doppler's current install docs.

## Implementation Units

- [ ] **Unit 1: Add Doppler to Homebrew-based scripts (mac.sh, bazzite.sh)**

**Goal:** Install Doppler via Homebrew on macOS and Bazzite

**Requirements:** R1, R2, R3, R5

**Dependencies:** None

**Files:**
- Modify: `mac.sh`
- Modify: `bazzite.sh`

**Approach:**
- Add `"dopplerhq/cli/doppler"` to the `packages` array in `install_core_packages()` in both scripts
- Place it near other security tools (`1password-cli`, `tailscale`) in the array for logical grouping
- Increment version numbers and update "Last changed" descriptions

**Patterns to follow:**
- Existing tap-qualified package: `tursodatabase/tap/turso` in both scripts

**Test scenarios:**
- Fresh install: `doppler` command available after script run
- Re-run: no reinstallation, no errors

**Verification:**
- `command -v doppler` succeeds after running either script
- `brew list dopplerhq/cli/doppler` shows installed

- [ ] **Unit 2: Add Doppler install function to apt-based scripts (ubuntu.sh, wsl.sh, pi.sh)**

**Goal:** Install Doppler via official apt repository on Ubuntu, WSL, and Raspberry Pi

**Requirements:** R1, R2, R3, R4, R5

**Dependencies:** None

**Files:**
- Modify: `ubuntu.sh`
- Modify: `wsl.sh`
- Modify: `pi.sh`

**Approach:**
- Create `install_doppler()` function following the `install_1password_cli()` pattern: check `command -v doppler`, check `can_sudo`, add GPG key to `/usr/share/keyrings/`, add apt source, install `doppler` package
- Add `install_doppler` call in the Security Tools section for ubuntu.sh and wsl.sh (after `install_tailscale`)
- Add `install_doppler` call in the Development Tools section for pi.sh (near `install_1password_cli`)
- Increment version numbers and update "Last changed" descriptions
- The install function should be defined once per script near the other security tool install functions

**Patterns to follow:**
- `install_1password_cli()` in `ubuntu.sh:1156` — GPG key + apt source + install pattern
- `install_tailscale()` in `ubuntu.sh:1206` — alternative curl-script pattern (but GPG+apt is preferred for Doppler since they provide a proper repo)

**Test scenarios:**
- Fresh install: `doppler` available after script run
- Re-run: `print_debug "Doppler CLI already installed."` shown, no reinstall
- No sudo access: warning printed, no failure
- ARM architecture (pi.sh): Doppler provides ARM packages in their apt repo

**Verification:**
- `command -v doppler` succeeds
- `dpkg -s doppler` shows installed
- Idempotent re-run produces debug message only

- [ ] **Unit 3: Add Doppler to AUR packages (omarchy.sh)**

**Goal:** Install Doppler via AUR on Arch/Omarchy

**Requirements:** R1, R2, R3, R5

**Dependencies:** None

**Files:**
- Modify: `omarchy.sh`

**Approach:**
- Add `"doppler-cli-bin"` to the `aur_packages` array in `install_dev_tools_aur()`
- Increment version number and update "Last changed" description

**Patterns to follow:**
- Existing AUR packages at `omarchy.sh:886`

**Test scenarios:**
- Fresh install: `doppler` available after script run
- Re-run: already-installed check passes

**Verification:**
- `command -v doppler` succeeds
- `yay -Qi doppler-cli-bin` shows installed

- [ ] **Unit 4: Add Doppler to WinGet packages (win.ps1)**

**Goal:** Install Doppler via WinGet on Windows

**Requirements:** R1, R2, R3, R5

**Dependencies:** None

**Files:**
- Modify: `win.ps1`

**Approach:**
- Add `"Doppler.doppler"` to the `$wingetPackages` array
- Increment version number and update "Last changed" description

**Patterns to follow:**
- Existing WinGet packages at `win.ps1:3`

**Test scenarios:**
- Fresh install: `doppler` command available
- Re-run: WinGet reports already installed

**Verification:**
- `doppler --version` succeeds in PowerShell
- `winget list Doppler.doppler` shows installed

## System-Wide Impact

- **Interaction graph:** No callbacks or middleware affected — Doppler is a standalone CLI binary
- **Error propagation:** Failed installation logs a warning/error but does not halt script execution (consistent with all other tool installations)
- **State lifecycle risks:** None — no persistent state created beyond the package installation
- **API surface parity:** All seven scripts get the same tool, maintaining fleet consistency

## Risks & Dependencies

- **Doppler apt repo availability**: If the GPG key URL or repo structure changes, the apt-based install function will fail. Mitigation: use the official documented URLs and verify at implementation time.
- **AUR package name**: `doppler-cli-bin` is community-maintained. If renamed or removed, omarchy.sh installation will fail silently (existing pattern for AUR packages).
- **WinGet package ID**: Verify `Doppler.doppler` is the correct ID at implementation time via `winget search doppler`.

## Sources & References

- Doppler CLI install docs: https://docs.doppler.com/docs/install-cli
- Existing pattern: `install_1password_cli()` in ubuntu.sh
- Mission Control CLAUDE.md: Doppler listed as shared infrastructure for secrets management
