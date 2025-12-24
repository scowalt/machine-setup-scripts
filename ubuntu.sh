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

# Fix dpkg interruptions if they exist
fix_dpkg_and_broken_dependencies() {
    print_message "Checking for and fixing dpkg interruptions or broken dependencies..."
    # The following commands will fix most common dpkg/apt issues.
    # They are safe to run even if there are no issues.
    sudo DEBIAN_FRONTEND=noninteractive dpkg --force-confold --configure -a
    sudo DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::="--force-confold" install -f -y
    print_success "dpkg and dependencies check/fix complete."
}

# Enforce that the script is run as the 'scowalt' user
enforce_scowalt_user() {
    local current_user
    current_user=$(whoami)
    if [[ "${current_user}" != "scowalt" ]]; then
        print_error "This script must be run as the 'scowalt' user for security reasons."

        # Check if the 'scowalt' user exists
        if ! id "scowalt" &>/dev/null; then
            print_message "User 'scowalt' not found. Creating user..."
            sudo useradd --create-home --shell /bin/bash scowalt
            sudo usermod -aG sudo scowalt
            print_success "User 'scowalt' created and added to the sudo group."
            print_warning "A password must be set for 'scowalt' to continue."
            print_message "Please run 'sudo passwd scowalt' to set a password."
            print_message "Then, switch to the 'scowalt' user and re-run this script."
        else
            print_warning "User 'scowalt' already exists."
            print_message "Please switch to the 'scowalt' user and re-run this script."
        fi

        exit 1
    else
        print_success "Running as 'scowalt' user. Proceeding with setup."
    fi

    cd ~ || exit 1
}

# Update dependencies non-silently
update_dependencies() {
    print_message "Updating package lists..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get update
    sudo DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::="--force-confold" upgrade -y
    sudo DEBIAN_FRONTEND=noninteractive apt-get autoremove -y
    print_success "Package lists updated."
}

# Update and install core dependencies silently
update_and_install_core() {
    print_message "Checking and installing core packages as needed..."

    # Define an array of required packages
    local packages=("git" "curl" "fish" "tmux" "fonts-firacode" "gh" "build-essential" "libssl-dev" "zlib1g-dev" "libbz2-dev" "libreadline-dev" "libsqlite3-dev" "wget" "unzip" "llvm" "libncurses5-dev" "libncursesw5-dev" "xz-utils" "tk-dev" "libffi-dev" "liblzma-dev")
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

# Install Infisical if not installed
install_infisical() {
    if ! command -v infisical &> /dev/null; then
        print_message "Installing Infisical CLI..."
        local infisical_setup
        infisical_setup=$(curl -1sLf 'https://artifacts-cli.infisical.com/setup.deb.sh')
        if ! echo "${infisical_setup}" | sudo -E bash; then
            print_error "Failed to add Infisical repository."
            exit 1
        fi
        sudo DEBIAN_FRONTEND=noninteractive apt-get update
        if ! sudo DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::="--force-confold" install -y infisical; then
            print_error "Failed to install Infisical CLI. Please review the output above."
            exit 1
        fi
        print_success "Infisical CLI installed."
    else
        print_debug "Infisical CLI is already installed."
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
    if [[ ! -d ~/.local/share/chezmoi ]]; then
        print_message "Initializing chezmoi with scowalt/dotfiles..."
        if ! chezmoi init --apply scowalt/dotfiles --ssh; then
            print_error "Failed to initialize chezmoi. Please review the output above."
            exit 1
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
        if chezmoi update > /dev/null; then
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

# Install git-town by downloading binary directly
install_git_town() {
    if command -v git-town &> /dev/null; then
        print_debug "git-town is already installed."
        return
    fi

    print_message "Installing git-town via direct binary download..."
    
    # For Ubuntu, we typically use amd64
    local arch
    arch=$(dpkg --print-architecture)
    local git_town_arch
    
    case "${arch}" in
        amd64)
            git_town_arch="linux_intel_64"
            ;;
        arm64)
            git_town_arch="linux_arm_64"
            ;;
        armhf)
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
    local download_result
    download_result=$(curl -sL "${download_url}")
    if echo "${download_result}" | tar -xz -C "${temp_dir}"; then
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

