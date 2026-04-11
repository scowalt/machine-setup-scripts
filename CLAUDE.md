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
- **bazzite.sh** - Bazzite OS setup using Homebrew (Lenovo Legion Go)
- **codespaces.sh** - GitHub Codespaces setup (sources ubuntu.sh for shared functions)

## Common Development Tasks

### Running Setup Scripts Locally

```bash
# macOS
./mac.sh

# Ubuntu/WSL/Pi/Arch/Bazzite
sudo ./ubuntu.sh  # or ./wsl.sh, ./pi.sh, ./omarchy.sh, ./bazzite.sh

# Windows (PowerShell as Administrator)
./win.ps1
```

### Remote Execution

Scripts are hosted at `https://scripts.scowalt.com/setup/` for remote execution via curl/wget as documented in README.md.

### Repository Management

Use `git` and `gh` CLI tools to manage this repository:

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

### Script Sourcing

`codespaces.sh` is the first script to source another (`ubuntu.sh`) for function reuse. This is enabled by a source guard at the bottom of `ubuntu.sh`:

```bash
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"
```

This ensures `main()` only runs when the script is executed directly, not when sourced. Other scripts can adopt this pattern if needed in the future.

### Key Design Principles

- **Idempotency**: Scripts check for existing installations before proceeding
- **Error Handling**: Failed installations are logged but don't stop execution
- **User Feedback**: Color-coded output for status messages
- **Platform-Specific**: Each script optimized for its target OS
- **Dotfile Management**: Shell configurations are managed by chezmoi - scripts should only install tools, not configure shells

### Common Tools Installed

- Version Control: git, gh (GitHub CLI)
- Shell: fish (with completions), tmux
- Node.js: fnm (Fast Node Manager)
- Python: pyenv (Python version management)
- Security: 1Password CLI, Tailscale
- Dotfiles: Chezmoi (with auto-sync)
- Terminal: Starship prompt
- CI/CD: act (local GitHub Actions)

### Important Notes

- Scripts require SSH keys to be registered with GitHub before running
- Ubuntu script enforces creation of 'scowalt' user
- All scripts configure fish as the default shell
- Chezmoi manages dotfiles with automatic git operations
- **IMPORTANT**: Do not add shell configuration (bashrc, zshrc, fish config, PowerShell profiles) in setup scripts - these are managed by chezmoi and will be overridden

## GitHub SSH Key Security Model

The setup scripts automatically detect whether a machine is physical or a VPS to enforce security best practices:

### Physical Machines (Local Access)

- **Detection**: No virtualization detected, no cloud-init present, or explicitly identified as Raspberry Pi/macOS/WSL
- **SSH Access**: Full write access via SSH authentication keys (`~/.ssh/id_rsa`)
- **Security Rationale**: Physical machines are in your possession and pose minimal risk if compromised
- **Examples**: Laptops, desktops, Raspberry Pi devices, WSL on Windows

### VPS/Cloud Machines (Remote Access)

- **Detection**: Virtualization detected (systemd-detect-virt), cloud-init present, or cloud provider IP address
- **SSH Access**: Read-only access via deploy keys (`~/.ssh/dotfiles-deploy-key`)
- **Write Access**: Optional via fine-grained tokens manually configured in `~/.env.local`
- **Security Rationale**: VPS compromise should not grant attackers write access to all your GitHub repositories
- **Examples**: DigitalOcean droplets, AWS EC2 instances, Linode VPS, Vultr servers, Hetzner cloud

### Detection Algorithm

The scripts use a weighted scoring system with multiple heuristic signals:

1. **Virtualization (3 points)**: `systemd-detect-virt` output, DMI product/vendor strings
2. **Cloud-init (2 points)**: Presence of `/etc/cloud/cloud.cfg`
3. **IP Analysis (2 points)**: Cloud provider detection via ipinfo.io
4. **Special Cases**: Raspberry Pi always detected as physical (ARM + device tree)

**Threshold**: 3+ points = VPS, otherwise physical

