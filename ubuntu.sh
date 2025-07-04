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
    if [ "$(whoami)" != "scowalt" ]; then
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
    local packages=("git" "curl" "fish" "tmux" "fonts-firacode" "gh" "git-town" "build-essential" "libssl-dev" "zlib1g-dev" "libbz2-dev" "libreadline-dev" "libsqlite3-dev" "wget" "llvm" "libncurses5-dev" "libncursesw5-dev" "xz-utils" "tk-dev" "libffi-dev" "liblzma-dev")
    local to_install=()

    # Check each package and add missing ones to the to_install array
    for package in "${packages[@]}"; do
        if ! dpkg -s "$package" &> /dev/null; then
            to_install+=("$package")
        else
            print_debug "$package is already installed."
        fi
    done

    # Install any packages that are not yet installed
    if [ "${#to_install[@]}" -gt 0 ]; then
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
    if [ -f ~/.ssh/id_rsa.pub ]; then
        # Extract only the actual key part from id_rsa.pub and log for debugging
        local local_key
        local_key=$(awk '{print $2}' ~/.ssh/id_rsa.pub)

        # Verify if the extracted key part matches any of the GitHub keys
        if echo "$existing_keys" | grep -q "$local_key"; then
            print_success "Existing SSH key recognized by GitHub."
        else
            print_error "SSH key not recognized by GitHub. Please add it manually."
            exit 1
        fi
    else
        # Generate a new SSH key and log details
        print_warning "No SSH key found. Generating a new SSH key..."
        ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N "" -C "scowalt@$(hostname)"
        print_success "SSH key generated."
        print_message "Please add the following SSH key to GitHub:"
        cat ~/.ssh/id_rsa.pub
        exit 1
    fi
}

# Add GitHub to known hosts to avoid prompts
add_github_to_known_hosts() {
    print_message "Ensuring GitHub is in known hosts..."
    local known_hosts_file=~/.ssh/known_hosts
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    touch "$known_hosts_file"
    chmod 600 "$known_hosts_file"

    if ! ssh-keygen -F github.com &>/dev/null; then
        print_message "Adding GitHub's SSH key to known_hosts..."
        if ! ssh-keyscan github.com >> "$known_hosts_file" 2>/dev/null; then
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
        sh -c "$(curl -fsSL https://starship.rs/install.sh)" -- -y
        print_success "Starship installed."
    else
        print_debug "Starship is already installed."
    fi
}