# Install Claude Code using official installer
install_claude_code() {
    if command -v claude &> /dev/null; then
        print_debug "Claude Code is already installed."
        return
    fi

    print_message "Installing Claude Code..."

    local install_script
    install_script=$(curl -fsSL https://claude.ai/install.sh)
    if echo "${install_script}" | bash; then
        print_success "Claude Code installed."
    else
        print_error "Failed to install Claude Code."
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
        
        # Check if a default/global version is set
        local current_version
        current_version=$(fnm current 2>/dev/null || echo "none")
        if [[ "${current_version}" != "none" ]] && [[ -n "${current_version}" ]]; then
            print_debug "Global Node.js version already set: ${current_version}"
        else
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
            
            print_debug "Found version to set as default: '${first_version}'"
            
            if [[ -n "${first_version}" ]]; then
                print_debug "Attempting to set default version to: ${first_version}"
                if fnm default "${first_version}"; then
                    print_success "Set ${first_version} as default Node.js version."
                    # Re-initialize fnm to pick up the new default
                    local fnm_env
                    fnm_env=$("${HOME}"/.local/share/fnm/fnm env --use-on-cd)
                    eval "${fnm_env}"
                else
                    print_error "Failed to set default Node.js version. You may need to run: fnm default ${first_version}"
                fi
            else
                print_warning "No Node.js versions found (only system version available)."
                print_message "Installing Node.js LTS version..."
                if fnm install --lts; then
                    print_success "Installed latest LTS Node.js."
                    # Get the version that was just installed
                    local installed_version
                    local installed_fnm_versions
                    installed_fnm_versions=$(fnm list)
                    local installed_version_lines
                    installed_version_lines=$(echo "${installed_fnm_versions}" | grep -E "^[[:space:]]*\*?[[:space:]]*v[0-9]")
                    local installed_first_line
                    installed_first_line=$(echo "${installed_version_lines}" | head -n1)
                    local installed_cleaned_line
                    # Remove leading whitespace and optional asterisk
                    installed_cleaned_line="${installed_first_line#"${installed_first_line%%[![:space:]]*}"}"
                    installed_cleaned_line="${installed_cleaned_line#\*}"
                    installed_cleaned_line="${installed_cleaned_line#"${installed_cleaned_line%%[![:space:]]*}"}"
                    installed_version=$(echo "${installed_cleaned_line}" | awk '{print $1}')
                    if [[ -n "${installed_version}" ]]; then
                        fnm default "${installed_version}"
                        print_success "Set ${installed_version} as default Node.js version."
                        local installed_fnm_env
                        installed_fnm_env=$("${HOME}"/.local/share/fnm/fnm env --use-on-cd)
                        eval "${installed_fnm_env}"
                    fi
                else
                    print_error "Failed to install Node.js LTS version."
                    print_message "You may need to manually install Node.js with: fnm install --lts"
                    print_message "Then set it as default with: fnm default <version>"
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
    if ! command -v tailscale &>/dev/null; then
        print_message "Installing Tailscale..."
        # Official install script (adds repo + installs package)
        local tailscale_install
        tailscale_install=$(curl -fsSL https://tailscale.com/install.sh)
        echo "${tailscale_install}" | sudo sh
        sudo systemctl enable --now tailscaled
        print_success "Tailscale installed and service started."

        # Optional immediate login
        read -rp "Run 'tailscale up' now to authenticate? (y/n): " ts_up
        if [[ "${ts_up}" =~ ^[Yy]$ ]]; then
            print_message "Bringing interface up..."
            sudo tailscale up       # add --authkey=... if you prefer key-based auth
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


echo -e "\n${BOLD}🐧 Ubuntu Development Environment Setup${NC}"
echo -e "${GRAY}Version 34 | Last changed: Add unattended-upgrades for automatic security updates${NC}"

print_section "User & System Setup"
enforce_scowalt_user
fix_dpkg_and_broken_dependencies

print_section "System Updates"
update_dependencies # I do this first b/c on raspberry pi, it's slow
update_and_install_core

print_section "SSH Configuration"
setup_ssh_server
setup_ssh_key
add_github_to_known_hosts

print_section "Development Tools"
install_starship
install_git_town
configure_git_town
install_fnm
setup_nodejs
install_pyenv

print_section "Security Tools"
install_1password_cli
install_tailscale
install_infisical
install_fail2ban
setup_unattended_upgrades

print_section "Dotfiles Management"
install_chezmoi
initialize_chezmoi
configure_chezmoi_git
update_chezmoi
chezmoi apply

print_section "Shell Configuration"
set_fish_as_default_shell
install_act
install_tmux_plugins
enable_tmux_service
install_iterm2_shell_integration

print_section "Additional Development Tools"
install_claude_code

print_section "Final Updates"
upgrade_npm_global_packages

echo -e "\n${GREEN}${BOLD}✨ Setup complete!${NC}\n"
