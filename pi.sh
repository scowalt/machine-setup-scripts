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

# Check if user has sudo access (cached result)
_sudo_checked=""
_has_sudo=""
can_sudo() {
    if [[ -z "${_sudo_checked}" ]]; then
        _sudo_checked=1
        # Method 1: Check if credentials are already cached
        if sudo -n true 2>/dev/null; then
            _has_sudo=1
        # Method 2: Check if user is in a sudo-capable group, then prompt
        elif groups 2>/dev/null | grep -qE '\b(sudo|wheel|admin)\b'; then
            # User is in sudo group but credentials aren't cached - prompt once
            if sudo -v 2>/dev/null; then
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
        exit 0
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
        ssh-keygen -t ed25519 -f "${key_file}" -N '' -C "dotfiles-deploy-key-$(hostname)"
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
        if ssh -i "${key_file}" -o StrictHostKeyChecking=accept-new -T git@github.com < /dev/null 2>&1 | grep -q "successfully authenticated"; then
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
        if ssh -T git@github.com < /dev/null 2>&1 | grep -q "successfully authenticated"; then
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
        if ssh -i ~/.ssh/dotfiles-deploy-key -T git@github.com < /dev/null 2>&1 | grep -q "successfully authenticated"; then
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
    local packages=("git" "curl" "jq" "fish" "tmux" "fonts-firacode" "gh" "build-essential" "libssl-dev" "zlib1g-dev" "libbz2-dev" "libreadline-dev" "libsqlite3-dev" "wget" "unzip" "llvm" "libncurses5-dev" "libncursesw5-dev" "xz-utils" "tk-dev" "libffi-dev" "liblzma-dev")
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
        exit 1
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
        exit 1
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
            exit 1
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
    if ! command -v tailscale &>/dev/null; then
        print_message "Installing Tailscale…"
        # Official install script (adds repo + installs package) :contentReference[oaicite:0]{index=0}
        local tailscale_install
        tailscale_install=$(curl -fsSL https://tailscale.com/install.sh)
        echo "${tailscale_install}" | sudo sh
        sudo systemctl enable --now tailscaled
        print_success "Tailscale installed and service started."

        # Optional immediate login
        echo -n "Run 'tailscale up' now to authenticate? (y/n): "
        read -r ts_up < /dev/tty
        if [[ "${ts_up}" =~ ^[Yy]$ ]]; then
            print_message "Bringing interface up…"
            sudo tailscale up       # add --authkey=... if you prefer key‑based auth
        else
            print_warning "Skip for now; run 'sudo tailscale up' later to log in."
        fi
    else
        print_debug "Tailscale already installed."
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
    sudo chsh -s /usr/bin/fish "${USER}"
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
        exit 1
    fi

    # Run verbosely; bail if anything returns non‑zero
    if ! ${chezmoi_cmd} apply --force --verbose; then
        print_error "chezmoi apply failed – fix the dotfiles, then rerun the script."
        exit 1
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
    if ssh-add ~/.ssh/id_rsa >/dev/null 2>&1; then
        print_success "SSH key added to agent."
    else
        print_error "Could not add ~/.ssh/id_rsa to ssh‑agent. Check permissions."
        exit 1
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

# Install git-town by downloading binary directly
install_git_town() {
    if command -v git-town &> /dev/null; then
        print_debug "git-town is already installed."
        return
    fi

    print_message "Installing git-town via direct binary download..."
    
    # Detect architecture
    local arch
    arch=$(uname -m)
    local git_town_arch
    
    case "${arch}" in
        x86_64)
            git_town_arch="linux_intel_64"
            ;;
        aarch64)
            git_town_arch="linux_arm_64"
            ;;
        armv7l)
            git_town_arch="linux_arm_32"
            ;;
        *)
            print_error "Unsupported architecture: ${arch}"
            return 1
            ;;
    esac
    
    # Create local bin directory if it doesn't exist
    local bin_dir="${HOME}/.local/bin"
    mkdir -p "${bin_dir}"
    
    # Download the latest binary
    local download_url="https://github.com/git-town/git-town/releases/latest/download/git-town_${git_town_arch}.tar.gz"
    local temp_dir
    temp_dir=$(mktemp -d)
    
    print_message "Downloading git-town binary for ${arch} architecture..."
    local tarball="${temp_dir}/git-town.tar.gz"
    if ! curl -sL "${download_url}" -o "${tarball}"; then
        print_error "Failed to download git-town."
        rm -rf "${temp_dir}"
        return 1
    fi
    if tar -xzf "${tarball}" -C "${temp_dir}"; then
        # Move binary to local bin
        if mv "${temp_dir}/git-town" "${bin_dir}/git-town"; then
            chmod +x "${bin_dir}/git-town"
            print_success "git-town installed to ${bin_dir}/git-town"
            
            # Add to PATH if not already present
            if ! echo "${PATH}" | grep -q "${bin_dir}"; then
                print_message "Adding ${bin_dir} to PATH in ~/.bashrc"
                echo "export PATH=\${HOME}/.local/bin:\${PATH}" >> ~/.bashrc
                export PATH="${bin_dir}:${PATH}"
            fi
        else
            print_error "Failed to move git-town binary."
            rm -rf "${temp_dir}"
            return 1
        fi
    else
        print_error "Failed to download git-town."
        rm -rf "${temp_dir}"
        return 1
    fi
    
    rm -rf "${temp_dir}"
}

