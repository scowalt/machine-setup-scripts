# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This repository contains idempotent machine setup scripts for automating the configuration of fresh development environments across different operating systems. The scripts are designed to be run multiple times safely and install a consistent set of development tools.

## Key Scripts

- **mac.sh** - macOS setup using Homebrew
- **ubuntu.sh** - Ubuntu Linux setup with user management
- **win.ps1** - Windows setup using WinGet and PowerShell
- **wsl.sh** - Windows Subsystem for Linux setup
- **pi.sh** - Raspberry Pi specific setup with ARM optimizations
- **omarchy.sh** - Arch Linux / Omarchy setup using pacman and yay

## Common Development Tasks

### Running Setup Scripts Locally

```bash
# macOS
./mac.sh

# Ubuntu/WSL/Pi/Arch
sudo ./ubuntu.sh  # or ./wsl.sh, ./pi.sh, ./omarchy.sh

# Windows (PowerShell as Administrator)
./win.ps1
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

### Tool Installation Methods

- **git-town**:
  - macOS: Installed via Homebrew
  - Linux (Ubuntu/WSL/Pi): Downloaded directly from GitHub releases (not available in apt repositories)
  - Arch/Omarchy: Installed via AUR using yay
  - Windows: Downloaded directly from GitHub releases

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

#### How to handle them

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

#### Common symbols used in these scripts

- Success indicators: ✓ (checkmark)
- Error indicators: ✗ (cross)
- Warning indicators: ⚠ (warning sign)
- Action indicators: → (arrow)
- Special icons: 🍎 (Apple emoji for macOS)

#### Example

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

## Important Implementation Notes

### Tool Installation Order

When installing tools that depend on package managers or shell configuration:

1. **Install package managers first** (Homebrew, fnm, pyenv)
2. **Apply dotfiles configuration** (chezmoi apply)
3. **Configure shell** (set default shell, install plugins)
4. **Install tools that require the configured environment** (e.g., Claude Code via npm)

This is critical because tools like fnm are initialized in shell configuration files deployed by chezmoi. Installing npm packages before the shell is configured will fail.

### Platform-Specific Considerations

#### Git-Town Binary Installation

On Linux platforms (Ubuntu, WSL, Raspberry Pi), git-town is not available in package repositories and must be downloaded directly from GitHub releases. The scripts automatically detect the system architecture and download the appropriate binary:

- `linux_intel_64` for x86_64/amd64 systems
- `linux_arm_64` for aarch64 systems (newer Raspberry Pi)
- `linux_arm_32` for armv7l/armhf systems (older Raspberry Pi)

The binary is installed to `~/.local/bin` and the PATH is updated in `~/.bashrc` if needed.

**Important**: Git-town changed their release naming convention. Old format was `git-town-linux-amd64`, new format is `git-town_linux_intel_64`.

#### Raspberry Pi Color Output

On Raspberry Pi, `printf` with format specifiers may not render ANSI color codes correctly. Use `echo -e` instead:

```bash
# May show raw escape codes on Pi
printf "\n%s🍓 Raspberry Pi Setup%s\n" "${BOLD}" "${NC}"

# Works correctly on Pi
echo -e "\n${BOLD}🍓 Raspberry Pi Setup${NC}"
```

#### Windows Unicode Support

Newer Unicode characters (like 🪟 window emoji from Unicode 13.0) may not display correctly in all Windows terminals. Use Nerd Font symbols instead:

```powershell
# May show as ?????? in some terminals
Write-Host "🪟 Windows Setup"

# More compatible approach
$windowsIcon = [char]0xf17a  # Windows logo from Nerd Fonts
Write-Host "$windowsIcon Windows Setup"
```

### Shell Integration Best Practices

When setup scripts need to use tools installed during the setup process:

1. **Source the appropriate initialization** for the current shell session
2. **Provide fallback instructions** if the tool isn't available
3. **Check tool availability** before attempting to use it

Example from Claude Code installation:

```bash
# Try to initialize fnm for current session
if [ -f ~/.config/fish/config.fish ]; then
    eval "$(fnm env --use-on-cd)"
fi

# Check if npm is now available
if ! command -v npm &> /dev/null; then
    print_warning "npm not found. Install manually with:"
    print_message "  npm install -g @anthropic-ai/claude-code"
    return
fi
```

### Node.js and fnm Management

#### Key Learnings from Implementation

1. **fnm Installation with Chezmoi**: When using fnm with chezmoi-managed dotfiles:
   - Use `--skip-shell` flag during fnm installation to prevent it from modifying shell configs
   - Let chezmoi handle all shell configuration including fnm initialization

2. **Node.js Version Detection**: fnm behavior can be tricky:
   - `fnm current` returns exit code 0 even when no version is set (outputs "none")
   - `fnm list` may show only "* system" when no Node.js versions are installed
   - Always check the actual output content, not just exit codes

3. **Parsing fnm list Output**: The output format varies:
   - With versions: `* v20.11.0 default`
   - Without versions: `* system`
   - Use regex to specifically look for version numbers: `grep -E "^[[:space:]]*\*?[[:space:]]*v[0-9]"`

4. **Automatic Node.js Installation**: The scripts now:
   - Check if any real Node.js versions exist (not just system)
   - Install LTS automatically if none found
   - Set the first available version as default if none is set
   - Re-initialize fnm environment after setting default

5. **PATH Considerations**:
   - fnm installs to different locations on different platforms
   - Ubuntu/Pi: `~/.local/share/fnm`
   - macOS/WSL (via Homebrew): Managed by brew
   - Always use full path to fnm binary during initialization: `"$HOME"/.local/share/fnm/fnm`

#### Common Issues and Solutions

- **"fnm: command not found"**: PATH not set correctly, use full path to binary
- **"none" as current version**: No default set, need to run `fnm default <version>`
- **Only "system" in fnm list**: No Node.js versions installed, need to run `fnm install --lts`
- **npm not found after fnm install**: Need to re-source fnm env after installing Node.js

### pyenv Installation Handling

The pyenv installer will fail if `~/.pyenv` directory already exists. The scripts now handle this by:

1. Checking if the directory exists when `pyenv` command is not found
2. Attempting to fix PATH by adding `$HOME/.pyenv/bin`
3. If pyenv is found after PATH fix, continue normally
4. If not found, warn user that manual intervention may be required

This prevents the confusing situation where pyenv is partially installed but not functional.

### Interactive Prompts with curl|bash

When scripts are executed via `curl | bash`, stdin is the script content itself, not the terminal. This means `read` commands will get EOF immediately instead of waiting for user input.

**Solution**: Read from `/dev/tty` explicitly:

```bash
# Won't work with curl|bash - gets EOF immediately
read -r

