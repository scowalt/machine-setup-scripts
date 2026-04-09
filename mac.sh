#!/bin/bash

# Define colors
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
GRAY='\033[0;90m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Print functions for readability
print_section() { printf "\n${BOLD}=== %s ===${NC}\n\n" "$1"; }
print_message() { printf "${CYAN} %s${NC}\n" "$1"; }
print_success() { printf "${GREEN} %s${NC}\n" "$1"; }
print_warning() { printf "${YELLOW} %s${NC}\n" "$1"; }
print_error() { printf "${RED} %s${NC}\n" "$1"; }
print_debug() { printf "${GRAY}  %s${NC}\n" "$1"; }

# Migrate old token files (~/.gh_token, ~/.op_token, ~/.rube_token) into ~/.env.local
migrate_token_files() {
    local env_file="${HOME}/.env.local"
    local migrated=0

    for old_file in "${HOME}/.gh_token" "${HOME}/.rube_token" "${HOME}/.op_token"; do
        if [[ -f "${old_file}" ]]; then
            # Extract uncommented KEY=VALUE lines (strip 'export ' prefix if present)
            local values
            values=$(grep -v '^\s*#' "${old_file}" | grep -v '^\s*$' | sed 's/^export //') || true
            if [[ -n "${values}" ]]; then
                touch "${env_file}"
                chmod 600 "${env_file}"
                while IFS= read -r line; do
                    local key="${line%%=*}"
                    if ! grep -q "^${key}=" "${env_file}" 2>/dev/null; then
                        echo "${line}" >> "${env_file}"
                    fi
                done <<< "${values}"
            fi
            rm -f "${old_file}"
            print_debug "Migrated $(basename "${old_file}") → ~/.env.local"
            migrated=1
        fi
    done

    if [[ "${migrated}" -eq 1 ]]; then
        print_message "Token files consolidated into ~/.env.local"
    fi
}

# Create placeholder ~/.env.local if it doesn't exist
create_env_local() {
    migrate_token_files

    if [[ ! -f "${HOME}/.env.local" ]]; then
        cat > "${HOME}/.env.local" << 'EOF'
# Machine-specific environment variables
# Format: KEY=VALUE (one per line)

# GitHub Personal Access Tokens
# Get tokens from: https://github.com/settings/tokens
# GH_TOKEN=github_pat_xxx
# GH_TOKEN_SCOWALT=github_pat_yyy

# Rube MCP API Key
# Get your API key from: https://rube.app
# RUBE_API_KEY=your_api_key_here

# 1Password Service Account Token
# Create a service account at: https://my.1password.com/integrations/infrastructure-secrets
# OP_SERVICE_ACCOUNT_TOKEN=ops_xxx
EOF
        chmod 600 "${HOME}/.env.local"
        print_debug "Created placeholder ~/.env.local"
    fi
}

# Check if running as main user (scowalt)
is_main_user() {
    [[ "${HOME}" == "/Users/scowalt" ]]
}

# Check if user has sudo access (cached result)
_sudo_checked=""
_has_sudo=""
can_sudo() {
    if [[ -z "${_sudo_checked}" ]]; then
        _sudo_checked=1
        local _user_groups
        _user_groups=$(groups 2>/dev/null) || true
        # Method 1: Check if credentials are already cached
        if sudo -n true 2>/dev/null; then
            _has_sudo=1
        # Method 2: Check if user is in a sudo-capable group, then prompt
        elif echo "${_user_groups}" | grep -qE '\b(sudo|wheel|admin)\b'; then
            # User is in sudo group but credentials aren't cached - prompt once
            # shellcheck disable=SC2024
            if sudo -v 2>/dev/null < /dev/tty; then
                _has_sudo=1
            else
                _has_sudo=0
            fi
        else
            _has_sudo=0
        fi
    fi
    [[ "${_has_sudo}" == "1" ]]
}

# Interactive setup for dotfiles deploy key
setup_dotfiles_deploy_key() {
    local key_file="${HOME}/.ssh/dotfiles-deploy-key"

    echo ""
    print_warning "Cannot access scowalt/dotfiles repository"
    echo ""
    echo -e "${BOLD}Let's set up a deploy key for read-only access to dotfiles.${NC}"
    echo ""

    # Step 1: Generate deploy key if it doesn't exist
    if [[ ! -f "${key_file}" ]]; then
        echo -e "${CYAN}Step 1: Generating deploy key...${NC}"
        mkdir -p ~/.ssh
        chmod 700 ~/.ssh
        local _hostname
        _hostname=$(hostname)
        ssh-keygen -t ed25519 -f "${key_file}" -N '' -C "dotfiles-deploy-key-${_hostname}"
        print_success "Deploy key generated at ${key_file}"
        echo ""
    else
        echo -e "${CYAN}Step 1: Deploy key already exists at ${key_file}${NC}"
        echo ""
    fi

    # Step 2: Display public key and instructions
    echo -e "${CYAN}Step 2: Add this public key to GitHub${NC}"
    echo ""
    echo -e "  Go to: ${BOLD}https://github.com/scowalt/dotfiles/settings/keys${NC}"
    echo -e "  Click 'Add deploy key', give it a name, and paste this key:"
    echo ""
    echo -e "${GRAY}────────────────────────────────────────────────────────────────${NC}"
    cat "${key_file}.pub"
    echo -e "${GRAY}────────────────────────────────────────────────────────────────${NC}"
    echo ""

    # Copy to clipboard if pbcopy is available
    if command -v pbcopy &>/dev/null; then
        pbcopy < "${key_file}.pub"
        print_success "Public key copied to clipboard!"
    fi
    echo ""

    # Step 3: Wait for user confirmation (read from /dev/tty for curl|bash compatibility)
    echo -e "${YELLOW}Press Enter after you've added the key to GitHub...${NC}"
    read -r < /dev/tty

    # Set up SSH config for the deploy key
    bootstrap_ssh_config

    # Test the key with retry loop
    local max_retries=5
    local attempt=1
    while [[ ${attempt} -le ${max_retries} ]]; do
        echo -e "${CYAN}Step 3: Testing deploy key access (attempt ${attempt}/${max_retries})...${NC}"
        # < /dev/null prevents ssh from consuming stdin (important for curl|bash)
        local _ssh_output
        _ssh_output=$(ssh -i "${key_file}" -o StrictHostKeyChecking=accept-new -T git@github.com < /dev/null 2>&1) || true
        if echo "${_ssh_output}" | grep -q "successfully authenticated"; then
            print_success "Deploy key works! Continuing setup..."
            return 0
        fi

        print_error "Deploy key authentication failed."
        echo -e "Please verify:"
        echo -e "  1. The key was added to https://github.com/scowalt/dotfiles/settings/keys"
        echo -e "  2. You have the correct permissions on the repository"
        echo ""

        if [[ ${attempt} -lt ${max_retries} ]]; then
            echo -e "${YELLOW}Press Enter to retry, or type 'skip' to continue without dotfiles:${NC}"
            local response
            read -r response < /dev/tty
            if [[ "${response}" == "skip" ]]; then
                print_warning "Skipping dotfiles setup."
                return 1
            fi
        else
            echo -e "${YELLOW}Max retries reached. Skipping dotfiles setup.${NC}"
            return 1
        fi
        ((attempt++))
    done
}

