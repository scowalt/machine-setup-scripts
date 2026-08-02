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

SETUP_ORIGINAL_PATH="${PATH}"
SETUP_ORIGINAL_CLAUDE_COMMAND=$(command -v claude 2>/dev/null || true)

# Acquire a non-blocking per-user setup lock so overlapping setup runs don't
# corrupt shared global package directories (npm, Bun, Homebrew, etc.). The lock
# is held by file descriptor 9 until the script exits.
acquire_setup_lock() {
    local _lock_root="${XDG_RUNTIME_DIR:-${HOME}/.local/state}"
    local _lock_file="${_lock_root}/machine-setup.lock"

    if [[ "${MACHINE_SETUP_ALLOW_CONCURRENT:-}" == "1" ]]; then
        print_warning "MACHINE_SETUP_ALLOW_CONCURRENT=1, skipping concurrent setup guard."
        return 0
    fi

    if ! command -v flock &> /dev/null; then
        print_debug "flock not found; concurrent setup guard disabled."
        return 0
    fi

    if ! mkdir -p "${_lock_root}"; then
        print_warning "Could not create setup lock directory at ${_lock_root}; continuing without a lock."
        return 0
    fi

    if ! exec 9>"${_lock_file}"; then
        print_warning "Could not open setup lock at ${_lock_file}; continuing without a lock."
        return 0
    fi

    if ! flock -n 9; then
        print_warning "Another machine setup run is already in progress; exiting before making changes."
        print_debug "Lock file: ${_lock_file}"
        return 1
    fi

    print_debug "Acquired setup lock at ${_lock_file}."
}
print_error() { printf "${RED} %s${NC}\n" "$1"; }

# Migrate old token files (~/.gh_token, ~/.op_token) into ~/.env.local
migrate_token_files() {
    local env_file="${HOME}/.env.local"
    local migrated=0

    for old_file in "${HOME}/.gh_token" "${HOME}/.op_token"; do
        if [[ -f "${old_file}" ]]; then
            # Extract uncommented KEY=VALUE lines (strip 'export ' prefix if present)
            local values
            values=$(grep -v '^\s*#' "${old_file}" | grep -v '^\s*$' | sed 's/^export //' || true)
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

# Machine/setup guards
# HEADLESS=1
# WORK_MACHINE=1
# BAN_PI_SUBAGENTS=1
# BAN_PI_MCP_ADAPTER=1
# BAN_PI_GOAL_AUTORESEARCH=1
# BAN_MATT_POCOCK_SKILLS=1
# BAN_RTK=1
# BAN_CLAUDE_CODE=1
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
        exit 1
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
    if command -v xclip &>/dev/null && [[ -n "${DISPLAY:-}" ]]; then
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
        local _ssh_test_output
        _ssh_test_output=$(ssh -i "${key_file}" -o StrictHostKeyChecking=accept-new -T git@github.com < /dev/null 2>&1) || true
        if echo "${_ssh_test_output}" | grep -q "successfully authenticated"; then
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

    print_message "IPv6-only network detected. Configuring DNS64..."

    # Check if already configured
    if [[ -f /etc/netplan/60-dns64.yaml ]]; then
        print_debug "DNS64 already configured."
        return 0
    fi

    # Find the primary network interface
    local interface
    local route_output
    local awk_output
    route_output=$(ip -6 route show default) || true
    awk_output=$(echo "${route_output}" | awk '{print $5}') || true
    interface=$(echo "${awk_output}" | head -1)

    if [[ -z "${interface}" ]]; then
        print_warning "Could not detect primary network interface for DNS64."
        return 1
    fi

    print_debug "Detected interface: ${interface}"

    # Create netplan config for DNS64 (using nat64.net public servers)
    sudo tee /etc/netplan/60-dns64.yaml > /dev/null <<EOF
network:
  version: 2
  ethernets:
    ${interface}:
      nameservers:
        addresses:
        - 2a00:1098:2c::1
        - 2a00:1098:2b::1
        - 2a01:4f8:c2c:123f::1
EOF

    sudo chmod 600 /etc/netplan/60-dns64.yaml

    if sudo netplan apply; then
        # Wait for DNS to settle
        sleep 2
        print_success "DNS64 configured for IPv6-only network."
    else
        print_error "Failed to apply DNS64 netplan configuration."
        return 1
    fi
}

# Check if running on Raspberry Pi OS
check_raspberry_pi() {
    print_message "Detecting Raspberry Pi hardware or OS…"

    local is_pi=false

    # 1) Look for Raspberry Pi OS IDs
    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        . /etc/os-release
        # shellcheck disable=SC2154
        if [[ "${ID}" =~ ^(raspbian|raspios)$ ]] || [[ "${PRETTY_NAME}" =~ Raspberry\ Pi ]]; then
            is_pi=true
        fi
    fi

    # 2) Hardware check via device‑tree model
    if [[ "${is_pi}" = false ]] && [[ -r /proc/device-tree/model ]]; then
        if grep -q "Raspberry Pi" /proc/device-tree/model 2>/dev/null; then
            is_pi=true
        fi
    fi

    # 3) Fallback to /proc/cpuinfo (older kernels)
    if [[ "${is_pi}" = false ]] && grep -q "Raspberry Pi" /proc/cpuinfo 2>/dev/null; then
        is_pi=true
    fi

    if [[ "${is_pi}" = true ]]; then
        print_success "Raspberry Pi hardware/OS detected."
    else
        print_warning "Could not confirm Raspberry Pi. Continuing anyway…"
    fi
}


# Update dependencies with Raspberry Pi specific optimizations
update_dependencies() {
    if ! can_sudo; then
        print_warning "No sudo access - skipping system updates."
        return
    fi

    print_message "Updating package lists (this may take a while on Raspberry Pi)..."
    sudo apt update

    # Hold tmux during upgrades to prevent killing existing sessions.
    sudo apt-mark hold tmux 2>/dev/null || true
    print_message "Upgrading packages (this may take a while)..."
    sudo apt upgrade -y
    sudo apt-mark unhold tmux 2>/dev/null || true

    print_message "Removing unnecessary packages..."
    sudo apt autoremove -y

    print_success "Package lists updated."
}

# Update and install core dependencies with Raspberry Pi considerations
update_and_install_core() {
    print_message "Checking and installing core packages as needed..."

    # Define an array of required packages
    local packages=("git" "curl" "jq" "fish" "tmux" "fonts-firacode" "gh" "build-essential" "libssl-dev" "zlib1g-dev" "libbz2-dev" "libreadline-dev" "libsqlite3-dev" "wget" "unzip" "llvm" "libncurses-dev" "xz-utils" "tk-dev" "libffi-dev" "liblzma-dev" "golang-go" "inotify-tools" "shellcheck" "gitleaks" "poppler-utils" "bubblewrap")
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
        sudo apt update -qq > /dev/null
        sudo apt install -qq -y "${to_install[@]}"
        print_success "Missing core packages installed."
    else
        print_success "All core packages are already installed."
    fi
}

