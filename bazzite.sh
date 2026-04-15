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
print_message() { printf "${CYAN}➜ %s${NC}\n" "$1"; }
print_success() { printf "${GREEN}✓ %s${NC}\n" "$1"; }
print_warning() { printf "${YELLOW}⚠ %s${NC}\n" "$1"; }
print_error() { printf "${RED}✗ %s${NC}\n" "$1"; }
print_debug() { printf "${GRAY}  %s${NC}\n" "$1"; }

# Migrate old token files (~/.gh_token, ~/.op_token) into ~/.env.local
migrate_token_files() {
    local env_file="${HOME}/.env.local"
    local migrated=0

    for old_file in "${HOME}/.gh_token" "${HOME}/.op_token"; do
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

# 1Password Service Account Token
# Create a service account at: https://my.1password.com/integrations/infrastructure-secrets
# OP_SERVICE_ACCOUNT_TOKEN=ops_xxx
EOF
        chmod 600 "${HOME}/.env.local"
        print_debug "Created placeholder ~/.env.local"
    fi
}

# Check if user is scowalt or a secondary user (<org>-scowalt pattern)
is_scowalt_user() {
    local user="${1:-$(whoami)}"
    [[ "${user}" == "scowalt" ]] || [[ "${user}" == *-scowalt ]]
}

# Check if running as main user (scowalt)
is_main_user() {
    local _whoami
    _whoami=$(whoami)
    [[ "${_whoami}" == "scowalt" ]]
}

