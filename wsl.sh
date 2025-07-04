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

# Fix apt issues if they exist
fix_apt_issues() {
    print_message "Checking for package manager issues..."
    sudo apt-get update -qq
    sudo apt-get install -f -y -qq
}

# Update and install core dependencies with error handling
update_and_install_core() {
    print_message "Checking and installing core packages as needed..."

    # Define an array of required packages
    local packages=("git" "curl" "fish" "tmux" "gh" "git-town" "build-essential" "libssl-dev" "zlib1g-dev" "libbz2-dev" "libreadline-dev" "libsqlite3-dev" "wget" "llvm" "libncurses5-dev" "libncursesw5-dev" "xz-utils" "tk-dev" "libffi-dev" "liblzma-dev")
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
        sudo apt update -qq
        if ! sudo apt install -qq -y "${to_install[@]}"; then
            print_error "Failed to install core packages: ${to_install[*]}"
            print_message "Trying to fix package issues..."
            fix_apt_issues
            if ! sudo apt install -qq -y "${to_install[@]}"; then
                print_error "Failed to install core packages after fixing. Please check manually."
                exit 1
            fi
        fi
        print_success "Missing core packages installed."
    else
        print_success "All core packages are already installed."
    fi
}


# Check and set up SSH key
setup_ssh_key() {
    print_message "Checking for existing SSH key associated with GitHub..."

    # Retrieve GitHub-associated keys and log for debug purposes
    local existing_keys
    existing_keys=$(curl -s https://github.com/scowalt.keys)

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
        ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N "" -C "scowalt@wsl"
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

# Install Homebrew if not installed
install_homebrew() {
    if ! command -v brew &> /dev/null; then
        print_message "Installing Homebrew..."
        if ! /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; then
            print_error "Failed to install Homebrew. Please check your internet connection."
            exit 1
        fi
        eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
        print_success "Homebrew installed."
    else
        print_warning "Homebrew is already installed."
        eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
    fi
}

# Ensure Homebrew is available before using it
ensure_brew_available() {
    if ! command -v brew &> /dev/null; then
        print_error "Homebrew not available. Previous installation may have failed."
        exit 1
    fi
}

# Install Starship if not installed
# NOTE: Uses Homebrew for WSL because it provides consistent Linux binary management
# DO NOT change to curl installer - Homebrew integration is intentional for WSL
install_starship() {
    if ! command -v starship &> /dev/null; then
        print_message "Installing Starship prompt..."
        ensure_brew_available
        if ! brew install starship; then
            print_error "Failed to install Starship via Homebrew."
            exit 1
        fi
        print_success "Starship installed."
    else
        print_warning "Starship is already installed."
    fi
}

# Install chezmoi if not installed
install_chezmoi() {
    if ! command -v chezmoi &> /dev/null; then
        print_message "Installing chezmoi..."
        ensure_brew_available
        if ! brew install chezmoi; then
            print_error "Failed to install chezmoi via Homebrew."
            exit 1
        fi
        print_success "chezmoi installed."
    else
        print_warning "chezmoi is already installed."
    fi
}

# Initialize chezmoi if not already initialized
initialize_chezmoi() {
    if [ ! -d ~/.local/share/chezmoi ]; then
        print_message "Initializing chezmoi with scowalt/dotfiles..."
        if ! chezmoi init --apply scowalt/dotfiles --ssh; then
            print_error "Failed to initialize chezmoi. Check SSH key and network connectivity."
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
    if [ "$(getent passwd $USER | cut -d: -f7)" != "/usr/bin/fish" ]; then
        print_message "Setting Fish as the default shell..."
        if ! grep -Fxq "/usr/bin/fish" /etc/shells; then
            echo "/usr/bin/fish" | sudo tee -a /etc/shells > /dev/null
        fi
        sudo chsh -s /usr/bin/fish $USER
        print_success "Fish shell set as default."
    else
        print_warning "Fish shell is already the default shell."
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
                print_warning "git-town Fish completions already configured."
            fi
        fi
        
        # Set up Bash completions for git-town via Homebrew
        ensure_brew_available
        local bash_completion_dir="$(brew --prefix)/etc/bash_completion.d"
        if [ -d "$bash_completion_dir" ]; then
            if ! [ -f "$bash_completion_dir/git-town" ]; then
                git town completion bash > "$bash_completion_dir/git-town"
                print_success "git-town Bash completions configured."
            else
                print_warning "git-town Bash completions already configured."
            fi
        fi
    else
        print_warning "git-town not found, skipping completion setup."
    fi
}

# Install fnm (Fast Node Manager)
install_fnm() {
    if command -v fnm &> /dev/null; then
        print_warning "fnm already installed."
        return
    fi

    print_message "Installing fnm (Fast Node Manager)..."
    ensure_brew_available
    if ! brew install fnm; then
        print_error "Failed to install fnm via Homebrew."
        exit 1
    fi

    # Set up Fish shell integration for fnm
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

# Install 1Password CLI
install_1password_cli() {
    if command -v op >/dev/null; then
        print_warning "1Password CLI already installed."
        return
    fi

    print_message "Installing 1Password CLI..."
    ensure_brew_available
    if ! brew install --cask 1password-cli; then
        print_error "Failed to install 1Password CLI via Homebrew."
        exit 1
    fi
    print_success "1Password CLI installed."
}

# Install Infisical CLI
install_infisical() {
    if command -v infisical &> /dev/null; then
        print_warning "Infisical CLI is already installed."
        return
    fi

    print_message "Installing Infisical CLI..."
    ensure_brew_available
    if ! brew install infisical; then
        print_error "Failed to install Infisical CLI via Homebrew."
        exit 1
    fi
    print_success "Infisical CLI installed."
}

# Install Tailscale
install_tailscale() {
    print_message "Skipping Tailscale installation as it is not needed on WSL."
}

# Install act for running GitHub Actions locally
install_act() {
    if ! command -v act &> /dev/null; then
        print_message "Installing act (GitHub Actions runner)..."
        ensure_brew_available
        if ! brew install act; then
            print_error "Failed to install act via Homebrew."
            exit 1
        fi
        print_success "act installed."
    else
        print_warning "act is already installed."
    fi
}

# Install pyenv for Python version management
install_pyenv() {
    if ! command -v pyenv &> /dev/null; then
        print_message "Installing pyenv..."
        ensure_brew_available
        if ! brew install pyenv; then
            print_error "Failed to install pyenv via Homebrew."
            exit 1
        fi
        
        # Set up Fish shell integration for pyenv
        if [ -d ~/.config/fish/conf.d ]; then
            # only add once
            if ! grep -q "pyenv init" ~/.config/fish/conf.d/pyenv.fish 2>/dev/null; then
                cat <<'EOF' > ~/.config/fish/conf.d/pyenv.fish
# auto-generated by setup script
set -Ux PYENV_ROOT $HOME/.pyenv
set -U fish_user_paths $PYENV_ROOT/bin $fish_user_paths
pyenv init - | source
EOF
            fi
        fi
        
        print_success "pyenv installed."
    else
        print_warning "pyenv is already installed."
    fi
    
    # Add to PATH for current session to check for Python versions
    export PYENV_ROOT="$HOME/.pyenv"
    export PATH="$PYENV_ROOT/bin:$PATH"
    eval "$(pyenv init -)"
    
    # Install a default Python version if none is installed
    if ! pyenv versions --bare &>/dev/null || [ -z "$(pyenv versions --bare 2>/dev/null)" ]; then
        print_message "Installing Python 3.12 as default version..."
        pyenv install 3.12
        pyenv global 3.12
        print_success "Python 3.12 installed and set as global default."
    else
        print_warning "Python version already installed via pyenv."
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

update_packages() {
    print_message "Updating all packages..."
    brew update 
    brew upgrade
    sudo apt update
    sudo apt upgrade -y
    sudo apt autoremove -y
    print_success "All packages updated."
}

# Run the setup tasks
print_message "WSL Setup v6"
print_message "Last changed: Added pyenv for Python version management"
update_and_install_core
setup_ssh_key
add_github_to_known_hosts
install_homebrew
install_starship
configure_git_town
install_fnm
install_pyenv
install_1password_cli
install_infisical
install_tailscale
install_chezmoi
initialize_chezmoi
configure_chezmoi_git
chezmoi apply
set_fish_as_default_shell
install_act
install_tmux_plugins
update_packages