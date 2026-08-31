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

SETUP_ORIGINAL_PATH="${PATH}"
SETUP_ORIGINAL_CLAUDE_COMMAND=$(command -v claude 2>/dev/null || true)
SETUP_LOG_FILE=""
SETUP_LOG_TEE_PID=""
SETUP_LOGGING_ACTIVE=0
DOTFILES_ACCESS_METHOD=""

# Acquire a non-blocking per-user setup lock so overlapping setup runs don't
# corrupt shared global package directories (npm, Bun, Homebrew, etc.). The lock
# is held by file descriptor 9 until the script exits.
acquire_setup_lock() {
    local _lock_root="${XDG_RUNTIME_DIR:-${HOME}/.local/state}"
    local _lock_file="${_lock_root}/machine-setup.lock"

    if [[ "${MACHINE_SETUP_ALLOW_CONCURRENT:-}" == "1" ]]; then
        print_warning "MACHINE_SETUP_ALLOW_CONCURRENT=1, skipping concurrent setup guard."
        return 0
    fi

    if ! command -v flock &> /dev/null; then
        print_debug "flock not found; concurrent setup guard disabled."
        return 0
    fi

    if ! mkdir -p "${_lock_root}"; then
        print_warning "Could not create setup lock directory at ${_lock_root}; continuing without a lock."
        return 0
    fi

    if ! exec 9>"${_lock_file}"; then
        print_warning "Could not open setup lock at ${_lock_file}; continuing without a lock."
        return 0
    fi

    if ! flock -n 9; then
        print_warning "Another machine setup run is already in progress; exiting before making changes."
        print_debug "Lock file: ${_lock_file}"
        return 1
    fi

    print_debug "Acquired setup lock at ${_lock_file}."
}
print_error() { printf "${RED} %s${NC}\n" "$1"; }

# Migrate old token files (~/.gh_token, ~/.op_token) into ~/.env.local
migrate_token_files() {
    local env_file="${HOME}/.env.local"
    local migrated=0

    for old_file in "${HOME}/.gh_token" "${HOME}/.op_token"; do
        if [[ -f "${old_file}" ]]; then
            # Extract uncommented KEY=VALUE lines (strip 'export ' prefix if present)
            local values
            values=$(grep -v '^\s*#' "${old_file}" | grep -v '^\s*$' | sed 's/^export //') || true
            if [[ -n "${values}" ]]; then
                touch "${env_file}"
                chmod 600 "${env_file}"
                while IFS= read -r line; do
                    local key="${line%%=*}"
                    if ! grep -q "^${key}=" "${env_file}" 2>/dev/null; then
                        echo "${line}" >> "${env_file}"
                    fi
                done <<< "${values}"
            fi
            rm -f "${old_file}"
            print_debug "Migrated $(basename "${old_file}") → ~/.env.local"
            migrated=1
        fi
    done

    if [[ "${migrated}" -eq 1 ]]; then
        print_message "Token files consolidated into ~/.env.local"
    fi
}

# Create placeholder ~/.env.local if it doesn't exist
create_env_local() {
    migrate_token_files

    if [[ ! -f "${HOME}/.env.local" ]]; then
        cat > "${HOME}/.env.local" << 'EOF'
# Machine-specific environment variables
# Format: KEY=VALUE (one per line)

# GitHub Personal Access Tokens
# Get tokens from: https://github.com/settings/tokens
# GH_TOKEN=github_pat_xxx
# GH_TOKEN_SCOWALT=github_pat_yyy

# 1Password Service Account Token
# Create a service account at: https://my.1password.com/integrations/infrastructure-secrets
# OP_SERVICE_ACCOUNT_TOKEN=ops_xxx

# Machine/setup guards
# HEADLESS=1
# WORK_MACHINE=1
# BAN_PI_MCP_ADAPTER=1
# BAN_PI_GOAL_AUTORESEARCH=1
# BAN_MATT_POCOCK_SKILLS=1
# SYNTHETIC_API_KEY=<your Synthetic API key>
# ZAI_API_KEY=<your z.ai API key>
# BAN_CLAUDE_CODE=1
EOF
        chmod 600 "${HOME}/.env.local"
        print_debug "Created placeholder ~/.env.local"
    fi
}


# Read KEY=1 guards from the process environment or an existing ~/.env.local without mutating it.
env_local_flag_is_one() {
    local _name="$1"
    local _line=""
    local _key=""
    local _value=""

    if [[ "${!_name:-}" == "1" ]]; then
        return 0
    fi

    [[ -f "${HOME}/.env.local" ]] || return 1
    while IFS= read -r _line; do
        _line="${_line#export }"
        [[ "${_line}" == \#* || "${_line}" != *=* ]] && continue
        _key="${_line%%=*}"
        _value="${_line#*=}"
        _value="${_value%\"}"
        _value="${_value#\"}"
        _value="${_value%\'}"
        _value="${_value#\'}"
        if [[ "${_key}" == "${_name}" && "${_value}" == "1" ]]; then
            return 0
        fi
    done < "${HOME}/.env.local"

    return 1
}

fail_unsupported_headless_paseo_daemon() {
    if ! env_local_flag_is_one "HEADLESS"; then
        return 0
    fi

    print_error "HEADLESS=1 requested, but WSL cannot guarantee a no-login Paseo daemon after Windows host reboot."
    print_error "Use a native Linux setup script on a booting system for strict Paseo headless support, or unset HEADLESS for WSL setup."
    return 1
}

# Check if user has sudo access (cached result)
_sudo_checked=""
_has_sudo=""
can_sudo() {
    if [[ -z "${_sudo_checked}" ]]; then
        _sudo_checked=1
        local _user_groups
        _user_groups=$(groups 2>/dev/null) || true
        # Method 1: Check if credentials are already cached
        if sudo -n true 2>/dev/null; then
            _has_sudo=1
        # Method 2: Check if user is in a sudo-capable group, then prompt
        elif echo "${_user_groups}" | grep -qE '\b(sudo|wheel|admin)\b'; then
            # User is in sudo group but credentials aren't cached - prompt once
            # shellcheck disable=SC2024
            if sudo -v 2>/dev/null < /dev/tty; then
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
        return 1
    fi
}

# Bootstrap SSH config for deploy key access to dotfiles
bootstrap_ssh_config() {
    # Ensure github-dotfiles host alias exists for deploy key access
    if ! awk 'tolower($1) == "host" { for (i=2; i<=NF; i++) if ($i == "github-dotfiles") found=1 } END { exit !found }' ~/.ssh/config 2>/dev/null; then
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
        local _hostname
        _hostname=$(hostname)
        ssh-keygen -t ed25519 -f "${key_file}" -N '' -C "dotfiles-deploy-key-${_hostname}"
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

    # Copy to clipboard via Windows clip.exe if available
    if command -v clip.exe &>/dev/null; then
        clip.exe < "${key_file}.pub" 2>/dev/null && print_success "Public key copied to clipboard!"
    fi
    echo ""

    # Open GitHub in browser via Windows
    powershell.exe -Command "Start-Process 'https://github.com/scowalt/dotfiles/settings/keys'" 2>/dev/null || true

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
        local _ssh_output
        _ssh_output=$(ssh -i "${key_file}" -o StrictHostKeyChecking=accept-new -T git@github.com < /dev/null 2>&1) || true
        if echo "${_ssh_output}" | grep -q "successfully authenticated"; then
            print_success "Deploy key works! Continuing setup..."
            DOTFILES_ACCESS_METHOD="deploy"
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
    DOTFILES_ACCESS_METHOD=""
    print_message "Checking access to scowalt/dotfiles..."

    # Method 1: SSH key (main user)
    # < /dev/null prevents ssh from consuming stdin (important for curl|bash)
    local _ssh_output
    _ssh_output=$(ssh -T git@github.com < /dev/null 2>&1) || true
    if echo "${_ssh_output}" | grep -q "successfully authenticated"; then
        print_debug "Access via SSH"
        DOTFILES_ACCESS_METHOD="ssh"
        return 0
    fi

    # Method 2: Deploy key at ~/.ssh/dotfiles-deploy-key
    if [[ -f ~/.ssh/dotfiles-deploy-key ]]; then
        # Set up SSH config for github-dotfiles if not present
        bootstrap_ssh_config
        # Test if the deploy key works
        # < /dev/null prevents ssh from consuming stdin (important for curl|bash)
        local _deploy_ssh_output
        _deploy_ssh_output=$(ssh -i ~/.ssh/dotfiles-deploy-key -T git@github.com < /dev/null 2>&1) || true
        if echo "${_deploy_ssh_output}" | grep -q "successfully authenticated"; then
            print_debug "Access via deploy key"
            DOTFILES_ACCESS_METHOD="deploy"
            return 0
        else
            print_warning "Deploy key exists but cannot authenticate with GitHub"
        fi
    fi

    # No access method worked
    return 1
}

# Fix apt issues if they exist
fix_apt_issues() {
    if ! can_sudo; then
        print_debug "No sudo access - skipping apt fix."
        return
    fi
    print_message "Checking for package manager issues..."
    sudo apt-get update -qq
    sudo apt-get install -f -y -qq
}

# Update and install core dependencies with error handling
update_and_install_core() {
    print_message "Checking and installing core packages as needed..."

    # Define an array of required packages
    local packages=("git" "curl" "jq" "fish" "tmux" "gh" "build-essential" "libssl-dev" "zlib1g-dev" "libbz2-dev" "libreadline-dev" "libsqlite3-dev" "wget" "llvm" "libncurses-dev" "xz-utils" "tk-dev" "libffi-dev" "liblzma-dev" "golang-go" "inotify-tools" "shellcheck" "gitleaks" "poppler-utils" "bubblewrap")
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
        sudo apt update -qq
        if ! sudo apt install -qq -y "${to_install[@]}"; then
            print_error "Failed to install core packages: ${to_install[*]}"
            print_message "Trying to fix package issues..."
            fix_apt_issues
            if ! sudo apt install -qq -y "${to_install[@]}"; then
                print_error "Failed to install core packages after fixing. Please check manually."
                return 1
            fi
        fi
        print_success "Missing core packages installed."
    else
        print_success "All core packages are already installed."
    fi
}


# Fetch GitHub SSH keys with bounded retries and reject empty responses.
fetch_github_ssh_keys() {
    local _keys_url="${1:-https://github.com/scowalt.keys}"
    local _attempt=1
    local _keys=""

    while [[ "${_attempt}" -le 3 ]]; do
        if _keys=$(curl --fail --silent --show-error --location \
            --connect-timeout 10 --max-time 20 "${_keys_url}") && \
            grep -q '[^[:space:]]' <<< "${_keys}"; then
            printf '%s\n' "${_keys}"
            return 0
        fi

        if [[ "${_attempt}" -lt 3 ]]; then
            sleep 2
        fi
        _attempt=$((_attempt + 1))
    done

    return 1
}

# Check and set up SSH key
setup_ssh_key() {
    # Skip SSH key setup for non-sudo users (they won't be making outbound SSH requests)
    if ! can_sudo; then
        print_debug "No sudo access - skipping SSH key setup."
        return
    fi

    print_message "Checking for existing SSH key associated with GitHub..."

    # Retrieve GitHub-associated keys and log for debug purposes
    local existing_keys
    if ! existing_keys=$(fetch_github_ssh_keys "https://github.com/scowalt.keys"); then
        print_error "Failed to download SSH keys from GitHub after three attempts; key registration could not be verified."
        return 1
    fi

    # Check if a local SSH key exists
    if [[ -f ~/.ssh/id_rsa.pub ]]; then
        # Extract only the actual key part from id_rsa.pub and log for debugging
        local local_key
        local_key=$(awk '{print $2}' ~/.ssh/id_rsa.pub)

        # Verify if the extracted key part matches any of the GitHub keys
        if awk -v expected="${local_key}" 'NF >= 2 && $2 == expected { found=1 } END { exit !found }' <<< "${existing_keys}"; then
            print_success "Existing SSH key recognized by GitHub."
        else
            print_error "SSH key not recognized by GitHub. Please add it manually."
            print_message "Please add the following SSH key to GitHub:"
            cat ~/.ssh/id_rsa.pub
            print_message "Opening GitHub SSH keys page..."
            powershell.exe -Command "Start-Process 'https://github.com/settings/keys'" 2>/dev/null || true
            return 1
        fi
    else
        # Generate a new SSH key and log details
        print_warning "No SSH key found. Generating a new SSH key..."
        ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N "" -C "scowalt@wsl"
        print_success "SSH key generated."
        print_message "Please add the following SSH key to GitHub:"
        cat ~/.ssh/id_rsa.pub
        print_message "Opening GitHub SSH keys page..."
        powershell.exe -Command "Start-Process 'https://github.com/settings/keys'" 2>/dev/null || true
        return 1
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
            return 1
        fi
        print_success "GitHub's SSH key added."
    else
        print_debug "GitHub's SSH key already exists in known_hosts."
    fi
}

# Install Homebrew if not installed
install_homebrew() {
    if ! command -v brew &> /dev/null; then
        print_message "Installing Homebrew..."
        local install_script
        install_script=$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh || true)
        if ! /bin/bash -c "${install_script}"; then
            print_error "Failed to install Homebrew. Please check your internet connection."
            return 1
        fi
        local brew_env
        brew_env=$(/home/linuxbrew/.linuxbrew/bin/brew shellenv || true)
        eval "${brew_env}"
        print_success "Homebrew installed."
    else
        print_debug "Homebrew is already installed."
        local brew_env
        brew_env=$(/home/linuxbrew/.linuxbrew/bin/brew shellenv || true)
        eval "${brew_env}"
    fi

    # Fix ownership if Cellar is not writable by current user (multi-user installs)
    local brew_prefix
    brew_prefix="$(brew --prefix 2>/dev/null)"
    if [[ -n "${brew_prefix}" ]] && [[ -d "${brew_prefix}/Cellar" ]] && [[ ! -w "${brew_prefix}/Cellar" ]]; then
        if can_sudo; then
            print_message "Fixing Homebrew permissions for $(whoami || true)..."
            sudo chown -R "$(whoami || true)" "${brew_prefix}/Cellar" "${brew_prefix}/Homebrew" "${brew_prefix}/lib" "${brew_prefix}/bin" "${brew_prefix}/share" "${brew_prefix}/etc" "${brew_prefix}/opt" "${brew_prefix}/var" 2>/dev/null
            print_success "Homebrew permissions fixed."
        else
            print_warning "Homebrew Cellar is not writable by $(whoami || true). Brew installs may fail."
            print_debug "An admin can fix this: sudo chown -R $(whoami || true) ${brew_prefix}/Cellar"
        fi
    fi
}

# Ensure Homebrew is available before using it
ensure_brew_available() {
    if ! command -v brew &> /dev/null; then
        print_error "Homebrew not available. Previous installation may have failed."
        return 1
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
            return 1
        fi
        print_success "Starship installed."
    else
        print_debug "Starship is already installed."
    fi
}

# Install chezmoi if not installed
install_chezmoi() {
    if ! command -v chezmoi &> /dev/null; then
        print_message "Installing chezmoi..."
        ensure_brew_available
        if ! brew install chezmoi; then
            print_error "Failed to install chezmoi via Homebrew."
            return 1
        fi
        print_success "chezmoi installed."
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
        case "${DOTFILES_ACCESS_METHOD}" in
            ssh)
                if ! chezmoi init --apply --force scowalt/dotfiles --ssh; then
                    print_error "Failed to initialize chezmoi with the verified SSH key."
                    return 1
                fi
                ;;
            token)
                if ! chezmoi init --apply --force "https://github.com/scowalt/dotfiles.git"; then
                    print_error "Failed to initialize chezmoi with the verified GitHub token."
                    return 1
                fi
                ;;
            deploy)
                if ! chezmoi init --apply --force "git@github-dotfiles:scowalt/dotfiles.git"; then
                    print_error "Failed to initialize chezmoi with the verified deploy key."
                    return 1
                fi
                ;;
            *)
                print_error "Cannot initialize chezmoi without a verified dotfiles access method."
                return 1
                ;;
        esac
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
    local chez_src="${HOME}/.local/share/chezmoi"
    if [[ -d "${chez_src}" ]]; then
        print_message "Updating chezmoi dotfiles repository..."
        # Reset any dirty state (merge conflicts, uncommitted changes) before pulling.
        # The remote repo is the source of truth — local edits in the chezmoi source dir
        # should never exist and are safe to discard.
        if [[ -d "${chez_src}/.git" ]]; then
            git -C "${chez_src}" reset --hard HEAD > /dev/null 2>&1
            git -C "${chez_src}" merge --abort > /dev/null 2>&1
            git -C "${chez_src}" clean -fd > /dev/null 2>&1
        fi
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
    # shellcheck disable=SC2024
    sudo chsh -s /usr/bin/fish "${USER}" < /dev/tty
    print_success "Fish shell set as default."
}



