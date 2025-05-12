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

# Install core packages with Homebrew if missing
install_core_packages() {
    print_message "Checking and installing core packages as needed..."

    # Define an array of required packages
    local packages=("git" "curl" "fish" "tmux" "1password-cli" "gh" "chezmoi" "starship")
    local to_install=()

    # Check each package and add missing ones to the to_install array
    for package in "${packages[@]}"; do
        if ! brew list "$package" &> /dev/null; then
            to_install+=("$package")
        else
            print_warning "$package is already installed."
        fi
    done

    # Install any packages that are not yet installed
    if [ "${#to_install[@]}" -gt 0 ]; then
        print_message "Installing missing packages: ${to_install[*]}"
        brew install "${to_install[@]}" > /dev/null
        print_success "Missing core packages installed."
    else
        print_success "All core packages are already installed."
    fi
}

# Check and set up SSH key
setup_ssh_key() {
    print_message "Checking for existing SSH key associated with GitHub..."

    # Retrieve GitHub-associated keys
    local existing_keys
    existing_keys=$(curl -s https://github.com/scowalt.keys)

    if [ -f ~/.ssh/id_rsa.pub ]; then
        local local_key
        local_key=$(awk '{print $2}' ~/.ssh/id_rsa.pub)

        if echo "$existing_keys" | grep -q "$local_key"; then
            print_success "Existing SSH key recognized by GitHub."
        else
            print_error "SSH key not recognized by GitHub. Please add it manually."
            exit 1
        fi
    else
        print_warning "No SSH key found. Generating a new SSH key..."
        ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
        print_success "SSH key generated."
        print_message "Please add the following SSH key to GitHub:"
        cat ~/.ssh/id_rsa.pub
        exit 1
    fi
}

# Install Homebrew if not installed
install_homebrew() {
    if ! command -v brew &> /dev/null; then
        print_message "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" > /dev/null
        eval "$(/opt/homebrew/bin/brew shellenv)"
        print_success "Homebrew installed."
    else
        print_warning "Homebrew is already installed."
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
}

# Initialize chezmoi if not already initialized
initialize_chezmoi() {
    if [ ! -d ~/.local/share/chezmoi ]; then
        print_message "Initializing chezmoi with scowalt/dotfiles..."
        chezmoi init --apply scowalt/dotfiles --ssh > /dev/null
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
    if [ "$SHELL" != "/opt/homebrew/bin/fish" ]; then
        print_message "Setting Fish as the default shell..."
        if ! grep -Fxq "/opt/homebrew/bin/fish" /etc/shells; then
            echo "/opt/homebrew/bin/fish" | sudo tee -a /etc/shells > /dev/null
        fi
        chsh -s /opt/homebrew/bin/fish
        print_success "Fish shell set as default."
    else
        print_warning "Fish shell is already the default shell."
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

    for plugin in tmux-resurrect tmux-continuum; do
        if [ ! -d "$plugin_dir/$plugin" ]; then
            print_message "Installing $plugin..."
            git clone -q https://github.com/tmux-plugins/$plugin "$plugin_dir/$plugin"
            print_success "$plugin installed."
        else
            print_warning "$plugin already installed."
        fi
    done

    tmux source ~/.tmux.conf 2> /dev/null || print_warning "tmux not started; source tmux.conf manually if needed."
    ~/.tmux/plugins/tpm/bin/install_plugins > /dev/null
    print_success "tmux plugins installed and updated."
}

update_brew() {
    print_message "Updating Homebrew..."
    brew update > /dev/null
    print_message "Upgrading outdated packages..."
    brew upgrade > /dev/null
    print_success "Homebrew updated."
}

# Run the setup tasks
print_message "Version 6 (macOS)"
install_homebrew
install_core_packages
setup_ssh_key
initialize_chezmoi
configure_chezmoi_git
chezmoi apply
set_fish_as_default_shell
install_tmux_plugins
update_brew
