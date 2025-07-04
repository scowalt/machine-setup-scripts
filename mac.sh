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

# Install core packages with Homebrew if missing
install_core_packages() {
    print_message "Checking and installing core packages as needed..."

    # Define an array of required packages
    # NOTE: starship installed via Homebrew for consistent macOS binary management
    local packages=("git" "curl" "fish" "tmux" "1password-cli" "gh" "chezmoi" "starship" "fnm" "tailscale" "infisical" "git-town" "act" "terminal-notifier" "pyenv")
    local to_install=()
    
    # Get all installed packages at once (much faster than checking individually)
    print_message "Getting list of installed packages..."
    local installed_formulae
    installed_formulae=$(brew list --formula -1 2>/dev/null | tr '\n' ' ')
    local installed_casks
    installed_casks=$(brew list --cask -1 2>/dev/null | tr '\n' ' ')
    local all_installed=" $installed_formulae $installed_casks "
    
    # Check each required package against the installed list
    for package in "${packages[@]}"; do
        if [[ ! "$all_installed" =~ \ $package\  ]]; then
            to_install+=("$package")
        else
            print_debug "$package is already installed."
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
        print_debug "Homebrew is already installed."
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
    if [ "$SHELL" != "/opt/homebrew/bin/fish" ]; then
        print_message "Setting Fish as the default shell..."
        if ! grep -Fxq "/opt/homebrew/bin/fish" /etc/shells; then
            echo "/opt/homebrew/bin/fish" | sudo tee -a /etc/shells > /dev/null
        fi
        chsh -s /opt/homebrew/bin/fish
        print_success "Fish shell set as default."
    else
        print_debug "Fish shell is already the default shell."
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
        local bash_completion_dir
        bash_completion_dir="$(brew --prefix)/etc/bash_completion.d"
        if [ -d "$bash_completion_dir" ]; then
            if ! [ -f "$bash_completion_dir/git-town" ]; then
                git town completion bash > "$bash_completion_dir/git-town"
                print_success "git-town Bash completions configured."
            else
                print_debug "git-town Bash completions already configured."
            fi
        fi
        
        # Set up Zsh completions for git-town
        local zsh_completion_dir
        zsh_completion_dir="$(brew --prefix)/share/zsh/site-functions"
        if [ -d "$zsh_completion_dir" ]; then
            if ! [ -f "$zsh_completion_dir/_git-town" ]; then
                git town completion zsh > "$zsh_completion_dir/_git-town"
                print_success "git-town Zsh completions configured."
            else
                print_debug "git-town Zsh completions already configured."
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
    
    # Source fnm initialization from fish config to make npm available
    if [ -f ~/.config/fish/config.fish ]; then
        # Extract and run fnm initialization commands for the current shell
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

    for plugin in tmux-resurrect tmux-continuum; do
        if [ ! -d "$plugin_dir/$plugin" ]; then
            print_message "Installing $plugin..."
            git clone -q https://github.com/tmux-plugins/$plugin "$plugin_dir/$plugin"
            print_success "$plugin installed."
        else
            print_debug "$plugin already installed."
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
echo -e "\n${BOLD}🍎 macOS Development Environment Setup${NC}"
echo -e "${GRAY}Version 17 | Last changed: Fix ANSI color codes rendering for consistency${NC}"

print_section "Package Manager Setup"
install_homebrew

print_section "Core Packages"
install_core_packages

print_section "SSH Configuration"
setup_ssh_key
add_github_to_known_hosts

print_section "Development Tools"
configure_git_town

print_section "Dotfiles Management"
initialize_chezmoi
configure_chezmoi_git
chezmoi apply

print_section "Shell Configuration"
set_fish_as_default_shell
install_tmux_plugins

print_section "Additional Development Tools"
install_claude_code

print_section "Final Updates"
update_brew

echo -e "\n${GREEN}${BOLD}✨ Setup complete!${NC}\n"