# Install packages via Homebrew
install_brew_packages() {
    if ! command -v brew &> /dev/null; then
        print_warning "Homebrew not available. Skipping brew packages."
        return 0
    fi

    local packages=("ffmpeg" "kubernetes-cli")
    local to_install=()

    for package in "${packages[@]}"; do
        if brew list "${package}" &> /dev/null 2>&1; then
            print_debug "${package} (brew) is already installed."
        else
            to_install+=("${package}")
        fi
    done

    if [[ "${#to_install[@]}" -gt 0 ]]; then
        print_message "Installing brew packages: ${to_install[*]}"
        brew install "${to_install[@]}" > /dev/null
        print_success "Brew packages installed."
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

# Install/update Codex CLI with OpenAI's per-user standalone installer.
install_codex_cli() {
    local bun_packages=""
    local curl_bin=""
    local installer=""
    local install_status=0
    local native_path="${HOME}/.local/bin/codex"
    local resolved_codex=""
    local version_output=""
    local safe_path=""

    print_message "Installing/updating Codex CLI..."

    if command -v bun &> /dev/null; then
        bun_packages=$(bun pm ls -g 2>/dev/null || true)
        if grep -Fq "@openai/codex" <<< "${bun_packages}"; then
            print_message "Removing Node-dependent Bun Codex package..."
            if ! bun remove -g @openai/codex > /dev/null; then
                print_error "Failed to remove Bun's @openai/codex package."
                return 1
            fi
        fi
    fi
    hash -r 2>/dev/null || true

    if ! curl_bin=$(claude_code_trusted_curl); then
        print_error "Trusted system curl not found. Cannot download the Codex installer."
        return 1
    fi

    if ! installer=$(mktemp); then
        print_error "Failed to create a temporary file for the Codex installer."
        return 1
    fi
    if ! claude_code_run_safely "${curl_bin}" -fsSL --connect-timeout 15 --max-time 120 --retry 2 --retry-delay 2 -o "${installer}" "https://chatgpt.com/codex/install.sh"; then
        rm -f "${installer}"
        print_error "Failed to download the Codex installer."
        return 1
    fi

    chmod 700 "${installer}"
    if claude_code_run_safely /usr/bin/env CODEX_NON_INTERACTIVE=1 /bin/sh "${installer}"; then
        install_status=0
    else
        install_status=$?
    fi
    rm -f "${installer}"
    if [[ "${install_status}" -ne 0 ]]; then
        print_error "Codex installer failed with exit code ${install_status}."
        return 1
    fi

    export PATH="${HOME}/.local/bin:${PATH}"
    hash -r 2>/dev/null || true
    resolved_codex=$(command -v codex 2>/dev/null || true)
    if [[ ! -x "${native_path}" ]]; then
        print_error "Codex installer completed, but ${native_path} is missing."
        return 1
    fi
    if [[ -z "${resolved_codex}" || ! "${resolved_codex}" -ef "${native_path}" ]]; then
        print_error "Codex is shadowed by ${resolved_codex:-<missing>}; expected ${native_path}."
        return 1
    fi

    safe_path="/nonexistent"
    if ! version_output=$(/usr/bin/env -u NODE_PATH -u NODE_OPTIONS HOME="${HOME}" PATH="${safe_path}" "${native_path}" --version 2>/dev/null) || [[ -z "${version_output}" ]]; then
        print_error "Native Codex CLI smoke test failed without Node.js on PATH."
        return 1
    fi

    print_success "Codex CLI installed/updated (${version_output})."
}

# Install/update Notion CLI.
install_ntn_cli() {
    local os
    local arch
    os=$(uname -s 2>/dev/null || true)
    arch=$(uname -m 2>/dev/null || true)

    case "${os}:${arch}" in
        Darwin:x86_64|Darwin:arm64|Darwin:aarch64|Linux:x86_64|Linux:amd64|Linux:arm64|Linux:aarch64) ;;
        *)
            print_warning "Notion CLI does not support ${os:-unknown} ${arch:-unknown}; skipping."
            return
            ;;
    esac

    print_message "Installing/updating Notion CLI..."

    local install_dir="${HOME}/.local/bin"
    local installer_path
    if ! installer_path=$(mktemp "${TMPDIR:-/tmp}/ntn-install.XXXXXX"); then
        print_warning "Failed to create a temporary file for the Notion CLI installer."
        return
    fi

    local install_output
    if ! install_output=$(curl -fsSL https://ntn.dev -o "${installer_path}" 2>&1); then
        rm -f "${installer_path}"
        print_warning "Failed to download the Notion CLI installer."
        print_debug "${install_output}"
        return
    fi

    if install_output=$(NTN_INSTALL_DIR="${install_dir}" bash "${installer_path}" 2>&1); then
        rm -f "${installer_path}"
        export PATH="${install_dir}:${PATH}"
        if "${install_dir}/ntn" --version > /dev/null 2>&1; then
            print_success "Notion CLI installed/updated."
        else
            print_warning "Notion CLI installer completed, but ${install_dir}/ntn did not verify."
            print_debug "${install_output}"
        fi
    else
        rm -f "${installer_path}"
        print_warning "Failed to install/update Notion CLI."
        print_debug "${install_output}"
    fi
}



# Install Portless CLI (Tailscale HTTPS tunnel helper)
install_portless_cli() {
    if command -v portless &> /dev/null; then
        print_debug "Portless CLI is already installed."
        return
    fi

    print_message "Installing Portless CLI..."

    # Ensure bun is available
    if [[ -d "${HOME}/.bun" ]]; then
        export PATH="${HOME}/.bun/bin:${PATH}"
    fi

    if ! command -v bun &> /dev/null; then
        print_warning "Bun not found. Cannot install Portless CLI."
        print_debug "Install Bun first, then run: bun install -g portless"
        return
    fi

    if ! command -v tailscale &> /dev/null; then
        print_warning "Tailscale not found. Portless requires Tailscale to create tunnels."
    fi

    if bun install -g portless; then
        print_success "Portless CLI installed."
    else
        print_error "Failed to install Portless CLI."
    fi
}

# Install/update Claude Code CLI (Anthropic's AI coding agent)
claude_code_native_path() {
    printf '%s/.local/bin/claude' "${HOME}"
}

claude_code_path_looks_package_managed() {
    local path="$1"
    local target="${path}"
    local path_details

    if [[ -L "${path}" ]]; then
        target=$(readlink "${path}" 2>/dev/null || printf '%s' "${path}")
    fi
    path_details="${path} ${target}"

    if [[ -f "${path}" ]] && [[ ! -L "${path}" ]]; then
        path_details="${path_details} $(LC_ALL=C head -c 512 "${path}" 2>/dev/null || true)"
    fi

    case "${path_details}" in
        *node_modules*|*pnpm*|*mise*|*asdf*|*volta*|*yarn*|*fnm*|*nvm*|*npm*|*"${HOME}/.bun"*|*Homebrew*|*Cellar*|*Caskroom*) return 0 ;;
        *) return 1 ;;
    esac
}

claude_code_canonical_path() {
    local path="$1"
    local target
    local dir
    local base
    local canonical_dir

    if command -v realpath > /dev/null 2>&1; then
        realpath "${path}"
        return
    fi

    if command -v python3 > /dev/null 2>&1; then
        python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "${path}"
        return
    fi

    if [[ -L "${path}" ]]; then
        target=$(readlink "${path}" 2>/dev/null || printf '%s' "${path}")
        case "${target}" in
            /*) path="${target}" ;;
            *) path="$(dirname "${path}")/${target}" ;;
        esac
    fi

    dir=$(dirname "${path}")
    base=$(basename "${path}")
    canonical_dir=$(cd -P "${dir}" 2>/dev/null && pwd -P) || return 1
    printf '%s/%s\n' "${canonical_dir}" "${base}"
}

claude_code_path_has_native_provenance() {
    local path="$1"
    local resolved_path
    local native_root

    [[ -x "${path}" ]] || return 1

    if claude_code_path_looks_package_managed "${path}"; then
        return 1
    fi

    resolved_path=$(claude_code_canonical_path "${path}") || return 1
    native_root=$(claude_code_canonical_path "${HOME}/.local/share/claude" 2>/dev/null || printf '%s' "${HOME}/.local/share/claude")

    case "${resolved_path}" in
        "${native_root}/"*) return 0 ;;
        *) return 1 ;;
    esac
}

claude_code_supported_platform() {
    local os
    local arch
    os=$(uname -s 2>/dev/null || true)
    arch=$(uname -m 2>/dev/null || true)

    case "${os}" in
        Darwin|Linux) ;;
        *)
            print_warning "Claude Code native installer does not support ${os:-unknown}."
            return 1
            ;;
    esac

    case "${arch}" in
        x86_64|amd64|arm64|aarch64) return 0 ;;
        *)
            print_warning "Claude Code native installer does not support architecture ${arch:-unknown}."
            return 1
            ;;
    esac
}

claude_code_trusted_curl() {
    local candidate

    for candidate in /usr/bin/curl /bin/curl /usr/local/bin/curl /opt/homebrew/bin/curl; do
        if [[ -x "${candidate}" ]]; then
            printf '%s\n' "${candidate}"
            return 0
        fi
    done

    return 1
}

claude_code_kill_process_tree() {
    local signal="$1"
    local pid="$2"
    local children=""
    local child

    if command -v pgrep > /dev/null 2>&1; then
        children=$(pgrep -P "${pid}" 2>/dev/null || true)
        while IFS= read -r child; do
            if [[ -n "${child}" ]]; then
                claude_code_kill_process_tree "${signal}" "${child}"
            fi
        done <<< "${children}"
    fi

    kill "-${signal}" "${pid}" 2>/dev/null || true
}

claude_code_run_safely() {
    local -a env_args=()
    local safe_path="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin"
    local env_bin="/usr/bin/env"
    local timeout_seconds="${CLAUDE_CODE_COMMAND_TIMEOUT_SECONDS:-300}"
    local timeout_flag
    local command_status=0
    local pid
    local watchdog
    local use_process_group=0

    if [[ ! -x "${env_bin}" ]]; then
        env_bin="/bin/env"
    fi

    env_args=(
        "HOME=${HOME}"
        "USER=${USER:-}"
        "LOGNAME=${LOGNAME:-${USER:-}}"
        "SHELL=${SHELL:-/bin/bash}"
        "PATH=${safe_path}"
        "TMPDIR=${TMPDIR:-/tmp}"
        "TMP=${TMP:-/tmp}"
        "TEMP=${TEMP:-/tmp}"
        "LANG=${LANG:-C}"
        "HTTP_PROXY=${HTTP_PROXY:-}"
        "HTTPS_PROXY=${HTTPS_PROXY:-}"
        "ALL_PROXY=${ALL_PROXY:-}"
        "NO_PROXY=${NO_PROXY:-}"
        "http_proxy=${http_proxy:-}"
        "https_proxy=${https_proxy:-}"
        "all_proxy=${all_proxy:-}"
        "no_proxy=${no_proxy:-}"
        "SSL_CERT_FILE=${SSL_CERT_FILE:-}"
        "SSL_CERT_DIR=${SSL_CERT_DIR:-}"
        "CURL_CA_BUNDLE=${CURL_CA_BUNDLE:-}"
    )

    timeout_flag=$(mktemp)
    rm -f "${timeout_flag}"

    if command -v setsid > /dev/null 2>&1; then
        "${env_bin}" -i "${env_args[@]}" setsid "$@" < /dev/null &
        use_process_group=1
    elif command -v perl > /dev/null 2>&1; then
        "${env_bin}" -i "${env_args[@]}" perl -MPOSIX=setsid -e 'setsid() or die "setsid failed"; exec @ARGV' "$@" < /dev/null &
        use_process_group=1
    else
        "${env_bin}" -i "${env_args[@]}" "$@" < /dev/null &
    fi
    pid=$!
    (
        sleep "${timeout_seconds}"
        if [[ "${use_process_group}" -eq 1 ]]; then
            if kill -- "-${pid}" 2>/dev/null; then
                : > "${timeout_flag}"
                for _ in 1 2 3 4 5; do
                    sleep 1
                    if ! kill -0 -- "-${pid}" 2>/dev/null; then
                        exit 0
                    fi
                done
                kill -KILL -- "-${pid}" 2>/dev/null || true
            fi
        elif kill -0 "${pid}" 2>/dev/null; then
            : > "${timeout_flag}"
            claude_code_kill_process_tree TERM "${pid}"
            for _ in 1 2 3 4 5; do
                sleep 1
                if ! kill -0 "${pid}" 2>/dev/null; then
                    exit 0
                fi
            done
            claude_code_kill_process_tree KILL "${pid}"
        fi
    ) > /dev/null 2>&1 &
    watchdog=$!

    wait "${pid}" 2>/dev/null || command_status=$?
    if [[ -f "${timeout_flag}" ]]; then
        wait "${watchdog}" 2>/dev/null || true
        rm -f "${timeout_flag}"
        return 124
    fi

    kill "${watchdog}" 2>/dev/null || true
    wait "${watchdog}" 2>/dev/null || true

    rm -f "${timeout_flag}"
    return "${command_status}"
}

claude_code_run_installer() {
    local installer
    local installer_output
    local install_status=0
    local curl_bin

    installer=$(mktemp)
    installer_output=$(mktemp)

    if ! curl_bin=$(claude_code_trusted_curl); then
        rm -f "${installer}" "${installer_output}"
        print_warning "Trusted system curl not found. Cannot download Claude Code installer."
        return 1
    fi

    if ! claude_code_run_safely "${curl_bin}" -fsSL --connect-timeout 15 --max-time 120 --retry 2 --retry-delay 2 -o "${installer}" "https://claude.ai/install.sh"; then
        rm -f "${installer}" "${installer_output}"
        print_warning "Failed to download Claude Code installer."
        return 1
    fi

    chmod 700 "${installer}"
    claude_code_run_safely /bin/bash "${installer}" latest > "${installer_output}" 2>&1
    install_status=$?

    rm -f "${installer}" "${installer_output}"

    if [[ "${install_status}" -ne 0 ]]; then
        print_warning "Claude Code installer failed with exit code ${install_status}."
        return 1
    fi

    return 0
}

claude_code_warn_if_shadowed() {
    local original_command="$1"
    local native_path="$2"

    if [[ -z "${original_command}" ]] || [[ "${original_command}" == "${native_path}" ]]; then
        return
    fi

    print_warning "The 'claude' command currently resolves to ${original_command}, not ${native_path}."
    print_warning "Do not use bare 'claude' for Fable login until PATH/package shadowing is resolved; use ${native_path} directly."
}

install_claude_code() {
    if [[ "${BAN_CLAUDE_CODE:-}" == "1" ]]; then
        print_debug "BAN_CLAUDE_CODE=1, skipping Claude Code CLI setup."
        return
    fi

    if ! claude_code_supported_platform; then
        return
    fi

    local native_path
    local native_dir
    local original_command
    local original_path
    local before_version=""
    local after_version=""
    local needs_install=1

    native_path=$(claude_code_native_path)
    native_dir=$(dirname "${native_path}")
    original_path="${SETUP_ORIGINAL_PATH:-${PATH}}"
    original_command="${SETUP_ORIGINAL_CLAUDE_COMMAND:-}"
    if [[ -z "${original_command}" ]]; then
        original_command=$(PATH="${original_path}" command -v claude 2>/dev/null || true)
    fi

    print_message "Installing/updating Claude Code CLI..."
    mkdir -p "${native_dir}"

    if claude_code_path_has_native_provenance "${native_path}"; then
        if before_version=$(claude_code_run_safely "${native_path}" --version 2>/dev/null) && [[ -n "${before_version}" ]]; then
            needs_install=0
            print_debug "Current Claude Code version: ${before_version}"
            if claude_code_run_safely "${native_path}" update > /dev/null 2>&1; then
                print_debug "Claude Code update completed."
            else
                print_warning "Claude Code update failed; keeping existing install."
            fi
        else
            print_warning "Claude Code native binary exists but did not run; reinstalling."
        fi
    elif [[ -e "${native_path}" ]]; then
        print_warning "Claude Code native path appears to be package-managed or invalid; reinstalling native Claude Code."
    fi

    if [[ "${needs_install}" -eq 1 ]]; then
        claude_code_run_installer || return
    fi

    export PATH="${native_dir}:${PATH}"
    if after_version=$(claude_code_run_safely "${native_path}" --version 2>/dev/null) && [[ -n "${after_version}" ]]; then
        print_success "Claude Code CLI installed/updated (${after_version})."
        claude_code_warn_if_shadowed "${original_command}" "${native_path}"
        if [[ -z "${original_command}" ]] && [[ ":${original_path}:" != *":${native_dir}:"* ]]; then
            print_warning "${native_dir} was not on PATH before setup; restart your shell after dotfiles apply or run ${native_path} directly."
        fi
    else
        print_warning "Claude Code CLI install completed, but ${native_path} did not verify."
    fi
}


# Remove the managed footprint of the retired RTK tool.
rtk_binary_is_token_killer() {
    local _binary="$1"
    local _output=""

    [[ -x "${_binary}" ]] || return 1

    if "${_binary}" gain > /dev/null 2>&1; then
        return 0
    fi

    _output=$("${_binary}" --help 2>&1 || true)
    if grep -Eiq 'Rust Token Killer|token-optimized|Initialize rtk instructions' <<< "${_output}"; then
        return 0
    fi

    grep -aEiq -m 1 'Rust Token Killer|rtk-ai/rtk' "${_binary}" 2>/dev/null
}

rtk_note_path() {
    local _path="$1"

    if [[ -e "${_path}" || -L "${_path}" ]]; then
        _rtk_cleanup_had_resources=1
    fi
}

rtk_remove_path() {
    local _path="$1"

    if [[ ! -e "${_path}" && ! -L "${_path}" ]]; then
        return 0
    fi

    if ! rm -rf -- "${_path:?}"; then
        print_error "Failed to remove retired RTK path: ${_path}"
        return 1
    fi

    if [[ -e "${_path}" || -L "${_path}" ]]; then
        print_error "Retired RTK path remains after cleanup: ${_path}"
        return 1
    fi

    _rtk_cleanup_had_resources=1
}

rtk_match_file_mode() {
    local _source="$1"
    local _target="$2"
    local _mode=""

    if chmod --reference="${_source}" "${_target}" 2>/dev/null; then
        return 0
    fi

    _mode=$(stat -f '%Lp' "${_source}" 2>/dev/null || true)
    [[ -n "${_mode}" ]] && chmod "${_mode}" "${_target}"
}

rtk_replace_file_if_changed() {
    local _file="$1"
    local _temporary="$2"

    if cmp -s "${_file}" "${_temporary}"; then
        rm -f -- "${_temporary}"
        return 0
    fi

    if ! rtk_match_file_mode "${_file}" "${_temporary}"; then
        rm -f -- "${_temporary}"
        print_error "Failed to preserve permissions while cleaning RTK from: ${_file}"
        return 1
    fi

    if ! mv -f -- "${_temporary}" "${_file}"; then
        rm -f -- "${_temporary}"
        print_error "Failed to update shared agent file during RTK cleanup: ${_file}"
        return 1
    fi

    _rtk_cleanup_had_resources=1
}

rtk_gemini_md_is_generated() {
    local _file="$1"

    awk '
        BEGIN { in_code = 0; saw_title = 0; invalid = 0 }
        /^```/ { in_code = !in_code; next }
        in_code {
            if ($0 ~ /^[[:space:]]*$/ || $0 ~ /^[[:space:]]*(rtk|which[[:space:]]+rtk)([[:space:]]|$)/) next
            invalid = 1
            next
        }
        /^[[:space:]]*$/ { next }
        /^# RTK([[:space:]-]|$)/ { saw_title = 1; next }
        /^## (Meta Commands|Installation Verification|Hook-Based Usage)/ { next }
        /^\*\*Usage\*\*:/ { next }
        /^⚠️ \*\*Name collision\*\*:/ { next }
        /^(All other commands|Example:|Refer to CLAUDE\.md)/ { next }
        { invalid = 1 }
        END { exit !(saw_title && !invalid && !in_code) }
    ' "${_file}"
}

rtk_assert_gemini_md_safe() {
    local _file="$1"

    [[ -f "${_file}" ]] || return 0
    if ! grep -Eiq '(^|[^[:alnum:]_])rtk([^[:alnum:]_]|$)|Rust Token Killer' "${_file}"; then
        return 0
    fi

    _rtk_cleanup_had_resources=1
    if rtk_gemini_md_is_generated "${_file}"; then
        _rtk_cleanup_remove_gemini_md=1
        return 0
    fi

    print_error "RTK cleanup found mixed user and RTK content in shared file: ${_file}"
    print_error "Move the user content out of this file, then run setup again."
    return 1
}

rtk_clean_instruction_file() {
    local _file="$1"
    local _reference="$2"
    local _temporary=""

    [[ -f "${_file}" ]] || return 0
    if ! grep -Eq '^[[:space:]]*@RTK\.md[[:space:]]*$|^[[:space:]]*@.*/RTK\.md[[:space:]]*$|<!--[[:space:]]*rtk-instructions' "${_file}"; then
        return 0
    fi

    _temporary=$(mktemp "${_file}.rtk-cleanup.XXXXXX") || {
        print_error "Failed to create a temporary file for RTK cleanup: ${_file}"
        return 1
    }

    if ! awk -v managed_reference="${_reference}" '
        BEGIN { in_rtk_block = 0 }
        {
            trimmed = $0
            sub(/^[[:space:]]+/, "", trimmed)
            sub(/[[:space:]]+$/, "", trimmed)

            if (trimmed ~ /^<!--[[:space:]]*rtk-instructions/) {
                in_rtk_block = 1
                next
            }
            if (in_rtk_block) {
                if (trimmed == "<!-- /rtk-instructions -->") in_rtk_block = 0
                next
            }
            if (trimmed == "@RTK.md" || trimmed == managed_reference) next
            print
        }
        END { if (in_rtk_block) exit 42 }
    ' "${_file}" > "${_temporary}"; then
        rm -f -- "${_temporary}"
        print_error "RTK cleanup found an incomplete managed block in: ${_file}"
        return 1
    fi

    rtk_replace_file_if_changed "${_file}" "${_temporary}"
}