# Check if user has a personal SSH key registered with GitHub
has_verified_ssh_key() {
    local local_key=""

    # Check for RSA key
    if [[ -f ~/.ssh/id_rsa.pub ]]; then
        local_key=$(awk '{print $2}' ~/.ssh/id_rsa.pub)
    # Check for ed25519 key
    elif [[ -f ~/.ssh/id_ed25519.pub ]]; then
        local_key=$(awk '{print $2}' ~/.ssh/id_ed25519.pub)
    else
        return 1
    fi

    # Verify key is registered with GitHub
    local existing_keys
    existing_keys=$(curl -s https://github.com/scowalt.keys 2>/dev/null) || return 1
    [[ -n "${local_key}" ]] && echo "${existing_keys}" | grep -q "${local_key}"
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

# Request sudo upfront and keep credentials fresh throughout script execution
# This avoids multiple password prompts during long-running scripts
request_sudo_upfront() {
    # Skip if user doesn't have sudo capability
    local _user_groups
    _user_groups=$(groups 2>/dev/null) || true
    if ! echo "${_user_groups}" | grep -qE '\b(sudo|wheel|admin)\b'; then
        print_debug "User not in sudo group, skipping sudo request."
        return 0
    fi

    # Check if credentials are already cached
    if sudo -n true 2>/dev/null; then
        print_debug "Sudo credentials already cached."
    else
        print_message "This script requires sudo access for system operations."
        print_message "Please enter your password once to authorize all operations."
        # shellcheck disable=SC2024
        if ! sudo -v < /dev/tty; then
            print_warning "Sudo authentication failed. Some operations will be skipped."
            return 1
        fi
    fi

    # Mark that we have sudo
    _sudo_checked=1
    _has_sudo=1

    # Start background process to keep credentials fresh
    # Refresh every 50 seconds (sudo timeout is typically 5-15 minutes)
    (
        while true; do
            sleep 50
            sudo -n true 2>/dev/null || exit 0
        done
    ) &
    SUDO_KEEPALIVE_PID=$!

    # Set up trap to kill the background process on exit
    trap 'kill "${SUDO_KEEPALIVE_PID}" 2>/dev/null' EXIT

    print_success "Sudo credentials cached for this session."
    return 0
}

# Ensure the script is not run as root
ensure_not_root() {
    if [[ "${EUID}" -eq 0 ]]; then
        print_section "Root User Detected"
        print_message "This script should be run as a regular user, not root."
        print_message "Run the following commands to create the 'scowalt' user:"
        echo ""
        echo "  # Create user with home directory"
        echo "  useradd -m -s /bin/bash -G wheel scowalt"
        echo ""
        echo "  # Set password for the new user"
        echo "  passwd scowalt"
        echo ""
        echo "  # Switch to the new user and re-run this script"
        echo "  su - scowalt"
        echo ""
        exit 1
    fi
}

# Verify we're running on Bazzite OS
verify_bazzite_system() {
    print_message "Verifying Bazzite OS..."

    if [[ ! -f /etc/os-release ]]; then
        print_error "Cannot detect operating system (/etc/os-release not found)."
        return 1
    fi

    if ! grep -qi "bazzite" /etc/os-release; then
        print_error "This script is designed for Bazzite OS only."
        print_message "Detected system:"
        grep "PRETTY_NAME" /etc/os-release
        return 1
    fi

    print_success "Bazzite OS confirmed."
}

# Ensure Homebrew is available in PATH
ensure_brew_available() {
    if command -v brew &> /dev/null; then
        print_debug "Homebrew is already in PATH."
        return 0
    fi

    # Try to initialize from Linuxbrew default location
    if [[ -x /home/linuxbrew/.linuxbrew/bin/brew ]]; then
        print_message "Initializing Homebrew..."
        local brew_env
        brew_env=$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)
        eval "${brew_env}"
        print_success "Homebrew initialized."
        return 0
    fi

    print_error "Homebrew not found. Bazzite should have Homebrew pre-installed."
    print_message "Try running: /home/linuxbrew/.linuxbrew/bin/brew shellenv"
    return 1
}

# Install core packages via Homebrew
install_core_packages() {
    print_message "Checking core packages..."

    # fish is pre-installed on Bazzite, so it's excluded from this list
    local packages=("git" "curl" "wget" "jq" "unzip" "tmux" "starship" "gh" "chezmoi" "opentofu" "go" "uv" "fswatch" "1password-cli" "tailscale" "act" "cloudflared" "tursodatabase/tap/turso" "shellcheck" "gitleaks" "lefthook" "mise" "poppler")
    local to_install=()

    # Get currently installed formulae
    local installed_formulae
    installed_formulae=$(brew list --formula -1 2>/dev/null)

    for package in "${packages[@]}"; do
        # Extract formula name (strip tap prefix for checking)
        local check_name="${package##*/}"
        if echo "${installed_formulae}" | grep -qx "${check_name}"; then
            print_debug "${check_name} is already installed."
        else
            to_install+=("${package}")
        fi
    done

    if [[ "${#to_install[@]}" -gt 0 ]]; then
        print_message "Installing missing packages: ${to_install[*]}"
        if ! brew install "${to_install[@]}"; then
            print_warning "Some packages failed to install. Continuing..."
        else
            print_success "Core packages installed."
        fi
    else
        print_success "All core packages are already installed."
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

# Enable Tailscale SSH for keyless access over Tailscale network
setup_tailscale_ssh() {
    if ! command -v tailscale &>/dev/null; then
        print_debug "Tailscale not installed, skipping SSH setup."
        return
    fi

    local run_ssh
    run_ssh=$(tailscale debug prefs 2>/dev/null | grep -o '"RunSSH":[a-z]*' | cut -d: -f2)
    if [[ "${run_ssh}" != "true" ]]; then
        print_message "Enabling Tailscale SSH..."
        sudo tailscale set --ssh
        print_success "Tailscale SSH enabled."
    else
        print_debug "Tailscale SSH is already enabled."
    fi
}

# Check and set up SSH key (simplified for physical machine — no VPS detection)
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
            xdg-open "https://github.com/settings/keys" 2>/dev/null || true
            return 1
        fi
    else
        print_warning "No SSH key found. Generating a new SSH key..."
        ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
        print_success "SSH key generated."
        print_message "Please add the following SSH key to GitHub:"
        cat ~/.ssh/id_rsa.pub
        print_message "Opening GitHub SSH keys page..."
        xdg-open "https://github.com/settings/keys" 2>/dev/null || true
        return 1
    fi
}

# Add GitHub to known hosts
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

    # Copy to clipboard if display is available
    if command -v wl-copy &>/dev/null && [[ -n "${WAYLAND_DISPLAY:-}" || -S "${XDG_RUNTIME_DIR:-}/wayland-0" ]]; then
        wl-copy < "${key_file}.pub" 2>/dev/null && print_success "Public key copied to clipboard!"
    elif command -v xclip &>/dev/null && [[ -n "${DISPLAY:-}" ]]; then
        xclip -selection clipboard < "${key_file}.pub" 2>/dev/null && print_success "Public key copied to clipboard!"
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

    # Method 1: User with verified SSH key on GitHub
    if has_verified_ssh_key; then
        # < /dev/null prevents ssh from consuming stdin (important for curl|bash)
        local _ssh_output
        _ssh_output=$(ssh -T git@github.com < /dev/null 2>&1) || true
        if echo "${_ssh_output}" | grep -q "successfully authenticated"; then
            print_debug "Access via SSH (verified key)"
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
    # Clear any existing helper first to avoid duplicates
    git config --global --unset-all credential.https://github.com.helper 2>/dev/null || true
    git config --global --add credential.https://github.com.helper ''
    git config --global --add credential.https://github.com.helper '!git-credential-github-multi'
    print_debug "Git configured to use multi-token credential helper for GitHub."
    return 0
}

