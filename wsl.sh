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
print_debug() { printf "${GRAY}  %s${NC}\n" "$1"; }
print_error() { printf "${RED} %s${NC}\n" "$1"; }

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

# Ensure the script is not run as root
ensure_not_root() {
    if [[ "${EUID}" -eq 0 ]]; then
        print_section "Root User Detected"
        print_message "This script should be run as a regular user, not root."
        print_message "Run the following commands to create the 'scowalt' user:"
        echo ""
        echo "  # Create user with home directory"
        echo "  useradd -m -s /bin/bash -G sudo scowalt"
        echo ""
        echo "  # Set password for the new user"
        echo "  passwd scowalt"
        echo ""
        echo "  # Switch to the new user and re-run this script"
        echo "  su - scowalt"
        echo ""
        return 0
    fi
}

# Bootstrap SSH config for deploy key access to dotfiles
bootstrap_ssh_config() {
    # Ensure github-dotfiles host alias exists for deploy key access
    if ! grep -q "Host github-dotfiles" ~/.ssh/config 2>/dev/null; then
        print_message "Bootstrapping SSH config for dotfiles access..."
        mkdir -p ~/.ssh
        chmod 700 ~/.ssh
        cat >> ~/.ssh/config << 'EOF'

# Deploy key for read-only access to scowalt/dotfiles
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

    # Copy to clipboard via Windows clip.exe if available
    if command -v clip.exe &>/dev/null; then
        clip.exe < "${key_file}.pub" 2>/dev/null && print_success "Public key copied to clipboard!"
    fi
    echo ""

    # Open GitHub in browser via Windows
    powershell.exe -Command "Start-Process 'https://github.com/scowalt/dotfiles/settings/keys'" 2>/dev/null || true

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

    # Method 1: SSH key (main user)
    # < /dev/null prevents ssh from consuming stdin (important for curl|bash)
    local _ssh_output
    _ssh_output=$(ssh -T git@github.com < /dev/null 2>&1) || true
    if echo "${_ssh_output}" | grep -q "successfully authenticated"; then
        print_debug "Access via SSH"
        return 0
    fi

    # Method 2: Deploy key at ~/.ssh/dotfiles-deploy-key
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

# Fix apt issues if they exist
fix_apt_issues() {
    if ! can_sudo; then
        print_debug "No sudo access - skipping apt fix."
        return
    fi
    print_message "Checking for package manager issues..."
    sudo apt-get update -qq
    sudo apt-get install -f -y -qq
}

# Update and install core dependencies with error handling
update_and_install_core() {
    print_message "Checking and installing core packages as needed..."

    # Define an array of required packages
    local packages=("git" "curl" "jq" "fish" "tmux" "gh" "build-essential" "libssl-dev" "zlib1g-dev" "libbz2-dev" "libreadline-dev" "libsqlite3-dev" "wget" "llvm" "libncurses5-dev" "libncursesw5-dev" "xz-utils" "tk-dev" "libffi-dev" "liblzma-dev" "golang-go" "inotify-tools")
    local to_install=()

    # Check each package and add missing ones to the to_install array
    for package in "${packages[@]}"; do
        if ! dpkg -s "${package}" &> /dev/null; then
            to_install+=("${package}")
        else
            print_debug "${package} is already installed."
        fi
    done

    # Install any packages that are not yet installed
    if [[ "${#to_install[@]}" -gt 0 ]]; then
        if ! can_sudo; then
            print_warning "No sudo access - cannot install missing packages: ${to_install[*]}"
            print_debug "Ask an admin to run: sudo apt install ${to_install[*]}"
            return
        fi
        print_message "Installing missing packages: ${to_install[*]}"
        sudo apt update -qq
        if ! sudo apt install -qq -y "${to_install[@]}"; then
            print_error "Failed to install core packages: ${to_install[*]}"
            print_message "Trying to fix package issues..."
            fix_apt_issues
            if ! sudo apt install -qq -y "${to_install[@]}"; then
                print_error "Failed to install core packages after fixing. Please check manually."
                return 1
            fi
        fi
        print_success "Missing core packages installed."
    else
        print_success "All core packages are already installed."
    fi
}


# Check and set up SSH key
setup_ssh_key() {
    # Skip SSH key setup for non-sudo users (they won't be making outbound SSH requests)
    if ! can_sudo; then
        print_debug "No sudo access - skipping SSH key setup."
        return
    fi

    print_message "Checking for existing SSH key associated with GitHub..."

    # Retrieve GitHub-associated keys and log for debug purposes
    local existing_keys
    existing_keys=$(curl -s https://github.com/scowalt.keys)

    # Check if a local SSH key exists
    if [[ -f ~/.ssh/id_rsa.pub ]]; then
        # Extract only the actual key part from id_rsa.pub and log for debugging
        local local_key
        local_key=$(awk '{print $2}' ~/.ssh/id_rsa.pub)

        # Verify if the extracted key part matches any of the GitHub keys
        if echo "${existing_keys}" | grep -q "${local_key}"; then
            print_success "Existing SSH key recognized by GitHub."
        else
            print_error "SSH key not recognized by GitHub. Please add it manually."
            print_message "Please add the following SSH key to GitHub:"
            cat ~/.ssh/id_rsa.pub
            print_message "Opening GitHub SSH keys page..."
            powershell.exe -Command "Start-Process 'https://github.com/settings/keys'" 2>/dev/null || true
            return 1
        fi
    else
        # Generate a new SSH key and log details
        print_warning "No SSH key found. Generating a new SSH key..."
        ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N "" -C "scowalt@wsl"
        print_success "SSH key generated."
        print_message "Please add the following SSH key to GitHub:"
        cat ~/.ssh/id_rsa.pub
        print_message "Opening GitHub SSH keys page..."
        powershell.exe -Command "Start-Process 'https://github.com/settings/keys'" 2>/dev/null || true
        return 1
    fi
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

# Install Homebrew if not installed
install_homebrew() {
    if ! command -v brew &> /dev/null; then
        print_message "Installing Homebrew..."
        local install_script
        install_script=$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)
        if ! /bin/bash -c "${install_script}"; then
            print_error "Failed to install Homebrew. Please check your internet connection."
            return 1
        fi
        local brew_env
        brew_env=$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)
        eval "${brew_env}"
        print_success "Homebrew installed."
    else
        print_debug "Homebrew is already installed."
        local brew_env
        brew_env=$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)
        eval "${brew_env}"
    fi
}

