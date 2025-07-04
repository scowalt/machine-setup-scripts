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
- **Dotfile Management**: Shell configurations are managed by chezmoi - scripts should only install tools, not configure shells

### Common Tools Installed

- Version Control: git, gh (GitHub CLI), git-town
- Shell: fish (with completions), tmux
- Node.js: fnm (Fast Node Manager)
- Python: pyenv (Python version management)
- Security: 1Password CLI, Tailscale, Infisical
- Dotfiles: Chezmoi (with auto-sync)
- Terminal: Starship prompt
- CI/CD: act (local GitHub Actions)

### Important Notes

- Scripts require SSH keys to be registered with GitHub before running
- Ubuntu script enforces creation of 'scowalt' user
- All scripts configure fish as the default shell
- Chezmoi manages dotfiles with automatic git operations
- **IMPORTANT**: Do not add shell configuration (bashrc, zshrc, fish config, PowerShell profiles) in setup scripts - these are managed by chezmoi and will be overridden

## Nerd Font Symbols

### What are Nerd Fonts?

Nerd Fonts are patched fonts that include thousands of icons from popular icon sets (Font Awesome, Devicons, Octicons, etc.). These scripts use Nerd Font symbols extensively for visual feedback in terminal output.

### Working with Nerd Font Symbols as an LLM

**IMPORTANT UPDATE**: Claude Code CAN successfully edit files containing Nerd Font symbols and preserve them correctly. The symbols are essential to the visual design.

#### How to handle them:

1. **When editing**: Nerd Font symbols will be preserved automatically when using the Edit tool
2. **To add new ones**: Use Unicode characters directly in your edits:
   - Arrow: → (U+2192)
   - Checkmark: ✓ (U+2713)
   - Warning: ⚠ (U+26A0)
   - Cross/Error: ✗ (U+2717)
   - Sparkles: ✨ (U+2728)
   - Apple: 🍎 (U+1F34E)
   - Penguin: 🐧 (U+1F427)
   - Strawberry: 🍓 (U+1F353)
   - Window: 🪟 (U+1FA9F)

#### Common symbols used in these scripts:

- Success indicators: ✓ (checkmark)
- Error indicators: ✗ (cross)
- Warning indicators: ⚠ (warning sign)
- Action indicators: → (arrow)
- Special icons: 🍎 (Apple emoji for macOS)

#### Example:
```bash
print_success() { printf "${GREEN}✓ %s${NC}\n" "$1"; }  # The ✓ is a Nerd Font symbol
```

**Remember**: These symbols are part of the user experience design. They make terminal output more readable and visually appealing.

## Logging Conventions

### Print Functions (Bash Scripts)

All bash scripts use consistent logging functions with Nerd Font symbols:

```bash
print_section()  # Bold section headers with === borders
print_message()  # Cyan messages with → arrow
print_success()  # Green messages with ✓ checkmark  
print_warning()  # Yellow messages with ⚠ warning sign
print_error()    # Red messages with ✗ cross
print_debug()    # Gray messages with subtle indent
```

### When to Use Each Level

- **print_section**: Major stages of the setup process
- **print_message**: General information and actions being taken
- **print_success**: Successful completions
- **print_warning**: ONLY for actual warnings (not for "already installed")
- **print_error**: Failures that stop execution
- **print_debug**: Informational messages like "already installed" or "already configured"

### PowerShell Equivalents

```powershell
Write-Section   # White on dark blue background
Write-Message   # Cyan with arrow symbol
Write-Success   # Green with checkmark
Write-Warning   # Yellow with warning icon
Write-Error     # Red with cross icon
Write-Debug     # Dark gray with indent
```

### Visual Structure

Scripts are organized into clear sections with:
1. Emoji header showing platform (🍎 macOS, 🐧 Linux, 🍓 Pi, 🪟 Windows)
2. Version and last change info in gray
3. Logical sections for different setup stages
4. Sparkle emoji (✨) for completion message
