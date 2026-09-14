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

SETUP_ORIGINAL_PATH="${PATH}"
SETUP_ORIGINAL_CLAUDE_COMMAND=$(command -v claude 2>/dev/null || true)
SETUP_BREW_TRUST_FAILURES=0
SETUP_LOG_FILE=""
SETUP_LOG_TEE_PID=""
SETUP_LOGGING_ACTIVE=0
DOTFILES_ACCESS_METHOD=""
SUDO_KEEPALIVE_PID=""

stop_sudo_keepalive() {
    if [[ -n "${SUDO_KEEPALIVE_PID}" ]]; then
        kill "${SUDO_KEEPALIVE_PID}" 2>/dev/null || true
        wait "${SUDO_KEEPALIVE_PID}" 2>/dev/null || true
        SUDO_KEEPALIVE_PID=""
    fi
}

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

# Scott's Telegram alerts (optional, direct Bot API requests)
# See ~/.config/agent-docs/telegram-alerts.md after chezmoi apply
# TELEGRAM_ALERTS_BOT_TOKEN=
# TELEGRAM_ALERTS_CHAT_ID=
# Work-machine alerts require Scott's explicit permission

# Machine/setup guards
# HEADLESS=1
# Paseo release channel (beta by default; use stable to follow stable releases)
# PASEO_CHANNEL=beta
# WORK_MACHINE=1
# BAN_PI_MCP_ADAPTER=1
# BAN_PI_GOAL_AUTORESEARCH=1
# BAN_MATT_POCOCK_SKILLS=1
# ZAI_API_KEY=<your z.ai API key>
# OpenCode Go console key (Go subscription; keep Use balance disabled in the console)
# OPENCODE_GO_API_KEY=<your OpenCode Go API key>
EOF
        chmod 600 "${HOME}/.env.local"
        print_debug "Created placeholder ~/.env.local"
    fi
}

# Check if user is scowalt or a secondary user (<org>-scowalt pattern)
is_scowalt_user() {
    local user="${1:-$(whoami || true)}"
    [[ "${user}" == "scowalt" ]] || [[ "${user}" == *-scowalt ]]
}