# Ensure Homebrew is available before using it
ensure_brew_available() {
    if ! command -v brew &> /dev/null; then
        print_error "Homebrew not available. Previous installation may have failed."
        return 1
    fi
}

# Install Starship if not installed
# NOTE: Uses Homebrew for WSL because it provides consistent Linux binary management
# DO NOT change to curl installer - Homebrew integration is intentional for WSL
install_starship() {
    if ! command -v starship &> /dev/null; then
        print_message "Installing Starship prompt..."
        ensure_brew_available
        if ! brew install starship; then
            print_error "Failed to install Starship via Homebrew."
            return 1
        fi
        print_success "Starship installed."
    else
        print_debug "Starship is already installed."
    fi
}

# Install chezmoi if not installed
install_chezmoi() {
    if ! command -v chezmoi &> /dev/null; then
        print_message "Installing chezmoi..."
        ensure_brew_available
        if ! brew install chezmoi; then
            print_error "Failed to install chezmoi via Homebrew."
            return 1
        fi
        print_success "chezmoi installed."
    else
        print_debug "chezmoi is already installed."
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
        local _current_user
        _current_user=$(whoami)
        if [[ "${_current_user}" == "scowalt" ]]; then
            # Main user uses SSH with default key for push access
            if ! chezmoi init --apply --force scowalt/dotfiles --ssh; then
                print_error "Failed to initialize chezmoi. Check SSH key and network connectivity."
                return 1
            fi
        else
            # Secondary users use SSH via deploy key (github-dotfiles alias)
            if ! chezmoi init --apply --force "git@github-dotfiles:scowalt/dotfiles.git"; then
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
    if [[ -d ~/.local/share/chezmoi ]]; then
        print_message "Updating chezmoi dotfiles repository..."
        if chezmoi update --force > /dev/null; then
            print_success "chezmoi dotfiles repository updated."
        else
            print_warning "Failed to update chezmoi dotfiles repository. Continuing anyway."
        fi
    else
        print_debug "chezmoi not initialized yet, skipping update."
    fi
}