**Override**: Set `MACHINE_TYPE=physical` or `MACHINE_TYPE=vps` environment variable to manually override detection

### Debugging Detection

Enable debug output to see detection decisions:

```bash
DEBUG=1 ./ubuntu.sh  # or ./omarchy.sh
```

This will show:

- VPS score
- Which signals were detected
- Final decision (vps or physical)

### Migration Strategy

**Existing VPS machines with SSH auth keys**:

- Keys continue to work (not automatically removed)
- Manually remove from GitHub after confirming deploy key works
- Future runs of setup scripts will use deploy keys instead

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

### SSH Commands Consuming stdin with curl|bash

When running scripts via `curl | bash`, SSH commands can consume the remaining script content from stdin, causing the script to exit prematurely with code 0.

**Problem**: `ssh -T git@github.com` reads from stdin by default. When stdin is the script content (via curl pipe), SSH consumes it, leaving nothing for bash to execute.

**Solution**: Redirect stdin from `/dev/null`:

```bash
# Will consume script content and cause early exit
ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"

# Fixed - prevents ssh from reading stdin
ssh -T git@github.com < /dev/null 2>&1 | grep -q "successfully authenticated"
```

**Symptoms of this bug**:

- Script exits with code 0 (success) but doesn't complete
- EXIT trap shows `$LINENO` as 1 (context reset)
- Happens consistently at the same point (first SSH command)

This fix has been applied to all SSH authentication checks in all setup scripts.

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

### Claude Remote Control Sessions

The scripts set up persistent Claude Code remote-control sessions that automatically start on boot and watch for configuration changes.

**Architecture**:

1. **Config file**: `~/.claude-remote-projects` - lists project directories (relative to `~/Code/`)
2. **Helper script**: `~/.local/bin/claude-remote-start` - long-running watcher that manages tmux sessions
3. **Auto-start**: systemd user service (Linux/WSL) or LaunchAgent (macOS)

**File Watching (Reconciliation Model)**:

The `claude-remote-start` script is a long-running process, not a one-shot script. It:

1. Performs initial reconciliation on startup (starts sessions for config entries, stops orphaned sessions)
2. Watches `~/.claude-remote-projects` for changes using `inotifywait` (Linux) or `fswatch` (macOS)
3. On any config change, reconciles again - only starting/stopping sessions that changed
4. Falls back to 30-second polling if neither file watcher is available

**Reconciliation vs Kill-All-Recreate**:

- Adding a project to the config starts only that project's session (existing sessions are untouched)
- Removing a project from the config stops only that project's session
- Existing sessions are never disrupted during reconciliation

**Systemd Service (Linux)**:

```ini
[Service]
Type=simple
ExecStart=%h/.local/bin/claude-remote-start
Restart=on-failure
RestartSec=30
KillMode=process
```

- `Type=simple` - the watcher stays running (not oneshot)
- `KillMode=process` - only kills the watcher on stop, tmux sessions survive
- `Restart=on-failure` - auto-restart if the watcher crashes
- Service is always restarted on setup script rerun to pick up script changes

**Dependencies**:

- Linux: `inotify-tools` (provides `inotifywait`) - installed via core packages
- macOS: `fswatch` - installed via Homebrew

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

# Instructions for the usage of Backlog.md CLI Tool

## Backlog.md: Comprehensive Project Management Tool via CLI

### Assistant Objective

Efficiently manage all project tasks, status, and documentation using the Backlog.md CLI, ensuring all project metadata
remains fully synchronized and up-to-date.

### Core Capabilities

- ✅ **Task Management**: Create, edit, assign, prioritize, and track tasks with full metadata
- ✅ **Search**: Fuzzy search across tasks, documents, and decisions with `backlog search`
- ✅ **Acceptance Criteria**: Granular control with add/remove/check/uncheck by index
- ✅ **Definition of Done checklists**: Per-task DoD items with add/remove/check/uncheck
- ✅ **Board Visualization**: Terminal-based Kanban board (`backlog board`) and web UI (`backlog browser`)
- ✅ **Git Integration**: Automatic tracking of task states across branches
- ✅ **Dependencies**: Task relationships and subtask hierarchies
- ✅ **Documentation & Decisions**: Structured docs and architectural decision records
- ✅ **Export & Reporting**: Generate markdown reports and board snapshots
- ✅ **AI-Optimized**: `--plain` flag provides clean text output for AI processing