# Check if running as main user (scowalt)
is_main_user() {
    local _whoami
    _whoami=$(whoami || true)
    [[ "${_whoami}" == "scowalt" ]]
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
    existing_keys=$(fetch_github_ssh_keys "https://github.com/scowalt.keys" 2>/dev/null) || return 1
    [[ -n "${local_key}" ]] && awk -v expected="${local_key}" 'NF >= 2 && $2 == expected { found=1 } END { exit !found }' <<< "${existing_keys}"
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

# Request sudo upfront and keep credentials fresh throughout script execution
# This avoids multiple password prompts during long-running scripts
request_sudo_upfront() {
    # Skip if user doesn't have sudo capability
    local _user_groups
    _user_groups=$(groups 2>/dev/null) || true
    if ! echo "${_user_groups}" | grep -qE '\b(sudo|wheel|admin)\b'; then
        print_debug "User not in sudo group, skipping sudo request."
        return 0
    fi

    # Check if credentials are already cached
    if sudo -n true 2>/dev/null; then
        print_debug "Sudo credentials already cached."
    else
        print_message "This script requires sudo access for system operations."
        print_message "Please enter your password once to authorize all operations."
        # shellcheck disable=SC2024
        if ! sudo -v < /dev/tty; then
            print_warning "Sudo authentication failed. Some operations will be skipped."
            return 1
        fi
    fi

    # Mark that we have sudo
    _sudo_checked=1
    _has_sudo=1

    # Start background process to keep credentials fresh
    # Refresh every 50 seconds (sudo timeout is typically 5-15 minutes)
    (
        while true; do
            sleep 50
            sudo -n true 2>/dev/null || exit 0
        done
    ) > /dev/null 2>&1 &
    SUDO_KEEPALIVE_PID=$!

    # Set up trap to kill the background process on exit
    trap stop_sudo_keepalive EXIT

    print_success "Sudo credentials cached for this session."
    return 0
}

# Ensure the script is not run as root
ensure_not_root() {
    if [[ "${EUID}" -eq 0 ]]; then
        print_section "Root User Detected"
        print_message "This script should be run as a regular user, not root."
        print_message "Run the following commands to create the 'scowalt' user:"
        echo ""
        echo "  # Create user with home directory"
        echo "  useradd -m -s /bin/bash -G wheel scowalt"
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

# Verify we're running on Bazzite OS
verify_bazzite_system() {
    print_message "Verifying Bazzite OS..."

    if [[ ! -f /etc/os-release ]]; then
        print_error "Cannot detect operating system (/etc/os-release not found)."
        return 1
    fi

    if ! grep -qi "bazzite" /etc/os-release; then
        print_error "This script is designed for Bazzite OS only."
        print_message "Detected system:"
        grep "PRETTY_NAME" /etc/os-release
        return 1
    fi

    print_success "Bazzite OS confirmed."
}

# Ensure Homebrew is available in PATH
ensure_brew_available() {
    if command -v brew &> /dev/null; then
        print_debug "Homebrew is already in PATH."
        export HOMEBREW_NO_AUTO_UPDATE=1
        export HOMEBREW_NO_INSTALL_CLEANUP=1
        return 0
    fi

    # Try to initialize from Linuxbrew default location
    if [[ -x /home/linuxbrew/.linuxbrew/bin/brew ]]; then
        print_message "Initializing Homebrew..."
        local brew_env
        brew_env=$(/home/linuxbrew/.linuxbrew/bin/brew shellenv || true)
        eval "${brew_env}"
        export HOMEBREW_NO_AUTO_UPDATE=1
        export HOMEBREW_NO_INSTALL_CLEANUP=1
        print_success "Homebrew initialized."
        return 0
    fi

    print_error "Homebrew not found. Bazzite should have Homebrew pre-installed."
    print_message "Try running: /home/linuxbrew/.linuxbrew/bin/brew shellenv"
    return 1
}

# Trust only third-party Homebrew formulae explicitly managed by this script.
ensure_brew_formula_trusted() {
    local item=$1
    local tap=$2

    if ! { brew tap || true; } | grep -Fxq "${tap}"; then
        print_message "Adding Homebrew tap ${tap}..."
        if ! brew tap "${tap}"; then
            SETUP_BREW_TRUST_FAILURES=1
            print_error "Failed to tap ${tap}; cannot manage ${item}."
            return 1
        fi
    fi

    if brew trust --formula "${item}" > /dev/null; then
        print_debug "Trusted managed Homebrew formula: ${item}"
        return 0
    fi

    SETUP_BREW_TRUST_FAILURES=1
    print_error "Failed to trust managed Homebrew formula ${item}."
    return 1
}

# Install core packages via Homebrew
install_core_packages() {
    print_message "Checking core packages..."

    ensure_brew_formula_trusted "libsql/sqld/sqld" "libsql/sqld" || return 1
    ensure_brew_formula_trusted "tursodatabase/tap/turso" "tursodatabase/tap" || return 1

    # fish is pre-installed on Bazzite, so it is excluded from these lists.
    local formulae=("git" "curl" "wget" "jq" "unzip" "tmux" "starship" "gh" "chezmoi" "opentofu" "go" "uv" "fswatch" "tailscale" "act" "cloudflared" "tursodatabase/tap/turso" "shellcheck" "gitleaks" "lefthook" "mise" "poppler" "bubblewrap")
    local casks=("1password-cli")
    local installed_formulae
    local installed_casks
    local package
    local short_name
    local failed=()
    local installed_count=0

    installed_formulae=$(brew list --formula -1 2>/dev/null || true)
    installed_casks=$(brew list --cask -1 2>/dev/null || true)

    for package in "${formulae[@]}"; do
        short_name="${package##*/}"
        if grep -Fxq "${short_name}" <<< "${installed_formulae}"; then
            print_debug "${short_name} is already installed."
            continue
        fi
        print_message "Installing missing formula: ${package}"
        if brew install "${package}"; then
            ((installed_count++)) || true
        else
            failed+=("${package}")
        fi
    done

    for package in "${casks[@]}"; do
        if grep -Fxq "${package}" <<< "${installed_casks}"; then
            print_debug "${package} cask is already installed."
            continue
        fi
        print_message "Installing missing cask: ${package}"
        if brew install --cask "${package}"; then
            ((installed_count++)) || true
        else
            failed+=("${package}")
        fi
    done

    if [[ "${#failed[@]}" -gt 0 ]]; then
        print_error "Failed to install required Homebrew packages: ${failed[*]}"
        return 1
    fi
    if [[ "${installed_count}" -gt 0 ]]; then
        print_success "Core packages installed."
    else
        print_success "All core packages are already installed."
    fi
}

# Install the appropriate secrets manager based on machine type
install_secrets_manager() {
    if [[ "${WORK_MACHINE:-}" == "1" ]]; then
        if command -v infisical &>/dev/null; then
            print_debug "Infisical CLI already installed."
            return
        fi
        print_message "Installing Infisical CLI..."
        if ! { brew tap || true; } | grep -q "^infisical/get-cli$"; then
            brew tap infisical/get-cli 2>/dev/null || true
        fi
        if brew install infisical/get-cli/infisical; then
            print_success "Infisical CLI installed."
        else
            print_error "Failed to install Infisical CLI."
            return 1
        fi
    else
        if ! ensure_brew_formula_trusted "dopplerhq/doppler/doppler" "dopplerhq/doppler"; then
            print_error "Doppler CLI formula is not trusted."
            return 1
        fi
        if command -v doppler &>/dev/null; then
            print_debug "Doppler CLI already installed."
            return
        fi
        print_message "Installing Doppler CLI..."
        if brew install dopplerhq/doppler/doppler; then
            print_success "Doppler CLI installed."
        else
            print_error "Failed to install Doppler CLI."
            return 1
        fi
    fi
}

# Update Google Cloud CLI components when the component manager is available.
update_gcloud_components() {
    if ! command -v gcloud &>/dev/null; then
        print_debug "Google Cloud CLI not installed; skipping component update."
        return
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

    if ! command -v brew &>/dev/null; then
        print_warning "Homebrew not found. Cannot install Google Cloud CLI."
        return
    fi

    print_message "Installing Google Cloud CLI..."
    if brew install --cask gcloud-cli; then
        print_success "Google Cloud CLI installed."
        update_gcloud_components
    else
        print_warning "Failed to install Google Cloud CLI."
    fi
}

# Enable Tailscale SSH for keyless access over Tailscale network
tailscale_ssh_is_enabled() {
    local prefs=""
    prefs=$(tailscale debug prefs 2>/dev/null || true)
    grep -Eq '"RunSSH"[[:space:]]*:[[:space:]]*true' <<< "${prefs}"
}

setup_tailscale_ssh() {
    if ! command -v tailscale &>/dev/null; then
        print_debug "Tailscale not installed, skipping SSH setup."
        return
    fi

    if ! tailscale_ssh_is_enabled; then
        if ! can_sudo; then
            print_error "No sudo access; cannot enable Tailscale SSH."
            return 1
        fi
        print_message "Enabling Tailscale SSH..."
        if ! sudo tailscale set --ssh; then
            print_error "Failed to enable Tailscale SSH."
            return 1
        fi
        if ! tailscale_ssh_is_enabled; then
            print_error "Tailscale accepted the SSH setting, but RunSSH is still disabled."
            return 1
        fi
        print_success "Tailscale SSH enabled."
    else
        print_debug "Tailscale SSH is already enabled."
    fi
}

# Check and set up SSH key (simplified for physical machine — no VPS detection)
setup_ssh_key() {
    print_message "Checking for existing SSH key associated with GitHub..."

    # Retrieve GitHub-associated keys
    local existing_keys
    if ! existing_keys=$(fetch_github_ssh_keys "https://github.com/scowalt.keys"); then
        print_error "Failed to download SSH keys from GitHub after three attempts; key registration could not be verified."
        return 1
    fi

    if [[ -f ~/.ssh/id_rsa.pub ]]; then
        local local_key
        local_key=$(awk '{print $2}' ~/.ssh/id_rsa.pub)

        if awk -v expected="${local_key}" 'NF >= 2 && $2 == expected { found=1 } END { exit !found }' <<< "${existing_keys}"; then
            print_success "Existing SSH key recognized by GitHub."
        else
            print_error "SSH key not recognized by GitHub. Please add it manually."
            print_message "Please add the following SSH key to GitHub:"
            cat ~/.ssh/id_rsa.pub
            print_message "Opening GitHub SSH keys page..."
            xdg-open "https://github.com/settings/keys" 2>/dev/null || true
            return 1
        fi
    else
        print_warning "No SSH key found. Generating a new SSH key..."
        ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
        print_success "SSH key generated."
        print_message "Please add the following SSH key to GitHub:"
        cat ~/.ssh/id_rsa.pub
        print_message "Opening GitHub SSH keys page..."
        xdg-open "https://github.com/settings/keys" 2>/dev/null || true
        return 1
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
            return 1
        fi
        print_success "GitHub's SSH key added."
    else
        print_debug "GitHub's SSH key already exists in known_hosts."
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

    # Method 1: User with verified SSH key on GitHub
    if has_verified_ssh_key; then
        # < /dev/null prevents ssh from consuming stdin (important for curl|bash)
        local _ssh_output
        _ssh_output=$(ssh -T git@github.com < /dev/null 2>&1) || true
        if echo "${_ssh_output}" | grep -q "successfully authenticated"; then
            print_debug "Access via SSH (verified key)"
            DOTFILES_ACCESS_METHOD="ssh"
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
            DOTFILES_ACCESS_METHOD="token"
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

source_gh_tokens() {
    if [[ -f "${HOME}/.env.local" ]]; then
        set -a
        # shellcheck source=/dev/null
        source "${HOME}/.env.local"
        set +a
        if [[ -n "${GH_TOKEN}" ]]; then
            print_debug "GH_TOKEN loaded from ~/.env.local"
        fi
        if [[ -n "${GH_TOKEN_SCOWALT}" ]]; then
            print_debug "GH_TOKEN_SCOWALT loaded from ~/.env.local"
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
            return 1
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

# Reconcile chezmoi's remote with the strongest verified SSH credential.
fix_chezmoi_remote_for_deploy_key() {
    local chez_src="${HOME}/.local/share/chezmoi"
    local current_remote=""
    local desired_remote=""
    local personal_key=""
    local ssh_output=""
    [[ ! -d "${chez_src}/.git" ]] && return 0

    current_remote=$(git -C "${chez_src}" remote get-url origin 2>/dev/null) || return 0
    if has_verified_ssh_key; then
        if [[ -f "${HOME}/.ssh/id_rsa" ]]; then
            personal_key="${HOME}/.ssh/id_rsa"
        elif [[ -f "${HOME}/.ssh/id_ed25519" ]]; then
            personal_key="${HOME}/.ssh/id_ed25519"
        fi
        if [[ -n "${personal_key}" ]]; then
            ssh_output=$(ssh -o IdentitiesOnly=yes -i "${personal_key}" -T git@github.com < /dev/null 2>&1) || true
            if grep -q "successfully authenticated" <<< "${ssh_output}"; then
                desired_remote="git@github.com:scowalt/dotfiles.git"
            fi
        fi
    fi
    if [[ -z "${desired_remote}" && -f "${HOME}/.ssh/dotfiles-deploy-key" ]]; then
        ssh_output=$(ssh -o IdentitiesOnly=yes -i "${HOME}/.ssh/dotfiles-deploy-key" -T git@github.com < /dev/null 2>&1) || true
        if grep -q "successfully authenticated" <<< "${ssh_output}"; then
            desired_remote="git@github-dotfiles:scowalt/dotfiles.git"
        fi
    fi
    if [[ -z "${desired_remote}" ]]; then
        print_warning "Could not verify an SSH credential for the chezmoi remote; leaving it unchanged."
        return 0
    fi

    [[ "${current_remote}" == "${desired_remote}" ]] && return 0
    case "${current_remote}" in
        git@github.com:scowalt/dotfiles.git|git@github-dotfiles:scowalt/dotfiles.git) ;;
        *) return 0 ;;
    esac

    print_message "Reconciling chezmoi remote with available SSH credentials..."
    if git -C "${chez_src}" remote set-url origin "${desired_remote}"; then
        print_success "Chezmoi remote URL updated."
    else
        print_warning "Failed to update chezmoi remote URL."
        return 1
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
    local user_name
    local current_shell
    local passwd_entry
    local shell_change_status=0

    user_name=$(whoami || true)
    if [[ -z "${user_name}" || ! -x /usr/bin/fish ]]; then
        print_error "Fish shell is unavailable at /usr/bin/fish."
        return 1
    fi

    passwd_entry=$(getent passwd "${user_name}" || true)
    current_shell=$(echo "${passwd_entry}" | cut -d: -f7)
    if [[ "${current_shell}" != "/usr/bin/fish" ]]; then
        if ! can_sudo; then
            print_error "No sudo access; cannot change the default shell to fish."
            return 1
        fi
        print_message "Setting Fish as the default shell..."
        if ! grep -Fxq "/usr/bin/fish" /etc/shells; then
            if ! echo "/usr/bin/fish" | sudo tee -a /etc/shells > /dev/null; then
                print_error "Failed to add /usr/bin/fish to /etc/shells."
                return 1
            fi
        fi

        if command -v chsh &> /dev/null; then
            # shellcheck disable=SC2024
            sudo chsh -s /usr/bin/fish "${user_name}" < /dev/tty || shell_change_status=$?
        elif command -v usermod &> /dev/null; then
            sudo usermod --shell /usr/bin/fish "${user_name}" || shell_change_status=$?
        elif [[ -x /usr/sbin/usermod ]]; then
            sudo /usr/sbin/usermod --shell /usr/bin/fish "${user_name}" || shell_change_status=$?
        else
            print_error "Neither chsh nor usermod is available to change the login shell."
            return 1
        fi

        if [[ "${shell_change_status}" -ne 0 ]]; then
            print_error "Failed to set Fish as the default shell (status ${shell_change_status})."
            return 1
        fi

        passwd_entry=$(getent passwd "${user_name}" || true)
        current_shell=$(echo "${passwd_entry}" | cut -d: -f7)
        if [[ "${current_shell}" != "/usr/bin/fish" ]]; then
            print_error "Login shell verification failed; getent reports ${current_shell:-<missing>}."
            return 1
        fi
        print_success "Fish shell set as default."
    else
        print_debug "Fish shell is already the default shell."
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
    if bash <<< "${bun_install_script}"; then
        # Add bun to PATH for current session
        export PATH="${HOME}/.bun/bin:${PATH}"
        print_success "Bun installed."
    else
        print_error "Failed to install Bun."
        return 1
    fi
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
    local installer_home=""
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

    if ! installer_home=$(mktemp -d); then
        print_error "Failed to create a temporary home for the Codex installer."
        return 1
    fi
    installer="${installer_home}/install.sh"
    if ! claude_code_run_safely "${curl_bin}" -fsSL --connect-timeout 15 --max-time 120 --retry 2 --retry-delay 2 -o "${installer}" "https://chatgpt.com/codex/install.sh"; then
        rm -rf -- "${installer_home}"
        print_error "Failed to download the Codex installer."
        return 1
    fi

    # The native installer has no skip-profile flag. Its HOME is disposable;
    # explicit destinations keep the CLI/data in the account, not the sandbox.
    # Chezmoi alone owns the real shell profiles. Keep the trusted tool PATH.
    chmod 700 "${installer}"
    if claude_code_run_safely /usr/bin/env CODEX_NON_INTERACTIVE=1 \
        HOME="${installer_home}" CODEX_INSTALL_DIR="${HOME}/.local/bin" \
        CODEX_HOME="${CODEX_HOME:-${HOME}/.codex}" /bin/sh "${installer}"; then
        install_status=0
    else
        install_status=$?
    fi
    rm -rf -- "${installer_home}"
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

# Return success when a resolved executable is within a prefix after resolving
# Bazzite's /home -> /var/home alias.
path_is_within_prefix() {
    local path=$1
    local prefix=$2
    local canonical_path=""
    local canonical_prefix=""

    canonical_path=$(realpath "${path}" 2>/dev/null || true)
    canonical_prefix=$(realpath "${prefix}" 2>/dev/null || true)
    if [[ -z "${canonical_path}" || -z "${canonical_prefix}" ]]; then
        return 1
    fi

    case "${canonical_path}" in
        "${canonical_prefix}"|"${canonical_prefix}/"*) return 0 ;;
        *) return 1 ;;
    esac
}

verify_fish_development_tools() {
    if ! command -v fish &> /dev/null; then
        print_error "Fish is unavailable for the final development-tool smoke test."
        return 1
    fi

    if ! fish -lc 'command -q node; and node --version >/dev/null; and command -q pi; and pi --version >/dev/null; and command -q codex; and codex --version >/dev/null'; then
        print_error "Fresh Fish login smoke test failed for Node.js, Pi, or Codex."
        return 1
    fi

    print_success "Node.js, Pi, and Codex verified in a fresh Fish login shell."
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
# Standalone installer shared verbatim with the other setup entry points.
# Managed Muse profile: offline merge with an identified local-owner barrier.
# 0 = saved/unchanged or warned defer; 1 = failed validation/write/restoration.
# The caller MUST skip later headless lifecycle when the defer flag is 1.
# shellcheck disable=SC2034 # Output flag is consumed by the caller, not on WSL.
configure_paseo_muse_profile() {
    PASEO_MUSE_DEFER_DAEMON_SETUP=0
    if ! command -v node &> /dev/null; then
        PASEO_MUSE_DEFER_DAEMON_SETUP=1
        print_warning "Paseo Muse deferred: Node.js is unavailable. Rerun setup outside Paseo after installing Node.js."
        return 0
    fi
    local result status=0 line
    result=$(HEADLESS="${HEADLESS:-}" PASEO_MACOS_HEADLESS_CANARY="${PASEO_MACOS_HEADLESS_CANARY:-}" \
        PASEO_MUSE_GO_CHANGED="${PI_OPENCODE_GO_CHANGED:-0}" env -u NODE_OPTIONS -u NODE_PATH node --input-type=commonjs - 2>/dev/null <<'PASEO_MUSE_PROFILE_JS'
// BEGIN PASEO MUSE PROFILE
// Paseo 0.8 AgentProfileSchema uses z.string() for IDs (not PluginIdSchema).
// pid-lock.js reserves <home>/paseo.pid before starting its config-owning worker.
// Do not replace this offline transaction with a live whole-array config patch.
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { spawnSync } = require('node:child_process');
const { randomUUID } = require('node:crypto');
const id = 'setup:pi:opencode-go:muse-spark-1.3-contributor';
const core = {provider: 'pi', model: 'opencode-go/muse-spark-1.3-contributor', thinkingOptionId: 'xhigh'};
const marker = 'Managed by scowalt machine setup: headless-paseo-daemon';
const service = 'paseo.service';
const label = 'com.scowalt.paseo-daemon';
const platform = process.platform;
const uid = process.getuid?.() ?? 0;
const headless = process.env.HEADLESS === '1';
const refresh = process.env.PASEO_MUSE_GO_CHANGED === '1';
const record = v => v !== null && typeof v === 'object' && !Array.isArray(v);
class Refusal extends Error { constructor(code, failed = false) { super(code); this.code = code; this.failed = failed; } }
const refuse = code => { throw new Refusal(code); };
const fail = code => { throw new Refusal(code, true); };
const maxSnapshotBytes = 4 * 1024 * 1024;
const maxPidBytes = 64 * 1024;
let home, logicalHome, paseoHome, configPath, pidPath, accountRoots, customHome;
let heldLock = null, restore = null, temporary = null, interrupted = false;
for (const signal of ['SIGINT', 'SIGTERM', 'SIGHUP']) process.on(signal, () => { interrupted = true; });
const checkpoint = async () => { await new Promise(resolve => setImmediate(resolve)); if (interrupted) fail('interrupted'); };
function stat(file) {
    try { return fs.lstatSync(file); } catch (error) { if (error.code === 'ENOENT') return null; throw error; }
}
function same(a, b) { return a === null ? b === null : b !== null && a.dev === b.dev && a.ino === b.ino && a.size === b.size && a.mtimeMs === b.mtimeMs && a.ctimeMs === b.ctimeMs; }
function rootDirectory(file) {
    const s = stat(file);
    return s && s.isDirectory() && !s.isSymbolicLink() && s.uid === 0 && !(s.mode & 0o022);
}
function trustedSystemHomeAlias() {
    const s = stat('/home');
    return platform === 'linux' && s?.isSymbolicLink() && s.uid === 0 &&
        ['var/home', '/var/home'].includes(fs.readlinkSync('/home')) &&
        ['/', '/var', '/var/home'].every(rootDirectory);
}
function checkedPath(file, directory = false) {
    const absolute = path.resolve(file);
    let current = path.parse(absolute).root;
    const parts = absolute.slice(current.length).split(path.sep).filter(Boolean);
    for (let n = 0; n < parts.length; n++) {
        current = path.join(current, parts[n]);
        const s = stat(current);
        if (!s) continue;
        if (s.isSymbolicLink()) {
            // Only Bazzite's root-owned system alias; never a linked user/profile.
            if (current === '/home' && trustedSystemHomeAlias()) continue;
            fail('linked-path');
        }
        const dir = n < parts.length - 1 || directory;
        if (dir ? !s.isDirectory() : !s.isFile() || s.nlink !== 1) fail('unsafe-file-type');
        if ((current === home || current.startsWith(home + path.sep)) && platform !== 'win32' &&
            (s.uid !== uid || (s.mode & 0o022))) fail('unsafe-owner-or-mode');
    }
    return stat(absolute);
}
function checkWindowsMetadataAcl(file) {
    if (platform !== 'win32') return;
    let current = path.resolve(file);
    const relative = path.relative(home, current);
    if (relative === '..' || relative.startsWith('..' + path.sep) || path.isAbsolute(relative)) fail('windows-acl-unverified');
    const existing = [];
    while (true) {
        if (stat(current)) existing.push(current);
        if (current === home) break;
        const parent = path.dirname(current);
        if (parent === current) fail('windows-acl-unverified');
        current = parent;
    }
    // Include HOME even when the default directory/file does not exist yet.
    // Repeat for every snapshot, including native PID and staged JSON metadata.
    const command = String.raw`$ErrorActionPreference='Stop'
$env:PSModulePath = "$PSHOME\Modules"
try {
    $owner = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
    $trusted = @($owner.Value, 'S-1-5-18', 'S-1-5-32-544')
    $paths = @($env:PASEO_MUSE_ACL_PATHS | ConvertFrom-Json)
    if ($paths.Count -eq 0 -or $paths[-1] -ne $env:PASEO_MUSE_ACCOUNT_HOME) { throw 'unverified-boundary' }
    $writes = [System.Security.AccessControl.FileSystemRights]'Write,Delete,DeleteSubdirectoriesAndFiles,ChangePermissions,TakeOwnership'
    foreach ($current in $paths) {
        $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'linked' }
        $acl = Get-Acl -LiteralPath $current
        $sddl = $acl.GetSecurityDescriptorSddlForm([System.Security.AccessControl.AccessControlSections]::Access)
        if (-not $sddl.StartsWith('D:') -or $sddl.Contains('NO_ACCESS_CONTROL')) { throw 'unverified-access' }
        if ($acl.GetOwner([System.Security.Principal.SecurityIdentifier]).Value -notin $trusted) { throw 'unverified-owner' }
        foreach ($rule in $acl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier])) {
            if ($rule.PropagationFlags -band [System.Security.AccessControl.PropagationFlags]::InheritOnly) { continue }
            if ($rule.AccessControlType -eq 'Allow' -and $rule.IdentityReference.Value -notin $trusted -and
                ($rule.FileSystemRights -band $writes)) { throw 'unverified-writer' }
        }
    }
    [Console]::Out.Write('ok')
} catch { exit 1 }`;
    const result = run('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', command], true,
        {PASEO_MUSE_ACL_PATHS: JSON.stringify(existing), PASEO_MUSE_ACCOUNT_HOME: home});
    if (result?.trim() !== 'ok') fail('windows-acl-unverified');
}
function snapshot(file) {
    const s = checkedPath(file);
    checkWindowsMetadataAcl(file);
    if (!s) return {s: null, text: null};
    const limit = file === pidPath ? maxPidBytes : maxSnapshotBytes;
    if (!Number.isSafeInteger(s.size) || s.size < 0 || s.size > limit) fail('metadata-too-large');
    const fd = fs.openSync(file, fs.constants.O_RDONLY | (fs.constants.O_NOFOLLOW || 0));
    try {
        if (!same(s, fs.fstatSync(fd))) fail('file-changed');
        // Read at most the checked size plus one byte, even if a writer grows it.
        const bytes = Buffer.alloc(s.size + 1);
        let used = 0;
        while (used < bytes.length) {
            const count = fs.readSync(fd, bytes, used, bytes.length - used, null);
            if (count === 0) break;
            used += count;
        }
        if (used !== s.size || !same(s, fs.fstatSync(fd)) || !same(s, checkedPath(file))) fail('file-changed');
        return {s, text: bytes.subarray(0, used).toString('utf8')};
    } finally { fs.closeSync(fd); }
}
function json(snap) {
    if (snap.text === null) return null;
    // JSON.parse silently discards duplicate keys. Refuse that ambiguous input.
    const text = snap.text;
    let at = 0;
    const space = () => { while (/\s/.test(text[at] || '') && at < text.length) at++; };
    function string() {
        const start = at++;
        while (at < text.length) { if (text[at++] === '"') return JSON.parse(text.slice(start, at)); if (text[at - 1] === '\\') at++; }
        throw new Error();
    }
    function value() {
        space();
        if (text[at] === '"') { string(); return; }
        if (text[at] === '{' || text[at] === '[') {
            const object = text[at++] === '{', end = object ? '}' : ']';
            const keys = new Set();
            space();
            if (text[at] === end) { at++; return; }
            do {
                space();
                if (object) {
                    if (text[at] !== '"') throw new Error();
                    const key = string();
                    if (keys.has(key)) fail('duplicate-json-key');
                    keys.add(key); space(); if (text[at++] !== ':') throw new Error();
                }
                value(); space();
                if (text[at] === end) { at++; return; }
            } while (text[at++] === ',');
            throw new Error();
        }
        const token = text.slice(at).match(/^(?:true|false|null|-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)/);
        if (!token) throw new Error();
        at += token[0].length;
    }
    try {
        const parsed = JSON.parse(text, (_key, item) => {
            if (typeof item === 'number' && (!Number.isFinite(item) || Number.isInteger(item) && !Number.isSafeInteger(item))) fail('unsafe-json-number');
            return item;
        });
        value(); space(); if (at !== text.length) throw new Error(); return parsed;
    } catch (error) { if (error instanceof Refusal) throw error; fail('invalid-json'); }
}
function merge(snap) {
    const config = snap.text === null ? {} : json(snap);
    if (!record(config) || ('daemon' in config && !record(config.daemon))) fail('invalid-config');
    const daemon = config.daemon || {};
    const profiles = daemon.agentProfiles === undefined ? [] : daemon.agentProfiles;
    if (!Array.isArray(profiles)) fail('invalid-profiles');
    const ids = new Set();
    for (const p of profiles) {
        if (!record(p) || typeof p.id !== 'string' || typeof p.name !== 'string' || typeof p.provider !== 'string' || ids.has(p.id)) fail('invalid-profiles');
        ids.add(p.id);
        for (const key of ['model', 'modeId', 'thinkingOptionId', 'icon', 'color', 'notes']) {
            if (key in p && typeof p[key] !== 'string') fail('invalid-profiles');
        }
        if ('featureValues' in p && !record(p.featureValues)) fail('invalid-profiles');
    }
    const managed = profiles.find(p => p.id === id);
    if (managed && Object.entries(core).every(([key, value]) => managed[key] === value)) return null;
    // A same-name user profile is not setup-owned. ID is the only ownership key.
    const next = managed ? profiles.map(p => p.id === id ? {...p, ...core} : p) :
        [...profiles, {id, name: 'Muse 1.3 Contributor', ...core}];
    return JSON.stringify({...config, daemon: {...daemon, agentProfiles: next}}, null, 2) + '\n';
}
function run(command, args, optional = false, env = {}) {
    if (platform === 'win32' && command === 'powershell.exe') {
        const at = args.indexOf('-Command');
        if (at >= 0) args = args.map((arg, n) => n === at + 1 ? '$env:PSModulePath = "$PSHOME\\Modules"; ' + arg : arg);
    }
    const result = spawnSync(command, args, {encoding: 'utf8', timeout: 30000, maxBuffer: 8 * 1024 * 1024,
        windowsHide: true, shell: false, stdio: ['ignore', 'pipe', 'pipe'],
        env: {...process.env, ...env, HOME: logicalHome, PASEO_HOME: paseoHome}});
    if (result.error || result.status !== 0) {
        if (optional) return null;
        refuse('command-unverified');
    }
    return result.stdout;
}
function systemctl(args) {
    const env = {XDG_RUNTIME_DIR: `/run/user/${uid}`, DBUS_SESSION_BUS_ADDRESS: `unix:path=/run/user/${uid}/bus`};
    const direct = run('systemctl', ['--user', ...args], true, env);
    if (direct !== null) return direct;
    return run('systemctl', [`--machine=${os.userInfo().username}@`, '--user', ...args], false, env);
}
function properties(text) {
    const result = {};
    for (const line of text.trim().split('\n')) {
        const at = line.indexOf('=');
        if (at <= 0 || Object.hasOwn(result, line.slice(0, at))) refuse('invalid-service-state');
        result[line.slice(0, at)] = line.slice(at + 1);
    }
    return result;
}
function serviceState() {
    return properties(systemctl(['show', service, '--property=Id,LoadState,ActiveState,SubState,MainPID,FragmentPath,DropInPaths,NeedDaemonReload,ControlGroup,User,ExecStart,Environment,EnvironmentFiles,KillMode']));
}
function live(pid) {
    try { process.kill(pid, 0); return true; } catch (error) { if (error.code === 'ESRCH') return false; refuse('pid-unverified'); }
}
function pidInfo() {
    const snap = snapshot(pidPath);
    if (!snap.s) return {snap, info: null};
    const info = json(snap);
    if (!record(info) || !Number.isInteger(info.pid) || info.pid <= 1 ||
        info.hostname !== os.hostname() || info.uid !== uid || typeof info.startedAt !== 'string' ||
        !Number.isFinite(Date.parse(info.startedAt)) || !(info.listen === null || typeof info.listen === 'string') ||
        ('desktopManaged' in info && typeof info.desktopManaged !== 'boolean')) refuse('pid-metadata-unverified');
    return {snap, info};
}
function inventory() {
    const processes = [];
    if (platform === 'linux') {
        for (const entry of fs.readdirSync('/proc')) {
            if (!/^\d+$/.test(entry)) continue;
            const dir = `/proc/${entry}`;
            try {
                const processUid = fs.statSync(dir).uid;
                const raw = fs.readFileSync(`${dir}/stat`, 'utf8');
                const fields = raw.slice(raw.lastIndexOf(')') + 2).split(' ');
                const command = fs.readFileSync(`${dir}/cmdline`, 'utf8').replace(/\0/g, ' ');
                const owned = processUid === uid;
                const env = owned ? Object.fromEntries(fs.readFileSync(`${dir}/environ`, 'utf8').split('\0').filter(v => v.includes('=')).map(v => [v.slice(0, v.indexOf('=')), v.slice(v.indexOf('=') + 1)])) : {};
                const cgroup = owned ? fs.readFileSync(`${dir}/cgroup`, 'utf8') : '';
                processes.push({pid: Number(entry), parent: Number(fields[1]), command, env, cgroup, owned});
            } catch (error) { if (error.code !== 'ENOENT' && error.code !== 'ESRCH') refuse('process-inventory-unverified'); }
        }
    } else if (platform === 'darwin') {
        const text = run('ps', ['-axww', '-o', 'pid=,ppid=,uid=,command=']);
        for (const line of text.trim().split('\n')) {
            const match = line.trim().match(/^(\d+)\s+(\d+)\s+(\d+)\s+(.*)$/);
            if (!match) refuse('process-inventory-unverified');
            processes.push({pid: Number(match[1]), parent: Number(match[2]), command: match[4], owned: Number(match[3]) === uid});
        }
    } else if (platform === 'win32') {
        const text = run('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command',
            '$ErrorActionPreference="Stop"; @(Get-CimInstance Win32_Process | Select-Object ProcessId,ParentProcessId,Name,ExecutablePath,CommandLine) | ConvertTo-Json -Compress']);
        let rows;
        try { rows = JSON.parse(text); } catch { refuse('process-inventory-unverified'); }
        if (!Array.isArray(rows)) refuse('process-inventory-unverified');
        for (const row of rows) {
            if (!Number.isInteger(row.ProcessId) || !Number.isInteger(row.ParentProcessId)) refuse('process-inventory-unverified');
            processes.push({pid: row.ProcessId, parent: row.ParentProcessId,
                command: `${row.Name || ''} ${row.ExecutablePath || ''} ${row.CommandLine || ''}`});
        }
    } else refuse('unsupported-platform');
    if (!processes.some(p => p.pid === process.pid)) refuse('process-inventory-unverified');
    return processes;
}
function descends(pid, parent, rows) {
    const seen = new Set();
    while (pid > 1 && !seen.has(pid)) {
        if (pid === parent) return true;
        seen.add(pid);
        const p = rows.find(row => row.pid === pid);
        if (!p) return false;
        pid = p.parent;
    }
    return false;
}
function verifySetupAncestry(rows) {
    let pid = process.pid;
    const seen = new Set();
    while (pid > 1) {
        if (seen.has(pid)) refuse('ancestry-unverified');
        seen.add(pid);
        const row = rows.find(p => p.pid === pid);
        if (!row || !Number.isInteger(row.parent) || row.parent < 0) refuse('ancestry-unverified');
        pid = row.parent;
    }
}
function inGroup(p, group) {
    return !!group && (p.cgroup || '').split('\n').some(line => {
        const value = line.slice(line.indexOf(':', line.indexOf(':') + 1) + 1);
        return value === group || value.startsWith(group + '/');
    });
}
function candidates(rows) {
    return rows.filter(p => p.pid !== process.pid && p.owned !== false && (
        /(?:@getpaseo[\\/]|paseo(?:\.exe|\.app|[\\/\s]|$)|supervisor-entrypoint|daemon-worker|node-entrypoint-runner)/i.test(p.command) ||
        p.env?.PASEO_DESKTOP_MANAGED === '1' ||
        (p.env?.PASEO_HOME && samePaseoHome(p.env.PASEO_HOME) && !descends(process.pid, p.pid, rows))));
}
function ensureNoWriters(owner = null) {
    const rows = inventory();
    if (candidates(rows).length || (owner && rows.some(p => inGroup(p, owner.group) || descends(p.pid, owner.pid, rows)))) refuse('writer-still-present');
    if (owner && live(owner.pid)) refuse('owner-still-present');
    return rows;
}
function checkWrapper() {
    const file = path.join(home, '.local/bin/paseo-daemon-start');
    const snap = snapshot(file);
    const lines = snap.text?.trimEnd().split('\n');
    // Match setup's shell-quoted HOME without executing the wrapper or sourcing it.
    const quoted = "'" + logicalHome.replace(/'/g, "'\\''") + "'";
    if (!lines || lines.length !== 8 || lines[0] !== '#!/bin/bash' || lines[1] !== `# ${marker}` ||
        lines[2] !== 'set -euo pipefail' || lines[3] !== `export HOME=${quoted}` ||
        !/^export PATH='[^'\r\n]*'$/.test(lines[4]) ||
        !/^\[\[ -x '[^'\r\n]+' \]\] \|\| exit 127$/.test(lines[5]) ||
        !/^\[\[ -x '[^'\r\n]+' \]\] \|\| exit 127$/.test(lines[6]) ||
        !/^exec '[^'\r\n]+' daemon start --foreground --listen '[^'\r\n]+'$/.test(lines[7])) refuse('unmanaged-wrapper');
    return {file, snap};
}
function sameHome(value) { return accountRoots.includes(value); }
function accountPath(value) {
    if (typeof value !== 'string' || !path.isAbsolute(value) || value.includes('\0') || value.split(path.sep).includes('..')) return null;
    const absolute = path.resolve(value);
    for (const root of accountRoots) {
        const relative = path.relative(root, absolute);
        if (relative && relative !== '..' && !relative.startsWith('..' + path.sep) && !path.isAbsolute(relative)) return path.join(home, relative);
    }
    return null;
}
function samePaseoHome(value) { return accountPath(value) === paseoHome; }
function daemonHomeMatches(value) {
    // Upstream treats an explicitly empty PASEO_HOME as cwd, not as unset.
    return value === undefined ? !customHome : samePaseoHome(value);
}
function checkCustomHome() {
    if (!customHome) return;
    const s = checkedPath(paseoHome, true);
    // Only pre-existing, private custom directories have an established boundary.
    if (!s) refuse('custom-home-unverified');
    if (platform !== 'win32') {
        if (s.uid !== uid || (s.mode & 0o077)) refuse('custom-home-permissions-unverified');
        return;
    }
    const command = `$ErrorActionPreference='Stop';
$sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$trusted = @($sid, 'S-1-5-18', 'S-1-5-32-544')
$directory = $env:PASEO_HOME
while ($true) {
    $acl = Get-Acl -LiteralPath $directory
    if ($acl.GetOwner([System.Security.Principal.SecurityIdentifier]).Value -ne $sid) { throw 'unverified-owner' }
    foreach ($rule in $acl.Access) {
        if ($rule.AccessControlType -ne 'Allow') { continue }
        $identity = $rule.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value
        if ($identity -in $trusted) { continue }
        $writes = [System.Security.AccessControl.FileSystemRights]'Write,Delete,DeleteSubdirectoriesAndFiles,ChangePermissions,TakeOwnership'
        if ($directory -eq $env:PASEO_HOME -or ($rule.FileSystemRights -band $writes)) { throw 'unverified-access' }
    }
    if ($directory -eq $env:PASEO_MUSE_ACCOUNT_HOME) { break }
    $parent = [System.IO.Path]::GetDirectoryName($directory)
    if (-not $parent -or $parent -eq $directory) { throw 'unverified-boundary' }
    $directory = $parent
}`;
    if (run('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', command], true,
        {PASEO_MUSE_ACCOUNT_HOME: home}) === null) refuse('custom-home-permissions-unverified');
}
function verifyOwnerProcess(info, mainPid, group, rows) {
    if (info.desktopManaged) refuse('desktop-owned');
    if (!descends(info.pid, mainPid, rows)) refuse('service-pid-mismatch');
    if (process.env.PASEO_AGENT_ID || descends(process.pid, mainPid, rows) ||
        rows.some(p => p.pid === process.pid && inGroup(p, group))) refuse('self-hosted-setup');
    if (candidates(rows).some(p => !descends(p.pid, mainPid, rows))) refuse('unknown-writer');
    const owner = rows.find(p => p.pid === info.pid);
    if (!owner || owner.owned === false) refuse('owner-unverified');
    if (platform === 'linux') {
        if (!inGroup(owner, group) || !sameHome(owner.env?.HOME) ||
            !daemonHomeMatches(owner.env?.PASEO_HOME)) refuse('service-home-mismatch');
    } else {
        // ps supplies the actual owner's environment; don't trust only the plist.
        if (/\s/.test(logicalHome) || /\s/.test(paseoHome)) refuse('service-home-unverified');
        const env = run('ps', ['eww', '-p', String(info.pid), '-o', 'command=']);
        const account = [...env.matchAll(/(?:^|\s)HOME=([^\s]*)/g)];
        const overrides = [...env.matchAll(/(?:^|\s)PASEO_HOME=([^\s]*)/g)];
        if (account.length !== 1 || !sameHome(account[0][1]) || overrides.length > 1 ||
            !daemonHomeMatches(overrides[0]?.[1])) refuse('service-home-mismatch');
    }
}
function safeToRestore() {
    // A new owner must not be masked by starting a replacement supervisor.
    if (snapshot(pidPath).s) fail('restore-owner-conflict');
    ensureNoWriters();
}
function linuxManagerHome() {
    const environment = systemctl(['show-environment']);
    const overrides = environment.split('\n').filter(line => line.startsWith('PASEO_HOME='));
    if (overrides.length > 1 || !daemonHomeMatches(overrides[0]?.slice('PASEO_HOME='.length))) refuse('service-home-mismatch');
}
function linuxOwner(info, rows) {
    if (!headless || /microsoft/i.test(os.release())) refuse('headless-control-not-authorized');
    const file = path.join(home, '.config/systemd/user', service);
    const unit = snapshot(file), wrapper = checkWrapper();
    // Disallow user edits, extra directives, drop-ins and a stale loaded definition.
    const expected = `# ${marker}\n[Unit]\nDescription=Paseo headless daemon\nDocumentation=https://www.getpaseo.com/\n\n[Service]\nType=simple\nExecStart=${logicalHome}/.local/bin/paseo-daemon-start\nWorkingDirectory=${logicalHome}\nEnvironment=HOME=${logicalHome}\nEnvironment=PATH=`;
    const tail = '\nRestart=on-failure\nRestartSec=5\n\n[Install]\nWantedBy=default.target\n';
    if (!unit.text?.startsWith(expected) || !unit.text.endsWith(tail) || unit.text.slice(expected.length, -tail.length).includes('\n')) refuse('unmanaged-service');
    const state = serviceState();
    if (state.Id !== service || state.LoadState !== 'loaded' || state.ActiveState !== 'active' || state.SubState !== 'running' ||
        state.FragmentPath !== path.join(logicalHome, '.config/systemd/user', service) || state.DropInPaths !== '' ||
        state.NeedDaemonReload !== 'no' || state.EnvironmentFiles !== '' || !['', os.userInfo().username].includes(state.User) ||
        state.KillMode !== 'control-group' || !state.ControlGroup?.startsWith(`/user.slice/user-${uid}.slice/`) ||
        !state.ExecStart?.includes(`path=${logicalHome}/.local/bin/paseo-daemon-start ;`) ||
        !state.Environment?.includes(`HOME=${logicalHome}`)) refuse('service-state-unverified');
    linuxManagerHome();
    const pid = Number(state.MainPID);
    if (!Number.isInteger(pid) || pid <= 1) refuse('service-pid-unverified');
    verifyOwnerProcess(info, pid, state.ControlGroup, rows);
    return {pid, group: state.ControlGroup, file, unit, wrapper,
        stop() { systemctl(['stop', service]); },
        stopped() { const s = serviceState(); if (s.ActiveState !== 'inactive' || s.SubState !== 'dead' || s.MainPID !== '0') refuse('stopped-state-unverified'); },
        start() {
            const before = serviceState();
            if (before.ActiveState === 'active' && before.SubState === 'running' && Number(before.MainPID) === pid) return;
            safeToRestore(); linuxManagerHome(); systemctl(['start', service]);
            const s = serviceState();
            if (s.ActiveState !== 'active' || s.SubState !== 'running' || Number(s.MainPID) <= 1) fail('restore-unverified');
        }};
}
function launchList() {
    const text = run('sudo', ['-n', 'launchctl', 'list']);
    const rows = text.trim().split('\n');
    if (!/^PID\s+Status\s+Label$/.test(rows.shift())) refuse('launchd-state-unverified');
    return rows.map(line => { const m = line.match(/^(\d+|-)\s+(-?\d+)\s+(\S+)$/); if (!m) refuse('launchd-state-unverified'); return {pid: m[1] === '-' ? 0 : Number(m[1]), label: m[3]}; });
}
function macManagerHome() {
    const domain = run('sudo', ['-n', 'launchctl', 'print', 'system']);
    const environment = domain.match(/\benvironment = \{([^}]*?)\}/);
    if (!environment) refuse('service-environment-unverified');
    const overrides = environment[1].split('\n').map(line => line.trim()).filter(line => /^PASEO_HOME\s+=>/.test(line));
    if (overrides.length > 1 || !daemonHomeMatches(overrides[0]?.replace(/^PASEO_HOME\s+=>\s*/, ''))) refuse('service-home-mismatch');
}
function macOwner(info, rows) {
    if (!headless || process.env.PASEO_MACOS_HEADLESS_CANARY !== '1') refuse('headless-control-not-authorized');
    const file = `/Library/LaunchDaemons/${label}.plist`;
    const unit = snapshot(file), wrapper = checkWrapper();
    if (!['/', '/Library', '/Library/LaunchDaemons'].every(rootDirectory) || !unit.s || unit.s.uid !== 0 ||
        unit.s.mode & 0o022 || !unit.text.includes(`<!-- ${marker} -->`)) refuse('unmanaged-service');
    let plist;
    try { plist = JSON.parse(run('plutil', ['-convert', 'json', '-o', '-', file])); } catch (error) { if (error instanceof Refusal) throw error; refuse('invalid-service-state'); }
    if (plist.Label !== label || plist.UserName !== os.userInfo().username || plist.WorkingDirectory !== logicalHome ||
        JSON.stringify(plist.ProgramArguments) !== JSON.stringify([path.join(logicalHome, '.local/bin/paseo-daemon-start')]) ||
        plist.EnvironmentVariables?.HOME !== logicalHome || typeof plist.EnvironmentVariables?.PATH !== 'string' ||
        Object.keys(plist.EnvironmentVariables).some(key => !['HOME', 'PATH'].includes(key)) ||
        plist.RunAtLoad !== true || plist.KeepAlive !== true ||
        Object.keys(plist).some(key => !['Label', 'UserName', 'ProgramArguments', 'WorkingDirectory', 'EnvironmentVariables', 'RunAtLoad', 'KeepAlive'].includes(key))) refuse('service-state-unverified');
    const entry = launchList().find(p => p.label === label);
    if (!entry || entry.pid <= 1) refuse('service-pid-unverified');
    const printed = run('sudo', ['-n', 'launchctl', 'print', `system/${label}`]);
    if (!printed.includes(`path = ${file}\n`) || !printed.includes(`program = ${logicalHome}/.local/bin/paseo-daemon-start\n`)) refuse('service-state-unverified');
    verifyOwnerProcess(info, entry.pid, null, rows);
    macManagerHome();
    return {pid: entry.pid, group: null, file, unit, wrapper,
        stop() { run('sudo', ['-n', 'launchctl', 'bootout', `system/${label}`]); },
        stopped() { if (launchList().some(p => p.label === label)) refuse('stopped-state-unverified'); },
        start() {
            const loaded = launchList().find(p => p.label === label);
            if (loaded?.pid === entry.pid) return;
            if (loaded) fail('restore-owner-conflict');
            safeToRestore(); macManagerHome(); run('sudo', ['-n', 'launchctl', 'bootstrap', 'system', file]);
            if (!launchList().some(p => p.label === label && p.pid > 1)) fail('restore-unverified');
        }};
}
function reservePid() {
    // Never unlink a stale/foreign native lock: its owner may be racing startup.
    if (snapshot(pidPath).s) refuse('pid-lock-present');
    const text = JSON.stringify({pid: process.pid, startedAt: new Date().toISOString(), hostname: os.hostname(), uid, listen: null, heartbeat: true});
    const fd = fs.openSync(pidPath, 'wx', 0o600);
    heldLock = {fd, text, initial: fs.fstatSync(fd)};
    fs.writeFileSync(fd, text);
    fs.fsyncSync(fd);
    heldLock.s = fs.fstatSync(fd);
}
function releasePid() {
    if (!heldLock) return;
    const held = heldLock;
    heldLock = null;
    try {
        const current = snapshot(pidPath);
        // A failed initial write still owns this inode; remove only our partial lock.
        if (!current.s || held.initial.dev !== current.s.dev || held.initial.ino !== current.s.ino ||
            !same(fs.fstatSync(held.fd), current.s) || (held.s && current.text !== held.text)) fail('pid-lock-changed');
        fs.unlinkSync(pidPath);
    } finally { fs.closeSync(held.fd); }
}
function secureTemporary(file, existing) {
    if (platform !== 'win32') return;
    const command = `$ErrorActionPreference='Stop';
if ($env:PASEO_MUSE_EXISTING -eq '1') { $acl = Get-Acl -LiteralPath $env:PASEO_MUSE_CONFIG }
else {
    $sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
    $acl = New-Object System.Security.AccessControl.FileSecurity
    $acl.SetOwner($sid)
    $acl.SetAccessRuleProtection($true, $false)
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($sid, 'FullControl', 'Allow')))
    $system = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-18')
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($system, 'FullControl', 'Allow')))
}
Set-Acl -LiteralPath $env:PASEO_MUSE_TEMP -AclObject $acl`;
    run('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', command], false,
        {PASEO_MUSE_EXISTING: existing ? '1' : '0', PASEO_MUSE_CONFIG: configPath, PASEO_MUSE_TEMP: file});
}
function lockUnchanged() {
    const current = snapshot(pidPath);
    if (!heldLock || !same(heldLock.s, current.s) || current.text !== heldLock.text) fail('pid-lock-changed');
}
async function main() {
    logicalHome = path.resolve(os.homedir());
    // HOME is trusted only for the effective account, not an arbitrary profile link.
    const accountHome = path.resolve(os.userInfo().homedir);
    if (fs.realpathSync(logicalHome) !== fs.realpathSync(accountHome)) refuse('account-home-mismatch');
    home = fs.realpathSync(logicalHome);
    checkedPath(logicalHome, true);
    checkedPath(home, true);
    accountRoots = [...new Set([home, logicalHome])];
    if (platform === 'linux' && home.startsWith('/var/home/') && trustedSystemHomeAlias()) {
        accountRoots.push(path.join('/home', path.relative('/var/home', home)));
    }
    const requested = process.env.PASEO_HOME;
    if (requested !== undefined && (requested === '' || !path.isAbsolute(requested))) refuse('invalid-home-override');
    paseoHome = requested === undefined ? path.join(home, '.paseo') : accountPath(requested);
    if (!paseoHome) refuse('custom-home-unverified');
    // Validate the supplied spelling too; only the trusted account aliases map.
    if (requested !== undefined) checkedPath(requested, true);
    customHome = paseoHome !== path.join(home, '.paseo');
    configPath = path.join(paseoHome, 'config.json');
    pidPath = path.join(paseoHome, 'paseo.pid');
    checkedPath(paseoHome, true);
    checkCustomHome();
    if (customHome) {
        // The later legacy service installer assumes the default home. It must
        // not undo this transaction's verified custom-home owner selection.
        console.log('PASEO_MUSE_DEFER_DAEMON_SETUP=1');
        console.log('Paseo Muse custom home: later managed-daemon setup is skipped. Keep this owner\'s launch environment and update that owner separately.');
    }
    const initial = snapshot(configPath);
    if (merge(initial) === null && !refresh) { console.log('PASEO_MUSE_UNCHANGED'); return; }
    if (process.env.PASEO_AGENT_ID) refuse('self-hosted-setup');
    const existing = pidInfo();
    const rows = inventory();
    verifySetupAncestry(rows);
    let owner = null;
    if (existing.info) {
        if (!live(existing.info.pid)) refuse('stale-pid-lock');
        if (existing.info.desktopManaged) refuse('desktop-owned');
        owner = platform === 'linux' ? linuxOwner(existing.info, rows) : platform === 'darwin' ? macOwner(existing.info, rows) : null;
        if (!owner) refuse('unknown-owner');
        if (!same(existing.snap.s, snapshot(pidPath).s) || !same(owner.unit.s, snapshot(owner.file).s) ||
            !same(owner.wrapper.snap.s, snapshot(owner.wrapper.file).s)) refuse('ownership-changed');
        console.log('PASEO_MUSE_RESTARTING');
        await checkpoint();
        // Arm restoration BEFORE stop: a timeout/failure can still have stopped it.
        restore = owner;
        owner.stop();
        await checkpoint();
        owner.stopped();
    } else if (candidates(rows).length) refuse('unknown-writer');
    ensureNoWriters(owner);
    checkedPath(paseoHome, true);
    fs.mkdirSync(paseoHome, {recursive: true, mode: 0o700});
    reservePid();
    await checkpoint();
    ensureNoWriters(owner);
    if (owner) owner.stopped();
    // Re-read AFTER shutdown. Daemon shutdown and concurrent unrelated updates win.
    const before = snapshot(configPath);
    const next = merge(before);
    if (next !== null) {
        if (Buffer.byteLength(next, 'utf8') > maxSnapshotBytes) fail('metadata-too-large');
        temporary = path.join(paseoHome, `.config.setup-muse-${randomUUID()}.tmp`);
        const fd = fs.openSync(temporary, 'wx', before.s ? before.s.mode & 0o777 : 0o600);
        try {
            if (before.s && platform !== 'win32') {
                if (fs.fstatSync(fd).gid !== before.s.gid) fs.fchownSync(fd, before.s.uid, before.s.gid);
                fs.fchmodSync(fd, before.s.mode & 0o777);
            }
            secureTemporary(temporary, !!before.s);
            fs.writeFileSync(fd, next); fs.fsyncSync(fd);
        } finally { fs.closeSync(fd); }
        const pending = snapshot(temporary);
        await checkpoint();
        ensureNoWriters(owner);
        if (owner) owner.stopped();
        lockUnchanged();
        const current = snapshot(configPath);
        if (!same(before.s, current.s) || before.text !== current.text) fail('concurrent-config-change');
        const ready = snapshot(temporary);
        if (!same(pending.s, ready.s) || ready.text !== next) fail('temporary-file-changed');
        fs.renameSync(temporary, configPath);
        temporary = null;
        console.log('PASEO_MUSE_UPDATED');
    } else console.log('PASEO_MUSE_UNCHANGED');
}
(async () => {
    let failure = null;
    try { await main(); } catch (error) { failure = error; }
    finally {
        try { if (temporary) fs.unlinkSync(temporary); } catch { failure = new Refusal('temporary-cleanup-failed', true); }
        try { releasePid(); } catch { failure = new Refusal('pid-release-failed', true); }
        if (restore) {
            try {
                if (!same(restore.unit.s, snapshot(restore.file).s) || !same(restore.wrapper.snap.s, snapshot(restore.wrapper.file).s)) fail('service-changed-before-restore');
                restore.start();
                console.log('PASEO_MUSE_RESTORED');
            }
            catch { failure = new Refusal('service-restore-failed', true); }
        }
    }
    if (failure) {
        const controlled = failure instanceof Refusal;
        const failed = !controlled || failure.failed;
        console.log(`PASEO_MUSE_DEFER_DAEMON_SETUP=1`);
        console.log(`Paseo Muse ${failed ? 'failed' : 'deferred'}: ${controlled ? failure.code : 'operation-failed'}.`);
        if (controlled && failure.code === 'stale-pid-lock') console.log('Paseo Muse recovery: inspect the stale paseo.pid privately; remove it manually only after every local owner is confirmed stopped.');
        if (controlled && ['custom-home-unverified', 'custom-home-permissions-unverified', 'invalid-home-override'].includes(failure.code)) console.log('Paseo Muse home: PASEO_HOME must be unset or an absolute directory below the account HOME, not HOME itself. Custom directories must already exist, be private and account-owned, and contain no linked paths.');
        console.log('Quit Paseo Desktop or stop the owning local daemon, then rerun setup from a terminal outside Paseo. Keep Desktop closed during setup. If Go authentication changed, restart that owner to refresh its model catalog.');
        // Deferred lifecycle cases are warnings, not a claim that a profile was saved.
        process.exitCode = failed ? 1 : 0;
    }
})();
// END PASEO MUSE PROFILE
PASEO_MUSE_PROFILE_JS
    ) || status=$?
    while IFS= read -r line; do
        case "${line}" in
            PASEO_MUSE_DEFER_DAEMON_SETUP=1) PASEO_MUSE_DEFER_DAEMON_SETUP=1 ;;
            PASEO_MUSE_UPDATED) print_success "Paseo Muse managed profile synchronized." ;;
            PASEO_MUSE_UNCHANGED) print_debug "Paseo Muse managed profile is unchanged." ;;
            PASEO_MUSE_RESTARTING) print_warning "Restarting the setup-managed local Paseo daemon to refresh Muse. Active agents may be interrupted." ;;
            PASEO_MUSE_RESTORED) print_debug "Paseo Muse restored the local managed service." ;;
            'Paseo Muse '*|'Quit Paseo Desktop '*) print_warning "${line}" ;;
            *) ;;
        esac
    done <<< "${result}"
    if [[ "${status}" != "0" ]]; then
        PASEO_MUSE_DEFER_DAEMON_SETUP=1
        print_warning "Paseo Muse profile setup failed; later daemon setup must be skipped. Inspect the local service privately and rerun outside Paseo."
        return 1
    fi
    return 0
}