# Configure DNS64 for IPv6-only networks
# This allows reaching IPv4-only hosts (like github.com) via NAT64
setup_dns64_for_ipv6_only() {
    # Check if we have IPv4 connectivity
    if ping -c 1 -W 3 8.8.8.8 &>/dev/null; then
        print_debug "IPv4 connectivity available, DNS64 not needed."
        return 0
    fi

    # Check if we have IPv6 connectivity
    if ! ping -6 -c 1 -W 3 2001:4860:4860::8888 &>/dev/null; then
        print_debug "No IPv6 connectivity, skipping DNS64 setup."
        return 0
    fi

    # Check if already configured
    if [[ -f /etc/systemd/resolved.conf.d/dns64.conf ]]; then
        print_debug "DNS64 already configured."
        return 0
    fi

    # Requires sudo to configure
    if ! can_sudo; then
        print_warning "IPv6-only network detected but no sudo access - cannot configure DNS64."
        print_debug "Ask an admin to configure DNS64 for NAT64 connectivity."
        return 0
    fi

    print_message "IPv6-only network detected. Configuring DNS64..."

    # Create systemd-resolved drop-in for DNS64 (using nat64.net public servers)
    sudo mkdir -p /etc/systemd/resolved.conf.d
    sudo tee /etc/systemd/resolved.conf.d/dns64.conf > /dev/null <<EOF
[Resolve]
DNS=2a00:1098:2c::1 2a00:1098:2b::1 2a01:4f8:c2c:123f::1
EOF

    if sudo systemctl restart systemd-resolved; then
        # Wait for DNS to settle
        sleep 2
        print_success "DNS64 configured for IPv6-only network."
    else
        print_error "Failed to restart systemd-resolved."
        return 1
    fi
}

# Install chezmoi if not installed
install_chezmoi() {
    if ! command -v chezmoi &> /dev/null; then
        print_message "Installing chezmoi..."
        local bin_dir="${HOME}/.local/bin"
        mkdir -p "${bin_dir}"
        local install_cmd
        install_cmd=$(curl -fsLS get.chezmoi.io)
        if sh -c "${install_cmd}" -- -b "${bin_dir}"; then
            export PATH="${bin_dir}:${PATH}"
            print_success "chezmoi installed."
        else
            print_error "Failed to install chezmoi."
            return 1
        fi
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
        if has_verified_ssh_key; then
            # User with verified SSH key uses default SSH for push access
            if ! chezmoi init --apply --force scowalt/dotfiles --ssh; then
                print_error "Failed to initialize chezmoi."
                return 1
            fi
        else
            # Other users use SSH via deploy key (github-dotfiles alias)
            if ! chezmoi init --apply --force "git@github-dotfiles:scowalt/dotfiles.git"; then
                print_error "Failed to initialize chezmoi."
                return 1
            fi
        fi
        print_success "chezmoi initialized with scowalt/dotfiles."
    else
        print_debug "chezmoi is already initialized."
    fi
}

# Fix chezmoi remote URL when switching from personal SSH to deploy key
fix_chezmoi_remote_for_deploy_key() {
    local chez_src="${HOME}/.local/share/chezmoi"
    [[ ! -d "${chez_src}/.git" ]] && return 0

    # Only fix if we're NOT using a verified personal SSH key
    if has_verified_ssh_key; then
        return 0
    fi

    # Check current remote URL
    local current_remote
    current_remote=$(git -C "${chez_src}" remote get-url origin 2>/dev/null) || return 0

    # If using github.com directly, switch to github-dotfiles alias for deploy key
    if [[ "${current_remote}" == "git@github.com:scowalt/dotfiles.git" ]]; then
        print_message "Updating chezmoi remote URL for deploy key access..."
        if git -C "${chez_src}" remote set-url origin "git@github-dotfiles:scowalt/dotfiles.git"; then
            print_success "Chezmoi remote URL updated to use deploy key."
        else
            print_warning "Failed to update chezmoi remote URL."
        fi
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
    local chez_src="${HOME}/.local/share/chezmoi"
    if [[ -d "${chez_src}" ]]; then
        print_message "Updating chezmoi dotfiles repository..."
        # Reset any dirty state (merge conflicts, uncommitted changes) before pulling.
        # The remote repo is the source of truth — local edits in the chezmoi source dir
        # should never exist and are safe to discard.
        if [[ -d "${chez_src}/.git" ]]; then
            git -C "${chez_src}" reset --hard HEAD > /dev/null 2>&1
            git -C "${chez_src}" merge --abort > /dev/null 2>&1
            git -C "${chez_src}" clean -fd > /dev/null 2>&1
        fi
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
    local current_shell
    local passwd_entry
    passwd_entry=$(getent passwd "${USER}")
    current_shell=$(echo "${passwd_entry}" | cut -d: -f7)
    if [[ "${current_shell}" != "/usr/bin/fish" ]]; then
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
    else
        print_debug "Fish shell is already the default shell."
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
    if bash <<< "${bun_install_script}"; then
        # Add bun to PATH for current session
        export PATH="${HOME}/.bun/bin:${PATH}"
        print_success "Bun installed."
    else
        print_error "Failed to install Bun."
        return 1
    fi
}