### Why This Matters to You (AI Agent)

1. **Comprehensive system** - Full project management capabilities through CLI
2. **The CLI is the interface** - All operations go through `backlog` commands
3. **Unified interaction model** - You can use CLI for both reading (`backlog task 1 --plain`) and writing (
   `backlog task edit 1`)
4. **Metadata stays synchronized** - The CLI handles all the complex relationships

### Key Understanding

- **Tasks** live in `backlog/tasks/` as `task-<id> - <title>.md` files
- **You interact via CLI only**: `backlog task create`, `backlog task edit`, etc.
- **Use `--plain` flag** for AI-friendly output when viewing/listing
- **Never bypass the CLI** - It handles Git, metadata, file naming, and relationships

---

# ⚠️ CRITICAL: NEVER EDIT TASK FILES DIRECTLY. Edit Only via CLI

**ALL task operations MUST use the Backlog.md CLI commands**

- ✅ **DO**: Use `backlog task edit` and other CLI commands
- ✅ **DO**: Use `backlog task create` to create new tasks
- ✅ **DO**: Use `backlog task edit <id> --check-ac <index>` to mark acceptance criteria
- ❌ **DON'T**: Edit markdown files directly
- ❌ **DON'T**: Manually change checkboxes in files
- ❌ **DON'T**: Add or modify text in task files without using CLI

**Why?** Direct file editing breaks metadata synchronization, Git tracking, and task relationships.

---

## 1. Source of Truth & File Structure

### 📖 **UNDERSTANDING** (What you'll see when reading)

- Markdown task files live under **`backlog/tasks/`** (drafts under **`backlog/drafts/`**)
- Files are named: `task-<id> - <title>.md` (e.g., `task-42 - Add GraphQL resolver.md`)
- Project documentation is in **`backlog/docs/`**
- Project decisions are in **`backlog/decisions/`**

### 🔧 **ACTING** (How to change things)

- **All task operations MUST use the Backlog.md CLI tool**
- This ensures metadata is correctly updated and the project stays in sync
- **Always use `--plain` flag** when listing or viewing tasks for AI-friendly text output

---

## 2. Common Mistakes to Avoid

### ❌ **WRONG: Direct File Editing**

```markdown
# DON'T DO THIS:

1. Open backlog/tasks/task-7 - Feature.md in editor
2. Change "- [ ]" to "- [x]" manually
3. Add notes or final summary directly to the file
4. Save the file
```

### ✅ **CORRECT: Using CLI Commands**

```bash
# DO THIS INSTEAD:
backlog task edit 7 --check-ac 1  # Mark AC #1 as complete
backlog task edit 7 --notes "Implementation complete"  # Add notes
backlog task edit 7 --final-summary "PR-style summary"  # Add final summary
backlog task edit 7 -s "In Progress" -a @agent-k  # Multiple commands: change status and assign the task when you start working on the task
```

---

## 3. Understanding Task Format (Read-Only Reference)

⚠️ **FORMAT REFERENCE ONLY** - The following sections show what you'll SEE in task files.
**Never edit these directly! Use CLI commands to make changes.**

### Task Structure You'll See

```markdown
---
id: task-42
title: Add GraphQL resolver
status: To Do
assignee: [@sara]
labels: [backend, api]
---

## Description

Brief explanation of the task purpose.

## Acceptance Criteria

<!-- AC:BEGIN -->

- [ ] #1 First criterion
- [x] #2 Second criterion (completed)
- [ ] #3 Third criterion

<!-- AC:END -->

## Definition of Done

<!-- DOD:BEGIN -->

- [ ] #1 Tests pass
- [ ] #2 Docs updated

<!-- DOD:END -->

## Implementation Plan

1. Research approach
2. Implement solution

## Implementation Notes

Progress notes captured during implementation.

## Final Summary

PR-style summary of what was implemented.
```

