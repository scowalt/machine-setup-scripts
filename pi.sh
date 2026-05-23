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
# WORK_MACHINE=1
# BAN_COMPOUND_PLUGIN=1
# BAN_PI_SUBAGENTS=1
# BAN_PI_GOAL_AUTORESEARCH=1
# BAN_MATT_POCOCK_SKILLS=1
# BAN_RTK=1
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

    # Hold tmux during upgrades to prevent killing existing sessions (ccgram, etc.)
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
    local packages=("git" "curl" "jq" "fish" "tmux" "fonts-firacode" "gh" "build-essential" "libssl-dev" "zlib1g-dev" "libbz2-dev" "libreadline-dev" "libsqlite3-dev" "wget" "unzip" "llvm" "libncurses5-dev" "libncursesw5-dev" "xz-utils" "tk-dev" "libffi-dev" "liblzma-dev" "golang-go" "inotify-tools" "shellcheck" "gitleaks" "poppler-utils" "bubblewrap")
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
    print_message "Updating Google Cloud CLI components..."
    if update_output=$(gcloud components update --quiet < /dev/null 2>&1); then
        print_success "Google Cloud CLI components updated."
    elif grep -qiE "component manager is disabled|managed by an external package manager" <<< "${update_output}"; then
        print_debug "Google Cloud CLI components are managed by the package manager; skipping component update."
    else
        print_warning "Failed to update Google Cloud CLI components."
        if [[ -n "${update_output}" ]]; then
            print_debug "${update_output}"
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
    if ! _mise_env=$(mise env -s bash "${_runtime}"); then
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