# Check if we have access to scowalt/dotfiles via any available method
check_dotfiles_access() {
    print_message "Checking access to scowalt/dotfiles..."

    # Method 1: Main user with SSH key
    if is_main_user; then
        # < /dev/null prevents ssh from consuming stdin (important for curl|bash)
        local _ssh_output
        _ssh_output=$(ssh -T git@github.com < /dev/null 2>&1) || true
        if echo "${_ssh_output}" | grep -q "successfully authenticated"; then
            print_debug "Access via SSH (main user)"
            return 0
        fi
    fi

    # Method 2: GH_TOKEN_SCOWALT for HTTPS access
    source_gh_tokens
    if [[ -n "${GH_TOKEN_SCOWALT}" ]]; then
        # Test if the token actually works
        if curl -sf -H "Authorization: token ${GH_TOKEN_SCOWALT}" \
            "https://api.github.com/repos/scowalt/dotfiles" > /dev/null 2>&1; then
            print_debug "Access via GH_TOKEN_SCOWALT"
            return 0
        else
            print_warning "GH_TOKEN_SCOWALT is set but cannot access scowalt/dotfiles"
        fi
    fi

    # Method 3: Deploy key at ~/.ssh/dotfiles-deploy-key
    if [[ -f ~/.ssh/dotfiles-deploy-key ]]; then
        # Set up SSH config for github-dotfiles if not present
        bootstrap_ssh_config
        # Test if the deploy key works
        # < /dev/null prevents ssh from consuming stdin (important for curl|bash)
        local _deploy_ssh_output
        _deploy_ssh_output=$(ssh -i ~/.ssh/dotfiles-deploy-key -T git@github.com < /dev/null 2>&1) || true
        if echo "${_deploy_ssh_output}" | grep -q "successfully authenticated"; then
            print_debug "Access via deploy key"
            return 0
        else
            print_warning "Deploy key exists but cannot authenticate with GitHub"
        fi
    fi

    # No access method worked
    return 1
}

source_gh_tokens() {
    if [[ -f "${HOME}/.env.local" ]]; then
        set -a
        # shellcheck source=/dev/null
        source "${HOME}/.env.local"
        set +a
        if [[ -n "${GH_TOKEN}" ]]; then
            print_debug "GH_TOKEN loaded from ~/.env.local"
        fi
        if [[ -n "${GH_TOKEN_SCOWALT}" ]]; then
            print_debug "GH_TOKEN_SCOWALT loaded from ~/.env.local"
        fi
        [[ -n "${GH_TOKEN}" ]] || [[ -n "${GH_TOKEN_SCOWALT}" ]]
        return $?
    fi
    return 1
}

# Configure git to use multi-token credential helper for GitHub HTTPS operations
# This helper routes to GH_TOKEN_SCOWALT for scowalt/* repos, GH_TOKEN for others
setup_github_credential_helper() {
    # Source tokens if not already set
    if [[ -z "${GH_TOKEN}" ]] && [[ -z "${GH_TOKEN_SCOWALT}" ]]; then
        source_gh_tokens
    fi

    # Need at least one token to proceed
    if [[ -z "${GH_TOKEN}" ]] && [[ -z "${GH_TOKEN_SCOWALT}" ]]; then
        print_debug "No GitHub tokens available, skipping credential helper setup."
        return 1
    fi

    # Check if the multi-token credential helper exists
    local helper_path="${HOME}/.local/bin/git-credential-github-multi"
    if [[ ! -x "${helper_path}" ]]; then
        print_debug "Multi-token credential helper not yet installed, will be set up by chezmoi."
    fi

    # Configure git to use our multi-token credential helper for github.com
    # Note: We write directly to the file because git config escapes ! to \\!
    # which breaks the shell command execution that ! is supposed to trigger
    git config --global --unset-all credential.https://github.com.helper 2>/dev/null || true

    # Remove any existing [credential "https://github.com"] section
    if [[ -f "${HOME}/.gitconfig" ]]; then
        # Use sed to remove the section (macOS sed syntax)
        sed -i '' '/^\[credential "https:\/\/github.com"\]/,/^\[/{ /^\[credential "https:\/\/github.com"\]/d; /^\[/!d; }' "${HOME}/.gitconfig" 2>/dev/null || true
    fi

    # Append the credential helper config directly to avoid git config escaping the !
    # Use heredoc with quoted delimiter to prevent any shell interpretation
    cat >> "${HOME}/.gitconfig" << 'CREDENTIAL_EOF'

[credential "https://github.com"]
	helper = !git-credential-github-multi
CREDENTIAL_EOF
    print_debug "Git configured to use multi-token credential helper for GitHub."
    return 0
}

# Fix zsh compaudit insecure directories warning
fix_zsh_compaudit() {
    print_message "Fixing zsh compaudit insecure directories..."

    # Ensure user owns the Homebrew zsh directories (required for brew upgrade)
    # This may need sudo if root currently owns them
    local current_user
    current_user=$(whoami)
    local zsh_dir="/opt/homebrew/share/zsh"
    local zsh_completions="/opt/homebrew/share/zsh-completions"

    for dir in "${zsh_dir}" "${zsh_completions}"; do
        if [[ -d "${dir}" ]]; then
            local owner
            owner=$(stat -f "%Su" "${dir}" 2>/dev/null)
            if [[ "${owner}" != "${current_user}" ]]; then
                print_debug "Fixing ownership of ${dir} (currently owned by ${owner})..."
                if can_sudo; then
                    sudo chown -R "${current_user}:admin" "${dir}" 2>/dev/null || true
                fi
            fi
        fi
    done

    # Fix permissions (remove group/other write) - this satisfies compaudit
    chmod -R go-w /opt/homebrew/share/zsh 2>/dev/null || true
    chmod -R go-w /opt/homebrew/share/zsh-completions 2>/dev/null || true
    chmod -R go-w /usr/local/share/zsh 2>/dev/null || true

    zsh -c 'compaudit 2>/dev/null | xargs -I {} chmod go-w {} 2>/dev/null' || true
    print_success "zsh directory permissions fixed."
}

# Install core packages with Homebrew if missing
install_core_packages() {
    print_message "Checking and installing core packages as needed..."

    # Ensure required taps are available (some packages have cross-tap dependencies)
    local taps=("libsql/sqld" "tursodatabase/tap")
    for tap in "${taps[@]}"; do
        if ! brew tap | grep -q "^${tap}$"; then
            print_debug "Tapping ${tap}..."
            brew tap "${tap}" 2>/dev/null || true
        fi
    done

    # Define an array of required packages
    # NOTE: starship installed via Homebrew for consistent macOS binary management
    # NOTE: tailscale installed as a cask (GUI app) separately by setup_tailscale()
    local packages=("git" "curl" "jq" "fish" "tmux" "1password-cli" "gh" "chezmoi" "starship" "mise" "act" "terminal-notifier" "hammerspoon" "switchaudio-osx" "opentofu" "uv" "go" "cloudflared" "tursodatabase/tap/turso" "fswatch" "shellcheck" "gitleaks" "lefthook" "poppler" "ffmpeg")
    local to_install=()

    # Get all installed packages at once (much faster than checking individually)
    print_message "Getting list of installed packages..."
    local installed_formulae
    local brew_formulae_list
    brew_formulae_list=$(brew list --formula -1 2>/dev/null)
    installed_formulae=$(echo "${brew_formulae_list}" | tr '\n' ' ')
    local installed_casks
    local brew_casks_list
    brew_casks_list=$(brew list --cask -1 2>/dev/null)
    installed_casks=$(echo "${brew_casks_list}" | tr '\n' ' ')
    local all_installed=" ${installed_formulae} ${installed_casks} "

    # Check each required package against the installed list
    # For tap packages (e.g., dopplerhq/cli/doppler), also check the short name (doppler)
    for package in "${packages[@]}"; do
        local short_name="${package##*/}"
        if [[ "${all_installed}" =~ \ ${package}\  ]] || [[ "${all_installed}" =~ \ ${short_name}\  ]]; then
            print_debug "${package} is already installed."
        else
            to_install+=("${package}")
        fi
    done

    # Install packages individually so one failure doesn't block everything
    if [[ "${#to_install[@]}" -gt 0 ]]; then
        print_message "Installing ${#to_install[@]} missing packages..."
        local failed=()
        for package in "${to_install[@]}"; do
            if ! brew install "${package}" 2>&1; then
                print_warning "Failed to install ${package}"
                failed+=("${package}")
            fi
        done
        if [[ "${#failed[@]}" -gt 0 ]]; then
            print_warning "Failed packages: ${failed[*]}"
        else
            print_success "All core packages installed."
        fi
    else
        print_success "All core packages are already installed."
    fi
}

