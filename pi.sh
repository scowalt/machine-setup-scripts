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

    print_message "Upgrading packages (this may take a while)..."
    sudo apt upgrade -y

    print_message "Removing unnecessary packages..."
    sudo apt autoremove -y

    print_success "Package lists updated."
}

# Update and install core dependencies with Raspberry Pi considerations
update_and_install_core() {
    print_message "Checking and installing core packages as needed..."

    # Define an array of required packages
    local packages=("git" "curl" "jq" "fish" "tmux" "fonts-firacode" "gh" "build-essential" "libssl-dev" "zlib1g-dev" "libbz2-dev" "libreadline-dev" "libsqlite3-dev" "wget" "unzip" "llvm" "libncurses5-dev" "libncursesw5-dev" "xz-utils" "tk-dev" "libffi-dev" "liblzma-dev" "golang-go" "inotify-tools" "shellcheck" "gitleaks" "poppler-utils")
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
    backend_state=$(tailscale status --json 2>/dev/null | grep -o '"BackendState":[[:space:]]*"[^"]*"' | cut -d'"' -f4)
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
    run_ssh=$(tailscale debug prefs 2>/dev/null | grep -o '"RunSSH":[a-z]*' | cut -d: -f2)
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
    if curl -1sLf 'https://dl.cloudsmith.io/public/infisical/infisical-cli/setup.deb.sh' | sudo bash; then
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
    if curl -fsSL https://mise.run | sh; then
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
        local _bun_packages
        _bun_packages=$(bun pm ls -g 2>/dev/null) || true
        if echo "${_bun_packages}" | grep -q "@anthropic-ai/claude-code"; then
            print_message "Removing bun-based Claude Code installation..."
            bun remove -g @anthropic-ai/claude-code 2>/dev/null || true
        fi
    fi

    # Clean up stale lock files
    rm -rf "${HOME}/.local/state/claude/locks" 2>/dev/null

    # Always run the installer — it handles both install and update idempotently
    print_message "Installing/updating Claude Code via official installer..."
    local _install_script
    _install_script=$(curl -fsSL https://claude.ai/install.sh) || true
    if bash <<< "${_install_script}"; then
        print_success "Claude Code installed/updated."
    else
        print_error "Failed to install Claude Code."
        return 1
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
            sudo chown -R "$(whoami)" /home/linuxbrew
        fi
        NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" > /dev/null
        print_success "Homebrew installed."
    fi
    # Ensure brew is in PATH for this session
    if [[ -x "/home/linuxbrew/.linuxbrew/bin/brew" ]]; then
        eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
    fi

    # Fix ownership if Cellar is not writable by current user (multi-user installs)
    local brew_prefix
    brew_prefix="$(brew --prefix 2>/dev/null)"
    if [[ -n "${brew_prefix}" ]] && [[ -d "${brew_prefix}/Cellar" ]] && [[ ! -w "${brew_prefix}/Cellar" ]]; then
        if can_sudo; then
            print_message "Fixing Homebrew permissions for $(whoami)..."
            sudo chown -R "$(whoami)" "${brew_prefix}/Cellar" "${brew_prefix}/Homebrew" "${brew_prefix}/lib" "${brew_prefix}/bin" "${brew_prefix}/share" "${brew_prefix}/etc" "${brew_prefix}/opt" "${brew_prefix}/var" 2>/dev/null
            print_success "Homebrew permissions fixed."
        else
            print_warning "Homebrew Cellar is not writable by $(whoami). Brew installs may fail."
            print_debug "An admin can fix this: sudo chown -R $(whoami) ${brew_prefix}/Cellar"
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
    curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | sudo tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
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
    echo -e "\n${BOLD}🍓 Raspberry Pi Development Environment Setup${NC}"
    echo -e "${GRAY}Version 122 | Last changed: Gate Socket Firewall behind WORK_MACHINE=1${NC}"

    # Log this run
    local log_dir="${HOME}/.local/log/machine-setup"
    mkdir -p "${log_dir}"
    local log_file
    log_file="${log_dir}/$(date +%Y-%m-%d-%H%M%S).log"
    exec > >(tee -a "${log_file}") 2>&1
    print_debug "Logging to ${log_file}"

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

    current_user=$(whoami)
    if [[ "${current_user}" == "scowalt" ]]; then
        print_section "Code Directory Setup"
        setup_code_directory
    fi

    print_section "Additional Development Tools"
    install_bun
    install_sfw
    install_claude_code
    setup_compound_plugin
    setup_telegram_plugin
    install_gemini_cli
    install_codex_cli
    install_ccgram

    print_section "Terminal & Shell"
    install_starship

    print_section "Shared Directories"
    setup_claude_shared_directory

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

    print_section "Shell Configuration"
    set_fish_as_default_shell
    install_act
    install_tmux_plugins
    install_iterm2_shell_integration
    
    print_section "Final Updates"
    upgrade_npm_global_packages

    echo -e "${GRAY}Run log saved to: ${log_file}${NC}"
    upload_log
    echo -e "\n${GREEN}${BOLD}✨ Setup complete! Please log out and log back in for all changes to take effect.${NC}\n"
}

main "$@"