### How to Modify Each Section

| What You Want to Change | CLI Command to Use                                       |
|-------------------------|----------------------------------------------------------|
| Title                   | `backlog task edit 42 -t "New Title"`                    |
| Status                  | `backlog task edit 42 -s "In Progress"`                  |
| Assignee                | `backlog task edit 42 -a @sara`                          |
| Labels                  | `backlog task edit 42 -l backend,api`                    |
| Description             | `backlog task edit 42 -d "New description"`              |
| Add AC                  | `backlog task edit 42 --ac "New criterion"`              |
| Add DoD                 | `backlog task edit 42 --dod "Ship notes"`                |
| Check AC #1             | `backlog task edit 42 --check-ac 1`                      |
| Check DoD #1            | `backlog task edit 42 --check-dod 1`                     |
| Uncheck AC #2           | `backlog task edit 42 --uncheck-ac 2`                    |
| Uncheck DoD #2          | `backlog task edit 42 --uncheck-dod 2`                   |
| Remove AC #3            | `backlog task edit 42 --remove-ac 3`                     |
| Remove DoD #3           | `backlog task edit 42 --remove-dod 3`                    |
| Add Plan                | `backlog task edit 42 --plan "1. Step one\n2. Step two"` |
| Add Notes (replace)     | `backlog task edit 42 --notes "What I did"`              |
| Append Notes            | `backlog task edit 42 --append-notes "Another note"` |
| Add Final Summary       | `backlog task edit 42 --final-summary "PR-style summary"` |
| Append Final Summary    | `backlog task edit 42 --append-final-summary "Another detail"` |
| Clear Final Summary     | `backlog task edit 42 --clear-final-summary` |

---

## 4. Defining Tasks

### Creating New Tasks

**Always use CLI to create tasks:**

```bash
# Example
backlog task create "Task title" -d "Description" --ac "First criterion" --ac "Second criterion"
```

### Title (one liner)

Use a clear brief title that summarizes the task.

### Description (The "why")

Provide a concise summary of the task purpose and its goal. Explains the context without implementation details.

### Acceptance Criteria (The "what")

**Understanding the Format:**

- Acceptance criteria appear as numbered checkboxes in the markdown files
- Format: `- [ ] #1 Criterion text` (unchecked) or `- [x] #1 Criterion text` (checked)

**Managing Acceptance Criteria via CLI:**

⚠️ **IMPORTANT: How AC Commands Work**

- **Adding criteria (`--ac`)** accepts multiple flags: `--ac "First" --ac "Second"` ✅
- **Checking/unchecking/removing** accept multiple flags too: `--check-ac 1 --check-ac 2` ✅
- **Mixed operations** work in a single command: `--check-ac 1 --uncheck-ac 2 --remove-ac 3` ✅

```bash
# Examples

# Add new criteria (MULTIPLE values allowed)
backlog task edit 42 --ac "User can login" --ac "Session persists"

# Check specific criteria by index (MULTIPLE values supported)
backlog task edit 42 --check-ac 1 --check-ac 2 --check-ac 3  # Check multiple ACs
# Or check them individually if you prefer:
backlog task edit 42 --check-ac 1    # Mark #1 as complete
backlog task edit 42 --check-ac 2    # Mark #2 as complete

# Mixed operations in single command
backlog task edit 42 --check-ac 1 --uncheck-ac 2 --remove-ac 3

# ❌ STILL WRONG - These formats don't work:
# backlog task edit 42 --check-ac 1,2,3  # No comma-separated values
# backlog task edit 42 --check-ac 1-3    # No ranges
# backlog task edit 42 --check 1         # Wrong flag name

# Multiple operations of same type
backlog task edit 42 --uncheck-ac 1 --uncheck-ac 2  # Uncheck multiple ACs
backlog task edit 42 --remove-ac 2 --remove-ac 4    # Remove multiple ACs (processed high-to-low)
```