# Set Fish as the default shell if it isn't already
set_fish_as_default_shell() {
    local user_shell
    local passwd_entry
    passwd_entry=$(getent passwd "${USER}")
    user_shell=$(echo "${passwd_entry}" | cut -d: -f7)
    if [[ "${user_shell}" == "/usr/bin/fish" ]]; then
        print_debug "Fish shell is already the default shell."
        return
    fi

    if ! can_sudo; then
        print_warning "No sudo access - cannot change default shell to fish."
        print_debug "Ask an admin to run: sudo chsh -s /usr/bin/fish ${USER}"
        return
    fi

    print_message "Setting Fish as the default shell..."
    if ! grep -Fxq "/usr/bin/fish" /etc/shells; then
        echo "/usr/bin/fish" | sudo tee -a /etc/shells > /dev/null
    fi
    # shellcheck disable=SC2024
    sudo chsh -s /usr/bin/fish "${USER}" < /dev/tty
    print_success "Fish shell set as default."
}

# Install jj (Jujutsu) version control by downloading binary directly
install_jj() {
    if command -v jj &> /dev/null; then
        print_debug "jj (Jujutsu) is already installed."
        return
    fi

    print_message "Installing jj (Jujutsu) via direct binary download..."

    # Detect architecture
    local arch
    arch=$(dpkg --print-architecture)
    local jj_arch

    case "${arch}" in
        amd64)
            jj_arch="x86_64-unknown-linux-musl"
            ;;
        arm64)
            jj_arch="aarch64-unknown-linux-musl"
            ;;
        *)
            print_error "Unsupported architecture for jj: ${arch}"
            return 1
            ;;
    esac

    # Create local bin directory if it doesn't exist
    local bin_dir="${HOME}/.local/bin"
    mkdir -p "${bin_dir}"

    # Get the latest version tag
    local latest_version
    latest_version=$(curl -sL "https://api.github.com/repos/jj-vcs/jj/releases/latest" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/') || true
    if [[ -z "${latest_version}" ]]; then
        print_error "Failed to get latest jj version."
        return 1
    fi

    # Download the latest binary
    local download_url="https://github.com/jj-vcs/jj/releases/download/${latest_version}/jj-${latest_version}-${jj_arch}.tar.gz"
    local temp_dir
    temp_dir=$(mktemp -d)

    print_message "Downloading jj ${latest_version} for ${arch} architecture..."
    local tarball="${temp_dir}/jj.tar.gz"
    if ! curl -sL "${download_url}" -o "${tarball}"; then
        print_error "Failed to download jj."
        rm -rf "${temp_dir}"
        return 1
    fi
    if tar -xzf "${tarball}" -C "${temp_dir}"; then
        # Move binary to local bin
        if mv "${temp_dir}/jj" "${bin_dir}/jj"; then
            chmod +x "${bin_dir}/jj"
            print_success "jj installed to ${bin_dir}/jj"

            # Add to PATH if not already present
            if ! echo "${PATH}" | grep -q "${bin_dir}"; then
                print_message "Adding ${bin_dir} to PATH in ~/.bashrc"
                echo "export PATH=\${HOME}/.local/bin:\${PATH}" >> ~/.bashrc
                export PATH="${bin_dir}:${PATH}"
            fi
        else
            print_error "Failed to move jj binary."
            rm -rf "${temp_dir}"
            return 1
        fi
    else
        print_error "Failed to extract jj archive."
        rm -rf "${temp_dir}"
        return 1
    fi

    rm -rf "${temp_dir}"
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

install_happy_coder() {
    if command -v happy &> /dev/null; then
        print_debug "happy-coder is already installed."
        return 0
    fi

    print_message "Installing happy-coder..."
    if bun install -g happy-coder > /dev/null 2>&1; then
        print_success "happy-coder installed. Run 'happy --auth' to authenticate."
    else
        print_error "Failed to install happy-coder."
    fi
}

# Configure Rube MCP server for Claude Code and Codex with Bearer token auth
setup_rube_mcp() {
    # Source env.local if not already set
    if [[ -z "${RUBE_API_KEY}" ]] && [[ -f "${HOME}/.env.local" ]]; then
        set -a
        # shellcheck source=/dev/null
        source "${HOME}/.env.local"
        set +a
    fi

    # Check if token is available
    if [[ -z "${RUBE_API_KEY}" ]]; then
        print_warning "RUBE_API_KEY not set. Skipping Rube MCP setup."
        print_debug "Add RUBE_API_KEY=your_api_key to ~/.env.local"
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
            --header "Authorization:Bearer ${RUBE_API_KEY}" 2>/dev/null; then
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

    # Ensure marketplace is registered (idempotent, needed for updates too)
    claude plugin marketplace add EveryInc/compound-engineering-plugin 2>/dev/null

    # Update if already installed, install if not
    local _plugin_list
    _plugin_list=$(claude plugin list 2>/dev/null) || true
    if echo "${_plugin_list}" | grep -q "compound-engineering"; then
        print_message "Updating Compound Engineering plugin..."
        if claude plugin update compound-engineering@every-marketplace 2>/dev/null; then
            print_success "Compound Engineering plugin updated."
        else
            print_warning "Failed to update Compound Engineering plugin."
        fi
    else
        print_message "Installing Compound Engineering plugin..."
        if claude plugin install compound-engineering --scope user 2>/dev/null; then
            print_success "Compound Engineering plugin installed."
        else
            print_warning "Failed to install Compound Engineering plugin."
        fi
    fi
}

# Install Compound Engineering skills for Codex CLI
setup_codex_compound_skills() {
    if ! command -v codex &> /dev/null; then
        print_debug "Codex CLI not found. Skipping Compound skills setup for Codex."
        return 0
    fi

    local repo_dir="${HOME}/.local/share/compound-engineering-plugin"
    local skills_dir="${HOME}/.agents/skills"

    # Clone or update the repo
    if [[ -d "${repo_dir}/.git" ]]; then
        print_message "Updating Compound Engineering skills for Codex..."
        if git -C "${repo_dir}" pull --quiet 2>/dev/null; then
            print_success "Compound Engineering repo updated."
        else
            print_warning "Failed to update Compound Engineering repo."
        fi
    else
        print_message "Cloning Compound Engineering plugin for Codex skills..."
        rm -rf "${repo_dir}"
        if git clone --quiet https://github.com/EveryInc/compound-engineering-plugin.git "${repo_dir}" 2>/dev/null; then
            print_success "Compound Engineering repo cloned."
        else
            print_warning "Failed to clone Compound Engineering repo."
            return
        fi
    fi

    # Symlink each skill into ~/.agents/skills/
    if [[ -d "${repo_dir}/skills" ]]; then
        mkdir -p "${skills_dir}"
        local _skill
        for _skill in "${repo_dir}"/skills/*/; do
            local skill_name
            skill_name=$(basename "${_skill}")
            local current_link
            current_link=$(readlink "${skills_dir}/${skill_name}") || true
            if [[ ! -L "${skills_dir}/${skill_name}" ]] || [[ "${current_link}" != "${_skill%/}" ]]; then
                ln -sfn "${_skill%/}" "${skills_dir}/${skill_name}"
            fi
        done
        print_success "Compound Engineering skills linked for Codex."
    else
        print_warning "No skills directory found in Compound Engineering repo."
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

# Install fnm (Fast Node Manager)
install_fnm() {
    if command -v fnm &> /dev/null; then
        print_debug "fnm already installed."
        return
    fi

    print_message "Installing fnm (Fast Node Manager)..."
    ensure_brew_available
    if ! brew install fnm; then
        print_error "Failed to install fnm via Homebrew."
        return 1
    fi

    print_success "fnm installed. Shell configuration will be managed by chezmoi."
}

# Setup Node.js using fnm
setup_nodejs() {
    print_message "Setting up Node.js with fnm..."
    
    # Initialize fnm for current session (Homebrew installation)
    if command -v fnm &> /dev/null; then
        local fnm_env
        fnm_env=$(fnm env --use-on-cd)
        eval "${fnm_env}"
    else
        print_warning "fnm command not available. Skipping Node.js setup."
        return
    fi
    
    # Check if any Node.js version is installed
    local fnm_list_output
    fnm_list_output=$(fnm list)
    if echo "${fnm_list_output}" | grep -q .; then
        print_debug "Node.js version already installed."
        
        # Always install latest LTS and set as default to keep Node.js current
        print_message "Installing latest LTS Node.js..."
        if fnm install --lts; then
            fnm use lts-latest
            local lts_version
            lts_version=$(fnm current)
            fnm default "${lts_version}"
            print_success "Default Node.js set to ${lts_version}."
        else
            print_warning "Failed to install latest LTS. Keeping current default."
        fi

        # Check if a default/global version is set (in case LTS install above didn't set one)
        local current_version
        current_version=$(fnm current 2>/dev/null || echo "none")
        if [[ "${current_version}" == "none" ]] || [[ -z "${current_version}" ]]; then
            print_message "No global Node.js version set. Setting the first installed version as default..."
            local first_version
            local fnm_versions
            fnm_versions=$(fnm list)
            local filtered_versions
            filtered_versions=$(echo "${fnm_versions}" | grep -v "system")
            local first_line
            first_line=$(echo "${filtered_versions}" | head -n1)
            first_version=$(echo "${first_line}" | awk '{print $2}')
            if [[ -n "${first_version}" ]]; then
                fnm default "${first_version}"
                print_success "Set ${first_version} as default Node.js version."
            fi
        fi
    else
        print_message "No Node.js version installed. Installing latest LTS..."
        if fnm install --lts; then
            print_success "Installed latest LTS Node.js."
            # Set it as default
            local current_node
            current_node=$(fnm current)
            fnm default "${current_node}"
            local current_version_display
            current_version_display=$(fnm current)
            print_success "Set ${current_version_display} as default Node.js version."
        else
            print_error "Failed to install Node.js."
            return 1
        fi
    fi
}

# Fix 1Password repository GPG key issues
fix_1password_repository() {
    print_message "Checking for 1Password repository issues..."
    
    # Check if 1Password repository exists and has key issues
    local apt_policy
    apt_policy=$(apt-cache policy 2>/dev/null || true)
    local apt_update_output
    apt_update_output=$(apt update 2>&1 || true)
    if echo "${apt_policy}" | grep -q "1password.com" && echo "${apt_update_output}" | grep -q "EXPKEYSIG.*1Password"; then
        print_message "Fixing expired 1Password repository key..."
        
        # Remove the problematic repository
        sudo rm -f /etc/apt/sources.list.d/1password.list
        sudo rm -f /usr/share/keyrings/1password-archive-keyring.gpg
        
        print_success "Removed problematic 1Password repository."
    else
        print_debug "No 1Password repository issues detected."
    fi
}

# Install 1Password CLI
install_1password_cli() {
    if command -v op >/dev/null; then
        print_debug "1Password CLI already installed."
        return
    fi

    print_message "Installing 1Password CLI..."
    
    # Fix any existing repository issues first
    fix_1password_repository
    
    ensure_brew_available
    if ! brew install --cask 1password-cli; then
        print_error "Failed to install 1Password CLI via Homebrew."
        return 1
    fi
    print_success "1Password CLI installed."
}

# Install Tailscale
install_tailscale() {
    print_message "Skipping Tailscale installation as it is not needed on WSL."
}

# Install and configure unattended-upgrades for automatic security updates
setup_unattended_upgrades() {
    if ! can_sudo; then
        print_debug "No sudo access - skipping unattended-upgrades setup."
        return
    fi

    if dpkg -s unattended-upgrades &> /dev/null; then
        print_debug "unattended-upgrades is already installed."
    else
        print_message "Installing unattended-upgrades..."
        if ! sudo apt install -qq -y unattended-upgrades; then
            print_error "Failed to install unattended-upgrades."
            return 1
        fi
        print_success "unattended-upgrades installed."
    fi

    # Configure automatic updates
    local auto_upgrades_conf="/etc/apt/apt.conf.d/20auto-upgrades"
    if [[ ! -f "${auto_upgrades_conf}" ]] || ! grep -q "Unattended-Upgrade" "${auto_upgrades_conf}"; then
        print_message "Configuring automatic security updates..."
        local auto_upgrades_content
        auto_upgrades_content='APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";'
        echo "${auto_upgrades_content}" | sudo tee "${auto_upgrades_conf}" > /dev/null
        print_success "Automatic security updates configured."
    else
        print_debug "Automatic updates already configured."
    fi

    # Note: WSL doesn't use systemd by default, so we check if it's available
    if command -v systemctl &>/dev/null && systemctl is-system-running &>/dev/null; then
        if systemctl is-enabled unattended-upgrades &>/dev/null; then
            print_debug "unattended-upgrades service already enabled."
        else
            print_message "Enabling unattended-upgrades service..."
            sudo systemctl enable unattended-upgrades
            sudo systemctl start unattended-upgrades
            print_success "unattended-upgrades service enabled."
        fi
    else
        print_debug "Systemd not available (typical for WSL1). Unattended-upgrades will run via cron."
    fi
}

# Install OpenTofu (open-source Terraform fork)
install_opentofu() {
    if command -v tofu &> /dev/null; then
        print_debug "OpenTofu is already installed."
        return
    fi

    print_message "Installing OpenTofu..."
    ensure_brew_available
    if brew install opentofu; then
        print_success "OpenTofu installed."
    else
        print_error "Failed to install OpenTofu."
    fi
}

# Install cloudflared (Cloudflare Tunnel client)
install_cloudflared() {
    if command -v cloudflared &> /dev/null; then
        print_debug "cloudflared is already installed."
        return
    fi

    print_message "Installing cloudflared..."
    ensure_brew_available
    if brew install cloudflared; then
        print_success "cloudflared installed."
    else
        print_error "Failed to install cloudflared."
    fi
}

# Install Turso CLI (libSQL database platform)
install_turso() {
    if command -v turso &> /dev/null; then
        print_debug "Turso CLI is already installed."
        return
    fi

    print_message "Installing Turso CLI..."
    ensure_brew_available
    if brew install tursodatabase/tap/turso; then
        print_success "Turso CLI installed."
    else
        print_error "Failed to install Turso CLI."
    fi
}

# Install act for running GitHub Actions locally
install_act() {
    if ! command -v act &> /dev/null; then
        print_message "Installing act (GitHub Actions runner)..."
        ensure_brew_available
        if ! brew install act; then
            print_error "Failed to install act via Homebrew."
            return 1
        fi
        print_success "act installed."
    else
        print_debug "act is already installed."
    fi
}

# Install uv (fast Python package manager)
install_uv() {
    if command -v uv &> /dev/null; then
        print_debug "uv is already installed."
        return
    fi

    print_message "Installing uv..."
    ensure_brew_available
    if brew install uv; then
        print_success "uv installed."
    else
        print_error "Failed to install uv."
    fi
}

# Install pyenv for Python version management
install_pyenv() {
    if ! command -v pyenv &> /dev/null; then
        print_message "Installing pyenv..."
        ensure_brew_available
        if ! brew install pyenv; then
            print_error "Failed to install pyenv via Homebrew."
            return 1
        fi
        print_success "pyenv installed. Shell configuration will be managed by chezmoi."
    else
        print_debug "pyenv is already installed."
    fi
}

# Install Bun JavaScript runtime and package manager
install_bun() {
    if command -v bun &> /dev/null; then
        print_debug "Bun is already installed."
        return
    fi

    print_message "Installing Bun..."
    local bun_install_script
    bun_install_script=$(curl -fsSL https://bun.sh/install)
    if ! bash <<< "${bun_install_script}"; then
        print_error "Failed to install Bun."
        return 1
    fi

    # Add bun to PATH for current session
    export PATH="${HOME}/.bun/bin:${PATH}"
    
    print_success "Bun installed."
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

# Install iTerm2 shell integration for automatic profile switching
install_iterm2_shell_integration() {
    local shell_integration_file="${HOME}/.iterm2_shell_integration.fish"
    if [[ -f "${shell_integration_file}" ]]; then
        print_debug "iTerm2 shell integration already installed."
        return
    fi

    print_message "Installing iTerm2 shell integration..."
    if curl -fsSL https://iterm2.com/shell_integration/fish -o "${shell_integration_file}"; then
        chmod +x "${shell_integration_file}"
        print_success "iTerm2 shell integration installed."
    else
        print_warning "Failed to download iTerm2 shell integration."
    fi
}

update_packages() {
    print_message "Updating all packages..."
    brew update
    brew upgrade
    if can_sudo; then
        sudo apt update
        sudo apt upgrade -y
        sudo apt autoremove -y
    else
        print_warning "No sudo access - skipping apt system updates."
    fi
    print_success "Package updates completed."
}

# Upgrade global npm packages
upgrade_npm_global_packages() {
    # Make sure fnm is initialized
    ensure_brew_available
    if command -v fnm &> /dev/null; then
        local fnm_env
        fnm_env=$(fnm env --use-on-cd)
        eval "${fnm_env}"
    fi

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
        # Check current permissions (Linux stat syntax)
        local current_perms
        current_perms=$(stat -c "%a" "${claude_tmp}" 2>/dev/null)

        if [[ "${current_perms}" == "1777" ]]; then
            print_debug "Claude temp directory already has correct permissions."
            return 0
        fi

        # Try to fix permissions
        print_message "Fixing permissions on ${claude_tmp}..."

        local owner_uid
        owner_uid=$(stat -c "%u" "${claude_tmp}" 2>/dev/null)

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

main() {
    # Run the setup tasks
    echo -e "\n${BOLD}🐧 WSL Development Environment Setup${NC}"
    echo -e "${GRAY}Version 89 | Last changed: Fix shellcheck SC2312 in Codex skills symlink${NC}"

    # Create ~/.env.local (migrating old token files if needed)
    create_env_local

    print_section "User & System Setup"
    ensure_not_root
    update_and_install_core

    print_section "SSH Configuration"
    setup_ssh_key || return 1
    add_github_to_known_hosts || return 1

    current_user=$(whoami)
    if [[ "${current_user}" == "scowalt" ]]; then
        print_section "Code Directory Setup"
        setup_code_directory
    fi

    print_section "Package Manager"
    install_homebrew

    print_section "Development Tools"
    install_starship
    install_jj
    install_fnm
    setup_nodejs
    install_pyenv
    install_uv
    install_bun
    install_sfw
    install_opentofu
    install_cloudflared
    install_turso

    print_section "Security Tools"
    install_1password_cli
    install_tailscale
    setup_unattended_upgrades

    print_section "Shared Directories"
    setup_claude_shared_directory

    print_section "Dotfiles Management"

    # Check if we have access (via SSH or deploy key)
    # If not, try interactive deploy key setup
    if check_dotfiles_access || setup_dotfiles_deploy_key; then
        # We have access, proceed with chezmoi setup
        install_chezmoi
        initialize_chezmoi
        configure_chezmoi_git
        update_chezmoi
        chezmoi apply --force
        tmux source ~/.tmux.conf 2>/dev/null || true
    else
        print_warning "Skipping dotfiles management - no access to repository."
    fi

    print_section "Shell Configuration"
    set_fish_as_default_shell
    install_act
    install_tmux_plugins
    install_iterm2_shell_integration

    print_section "Additional Development Tools"
    install_claude_code
    install_happy_coder
    setup_rube_mcp
    setup_compound_plugin
    install_gemini_cli
    install_codex_cli
    setup_codex_compound_skills

    print_section "Final Updates"
    update_packages
    upgrade_npm_global_packages

    echo -e "\n${GREEN}${BOLD}✨ Setup complete!${NC}\n"
}

main "$@"