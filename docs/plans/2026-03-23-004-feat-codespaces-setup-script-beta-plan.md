---
title: "feat: Add GitHub Codespaces setup script"
type: feat
status: completed
date: 2026-03-23
---

# feat: Add GitHub Codespaces setup script

## Overview

Create a `codespaces.sh` script that reuses functions from `ubuntu.sh` to set up a consistent development environment in GitHub Codespaces containers. This is the first script in the repo to source another script, introducing a lightweight function-reuse pattern.

## Problem Frame

GitHub Codespaces provides ephemeral Ubuntu 24.04 containers with a pre-configured user and `GITHUB_TOKEN`. The user wants the same dev tooling (fish, starship, mise, chezmoi dotfiles, AI CLIs, etc.) available in Codespaces without maintaining a separate copy of all installation logic. The existing `ubuntu.sh` has all the right functions but also includes server hardening, SSH setup, VPS detection, and systemd services that don't apply to Codespaces.

## Requirements Trace

- R1. `codespaces.sh` installs the dev tool subset appropriate for ephemeral Codespaces containers
- R2. Reuse `ubuntu.sh` functions via `source` rather than duplicating code
- R3. Skip server/infrastructure concerns: SSH server, SSH keys, fail2ban, unattended-upgrades, tailscale, DNS64, systemd services, 1Password CLI, Doppler CLI
- R4. Skip iterm2 shell integration (macOS-specific)
- R5. Bridge `GITHUB_TOKEN` (Codespaces-provided) to `GH_TOKEN` so chezmoi HTTPS clone works
- R6. Codespaces user is `codespace`, not `scowalt` — `is_main_user()` returns false, which is fine
- R7. Follow existing script patterns: version header, color output, section structure, idempotency
- R8. Update README.md and CLAUDE.md to document the new script
- R9. Guard `ubuntu.sh`'s `main "$@"` so sourcing it doesn't execute the full Ubuntu setup

## Scope Boundaries