### Definition of Done checklist (per-task)

Definition of Done items are a second checklist in each task. Defaults come from `definition_of_done` in the project config file (`backlog/config.yml`, `.backlog/config.yml`, or `backlog.config.yml`) or from Web UI Settings, and can be disabled per task.

**Managing Definition of Done via CLI:**

```bash
# Add DoD items (MULTIPLE values allowed)
backlog task edit 42 --dod "Run tests" --dod "Update docs"

# Check/uncheck DoD items by index (MULTIPLE values supported)
backlog task edit 42 --check-dod 1 --check-dod 2
backlog task edit 42 --uncheck-dod 1

# Remove DoD items by index
backlog task edit 42 --remove-dod 2

# Create without defaults
backlog task create "Feature" --no-dod-defaults
```

**Key Principles for Good ACs:**

- **Outcome-Oriented:** Focus on the result, not the method.
- **Testable/Verifiable:** Each criterion should be objectively testable
- **Clear and Concise:** Unambiguous language
- **Complete:** Collectively cover the task scope
- **User-Focused:** Frame from end-user or system behavior perspective

Good Examples:

- "User can successfully log in with valid credentials"
- "System processes 1000 requests per second without errors"
- "CLI preserves literal newlines in description/plan/notes/final summary; `\\n` sequences are not auto‑converted"

Bad Example (Implementation Step):

- "Add a new function handleLogin() in auth.ts"
- "Define expected behavior and document supported input patterns"

### Task Breakdown Strategy

1. Identify foundational components first
2. Create tasks in dependency order (foundations before features)
3. Ensure each task delivers value independently
4. Avoid creating tasks that block each other

### Task Requirements

- Tasks must be **atomic** and **testable** or **verifiable**
- Each task should represent a single unit of work for one PR
- **Never** reference future tasks (only tasks with id < current task id)
- Ensure tasks are **independent** and don't depend on future work

---

## 5. Implementing Tasks

### 5.1. First step when implementing a task

The very first things you must do when you take over a task are:

* set the task in progress
* assign it to yourself

```bash
# Example
backlog task edit 42 -s "In Progress" -a @{myself}
```

### 5.2. Review Task References and Documentation

Before planning, check if the task has any attached `references` or `documentation`:
- **References**: Related code files, GitHub issues, or URLs relevant to the implementation
- **Documentation**: Design docs, API specs, or other materials for understanding context

These are visible in the task view output. Review them to understand the full context before drafting your plan.

### 5.3. Create an Implementation Plan (The "how")

Previously created tasks contain the why and the what. Once you are familiar with that part you should think about a
plan on **HOW** to tackle the task and all its acceptance criteria. This is your **Implementation Plan**.
First do a quick check to see if all the tools that you are planning to use are available in the environment you are
working in.
When you are ready, write it down in the task so that you can refer to it later.

```bash
# Example
backlog task edit 42 --plan "1. Research codebase for references\n2Research on internet for similar cases\n3. Implement\n4. Test"
```

## 5.4. Implementation

Once you have a plan, you can start implementing the task. This is where you write code, run tests, and make sure
everything works as expected. Follow the acceptance criteria one by one and MARK THEM AS COMPLETE as soon as you
finish them.

### 5.5 Implementation Notes (Progress log)

Use Implementation Notes to log progress, decisions, and blockers as you work.
Append notes progressively during implementation using `--append-notes`:

```
backlog task edit 42 --append-notes "Investigated root cause" --append-notes "Added tests for edge case"
```

```bash
# Example
backlog task edit 42 --notes "Initial implementation done; pending integration tests"
```

### 5.6 Final Summary (PR description)

When you are done implementing a task you need to prepare a PR description for it.
Because you cannot create PRs directly, write the PR as a clean summary in the Final Summary field.

**Quality bar:** Write it like a reviewer will see it. A one‑liner is rarely enough unless the change is truly trivial.
Include the key scope so someone can understand the impact without reading the whole diff.