rtk_clean_pi_instructions() {
    local _file="$1"
    local _section=""
    local _expected=""
    local _temporary=""

    [[ -f "${_file}" ]] || return 0
    if ! grep -Fq '## RTK token-optimized commands' "${_file}"; then
        return 0
    fi

    _section=$(awk '
        $0 == "## RTK token-optimized commands" { capture = 1 }
        capture && $0 ~ /^## / && $0 != "## RTK token-optimized commands" { exit }
        capture { print }
    ' "${_file}")
    _expected=$(cat <<'RTK_PI_SECTION'
## RTK token-optimized commands

- RTK (`rtk-ai/rtk`) is installed by the machine setup scripts when available. Prefer `rtk <command>` for noisy shell commands with supported filters (`git`, `gh`, tests, build/lint tools, package managers, file/search commands) unless full raw output is required.
- Bypass RTK for one command with `RTK_DISABLED=1 <command>` or by running the raw command directly when exact output formatting matters.
RTK_PI_SECTION
)

    if [[ "${_section}" != "${_expected}" ]]; then
        print_error "RTK cleanup found mixed user and RTK content in shared file: ${_file}"
        print_error "Move the user content out of the RTK section, then run setup again."
        return 1
    fi

    _temporary=$(mktemp "${_file}.rtk-cleanup.XXXXXX") || {
        print_error "Failed to create a temporary file for RTK cleanup: ${_file}"
        return 1
    }

    awk '
        $0 == "## RTK token-optimized commands" { skip = 1; next }
        skip && /^## / { skip = 0 }
        !skip { print }
    ' "${_file}" > "${_temporary}"

    rtk_replace_file_if_changed "${_file}" "${_temporary}"
}

rtk_clean_json_hooks() {
    local _file="$1"
    local _hook_key="$2"
    local _grep_pattern="$3"
    local _command_pattern="$4"
    local _temporary=""

    [[ -f "${_file}" ]] || return 0
    if ! grep -Eq "${_grep_pattern}" "${_file}"; then
        return 0
    fi
    if ! command -v jq > /dev/null 2>&1; then
        print_error "jq is required to remove RTK from shared agent settings: ${_file}"
        return 1
    fi

    _temporary=$(mktemp "${_file}.rtk-cleanup.XXXXXX") || {
        print_error "Failed to create a temporary file for RTK cleanup: ${_file}"
        return 1
    }

    if ! jq --arg hook_key "${_hook_key}" --arg command_pattern "${_command_pattern}" '
        def has_managed_command:
            [.hooks[]? | .command? | strings | test($command_pattern)] | any;

        if ((.hooks? | type) == "object" and (.hooks[$hook_key]? | type) == "array") then
            .hooks[$hook_key] |= map(select((has_managed_command | not)))
        else
            .
        end |
        if ((.hooks? | type) == "object" and (.hooks[$hook_key]? | type) == "array" and (.hooks[$hook_key] | length) == 0) then
            del(.hooks[$hook_key])
        else
            .
        end |
        if ((.hooks? | type) == "object" and (.hooks | length) == 0) then del(.hooks) else . end
    ' "${_file}" > "${_temporary}"; then
        rm -f -- "${_temporary}"
        print_error "Failed to parse shared agent settings during RTK cleanup: ${_file}"
        return 1
    fi

    rtk_replace_file_if_changed "${_file}" "${_temporary}"
}

rtk_run_upstream_uninstall() {
    local _binary="$1"
    local _mode="$2"
    local _config_dir="${3:-}"
    local _output=""

    case "${_mode}" in
        codex)
            if ! _output=$(CODEX_HOME="${_config_dir}" "${_binary}" init -g --codex --uninstall < /dev/null 2>&1); then
                print_debug "RTK Codex uninstall was not available; using deterministic cleanup. ${_output}"
            fi
            ;;
        gemini)
            if ! _output=$("${_binary}" init -g --gemini --uninstall < /dev/null 2>&1); then
                print_debug "RTK Gemini uninstall was not available; using deterministic cleanup. ${_output}"
            fi
            ;;
        *)
            print_error "Unknown RTK uninstall mode: ${_mode}"
            return 1
            ;;
    esac
}

remove_rtk_resources() {
    local _managed_binary="${HOME}/.local/bin/rtk"
    local _binary_is_rtk=0
    local _dir=""
    local _path=""
    local -a _claude_dirs=("${HOME}/.claude")
    local -a _codex_dirs=("${HOME}/.codex")
    local -a _pi_dirs=("${HOME}/.pi/agent")
    local -a _data_dirs=(
        "${HOME}/.config/rtk"
        "${HOME}/.local/share/rtk"
        "${XDG_CONFIG_HOME:-${HOME}/.config}/rtk"
        "${XDG_DATA_HOME:-${HOME}/.local/share}/rtk"
    )
    _rtk_cleanup_had_resources=0
    _rtk_cleanup_remove_gemini_md=0

    if [[ -n "${CLAUDE_CONFIG_DIR:-}" ]]; then
        _claude_dirs+=("${CLAUDE_CONFIG_DIR}")
    fi
    if [[ -n "${CODEX_HOME:-}" ]]; then
        _codex_dirs+=("${CODEX_HOME}")
    fi
    if [[ -n "${PI_CODING_AGENT_DIR:-}" ]]; then
        _pi_dirs+=("${PI_CODING_AGENT_DIR}")
    fi
    if [[ "$(uname -s 2>/dev/null || true)" == "Darwin" ]]; then
        _data_dirs+=("${HOME}/Library/Application Support/rtk")
    fi

    rtk_assert_gemini_md_safe "${HOME}/.gemini/GEMINI.md" || return 1
    for _dir in "${_pi_dirs[@]}"; do
        rtk_clean_pi_instructions "${_dir}/AGENTS.md" || return 1
    done

    if [[ -e "${_managed_binary}" || -L "${_managed_binary}" ]]; then
        if rtk_binary_is_token_killer "${_managed_binary}"; then
            _binary_is_rtk=1
            _rtk_cleanup_had_resources=1
        else
            print_warning "Preserving unrelated or unverified rtk command at ${_managed_binary}."
        fi
    fi

    if [[ "${_binary_is_rtk}" -eq 1 ]]; then
        for _dir in "${_codex_dirs[@]}"; do
            rtk_run_upstream_uninstall "${_managed_binary}" codex "${_dir}"
        done
        if [[ ! -f "${HOME}/.gemini/GEMINI.md" || "${_rtk_cleanup_remove_gemini_md}" -eq 1 ]]; then
            rtk_run_upstream_uninstall "${_managed_binary}" gemini
        else
            print_debug "Preserving unrelated Gemini instructions and using deterministic RTK cleanup."
        fi
    fi

    for _dir in "${_claude_dirs[@]}"; do
        rtk_clean_instruction_file "${_dir}/CLAUDE.md" '@RTK.md' || return 1
        rtk_clean_json_hooks \
            "${_dir}/settings.json" \
            'PreToolUse' \
            'rtk hook claude|rtk-rewrite\.sh' \
            '(^|[/\\])rtk-rewrite\.sh([[:space:]]|$)|^rtk hook claude([[:space:]]|$)' || return 1
        rtk_remove_path "${_dir}/RTK.md" || return 1
        rtk_remove_path "${_dir}/hooks/rtk-rewrite.sh" || return 1
        rtk_remove_path "${_dir}/hooks/.rtk-hook.sha256" || return 1
    done

    for _dir in "${_codex_dirs[@]}"; do
        rtk_clean_instruction_file "${_dir}/AGENTS.md" "@${_dir}/RTK.md" || return 1
        rtk_remove_path "${_dir}/RTK.md" || return 1
    done

    rtk_clean_json_hooks \
        "${HOME}/.gemini/settings.json" \
        'BeforeTool' \
        'rtk hook gemini|rtk-hook-gemini\.sh' \
        '(^|[/\\])rtk-hook-gemini\.sh([[:space:]]|$)|^rtk hook gemini([[:space:]]|$)' || return 1
    rtk_remove_path "${HOME}/.gemini/hooks/rtk-hook-gemini.sh" || return 1
    rtk_remove_path "${HOME}/.gemini/hooks/.rtk-hook.sha256" || return 1
    if [[ "${_rtk_cleanup_remove_gemini_md}" -eq 1 ]]; then
        rtk_remove_path "${HOME}/.gemini/GEMINI.md" || return 1
    fi
    rtk_remove_path "${HOME}/.config/opencode/plugins/rtk.ts" || return 1

    for _path in "${_data_dirs[@]}"; do
        rtk_note_path "${_path}"
        rtk_remove_path "${_path}" || return 1
    done

    if [[ "${_binary_is_rtk}" -eq 1 ]]; then
        rtk_remove_path "${_managed_binary}" || return 1
        hash -r 2>/dev/null || true
    fi

    if [[ "${_rtk_cleanup_had_resources}" -eq 1 ]]; then
        print_success "Legacy RTK resources removed."
    else
        print_debug "No legacy RTK resources found."
    fi
}

# Check whether the active Node.js runtime can run current Pi packages.
pi_node_runtime_ready() {
    command -v node &> /dev/null || return 1
    node -e 'const [major, minor] = process.versions.node.split(".").map(Number); process.exit(major > 20 || (major === 20 && minor >= 6) ? 0 : 1)' >/dev/null 2>&1
}

# Ensure Pi runs with a Node.js version new enough for current @earendil-works packages.
ensure_pi_node_runtime() {
    local _runtime="node@24"

    if pi_node_runtime_ready; then
        print_debug "Node.js $(node --version || true) is ready for Pi."
        return 0
    fi

    if [[ -d "${HOME}/.local/bin" ]]; then
        export PATH="${HOME}/.local/bin:${PATH}"
    fi

    if [[ -d "${HOME}/.mise/bin" ]]; then
        export PATH="${HOME}/.mise/bin:${PATH}"
    fi

    if ! command -v mise &> /dev/null; then
        print_warning "Node.js >=20.6 is required for Pi, but mise is not available to install it."
        print_debug "Install mise, then run: mise use -g -y ${_runtime}"
        return 1
    fi

    print_message "Ensuring Node.js 24 runtime for Pi..."
    if ! mise use -g -y "${_runtime}" > /dev/null; then
        print_warning "Failed to install/configure ${_runtime} with mise."
        return 1
    fi

    local _mise_env=""
    if ! _mise_env=$(mise env -C "${HOME}" -s bash "${_runtime}"); then
        print_warning "Failed to generate mise environment for ${_runtime}."
        return 1
    fi

    if ! eval "${_mise_env}"; then
        print_warning "Failed to activate ${_runtime} with mise."
        return 1
    fi

    if pi_node_runtime_ready; then
        print_success "Node.js $(node --version || true) is ready for Pi."
        return 0
    fi

    print_warning "Node.js >=20.6 is still not active after installing ${_runtime}."
    return 1
}

# Remove the managed footprint of the retired Attention-kind guidance.
attention_span_cleanup_prepare_file_mode() {
    local _staged_file="$1"
    local _target_file="$2"
    local _mode=""

    if [[ -e "${_target_file}" ]]; then
        _mode=$(stat -c '%a' "${_target_file}" 2>/dev/null || stat -f '%Lp' "${_target_file}" 2>/dev/null || true)
    fi
    if [[ -n "${_mode}" ]]; then
        chmod "${_mode}" "${_staged_file}"
    else
        chmod 600 "${_staged_file}"
    fi
}

attention_span_cleanup_style_is_safe() {
    local _style_file="$1"

    [[ -e "${_style_file}" || -L "${_style_file}" ]] || return 0
    [[ -L "${_style_file}" || -f "${_style_file}" ]] || {
        print_warning "Attention-kind style target is not a file or symlink: ${_style_file}"
        return 1
    }
}

attention_span_cleanup_settings_is_safe() {
    local _settings_file="$1"

    [[ -e "${_settings_file}" || -L "${_settings_file}" ]] || return 0
    if [[ -L "${_settings_file}" ]]; then
        print_warning "Cannot safely remove Attention-kind from symlinked Claude settings: ${_settings_file}"
        return 1
    fi
    if [[ ! -f "${_settings_file}" ]]; then
        print_warning "Claude settings target is not a regular file: ${_settings_file}"
        return 1
    fi
    if ! command -v jq > /dev/null 2>&1; then
        print_warning "jq is required to remove Attention-kind from Claude settings: ${_settings_file}"
        return 1
    fi
    if ! jq -e 'type == "object"' "${_settings_file}" > /dev/null 2>&1; then
        print_warning "Claude settings are not a valid JSON object: ${_settings_file}"
        return 1
    fi
}

attention_span_cleanup_managed_file_is_safe() {
    local _target_file="$1"
    local _begin_marker="<!-- attention-span:start -->"
    local _end_marker="<!-- attention-span:end -->"
    local _begin_count=0
    local _end_count=0
    local _begin_line=""
    local _end_line=""

    [[ -e "${_target_file}" || -L "${_target_file}" ]] || return 0
    if [[ -L "${_target_file}" ]]; then
        print_warning "Cannot safely remove Attention-kind from symlinked shared instructions: ${_target_file}"
        return 1
    fi
    if [[ ! -f "${_target_file}" ]]; then
        print_warning "Shared instruction target is not a regular file: ${_target_file}"
        return 1
    fi

    _begin_count=$(grep -Fxc -- "${_begin_marker}" "${_target_file}" || true)
    _end_count=$(grep -Fxc -- "${_end_marker}" "${_target_file}" || true)
    if [[ "${_begin_count}" -eq 0 && "${_end_count}" -eq 0 ]]; then
        return 0
    fi
    if [[ "${_begin_count}" -ne 1 || "${_end_count}" -ne 1 ]]; then
        print_warning "Attention-kind markers are malformed in ${_target_file}; leaving it unchanged."
        return 1
    fi

    _begin_line=$(grep -nFx -- "${_begin_marker}" "${_target_file}" || true)
    _begin_line=${_begin_line%%:*}
    _end_line=$(grep -nFx -- "${_end_marker}" "${_target_file}" || true)
    _end_line=${_end_line%%:*}
    if [[ "${_begin_line}" -ge "${_end_line}" ]]; then
        print_warning "Attention-kind markers are malformed in ${_target_file}; leaving it unchanged."
        return 1
    fi
}

attention_span_cleanup_remove_style() {
    local _style_file="$1"

    [[ -e "${_style_file}" || -L "${_style_file}" ]] || return 0
    if ! rm -f -- "${_style_file}" || [[ -e "${_style_file}" || -L "${_style_file}" ]]; then
        print_warning "Failed to remove retired Attention-kind style: ${_style_file}"
        return 1
    fi
    _attention_span_cleanup_removed=1
}

attention_span_cleanup_remove_setting() {
    local _settings_file="$1"
    local _tmp_file=""

    attention_span_cleanup_settings_is_safe "${_settings_file}" || return 1
    [[ -f "${_settings_file}" ]] || return 0
    if ! jq -e '.outputStyle? == "Attention-kind"' "${_settings_file}" > /dev/null; then
        return 0
    fi
    if ! _tmp_file=$(mktemp "${_settings_file}.XXXXXX"); then
        print_warning "Could not create a temporary file for Claude settings cleanup: ${_settings_file}"
        return 1
    fi
    if jq 'del(.outputStyle)' "${_settings_file}" > "${_tmp_file}" &&
        attention_span_cleanup_prepare_file_mode "${_tmp_file}" "${_settings_file}" &&
        mv -f -- "${_tmp_file}" "${_settings_file}"; then
        _attention_span_cleanup_removed=1
        return 0
    fi

    rm -f -- "${_tmp_file}"
    print_warning "Failed to remove Attention-kind from Claude settings: ${_settings_file}"
    return 1
}

