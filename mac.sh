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

# Check if running as main user (scowalt)
is_main_user() {
    [[ "${HOME}" == "/Users/scowalt" ]]
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

    # Copy to clipboard if pbcopy is available
    if command -v pbcopy &>/dev/null; then
        cat "${key_file}.pub" | pbcopy
        print_success "Public key copied to clipboard!"
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

    # Method 1: Main user with SSH key
    if is_main_user; then
        # < /dev/null prevents ssh from consuming stdin (important for curl|bash)
        if ssh -T git@github.com < /dev/null 2>&1 | grep -q "successfully authenticated"; then
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
    # Note: We write directly to the file because git config escapes ! to \\!
    # which breaks the shell command execution that ! is supposed to trigger
    git config --global --unset-all credential.https://github.com.helper 2>/dev/null || true

    # Remove any existing [credential "https://github.com"] section
    if [[ -f "${HOME}/.gitconfig" ]]; then
        # Use sed to remove the section (macOS sed syntax)
        sed -i '' '/^\[credential "https:\/\/github.com"\]/,/^\[/{ /^\[credential "https:\/\/github.com"\]/d; /^\[/!d; }' "${HOME}/.gitconfig" 2>/dev/null || true
    fi

    # Append the credential helper config directly to avoid git config escaping the !
    # Use heredoc with quoted delimiter to prevent any shell interpretation
    cat >> "${HOME}/.gitconfig" << 'CREDENTIAL_EOF'

[credential "https://github.com"]
	helper = !git-credential-github-multi
CREDENTIAL_EOF
    print_debug "Git configured to use multi-token credential helper for GitHub."
    return 0
}

# Fix zsh compaudit insecure directories warning
fix_zsh_compaudit() {
    print_message "Fixing zsh compaudit insecure directories..."
    # Fix all common zsh directories unconditionally
    chmod -R go-w /opt/homebrew/share/zsh 2>/dev/null || true
    chmod -R go-w /opt/homebrew/share/zsh-completions 2>/dev/null || true
    chmod -R go-w /usr/local/share/zsh 2>/dev/null || true
    # Also fix any directories compaudit finds
    zsh -c 'compaudit 2>/dev/null | xargs -I {} chmod go-w {} 2>/dev/null' || true
    print_success "zsh directory permissions fixed."
}

# Install core packages with Homebrew if missing
install_core_packages() {
    print_message "Checking and installing core packages as needed..."

    # Define an array of required packages
    # NOTE: starship installed via Homebrew for consistent macOS binary management
    local packages=("git" "curl" "jq" "fish" "tmux" "1password-cli" "gh" "chezmoi" "starship" "fnm" "tailscale" "git-town" "jj" "act" "terminal-notifier" "pyenv" "hammerspoon" "switchaudio-osx" "opentofu" "uv" "go")
    local to_install=()
    
    # Get all installed packages at once (much faster than checking individually)
    print_message "Getting list of installed packages..."
    local installed_formulae
    local brew_formulae_list
    brew_formulae_list=$(brew list --formula -1 2>/dev/null)
    installed_formulae=$(echo "${brew_formulae_list}" | tr '\n' ' ')
    local installed_casks
    local brew_casks_list
    brew_casks_list=$(brew list --cask -1 2>/dev/null)
    installed_casks=$(echo "${brew_casks_list}" | tr '\n' ' ')
    local all_installed=" ${installed_formulae} ${installed_casks} "
    
    # Check each required package against the installed list
    for package in "${packages[@]}"; do
        if [[ ! "${all_installed}" =~ \ ${package}\  ]]; then
            to_install+=("${package}")
        else
            print_debug "${package} is already installed."
        fi
    done

    # Install any packages that are not yet installed
    if [[ "${#to_install[@]}" -gt 0 ]]; then
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

    if [[ -f ~/.ssh/id_rsa.pub ]]; then
        local local_key
        local_key=$(awk '{print $2}' ~/.ssh/id_rsa.pub)

        if echo "${existing_keys}" | grep -q "${local_key}"; then
            print_success "Existing SSH key recognized by GitHub."
        else
            print_error "SSH key not recognized by GitHub. Please add it manually."
            print_message "Please add the following SSH key to GitHub:"
            cat ~/.ssh/id_rsa.pub
            print_message "Opening GitHub SSH keys page..."
            open "https://github.com/settings/keys"
            exit 1
        fi
    else
        print_warning "No SSH key found. Generating a new SSH key..."
        ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
        print_success "SSH key generated."
        print_message "Please add the following SSH key to GitHub:"
        cat ~/.ssh/id_rsa.pub
        print_message "Opening GitHub SSH keys page..."
        open "https://github.com/settings/keys"
        exit 1
    fi
}