```bash
# Example
backlog task edit 42 --final-summary "Implemented pattern X because Reason Y; updated files Z and W; added tests"
```

**IMPORTANT**: Do NOT include an Implementation Plan when creating a task. The plan is added only after you start the
implementation.

- Creation phase: provide Title, Description, Acceptance Criteria, and optionally labels/priority/assignee.
- When you begin work, switch to edit, set the task in progress and assign to yourself
  `backlog task edit <id> -s "In Progress" -a "..."`.
- Think about how you would solve the task and add the plan: `backlog task edit <id> --plan "..."`.
- After updating the plan, share it with the user and ask for confirmation. Do not begin coding until the user approves the plan or explicitly tells you to skip the review.
- Append Implementation Notes during implementation using `--append-notes` as progress is made.
- Add Final Summary only after completing the work: `backlog task edit <id> --final-summary "..."` (replace) or append using `--append-final-summary`.

## Phase discipline: What goes where

- Creation: Title, Description, Acceptance Criteria, labels/priority/assignee.
- Implementation: Implementation Plan (after moving to In Progress and assigning to yourself) + Implementation Notes (progress log, appended as you work).
- Wrap-up: Final Summary (PR description), verify AC and Definition of Done checks.

**IMPORTANT**: Only implement what's in the Acceptance Criteria. If you need to do more, either:

1. Update the AC first: `backlog task edit 42 --ac "New requirement"`
2. Or create a new follow up task: `backlog task create "Additional feature"`

---

## 6. Typical Workflow

```bash
# 1. Identify work
backlog task list -s "To Do" --plain

# 2. Read task details
backlog task 42 --plain

# 3. Start work: assign yourself & change status
backlog task edit 42 -s "In Progress" -a @myself

# 4. Add implementation plan
backlog task edit 42 --plan "1. Analyze\n2. Refactor\n3. Test"

# 5. Share the plan with the user and wait for approval (do not write code yet)

# 6. Work on the task (write code, test, etc.)

# 7. Mark acceptance criteria as complete (supports multiple in one command)
backlog task edit 42 --check-ac 1 --check-ac 2 --check-ac 3  # Check all at once
# Or check them individually if preferred:
# backlog task edit 42 --check-ac 1
# backlog task edit 42 --check-ac 2
# backlog task edit 42 --check-ac 3

# 8. Add Final Summary (PR Description)
backlog task edit 42 --final-summary "Refactored using strategy pattern, updated tests"

# 9. Mark task as done
backlog task edit 42 -s Done
```

---

## 7. Definition of Done (DoD)

A task is **Done** only when **ALL** of the following are complete:

### ✅ Via CLI Commands:

1. **All acceptance criteria checked**: Use `backlog task edit <id> --check-ac <index>` for each
2. **All Definition of Done items checked**: Use `backlog task edit <id> --check-dod <index>` for each
3. **Final Summary added**: Use `backlog task edit <id> --final-summary "..."`
4. **Status set to Done**: Use `backlog task edit <id> -s Done`

### ✅ Via Code/Testing:

5. **Tests pass**: Run test suite and linting
6. **Documentation updated**: Update relevant docs if needed
7. **Code reviewed**: Self-review your changes
8. **No regressions**: Performance, security checks pass

⚠️ **NEVER mark a task as Done without completing ALL items above**

---

## 8. Finding Tasks and Content with Search

When users ask you to find tasks related to a topic, use the `backlog search` command with `--plain` flag:

```bash
# Search for tasks about authentication
backlog search "auth" --plain

# Search only in tasks (not docs/decisions)
backlog search "login" --type task --plain

# Search with filters
backlog search "api" --status "In Progress" --plain
backlog search "bug" --priority high --plain
```

**Key points:**
- Uses fuzzy matching - finds "authentication" when searching "auth"
- Searches task titles, descriptions, and content
- Also searches documents and decisions unless filtered with `--type task`
- Always use `--plain` flag for AI-readable output

---

## 9. Quick Reference: DO vs DON'T

### Viewing and Finding Tasks

