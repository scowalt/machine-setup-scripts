# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This repository contains idempotent machine setup scripts for automating the configuration of fresh development environments across different operating systems. The scripts are designed to be run multiple times safely and install a consistent set of development tools.

## Key Scripts

- **mac.sh** - macOS setup using Homebrew
- **ubuntu.sh** - Ubuntu Linux setup with user management
- **windows.ps1** - Windows setup using WinGet and PowerShell
- **wsl.sh** - Windows Subsystem for Linux setup
- **pi.sh** - Raspberry Pi specific setup with ARM optimizations

## Common Development Tasks

### Running Setup Scripts Locally

```bash
# macOS
./mac.sh

# Ubuntu/WSL/Pi
sudo ./ubuntu.sh  # or ./wsl.sh, ./pi.sh

# Windows (PowerShell as Administrator)
./windows.ps1
```

### Remote Execution

Scripts are hosted at `https://scripts.scowalt.com/setup/` for remote execution via curl/wget as documented in README.md.

### Repository Management

Use `git town` and `gh` CLI tools to manage this repository:
- `git town sync` - Keep branches in sync with main
- `git town new-pull-request` - Create feature branches and PRs
- `gh pr create` - Create pull requests via GitHub CLI
- `gh pr merge` - Merge pull requests

## Architecture and Patterns

### Script Structure

All scripts follow a consistent pattern:

1. Color function definitions (cyan/green/yellow/red output)
2. SSH key verification with GitHub
3. Tool installation checks (idempotent)
4. Package manager setup
5. Individual tool installations
6. Configuration steps (dotfiles, shell setup)

### Key Design Principles

- **Idempotency**: Scripts check for existing installations before proceeding
- **Error Handling**: Failed installations are logged but don't stop execution
- **User Feedback**: Color-coded output for status messages
- **Platform-Specific**: Each script optimized for its target OS

### Common Tools Installed

- Version Control: git, gh (GitHub CLI), git-town
- Shell: fish (with completions), tmux
- Node.js: fnm (Fast Node Manager)
- Security: 1Password CLI, Tailscale, Infisical
- Dotfiles: Chezmoi (with auto-sync)
- Terminal: Starship prompt
- CI/CD: act (local GitHub Actions)

### Important Notes

- Scripts require SSH keys to be registered with GitHub before running
- Ubuntu script enforces creation of 'scowalt' user
- All scripts configure fish as the default shell
- Chezmoi manages dotfiles with automatic git operations