# Ensure Tailscale is installed as the cask (GUI app), not the formula (CLI-only).
# The formula's daemon management is broken on macOS — brew services can't handle
# privileged network daemons properly. The cask installs the same app as a direct
# download from tailscale.com and manages the daemon natively.
setup_tailscale() {
    # If the formula is installed (not the cask), replace it with the cask
    if brew list --formula tailscale &>/dev/null 2>&1; then
        print_message "Replacing Tailscale formula with cask (GUI app)..."
        brew services stop tailscale 2>/dev/null || true
        brew uninstall tailscale 2>/dev/null || true
    fi

    # Install the cask if not already present
    if ! brew list --cask tailscale &>/dev/null 2>&1; then
        print_message "Installing Tailscale (cask)..."
        brew install --cask tailscale
        print_success "Tailscale cask installed."
    else
        print_debug "Tailscale cask is already installed."
    fi

    # Launch the app if not running (starts the daemon automatically)
    # Check if the Tailscale process is already running, not tailscale status
    # (which fails if not logged in even when the daemon is running)
    if pgrep -q "Tailscale" 2>/dev/null; then
        print_debug "Tailscale app is already running."
    else
        print_message "Starting Tailscale..."
        open -a Tailscale 2>/dev/null || true
        sleep 3
        print_success "Tailscale started."
    fi
}

# Install the appropriate secrets manager based on machine type
install_secrets_manager() {
    if [[ "${WORK_MACHINE:-}" == "1" ]]; then
        if command -v infisical &>/dev/null; then
            print_debug "Infisical CLI already installed."
            return
        fi
        print_message "Installing Infisical CLI..."
        if ! brew tap | grep -q "^infisical/get-cli$"; then
            brew tap infisical/get-cli 2>/dev/null || true
        fi
        if brew install infisical/get-cli/infisical; then
            print_success "Infisical CLI installed."
        else
            print_error "Failed to install Infisical CLI."
        fi
    else
        if command -v doppler &>/dev/null; then
            print_debug "Doppler CLI already installed."
            return
        fi
        print_message "Installing Doppler CLI..."
        if ! brew tap | grep -q "^dopplerhq/cli$"; then
            brew tap dopplerhq/cli 2>/dev/null || true
        fi
        if brew install dopplerhq/cli/doppler; then
            print_success "Doppler CLI installed."
        else
            print_error "Failed to install Doppler CLI."
        fi
    fi
}

# Enable SSH (Remote Login) with key-only auth, no password
# Block public file upload services on work machines to prevent accidental data leaks.
# AI coding agents (Claude Code, Codex) may upload screenshots/code to these services.
# Only applies when WORK_MACHINE=1 is set in ~/.env.local.
block_public_upload_services() {
    if [[ "${WORK_MACHINE:-}" != "1" ]]; then
        print_debug "Not a work machine, skipping upload service blocks."
        return
    fi

    if ! can_sudo; then
        print_warning "No sudo access — cannot block upload services."
        return
    fi

    local hosts_file="/etc/hosts"
    local marker="# WORK_MACHINE: blocked public upload services"

    # Check if already configured
    if grep -q "${marker}" "${hosts_file}" 2>/dev/null; then
        print_debug "Public upload services already blocked."
        return
    fi

    print_message "Blocking public file upload services (work machine policy)..."

    sudo tee -a "${hosts_file}" > /dev/null << EOF

${marker}
# Image/file upload services (prevent AI agents from leaking data)
127.0.0.1 0x0.st
::1 0x0.st
127.0.0.1 catbox.moe
::1 catbox.moe
127.0.0.1 files.catbox.moe
::1 files.catbox.moe
127.0.0.1 litterbox.catbox.moe
::1 litterbox.catbox.moe
127.0.0.1 pixhost.to
::1 pixhost.to
127.0.0.1 imagebin.ca
::1 imagebin.ca
127.0.0.1 beeimg.com
::1 beeimg.com
# Paste services
127.0.0.1 pastebin.com
::1 pastebin.com
127.0.0.1 hastebin.com
::1 hastebin.com
127.0.0.1 paste.rs
::1 paste.rs
127.0.0.1 dpaste.org
::1 dpaste.org
127.0.0.1 ix.io
::1 ix.io
127.0.0.1 sprunge.us
::1 sprunge.us
127.0.0.1 clbin.com
::1 clbin.com
127.0.0.1 termbin.com
::1 termbin.com
# Temporary file sharing
127.0.0.1 transfer.sh
::1 transfer.sh
127.0.0.1 file.io
::1 file.io
127.0.0.1 tmpfiles.org
::1 tmpfiles.org
127.0.0.1 uguu.se
::1 uguu.se
127.0.0.1 pomf.cat
::1 pomf.cat
EOF

    # Flush DNS cache on macOS
    sudo dscacheutil -flushcache 2>/dev/null
    sudo killall -HUP mDNSResponder 2>/dev/null

    print_success "Blocked ${marker##*: } on this work machine."
}

enable_ssh() {
    if ! can_sudo; then
        print_warning "No sudo access — cannot enable SSH."
        return
    fi

    # Enable Remote Login (SSH)
    # Check if sshd is already running
    if sudo launchctl list com.openssh.sshd &>/dev/null; then
        print_debug "SSH (Remote Login) is already enabled."
    else
        print_message "Enabling SSH (Remote Login)..."
        # Try systemsetup first (works if terminal has Full Disk Access)
        if sudo systemsetup -setremotelogin on 2>/dev/null; then
            print_success "SSH enabled via systemsetup."
        # Fallback: load the SSH launch daemon directly (avoids FDA requirement)
        elif sudo launchctl load -w /System/Library/LaunchDaemons/ssh.plist 2>/dev/null; then
            print_success "SSH enabled via launchctl."
        else
            print_warning "Could not enable SSH. Enable manually: System Settings → General → Sharing → Remote Login"
        fi
    fi

    # Configure key-only auth (disable password auth for SSH)
    local sshd_config="/etc/ssh/sshd_config"
    local needs_restart=false

    # Disable password authentication
    if ! grep -q "^PasswordAuthentication no" "${sshd_config}" 2>/dev/null; then
        print_message "Disabling SSH password authentication (key-only)..."
        # Remove any existing PasswordAuthentication lines and add our own
        sudo sed -i '' '/^#*PasswordAuthentication/d' "${sshd_config}"
        echo "PasswordAuthentication no" | sudo tee -a "${sshd_config}" > /dev/null
        needs_restart=true
    fi

    # Disable keyboard-interactive auth
    if ! grep -q "^KbdInteractiveAuthentication no" "${sshd_config}" 2>/dev/null; then
        sudo sed -i '' '/^#*KbdInteractiveAuthentication/d' "${sshd_config}"
        echo "KbdInteractiveAuthentication no" | sudo tee -a "${sshd_config}" > /dev/null
        needs_restart=true
    fi

    # Disable challenge-response auth
    if ! grep -q "^ChallengeResponseAuthentication no" "${sshd_config}" 2>/dev/null; then
        sudo sed -i '' '/^#*ChallengeResponseAuthentication/d' "${sshd_config}"
        echo "ChallengeResponseAuthentication no" | sudo tee -a "${sshd_config}" > /dev/null
        needs_restart=true
    fi

    if [[ "${needs_restart}" == true ]]; then
        # Restart SSH to apply changes
        sudo launchctl stop com.openssh.sshd 2>/dev/null || true
        sudo launchctl start com.openssh.sshd 2>/dev/null || true
        print_success "SSH configured for key-only authentication."
    else
        print_debug "SSH already configured for key-only auth."
    fi
}