install_paseo_plain() {
    if ! command -v node &> /dev/null; then
        print_warning "Paseo Plain deferred: install Node.js >=22.19 and rerun setup."
        return 0
    fi
    local result
    local status=0
    result=$(node --input-type=commonjs - <<'PASEO_PLAIN_SETUP_JS'
// BEGIN PASEO PLAIN INSTALLER
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { spawnSync } = require('node:child_process');
const remote = 'https://github.com/scowalt/paseo-plain.git';
const id = 'paseo-plain';
const { createHash } = require('node:crypto');
const { isDeepStrictEqual } = require('node:util');
let recovery = null;
let migrationPhase = 'preparing';
let operation = 'preflight';
class SetupFailure extends Error {}
const deferred = message => { console.log(`Paseo Plain deferred: ${message}`); };
function executable(name, packageName) {
    for (const directory of (process.env.PATH || '').split(path.delimiter)) {
        if (!path.isAbsolute(directory)) continue;
        const file = path.join(directory, name + (process.platform === 'win32' ? '.exe' : ''));
        try { fs.accessSync(file, fs.constants.X_OK); return [file]; } catch {}
        if (process.platform !== 'win32' || !packageName || !fs.existsSync(path.join(directory, `${name}.cmd`))) continue;
        for (const base of [path.join(directory, 'node_modules'), path.resolve(directory, '../install/global/node_modules')]) {
            try {
                const root = path.join(base, packageName);
                const pkg = JSON.parse(fs.readFileSync(path.join(root, 'package.json'), 'utf8'));
                const bin = typeof pkg.bin === 'string' ? pkg.bin : pkg.bin?.[name];
                if (pkg.name !== packageName || typeof bin !== 'string') continue;
                const script = path.resolve(root, bin);
                if (!script.startsWith(root + path.sep) || !fs.statSync(script).isFile()) continue;
                return [process.execPath, script];
            } catch {}
        }
    }
    return null;
}
const info = file => { try { return fs.lstatSync(file); } catch (error) { if (error.code === 'ENOENT') return null; throw error; } };
function regularPath(home, file) {
    const relative = path.relative(home, file);
    if (relative === '..' || relative.startsWith('..' + path.sep) || path.isAbsolute(relative)) throw new SetupFailure('outside-home');
    let current = home;
    for (const part of ['', ...relative.split(path.sep).filter(Boolean)]) {
        current = path.join(current, part);
        const stat = info(current);
        if (stat && (stat.isSymbolicLink() || (!stat.isFile() && !stat.isDirectory()))) throw new SetupFailure('unsafe-path');
    }
}
function tree(root, links = false) {
    const entries = [];
    let bytes = 0;
    function visit(relative) {
        const file = path.join(root, relative);
        const stat = fs.lstatSync(file);
        if (entries.length >= 20000 || (bytes += stat.size) > 256 * 1024 * 1024) throw new SetupFailure('backup-limit');
        if (stat.isSymbolicLink()) {
            const target = fs.readlinkSync(file);
            if (!links || path.isAbsolute(target) || !fs.realpathSync(file).startsWith(fs.realpathSync(root) + path.sep)) throw new SetupFailure('unsafe-link');
            entries.push([relative, 'link', target]);
        } else if (stat.isDirectory()) {
            entries.push([relative, 'directory']);
            for (const name of fs.readdirSync(file).sort()) visit(path.join(relative, name));
        } else if (stat.isFile()) {
            entries.push([relative, 'file', createHash('sha256').update(fs.readFileSync(file)).digest('hex'), Boolean(stat.mode & 0o111)]);
        } else throw new SetupFailure('unsafe-file');
    }
    if (info(root)) visit('');
    return entries;
}
function copyTree(source, destination, links = false) {
    const before = tree(source, links);
    for (const [relative, kind, value, executable] of before) {
        const target = path.join(destination, relative);
        if (kind === 'directory') {
            if (relative === '') privateRecoveryDirectory(target);
            else fs.mkdirSync(target, {mode: 0o700});
        }
        else if (kind === 'link') fs.symlinkSync(value, target);
        else {
            fs.copyFileSync(path.join(source, relative), target, fs.constants.COPYFILE_EXCL);
            fs.chmodSync(target, executable ? 0o700 : 0o600);
            const fd = fs.openSync(target, 'r+');
            try { fs.fsyncSync(fd); } finally { fs.closeSync(fd); }
        }
    }
    if (process.platform !== 'win32') {
        for (const [relative, kind] of [...before].reverse()) {
            if (kind !== 'directory') continue;
            const fd = fs.openSync(path.join(destination, relative), 'r');
            try { fs.fsyncSync(fd); } finally { fs.closeSync(fd); }
        }
    }
    if (!isDeepStrictEqual(before, tree(source, links)) || !isDeepStrictEqual(before, tree(destination, links))) throw new SetupFailure('backup-changed');
    return before;
}
function privateRecoveryDirectory(directory) {
    fs.mkdirSync(directory, {mode: 0o700});
    if (process.platform !== 'win32') return;
    const script = `$ErrorActionPreference = 'Stop'
$env:PSModulePath = "$PSHOME\\Modules"
$owner = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
$acl = [System.Security.AccessControl.DirectorySecurity]::new()
$acl.SetOwner($owner)
$acl.SetAccessRuleProtection($true, $false)
foreach ($sid in @($owner, [System.Security.Principal.SecurityIdentifier]::new('S-1-5-18'), [System.Security.Principal.SecurityIdentifier]::new('S-1-5-32-544'))) {
    $acl.AddAccessRule([System.Security.AccessControl.FileSystemAccessRule]::new($sid, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow'))
}
Set-Acl -LiteralPath $env:PASEO_PLAIN_RECOVERY_DIRECTORY -AclObject $acl`;
    const result = spawnSync(path.join(process.env.SystemRoot || 'C:\\Windows', 'System32/WindowsPowerShell/v1.0/powershell.exe'),
        ['-NoProfile', '-NonInteractive', '-EncodedCommand', Buffer.from(script, 'utf16le').toString('base64')], {
            env: {...process.env, PASEO_PLAIN_RECOVERY_DIRECTORY: directory}, shell: false, windowsHide: true,
            timeout: 15000, maxBuffer: 16384, stdio: ['ignore', 'pipe', 'pipe'],
        });
    if (result.error || result.status !== 0) throw new SetupFailure('private-backup-unavailable');
}
function migrationJournal(phase) {
    migrationPhase = phase;
    operation = `release migration ${phase}`;
    const pending = path.join(recovery, 'state.next');
    const fd = fs.openSync(pending, 'wx', 0o600);
    try { fs.writeFileSync(fd, JSON.stringify({version: 1, from: 'release', to: 'main', phase}) + '\n'); fs.fsyncSync(fd); }
    finally { fs.closeSync(fd); }
    fs.renameSync(pending, path.join(recovery, 'state.json'));
    if (process.platform !== 'win32') {
        const directory = fs.openSync(recovery, 'r');
        try { fs.fsyncSync(directory); } finally { fs.closeSync(directory); }
    }
}
function migrateRelease({home, existing, config, args, run, directory}) {
    operation = 'release migration validation';
    const sourcesFile = path.join(home, 'plugins/sources.json');
    const native = path.join(home, 'plugin-settings', id);
    for (const file of [home, sourcesFile, native, directory]) regularPath(home, file);
    const record = JSON.parse(fs.readFileSync(sourcesFile, 'utf8'))[id];
    const source = config.plugins?.[id];
    const root = path.join(home, 'plugins', id);
    if (existing.enabled !== true || existing.status !== 'running' || source?.enabled === false ||
        record?.remote !== remote || record.requestedRef !== 'release' || record.trackingBranch !== 'release' ||
        record.pluginPath !== '.' || !/^[0-9a-f]{40,64}$/.test(record.commit) || record.commit !== existing.commit ||
        typeof record.checkoutRoot !== 'string' || path.dirname(path.dirname(record.checkoutRoot)) !== root ||
        path.basename(record.checkoutRoot) !== 'checkout' || source?.source !== 'directory' ||
        source.path !== existing.path || source.path !== record.checkoutRoot) throw new SetupFailure('unverified-release-source');
    regularPath(home, record.checkoutRoot);
    if (!info(record.checkoutRoot)?.isDirectory() || (info(native) && !info(native).isDirectory())) throw new SetupFailure('invalid-migration-directory');
    const parent = path.join(home, 'setup-recovery');
    regularPath(home, parent);
    if (!info(parent)) fs.mkdirSync(parent, {mode: 0o700});
    recovery = path.join(parent, 'paseo-plain-release-to-main');
    privateRecoveryDirectory(recovery);
    migrationJournal('preparing');
    fs.writeFileSync(path.join(recovery, 'RECOVERY.md'),
        '# Paseo Plain migration recovery\n\nDo not rerun setup or remove another installation until any timed-out Paseo operation has finished.\n' +
        'Inspect the local plugin catalog using the same explicit --host target. Keep these recovery files private.\n' +
        'If the plugin is absent, the checkout directory is a local recovery source for paseo plugin install with --id paseo-plain.\n' +
        'A recovered directory installation will not receive automatic Git updates. Never replace an occupied ID blindly.\n' +
        'plugin-settings contains the removed Paseo-owned settings. Restore it only to an absent destination before activation.\n' +
        'plugin-data is a safety copy, not an instruction to overwrite newer live preferences or cached rewrites.\n' +
        'registration.json and source.json describe only the former plugin. Do not overwrite daemon config.json or sources.json.\n' +
        'Never move this recovery directory while it is the installed directory source.\n' +
        'If the installed path is outside this directory, no operation is pending, and source/state/settings are verified, move this recovery directory aside before retrying setup.\n' +
        'See https://github.com/scowalt/machine-setup-scripts#paseo-plain-migration-recovery for the recovery procedure.\n', {flag: 'wx', mode: 0o600});
    fs.writeFileSync(path.join(recovery, 'source.json'), JSON.stringify(record), {flag: 'wx', mode: 0o600});
    fs.writeFileSync(path.join(recovery, 'registration.json'), JSON.stringify(source), {flag: 'wx', mode: 0o600});
    const checkoutSnapshot = copyTree(record.checkoutRoot, path.join(recovery, 'checkout'), true);
    const dataSnapshot = copyTree(directory, path.join(recovery, 'plugin-data'));
    const nativeSnapshot = copyTree(native, path.join(recovery, 'plugin-settings'));
    const currentConfig = () => JSON.parse(fs.readFileSync(path.join(home, 'config.json'), 'utf8'));
    const otherConfig = value => { const copy = {...value, plugins: {...value.plugins}}; delete copy.plugins[id]; return copy; };
    if (!isDeepStrictEqual(config, currentConfig()) ||
        !isDeepStrictEqual(record, JSON.parse(fs.readFileSync(sourcesFile, 'utf8'))[id]) ||
        !isDeepStrictEqual(checkoutSnapshot, tree(record.checkoutRoot, true)) ||
        !isDeepStrictEqual(dataSnapshot, tree(directory)) || !isDeepStrictEqual(nativeSnapshot, tree(native))) throw new SetupFailure('migration-state-changed');
    migrationJournal('removing');
    run([...args, 'remove', id, '--json'], 180000);
    const remaining = run([...args, 'ls', '--json']);
    if (!Array.isArray(remaining) || remaining.some(item => item.id === id) || currentConfig().plugins?.[id] ||
        !isDeepStrictEqual(otherConfig(config), otherConfig(currentConfig())) ||
        !isDeepStrictEqual(dataSnapshot, tree(directory))) throw new SetupFailure('removal-not-confirmed');
    migrationJournal('restoring');
    regularPath(home, native);
    if (info(native)) throw new SetupFailure('native-settings-reappeared');
    if (nativeSnapshot.length) {
        if (!info(path.dirname(native))) fs.mkdirSync(path.dirname(native), {mode: 0o700});
        copyTree(path.join(recovery, 'plugin-settings'), native);
    }
    migrationJournal('adding');
    run([...args, 'add', remote, '--ref', 'main', '--id', id, '--json'], 180000);
    migrationJournal('verifying');
    const after = run([...args, 'ls', '--json']);
    if (!Array.isArray(after) || !after.some(item => item.id === id && item.source === 'git' && item.remote === remote &&
        item.ref === 'main' && item.enabled === true && item.status === 'running') ||
        !isDeepStrictEqual(otherConfig(config), otherConfig(currentConfig())) ||
        !isDeepStrictEqual(dataSnapshot, tree(directory)) || !isDeepStrictEqual(nativeSnapshot, tree(native))) throw new SetupFailure('migration-not-verified');
    migrationJournal('complete');
    console.log('Paseo Plain migrated from release to main; preferences and cache preserved. Private recovery files were retained.');
}
function main() {
    const [major, minor] = process.versions.node.split('.').map(Number);
    if (major < 22 || (major === 22 && minor < 19)) return deferred('Node.js >=22.19 is required.');
    const paseo = executable('paseo', '@getpaseo/cli');
    if (!paseo || !executable('pi', '@earendil-works/pi-coding-agent')) return deferred('install Paseo and Pi, then rerun setup.');
    const home = path.resolve(process.env.PASEO_HOME || path.join(os.homedir(), '.paseo'));
    const configFile = path.join(home, 'config.json');
    if (!fs.existsSync(configFile)) return deferred('start and configure the local Paseo daemon, then rerun setup.');
    const config = JSON.parse(fs.readFileSync(configFile, 'utf8'));
    if (config.pluginsEnabled !== true) return deferred('enable trusted plugins in Paseo Settings > Plugins, then rerun setup.');
    const localTarget = value => typeof value === 'string' && /^(127\.0\.0\.1|localhost|\[::1\]):[1-9][0-9]{0,4}$/.test(value) && Number(value.split(':').pop()) <= 65535;
    if (config.daemon?.listen !== undefined && !localTarget(config.daemon.listen)) return deferred('a loopback TCP daemon endpoint is required; no remote host was changed.');
    // Paseo status prefers the saved PID endpoint over daemon.listen and probes it.
    const pidFile = path.join(home, 'paseo.pid');
    if (fs.existsSync(pidFile)) {
        const pidInfo = JSON.parse(fs.readFileSync(pidFile, 'utf8'));
        const target = pidInfo?.listen ?? pidInfo?.sockPath;
        if (target !== undefined && !localTarget(target)) return deferred('the saved daemon endpoint is not loopback TCP; inspect local Paseo configuration.');
    }
    const run = (args, timeout = 20000) => {
        operation = args[0] === 'daemon' ? 'daemon status' : `plugin ${args[3]}`;
        // --home is not a global Paseo option. Scope every command via its environment.
        const result = spawnSync(paseo[0], [...paseo.slice(1), ...args], {
            env: {...process.env, PASEO_HOME: home},
            cwd: os.homedir(), encoding: 'utf8', timeout, maxBuffer: 2 * 1024 * 1024,
            stdio: ['ignore', 'pipe', 'pipe'], shell: false,
        });
        if (result.error) throw new SetupFailure(result.error.code === 'ETIMEDOUT' ? 'timeout' : 'spawn-failed');
        if (result.status !== 0) throw new SetupFailure(Number.isInteger(result.status) ? `exit-${result.status}` : 'terminated');
        try { return JSON.parse(result.stdout); }
        catch { throw new SetupFailure('invalid-response-json'); }
    };
    const status = run(['daemon', 'status', '--json']);
    if (status.localDaemon !== 'running' || status.connectedDaemon !== 'reachable' ||
        typeof status.home !== 'string' || fs.realpathSync(status.home) !== fs.realpathSync(home) || !localTarget(status.listen)) {
        return deferred('the configured local daemon is not reachable; start it and rerun setup.');
    }
    if (![status.cliVersion, status.daemonVersion].every(v => typeof v === 'string' && /^0\.8\.\d+(?:[-+][\w.-]+)?$/.test(v))) {
        return deferred('Paseo CLI and daemon 0.8.x are required; setup does not change release channels.');
    }
    const args = ['--host', status.listen, 'plugin'];
    const catalog = run([...args, 'ls', '--json']);
    if (!Array.isArray(catalog)) throw new SetupFailure('invalid-catalog');
    const matches = catalog.filter(item => item.id === id);
    if (matches.length > 1) throw new SetupFailure('duplicate-id');
    const existing = matches[0];
    if (existing?.enabled === false || config.plugins?.[id]?.enabled === false) return deferred('the saved disabled state was preserved.');
    if (existing && (existing.source !== 'git' || existing.remote !== remote || !['main', 'release'].includes(existing.ref))) {
        const reason = existing.source === 'directory' ? 'directory-source' : existing.source !== 'git' ? 'non-git-source' :
            existing.remote !== remote ? 'repository-mismatch' : 'custom-or-pinned-ref';
        return deferred(`${reason}. Setup manages only the canonical Git repository on main or its release migration. ` +
            'The existing installation was left unchanged. Review the paseo-plain source in Paseo Settings > Plugins before planning a migration.');
    }
    if (!existing && config.plugins?.[id]) return deferred('the configured plugin is absent from the catalog; inspect Paseo before retrying.');
    const recoveryPath = path.join(home, 'setup-recovery/paseo-plain-release-to-main');
    regularPath(home, recoveryPath);
    if (info(recoveryPath)) {
        recovery = recoveryPath;
        migrationPhase = 'previous attempt';
        regularPath(home, path.join(recovery, 'state.json'));
        const saved = JSON.parse(fs.readFileSync(path.join(recovery, 'state.json'), 'utf8'));
        if (saved.version !== 1 || saved.from !== 'release' || saved.to !== 'main' || saved.phase !== 'complete' || existing?.ref === 'release') {
            throw new SetupFailure('migration-needs-review');
        }
        recovery = null;
    }
    const directory = path.join(home, 'plugin-data', id);
    for (const folder of [path.join(home, 'plugin-data'), directory]) {
        if (fs.existsSync(folder) && (fs.lstatSync(folder).isSymbolicLink() || !fs.statSync(folder).isDirectory())) {
            return deferred('plugin storage must use regular directories.');
        }
    }
    const settings = path.join(directory, 'configuration.json');
    if (fs.existsSync(settings)) {
        if (!fs.lstatSync(settings).isFile() || fs.lstatSync(settings).isSymbolicLink()) return deferred('settings must be a regular file.');
        const saved = JSON.parse(fs.readFileSync(settings, 'utf8'));
        if (!saved.values || typeof saved.values !== 'object' || !Number.isInteger(saved.revision)) throw new SetupFailure('invalid-settings');
    } else if (!existing) {
        fs.mkdirSync(directory, {recursive: true, mode: 0o700});
        // Defaults are filled by the plugin schema. Never overwrite an existing preference file.
        fs.writeFileSync(settings, JSON.stringify({values: {enabled: true}, revision: 0, error: null}), {flag: 'wx', mode: 0o600});
    }
    if (existing?.ref === 'release') return migrateRelease({home, existing, config, args, run, directory});
    run(existing ? [...args, 'update', id, '--json'] : [...args, 'add', remote, '--ref', 'main', '--id', id, '--json'], 180000);
    const after = run([...args, 'ls', '--json']);
    if (!Array.isArray(after) || !after.some(item => item.id === id && item.status === 'running' && item.enabled === true && item.source === 'git' && item.remote === remote && item.ref === 'main')) {
        throw new SetupFailure('plugin-not-running');
    }
    console.log(`Paseo Plain ${existing ? 'checked for updates' : 'installed'}; saved preferences preserved. Rewrites require an explicit request and an existing Pi login.`);
}
try { main(); } catch (error) {
    // Only controlled labels/codes are logged, never stderr, JSON values, or paths from exceptions.
    const reason = error instanceof SetupFailure ? error.message : error instanceof SyntaxError ? 'invalid-json' :
        ['EACCES', 'EPERM', 'ENOENT', 'EEXIST', 'ENOSPC', 'EROFS'].includes(error?.code) ? error.code : 'unexpected-error';
    console.log(`Paseo Plain failure: ${operation}: ${reason}.`);
    if (recovery) console.log(`Paseo Plain migration stopped (${migrationPhase}). Do not retry until reviewed. Private recovery location: ${JSON.stringify(recovery)}. See RECOVERY.md and the setup README.`);
    console.log('Paseo Plain setup could not finish. Inspect local plugin status before retrying. Setup did not reset rewrite preferences.');
    process.exitCode = 1;
}
// END PASEO PLAIN INSTALLER
PASEO_PLAIN_SETUP_JS
    ) || status=$?
    if [[ "${status}" -ne 0 ]]; then
        print_warning "${result}"
        return 1
    elif [[ "${result}" == "Paseo Plain deferred:"* ]]; then
        print_warning "${result}"
    else
        print_success "${result}"
    fi
}

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

