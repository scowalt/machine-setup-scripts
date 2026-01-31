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

# Check if user is scowalt or a secondary user (<org>-scowalt pattern)
is_scowalt_user() {
    local user="${1:-$(whoami)}"
    [[ "${user}" == "scowalt" ]] || [[ "${user}" == *-scowalt ]]
}

# Check if running as main user (scowalt)
is_main_user() {
    [[ "$(whoami)" == "scowalt" ]]
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

# Source GitHub tokens from ~/.gh_token if it exists
# File format:
#   export GH_TOKEN=github_pat_xxx           # work/primary org token
#   export GH_TOKEN_SCOWALT=github_pat_yyy   # scowalt org token (for dotfiles)
source_gh_tokens() {
    if [[ -f "${HOME}/.gh_token" ]]; then
        # shellcheck source=/dev/null
        source "${HOME}/.gh_token"
        if [[ -n "${GH_TOKEN}" ]]; then
            print_debug "GH_TOKEN loaded from ~/.gh_token"
        fi
        if [[ -n "${GH_TOKEN_SCOWALT}" ]]; then
            print_debug "GH_TOKEN_SCOWALT loaded from ~/.gh_token"
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
    if [[ -f /etc/netplan/60-dns64.yaml ]]; then
        print_debug "DNS64 already configured."
        return 0
    fi

    # Requires sudo to configure
    if ! can_sudo; then
        print_warning "IPv6-only network detected but no sudo access - cannot configure DNS64."
        return 0
    fi

    print_message "IPv6-only network detected. Configuring DNS64..."

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

# Fix dpkg interruptions if they exist
fix_dpkg_and_broken_dependencies() {
    if ! can_sudo; then
        print_debug "No sudo access - skipping dpkg fix."
        return
    fi
    print_message "Checking for and fixing dpkg interruptions or broken dependencies..."
    # The following commands will fix most common dpkg/apt issues.
    # They are safe to run even if there are no issues.
    sudo DEBIAN_FRONTEND=noninteractive dpkg --force-confold --configure -a
    sudo DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::="--force-confold" install -f -y
    print_success "dpkg and dependencies check/fix complete."
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

    local current_user
    current_user=$(whoami)
    print_success "Running as user '${current_user}'. Proceeding with setup."
    cd ~ || exit 1
}

# Update dependencies non-silently
update_dependencies() {
    if ! can_sudo; then
        print_warning "No sudo access - skipping system updates."
        return
    fi
    print_message "Updating package lists..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get update
    sudo DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::="--force-confold" upgrade -y
    sudo DEBIAN_FRONTEND=noninteractive apt-get autoremove -y
    print_success "Package lists updated."
}

# Update and install core dependencies silently
update_and_install_core() {
    print_message "Checking core packages..."

    # Define an array of required packages
    local packages=("git" "curl" "jq" "fish" "tmux" "fonts-firacode" "gh" "build-essential" "libssl-dev" "zlib1g-dev" "libbz2-dev" "libreadline-dev" "libsqlite3-dev" "wget" "unzip" "llvm" "libncurses5-dev" "libncursesw5-dev" "xz-utils" "tk-dev" "libffi-dev" "liblzma-dev" "golang-go")
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
        if ! sudo DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::="--force-confold" install -qq -y "${to_install[@]}"; then
            print_error "Failed to install some core packages. Please review the output above."
            exit 1
        fi
        print_success "Missing core packages installed."
    else
        print_success "All core packages are already installed."
    fi
}

# Install and enable SSH server
setup_ssh_server() {
    if ! can_sudo; then
        print_debug "No sudo access - skipping SSH server setup."
        return
    fi

    print_message "Checking and setting up SSH server..."

    # Check if openssh-server is installed
    if ! dpkg -s "openssh-server" &> /dev/null; then
        print_message "Installing openssh-server..."
        if ! sudo DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::="--force-confold" install -qq -y openssh-server; then
            print_error "Failed to install openssh-server."
            exit 1
        fi
        print_success "openssh-server installed."
    else
        print_debug "openssh-server is already installed."
    fi

    # Check if ssh service is active
    if ! systemctl is-active --quiet ssh; then
        print_message "Starting ssh service..."
        sudo systemctl start ssh
        print_success "ssh service started."
    else
        print_debug "ssh service is already active."
    fi

    # Check if ssh service is enabled to start on boot
    if ! systemctl is-enabled --quiet ssh; then
        print_message "Enabling ssh service to start on boot..."
        sudo systemctl enable ssh
        print_success "ssh service enabled."
    else
        print_debug "ssh service is already enabled."
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

    local existing_keys
    existing_keys=$(curl -s https://github.com/scowalt.keys)
    # Remember - chezmoi will set up authorized_keys for you

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
            xdg-open "https://github.com/settings/keys" 2>/dev/null || true
            exit 1
        fi
    else
        # Generate a new SSH key and log details
        print_warning "No SSH key found. Generating a new SSH key..."
        local hostname_value
        hostname_value=$(hostname)
        ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N "" -C "scowalt@${hostname_value}"
        print_success "SSH key generated."
        print_message "Please add the following SSH key to GitHub:"
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

# Install Starship if not installed
# NOTE: Uses official install script because starship not available in Ubuntu repos
# DO NOT change to Homebrew - this ensures latest version and proper permissions
install_starship() {
    if ! command -v starship &> /dev/null; then
        print_message "Installing Starship prompt..."
        local starship_install
        starship_install=$(curl -fsSL https://starship.rs/install.sh)
        sh -c "${starship_install}" -- -y
        print_success "Starship installed."
    else
        print_debug "Starship is already installed."
    fi
}

# Install chezmoi if not installed
install_chezmoi() {
    if ! command -v chezmoi &> /dev/null; then
        print_message "Installing chezmoi..."
        local bin_dir="${HOME}/.local/bin"
        mkdir -p "${bin_dir}"
        local chezmoi_install
        chezmoi_install=$(curl -fsLS get.chezmoi.io)
        if sh -c "${chezmoi_install}" -- -b "${bin_dir}"; then
            # Add bin_dir to PATH for the current script session
            export PATH="${bin_dir}:${PATH}"
            print_success "chezmoi installed."
        else
            print_error "Failed to install chezmoi. Please review the output above."
            exit 1
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
                print_error "Failed to initialize chezmoi. Please review the output above."
                exit 1
            fi
        else
            # Other users use SSH via deploy key (github-dotfiles alias)
            if ! chezmoi init --apply --force "git@github-dotfiles:scowalt/dotfiles.git"; then
                print_error "Failed to initialize chezmoi. Please review the output above."
                exit 1
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
    if [[ "${user_shell}" != "/usr/bin/fish" ]]; then
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
        print_success "Fish shell set as default."
    else
        print_debug "Fish shell is already the default shell."
    fi
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

# Install Claude Code version 2.0.63 using bun
# Pinned version to avoid breaking changes from auto-updates
install_claude_code() {
    local target_version="2.0.63"

    # Ensure bun is available first
    if [[ -d "${HOME}/.bun" ]]; then
        export PATH="${HOME}/.bun/bin:${PATH}"
    fi

    if ! command -v bun &> /dev/null; then
        print_error "Bun is not installed. Cannot install Claude Code."
        return 1
    fi

    # Check if Claude Code is already installed
    if command -v claude &> /dev/null; then
        local current_version
        current_version=$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)

        if [[ "${current_version}" == "${target_version}" ]]; then
            print_debug "Claude Code v${target_version} is already installed."
            return 0
        elif [[ -n "${current_version}" ]]; then
            print_warning "Claude Code v${current_version} found, but v${target_version} is required."
            print_message "Uninstalling current version..."

            # Try to uninstall via bun first, then npm, then remove native binaries
            bun remove -g @anthropic-ai/claude-code 2>/dev/null || true
            npm uninstall -g @anthropic-ai/claude-code 2>/dev/null || true

            # Remove native installer binaries if present
            rm -f "${HOME}/.claude/bin/claude" 2>/dev/null || true
            rm -f "${HOME}/.local/bin/claude" 2>/dev/null || true

            # Clear shell hash table
            hash -r 2>/dev/null || true

            print_success "Previous version uninstalled."
        fi
    fi

    print_message "Installing Claude Code v${target_version}..."

    # Clean up stale lock files from previous interrupted installs
    rm -rf "${HOME}/.local/state/claude/locks" 2>/dev/null

    # Install specific version using bun
    if bun install -g @anthropic-ai/claude-code@${target_version}; then
        print_success "Claude Code v${target_version} installed."
    else
        print_error "Failed to install Claude Code."
        return 1
    fi
}

# Configure Rube MCP server for Claude Code
setup_rube_mcp() {
    if ! command -v claude &> /dev/null; then
        print_debug "Claude Code not found. Skipping Rube MCP setup."
        return 0
    fi

    # Check if rube MCP server is already configured
    if claude mcp list 2>/dev/null | grep -q "rube"; then
        print_debug "Rube MCP server is already configured."
        return 0
    fi

    print_message "Configuring Rube MCP server for Claude Code..."
    if claude mcp add rube --transport http https://rube.app/mcp 2>/dev/null; then
        print_success "Rube MCP server configured."
    else
        print_warning "Failed to configure Rube MCP server."
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
        fnm_env=$("${HOME}"/.local/share/fnm/fnm env --use-on-cd)
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
    fnm_list_output=$(fnm list 2>&1)
    if echo "${fnm_list_output}" | grep -q "error\|Error"; then
        print_error "fnm list returned an error: ${fnm_list_output}"
        return 1
    fi
    
    # Check if only system version is available
    local filtered_fnm_output
    filtered_fnm_output=$(echo "${fnm_list_output}" | grep -v "system")
    if echo "${filtered_fnm_output}" | grep -q "v[0-9]"; then
        print_debug "Node.js version already installed."
        
        # Always install latest LTS and set as default to keep Node.js current
        print_message "Installing latest LTS Node.js..."
        if fnm install --lts; then
            fnm use lts-latest
            local lts_version
            lts_version=$(fnm current)
            fnm default "${lts_version}"
            # Re-initialize fnm to pick up the new default
            local fnm_env_update
            fnm_env_update=$("${HOME}"/.local/share/fnm/fnm env --use-on-cd)
            eval "${fnm_env_update}"
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
            # Extract the first non-system version
            local fnm_versions
            fnm_versions=$(fnm list)
            local version_lines
            version_lines=$(echo "${fnm_versions}" | grep -E "^[[:space:]]*\*?[[:space:]]*v[0-9]")
            local first_line
            first_line=$(echo "${version_lines}" | head -n1)
            local cleaned_line
            # Remove leading whitespace and optional asterisk
            cleaned_line="${first_line#"${first_line%%[![:space:]]*}"}"
            cleaned_line="${cleaned_line#\*}"
            cleaned_line="${cleaned_line#"${cleaned_line%%[![:space:]]*}"}"
            first_version=$(echo "${cleaned_line}" | awk '{print $1}')

            if [[ -n "${first_version}" ]]; then
                if fnm default "${first_version}"; then
                    print_success "Set ${first_version} as default Node.js version."
                    local fnm_env_default
                    fnm_env_default=$("${HOME}"/.local/share/fnm/fnm env --use-on-cd)
                    eval "${fnm_env_default}"
                else
                    print_error "Failed to set default Node.js version. You may need to run: fnm default ${first_version}"
                fi
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
            local current_display
            current_display=$(fnm current)
            print_success "Set ${current_display} as default Node.js version."
        else
            print_error "Failed to install Node.js."
            return 1
        fi
    fi
}

# Install 1Password CLI
install_1password_cli() {
    if command -v op >/dev/null; then
        print_debug "1Password CLI already installed."
        return
    fi

    if ! can_sudo; then
        print_warning "No sudo access - cannot install 1Password CLI."
        return
    fi

    print_message "Installing 1Password CLI..."

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
    [[ "${dpkg_arch}" == "armhf" ]] && repo_arch="arm"   # 32-bit Pi

    # Add repo
    echo \
"deb [arch=${dpkg_arch} signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] \
https://downloads.1password.com/linux/debian/${repo_arch} stable main" \
        | sudo tee /etc/apt/sources.list.d/1password-cli.list >/dev/null

    # Add debsig-verify policy (required for future updates)
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

# Install Tailscale
install_tailscale() {
    if command -v tailscale &>/dev/null; then
        print_debug "Tailscale already installed."
        return
    fi

    if ! can_sudo; then
        print_warning "No sudo access - cannot install Tailscale."
        return
    fi

    print_message "Installing Tailscale..."
    # Official install script (adds repo + installs package)
    local tailscale_install
    tailscale_install=$(curl -fsSL https://tailscale.com/install.sh)
    echo "${tailscale_install}" | sudo sh
    sudo systemctl enable --now tailscaled
    print_success "Tailscale installed and service started."

    # Optional immediate login
    echo -n "Run 'tailscale up' now to authenticate? (y/n): "
    read -r ts_up < /dev/tty
    if [[ "${ts_up}" =~ ^[Yy]$ ]]; then
        print_message "Bringing interface up..."
        sudo tailscale up       # add --authkey=... if you prefer key-based auth
    else
        print_warning "Skip for now; run 'sudo tailscale up' later to log in."
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
    if sudo DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::="--force-confold" install -y fail2ban; then
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
        if ! sudo DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::="--force-confold" install -y unattended-upgrades; then
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

# Install cloudflared (Cloudflare Tunnel client)
install_cloudflared() {
    if command -v cloudflared &> /dev/null; then
        print_debug "cloudflared is already installed."
        return
    fi

    if ! can_sudo; then
        print_warning "No sudo access - cannot install cloudflared."
        return
    fi

    print_message "Installing cloudflared..."

    # Add Cloudflare GPG key
    sudo mkdir -p --mode=0755 /usr/share/keyrings
    local gpg_key
    gpg_key=$(curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg)
    echo "${gpg_key}" | sudo tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null

    # Add cloudflared apt repository
    echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main' | sudo tee /etc/apt/sources.list.d/cloudflared.list >/dev/null

    # Install cloudflared
    sudo apt-get update -qq
    if sudo apt-get install -y cloudflared; then
        print_success "cloudflared installed."
    else
        print_error "Failed to install cloudflared."
        return 1
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
    if command -v act &> /dev/null; then
        print_debug "act is already installed."
        return
    fi

    if ! can_sudo; then
        print_warning "No sudo access - cannot install act."
        return
    fi

    print_message "Installing act (GitHub Actions runner)..."
    # Use the official install script
    local act_install
    act_install=$(curl -s https://raw.githubusercontent.com/nektos/act/master/install.sh)
    if ! echo "${act_install}" | sudo bash; then
        print_error "Failed to install act."
        exit 1
    fi
    print_success "act installed."
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

# Install pyenv for Python version management
install_pyenv() {
    if ! command -v pyenv &> /dev/null; then
        # Check if ~/.pyenv exists but pyenv command is not available
        if [[ -d "${HOME}/.pyenv" ]]; then
            print_warning "pyenv directory exists but command not found. Trying to fix PATH..."
            export PYENV_ROOT="${HOME}/.pyenv"
            export PATH="${PYENV_ROOT}/bin:${PATH}"
            if command -v pyenv &> /dev/null; then
                print_success "pyenv found after fixing PATH."
                return
            else
                print_error "pyenv directory exists but binary not found. Manual intervention may be required."
                return 1
            fi
        fi
        
        print_message "Installing pyenv..."
        # Use the official install script
        local pyenv_installer
        pyenv_installer=$(curl -L https://github.com/pyenv/pyenv-installer/raw/master/bin/pyenv-installer)
        if bash <<< "${pyenv_installer}"; then
            print_success "pyenv installed. Shell configuration will be managed by chezmoi."
        else
            print_error "Failed to install pyenv."
            return 1
        fi
    else
        print_debug "pyenv is already installed."
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

    print_message "Installing/updating tmux plugins via tpm..."
    local tpm_installer=~/.tmux/plugins/tpm/bin/install_plugins
    
    # Let tpm script install plugins. It handles finding tmux.conf and starting a server.
    # Capture output to show only on failure.
    local output
    if ! output=$(${tpm_installer} 2>&1); then
        print_error "Failed to install tmux plugins. tpm output was:"
        echo "${output}"
        # Not exiting, to maintain original script's behavior.
        return
    fi

    # Try to source the config to make plugins available in a running session.
    # This might fail if tmux server is not running, which is fine.
    local tmux_conf="${HOME}/.config/tmux/tmux.conf"
    if [[ -f "${tmux_conf}" ]]; then
        tmux source-file "${tmux_conf}" >/dev/null 2>&1
    elif [[ -f "${HOME}/.tmux.conf" ]]; then # fallback to old location
        tmux source-file "${HOME}/.tmux.conf" >/dev/null 2>&1
    fi
    print_success "tmux plugins installed and updated."
}

# Enable tmux systemd user service for session persistence
enable_tmux_service() {
    # Skip if running inside tmux - daemon-reload/enable can kill the session
    if [[ -n "${TMUX}" ]]; then
        print_debug "Running inside tmux, skipping service reload to avoid killing session."
        return
    fi

    local service_file="${HOME}/.config/systemd/user/tmux.service"
    if [[ ! -f "${service_file}" ]]; then
        print_debug "tmux.service not found - will be created by chezmoi apply"
        return
    fi

    print_message "Enabling tmux systemd user service..."
    systemctl --user daemon-reload
    if systemctl --user enable --now tmux.service 2>/dev/null; then
        print_success "tmux service enabled and started."
    else
        # Service might already be running or have issues
        if systemctl --user is-enabled tmux.service &>/dev/null; then
            print_debug "tmux service already enabled."
        else
            print_warning "Could not enable tmux service."
        fi
    fi
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

        if [[ "${owner_uid}" == "$(id -u)" ]]; then
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


echo -e "\n${BOLD}🐧 Ubuntu Development Environment Setup${NC}"
echo -e "${GRAY}Version 99 | Last changed: Always update fnm default to latest LTS${NC}"

print_section "User & System Setup"
ensure_not_root
setup_dns64_for_ipv6_only
fix_dpkg_and_broken_dependencies

print_section "System Updates"
update_dependencies # I do this first b/c on raspberry pi, it's slow
update_and_install_core

print_section "SSH Configuration"
setup_ssh_server
add_github_to_known_hosts

if is_main_user; then
    print_section "Code Directory Setup"
    setup_code_directory
fi

print_section "Development Tools"
install_starship
install_jj
install_fnm
setup_nodejs
install_pyenv
install_uv
install_opentofu
install_cloudflared
install_turso

print_section "Security Tools"
install_1password_cli
install_tailscale
install_fail2ban
setup_unattended_upgrades

print_section "Shared Directories"
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
    configure_chezmoi_git
    fix_chezmoi_remote_for_deploy_key
    update_chezmoi
    (chezmoi apply --force) || true
    tmux source ~/.tmux.conf 2>/dev/null || true
else
    print_warning "Skipping dotfiles management - no access to repository."
fi

print_section "Shell Configuration"
set_fish_as_default_shell
install_act
install_tmux_plugins
enable_tmux_service
install_iterm2_shell_integration

print_section "Additional Development Tools"
install_bun
install_claude_code
setup_rube_mcp
install_gemini_cli
install_codex_cli

print_section "Final Updates"
upgrade_npm_global_packages

echo -e "\n${GREEN}${BOLD}✨ Setup complete!${NC}\n"