attention_span_cleanup_remove_managed_block() {
    local _target_file="$1"
    local _begin_marker="<!-- attention-span:start -->"
    local _end_marker="<!-- attention-span:end -->"
    local _tmp_file=""

    attention_span_cleanup_managed_file_is_safe "${_target_file}" || return 1
    [[ -f "${_target_file}" ]] || return 0
    if ! grep -Fqx -- "${_begin_marker}" "${_target_file}"; then
        return 0
    fi
    if ! _tmp_file=$(mktemp "${_target_file}.XXXXXX"); then
        print_warning "Could not create a temporary file for Attention-kind cleanup: ${_target_file}"
        return 1
    fi
    if awk -v begin="${_begin_marker}" -v end="${_end_marker}" '
        $0 == begin { in_block = 1; next }
        $0 == end && in_block { in_block = 0; next }
        !in_block { print }
        END { exit in_block ? 1 : 0 }
    ' "${_target_file}" > "${_tmp_file}" &&
        attention_span_cleanup_prepare_file_mode "${_tmp_file}" "${_target_file}" &&
        mv -f -- "${_tmp_file}" "${_target_file}"; then
        _attention_span_cleanup_removed=1
        return 0
    fi

    rm -f -- "${_tmp_file}"
    print_warning "Failed to safely remove Attention-kind from ${_target_file}."
    return 1
}

remove_attention_span_resources() {
    local _default_claude_dir="${HOME}/.claude"
    local _active_claude_dir="${CLAUDE_CONFIG_DIR:-${_default_claude_dir}}"
    local _default_codex_dir="${HOME}/.codex"
    local _active_codex_dir="${CODEX_HOME:-${_default_codex_dir}}"
    local _default_pi_dir="${HOME}/.pi/agent"
    local _active_pi_dir="${PI_CODING_AGENT_DIR:-${_default_pi_dir}}"
    local _dir=""
    local _managed_file=""
    local -a _claude_dirs=("${_default_claude_dir}")
    local -a _codex_dirs=("${_default_codex_dir}")
    local -a _pi_dirs=("${_default_pi_dir}")
    local -a _managed_files=()
    _attention_span_cleanup_removed=0

    [[ "${_active_claude_dir}" == "${_default_claude_dir}" ]] || _claude_dirs+=("${_active_claude_dir}")
    [[ "${_active_codex_dir}" == "${_default_codex_dir}" ]] || _codex_dirs+=("${_active_codex_dir}")
    [[ "${_active_pi_dir}" == "${_default_pi_dir}" ]] || _pi_dirs+=("${_active_pi_dir}")

    for _dir in "${_codex_dirs[@]}"; do
        _managed_files+=("${_dir}/AGENTS.md")
    done
    _managed_files+=("${HOME}/.gemini/GEMINI.md")
    for _dir in "${_pi_dirs[@]}"; do
        _managed_files+=("${_dir}/APPEND_SYSTEM.md")
    done

    # Preflight every target before changing any file.
    for _dir in "${_claude_dirs[@]}"; do
        attention_span_cleanup_style_is_safe "${_dir}/output-styles/attention-kind.md" || return 1
        attention_span_cleanup_settings_is_safe "${_dir}/settings.json" || return 1
    done
    for _managed_file in "${_managed_files[@]}"; do
        attention_span_cleanup_managed_file_is_safe "${_managed_file}" || return 1
    done

    for _dir in "${_claude_dirs[@]}"; do
        attention_span_cleanup_remove_style "${_dir}/output-styles/attention-kind.md" || return 1
        attention_span_cleanup_remove_setting "${_dir}/settings.json" || return 1
    done
    for _managed_file in "${_managed_files[@]}"; do
        attention_span_cleanup_remove_managed_block "${_managed_file}" || return 1
    done

    if [[ "${_attention_span_cleanup_removed}" -eq 1 ]]; then
        print_success "Retired Attention-kind guidance removed."
    else
        print_debug "No retired Attention-kind guidance found."
    fi
}

# Check whether the active Node.js runtime can run the current skills CLI.
skills_cli_node_runtime_ready() {
    command -v node &> /dev/null || return 1
    node -e 'const [major, minor] = process.versions.node.split(".").map(Number); process.exit(major > 22 || (major === 22 && minor >= 20) ? 0 : 1)' >/dev/null 2>&1
}

# Ensure the skills CLI runs on its required Node.js version.
ensure_skills_cli_node_runtime() {
    local _runtime="node@24"

    if skills_cli_node_runtime_ready; then
        print_debug "Node.js $(node --version || true) is ready for the skills CLI."
        return 0
    fi

    if [[ -d "${HOME}/.local/bin" ]]; then
        export PATH="${HOME}/.local/bin:${PATH}"
    fi

    if [[ -d "${HOME}/.mise/bin" ]]; then
        export PATH="${HOME}/.mise/bin:${PATH}"
    fi

    if ! command -v mise &> /dev/null; then
        print_warning "Node.js >=22.20 is required for the skills CLI, but mise is not available to install it."
        print_debug "Install mise, then run: mise use -g -y ${_runtime}"
        return 1
    fi

    print_message "Ensuring Node.js 24 runtime for the skills CLI..."
    if ! mise use -g -y "${_runtime}" > /dev/null; then
        print_warning "Failed to install/configure ${_runtime} with mise."
        return 1
    fi

    local _mise_env=""
    if ! _mise_env=$(mise env -C "${HOME}" -s bash "${_runtime}"); then
        print_warning "Failed to generate mise environment for ${_runtime}."
        return 1
    fi

    if ! eval "${_mise_env}"; then
        print_warning "Failed to activate ${_runtime} with mise."
        return 1
    fi

    if skills_cli_node_runtime_ready; then
        print_success "Node.js $(node --version || true) is ready for the skills CLI."
        return 0
    fi

    print_warning "Node.js >=22.20 is still not active after installing ${_runtime}."
    return 1
}

# Install/update one copied global skill for every supported AI coding harness.
install_managed_agent_skill() {
    local _repository=$1
    local _skill_name=$2
    local _display_name=$3
    local _install_output=""
    local _skill_dir=""
    local _skill_file=""
    # Codex, Gemini CLI, and Pi discover the skills CLI's shared user copy.
    local -a _skill_files=(
        "${CLAUDE_CONFIG_DIR:-${HOME}/.claude}/skills/${_skill_name}/SKILL.md"
        "${HOME}/.agents/skills/${_skill_name}/SKILL.md"
    )

    if ! ensure_skills_cli_node_runtime; then
        return 1
    fi

    if ! command -v npx &> /dev/null; then
        print_warning "npx is not available; cannot install the ${_display_name} skill."
        return 1
    fi

    print_message "Installing/updating ${_display_name} across AI harnesses..."
    if ! _install_output=$(npx --yes skills@latest add "${_repository}" \
        --global \
        --agent claude-code \
        --agent codex \
        --agent gemini-cli \
        --skill "${_skill_name}" \
        --copy \
        --yes < /dev/null 2>&1); then
        print_warning "Failed to install/update the ${_display_name} skill."
        print_debug "${_install_output}"
        return 1
    fi

    for _skill_file in "${_skill_files[@]}"; do
        _skill_dir=${_skill_file%/SKILL.md}
        if [[ -L "${_skill_dir}" || -L "${_skill_file}" ]]; then
            print_warning "${_display_name} validation failed: copied artifact is a symlink at ${_skill_file}."
            return 1
        fi
        if [[ ! -f "${_skill_file}" ]]; then
            print_warning "${_display_name} validation failed: missing ${_skill_file}."
            return 1
        fi
    done

    print_success "${_display_name} installed/updated for Claude Code, Codex, Gemini CLI, and Pi through the shared skill path."
    print_debug "${_install_output}"
}

# Preserve the named Simple English setup interface.
setup_simple_english_skill() {
    install_managed_agent_skill "AminBlg/SimpleEnglish" "simple-english" "Simple English"
}

# Install/update HumanLayer show-me for every supported AI coding harness.
setup_show_me_skill() {
    install_managed_agent_skill "humanlayer/skills" "show-me" "show-me"
}