# Install a Nerd Font for terminal icons (Starship, tmux, etc.)
install_nerd_font() {
    if brew list --cask font-jetbrains-mono-nerd-font &>/dev/null 2>&1; then
        print_debug "JetBrains Mono Nerd Font is already installed."
        return
    fi

    print_message "Installing JetBrains Mono Nerd Font..."
    if ! brew install --cask font-jetbrains-mono-nerd-font; then
        print_warning "Failed to install Nerd Font."
        return
    fi
    print_success "JetBrains Mono Nerd Font installed."

    # Set as default font in Terminal.app
    local font_name="JetBrainsMonoNFM-Regular"
    local font_size=14
    defaults write com.apple.Terminal "Default Window Settings" -string "Basic"
    defaults write com.apple.Terminal "Startup Window Settings" -string "Basic"
    /usr/libexec/PlistBuddy -c "Set :Window\ Settings:Basic:Font $(python3 -c "
import plistlib, sys
font_data = plistlib.dumps({'NSFontNameAttribute': '${font_name}', 'NSFontSizeAttribute': ${font_size}}, fmt=plistlib.FMT_BINARY)
sys.stdout.buffer.write(font_data)
" | base64)" ~/Library/Preferences/com.apple.Terminal.plist 2>/dev/null || true
    print_debug "Terminal.app font configuration attempted."

    # Set as default font in iTerm2 (if installed)
    if [[ -d "/Applications/iTerm.app" ]]; then
        # Set font for the Default profile
        defaults write com.googlecode.iterm2 "New Bookmarks" -array-add 2>/dev/null || true
        /usr/libexec/PlistBuddy -c "Set ':New Bookmarks:0:Normal Font' 'JetBrainsMonoNFM-Regular 14'" \
            ~/Library/Preferences/com.googlecode.iterm2.plist 2>/dev/null || \
        /usr/libexec/PlistBuddy -c "Add ':New Bookmarks:0:Normal Font' string 'JetBrainsMonoNFM-Regular 14'" \
            ~/Library/Preferences/com.googlecode.iterm2.plist 2>/dev/null || true
        # Also set the non-ASCII font to match
        /usr/libexec/PlistBuddy -c "Set ':New Bookmarks:0:Non Ascii Font' 'JetBrainsMonoNFM-Regular 14'" \
            ~/Library/Preferences/com.googlecode.iterm2.plist 2>/dev/null || \
        /usr/libexec/PlistBuddy -c "Add ':New Bookmarks:0:Non Ascii Font' string 'JetBrainsMonoNFM-Regular 14'" \
            ~/Library/Preferences/com.googlecode.iterm2.plist 2>/dev/null || true
        print_debug "iTerm2 font set to JetBrains Mono Nerd Font."
    fi
}

# Check and set up SSH key
setup_ssh_key() {
    print_message "Checking for existing SSH key associated with GitHub..."

    # Retrieve GitHub-associated keys
    local existing_keys
    existing_keys=$(curl -s https://github.com/scowalt.keys)

    if [[ -f ~/.ssh/id_rsa.pub ]]; then
        local local_key
        local_key=$(awk '{print $2}' ~/.ssh/id_rsa.pub)

        if echo "${existing_keys}" | grep -q "${local_key}"; then
            print_success "Existing SSH key recognized by GitHub."
        else
            print_error "SSH key not recognized by GitHub. Please add it manually."
            print_message "Please add the following SSH key to GitHub:"
            cat ~/.ssh/id_rsa.pub
            print_message "Opening GitHub SSH keys page..."
            open "https://github.com/settings/keys"
            return 1
        fi
    else
        print_warning "No SSH key found. Generating a new SSH key..."
        ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
        print_success "SSH key generated."
        print_message "Please add the following SSH key to GitHub:"
        cat ~/.ssh/id_rsa.pub
        print_message "Opening GitHub SSH keys page..."
        open "https://github.com/settings/keys"
        return 1
    fi
}

# Install Xcode CLT headlessly via softwareupdate (no GUI dialog)
# xcode-select --install opens a GUI prompt that hangs on headless machines.
# Instead, we create the /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
# sentinel file and use softwareupdate to find and install the CLT package directly.
install_xcode_cli_tools() {
    if xcode-select -p &>/dev/null; then
        # CLT is installed — check if it needs updating
        local updates
        updates=$(softwareupdate --list 2>&1)
        if echo "${updates}" | grep -qi "Command Line Tools"; then
            print_message "Xcode Command Line Tools update available. Installing..."
            sudo rm -rf /Library/Developer/CommandLineTools 2>/dev/null
            _install_clt_via_softwareupdate
            print_success "Xcode Command Line Tools updated."
        else
            print_debug "Xcode Command Line Tools are already installed and up to date."
        fi
        return 0
    fi

    print_message "Installing Xcode Command Line Tools..."
    _install_clt_via_softwareupdate
    print_success "Xcode Command Line Tools installed."
}

# Helper: install CLT non-interactively using softwareupdate
_install_clt_via_softwareupdate() {
    # This sentinel file makes softwareupdate list the CLT package
    local placeholder="/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress"
    sudo touch "${placeholder}"

    # Find the latest Command Line Tools package label
    local clt_label
    clt_label=$(softwareupdate --list 2>&1 \
        | grep -o 'Label: Command Line Tools.*' \
        | sed 's/^Label: //' \
        | sort -V \
        | tail -n1)

    if [[ -z "${clt_label}" ]]; then
        # Fallback: try the '*' wildcard format (older macOS)
        clt_label=$(softwareupdate --list 2>&1 \
            | grep '\* .*Command Line Tools' \
            | sed 's/^[[:space:]]*\* //' \
            | sort -V \
            | tail -n1)
    fi

    if [[ -z "${clt_label}" ]]; then
        sudo rm -f "${placeholder}"
        print_error "Could not find Command Line Tools package in softwareupdate."
        return 1
    fi

    print_message "Installing '${clt_label}' via softwareupdate..."
    sudo softwareupdate --install "${clt_label}" --verbose

    sudo rm -f "${placeholder}"
}

# Install Homebrew if not installed
install_homebrew() {
    if ! command -v brew &> /dev/null && [[ ! -x "/opt/homebrew/bin/brew" ]]; then
        print_message "Installing Homebrew..."
        # Cache sudo credentials before running installer (Homebrew needs sudo)
        sudo -v < /dev/tty 2>/dev/null || true
        # Download the install script first, then run it with stdin from /dev/tty
        # so sudo can prompt if needed. NONINTERACTIVE prevents Homebrew's own
        # "press RETURN" prompt but still allows sudo to work.
        local install_script
        install_script=$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)
        NONINTERACTIVE=1 /bin/bash -c "${install_script}" < /dev/tty
        if [[ ! -x "/opt/homebrew/bin/brew" ]]; then
            print_error "Homebrew installation failed."
            return 1
        fi
        print_success "Homebrew installed."
    else
        print_debug "Homebrew is already installed."
    fi

    # Always source brew shellenv to ensure PATH is set for the rest of the script
    eval "$(/opt/homebrew/bin/brew shellenv)"
}