# Works correctly - reads from terminal
read -r < /dev/tty

# For reading into a variable
read -r response < /dev/tty
```

This applies to any interactive prompt in the scripts (e.g., deploy key setup confirmation).

### Chezmoi Initialization Validation

Simply checking if `~/.local/share/chezmoi` exists is not sufficient to determine if chezmoi is properly initialized. The directory might exist but be empty or corrupted (missing `.git`).

**Solution**: Check for the `.git` subdirectory:

```bash
local chez_src="${HOME}/.local/share/chezmoi"

# Check if directory exists but is not a valid git repo
if [[ -d "${chez_src}" ]] && [[ ! -d "${chez_src}/.git" ]]; then
    print_warning "chezmoi directory exists but is not a git repository. Reinitializing..."
    rm -rf "${chez_src}"
fi
```

This prevents the "fatal: not a git repository" error during `chezmoi update`.

### Deploy Key Setup for Non-Main Users

The scripts support running dotfiles setup for users other than the main user (scowalt) via SSH deploy keys. This is more reliable than requiring personal access tokens.

**Architecture**:

1. **Deploy key generation**: `~/.ssh/dotfiles-deploy-key` (ed25519)
2. **SSH config alias**: `github-dotfiles` host that uses the deploy key
3. **Chezmoi initialization**: Uses `git@github-dotfiles:scowalt/dotfiles.git` instead of the default SSH URL

**How it works**:

```bash
# SSH config (~/.ssh/config) set up by bootstrap_ssh_config()
Host github-dotfiles
    HostName github.com
    User git
    IdentityFile ~/.ssh/dotfiles-deploy-key
    IdentitiesOnly yes

# Chezmoi init for non-main users
chezmoi init --apply --force "git@github-dotfiles:scowalt/dotfiles.git"
```

**User flow**:

1. Script detects no SSH/token access to dotfiles repo
2. Generates deploy key and displays public key
3. User adds deploy key to GitHub repo settings (read-only)
4. Script tests the key with retry loop
5. Chezmoi initializes using the `github-dotfiles` alias

## Development Practices

### Code Quality Tools

This repository uses automated tools to maintain code quality:

- **Shellcheck**: Validates all shell scripts for common issues and best practices
- **Markdownlint**: Ensures consistent markdown formatting
  - Configuration: `.markdownlint.json`
  - MD013 (line length) is disabled to allow long lines in documentation
- **Lefthook**: Manages git hooks for pre-commit and pre-push validation
  - Runs via `bunx` (preferred over `npx`)

#### ShellCheck Configuration

This repository is configured for maximum error detection with shellcheck:

**Configuration File**: `.shellcheckrc`

- `severity=style` - Catches all issues including style suggestions
- `enable=all` - Enables all optional checks
- `external-sources=true` - Follows external source files
- `check-sourced=true` - Validates sourced scripts
- `shell=bash` - Uses bash dialect by default

**Automated Validation**:

- **Pre-commit hook**: Validates staged shell scripts before commit
- **Pre-push hook**: Validates all shell scripts before push
- **Manual validation**: Simply run `shellcheck script.sh` - the `.shellcheckrc` handles all settings automatically

**Shell Script Standards**:

- Use `[[ ]]` for test conditions instead of `[ ]`
- Always brace variable references: `"${variable}"` not `"$variable"`
- Use `read -r` to prevent backslash mangling
- Separate command substitution for complex pipelines to avoid masking return values
- Quote all variable expansions to prevent word splitting

### Commit Guidelines

- Always run shellcheck on modified shell scripts before committing
- **IMPORTANT**: Update script version numbers whenever making changes to any script
- Use descriptive commit messages that explain the "why" not just the "what"
- Include the robot emoji and Claude Code attribution for AI-assisted commits

### Version Number Management

**Critical Rule**: Whenever you modify any setup script, you MUST update its version number.

Each script has a version number in its header that follows this pattern:

```bash
# Bash scripts (mac.sh, ubuntu.sh, wsl.sh, pi.sh, omarchy.sh)
echo -e "${GRAY}Version XX | Last changed: Description of change${NC}"
```

```powershell
# PowerShell scripts (win.ps1)
Write-Host "Version XX | Last changed: Description of change" -ForegroundColor DarkGray
```

**Steps for updating versions:**

1. Increment the version number by 1
2. Update the "Last changed" description to match your commit message
3. Keep it concise (one line describing the change)