| Task         | ✅ DO                        | ❌ DON'T                         |
|--------------|-----------------------------|---------------------------------|
| View task    | `backlog task 42 --plain`   | Open and read .md file directly |
| List tasks   | `backlog task list --plain` | Browse backlog/tasks folder     |
| Check status | `backlog task 42 --plain`   | Look at file content            |
| Find by topic| `backlog search "auth" --plain` | Manually grep through files |

### Modifying Tasks

| Task          | ✅ DO                                 | ❌ DON'T                           |
|---------------|--------------------------------------|-----------------------------------|
| Check AC      | `backlog task edit 42 --check-ac 1`  | Change `- [ ]` to `- [x]` in file |
| Add notes     | `backlog task edit 42 --notes "..."` | Type notes into .md file          |
| Add final summary | `backlog task edit 42 --final-summary "..."` | Type summary into .md file |
| Change status | `backlog task edit 42 -s Done`       | Edit status in frontmatter        |
| Add AC        | `backlog task edit 42 --ac "New"`    | Add `- [ ] New` to file           |

---

## 10. Complete CLI Command Reference

### Task Creation

| Action           | Command                                                                             |
|------------------|-------------------------------------------------------------------------------------|
| Create task      | `backlog task create "Title"`                                                       |
| With description | `backlog task create "Title" -d "Description"`                                      |
| With AC          | `backlog task create "Title" --ac "Criterion 1" --ac "Criterion 2"`                 |
| With final summary | `backlog task create "Title" --final-summary "PR-style summary"`                 |
| With references  | `backlog task create "Title" --ref src/api.ts --ref https://github.com/issue/123`   |
| With documentation | `backlog task create "Title" --doc https://design-docs.example.com`               |
| With all options | `backlog task create "Title" -d "Desc" -a @sara -s "To Do" -l auth --priority high --ref src/api.ts --doc docs/spec.md` |
| Create draft     | `backlog task create "Title" --draft`                                               |
| Create subtask   | `backlog task create "Title" -p 42`                                                 |

### Task Modification

| Action           | Command                                     |
|------------------|---------------------------------------------|
| Edit title       | `backlog task edit 42 -t "New Title"`       |
| Edit description | `backlog task edit 42 -d "New description"` |
| Change status    | `backlog task edit 42 -s "In Progress"`     |
| Assign           | `backlog task edit 42 -a @sara`             |
| Add labels       | `backlog task edit 42 -l backend,api`       |
| Set priority     | `backlog task edit 42 --priority high`      |

### Acceptance Criteria Management

| Action              | Command                                                                     |
|---------------------|-----------------------------------------------------------------------------|
| Add AC              | `backlog task edit 42 --ac "New criterion" --ac "Another"`                  |
| Remove AC #2        | `backlog task edit 42 --remove-ac 2`                                        |
| Remove multiple ACs | `backlog task edit 42 --remove-ac 2 --remove-ac 4`                          |
| Check AC #1         | `backlog task edit 42 --check-ac 1`                                         |
| Check multiple ACs  | `backlog task edit 42 --check-ac 1 --check-ac 3`                            |
| Uncheck AC #3       | `backlog task edit 42 --uncheck-ac 3`                                       |
| Mixed operations    | `backlog task edit 42 --check-ac 1 --uncheck-ac 2 --remove-ac 3 --ac "New"` |

### Task Content

| Action           | Command                                                  |
|------------------|----------------------------------------------------------|
| Add plan         | `backlog task edit 42 --plan "1. Step one\n2. Step two"` |
| Add notes        | `backlog task edit 42 --notes "Implementation details"`  |
| Add final summary | `backlog task edit 42 --final-summary "PR-style summary"` |
| Append final summary | `backlog task edit 42 --append-final-summary "More details"` |
| Clear final summary | `backlog task edit 42 --clear-final-summary` |
| Add dependencies | `backlog task edit 42 --dep task-1 --dep task-2`         |
| Add references   | `backlog task edit 42 --ref src/api.ts --ref https://github.com/issue/123` |
| Add documentation | `backlog task edit 42 --doc https://design-docs.example.com --doc docs/spec.md` |