# ----------------------[ 1Password CLI ]-------------------------
install_1password_cli() {
    if command -v op >/dev/null; then
        print_debug "1Password CLI already installed."
        return
    fi

    print_message "Installing 1Password CLI…"

    # Make sure gnupg is available for key import
    sudo apt install -y gnupg >/dev/null

    # Import signing key
    local signing_key
    signing_key=$(curl -sS https://downloads.1password.com/linux/keys/1password.asc)
    echo "${signing_key}" | sudo gpg --dearmor --output /usr/share/keyrings/1password-archive-keyring.gpg

    # Figure out repo path for the current CPU architecture
    local dpkg_arch
    dpkg_arch=$(dpkg --print-architecture)       # arm64, armhf, amd64…
    local repo_arch="${dpkg_arch}"
    [[ "${dpkg_arch}" == "armhf" ]] && repo_arch="arm"   # 32‑bit Pi

    # Add repo
    echo \
"deb [arch=${dpkg_arch} signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] \
https://downloads.1password.com/linux/debian/${repo_arch} stable main" \
        | sudo tee /etc/apt/sources.list.d/1password-cli.list >/dev/null

    # Add debsig‑verify policy (required for future updates)
    sudo mkdir -p /etc/debsig/policies/AC2D62742012EA22/
    local policy_content
    policy_content=$(curl -sS https://downloads.1password.com/linux/debsig/1password.pol)
    echo "${policy_content}" | sudo tee /etc/debsig/policies/AC2D62742012EA22/1password.pol >/dev/null
    local debsig_key
    debsig_key=$(curl -sS https://downloads.1password.com/linux/keys/1password.asc)
    echo "${debsig_key}" | sudo tee /etc/debsig/keys/AC2D62742012EA22.asc >/dev/null

    # Install package
    sudo apt update -qq
    sudo apt install -y 1password-cli

    print_success "1Password CLI installed."
}

setup_ssh_key() {
    # Skip SSH key setup for non-sudo users (they won't be making outbound SSH requests)
    if ! can_sudo; then
        print_debug "No sudo access - skipping SSH key setup."
        return
    fi

    print_message "Checking for existing SSH key…"

    mkdir -p ~/.ssh && chmod 700 ~/.ssh

    # Generate a key if none exists
    if [[ ! -f ~/.ssh/id_rsa.pub ]]; then
        print_warning "No SSH key found. Generating a new one…"
        local hostname_value
        hostname_value=$(hostname)
        ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N "" -C "${USER}@${hostname_value}"
        print_success "SSH key generated."
        print_message "Public key (add this to GitHub if you haven't already):"
        cat ~/.ssh/id_rsa.pub
    else
        print_success "SSH key already present."
    fi
}

verify_github_key() {
    local github_user="${GITHUB_USERNAME:-scowalt}"   # change default if you like
    local keys_url="https://github.com/${github_user}.keys"

    print_message "Verifying that your public key is registered with GitHub user '${github_user}'…"

    # Pull remote keys (fail hard if the request itself fails)
    local remote_keys
    if ! remote_keys="$(curl -fsSL "${keys_url}")"; then
        print_error "Failed to download keys from ${keys_url}"
        return 1
    fi

    # Pick the second field (base64 blob) from the local key
    local local_key_value
    local_key_value=$(awk '{print $2}' ~/.ssh/id_rsa.pub)

    # Search the list returned by GitHub
    local awk_output
    awk_output=$(echo "${remote_keys}" | awk '{print $2}')
    if echo "${awk_output}" | grep -qx "${local_key_value}"; then
        print_success "Local key is recognized by GitHub."
    else
        print_error "Your public key is NOT registered with GitHub!"
        print_message "Add this key to https://github.com/settings/keys, then rerun the script:"
        cat ~/.ssh/id_rsa.pub
        print_message "Opening GitHub SSH keys page..."
        xdg-open "https://github.com/settings/keys" 2>/dev/null || true
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

# Install Starship with Raspberry Pi considerations
# NOTE: Uses official install script with ARM architecture detection for Raspberry Pi
# DO NOT standardize - ARM detection and Pi-specific optimizations are critical
# Different from other platforms due to ARM compatibility requirements
install_starship() {
    if ! command -v starship &> /dev/null; then
        print_message "Installing Starship prompt (this may take a while on Raspberry Pi)..."
        
        # Check architecture for compatibility
        local arch
        arch=$(uname -m)
        if [[ "${arch}" == "armv"* || "${arch}" == "aarch64" ]]; then
            print_message "Detected ARM architecture: ${arch}"
            local starship_install
            starship_install=$(curl -sS https://starship.rs/install.sh)
            if echo "${starship_install}" | sh -s -- -y; then
                print_success "Starship installed."
            else
                print_error "Failed to install Starship."
                return 1
            fi
        else
            print_error "Unsupported architecture: ${arch}. Starship might not work correctly."
            print_message "Attempting installation anyway..."
            local starship_install
            starship_install=$(curl -sS https://starship.rs/install.sh)
            if echo "${starship_install}" | sh -s -- -y; then
                print_success "Starship installed despite architecture warning."
            else
                print_error "Failed to install Starship."
                return 1
            fi
        fi
    else
        print_debug "Starship is already installed."
    fi
}

install_tailscale() {
    # --- Install if not present ---
    if ! command -v tailscale &>/dev/null; then
        print_message "Installing Tailscale…"
        # Official install script (adds repo + installs package)
        local tailscale_install
        tailscale_install=$(curl -fsSL https://tailscale.com/install.sh)
        echo "${tailscale_install}" | sudo sh

        if ! command -v tailscale &>/dev/null; then
            print_error "Tailscale installation failed (binary not found). Check apt errors above."
            return
        fi

        print_success "Tailscale installed."
    else
        print_debug "Tailscale already installed."
    fi

    # --- Ensure tailscaled service is enabled and running ---
    if ! systemctl is-enabled tailscaled &>/dev/null; then
        print_message "Enabling tailscaled service…"
        sudo systemctl enable tailscaled
    fi
    if ! systemctl is-active tailscaled &>/dev/null; then
        print_message "Starting tailscaled service…"
        sudo systemctl start tailscaled
    fi
    print_debug "tailscaled service is enabled and running."

    # --- Ensure authenticated ---
    local backend_state
    backend_state=$(tailscale status --json 2>/dev/null | grep -o '"BackendState":[[:space:]]*"[^"]*"' | cut -d'"' -f4 || true)
    if [[ "${backend_state}" != "Running" ]]; then
        print_warning "Tailscale is not authenticated (state: ${backend_state:-unknown})."
        echo -n "Run 'tailscale up' now to authenticate? (y/n): "
        read -r ts_up < /dev/tty
        if [[ "${ts_up}" =~ ^[Yy]$ ]]; then
            print_message "Bringing interface up…"
            # shellcheck disable=SC2024
            sudo tailscale up < /dev/tty       # add --authkey=... if you prefer key‑based auth
        else
            print_warning "Run 'sudo tailscale up' later to log in."
            return
        fi
    else
        print_debug "Tailscale is authenticated and running."
    fi

    # --- Ensure Tailscale SSH is enabled ---
    local run_ssh
    run_ssh=$(tailscale debug prefs 2>/dev/null | grep -o '"RunSSH":[a-z]*' | cut -d: -f2 || true)
    if [[ "${run_ssh}" != "true" ]]; then
        print_message "Enabling Tailscale SSH…"
        sudo tailscale set --ssh
        print_success "Tailscale SSH enabled."
    else
        print_debug "Tailscale SSH is already enabled."
    fi

    # --- Verify SSH is accessible (ACL check) ---
    local tailscale_ip
    tailscale_ip=$(tailscale ip -4 2>/dev/null)
    if [[ -n "${tailscale_ip}" ]]; then
        # Connect to our own Tailscale SSH to verify ACLs allow it
        if timeout 5 tailscale nc "${tailscale_ip}" 22 </dev/null &>/dev/null; then
            print_success "Tailscale SSH is accessible (ACLs OK)."
        else
            print_warning "Tailscale SSH may not be accessible — check ACLs in Tailscale admin console."
        fi
    fi
}

# Install Doppler CLI for secrets management (non-work machines)
install_doppler() {
    if command -v doppler &>/dev/null; then
        print_debug "Doppler CLI already installed."
        return
    fi

    if ! can_sudo; then
        print_warning "No sudo access - cannot install Doppler CLI."
        return
    fi

    print_message "Installing Doppler CLI..."

    # Import signing key
    local signing_key
    signing_key=$(curl -sLf --retry 3 --tlsv1.2 --proto "=https" \
        'https://packages.doppler.com/public/cli/gpg.DE2A7741A397C129.key')
    echo "${signing_key}" | sudo gpg --dearmor -o /usr/share/keyrings/doppler-archive-keyring.gpg

    # Add repo
    echo "deb [signed-by=/usr/share/keyrings/doppler-archive-keyring.gpg] https://packages.doppler.com/public/cli/deb/debian any-version main" \
        | sudo tee /etc/apt/sources.list.d/doppler-cli.list >/dev/null

    # Install package
    sudo apt-get update -qq
    if sudo apt-get install -y doppler; then
        print_success "Doppler CLI installed."
    else
        print_error "Failed to install Doppler CLI."
    fi
}

# Install Infisical CLI for secrets management (work machines)
install_infisical() {
    if command -v infisical &>/dev/null; then
        print_debug "Infisical CLI already installed."
        return
    fi

    if ! can_sudo; then
        print_warning "No sudo access - cannot install Infisical CLI."
        return
    fi

    print_message "Installing Infisical CLI..."

    # Add repository and install
    if { curl -1sLf 'https://dl.cloudsmith.io/public/infisical/infisical-cli/setup.deb.sh' || true; } | sudo bash; then
        sudo apt-get update -qq
        if sudo apt-get install -y infisical; then
            print_success "Infisical CLI installed."
        else
            print_error "Failed to install Infisical CLI."
        fi
    else
        print_error "Failed to add Infisical repository."
    fi
}

# Install the appropriate secrets manager based on machine type
install_secrets_manager() {
    if [[ "${WORK_MACHINE:-}" == "1" ]]; then
        install_infisical
    else
        install_doppler
    fi
}

# Update Google Cloud CLI components when the component manager is available.
update_gcloud_components() {
    if ! command -v gcloud &>/dev/null; then
        print_debug "Google Cloud CLI not installed; skipping component update."
        return
    fi

    local update_output
    local normalized_output
    print_message "Updating Google Cloud CLI components..."
    if update_output=$(gcloud components update --quiet < /dev/null 2>&1); then
        print_success "Google Cloud CLI components updated."
    else
        normalized_output=$(printf '%s' "${update_output}" | tr '\r\n\t' '   ')
        if grep -qiE "component[[:space:]]+manager[[:space:]]+is[[:space:]]+disabled|managed[[:space:]]+by[[:space:]]+an[[:space:]]+external[[:space:]]+package[[:space:]]+manager" <<< "${normalized_output}"; then
            print_debug "Google Cloud CLI components are managed by the package manager; skipping component update."
        else
            print_warning "Failed to update Google Cloud CLI components."
            if [[ -n "${update_output}" ]]; then
                print_debug "${update_output}"
            fi
        fi
    fi
}

# Install Google Cloud CLI on work machines.
install_gcloud_cli() {
    if [[ "${WORK_MACHINE:-}" != "1" ]]; then
        print_debug "Skipping Google Cloud CLI (not a work machine)."
        return
    fi

    if command -v gcloud &>/dev/null; then
        print_debug "Google Cloud CLI already installed."
        update_gcloud_components
        return
    fi

    if ! can_sudo; then
        print_warning "No sudo access - cannot install Google Cloud CLI."
        return
    fi

    print_message "Installing Google Cloud CLI..."

    sudo install -m 0755 -d /usr/share/keyrings
    if ! { curl --connect-timeout 10 --max-time 60 -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg || true; } \
        | sudo gpg --batch --yes --dearmor -o /usr/share/keyrings/cloud.google.gpg; then
        print_warning "Failed to install Google Cloud CLI signing key."
        return
    fi

    echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
        | sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list >/dev/null

    if ! sudo apt-get update -qq; then
        print_warning "Failed to update apt repositories for Google Cloud CLI."
        return
    fi

    if sudo apt-get install -y google-cloud-cli; then
        print_success "Google Cloud CLI installed."
        update_gcloud_components
    else
        print_warning "Failed to install Google Cloud CLI."
    fi
}

# Install and configure fail2ban for brute-force protection
install_fail2ban() {
    if dpkg -s fail2ban &> /dev/null; then
        print_debug "fail2ban is already installed."
        return
    fi

    if ! can_sudo; then
        print_warning "No sudo access - cannot install fail2ban."
        return
    fi

    print_message "Installing fail2ban..."
    if sudo apt install -y fail2ban; then
        # Enable and start fail2ban service
        sudo systemctl enable fail2ban
        sudo systemctl start fail2ban
        print_success "fail2ban installed and enabled."
    else
        print_error "Failed to install fail2ban."
    fi
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
        if ! sudo apt install -y unattended-upgrades; then
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

    # Enable the unattended-upgrades service
    if systemctl is-enabled unattended-upgrades &>/dev/null; then
        print_debug "unattended-upgrades service already enabled."
    else
        print_message "Enabling unattended-upgrades service..."
        sudo systemctl enable unattended-upgrades
        sudo systemctl start unattended-upgrades
        print_success "unattended-upgrades service enabled."
    fi
}

# Install chezmoi with Raspberry Pi considerations
install_chezmoi() {
    if ! command -v chezmoi &> /dev/null; then
        print_message "Installing chezmoi (this may take a while on Raspberry Pi)..."
        local chezmoi_install
        chezmoi_install=$(curl -fsLS get.chezmoi.io)
        if sh -c "${chezmoi_install}" -- -b "${HOME}/bin"; then
            # Add ~/bin to PATH if not already present
            if ! grep -q "PATH=\${HOME}/bin" ~/.bashrc; then
                echo "export PATH=\${HOME}/bin:\${PATH}" >> ~/.bashrc
                # Source bashrc in the current session to make chezmoi available
                export PATH=${HOME}/bin:${PATH}
            fi
            print_success "chezmoi installed."
        else
            print_error "Failed to install chezmoi."
            return 1
        fi
    else
        print_debug "chezmoi is already installed."
    fi
}

# Initialize chezmoi with Raspberry Pi optimizations
initialize_chezmoi() {
    # If chezmoi isn't on PATH, fall back to ~/bin/chezmoi
    if ! command -v chezmoi >/dev/null; then
        if [[ -x "${HOME}/bin/chezmoi" ]]; then
            local chezmoi_cmd="${HOME}/bin/chezmoi"
        else
            print_error "chezmoi not found. Install chezmoi first."
            return 1
        fi
    else
        local chezmoi_cmd="chezmoi"
    fi

    local chez_src="${HOME}/.local/share/chezmoi"

    # Check if directory exists but is not a valid git repo (empty or missing .git)
    if [[ -d "${chez_src}" ]] && [[ ! -d "${chez_src}/.git" ]]; then
        print_warning "chezmoi directory exists but is not a git repository. Reinitializing..."
        rm -rf "${chez_src}"
    fi

    if [[ ! -d "${chez_src}" ]]; then
        print_message "Initializing chezmoi with scowalt/dotfiles…"
        if has_verified_ssh_key; then
            # User with verified SSH key uses default SSH for push access
            if ! ${chezmoi_cmd} init --apply --force scowalt/dotfiles --ssh; then
                print_error "Failed to initialize chezmoi. Check SSH key and network connectivity."
                return 1
            fi
        else
            # Other users use SSH via deploy key (github-dotfiles alias)
            if ! ${chezmoi_cmd} init --apply --force "git@github-dotfiles:scowalt/dotfiles.git"; then
                print_error "Failed to initialize chezmoi. Check deploy key setup."
                return 1
            fi
        fi
        print_success "chezmoi initialized with scowalt/dotfiles."
    else
        print_debug "chezmoi already initialized."
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

# Update chezmoi dotfiles repository to latest version
update_chezmoi() {
    # If chezmoi isn't on PATH, fall back to ~/bin/chezmoi
    if ! command -v chezmoi >/dev/null; then
        if [[ -x "${HOME}/bin/chezmoi" ]]; then
            local chezmoi_cmd="${HOME}/bin/chezmoi"
        else
            print_error "chezmoi not found. Install chezmoi first."
            return 1
        fi
    else
        local chezmoi_cmd="chezmoi"
    fi

    local chez_src="${HOME}/.local/share/chezmoi"
    if [[ -d "${chez_src}" ]]; then
        print_message "Updating chezmoi dotfiles repository..."
        if ${chezmoi_cmd} update > /dev/null; then
            print_success "chezmoi dotfiles repository updated."
        else
            print_warning "Failed to update chezmoi dotfiles repository. Continuing anyway."
        fi
    else
        print_debug "chezmoi not initialized yet, skipping update."
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
    print_success "Fish shell set as default. Please log out and back in for changes to take effect."
}

# Install tmux plugins with Raspberry Pi optimizations
install_tmux_plugins() {
    local plugin_dir=~/.tmux/plugins
    mkdir -p "${plugin_dir}"
    
    if [[ ! -d "${plugin_dir}/tpm" ]]; then
        print_message "Installing tmux plugin manager..."
        git clone -q https://github.com/tmux-plugins/tpm "${plugin_dir}/tpm"
        print_success "tmux plugin manager installed."
    else
        print_debug "tmux plugin manager already installed."
        # Update TPM
        (cd "${plugin_dir}/tpm" && git pull -q origin master)
        print_success "tmux plugin manager updated."
    fi

    for plugin in tmux-resurrect tmux-continuum; do
        if [[ ! -d "${plugin_dir}/${plugin}" ]]; then
            print_message "Installing ${plugin}..."
            git clone -q "https://github.com/tmux-plugins/${plugin}" "${plugin_dir}/${plugin}"
            print_success "${plugin} installed."
        else
            print_debug "${plugin} already installed."
            # Update plugin
            (cd "${plugin_dir}/${plugin}" && git pull -q origin master)
            print_success "${plugin} updated."
        fi
    done

    # Check if tmux is running
    if tmux info &> /dev/null; then
        print_message "Reloading tmux configuration..."
        tmux source-file ~/.tmux.conf
    else
        print_warning "tmux not running; configuration will be loaded on next start."
    fi
    
    print_message "Installing tmux plugins..."
    "${plugin_dir}/tpm/bin/install_plugins" > /dev/null 2>&1
    "${plugin_dir}/tpm/bin/update_plugins" all > /dev/null 2>&1
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

# Apply chezmoi configuration
apply_chezmoi_config() {
    print_message "Applying chezmoi configuration…"

    # Locate executable
    local chezmoi_cmd
    if command -v chezmoi >/dev/null;      then chezmoi_cmd="chezmoi"
    elif [[ -x "${HOME}/bin/chezmoi" ]];       then chezmoi_cmd="${HOME}/bin/chezmoi"
    else
        print_error "chezmoi not found."
        return 1
    fi

    # Run verbosely; bail if anything returns non‑zero
    if ! ${chezmoi_cmd} apply --force --verbose; then
        print_error "chezmoi apply failed – fix the dotfiles, then rerun the script."
        return 1
    fi

    print_success "chezmoi configuration applied."
    tmux source ~/.tmux.conf 2>/dev/null || true
}


# Setup a small swap file if memory is limited
setup_swap() {
    local total_mem
    local free_output
    free_output=$(free -m)
    total_mem=$(echo "${free_output}" | awk '/^Mem:/{print $2}')
    
    if [[ "${total_mem}" -lt 2048 ]]; then
        print_message "Limited RAM detected (${total_mem} MB). Setting up swap file..."
        
        # Check if swap is already configured
        local swap_count
        local swap_output
        swap_output=$(swapon --show)
        swap_count=$(echo "${swap_output}" | wc -l)
        if [[ "${swap_count}" -gt 0 ]]; then
            print_debug "Swap already configured."
            swapon --show
            return
        fi
        
        # Create a 1GB swap file
        sudo fallocate -l 1G /swapfile
        sudo chmod 600 /swapfile
        sudo mkswap /swapfile
        sudo swapon /swapfile
        
        # Make swap permanent
        if ! grep -q "/swapfile" /etc/fstab; then
            echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab > /dev/null
        fi
        
        # Adjust swappiness
        echo 'vm.swappiness=10' | sudo tee -a /etc/sysctl.conf > /dev/null
        sudo sysctl vm.swappiness=10
        
        print_success "Swap file configured."
    else
        print_message "Sufficient RAM detected (${total_mem} MB). Skipping swap setup."
    fi
}

# ----------------------[ SSH *server* helper ]-------------------
enable_ssh_server() {
    # Install server package if missing
    if ! dpkg -s openssh-server &>/dev/null; then
        print_message "Installing OpenSSH server…"
        sudo apt install -y openssh-server
    else
        print_debug "OpenSSH server already installed."
    fi

    # Enable and start the service now and on boot
    sudo systemctl enable --now ssh
    print_success "OpenSSH server enabled and running."
}

# ----------------------[ ssh‑agent helper ]----------------------
ensure_ssh_agent() {
    print_message "Making sure ssh‑agent is running and key is loaded…"

    # If a key is already listed, we're done.
    if ssh-add -l >/dev/null 2>&1; then
        print_success "ssh‑agent already running with a key loaded."
        return
    fi

    # Otherwise start (or reuse) an agent.
    if [[ -z "${SSH_AUTH_SOCK}" ]] || ! ssh-add -l >/dev/null 2>&1; then
        print_warning "Starting a new ssh‑agent instance…"
        local ssh_agent_output
        ssh_agent_output=$(ssh-agent -s)
        eval "${ssh_agent_output}" >/dev/null
    fi

    # Add the default key
    if ssh-add ~/.ssh/id_rsa < /dev/tty >/dev/null 2>&1; then
        print_success "SSH key added to agent."
    else
        print_error "Could not add ~/.ssh/id_rsa to ssh‑agent. Check permissions."
        return 1
    fi

    # Persist agent environment for future shells ----------------
    echo "export SSH_AUTH_SOCK=${SSH_AUTH_SOCK}" >  ~/.ssh-agent-env
    # shellcheck disable=SC2154
    echo "export SSH_AGENT_PID=${SSH_AGENT_PID}" >> ~/.ssh-agent-env

    # Source for future Bash sessions
    if ! grep -q 'ssh-agent-env' ~/.bashrc 2>/dev/null; then
        echo '[ -f ~/.ssh-agent-env ] && source ~/.ssh-agent-env >/dev/null' >> ~/.bashrc
    fi

    # Source for future Fish sessions
    if [[ -d ~/.config/fish/conf.d ]]; then
        cat <<EOF > ~/.config/fish/conf.d/ssh-agent.fish
# auto‑generated by setup script
if test -f ~/.ssh-agent-env
    source ~/.ssh-agent-env ^/dev/null
end
EOF
    fi
    # ------------------------------------------------------------
}

# ----------------------[ mise (polyglot runtime manager) ]--------------------
install_mise() {
    if command -v mise &> /dev/null; then
        print_debug "mise already installed."
        return
    fi

    print_message "Installing mise..."
    if { curl -fsSL https://mise.run || true; } | sh; then
        print_success "mise installed. Shell configuration will be managed by chezmoi."
    else
        print_error "Failed to install mise."
        return 1
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

# Install/update Codex CLI (OpenAI's AI coding agent)
install_codex_cli() {
    print_message "Installing/updating Codex CLI..."

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
        print_success "Codex CLI installed/updated."
    else
        print_error "Failed to install Codex CLI."
    fi
}

# Install/update Notion CLI.
install_ntn_cli() {
    local os
    local arch
    os=$(uname -s 2>/dev/null || true)
    arch=$(uname -m 2>/dev/null || true)

    case "${os}:${arch}" in
        Darwin:x86_64|Darwin:arm64|Darwin:aarch64|Linux:x86_64|Linux:amd64|Linux:arm64|Linux:aarch64) ;;
        *)
            print_warning "Notion CLI does not support ${os:-unknown} ${arch:-unknown}; skipping."
            return
            ;;
    esac

    print_message "Installing/updating Notion CLI..."

    local install_dir="${HOME}/.local/bin"
    local installer_path
    if ! installer_path=$(mktemp "${TMPDIR:-/tmp}/ntn-install.XXXXXX"); then
        print_warning "Failed to create a temporary file for the Notion CLI installer."
        return
    fi

    local install_output
    if ! install_output=$(curl -fsSL https://ntn.dev -o "${installer_path}" 2>&1); then
        rm -f "${installer_path}"
        print_warning "Failed to download the Notion CLI installer."
        print_debug "${install_output}"
        return
    fi

    if install_output=$(NTN_INSTALL_DIR="${install_dir}" bash "${installer_path}" 2>&1); then
        rm -f "${installer_path}"
        export PATH="${install_dir}:${PATH}"
        if "${install_dir}/ntn" --version > /dev/null 2>&1; then
            print_success "Notion CLI installed/updated."
        else
            print_warning "Notion CLI installer completed, but ${install_dir}/ntn did not verify."
            print_debug "${install_output}"
        fi
    else
        rm -f "${installer_path}"
        print_warning "Failed to install/update Notion CLI."
        print_debug "${install_output}"
    fi
}



# Install Portless CLI (Tailscale HTTPS tunnel helper)
install_portless_cli() {
    if command -v portless &> /dev/null; then
        print_debug "Portless CLI is already installed."
        return
    fi

    print_message "Installing Portless CLI..."

    # Ensure bun is available
    if [[ -d "${HOME}/.bun" ]]; then
        export PATH="${HOME}/.bun/bin:${PATH}"
    fi

    if ! command -v bun &> /dev/null; then
        print_warning "Bun not found. Cannot install Portless CLI."
        print_debug "Install Bun first, then run: bun install -g portless"
        return
    fi

    if ! command -v tailscale &> /dev/null; then
        print_warning "Tailscale not found. Portless requires Tailscale to create tunnels."
    fi

    if bun install -g portless; then
        print_success "Portless CLI installed."
    else
        print_error "Failed to install Portless CLI."
    fi
}

# Install/update Claude Code CLI (Anthropic's AI coding agent)
claude_code_native_path() {
    printf '%s/.local/bin/claude' "${HOME}"
}

claude_code_path_looks_package_managed() {
    local path="$1"
    local target="${path}"
    local path_details

    if [[ -L "${path}" ]]; then
        target=$(readlink "${path}" 2>/dev/null || printf '%s' "${path}")
    fi
    path_details="${path} ${target}"

    if [[ -f "${path}" ]] && [[ ! -L "${path}" ]]; then
        path_details="${path_details} $(LC_ALL=C head -c 512 "${path}" 2>/dev/null || true)"
    fi

    case "${path_details}" in
        *node_modules*|*pnpm*|*mise*|*asdf*|*volta*|*yarn*|*fnm*|*nvm*|*npm*|*"${HOME}/.bun"*|*Homebrew*|*Cellar*|*Caskroom*) return 0 ;;
        *) return 1 ;;
    esac
}

claude_code_canonical_path() {
    local path="$1"
    local target
    local dir
    local base
    local canonical_dir

    if command -v realpath > /dev/null 2>&1; then
        realpath "${path}"
        return
    fi

    if command -v python3 > /dev/null 2>&1; then
        python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "${path}"
        return
    fi

    if [[ -L "${path}" ]]; then
        target=$(readlink "${path}" 2>/dev/null || printf '%s' "${path}")
        case "${target}" in
            /*) path="${target}" ;;
            *) path="$(dirname "${path}")/${target}" ;;
        esac
    fi

    dir=$(dirname "${path}")
    base=$(basename "${path}")
    canonical_dir=$(cd -P "${dir}" 2>/dev/null && pwd -P) || return 1
    printf '%s/%s\n' "${canonical_dir}" "${base}"
}

claude_code_path_has_native_provenance() {
    local path="$1"
    local resolved_path
    local native_root

    [[ -x "${path}" ]] || return 1

    if claude_code_path_looks_package_managed "${path}"; then
        return 1
    fi

    resolved_path=$(claude_code_canonical_path "${path}") || return 1
    native_root=$(claude_code_canonical_path "${HOME}/.local/share/claude" 2>/dev/null || printf '%s' "${HOME}/.local/share/claude")

    case "${resolved_path}" in
        "${native_root}/"*) return 0 ;;
        *) return 1 ;;
    esac
}

claude_code_supported_platform() {
    local os
    local arch
    os=$(uname -s 2>/dev/null || true)
    arch=$(uname -m 2>/dev/null || true)

    case "${os}" in
        Darwin|Linux) ;;
        *)
            print_warning "Claude Code native installer does not support ${os:-unknown}."
            return 1
            ;;
    esac

    case "${arch}" in
        x86_64|amd64|arm64|aarch64) return 0 ;;
        *)
            print_warning "Claude Code native installer does not support architecture ${arch:-unknown}."
            return 1
            ;;
    esac
}

claude_code_trusted_curl() {
    local candidate

    for candidate in /usr/bin/curl /bin/curl /usr/local/bin/curl /opt/homebrew/bin/curl; do
        if [[ -x "${candidate}" ]]; then
            printf '%s\n' "${candidate}"
            return 0
        fi
    done

    return 1
}

claude_code_kill_process_tree() {
    local signal="$1"
    local pid="$2"
    local children=""
    local child

    if command -v pgrep > /dev/null 2>&1; then
        children=$(pgrep -P "${pid}" 2>/dev/null || true)
        while IFS= read -r child; do
            if [[ -n "${child}" ]]; then
                claude_code_kill_process_tree "${signal}" "${child}"
            fi
        done <<< "${children}"
    fi

    kill "-${signal}" "${pid}" 2>/dev/null || true
}

claude_code_run_safely() {
    local -a env_args=()
    local safe_path="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin"
    local env_bin="/usr/bin/env"
    local timeout_seconds="${CLAUDE_CODE_COMMAND_TIMEOUT_SECONDS:-300}"
    local timeout_flag
    local command_status=0
    local pid
    local watchdog
    local use_process_group=0

    if [[ ! -x "${env_bin}" ]]; then
        env_bin="/bin/env"
    fi

    env_args=(
        "HOME=${HOME}"
        "USER=${USER:-}"
        "LOGNAME=${LOGNAME:-${USER:-}}"
        "SHELL=${SHELL:-/bin/bash}"
        "PATH=${safe_path}"
        "TMPDIR=${TMPDIR:-/tmp}"
        "TMP=${TMP:-/tmp}"
        "TEMP=${TEMP:-/tmp}"
        "LANG=${LANG:-C}"
        "HTTP_PROXY=${HTTP_PROXY:-}"
        "HTTPS_PROXY=${HTTPS_PROXY:-}"
        "ALL_PROXY=${ALL_PROXY:-}"
        "NO_PROXY=${NO_PROXY:-}"
        "http_proxy=${http_proxy:-}"
        "https_proxy=${https_proxy:-}"
        "all_proxy=${all_proxy:-}"
        "no_proxy=${no_proxy:-}"
        "SSL_CERT_FILE=${SSL_CERT_FILE:-}"
        "SSL_CERT_DIR=${SSL_CERT_DIR:-}"
        "CURL_CA_BUNDLE=${CURL_CA_BUNDLE:-}"
    )

    timeout_flag=$(mktemp)
    rm -f "${timeout_flag}"

    if command -v setsid > /dev/null 2>&1; then
        "${env_bin}" -i "${env_args[@]}" setsid "$@" < /dev/null &
        use_process_group=1
    elif command -v perl > /dev/null 2>&1; then
        "${env_bin}" -i "${env_args[@]}" perl -MPOSIX=setsid -e 'setsid() or die "setsid failed"; exec @ARGV' "$@" < /dev/null &
        use_process_group=1
    else
        "${env_bin}" -i "${env_args[@]}" "$@" < /dev/null &
    fi
    pid=$!
    (
        sleep "${timeout_seconds}"
        if [[ "${use_process_group}" -eq 1 ]]; then
            if kill -- "-${pid}" 2>/dev/null; then
                : > "${timeout_flag}"
                for _ in 1 2 3 4 5; do
                    sleep 1
                    if ! kill -0 -- "-${pid}" 2>/dev/null; then
                        exit 0
                    fi
                done
                kill -KILL -- "-${pid}" 2>/dev/null || true
            fi
        elif kill -0 "${pid}" 2>/dev/null; then
            : > "${timeout_flag}"
            claude_code_kill_process_tree TERM "${pid}"
            for _ in 1 2 3 4 5; do
                sleep 1
                if ! kill -0 "${pid}" 2>/dev/null; then
                    exit 0
                fi
            done
            claude_code_kill_process_tree KILL "${pid}"
        fi
    ) > /dev/null 2>&1 &
    watchdog=$!

    wait "${pid}" 2>/dev/null || command_status=$?
    if [[ -f "${timeout_flag}" ]]; then
        wait "${watchdog}" 2>/dev/null || true
        rm -f "${timeout_flag}"
        return 124
    fi

    kill "${watchdog}" 2>/dev/null || true
    wait "${watchdog}" 2>/dev/null || true

    rm -f "${timeout_flag}"
    return "${command_status}"
}

claude_code_run_installer() {
    local installer
    local installer_output
    local install_status=0
    local curl_bin

    installer=$(mktemp)
    installer_output=$(mktemp)

    if ! curl_bin=$(claude_code_trusted_curl); then
        rm -f "${installer}" "${installer_output}"
        print_warning "Trusted system curl not found. Cannot download Claude Code installer."
        return 1
    fi

    if ! claude_code_run_safely "${curl_bin}" -fsSL --connect-timeout 15 --max-time 120 --retry 2 --retry-delay 2 -o "${installer}" "https://claude.ai/install.sh"; then
        rm -f "${installer}" "${installer_output}"
        print_warning "Failed to download Claude Code installer."
        return 1
    fi

    chmod 700 "${installer}"
    claude_code_run_safely /bin/bash "${installer}" latest > "${installer_output}" 2>&1
    install_status=$?

    rm -f "${installer}" "${installer_output}"

    if [[ "${install_status}" -ne 0 ]]; then
        print_warning "Claude Code installer failed with exit code ${install_status}."
        return 1
    fi

    return 0
}

claude_code_warn_if_shadowed() {
    local original_command="$1"
    local native_path="$2"

    if [[ -z "${original_command}" ]] || [[ "${original_command}" == "${native_path}" ]]; then
        return
    fi

    print_warning "The 'claude' command currently resolves to ${original_command}, not ${native_path}."
    print_warning "Do not use bare 'claude' for Fable login until PATH/package shadowing is resolved; use ${native_path} directly."
}

install_claude_code() {
    if [[ "${BAN_CLAUDE_CODE:-}" == "1" ]]; then
        print_debug "BAN_CLAUDE_CODE=1, skipping Claude Code CLI setup."
        return
    fi

    if ! claude_code_supported_platform; then
        return
    fi

    local native_path
    local native_dir
    local original_command
    local original_path
    local before_version=""
    local after_version=""
    local needs_install=1

    native_path=$(claude_code_native_path)
    native_dir=$(dirname "${native_path}")
    original_path="${SETUP_ORIGINAL_PATH:-${PATH}}"
    original_command="${SETUP_ORIGINAL_CLAUDE_COMMAND:-}"
    if [[ -z "${original_command}" ]]; then
        original_command=$(PATH="${original_path}" command -v claude 2>/dev/null || true)
    fi

    print_message "Installing/updating Claude Code CLI..."
    mkdir -p "${native_dir}"

    if claude_code_path_has_native_provenance "${native_path}"; then
        if before_version=$(claude_code_run_safely "${native_path}" --version 2>/dev/null) && [[ -n "${before_version}" ]]; then
            needs_install=0
            print_debug "Current Claude Code version: ${before_version}"
            if claude_code_run_safely "${native_path}" update > /dev/null 2>&1; then
                print_debug "Claude Code update completed."
            else
                print_warning "Claude Code update failed; keeping existing install."
            fi
        else
            print_warning "Claude Code native binary exists but did not run; reinstalling."
        fi
    elif [[ -e "${native_path}" ]]; then
        print_warning "Claude Code native path appears to be package-managed or invalid; reinstalling native Claude Code."
    fi

    if [[ "${needs_install}" -eq 1 ]]; then
        claude_code_run_installer || return
    fi

    export PATH="${native_dir}:${PATH}"
    if after_version=$(claude_code_run_safely "${native_path}" --version 2>/dev/null) && [[ -n "${after_version}" ]]; then
        print_success "Claude Code CLI installed/updated (${after_version})."
        claude_code_warn_if_shadowed "${original_command}" "${native_path}"
        if [[ -z "${original_command}" ]] && [[ ":${original_path}:" != *":${native_dir}:"* ]]; then
            print_warning "${native_dir} was not on PATH before setup; restart your shell after dotfiles apply or run ${native_path} directly."
        fi
    else
        print_warning "Claude Code CLI install completed, but ${native_path} did not verify."
    fi
}


# Verify the installed rtk is Rust Token Killer, not the unrelated Rust Type Kit.
rtk_cli_ready() {
    command -v rtk &> /dev/null && rtk gain > /dev/null 2>&1
}

# Install RTK (Rust Token Killer) for token-optimized agent command output.
install_rtk_cli() {
    if [[ "${BAN_RTK:-}" == "1" ]]; then
        print_debug "BAN_RTK=1, skipping RTK setup."
        return
    fi

    export PATH="${HOME}/.local/bin:${PATH}"

    local had_rtk=0
    if rtk_cli_ready; then
        had_rtk=1
        print_message "Updating RTK CLI..."
    elif command -v rtk &> /dev/null; then
        print_warning "An rtk command exists, but it does not look like Rust Token Killer. Installing the rtk-ai binary to ~/.local/bin."
    else
        print_message "Installing RTK CLI..."
    fi

    local install_script
    if ! install_script=$(curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh 2>&1); then
        if [[ "${had_rtk}" == "1" ]]; then
            print_warning "Failed to update RTK CLI; existing install remains available."
        else
            print_warning "Failed to download RTK installer."
        fi
        print_debug "${install_script}"
        return
    fi

    local install_output
    if install_output=$(RTK_INSTALL_DIR="${HOME}/.local/bin" sh -c "${install_script}" 2>&1); then
        hash -r 2>/dev/null || true
        if rtk_cli_ready; then
            print_success "RTK CLI installed/updated."
        else
            print_warning "RTK installer completed, but 'rtk gain' did not verify the expected binary."
            print_debug "${install_output}"
        fi
    else
        if [[ "${had_rtk}" == "1" ]]; then
            print_warning "Failed to update RTK CLI; existing install remains available."
        else
            print_warning "Failed to install RTK CLI."
        fi
        print_debug "${install_output}"
    fi
}

# Configure RTK integrations for installed AI agents. Non-fatal by design.
setup_rtk_integrations() {
    if [[ "${BAN_RTK:-}" == "1" ]]; then
        print_debug "BAN_RTK=1, skipping RTK integrations."
        return
    fi

    export PATH="${HOME}/.local/bin:${PATH}"

    if ! rtk_cli_ready; then
        print_warning "RTK CLI is not available; skipping RTK integrations."
        return
    fi

    # Automated setup should not prompt for telemetry consent. Users can opt in later with `rtk telemetry enable`.
    rtk telemetry disable > /dev/null 2>&1 || true

    local init_output

    if command -v gemini &> /dev/null; then
        print_message "Configuring RTK for Gemini CLI..."
        if init_output=$(rtk init -g --gemini --auto-patch < /dev/null 2>&1); then
            print_success "RTK configured for Gemini CLI."
        else
            print_warning "Failed to configure RTK for Gemini CLI."
            print_debug "${init_output}"
        fi
    else
        print_debug "Gemini CLI not installed; skipping RTK Gemini integration."
    fi

    if command -v codex &> /dev/null; then
        print_message "Configuring RTK for Codex CLI..."
        if init_output=$(rtk init -g --codex < /dev/null 2>&1); then
            print_success "RTK configured for Codex CLI."
        else
            print_warning "Failed to configure RTK for Codex CLI."
            print_debug "${init_output}"
        fi
    else
        print_debug "Codex CLI not installed; skipping RTK Codex integration."
    fi
}

# Check whether the active Node.js runtime can run current Pi packages.
pi_node_runtime_ready() {
    command -v node &> /dev/null || return 1
    node -e 'const [major, minor] = process.versions.node.split(".").map(Number); process.exit(major > 20 || (major === 20 && minor >= 6) ? 0 : 1)' >/dev/null 2>&1
}

# Ensure Pi runs with a Node.js version new enough for current @earendil-works packages.
ensure_pi_node_runtime() {
    local _runtime="node@24"

    if pi_node_runtime_ready; then
        print_debug "Node.js $(node --version || true) is ready for Pi."
        return 0
    fi

    if [[ -d "${HOME}/.local/bin" ]]; then
        export PATH="${HOME}/.local/bin:${PATH}"
    fi

    if [[ -d "${HOME}/.mise/bin" ]]; then
        export PATH="${HOME}/.mise/bin:${PATH}"
    fi

    if ! command -v mise &> /dev/null; then
        print_warning "Node.js >=20.6 is required for Pi, but mise is not available to install it."
        print_debug "Install mise, then run: mise use -g -y ${_runtime}"
        return 1
    fi

    print_message "Ensuring Node.js 24 runtime for Pi..."
    if ! mise use -g -y "${_runtime}" > /dev/null; then
        print_warning "Failed to install/configure ${_runtime} with mise."
        return 1
    fi

    local _mise_env=""
    if ! _mise_env=$(mise env -C "${HOME}" -s bash "${_runtime}"); then
        print_warning "Failed to generate mise environment for ${_runtime}."
        return 1
    fi

    if ! eval "${_mise_env}"; then
        print_warning "Failed to activate ${_runtime} with mise."
        return 1
    fi

    if pi_node_runtime_ready; then
        print_success "Node.js $(node --version || true) is ready for Pi."
        return 0
    fi

    print_warning "Node.js >=20.6 is still not active after installing ${_runtime}."
    return 1
}

# Resolve the Pi command target across Linux, macOS, and WSL.
pi_command_target() {
    local _pi_cmd=""
    local _link_target=""
    local _link_dir=""

    if ! command -v pi &> /dev/null; then
        return 1
    fi

    _pi_cmd=$(command -v pi)

    if command -v realpath &> /dev/null; then
        realpath "${_pi_cmd}" 2>/dev/null && return 0
    fi

    if readlink -f "${_pi_cmd}" > /dev/null 2>&1; then
        readlink -f "${_pi_cmd}" 2>/dev/null && return 0
    fi

    if [[ -L "${_pi_cmd}" ]]; then
        _link_target=$(readlink "${_pi_cmd}" 2>/dev/null || true)
        if [[ "${_link_target}" == /* ]]; then
            printf '%s\n' "${_link_target}"
        elif [[ -n "${_link_target}" ]]; then
            _link_dir=$(cd "$(dirname "${_pi_cmd}")" && pwd -P)
            printf '%s\n' "${_link_dir}/${_link_target}"
        else
            printf '%s\n' "${_pi_cmd}"
        fi
    else
        printf '%s\n' "${_pi_cmd}"
    fi
}

# Remove stale Pi installs from Bun-managed global locations.
cleanup_noncanonical_pi_installs() {
    local _new_package="${1}"
    local _old_package="${2}"
    local _bun_cmd=""
    local _global_packages=""
    local _package=""
    local _path=""
    local _removed=0

    if command -v bun &> /dev/null; then
        _bun_cmd=$(command -v bun)
    elif [[ -x "${HOME}/.bun/bin/bun" ]]; then
        _bun_cmd="${HOME}/.bun/bin/bun"
    elif [[ -x "${HOME}/.cache/.bun/bin/bun" ]]; then
        _bun_cmd="${HOME}/.cache/.bun/bin/bun"
    fi

    if [[ -n "${_bun_cmd}" ]]; then
        _global_packages=$("${_bun_cmd}" pm ls -g 2>/dev/null || true)
        for _package in "${_new_package}" "${_old_package}"; do
            if grep -Fq "${_package}" <<< "${_global_packages}"; then
                print_message "Removing non-canonical Bun Pi package ${_package}..."
                if "${_bun_cmd}" remove -g "${_package}" > /dev/null 2>&1; then
                    _removed=1
                else
                    print_warning "Failed to remove Bun Pi package ${_package}."
                fi
            fi
        done
    fi

    for _path in \
        "${HOME}/.bun/bin/pi" \
        "${HOME}/.cache/.bun/bin/pi" \
        "${HOME}/.bun/install/global/node_modules/@earendil-works/pi-coding-agent" \
        "${HOME}/.bun/install/global/node_modules/@earendil-works/pi-agent-core" \
        "${HOME}/.bun/install/global/node_modules/@earendil-works/pi-ai" \
        "${HOME}/.bun/install/global/node_modules/@earendil-works/pi-tui" \
        "${HOME}/.bun/install/global/node_modules/@mariozechner/pi-coding-agent" \
        "${HOME}/.bun/install/global/node_modules/@mariozechner/pi-agent-core" \
        "${HOME}/.bun/install/global/node_modules/@mariozechner/pi-ai" \
        "${HOME}/.bun/install/global/node_modules/@mariozechner/pi-tui" \
        "${HOME}/.cache/.bun/install/global/node_modules/@earendil-works/pi-coding-agent" \
        "${HOME}/.cache/.bun/install/global/node_modules/@earendil-works/pi-agent-core" \
        "${HOME}/.cache/.bun/install/global/node_modules/@earendil-works/pi-ai" \
        "${HOME}/.cache/.bun/install/global/node_modules/@earendil-works/pi-tui" \
        "${HOME}/.cache/.bun/install/global/node_modules/@mariozechner/pi-coding-agent" \
        "${HOME}/.cache/.bun/install/global/node_modules/@mariozechner/pi-agent-core" \
        "${HOME}/.cache/.bun/install/global/node_modules/@mariozechner/pi-ai" \
        "${HOME}/.cache/.bun/install/global/node_modules/@mariozechner/pi-tui"; do
        if [[ -e "${_path}" || -L "${_path}" ]]; then
            if rm -rf -- "${_path}"; then
                _removed=1
            else
                print_warning "Failed to remove non-canonical Pi path: ${_path}"
            fi
        fi
    done

    if [[ "${_removed}" -eq 1 ]]; then
        hash -r 2>/dev/null || true
        print_success "Removed non-canonical Bun Pi installs."
    else
        print_debug "No non-canonical Bun Pi installs found."
    fi
}

# Install/update Pi coding agent
install_pi_cli() {
    local _new_package="@earendil-works/pi-coding-agent"
    local _old_package="@mariozechner/pi-coding-agent"
    local _local_prefix="${HOME}/.local"
    local _canonical_bin="${_local_prefix}/bin"
    local _canonical_pi="${_canonical_bin}/pi"
    local _canonical_package_dir="${_local_prefix}/lib/node_modules/${_new_package}"
    local _pi_cmd=""
    local _pi_link_target=""
    local _pi_commands=""
    local _pi_commands_inline=""
    local _pi_target=""
    local _pi_version=""
    local _path_entry=""

    print_message "Installing/updating Pi coding agent..."

    mkdir -p "${_canonical_bin}"
    export PATH="${_canonical_bin}:${PATH}"
    if command -v fish &> /dev/null; then
        fish -lc "fish_add_path -m \"${HOME}/.local/bin\"" > /dev/null 2>&1 || print_debug "Could not persist ~/.local/bin path preference with fish_add_path."
    fi

    if ! ensure_pi_node_runtime; then
        print_warning "Skipping Pi installation and extension setup because the Pi Node.js runtime is not ready."
        return 1
    fi

    if ! command -v npm &> /dev/null; then
        print_warning "npm not found. Cannot install Pi coding agent."
        print_debug "Install Node.js/npm, then run: npm install -g --ignore-scripts --prefix \"${_local_prefix}\" ${_new_package}@latest"
        return 1
    fi

    # Remove old npm-package ownership before installing so npm can claim ~/.local/bin/pi.
    npm uninstall -g --prefix "${_local_prefix}" "${_old_package}" > /dev/null 2>&1 || true
    if [[ -L "${_canonical_pi}" ]]; then
        _pi_target=$(pi_command_target 2>/dev/null || true)
        if [[ "${_pi_target}" == *"/.bun/"* || "${_pi_target}" == *"/.cache/.bun/"* || "${_pi_target}" == *"${_old_package}"* ]]; then
            rm -f -- "${_canonical_pi}" || true
            hash -r 2>/dev/null || true
        fi
    fi

    if [[ -e "${_canonical_pi}" || -L "${_canonical_pi}" ]]; then
        if ! "${_canonical_pi}" --version > /dev/null 2>&1; then
            print_warning "Existing Pi install at ${_canonical_pi} is broken; removing before reinstall."
            if [[ -L "${_canonical_pi}" ]]; then
                _pi_link_target=$(readlink "${_canonical_pi}" 2>/dev/null || true)
                if [[ "${_pi_link_target}" == *"${_new_package}"* || "${_pi_link_target}" == *"${_old_package}"* ]]; then
                    rm -f -- "${_canonical_pi}" || true
                fi
            fi
            if [[ -e "${_canonical_package_dir}" || -L "${_canonical_package_dir}" ]]; then
                if ! rm -rf -- "${_canonical_package_dir}"; then
                    print_error "Failed to remove existing Pi package directory at ${_canonical_package_dir}."
                    return 1
                fi
            fi
        fi
    elif [[ -e "${_canonical_package_dir}" || -L "${_canonical_package_dir}" ]]; then
        print_warning "Found Pi package directory without canonical command; removing before reinstall."
        if ! rm -rf -- "${_canonical_package_dir}"; then
            print_error "Failed to remove existing Pi package directory at ${_canonical_package_dir}."
            return 1
        fi
    fi

    print_message "Installing Pi with npm into ${_canonical_pi}..."
    if ! npm install -g --ignore-scripts --prefix "${_local_prefix}" "${_new_package}@latest"; then
        print_error "Failed to install Pi coding agent."
        return 1
    fi

    npm uninstall -g --prefix "${_local_prefix}" "${_old_package}" > /dev/null 2>&1 || true
    cleanup_noncanonical_pi_installs "${_new_package}" "${_old_package}"
    hash -r 2>/dev/null || true

    _pi_cmd=$(command -v pi 2>/dev/null || true)
    _pi_target=$(pi_command_target 2>/dev/null || true)

    if [[ ! -x "${_canonical_pi}" ]]; then
        print_warning "Pi migration incomplete: canonical Pi command is missing at ${_canonical_pi}."
        return 1
    fi

    if [[ "${_pi_cmd}" != "${_canonical_pi}" ]]; then
        print_warning "Pi migration incomplete: PATH resolves pi to ${_pi_cmd:-<missing>} instead of ${_canonical_pi}."
        if type -P -a pi > /dev/null 2>&1; then
            _pi_commands=$(type -P -a pi 2>/dev/null | awk '!seen[$0]++' || true)
            _pi_commands_inline=${_pi_commands//$'\n'/ }
            print_debug "pi commands on PATH: ${_pi_commands_inline}"
        fi
        return 1
    fi

    if [[ "${_pi_target}" == *"/.bun/"* || "${_pi_target}" == *"/.cache/.bun/"* || "${_pi_target}" == *"${_old_package}"* ]]; then
        print_warning "Pi migration incomplete: canonical pi resolves to non-canonical target ${_pi_target}."
        return 1
    fi

    if [[ "${_pi_target}" != "${_local_prefix}/"* ]]; then
        print_warning "Pi is first on PATH, but resolves outside ${_local_prefix}: ${_pi_target}"
    fi

    if type -P -a pi > /dev/null 2>&1; then
        _pi_commands=$(type -P -a pi 2>/dev/null | awk '!seen[$0]++' || true)
        while IFS= read -r _path_entry; do
            if [[ -n "${_path_entry}" && "${_path_entry}" != "${_canonical_pi}" ]]; then
                print_warning "Additional pi command remains on PATH: ${_path_entry}"
            fi
        done <<< "${_pi_commands}"
    fi

    if ! _pi_version=$(pi --version 2>/dev/null) || [[ -z "${_pi_version}" ]]; then
        print_warning "Pi migration incomplete: pi command failed after installing ${_new_package}."
        return 1
    fi

    print_success "Pi coding agent ${_pi_version} installed/updated at ${_canonical_pi}."
}


# shellcheck disable=SC2312
# Managed marker used to distinguish setup-owned Paseo service artifacts from user-managed ones.
PASEO_MANAGED_MARKER="Managed by scowalt machine setup: headless-paseo-daemon"
PASEO_PACKAGE="@getpaseo/cli"
PASEO_SERVICE_NAME="paseo.service"
PASEO_VALIDATED_CMD=""
PASEO_VALIDATED_NODE=""
PASEO_SERVICE_PATH=""
PASEO_MANAGED_SERVICE_TOUCHED=0
PASEO_PACKAGE_VERSION="unknown"
PASEO_PACKAGE_CHANGED=0
PASEO_DAEMON_WRAPPER_CHANGED=0
PASEO_SYSTEMD_SERVICE_CHANGED=0
PASEO_LAST_HEALTH_ERROR=""
PASEO_LAST_HEALTH_SUMMARY=""

paseo_service_path() {
    printf '%s:%s:%s:%s:%s:%s:%s:%s:%s
' \
        "${HOME}/.local/bin" \
        "${HOME}/.bun/bin" \
        "${HOME}/.local/share/mise/shims" \
        "${HOME}/.mise/shims" \
        "${HOME}/.mise/bin" \
        "/opt/homebrew/bin" \
        "/home/linuxbrew/.linuxbrew/bin" \
        "/usr/local/bin" \
        "/usr/bin:/bin:/usr/sbin:/sbin"
}

paseo_effective_service_path() {
    if [[ -n "${PASEO_SERVICE_PATH}" ]]; then
        printf '%s
' "${PASEO_SERVICE_PATH}"
    else
        paseo_service_path
    fi
}

paseo_shell_quote() {
    local _escaped=""

    _escaped=$(printf '%s' "$1" | sed "s/'/'\\''/g") || return 1
    printf "'%s'" "${_escaped}"
}

paseo_command_target() {
    local _cmd=""
    local _link_target=""
    local _link_dir=""

    if ! command -v paseo &> /dev/null; then
        return 1
    fi

    _cmd=$(command -v paseo)

    if command -v realpath &> /dev/null; then
        realpath "${_cmd}" 2>/dev/null && return 0
    fi

    if readlink -f "${_cmd}" > /dev/null 2>&1; then
        readlink -f "${_cmd}" 2>/dev/null && return 0
    fi

    if [[ -L "${_cmd}" ]]; then
        _link_target=$(readlink "${_cmd}" 2>/dev/null || true)
        if [[ "${_link_target}" == /* ]]; then
            printf '%s\n' "${_link_target}"
        elif [[ -n "${_link_target}" ]]; then
            _link_dir=$(cd "$(dirname "${_cmd}")" && pwd -P)
            printf '%s\n' "${_link_dir}/${_link_target}"
        else
            printf '%s\n' "${_cmd}"
        fi
    else
        printf '%s\n' "${_cmd}"
    fi
}

paseo_command_matches_bun_global() {
    local _paseo_target="$1"
    local _bun_global_bin="$2"
    local _bun_paseo="${_bun_global_bin}/paseo"

    [[ -n "${_paseo_target}" && -n "${_bun_global_bin}" && -e "${_bun_paseo}" ]] || return 1
    [[ "${_paseo_target}" -ef "${_bun_paseo}" ]]
}

paseo_runtime_target() {
    local _cmd=""

    if ! command -v node &> /dev/null; then
        return 1
    fi

    _cmd=$(command -v node)
    if command -v realpath &> /dev/null; then
        realpath "${_cmd}" 2>/dev/null && return 0
    fi
    if readlink -f "${_cmd}" > /dev/null 2>&1; then
        readlink -f "${_cmd}" 2>/dev/null && return 0
    fi
    printf '%s\n' "${_cmd}"
}

paseo_path_owner() {
    local _path="$1"

    if stat -c '%U' "${_path}" >/dev/null 2>&1; then
        stat -c '%U' "${_path}" 2>/dev/null
    else
        stat -f '%Su' "${_path}" 2>/dev/null || true
    fi
}

paseo_path_is_group_or_world_writable() {
    local _path="$1"
    local _dir=""
    local _unsafe=""

    if [[ -z "${_path}" ]]; then
        return 0
    fi

    _unsafe=$(find "${_path}" -prune \( -perm -020 -o -perm -002 \) -print -quit 2>/dev/null || true)
    if [[ -n "${_unsafe}" ]]; then
        return 0
    fi

    if [[ -d "${_path}" ]]; then
        _dir="${_path}"
    else
        _dir=$(dirname "${_path}")
    fi

    [[ -d "${_dir}" ]] || return 0

    while [[ -n "${_dir}" && "${_dir}" != "/" ]]; do
        _unsafe=$(find "${_dir}" -prune \( -perm -020 -o -perm -002 \) -print -quit 2>/dev/null || true)
        if [[ -n "${_unsafe}" ]]; then
            return 0
        fi
        _dir=$(dirname "${_dir}")
    done

    _unsafe=$(find / -prune \( -perm -020 -o -perm -002 \) -print -quit 2>/dev/null || true)
    [[ -n "${_unsafe}" ]]
}

paseo_harden_user_path_chain() {
    local _path="$1"
    local _label="$2"
    local _home_real=""
    local _target=""
    local _dir=""
    local _owner=""
    local _target_under_home=0
    local _user=""

    [[ -n "${_path}" && -e "${_path}" ]] || return 0
    [[ -n "${HOME}" && -d "${HOME}" ]] || return 0

    _user=$(whoami || true)
    [[ -n "${_user}" ]] || return 0

    if command -v realpath &> /dev/null; then
        _home_real=$(realpath "${HOME}" 2>/dev/null || true)
        _target=$(realpath "${_path}" 2>/dev/null || true)
    elif readlink -f "${HOME}" > /dev/null 2>&1 && readlink -f "${_path}" > /dev/null 2>&1; then
        _home_real=$(readlink -f "${HOME}" 2>/dev/null || true)
        _target=$(readlink -f "${_path}" 2>/dev/null || true)
    else
        _home_real=$(cd "${HOME}" && pwd -P) || return 0
        if [[ -d "${_path}" ]]; then
            _target=$(cd "${_path}" && pwd -P) || return 0
        else
            _dir=$(cd "$(dirname "${_path}")" && pwd -P) || return 0
            _target="${_dir}/$(basename "${_path}")"
        fi
    fi

    [[ -n "${_home_real}" && -n "${_target}" ]] || return 0

    case "${_target}" in
        "${_home_real}"|"${_home_real}/"*) _target_under_home=1 ;;
        *) ;;
    esac

    _owner=$(paseo_path_owner "${_target}")
    if [[ "${_owner}" == "${_user}" ]] && ! chmod go-w "${_target}"; then
        print_error "Failed to harden Paseo ${_label} path permissions: ${_target}"
        return 1
    fi

    if [[ -d "${_target}" ]]; then
        _dir="${_target}"
    else
        _dir=$(dirname "${_target}")
    fi

    while [[ -n "${_dir}" && "${_dir}" != "/" ]]; do
        if [[ "${_target_under_home}" == "1" ]]; then
            case "${_dir}" in
                "${_home_real}"|"${_home_real}/"*) ;;
                *) break ;;
            esac
        fi

        _owner=$(paseo_path_owner "${_dir}")
        if [[ "${_owner}" == "${_user}" ]] && ! chmod go-w "${_dir}"; then
            print_error "Failed to harden Paseo ${_label} parent permissions: ${_dir}"
            return 1
        elif [[ "${_owner}" != "${_user}" && "${_target_under_home}" != "1" ]]; then
            break
        fi

        [[ "${_dir}" == "${_home_real}" ]] && break
        _dir=$(dirname "${_dir}")
    done
}

paseo_harden_service_path_components() {
    local _path_value="$1"
    local _component=""

    while IFS= read -r _component; do
        [[ -n "${_component}" ]] || continue

        if [[ -L "${_component}" ]]; then
            paseo_harden_user_path_chain "$(dirname "${_component}")" "service PATH component parent" || return 1
        fi

        [[ -e "${_component}" ]] || continue
        paseo_harden_user_path_chain "${_component}" "service PATH component" || return 1
    done < <(printf '%s\n' "${_path_value}" | tr ':' '\n' || true)
}

paseo_existing_service_path() {
    local _path_value="$1"
    local _component=""
    local _result=""

    while IFS= read -r _component; do
        [[ -n "${_component}" && -d "${_component}" ]] || continue

        if [[ -z "${_result}" ]]; then
            _result="${_component}"
        else
            _result="${_result}:${_component}"
        fi
    done < <(printf '%s\n' "${_path_value}" | tr ':' '\n' || true)

    printf '%s\n' "${_result}"
}

paseo_path_owner_is_trusted() {
    local _path="$1"
    local _dir=""
    local _owner=""
    local _user=""

    _user=$(whoami || true)
    _owner=$(paseo_path_owner "${_path}")
    case "${_owner}" in
        root|"${_user}"|linuxbrew|homebrew) ;;
        *) return 1 ;;
    esac

    if [[ -d "${_path}" ]]; then
        _dir="${_path}"
    else
        _dir=$(dirname "${_path}")
    fi

    [[ -d "${_dir}" ]] || return 1

    while [[ -n "${_dir}" && "${_dir}" != "/" ]]; do
        _owner=$(paseo_path_owner "${_dir}")
        case "${_owner}" in
            root|"${_user}"|linuxbrew|homebrew) ;;
            *) return 1 ;;
        esac
        _dir=$(dirname "${_dir}")
    done

    return 0
}

paseo_validate_trusted_path() {
    local _path="$1"
    local _label="$2"

    if [[ -z "${_path}" || ! -e "${_path}" ]]; then
        print_error "Paseo ${_label} path is missing."
        return 1
    fi

    if paseo_path_is_group_or_world_writable "${_path}"; then
        print_error "Paseo ${_label} path is under a group/world-writable directory; refusing to trust it."
        return 1
    fi

    if ! paseo_path_owner_is_trusted "${_path}"; then
        print_error "Paseo ${_label} path has an untrusted owner in its parent chain; refusing to trust it."
        return 1
    fi
}

paseo_validate_service_path_components() {
    local _path_value="$1"
    local _component=""
    local _resolved_component=""
    local _link_target=""
    local _link_dir=""

    while IFS= read -r _component; do
        [[ -n "${_component}" && -d "${_component}" ]] || continue

        _resolved_component="${_component}"
        if [[ -L "${_component}" ]]; then
            if command -v realpath &> /dev/null; then
                _resolved_component=$(realpath "${_component}" 2>/dev/null || true)
            elif readlink -f "${_component}" > /dev/null 2>&1; then
                _resolved_component=$(readlink -f "${_component}" 2>/dev/null || true)
            else
                _link_target=$(readlink "${_component}" 2>/dev/null || true)
                if [[ "${_link_target}" == /* ]]; then
                    _resolved_component="${_link_target}"
                elif [[ -n "${_link_target}" ]]; then
                    _link_dir=$(cd "$(dirname "${_component}")" && pwd -P)
                    _resolved_component="${_link_dir}/${_link_target}"
                fi
            fi

            if [[ -z "${_resolved_component}" || ! -d "${_resolved_component}" ]]; then
                print_error "Paseo service PATH component ${_component} resolves to a missing target."
                return 1
            fi

            # Symlink mode bits are commonly 0777 and not security-relevant; validate
            # the trusted parent plus the resolved target instead.
            paseo_validate_trusted_path "$(dirname "${_component}")" "service PATH component parent" || return 1
        fi

        paseo_validate_trusted_path "${_resolved_component}" "service PATH component" || return 1
    done < <(printf '%s\n' "${_path_value}" | tr ':' '\n' || true)
}

install_paseo_cli() {
    local _global_packages=""
    local _paseo_target=""
    local _previous_paseo_target=""
    local _previous_version_output=""
    local _node_target=""
    local _node_dir=""
    local _version_output=""
    local _service_path=""
    local _bun_global_bin=""

    if [[ "${HEADLESS:-}" != "1" ]]; then
        return 0
    fi

    PASEO_PACKAGE_CHANGED=0
    print_message "Installing/updating Paseo CLI for headless daemon setup..."

    _service_path=$(paseo_service_path)
    export PATH="${HOME}/.bun/bin:${_service_path}:${PATH}"

    _previous_paseo_target=$(paseo_command_target 2>/dev/null || true)
    if [[ -n "${_previous_paseo_target}" ]]; then
        _previous_version_output=$(HOME="${HOME}" PATH="${PATH}" "${_previous_paseo_target}" --version 2>/dev/null || true)
    fi
    if ! command -v bun &> /dev/null; then
        print_error "Bun not found. Cannot install ${PASEO_PACKAGE} for HEADLESS=1."
        return 1
    fi

    if ! ensure_pi_node_runtime; then
        print_error "Node.js >=20.6 is required before installing ${PASEO_PACKAGE}."
        return 1
    fi

    if ! bun install -g "${PASEO_PACKAGE}"; then
        print_error "Failed to install ${PASEO_PACKAGE}."
        return 1
    fi

    hash -r 2>/dev/null || true
    _global_packages=$(bun pm ls -g 2>/dev/null || true)
    if ! grep -Fq "${PASEO_PACKAGE}" <<< "${_global_packages}"; then
        print_error "Paseo install validation failed: ${PASEO_PACKAGE} is not listed in Bun global packages."
        return 1
    fi

    _paseo_target=$(paseo_command_target 2>/dev/null || true)
    if [[ -z "${_paseo_target}" ]]; then
        print_error "Paseo install validation failed: paseo command is not available after installing ${PASEO_PACKAGE}."
        return 1
    fi

    _bun_global_bin=$(bun pm bin -g 2>/dev/null || true)
    if [[ -z "${_bun_global_bin}" ]]; then
        print_error "Paseo install validation failed: Bun global bin path could not be resolved."
        return 1
    fi
    if ! paseo_command_matches_bun_global "${_paseo_target}" "${_bun_global_bin}"; then
        if [[ "${_paseo_target}" == *"/node_modules/paseo/"* ]] || [[ "${_paseo_target}" == *"/node_modules/paseo/bin"* ]]; then
            print_error "Paseo command resolves to the unrelated unscoped paseo package: ${_paseo_target}"
        else
            print_error "Paseo command does not match Bun's global paseo executable: ${_paseo_target}"
        fi
        return 1
    fi

    paseo_harden_user_path_chain "${_paseo_target}" "executable" || return 1
    paseo_validate_trusted_path "${_paseo_target}" "executable" || return 1

    _node_target=$(paseo_runtime_target 2>/dev/null || true)
    if [[ -z "${_node_target}" ]]; then
        print_error "Paseo runtime validation failed: node is not available for the service wrapper."
        return 1
    fi
    paseo_harden_user_path_chain "${_node_target}" "runtime" || return 1
    paseo_validate_trusted_path "${_node_target}" "runtime" || return 1

    PASEO_VALIDATED_CMD="${_paseo_target}"
    PASEO_VALIDATED_NODE="${_node_target}"
    _node_dir=$(dirname "${_node_target}")
    _service_path=$(paseo_service_path)
    _service_path="${_node_dir}:${_service_path}"
    PASEO_SERVICE_PATH=$(paseo_existing_service_path "${_service_path}")
    if [[ -z "${PASEO_SERVICE_PATH}" ]]; then
        print_error "Paseo service PATH validation failed: no existing PATH components remain."
        return 1
    fi
    paseo_harden_service_path_components "${PASEO_SERVICE_PATH}" || return 1
    paseo_validate_service_path_components "${PASEO_SERVICE_PATH}" || return 1

    if ! _version_output=$(HOME="${HOME}" PATH="${PASEO_SERVICE_PATH}:${PATH}" "${_paseo_target}" --version 2>/dev/null); then
        print_error "Paseo install validation failed: validated paseo command did not run successfully with the service PATH."
        return 1
    fi

    PASEO_PACKAGE_VERSION=$(printf '%s' "${_version_output}" | head -n 1 || true)
    PASEO_PACKAGE_VERSION=$(printf '%s' "${PASEO_PACKAGE_VERSION}" | tr -cd '[:alnum:].:_/@ -' | cut -c1-80 || true)
    [[ -n "${PASEO_PACKAGE_VERSION}" ]] || PASEO_PACKAGE_VERSION="unknown"

    if [[ "${_previous_paseo_target}" != "${_paseo_target}" || "${_previous_version_output}" != "${_version_output}" ]]; then
        PASEO_PACKAGE_CHANGED=1
    fi

    print_success "Paseo CLI ready (${PASEO_PACKAGE}, ${PASEO_PACKAGE_VERSION})."
}

write_paseo_daemon_wrapper() {
    local _wrapper="${HOME}/.local/bin/paseo-daemon-start"
    local _log_dir="${HOME}/.local/log/paseo-daemon"
    local _tmp=""
    local _home_q=""
    local _path_q=""
    local _cmd_q=""
    local _node_q=""
    local _service_path=""

    if [[ -z "${PASEO_VALIDATED_CMD}" ]]; then
        print_error "Cannot write Paseo daemon wrapper before validating the paseo command."
        return 1
    fi

    PASEO_DAEMON_WRAPPER_CHANGED=0
    mkdir -p "${HOME}/.local/bin" "${_log_dir}"
    chmod 700 "${HOME}/.local/bin" "${_log_dir}"

    _service_path=$(paseo_effective_service_path)
    _home_q=$(paseo_shell_quote "${HOME}")
    _path_q=$(paseo_shell_quote "${_service_path}")
    _cmd_q=$(paseo_shell_quote "${PASEO_VALIDATED_CMD}")
    _node_q=$(paseo_shell_quote "${PASEO_VALIDATED_NODE}")
    _tmp=$(mktemp)
    if ! cat > "${_tmp}" << EOF
#!/bin/bash
# ${PASEO_MANAGED_MARKER}
set -euo pipefail
export HOME=${_home_q}
export PATH=${_path_q}
[[ -x ${_node_q} ]] || exit 127
[[ -x ${_cmd_q} ]] || exit 127
exec ${_cmd_q} daemon start --foreground
EOF
    then
        rm -f "${_tmp}"
        print_error "Failed to write Paseo daemon wrapper."
        return 1
    fi
    if ! chmod 700 "${_tmp}"; then
        rm -f "${_tmp}"
        print_error "Failed to install Paseo daemon wrapper."
        return 1
    fi

    if [[ -f "${_wrapper}" ]] && cmp -s "${_tmp}" "${_wrapper}"; then
        rm -f "${_tmp}"
        if ! chmod 700 "${_wrapper}"; then
            print_error "Failed to secure Paseo daemon wrapper."
            return 1
        fi
        print_debug "Paseo daemon wrapper is unchanged."
    else
        if ! mv "${_tmp}" "${_wrapper}"; then
            rm -f "${_tmp}"
            print_error "Failed to install Paseo daemon wrapper."
            return 1
        fi
        PASEO_DAEMON_WRAPPER_CHANGED=1
        print_success "Paseo daemon wrapper installed at ${_wrapper}."
    fi
}

paseo_managed_service_is_active() {
    paseo_systemctl_user is-active "${PASEO_SERVICE_NAME}" >/dev/null 2>&1
}

paseo_systemctl_user() {
    local _uid=""
    local _runtime_dir=""

    _uid=$(id -u 2>/dev/null || true)
    [[ "${_uid}" =~ ^[0-9]+$ ]] || return 1
    _runtime_dir="/run/user/${_uid}"

    XDG_RUNTIME_DIR="${_runtime_dir}" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=${_runtime_dir}/bus" \
        systemctl --user "$@"
}

stop_existing_paseo_daemon() {
    local _service_path=""
    local _state=""

    if [[ -z "${PASEO_VALIDATED_CMD}" ]]; then
        return 0
    fi

    if paseo_managed_service_is_active; then
        print_debug "Existing Paseo daemon is already managed by ${PASEO_SERVICE_NAME}; leaving it running until change detection completes."
        return 0
    fi

    _state=$(paseo_local_daemon_state 2>/dev/null || true)
    if [[ "${_state}" != "running" ]]; then
        print_debug "No running unmanaged Paseo daemon detected before service start."
        return 0
    fi

    print_message "Stopping existing unmanaged Paseo daemon before service start..."
    _service_path=$(paseo_effective_service_path)
    if ! HOME="${HOME}" PATH="${_service_path}:${PATH}" paseo_run_with_timeout "${PASEO_STATUS_TIMEOUT_SECONDS:-10}" "${PASEO_VALIDATED_CMD}" daemon stop >/dev/null 2>&1; then
        print_error "Failed to stop existing Paseo daemon before installing the managed service."
        return 1
    fi

    sleep 1
    _state=$(paseo_local_daemon_state 2>/dev/null || true)
    if [[ "${_state}" == "running" ]]; then
        print_error "Existing Paseo daemon is still running after stop; refusing to let it mask managed-service health."
        return 1
    fi
}

paseo_sanitize_status_value() {
    printf '%s' "${1:-unknown}" | tr -cd '[:alnum:]_.:-' | cut -c1-64 || true
}

paseo_json_string_field() {
    local _json="$1"
    local _field="$2"

    printf '%s\n' "${_json}" | sed -n "s/.*\"${_field}\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -n 1 || true
}

paseo_status_relay_disabled() {
    local _json="$1"

    printf '%s\n' "${_json}" | grep -Eqi '\"relayDisabled\"[[:space:]]*:[[:space:]]*true|\"relayEnabled\"[[:space:]]*:[[:space:]]*false|\"relay\"[[:space:]]*:[[:space:]]*\"disabled\"|\"relayStatus\"[[:space:]]*:[[:space:]]*\"disabled\"'
}


paseo_run_with_timeout() {
    local _seconds="$1"
    shift

    if command -v timeout &> /dev/null; then
        timeout "${_seconds}" "$@"
    elif command -v perl &> /dev/null; then
        perl -e 'alarm shift; exec @ARGV' "${_seconds}" "$@"
    else
        print_error "No timeout helper (timeout or perl) is available for Paseo health checks."
        return 124
    fi
}

paseo_local_daemon_state() {
    local _status_json=""
    local _service_path=""

    _service_path=$(paseo_effective_service_path)
    if ! _status_json=$(HOME="${HOME}" PATH="${_service_path}:${PATH}" paseo_run_with_timeout "${PASEO_STATUS_TIMEOUT_SECONDS:-10}" "${PASEO_VALIDATED_CMD}" daemon status --json 2>/dev/null); then
        return 1
    fi

    paseo_json_string_field "${_status_json}" "localDaemon"
}

paseo_check_status_once() {
    local _status_json=""
    local _local_daemon=""
    local _connected_daemon=""
    local _field_value=""
    local _service_path=""

    _service_path=$(paseo_effective_service_path)
    if ! _status_json=$(HOME="${HOME}" PATH="${_service_path}:${PATH}" paseo_run_with_timeout "${PASEO_STATUS_TIMEOUT_SECONDS:-10}" "${PASEO_VALIDATED_CMD}" daemon status --json 2>/dev/null); then
        PASEO_LAST_HEALTH_ERROR="status command failed or timed out"
        return 1
    fi

    if ! printf '%s' "${_status_json}" | grep -q '^{'; then
        PASEO_LAST_HEALTH_ERROR="status command did not return JSON"
        return 1
    fi

    _field_value=$(paseo_json_string_field "${_status_json}" "localDaemon")
    _local_daemon=$(paseo_sanitize_status_value "${_field_value}")
    _field_value=$(paseo_json_string_field "${_status_json}" "connectedDaemon")
    _connected_daemon=$(paseo_sanitize_status_value "${_field_value}")
    PASEO_LAST_HEALTH_SUMMARY="localDaemon=${_local_daemon:-unknown}, connectedDaemon=${_connected_daemon:-unknown}"

    if [[ "${_local_daemon}" != "running" ]]; then
        PASEO_LAST_HEALTH_ERROR="${PASEO_LAST_HEALTH_SUMMARY}"
        return 1
    fi

    case "${_connected_daemon}" in
        reachable|auth_required) ;;
        auth_failed)
            PASEO_LAST_HEALTH_ERROR="${PASEO_LAST_HEALTH_SUMMARY}"
            return 1
            ;;
        *)
            PASEO_LAST_HEALTH_ERROR="${PASEO_LAST_HEALTH_SUMMARY}"
            return 1
            ;;
    esac

    if paseo_status_relay_disabled "${_status_json}"; then
        PASEO_LAST_HEALTH_ERROR="${PASEO_LAST_HEALTH_SUMMARY}, relay=disabled"
        return 1
    fi

    PASEO_LAST_HEALTH_ERROR=""
    return 0
}

wait_for_paseo_health() {
    local _attempt=1
    local _max_attempts="${PASEO_HEALTH_ATTEMPTS:-12}"
    local _interval="${PASEO_HEALTH_INTERVAL_SECONDS:-5}"

    while [[ "${_attempt}" -le "${_max_attempts}" ]]; do
        if paseo_check_status_once; then
            print_success "Paseo daemon health verified (${PASEO_LAST_HEALTH_SUMMARY})."
            return 0
        fi

        print_debug "Waiting for Paseo daemon health (${_attempt}/${_max_attempts}): ${PASEO_LAST_HEALTH_ERROR}"
        sleep "${_interval}"
        _attempt=$((_attempt + 1))
    done

    print_error "Paseo daemon health check failed after ${_max_attempts} attempts: ${PASEO_LAST_HEALTH_ERROR}"
    print_debug "Diagnostics: package=${PASEO_PACKAGE} version=${PASEO_PACKAGE_VERSION} node=${PASEO_VALIDATED_NODE:-unknown} user=$(whoami || true) home=${HOME} logs=${HOME}/.local/log/paseo-daemon"
    return 1
}

paseo_service_process_pids() {
    local _root_pid="$1"
    local _process_rows=""

    [[ -n "${_root_pid}" && "${_root_pid}" != "0" ]] || return 0
    printf '%s\n' "${_root_pid}"

    if ! _process_rows=$(ps -eo pid=,ppid= 2>/dev/null); then
        return 0
    fi

    printf '%s\n' "${_process_rows}" | awk -v root="${_root_pid}" '
        $1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ {
            _pid = $1
            _ppid = $2
            children[_ppid] = children[_ppid] " " _pid
        }
        END {
            if (root !~ /^[0-9]+$/) {
                exit
            }
            seen[root] = 1
            queue[1] = root
            head = 1
            tail = 1
            while (head <= tail) {
                _pid = queue[head++]
                split(children[_pid], child, " ")
                for (i in child) {
                    if (child[i] != "" && !seen[child[i]]) {
                        seen[child[i]] = 1
                        queue[++tail] = child[i]
                        print child[i]
                    }
                }
            }
        }
    ' || true
}

paseo_listener_audit() {
    local _pid="$1"
    local _pid_list=""
    local _listener_pid=""
    local _bad_listener=""
    local _addr=""
    local _listeners=""
    local _listener_source=""

    if [[ -z "${_pid}" || "${_pid}" == "0" ]]; then
        print_error "Paseo service PID unavailable; cannot audit listeners for HEADLESS=1."
        return 1
    fi

    _pid_list=$(paseo_service_process_pids "${_pid}" | awk 'NF && !seen[$0]++' || true)
    if [[ -z "${_pid_list}" ]]; then
        _pid_list="${_pid}"
    fi

    if command -v ss &> /dev/null; then
        if ! _listener_source=$(ss -H -ltnp 2>/dev/null); then
            print_error "Failed to inspect Paseo listeners with ss."
            return 1
        fi
        if ! _listeners=$(printf '%s
' "${_listener_source}" | awk -v pids="${_pid_list}" '
            BEGIN {
                split(pids, pid_values, /[[:space:]]+/)
                for (i in pid_values) {
                    if (pid_values[i] ~ /^[0-9]+$/) {
                        wanted[pid_values[i]] = 1
                    }
                }
            }
            {
                for (pid in wanted) {
                    if ($0 ~ "pid=" pid ",") {
                        print $4
                        next
                    }
                }
            }
        '); then
            print_error "Failed to parse Paseo listeners from ss output."
            return 1
        fi
    elif command -v lsof &> /dev/null; then
        _listener_source=$(
            while IFS= read -r _listener_pid; do
                [[ -n "${_listener_pid}" ]] || continue
                lsof -nP -a -p "${_listener_pid}" -iTCP -sTCP:LISTEN 2>/dev/null || true
            done <<< "${_pid_list}"
        )
        if ! _listeners=$(printf '%s
' "${_listener_source}" | awk '$1 != "COMMAND" && $9 != "" {print $9}'); then
            print_error "Failed to parse Paseo listeners from lsof output."
            return 1
        fi
    else
        print_error "No listener-audit tool found (ss/lsof); cannot verify Paseo is loopback-only."
        return 1
    fi

    if [[ -z "${_listeners}" ]]; then
        print_error "No TCP listeners could be associated with the managed Paseo service process tree; refusing to let another daemon satisfy health checks."
        return 1
    fi

    while IFS= read -r _addr; do
        [[ -n "${_addr}" ]] || continue
        case "${_addr}" in
            127.*|"[::1]:"*|"::1:"*|localhost:*|"[::ffff:127."*) ;;
            *)
                _bad_listener="${_addr}"
                break
                ;;
        esac
    done <<< "${_listeners}"

    if [[ -n "${_bad_listener}" ]]; then
        print_error "Paseo daemon appears to listen on a non-loopback address (${_bad_listener}); refusing HEADLESS=1 setup."
        return 1
    fi

    print_debug "Paseo listener audit passed."
}

paseo_service_owner_check() {
    local _pid="$1"
    local _expected_user=""
    local _actual_user=""

    if [[ -z "${_pid}" || "${_pid}" == "0" ]]; then
        print_error "Paseo service PID unavailable; cannot verify managed service ownership."
        return 1
    fi

    _expected_user=$(whoami || true)
    _actual_user=$(ps -o user= -p "${_pid}" 2>/dev/null | awk '{print $1}' || true)
    if [[ -z "${_actual_user}" ]]; then
        print_error "Could not verify owner for Paseo service PID ${_pid}."
        return 1
    fi
    if [[ "${_actual_user}" != "${_expected_user}" ]]; then
        print_error "Paseo daemon is running as ${_actual_user}, expected ${_expected_user}."
        return 1
    fi
}

paseo_is_wsl_environment() {
    grep -qiE '(microsoft|wsl)' /proc/version /proc/sys/kernel/osrelease 2>/dev/null || [[ -n "${WSL_DISTRO_NAME:-}" ]] || [[ -f /proc/sys/fs/binfmt_misc/WSLInterop ]]
}

paseo_is_container_environment() {
    [[ -f /.dockerenv ]] || { command -v systemd-detect-virt &> /dev/null && systemd-detect-virt --container --quiet 2>/dev/null; }
}

paseo_headless_platform_gate() {
    if [[ "${HEADLESS:-}" != "1" ]]; then
        return 0
    fi

    if [[ "$(uname -s 2>/dev/null || true)" != "Linux" ]]; then
        return 0
    fi

    if paseo_is_wsl_environment; then
        print_error "HEADLESS=1 Paseo daemon setup is unsupported in WSL because WSL cannot guarantee startup after Windows host reboot without login."
        return 1
    fi

    if paseo_is_container_environment; then
        print_error "HEADLESS=1 Paseo daemon setup requires a booting native Linux user manager; container environments are unsupported."
        return 1
    fi
}

paseo_native_linux_preflight() {
    local _user=""

    if [[ "$(uname -s 2>/dev/null || true)" != "Linux" ]]; then
        print_error "Native Linux Paseo headless service setup requires Linux."
        return 1
    fi

    if paseo_is_wsl_environment; then
        print_error "HEADLESS=1 Paseo daemon setup is unsupported in WSL because WSL cannot guarantee startup after Windows host reboot without login."
        return 1
    fi

    if paseo_is_container_environment; then
        print_error "HEADLESS=1 Paseo daemon setup requires a booting native Linux user manager; container environments are unsupported."
        return 1
    fi

    _user=$(whoami || true)
    if [[ -z "${_user}" || -z "${HOME}" || ! -d "${HOME}" ]]; then
        print_error "Cannot resolve target user/home for Paseo daemon setup."
        return 1
    fi

    if ! command -v loginctl &> /dev/null; then
        print_error "loginctl is required to enable lingering for the Paseo user service."
        return 1
    fi

    if ! command -v systemctl &> /dev/null; then
        print_error "systemctl is required to manage the Paseo user service."
        return 1
    fi

    if ! loginctl show-user "${_user}" >/dev/null 2>&1; then
        print_error "loginctl cannot inspect user ${_user}; cannot guarantee no-login Paseo startup."
        return 1
    fi

    if ! paseo_user_lingering_enabled "${_user}" && ! can_sudo; then
        print_error "sudo access is required to enable lingering for HEADLESS=1 Paseo daemon setup."
        return 1
    fi

    if ! paseo_systemctl_user show-environment >/dev/null 2>&1; then
        print_error "The systemd user manager is unavailable; cannot configure the Paseo user service safely."
        return 1
    fi
}

paseo_user_lingering_enabled() {
    local _user="$1"

    { loginctl show-user "${_user}" --property=Linger 2>/dev/null || true; } | grep -q 'Linger=yes'
}

paseo_enable_lingering_strict() {
    local _user=""

    _user=$(whoami || true)
    if paseo_user_lingering_enabled "${_user}"; then
        print_debug "User lingering already enabled for Paseo daemon."
        return 0
    fi

    if ! can_sudo; then
        print_error "sudo access is required to enable lingering for HEADLESS=1 Paseo daemon setup."
        return 1
    fi

    print_message "Enabling lingering for Paseo systemd user service..."
    if ! sudo loginctl enable-linger "${_user}"; then
        print_error "Failed to enable lingering for ${_user}."
        return 1
    fi

    if ! paseo_user_lingering_enabled "${_user}"; then
        print_error "Lingering verification failed for ${_user}."
        return 1
    fi
    print_success "User lingering enabled for Paseo daemon."
}

paseo_existing_managed_service_check() {
    local _service_file="${HOME}/.config/systemd/user/${PASEO_SERVICE_NAME}"
    local _wrapper="${HOME}/.local/bin/paseo-daemon-start"

    if [[ -f "${_service_file}" ]] && ! grep -qF "${PASEO_MANAGED_MARKER}" "${_service_file}"; then
        print_error "Existing unmanaged ${_service_file} found. Remove or rename it before rerunning HEADLESS=1 setup."
        return 1
    fi

    if [[ -f "${_wrapper}" ]] && ! grep -qF "${PASEO_MANAGED_MARKER}" "${_wrapper}"; then
        print_error "Existing unmanaged ${_wrapper} found. Remove or rename it before rerunning HEADLESS=1 setup."
        return 1
    fi
}

paseo_linux_service_pid() {
    paseo_systemctl_user show "${PASEO_SERVICE_NAME}" --property=MainPID --value 2>/dev/null | head -n 1 || true
}

install_paseo_systemd_user_service() {
    local _service_dir="${HOME}/.config/systemd/user"
    local _service_file="${_service_dir}/${PASEO_SERVICE_NAME}"
    local _service_path=""
    local _tmp=""

    _service_path=$(paseo_effective_service_path)
    PASEO_SYSTEMD_SERVICE_CHANGED=0
    mkdir -p "${_service_dir}"
    chmod 700 "${_service_dir}"

    if [[ -f "${_service_file}" ]] && ! grep -qF "${PASEO_MANAGED_MARKER}" "${_service_file}"; then
        print_error "Existing unmanaged ${_service_file} found. Remove or rename it before rerunning HEADLESS=1 setup."
        return 1
    fi

    _tmp=$(mktemp)
    if ! cat > "${_tmp}" << EOF
# ${PASEO_MANAGED_MARKER}
[Unit]
Description=Paseo headless daemon
Documentation=https://www.getpaseo.com/

[Service]
Type=simple
ExecStart=${HOME}/.local/bin/paseo-daemon-start
WorkingDirectory=${HOME}
Environment=HOME=${HOME}
Environment=PATH=${_service_path}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF
    then
        rm -f "${_tmp}"
        print_error "Failed to write Paseo systemd user service."
        return 1
    fi
    if ! chmod 600 "${_tmp}"; then
        rm -f "${_tmp}"
        print_error "Failed to install Paseo systemd user service."
        return 1
    fi

    if [[ -f "${_service_file}" ]] && cmp -s "${_tmp}" "${_service_file}"; then
        rm -f "${_tmp}"
        if ! chmod 600 "${_service_file}"; then
            print_error "Failed to secure Paseo systemd user service."
            return 1
        fi
        print_debug "Paseo systemd user service definition is unchanged."
    else
        if ! mv "${_tmp}" "${_service_file}"; then
            rm -f "${_tmp}"
            print_error "Failed to install Paseo systemd user service."
            return 1
        fi
        PASEO_SYSTEMD_SERVICE_CHANGED=1
    fi

    paseo_enable_lingering_strict || return 1

    if [[ "${PASEO_SYSTEMD_SERVICE_CHANGED}" == "1" ]]; then
        if ! paseo_systemctl_user daemon-reload; then
            print_error "Failed to reload systemd user units for Paseo."
            return 1
        fi
    fi

    if ! paseo_systemctl_user enable "${PASEO_SERVICE_NAME}"; then
        print_error "Failed to enable ${PASEO_SERVICE_NAME}."
        return 1
    fi

    if ! paseo_managed_service_is_active; then
        PASEO_MANAGED_SERVICE_TOUCHED=1
        if ! paseo_systemctl_user start "${PASEO_SERVICE_NAME}"; then
            print_error "Failed to start ${PASEO_SERVICE_NAME}."
            return 1
        fi
    elif [[ "${PASEO_PACKAGE_CHANGED}" == "1" || "${PASEO_DAEMON_WRAPPER_CHANGED}" == "1" || "${PASEO_SYSTEMD_SERVICE_CHANGED}" == "1" ]]; then
        PASEO_MANAGED_SERVICE_TOUCHED=1
        if ! paseo_systemctl_user restart "${PASEO_SERVICE_NAME}"; then
            print_error "Failed to restart ${PASEO_SERVICE_NAME} after a Paseo package or service change."
            return 1
        fi
    else
        print_debug "Paseo package, wrapper, and service definition are unchanged; leaving the active daemon running."
    fi

    if ! paseo_systemctl_user is-enabled "${PASEO_SERVICE_NAME}" >/dev/null 2>&1; then
        print_error "${PASEO_SERVICE_NAME} is not enabled after setup."
        return 1
    fi

    if ! paseo_systemctl_user is-active "${PASEO_SERVICE_NAME}" >/dev/null 2>&1; then
        print_error "${PASEO_SERVICE_NAME} is not active after setup."
        print_debug "Inspect privately with: journalctl --user -u ${PASEO_SERVICE_NAME} --no-pager"
        return 1
    fi

    print_success "Paseo systemd user service enabled and active."
}

cleanup_paseo_managed_service() {
    local _platform="$1"

    if [[ "${PASEO_MANAGED_SERVICE_TOUCHED}" != "1" ]]; then
        return 0
    fi

    case "${_platform}" in
        Linux)
            paseo_systemctl_user stop "${PASEO_SERVICE_NAME}" >/dev/null 2>&1 || true
            paseo_systemctl_user disable "${PASEO_SERVICE_NAME}" >/dev/null 2>&1 || true
            ;;
        *) ;;
    esac
    print_debug "Stopped managed Paseo service after failed verification; managed files and logs remain for inspection."
}

setup_headless_paseo_daemon() {
    local _platform=""
    local _service_pid=""

    if [[ "${HEADLESS:-}" != "1" ]]; then
        return 0
    fi

    _platform=$(uname -s 2>/dev/null || true)
    if [[ "${_platform}" != "Linux" ]]; then
        print_error "HEADLESS=1 Paseo daemon setup is unsupported on ${_platform:-this platform}."
        return 1
    fi
    paseo_native_linux_preflight || return 1
    paseo_existing_managed_service_check || return 1

    install_paseo_cli || return 1
    write_paseo_daemon_wrapper || return 1
    stop_existing_paseo_daemon || return 1

    if ! install_paseo_systemd_user_service; then
        cleanup_paseo_managed_service "${_platform}"
        return 1
    fi
    _service_pid=$(paseo_linux_service_pid || true)

    if ! paseo_service_owner_check "${_service_pid}" || ! wait_for_paseo_health || ! paseo_listener_audit "${_service_pid}"; then
        cleanup_paseo_managed_service "${_platform}"
        return 1
    fi

    print_success "Headless Paseo daemon is service-managed and locally reachable. Use Paseo's normal pairing flow later if needed."
}

# Update Pi settings for the tintinweb subagents extension
update_pi_subagents_settings() {
    local _mode="${1:-install}"
    local _settings_dir="${PI_CODING_AGENT_DIR:-${HOME}/.pi/agent}"
    local _settings_file="${_settings_dir}/settings.json"
    local _tmp=""

    if ! command -v jq &> /dev/null; then
        print_warning "jq not found. Cannot update Pi subagents settings."
        return 1
    fi

    mkdir -p "${_settings_dir}"

    if [[ ! -f "${_settings_file}" ]]; then
        printf '{}\n' > "${_settings_file}"
    fi

    _tmp=$(mktemp)
    if [[ "${_mode}" == "remove" ]]; then
        if jq '
            def package_source:
                if type == "string" then .
                elif type == "object" then (.source // "")
                else ""
                end;
            def packages_array:
                if (.packages | type) == "array" then .packages else [] end;
            .packages = (packages_array | map(select((package_source != "npm:pi-subagents") and (package_source != "npm:@tintinweb/pi-subagents"))))
            | if (.packages | length) == 0 then del(.packages) else . end
        ' "${_settings_file}" > "${_tmp}"; then
            mv "${_tmp}" "${_settings_file}"
        else
            rm -f "${_tmp}"
            print_warning "Failed to update Pi settings at ${_settings_file}."
            return 1
        fi
    else
        if jq '
            def package_source:
                if type == "string" then .
                elif type == "object" then (.source // "")
                else ""
                end;
            def packages_array:
                if (.packages | type) == "array" then .packages else [] end;
            .packages = (packages_array | map(select(package_source != "npm:pi-subagents")))
        ' "${_settings_file}" > "${_tmp}"; then
            mv "${_tmp}" "${_settings_file}"
        else
            rm -f "${_tmp}"
            print_warning "Failed to update Pi settings at ${_settings_file}."
            return 1
        fi
    fi
}

# Install/update tintinweb Pi subagents extension
setup_pi_subagents() {
    local _package="npm:@tintinweb/pi-subagents"
    local _output=""

    if [[ "${BAN_PI_SUBAGENTS:-}" == "1" ]]; then
        if update_pi_subagents_settings remove; then
            print_success "Pi subagents extension disabled in Pi settings."
        fi
        return 0
    fi

    if ! command -v npm &> /dev/null; then
        print_warning "npm not found. Cannot install Pi subagents."
        print_debug "Install Node.js/npm, then run: pi install npm:@tintinweb/pi-subagents"
        return 0
    fi

    if ! command -v pi &> /dev/null; then
        print_warning "Pi coding agent not found. Cannot install Pi subagents."
        return 0
    fi

    if ! update_pi_subagents_settings install; then
        return 0
    fi

    print_message "Installing/updating tintinweb Pi subagents..."
    if _output=$(pi install "${_package}" 2>&1); then
        if _output=$(pi list 2>&1) && grep -q "npm:@tintinweb/pi-subagents" <<< "${_output}" && ! grep -q "npm:pi-subagents" <<< "${_output}"; then
            print_success "tintinweb Pi subagents installed/updated."
        else
            print_warning "Pi subagents install completed, but package validation was inconclusive: ${_output}"
        fi
    else
        print_warning "Failed to install tintinweb Pi subagents: ${_output}"
    fi
}

# Remove Pi MCP adapter package source from settings when disabled
remove_pi_mcp_adapter_settings() {
    local _settings_dir="${PI_CODING_AGENT_DIR:-${HOME}/.pi/agent}"
    local _settings_file="${_settings_dir}/settings.json"
    local _tmp=""

    if ! command -v jq &> /dev/null; then
        print_warning "jq not found. Cannot update Pi MCP adapter settings."
        return 1
    fi

    mkdir -p "${_settings_dir}"

    if [[ ! -f "${_settings_file}" ]]; then
        printf '{}
' > "${_settings_file}"
    fi

    _tmp=$(mktemp)
    if jq '
        def package_source:
            if type == "string" then .
            elif type == "object" then (.source // "")
            else ""
            end;
        def packages_array:
            if (.packages | type) == "array" then .packages else [] end;
        .packages = (packages_array | map(select(package_source != "npm:pi-mcp-adapter")))
        | if (.packages | length) == 0 then del(.packages) else . end
    ' "${_settings_file}" > "${_tmp}"; then
        mv "${_tmp}" "${_settings_file}"
    else
        rm -f "${_tmp}"
        print_warning "Failed to update Pi settings at ${_settings_file}."
        return 1
    fi
}

# Install/update Pi MCP adapter extension
setup_pi_mcp_adapter() {
    local _package="npm:pi-mcp-adapter"
    local _output=""
    local _list_output=""

    if [[ "${BAN_PI_MCP_ADAPTER:-}" == "1" ]]; then
        if remove_pi_mcp_adapter_settings; then
            print_success "Pi MCP adapter extension disabled in Pi settings."
        fi
        return 0
    fi

    if ! command -v npm &> /dev/null; then
        print_warning "npm not found. Cannot install Pi MCP adapter."
        print_debug "Install Node.js/npm, then run: pi install npm:pi-mcp-adapter"
        return 0
    fi

    if ! command -v pi &> /dev/null; then
        print_warning "Pi coding agent not found. Cannot install Pi MCP adapter."
        return 0
    fi

    print_message "Installing/updating Pi MCP adapter..."
    if _output=$(pi install "${_package}" 2>&1); then
        if _list_output=$(pi list 2>&1) && grep -q "npm:pi-mcp-adapter" <<< "${_list_output}"; then
            print_success "Pi MCP adapter installed/updated."
        else
            print_warning "Pi MCP adapter install completed, but package validation was inconclusive: ${_list_output}"
        fi
    else
        print_warning "Failed to install Pi MCP adapter: ${_output}"
    fi
}

# Install/update Pi Claude bridge extension
setup_pi_claude_bridge() {
    local _package="npm:pi-claude-bridge"
    local _output=""
    local _list_output=""

    if ! command -v npm &> /dev/null; then
        print_warning "npm not found. Cannot install Pi Claude bridge."
        print_debug "Install Node.js/npm, then run: pi install npm:pi-claude-bridge"
        return 0
    fi

    if ! command -v pi &> /dev/null; then
        print_warning "Pi coding agent not found. Cannot install Pi Claude bridge."
        return 0
    fi

    print_message "Installing/updating Pi Claude bridge..."
    if _output=$(pi install "${_package}" 2>&1); then
        if _list_output=$(pi list 2>&1) && grep -q "npm:pi-claude-bridge" <<< "${_list_output}"; then
            print_success "Pi Claude bridge installed/updated."
        else
            print_warning "Pi Claude bridge install completed, but package validation was inconclusive: ${_list_output}"
        fi
    else
        print_warning "Failed to install Pi Claude bridge: ${_output}"
    fi
}

# Remove Pi goal/autoresearch package sources from settings when disabled
remove_pi_goal_autoresearch_settings() {
    local _settings_dir="${PI_CODING_AGENT_DIR:-${HOME}/.pi/agent}"
    local _settings_file="${_settings_dir}/settings.json"
    local _tmp=""

    if ! command -v jq &> /dev/null; then
        print_warning "jq not found. Cannot update Pi goal/autoresearch settings."
        return 1
    fi

    mkdir -p "${_settings_dir}"

    if [[ ! -f "${_settings_file}" ]]; then
        printf '{}\n' > "${_settings_file}"
    fi

    _tmp=$(mktemp)
    if jq '
        def package_source:
            if type == "string" then .
            elif type == "object" then (.source // "")
            else ""
            end;
        def packages_array:
            if (.packages | type) == "array" then .packages else [] end;
        .packages = (packages_array | map(select((package_source != "npm:pi-goal") and (package_source != "npm:pi-autoresearch"))))
        | if (.packages | length) == 0 then del(.packages) else . end
    ' "${_settings_file}" > "${_tmp}"; then
        mv "${_tmp}" "${_settings_file}"
    else
        rm -f "${_tmp}"
        print_warning "Failed to update Pi settings at ${_settings_file}."
        return 1
    fi
}

# Install/update Pi goal and autoresearch extensions
setup_pi_goal_autoresearch() {
    local _package=""
    local _output=""
    local _list_output=""
    local _had_failure=0

    if [[ "${BAN_PI_GOAL_AUTORESEARCH:-}" == "1" ]]; then
        if remove_pi_goal_autoresearch_settings; then
            print_success "Pi goal/autoresearch extensions disabled in Pi settings."
        fi
        return 0
    fi

    if ! command -v pi &> /dev/null; then
        print_warning "Pi coding agent not found. Cannot install Pi goal/autoresearch extensions."
        return 0
    fi

    for _package in npm:pi-goal npm:pi-autoresearch; do
        print_message "Installing/updating ${_package}..."
        if _output=$(pi install "${_package}" 2>&1); then
            print_success "${_package} installed/updated."
        else
            _had_failure=1
            print_warning "Failed to install ${_package}: ${_output}"
        fi
    done

    if _list_output=$(pi list 2>&1) && grep -q "npm:pi-goal" <<< "${_list_output}" && grep -q "npm:pi-autoresearch" <<< "${_list_output}"; then
        print_success "Pi goal/autoresearch extensions are active."
    elif [[ "${_had_failure}" -eq 0 ]]; then
        print_warning "Pi goal/autoresearch install completed, but package validation was inconclusive: ${_list_output}"
    fi
}


# Matt Pocock skills to install for Pi.
matt_pocock_pi_skills() {
    printf '%s\n' \
        setup-matt-pocock-skills \
        diagnose \
        tdd \
        improve-codebase-architecture \
        zoom-out \
        grill-with-docs
}

matt_pocock_pi_skills_disabled() {
    [[ "${WORK_MACHINE:-}" == "1" || "${BAN_MATT_POCOCK_SKILLS:-}" == "1" || "${BAN_MATT_POCKOCK_SKILLS:-}" == "1" ]]
}

# Remove Matt Pocock skill copies from Pi when disabled.
remove_matt_pocock_pi_skills() {
    local _default_agent_dir="${HOME}/.pi/agent"
    local _active_agent_dir="${PI_CODING_AGENT_DIR:-${_default_agent_dir}}"
    local _skills_dir=""
    local _skill=""
    local _skill_path=""
    local _removed=0
    local _failed=()
    local _skills_dirs=("${_default_agent_dir}/skills")

    if [[ "${_active_agent_dir}" != "${_default_agent_dir}" ]]; then
        _skills_dirs+=("${_active_agent_dir}/skills")
    fi

    for _skills_dir in "${_skills_dirs[@]}"; do
        while IFS= read -r _skill; do
            _skill_path="${_skills_dir}/${_skill}"
            if [[ -e "${_skill_path}" ]]; then
                if rm -rf -- "${_skill_path:?}" && [[ ! -e "${_skill_path}" ]]; then
                    _removed=1
                else
                    _failed+=("${_skill}")
                fi
            fi
        done < <(matt_pocock_pi_skills || true)
    done

    if [[ "${#_failed[@]}" -gt 0 ]]; then
        print_warning "Failed to remove Matt Pocock Pi skills: ${_failed[*]}"
        return 1
    elif [[ "${_removed}" -eq 1 ]]; then
        print_success "Matt Pocock Pi skills disabled."
    else
        print_debug "Matt Pocock Pi skills disabled; no installed copies found."
    fi
}

# Install/update Matt Pocock engineering skills for Pi.
setup_matt_pocock_pi_skills() {
    local _repo="mattpocock/skills"
    local _default_agent_dir="${HOME}/.pi/agent"
    local _agent_dir="${PI_CODING_AGENT_DIR:-${_default_agent_dir}}"
    local _default_skills_dir="${_default_agent_dir}/skills"
    local _skills_dir="${_agent_dir}/skills"
    local _skill=""
    local _output=""
    local _source_path=""
    local _dest_path=""
    local _args=(--yes skills@latest add "${_repo}" --global --agent pi --copy -y)
    local _missing=()
    local _sync_failed=()

    if matt_pocock_pi_skills_disabled; then
        if [[ "${WORK_MACHINE:-}" == "1" ]]; then
            print_debug "WORK_MACHINE=1, skipping Matt Pocock Pi skills."
        fi
        remove_matt_pocock_pi_skills
        return 0
    fi

    if ! command -v pi &> /dev/null; then
        print_warning "Pi coding agent not found. Cannot install Matt Pocock Pi skills."
        return 0
    fi

    if ! ensure_pi_node_runtime; then
        print_warning "Skipping Matt Pocock Pi skills because the Pi Node.js runtime is not ready."
        return 0
    fi

    if ! command -v npx &> /dev/null; then
        print_warning "npx not found. Cannot install Matt Pocock Pi skills."
        print_debug "Install Node.js >=20.6, then run: npx --yes skills@latest add mattpocock/skills --global --agent pi --copy"
        return 0
    fi

    while IFS= read -r _skill; do
        _args+=(--skill "${_skill}")
    done < <(matt_pocock_pi_skills || true)

    print_message "Installing/updating Matt Pocock Pi skills..."
    if _output=$(npx "${_args[@]}" 2>&1); then
        if [[ "${_agent_dir}" != "${_default_agent_dir}" ]]; then
            mkdir -p "${_skills_dir}"
            while IFS= read -r _skill; do
                _source_path="${_default_skills_dir}/${_skill}"
                _dest_path="${_skills_dir}/${_skill}"
                if [[ -d "${_source_path}" ]]; then
                    if rm -rf -- "${_dest_path:?}" && cp -a "${_source_path}" "${_dest_path}"; then
                        true
                    else
                        _sync_failed+=("${_skill}")
                    fi
                else
                    _sync_failed+=("${_skill}")
                fi
            done < <(matt_pocock_pi_skills || true)
        fi

        while IFS= read -r _skill; do
            if [[ ! -f "${_skills_dir}/${_skill}/SKILL.md" ]]; then
                _missing+=("${_skill}")
            fi
        done < <(matt_pocock_pi_skills || true)

        if [[ "${#_sync_failed[@]}" -gt 0 ]]; then
            print_warning "Matt Pocock Pi skills installed, but failed to sync to active Pi dir ${_agent_dir}: ${_sync_failed[*]}"
        elif [[ "${#_missing[@]}" -eq 0 ]]; then
            print_success "Matt Pocock Pi skills installed/updated."
        else
            print_warning "Matt Pocock Pi skills install completed, but missing expected skills: ${_missing[*]}"
        fi
    else
        print_warning "Failed to install Matt Pocock Pi skills: ${_output}"
    fi
}


# Remove legacy Compound Engineering resources without affecting unrelated agent tooling.
compound_path_is_within() {
    local _path="$1"
    local _root="$2"
    local _canonical_path=""
    local _canonical_root=""

    _canonical_root=$(cd -P "${_root}" 2>/dev/null && pwd -P) || return 1
    _canonical_path=$(cd -P "${_path}" 2>/dev/null && pwd -P) || return 1
    case "${_canonical_path}" in
        "${_canonical_root}"/*) return 0 ;;
        *) return 1 ;;
    esac
}

compound_link_target_is_within() {
    local _link_path="$1"
    local _root_path="$2"
    local _link_target=""

    [[ -L "${_link_path}" ]] || return 1
    _link_target=$(readlink "${_link_path}") || return 1
    case "${_link_target}" in
        /*) ;;
        *) _link_target="$(dirname "${_link_path}")/${_link_target}" ;;
    esac

    if compound_path_is_within "${_link_target}" "${_root_path}"; then
        return 0
    fi

    # Legacy installer links use an absolute target. This lexical check also
    # removes a dangling link after a previous partial cleanup, while keeping
    # the trailing slash boundary from matching sibling directories. Do not
    # trust an unresolved target with traversal segments.
    case "${_link_target}" in
        */../*|*/..) return 1 ;;
        "${_root_path}"/*) return 0 ;;
        *) return 1 ;;
    esac
}

compound_pi_skill_names() {
    printf '%s
' \
        ce-agent-native-architecture \
        ce-agent-native-audit \
        ce-brainstorm \
        ce-clean-gone-branches \
        ce-code-review \
        ce-commit \
        ce-commit-push-pr \
        ce-compound \
        ce-compound-refresh \
        ce-debug \
        ce-demo-reel \
        ce-dhh-rails-style \
        ce-doc-review \
        ce-frontend-design \
        ce-gemini-imagegen \
        ce-ideate \
        ce-optimize \
        ce-plan \
        ce-polish-beta \
        ce-product-pulse \
        ce-proof \
        ce-release-notes \
        ce-report-bug \
        ce-resolve-pr-feedback \
        ce-riffrec-feedback-analysis \
        ce-sessions \
        ce-setup \
        ce-simplify-code \
        ce-slack-research \
        ce-strategy \
        ce-test-browser \
        ce-test-xcode \
        ce-work \
        ce-work-beta \
        ce-worktree
}

compound_pi_agent_names() {
    printf '%s
' \
        ce-adversarial-document-reviewer \
        ce-adversarial-reviewer \
        ce-agent-native-reviewer \
        ce-ankane-readme-writer \
        ce-api-contract-reviewer \
        ce-architecture-strategist \
        ce-best-practices-researcher \
        ce-code-simplicity-reviewer \
        ce-coherence-reviewer \
        ce-correctness-reviewer \
        ce-data-integrity-guardian \
        ce-data-migration-expert \
        ce-data-migrations-reviewer \
        ce-deployment-verification-agent \
        ce-design-implementation-reviewer \
        ce-design-iterator \
        ce-design-lens-reviewer \
        ce-dhh-rails-reviewer \
        ce-feasibility-reviewer \
        ce-figma-design-sync \
        ce-framework-docs-researcher \
        ce-git-history-analyzer \
        ce-issue-intelligence-analyst \
        ce-julik-frontend-races-reviewer \
        ce-kieran-python-reviewer \
        ce-kieran-rails-reviewer \
        ce-kieran-typescript-reviewer \
        ce-learnings-researcher \
        ce-maintainability-reviewer \
        ce-pattern-recognition-specialist \
        ce-performance-oracle \
        ce-performance-reviewer \
        ce-pr-comment-resolver \
        ce-previous-comments-reviewer \
        ce-product-lens-reviewer \
        ce-project-standards-reviewer \
        ce-reliability-reviewer \
        ce-repo-research-analyst \
        ce-schema-drift-detector \
        ce-scope-guardian-reviewer \
        ce-security-lens-reviewer \
        ce-security-reviewer \
        ce-security-sentinel \
        ce-session-historian \
        ce-slack-researcher \
        ce-spec-flow-analyzer \
        ce-swift-ios-reviewer \
        ce-testing-reviewer \
        ce-web-researcher
}

remove_pi_compound_settings() {
    local _agent_dir="$1"
    local _settings_file="${_agent_dir}/settings.json"
    local _tmp=""

    [[ -f "${_settings_file}" && ! -L "${_settings_file}" ]] || return 1

    if ! command -v jq &> /dev/null; then
        print_warning "jq not found. Cannot remove Compound Engineering entries from Pi settings at ${_settings_file}."
        return 1
    fi

    if ! jq -e '
        def package_source:
            if type == "string" then .
            elif type == "object" then (.source // "")
            else ""
            end;
        def compound_source:
            package_source | ascii_downcase as $source |
            ($source == "npm:@every-env/compound-plugin"
                or $source == "npm:@every-env/compound-engineering-plugin"
                or $source == "https://github.com/everyinc/compound-engineering-plugin.git");
        (.packages | type) == "array" and any(.packages[]; compound_source)
    ' "${_settings_file}" > /dev/null; then
        return 1
    fi

    if ! _tmp=$(mktemp); then
        print_warning "Could not create a temporary file for Pi settings cleanup at ${_settings_file}."
        return 1
    fi

    if jq '
        def package_source:
            if type == "string" then .
            elif type == "object" then (.source // "")
            else ""
            end;
        def compound_source:
            package_source | ascii_downcase as $source |
            ($source == "npm:@every-env/compound-plugin"
                or $source == "npm:@every-env/compound-engineering-plugin"
                or $source == "https://github.com/everyinc/compound-engineering-plugin.git");
        .packages = (.packages | map(select(compound_source | not)))
        | if (.packages | length) == 0 then del(.packages) else . end
    ' "${_settings_file}" > "${_tmp}"; then
        if mv "${_tmp}" "${_settings_file}"; then
            return 0
        fi
        rm -f "${_tmp}"
        print_warning "Failed to replace Pi settings after Compound Engineering cleanup at ${_settings_file}."
    else
        rm -f "${_tmp}"
        print_warning "Failed to parse Pi settings at ${_settings_file}; leaving it unchanged."
    fi

    return 1
}

remove_compound_engineering_resources() {
    local _default_agent_dir="${HOME}/.pi/agent"
    local _active_agent_dir="${PI_CODING_AGENT_DIR:-${_default_agent_dir}}"
    local _compound_repo="${HOME}/.local/share/compound-engineering-plugin"
    local _skills_dir="${HOME}/.agents/skills"
    local _agent_dir=""
    local _resource_dir=""
    local _resource_path=""
    local _resource_name=""
    local _extension_path=""
    local _agents_path=""
    local _tmp=""
    local _begin_marker="<!-- BEGIN COMPOUND PI TOOL MAP -->"
    local _end_marker="<!-- END COMPOUND PI TOOL MAP -->"
    local _begin_count=0
    local _end_count=0
    local _removed=0
    local _failed=()
    local _agent_dirs=()

    if [[ -d "${_default_agent_dir}" ]]; then
        if compound_path_is_within "${_default_agent_dir}" "${HOME}"; then
            _agent_dirs+=("${_default_agent_dir}")
        else
            print_warning "Skipping Pi cleanup outside ${HOME}: ${_default_agent_dir}"
        fi
    fi

    if [[ "${_active_agent_dir}" != "${_default_agent_dir}" && -d "${_active_agent_dir}" ]]; then
        if compound_path_is_within "${_active_agent_dir}" "${HOME}"; then
            _agent_dirs+=("${_active_agent_dir}")
        else
            print_warning "Skipping Pi cleanup outside ${HOME}: ${_active_agent_dir}"
        fi
    fi

    if [[ -d "${_skills_dir}" ]] && compound_path_is_within "${_skills_dir}" "${HOME}"; then
        for _resource_path in "${_skills_dir}"/*; do
            [[ -L "${_resource_path}" ]] || continue
            if compound_link_target_is_within "${_resource_path}" "${_compound_repo}"; then
                if rm -f -- "${_resource_path}" && [[ ! -e "${_resource_path}" && ! -L "${_resource_path}" ]]; then
                    _removed=1
                else
                    _failed+=("${_resource_path}")
                fi
            fi
        done
    fi

    for _agent_dir in "${_agent_dirs[@]}"; do
        if remove_pi_compound_settings "${_agent_dir}"; then
            _removed=1
        fi

        _resource_dir="${_agent_dir}/extensions"
        if [[ -d "${_resource_dir}" ]] && compound_path_is_within "${_resource_dir}" "${HOME}"; then
            for _extension_path in "${_resource_dir}"/compound-engineering*; do
                [[ -e "${_extension_path}" || -L "${_extension_path}" ]] || continue
                if rm -rf -- "${_extension_path}" && [[ ! -e "${_extension_path}" && ! -L "${_extension_path}" ]]; then
                    _removed=1
                else
                    _failed+=("${_extension_path}")
                fi
            done
        fi

        _resource_dir="${_agent_dir}/skills"
        if [[ -d "${_resource_dir}" ]] && compound_path_is_within "${_resource_dir}" "${HOME}"; then
            while IFS= read -r _resource_name; do
                _resource_path="${_resource_dir}/${_resource_name}"
                [[ -d "${_resource_path}" || -L "${_resource_path}" ]] || continue
                if rm -rf -- "${_resource_path}" && [[ ! -e "${_resource_path}" && ! -L "${_resource_path}" ]]; then
                    _removed=1
                else
                    _failed+=("${_resource_path}")
                fi
            done < <(compound_pi_skill_names || true)
        fi

        _resource_dir="${_agent_dir}/agents"
        if [[ -d "${_resource_dir}" ]] && compound_path_is_within "${_resource_dir}" "${HOME}"; then
            while IFS= read -r _resource_name; do
                for _resource_path in "${_resource_dir}/${_resource_name}" "${_resource_dir}/${_resource_name}.md"; do
                    [[ -e "${_resource_path}" || -L "${_resource_path}" ]] || continue
                    if [[ -d "${_resource_path}" || -L "${_resource_path}" ]]; then
                        rm -rf -- "${_resource_path}"
                    else
                        rm -f -- "${_resource_path}"
                    fi
                    if [[ ! -e "${_resource_path}" && ! -L "${_resource_path}" ]]; then
                        _removed=1
                    else
                        _failed+=("${_resource_path}")
                    fi
                done
            done < <(compound_pi_agent_names || true)
        fi

        _agents_path="${_agent_dir}/AGENTS.md"
        if [[ -f "${_agents_path}" && ! -L "${_agents_path}" ]]; then
            _begin_count=$(grep -Fxc "${_begin_marker}" "${_agents_path}" || true)
            _end_count=$(grep -Fxc "${_end_marker}" "${_agents_path}" || true)
            if [[ "${_begin_count}" -eq 1 && "${_end_count}" -eq 1 ]]; then
                if ! _tmp=$(mktemp "${_agents_path}.XXXXXX"); then
                    print_warning "Could not create a temporary file to remove the Compound Engineering block from ${_agents_path}."
                elif awk -v begin="${_begin_marker}" -v end="${_end_marker}" '
                    $0 == begin { in_block = 1; next }
                    $0 == end && in_block { in_block = 0; next }
                    !in_block { print }
                    END { exit in_block ? 1 : 0 }
                ' "${_agents_path}" > "${_tmp}" && mv "${_tmp}" "${_agents_path}"; then
                    _removed=1
                else
                    rm -f "${_tmp}"
                    print_warning "Failed to safely remove the Compound Engineering block from ${_agents_path}."
                fi
            elif [[ "${_begin_count}" -ne 0 || "${_end_count}" -ne 0 ]]; then
                print_warning "Compound Engineering markers are malformed in ${_agents_path}; leaving it unchanged."
            fi
        elif [[ -L "${_agents_path}" ]]; then
            print_warning "Skipping Compound Engineering block cleanup in symlinked ${_agents_path}."
        fi
    done

    if [[ -L "${_compound_repo}" ]]; then
        if rm -f -- "${_compound_repo}" && [[ ! -e "${_compound_repo}" && ! -L "${_compound_repo}" ]]; then
            _removed=1
        else
            _failed+=("${_compound_repo}")
        fi
    elif [[ -d "${_compound_repo}" ]] && compound_path_is_within "${_compound_repo}" "${HOME}"; then
        if rm -rf -- "${_compound_repo}" && [[ ! -e "${_compound_repo}" && ! -L "${_compound_repo}" ]]; then
            _removed=1
        else
            _failed+=("${_compound_repo}")
        fi
    fi

    if [[ "${#_failed[@]}" -gt 0 ]]; then
        print_warning "Failed to remove legacy Compound Engineering resources: ${_failed[*]}"
    elif [[ "${_removed}" -eq 1 ]]; then
        print_success "Legacy Compound Engineering resources removed."
    else
        print_debug "No legacy Compound Engineering resources found."
    fi

    return 0
}

# Enable loginctl lingering so systemd user services survive logout
enable_user_lingering() {
    if { loginctl show-user "$(whoami || true)" --property=Linger 2>/dev/null || true; } | grep -q 'Linger=yes'; then
        print_debug "User lingering already enabled."
        return
    fi

    print_message "Enabling user lingering for systemd user services..."

    if can_sudo; then
        if sudo loginctl enable-linger "$(whoami || true)"; then
            print_success "User lingering enabled — systemd user services will survive logout."
        else
            print_warning "Could not enable user lingering."
        fi
    else
        print_warning "No sudo access — cannot enable user lingering."
        print_debug "Run 'sudo loginctl enable-linger $(whoami || true)' manually."
    fi
}

# Install Homebrew (linuxbrew) on Linux
install_homebrew() {
    if command -v brew &> /dev/null; then
        print_debug "Homebrew is already installed."
    elif [[ -x "/home/linuxbrew/.linuxbrew/bin/brew" ]]; then
        print_debug "Homebrew found but not in PATH, adding..."
    else
        print_message "Installing Homebrew (linuxbrew)..."
        if can_sudo; then
            sudo mkdir -p /home/linuxbrew
            sudo chown -R "$(whoami || true)" /home/linuxbrew
        fi
        local install_script
        install_script=$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh || true)
        NONINTERACTIVE=1 /bin/bash -c "${install_script}" > /dev/null
        print_success "Homebrew installed."
    fi
    # Ensure brew is in PATH for this session
    if [[ -x "/home/linuxbrew/.linuxbrew/bin/brew" ]]; then
        local brew_shellenv
        brew_shellenv=$(/home/linuxbrew/.linuxbrew/bin/brew shellenv || true)
        eval "${brew_shellenv}"
    fi

    # Fix ownership if Cellar is not writable by current user (multi-user installs)
    local brew_prefix
    brew_prefix="$(brew --prefix 2>/dev/null)"
    if [[ -n "${brew_prefix}" ]] && [[ -d "${brew_prefix}/Cellar" ]] && [[ ! -w "${brew_prefix}/Cellar" ]]; then
        if can_sudo; then
            print_message "Fixing Homebrew permissions for $(whoami || true)..."
            sudo chown -R "$(whoami || true)" "${brew_prefix}/Cellar" "${brew_prefix}/Homebrew" "${brew_prefix}/lib" "${brew_prefix}/bin" "${brew_prefix}/share" "${brew_prefix}/etc" "${brew_prefix}/opt" "${brew_prefix}/var" 2>/dev/null
            print_success "Homebrew permissions fixed."
        else
            print_warning "Homebrew Cellar is not writable by $(whoami || true). Brew installs may fail."
            print_debug "An admin can fix this: sudo chown -R $(whoami || true) ${brew_prefix}/Cellar"
        fi
    fi
}

# Install packages via Homebrew
install_brew_packages() {
    if ! command -v brew &> /dev/null; then
        print_warning "Homebrew not available. Skipping brew packages."
        return 0
    fi

    local packages=("ffmpeg" "kubernetes-cli")
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


# Install OpenTofu (open-source Terraform fork)
install_opentofu() {
    if command -v tofu &> /dev/null; then
        print_debug "OpenTofu is already installed."
        return
    fi

    print_message "Installing OpenTofu..."
    curl --proto '=https' --tlsv1.2 -fsSL https://get.opentofu.org/install-opentofu.sh -o /tmp/install-opentofu.sh
    chmod +x /tmp/install-opentofu.sh
    if /tmp/install-opentofu.sh --install-method deb; then
        rm -f /tmp/install-opentofu.sh
        print_success "OpenTofu installed."
    else
        rm -f /tmp/install-opentofu.sh
        print_error "Failed to install OpenTofu."
    fi
}

# Install cloudflared (Cloudflare Tunnel client)
install_cloudflared() {
    if ! can_sudo; then
        print_warning "No sudo access - cannot install cloudflared."
        return
    fi

    # Always refresh the GPG key and repo config to prevent stale keys from
    # breaking apt-get update for other packages (e.g. Tailscale)
    sudo mkdir -p --mode=0755 /usr/share/keyrings
    { curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg || true; } | sudo tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
    echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main' | sudo tee /etc/apt/sources.list.d/cloudflared.list >/dev/null

    if command -v cloudflared &> /dev/null; then
        print_debug "cloudflared is already installed (GPG key refreshed)."
        return
    fi

    print_message "Installing cloudflared..."
    sudo apt-get update -qq
    if sudo apt-get install -y cloudflared; then
        print_success "cloudflared installed."
    else
        print_error "Failed to install cloudflared."
        return 1
    fi
}

# Install Turso CLI (libSQL database platform)
install_turso() {
    if command -v turso &> /dev/null; then
        print_debug "Turso CLI is already installed."
        return
    fi

    print_message "Installing Turso CLI..."
    local turso_install
    turso_install=$(curl -sSfL https://get.tur.so/install.sh)
    if bash <<< "${turso_install}"; then
        # Add turso to PATH for current session
        export PATH="${HOME}/.turso:${PATH}"
        print_success "Turso CLI installed."
    else
        print_error "Failed to install Turso CLI."
    fi
}

# Install lefthook (git hooks manager)
install_lefthook() {
    if command -v lefthook &> /dev/null; then
        print_debug "lefthook is already installed."
        return
    fi

    print_message "Installing lefthook..."
    if ! go install github.com/evilmartians/lefthook@latest; then
        print_error "Failed to install lefthook."
        return 1
    fi
    print_success "lefthook installed."
}

# Install act for running GitHub Actions locally
install_act() {
    if ! command -v act &> /dev/null; then
        print_message "Installing act (GitHub Actions runner)..."
        # Use the official install script, installing to /usr/local/bin to avoid
        # creating ~/bin owned by root (the installer defaults to ./bin under sudo)
        local act_install
        act_install=$(curl -s https://raw.githubusercontent.com/nektos/act/master/install.sh)
        if ! echo "${act_install}" | sudo bash -s -- -b /usr/local/bin; then
            print_error "Failed to install act."
            return 1
        fi
        # Clean up stale ~/bin/act from previous installs
        if [[ -f "${HOME}/bin/act" ]]; then
            sudo rm -f "${HOME}/bin/act"
            rmdir "${HOME}/bin" 2>/dev/null || true
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
    local uv_install
    uv_install=$(curl -LsSf https://astral.sh/uv/install.sh)
    if sh <<< "${uv_install}"; then
        print_success "uv installed."
    else
        print_error "Failed to install uv."
    fi
}

# Upgrade global npm packages
upgrade_npm_global_packages() {
    # Initialize mise for current session (provides npm if Node.js is installed)
    if command -v mise &> /dev/null; then
        local mise_activation
        mise_activation=$(mise activate bash || true)
        eval "${mise_activation}"
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
    # Log this run (before banner so version appears in logs)
    local log_dir="${HOME}/.local/log/machine-setup"
    mkdir -p "${log_dir}"
    local log_file
    log_file="${log_dir}/$(date +%Y-%m-%d-%H%M%S).log"
    exec 3>&1
    exec > >({ tee -a "${log_file}" || true; }) 2>&1
    print_debug "Logging to ${log_file}"

    echo -e "\n${BOLD}🍓 Raspberry Pi Development Environment Setup${NC}"
    echo -e "${GRAY}Version 164 | Last changed: Validate Paseo against Bun command identity${NC}"

    if ! acquire_setup_lock; then
        echo -e "${GRAY}Run log saved to: ${log_file}${NC}"
        upload_log
        return 1
    fi

    # Create placeholder env file early
    create_env_local

    # Source env vars early so optional setup flags are available
    if [[ -f "${HOME}/.env.local" ]]; then
        set -a
        # shellcheck source=/dev/null
        source "${HOME}/.env.local"
        set +a
    fi

    paseo_headless_platform_gate || return 1

    print_section "User & System Setup"
    ensure_not_root
    check_raspberry_pi
    setup_swap
    setup_dns64_for_ipv6_only

    print_section "System Updates"
    update_dependencies
    update_and_install_core

    print_section "Development Tools"
    install_homebrew
    install_brew_packages
    install_1password_cli
    install_secrets_manager
    install_gcloud_cli
    install_lefthook
    install_mise
    install_uv
    install_opentofu
    install_cloudflared
    install_turso

    print_section "Network & SSH"
    enable_ssh_server
    install_tailscale
    install_fail2ban
    setup_unattended_upgrades
    add_github_to_known_hosts || return 1
    ensure_ssh_agent || return 1

    current_user=$(whoami || true)
    if [[ "${current_user}" == "scowalt" ]]; then
        print_section "Code Directory Setup"
        setup_code_directory
    fi

    print_section "Additional Development Tools"
    install_bun
    install_sfw
    install_claude_code
    install_gemini_cli
    install_codex_cli
    install_portless_cli
    install_ntn_cli
    install_rtk_cli

    print_section "Terminal & Shell"
    install_starship

    print_section "Shared Directories"
    print_section "Dotfiles Management"

    # Check if we have access (via SSH or deploy key)
    # If not, try interactive deploy key setup
    if check_dotfiles_access || setup_dotfiles_deploy_key; then
        # We have access, proceed with chezmoi setup
        install_chezmoi
        initialize_chezmoi
        # chezmoi init --apply overwrites ~/.ssh/config, removing the
        # github-dotfiles host alias needed for deploy key access.
        # Re-bootstrap it before any further chezmoi network operations.
        bootstrap_ssh_config
        configure_chezmoi_git
        fix_chezmoi_remote_for_deploy_key
        update_chezmoi
        apply_chezmoi_config
    else
        print_warning "Skipping dotfiles management - no access to repository."
    fi

    setup_rtk_integrations

    print_section "Pi Extensions"
    if matt_pocock_pi_skills_disabled; then
        setup_matt_pocock_pi_skills
    fi
    if install_pi_cli; then
        setup_pi_subagents
        setup_pi_mcp_adapter
        setup_pi_claude_bridge
        setup_pi_goal_autoresearch
        if ! matt_pocock_pi_skills_disabled; then
            setup_matt_pocock_pi_skills
        fi
    else
        if [[ "${BAN_PI_SUBAGENTS:-}" == "1" ]]; then
            setup_pi_subagents
        fi
        if [[ "${BAN_PI_MCP_ADAPTER:-}" == "1" ]]; then
            setup_pi_mcp_adapter
        fi
        if [[ "${BAN_PI_GOAL_AUTORESEARCH:-}" == "1" ]]; then
            setup_pi_goal_autoresearch
        fi
        print_warning "Skipping Pi extension setup because Pi migration failed."
    fi

    remove_compound_engineering_resources

    print_section "Shell Configuration"
    set_fish_as_default_shell
    install_act
    install_tmux_plugins
    enable_user_lingering
    setup_headless_paseo_daemon || return 1
    install_iterm2_shell_integration

    print_section "Final Updates"
    upgrade_npm_global_packages

    echo -e "${GRAY}Run log saved to: ${log_file}${NC}"
    printf '\n%s%s✨ Setup complete! Please log out and log back in for all changes to take effect.%s\n\n' "${GREEN}" "${BOLD}" "${NC}" | tee -a "${log_file}" >&3
    upload_log
}

main "$@"