# Pi needs Node >=22.19 and fs.globSync; the shared skills CLI needs >=22.20.
pi_node_runtime_ready() {
    command -v node &> /dev/null || return 1
    node -e 'const [major, minor] = process.versions.node.split(".").map(Number); process.exit((major > 22 || (major === 22 && minor >= 19)) && typeof require("node:fs").globSync === "function" ? 0 : 1)' >/dev/null 2>&1
}

shared_node_runtime_ready() {
    local _node="${1:-node}"
    "${_node}" -e 'const [major, minor] = process.versions.node.split(".").map(Number); process.exit((major > 22 || (major === 22 && minor >= 20)) && typeof require("node:fs").globSync === "function" ? 0 : 1)' >/dev/null 2>&1
}

# Only select releases with official binaries. Never fall back to a source build.
shared_node_fallback() {
    local _os _arch _bits
    _os=$(uname -s) || return 1
    _arch=$(uname -m) || return 1
    case "${_os}:${_arch}" in
        Linux:armv7l|Linux:armv8l) printf '%s\n' 'node@22' ;;
        Linux:aarch64|Linux:arm64)
            _bits=$(getconf LONG_BIT) || return 1
            if [[ "${_bits}" == "32" ]]; then
                printf '%s\n' 'node@22'
            else
                printf '%s\n' 'node@24'
            fi
            ;;
        Linux:x86_64|Darwin:x86_64|Darwin:arm64) printf '%s\n' 'node@24' ;;
        *) return 1 ;;
    esac
}

# Test the normal chezmoi-owned fish activation, not setup's inherited runtime PATH.
# An optional argument also verifies the canonical Pi command after installation.
verify_shared_node_shell() {
    local _fish="" _variable
    _fish=$(command -v fish) || return 1
    (
        cd "${HOME}" || exit 1
        for _variable in "${!__MISE_@}" "${!FNM_@}" "${!MISE_@}"; do
            case "${_variable}" in
                __MISE_*|FNM_*|MISE_SHELL|MISE_*_VERSION|MISE_TOOL_OPTS__NODE) unset "${_variable}" ;;
                *) ;;
            esac
        done
        unset NODE_PATH NODE_OPTIONS BASH_ENV
        # Fish, not Bash, expands $argv in this probe.
        # shellcheck disable=SC2016
        env PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" MISE_AUTO_INSTALL=false "${_fish}" -l -c '
            type -q mise; or exit 1
            set -l expected_node (mise which -C "$HOME" node); or exit 1
            node -e '\''const fs = require("node:fs"); const [major, minor] = process.versions.node.split(".").map(Number); process.exit((major > 22 || (major === 22 && minor >= 20)) && typeof fs.globSync === "function" && fs.realpathSync(process.execPath) === fs.realpathSync(process.argv[1]) ? 0 : 1)'\'' "$expected_node"; or exit 1
            npm --version >/dev/null; or exit 1
            if test (count $argv) -gt 0
                test (command -s pi) = "$argv[1]"; or exit 1
                pi --version >/dev/null; or exit 1
            end
        ' "$@" < /dev/null
    ) >/dev/null 2>&1
}

# A compatible inherited Node is not evidence of a durable shared mise selection.
ensure_shared_node_runtime() {
    local _inventory="" _count="" _install_path="" _version="" _runtime="" _mise_env="" _attempt
    export PATH="${HOME}/.local/bin:${HOME}/.mise/bin:${PATH}"
    if ! command -v mise &> /dev/null || ! command -v jq &> /dev/null; then
        print_warning "mise and jq are required to verify the shared Node runtime."
        return 1
    fi

    # Query outside HOME: --global filters active sources, so a HOME override can
    # otherwise hide a valid global default. Activation below still honors HOME.
    for _attempt in 1 2; do
        if ! _inventory=$(MISE_AUTO_INSTALL=false mise ls -C / --global --json node < /dev/null) ||
            ! _inventory=$(jq -ce 'if type == "array" then . elif type == "object" then (.node // []) else error("Invalid mise inventory") end' <<< "${_inventory}"); then
            print_warning "Cannot read the global mise Node selection; leaving Pi unchanged."
            return 1
        fi
        _count=$(jq -r 'length' <<< "${_inventory}") || return 1
        if [[ "${_count}" -gt 1 ]]; then
            print_warning "Multiple global Node versions are configured; select one compatible default before rerunning setup."
            return 1
        fi
        _install_path=$(jq -r '.[0].install_path // empty' <<< "${_inventory}") || return 1
        if [[ -n "${_install_path}" ]] && shared_node_runtime_ready "${_install_path}/bin/node"; then
            break
        fi
        if [[ "${_attempt}" -eq 2 ]]; then
            print_warning "The global mise Node runtime is still unavailable or incompatible; leaving Pi unchanged."
            return 1
        fi
        if ! _runtime=$(shared_node_fallback); then
            print_warning "No supported prebuilt Node runtime for this platform; leaving Pi unchanged."
            return 1
        fi
        # Preserve an absent compatible selection when this platform has binaries.
        # ARMv7 has official Node 22 binaries, not Node 24+ binaries.
        _version=$(jq -r '.[0].version // empty' <<< "${_inventory}") || return 1
        if [[ -z "${_install_path}" || ! -f "${_install_path}/bin/node" ]] &&
            jq -e '.[0].version // "" | select(test("^[0-9]+(\\.[0-9]+){0,2}$")) | split(".") | map(tonumber) | .[0] > 22 or (.[0] == 22 and (length == 1 or .[1] >= 20))' <<< "${_inventory}" > /dev/null &&
            { [[ "${_runtime}" != "node@22" ]] || [[ "${_version}" == "22" || "${_version}" == 22.* ]]; }; then
            print_message "Installing the configured shared Node runtime (${_version})..."
            if ! MISE_NODE_COMPILE=false MISE_AUTO_INSTALL=false mise install -C "${HOME}" "node@${_version}" < /dev/null; then
                print_warning "Failed to install the configured Node runtime; leaving Pi unchanged."
                return 1
            fi
        else
            print_message "Selecting shared ${_runtime} for Pi and the skills CLI..."
            if ! MISE_NODE_COMPILE=false MISE_AUTO_INSTALL=false mise use -g -y -C "${HOME}" "${_runtime}" < /dev/null; then
                print_warning "Failed to install/select ${_runtime}; leaving Pi unchanged."
                return 1
            fi
        fi
    done

    # No explicit node@ argument: HOME overrides must not be hidden by setup.
    if ! _mise_env=$(MISE_AUTO_INSTALL=false mise env -C "${HOME}" -s bash < /dev/null) || ! eval "${_mise_env}"; then
        print_warning "Failed to activate the shared mise environment; leaving Pi unchanged."
        return 1
    fi
    if ! shared_node_runtime_ready || ! npm --version >/dev/null 2>&1; then
        print_warning "HOME does not select Node >=22.20 with fs.globSync and npm. Review mise overrides; leaving Pi unchanged."
        return 1
    fi
    if ! verify_shared_node_shell; then
        print_warning "A fresh fish shell cannot use the shared Node/npm runtime. Apply the chezmoi mise activation and review HOME overrides before rerunning setup."
        return 1
    fi
    print_debug "Shared Node.js $(node --version || true) is ready in setup and a fresh fish shell."
}