### Multi‑line Input (Description/Plan/Notes/Final Summary)

The CLI preserves input literally. Shells do not convert `\n` inside normal quotes. Use one of the following to insert real newlines:

- Bash/Zsh (ANSI‑C quoting):
  - Description: `backlog task edit 42 --desc $'Line1\nLine2\n\nFinal'`
  - Plan: `backlog task edit 42 --plan $'1. A\n2. B'`
  - Notes: `backlog task edit 42 --notes $'Done A\nDoing B'`
  - Append notes: `backlog task edit 42 --append-notes $'Progress update line 1\nLine 2'`
  - Final summary: `backlog task edit 42 --final-summary $'Shipped A\nAdded B'`
  - Append final summary: `backlog task edit 42 --append-final-summary $'Added X\nAdded Y'`
- POSIX portable (printf):
  - `backlog task edit 42 --notes "$(printf 'Line1\nLine2')"`
- PowerShell (backtick n):
  - `backlog task edit 42 --notes "Line1`nLine2"`

Do not expect `"...\n..."` to become a newline. That passes the literal backslash + n to the CLI by design.

Descriptions support literal newlines; shell examples may show escaped `\\n`, but enter a single `\n` to create a newline.

### Implementation Notes Formatting

- Keep implementation notes concise and time-ordered; focus on progress, decisions, and blockers.
- Use short paragraphs or bullet lists instead of a single long line.
- Use Markdown bullets (`-` for unordered, `1.` for ordered) for readability.
- When using CLI flags like `--append-notes`, remember to include explicit
  newlines. Example:

  ```bash
  backlog task edit 42 --append-notes $'- Added new API endpoint\n- Updated tests\n- TODO: monitor staging deploy'
  ```

### Final Summary Formatting

- Treat the Final Summary as a PR description: lead with the outcome, then add key changes and tests.
- Keep it clean and structured so it can be pasted directly into GitHub.
- Prefer short paragraphs or bullet lists and avoid raw progress logs.
- Aim to cover: **what changed**, **why**, **user impact**, **tests run**, and **risks/follow‑ups** when relevant.
- Avoid single‑line summaries unless the change is truly tiny.

**Example (good, not rigid):**
```
Added Final Summary support across CLI/MCP/Web/TUI to separate PR summaries from progress notes.

Changes:
- Added `finalSummary` to task types and markdown section parsing/serialization (ordered after notes).
- CLI/MCP/Web/TUI now render and edit Final Summary; plain output includes it.

Tests:
- bun test src/test/final-summary.test.ts
- bun test src/test/cli-final-summary.test.ts
```

### Task Operations

| Action             | Command                                      |
|--------------------|----------------------------------------------|
| View task          | `backlog task 42 --plain`                    |
| List tasks         | `backlog task list --plain`                  |
| Search tasks       | `backlog search "topic" --plain`              |
| Search with filter | `backlog search "api" --status "To Do" --plain` |
| Filter by status   | `backlog task list -s "In Progress" --plain` |
| Filter by assignee | `backlog task list -a @sara --plain`         |
| Archive task       | `backlog task archive 42`                    |
| Demote to draft    | `backlog task demote 42`                     |

---

## Common Issues

| Problem              | Solution                                                           |
|----------------------|--------------------------------------------------------------------|
| Task not found       | Check task ID with `backlog task list --plain`                     |
| AC won't check       | Use correct index: `backlog task 42 --plain` to see AC numbers     |
| Changes not saving   | Ensure you're using CLI, not editing files                         |
| Metadata out of sync | Re-edit via CLI to fix: `backlog task edit 42 -s <current-status>` |

---

## Remember: The Golden Rule

**🎯 If you want to change ANYTHING in a task, use the `backlog task edit` command.**
**📖 Use CLI to read tasks, exceptionally READ task files directly, never WRITE to them.**

Full help available: `backlog --help`

<!-- BACKLOG.MD GUIDELINES END -->