# Bootstrap SSH config for secondary users (needed before chezmoi can run)
bootstrap_ssh_config() {
    if is_main_user; then
        return
    fi

    # Ensure github-dotfiles host alias exists for deploy key access
    if ! grep -q "Host github-dotfiles" ~/.ssh/config 2>/dev/null; then
        print_message "Bootstrapping SSH config for dotfiles access..."
        mkdir -p ~/.ssh
        chmod 700 ~/.ssh
        cat >> ~/.ssh/config << 'EOF'

# Deploy key for read-only access to scowalt/dotfiles (secondary users only)
Host github-dotfiles
    HostName github.com
    User git
    IdentityFile ~/.ssh/dotfiles-deploy-key
    IdentitiesOnly yes
EOF
        chmod 600 ~/.ssh/config
        print_success "SSH config bootstrapped."
    fi
}

# Initialize chezmoi if not already initialized
initialize_chezmoi() {
    local chez_src="${HOME}/.local/share/chezmoi"

    # Check if directory exists but is not a valid git repo
    if [[ -d "${chez_src}" ]] && [[ ! -d "${chez_src}/.git" ]]; then
        print_warning "chezmoi directory exists but is not a git repository. Reinitializing..."
        rm -rf "${chez_src}"
    fi

    if [[ ! -d "${chez_src}" ]]; then
        print_message "Initializing chezmoi with scowalt/dotfiles..."
        if is_main_user; then
            # Main user uses SSH with default key for push access
            if ! chezmoi init --apply --force scowalt/dotfiles --ssh > /dev/null; then
                print_error "Failed to initialize chezmoi."
                return 1
            fi
        else
            # Secondary users use SSH via deploy key (github-dotfiles alias)
            if ! chezmoi init --apply --force "git@github-dotfiles:scowalt/dotfiles.git" > /dev/null; then
                print_error "Failed to initialize chezmoi. Check deploy key setup."
                return 1
            fi
        fi
        print_success "chezmoi initialized with scowalt/dotfiles."
    else
        print_debug "chezmoi is already initialized."
    fi
}

# Configure chezmoi for auto commit, push, and pull
configure_chezmoi_git() {
    # Only configure auto-push for main user (secondary users are read-only)
    if ! is_main_user; then
        print_debug "Skipping chezmoi git config for secondary user (read-only)."
        return
    fi

    local chezmoi_config=~/.config/chezmoi/chezmoi.toml
    if [[ ! -f "${chezmoi_config}" ]]; then
        print_message "Configuring chezmoi with auto-commit, auto-push, and auto-pull..."
        mkdir -p ~/.config/chezmoi
        cat <<EOF > "${chezmoi_config}"
[git]
autoCommit = true
autoPush = true
autoPull = true
EOF
        print_success "chezmoi configuration set."
    else
        print_debug "chezmoi configuration already exists."
    fi
}

# Update chezmoi dotfiles repository to latest version
update_chezmoi() {
    local chez_src="${HOME}/.local/share/chezmoi"
    if [[ -d "${chez_src}/.git" ]]; then
        print_message "Updating chezmoi dotfiles repository..."
        # Reset any dirty state (merge conflicts, uncommitted changes) before pulling.
        # The remote repo is the source of truth — local edits in the chezmoi source dir
        # should never exist and are safe to discard.
        git -C "${chez_src}" reset --hard HEAD > /dev/null 2>&1
        git -C "${chez_src}" merge --abort > /dev/null 2>&1
        git -C "${chez_src}" clean -fd > /dev/null 2>&1
        if chezmoi update --force > /dev/null; then
            print_success "chezmoi dotfiles repository updated."
        else
            print_warning "Failed to update chezmoi dotfiles repository. Continuing anyway."
        fi
    elif [[ -d "${chez_src}" ]]; then
        # Directory exists but no .git - broken state, clean up
        print_warning "Broken chezmoi directory detected, reinitializing..."
        rm -rf "${chez_src}"
        initialize_chezmoi
    else
        print_debug "chezmoi not initialized yet, skipping update."
    fi
}

# Set Fish as the default shell if it isn't already
set_fish_as_default_shell() {
    # Guard: don't set fish as default if it isn't installed yet
    if [[ ! -x "/opt/homebrew/bin/fish" ]]; then
        print_warning "Fish shell not found at /opt/homebrew/bin/fish — skipping default shell change."
        print_debug "Install fish first with: brew install fish"
        return
    fi

    # Check the actual configured login shell from the system (not $SHELL which
    # reflects the current session, not the configured default)
    local current_shell
    current_shell=$(dscl . -read /Users/"$(whoami)" UserShell 2>/dev/null | awk '{print $2}')
    if [[ "${current_shell}" == "/opt/homebrew/bin/fish" ]]; then
        print_debug "Fish shell is already the default shell."
        return
    fi

    # Check if fish is in /etc/shells - requires sudo to add if missing
    if ! grep -Fxq "/opt/homebrew/bin/fish" /etc/shells; then
        if ! can_sudo; then
            print_warning "No sudo access - cannot add fish to /etc/shells."
            print_debug "Ask an admin to run: echo '/opt/homebrew/bin/fish' | sudo tee -a /etc/shells"
            return
        fi
        print_message "Adding fish to /etc/shells..."
        echo "/opt/homebrew/bin/fish" | sudo tee -a /etc/shells > /dev/null
    fi

    print_message "Setting Fish as the default shell..."
    chsh -s /opt/homebrew/bin/fish < /dev/tty
    print_success "Fish shell set as default."
}

# Add GitHub to known hosts to avoid prompts
add_github_to_known_hosts() {
    print_message "Ensuring GitHub is in known hosts..."
    local known_hosts_file=~/.ssh/known_hosts
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    touch "${known_hosts_file}"
    chmod 600 "${known_hosts_file}"

    if ! ssh-keygen -F github.com &>/dev/null; then
        print_message "Adding GitHub's SSH key to known_hosts..."
        if ! ssh-keyscan github.com >> "${known_hosts_file}" 2>/dev/null; then
            print_error "Failed to add GitHub's SSH key to known_hosts."
            return 1
        fi
        print_success "GitHub's SSH key added."
    else
        print_debug "GitHub's SSH key already exists in known_hosts."
    fi
}