# Install Socket Firewall for supply chain security scanning
install_sfw() {
    if [[ "${WORK_MACHINE:-}" != "1" ]]; then
        print_debug "Skipping Socket Firewall (not a work machine)."
        return
    fi

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

# Install Claude Code using official installer
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
        local _bun_packages
        _bun_packages=$(bun pm ls -g 2>/dev/null) || true
        if echo "${_bun_packages}" | grep -q "@anthropic-ai/claude-code"; then
            print_message "Removing bun-based Claude Code installation..."
            bun remove -g @anthropic-ai/claude-code 2>/dev/null || true
        fi
    fi

    # Clean up stale lock files
    rm -rf "${HOME}/.local/state/claude/locks" 2>/dev/null

    # Skip installer if already on the latest version
    if command -v claude &> /dev/null; then
        local _installed_version _latest_version
        _installed_version=$(claude --version 2>/dev/null | head -1 | awk '{print $1}')
        _latest_version=$(curl -fsSL https://registry.npmjs.org/@anthropic-ai/claude-code/latest 2>/dev/null | grep -o '"version":"[^"]*"' | head -1 | cut -d'"' -f4)
        if [[ -n "${_installed_version}" && -n "${_latest_version}" && "${_installed_version}" == "${_latest_version}" ]]; then
            print_success "Claude Code already at latest version (${_installed_version})."
            return 0
        fi
    fi

    print_message "Installing/updating Claude Code via official installer..."
    local _install_script
    _install_script=$(curl -fsSL https://claude.ai/install.sh) || { print_error "Failed to download Claude Code installer."; return 1; }
    if bash <<< "${_install_script}"; then
        export PATH="${HOME}/.local/bin:${PATH}"
        print_success "Claude Code installed/updated."
    else
        print_error "Failed to install Claude Code."
        return 1
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

        local _current_uid
        _current_uid=$(id -u)
        if [[ "${owner_uid}" == "${_current_uid}" ]]; then
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

# Install/update ccgram (Telegram-to-tmux bridge for AI coding agents)
install_ccgram() {
    if ! command -v uv &> /dev/null; then
        print_warning "uv not found. Cannot install ccgram."
        return
    fi

    # Use system-native TLS instead of uv's bundled OpenSSL, which may not find
    # system CA certificates (especially behind TLS-intercepting proxies like sfw)
    export UV_NATIVE_TLS=true

    print_message "Installing/updating ccgram..."
    if uv tool install --force --upgrade ccgram --from "git+https://github.com/scowalt/ccgram.git@main"; then
        print_success "ccgram installed/updated."
    else
        print_error "Failed to install ccgram."
        return 1
    fi

    # Register Claude Code hooks for auto-detection and interactive UI
    if command -v ccgram &> /dev/null && command -v claude &> /dev/null; then
        print_message "Installing ccgram hooks..."
        if ccgram hook --install; then
            print_success "ccgram hooks installed."
        else
            print_warning "Failed to install ccgram hooks."
        fi
    fi
}

# Setup Compound Engineering plugin for Claude Code
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

# Upgrade global npm packages
upgrade_npm_global_packages() {
    # Initialize mise for current session (provides npm if Node.js is installed)
    if command -v mise &> /dev/null; then
        eval "$(mise activate bash)"
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

# Update Homebrew and upgrade packages
update_brew() {
    print_message "Updating Homebrew..."
    brew update > /dev/null
    # Pin tmux during upgrades to prevent killing existing sessions (ccgram, etc.)
    brew pin tmux 2>/dev/null || true
    print_message "Upgrading outdated packages..."
    brew upgrade > /dev/null
    brew unpin tmux 2>/dev/null || true
    print_success "Homebrew updated."
}

# Install packages via Homebrew (separate from core packages)
install_brew_packages() {
    if ! command -v brew &> /dev/null; then
        print_warning "Homebrew not available. Skipping brew packages."
        return 0
    fi

    local packages=("ffmpeg")
    local to_install=()

    for package in "${packages[@]}"; do
        if brew list "${package}" &> /dev/null 2>&1; then
            print_debug "${package} (brew) is already installed."
        else
            to_install+=("${package}")
        fi
    done

    if [[ "${#to_install[@]}" -gt 0 ]]; then
        print_message "Installing brew packages: ${to_install[*]}"
        brew install "${to_install[@]}" > /dev/null
        print_success "Brew packages installed."
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

install_whisper() {
    if pip3 show openai-whisper &> /dev/null; then
        print_debug "openai-whisper is already installed."
        return
    fi

    print_message "Installing openai-whisper..."
    if pip3 install --user --break-system-packages openai-whisper; then
        print_success "openai-whisper installed."
    else
        print_error "Failed to install openai-whisper."
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

main() {
    echo -e "\n${BOLD}🎮 Bazzite Development Environment Setup${NC}"
    echo -e "${GRAY}Version 25 | Last changed: Use UV_NATIVE_TLS for ccgram install SSL fix${NC}"

    # Log this run
    local log_dir="${HOME}/.local/log/machine-setup"
    mkdir -p "${log_dir}"
    local log_file
    log_file="${log_dir}/$(date +%Y-%m-%d-%H%M%S).log"
    exec > >(tee -a "${log_file}") 2>&1
    print_debug "Logging to ${log_file}"

    # Create placeholder env file early (migrates old token files if present)
    create_env_local

    # Source env vars early so BAN_COMPOUND_PLUGIN etc. are available
    if [[ -f "${HOME}/.env.local" ]]; then
        set -a
        # shellcheck source=/dev/null
        source "${HOME}/.env.local"
        set +a
    fi

    print_section "User & System Setup"
    ensure_not_root
    verify_bazzite_system || return 1
    request_sudo_upfront
    setup_dns64_for_ipv6_only

    print_section "Package Manager"
    ensure_brew_available || return 1
    install_core_packages
    install_secrets_manager
    install_brew_packages
    setup_tailscale_ssh

    print_section "SSH Configuration"
    setup_ssh_key
    add_github_to_known_hosts || return 1

    if is_main_user; then
        print_section "Code Directory Setup"
        setup_code_directory
    fi

    print_section "Development Environment"
    setup_claude_shared_directory

    print_section "Dotfiles Management"

    # Check if we have access (via SSH, token, or deploy key)
    # If not, try interactive deploy key setup
    if check_dotfiles_access || setup_dotfiles_deploy_key; then
        # We have access, proceed with chezmoi setup

        # Bootstrap the credential helper before chezmoi (chicken-and-egg problem)
        if [[ ! -x "${HOME}/.local/bin/git-credential-github-multi" ]]; then
            source_gh_tokens
            if [[ -n "${GH_TOKEN_SCOWALT}" ]] || [[ -n "${GH_TOKEN}" ]]; then
                print_message "Bootstrapping git credential helper..."
                mkdir -p "${HOME}/.local/bin"
                cat > "${HOME}/.local/bin/git-credential-github-multi" << 'HELPER_EOF'
#!/bin/bash
# Git credential helper that routes to different GitHub tokens based on repo owner
declare -A input
while IFS='=' read -r key value; do
    [[ -z "${key}" ]] && break
    input["${key}"]="${value}"
done
[[ "${input[host]}" != "github.com" ]] && exit 1
owner=""
[[ -n "${input[path]}" ]] && owner=$(echo "${input[path]}" | cut -d'/' -f1)
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

        install_chezmoi
        initialize_chezmoi
        # chezmoi init --apply overwrites ~/.ssh/config, removing the
        # github-dotfiles host alias needed for deploy key access.
        # Re-bootstrap it before any further chezmoi network operations.
        bootstrap_ssh_config
        configure_chezmoi_git
        fix_chezmoi_remote_for_deploy_key
        update_chezmoi
        chezmoi apply --force
    else
        print_warning "Skipping dotfiles management - no access to repository."
    fi

    print_section "Shell Configuration"
    set_fish_as_default_shell
    install_tmux_plugins

    print_section "Development Tools"
    install_bun
    install_sfw
    install_claude_code
    setup_compound_plugin
    setup_telegram_plugin
    install_gemini_cli
    install_codex_cli
    install_ccgram
    install_whisper

    print_section "Final Updates"
    update_brew
    upgrade_npm_global_packages

    echo -e "${GRAY}Run log saved to: ${log_file}${NC}"
    upload_log
    echo -e "\n${GREEN}${BOLD}✨ Setup complete!${NC}\n"
}

main "$@"