ensure_pi_node_runtime() {
    ensure_shared_node_runtime && pi_node_runtime_ready
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

# Pi and the skills CLI share one durable Node selection.
skills_cli_node_runtime_ready() {
    shared_node_runtime_ready
}

ensure_skills_cli_node_runtime() {
    ensure_shared_node_runtime
}

# Install/update one copied global skill for every supported AI coding harness.
install_managed_agent_skill() {
    local _repository=$1
    local _skill_name=$2
    local _display_name=$3
    shift 3
    local -a _required_files=("SKILL.md" "$@")
    local _install_output=""
    local _skill_dir=""
    local _relative_file=""
    local _skill_file=""
    local _artifact_path=""
    # Codex, Gemini CLI, and Pi discover the skills CLI's shared user copy.
    local -a _skill_dirs=(
        "${CLAUDE_CONFIG_DIR:-${HOME}/.claude}/skills/${_skill_name}"
        "${HOME}/.agents/skills/${_skill_name}"
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

    for _skill_dir in "${_skill_dirs[@]}"; do
        for _relative_file in "${_required_files[@]}"; do
            _skill_file="${_skill_dir}/${_relative_file}"
            _artifact_path=${_skill_file}
            # Reject links in the file and every directory inside the skill copy.
            while :; do
                if [[ -L "${_artifact_path}" ]]; then
                    print_warning "${_display_name} validation failed: copied artifact is a symlink at ${_artifact_path}."
                    return 1
                fi
                [[ "${_artifact_path}" == "${_skill_dir}" ]] && break
                _artifact_path=${_artifact_path%/*}
            done
            if [[ ! -f "${_skill_file}" || ! -s "${_skill_file}" ]]; then
                print_warning "${_display_name} validation failed: missing, empty, or non-regular file at ${_skill_file}."
                return 1
            fi
        done
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

# Install/update upstream PR Lens unchanged, including its default hosted uploads.
setup_pr_lens_skill() {
    install_managed_agent_skill "coldteadotai/pr-lens" "pr-lens" "PR Lens" \
        "LICENSE" "references/graph-document.md" "references/config.md" "references/example.graph.json"
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

# Native Go auth only. Success also verifies the installed catalog offline.
# Keep the embedded Node body identical in all six setup scripts.
configure_pi_opencode_go() {
    local _result="" _status=0
    local _operations='preflight|home|pi-package|pi-dependency|go-catalog|environment-file|active-profile|models-json|auth-lock|lock-dependency|auth-preflight|profile-create|lock-acquire|auth-read|auth-write|auth-cleanup|lock-release'
    local _reasons='acl-timeout|acl-unavailable|acl-unsafe|catalog-incompatible|concurrent-metadata-change|duplicate-json-key|file-changed|go-provider-overridden|invalid-credential|invalid-json|invalid-json-object|invalid-key-format|invalid-mode|invalid-providers|linked-directory|linked-or-nonregular-file|lock-compromised|lock-unavailable|lock-unverified|lock-version-unsupported|missing-directory|node-incompatible|oversized-metadata|pi-dependency-unavailable|pi-package-unavailable|unexpected-dependency|unowned-auth-file|unowned-home|unsafe-file-permissions|unsafe-json-number|unsafe-lock|unsafe-lock-dependency|unsafe-path|unsafe-profile|untrusted-directory|operation-failed|EACCES|EPERM|EROFS|ENOSPC|EDQUOT|ENOENT|ENOTDIR|EISDIR|ELOOP|EEXIST|EIO|ELOCKED|ECOMPROMISED|MODULE_NOT_FOUND|ERR_PACKAGE_PATH_NOT_EXPORTED'
    PI_OPENCODE_GO_CHANGED=0
    if ! command -v node > /dev/null 2>&1; then
        print_warning "Pi Go setup failed: shared Node runtime unavailable."
        return 1
    fi
    _result=$(env -u NODE_OPTIONS -u NODE_PATH node --input-type=commonjs - "${HOME}" "${PI_CODING_AGENT_DIR:-}" sync 2>/dev/null <<'PI_OPENCODE_GO_JS'
// BEGIN PI_OPENCODE_GO_SETUP
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const {createRequire} = require('node:module');
const {spawn} = require('node:child_process');
const crypto = require('node:crypto');
let operation = 'preflight';
class GoSetupError extends Error {
    constructor(code) { super(code); this.operation = operation; }
}
// Only controlled codes cross stdout. Never serialize an exception or a path.
const nativeErrors = new Set('EACCES EPERM EROFS ENOSPC EDQUOT ENOENT ENOTDIR EISDIR ELOOP EEXIST EIO ELOCKED ECOMPROMISED MODULE_NOT_FOUND ERR_PACKAGE_PATH_NOT_EXPORTED'.split(' '));
const failureReason = error => error instanceof GoSetupError ? error.message :
    nativeErrors.has(error?.code) ? error.code : 'operation-failed';
const fail = code => { throw new GoSetupError(code); };
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const windows = process.platform === 'win32';
const uid = windows ? null : process.getuid();
const within = (file, base) => {
    const key = value => windows ? value.toLowerCase() : value;
    return key(file) === key(base) || key(file).startsWith(key(base + path.sep));
};
function info(file) {
    try { return fs.lstatSync(file); }
    catch (error) { if (error.code === 'ENOENT') return null; throw error; }
}
function absolute(value) {
    if (!value || !path.isAbsolute(value) || value.split(/[\\/]/).some(part => part === '.' || part === '..')) fail('unsafe-path');
    return path.resolve(value);
}
function systemHomeAlias(file, stat) {
    if (process.platform !== 'linux' || file !== '/home' || stat.uid !== 0) return false;
    if (!['var/home', '/var/home'].includes(fs.readlinkSync(file))) return false;
    return ['/', '/var', '/var/home'].every(dir => {
        const entry = info(dir);
        return entry && entry.isDirectory() && !entry.isSymbolicLink() && entry.uid === 0 && !(entry.mode & 0o022);
    });
}
function directoryChain(directory, missing = false, installed = false) {
    const chain = [];
    for (let current = directory; ; current = path.dirname(current)) {
        chain.unshift(current);
        if (current === path.dirname(current)) break;
    }
    for (const current of chain) {
        const stat = info(current);
        if (!stat && missing) continue;
        if (!stat) fail('missing-directory');
        if (stat.isSymbolicLink() && systemHomeAlias(current, stat)) continue;
        if (!stat.isDirectory() || stat.isSymbolicLink()) fail('linked-directory');
        // A root-owned sticky temporary ancestor cannot replace this user's child.
        const stickyRoot = stat.uid === 0 && (stat.mode & 0o1000);
        if (!windows && (![0, uid].includes(stat.uid) || ((stat.mode & (installed ? 0o002 : 0o022)) && !stickyRoot))) fail('untrusted-directory');
    }
}
function regular(file, privateFile = false, installed = false) {
    directoryChain(path.dirname(file), false, installed);
    const stat = info(file);
    if (!stat) return null;
    if (!stat.isFile() || stat.isSymbolicLink() || stat.nlink !== 1) fail('linked-or-nonregular-file');
    if (!windows && (stat.uid !== uid && stat.uid !== 0 || stat.mode & (privateFile ? 0o077 : installed ? 0o002 : 0o022))) fail('unsafe-file-permissions');
    if (privateFile && !windows && stat.uid !== uid) fail('unowned-auth-file');
    if (stat.size > 2 * 1024 * 1024) fail('oversized-metadata');
    return stat;
}
function readText(file, privateFile = false, installed = false) {
    const before = regular(file, privateFile, installed);
    if (!before) return null;
    const fd = fs.openSync(file, fs.constants.O_RDONLY | (fs.constants.O_NOFOLLOW || 0));
    try {
        const opened = fs.fstatSync(fd);
        if (opened.ino !== before.ino || opened.dev !== before.dev || opened.nlink !== 1) fail('file-changed');
        return fs.readFileSync(fd, 'utf8');
    } finally { fs.closeSync(fd); }
}
function json(text) {
    let value;
    try {
        value = JSON.parse(text.replace(/^\uFEFF/, ''), (_key, item) => {
            if (typeof item === 'number' && (!Number.isFinite(item) || Number.isInteger(item) && !Number.isSafeInteger(item))) fail('unsafe-json-number');
            return item;
        });
    } catch { fail('invalid-json'); }
    // JSON.parse silently discards duplicate keys, which could discard credentials.
    const tokens = text.match(/"(?:[^"\\]|\\.)*"|[{}\[\]:,]/g) || [];
    const stack = [];
    for (let i = 0; i < tokens.length; i++) {
        const token = tokens[i];
        if (token === '{' || token === '[') stack.push(token === '{' ? new Set() : null);
        else if (token === '}' || token === ']') stack.pop();
        else if (token.startsWith('"') && tokens[i + 1] === ':') {
            const name = JSON.parse(token);
            const names = stack[stack.length - 1];
            if (!names || names.has(name)) fail('duplicate-json-key');
            names.add(name);
        }
    }
    if (!object(value)) fail('invalid-json-object');
    return value;
}
// No provider SDK, auth resolver, extension, or model process is loaded here.
function installedPackages(home) {
    operation = 'pi-package';
    const prefix = path.join(home, '.local', ...(windows ? [] : ['lib']), 'node_modules');
    const manifest = path.join(prefix, '@earendil-works/pi-coding-agent/package.json');
    // npm inherits the account umask. This already-installed/executed code is trusted
    // like Pi itself; credential paths still require private, non-writable boundaries.
    const metadata = json(readText(manifest, false, true) || 'null');
    if (metadata.name !== '@earendil-works/pi-coding-agent') fail('pi-package-unavailable');
    const request = createRequire(manifest);
    function dependency(name) {
        for (const search of request.resolve.paths(name) || []) {
            if (!within(search, prefix)) continue;
            const root = path.join(search, name);
            directoryChain(root, true, true);
            const contents = info(path.join(root, 'package.json')) ? readText(path.join(root, 'package.json'), false, true) : null;
            if (contents !== null) {
                const data = json(contents);
                if (data.name !== name) fail('unexpected-dependency');
                return {root, data};
            }
        }
        fail('pi-dependency-unavailable');
    }
    operation = 'pi-dependency';
    const ai = dependency('@earendil-works/pi-ai');
    operation = 'go-catalog';
    const catalog = json(readText(path.join(ai.root, 'dist/providers/data/opencode-go.json'), false, true) || 'null');
    const id = 'muse-spark-1.3-contributor';
    const matches = Object.values(catalog).flatMap(group => object(group) ? Object.values(group).filter(model => model?.id === id) : []);
    const model = catalog['openai-responses']?.[id];
    if (matches.length !== 1 || matches[0] !== model || model.provider !== 'opencode-go' ||
        model.api !== 'openai-responses' || model.baseUrl !== 'https://opencode.ai/zen/go/v1' ||
        model.reasoning !== true || model.thinkingLevelMap?.xhigh !== 'xhigh') fail('catalog-incompatible');
    return {request, dependency, prefix};
}
// PowerShell receives only a path/action, never credentials, via its environment.
// Async execution keeps the native lock heartbeat alive while Windows checks ACLs.
async function acl(file, action) {
    if (!windows) return;
    const script = String.raw`$ErrorActionPreference = 'Stop'
$env:PSModulePath = "$PSHOME\Modules"
try {
    $file = $env:PI_GO_ACL_PATH
    $action = $env:PI_GO_ACL_ACTION
    $owner = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
    $allowed = @($owner.Value, 'S-1-5-18', 'S-1-5-32-544')
    $target = Get-Item -LiteralPath $file -Force -ErrorAction Stop
    $boundary = if ($target.PSIsContainer) { $file } else { Split-Path -Parent $file }
    $current = $file
    while ($current) {
        $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'linked' }
        $security = Get-Acl -LiteralPath $current
        $owners = $allowed
        if ($current -ne $file -and $current -ne $boundary) {
            # TrustedInstaller can own system ancestors, never the secret or its parent.
            $owners += 'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464'
        }
        if ($security.GetOwner([System.Security.Principal.SecurityIdentifier]).Value -notin $owners) { throw 'owner' }
        $write = [System.Security.AccessControl.FileSystemRights]::Delete -bor [System.Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles -bor [System.Security.AccessControl.FileSystemRights]::ChangePermissions -bor [System.Security.AccessControl.FileSystemRights]::TakeOwnership
        if ($current -eq $file -or $current -eq $boundary) { $write = $write -bor [System.Security.AccessControl.FileSystemRights]::Write }
        foreach ($rule in $security.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier])) {
            if ($rule.PropagationFlags -band [System.Security.AccessControl.PropagationFlags]::InheritOnly) { continue }
            if ($rule.AccessControlType -eq 'Allow' -and $rule.IdentityReference.Value -notin $allowed) {
                if (($rule.FileSystemRights -band $write) -or ($current -eq $file -and $action -eq 'private')) { throw 'access' }
            }
        }
        $current = Split-Path -Parent $current
    }
    if ($action -eq 'secure') {
        $security = [System.Security.AccessControl.FileSecurity]::new()
        $security.SetOwner($owner)
        $security.SetAccessRuleProtection($true, $false)
        foreach ($sid in $allowed) {
            $security.AddAccessRule([System.Security.AccessControl.FileSystemAccessRule]::new([System.Security.Principal.SecurityIdentifier]::new($sid), 'FullControl', 'Allow'))
        }
        Set-Acl -LiteralPath $file -AclObject $security
    }
    [Console]::Out.Write('ok')
} catch { exit 1 }`;
    const systemRoot = absolute(process.env.SystemRoot || 'C:\\Windows');
    const executable = path.join(systemRoot, 'System32/WindowsPowerShell/v1.0/powershell.exe');
    await new Promise((resolve, reject) => {
        const child = spawn(executable, ['-NoProfile', '-NonInteractive', '-EncodedCommand', Buffer.from(script, 'utf16le').toString('base64')], {
            env: {SystemRoot: systemRoot, WINDIR: systemRoot, PI_GO_ACL_PATH: file, PI_GO_ACL_ACTION: action},
            windowsHide: true, shell: false, stdio: ['ignore', 'pipe', 'pipe'],
        });
        let output = '';
        const timer = setTimeout(() => { child.kill(); reject(new GoSetupError('acl-timeout')); }, 15000);
        child.stdout.on('data', data => { if (output.length < 32) output += data.toString(); });
        child.stderr.resume();
        child.on('error', () => { clearTimeout(timer); reject(new GoSetupError('acl-unavailable')); });
        child.on('close', code => {
            clearTimeout(timer);
            if (code === 0 && output === 'ok') resolve(); else reject(new GoSetupError('acl-unsafe'));
        });
    });
}
function envKey(home) {
    const text = readText(path.join(home, '.env.local'));
    if (text === null) return '';
    let result = '';
    for (const line of text.replace(/^\uFEFF/, '').split(/\r?\n/)) {
        const match = line.match(/^[ \t]*(?:export[ \t]+)?OPENCODE_GO_API_KEY[ \t]*=[ \t]*(.*)$/);
        if (!match) continue;
        result = match[1].trim();
        if (result.length >= 2 && ['"', "'"].includes(result[0]) && result.at(-1) === result[0]) result = result.slice(1, -1).trim();
    }
    // Accept plain token syntax, never Pi's $ interpolation or ! command syntax.
    if (result && !/^[A-Za-z0-9._~+/=-]{1,4096}$/.test(result)) fail('invalid-key-format');
    if (result) regular(path.join(home, '.env.local'), true);
    return result;
}
function authDocument(text) {
    const document = json(text);
    for (const credential of Object.values(document)) {
        if (!object(credential) || typeof credential.type !== 'string' || !credential.type) fail('invalid-credential');
        if (credential.type === 'api_key' &&
            (credential.key !== undefined && typeof credential.key !== 'string' || credential.env !== undefined &&
                (!object(credential.env) || Object.values(credential.env).some(value => typeof value !== 'string')))) fail('invalid-credential');
    }
    return document;
}
async function main() {
    process.umask(0o077);
    if (!['sync', 'check-catalog'].includes(process.argv[4] || 'sync')) fail('invalid-mode');
    const [major, minor] = process.versions.node.split('.').map(Number);
    if (major < 22 || major === 22 && minor < 20 || typeof fs.globSync !== 'function') fail('node-incompatible');
    operation = 'home';
    const logicalHome = absolute(process.argv[2]);
    directoryChain(logicalHome);
    const home = fs.realpathSync(logicalHome); // Only the verified account HOME boundary is resolved.
    if (!windows && fs.statSync(home).uid !== uid) fail('unowned-home');
    await acl(home, 'directory');
    const packages = installedPackages(home);
    if (process.argv[4] === 'check-catalog') return 'catalog-ready';
    operation = 'environment-file';
    const envFile = path.join(home, '.env.local');
    if (info(envFile)) await acl(envFile, 'directory');
    const key = envKey(home);
    if (key) await acl(envFile, 'private');
    operation = 'active-profile';
    let selected = process.argv[3] || path.join(logicalHome, '.pi/agent');
    if (selected === '~' || selected.startsWith('~/') || windows && selected.startsWith('~\\')) selected = path.join(logicalHome, selected.slice(2));
    selected = absolute(selected);
    const profile = within(selected, logicalHome) ? path.join(home, path.relative(logicalHome, selected)) : selected;
    if (profile === path.parse(profile).root || profile === home) fail('unsafe-profile');
    directoryChain(profile, true);
    if (info(profile)) {
        operation = 'models-json';
        const modelsText = readText(path.join(profile, 'models.json'));
        if (modelsText !== null) {
            const models = json(modelsText);
            if (models.providers !== undefined && !object(models.providers)) fail('invalid-providers');
            if (models.providers && Object.hasOwn(models.providers, 'opencode-go')) fail('go-provider-overridden');
        }
    }
    if (!key) return 'missing-key'; // Never open auth.json or create a profile for absent input.
    operation = 'auth-lock';
    const auth = path.join(profile, 'auth.json');
    const lockPath = auth + '.lock';
    function inspectLock() {
        const stat = info(lockPath);
        if (stat && (!stat.isDirectory() || stat.isSymbolicLink() || !windows && (stat.uid !== uid || stat.mode & 0o002) || fs.readdirSync(lockPath).length)) fail('unsafe-lock');
        return stat;
    }
    inspectLock();
    operation = 'lock-dependency';
    const dependency = packages.dependency('proper-lockfile');
    if (dependency.data.version !== '4.1.2') fail('lock-version-unsupported');
    const expectedEntry = path.join(dependency.root, 'index.js');
    if (!regular(expectedEntry, false, true)) fail('unsafe-lock-dependency');
    const lockEntry = packages.request.resolve('proper-lockfile');
    if (lockEntry !== expectedEntry) fail('unsafe-lock-dependency');
    await acl(lockEntry, 'directory');
    const lockfile = packages.request(lockEntry); // Only Pi's installed native lock dependency executes.
    if (typeof lockfile.lock !== 'function') fail('lock-unavailable');
    // Preflight existing metadata before creating directories or lock files.
    operation = 'auth-preflight';
    if (info(profile)) {
        await acl(profile, 'directory');
        if (regular(auth, true)) {
            await acl(auth, 'private');
            // Actual content is read only after locking; OAuth may be writing now.
        }
    }
    operation = 'profile-create';
    fs.mkdirSync(profile, {recursive: true, mode: 0o700});
    directoryChain(profile);
    await acl(profile, 'directory');
    let compromised = false;
    let release;
    let temporary;
    try {
        // realpath:false matches Pi; locking by pathname also survives atomic rename.
        // A short update interval interoperates with Pi's synchronous 10s stale timeout.
        operation = 'lock-acquire';
        release = await lockfile.lock(auth, {realpath: false, stale: 30000, update: 1000,
            retries: {retries: 30, minTimeout: 100, maxTimeout: 1000, factor: 1.2},
            onCompromised: () => { compromised = true; }});
        operation = 'auth-read';
        const held = inspectLock();
        if (!held) fail('lock-unverified');
        directoryChain(profile);
        const before = readText(auth, true);
        if (before !== null) await acl(auth, 'private');
        const document = before === null ? {} : authDocument(before);
        if (compromised) fail('lock-compromised');
        const replacement = {type: 'api_key', key};
        if (JSON.stringify(document['opencode-go']) === JSON.stringify(replacement)) return 'unchanged';
        document['opencode-go'] = replacement;
        operation = 'auth-write';
        temporary = path.join(profile, '.opencode-go-' + crypto.randomBytes(16).toString('hex'));
        // Empty file first: inherited Windows ACLs are secured before any secret write.
        const fd = fs.openSync(temporary, 'wx', 0o600);
        try {
            await acl(temporary, 'secure');
            await acl(temporary, 'private');
            directoryChain(profile);
            const currentLock = inspectLock();
            if (compromised || !currentLock || held.ino !== currentLock.ino || held.dev !== currentLock.dev) fail('lock-compromised');
            if (readText(auth, true) !== before) fail('concurrent-metadata-change');
            fs.writeFileSync(fd, (before?.startsWith('\uFEFF') ? '\uFEFF' : '') + JSON.stringify(document, null, 2) + '\n');
            fs.fsyncSync(fd);
        } finally { fs.closeSync(fd); }
        fs.renameSync(temporary, auth);
        temporary = null;
        if (!windows) {
            const fd = fs.openSync(profile, 'r');
            try { fs.fsyncSync(fd); } finally { fs.closeSync(fd); }
        }
        if (compromised) fail('lock-compromised');
        return 'updated';
    } catch (error) {
        // Preserve the failing phase when finally advances to cleanup/release.
        throw error instanceof GoSetupError ? error : new GoSetupError(failureReason(error));
    } finally {
        operation = 'auth-cleanup';
        if (temporary && info(temporary)) fs.unlinkSync(temporary);
        operation = 'lock-release';
        if (release) await release();
    }
}
main().then(result => console.log(result)).catch(error => {
    const phase = error instanceof GoSetupError ? error.operation : operation;
    console.log('go-failure:' + phase + ':' + failureReason(error));
    process.exitCode = 1;
});
// END PI_OPENCODE_GO_SETUP
PI_OPENCODE_GO_JS
    ) || _status=$?
    if [[ "${_status}" -ne 0 ]]; then
        if [[ "${_result}" =~ ^go-failure:(${_operations}):(${_reasons})$ ]]; then
            print_warning "Pi Go setup failed: ${BASH_REMATCH[1]}: ${BASH_REMATCH[2]}. Review this check locally, then rerun setup."
        else
            print_warning "Pi Go setup failed: helper-exit-${_status}: diagnostic-unavailable. No safe helper detail was received."
        fi
        return 1
    fi
    case "${_result}" in
        missing-key) print_warning "Pi Go authentication not supplied: add OPENCODE_GO_API_KEY to ~/.env.local. Existing credentials were preserved; the Muse profile can still be configured." ;;
        updated) PI_OPENCODE_GO_CHANGED=1; print_success "Pi Go credential synchronized in the active Pi profile." ;;
        unchanged) print_debug "Pi Go credential is unchanged." ;;
        catalog-ready) print_debug "Installed Pi supports Go Muse Contributor with native Responses/xhigh." ;;
        *) print_warning "Pi Go setup failed: invalid-helper-result. No safe helper detail was received."; return 1 ;;
    esac
    return 0
}

# Force Pi defaults: GPT-6 Astra (OpenAI Codex) with xhigh thinking on all machines.
# Chezmoi owns ~/.pi/agent/settings.json long-term; this seeds the desired
# state on fresh machines and repairs drift where dotfiles are not applied.
configure_pi_defaults() {
    local _agent_dir="${PI_CODING_AGENT_DIR:-${HOME}/.pi/agent}"
    local _settings_file="${_agent_dir}/settings.json"
    local _tmp=""
    local _jq_expr='
        .defaultProvider = "openai-codex"
        | .defaultModel = "gpt-6-astra"
        | .defaultThinkingLevel = "xhigh"
        | .modelThinkingLevels = (.modelThinkingLevels // {})
        | .modelThinkingLevels["openai-codex/gpt-6-astra"] = "xhigh"
    '

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

    if jq "${_jq_expr}" "${_settings_file}" > "${_tmp}"; then
        if cat "${_tmp}" > "${_settings_file}"; then
            rm -f "${_tmp}"
            print_success "Pi default model set to GPT-6 Astra (OpenAI Codex) with xhigh thinking."
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

# Paseo release channels. Keep this block identical in the Bash setup scripts.
paseo_release_channel() {
    # The setup-scoped value survives later helpers that source .env.local again.
    local _channel="${_paseo_setup_channel:-${PASEO_CHANNEL:-}}"
    if [[ -z "${_channel}" ]]; then
        _channel=$(read_env_local_value "PASEO_CHANNEL" || true)
    fi
    case "${_channel:-beta}" in
        beta|stable) printf '%s\n' "${_channel:-beta}" ;;
        *)
            print_error "Invalid PASEO_CHANNEL. Use beta or stable." >&2
            return 1
            ;;
    esac
}

paseo_package_spec() {
    local _channel
    _channel=$(paseo_release_channel) || return 1
    if [[ "${_channel}" == "stable" ]]; then
        printf '%s\n' '@getpaseo/cli@latest'
    else
        printf '%s\n' '@getpaseo/cli@beta'
    fi
}

paseo_desktop_is_running() {
    if ! command -v pgrep &> /dev/null; then
        return 2
    fi
    local _uid
    _uid=$(id -u) || return 2
    pgrep -u "${_uid}" -x 'Paseo|paseo' > /dev/null
}

# Fedora Atomic/Bazzite use a system /home alias. Never resolve user-owned links.
# GNU stat is used only by the Linux caller below.
paseo_desktop_is_system_home_alias() {
    local _target _path _owner _mode
    [[ -L "/home" ]] || return 1
    _target=$(readlink "/home") || return 1
    case "${_target}" in
        var/home|"/var/home") ;;
        *) return 1 ;;
    esac
    _owner=$(stat -c %u "/home" 2>/dev/null) || return 1
    [[ "${_owner}" == 0 ]] || return 1
    for _path in "/" "/var" "/var/home"; do
        [[ -d "${_path}" && ! -L "${_path}" ]] || return 1
        _owner=$(stat -c %u "${_path}" 2>/dev/null) || return 1
        _mode=$(stat -c %a "${_path}" 2>/dev/null) || return 1
        [[ "${_owner}" == 0 && "${_mode}" =~ ^[0-7]{3,4}$ ]] || return 1
        (( (8#${_mode} & 0022) == 0 )) || return 1
    done
}

configure_paseo_desktop_channel() {
    local _platform="$1"
    local _channel _dir _file _parent _input _tmp _process_status
    _channel=$(paseo_release_channel) || return 1
    case "${_platform}" in
        macos) _dir="${HOME}/Library/Application Support/Paseo" ;;
        linux) _dir="${XDG_CONFIG_HOME:-${HOME}/.config}/Paseo" ;;
        wsl)
            print_message "Run win.ps1 on the Windows host to select the Paseo Desktop release channel. WSL does not change host client files."
            return 0
            ;;
        *) print_error "Unsupported Paseo Desktop platform."; return 1 ;;
    esac
    _dir="${PASEO_ELECTRON_USER_DATA_DIR:-${_dir}}"
    _file="${_dir}/desktop-settings.json"

    # Do not create desktop state on a headless machine without a client profile.
    if [[ "${HEADLESS:-}" == "1" && ! -e "${_dir}" && ! -L "${_dir}" ]]; then
        print_debug "No Paseo Desktop profile on this headless machine; skipping client channel setup."
        return 0
    fi
    if [[ "${_platform}" == "linux" && ! -e "${_dir}" && ! -L "${_dir}" ]]; then
        case "$(uname -m)" in
            x86_64|amd64) ;;
            *)
                print_warning "Paseo publishes Linux Desktop builds only for x64. Use the daemon with a supported client or browser."
                return 0
                ;;
        esac
    fi
    if [[ "${_dir}" != /* ]]; then
        print_error "Paseo Desktop user-data path must be absolute."
        return 1
    fi
    _parent="${_dir}"
    while [[ "${_parent}" != / ]]; do
        if [[ "${_platform}" == linux && "${_parent}" == "/home" ]] && paseo_desktop_is_system_home_alias; then
            # Inspect the real system ancestors too, without resolving the client path.
            _parent="/var/home"
            continue
        fi
        if [[ -L "${_parent}" || ( -e "${_parent}" && ! -d "${_parent}" ) ]]; then
            print_error "Unsafe Paseo Desktop directory. Linked or non-directory paths are not changed."
            return 1
        fi
        _parent=$(dirname "${_parent}")
    done
    if [[ -L "${_file}" || ( -e "${_file}" && ! -f "${_file}" ) ]]; then
        print_error "Unsafe Paseo Desktop settings path. Leaving it unchanged."
        return 1
    fi
    if ! command -v jq &> /dev/null; then
        print_error "jq is required to select the Paseo Desktop release channel."
        return 1
    fi
    _input=/dev/null
    if [[ -f "${_file}" ]]; then
        _input="${_file}"
        if ! jq -se 'length == 1 and (.[0] | type == "object" and .version == 1 and (.settings | type == "object") and ((has("migrations") | not) or (.migrations | type == "object")))' "${_file}" > /dev/null 2>&1; then
            print_error "Invalid or unsupported Paseo Desktop settings. Leaving the file unchanged."
            return 1
        fi
        if jq -e --arg channel "${_channel}" '.settings.releaseChannel == $channel and .migrations.legacyRendererSettingsImported == true' "${_file}" > /dev/null 2>&1; then
            print_debug "Paseo Desktop release channel is already ${_channel}."
            return 0
        fi
    fi
    if paseo_desktop_is_running; then
        print_error "Close Paseo Desktop and rerun setup to change its release channel. Setup does not stop the app or its daemon."
        return 1
    else
        _process_status=$?
        if [[ "${_process_status}" != "1" ]]; then
            print_error "Cannot determine whether Paseo Desktop is running. Leaving client settings unchanged."
            return 1
        fi
    fi
    if ! (umask 077; mkdir -p "${_dir}"); then
        print_error "Failed to create the Paseo Desktop settings directory."
        return 1
    fi
    _tmp=$(mktemp "${_file}.tmp.XXXXXX") || return 1
    # Match upstream's channel patch: prevent a legacy renderer preference from
    # importing the old channel on launch. Preserve all other settings/migrations.
    if ! jq -s --arg channel "${_channel}" '
        (if length == 0 then {version: 1, settings: {}, migrations: {}} else .[0] end)
        | .settings.releaseChannel = $channel
        | .migrations.legacyRendererSettingsImported = true
    ' "${_input}" > "${_tmp}" 2>/dev/null || ! chmod 600 "${_tmp}" || ! mv -f "${_tmp}" "${_file}"; then
        rm -f "${_tmp}"
        print_error "Failed to save the Paseo Desktop release channel."
        return 1
    fi
    print_success "Paseo Desktop release channel set to ${_channel}. Open Desktop and check for updates in Settings > About."
}
# End Paseo release channels.

# Remove the retired Synthetic provider without touching other providers or auth.json.
remove_pi_synthetic_models() {
    local _agent_dir="${PI_CODING_AGENT_DIR:-${HOME}/.pi/agent}"
    local _models_file="${_agent_dir}/models.json"
    local _tmp=""

    if [[ ! -e "${_models_file}" && ! -L "${_models_file}" ]]; then
        return 0
    fi
    if ! command -v jq &> /dev/null; then
        print_warning "jq not found. Cannot remove the Synthetic provider from ${_models_file}."
        return 1
    fi
    if ! jq -e 'type == "object" and (.providers == null or (.providers | type == "object"))' "${_models_file}" > /dev/null 2>&1; then
        print_warning "Invalid Pi models at ${_models_file}; leaving the file unchanged."
        return 1
    fi
    if ! jq -e '(.providers // {}) | has("synthetic")' "${_models_file}" > /dev/null; then
        return 0
    fi
    if ! _tmp=$(mktemp); then
        print_warning "Could not create a temporary file for Pi models at ${_models_file}."
        return 1
    fi

    # Write through existing symlinks, including chezmoi-managed files.
    if jq 'del(.providers.synthetic)' "${_models_file}" > "${_tmp}" \
        && cat "${_tmp}" > "${_models_file}" && chmod 600 "${_models_file}"; then
        rm -f "${_tmp}"
        print_success "Removed the Synthetic provider from ${_models_file}."
        return 0
    fi
    rm -f "${_tmp}"
    print_warning "Failed to remove the Synthetic provider from ${_models_file}."
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
            print_warning "ZAI_API_KEY not set in ~/.env.local. Add the key and rerun setup to enable the optional z.ai provider."
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

    PI_RUNTIME_PREFLIGHT_PASSED=0
    print_message "Installing/updating Pi coding agent..."

    mkdir -p "${_canonical_bin}"
    export PATH="${_canonical_bin}:${PATH}"
    # Chezmoi owns persistent shell PATH configuration.
    if ! ensure_pi_node_runtime; then
        print_warning "Skipping Pi installation and extension setup because the Pi Node.js runtime is not ready."
        return 1
    fi
    PI_RUNTIME_PREFLIGHT_PASSED=1

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

    if ! path_is_within_prefix "${_pi_target}" "${_local_prefix}"; then
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

    if ! verify_shared_node_shell "${_canonical_pi}"; then
        print_warning "Pi was installed, but a fresh fish shell cannot launch the canonical command. Review PATH and chezmoi activation."
        return 1
    fi
    print_success "Pi coding agent ${_pi_version} installed/updated at ${_canonical_pi}."
}


# shellcheck disable=SC2312
# Managed marker used to distinguish setup-owned Paseo service artifacts from user-managed ones.
PASEO_MANAGED_MARKER="Managed by scowalt machine setup: headless-paseo-daemon"
PASEO_PACKAGE="@getpaseo/cli"
PASEO_DEFAULT_LISTEN_TARGET="127.0.0.1:6767"
PASEO_LISTEN_TARGET=""
PASEO_SERVICE_NAME="paseo.service"
PASEO_VALIDATED_CMD=""
PASEO_VALIDATED_NODE=""
PASEO_SERVICE_PATH=""
PASEO_MANAGED_SERVICE_TOUCHED=0
PASEO_PACKAGE_VERSION="unknown"
PASEO_PACKAGE_CHANGED=0
PASEO_DAEMON_WRAPPER_CHANGED=0
PASEO_SYSTEMD_SERVICE_CHANGED=0
PASEO_LAST_HEALTH_ERROR=""
PASEO_LAST_HEALTH_SUMMARY=""

paseo_service_path() {
    printf '%s:%s:%s:%s:%s:%s:%s:%s:%s
' \
        "${HOME}/.local/bin" \
        "${HOME}/.bun/bin" \
        "${HOME}/.local/share/mise/shims" \
        "${HOME}/.mise/shims" \
        "${HOME}/.mise/bin" \
        "/opt/homebrew/bin" \
        "/home/linuxbrew/.linuxbrew/bin" \
        "/usr/local/bin" \
        "/usr/bin:/bin:/usr/sbin:/sbin"
}

paseo_effective_service_path() {
    if [[ -n "${PASEO_SERVICE_PATH}" ]]; then
        printf '%s
' "${PASEO_SERVICE_PATH}"
    else
        paseo_service_path
    fi
}

paseo_shell_quote() {
    local _escaped=""

    _escaped=$(printf '%s' "$1" | sed "s/'/'\\''/g") || return 1
    printf "'%s'" "${_escaped}"
}

paseo_command_target() {
    local _cmd=""
    local _link_target=""
    local _link_dir=""

    if ! command -v paseo &> /dev/null; then
        return 1
    fi

    _cmd=$(command -v paseo)

    if command -v realpath &> /dev/null; then
        realpath "${_cmd}" 2>/dev/null && return 0
    fi

    if readlink -f "${_cmd}" > /dev/null 2>&1; then
        readlink -f "${_cmd}" 2>/dev/null && return 0
    fi

    if [[ -L "${_cmd}" ]]; then
        _link_target=$(readlink "${_cmd}" 2>/dev/null || true)
        if [[ "${_link_target}" == /* ]]; then
            printf '%s\n' "${_link_target}"
        elif [[ -n "${_link_target}" ]]; then
            _link_dir=$(cd "$(dirname "${_cmd}")" && pwd -P)
            printf '%s\n' "${_link_dir}/${_link_target}"
        else
            printf '%s\n' "${_cmd}"
        fi
    else
        printf '%s\n' "${_cmd}"
    fi
}

paseo_command_matches_bun_global() {
    local _paseo_target="$1"
    local _bun_global_bin="$2"
    local _bun_paseo="${_bun_global_bin}/paseo"

    [[ -n "${_paseo_target}" && -n "${_bun_global_bin}" && -e "${_bun_paseo}" ]] || return 1
    [[ "${_paseo_target}" -ef "${_bun_paseo}" ]]
}

paseo_runtime_target() {
    local _cmd=""

    if ! command -v node &> /dev/null; then
        return 1
    fi

    _cmd=$(command -v node)
    if command -v realpath &> /dev/null; then
        realpath "${_cmd}" 2>/dev/null && return 0
    fi
    if readlink -f "${_cmd}" > /dev/null 2>&1; then
        readlink -f "${_cmd}" 2>/dev/null && return 0
    fi
    printf '%s\n' "${_cmd}"
}

paseo_path_owner() {
    local _path="$1"

    if stat -c '%U' "${_path}" >/dev/null 2>&1; then
        stat -c '%U' "${_path}" 2>/dev/null
    else
        stat -f '%Su' "${_path}" 2>/dev/null || true
    fi
}

paseo_path_is_group_or_world_writable() {
    local _path="$1"
    local _dir=""
    local _unsafe=""

    if [[ -z "${_path}" ]]; then
        return 0
    fi

    _unsafe=$(find "${_path}" -prune \( -perm -020 -o -perm -002 \) -print -quit 2>/dev/null || true)
    if [[ -n "${_unsafe}" ]]; then
        return 0
    fi

    if [[ -d "${_path}" ]]; then
        _dir="${_path}"
    else
        _dir=$(dirname "${_path}")
    fi

    [[ -d "${_dir}" ]] || return 0

    while [[ -n "${_dir}" && "${_dir}" != "/" ]]; do
        _unsafe=$(find "${_dir}" -prune \( -perm -020 -o -perm -002 \) -print -quit 2>/dev/null || true)
        if [[ -n "${_unsafe}" ]]; then
            return 0
        fi
        _dir=$(dirname "${_dir}")
    done

    _unsafe=$(find / -prune \( -perm -020 -o -perm -002 \) -print -quit 2>/dev/null || true)
    [[ -n "${_unsafe}" ]]
}

paseo_harden_user_path_chain() {
    local _path="$1"
    local _label="$2"
    local _home_real=""
    local _target=""
    local _dir=""
    local _owner=""
    local _target_under_home=0
    local _user=""

    [[ -n "${_path}" && -e "${_path}" ]] || return 0
    [[ -n "${HOME}" && -d "${HOME}" ]] || return 0

    _user=$(whoami || true)
    [[ -n "${_user}" ]] || return 0

    if command -v realpath &> /dev/null; then
        _home_real=$(realpath "${HOME}" 2>/dev/null || true)
        _target=$(realpath "${_path}" 2>/dev/null || true)
    elif readlink -f "${HOME}" > /dev/null 2>&1 && readlink -f "${_path}" > /dev/null 2>&1; then
        _home_real=$(readlink -f "${HOME}" 2>/dev/null || true)
        _target=$(readlink -f "${_path}" 2>/dev/null || true)
    else
        _home_real=$(cd "${HOME}" && pwd -P) || return 0
        if [[ -d "${_path}" ]]; then
            _target=$(cd "${_path}" && pwd -P) || return 0
        else
            _dir=$(cd "$(dirname "${_path}")" && pwd -P) || return 0
            _target="${_dir}/$(basename "${_path}")"
        fi
    fi

    [[ -n "${_home_real}" && -n "${_target}" ]] || return 0

    case "${_target}" in
        "${_home_real}"|"${_home_real}/"*) _target_under_home=1 ;;
        *) ;;
    esac

    _owner=$(paseo_path_owner "${_target}")
    if [[ "${_owner}" == "${_user}" ]] && ! chmod go-w "${_target}"; then
        print_error "Failed to harden Paseo ${_label} path permissions: ${_target}"
        return 1
    fi

    if [[ -d "${_target}" ]]; then
        _dir="${_target}"
    else
        _dir=$(dirname "${_target}")
    fi

    while [[ -n "${_dir}" && "${_dir}" != "/" ]]; do
        if [[ "${_target_under_home}" == "1" ]]; then
            case "${_dir}" in
                "${_home_real}"|"${_home_real}/"*) ;;
                *) break ;;
            esac
        fi

        _owner=$(paseo_path_owner "${_dir}")
        if [[ "${_owner}" == "${_user}" ]] && ! chmod go-w "${_dir}"; then
            print_error "Failed to harden Paseo ${_label} parent permissions: ${_dir}"
            return 1
        elif [[ "${_owner}" != "${_user}" && "${_target_under_home}" != "1" ]]; then
            break
        fi

        [[ "${_dir}" == "${_home_real}" ]] && break
        _dir=$(dirname "${_dir}")
    done
}

paseo_harden_service_path_components() {
    local _path_value="$1"
    local _component=""

    while IFS= read -r _component; do
        [[ -n "${_component}" ]] || continue

        if [[ -L "${_component}" ]]; then
            paseo_harden_user_path_chain "$(dirname "${_component}")" "service PATH component parent" || return 1
        fi

        [[ -e "${_component}" ]] || continue
        paseo_harden_user_path_chain "${_component}" "service PATH component" || return 1
    done < <(printf '%s\n' "${_path_value}" | tr ':' '\n' || true)
}

paseo_existing_service_path() {
    local _path_value="$1"
    local _component=""
    local _result=""

    while IFS= read -r _component; do
        [[ -n "${_component}" && -d "${_component}" ]] || continue

        if [[ -z "${_result}" ]]; then
            _result="${_component}"
        else
            _result="${_result}:${_component}"
        fi
    done < <(printf '%s\n' "${_path_value}" | tr ':' '\n' || true)

    printf '%s\n' "${_result}"
}

paseo_path_owner_is_trusted() {
    local _path="$1"
    local _dir=""
    local _owner=""
    local _user=""

    _user=$(whoami || true)
    _owner=$(paseo_path_owner "${_path}")
    case "${_owner}" in
        root|"${_user}"|linuxbrew|homebrew) ;;
        *) return 1 ;;
    esac

    if [[ -d "${_path}" ]]; then
        _dir="${_path}"
    else
        _dir=$(dirname "${_path}")
    fi

    [[ -d "${_dir}" ]] || return 1

    while [[ -n "${_dir}" && "${_dir}" != "/" ]]; do
        _owner=$(paseo_path_owner "${_dir}")
        case "${_owner}" in
            root|"${_user}"|linuxbrew|homebrew) ;;
            *) return 1 ;;
        esac
        _dir=$(dirname "${_dir}")
    done

    return 0
}

paseo_validate_trusted_path() {
    local _path="$1"
    local _label="$2"

    if [[ -z "${_path}" || ! -e "${_path}" ]]; then
        print_error "Paseo ${_label} path is missing."
        return 1
    fi

    if paseo_path_is_group_or_world_writable "${_path}"; then
        print_error "Paseo ${_label} path is under a group/world-writable directory; refusing to trust it."
        return 1
    fi

    if ! paseo_path_owner_is_trusted "${_path}"; then
        print_error "Paseo ${_label} path has an untrusted owner in its parent chain; refusing to trust it."
        return 1
    fi
}

paseo_validate_service_path_components() {
    local _path_value="$1"
    local _component=""
    local _resolved_component=""
    local _link_target=""
    local _link_dir=""

    while IFS= read -r _component; do
        [[ -n "${_component}" && -d "${_component}" ]] || continue

        _resolved_component="${_component}"
        if [[ -L "${_component}" ]]; then
            if command -v realpath &> /dev/null; then
                _resolved_component=$(realpath "${_component}" 2>/dev/null || true)
            elif readlink -f "${_component}" > /dev/null 2>&1; then
                _resolved_component=$(readlink -f "${_component}" 2>/dev/null || true)
            else
                _link_target=$(readlink "${_component}" 2>/dev/null || true)
                if [[ "${_link_target}" == /* ]]; then
                    _resolved_component="${_link_target}"
                elif [[ -n "${_link_target}" ]]; then
                    _link_dir=$(cd "$(dirname "${_component}")" && pwd -P)
                    _resolved_component="${_link_dir}/${_link_target}"
                fi
            fi

            if [[ -z "${_resolved_component}" || ! -d "${_resolved_component}" ]]; then
                print_error "Paseo service PATH component ${_component} resolves to a missing target."
                return 1
            fi

            # Symlink mode bits are commonly 0777 and not security-relevant; validate
            # the trusted parent plus the resolved target instead.
            paseo_validate_trusted_path "$(dirname "${_component}")" "service PATH component parent" || return 1
        fi

        paseo_validate_trusted_path "${_resolved_component}" "service PATH component" || return 1
    done < <(printf '%s\n' "${_path_value}" | tr ':' '\n' || true)
}

paseo_trusted_service_path() {
    local _path_value="$1"
    local _component=""
    local _result=""

    while IFS= read -r _component; do
        [[ -n "${_component}" && -d "${_component}" ]] || continue

        if ! paseo_validate_service_path_components "${_component}" >/dev/null 2>&1; then
            print_warning "Skipping untrusted optional Paseo service PATH component: ${_component}" >&2
            continue
        fi

        if [[ -z "${_result}" ]]; then
            _result="${_component}"
        else
            _result="${_result}:${_component}"
        fi
    done < <(printf '%s\n' "${_path_value}" | tr ':' '\n' || true)

    printf '%s\n' "${_result}"
}

install_paseo_cli() {
    local _global_packages=""
    local _paseo_target=""
    local _previous_paseo_target=""
    local _previous_version_output=""
    local _node_target=""
    local _node_dir=""
    local _version_output=""
    local _service_path=""
    local _bun_global_bin=""
    local _package_spec=""

    if [[ "${HEADLESS:-}" != "1" ]]; then
        return 0
    fi

    _package_spec=$(paseo_package_spec) || return 1
    PASEO_PACKAGE_CHANGED=0
    print_message "Installing/updating ${_package_spec} for headless daemon setup..."

    _service_path=$(paseo_service_path)
    export PATH="${HOME}/.bun/bin:${_service_path}:${PATH}"

    _previous_paseo_target=$(paseo_command_target 2>/dev/null || true)
    if [[ -n "${_previous_paseo_target}" ]]; then
        _previous_version_output=$(HOME="${HOME}" PATH="${PATH}" "${_previous_paseo_target}" --version 2>/dev/null || true)
    fi
    if ! command -v bun &> /dev/null; then
        print_error "Bun not found. Cannot install ${PASEO_PACKAGE} for HEADLESS=1."
        return 1
    fi

    if ! ensure_pi_node_runtime; then
        print_error "A supported shared Node/npm runtime is required before installing ${PASEO_PACKAGE}."
        return 1
    fi

    if ! bun install -g "${_package_spec}"; then
        print_error "Failed to install ${_package_spec}."
        return 1
    fi

    hash -r 2>/dev/null || true
    _global_packages=$(bun pm ls -g 2>/dev/null || true)
    if ! grep -Fq "${PASEO_PACKAGE}" <<< "${_global_packages}"; then
        print_error "Paseo install validation failed: ${PASEO_PACKAGE} is not listed in Bun global packages."
        return 1
    fi

    _paseo_target=$(paseo_command_target 2>/dev/null || true)
    if [[ -z "${_paseo_target}" ]]; then
        print_error "Paseo install validation failed: paseo command is not available after installing ${PASEO_PACKAGE}."
        return 1
    fi

    _bun_global_bin=$(bun pm bin -g 2>/dev/null || true)
    if [[ -z "${_bun_global_bin}" ]]; then
        print_error "Paseo install validation failed: Bun global bin path could not be resolved."
        return 1
    fi
    if ! paseo_command_matches_bun_global "${_paseo_target}" "${_bun_global_bin}"; then
        if [[ "${_paseo_target}" == *"/node_modules/paseo/"* ]] || [[ "${_paseo_target}" == *"/node_modules/paseo/bin"* ]]; then
            print_error "Paseo command resolves to the unrelated unscoped paseo package: ${_paseo_target}"
        else
            print_error "Paseo command does not match Bun's global paseo executable: ${_paseo_target}"
        fi
        return 1
    fi

    paseo_harden_user_path_chain "${_paseo_target}" "executable" || return 1
    paseo_validate_trusted_path "${_paseo_target}" "executable" || return 1

    _node_target=$(paseo_runtime_target 2>/dev/null || true)
    if [[ -z "${_node_target}" ]]; then
        print_error "Paseo runtime validation failed: node is not available for the service wrapper."
        return 1
    fi
    paseo_harden_user_path_chain "${_node_target}" "runtime" || return 1
    paseo_validate_trusted_path "${_node_target}" "runtime" || return 1

    PASEO_VALIDATED_CMD="${_paseo_target}"
    PASEO_VALIDATED_NODE="${_node_target}"
    _node_dir=$(dirname "${_node_target}")
    _service_path=$(paseo_service_path)
    _service_path=$(paseo_existing_service_path "${_service_path}")
    paseo_harden_service_path_components "${_service_path}" || return 1
    _service_path=$(paseo_trusted_service_path "${_service_path}")
    PASEO_SERVICE_PATH="${_node_dir}${_service_path:+:${_service_path}}"
    if [[ -z "${PASEO_SERVICE_PATH}" ]]; then
        print_error "Paseo service PATH validation failed: no existing PATH components remain."
        return 1
    fi
    paseo_validate_service_path_components "${PASEO_SERVICE_PATH}" || return 1

    if ! _version_output=$(HOME="${HOME}" PATH="${PASEO_SERVICE_PATH}:${PATH}" "${_paseo_target}" --version 2>/dev/null); then
        print_error "Paseo install validation failed: validated paseo command did not run successfully with the service PATH."
        return 1
    fi

    PASEO_PACKAGE_VERSION=$(printf '%s' "${_version_output}" | head -n 1 || true)
    PASEO_PACKAGE_VERSION=$(printf '%s' "${PASEO_PACKAGE_VERSION}" | tr -cd '[:alnum:].:_/@ -' | cut -c1-80 || true)
    [[ -n "${PASEO_PACKAGE_VERSION}" ]] || PASEO_PACKAGE_VERSION="unknown"

    if [[ "${_previous_paseo_target}" != "${_paseo_target}" || "${_previous_version_output}" != "${_version_output}" ]]; then
        PASEO_PACKAGE_CHANGED=1
    fi

    print_success "Paseo CLI ready (${PASEO_PACKAGE}, ${PASEO_PACKAGE_VERSION})."
}

write_paseo_daemon_wrapper() {
    local _wrapper="${HOME}/.local/bin/paseo-daemon-start"
    local _log_dir="${HOME}/.local/log/paseo-daemon"
    local _tmp=""
    local _home_q=""
    local _path_q=""
    local _cmd_q=""
    local _node_q=""
    local _listen_q=""
    local _service_path=""

    if [[ -z "${PASEO_VALIDATED_CMD}" ]]; then
        print_error "Cannot write Paseo daemon wrapper before validating the paseo command."
        return 1
    fi
    paseo_resolve_listen_target || return 1

    PASEO_DAEMON_WRAPPER_CHANGED=0
    mkdir -p "${HOME}/.local/bin" "${_log_dir}"
    chmod 700 "${HOME}/.local/bin" "${_log_dir}"

    _service_path=$(paseo_effective_service_path)
    _home_q=$(paseo_shell_quote "${HOME}")
    _path_q=$(paseo_shell_quote "${_service_path}")
    _cmd_q=$(paseo_shell_quote "${PASEO_VALIDATED_CMD}")
    _node_q=$(paseo_shell_quote "${PASEO_VALIDATED_NODE}")
    _listen_q=$(paseo_shell_quote "${PASEO_LISTEN_TARGET}")
    _tmp=$(mktemp)
    if ! cat > "${_tmp}" << EOF
#!/bin/bash
# ${PASEO_MANAGED_MARKER}
set -euo pipefail
export HOME=${_home_q}
export PATH=${_path_q}
[[ -x ${_node_q} ]] || exit 127
[[ -x ${_cmd_q} ]] || exit 127
exec ${_cmd_q} daemon start --foreground --listen ${_listen_q}
EOF
    then
        rm -f "${_tmp}"
        print_error "Failed to write Paseo daemon wrapper."
        return 1
    fi
    if ! chmod 700 "${_tmp}"; then
        rm -f "${_tmp}"
        print_error "Failed to install Paseo daemon wrapper."
        return 1
    fi

    if [[ -f "${_wrapper}" ]] && cmp -s "${_tmp}" "${_wrapper}"; then
        rm -f "${_tmp}"
        if ! chmod 700 "${_wrapper}"; then
            print_error "Failed to secure Paseo daemon wrapper."
            return 1
        fi
        print_debug "Paseo daemon wrapper is unchanged."
    else
        if ! mv "${_tmp}" "${_wrapper}"; then
            rm -f "${_tmp}"
            print_error "Failed to install Paseo daemon wrapper."
            return 1
        fi
        PASEO_DAEMON_WRAPPER_CHANGED=1
        print_success "Paseo daemon wrapper installed at ${_wrapper}."
    fi
}

paseo_managed_service_is_active() {
    paseo_systemctl_user is-active "${PASEO_SERVICE_NAME}" >/dev/null 2>&1
}

# systemd --user bus-backed control. When D-Bus is unavailable or stale (e.g.
# after lingering sessions close PAM sessions and systemd --runtime-dir is
# removed), fall back to the machined-mediated control channel
# (`--machine=<user>@ --user`) which works for any user manager systemd
# has spawned.
paseo_systemctl_user() {
    local _uid=""
    local _runtime_dir=""
    local _user=""

    _uid=$(id -u 2>/dev/null || true)
    [[ "${_uid}" =~ ^[0-9]+$ ]] || return 1
    _runtime_dir="/run/user/${_uid}"

    if XDG_RUNTIME_DIR="${_runtime_dir}" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=${_runtime_dir}/bus" \
        systemctl --user "$@" 2>/dev/null; then
        return 0
    fi

    _user=$(whoami 2>/dev/null || true)
    if [[ -z "${_user}" ]]; then
        return 1
    fi

    systemctl --machine="${_user}@" --user "$@" 2>/dev/null
}

paseo_managed_service_is_active_strict() {
    local _attempt=0
    local _max_attempts=${PASEO_ACTIVE_CHECK_ATTEMPTS:-5}
    local _delay=${PASEO_ACTIVE_CHECK_DELAY:-1}

    while [[ ${_attempt} -lt ${_max_attempts} ]]; do
        if paseo_systemctl_user is-active "${PASEO_SERVICE_NAME}" >/dev/null 2>&1; then
            return 0
        fi
        _attempt=$(( _attempt + 1 ))
        if [[ ${_attempt} -lt ${_max_attempts} ]]; then
            sleep "${_delay}" || true
        fi
    done
    return 1
}

stop_existing_paseo_daemon() {
    local _service_path=""
    local _state=""

    if [[ -z "${PASEO_VALIDATED_CMD}" ]]; then
        return 0
    fi

    if paseo_managed_service_is_active; then
        print_debug "Existing Paseo daemon is already managed by ${PASEO_SERVICE_NAME}; leaving it running until change detection completes."
        return 0
    fi

    _state=$(paseo_local_daemon_state 2>/dev/null || true)
    if [[ "${_state}" != "running" ]]; then
        print_debug "No running unmanaged Paseo daemon detected before service start."
        return 0
    fi

    print_message "Stopping existing unmanaged Paseo daemon before service start..."
    _service_path=$(paseo_effective_service_path)
    if ! HOME="${HOME}" PATH="${_service_path}:${PATH}" paseo_run_with_timeout "${PASEO_STATUS_TIMEOUT_SECONDS:-10}" "${PASEO_VALIDATED_CMD}" daemon stop >/dev/null 2>&1; then
        print_error "Failed to stop existing Paseo daemon before installing the managed service."
        return 1
    fi

    sleep 1
    _state=$(paseo_local_daemon_state 2>/dev/null || true)
    if [[ "${_state}" == "running" ]]; then
        print_error "Existing Paseo daemon is still running after stop; refusing to let it mask managed-service health."
        return 1
    fi
}

paseo_sanitize_status_value() {
    printf '%s' "${1:-unknown}" | tr -cd '[:alnum:]_.:-' | cut -c1-64 || true
}

paseo_json_string_field() {
    local _json="$1"
    local _field="$2"

    printf '%s\n' "${_json}" | sed -n "s/.*\"${_field}\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -n 1 || true
}

paseo_resolve_listen_target() {
    local _config_file="${HOME}/.paseo/config.json"
    local _configured_target="${PASEO_DEFAULT_LISTEN_TARGET}"
    local _target=""
    local _host=""
    local _port=""

    if [[ -n "${PASEO_LISTEN_TARGET}" ]]; then
        return 0
    fi

    if [[ -f "${_config_file}" ]]; then
        if ! command -v jq &> /dev/null; then
            print_error "jq is required to read Paseo daemon.listen for HEADLESS=1."
            return 1
        fi
        if ! _configured_target=$(jq -er --arg default "${PASEO_DEFAULT_LISTEN_TARGET}" '(.daemon.listen // $default) | if type == "string" then . else error("daemon.listen must be a string") end' "${_config_file}" 2>/dev/null); then
            print_error "Failed to read daemon.listen from ${_config_file}."
            return 1
        fi
    fi

    _target=$(paseo_sanitize_status_value "${_configured_target}")
    _host=${_target%:*}
    _port=${_target##*:}
    if [[ "${_configured_target}" != "${_target}" || "${_host}" != "127.0.0.1" || ! "${_port}" =~ ^[0-9]+$ ]] || (( 10#${_port} < 1 || 10#${_port} > 65535 )); then
        print_error "Paseo daemon.listen must use 127.0.0.1 and a port for HEADLESS=1; found ${_target:-unknown}."
        return 1
    fi

    PASEO_LISTEN_TARGET="${_target}"
    print_debug "Paseo managed listener resolved from configuration: ${PASEO_LISTEN_TARGET}"
}

paseo_status_relay_disabled() {
    local _json="$1"

    printf '%s\n' "${_json}" | grep -Eqi '\"relayDisabled\"[[:space:]]*:[[:space:]]*true|\"relayEnabled\"[[:space:]]*:[[:space:]]*false|\"relay\"[[:space:]]*:[[:space:]]*\"disabled\"|\"relayStatus\"[[:space:]]*:[[:space:]]*\"disabled\"'
}


paseo_run_with_timeout() {
    local _seconds="$1"
    shift

    if command -v timeout &> /dev/null; then
        timeout "${_seconds}" "$@"
    elif command -v perl &> /dev/null; then
        perl -e 'alarm shift; exec @ARGV' "${_seconds}" "$@"
    else
        print_error "No timeout helper (timeout or perl) is available for Paseo health checks."
        return 124
    fi
}

paseo_local_daemon_state() {
    local _status_json=""
    local _service_path=""

    _service_path=$(paseo_effective_service_path)
    if ! _status_json=$(HOME="${HOME}" PATH="${_service_path}:${PATH}" paseo_run_with_timeout "${PASEO_STATUS_TIMEOUT_SECONDS:-10}" "${PASEO_VALIDATED_CMD}" daemon status --json 2>/dev/null); then
        return 1
    fi

    paseo_json_string_field "${_status_json}" "localDaemon"
}

paseo_check_status_once() {
    local _status_json=""
    local _local_daemon=""
    local _connected_daemon=""
    local _field_value=""
    local _service_path=""

    _service_path=$(paseo_effective_service_path)
    if ! _status_json=$(HOME="${HOME}" PATH="${_service_path}:${PATH}" paseo_run_with_timeout "${PASEO_STATUS_TIMEOUT_SECONDS:-10}" "${PASEO_VALIDATED_CMD}" daemon status --json 2>/dev/null); then
        PASEO_LAST_HEALTH_ERROR="status command failed or timed out"
        return 1
    fi

    if ! printf '%s' "${_status_json}" | grep -q '^{'; then
        PASEO_LAST_HEALTH_ERROR="status command did not return JSON"
        return 1
    fi

    _field_value=$(paseo_json_string_field "${_status_json}" "localDaemon")
    _local_daemon=$(paseo_sanitize_status_value "${_field_value}")
    _field_value=$(paseo_json_string_field "${_status_json}" "connectedDaemon")
    _connected_daemon=$(paseo_sanitize_status_value "${_field_value}")
    PASEO_LAST_HEALTH_SUMMARY="localDaemon=${_local_daemon:-unknown}, connectedDaemon=${_connected_daemon:-unknown}"

    if [[ "${_local_daemon}" != "running" ]]; then
        PASEO_LAST_HEALTH_ERROR="${PASEO_LAST_HEALTH_SUMMARY}"
        return 1
    fi

    case "${_connected_daemon}" in
        reachable|auth_required) ;;
        auth_failed)
            PASEO_LAST_HEALTH_ERROR="${PASEO_LAST_HEALTH_SUMMARY}"
            return 1
            ;;
        *)
            PASEO_LAST_HEALTH_ERROR="${PASEO_LAST_HEALTH_SUMMARY}"
            return 1
            ;;
    esac

    if paseo_status_relay_disabled "${_status_json}"; then
        PASEO_LAST_HEALTH_ERROR="${PASEO_LAST_HEALTH_SUMMARY}, relay=disabled"
        return 1
    fi

    PASEO_LAST_HEALTH_ERROR=""
    return 0
}

wait_for_paseo_health() {
    local _attempt=1
    local _max_attempts="${PASEO_HEALTH_ATTEMPTS:-12}"
    local _interval="${PASEO_HEALTH_INTERVAL_SECONDS:-5}"

    while [[ "${_attempt}" -le "${_max_attempts}" ]]; do
        if paseo_check_status_once; then
            print_success "Paseo daemon health verified (${PASEO_LAST_HEALTH_SUMMARY})."
            return 0
        fi

        print_debug "Waiting for Paseo daemon health (${_attempt}/${_max_attempts}): ${PASEO_LAST_HEALTH_ERROR}"
        sleep "${_interval}"
        _attempt=$((_attempt + 1))
    done

    print_error "Paseo daemon health check failed after ${_max_attempts} attempts: ${PASEO_LAST_HEALTH_ERROR}"
    print_debug "Diagnostics: package=${PASEO_PACKAGE} version=${PASEO_PACKAGE_VERSION} node=${PASEO_VALIDATED_NODE:-unknown} user=$(whoami || true) home=${HOME} logs=${HOME}/.local/log/paseo-daemon"
    return 1
}

paseo_service_process_pids() {
    local _root_pid="$1"
    local _process_rows=""

    [[ -n "${_root_pid}" && "${_root_pid}" != "0" ]] || return 0
    printf '%s\n' "${_root_pid}"

    if ! _process_rows=$(ps -eo pid=,ppid= 2>/dev/null); then
        return 0
    fi

    printf '%s\n' "${_process_rows}" | awk -v root="${_root_pid}" '
        $1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ {
            _pid = $1
            _ppid = $2
            children[_ppid] = children[_ppid] " " _pid
        }
        END {
            if (root !~ /^[0-9]+$/) {
                exit
            }
            seen[root] = 1
            queue[1] = root
            head = 1
            tail = 1
            while (head <= tail) {
                _pid = queue[head++]
                split(children[_pid], child, " ")
                for (i in child) {
                    if (child[i] != "" && !seen[child[i]]) {
                        seen[child[i]] = 1
                        queue[++tail] = child[i]
                        print child[i]
                    }
                }
            }
        }
    ' || true
}

paseo_listener_audit() {
    local _pid="$1"
    local _pid_list=""
    local _listener_pid=""
    local _listener_rows=""
    local _listener_owner_pids=""
    local _bad_listener=""
    local _addr=""
    local _listeners=""
    local _listener_source=""

    if [[ -z "${_pid}" || "${_pid}" == "0" ]]; then
        print_error "Paseo service PID unavailable; cannot audit listeners for HEADLESS=1."
        return 1
    fi

    _pid_list=$(paseo_service_process_pids "${_pid}" | awk 'NF && !seen[$0]++' || true)
    if [[ -z "${_pid_list}" ]]; then
        _pid_list="${_pid}"
    fi

    if command -v ss &> /dev/null; then
        if ! _listener_source=$(ss -H -ltnp 2>/dev/null); then
            print_error "Failed to inspect Paseo listeners with ss."
            return 1
        fi
        if ! _listener_rows=$(printf '%s\n' "${_listener_source}" | awk -v pids="${_pid_list}" '
            BEGIN {
                split(pids, pid_values, /[[:space:]]+/)
                for (i in pid_values) {
                    if (pid_values[i] ~ /^[0-9]+$/) {
                        wanted[pid_values[i]] = 1
                    }
                }
            }
            {
                for (pid in wanted) {
                    if ($0 ~ "pid=" pid ",") {
                        print pid, $4
                    }
                }
            }
        '); then
            print_error "Failed to parse Paseo listeners from ss output."
            return 1
        fi
    elif command -v lsof &> /dev/null; then
        _listener_source=$(
            while IFS= read -r _listener_pid; do
                [[ -n "${_listener_pid}" ]] || continue
                lsof -nP -a -p "${_listener_pid}" -iTCP -sTCP:LISTEN 2>/dev/null || true
            done <<< "${_pid_list}"
        )
        if ! _listener_rows=$(printf '%s\n' "${_listener_source}" | awk '$1 != "COMMAND" && $2 ~ /^[0-9]+$/ && $9 != "" {print $2, $9}'); then
            print_error "Failed to parse Paseo listeners from lsof output."
            return 1
        fi
    else
        print_error "No listener-audit tool found (ss/lsof); cannot verify Paseo is loopback-only."
        return 1
    fi

    # Paseo-launched agents remain in the service process tree and may open their
    # own listeners. Audit only the process that owns Paseo's managed endpoint.
    _listener_owner_pids=$(printf '%s\n' "${_listener_rows}" | awk -v target="${PASEO_LISTEN_TARGET}" '$2 == target && !seen[$1]++ {print $1}' || true)
    if [[ -z "${_listener_owner_pids}" ]]; then
        print_error "The managed Paseo service does not own its expected loopback listener (${PASEO_LISTEN_TARGET}); refusing to let another daemon satisfy health checks."
        return 1
    fi

    _listeners=$(printf '%s\n' "${_listener_rows}" | awk -v pids="${_listener_owner_pids}" '
        BEGIN {
            split(pids, pid_values, /[[:space:]]+/)
            for (i in pid_values) {
                if (pid_values[i] ~ /^[0-9]+$/) {
                    wanted[pid_values[i]] = 1
                }
            }
        }
        $1 in wanted {print $2}
    ' || true)

    while IFS= read -r _addr; do
        [[ -n "${_addr}" ]] || continue
        case "${_addr}" in
            127.*|"[::1]:"*|"::1:"*|localhost:*|"[::ffff:127."*) ;;
            *)
                _bad_listener="${_addr}"
                break
                ;;
        esac
    done <<< "${_listeners}"

    if [[ -n "${_bad_listener}" ]]; then
        print_error "Paseo daemon appears to listen on a non-loopback address (${_bad_listener}); refusing HEADLESS=1 setup."
        return 1
    fi

    print_debug "Paseo listener audit passed."
}

paseo_listener_target_available() {
    local _managed_pid="${1:-}"
    local _listener_source=""
    local _occupied=""

    if [[ -z "${PASEO_LISTEN_TARGET}" ]]; then
        print_error "Paseo listener target is unavailable before service start."
        return 1
    fi

    if command -v ss &> /dev/null; then
        if ! _listener_source=$(ss -H -ltn 2>/dev/null); then
            print_error "Failed to inspect the configured Paseo listener before service start."
            return 1
        fi
        _occupied=$(printf '%s\n' "${_listener_source}" | awk -v target="${PASEO_LISTEN_TARGET}" '$4 == target {print; exit}' || true)
    elif command -v lsof &> /dev/null; then
        _listener_source=$(lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null || true)
        _occupied=$(printf '%s\n' "${_listener_source}" | awk -v target="${PASEO_LISTEN_TARGET}" '$1 != "COMMAND" && $9 == target {print; exit}' || true)
    else
        print_error "No listener-audit tool found (ss/lsof); cannot check the configured Paseo listener before service start."
        return 1
    fi

    if [[ -z "${_occupied}" ]]; then
        return 0
    fi
    if [[ -n "${_managed_pid}" && "${_managed_pid}" != "0" ]] && paseo_listener_audit "${_managed_pid}" >/dev/null 2>&1; then
        return 0
    fi

    print_error "Paseo listener target ${PASEO_LISTEN_TARGET} is already in use by another process. Set daemon.listen to an unused IPv4 loopback port and rerun setup."
    return 1
}

paseo_service_owner_check() {
    local _pid="$1"
    local _expected_user=""
    local _actual_user=""

    if [[ -z "${_pid}" || "${_pid}" == "0" ]]; then
        print_error "Paseo service PID unavailable; cannot verify managed service ownership."
        return 1
    fi

    _expected_user=$(whoami || true)
    _actual_user=$(ps -o user= -p "${_pid}" 2>/dev/null | awk '{print $1}' || true)
    if [[ -z "${_actual_user}" ]]; then
        print_error "Could not verify owner for Paseo service PID ${_pid}."
        return 1
    fi
    if [[ "${_actual_user}" != "${_expected_user}" ]]; then
        print_error "Paseo daemon is running as ${_actual_user}, expected ${_expected_user}."
        return 1
    fi
}

paseo_is_wsl_environment() {
    grep -qiE '(microsoft|wsl)' /proc/version /proc/sys/kernel/osrelease 2>/dev/null || [[ -n "${WSL_DISTRO_NAME:-}" ]] || [[ -f /proc/sys/fs/binfmt_misc/WSLInterop ]]
}

paseo_is_container_environment() {
    [[ -f /.dockerenv ]] || { command -v systemd-detect-virt &> /dev/null && systemd-detect-virt --container --quiet 2>/dev/null; }
}

paseo_headless_platform_gate() {
    if [[ "${HEADLESS:-}" != "1" ]]; then
        return 0
    fi

    if [[ "$(uname -s 2>/dev/null || true)" != "Linux" ]]; then
        return 0
    fi

    if paseo_is_wsl_environment; then
        print_error "HEADLESS=1 Paseo daemon setup is unsupported in WSL because WSL cannot guarantee startup after Windows host reboot without login."
        return 1
    fi

    if paseo_is_container_environment; then
        print_error "HEADLESS=1 Paseo daemon setup requires a booting native Linux user manager; container environments are unsupported."
        return 1
    fi
}

paseo_native_linux_preflight() {
    local _user=""

    if [[ "$(uname -s 2>/dev/null || true)" != "Linux" ]]; then
        print_error "Native Linux Paseo headless service setup requires Linux."
        return 1
    fi

    if paseo_is_wsl_environment; then
        print_error "HEADLESS=1 Paseo daemon setup is unsupported in WSL because WSL cannot guarantee startup after Windows host reboot without login."
        return 1
    fi

    if paseo_is_container_environment; then
        print_error "HEADLESS=1 Paseo daemon setup requires a booting native Linux user manager; container environments are unsupported."
        return 1
    fi

    _user=$(whoami || true)
    if [[ -z "${_user}" || -z "${HOME}" || ! -d "${HOME}" ]]; then
        print_error "Cannot resolve target user/home for Paseo daemon setup."
        return 1
    fi

    if ! command -v loginctl &> /dev/null; then
        print_error "loginctl is required to enable lingering for the Paseo user service."
        return 1
    fi

    if ! command -v systemctl &> /dev/null; then
        print_error "systemctl is required to manage the Paseo user service."
        return 1
    fi

    if ! loginctl show-user "${_user}" >/dev/null 2>&1; then
        print_error "loginctl cannot inspect user ${_user}; cannot guarantee no-login Paseo startup."
        return 1
    fi

    if ! paseo_user_lingering_enabled "${_user}" && ! can_sudo; then
        print_error "sudo access is required to enable lingering for HEADLESS=1 Paseo daemon setup."
        return 1
    fi

    if ! paseo_systemctl_user show-environment >/dev/null 2>&1; then
        print_error "The systemd user manager is unavailable; cannot configure the Paseo user service safely."
        return 1
    fi
}

paseo_user_lingering_enabled() {
    local _user="$1"

    { loginctl show-user "${_user}" --property=Linger 2>/dev/null || true; } | grep -q 'Linger=yes'
}

paseo_enable_lingering_strict() {
    local _user=""

    _user=$(whoami || true)
    if paseo_user_lingering_enabled "${_user}"; then
        print_debug "User lingering already enabled for Paseo daemon."
        return 0
    fi

    if ! can_sudo; then
        print_error "sudo access is required to enable lingering for HEADLESS=1 Paseo daemon setup."
        return 1
    fi

    print_message "Enabling lingering for Paseo systemd user service..."
    if ! sudo loginctl enable-linger "${_user}"; then
        print_error "Failed to enable lingering for ${_user}."
        return 1
    fi

    if ! paseo_user_lingering_enabled "${_user}"; then
        print_error "Lingering verification failed for ${_user}."
        return 1
    fi
    print_success "User lingering enabled for Paseo daemon."
}

paseo_existing_managed_service_check() {
    local _service_file="${HOME}/.config/systemd/user/${PASEO_SERVICE_NAME}"
    local _wrapper="${HOME}/.local/bin/paseo-daemon-start"

    if [[ -f "${_service_file}" ]] && ! grep -qF "${PASEO_MANAGED_MARKER}" "${_service_file}"; then
        print_error "Existing unmanaged ${_service_file} found. Remove or rename it before rerunning HEADLESS=1 setup."
        return 1
    fi

    if [[ -f "${_wrapper}" ]] && ! grep -qF "${PASEO_MANAGED_MARKER}" "${_wrapper}"; then
        print_error "Existing unmanaged ${_wrapper} found. Remove or rename it before rerunning HEADLESS=1 setup."
        return 1
    fi
}

paseo_linux_service_pid() {
    paseo_systemctl_user show "${PASEO_SERVICE_NAME}" --property=MainPID --value 2>/dev/null | head -n 1 || true
}

install_paseo_systemd_user_service() {
    local _service_dir="${HOME}/.config/systemd/user"
    local _service_file="${_service_dir}/${PASEO_SERVICE_NAME}"
    local _service_path=""
    local _tmp=""

    _service_path=$(paseo_effective_service_path)
    PASEO_SYSTEMD_SERVICE_CHANGED=0
    mkdir -p "${_service_dir}"
    chmod 700 "${_service_dir}"

    if [[ -f "${_service_file}" ]] && ! grep -qF "${PASEO_MANAGED_MARKER}" "${_service_file}"; then
        print_error "Existing unmanaged ${_service_file} found. Remove or rename it before rerunning HEADLESS=1 setup."
        return 1
    fi

    _tmp=$(mktemp)
    if ! cat > "${_tmp}" << EOF
# ${PASEO_MANAGED_MARKER}
[Unit]
Description=Paseo headless daemon
Documentation=https://www.getpaseo.com/

[Service]
Type=simple
ExecStart=${HOME}/.local/bin/paseo-daemon-start
WorkingDirectory=${HOME}
Environment=HOME=${HOME}
Environment=PATH=${_service_path}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF
    then
        rm -f "${_tmp}"
        print_error "Failed to write Paseo systemd user service."
        return 1
    fi
    if ! chmod 600 "${_tmp}"; then
        rm -f "${_tmp}"
        print_error "Failed to install Paseo systemd user service."
        return 1
    fi

    if [[ -f "${_service_file}" ]] && cmp -s "${_tmp}" "${_service_file}"; then
        rm -f "${_tmp}"
        if ! chmod 600 "${_service_file}"; then
            print_error "Failed to secure Paseo systemd user service."
            return 1
        fi
        print_debug "Paseo systemd user service definition is unchanged."
    else
        if ! mv "${_tmp}" "${_service_file}"; then
            rm -f "${_tmp}"
            print_error "Failed to install Paseo systemd user service."
            return 1
        fi
        PASEO_SYSTEMD_SERVICE_CHANGED=1
    fi

    paseo_enable_lingering_strict || return 1

    if [[ "${PASEO_SYSTEMD_SERVICE_CHANGED}" == "1" ]]; then
        if ! paseo_systemctl_user daemon-reload; then
            print_error "Failed to reload systemd user units for Paseo."
            return 1
        fi
    fi

    if ! paseo_systemctl_user enable "${PASEO_SERVICE_NAME}"; then
        print_error "Failed to enable ${PASEO_SERVICE_NAME}."
        return 1
    fi

    if ! paseo_managed_service_is_active; then
        PASEO_MANAGED_SERVICE_TOUCHED=1
        if ! paseo_systemctl_user start "${PASEO_SERVICE_NAME}"; then
            print_debug "Initial start of ${PASEO_SERVICE_NAME} reported an error; attempting recovery."
        fi
    elif [[ "${PASEO_PACKAGE_CHANGED}" == "1" || "${PASEO_DAEMON_WRAPPER_CHANGED}" == "1" || "${PASEO_SYSTEMD_SERVICE_CHANGED}" == "1" ]]; then
        PASEO_MANAGED_SERVICE_TOUCHED=1
        if ! paseo_systemctl_user reset-failed "${PASEO_SERVICE_NAME}" >/dev/null 2>&1; then
            print_debug "reset-failed reported an error (unit may not be failed); continuing."
        fi
        # Kill any leftover orphan processes in the Paseo cgroup before restarting;
        # otherwise systemd can refuse the new start (exit-code 219/cgroup).
        paseo_systemctl_user kill "${PASEO_SERVICE_NAME}" --kill-whom=all >/dev/null 2>&1 || true
        sleep 1
        if ! paseo_systemctl_user restart "${PASEO_SERVICE_NAME}"; then
            print_debug "Initial restart of ${PASEO_SERVICE_NAME} reported an error; attempting recovery."
        fi
    else
        print_debug "Paseo package, wrapper, and service definition are unchanged; leaving the active daemon running."
    fi

    if ! paseo_systemctl_user is-enabled "${PASEO_SERVICE_NAME}" >/dev/null 2>&1; then
        print_error "${PASEO_SERVICE_NAME} is not enabled after setup."
        print_debug "Inspect privately with: systemctl --user is-enabled ${PASEO_SERVICE_NAME}"
        return 1
    fi

    if ! paseo_managed_service_is_active_strict; then
        # Give the service one last chance: reset failed state, sweep orphan
        # processes, and start it before declaring failure.
        paseo_systemctl_user reset-failed "${PASEO_SERVICE_NAME}" >/dev/null 2>&1 || true
        paseo_systemctl_user kill "${PASEO_SERVICE_NAME}" --kill-whom=all >/dev/null 2>&1 || true
        sleep 1
        paseo_systemctl_user start "${PASEO_SERVICE_NAME}" >/dev/null 2>&1 || true
        PASEO_MANAGED_SERVICE_TOUCHED=1
    fi

    if ! paseo_managed_service_is_active_strict; then
        print_error "${PASEO_SERVICE_NAME} is not active after setup."
        print_debug "State captured from systemd:"
        paseo_systemctl_user status "${PASEO_SERVICE_NAME}" --no-pager 2>&1 | head -10 | sed 's/^/  /' || true
        print_debug "Inspect privately with: journalctl --user -u ${PASEO_SERVICE_NAME} --no-pager"
        return 1
    fi

    print_success "Paseo systemd user service enabled and active."
}

cleanup_paseo_managed_service() {
    local _platform="$1"

    if [[ "${PASEO_MANAGED_SERVICE_TOUCHED}" != "1" ]]; then
        return 0
    fi

    case "${_platform}" in
        Linux)
            paseo_systemctl_user stop "${PASEO_SERVICE_NAME}" >/dev/null 2>&1 || true
            ;;
        *) ;;
    esac
    print_debug "Stopped managed Paseo service after failed verification; managed files and logs remain for inspection."
}

setup_headless_paseo_daemon() {
    local _platform=""
    local _service_pid=""

    if [[ "${HEADLESS:-}" != "1" ]]; then
        return 0
    fi

    _platform=$(uname -s 2>/dev/null || true)
    if [[ "${_platform}" != "Linux" ]]; then
        print_error "HEADLESS=1 Paseo daemon setup is unsupported on ${_platform:-this platform}."
        return 1
    fi
    paseo_native_linux_preflight || return 1
    paseo_existing_managed_service_check || return 1

    install_paseo_cli || return 1
    paseo_resolve_listen_target || return 1
    stop_existing_paseo_daemon || return 1
    _service_pid=$(paseo_linux_service_pid || true)
    paseo_listener_target_available "${_service_pid}" || return 1
    write_paseo_daemon_wrapper || return 1

    if ! install_paseo_systemd_user_service; then
        cleanup_paseo_managed_service "${_platform}"
        return 1
    fi
    _service_pid=$(paseo_linux_service_pid || true)

    if ! paseo_service_owner_check "${_service_pid}" || ! wait_for_paseo_health || ! paseo_listener_audit "${_service_pid}"; then
        cleanup_paseo_managed_service "${_platform}"
        return 1
    fi

    print_success "Headless Paseo daemon is service-managed and locally reachable. Use Paseo's normal pairing flow later if needed."
}

# Remove Pi subagents extension
remove_pi_subagents() {
    local _had_failure=0
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
                _had_failure=1
            fi
        done
        return "${_had_failure}"
    fi

    # Fallback when the pi CLI is unavailable: strip both package sources
    # directly from settings.json.
    if [[ ! -f "${_settings_file}" ]]; then
        print_debug "Pi settings not found; Pi subagents extension not installed."
        return 0
    fi

    if ! command -v jq &> /dev/null; then
        print_warning "jq not found. Cannot remove Pi subagents from Pi settings."
        return 1
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
        mv "${_tmp}" "${_settings_file}" || return 1
        print_success "Removed Pi subagents extension from Pi settings."
    else
        rm -f "${_tmp}"
        print_warning "Failed to update Pi settings at ${_settings_file}."
        return 1
    fi
    return 0
}

# Pi prose retirement. Keep this block identical in the Bash setup scripts.
remove_pi_prose() {
    local _default_dir="${HOME}/.pi/agent"
    local _active_dir="${PI_CODING_AGENT_DIR:-${_default_dir}}"
    local _result=""
    if [[ ! -e "${_default_dir}" && ! -L "${_default_dir}" && ! -e "${_active_dir}" && ! -L "${_active_dir}" ]]; then
        print_debug "No global Pi profiles; pi-prose is absent."
        return 0
    fi
    if ! command -v node &> /dev/null; then
        print_error "Node.js is required to retire pi-prose from existing Pi profiles."
        return 1
    fi
    if ! _result=$(node --input-type=commonjs - "${HOME}" "${_active_dir}" <<'PI_PROSE_RETIREMENT_JS'
// BEGIN PI_PROSE_RETIREMENT
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
class RetirementError extends Error {}
const fail = message => { throw new RetirementError(message); };
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const own = (value, key) => Object.prototype.hasOwnProperty.call(value, key);
const prose = source => typeof source === 'string' && (source === 'npm:pi-prose' || source.startsWith('npm:pi-prose@'));
const packageKey = key => key === 'pi-prose' || key.startsWith('pi-prose@');
function info(file) {
    try { return fs.lstatSync(file); }
    catch (error) { if (error.code === 'ENOENT') return null; throw error; }
}
function absolute(value) {
    if (!value || !path.isAbsolute(value) || value.split(/[\\/]/).some(part => part === '..' || part === '.')) {
        fail('Pi prose retirement requires absolute profile paths without dot segments.');
    }
    return path.resolve(value);
}
function readJson(file) {
    const stat = info(file);
    if (!stat) return null;
    if (!stat.isFile() || stat.isSymbolicLink() || stat.nlink > 1) fail('Pi prose metadata must be regular, unlinked JSON files.');
    const text = fs.readFileSync(file, 'utf8');
    let value;
    try { value = JSON.parse(text.replace(/^\uFEFF/, '')); }
    catch { fail('Invalid JSON in Pi prose retirement metadata; leaving it unchanged.'); }
    if (!object(value)) fail('Pi prose retirement metadata must contain a JSON object.');
    return { file, stat, text, value };
}
function stripDependencies(value) {
    let changed = false;
    for (const field of ['dependencies', 'devDependencies', 'optionalDependencies', 'peerDependencies', 'peerDependenciesMeta', 'overrides']) {
        if (!own(value, field)) continue;
        if (!object(value[field])) fail('Invalid dependency map in Pi prose retirement metadata.');
        for (const key of Object.keys(value[field])) {
            if (key === 'pi-prose' || (field === 'overrides' && packageKey(key))) {
                delete value[field][key];
                changed = true;
            }
        }
    }
    return changed;
}
try {
    // HOME is the trusted account boundary. Resolve only HOME, not Pi-owned paths,
    // so OS home aliases work without following linked profiles or package stores.
    const logicalHome = absolute(process.argv[2]);
    const home = fs.realpathSync(logicalHome);
    if (!fs.statSync(home).isDirectory()) fail('Pi prose retirement requires a home directory.');
    const key = value => process.platform === 'win32' ? value.toLowerCase() : value;
    const within = (file, base) => key(file) === key(base) || key(file).startsWith(key(base + path.sep));
    const normalize = value => {
        const file = absolute(value);
        return within(file, logicalHome) ? path.join(home, path.relative(logicalHome, file)) : file;
    };
    const directories = [...new Map([path.join(home, '.pi', 'agent'), process.argv[3] || path.join(home, '.pi', 'agent')]
        .map(normalize).map(dir => [key(dir), dir])).values()];
    function safeDirectory(dir) {
        const stop = within(dir, home) ? home : path.parse(dir).root;
        for (let current = dir; current !== stop; current = path.dirname(current)) {
            const stat = info(current);
            if (stat && (!stat.isDirectory() || stat.isSymbolicLink())) fail('Linked or non-directory Pi profile paths are not changed.');
        }
    }
    const writes = [];
    const removals = [];
    for (const dir of directories) {
        if (dir === path.parse(dir).root) fail('The filesystem root cannot be a Pi profile.');
        safeDirectory(dir);
        const npm = path.join(dir, 'npm');
        const modules = path.join(npm, 'node_modules');
        safeDirectory(modules);
        const settings = readJson(path.join(dir, 'settings.json'));
        if (settings && own(settings.value, 'packages')) {
            if (!Array.isArray(settings.value.packages)) fail('Pi settings packages must be an array.');
            if (settings.value.packages.some(entry => typeof entry !== 'string' && (!object(entry) || typeof entry.source !== 'string'))) {
                fail('Invalid package declaration in Pi settings; leaving it unchanged.');
            }
            const filtered = settings.value.packages.filter(entry => !prose(typeof entry === 'string' ? entry : entry.source));
            if (filtered.length !== settings.value.packages.length) {
                settings.value.packages = filtered;
                writes.push(settings);
            }
        }
        const manifest = readJson(path.join(npm, 'package.json'));
        if (manifest && stripDependencies(manifest.value)) writes.push(manifest);
        for (const file of [path.join(npm, 'package-lock.json'), path.join(npm, 'npm-shrinkwrap.json'), path.join(modules, '.package-lock.json')]) {
            const lock = readJson(file);
            if (!lock) continue;
            const value = lock.value;
            if (![1, 2, 3].includes(value.lockfileVersion)) fail('Unsupported Pi npm lockfile version; leaving it unchanged.');
            let changed = stripDependencies(value);
            if (own(value, 'packages')) {
                if (!object(value.packages)) fail('Invalid packages map in Pi npm lockfile.');
                if (own(value.packages, '')) {
                    if (!object(value.packages[''])) fail('Invalid root record in Pi npm lockfile.');
                    changed = stripDependencies(value.packages['']) || changed;
                }
                for (const name of Object.keys(value.packages)) {
                    if (name === 'node_modules/pi-prose' || name.startsWith('node_modules/pi-prose/')) {
                        delete value.packages[name];
                        changed = true;
                    }
                }
            }
            if (changed) writes.push(lock);
        }
        const target = path.join(modules, 'pi-prose');
        const stat = info(target);
        if (stat) {
            if (directories.some(profile => within(profile, target))) fail('A Pi profile overlaps the retired package directory; manual review is required.');
            // A linked package is unlinked, never followed into a user's source tree.
            if (!stat.isSymbolicLink()) {
                if (!stat.isDirectory()) fail('The installed pi-prose path is not a package directory.');
                const installed = readJson(path.join(target, 'package.json'));
                if (!installed || installed.value.name !== 'pi-prose') fail('Cannot verify the installed pi-prose package; leaving it unchanged.');
            }
            removals.push({ file: target, stat });
        }
    }
    // Preflight every profile before changing any of them. Remove declarations
    // before package files, without running npm, Pi, or lifecycle scripts.
    for (const record of writes) {
        safeDirectory(path.dirname(record.file));
        const current = info(record.file);
        if (!current || current.isSymbolicLink() || current.ino !== record.stat.ino || current.dev !== record.stat.dev ||
            fs.readFileSync(record.file, 'utf8') !== record.text) fail('Pi metadata changed during retirement; rerun setup after reviewing it.');
        const temporary = record.file + '.retire-' + crypto.randomBytes(12).toString('hex');
        try {
            const bom = record.text.startsWith('\uFEFF') ? '\uFEFF' : '';
            fs.writeFileSync(temporary, bom + JSON.stringify(record.value, null, 2) + '\n', { flag: 'wx', mode: record.stat.mode & 0o777 });
            fs.renameSync(temporary, record.file);
        } finally {
            if (info(temporary)) fs.unlinkSync(temporary);
        }
    }
    for (const record of removals) {
        safeDirectory(path.dirname(record.file));
        const current = info(record.file);
        if (!current || current.ino !== record.stat.ino || current.dev !== record.stat.dev ||
            current.isSymbolicLink() !== record.stat.isSymbolicLink()) fail('The pi-prose package changed during retirement; review it before retrying.');
        if (current.isSymbolicLink()) fs.unlinkSync(record.file);
        else fs.rmSync(record.file, { recursive: true });
        if (info(record.file)) fail('The pi-prose package still exists after retirement.');
    }
    console.log(writes.length || removals.length ? 'removed' : 'absent');
} catch (error) {
    console.error(error instanceof RetirementError ? error.message : 'Pi prose retirement failed during a filesystem operation; check permissions and retry.');
    process.exitCode = 1;
}
// END PI_PROSE_RETIREMENT
PI_PROSE_RETIREMENT_JS
    ); then
        print_error "Required pi-prose retirement failed. No npm security settings were changed."
        return 1
    fi
    case "${_result}" in
        removed) print_success "Retired pi-prose from global Pi profiles; custom prose files preserved." ;;
        absent) print_debug "pi-prose is absent from global Pi profiles." ;;
        *) print_error "Pi prose retirement did not return a valid result."; return 1 ;;
    esac
}
# End Pi prose retirement.

# Remove retired Pi RPIV packages (ask-user-question and todo)
remove_pi_rpiv_packages() {
    local _had_failure=0
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
                _had_failure=1
            fi
        done
        return "${_had_failure}"
    fi

    # Fallback when the pi CLI is unavailable: strip both package sources
    # directly from settings.json.
    if [[ ! -f "${_settings_file}" ]]; then
        print_debug "Pi settings not found; Pi RPIV packages not installed."
        return 0
    fi

    if ! command -v jq &> /dev/null; then
        print_warning "jq not found. Cannot remove Pi RPIV packages from Pi settings."
        return 1
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
        mv "${_tmp}" "${_settings_file}" || return 1
        print_success "Removed Pi RPIV packages from Pi settings."
    else
        rm -f "${_tmp}"
        print_warning "Failed to update Pi settings at ${_settings_file}."
        return 1
    fi
    return 0
}

# Repair only the active profile's managed adapter metadata; npm owns lockfiles.
prepare_pi_mcp_adapter() {
    local _agent_dir="${PI_CODING_AGENT_DIR:-${HOME}/.pi/agent}"
    if ! command -v node &> /dev/null; then
        print_warning "Node.js not found. Cannot safely prepare Pi package metadata."
        return 1
    fi
    node - "${_agent_dir}" "${BAN_PI_MCP_ADAPTER:-0}" "${1:-prepare}" <<'PI_ADAPTER_POLICY_JS'
    // Only the active profile's managed adapter records are changed. npm owns locks.
    const fs = require('node:fs');
    const path = require('node:path');
    const [agentDir, disabled, mode] = process.argv.slice(2);
    const version = '2.32.1';
    const source = `npm:pi-mcp-adapter@${version}`;
    const isObject = value => value !== null && typeof value === 'object' && !Array.isArray(value);
    const isAdapter = value => typeof value === 'string' && /^npm:pi-mcp-adapter(?:@[^\s]+)?$/.test(value);
    function stat(file) {
        try { return fs.lstatSync(file); }
        catch (error) { if (error.code === 'ENOENT') return null; throw error; }
    }
    function read(file) {
        const info = stat(file);
        if (!info) return { file, data: null };
        if (!info.isFile() || info.isSymbolicLink() || info.nlink !== 1) throw new Error('unsafe file');
        const original = fs.readFileSync(file, 'utf8');
        const data = JSON.parse(original.replace(/^\uFEFF/, ''));
        if (!isObject(data)) throw new Error('invalid object');
        return { file, data, original, info };
    }
    try {
        if (!['prepare', 'verify'].includes(mode)) throw new Error('invalid mode');
        const store = path.join(agentDir, 'npm');
        // Reject linked managed directories, but allow platform aliases above agentDir.
        for (const directory of [agentDir, store, path.join(store, 'node_modules'), path.join(store, 'node_modules/pi-mcp-adapter')]) {
            const info = stat(directory);
            if (info && (!info.isDirectory() || info.isSymbolicLink())) throw new Error('unsafe directory');
        }
        const settings = read(path.join(agentDir, 'settings.json'));
        const manifest = read(path.join(store, 'package.json'));
        const installed = read(path.join(store, 'node_modules/pi-mcp-adapter/package.json'));
        read(path.join(store, 'package-lock.json'));
        read(path.join(store, 'node_modules/.package-lock.json'));
        if (settings.data && 'packages' in settings.data && !Array.isArray(settings.data.packages)) throw new Error('invalid packages');
        const packages = settings.data?.packages ?? [];
        if (packages.some(entry => typeof entry !== 'string' && (!isObject(entry) || typeof entry.source !== 'string'))) throw new Error('invalid package');
        const adapters = packages.filter(entry => isAdapter(typeof entry === 'string' ? entry : entry.source));
        for (const entry of adapters) {
            if (typeof entry === 'string') continue;
            if (('extensions' in entry && (!Array.isArray(entry.extensions) || entry.extensions.some(item => typeof item !== 'string'))) ||
                ('autoload' in entry && typeof entry.autoload !== 'boolean')) throw new Error('adapter activation');
        }
        for (const field of ['dependencies', 'devDependencies', 'optionalDependencies']) {
            if (manifest.data && field in manifest.data && !isObject(manifest.data[field])) throw new Error('invalid dependencies');
        }
        if (mode === 'verify') {
            if (disabled !== '1' && (installed.data?.name !== 'pi-mcp-adapter' || installed.data?.version !== version ||
                manifest.data?.dependencies?.['pi-mcp-adapter'] !== version ||
                !packages.some(entry => (typeof entry === 'string' ? entry : entry.source) === source))) throw new Error('unverified adapter');
            if (disabled !== '1') {
                // 2.32.1 declares one extension. Do not execute it during live setup:
                // extension startup can connect MCP servers or run configured commands.
                const resources = installed.data.pi?.extensions;
                const entryPoint = stat(path.join(store, 'node_modules/pi-mcp-adapter/index.ts'));
                if (!Array.isArray(resources) || resources.length !== 1 || resources[0] !== './index.ts' ||
                    !entryPoint?.isFile() || entryPoint.isSymbolicLink() || entryPoint.nlink !== 1 || entryPoint.size === 0) {
                    throw new Error('unverified adapter resource');
                }
                if (adapters.length !== 1) throw new Error('adapter activation');
                const entry = adapters[0];
                if (typeof entry !== 'string') {
                    // Accept Pi's defaults or explicit entry-point selections.
                    // A force-include overrides globs, but never a force-exclude.
                    // Preserve other complex filters without guessing their meaning.
                    const filters = entry.extensions;
                    const exact = value => {
                        const normalized = value.replaceAll('\\', '/').replace(/^\.\//, '');
                        return normalized === 'index.ts' || normalized ===
                            path.resolve(store, 'node_modules/pi-mcp-adapter/index.ts').replaceAll('\\', '/');
                    };
                    let enabled = filters === undefined && entry.autoload !== false;
                    if (filters?.length) {
                        const last = filters[filters.length - 1];
                        enabled = entry.autoload === false
                            ? last === 'index.ts' || (last.startsWith('+') && exact(last.slice(1)))
                            : (filters.length === 1 && filters[0] === 'index.ts' ||
                                filters.some(item => item.startsWith('+') && exact(item.slice(1)))) &&
                                !filters.some(item => item.startsWith('-') && exact(item.slice(1)));
                    }
                    if (!enabled) throw new Error('adapter activation');
                }
            }
        } else {
            const changes = [];
            if (settings.data && 'packages' in settings.data) {
                const next = packages.flatMap(entry => {
                    const current = typeof entry === 'string' ? entry : entry.source;
                    if (!isAdapter(current)) return [entry];
                    if (disabled === '1') return [];
                    return [typeof entry === 'string' ? source : { ...entry, source }];
                });
                if (JSON.stringify(next) !== JSON.stringify(packages)) {
                    settings.data.packages = next;
                    changes.push(settings);
                }
            }
            if (manifest.data) {
                let changed = false;
                for (const field of ['dependencies', 'devDependencies', 'optionalDependencies']) {
                    const deps = manifest.data[field];
                    if (!deps || !Object.hasOwn(deps, 'pi-mcp-adapter')) continue;
                    if (disabled === '1') { delete deps['pi-mcp-adapter']; changed = true; }
                    else if (deps['pi-mcp-adapter'] !== version) { deps['pi-mcp-adapter'] = version; changed = true; }
                }
                if (changed) changes.push(manifest);
            }
            // Validate every input before writing. Replace only changed files, atomically.
            for (const record of changes) {
                const temporary = `${record.file}.setup-${process.pid}.tmp`;
                let created = false;
                try {
                    const current = fs.lstatSync(record.file);
                    if (current.ino !== record.info.ino || current.dev !== record.info.dev || current.nlink !== 1 ||
                        current.isSymbolicLink() || fs.readFileSync(record.file, 'utf8') !== record.original) throw new Error('concurrent edit');
                    fs.writeFileSync(temporary, JSON.stringify(record.data, null, 2) + '\n', { flag: 'wx', mode: record.info.mode & 0o777 });
                    created = true;
                    fs.renameSync(temporary, record.file);
                } finally {
                    if (created && fs.existsSync(temporary)) fs.unlinkSync(temporary);
                }
            }
        }
    } catch (error) {
        if (error.message === 'adapter activation') {
            console.error('Pi MCP adapter enablement could not be verified. Existing filters were preserved. Use pi config in the active global profile to enable index.ts, or set BAN_PI_MCP_ADAPTER=1 for an intentional opt-out.');
        } else {
            console.error('Pi MCP adapter metadata/resource validation failed; inspect the active profile and reinstall the pinned package if needed. npm security settings were not changed.');
        }
        process.exitCode = 1;
    }
PI_ADAPTER_POLICY_JS
}

# Install/update Pi MCP adapter extension
setup_pi_mcp_adapter() {
    # 2.33.0 uses remote preview dependencies rejected by managed npm policy.
    local _package="npm:pi-mcp-adapter@2.32.1"
    local _output=""
    local _list_output=""

    prepare_pi_mcp_adapter || return 1
    if [[ "${BAN_PI_MCP_ADAPTER:-}" == "1" ]]; then
        print_success "Pi MCP adapter extension disabled in Pi settings."
        return 0
    fi

    if ! command -v npm &> /dev/null; then
        print_warning "npm not found. Cannot install Pi MCP adapter."
        print_debug "Install Node.js/npm, then run: pi install npm:pi-mcp-adapter@2.32.1"
        return 1
    fi

    if ! command -v pi &> /dev/null; then
        print_warning "Pi coding agent not found. Cannot install Pi MCP adapter."
        return 1
    fi

    print_message "Installing/updating Pi MCP adapter..."
    if _output=$(npm_config_save_exact=true pi install "${_package}" 2>&1); then
        if _list_output=$(pi list 2>&1) && grep -Fq "${_package}" <<< "${_list_output}"; then
            prepare_pi_mcp_adapter verify || return 1
            print_success "Pi MCP adapter installed/updated and enabled in the active global profile (restart Pi or /reload to load it)."
        else
            print_warning "Pi MCP adapter install completed, but package validation was inconclusive: ${_list_output}"
            return 1
        fi
    else
        print_warning "Failed to install Pi MCP adapter: ${_output}"
        return 1
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
        return 1
    fi

    if ! command -v pi &> /dev/null; then
        print_warning "Pi coding agent not found. Cannot install Pi Claude bridge."
        return 1
    fi

    print_message "Installing/updating Pi Claude bridge..."
    if _output=$(pi install "${_package}" 2>&1); then
        if _list_output=$(pi list 2>&1) && grep -q "npm:pi-claude-bridge" <<< "${_list_output}"; then
            print_success "Pi Claude bridge installed/updated."
        else
            print_warning "Pi Claude bridge install completed, but package validation was inconclusive: ${_list_output}"
            return 1
        fi
    else
        print_warning "Failed to install Pi Claude bridge: ${_output}"
        return 1
    fi
}

# Remove legacy Pi Ask User and install/update the Pi companion packages
setup_pi_companion_packages() {
    local _had_failure=0
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
        return 1
    fi

    if ! command -v pi &> /dev/null; then
        print_warning "Pi coding agent not found. Cannot install Pi companion packages."
        return 1
    fi

    if _list_output=$(pi list 2>&1); then
        if grep -Fq -- "${_legacy_package}" <<< "${_list_output}"; then
            print_message "Removing legacy Pi Ask User package..."
            if _output=$(pi remove "${_legacy_package}" 2>&1); then
                print_success "Legacy Pi Ask User package removed."
            else
                print_warning "Failed to remove legacy Pi Ask User package: ${_output}"
                _had_failure=1
            fi
        fi
    else
        print_warning "Cannot inspect Pi packages before legacy cleanup: ${_list_output}"
        _had_failure=1
    fi

    for _package in "${_packages[@]}"; do
        print_message "Installing/updating Pi package ${_package}..."
        if _output=$(pi install "${_package}" 2>&1); then
            if _list_output=$(pi list 2>&1) && grep -Fq -- "${_package}" <<< "${_list_output}"; then
                print_success "Pi package ${_package} installed/updated."
            else
                print_warning "Pi package ${_package} install completed, but validation was inconclusive: ${_list_output}"
                _had_failure=1
            fi
        else
            print_warning "Failed to install Pi package ${_package}: ${_output}"
            _had_failure=1
        fi
    done
    return "${_had_failure}"
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
        simple-english show-me pr-lens setup-matt-pocock-skills diagnosing-bugs tdd
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
        remove_pi_goal_autoresearch_settings || return 1
        print_success "Pi goal/autoresearch extensions disabled in Pi settings."
        return 0
    fi

    if ! command -v pi &> /dev/null; then
        print_warning "Pi coding agent not found. Cannot install Pi goal/autoresearch extensions."
        return 1
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

    if [[ "${_had_failure}" -eq 0 ]]; then
        if _list_output=$(pi list 2>&1) && grep -q "npm:pi-goal" <<< "${_list_output}" && grep -q "npm:pi-autoresearch" <<< "${_list_output}"; then
            print_success "Pi goal/autoresearch extensions are active."
        else
            print_warning "Pi goal/autoresearch install completed, but package validation was inconclusive: ${_list_output}"
            _had_failure=1
        fi
    fi

    configure_pi_autoresearch_shortcut || return 1
    return "${_had_failure}"
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

# Update Homebrew and upgrade packages
update_brew() {
    local update_status=0
    local upgrade_status=0
    local unpin_status=0

    print_message "Updating Homebrew..."
    brew update > /dev/null || update_status=$?
    # Pin tmux during upgrades to prevent killing existing sessions.
    brew pin tmux 2>/dev/null || true
    print_message "Upgrading outdated packages..."
    brew upgrade > /dev/null || upgrade_status=$?
    if brew unpin tmux 2>/dev/null; then
        :
    else
        unpin_status=$?
        print_warning "Could not unpin tmux; retry with: brew unpin tmux"
    fi

    if [[ "${update_status}" -eq 0 && "${upgrade_status}" -eq 0 && "${unpin_status}" -eq 0 && "${SETUP_BREW_TRUST_FAILURES}" -eq 0 ]]; then
        print_success "Homebrew updated."
        return 0
    fi

    print_error "Homebrew update/upgrade incomplete (update=${update_status}, upgrade=${upgrade_status}, unpin=${unpin_status}, trust=${SETUP_BREW_TRUST_FAILURES})."
    return 1
}

# Install packages via Homebrew (separate from core packages)
install_brew_packages() {
    if ! command -v brew &> /dev/null; then
        print_warning "Homebrew not available. Skipping brew packages."
        return 0
    fi

    local packages=("ffmpeg")
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
        if brew install "${to_install[@]}" > /dev/null; then
            print_success "Brew packages installed."
        else
            print_error "Failed to install required Brew packages: ${to_install[*]}"
            return 1
        fi
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
        stop_sudo_keepalive
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

# Warn if the machine has a reboot pending. Informational only; never affects
# the run's exit status. Bazzite is rpm-ostree based: system updates stage a
# new deployment that only becomes active after reboot. The Debian-style
# /var/run/reboot-required sentinel is checked as a fallback.
check_pending_reboot() {
    local staged_version=""

    if command -v rpm-ostree > /dev/null 2>&1; then
        local ostree_status
        ostree_status=$(rpm-ostree status --json 2> /dev/null) || ostree_status=""
        if [[ -n "${ostree_status}" ]]; then
            if command -v python3 > /dev/null 2>&1; then
                staged_version=$(printf '%s' "${ostree_status}" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for deployment in data.get("deployments", []):
    if deployment.get("staged"):
        print(deployment.get("version") or deployment.get("id") or "")
        break
' 2> /dev/null) || staged_version=""
            elif printf '%s' "${ostree_status}" | grep -qE '"staged"[[:space:]]*:[[:space:]]*true'; then
                staged_version="unknown"
            fi
        fi
    fi

    if [[ -n "${staged_version}" ]]; then
        print_warning "Machine reboot pending: staged system deployment ${staged_version} becomes active after restart."
        return 0
    fi

    if [[ -f /var/run/reboot-required ]]; then
        print_warning "Machine reboot pending. Restart this machine for applied updates to take effect."
        return 0
    fi

    print_debug "No reboot pending."
}

run_setup_tasks() {
    local _setup_had_errors=0
    local _pi_go_ready=0
    local PASEO_MUSE_DEFER_DAEMON_SETUP=0
    echo -e "\n${BOLD}🎮 Bazzite Development Environment Setup${NC}"
    echo -e "${GRAY}Version 111 | Last changed: Expose safe Go and Plain setup diagnostics"

    if ! acquire_setup_lock; then
        return 1
    fi

    # Create placeholder env file early (migrates old token files if present)
    create_env_local

    local _paseo_channel_override="${PASEO_CHANNEL:-}"
    local _paseo_setup_channel=""
    # Source env vars early so optional setup flags are available
    if [[ -f "${HOME}/.env.local" ]]; then
        set -a
        # shellcheck source=/dev/null
        source "${HOME}/.env.local"
        set +a
    fi

    if [[ -n "${_paseo_channel_override}" ]]; then
        PASEO_CHANNEL="${_paseo_channel_override}"
    fi
    _paseo_setup_channel=$(paseo_release_channel) || return 1
    paseo_headless_platform_gate || return 1

    print_section "User & System Setup"
    ensure_not_root || return 1
    verify_bazzite_system || return 1
    request_sudo_upfront || return 1
    set_fish_as_default_shell || return 1
    if command -v tailscale &> /dev/null; then
        setup_tailscale_ssh || return 1
    fi
    setup_dns64_for_ipv6_only

    print_section "Package Manager"
    ensure_brew_available || return 1
    install_core_packages || return 1
    install_secrets_manager || return 1
    install_gcloud_cli
    install_brew_packages || return 1
    setup_tailscale_ssh || return 1

    print_section "SSH Configuration"
    setup_ssh_key
    add_github_to_known_hosts || return 1

    if is_main_user; then
        print_section "Code Directory Setup"
        setup_code_directory
    fi

    print_section "Development Environment"
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
        if ! initialize_chezmoi; then
            _setup_had_errors=1
        fi
        # chezmoi init --apply overwrites ~/.ssh/config, removing the
        # github-dotfiles host alias needed for deploy key access.
        # Re-bootstrap it before any further chezmoi network operations.
        bootstrap_ssh_config
        configure_chezmoi_git
        if ! fix_chezmoi_remote_for_deploy_key; then
            _setup_had_errors=1
        fi
        update_chezmoi
        if ! chezmoi apply --force; then
            print_error "Failed to apply chezmoi dotfiles."
            _setup_had_errors=1
        fi
        # The apply may replace ~/.ssh/config; leave the deploy alias durable.
        bootstrap_ssh_config
    else
        print_warning "Skipping dotfiles management - no access to repository."
    fi

    print_section "Shell Configuration"
    install_tmux_plugins
    enable_user_lingering

    print_section "Development Tools"
    install_gitea_client || return 1
    install_bun || return 1
    configure_paseo_desktop_channel linux || return 1
    install_sfw
    install_claude_code
    install_gemini_cli
    install_codex_cli || return 1
    install_portless_cli
    install_ntn_cli
    remove_rtk_resources || return 1
    remove_attention_span_resources || return 1
    setup_matt_pocock_skills || return 1
    if ! remove_pi_prose; then
        print_warning "Skipping Pi package setup because prose retirement failed."
        _setup_had_errors=1
    elif install_pi_cli; then
        configure_pi_defaults
        remove_pi_synthetic_models
        seed_pi_zai_models
        if configure_pi_opencode_go; then
            _pi_go_ready=1
        else
            _setup_had_errors=1
        fi
        # Re-pin the adapter before any operation resolves the shared npm tree.
        if [[ "${_pi_go_ready}" -eq 1 ]] && prepare_pi_mcp_adapter; then
            setup_pi_mcp_adapter || _setup_had_errors=1
            remove_pi_subagents || _setup_had_errors=1
            remove_pi_rpiv_packages || _setup_had_errors=1
            setup_pi_claude_bridge || _setup_had_errors=1
            setup_pi_companion_packages || _setup_had_errors=1
            setup_pi_goal_autoresearch || _setup_had_errors=1
        else
            _setup_had_errors=1
        fi
    else
        # Do not run Pi package cleanup after a failed runtime preflight.
        if [[ "${PI_RUNTIME_PREFLIGHT_PASSED:-0}" -eq 1 ]] && prepare_pi_mcp_adapter; then
            if [[ "${BAN_PI_MCP_ADAPTER:-}" == "1" ]]; then
                setup_pi_mcp_adapter || _setup_had_errors=1
            fi
            remove_pi_subagents || _setup_had_errors=1
            remove_pi_rpiv_packages || _setup_had_errors=1
            if [[ "${BAN_PI_GOAL_AUTORESEARCH:-}" == "1" ]]; then
                setup_pi_goal_autoresearch || _setup_had_errors=1
            fi
        fi
        print_warning "Skipping Pi extension setup because Pi migration failed."
        _setup_had_errors=1
    fi

    if [[ "${_pi_go_ready}" -eq 1 ]]; then
        configure_paseo_muse_profile || _setup_had_errors=1
    else
        PASEO_MUSE_DEFER_DAEMON_SETUP=1
        print_warning "Muse profile and Paseo daemon setup deferred because Pi OpenCode Go setup is unavailable."
    fi
    if [[ "${PASEO_MUSE_DEFER_DAEMON_SETUP:-0}" != "1" ]]; then
        setup_headless_paseo_daemon || return 1
    fi

    setup_simple_english_skill || return 1
    setup_show_me_skill || return 1
    setup_pr_lens_skill || return 1
    configure_pi_skill_ownership || return 1

    verify_fish_development_tools || return 1
    remove_impeccable_resources

    remove_compound_engineering_resources

    install_paseo_plain || return 1

    print_section "Final Updates"
    update_brew || return 1

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