# Install Homebrew if not installed
install_homebrew() {
    if ! command -v brew &> /dev/null; then
        print_message "Installing Homebrew..."
        local install_script
        install_script=$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)
        /bin/bash -c "${install_script}" > /dev/null
        local brew_env
        brew_env=$(/opt/homebrew/bin/brew shellenv)
        eval "${brew_env}"
        print_success "Homebrew installed."
    else
        print_debug "Homebrew is already installed."
        local brew_env
        brew_env=$(/opt/homebrew/bin/brew shellenv)
        eval "${brew_env}"
    fi
}

# Bootstrap SSH config for secondary users (needed before chezmoi can run)
bootstrap_ssh_config() {
    if is_main_user; then
        return
    fi

    # Ensure github-dotfiles host alias exists for deploy key access
    if ! grep -q "Host github-dotfiles" ~/.ssh/config 2>/dev/null; then
        print_message "Bootstrapping SSH config for dotfiles access..."
        mkdir -p ~/.ssh
        chmod 700 ~/.ssh
        cat >> ~/.ssh/config << 'EOF'

# Deploy key for read-only access to scowalt/dotfiles (secondary users only)
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
            if ! chezmoi init --apply --force scowalt/dotfiles --ssh > /dev/null; then
                print_error "Failed to initialize chezmoi."
                return 1
            fi
        else
            # Secondary users use SSH via deploy key (github-dotfiles alias)
            if ! chezmoi init --apply --force "git@github-dotfiles:scowalt/dotfiles.git" > /dev/null; then
                print_error "Failed to initialize chezmoi. Check deploy key setup."
                return 1
            fi
        fi
        print_success "chezmoi initialized with scowalt/dotfiles."
    else
        print_debug "chezmoi is already initialized."
    fi
}

# Configure chezmoi for auto commit, push, and pull
configure_chezmoi_git() {
    # Only configure auto-push for main user (secondary users are read-only)
    if ! is_main_user; then
        print_debug "Skipping chezmoi git config for secondary user (read-only)."
        return
    fi

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
    if [[ -d ~/.local/share/chezmoi/.git ]]; then
        print_message "Updating chezmoi dotfiles repository..."
        if chezmoi update --force > /dev/null; then
            print_success "chezmoi dotfiles repository updated."
        else
            print_warning "Failed to update chezmoi dotfiles repository. Continuing anyway."
        fi
    elif [[ -d ~/.local/share/chezmoi ]]; then
        # Directory exists but no .git - broken state, clean up
        print_warning "Broken chezmoi directory detected, reinitializing..."
        rm -rf ~/.local/share/chezmoi
        initialize_chezmoi
    else
        print_debug "chezmoi not initialized yet, skipping update."
    fi
}