# Install/update Pi coding agent
install_pi_cli() {
    local _new_package="@earendil-works/pi-coding-agent"
    local _old_package="@mariozechner/pi-coding-agent"
    local _global_packages=""
    local _pi_target=""
    local _needs_reinstall=0

    print_message "Installing/updating Pi coding agent..."

    # Ensure bun is available
    if [[ -d "${HOME}/.bun" ]]; then
        export PATH="${HOME}/.bun/bin:${PATH}"
    fi

    if ! command -v bun &> /dev/null; then
        print_warning "Bun not found. Cannot install Pi coding agent."
        print_debug "Install Bun first, then run: bun install -g ${_new_package}"
        return 1
    fi

    if ! ensure_pi_node_runtime; then
        print_warning "Skipping Pi installation and extension setup because the Pi Node.js runtime is not ready."
        return 1
    fi

    if ! bun install -g "${_new_package}"; then
        print_error "Failed to install Pi coding agent."
        return 1
    fi

    hash -r 2>/dev/null || true

    if { bun pm ls -g 2>/dev/null || true; } | grep -Fq "${_old_package}"; then
        print_message "Removing deprecated Pi package ${_old_package}..."
        if bun remove -g "${_old_package}"; then
            hash -r 2>/dev/null || true
            print_success "Deprecated Pi package removed."
        else
            print_warning "Failed to remove old ${_old_package} package."
        fi
    fi

    _pi_target=$(pi_command_target 2>/dev/null || true)
    if [[ -z "${_pi_target}" ]]; then
        print_warning "Pi command was not found after migration. Reinstalling ${_new_package}."
        _needs_reinstall=1
    elif [[ "${_pi_target}" == *"${_old_package}"* ]]; then
        print_warning "Pi still points to old @mariozechner install path: ${_pi_target}"
        print_message "Reinstalling ${_new_package} to refresh the Pi shim..."
        _needs_reinstall=1
    fi

    if [[ "${_needs_reinstall}" -eq 1 ]]; then
        if bun install -g "${_new_package}"; then
            hash -r 2>/dev/null || true
        else
            print_warning "Failed to reinstall ${_new_package} after cleanup."
        fi
    fi

    _global_packages=$(bun pm ls -g 2>/dev/null || true)
    _pi_target=$(pi_command_target 2>/dev/null || true)

    if ! grep -Fq "${_new_package}" <<< "${_global_packages}"; then
        print_warning "Pi migration incomplete: ${_new_package} is not listed in Bun global packages."
        return 1
    fi

    if grep -Fq "${_old_package}" <<< "${_global_packages}"; then
        print_warning "Pi migration incomplete: deprecated ${_old_package} is still listed in Bun global packages."
        return 1
    fi

    if [[ -z "${_pi_target}" ]]; then
        print_warning "Pi migration incomplete: pi command is not available after installing ${_new_package}."
        return 1
    fi

    if [[ "${_pi_target}" == *"${_old_package}"* ]]; then
        print_warning "Pi migration incomplete: pi still points to old @mariozechner install path after reinstall: ${_pi_target}"
        return 1
    fi

    print_success "Pi coding agent installed/updated."
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

    # Ensure bun is available
    if [[ -d "${HOME}/.bun" ]]; then
        export PATH="${HOME}/.bun/bin:${PATH}"
    fi

    if [[ "${BAN_PI_SUBAGENTS:-}" == "1" ]]; then
        if update_pi_subagents_settings remove; then
            print_success "Pi subagents extension disabled in Pi settings."
        fi
        return 0
    fi

    if ! command -v bun &> /dev/null; then
        print_warning "Bun not found. Cannot install Pi subagents."
        print_debug "Install Bun first, then run: pi install npm:@tintinweb/pi-subagents"
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


# Remove unsupported AskUserQuestion references from Compound Engineering files installed for Pi.
sanitize_pi_compound_engineering_for_pi() {
    local _agent_dir="${1:-${PI_CODING_AGENT_DIR:-${HOME}/.pi/agent}}"
    local _skills_dir="${_agent_dir}/skills"
    # shellcheck disable=SC2016
    local _perl_expr='
s/^[ \t]*-[ \t]*AskUserQuestion\r?\n//mg;
s/`AskUserQuestion` in [^,;.]* with `ToolSearch select:AskUserQuestion` pre-loaded if needed,[ \t]*//g;
s/`AskUserQuestion` in [^,;.]* — call `ToolSearch` with `select:AskUserQuestion`[^;]*;[ \t]*//g;
s/`AskUserQuestion` in [^,;.]* \(call `ToolSearch` with `select:AskUserQuestion`[^)]*\),[ \t]*//g;
s/`AskUserQuestion` in [^,;.]*,[ \t]*//g;
s/`AskUserQuestion` in [^,;.]*[ \t]*//g;
s/[ \t]*\*\*[^*]* only:\*\* if `AskUserQuestion`[^\n.]*\.[ \t]*/ /g;
s/[ \t]*In [^,\n.]*,? call `ToolSearch` with `select:AskUserQuestion`[^\n.]*\.[ \t]*/ /g;
s/[ \t]*In [^,\n.]*,? the tool should already be loaded[^\n.]*`ToolSearch`[^\n.]*\.[ \t]*/ /g;
s/[ \t]*In [^,\n.]* the tool should already be loaded[^\n.]*`ToolSearch`[^\n.]*\.[ \t]*/ /g;
s/[ \t]*In [^\n.]*`select:AskUserQuestion`[^\n.]*\.[ \t]*/ /g;
s/[ \t]*At the start of Interactive-mode work[^\n.]*`select:AskUserQuestion`[^\n.]*\.[ \t]*/ /g;
s/[ \t]*Load it \*\*once[^\n.]*\.[ \t]*/ /g;
s/`ToolSearch` returns no match, the tool call explicitly fails, or/the tool call is unavailable, errors, or/g;
s/Only when `ToolSearch` explicitly returns no match or the tool call errors — or on a platform with no blocking question tool —/Only when no blocking question tool exists or the tool call errors,/g;
s/A pending schema load is not a fallback trigger; call `ToolSearch` first per the pre-load rule\. //g;
s/A pending schema load is not a fallback trigger\. //g;
s/ — not because a schema load is required//g;
s/no `AskUserQuestion` menu/no formal question menu/g;
s/`AskUserQuestion` menu/formal question menu/g;
s/AskUserQuestion/blocking question tool/g;
'

    if [[ ! -d "${_skills_dir}" && ! -f "${_agent_dir}/AGENTS.md" ]]; then
        return 0
    fi

    if ! command -v perl &> /dev/null; then
        print_warning "perl not found. Cannot sanitize Compound Engineering Pi skill files."
        return 0
    fi

    if [[ -d "${_skills_dir}" ]]; then
        find "${_skills_dir}" -type f -name '*.md' -exec perl -0pi -e "${_perl_expr}" {} +
    fi

    if [[ -f "${_agent_dir}/AGENTS.md" ]]; then
        perl -0pi -e "${_perl_expr}" "${_agent_dir}/AGENTS.md"
    fi

    if { [[ -d "${_skills_dir}" ]] && grep -R "AskUserQuestion" "${_skills_dir}" &> /dev/null; } || { [[ -f "${_agent_dir}/AGENTS.md" ]] && grep -q "AskUserQuestion" "${_agent_dir}/AGENTS.md"; }; then
        print_warning "Compound Engineering Pi files still mention AskUserQuestion after sanitizing."
    else
        print_success "Compound Engineering Pi files sanitized for Pi."
    fi
}