# Configure git-town completions
configure_git_town() {
    if command -v git-town &> /dev/null; then
        print_message "Configuring git-town completions..."
        
        # Set up Fish shell completions for git-town
        if [[ -d ~/.config/fish/completions ]]; then
            if ! [[ -f ~/.config/fish/completions/git-town.fish ]]; then
                git town completion fish > ~/.config/fish/completions/git-town.fish
                print_success "git-town Fish completions configured."
            else
                print_debug "git-town Fish completions already configured."
            fi
        fi
        
        # Set up Bash completions for git-town
        local bash_completion_dir="/etc/bash_completion.d"
        if [[ -d "${bash_completion_dir}" ]]; then
            if ! [[ -f "${bash_completion_dir}/git-town" ]]; then
                local bash_completion
                bash_completion=$(git town completion bash)
                echo "${bash_completion}" | sudo tee "${bash_completion_dir}/git-town" > /dev/null
                print_success "git-town Bash completions configured."
            else
                print_debug "git-town Bash completions already configured."
            fi
        fi
    else
        print_warning "git-town not found, skipping completion setup."
    fi
}

# Install jj (Jujutsu) version control by downloading binary directly
install_jj() {
    if command -v jj &> /dev/null; then
        print_debug "jj (Jujutsu) is already installed."
        return
    fi

    print_message "Installing jj (Jujutsu) via direct binary download..."

    # Detect architecture using uname
    local arch
    arch=$(uname -m)
    local jj_arch

    case "${arch}" in
        x86_64)
            jj_arch="x86_64-unknown-linux-musl"
            ;;
        aarch64)
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
    latest_version=$(curl -sL "https://api.github.com/repos/jj-vcs/jj/releases/latest" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
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

# ----------------------[ Fast Node Manager ]--------------------
install_fnm() {
    if command -v fnm >/dev/null; then
        print_debug "fnm already installed."
        return
    fi

    print_message "Installing fnm (Fast Node Manager)…"
    local fnm_install_script
    fnm_install_script=$(curl -fsSL https://fnm.vercel.app/install)
    if bash -s -- --skip-shell <<< "${fnm_install_script}"; then
        print_success "fnm installed. Shell configuration will be managed by chezmoi."
    else
        print_error "Failed to install fnm."
        return 1
    fi
}

# Setup Node.js using fnm
setup_nodejs() {
    print_message "Setting up Node.js with fnm..."
    
    # Initialize fnm for current session
    if [[ -s "${HOME}/.local/share/fnm/fnm" ]]; then
        export PATH="${HOME}/.local/share/fnm:${PATH}"
        local fnm_env
        fnm_env=$(fnm env --use-on-cd)
        eval "${fnm_env}"
    else
        print_warning "fnm not found in expected location. Skipping Node.js setup."
        return
    fi
    
    # Check if fnm is now available
    if ! command -v fnm &> /dev/null; then
        print_warning "fnm command not available. Skipping Node.js setup."
        return
    fi
    
    # Check if any Node.js version is installed
    local fnm_list_output
    fnm_list_output=$(fnm list)
    if echo "${fnm_list_output}" | grep -q .; then
        print_debug "Node.js version already installed."
        
        # Check if a default/global version is set
        local current_version
        current_version=$(fnm current 2>/dev/null || echo "none")
        if [[ "${current_version}" != "none" ]] && [[ -n "${current_version}" ]]; then
            print_debug "Global Node.js version already set: ${current_version}"
        else
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
        print_warning "Note: Compiling Node.js on Raspberry Pi can take 10-20 minutes."
        if fnm install --lts; then
            print_success "Installed latest LTS Node.js."
            # Set it as default
            local current_node
            current_node=$(fnm current)
            fnm default "${current_node}"
            local current_display
            current_display=$(fnm current)
            print_success "Set ${current_display} as default Node.js version."
        else
            print_error "Failed to install Node.js."
            return 1
        fi
    fi
}

# Install Claude Code using official installer
install_claude_code() {
    if command -v claude &> /dev/null; then
        print_debug "Claude Code is already installed."
        return
    fi

    print_message "Installing Claude Code..."

    # Clean up stale lock files from previous interrupted installs
    rm -rf "${HOME}/.local/state/claude/locks" 2>/dev/null

    # Use the native installer (doesn't require Node.js)
    # Download to temp file and execute (more reliable than piping when run via curl|bash)
    local temp_script
    temp_script=$(mktemp)
    if curl -fsSL https://claude.ai/install.sh -o "${temp_script}"; then
        chmod +x "${temp_script}"
        # Redirect stdin from /dev/null to prevent installer from consuming script input
        if bash "${temp_script}" < /dev/null; then
            # Add claude bin directory to PATH for current session
            # The native installer puts claude in ~/.local/bin
            if [[ -d "${HOME}/.local/bin" ]]; then
                export PATH="${HOME}/.local/bin:${PATH}"
            fi
            print_success "Claude Code installed."
        else
            print_error "Failed to install Claude Code."
        fi
        rm -f "${temp_script}"
    else
        print_error "Failed to download Claude Code installer."
        rm -f "${temp_script}"
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

# Install act for running GitHub Actions locally
install_act() {
    if ! command -v act &> /dev/null; then
        print_message "Installing act (GitHub Actions runner)..."
        # Use the official install script
        local act_install
        act_install=$(curl -s https://raw.githubusercontent.com/nektos/act/master/install.sh)
        if ! echo "${act_install}" | sudo bash; then
            print_error "Failed to install act."
            exit 1
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

# Install pyenv for Python version management with Raspberry Pi optimizations
install_pyenv() {
    if ! command -v pyenv &> /dev/null; then
        # Check if ~/.pyenv exists but pyenv command is not available
        if [[ -d "${HOME}/.pyenv" ]]; then
            print_warning "pyenv directory exists but command not found. Trying to fix PATH..."
            export PYENV_ROOT="${HOME}/.pyenv"
            export PATH="${PYENV_ROOT}/bin:${PATH}"
            if command -v pyenv &> /dev/null; then
                print_success "pyenv found after fixing PATH."
                # Still show memory warning for Pi
                local total_mem
                local free_output
    free_output=$(free -m)
    total_mem=$(echo "${free_output}" | awk '/^Mem:/{print $2}')
                if [[ "${total_mem}" -lt 1024 ]]; then
                    print_warning "Limited RAM detected. Python compilation may be slow or fail."
                    print_message "Consider using pre-built Python packages or increasing swap."
                fi
                return
            else
                print_error "pyenv directory exists but binary not found. Manual intervention may be required."
                return 1
            fi
        fi
        
        print_message "Installing pyenv (this may take a while on Raspberry Pi)..."
        # Use the official install script
        local pyenv_installer
        pyenv_installer=$(curl -L https://github.com/pyenv/pyenv-installer/raw/master/bin/pyenv-installer)
        if bash <<< "${pyenv_installer}"; then
            print_success "pyenv installed. Shell configuration will be managed by chezmoi."
        else
            print_error "Failed to install pyenv."
            return 1
        fi
        
        # Check available memory for warning about Python compilation
        local total_mem
    local free_output
    free_output=$(free -m)
    total_mem=$(echo "${free_output}" | awk '/^Mem:/{print $2}')
        if [[ "${total_mem}" -lt 1024 ]]; then
            print_warning "Low memory detected. Python compilation may take a very long time."
            print_message "Consider using system Python instead if compilation fails."
        fi
    else
        print_debug "pyenv is already installed."
    fi
}

# Upgrade global npm packages
upgrade_npm_global_packages() {
    # Initialize fnm for current session
    if [[ -s "${HOME}/.local/share/fnm/fnm" ]]; then
        export PATH="${HOME}/.local/share/fnm:${PATH}"
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

# Main execution
echo -e "\n${BOLD}🍓 Raspberry Pi Development Environment Setup${NC}"
echo -e "${GRAY}Version 64 | Last changed: Add jq to core packages${NC}"

print_section "User & System Setup"
ensure_not_root
check_raspberry_pi
setup_swap
setup_dns64_for_ipv6_only

print_section "System Updates"
update_dependencies
update_and_install_core

print_section "Development Tools"
install_1password_cli
install_fnm
setup_nodejs
install_pyenv
install_uv
install_opentofu

print_section "Network & SSH"
enable_ssh_server
install_tailscale
install_fail2ban
setup_unattended_upgrades
add_github_to_known_hosts
ensure_ssh_agent

current_user=$(whoami)
if [[ "${current_user}" == "scowalt" ]]; then
    print_section "Code Directory Setup"
    setup_code_directory
fi

print_section "Additional Development Tools"
install_claude_code

print_section "Terminal & Shell"
install_starship
install_git_town
configure_git_town
install_jj

print_section "Dotfiles Management"

# Check if we have access (via SSH or deploy key)
# If not, try interactive deploy key setup
if check_dotfiles_access || setup_dotfiles_deploy_key; then
    # We have access, proceed with chezmoi setup
    install_chezmoi
    initialize_chezmoi
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

echo -e "\n${GREEN}${BOLD}✨ Setup complete! Please log out and log back in for all changes to take effect.${NC}\n"