# Install Claude Code using bun
install_claude_code() {
    # Uninstall any existing npm/bun versions to clean up
    if command -v npm &> /dev/null; then
        if npm list -g @anthropic-ai/claude-code &> /dev/null 2>&1; then
            print_message "Removing npm-based Claude Code installation..."
            npm uninstall -g @anthropic-ai/claude-code 2>/dev/null || true
        fi
    fi

    if [[ -d "${HOME}/.bun" ]]; then
        export PATH="${HOME}/.bun/bin:${PATH}"
    fi

    if command -v bun &> /dev/null; then
        local _bun_global_list
        _bun_global_list=$(bun pm ls -g 2>/dev/null) || true
        if echo "${_bun_global_list}" | grep -q "@anthropic-ai/claude-code"; then
            print_message "Removing bun-based Claude Code installation..."
            bun remove -g @anthropic-ai/claude-code 2>/dev/null || true
        fi
    fi

    # Clean up stale lock files
    rm -rf "${HOME}/.local/state/claude/locks" 2>/dev/null

    # Skip if native version already installed
    if [[ -x "${HOME}/.local/bin/claude" ]]; then
        print_debug "Claude Code is already installed (native)."
        return 0
    fi

    print_message "Installing Claude Code via official installer..."
    local _claude_install_script
    _claude_install_script=$(curl -fsSL https://claude.ai/install.sh)
    if bash <<< "${_claude_install_script}"; then
        print_success "Claude Code installed."
    else
        print_error "Failed to install Claude Code."
        return 1
    fi
}

# Configure Rube MCP server for Claude Code and Codex with Bearer token auth
setup_rube_mcp() {
    # Rube is only needed on work machines (personal machines use claude.ai integrations)
    if [[ "${WORK_MACHINE:-}" != "1" ]]; then
        print_debug "Not a work machine. Skipping Rube MCP setup."
        return 0
    fi

    # Source Rube token if not already set
    if [[ -z "${RUBE_API_KEY}" ]] && [[ -f "${HOME}/.env.local" ]]; then
        set -a
        # shellcheck source=/dev/null
        source "${HOME}/.env.local"
        set +a
    fi

    # Check if token is available
    if [[ -z "${RUBE_API_KEY}" ]]; then
        print_warning "RUBE_API_KEY not set. Skipping Rube MCP setup."
        print_debug "Set RUBE_API_KEY in ~/.env.local"
        return 0
    fi

    # Configure for Claude Code
    if command -v claude &> /dev/null; then
        # Remove existing config for idempotency (may have old auth or scope)
        local _mcp_list
        _mcp_list=$(claude mcp list 2>/dev/null) || true
        if echo "${_mcp_list}" | grep -q "rube"; then
            print_message "Removing existing Claude Code Rube MCP configuration..."
            claude mcp remove rube -s user 2>/dev/null || true
            claude mcp remove rube 2>/dev/null || true
        fi

        print_message "Configuring Rube MCP server for Claude Code..."
        if claude mcp add --transport http rube -s user "https://rube.app/mcp" \
            --header "Authorization:Bearer ${RUBE_API_KEY}" >/dev/null 2>&1; then
            print_success "Rube MCP server configured for Claude Code."
        else
            print_warning "Failed to configure Rube MCP server for Claude Code."
        fi
    else
        print_debug "Claude Code not found. Skipping Claude Code Rube MCP setup."
    fi

    # Configure for Codex
    if command -v codex &> /dev/null; then
        local codex_config_dir="${HOME}/.codex"
        local codex_config="${codex_config_dir}/config.toml"

        mkdir -p "${codex_config_dir}"

        # Remove existing rube section for idempotency
        if [[ -f "${codex_config}" ]] && grep -q '\[mcp_servers\.rube\]' "${codex_config}"; then
            awk '
                /^\[mcp_servers\.rube\]/ { skip=1; next }
                /^\[/ { skip=0 }
                !skip { print }
            ' "${codex_config}" > "${codex_config}.tmp" && mv "${codex_config}.tmp" "${codex_config}"
        fi

        # Append rube MCP config
        print_message "Configuring Rube MCP server for Codex..."
        {
            echo ""
            echo "[mcp_servers.rube]"
            echo 'url = "https://rube.app/mcp"'
            echo 'bearer_token_env_var = "RUBE_API_KEY"'
        } >> "${codex_config}"
        print_success "Rube MCP server configured for Codex."
    else
        print_debug "Codex not found. Skipping Codex Rube MCP setup."
    fi
}

# Install Compound Engineering plugin for Claude Code
setup_compound_plugin() {
    if ! command -v claude &> /dev/null; then
        print_debug "Claude Code not found. Skipping Compound plugin setup."
        return 0
    fi

    if [[ "${BAN_COMPOUND_PLUGIN:-}" == "1" ]]; then
        local _claude_plugin_list
        _claude_plugin_list=$(claude plugin list 2>/dev/null) || true
        if echo "${_claude_plugin_list}" | grep -q "compound-engineering@"; then
            print_message "BAN_COMPOUND_PLUGIN=1, uninstalling Compound Engineering plugin..."
            local _output
            if _output=$(claude plugin uninstall compound-engineering@compound-engineering-plugin 2>&1); then
                print_success "Compound Engineering plugin uninstalled."
            else
                print_warning "Failed to uninstall Compound Engineering plugin: ${_output}"
            fi
        else
            print_debug "BAN_COMPOUND_PLUGIN=1, Compound Engineering not installed."
        fi
        return 0
    fi

    # Ensure marketplace is registered
    local _output
    if ! _output=$(claude plugin marketplace add EveryInc/compound-engineering-plugin 2>&1); then
        print_warning "Failed to register Compound Engineering marketplace: ${_output}"
    fi

    # Try install first (succeeds if not installed), then update (succeeds if already installed)
    print_message "Installing/updating Compound Engineering plugin..."
    if _output=$(claude plugin install compound-engineering --scope user 2>&1); then
        print_success "Compound Engineering plugin installed."
    elif _output=$(claude plugin update compound-engineering@compound-engineering-plugin 2>&1); then
        print_success "Compound Engineering plugin updated."
    else
        print_warning "Failed to install/update Compound Engineering plugin: ${_output}"
    fi
}

# Install Gemini CLI (Google's AI coding agent)
install_gemini_cli() {
    if command -v gemini &> /dev/null; then
        print_debug "Gemini CLI is already installed."
        return
    fi

    print_message "Installing Gemini CLI..."

    # Ensure bun is available
    if [[ -d "${HOME}/.bun" ]]; then
        export PATH="${HOME}/.bun/bin:${PATH}"
    fi

    if ! command -v bun &> /dev/null; then
        print_warning "Bun not found. Cannot install Gemini CLI."
        print_debug "Install Bun first, then run: bun install -g @google/gemini-cli"
        return
    fi

    if bun install -g @google/gemini-cli; then
        print_success "Gemini CLI installed."
    else
        print_error "Failed to install Gemini CLI."
    fi
}

# Install Codex CLI (OpenAI's AI coding agent)
install_codex_cli() {
    if command -v codex &> /dev/null; then
        print_debug "Codex CLI is already installed."
        return
    fi

    print_message "Installing Codex CLI..."

    # Ensure bun is available
    if [[ -d "${HOME}/.bun" ]]; then
        export PATH="${HOME}/.bun/bin:${PATH}"
    fi

    if ! command -v bun &> /dev/null; then
        print_warning "Bun not found. Cannot install Codex CLI."
        print_debug "Install Bun first, then run: bun install -g @openai/codex"
        return
    fi

    if bun install -g @openai/codex; then
        print_success "Codex CLI installed."
    else
        print_error "Failed to install Codex CLI."
    fi
}

# Install Bun JavaScript runtime
install_bun() {
    if [[ -d "${HOME}/.bun" ]]; then
        print_debug "Bun is already installed."
        return
    fi

    print_message "Installing Bun..."
    local bun_install
    bun_install=$(curl -fsSL https://bun.sh/install)
    if bash <<< "${bun_install}"; then
        print_success "Bun installed."
    else
        print_error "Failed to install Bun."
    fi
}

# Install Socket Firewall for supply chain security scanning
install_sfw() {
    if command -v sfw &> /dev/null; then
        print_debug "sfw is already installed."
        return
    fi

    # Ensure bun is available
    if [[ -d "${HOME}/.bun" ]]; then
        export PATH="${HOME}/.bun/bin:${PATH}"
    fi

    if ! command -v bun &> /dev/null; then
        print_warning "Bun not found. Cannot install Socket Firewall."
        print_debug "Install Bun first, then run: bun install -g sfw"
        return
    fi

    print_message "Installing Socket Firewall..."
    if bun install -g sfw > /dev/null 2>&1; then
        print_success "Socket Firewall installed."
    else
        print_error "Failed to install Socket Firewall."
    fi
}

# Install tmux plugins for session persistence
install_tmux_plugins() {
    local plugin_dir=~/.tmux/plugins
    if [[ ! -d "${plugin_dir}/tpm" ]]; then
        print_message "Installing tmux plugin manager..."
        git clone -q https://github.com/tmux-plugins/tpm "${plugin_dir}/tpm"
        print_success "tmux plugin manager installed."
    else
        print_debug "tmux plugin manager already installed."
    fi

    for plugin in tmux-resurrect tmux-continuum; do
        if [[ ! -d "${plugin_dir}/${plugin}" ]]; then
            print_message "Installing ${plugin}..."
            git clone -q "https://github.com/tmux-plugins/${plugin}" "${plugin_dir}/${plugin}"
            print_success "${plugin} installed."
        else
            print_debug "${plugin} already installed."
        fi
    done

    tmux source ~/.tmux.conf 2> /dev/null || print_warning "tmux not started; source tmux.conf manually if needed."
    ~/.tmux/plugins/tpm/bin/install_plugins > /dev/null
    print_success "tmux plugins installed and updated."
}

update_brew() {
    print_message "Updating Homebrew..."
    brew update > /dev/null
    print_message "Upgrading outdated packages..."
    brew upgrade > /dev/null
    print_success "Homebrew updated."
}

# Upgrade global npm packages
upgrade_npm_global_packages() {
    # Make sure npm is available
    if ! command -v npm &> /dev/null; then
        print_warning "npm not found. Skipping global package upgrade."
        return
    fi

    print_message "Upgrading global npm packages..."
    if npm update -g &> /dev/null; then
        print_success "Global npm packages upgraded."
    else
        print_warning "Failed to upgrade some global npm packages."
    fi
}

# Setup shared /tmp/claude directory for multi-user Claude Code access
setup_claude_shared_directory() {
    local claude_tmp="/tmp/claude"

    print_message "Setting up shared Claude Code temp directory..."

    if [[ -d "${claude_tmp}" ]]; then
        # Check current permissions (macOS stat syntax)
        local current_perms
        current_perms=$(stat -f "%OLp" "${claude_tmp}" 2>/dev/null)

        if [[ "${current_perms}" == "1777" ]]; then
            print_debug "Claude temp directory already has correct permissions."
            return 0
        fi

        # Try to fix permissions
        print_message "Fixing permissions on ${claude_tmp}..."

        local owner_uid
        owner_uid=$(stat -f "%u" "${claude_tmp}" 2>/dev/null)
        local current_uid
        current_uid=$(id -u)

        if [[ "${owner_uid}" == "${current_uid}" ]]; then
            if chmod 1777 "${claude_tmp}"; then
                print_success "Fixed permissions on Claude temp directory."
                return 0
            fi
        fi

        if can_sudo; then
            if sudo chmod 1777 "${claude_tmp}"; then
                print_success "Fixed permissions on Claude temp directory (with sudo)."
                return 0
            fi
        fi

        print_warning "Cannot fix permissions on ${claude_tmp}."
        print_debug "Ask an admin to run: sudo chmod 1777 ${claude_tmp}"
        return 0
    else
        if mkdir -p "${claude_tmp}" && chmod 1777 "${claude_tmp}"; then
            print_success "Created shared Claude temp directory."
            return 0
        fi

        if can_sudo; then
            if sudo mkdir -p "${claude_tmp}" && sudo chmod 1777 "${claude_tmp}"; then
                print_success "Created shared Claude temp directory (with sudo)."
                return 0
            fi
        fi

        print_warning "Cannot create ${claude_tmp}."
        print_debug "Ask an admin to run: sudo mkdir -p ${claude_tmp} && sudo chmod 1777 ${claude_tmp}"
        return 0
    fi
}

# Setup ~/Code directory
setup_code_directory() {
    local code_dir="${HOME}/Code"

    print_message "Setting up \$HOME/Code directory..."

    # Create ~/Code directory if it doesn't exist
    if [[ ! -d "${code_dir}" ]]; then
        mkdir -p "${code_dir}"
        print_success "Created \$HOME/Code directory."
    else
        print_debug "\$HOME/Code directory already exists."
    fi
}

# Install Telegram plugin for Claude Code
setup_telegram_plugin() {
    if ! command -v claude &> /dev/null; then
        print_debug "Claude Code not found. Skipping Telegram plugin setup."
        return 0
    fi

    # Ensure the official plugins marketplace is registered
    local _output
    if ! _output=$(claude plugin marketplace add anthropics/claude-plugins-official 2>&1); then
        print_warning "Failed to register official plugins marketplace: ${_output}"
    fi

    # Try install first (succeeds if not installed), then update (succeeds if already installed)
    print_message "Installing/updating Telegram plugin..."
    if _output=$(claude plugin install telegram@claude-plugins-official 2>&1); then
        print_success "Telegram plugin installed."
    elif _output=$(claude plugin update telegram@claude-plugins-official 2>&1); then
        print_success "Telegram plugin updated."
    else
        print_warning "Failed to install/update Telegram plugin: ${_output}"
    fi
}

# Upload log to centralized collector (non-fatal)
upload_log() {
    if [[ -n "${log_file:-}" ]] && [[ -f "${log_file:-}" ]]; then
        print_debug "Uploading log to logs.scowalt.com..."
        curl -s -X POST \
            -F "file=@${log_file}" \
            "https://logs.scowalt.com/upload?hostname=$(hostname)" \
            --max-time 10 \
            > /dev/null 2>&1 || true
    fi
}

install_betterdisplay() {
    if [[ "${HEADLESS}" != "1" ]]; then
        return
    fi

    if brew list --cask betterdisplay &>/dev/null 2>&1; then
        print_debug "BetterDisplay is already installed."
        return
    fi

    print_message "Installing BetterDisplay for headless display management..."
    if brew install --cask betterdisplay; then
        print_success "BetterDisplay installed."
    else
        print_error "Failed to install BetterDisplay."
    fi
}

configure_power_settings() {
    if [[ "${HEADLESS}" != "1" ]]; then
        return
    fi

    if ! can_sudo; then
        print_warning "No sudo access — cannot configure power settings."
        return
    fi

    print_message "Configuring power settings for headless operation..."

    local changed=false

    # Disable system sleep (0 = never sleep)
    if [[ "$(sudo pmset -g custom 2>/dev/null | awk '/^ sleep/{print $2; exit}')" != "0" ]]; then
        sudo pmset -a sleep 0
        changed=true
    fi

    # Disable display sleep
    if [[ "$(sudo pmset -g custom 2>/dev/null | awk '/^ displaysleep/{print $2; exit}')" != "0" ]]; then
        sudo pmset -a displaysleep 0
        changed=true
    fi

    # Disable hard disk sleep
    if [[ "$(sudo pmset -g custom 2>/dev/null | awk '/^ disksleep/{print $2; exit}')" != "0" ]]; then
        sudo pmset -a disksleep 0
        changed=true
    fi

    # Restart automatically after a power failure
    if [[ "$(sudo pmset -g custom 2>/dev/null | awk '/^ autorestart/{print $2; exit}')" != "1" ]]; then
        sudo pmset -a autorestart 1
        changed=true
    fi

    # Wake on network access (for SSH/remote access)
    if [[ "$(sudo pmset -g custom 2>/dev/null | awk '/^ womp/{print $2; exit}')" != "1" ]]; then
        sudo pmset -a womp 1
        changed=true
    fi

    if [[ "${changed}" == "true" ]]; then
        print_success "Power settings configured for headless operation (never sleep, auto-restart on power loss)."
    else
        print_debug "Power settings already configured for headless operation."
    fi
}

enable_screen_sharing() {
    if [[ "${HEADLESS}" != "1" ]]; then
        return
    fi

    if ! can_sudo; then
        print_warning "No sudo access — cannot enable Screen Sharing."
        return
    fi

    # Ensure the screensharing launchd job is loaded
    if ! sudo launchctl list com.apple.screensharing &>/dev/null; then
        print_message "Loading Screen Sharing launchd job..."
        sudo launchctl load -w /System/Library/LaunchDaemons/com.apple.screensharing.plist 2>/dev/null
        sudo launchctl enable system/com.apple.screensharing 2>/dev/null
    fi

    # Verify Screen Sharing is properly enabled via System Settings.
    # The launchd job can be loaded and VNC port listening, but connections get rejected
    # if Screen Sharing was never toggled on in System Settings. The kickstart command
    # prints "must be enabled from System Settings" when this is the case.
    local kickstart="/System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart"
    local tmpfile
    tmpfile=$(mktemp)
    sudo "$kickstart" -activate &>"$tmpfile" &
    local pid=$!
    ( sleep 10 && kill "$pid" 2>/dev/null ) &
    local watchdog=$!
    wait "$pid" 2>/dev/null
    kill "$watchdog" 2>/dev/null
    wait "$watchdog" 2>/dev/null
    local kickstart_output
    kickstart_output=$(cat "$tmpfile")
    rm -f "$tmpfile"
    if echo "$kickstart_output" | grep -q "must be enabled from System Settings"; then
        print_error "Screen Sharing is NOT properly enabled."
        print_error "The launchd job is loaded but macOS requires manual GUI enablement:"
        print_error "  1. Open System Settings → General → Sharing"
        print_error "  2. Toggle ON 'Screen Sharing'"
        print_error "  3. Re-run this setup script to verify"
        print_error "If you cannot access the GUI, connect a monitor/keyboard temporarily."
    else
        print_debug "Screen Sharing is enabled and accepting connections."
    fi
}

main() {
    # Run the setup tasks
    current_user=$(whoami)
    echo -e "\n${BOLD}🍎 macOS Development Environment Setup${NC}"
    echo -e "${GRAY}Version 139 | Last changed: Add timeout to kickstart Screen Sharing check${NC}"

    # Log this run
    local log_dir="${HOME}/.local/log/machine-setup"
    mkdir -p "${log_dir}"
    local log_file
    log_file="${log_dir}/$(date +%Y-%m-%d-%H%M%S).log"
    exec > >(tee -a "${log_file}") 2>&1
    print_debug "Logging to ${log_file}"

    # Create ~/.env.local (migrating old token files if needed)
    create_env_local

    # Source env vars early so BAN_COMPOUND_PLUGIN etc. are available
    if [[ -f "${HOME}/.env.local" ]]; then
        set -a
        # shellcheck source=/dev/null
        source "${HOME}/.env.local"
        set +a
    fi

    print_section "Xcode Command Line Tools"
    install_xcode_cli_tools

    if is_main_user; then
        echo -e "${CYAN}Running full setup for main user (scowalt)${NC}"

        print_section "Package Manager Setup"
        install_homebrew

        print_section "Core Packages"
        install_core_packages
        install_secrets_manager

        # Block public upload services on work machines
        block_public_upload_services

        # Enable SSH with key-only auth
        enable_ssh

        # Install Tailscale as cask (GUI app) and start daemon
        setup_tailscale

        # Install Nerd Font for terminal icons (Starship prompt, etc.)
        install_nerd_font

        # Install BetterDisplay for headless machines with dummy HDMI
        install_betterdisplay

        # Prevent sleep on headless machines
        configure_power_settings

        # Enable Screen Sharing on headless machines (VNC access)
        enable_screen_sharing

        # Fix zsh permissions early (before any tool might invoke zsh)
        fix_zsh_compaudit

        print_section "SSH Configuration"
        setup_ssh_key || return 1
        add_github_to_known_hosts || return 1

        print_section "Code Directory Setup"
        setup_code_directory

    else
        echo -e "${CYAN}Running secondary user setup for ${current_user}${NC}"

        # Ensure Homebrew is in PATH (already installed by main user)
        local brew_env
        brew_env=$(/opt/homebrew/bin/brew shellenv) || true
        eval "${brew_env}"

        # Fix zsh permissions early (before any tool might invoke zsh)
        fix_zsh_compaudit

        print_section "SSH Configuration"
        add_github_to_known_hosts || return 1
    fi

    # Common setup for all users
    print_section "Shared Directories"
    setup_claude_shared_directory

    print_section "Dotfiles Management"

    # Check if we have access (via SSH, token, or deploy key)
    # If not, try interactive deploy key setup
    if check_dotfiles_access || setup_dotfiles_deploy_key; then
        # We have access, proceed with chezmoi setup

        # Bootstrap the credential helper before chezmoi (chicken-and-egg problem)
        # The helper script is part of dotfiles but we need it to pull dotfiles
        if [[ ! -x "${HOME}/.local/bin/git-credential-github-multi" ]]; then
            source_gh_tokens
            if [[ -n "${GH_TOKEN_SCOWALT}" ]] || [[ -n "${GH_TOKEN}" ]]; then
                print_message "Bootstrapping git credential helper..."
                mkdir -p "${HOME}/.local/bin"
                cat > "${HOME}/.local/bin/git-credential-github-multi" << 'HELPER_EOF'
#!/bin/bash
# Git credential helper that routes to different GitHub tokens based on repo owner
# Note: Uses simple variables instead of associative arrays for bash 3.2 compatibility (macOS default)
host=""
path=""
while IFS='=' read -r key value; do
    [[ -z "${key}" ]] && break
    case "${key}" in
        host) host="${value}" ;;
        path) path="${value}" ;;
    esac
done
[[ "${host}" != "github.com" ]] && exit 1
owner=""
[[ -n "${path}" ]] && owner=$(echo "${path}" | cut -d'/' -f1)
token=""
if [[ "${owner}" == "scowalt" ]] && [[ -n "${GH_TOKEN_SCOWALT}" ]]; then
    token="${GH_TOKEN_SCOWALT}"
elif [[ -n "${GH_TOKEN}" ]]; then
    token="${GH_TOKEN}"
fi
[[ -z "${token}" ]] && exit 1
echo "protocol=https"
echo "host=github.com"
echo "username=x-access-token"
echo "password=${token}"
HELPER_EOF
                chmod +x "${HOME}/.local/bin/git-credential-github-multi"
                print_success "Git credential helper bootstrapped."
            fi
        fi

        # Ensure ~/.local/bin is in PATH for the credential helper
        export PATH="${HOME}/.local/bin:${PATH}"

        # Set up the credential helper for GitHub
        setup_github_credential_helper

        initialize_chezmoi
        # chezmoi init --apply overwrites ~/.ssh/config, removing the
        # github-dotfiles host alias needed for deploy key access.
        # Re-bootstrap it before any further chezmoi network operations.
        bootstrap_ssh_config
        configure_chezmoi_git
        update_chezmoi
        chezmoi apply --force
        tmux source ~/.tmux.conf 2>/dev/null || true
    else
        print_warning "Skipping dotfiles management - no access to repository."
    fi

    print_section "Shell Configuration"
    if is_main_user; then
        set_fish_as_default_shell
    else
        # Secondary users have locked passwords, can't use chsh
        # Their shell must be set by main user with: sudo chsh -s /opt/homebrew/bin/fish <username>
        if [[ "${SHELL}" != "/opt/homebrew/bin/fish" ]]; then
            print_warning "Shell is not fish. Main user must run: sudo chsh -s /opt/homebrew/bin/fish ${current_user}"
        else
            print_debug "Fish shell is already the default shell."
        fi
    fi
    install_tmux_plugins

    print_section "Development Tools"
    install_bun
    install_sfw
    install_claude_code
    setup_rube_mcp
    setup_compound_plugin
    setup_telegram_plugin
    install_gemini_cli
    install_codex_cli

    if is_main_user; then
        print_section "Final Updates"
        update_brew
    fi

    upgrade_npm_global_packages

    echo -e "${GRAY}Run log saved to: ${log_file}${NC}"
    upload_log
    echo -e "\n${GREEN}${BOLD}✨ Setup complete!${NC}\n"
}

main "$@"
