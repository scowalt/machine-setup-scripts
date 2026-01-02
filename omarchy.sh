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

# Check if user is scowalt or a secondary user (<org>-scowalt pattern)
is_scowalt_user() {
    local user="${1:-$(whoami)}"
    [[ "${user}" == "scowalt" ]] || [[ "${user}" == *-scowalt ]]
}

# Check if running as main user (scowalt)
is_main_user() {
    [[ "$(whoami)" == "scowalt" ]]
}

# Check if user has sudo access (cached result)
_sudo_checked=""
_has_sudo=""
can_sudo() {
    if [[ -z "${_sudo_checked}" ]]; then
        _sudo_checked=1
        if sudo -n true 2>/dev/null; then
            _has_sudo=1
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
        if ssh -i "${key_file}" -o StrictHostKeyChecking=accept-new -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
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
        if ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
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
        if ssh -i ~/.ssh/dotfiles-deploy-key -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
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

# Verify we're running on Arch/Omarchy
verify_arch_system() {
    print_message "Verifying Arch Linux or Omarchy system..."
    
    if [[ ! -f /etc/arch-release ]]; then
        print_error "This script is designed for Arch Linux or Omarchy systems only."
        print_message "Detected system:"
        if [[ -f /etc/os-release ]]; then
            grep "PRETTY_NAME" /etc/os-release
        fi
        exit 1
    fi
    
    print_success "Arch Linux system confirmed."
}

# Check if system is already Omarchy
check_omarchy_installation() {
    if command -v omarchy-pkg-install &> /dev/null; then
        print_success "Omarchy environment detected."
        export IS_OMARCHY=true
    else
        print_message "Standard Arch Linux detected."
        export IS_OMARCHY=false
    fi
}

# Update system packages
update_system() {
    if ! can_sudo; then
        print_warning "No sudo access - skipping system updates."
        print_debug "Run 'sudo pacman -Syu' manually when you have admin access."
        return
    fi

    print_message "Updating system packages..."

    # Update pacman database
    sudo pacman -Sy --noconfirm

    # Update all packages
    if ! sudo pacman -Syu --noconfirm; then
        print_error "Failed to update system packages."
        exit 1
    fi

    print_success "System packages updated."
}

# Install and configure fail2ban for brute-force protection
install_fail2ban() {
    if ! can_sudo; then
        print_warning "No sudo access - skipping fail2ban installation."
        return
    fi

    if pacman -Qi fail2ban &> /dev/null; then
        print_debug "fail2ban is already installed."
        # Ensure service is enabled
        if ! systemctl is-enabled fail2ban &> /dev/null; then
            sudo systemctl enable fail2ban
            sudo systemctl start fail2ban
            print_success "fail2ban service enabled."
        fi
        return
    fi

    print_message "Installing fail2ban..."
    if sudo pacman -S --noconfirm fail2ban; then
        # Enable and start fail2ban service
        sudo systemctl enable fail2ban
        sudo systemctl start fail2ban
        print_success "fail2ban installed and enabled."
    else
        print_error "Failed to install fail2ban."
    fi
}

# Install core packages using pacman
install_core_packages() {
    print_message "Checking core packages..."

    # Define core packages
    local packages=("git" "curl" "fish" "tmux" "base-devel" "wget" "unzip" "github-cli" "starship" "openssh" "opentofu" "jujutsu" "uv")
    local to_install=()

    # Check which packages need installation
    for package in "${packages[@]}"; do
        if ! pacman -Qi "${package}" &> /dev/null; then
            to_install+=("${package}")
        else
            print_debug "${package} is already installed."
        fi
    done

    # Install missing packages
    if [[ "${#to_install[@]}" -gt 0 ]]; then
        if ! can_sudo; then
            print_warning "No sudo access - cannot install missing packages: ${to_install[*]}"
            print_debug "Ask an admin to run: sudo pacman -S ${to_install[*]}"
            return
        fi
        print_message "Installing missing packages: ${to_install[*]}"
        if ! sudo pacman -S --noconfirm "${to_install[@]}"; then
            print_error "Failed to install core packages."
            exit 1
        fi
        print_success "Core packages installed."
    else
        print_success "All core packages are already installed."
    fi
}

# Install yay AUR helper if not present
install_yay() {
    if command -v yay &> /dev/null; then
        print_debug "yay AUR helper is already installed."
        return
    fi
    
    print_message "Installing yay AUR helper..."
    
    # Create temporary directory
    local temp_dir
    temp_dir=$(mktemp -d)
    cd "${temp_dir}" || exit 1
    
    # Clone and install yay
    if git clone https://aur.archlinux.org/yay.git; then
        cd yay || exit 1
        if makepkg -si --noconfirm; then
            print_success "yay AUR helper installed."
        else
            print_error "Failed to build yay."
            cd ~ && rm -rf "${temp_dir}"
            exit 1
        fi
    else
        print_error "Failed to clone yay repository."
        cd ~ && rm -rf "${temp_dir}"
        exit 1
    fi
    
    # Cleanup
    cd ~ && rm -rf "${temp_dir}"
}

# Install Omarchy if not already installed
install_omarchy() {
    if [[ "${IS_OMARCHY}" = true ]]; then
        print_debug "Omarchy is already installed."
        return
    fi
    
    print_message "Installing Omarchy environment..."
    print_warning "This will install the complete Omarchy Hyprland desktop environment."
    
    # Confirm installation
    read -rp "Do you want to proceed with Omarchy installation? (y/N): " confirm
    if [[ ! "${confirm}" =~ ^[Yy]$ ]]; then
        print_message "Skipping Omarchy installation."
        return
    fi
    
    # Install Omarchy
    local install_cmd
    install_cmd=$(curl -sSL https://omarchy.org/install)
    if bash <<< "${install_cmd}"; then
        print_success "Omarchy environment installed."
        export IS_OMARCHY=true
    else
        print_error "Failed to install Omarchy."
        return 1
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
            print_message "Opening GitHub SSH keys page..."
            xdg-open "https://github.com/settings/keys" 2>/dev/null || true
            exit 1
        fi
    else
        print_warning "No SSH key found. Generating a new SSH key..."
        ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
        print_success "SSH key generated."
        print_message "Please add the following SSH key to GitHub:"
        cat ~/.ssh/id_rsa.pub
        print_message "Opening GitHub SSH keys page..."
        xdg-open "https://github.com/settings/keys" 2>/dev/null || true
        exit 1
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
            exit 1
        fi
        print_success "GitHub's SSH key added."
    else
        print_debug "GitHub's SSH key already exists in known_hosts."
    fi
}

# Install development tools via AUR
install_dev_tools_aur() {
    print_message "Installing development tools from AUR..."

    # Development tools available in AUR
    local aur_packages=("fnm-bin" "chezmoi" "1password-cli" "tailscale" "infisical" "act")
    local to_install=()

    # Check which packages need installation
    for package in "${aur_packages[@]}"; do
        # Special case: fnm-bin and fnm are alternatives that provide the same command
        if [[ "${package}" == "fnm-bin" ]]; then
            if pacman -Qi "fnm-bin" &> /dev/null || pacman -Qi "fnm" &> /dev/null; then
                print_debug "fnm is already installed."
            else
                to_install+=("${package}")
            fi
        # Special case: infisical and infisical-bin are alternatives
        elif [[ "${package}" == "infisical" ]]; then
            if pacman -Qi "infisical" &> /dev/null || pacman -Qi "infisical-bin" &> /dev/null; then
                print_debug "infisical is already installed."
            else
                to_install+=("${package}")
            fi
        elif ! pacman -Qi "${package}" &> /dev/null; then
            to_install+=("${package}")
        else
            print_debug "${package} is already installed."
        fi
    done
    
    # Install missing packages via yay
    if [[ "${#to_install[@]}" -gt 0 ]]; then
        print_message "Installing AUR packages: ${to_install[*]}"
        if ! yay -S --noconfirm "${to_install[@]}"; then
            print_warning "Some AUR packages failed to install. Continuing..."
        else
            print_success "AUR development tools installed."
        fi
    else
        print_success "All AUR development tools are already installed."
    fi
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
    if curl -sL "${download_url}" > "${temp_dir}/git-town.tar.gz" && tar -xz -C "${temp_dir}" -f "${temp_dir}/git-town.tar.gz"; then
        if mv "${temp_dir}/git-town" "${bin_dir}/git-town"; then
            chmod +x "${bin_dir}/git-town"
            print_success "git-town installed to ${bin_dir}/git-town"
            
            # Add to PATH if not already present
            if ! echo "${PATH}" | grep -q "${bin_dir}"; then
                print_message "Adding ${bin_dir} to PATH in ~/.bashrc"
                echo "export PATH=\$HOME/.local/bin:\$PATH" >> ~/.bashrc
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
                git-town completions fish > ~/.config/fish/completions/git-town.fish
                print_success "git-town Fish completions configured."
            else
                print_debug "git-town Fish completions already configured."
            fi
        fi

        # Set up Bash completions for git-town (requires sudo for system-wide install)
        local bash_completion_dir="/etc/bash_completion.d"
        if [[ -d "${bash_completion_dir}" ]]; then
            if ! [[ -f "${bash_completion_dir}/git-town" ]]; then
                if can_sudo; then
                    local completion_content
                    completion_content=$(git-town completions bash)
                    echo "${completion_content}" | sudo tee "${bash_completion_dir}/git-town" > /dev/null
                    print_success "git-town Bash completions configured."
                else
                    print_debug "No sudo access - skipping system-wide Bash completions."
                fi
            else
                print_debug "git-town Bash completions already configured."
            fi
        fi
    else
        print_warning "git-town not found, skipping completion setup."
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
        if is_main_user; then
            # Main user uses SSH with default key for push access
            if ! chezmoi init --apply --force scowalt/dotfiles --ssh; then
                print_error "Failed to initialize chezmoi."
                exit 1
            fi
        else
            # Secondary users use SSH via deploy key (github-dotfiles alias)
            if ! chezmoi init --apply --force "git@github-dotfiles:scowalt/dotfiles.git"; then
                print_error "Failed to initialize chezmoi."
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
        sudo chsh -s /usr/bin/fish "${USER}"
        print_success "Fish shell set as default."
    else
        print_debug "Fish shell is already the default shell."
    fi
}

# Setup Node.js using fnm
setup_nodejs() {
    print_message "Setting up Node.js with fnm..."
    
    # Initialize fnm for current session
    if command -v fnm &> /dev/null; then
        local fnm_env
        fnm_env=$(fnm env --use-on-cd)
        eval "${fnm_env}"
    else
        print_warning "fnm command not available. Skipping Node.js setup."
        return
    fi
    
    # Check if any Node.js version is installed
    local fnm_output
    fnm_output=$(fnm list)
    local filtered_fnm
    filtered_fnm=$(echo "${fnm_output}" | grep -v "system")
    if echo "${filtered_fnm}" | grep -q "v[0-9]"; then
        print_debug "Node.js version already installed."
        
        # Check if a default/global version is set
        local current_version
        current_version=$(fnm current 2>/dev/null || echo "none")
        if [[ "${current_version}" != "none" ]] && [[ -n "${current_version}" ]]; then
            print_debug "Global Node.js version already set: ${current_version}"
        else
            print_message "Setting the first installed version as default..."
            local first_version
            local fnm_list_output
            fnm_list_output=$(fnm list)
            local version_lines
            version_lines=$(echo "${fnm_list_output}" | grep -E "^[[:space:]]*\*?[[:space:]]*v[0-9]")
            local first_line
            first_line=$(echo "${version_lines}" | head -n1)
            local cleaned_line
            # Remove leading whitespace and optional asterisk
            cleaned_line="${first_line#"${first_line%%[![:space:]]*}"}"  # Remove leading whitespace
            cleaned_line="${cleaned_line#\*}"  # Remove optional asterisk
            cleaned_line="${cleaned_line#"${cleaned_line%%[![:space:]]*}"}"  # Remove any remaining leading whitespace
            first_version=$(echo "${cleaned_line}" | awk '{print $1}')
            if [[ -n "${first_version}" ]]; then
                fnm default "${first_version}"
                print_success "Set ${first_version} as default Node.js version."
            fi
        fi
    else
        print_message "Installing latest LTS Node.js..."
        if fnm install --lts; then
            print_success "Installed latest LTS Node.js."
            local current_node
            current_node=$(fnm current)
            fnm default "${current_node}"
            print_success "Set ${current_node} as default Node.js version."
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

    # Use the native installer (doesn't require Node.js)
    # Download to temp file and execute (more reliable than piping when run via curl|bash)
    local temp_script
    temp_script=$(mktemp)
    if curl -fsSL https://claude.ai/install.sh -o "${temp_script}"; then
        chmod +x "${temp_script}"
        if bash "${temp_script}"; then
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

# Install pyenv for Python version management
install_pyenv() {
    if ! command -v pyenv &> /dev/null; then
        # Check if ~/.pyenv exists but pyenv is not in PATH
        if [[ -d "${HOME}/.pyenv" ]]; then
            # Try to add pyenv to PATH
            export PATH="${HOME}/.pyenv/bin:${PATH}"
            if command -v pyenv &> /dev/null; then
                print_debug "pyenv is already installed (added to PATH)."
                return 0
            else
                print_warning "\$HOME/.pyenv directory exists but pyenv not functional."
                print_message "Please check your pyenv installation or remove \$HOME/.pyenv and rerun."
                return 1
            fi
        fi

        print_message "Installing pyenv..."
        # Use the official install script
        local install_cmd
        install_cmd=$(curl -L https://github.com/pyenv/pyenv-installer/raw/master/bin/pyenv-installer)
        if bash <<< "${install_cmd}"; then
            export PATH="${HOME}/.pyenv/bin:${PATH}"
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

# Update all packages
update_all_packages() {
    print_message "Updating all packages..."

    if can_sudo; then
        # Update Arch packages (requires sudo)
        sudo pacman -Syu --noconfirm

        # Update AUR packages if yay is available (yay internally uses sudo)
        if command -v yay &> /dev/null; then
            yay -Syu --noconfirm
        fi

        # Update Omarchy if installed
        if [[ "${IS_OMARCHY}" = true ]] && command -v omarchy-update-system-pkgs &> /dev/null; then
            omarchy-update-system-pkgs
        fi
    else
        print_warning "No sudo access - skipping system package updates."
    fi

    print_success "Package updates completed."
}

# Upgrade global npm packages
upgrade_npm_global_packages() {
    # Initialize fnm for current session
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
echo -e "\n${BOLD}🏛️ Omarchy/Arch Linux Development Environment Setup${NC}"
echo -e "${GRAY}Version 41 | Last changed: Fix Claude Code PATH (uses ~/.local/bin not ~/.claude/bin)${NC}"

print_section "System Verification"
verify_arch_system
check_omarchy_installation
setup_dns64_for_ipv6_only

print_section "System Updates"
update_system

print_section "Core Package Installation"
install_core_packages
install_yay

print_section "SSH Configuration"
setup_ssh_key
add_github_to_known_hosts

if is_main_user; then
    print_section "Code Directory Setup"
    setup_code_directory
fi

print_section "Security Tools"
install_fail2ban

print_section "Development Environment"
install_omarchy
install_dev_tools_aur
install_git_town
configure_git_town

print_section "Development Tools"
setup_nodejs
install_claude_code
install_pyenv

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
    update_chezmoi
    chezmoi apply --force
    tmux source ~/.tmux.conf 2>/dev/null || true
else
    print_warning "Skipping dotfiles management - no access to repository."
fi

print_section "Shell Configuration"
set_fish_as_default_shell
install_tmux_plugins
install_iterm2_shell_integration

print_section "Final Updates"
update_all_packages
upgrade_npm_global_packages

echo -e "\n${GREEN}${BOLD}✨ Setup complete!${NC}\n"