- No changes to chezmoi templates (Codespaces-aware conditionals like `{{ if env "CODESPACES" }}` are a separate dotfiles-repo task)
- No `install.sh` in the dotfiles repo (that's a separate change the user will do in their dotfiles repo)
- No opentofu, cloudflared, turso, or act — these are project-specific or infrastructure tools
- No Codex CLI or Codex compound skills — user only uses Codex on omarchy

## Context & Research

### Relevant Code and Patterns

- `ubuntu.sh` — source of all reusable functions; `main()` at line 1653, `main "$@"` at line 1782
- All scripts follow identical structure: color vars → print functions → helper functions → tool functions → `main()` → `main "$@"`
- No script currently sources another — this is the first
- `check_dotfiles_access()` (line 332) checks SSH keys and `GH_TOKEN_SCOWALT` — neither available in Codespaces; needs `GITHUB_TOKEN` bridging
- `is_main_user()` checks `whoami == scowalt` — Codespaces user is `codespace`, so code-directory setup and main-user-gated features will be skipped naturally
- `can_sudo()` — Codespaces provides sudo, so apt-based installs work

### External References

- [GitHub Codespaces dotfiles docs](https://docs.github.com/en/codespaces/setting-your-user-preferences/personalizing-github-codespaces-for-your-account#dotfiles) — Codespaces clones dotfiles repo and runs `install.sh` if present; symlinks `.`-prefixed files as fallback
- Default Codespaces image: `mcr.microsoft.com/devcontainers/universal:noble` (Ubuntu 24.04)
- Codespaces environment variables: `CODESPACES=true`, `GITHUB_TOKEN` pre-set, `GITHUB_USER` set to GitHub username

## Key Technical Decisions

- **Source guard pattern**: Modify `ubuntu.sh` to wrap `main "$@"` in `[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"`. This is a one-line, zero-risk change — `BASH_SOURCE[0]` equals `$0` when run directly, differs when sourced. All other scripts can adopt this pattern later but don't need to now.
- **Token bridging**: Export `GH_TOKEN="${GITHUB_TOKEN}"` before calling chezmoi functions. This makes `check_dotfiles_access()` succeed via the `GH_TOKEN_SCOWALT` / `GH_TOKEN` path without any changes to ubuntu.sh's access-checking logic.
- **Separate main function**: `codespaces.sh` defines its own `main()` that calls the specific ubuntu.sh functions it needs. Since it sources ubuntu.sh after the guard change, ubuntu.sh's `main()` becomes just another available function (not auto-called).
- **No Codex CLI/skills in Codespaces**: User only uses Codex on omarchy. Codespaces gets Claude Code, Gemini CLI, but not Codex.
- **Include update_and_install_core but not update_dependencies**: Core packages (fish, git, curl, build-essential, etc.) are needed; full apt upgrade is slow and unnecessary in an ephemeral container that's already up to date.

## Open Questions

### Resolved During Planning

- **Which emoji for Codespaces?**: Use ☁️ (cloud) — fits the ephemeral cloud container concept and is standard Unicode
- **Should we skip apt update entirely?**: No — `update_and_install_core` needs apt cache to install missing packages; skip only the full `update_dependencies` (upgrade all packages)
- **Codex CLI in Codespaces?**: No — user only uses Codex on omarchy
- **Should we handle the case where ubuntu.sh can't be found at source time?**: Yes — when run via `curl | bash`, ubuntu.sh won't be adjacent. The script should detect this and curl ubuntu.sh to a temp location.

### Deferred to Implementation

- **Exact subset of core packages needed in Codespaces**: The default Codespaces image already has many packages. `update_and_install_core` is idempotent so calling it is safe even if most packages exist.
- **Whether `setup_code_directory` should run**: It's gated on `is_main_user()` which returns false for `codespace` user — may need to run it unconditionally in Codespaces if the user wants `~/Code`.

## Implementation Units

- [x] **Unit 1: Guard ubuntu.sh's main invocation for sourcing**

  **Goal:** Allow `ubuntu.sh` to be sourced by other scripts without auto-executing its `main()`.

  **Requirements:** R2, R9

  **Dependencies:** None

  **Files:**
  - Modify: `ubuntu.sh`

  **Approach:**
  - Replace `main "$@"` (line 1782) with `[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"`
  - Bump version number
  - This is the standard bash pattern for "only run main when executed directly, not when sourced"

  **Patterns to follow:**
  - Common bash library pattern: `[[ "${BASH_SOURCE[0]}" == "${0}" ]]`

  **Test scenarios:**
  - Running `./ubuntu.sh` directly still executes `main()` as before
  - Running `source ubuntu.sh` in another script does NOT execute `main()`
  - All ubuntu.sh functions are available after sourcing

  **Verification:**
  - `bash ubuntu.sh` still prints the header and runs (can abort early)
  - `bash -c 'source ubuntu.sh; type install_starship'` succeeds without running main

- [x] **Unit 2: Create codespaces.sh with sourced ubuntu.sh functions**

  **Goal:** New script that sources ubuntu.sh and calls the Codespaces-appropriate subset of functions.

  **Requirements:** R1, R2, R3, R4, R5, R6, R7

  **Dependencies:** Unit 1

  **Files:**
  - Create: `codespaces.sh`

  **Approach:**
  - Follow the same structure as other scripts: `#!/bin/bash`, color vars (inherited from source), own `main()`
  - Determine path to ubuntu.sh: if adjacent (same directory), source directly; if not (curl|bash scenario), curl it to temp file and source that
  - Bridge tokens: `export GH_TOKEN="${GITHUB_TOKEN}"` before dotfiles section
  - Own `main()` with these sections:
    - **Header**: ☁️ emoji, "GitHub Codespaces Development Environment Setup", Version 1
    - **Environment Setup**: `create_env_local`
    - **System Setup**: `fix_dpkg_and_broken_dependencies`, `update_and_install_core` (skip `update_dependencies`, `ensure_not_root`, `setup_dns64_for_ipv6_only`)
    - **Code Directory**: `setup_code_directory` called unconditionally (not gated on `is_main_user`)
    - **Development Tools**: `install_starship`, `install_lefthook`, `install_mise`, `install_uv`
    - **Shared Directories**: `setup_claude_shared_directory`
    - **Dotfiles Management**: Token bridging (`GH_TOKEN`), then `check_dotfiles_access`, credential helper bootstrap, `install_chezmoi`, `initialize_chezmoi`, `configure_chezmoi_git`, `update_chezmoi`, `chezmoi apply`
    - **Shell Configuration**: `set_fish_as_default_shell`, `install_tmux_plugins`
    - **Development Tools (AI/JS)**: `install_bun`, `install_sfw`, `install_claude_code`, `setup_rube_mcp`, `setup_compound_plugin`, `install_gemini_cli`
    - **Final**: `upgrade_npm_global_packages`, completion message
  - Skip entirely: SSH server/keys, tailscale, 1password, doppler, fail2ban, unattended-upgrades, opentofu, cloudflared, turso, act, enable_tmux_service, iterm2_shell_integration, codex CLI
  - Include the source guard on its own main: `[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"`

  **Patterns to follow:**
  - `ubuntu.sh` main() structure for section ordering and print_section usage
  - `ubuntu.sh` dotfiles section (lines 1698-1758) for the chezmoi initialization flow
  - Version header pattern from all scripts

  **Test scenarios:**
  - Script runs successfully when executed directly (with ubuntu.sh adjacent)
  - Script handles missing ubuntu.sh gracefully (curl fallback for remote execution)
  - Token bridging: `GITHUB_TOKEN` becomes available as `GH_TOKEN` for chezmoi access
  - All skipped functions (tailscale, fail2ban, etc.) are never called
  - Idempotent: running twice doesn't break anything
  - shellcheck passes

  **Verification:**
  - `shellcheck codespaces.sh` passes with no errors
  - Script sources ubuntu.sh without triggering ubuntu.sh's main
  - All included functions are called in a logical order
  - No references to skipped tools (tailscale, fail2ban, 1password, doppler, etc.)

- [x] **Unit 3: Update documentation**

  **Goal:** Document the new script in README.md and CLAUDE.md.

  **Requirements:** R8

  **Dependencies:** Unit 2

  **Files:**
  - Modify: `README.md`
  - Modify: `CLAUDE.md`

  **Approach:**
  - README.md: Add a `## GitHub Codespaces` section following the existing platform pattern. Note that this script is typically called from a dotfiles repo's `install.sh`, not via curl directly. Include both usage patterns.
  - CLAUDE.md: Add `codespaces.sh` to the "Key Scripts" list. Add a note about the source-guard pattern and that `codespaces.sh` is the first script to source another.

  **Patterns to follow:**
  - README.md existing platform sections (curl one-liner pattern)
  - CLAUDE.md "Key Scripts" bullet format

  **Test scenarios:**
  - README.md renders correctly with the new section
  - CLAUDE.md accurately describes the new script and its relationship to ubuntu.sh

  **Verification:**
  - `markdownlint README.md CLAUDE.md` passes
  - New script is documented in both files

## System-Wide Impact

- **Interaction graph:** Modifying `ubuntu.sh`'s final line affects how it's invoked. The `BASH_SOURCE` guard is a no-op when run directly, so no existing workflows break.
- **Error propagation:** If ubuntu.sh can't be sourced (file not found, curl fails), `codespaces.sh` should fail fast with a clear error message rather than silently continuing with undefined functions.
- **API surface parity:** `codespaces.sh` is intentionally a subset — no parity requirement with the full ubuntu.sh.
- **Integration coverage:** The source-guard change to ubuntu.sh should be verified to not affect direct execution on actual Ubuntu machines.

## Risks & Dependencies

- **First script to source another**: Introduces a new pattern. Low risk since the `BASH_SOURCE` guard is a well-established bash idiom, but worth noting as a precedent.
- **curl|bash sourcing**: When `codespaces.sh` is piped via curl, it needs to fetch `ubuntu.sh` separately. The script must handle this gracefully.
- **Codespaces image variation**: Enterprise Codespaces might use different base images. The script relies on apt being available (Ubuntu/Debian). Non-apt images would fail at `update_and_install_core`.
- **chezmoi template compatibility**: Chezmoi templates may produce unexpected results in the Codespaces environment (different hostname, different user). This is explicitly out of scope — dotfiles repo changes are separate.

## Sources & References

- Related code: `ubuntu.sh` (primary source of reusable functions)
- External docs: [GitHub Codespaces dotfiles integration](https://docs.github.com/en/codespaces/setting-your-user-preferences/personalizing-github-codespaces-for-your-account#dotfiles)
- External docs: [devcontainers/images universal image](https://github.com/devcontainers/images/tree/main/src/universal) — Ubuntu 24.04 Noble base
