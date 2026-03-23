---
title: "fix: Skip AUR package installation when user lacks sudo access"
type: fix
status: completed
date: 2026-03-23
---

# fix: Skip AUR package installation when user lacks sudo access

## Overview

Add a `can_sudo` guard to `install_dev_tools_aur()` in `omarchy.sh` so that AUR package installation (including Doppler CLI) is skipped for non-sudo users, matching the pattern used everywhere else in the script.

## Problem Frame

When `omarchy.sh` runs for a user without sudo access, other sudo-requiring operations (fail2ban, system updates, Omarchy installation) are correctly skipped. However, `install_dev_tools_aur()` has no such guard, causing `yay -S` to hang at a `[sudo] password` prompt — or fail — because `yay` needs sudo for the final `pacman -U` step.

The apt-based scripts (ubuntu.sh, wsl.sh, pi.sh) already have `can_sudo` guards in their `install_doppler()` functions. Omarchy needs the same treatment at the AUR install level.

## Requirements Trace

- R1. AUR package installation must not attempt `yay -S` when the user lacks sudo access
- R2. Follow the existing `can_sudo` guard pattern used throughout `omarchy.sh`
- R3. Bump the script version number per repository conventions

## Scope Boundaries

- Only `omarchy.sh` is affected — the apt-based scripts already handle this correctly
- This does not change which packages are installed; it only gates the install on sudo availability

## Context & Research

### Relevant Code and Patterns

- `omarchy.sh:723-726` — `install_core_packages()` already guards pacman installs with `can_sudo`
- `omarchy.sh:677-678` — `install_fail2ban()` uses `can_sudo` guard
- `ubuntu.sh:1296-1298` — `install_doppler()` uses `can_sudo` guard (pattern to match)

## Key Technical Decisions

- **Guard the entire `install_dev_tools_aur()` function, not just doppler**: `yay -S` requires sudo for all package installs, so there's no point filtering individual packages. This is simpler and correct.

## Open Questions

### Resolved During Planning

- **Should we split doppler out of the AUR batch?** No — the issue affects all AUR installs via yay, not just doppler. A single guard at the function level is cleaner.

### Deferred to Implementation

- None

## Implementation Units

- [x] **Unit 1: Add can_sudo guard to install_dev_tools_aur()**

**Goal:** Prevent AUR package installation from hanging/failing when the user lacks sudo access

**Requirements:** R1, R2, R3

**Dependencies:** None

**Files:**
- Modify: `omarchy.sh`

**Approach:**
- Add `can_sudo` check at the top of `install_dev_tools_aur()` (after the print_message), returning early with a warning message
- Follow the exact pattern from `install_core_packages()` at line 723: `if ! can_sudo; then print_warning "..."; return; fi`
- Increment version number from 99 to 100 and update "Last changed" description

**Patterns to follow:**
- `omarchy.sh:723-726` — existing `can_sudo` guard in `install_core_packages()`
- `omarchy.sh:677-678` — existing `can_sudo` guard in `install_fail2ban()`

**Test scenarios:**
- User without sudo: function prints warning and returns without attempting yay
- User with sudo: function behaves exactly as before (no change to happy path)
- Packages already installed: existing `pacman -Qi` check still runs before the sudo guard matters (the check loop runs first, and if nothing needs installing, no yay call happens regardless)

**Verification:**
- Running `omarchy.sh` without sudo access no longer hangs at a password prompt during AUR installation
- The warning message is visible in output

## Risks & Dependencies

- None — this is a minimal, additive guard following an established pattern