# Remove setup-managed Impeccable resources without affecting sibling agent tooling.
remove_impeccable_resources() {
    local -a _paths=(
        "${HOME}/.claude/skills/impeccable"
        "${HOME}/.agents/skills/impeccable"
        "${HOME}/.cursor/skills/impeccable"
        "${HOME}/.gemini/skills/impeccable"
        "${HOME}/.pi/agent/skills/impeccable"
        "${HOME}/.cursor/agents/impeccable-manual-edit-applier.md"
        "${HOME}/.cursor/agents/impeccable-asset-producer.md"
        "${HOME}/.cursor/agents/impeccable-documenter.md"
        "${HOME}/.cursor/agents/impeccable-finish-reviewer.md"
    )
    local -a _failed=()
    local _path=""
    local _removed=0

    for _path in "${_paths[@]}"; do
        if [[ ! -e "${_path}" && ! -L "${_path}" ]]; then
            continue
        fi

        if [[ -L "${_path}" ]] || [[ ! -d "${_path}" ]]; then
            if rm -f -- "${_path}"; then
                _removed=1
            else
                _failed+=("${_path}")
            fi
        elif rm -rf -- "${_path}"; then
            _removed=1
        else
            _failed+=("${_path}")
        fi
    done

    if (( ${#_failed[@]} > 0 )); then
        print_warning "Failed to remove legacy Impeccable resources: ${_failed[*]}"
    elif (( _removed == 1 )); then
        print_success "Legacy Impeccable resources removed."
    else
        print_debug "No legacy Impeccable resources found."
    fi
}

# Resolve the Pi command target across Linux, macOS, and WSL.
pi_command_target() {
    local _pi_cmd=""
    local _link_target=""
    local _link_dir=""

    if ! command -v pi &> /dev/null; then
        return 1
    fi

    _pi_cmd=$(command -v pi)

    if command -v realpath &> /dev/null; then
        realpath "${_pi_cmd}" 2>/dev/null && return 0
    fi

    if readlink -f "${_pi_cmd}" > /dev/null 2>&1; then
        readlink -f "${_pi_cmd}" 2>/dev/null && return 0
    fi

    if [[ -L "${_pi_cmd}" ]]; then
        _link_target=$(readlink "${_pi_cmd}" 2>/dev/null || true)
        if [[ "${_link_target}" == /* ]]; then
            printf '%s\n' "${_link_target}"
        elif [[ -n "${_link_target}" ]]; then
            _link_dir=$(cd "$(dirname "${_pi_cmd}")" && pwd -P)
            printf '%s\n' "${_link_dir}/${_link_target}"
        else
            printf '%s\n' "${_pi_cmd}"
        fi
    else
        printf '%s\n' "${_pi_cmd}"
    fi
}

# Remove stale Pi installs from Bun-managed global locations.
cleanup_noncanonical_pi_installs() {
    local _new_package="${1}"
    local _old_package="${2}"
    local _bun_cmd=""
    local _global_packages=""
    local _package=""
    local _path=""
    local _removed=0

    if command -v bun &> /dev/null; then
        _bun_cmd=$(command -v bun)
    elif [[ -x "${HOME}/.bun/bin/bun" ]]; then
        _bun_cmd="${HOME}/.bun/bin/bun"
    elif [[ -x "${HOME}/.cache/.bun/bin/bun" ]]; then
        _bun_cmd="${HOME}/.cache/.bun/bin/bun"
    fi

    if [[ -n "${_bun_cmd}" ]]; then
        _global_packages=$("${_bun_cmd}" pm ls -g 2>/dev/null || true)
        for _package in "${_new_package}" "${_old_package}"; do
            if grep -Fq "${_package}" <<< "${_global_packages}"; then
                print_message "Removing non-canonical Bun Pi package ${_package}..."
                if "${_bun_cmd}" remove -g "${_package}" > /dev/null 2>&1; then
                    _removed=1
                else
                    print_warning "Failed to remove Bun Pi package ${_package}."
                fi
            fi
        done
    fi

    for _path in \
        "${HOME}/.bun/bin/pi" \
        "${HOME}/.cache/.bun/bin/pi" \
        "${HOME}/.bun/install/global/node_modules/@earendil-works/pi-coding-agent" \
        "${HOME}/.bun/install/global/node_modules/@earendil-works/pi-agent-core" \
        "${HOME}/.bun/install/global/node_modules/@earendil-works/pi-ai" \
        "${HOME}/.bun/install/global/node_modules/@earendil-works/pi-tui" \
        "${HOME}/.bun/install/global/node_modules/@mariozechner/pi-coding-agent" \
        "${HOME}/.bun/install/global/node_modules/@mariozechner/pi-agent-core" \
        "${HOME}/.bun/install/global/node_modules/@mariozechner/pi-ai" \
        "${HOME}/.bun/install/global/node_modules/@mariozechner/pi-tui" \
        "${HOME}/.cache/.bun/install/global/node_modules/@earendil-works/pi-coding-agent" \
        "${HOME}/.cache/.bun/install/global/node_modules/@earendil-works/pi-agent-core" \
        "${HOME}/.cache/.bun/install/global/node_modules/@earendil-works/pi-ai" \
        "${HOME}/.cache/.bun/install/global/node_modules/@earendil-works/pi-tui" \
        "${HOME}/.cache/.bun/install/global/node_modules/@mariozechner/pi-coding-agent" \
        "${HOME}/.cache/.bun/install/global/node_modules/@mariozechner/pi-agent-core" \
        "${HOME}/.cache/.bun/install/global/node_modules/@mariozechner/pi-ai" \
        "${HOME}/.cache/.bun/install/global/node_modules/@mariozechner/pi-tui"; do
        if [[ -e "${_path}" || -L "${_path}" ]]; then
            if rm -rf -- "${_path}"; then
                _removed=1
            else
                print_warning "Failed to remove non-canonical Pi path: ${_path}"
            fi
        fi
    done

    if [[ "${_removed}" -eq 1 ]]; then
        hash -r 2>/dev/null || true
        print_success "Removed non-canonical Bun Pi installs."
    else
        print_debug "No non-canonical Bun Pi installs found."
    fi
}

# Force Pi defaults: Kimi K3 (Synthetic) as the default model, or GLM-5.3
# (z.ai GLM Coding Plan) on work machines that have a z.ai API key.
# Chezmoi owns ~/.pi/agent/settings.json long-term; this seeds the desired
# state on fresh machines and repairs drift where dotfiles are not applied.
configure_pi_defaults() {
    local _agent_dir="${PI_CODING_AGENT_DIR:-${HOME}/.pi/agent}"
    local _settings_file="${_agent_dir}/settings.json"
    local _tmp=""
    local _jq_expr=""
    local _default_desc="Kimi K3 (Synthetic)"

    if ! command -v jq &> /dev/null; then
        print_warning "jq not found. Cannot set Pi default model in ${_settings_file}."
        return 1
    fi

    mkdir -p "${_agent_dir}"
    if [[ -L "${_settings_file}" ]]; then
        print_debug "Pi settings at ${_settings_file} are symlinked (chezmoi-managed); writing defaults through the link."
    elif [[ ! -f "${_settings_file}" ]]; then
        printf '{}\n' > "${_settings_file}"
    fi

    if ! _tmp=$(mktemp); then
        print_warning "Could not create a temporary file for Pi defaults at ${_settings_file}."
        return 1
    fi

    if [[ "${WORK_MACHINE:-}" == "1" ]] && pi_zai_key_available; then
        _default_desc="GLM-5.3 (z.ai)"
        _jq_expr='
            .defaultProvider = "zai"
            | .defaultModel = "glm-5.3"
            | .defaultThinkingLevel = "high"
        '
    else
        _jq_expr='
            .defaultProvider = "synthetic"
            | .defaultModel = "hf:moonshotai/Kimi-K3"
            | .defaultThinkingLevel = "high"
        '
    fi

    if jq "${_jq_expr}" "${_settings_file}" > "${_tmp}"; then
        if cat "${_tmp}" > "${_settings_file}"; then
            rm -f "${_tmp}"
            print_success "Pi default model set to ${_default_desc} with high thinking."
            return 0
        fi
        rm -f "${_tmp}"
        print_warning "Failed to write Pi defaults to ${_settings_file}."
        return 1
    fi

    rm -f "${_tmp}"
    print_warning "Failed to parse Pi settings at ${_settings_file}; leaving defaults unchanged."
    return 1
}

# shellcheck disable=SC2312
# Read a KEY=VALUE pair from ~/.env.local (strips optional export/quotes).
read_env_local_value() {
    local _key="$1"
    local _env_file="${HOME}/.env.local"
    local _line=""
    local _value=""

    [[ -f "${_env_file}" ]] || return 1

    _line=$(grep -E "^[[:space:]]*(export[[:space:]]+)?${_key}=" "${_env_file}" | tail -n 1) || return 1
    _value="${_line#*=}"
    _value="${_value#\"}" && _value="${_value%\"}"
    _value="${_value#\'}" && _value="${_value%\'}"
    [[ -n "${_value}" ]] || return 1
    printf '%s\n' "${_value}"
}

# Check whether a z.ai API key is available from ~/.env.local or from an
# existing z.ai provider block in Pi's models.json.
pi_zai_key_available() {
    local _agent_dir="${PI_CODING_AGENT_DIR:-${HOME}/.pi/agent}"
    local _models_file="${_agent_dir}/models.json"

    if read_env_local_value "ZAI_API_KEY" > /dev/null 2>&1; then
        return 0
    fi
    if [[ -f "${_models_file}" ]] \
        && jq -e '.providers.zai.apiKey // empty | length > 0' "${_models_file}" > /dev/null 2>&1; then
        return 0
    fi
    return 1
}

# Seed the Synthetic provider block (Kimi K3) into Pi's models.json.
# The API key comes from SYNTHETIC_API_KEY in ~/.env.local; it is never
# stored in this repository. Existing synthetic keys are preserved.
seed_pi_synthetic_models() {
    local _agent_dir="${PI_CODING_AGENT_DIR:-${HOME}/.pi/agent}"
    local _models_file="${_agent_dir}/models.json"
    local _api_key=""
    local _tmp=""

    if ! command -v jq &> /dev/null; then
        print_warning "jq not found. Cannot seed Synthetic provider in ${_models_file}."
        return 1
    fi

    if [[ -f "${_models_file}" ]] && jq -e '.providers.synthetic.apiKey // empty | length > 0' "${_models_file}" > /dev/null 2>&1; then
        print_debug "Synthetic provider with an API key already configured in ${_models_file}."
        return 0
    fi

    if ! _api_key=$(read_env_local_value "SYNTHETIC_API_KEY"); then
        print_warning "SYNTHETIC_API_KEY not set in ~/.env.local. Kimi K3 (Synthetic) is the Pi default but has no API key yet; add the key and rerun setup."
        return 1
    fi

    mkdir -p "${_agent_dir}"
    if [[ ! -f "${_models_file}" ]]; then
        printf '{"providers":{}}\n' > "${_models_file}"
    fi

    if ! _tmp=$(mktemp); then
        print_warning "Could not create a temporary file for Pi models at ${_models_file}."
        return 1
    fi

    if jq --arg apiKey "${_api_key}" '
        .providers = (.providers // {})
        | .providers.synthetic = {
            baseUrl: "https://api.synthetic.new/v1",
            api: "openai-completions",
            apiKey: ((.providers.synthetic.apiKey // "") | if length > 0 then . else $apiKey end),
            compat: {
                supportsDeveloperRole: false,
                supportsStore: false,
                maxTokensField: "max_tokens",
                supportsStrictMode: false,
                deferredToolsMode: "kimi"
            },
            models: [
                {
                    id: "hf:moonshotai/Kimi-K3",
                    name: "Kimi K3 (Synthetic)",
                    reasoning: true,
                    thinkingLevelMap: {
                        off: null,
                        minimal: null,
                        low: "low",
                        medium: null,
                        high: "high",
                        xhigh: null,
                        max: "max"
                    },
                    input: ["text", "image"],
                    contextWindow: 512000,
                    maxTokens: 131072,
                    cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
                    compat: {
                        supportsReasoningEffort: true,
                        thinkingFormat: "openai",
                        requiresReasoningContentOnAssistantMessages: true
                    }
                }
            ]
        }
    ' "${_models_file}" > "${_tmp}"; then
        if cat "${_tmp}" > "${_models_file}" && chmod 600 "${_models_file}"; then
            rm -f "${_tmp}"
            print_success "Synthetic provider (Kimi K3) seeded in ${_models_file}."
            return 0
        fi
        rm -f "${_tmp}"
        print_warning "Failed to write Synthetic provider to ${_models_file}."
        return 1
    fi

    rm -f "${_tmp}"
    print_warning "Failed to parse Pi models at ${_models_file}; leaving it unchanged."
    return 1
}
# Seed the z.ai provider block (GLM Coding Plan) into Pi's models.json.
# The API key comes from ZAI_API_KEY in ~/.env.local; it is never stored in
# this repository. Existing z.ai keys are preserved. Seeding follows key
# presence: any machine with the key gets the provider, and only work
# machines are warned when the key is missing.
seed_pi_zai_models() {
    local _agent_dir="${PI_CODING_AGENT_DIR:-${HOME}/.pi/agent}"
    local _models_file="${_agent_dir}/models.json"
    local _api_key=""
    local _tmp=""

    if ! command -v jq &> /dev/null; then
        print_warning "jq not found. Cannot seed z.ai provider in ${_models_file}."
        return 1
    fi

    if [[ -f "${_models_file}" ]] && jq -e '.providers.zai.apiKey // empty | length > 0' "${_models_file}" > /dev/null 2>&1; then
        print_debug "z.ai provider with an API key already configured in ${_models_file}."
        return 0
    fi

    if ! _api_key=$(read_env_local_value "ZAI_API_KEY"); then
        if [[ "${WORK_MACHINE:-}" == "1" ]]; then
            print_warning "ZAI_API_KEY not set in ~/.env.local. Work machines default Pi to GLM-5.3 (z.ai) but there is no API key yet; add the key and rerun setup."
            return 1
        fi
        print_debug "ZAI_API_KEY not set in ~/.env.local; skipping z.ai provider seeding."
        return 0
    fi

    mkdir -p "${_agent_dir}"
    if [[ ! -f "${_models_file}" ]]; then
        printf '{"providers":{}}\n' > "${_models_file}"
    fi

    if ! _tmp=$(mktemp); then
        print_warning "Could not create a temporary file for Pi models at ${_models_file}."
        return 1
    fi

    if jq --arg apiKey "${_api_key}" '
        .providers = (.providers // {})
        | .providers.zai = {
            baseUrl: "https://api.z.ai/api/coding/paas/v4",
            api: "openai-completions",
            apiKey: ((.providers.zai.apiKey // "") | if length > 0 then . else $apiKey end),
            compat: {
                supportsDeveloperRole: false,
                supportsStore: false,
                maxTokensField: "max_tokens",
                supportsStrictMode: false
            },
            models: [
                {
                    id: "glm-5.3",
                    name: "GLM-5.3 (z.ai)",
                    reasoning: true,
                    thinkingLevelMap: {
                        off: null,
                        minimal: null,
                        low: "low",
                        medium: null,
                        high: "high",
                        xhigh: null,
                        max: "max"
                    },
                    input: ["text"],
                    contextWindow: 1000000,
                    maxTokens: 131072,
                    cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
                    compat: {
                        supportsReasoningEffort: true,
                        thinkingFormat: "openai"
                    }
                },
                {
                    id: "glm-5-turbo",
                    name: "GLM-5-Turbo (z.ai)",
                    reasoning: true,
                    thinkingLevelMap: {
                        off: "none",
                        minimal: "minimal",
                        low: "low",
                        medium: "medium",
                        high: "high",
                        xhigh: "xhigh",
                        max: "max"
                    },
                    input: ["text"],
                    contextWindow: 200000,
                    maxTokens: 131072,
                    cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
                    compat: {
                        supportsReasoningEffort: true,
                        thinkingFormat: "openai"
                    }
                },
                {
                    id: "glm-4.7",
                    name: "GLM-4.7 (z.ai)",
                    reasoning: true,
                    input: ["text"],
                    contextWindow: 200000,
                    maxTokens: 131072,
                    cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
                    compat: {
                        supportsReasoningEffort: false,
                        thinkingFormat: "openai"
                    }
                }
            ]
        }
    ' "${_models_file}" > "${_tmp}"; then
        if cat "${_tmp}" > "${_models_file}" && chmod 600 "${_models_file}"; then
            rm -f "${_tmp}"
            print_success "z.ai provider (GLM Coding Plan) seeded in ${_models_file}."
            return 0
        fi
        rm -f "${_tmp}"
        print_warning "Failed to write z.ai provider to ${_models_file}."
        return 1
    fi

    rm -f "${_tmp}"
    print_warning "Failed to parse Pi models at ${_models_file}; leaving it unchanged."
    return 1
}

# Validate and repair npm's effective user configuration before setup mutates
# any npm-owned package tree. npm handles registry-scoped auth migration without
# exposing configuration values in the setup log.
NPM_CONFIGURATION_COMMAND=""
ensure_npm_configuration() {
    local _npm_command=""

    _npm_command=$(command -v npm 2>/dev/null || true)
    if [[ -z "${_npm_command}" ]]; then
        print_warning "npm not found. Cannot validate npm configuration."
        return 1
    fi
    if [[ "${NPM_CONFIGURATION_COMMAND}" == "${_npm_command}" ]]; then
        return 0
    fi

    if ! npm config fix > /dev/null 2>&1 || ! npm config list --location=user > /dev/null 2>&1; then
        print_error "npm configuration is invalid and automatic repair failed."
        print_debug "Run 'npm config fix', review the user npmrc, and rerun setup."
        return 1
    fi

    NPM_CONFIGURATION_COMMAND="${_npm_command}"
    print_debug "npm configuration validated."
}

# Install/update Pi coding agent
install_pi_cli() {
    local _new_package="@earendil-works/pi-coding-agent"
    local _old_package="@mariozechner/pi-coding-agent"
    local _local_prefix="${HOME}/.local"
    local _canonical_bin="${_local_prefix}/bin"
    local _canonical_pi="${_canonical_bin}/pi"
    local _canonical_package_dir="${_local_prefix}/lib/node_modules/${_new_package}"
    local _pi_cmd=""
    local _pi_link_target=""
    local _pi_commands=""
    local _pi_commands_inline=""
    local _pi_target=""
    local _pi_version=""
    local _path_entry=""

    print_message "Installing/updating Pi coding agent..."

    mkdir -p "${_canonical_bin}"
    export PATH="${_canonical_bin}:${PATH}"
    if command -v fish &> /dev/null; then
        fish -lc "fish_add_path -m \"${HOME}/.local/bin\"" > /dev/null 2>&1 || print_debug "Could not persist ~/.local/bin path preference with fish_add_path."
    fi

    if ! ensure_pi_node_runtime; then
        print_warning "Skipping Pi installation and extension setup because the Pi Node.js runtime is not ready."
        return 1
    fi

    if ! command -v npm &> /dev/null; then
        print_warning "npm not found. Cannot install Pi coding agent."
        print_debug "Install Node.js/npm, then run: npm install -g --ignore-scripts --prefix \"${_local_prefix}\" ${_new_package}@latest"
        return 1
    fi

    ensure_npm_configuration || return 1

    # Remove old npm-package ownership before installing so npm can claim ~/.local/bin/pi.
    npm uninstall -g --prefix "${_local_prefix}" "${_old_package}" > /dev/null 2>&1 || true
    if [[ -L "${_canonical_pi}" ]]; then
        _pi_target=$(pi_command_target 2>/dev/null || true)
        if [[ "${_pi_target}" == *"/.bun/"* || "${_pi_target}" == *"/.cache/.bun/"* || "${_pi_target}" == *"${_old_package}"* ]]; then
            rm -f -- "${_canonical_pi}" || true
            hash -r 2>/dev/null || true
        fi
    fi

    if [[ -e "${_canonical_pi}" || -L "${_canonical_pi}" ]]; then
        if ! "${_canonical_pi}" --version > /dev/null 2>&1; then
            print_warning "Existing Pi install at ${_canonical_pi} is broken; removing before reinstall."
            if [[ -L "${_canonical_pi}" ]]; then
                _pi_link_target=$(readlink "${_canonical_pi}" 2>/dev/null || true)
                if [[ "${_pi_link_target}" == *"${_new_package}"* || "${_pi_link_target}" == *"${_old_package}"* ]]; then
                    rm -f -- "${_canonical_pi}" || true
                fi
            fi
            if [[ -e "${_canonical_package_dir}" || -L "${_canonical_package_dir}" ]]; then
                if ! rm -rf -- "${_canonical_package_dir}"; then
                    print_error "Failed to remove existing Pi package directory at ${_canonical_package_dir}."
                    return 1
                fi
            fi
        fi
    elif [[ -e "${_canonical_package_dir}" || -L "${_canonical_package_dir}" ]]; then
        print_warning "Found Pi package directory without canonical command; removing before reinstall."
        if ! rm -rf -- "${_canonical_package_dir}"; then
            print_error "Failed to remove existing Pi package directory at ${_canonical_package_dir}."
            return 1
        fi
    fi

    print_message "Installing Pi with npm into ${_canonical_pi}..."
    if ! npm install -g --ignore-scripts --prefix "${_local_prefix}" "${_new_package}@latest"; then
        print_error "Failed to install Pi coding agent."
        return 1
    fi

    npm uninstall -g --prefix "${_local_prefix}" "${_old_package}" > /dev/null 2>&1 || true
    cleanup_noncanonical_pi_installs "${_new_package}" "${_old_package}"
    hash -r 2>/dev/null || true

    _pi_cmd=$(command -v pi 2>/dev/null || true)
    _pi_target=$(pi_command_target 2>/dev/null || true)

    if [[ ! -x "${_canonical_pi}" ]]; then
        print_warning "Pi migration incomplete: canonical Pi command is missing at ${_canonical_pi}."
        return 1
    fi

    if [[ "${_pi_cmd}" != "${_canonical_pi}" ]]; then
        print_warning "Pi migration incomplete: PATH resolves pi to ${_pi_cmd:-<missing>} instead of ${_canonical_pi}."
        if type -P -a pi > /dev/null 2>&1; then
            _pi_commands=$(type -P -a pi 2>/dev/null | awk '!seen[$0]++' || true)
            _pi_commands_inline=${_pi_commands//$'\n'/ }
            print_debug "pi commands on PATH: ${_pi_commands_inline}"
        fi
        return 1
    fi

    if [[ "${_pi_target}" == *"/.bun/"* || "${_pi_target}" == *"/.cache/.bun/"* || "${_pi_target}" == *"${_old_package}"* ]]; then
        print_warning "Pi migration incomplete: canonical pi resolves to non-canonical target ${_pi_target}."
        return 1
    fi

    if [[ "${_pi_target}" != "${_local_prefix}/"* ]]; then
        print_warning "Pi is first on PATH, but resolves outside ${_local_prefix}: ${_pi_target}"
    fi

    if type -P -a pi > /dev/null 2>&1; then
        _pi_commands=$(type -P -a pi 2>/dev/null | awk '!seen[$0]++' || true)
        while IFS= read -r _path_entry; do
            if [[ -n "${_path_entry}" && "${_path_entry}" != "${_canonical_pi}" ]]; then
                print_warning "Additional pi command remains on PATH: ${_path_entry}"
            fi
        done <<< "${_pi_commands}"
    fi

    if ! _pi_version=$(pi --version 2>/dev/null) || [[ -z "${_pi_version}" ]]; then
        print_warning "Pi migration incomplete: pi command failed after installing ${_new_package}."
        return 1
    fi

    print_success "Pi coding agent ${_pi_version} installed/updated at ${_canonical_pi}."
}

# Remove Pi subagents extension
remove_pi_subagents() {
    local _settings_dir="${PI_CODING_AGENT_DIR:-${HOME}/.pi/agent}"
    local _settings_file="${_settings_dir}/settings.json"
    local _package=""
    local _output=""
    local _tmp=""

    if command -v pi &> /dev/null; then
        for _package in "npm:@tintinweb/pi-subagents" "npm:pi-subagents"; do
            if _output=$(pi remove "${_package}" 2>&1); then
                print_success "Removed Pi subagents extension (${_package})."
            elif grep -qi "no matching package found" <<< "${_output}"; then
                print_debug "Pi subagents extension not installed (${_package})."
            else
                print_warning "Failed to remove Pi subagents extension (${_package}): ${_output}"
            fi
        done
        return 0
    fi

    # Fallback when the pi CLI is unavailable: strip both package sources
    # directly from settings.json.
    if [[ ! -f "${_settings_file}" ]]; then
        print_debug "Pi settings not found; Pi subagents extension not installed."
        return 0
    fi

    if ! command -v jq &> /dev/null; then
        print_warning "jq not found. Cannot remove Pi subagents from Pi settings."
        return 0
    fi

    _tmp=$(mktemp)
    if jq '
        def package_source:
            if type == "string" then .
            elif type == "object" then (.source // "")
            else ""
            end;
        def packages_array:
            if (.packages | type) == "array" then .packages else [] end;
        .packages = (packages_array | map(select((package_source != "npm:pi-subagents") and (package_source != "npm:@tintinweb/pi-subagents"))))
        | if (.packages | length) == 0 then del(.packages) else . end
    ' "${_settings_file}" > "${_tmp}"; then
        mv "${_tmp}" "${_settings_file}"
        print_success "Removed Pi subagents extension from Pi settings."
    else
        rm -f "${_tmp}"
        print_warning "Failed to update Pi settings at ${_settings_file}."
    fi
    return 0
}

# Remove retired Pi RPIV packages (ask-user-question and todo)
remove_pi_rpiv_packages() {
    local _settings_dir="${PI_CODING_AGENT_DIR:-${HOME}/.pi/agent}"
    local _settings_file="${_settings_dir}/settings.json"
    local _package=""
    local _output=""
    local _tmp=""

    if command -v pi &> /dev/null; then
        for _package in "npm:@juicesharp/rpiv-ask-user-question" "npm:@juicesharp/rpiv-todo"; do
            if _output=$(pi remove "${_package}" 2>&1); then
                print_success "Removed Pi RPIV package (${_package})."
            elif grep -qi "no matching package found" <<< "${_output}"; then
                print_debug "Pi RPIV package not installed (${_package})."
            else
                print_warning "Failed to remove Pi RPIV package (${_package}): ${_output}"
            fi
        done
        return 0
    fi

    # Fallback when the pi CLI is unavailable: strip both package sources
    # directly from settings.json.
    if [[ ! -f "${_settings_file}" ]]; then
        print_debug "Pi settings not found; Pi RPIV packages not installed."
        return 0
    fi

    if ! command -v jq &> /dev/null; then
        print_warning "jq not found. Cannot remove Pi RPIV packages from Pi settings."
        return 0
    fi

    _tmp=$(mktemp)
    if jq '
        def package_source:
            if type == "string" then .
            elif type == "object" then (.source // "")
            else ""
            end;
        def packages_array:
            if (.packages | type) == "array" then .packages else [] end;
        .packages = (packages_array | map(select((package_source != "npm:@juicesharp/rpiv-ask-user-question") and (package_source != "npm:@juicesharp/rpiv-todo"))))
        | if (.packages | length) == 0 then del(.packages) else . end
    ' "${_settings_file}" > "${_tmp}"; then
        mv "${_tmp}" "${_settings_file}"
        print_success "Removed Pi RPIV packages from Pi settings."
    else
        rm -f "${_tmp}"
        print_warning "Failed to update Pi settings at ${_settings_file}."
    fi
    return 0
}

# Remove Pi MCP adapter package source from settings when disabled
remove_pi_mcp_adapter_settings() {
    local _settings_dir="${PI_CODING_AGENT_DIR:-${HOME}/.pi/agent}"
    local _settings_file="${_settings_dir}/settings.json"
    local _tmp=""

    if ! command -v jq &> /dev/null; then
        print_warning "jq not found. Cannot update Pi MCP adapter settings."
        return 1
    fi

    mkdir -p "${_settings_dir}"

    if [[ ! -f "${_settings_file}" ]]; then
        printf '{}
' > "${_settings_file}"
    fi

    _tmp=$(mktemp)
    if jq '
        def package_source:
            if type == "string" then .
            elif type == "object" then (.source // "")
            else ""
            end;
        def packages_array:
            if (.packages | type) == "array" then .packages else [] end;
        .packages = (packages_array | map(select(package_source != "npm:pi-mcp-adapter")))
        | if (.packages | length) == 0 then del(.packages) else . end
    ' "${_settings_file}" > "${_tmp}"; then
        mv "${_tmp}" "${_settings_file}"
    else
        rm -f "${_tmp}"
        print_warning "Failed to update Pi settings at ${_settings_file}."
        return 1
    fi
}

# Install/update Pi MCP adapter extension
setup_pi_mcp_adapter() {
    local _package="npm:pi-mcp-adapter"
    local _output=""
    local _list_output=""

    if [[ "${BAN_PI_MCP_ADAPTER:-}" == "1" ]]; then
        if remove_pi_mcp_adapter_settings; then
            print_success "Pi MCP adapter extension disabled in Pi settings."
        fi
        return 0
    fi

    if ! command -v npm &> /dev/null; then
        print_warning "npm not found. Cannot install Pi MCP adapter."
        print_debug "Install Node.js/npm, then run: pi install npm:pi-mcp-adapter"
        return 0
    fi

    if ! command -v pi &> /dev/null; then
        print_warning "Pi coding agent not found. Cannot install Pi MCP adapter."
        return 0
    fi

    print_message "Installing/updating Pi MCP adapter..."
    if _output=$(pi install "${_package}" 2>&1); then
        if _list_output=$(pi list 2>&1) && grep -q "npm:pi-mcp-adapter" <<< "${_list_output}"; then
            print_success "Pi MCP adapter installed/updated."
        else
            print_warning "Pi MCP adapter install completed, but package validation was inconclusive: ${_list_output}"
        fi
    else
        print_warning "Failed to install Pi MCP adapter: ${_output}"
    fi
}

# Install/update Pi Claude bridge extension
setup_pi_claude_bridge() {
    local _package="npm:pi-claude-bridge"
    local _output=""
    local _list_output=""

    if ! command -v npm &> /dev/null; then
        print_warning "npm not found. Cannot install Pi Claude bridge."
        print_debug "Install Node.js/npm, then run: pi install npm:pi-claude-bridge"
        return 0
    fi

    if ! command -v pi &> /dev/null; then
        print_warning "Pi coding agent not found. Cannot install Pi Claude bridge."
        return 0
    fi

    print_message "Installing/updating Pi Claude bridge..."
    if _output=$(pi install "${_package}" 2>&1); then
        if _list_output=$(pi list 2>&1) && grep -q "npm:pi-claude-bridge" <<< "${_list_output}"; then
            print_success "Pi Claude bridge installed/updated."
        else
            print_warning "Pi Claude bridge install completed, but package validation was inconclusive: ${_list_output}"
        fi
    else
        print_warning "Failed to install Pi Claude bridge: ${_output}"
    fi
}

# Remove legacy Pi Ask User and install/update the Pi web access package
setup_pi_companion_packages() {
    local _legacy_package="npm:pi-ask-user"
    local -a _packages=(
        "npm:pi-web-access"
    )
    local _package=""
    local _output=""
    local _list_output=""

    if ! command -v npm &> /dev/null; then
        print_warning "npm not found. Cannot install Pi companion packages."
        print_debug "Install Node.js/npm, then install these Pi packages manually: ${_packages[*]}"
        return 0
    fi

    if ! command -v pi &> /dev/null; then
        print_warning "Pi coding agent not found. Cannot install Pi companion packages."
        return 0
    fi

    if _list_output=$(pi list 2>&1); then
        if grep -Fq -- "${_legacy_package}" <<< "${_list_output}"; then
            print_message "Removing legacy Pi Ask User package..."
            if _output=$(pi remove "${_legacy_package}" 2>&1); then
                print_success "Legacy Pi Ask User package removed."
            else
                print_warning "Failed to remove legacy Pi Ask User package: ${_output}"
            fi
        fi
    else
        print_warning "Cannot inspect Pi packages before legacy cleanup: ${_list_output}"
    fi

    for _package in "${_packages[@]}"; do
        print_message "Installing/updating Pi package ${_package}..."
        if _output=$(pi install "${_package}" 2>&1); then
            if _list_output=$(pi list 2>&1) && grep -Fq -- "${_package}" <<< "${_list_output}"; then
                print_success "Pi package ${_package} installed/updated."
            else
                print_warning "Pi package ${_package} install completed, but validation was inconclusive: ${_list_output}"
            fi
        else
            print_warning "Failed to install Pi package ${_package}: ${_output}"
        fi
    done
}

# Keep shared skills canonical for Pi and suppress stale direct/package collisions.
configure_pi_skill_ownership() {
    local _default_agent_dir="${HOME}/.pi/agent"
    local _active_agent_dir="${PI_CODING_AGENT_DIR:-${_default_agent_dir}}"
    local _settings_file="${_active_agent_dir}/settings.json"
    local _canonical_dir="${HOME}/.agents/skills"
    local _agent_dir=""
    local _skill=""
    local _duplicate=""
    local _managed_json=""
    local _tmp=""
    local -a _agent_dirs=("${_default_agent_dir}")
    local -a _shared_exclusions=(
        "!${_canonical_dir}/pi-goal-writer/**"
        "!${_canonical_dir}/autoresearch-create/**"
        "!${_canonical_dir}/autoresearch-finalize/**"
        "!${_canonical_dir}/autoresearch-hooks/**"
    )
    local -a _shared_skills=(
        simple-english show-me setup-matt-pocock-skills diagnosing-bugs tdd
        improve-codebase-architecture grill-with-docs grilling domain-modeling codebase-design
    )
    local -a _managed_exclusions=("${_shared_exclusions[@]}")

    if [[ "${_active_agent_dir}" != "${_default_agent_dir}" ]]; then
        _agent_dirs+=("${_active_agent_dir}")
    fi

    for _agent_dir in "${_agent_dirs[@]}"; do
        for _skill in "${_shared_skills[@]}"; do
            _duplicate="${_agent_dir}/skills/${_skill}"
            _managed_exclusions+=("!${_duplicate}/**")
            if [[ -d "${_duplicate}" && ! -L "${_duplicate}" && -d "${_canonical_dir}/${_skill}" && ! -L "${_canonical_dir}/${_skill}" ]] &&
                diff -qr -- "${_canonical_dir}/${_skill}" "${_duplicate}" > /dev/null 2>&1; then
                if rm -rf -- "${_duplicate:?}"; then
                    print_debug "Removed obsolete duplicate Pi skill: ${_duplicate}"
                else
                    print_warning "Failed to remove obsolete duplicate Pi skill: ${_duplicate}"
                fi
            fi
        done
    done

    if ! command -v jq &> /dev/null; then
        print_warning "jq not found. Cannot configure Pi skill ownership."
        return 1
    fi

    mkdir -p "${_active_agent_dir}"
    [[ -f "${_settings_file}" ]] || printf '{}\n' > "${_settings_file}"
    _managed_json=$(printf '%s\n' "${_managed_exclusions[@]}" | jq -Rsc 'split("\n") | map(select(length > 0))')
    _tmp=$(mktemp)
    if jq --argjson managed "${_managed_json}" '
        .skills = (reduce $managed[] as $entry (
            (if (.skills | type) == "array" then .skills else [] end);
            if index($entry) then . else . + [$entry] end
        ))
    ' "${_settings_file}" > "${_tmp}"; then
        mv "${_tmp}" "${_settings_file}"
        print_success "Pi skill ownership configured without removing shared harness copies."
    else
        rm -f "${_tmp}"
        print_warning "Failed to configure Pi skill ownership at ${_settings_file}."
        return 1
    fi
}

# Configure pi-autoresearch without overriding Pi transcript search.
configure_pi_autoresearch_shortcut() {
    local _agent_dir="${PI_CODING_AGENT_DIR:-${HOME}/.pi/agent}"
    local _config_dir="${_agent_dir}/extensions"
    local _config_file="${_config_dir}/pi-autoresearch.json"
    local _tmp=""

    if ! command -v jq &> /dev/null; then
        print_warning "jq not found. Cannot configure the pi-autoresearch shortcut."
        return 1
    fi

    mkdir -p "${_config_dir}"
    [[ -f "${_config_file}" ]] || printf '{}\n' > "${_config_file}"
    _tmp=$(mktemp)
    if jq '.shortcuts.fullscreenDashboard = "ctrl+shift+r"' "${_config_file}" > "${_tmp}"; then
        mv "${_tmp}" "${_config_file}"
        print_success "pi-autoresearch dashboard shortcut set to Ctrl+Shift+R."
    else
        rm -f "${_tmp}"
        print_warning "Failed to configure pi-autoresearch at ${_config_file}."
        return 1
    fi
}

# Remove Pi goal/autoresearch package sources from settings when disabled
remove_pi_goal_autoresearch_settings() {
    local _settings_dir="${PI_CODING_AGENT_DIR:-${HOME}/.pi/agent}"
    local _settings_file="${_settings_dir}/settings.json"
    local _tmp=""

    if ! command -v jq &> /dev/null; then
        print_warning "jq not found. Cannot update Pi goal/autoresearch settings."
        return 1
    fi

    mkdir -p "${_settings_dir}"

    if [[ ! -f "${_settings_file}" ]]; then
        printf '{}\n' > "${_settings_file}"
    fi

    _tmp=$(mktemp)
    if jq '
        def package_source:
            if type == "string" then .
            elif type == "object" then (.source // "")
            else ""
            end;
        def packages_array:
            if (.packages | type) == "array" then .packages else [] end;
        .packages = (packages_array | map(select((package_source != "npm:pi-goal") and (package_source != "npm:pi-autoresearch"))))
        | if (.packages | length) == 0 then del(.packages) else . end
    ' "${_settings_file}" > "${_tmp}"; then
        mv "${_tmp}" "${_settings_file}"
    else
        rm -f "${_tmp}"
        print_warning "Failed to update Pi settings at ${_settings_file}."
        return 1
    fi
}

# Install/update Pi goal and autoresearch extensions
setup_pi_goal_autoresearch() {
    local _package=""
    local _output=""
    local _list_output=""
    local _had_failure=0

    if [[ "${BAN_PI_GOAL_AUTORESEARCH:-}" == "1" ]]; then
        if remove_pi_goal_autoresearch_settings; then
            print_success "Pi goal/autoresearch extensions disabled in Pi settings."
        fi
        return 0
    fi

    if ! command -v pi &> /dev/null; then
        print_warning "Pi coding agent not found. Cannot install Pi goal/autoresearch extensions."
        return 0
    fi

    for _package in npm:pi-goal npm:pi-autoresearch; do
        print_message "Installing/updating ${_package}..."
        if _output=$(pi install "${_package}" 2>&1); then
            print_success "${_package} installed/updated."
        else
            _had_failure=1
            print_warning "Failed to install ${_package}: ${_output}"
        fi
    done

    if _list_output=$(pi list 2>&1) && grep -q "npm:pi-goal" <<< "${_list_output}" && grep -q "npm:pi-autoresearch" <<< "${_list_output}"; then
        print_success "Pi goal/autoresearch extensions are active."
    elif [[ "${_had_failure}" -eq 0 ]]; then
        print_warning "Pi goal/autoresearch install completed, but package validation was inconclusive: ${_list_output}"
    fi

    configure_pi_autoresearch_shortcut || return 1
}


# Matt Pocock skills to install in the shared Codex/Pi path.
matt_pocock_skills() {
    printf '%s\n' \
        setup-matt-pocock-skills \
        diagnosing-bugs \
        tdd \
        improve-codebase-architecture \
        grill-with-docs \
        grilling \
        domain-modeling \
        codebase-design
}

# Setup-managed skill names retired or renamed upstream.
matt_pocock_obsolete_skills() {
    printf '%s\n' \
        diagnose \
        zoom-out
}

matt_pocock_all_managed_skills() {
    matt_pocock_skills
    matt_pocock_obsolete_skills
}

matt_pocock_skills_disabled() {
    [[ "${BAN_MATT_POCOCK_SKILLS:-}" == "1" || "${BAN_MATT_POCKOCK_SKILLS:-}" == "1" ]]
}

# Remove setup-managed Matt Pocock skills without following symlink targets.
remove_matt_pocock_skills() {
    local _default_agent_dir="${HOME}/.pi/agent"
    local _active_agent_dir="${PI_CODING_AGENT_DIR:-${_default_agent_dir}}"
    local _skills_dir=""
    local _skill=""
    local _skill_path=""
    local _removed=0
    local _failed=()
    local _skills_dirs=("${_default_agent_dir}/skills" "${HOME}/.agents/skills")

    if [[ "${_active_agent_dir}" != "${_default_agent_dir}" ]]; then
        _skills_dirs+=("${_active_agent_dir}/skills")
    fi

    for _skills_dir in "${_skills_dirs[@]}"; do
        while IFS= read -r _skill; do
            _skill_path="${_skills_dir}/${_skill}"
            if [[ -e "${_skill_path}" || -L "${_skill_path}" ]]; then
                if rm -rf -- "${_skill_path:?}" && [[ ! -e "${_skill_path}" && ! -L "${_skill_path}" ]]; then
                    _removed=1
                else
                    _failed+=("${_skill}")
                fi
            fi
        done < <(matt_pocock_all_managed_skills || true)
    done

    if [[ "${#_failed[@]}" -gt 0 ]]; then
        print_warning "Failed to remove Matt Pocock skills: ${_failed[*]}"
        return 1
    elif [[ "${_removed}" -eq 1 ]]; then
        print_success "Matt Pocock skills disabled."
    else
        print_debug "Matt Pocock skills disabled; no installed copies found."
    fi
}

# Remove only retired setup-managed names after their replacements validate.
remove_obsolete_matt_pocock_skills() {
    local _default_agent_dir="${HOME}/.pi/agent"
    local _active_agent_dir="${PI_CODING_AGENT_DIR:-${_default_agent_dir}}"
    local _skills_dir=""
    local _skill=""
    local _skill_path=""
    local _failed=()
    local _skills_dirs=("${_default_agent_dir}/skills" "${HOME}/.agents/skills")

    if [[ "${_active_agent_dir}" != "${_default_agent_dir}" ]]; then
        _skills_dirs+=("${_active_agent_dir}/skills")
    fi

    for _skills_dir in "${_skills_dirs[@]}"; do
        while IFS= read -r _skill; do
            _skill_path="${_skills_dir}/${_skill}"
            if [[ -e "${_skill_path}" || -L "${_skill_path}" ]]; then
                if ! rm -rf -- "${_skill_path:?}" || [[ -e "${_skill_path}" || -L "${_skill_path}" ]]; then
                    _failed+=("${_skill_path}")
                fi
            fi
        done < <(matt_pocock_obsolete_skills || true)
    done

    if [[ "${#_failed[@]}" -gt 0 ]]; then
        print_warning "Failed to remove obsolete Matt Pocock skills: ${_failed[*]}"
        return 1
    fi
}

# Install/update Matt Pocock engineering skills for Codex and Pi.
setup_matt_pocock_skills() {
    local _repo="mattpocock/skills"
    local _codex_skills_dir="${HOME}/.agents/skills"
    local _validation_dir=""
    local _skill=""
    local _output=""
    local _source_path=""
    local _args=(--yes skills@latest add "${_repo}" --global --agent codex --copy --yes)
    local _validation_dirs=("${_codex_skills_dir}")
    local _missing=()

    if matt_pocock_skills_disabled; then
        remove_matt_pocock_skills
        return
    fi

    if ! ensure_skills_cli_node_runtime; then
        print_warning "Cannot install Matt Pocock skills because the skills CLI runtime is not ready."
        return 1
    fi

    if ! command -v npx &> /dev/null; then
        print_warning "npx is not available; cannot install Matt Pocock skills."
        print_debug "Install Node.js >=22.20, then run: npx --yes skills@latest add mattpocock/skills --global --agent codex --copy --yes"
        return 1
    fi

    while IFS= read -r _skill; do
        _args+=(--skill "${_skill}")
    done < <(matt_pocock_skills || true)

    print_message "Installing/updating Matt Pocock skills for Pi and Codex..."
    if ! _output=$(npx "${_args[@]}" < /dev/null 2>&1); then
        print_warning "Failed to install Matt Pocock skills."
        print_debug "${_output}"
        return 1
    fi

    for _validation_dir in "${_validation_dirs[@]}"; do
        while IFS= read -r _skill; do
            _source_path="${_validation_dir}/${_skill}"
            if [[ ! -d "${_source_path}" || -L "${_source_path}" || ! -f "${_source_path}/SKILL.md" || -L "${_source_path}/SKILL.md" ]]; then
                _missing+=("${_source_path}")
            fi
        done < <(matt_pocock_skills || true)
    done

    if [[ "${#_missing[@]}" -gt 0 ]]; then
        print_warning "Matt Pocock skills are missing required files: ${_missing[*]}"
        return 1
    elif ! remove_obsolete_matt_pocock_skills; then
        return 1
    fi

    print_success "Matt Pocock skills installed/updated for Pi and Codex through the shared path."
    print_debug "${_output}"
}


# Remove legacy Compound Engineering resources without affecting unrelated agent tooling.
compound_path_is_within() {
    local _path="$1"
    local _root="$2"
    local _canonical_path=""
    local _canonical_root=""

    _canonical_root=$(cd -P "${_root}" 2>/dev/null && pwd -P) || return 1
    _canonical_path=$(cd -P "${_path}" 2>/dev/null && pwd -P) || return 1
    case "${_canonical_path}" in
        "${_canonical_root}"/*) return 0 ;;
        *) return 1 ;;
    esac
}

compound_link_target_is_within() {
    local _link_path="$1"
    local _root_path="$2"
    local _link_target=""

    [[ -L "${_link_path}" ]] || return 1
    _link_target=$(readlink "${_link_path}") || return 1
    case "${_link_target}" in
        /*) ;;
        *) _link_target="$(dirname "${_link_path}")/${_link_target}" ;;
    esac

    if compound_path_is_within "${_link_target}" "${_root_path}"; then
        return 0
    fi

    # Legacy installer links use an absolute target. This lexical check also
    # removes a dangling link after a previous partial cleanup, while keeping
    # the trailing slash boundary from matching sibling directories. Do not
    # trust an unresolved target with traversal segments.
    case "${_link_target}" in
        */../*|*/..) return 1 ;;
        "${_root_path}"/*) return 0 ;;
        *) return 1 ;;
    esac
}

compound_pi_skill_names() {
    printf '%s
' \
        ce-agent-native-architecture \
        ce-agent-native-audit \
        ce-brainstorm \
        ce-clean-gone-branches \
        ce-code-review \
        ce-commit \
        ce-commit-push-pr \
        ce-compound \
        ce-compound-refresh \
        ce-debug \
        ce-demo-reel \
        ce-dhh-rails-style \
        ce-doc-review \
        ce-frontend-design \
        ce-gemini-imagegen \
        ce-ideate \
        ce-optimize \
        ce-plan \
        ce-polish-beta \
        ce-product-pulse \
        ce-proof \
        ce-release-notes \
        ce-report-bug \
        ce-resolve-pr-feedback \
        ce-riffrec-feedback-analysis \
        ce-sessions \
        ce-setup \
        ce-simplify-code \
        ce-slack-research \
        ce-strategy \
        ce-test-browser \
        ce-test-xcode \
        ce-work \
        ce-work-beta \
        ce-worktree \
        lfg
}

compound_pi_agent_names() {
    printf '%s
' \
        ce-adversarial-document-reviewer \
        ce-adversarial-reviewer \
        ce-agent-native-reviewer \
        ce-ankane-readme-writer \
        ce-api-contract-reviewer \
        ce-architecture-strategist \
        ce-best-practices-researcher \
        ce-code-simplicity-reviewer \
        ce-coherence-reviewer \
        ce-correctness-reviewer \
        ce-data-integrity-guardian \
        ce-data-migration-expert \
        ce-data-migrations-reviewer \
        ce-deployment-verification-agent \
        ce-design-implementation-reviewer \
        ce-design-iterator \
        ce-design-lens-reviewer \
        ce-dhh-rails-reviewer \
        ce-feasibility-reviewer \
        ce-figma-design-sync \
        ce-framework-docs-researcher \
        ce-git-history-analyzer \
        ce-issue-intelligence-analyst \
        ce-julik-frontend-races-reviewer \
        ce-kieran-python-reviewer \
        ce-kieran-rails-reviewer \
        ce-kieran-typescript-reviewer \
        ce-learnings-researcher \
        ce-maintainability-reviewer \
        ce-pattern-recognition-specialist \
        ce-performance-oracle \
        ce-performance-reviewer \
        ce-pr-comment-resolver \
        ce-previous-comments-reviewer \
        ce-product-lens-reviewer \
        ce-project-standards-reviewer \
        ce-reliability-reviewer \
        ce-repo-research-analyst \
        ce-schema-drift-detector \
        ce-scope-guardian-reviewer \
        ce-security-lens-reviewer \
        ce-security-reviewer \
        ce-security-sentinel \
        ce-session-historian \
        ce-slack-researcher \
        ce-spec-flow-analyzer \
        ce-swift-ios-reviewer \
        ce-testing-reviewer \
        ce-web-researcher
}

remove_pi_compound_settings() {
    local _agent_dir="$1"
    local _settings_file="${_agent_dir}/settings.json"
    local _tmp=""

    [[ -f "${_settings_file}" && ! -L "${_settings_file}" ]] || return 1

    if ! command -v jq &> /dev/null; then
        print_warning "jq not found. Cannot remove Compound Engineering entries from Pi settings at ${_settings_file}."
        return 1
    fi

    if ! jq -e '
        def package_source:
            if type == "string" then .
            elif type == "object" then (.source // "")
            else ""
            end;
        def compound_source:
            package_source | ascii_downcase as $source |
            ($source == "npm:@every-env/compound-plugin"
                or $source == "npm:@every-env/compound-engineering-plugin"
                or $source == "https://github.com/everyinc/compound-engineering-plugin.git");
        (.packages | type) == "array" and any(.packages[]; compound_source)
    ' "${_settings_file}" > /dev/null; then
        return 1
    fi

    if ! _tmp=$(mktemp); then
        print_warning "Could not create a temporary file for Pi settings cleanup at ${_settings_file}."
        return 1
    fi

    if jq '
        def package_source:
            if type == "string" then .
            elif type == "object" then (.source // "")
            else ""
            end;
        def compound_source:
            package_source | ascii_downcase as $source |
            ($source == "npm:@every-env/compound-plugin"
                or $source == "npm:@every-env/compound-engineering-plugin"
                or $source == "https://github.com/everyinc/compound-engineering-plugin.git");
        .packages = (.packages | map(select(compound_source | not)))
        | if (.packages | length) == 0 then del(.packages) else . end
    ' "${_settings_file}" > "${_tmp}"; then
        if mv "${_tmp}" "${_settings_file}"; then
            return 0
        fi
        rm -f "${_tmp}"
        print_warning "Failed to replace Pi settings after Compound Engineering cleanup at ${_settings_file}."
    else
        rm -f "${_tmp}"
        print_warning "Failed to parse Pi settings at ${_settings_file}; leaving it unchanged."
    fi

    return 1
}

remove_compound_engineering_resources() {
    local _default_agent_dir="${HOME}/.pi/agent"
    local _active_agent_dir="${PI_CODING_AGENT_DIR:-${_default_agent_dir}}"
    local _compound_repo="${HOME}/.local/share/compound-engineering-plugin"
    local _skills_dir="${HOME}/.agents/skills"
    local _agent_dir=""
    local _resource_dir=""
    local _resource_path=""
    local _resource_name=""
    local _extension_path=""
    local _agents_path=""
    local _tmp=""
    local _begin_marker="<!-- BEGIN COMPOUND PI TOOL MAP -->"
    local _end_marker="<!-- END COMPOUND PI TOOL MAP -->"
    local _begin_count=0
    local _end_count=0
    local _removed=0
    local _failed=()
    local _agent_dirs=()

    if [[ -d "${_default_agent_dir}" ]]; then
        if compound_path_is_within "${_default_agent_dir}" "${HOME}"; then
            _agent_dirs+=("${_default_agent_dir}")
        else
            print_warning "Skipping Pi cleanup outside ${HOME}: ${_default_agent_dir}"
        fi
    fi

    if [[ "${_active_agent_dir}" != "${_default_agent_dir}" && -d "${_active_agent_dir}" ]]; then
        if compound_path_is_within "${_active_agent_dir}" "${HOME}"; then
            _agent_dirs+=("${_active_agent_dir}")
        else
            print_warning "Skipping Pi cleanup outside ${HOME}: ${_active_agent_dir}"
        fi
    fi

    if [[ -d "${_skills_dir}" ]] && compound_path_is_within "${_skills_dir}" "${HOME}"; then
        for _resource_path in "${_skills_dir}"/*; do
            [[ -L "${_resource_path}" ]] || continue
            if compound_link_target_is_within "${_resource_path}" "${_compound_repo}"; then
                if rm -f -- "${_resource_path}" && [[ ! -e "${_resource_path}" && ! -L "${_resource_path}" ]]; then
                    _removed=1
                else
                    _failed+=("${_resource_path}")
                fi
            fi
        done
    fi

    for _agent_dir in "${_agent_dirs[@]}"; do
        if remove_pi_compound_settings "${_agent_dir}"; then
            _removed=1
        fi

        _resource_dir="${_agent_dir}/extensions"
        if [[ -d "${_resource_dir}" ]] && compound_path_is_within "${_resource_dir}" "${HOME}"; then
            for _extension_path in "${_resource_dir}"/compound-engineering*; do
                [[ -e "${_extension_path}" || -L "${_extension_path}" ]] || continue
                if rm -rf -- "${_extension_path}" && [[ ! -e "${_extension_path}" && ! -L "${_extension_path}" ]]; then
                    _removed=1
                else
                    _failed+=("${_extension_path}")
                fi
            done
        fi

        _resource_dir="${_agent_dir}/skills"
        if [[ -d "${_resource_dir}" ]] && compound_path_is_within "${_resource_dir}" "${HOME}"; then
            while IFS= read -r _resource_name; do
                _resource_path="${_resource_dir}/${_resource_name}"
                [[ -d "${_resource_path}" || -L "${_resource_path}" ]] || continue
                if rm -rf -- "${_resource_path}" && [[ ! -e "${_resource_path}" && ! -L "${_resource_path}" ]]; then
                    _removed=1
                else
                    _failed+=("${_resource_path}")
                fi
            done < <(compound_pi_skill_names || true)
        fi

        _resource_dir="${_agent_dir}/agents"
        if [[ -d "${_resource_dir}" ]] && compound_path_is_within "${_resource_dir}" "${HOME}"; then
            while IFS= read -r _resource_name; do
                for _resource_path in "${_resource_dir}/${_resource_name}" "${_resource_dir}/${_resource_name}.md"; do
                    [[ -e "${_resource_path}" || -L "${_resource_path}" ]] || continue
                    if [[ -d "${_resource_path}" || -L "${_resource_path}" ]]; then
                        rm -rf -- "${_resource_path}"
                    else
                        rm -f -- "${_resource_path}"
                    fi
                    if [[ ! -e "${_resource_path}" && ! -L "${_resource_path}" ]]; then
                        _removed=1
                    else
                        _failed+=("${_resource_path}")
                    fi
                done
            done < <(compound_pi_agent_names || true)
        fi

        # The Pi plugin installer leaves its install manifest behind. The
        # manifest is part of the legacy installation and must be removed too.
        _resource_path="${_agent_dir}/compound-engineering"
        if [[ -e "${_resource_path}" || -L "${_resource_path}" ]]; then
            if [[ -d "${_resource_path}" || -L "${_resource_path}" ]]; then
                rm -rf -- "${_resource_path}"
            else
                rm -f -- "${_resource_path}"
            fi
            if [[ ! -e "${_resource_path}" && ! -L "${_resource_path}" ]]; then
                _removed=1
            else
                _failed+=("${_resource_path}")
            fi
        fi

        _agents_path="${_agent_dir}/AGENTS.md"
        if [[ -f "${_agents_path}" && ! -L "${_agents_path}" ]]; then
            _begin_count=$(grep -Fxc "${_begin_marker}" "${_agents_path}" || true)
            _end_count=$(grep -Fxc "${_end_marker}" "${_agents_path}" || true)
            if [[ "${_begin_count}" -eq 1 && "${_end_count}" -eq 1 ]]; then
                if ! _tmp=$(mktemp "${_agents_path}.XXXXXX"); then
                    print_warning "Could not create a temporary file to remove the Compound Engineering block from ${_agents_path}."
                elif awk -v begin="${_begin_marker}" -v end="${_end_marker}" '
                    $0 == begin { in_block = 1; next }
                    $0 == end && in_block { in_block = 0; next }
                    !in_block { print }
                    END { exit in_block ? 1 : 0 }
                ' "${_agents_path}" > "${_tmp}" && mv "${_tmp}" "${_agents_path}"; then
                    _removed=1
                else
                    rm -f "${_tmp}"
                    print_warning "Failed to safely remove the Compound Engineering block from ${_agents_path}."
                fi
            elif [[ "${_begin_count}" -ne 0 || "${_end_count}" -ne 0 ]]; then
                print_warning "Compound Engineering markers are malformed in ${_agents_path}; leaving it unchanged."
            fi
        elif [[ -L "${_agents_path}" ]]; then
            print_warning "Skipping Compound Engineering block cleanup in symlinked ${_agents_path}."
        fi
    done

    if [[ -L "${_compound_repo}" ]]; then
        if rm -f -- "${_compound_repo}" && [[ ! -e "${_compound_repo}" && ! -L "${_compound_repo}" ]]; then
            _removed=1
        else
            _failed+=("${_compound_repo}")
        fi
    elif [[ -d "${_compound_repo}" ]] && compound_path_is_within "${_compound_repo}" "${HOME}"; then
        if rm -rf -- "${_compound_repo}" && [[ ! -e "${_compound_repo}" && ! -L "${_compound_repo}" ]]; then
            _removed=1
        else
            _failed+=("${_compound_repo}")
        fi
    fi

    if [[ "${#_failed[@]}" -gt 0 ]]; then
        print_warning "Failed to remove legacy Compound Engineering resources: ${_failed[*]}"
    elif [[ "${_removed}" -eq 1 ]]; then
        print_success "Legacy Compound Engineering resources removed."
    else
        print_debug "No legacy Compound Engineering resources found."
    fi

    return 0
}

# Enable loginctl lingering so systemd user services survive logout
enable_user_lingering() {
    if { loginctl show-user "$(whoami || true)" --property=Linger 2>/dev/null || true; } | grep -q 'Linger=yes'; then
        print_debug "User lingering already enabled."
        return
    fi

    print_message "Enabling user lingering for systemd user services..."

    if can_sudo; then
        if sudo loginctl enable-linger "$(whoami || true)"; then
            print_success "User lingering enabled — systemd user services will survive logout."
        else
            print_warning "Could not enable user lingering."
        fi
    else
        print_warning "No sudo access — cannot enable user lingering."
        print_debug "Run 'sudo loginctl enable-linger $(whoami || true)' manually."
    fi
}


# Install mise (runtime version manager, replaces fnm and pyenv)
install_mise() {
    if command -v mise &> /dev/null; then
        print_debug "mise already installed."
        return
    fi

    print_message "Installing mise..."
    ensure_brew_available
    if ! brew install mise; then
        print_error "Failed to install mise via Homebrew."
        return 1
    fi

    print_success "mise installed. Shell configuration will be managed by chezmoi."
}

# Fix 1Password repository GPG key issues
fix_1password_repository() {
    print_message "Checking for 1Password repository issues..."
    
    # Check if 1Password repository exists and has key issues
    local apt_policy
    apt_policy=$(apt-cache policy 2>/dev/null || true)
    local apt_update_output
    apt_update_output=$(apt update 2>&1 || true)
    if echo "${apt_policy}" | grep -q "1password.com" && echo "${apt_update_output}" | grep -q "EXPKEYSIG.*1Password"; then
        print_message "Fixing expired 1Password repository key..."
        
        # Remove the problematic repository
        sudo rm -f /etc/apt/sources.list.d/1password.list
        sudo rm -f /usr/share/keyrings/1password-archive-keyring.gpg
        
        print_success "Removed problematic 1Password repository."
    else
        print_debug "No 1Password repository issues detected."
    fi
}

# Install 1Password CLI
install_1password_cli() {
    if command -v op >/dev/null; then
        print_debug "1Password CLI already installed."
        return
    fi

    print_message "Installing 1Password CLI..."
    
    # Fix any existing repository issues first
    fix_1password_repository
    
    ensure_brew_available
    if ! brew install --cask 1password-cli; then
        print_error "Failed to install 1Password CLI via Homebrew."
        return 1
    fi
    print_success "1Password CLI installed."
}

# Install Tailscale
install_tailscale() {
    print_message "Skipping Tailscale installation as it is not needed on WSL."
}

# Install Doppler CLI for secrets management (non-work machines)
install_doppler() {
    if command -v doppler &>/dev/null; then
        print_debug "Doppler CLI already installed."
        return
    fi

    if ! can_sudo; then
        print_warning "No sudo access - cannot install Doppler CLI."
        return
    fi

    print_message "Installing Doppler CLI..."

    # Import signing key
    local signing_key
    signing_key=$(curl -sLf --retry 3 --tlsv1.2 --proto "=https" \
        'https://packages.doppler.com/public/cli/gpg.DE2A7741A397C129.key')
    echo "${signing_key}" | sudo gpg --dearmor -o /usr/share/keyrings/doppler-archive-keyring.gpg

    # Add repo
    echo "deb [signed-by=/usr/share/keyrings/doppler-archive-keyring.gpg] https://packages.doppler.com/public/cli/deb/debian any-version main" \
        | sudo tee /etc/apt/sources.list.d/doppler-cli.list >/dev/null

    # Install package
    sudo apt-get update -qq
    if sudo apt-get install -y doppler; then
        print_success "Doppler CLI installed."
    else
        print_error "Failed to install Doppler CLI."
    fi
}

# Install Infisical CLI for secrets management (work machines)
install_infisical() {
    if command -v infisical &>/dev/null; then
        print_debug "Infisical CLI already installed."
        return
    fi

    if ! can_sudo; then
        print_warning "No sudo access - cannot install Infisical CLI."
        return
    fi

    print_message "Installing Infisical CLI..."

    # Add repository and install
    if { curl -1sLf 'https://dl.cloudsmith.io/public/infisical/infisical-cli/setup.deb.sh' || true; } | sudo bash; then
        sudo apt-get update -qq
        if sudo apt-get install -y infisical; then
            print_success "Infisical CLI installed."
        else
            print_error "Failed to install Infisical CLI."
        fi
    else
        print_error "Failed to add Infisical repository."
    fi
}

# Install the appropriate secrets manager based on machine type
install_secrets_manager() {
    if [[ "${WORK_MACHINE:-}" == "1" ]]; then
        install_infisical
    else
        install_doppler
    fi
}

# Update Google Cloud CLI components when the component manager is available.
update_gcloud_components() {
    if ! command -v gcloud &>/dev/null; then
        print_debug "Google Cloud CLI not installed; skipping component update."
        return
    fi

    local package=""
    local package_status=""
    if command -v dpkg-query &>/dev/null; then
        for package in google-cloud-cli google-cloud-sdk; do
            package_status=$(dpkg-query -W -f='${Status}' "${package}" 2>/dev/null || true)
            if [[ "${package_status}" == "install ok installed" ]]; then
                print_debug "Google Cloud CLI is managed by apt; skipping component update."
                return
            fi
        done
    fi

    local update_output
    local normalized_output
    print_message "Updating Google Cloud CLI components..."
    if update_output=$(gcloud components update --quiet < /dev/null 2>&1); then
        print_success "Google Cloud CLI components updated."
    else
        normalized_output=$(printf '%s' "${update_output}" | tr '\r\n\t' '   ')
        if grep -qiE "component[[:space:]]+manager[[:space:]]+is[[:space:]]+disabled|managed[[:space:]]+by[[:space:]]+an[[:space:]]+external[[:space:]]+package[[:space:]]+manager" <<< "${normalized_output}"; then
            print_debug "Google Cloud CLI components are managed by the package manager; skipping component update."
        else
            print_warning "Failed to update Google Cloud CLI components."
            if [[ -n "${update_output}" ]]; then
                print_debug "${update_output}"
            fi
        fi
    fi
}

# Install Google Cloud CLI on work machines.
install_gcloud_cli() {
    if [[ "${WORK_MACHINE:-}" != "1" ]]; then
        print_debug "Skipping Google Cloud CLI (not a work machine)."
        return
    fi

    if command -v gcloud &>/dev/null; then
        print_debug "Google Cloud CLI already installed."
        update_gcloud_components
        return
    fi

    if ! can_sudo; then
        print_warning "No sudo access - cannot install Google Cloud CLI."
        return
    fi

    print_message "Installing Google Cloud CLI..."

    sudo install -m 0755 -d /usr/share/keyrings
    if ! { curl --connect-timeout 10 --max-time 60 -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg || true; } \
        | sudo gpg --batch --yes --dearmor -o /usr/share/keyrings/cloud.google.gpg; then
        print_warning "Failed to install Google Cloud CLI signing key."
        return
    fi

    echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
        | sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list >/dev/null

    if ! sudo apt-get update -qq; then
        print_warning "Failed to update apt repositories for Google Cloud CLI."
        return
    fi

    if sudo apt-get install -y google-cloud-cli; then
        print_success "Google Cloud CLI installed."
        update_gcloud_components
    else
        print_warning "Failed to install Google Cloud CLI."
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
        if ! sudo apt install -qq -y unattended-upgrades; then
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

    # Note: WSL doesn't use systemd by default, so we check if it's available
    if command -v systemctl &>/dev/null && systemctl is-system-running &>/dev/null; then
        if systemctl is-enabled unattended-upgrades &>/dev/null; then
            print_debug "unattended-upgrades service already enabled."
        else
            print_message "Enabling unattended-upgrades service..."
            sudo systemctl enable unattended-upgrades
            sudo systemctl start unattended-upgrades
            print_success "unattended-upgrades service enabled."
        fi
    else
        print_debug "Systemd not available (typical for WSL1). Unattended-upgrades will run via cron."
    fi
}

# Install OpenTofu (open-source Terraform fork)
install_opentofu() {
    if command -v tofu &> /dev/null; then
        print_debug "OpenTofu is already installed."
        return
    fi

    print_message "Installing OpenTofu..."
    ensure_brew_available
    if brew install opentofu; then
        print_success "OpenTofu installed."
    else
        print_error "Failed to install OpenTofu."
    fi
}

# Install cloudflared (Cloudflare Tunnel client)
install_cloudflared() {
    if command -v cloudflared &> /dev/null; then
        print_debug "cloudflared is already installed."
        return
    fi

    print_message "Installing cloudflared..."
    ensure_brew_available
    if brew install cloudflared; then
        print_success "cloudflared installed."
    else
        print_error "Failed to install cloudflared."
    fi
}

# Install Turso CLI (libSQL database platform)
install_turso() {
    if command -v turso &> /dev/null; then
        print_debug "Turso CLI is already installed."
        return
    fi

    print_message "Installing Turso CLI..."
    ensure_brew_available
    if brew install tursodatabase/tap/turso; then
        print_success "Turso CLI installed."
    else
        print_error "Failed to install Turso CLI."
    fi
}

# Install lefthook (git hooks manager)
install_lefthook() {
    if command -v lefthook &> /dev/null; then
        print_debug "lefthook is already installed."
        return
    fi

    print_message "Installing lefthook..."
    if ! go install github.com/evilmartians/lefthook@latest; then
        print_error "Failed to install lefthook."
        return 1
    fi
    print_success "lefthook installed."
}

# Install act for running GitHub Actions locally
install_act() {
    if ! command -v act &> /dev/null; then
        print_message "Installing act (GitHub Actions runner)..."
        ensure_brew_available
        if ! brew install act; then
            print_error "Failed to install act via Homebrew."
            return 1
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
    ensure_brew_available
    if brew install uv; then
        print_success "uv installed."
    else
        print_error "Failed to install uv."
    fi
}

# Install the Tea workstation client on work machines.
install_gitea_client() {
    if [[ "${WORK_MACHINE:-}" != "1" ]]; then
        print_debug "Skipping Gitea client (not a work machine)."
        return 0
    fi

    if ! command -v brew &> /dev/null; then
        print_error "Homebrew is required to install the Gitea client on this platform."
        return 1
    fi

    local brew_prefix=""
    local managed_path=""
    local original_command=""
    local resolved_command=""
    local version_output=""
    brew_prefix=$(brew --prefix) || {
        print_error "Could not resolve the Homebrew prefix for the Gitea client."
        return 1
    }
    managed_path="${brew_prefix}/bin/tea"
    original_command=$(PATH="${SETUP_ORIGINAL_PATH:-${PATH}}" command -v tea 2>/dev/null || true)
    if [[ -n "${original_command}" && "${original_command}" != "${managed_path}" ]] && { [[ ! -e "${managed_path}" ]] || [[ ! "${original_command}" -ef "${managed_path}" ]]; }; then
        print_error "A conflicting tea executable is earlier on PATH: ${original_command}"
        print_debug "Remove it from PATH or move ${brew_prefix}/bin ahead of it, then rerun setup."
        return 1
    fi

    if brew list --formula tea &> /dev/null; then
        print_message "Updating Gitea client with Homebrew..."
        if ! brew upgrade tea; then
            print_error "Failed to update the Gitea client with Homebrew."
            return 1
        fi
    else
        print_message "Installing Gitea client with Homebrew..."
        if ! brew install tea; then
            print_error "Failed to install the Gitea client with Homebrew."
            return 1
        fi
    fi

    export PATH="${brew_prefix}/bin:${PATH}"
    if [[ ! -x "${managed_path}" ]] || ! version_output=$("${managed_path}" --version 2>/dev/null) || [[ ! "${version_output}" =~ [0-9]+\.[0-9]+ ]]; then
        print_error "Gitea client verification failed at ${managed_path}."
        return 1
    fi
    resolved_command=$(command -v tea 2>/dev/null || true)
    if [[ "${resolved_command}" != "${managed_path}" ]] && { [[ -z "${resolved_command}" || ! -e "${managed_path}" ]] || [[ ! "${resolved_command}" -ef "${managed_path}" ]]; }; then
        print_error "The tea command resolves to ${resolved_command:-<missing>} instead of ${managed_path}."
        return 1
    fi

    print_success "Gitea client is ready (${version_output})."
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
    if ! bash <<< "${bun_install_script}"; then
        print_error "Failed to install Bun."
        return 1
    fi

    # Add bun to PATH for current session
    export PATH="${HOME}/.bun/bin:${PATH}"
    
    print_success "Bun installed."
}

# Install Socket Firewall for supply chain security scanning
install_sfw() {
    if [[ "${WORK_MACHINE:-}" != "1" ]]; then
        print_debug "Skipping Socket Firewall (not a work machine)."
        return
    fi

    if command -v sfw &> /dev/null; then
        print_debug "sfw is already installed."
        return
    fi

    # Ensure bun is available
    if [[ -d "${HOME}/.bun" ]]; then
        export PATH="${HOME}/.bun/bin:${PATH}"
    fi

    if ! command -v bun &> /dev/null; then
        print_warning "Bun not found. Cannot install Socket Firewall."
        print_debug "Install Bun first, then run: bun install -g sfw"
        return
    fi

    print_message "Installing Socket Firewall..."
    if bun install -g sfw > /dev/null 2>&1; then
        print_success "Socket Firewall installed."
    else
        print_error "Failed to install Socket Firewall."
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

apt_kept_back_packages() {
    awk '
        /The following packages have been kept back:|The following upgrades have been deferred due to phasing:/ { capture=1; next }
        capture && /^  / {
            for (i=1; i<=NF; i++) {
                printf "%s%s", separator, $i
                separator=" "
            }
            next
        }
        capture { capture=0 }
        END { if (separator != "") print "" }
    '
}

update_packages() {
    local _upgrade_output=""
    local _upgrade_status=0
    local _kept_back=""
    local _updates_complete=1
    local _tmux_hold_added=0
    local _brew_tmux_pin_added=0
    local _brew_upgrade_status=0
    local _apt_holds=""
    local _brew_pins=""

    print_message "Updating all packages..."
    if ! brew update; then
        print_error "Homebrew update failed."
        return 1
    fi
    # Pin tmux during upgrades without changing a pre-existing user pin.
    _brew_pins=$(brew list --pinned 2>/dev/null || true)
    if ! grep -Fxq tmux <<< "${_brew_pins}" && brew pin tmux 2>/dev/null; then
        _brew_tmux_pin_added=1
    fi
    brew upgrade || _brew_upgrade_status=$?
    if [[ "${_brew_tmux_pin_added}" -eq 1 ]] && ! brew unpin tmux 2>/dev/null; then
        print_error "Failed to remove the temporary Homebrew tmux pin."
        return 1
    fi
    if [[ "${_brew_upgrade_status}" -ne 0 ]]; then
        print_error "Homebrew package upgrade failed."
        return "${_brew_upgrade_status}"
    fi
    if can_sudo; then
        if ! sudo apt update; then
            print_error "Failed to update apt package lists."
            return 1
        fi
        _apt_holds=$(apt-mark showhold 2>/dev/null || true)
        if dpkg -s tmux > /dev/null 2>&1 && ! grep -Fxq tmux <<< "${_apt_holds}"; then
            if ! sudo apt-mark hold tmux 2>/dev/null; then
                print_error "Failed to hold tmux before the package upgrade."
                return 1
            fi
            _tmux_hold_added=1
        fi
        _upgrade_output=$(sudo LC_ALL=C apt upgrade --with-new-pkgs -y 2>&1) || _upgrade_status=$?
        printf '%s\n' "${_upgrade_output}"
        if [[ "${_tmux_hold_added}" -eq 1 ]] && ! sudo apt-mark unhold tmux 2>/dev/null; then
            print_error "Failed to remove the temporary tmux hold after the package upgrade."
            return 1
        fi
        if [[ "${_upgrade_status}" -ne 0 ]]; then
            print_error "Package upgrade failed."
            return "${_upgrade_status}"
        fi
        if ! sudo apt autoremove -y; then
            print_warning "Package upgrade completed, but autoremove failed."
            return 1
        fi
        _kept_back=$(apt_kept_back_packages <<< "${_upgrade_output}")
        if [[ -n "${_kept_back}" ]]; then
            print_warning "Packages remain kept back after upgrade: ${_kept_back}"
            _updates_complete=0
        fi
    else
        print_warning "No sudo access - skipping apt system updates."
    fi

    if [[ "${_updates_complete}" -eq 1 ]]; then
        print_success "Package updates completed."
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

# Upload log to centralized collector (non-fatal)
upload_log() {
    local setup_hostname=""

    if [[ -z "${SETUP_LOG_FILE}" ]] || [[ ! -f "${SETUP_LOG_FILE}" ]]; then
        return 0
    fi

    setup_hostname=$(hostname 2>/dev/null) || setup_hostname="unknown"
    print_debug "Uploading log to logs.scowalt.com..."
    if ! curl --fail --silent -X POST \
        -F "file=@${SETUP_LOG_FILE}" \
        "https://logs.scowalt.com/upload?hostname=${setup_hostname}" \
        --max-time 10 \
        > /dev/null 2>&1; then
        print_warning "Failed to upload setup log. Local log remains at ${SETUP_LOG_FILE}."
    fi
}

start_setup_log() {
    local log_dir="${HOME}/.local/log/machine-setup"
    if ! mkdir -p "${log_dir}"; then
        print_warning "Could not create setup log directory at ${log_dir}; continuing without log upload."
        return 1
    fi

    SETUP_LOG_FILE="${log_dir}/$(date +%Y-%m-%d-%H%M%S).log"
    if ! touch "${SETUP_LOG_FILE}"; then
        print_warning "Could not create setup log at ${SETUP_LOG_FILE}; continuing without log upload."
        SETUP_LOG_FILE=""
        return 1
    fi

    exec 3>&1
    exec > >({ tee -a "${SETUP_LOG_FILE}" || true; }) 2>&1
    SETUP_LOG_TEE_PID=$!
    SETUP_LOGGING_ACTIVE=1
    print_debug "Logging to ${SETUP_LOG_FILE}"
}

finish_setup_log() {
    local setup_status="$1"

    if [[ "${SETUP_LOGGING_ACTIVE}" == "1" ]]; then
        echo -e "${GRAY}Run log saved to: ${SETUP_LOG_FILE}${NC}"
        exec 1>&3 2>&3
        exec 3>&-
        if [[ -n "${SETUP_LOG_TEE_PID}" ]]; then
            wait "${SETUP_LOG_TEE_PID}" 2>/dev/null || true
        fi
        SETUP_LOG_TEE_PID=""
        SETUP_LOGGING_ACTIVE=0
        upload_log
    fi

    return "${setup_status}"
}

# Warn if the WSL instance has a restart pending. Informational only; never
# affects the run's exit status. The pending-reboot state is for the WSL
# instance, not the Windows host (win.ps1 reports host state). Note: an instance
# restart cannot apply new kernels; the WSL kernel ships with Windows.
check_pending_reboot() {
    if [[ ! -f /var/run/reboot-required ]]; then
        print_debug "No WSL instance restart pending."
        return 0
    fi

    print_warning "WSL instance restart pending. Run 'wsl --shutdown' in Windows PowerShell, then reopen WSL."

    if [[ -f /var/run/reboot-required.pkgs ]]; then
        local pkg pkgs
        pkgs=$(head -n 5 /var/run/reboot-required.pkgs 2> /dev/null) || pkgs=""
        if [[ -n "${pkgs}" ]]; then
            print_debug "Packages that triggered it (up to 5):"
            while IFS= read -r pkg; do
                print_debug "  ${pkg}"
            done <<< "${pkgs}"
        fi
    fi
}

run_setup_tasks() {
    local _setup_had_errors=0

    # Run the setup tasks
    echo -e "\n${BOLD}🐧 WSL Development Environment Setup${NC}"
    echo -e "${GRAY}Version 178 | Last changed: Manage show-me agent skill${NC}"

    if ! acquire_setup_lock; then
        return 1
    fi

    fail_unsupported_headless_paseo_daemon || return 1

    # Create ~/.env.local (migrating old token files if needed)
    create_env_local

    # Source env vars early so optional setup flags are available
    if [[ -f "${HOME}/.env.local" ]]; then
        set -a
        # shellcheck source=/dev/null
        source "${HOME}/.env.local"
        set +a
    fi

    print_section "User & System Setup"
    ensure_not_root || return 1
    update_and_install_core

    print_section "SSH Configuration"
    setup_ssh_key || return 1
    add_github_to_known_hosts || return 1

    current_user=$(whoami || true)
    if [[ "${current_user}" == "scowalt" ]]; then
        print_section "Code Directory Setup"
        setup_code_directory
    fi

    print_section "Package Manager"
    install_homebrew
    install_brew_packages

    print_section "Development Tools"
    install_gitea_client || return 1
    install_starship
    install_lefthook
    install_mise
    install_uv
    install_bun
    install_sfw
    install_opentofu
    install_cloudflared
    install_turso

    print_section "Security Tools"
    install_1password_cli
    install_tailscale
    install_secrets_manager
    install_gcloud_cli
    setup_unattended_upgrades

    print_section "Shared Directories"
    print_section "Dotfiles Management"

    # Check if we have access (via SSH or deploy key)
    # If not, try interactive deploy key setup
    if check_dotfiles_access || setup_dotfiles_deploy_key; then
        # We have access, proceed with chezmoi setup
        install_chezmoi
        if ! initialize_chezmoi; then
            _setup_had_errors=1
        fi
        # chezmoi init --apply overwrites ~/.ssh/config, removing the
        # github-dotfiles host alias needed for deploy key access.
        # Re-bootstrap it before any further chezmoi network operations.
        bootstrap_ssh_config
        configure_chezmoi_git
        update_chezmoi
        if ! chezmoi apply --force; then
            print_error "Failed to apply chezmoi dotfiles."
            _setup_had_errors=1
        fi
        # The apply may replace ~/.ssh/config; leave the deploy alias durable.
        bootstrap_ssh_config
        tmux source ~/.tmux.conf 2>/dev/null || true
    else
        print_warning "Skipping dotfiles management - no access to repository."
    fi

    print_section "Shell Configuration"
    set_fish_as_default_shell
    install_act
    install_tmux_plugins
    enable_user_lingering
    install_iterm2_shell_integration

    print_section "Additional Development Tools"
    install_claude_code
    install_gemini_cli
    install_codex_cli
    install_portless_cli
    install_ntn_cli
    remove_rtk_resources || return 1
    remove_attention_span_resources || return 1
    if ! setup_matt_pocock_skills; then
        _setup_had_errors=1
    fi
    if install_pi_cli; then
        configure_pi_defaults
        seed_pi_synthetic_models
        seed_pi_zai_models
        remove_pi_subagents
        remove_pi_rpiv_packages
        setup_pi_mcp_adapter
        setup_pi_claude_bridge
        setup_pi_companion_packages
        setup_pi_goal_autoresearch
    else
        remove_pi_subagents
        remove_pi_rpiv_packages
        if [[ "${BAN_PI_MCP_ADAPTER:-}" == "1" ]]; then
            setup_pi_mcp_adapter
        fi
        if [[ "${BAN_PI_GOAL_AUTORESEARCH:-}" == "1" ]]; then
            setup_pi_goal_autoresearch
        fi
        print_warning "Skipping Pi extension setup because Pi migration failed."
        _setup_had_errors=1
    fi

    if ! setup_simple_english_skill; then
        _setup_had_errors=1
    fi
    if ! setup_show_me_skill; then
        _setup_had_errors=1
    fi
    if ! configure_pi_skill_ownership; then
        _setup_had_errors=1
    fi

    remove_impeccable_resources

    remove_compound_engineering_resources

    print_section "Final Updates"
    if ! update_packages; then
        _setup_had_errors=1
    fi

    check_pending_reboot

    if [[ "${_setup_had_errors}" -eq 0 ]]; then
        printf '\n%b%b✨ Setup complete!%b\n\n' "${GREEN}" "${BOLD}" "${NC}"
    else
        print_warning "Setup completed with errors; review the failures above."
    fi

    return "${_setup_had_errors}"
}

main() {
    local setup_status=0

    start_setup_log || true
    run_setup_tasks "$@" || setup_status=$?
    finish_setup_log "${setup_status}"
}

main "$@"