# Set Fish as the default shell if it isn't already
set_fish_as_default_shell() {
    if [[ "${SHELL}" == "/opt/homebrew/bin/fish" ]]; then
        print_debug "Fish shell is already the default shell."
        return
    fi

    # Check if fish is in /etc/shells - requires sudo to add if missing
    if ! grep -Fxq "/opt/homebrew/bin/fish" /etc/shells; then
        if ! can_sudo; then
            print_warning "No sudo access - cannot add fish to /etc/shells."
            print_debug "Ask an admin to run: echo '/opt/homebrew/bin/fish' | sudo tee -a /etc/shells"
            return
        fi
        print_message "Adding fish to /etc/shells..."
        echo "/opt/homebrew/bin/fish" | sudo tee -a /etc/shells > /dev/null
    fi

    print_message "Setting Fish as the default shell..."
    chsh -s /opt/homebrew/bin/fish
    print_success "Fish shell set as default."
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
        local bash_completion_dir
        local brew_prefix
        brew_prefix=$(brew --prefix)
        bash_completion_dir="${brew_prefix}/etc/bash_completion.d"
        if [[ -d "${bash_completion_dir}" ]]; then
            if ! [[ -f "${bash_completion_dir}/git-town" ]]; then
                git town completion bash > "${bash_completion_dir}/git-town"
                print_success "git-town Bash completions configured."
            else
                print_debug "git-town Bash completions already configured."
            fi
        fi
        
        # Set up Zsh completions for git-town
        local zsh_completion_dir
        zsh_completion_dir="${brew_prefix}/share/zsh/site-functions"
        if [[ -d "${zsh_completion_dir}" ]]; then
            if ! [[ -f "${zsh_completion_dir}/_git-town" ]]; then
                git town completion zsh > "${zsh_completion_dir}/_git-town"
                print_success "git-town Zsh completions configured."
            else
                print_debug "git-town Zsh completions already configured."
            fi
        fi
    else
        print_warning "git-town not found, skipping completion setup."
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
    if echo "${fnm_output}" | grep -q .; then
        print_debug "Node.js version already installed."
        
        # Check if a default/global version is set
        local current_version
        current_version=$(fnm current 2>/dev/null || echo "none")
        if [[ "${current_version}" != "none" ]] && [[ -n "${current_version}" ]]; then
            print_debug "Global Node.js version already set: ${current_version}"
        else
            print_message "No global Node.js version set. Setting the first installed version as default..."
            local first_version
            local fnm_list
            fnm_list=$(fnm list)
            local filtered_list
            filtered_list=$(echo "${fnm_list}" | grep -v "system")
            local first_line
            first_line=$(echo "${filtered_list}" | head -n1)
            first_version=$(echo "${first_line}" | awk '{print $2}')
            if [[ -n "${first_version}" ]]; then
                fnm default "${first_version}"
                print_success "Set ${first_version} as default Node.js version."
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
            local current_version_display
            current_version_display=$(fnm current)
            print_success "Set ${current_version_display} as default Node.js version."
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

# Install Gemini CLI (Google's AI coding agent)
install_gemini_cli() {
    if command -v gemini &> /dev/null; then
        print_debug "Gemini CLI is already installed."
        return
    fi

    print_message "Installing Gemini CLI..."

    # Make sure npm is available
    if ! command -v npm &> /dev/null; then
        print_warning "npm not found. Cannot install Gemini CLI."
        print_debug "Install Node.js first, then run: npm install -g @google/gemini-cli"
        return
    fi

    if npm install -g @google/gemini-cli; then
        print_success "Gemini CLI installed."
    else
        print_error "Failed to install Gemini CLI."
    fi
}

# Install Visual Studio Code
install_vscode() {
    if brew list --cask visual-studio-code &> /dev/null; then
        print_debug "Visual Studio Code is already installed."
        return
    fi
    
    print_message "Installing Visual Studio Code..."
    if ! brew install --cask visual-studio-code > /dev/null; then
        print_error "Failed to install Visual Studio Code."
        exit 1
    fi
    print_success "Visual Studio Code installed."
}

# Install Bun JavaScript runtime
install_bun() {
    if [[ -d "${HOME}/.bun" ]]; then
        print_debug "Bun is already installed."
        return
    fi

    print_message "Installing Bun..."
    local bun_install
    bun_install=$(curl -fsSL https://bun.sh/install)
    if bash <<< "${bun_install}"; then
        print_success "Bun installed."
    else
        print_error "Failed to install Bun."
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

update_brew() {
    print_message "Updating Homebrew..."
    brew update > /dev/null
    print_message "Upgrading outdated packages..."
    brew upgrade > /dev/null
    print_success "Homebrew updated."
}

# Upgrade global npm packages
upgrade_npm_global_packages() {
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

# Run the setup tasks
current_user=$(whoami)
echo -e "\n${BOLD}🍎 macOS Development Environment Setup${NC}"
echo -e "${GRAY}Version 65 | Last changed: Add Gemini CLI installation${NC}"

if is_main_user; then
    echo -e "${CYAN}Running full setup for main user (scowalt)${NC}"

    print_section "Package Manager Setup"
    install_homebrew

    print_section "Core Packages"
    install_core_packages

    # Fix zsh permissions early (before any tool might invoke zsh)
    fix_zsh_compaudit

    print_section "SSH Configuration"
    setup_ssh_key
    add_github_to_known_hosts

    print_section "Code Directory Setup"
    setup_code_directory

    print_section "Development Tools"
    configure_git_town
else
    echo -e "${CYAN}Running secondary user setup for ${current_user}${NC}"

    # Ensure Homebrew is in PATH (already installed by main user)
    eval "$(/opt/homebrew/bin/brew shellenv)"

    # Fix zsh permissions early (before any tool might invoke zsh)
    fix_zsh_compaudit

    print_section "SSH Configuration"
    add_github_to_known_hosts
fi

# Common setup for all users
print_section "Dotfiles Management"

# Check if we have access (via SSH, token, or deploy key)
# If not, try interactive deploy key setup
if check_dotfiles_access || setup_dotfiles_deploy_key; then
    # We have access, proceed with chezmoi setup

    # Bootstrap the credential helper before chezmoi (chicken-and-egg problem)
    # The helper script is part of dotfiles but we need it to pull dotfiles
    if [[ ! -x "${HOME}/.local/bin/git-credential-github-multi" ]]; then
        source_gh_tokens
        if [[ -n "${GH_TOKEN_SCOWALT}" ]] || [[ -n "${GH_TOKEN}" ]]; then
            print_message "Bootstrapping git credential helper..."
            mkdir -p "${HOME}/.local/bin"
            cat > "${HOME}/.local/bin/git-credential-github-multi" << 'HELPER_EOF'
#!/bin/bash
# Git credential helper that routes to different GitHub tokens based on repo owner
# Note: Uses simple variables instead of associative arrays for bash 3.2 compatibility (macOS default)
host=""
path=""
while IFS='=' read -r key value; do
    [[ -z "${key}" ]] && break
    case "${key}" in
        host) host="${value}" ;;
        path) path="${value}" ;;
    esac
done
[[ "${host}" != "github.com" ]] && exit 1
owner=""
[[ -n "${path}" ]] && owner=$(echo "${path}" | cut -d'/' -f1)
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

    initialize_chezmoi
    configure_chezmoi_git
    update_chezmoi
    chezmoi apply --force
    tmux source ~/.tmux.conf 2>/dev/null || true
else
    print_warning "Skipping dotfiles management - no access to repository."
fi

print_section "Shell Configuration"
if is_main_user; then
    set_fish_as_default_shell
else
    # Secondary users have locked passwords, can't use chsh
    # Their shell must be set by main user with: sudo chsh -s /opt/homebrew/bin/fish <username>
    if [[ "${SHELL}" != "/opt/homebrew/bin/fish" ]]; then
        print_warning "Shell is not fish. Main user must run: sudo chsh -s /opt/homebrew/bin/fish ${current_user}"
    else
        print_debug "Fish shell is already the default shell."
    fi
fi
install_tmux_plugins

print_section "Development Tools"
setup_nodejs
install_bun
install_claude_code
install_gemini_cli

if is_main_user; then
    install_vscode

    print_section "Final Updates"
    update_brew
fi

upgrade_npm_global_packages

echo -e "\n${GREEN}${BOLD}✨ Setup complete!${NC}\n"