# Install Compound Engineering prompts/skills for Pi
setup_pi_compound_engineering() {
    local _helper="${HOME}/.local/bin/setup-pi-compound-engineering"
    if [[ -x "${_helper}" ]]; then
        "${_helper}"
        return 0
    fi

    if [[ "${WORK_MACHINE:-}" == "1" ]]; then
        print_debug "WORK_MACHINE=1, skipping Compound Engineering for Pi."
        return 0
    fi

    if [[ "${BAN_COMPOUND_PLUGIN:-}" == "1" ]]; then
        print_debug "BAN_COMPOUND_PLUGIN=1, skipping Compound Engineering for Pi."
        return 0
    fi

    # Ensure bun is available
    if [[ -d "${HOME}/.bun" ]]; then
        export PATH="${HOME}/.bun/bin:${PATH}"
    fi

    if ! command -v bun &> /dev/null; then
        print_warning "Bun not found. Cannot install Compound Engineering for Pi."
        print_debug "Install Bun first, then run: bunx @every-env/compound-plugin install compound-engineering --to pi"
        return 0
    fi

    if ! command -v bunx &> /dev/null; then
        print_warning "bunx not found. Cannot install Compound Engineering for Pi."
        return 0
    fi

    if ! command -v pi &> /dev/null; then
        print_warning "Pi coding agent not found. Cannot install Compound Engineering for Pi."
        return 0
    fi

    print_message "Installing/updating Compound Engineering for Pi..."
    local _output
    if _output=$(bunx @every-env/compound-plugin install compound-engineering --to pi 2>&1); then
        local _agent_dir="${HOME}/.pi/agent"
        if [[ -f "${_agent_dir}/extensions/compound-engineering-compat.ts" ]] || grep -q "BEGIN COMPOUND PI TOOL MAP" "${_agent_dir}/AGENTS.md" 2>/dev/null; then
            print_success "Compound Engineering installed for Pi."
        else
            print_warning "Compound Engineering Pi install completed, but expected artifacts were not found."
        fi
        sanitize_pi_compound_engineering_for_pi "${_agent_dir}"
    else
        print_warning "Failed to install Compound Engineering for Pi: ${_output}"
    fi
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

# Install/update ccgram (Telegram-to-tmux bridge for AI coding agents)
install_ccgram() {
    if ! command -v uv &> /dev/null; then
        print_warning "uv not found. Cannot install ccgram."
        return
    fi

    local old_version=""
    if command -v ccgram &> /dev/null; then
        old_version=$(ccgram --version 2>/dev/null || echo "")
    fi

    print_message "Installing/updating ccgram..."
    # GIT_SSL_NO_VERIFY: Socket Firewall (sfw) intercepts TLS with its own CA
    # that isn't in the system CA bundle. Since this fetches from our own GitHub
    # repo, disabling SSL verification here is an acceptable tradeoff.
    # UV_NATIVE_TLS: use system TLS instead of uv's bundled OpenSSL
    if GIT_SSL_NO_VERIFY=1 UV_NATIVE_TLS=true uv tool install --force --upgrade --python 3.14 --allow-insecure-host github.com ccgram --from "git+https://github.com/scowalt/ccgram.git@main"; then
        print_success "ccgram installed/updated."
    else
        print_error "Failed to install ccgram."
        return 1
    fi

    # Enable and manage ccgram systemd service
    local service_file="${HOME}/.config/systemd/user/ccgram.service"
    if [[ -f "${service_file}" ]] && systemctl --user daemon-reload 2>/dev/null; then
        if ! systemctl --user is-enabled ccgram.service &>/dev/null; then
            if systemctl --user enable ccgram.service 2>/dev/null; then
                print_success "ccgram service enabled."
            fi
        fi

        local new_version=""
        new_version=$(ccgram --version 2>/dev/null || echo "")

        if [[ -n "${old_version}" && "${old_version}" != "${new_version}" ]]; then
            print_message "ccgram upgraded (${old_version} -> ${new_version}), restarting service..."
            if systemctl --user restart ccgram.service 2>/dev/null; then
                print_success "ccgram service restarted."
            else
                print_warning "Could not restart ccgram service."
            fi
        elif ! systemctl --user is-active ccgram.service &>/dev/null; then
            if systemctl --user start ccgram.service 2>/dev/null; then
                print_success "ccgram service started."
            fi
        fi
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
    echo -e "${GRAY}Version 146 | Last changed: Remove retired AI agent setup${NC}"

    # Create placeholder env file early
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
    install_whisper
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
    install_gemini_cli
    install_codex_cli
    install_rtk_cli
    install_ccgram

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
        setup_pi_goal_autoresearch
        if ! matt_pocock_pi_skills_disabled; then
            setup_matt_pocock_pi_skills
        fi
        setup_pi_compound_engineering
    else
        print_warning "Skipping Pi extension setup because Pi migration failed."
    fi

    print_section "Shell Configuration"
    set_fish_as_default_shell
    install_act
    install_tmux_plugins
    enable_user_lingering
    install_iterm2_shell_integration

    print_section "Final Updates"
    upgrade_npm_global_packages

    echo -e "${GRAY}Run log saved to: ${log_file}${NC}"
    printf '\n%s%s✨ Setup complete! Please log out and log back in for all changes to take effect.%s\n\n' "${GREEN}" "${BOLD}" "${NC}" | tee -a "${log_file}" >&3
    upload_log
}

main "$@"