# Install Infisical if not installed
install_infisical() {
    if ! command -v infisical &> /dev/null; then
        print_message "Installing Infisical CLI..."
        if ! (curl -1sLf 'https://artifacts-cli.infisical.com/setup.deb.sh' | sudo -E bash); then
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
        local bin_dir="$HOME/.local/bin"
        mkdir -p "$bin_dir"
        if (sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$bin_dir"); then
            # Add bin_dir to PATH for the current script session
            export PATH="$bin_dir:$PATH"
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
    if [ ! -d ~/.local/share/chezmoi ]; then
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
    if [ ! -f "$chezmoi_config" ]; then
        print_message "Configuring chezmoi with auto-commit, auto-push, and auto-pull..."
        mkdir -p ~/.config/chezmoi
        cat <<EOF > "$chezmoi_config"
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
    if [ "$(getent passwd "$USER" | cut -d: -f7)" != "/usr/bin/fish" ]; then
        print_message "Setting Fish as the default shell..."
        if ! grep -Fxq "/usr/bin/fish" /etc/shells; then
            echo "/usr/bin/fish" | sudo tee -a /etc/shells > /dev/null
        fi
        sudo chsh -s /usr/bin/fish "$USER"
        print_success "Fish shell set as default."
    else
        print_debug "Fish shell is already the default shell."
    fi
}

# Configure git-town completions
configure_git_town() {
    if command -v git-town &> /dev/null; then
        print_message "Configuring git-town completions..."
        
        # Set up Fish shell completions for git-town
        if [ -d ~/.config/fish/completions ]; then
            if ! [ -f ~/.config/fish/completions/git-town.fish ]; then
                git town completion fish > ~/.config/fish/completions/git-town.fish
                print_success "git-town Fish completions configured."
            else
                print_debug "git-town Fish completions already configured."
            fi
        fi
        
        # Set up Bash completions for git-town
        local bash_completion_dir="/etc/bash_completion.d"
        if [ -d "$bash_completion_dir" ]; then
            if ! [ -f "$bash_completion_dir/git-town" ]; then
                git town completion bash | sudo tee "$bash_completion_dir/git-town" > /dev/null
                print_success "git-town Bash completions configured."
            else
                print_debug "git-town Bash completions already configured."
            fi
        fi
    else
        print_warning "git-town not found, skipping completion setup."
    fi
}

# Install Claude Code via npm
install_claude_code() {
    if command -v claude &> /dev/null; then
        print_debug "Claude Code is already installed."
        return
    fi
    
    print_message "Installing Claude Code..."
    
    # Source fnm initialization to make npm available
    if [ -s "$HOME/.local/share/fnm/fnm" ]; then
        export PATH="$HOME/.local/share/fnm:$PATH"
        eval "$(fnm env --use-on-cd)"
    fi
    
    # Make sure npm is available
    if ! command -v npm &> /dev/null; then
        print_warning "npm not found. Make sure fnm is installed and Node.js is set up."
        print_message "You may need to install Claude Code manually after setting up Node.js:"
        print_message "  npm install -g @anthropic-ai/claude-code"
        return
    fi
    
    # Install Claude Code globally via npm
    if npm install -g @anthropic-ai/claude-code &> /dev/null; then
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
    curl -fsSL https://fnm.vercel.app/install | bash
    print_success "fnm installed. Shell configuration will be managed by chezmoi."
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
    curl -sS https://downloads.1password.com/linux/keys/1password.asc \
      | sudo gpg --dearmor --output /usr/share/keyrings/1password-archive-keyring.gpg

    # Figure out repo path for the current CPU architecture
    local dpkg_arch
    dpkg_arch="$(dpkg --print-architecture)"       # arm64, armhf, amd64…
    local repo_arch="$dpkg_arch"
    [[ "$dpkg_arch" == "armhf" ]] && repo_arch="arm"   # 32-bit Pi

    # Add repo
    echo \
"deb [arch=$dpkg_arch signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] \
https://downloads.1password.com/linux/debian/${repo_arch} stable main" \
        | sudo tee /etc/apt/sources.list.d/1password-cli.list >/dev/null

    # Add debsig-verify policy (required for future updates)
    sudo mkdir -p /etc/debsig/policies/AC2D62742012EA22/
    curl -sS https://downloads.1password.com/linux/debsig/1password.pol \
      | sudo tee /etc/debsig/policies/AC2D62742012EA22/1password.pol >/dev/null
    curl -sS https://downloads.1password.com/linux/keys/1password.asc \
      | sudo tee /etc/debsig/keys/AC2D62742012EA22.asc >/dev/null

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
        curl -fsSL https://tailscale.com/install.sh | sudo sh
        sudo systemctl enable --now tailscaled
        print_success "Tailscale installed and service started."

        # Optional immediate login
        read -rp "Run 'tailscale up' now to authenticate? (y/n): " ts_up
        if [[ "$ts_up" =~ ^[Yy]$ ]]; then
            print_message "Bringing interface up..."
            sudo tailscale up       # add --authkey=... if you prefer key-based auth
        else
            print_warning "Skip for now; run 'sudo tailscale up' later to log in."
        fi
    else
        print_debug "Tailscale already installed."
    fi
}

# Install act for running GitHub Actions locally
install_act() {
    if ! command -v act &> /dev/null; then
        print_message "Installing act (GitHub Actions runner)..."
        # Use the official install script
        if ! (curl -s https://raw.githubusercontent.com/nektos/act/master/install.sh | sudo bash); then
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
        print_message "Installing pyenv..."
        # Use the official install script
        curl -L https://github.com/pyenv/pyenv-installer/raw/master/bin/pyenv-installer | bash
        print_success "pyenv installed. Shell configuration will be managed by chezmoi."
    else
        print_debug "pyenv is already installed."
    fi
}

# Install tmux plugins for session persistence
install_tmux_plugins() {
    local plugin_dir=~/.tmux/plugins
    if [ ! -d "$plugin_dir/tpm" ]; then
        print_message "Installing tmux plugin manager..."
        git clone -q https://github.com/tmux-plugins/tpm "$plugin_dir/tpm"
        print_success "tmux plugin manager installed."
    else
        print_debug "tmux plugin manager already installed."
    fi

    print_message "Installing/updating tmux plugins via tpm..."
    local tpm_installer=~/.tmux/plugins/tpm/bin/install_plugins
    
    # Let tpm script install plugins. It handles finding tmux.conf and starting a server.
    # Capture output to show only on failure.
    local output
    if ! output=$($tpm_installer 2>&1); then
        print_error "Failed to install tmux plugins. tpm output was:"
        echo "$output"
        # Not exiting, to maintain original script's behavior.
        return
    fi

    # Try to source the config to make plugins available in a running session.
    # This might fail if tmux server is not running, which is fine.
    local tmux_conf="$HOME/.config/tmux/tmux.conf"
    if [ -f "$tmux_conf" ]; then
        tmux source-file "$tmux_conf" >/dev/null 2>&1
    elif [ -f "$HOME/.tmux.conf" ]; then # fallback to old location
        tmux source-file "$HOME/.tmux.conf" >/dev/null 2>&1
    fi
    print_success "tmux plugins installed and updated."
}


printf "\n%s🐧 Ubuntu Development Environment Setup%s\n" "${BOLD}" "${NC}"
printf "%sVersion 14 | Last changed: Add Claude Code installation after chezmoi apply%s\n" "${GRAY}" "${NC}"

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
configure_git_town
install_fnm
install_pyenv

print_section "Security Tools"
install_1password_cli
install_tailscale
install_infisical

print_section "Dotfiles Management"
install_chezmoi
initialize_chezmoi
configure_chezmoi_git
chezmoi apply

print_section "Shell Configuration"
set_fish_as_default_shell
install_act
install_tmux_plugins

print_section "Additional Development Tools"
install_claude_code

printf "\n%s%s✨ Setup complete!%s\n\n" "${GREEN}" "${BOLD}" "${NC}"
