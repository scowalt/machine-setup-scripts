#!/bin/bash

# Define colors
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Print functions for readability
print_message() { printf "${CYAN} %s${NC}\n" "$1"; }
print_success() { printf "${GREEN} %s${NC}\n" "$1"; }
print_warning() { printf "${YELLOW} %s${NC}\n" "$1"; }
print_error() { printf "${RED} %s${NC}\n" "$1"; }

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
    local packages=("git" "curl" "fish" "tmux" "fonts-firacode" "gh")
    local to_install=()

    # Check each package and add missing ones to the to_install array
    for package in "${packages[@]}"; do
        if ! dpkg -s "$package" &> /dev/null; then
            to_install+=("$package")
        else
            print_warning "$package is already installed."
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
        print_warning "openssh-server is already installed."
    fi

    # Check if ssh service is active
    if ! systemctl is-active --quiet ssh; then
        print_message "Starting ssh service..."
        sudo systemctl start ssh
        print_success "ssh service started."
    else
        print_warning "ssh service is already active."
    fi

    # Check if ssh service is enabled to start on boot
    if ! systemctl is-enabled --quiet ssh; then
        print_message "Enabling ssh service to start on boot..."
        sudo systemctl enable ssh
        print_success "ssh service enabled."
    else
        print_warning "ssh service is already enabled."
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
        print_warning "GitHub's SSH key already exists in known_hosts."
    fi
}

# Install Starship if not installed
install_starship() {
    if ! command -v starship &> /dev/null; then
        print_message "Installing Starship prompt..."
        sh -c "$(curl -fsSL https://starship.rs/install.sh)" -- -y
        print_success "Starship installed."
    else
        print_warning "Starship is already installed."
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
        print_warning "Infisical CLI is already installed."
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
        print_warning "chezmoi is already installed."
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
        print_warning "chezmoi is already initialized."
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
        print_warning "chezmoi configuration already exists."
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
        print_warning "Fish shell is already the default shell."
    fi
}

# Install fnm (Fast Node Manager)
install_fnm() {
    if command -v fnm &> /dev/null; then
        print_warning "fnm already installed."
        return
    fi

    print_message "Installing fnm (Fast Node Manager)..."
    curl -fsSL https://fnm.vercel.app/install | bash

    # fnm's installer drops a snippet in ~/.bashrc; make sure Fish picks it up too
    if [ -d ~/.config/fish/conf.d ]; then
        # only add once
        if ! grep -q "fnm env" ~/.config/fish/conf.d/fnm.fish 2>/dev/null; then
            cat <<'EOF' > ~/.config/fish/conf.d/fnm.fish
# auto-generated by setup script
fnm env | source
EOF
        fi
    fi

    print_success "fnm installed. Restart your shell or run 'eval \"$(fnm env)\"' to activate it now."
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
        read -p "Run 'tailscale up' now to authenticate? (y/n): " ts_up
        if [[ "$ts_up" =~ ^[Yy]$ ]]; then
            print_message "Bringing interface up..."
            sudo tailscale up       # add --authkey=... if you prefer key-based auth
        else
            print_warning "Skip for now; run 'sudo tailscale up' later to log in."
        fi
    else
        print_warning "Tailscale already installed."
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
        print_warning "tmux plugin manager already installed."
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


print_message "Setup script v6"
enforce_scowalt_user
fix_dpkg_and_broken_dependencies
update_dependencies # I do this first b/c on raspberry pi, it's slow
update_and_install_core
setup_ssh_server
setup_ssh_key
add_github_to_known_hosts
install_starship
install_fnm
install_tailscale
install_infisical
install_chezmoi
initialize_chezmoi
configure_chezmoi_git
chezmoi apply
set_fish_as_default_shell
install_tmux_plugins
