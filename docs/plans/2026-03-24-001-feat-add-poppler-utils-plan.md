---
title: "feat: Add poppler-utils for Claude Code PDF support"
type: feat
status: completed
date: 2026-03-24
---

# feat: Add poppler-utils for Claude Code PDF support

Add poppler-utils (pdftotext, pdfinfo, etc.) to all platform setup scripts so Claude Code can read PDF files natively.

## Acceptance Criteria

- [ ] `poppler-utils` added to apt packages array in `ubuntu.sh` (`update_and_install_core()`)
- [ ] `poppler-utils` added to apt packages array in `pi.sh` (`update_and_install_core()`)
- [ ] `poppler-utils` added to apt packages array in `wsl.sh` (`update_and_install_core()`)
- [ ] `poppler` added to Homebrew packages array in `mac.sh` (`install_core_packages()`)
- [ ] `poppler` added to Homebrew packages array in `bazzite.sh` (`install_core_packages()`)
- [ ] `poppler` added to pacman packages array in `omarchy.sh` (`install_core_packages()`)
- [ ] `codespaces.sh` inherits from `ubuntu.sh` automatically -- no changes needed
- [ ] `win.ps1` skipped -- no WinGet package; WSL covers Windows via `wsl.sh`
- [ ] Version numbers incremented in all modified scripts
- [ ] Shellcheck passes on all modified scripts

## Context

Claude Code uses poppler-utils (specifically `pdftotext` and `pdfinfo`) to read PDF files. Without it, PDF reading is degraded or unavailable.

### Package Names by Platform

| Platform | Package Manager | Package Name | Script | Array Function |
|---|---|---|---|---|
| Ubuntu | apt | `poppler-utils` | `ubuntu.sh` | `update_and_install_core()` |
| Raspberry Pi | apt | `poppler-utils` | `pi.sh` | `update_and_install_core()` |
| WSL | apt | `poppler-utils` | `wsl.sh` | `update_and_install_core()` |
| Codespaces | apt (inherited) | `poppler-utils` | `codespaces.sh` | Inherited from `ubuntu.sh` |
| macOS | Homebrew | `poppler` | `mac.sh` | `install_core_packages()` |
| Bazzite | Homebrew | `poppler` | `bazzite.sh` | `install_core_packages()` |
| Arch/Omarchy | pacman | `poppler` | `omarchy.sh` | `install_core_packages()` |
| Windows | WinGet | N/A | `win.ps1` | Skipped -- no package available |

### Implementation Pattern

This follows **Approach A** (add to core array) used by all existing utility packages. Each script's idempotent installation loop handles detection and installation automatically. No post-install configuration is needed.

### Key File Locations

- `ubuntu.sh` -- packages array in `update_and_install_core()` (~line 553)
- `pi.sh` -- packages array in `update_and_install_core()` (~line 408)
- `wsl.sh` -- packages array in `update_and_install_core()` (~line 282)
- `mac.sh` -- packages array in `install_core_packages()` (~line 342)
- `bazzite.sh` -- packages array in `install_core_packages()` (~line 249)
- `omarchy.sh` -- packages array in `install_core_packages()` (~line 709)

## MVP

Add the package name string to each script's core packages array. Example for ubuntu.sh:

### ubuntu.sh (and similarly pi.sh, wsl.sh)

```bash
local packages=(
    # ... existing packages ...
    poppler-utils
)
```

### mac.sh (and similarly bazzite.sh)

```bash
local packages=(
    # ... existing packages ...
    poppler
)
```

### omarchy.sh

```bash
local packages=(
    # ... existing packages ...
    poppler
)
```

## Sources

- Homebrew formula: `poppler` (includes CLI utils)
- Arch package: `poppler` (includes CLI utils)
- Debian/Ubuntu package: `poppler-utils` (CLI utils split from library)
