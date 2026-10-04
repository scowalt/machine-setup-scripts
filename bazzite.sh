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

# BEGIN SETUP ENVIRONMENT POLICY
# Data-only environment policy. Embedded verbatim; no scheduling or runtime dependency.
# Version 2 | Last changed: Restore ordinary provisioning and retain literal dotenv parsing
setup_environment_failure() {
    print_error "Failed: $1. Environment file preserved."
    return 1
}

setup_trim() {
    SETUP_TRIMMED="${1#"${1%%[![:space:]]*}"}"
    SETUP_TRIMMED="${SETUP_TRIMMED%"${SETUP_TRIMMED##*[![:space:]]}"}"
}

setup_environment_value() {
    local value="$1" quote rest suffix index character previous=''
    quote="${value:0:1}"
    if [[ "${quote}" == '"' || "${quote}" == "'" ]]; then
        rest="${value:1}"
        [[ "${rest}" == *"${quote}"* ]] || return 1
        value="${rest%%"${quote}"*}"
        suffix="${rest#*"${quote}"}"
        if [[ -n "${suffix}" ]]; then
            [[ "${suffix}" == [[:space:]]* ]] || return 1
            setup_trim "${suffix}"
            [[ -z "${SETUP_TRIMMED}" || "${SETUP_TRIMMED}" == \#* ]] || return 1
        fi
    else
        for ((index=0; index<${#value}; index++)); do
            character="${value:index:1}"
            if [[ "${character}" == '#' && ( ${index} == 0 || "${previous}" == [[:space:]] ) ]]; then
                value="${value:0:index}"
                break
            fi
            previous="${character}"
        done
        setup_trim "${value}"; value="${SETUP_TRIMMED}"
        case "${value}" in *[[:space:]]*|*\"*|*\'*) return 1 ;; *) ;; esac
    fi
    # No escapes, interpolation, concatenation or multiline values. Backslashes
    # are literal data; quoted command-looking text is never evaluated.
    SETUP_ENV_VALUE="${value}"
}

# The documented dotenv format is data, not shell code. No eval/source or expansion.
# Unknown keys are ignored.
setup_load_environment() {
    local environment_file="${HOME}/.env.local" line key value
    [[ -e "${environment_file}" || -L "${environment_file}" ]] || return 0
    [[ -f "${environment_file}" && ! -L "${environment_file}" && -r "${environment_file}" ]] || { setup_environment_failure 'environment-file inspection'; return 1; }
    while IFS= read -r line || [[ -n "${line}" ]]; do
        setup_trim "${line%$'\r'}"; line="${SETUP_TRIMMED}"
        case "${line}" in ''|\#*) continue ;; *) ;; esac
        line="${line#export }"
        [[ "${line}" == *=* ]] || { setup_environment_failure 'unsupported environment-file statement'; return 1; }
        setup_trim "${line%%=*}"; key="${SETUP_TRIMMED}"
        [[ "${key}" =~ ^[A-Za-z_][A-Za-z_0-9]*$ ]] || { setup_environment_failure 'unsupported environment-file key'; return 1; }
        case "${key}" in
            HEADLESS|HEADLESS_PASSWORDLESS_SUDO|BB_SERVER|BB_DATA_DIR|BB_APP_NPM_PREFIX|WORK_MACHINE|MACHINE_TYPE|BAN_PI_MCP_ADAPTER|BAN_PI_GOAL_AUTORESEARCH|BAN_MATT_POCOCK_SKILLS|BAN_MATT_POCKOCK_SKILLS|GH_TOKEN|GH_TOKEN_SCOWALT|OP_SERVICE_ACCOUNT_TOKEN|ZAI_API_KEY|OPENCODE_GO_API_KEY|CLAUDE_CONFIG_DIR|CODEX_HOME|PI_CODING_AGENT_DIR) ;;
            *) continue ;;
        esac
        setup_trim "${line#*=}"; value="${SETUP_TRIMMED}"
        setup_environment_value "${value}" || { setup_environment_failure 'unsupported environment-file value'; return 1; }
        value="${SETUP_ENV_VALUE}"
        # BB_SERVER's explicit process value wins on Ubuntu, including 0.
        # WSL's exact-1 headless gate also checks the file before this loader.
        [[ "${key}" != BB_SERVER || "${SETUP_ENTRY_PLATFORM:-}" != ubuntu || -z "${BB_SERVER:-}" ]] || continue
        export "${key}=${value}"
    done < "${environment_file}"
}
# END SETUP ENVIRONMENT POLICY

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

# Personal machines retain Doppler; work machines have no replacement.
install_secrets_manager() {
    if [[ "${WORK_MACHINE:-}" != "1" ]]; then
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
        setup_load_environment || return 1
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
                if ! with_bb_dotfiles_umask bazzite chezmoi init --apply --force scowalt/dotfiles --ssh; then
                    print_error "Failed to initialize chezmoi with the verified SSH key."
                    return 1
                fi
                ;;
            token)
                if ! with_bb_dotfiles_umask bazzite chezmoi init --apply --force "https://github.com/scowalt/dotfiles.git"; then
                    print_error "Failed to initialize chezmoi with the verified GitHub token."
                    return 1
                fi
                ;;
            deploy)
                if ! with_bb_dotfiles_umask bazzite chezmoi init --apply --force "git@github-dotfiles:scowalt/dotfiles.git"; then
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
        if with_bb_dotfiles_umask bazzite chezmoi update --force > /dev/null; then
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
# BEGIN GENERATED OPENCODE CLI
# Version 9 | Last changed: Report bounded secret-safe evidence at real PATH discovery
install_opencode_cli() {
    local result status=0 machine kind native_shell cached_command recovery=0
    machine=$(uname -m) || return 1
    case "${machine}" in
        x86_64|arm64|aarch64) ;;
        *) print_warning 'OpenCode CLI: unsupported architecture; skipping without source builds.'; return 0 ;;
    esac
    kind=$(type -t opencode 2>/dev/null) || kind=''
    if [[ "${kind}" == function || "${kind}" == alias ]]; then
        print_error 'OpenCode CLI blocked (operation=setup-selection, reason=command-conflict).'
        print_error 'Preserving the shell function/alias without execution.'
        return 1
    fi
    if ! command -v node >/dev/null || ! env -u NODE_OPTIONS -u NODE_PATH node -e 'require("node:https"); require("node:zlib"); require("node:crypto"); if (Number(process.versions.node.split(".")[0]) < 22) process.exit(1)' </dev/null >/dev/null 2>&1; then
        print_error 'OpenCode CLI blocked (operation=prerequisites, reason=unverified).'
        print_error 'OpenCode CLI requires a working Node >=22 for verified native downloads/extraction (no npm execution).'
        return 1
    fi
    native_shell=$(type -P fish) || native_shell=''
    cached_command=$(hash -t opencode 2>/dev/null) || cached_command=''
    # Bash 3.2 misparses quoted heredocs inside $(); redirect the group instead.
    {
        result=$(
            set -o pipefail
            # Preserve extra records through command substitution. Translate NUL
            # to a rejected control byte rather than letting Bash erase it.
            SETUP_OPENCODE_SHELL="${native_shell}" SETUP_OPENCODE_HASHED="${cached_command}" env -u NODE_OPTIONS -u NODE_PATH node - 2>/dev/null |
                LC_ALL=C tr '\000' '\001' || status=$?
            printf '.'
            exit "${status}"
        ) || status=$?
    } <<'OPENCODE_CLI_JS'
// Embedded in all six entry points by tools/embed-opencode-cli.py.
// Version 8 | Last changed: Report bounded secret-safe evidence at real PATH discovery.
// Installation only: never import application code or inherit its environment.
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const https = require('node:https');
const crypto = require('node:crypto');
const zlib = require('node:zlib');
const cp = require('node:child_process');
const {isNativeError} = require('node:util').types;
const policyReasons = new Set(('archive archive-header archive-path archive-tail archive-truncated archive-type artifact-identity artifact-metadata ' +
    'brew-command brew-origin brew-path brew-snapshot-changed ' +
    'changed-copy changed-receipt custom-link custom-prefix custom-wrapper duplicate-metadata integrity libc metadata missing-binary outside-home package-conflict pinned receipt ' +
    'recovery-occupied relative-path release-metadata shadowed shadowed-newer unreachable unsafe-file unsafe-path unverified-copy url version version-probe windows-acl foreign-command command-conflict selection-unverified').split(' '));
const nativeCodes = new Set('EACCES EPERM ENOENT EIO EEXIST ENOTDIR ELOOP ENOSPC EROFS ETIMEDOUT ENOBUFS'.split(' '));
const diagnosticErrors = new WeakSet();
class PolicyError extends Error {
    constructor(reason, operation = reason.startsWith('brew-') ? 'homebrew-preflight' : 'installation') {
        super(reason); this.reason = reason; this.operation = operation; diagnosticErrors.add(this);
    }
}
// Only actual discovery can attach evidence; public exception properties (or
// objects with the same prototype) cannot forge it. Six decimal digits bound
// the wire record. Larger positions still fail, with the legacy generic reason.
const pathRefusals = new WeakMap();
function rejectPathComponent(index, kind) {
    const error = new PolicyError('relative-path');
    try {
        if (Number.isInteger(index) && index >= 1 && index <= 999999 && ['empty', 'relative'].includes(kind)) {
            pathRefusals.set(error, Object.freeze({index, kind}));
        }
    } catch { /* Diagnostic construction must not replace the original refusal. */ }
    throw error;
}
const fail = reason => { throw new PolicyError(reason); };
const nativeFailure = (operation, error) => nativeCodes.has(error?.code) ? new PolicyError(`native-${error.code}`, operation) : error;
const version = value => {
    if (typeof value !== 'string' || !/^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/.test(value)) fail('version');
    const parts = value.split('.').map(Number);
    if (parts.some(n => !Number.isSafeInteger(n))) fail('version');
    return parts;
};
const compare = (a, b) => {
    const aa = version(a), bb = version(b);
    for (let i = 0; i < 3; i++) if (aa[i] !== bb[i]) return Math.sign(aa[i] - bb[i]);
    return 0;
};
const samePath = (a, b) => process.platform === 'win32' ? a.toLowerCase() === b.toLowerCase() : a === b;
const digest = bytes => crypto.createHash('sha512').update(bytes).digest('base64');
function json(bytes) {
    const text = bytes.toString(); let value;
    try { value = JSON.parse(text); } catch { fail('metadata'); }
    // JSON.parse accepts duplicate keys; that can otherwise erase an explicit pin.
    const stack = [];
    for (const match of text.matchAll(/"(?:\\.|[^"\\])*"|[{}[\],:]|[^\s{}[\],:]+/g)) {
        const token = match[0];
        if (token === '{') stack.push({keys: new Set(), expectingKey: true});
        else if (token === '[') stack.push(null);
        else if (token === '}' || token === ']') stack.pop();
        else if (token === ',' && stack.at(-1)) stack.at(-1).expectingKey = true;
        else if (token.startsWith('"') && stack.at(-1)?.expectingKey) {
            const top = stack.at(-1), key = JSON.parse(token);
            if (top.keys.has(key)) fail('duplicate-metadata');
            top.keys.add(key); top.expectingKey = false;
        }
    }
    return value;
}
function target(platform = process.platform, machine = os.machine(), glibc = process.report.getReport().header.glibcVersionRuntime) {
    const arch = {x86_64: 'x64', AMD64: 'x64', x64: 'x64', arm64: 'arm64', ARM64: 'arm64', aarch64: 'arm64'}[machine];
    if (!arch || !['linux', 'darwin', 'win32'].includes(platform)) return null;
    // Always use the official baseline on x64, including Rosetta. No AVX2 assumption.
    let result = `${platform === 'win32' ? 'windows' : platform}-${arch}${arch === 'x64' ? '-baseline' : ''}`;
    if (platform === 'linux' && !glibc) {
        if (!fs.readdirSync('/lib').some(n => /^ld-musl-(x86_64|aarch64)\.so\.1$/.test(n))) fail('libc');
        result += '-musl';
    }
    return result;
}
// Only these labels/statuses may cross the core-to-shell diagnostic boundary.
class DownloadError extends Error {
    constructor(operation, status) { super('download'); this.operation = operation; this.status = status; diagnosticErrors.add(this); }
}
class RecoveryError extends Error {
    constructor(original) { super('recovery-required'); this.original = original; diagnosticErrors.add(this); }
}
function failureResult(error, recovering = false) {
    try { return formatFailure(error, recovering); } catch { return 'opencode-cli:failed'; }
}
function formatFailure(error, recovering) {
    const typed = diagnosticErrors.has(error);
    if (typed && error instanceof RecoveryError) {
        if (recovering) return 'opencode-cli:failed';
        return `opencode-cli:recovery-required:${failureResult(error.original, true).slice('opencode-cli:'.length)}`;
    }
    if (isNativeError(error) && error.message === 'recovery-required') return 'opencode-cli:recovery-required';
    if (typed && error instanceof DownloadError && ['latest-release', 'package-index', 'package-version', 'artifact-download', 'download'].includes(error.operation)) {
        const status = Number.isInteger(error.status) && error.status >= 100 && error.status <= 599 ? error.status : 'unknown';
        return `opencode-cli:download-failed:${error.operation}:http-${status}`;
    }
    if (typed && error instanceof PolicyError && typeof error.reason === 'string' && ['homebrew-preflight', 'installation', 'setup-selection', 'fresh-shell-selection'].includes(error.operation) &&
        (policyReasons.has(error.reason) || (error.reason.startsWith('native-') && nativeCodes.has(error.reason.slice(7))))) {
        const generic = `opencode-cli:policy-failed:${error.operation}:${error.reason}`;
        try {
            const context = pathRefusals.get(error);
            if (error.operation === 'installation' && error.reason === 'relative-path' && context &&
                Number.isInteger(context.index) && context.index >= 1 && context.index <= 999999 && ['empty', 'relative'].includes(context.kind)) {
                return `${generic}:command-discovery:${context.index}:${context.kind}`;
            }
        } catch { /* Retain the controlled generic failure if evidence is unavailable. */ }
        return generic;
    }
    return 'opencode-cli:failed';
}
function downloadOperation(parsed) {
    if (parsed.hostname === 'opencode.ai') return parsed.pathname === '/update/api/latest/cli/npm' ? 'latest-release' : 'download';
    let pathname;
    try { pathname = decodeURIComponent(parsed.pathname); } catch { fail('url'); }
    // Scoped names may use either a literal or percent-encoded slash. Only whole
    // package indexes support npm's abbreviated media type; versions require JSON.
    if (/^\/(?:@[A-Za-z0-9_.-]+\/)?[A-Za-z0-9_.-]+\/?$/.test(pathname)) return 'package-index';
    if (/^\/(?:@[A-Za-z0-9_.-]+\/)?[A-Za-z0-9_.-]+\/-\/[A-Za-z0-9_.-]+\.tgz$/.test(pathname)) return 'artifact-download';
    if (/^\/(?:@[A-Za-z0-9_.-]+\/)?[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+\/?$/.test(pathname)) return 'package-version';
    return 'download';
}
function fetchBytes(url, limit = 32 * 1024 * 1024) {
    const parsed = new URL(url);
    if (parsed.protocol !== 'https:' || parsed.username || parsed.password || parsed.port ||
        !['registry.npmjs.org', 'opencode.ai'].includes(parsed.hostname)) fail('url');
    const operation = downloadOperation(parsed);
    const accept = operation === 'package-index' ? 'application/vnd.npm.install-v1+json' : operation === 'artifact-download' ? 'application/octet-stream' : 'application/json';
    return new Promise((resolve, reject) => {
        let status;
        const request = https.get(url, {rejectUnauthorized: true, headers: {'User-Agent': 'curl/8.0', Accept: accept}}, response => {
            status = response.statusCode;
            if (status !== 200) { response.resume(); reject(new DownloadError(operation, status)); return; }
            const chunks = []; let length = 0;
            response.on('data', data => {
                length += data.length;
                if (length > limit) request.destroy(new Error('download-size'));
                else chunks.push(data);
            });
            response.on('end', () => resolve(Buffer.concat(chunks)));
            response.on('error', () => reject(new DownloadError(operation, status)));
        });
        const deadline = setTimeout(() => request.destroy(new Error('download-timeout')), 90000);
        request.on('close', () => clearTimeout(deadline));
        request.setTimeout(60000, () => request.destroy(new Error('download-timeout')));
        request.on('error', () => reject(new DownloadError(operation, status)));
    });
}
function unpack(bytes) {
    let tar;
    try { tar = zlib.gunzipSync(bytes, {maxOutputLength: 512 * 1024 * 1024}); } catch { fail('archive'); }
    const files = new Map(); let ended = false;
    for (let offset = 0; offset + 512 <= tar.length;) {
        const header = tar.subarray(offset, offset + 512); offset += 512;
        if (header.every(b => b === 0)) { ended = true; if (tar.subarray(offset).some(b => b !== 0)) fail('archive-tail'); break; }
        const text = (start, end) => header.subarray(start, end).toString().replace(/\0.*$/s, '');
        const name = text(0, 100), sizeText = text(124, 136).trim(), checksum = text(148, 156).trim();
        if (!/^[0-7]+$/.test(sizeText) || !/^[0-7]+$/.test(checksum)) fail('archive-header');
        const sum = header.reduce((n, b, i) => n + (i >= 148 && i < 156 ? 32 : b), 0);
        if (sum !== parseInt(checksum, 8) || text(345, 500) || text(157, 257)) fail('archive-header');
        if (!/^package\/(?:[A-Za-z0-9_@.-]+\/)*[A-Za-z0-9_.-]+\/?$/.test(name) ||
            name.split('/').some(p => p === '..' || p === '.') || files.has(name)) fail('archive-path');
        const size = parseInt(sizeText, 8), type = text(156, 157);
        if (!['', '0', '5'].includes(type) || (type === '5' && size) || offset + size > tar.length) fail('archive-type');
        files.set(name, tar.subarray(offset, offset + size));
        offset += Math.ceil(size / 512) * 512;
    }
    if (!ended) fail('archive-truncated');
    return files;
}
async function artifact(name, release, get = fetchBytes) {
    version(release);
    const metadata = json(await get(`https://registry.npmjs.org/${name}/${release}`));
    const basename = name.split('/').pop();
    if (metadata.name !== name || metadata.version !== release ||
        metadata.dist?.tarball !== `https://registry.npmjs.org/${name}/-/${basename}-${release}.tgz` ||
        !/^sha512-[A-Za-z0-9+/]{86}==$/.test(metadata.dist?.integrity || '')) fail('artifact-metadata');
    const bytes = await get(metadata.dist.tarball, 256 * 1024 * 1024);
    if (`sha512-${digest(bytes)}` !== metadata.dist.integrity) fail('integrity');
    const files = unpack(bytes), manifest = json(files.get('package/package.json') || 'null');
    if (manifest?.name !== name || manifest.version !== release) fail('artifact-identity');
    return files;
}
function safePath(file, home, leafLink = false) {
    // Resolve only the account HOME boundary (including Bazzite's system alias).
    const relative = path.relative(home, file);
    if (relative.startsWith('..') || path.isAbsolute(relative)) fail('outside-home');
    const chain = [home];
    for (const part of relative.split(path.sep).filter(Boolean)) chain.push(path.join(chain.at(-1), part));
    for (const item of chain) {
        let st;
        try { st = fs.lstatSync(item); } catch (e) { if (e.code === 'ENOENT') continue; throw e; }
        if ((st.isSymbolicLink() && !(leafLink && item === file)) ||
            (!st.isSymbolicLink() && !st.isDirectory() && !st.isFile()) ||
            (process.platform !== 'win32' && (st.uid !== process.getuid() || (!st.isSymbolicLink() && (st.mode & 0o022))))) fail('unsafe-path');
    }
}
function boundedRead(file) {
    const before = fs.lstatSync(file);
    if (!before.isFile() || before.size > 512 * 1024 * 1024) fail('unsafe-file');
    const fd = fs.openSync(file, fs.constants.O_RDONLY | fs.constants.O_NONBLOCK | (fs.constants.O_NOFOLLOW || 0));
    try {
        const opened = fs.fstatSync(fd);
        if (!opened.isFile() || opened.dev !== before.dev || opened.ino !== before.ino || opened.size !== before.size) fail('changed-copy');
        const bytes = fs.readFileSync(fd), after = fs.fstatSync(fd);
        if (bytes.length !== before.size || after.size !== before.size || after.mtimeMs !== before.mtimeMs) fail('changed-copy');
        return bytes;
    } finally { fs.closeSync(fd); }
}
function commands(home, env = process.env) {
    const dirs = new Set([path.join(home, '.local/bin'), path.join(home, '.opencode/bin'), path.join(home, '.bun/bin')]);
    for (const [offset, dir] of (env.PATH || '').split(path.delimiter).entries()) {
        if (!dir && process.platform === 'win32') continue;
        if (!dir || !path.isAbsolute(dir)) rejectPathComponent(offset + 1, dir ? 'relative' : 'empty');
        dirs.add(dir.startsWith(env.HOME + path.sep) ? path.join(home, path.relative(env.HOME, dir)) : dir);
    }
    const names = process.platform === 'win32' ? ['opencode.exe', 'opencode.cmd', 'opencode.ps1', 'opencode'] : ['opencode'];
    const result = [];
    for (const dir of dirs) for (const name of names) {
        const file = path.join(dir, name);
        try { fs.lstatSync(file); result.push(file); } catch (e) { if (e.code !== 'ENOENT') throw e; }
    }
    return [...new Map(result.map(file => [process.platform === 'win32' ? file.toLowerCase() : file, file])).values()];
}
// Foreign commands are observations, never migration candidates. Stop at the
// first foreign boundary: do not traverse its links, receipts or package store.
function foreignCommand(file, home) {
    const relative = path.relative(home, file);
    if (!relative.startsWith('..') && !path.isAbsolute(relative)) return false;
    if (!path.isAbsolute(file)) fail('relative-path');
    // Windows migration is HOME-only and retains the native ACL preflight.
    if (process.platform === 'win32') return true;
    const chain = [path.parse(file).root];
    for (const part of file.slice(chain[0].length).split(path.sep).filter(Boolean)) chain.push(path.join(chain.at(-1), part));
    for (const item of chain) {
        const info = fs.lstatSync(item);
        if (![0, process.getuid()].includes(info.uid) || (item === file && info.uid !== process.getuid())) return true;
        if (item !== file && (!info.isDirectory() || (info.mode & 0o002))) fail('unsafe-path');
    }
    return false;
}
function verifySetupSelection(expected, home, homeInput, searchPath, brewTrust) {
    const reject = reason => { throw new PolicyError(reason, 'setup-selection'); };
    const cached = process.env.SETUP_OPENCODE_HASHED;
    if (cached) {
        const normalized = cached.startsWith(homeInput + path.sep) ? path.join(home, path.relative(homeInput, cached)) : cached;
        if (!samePath(normalized, expected)) reject('command-conflict');
    }
    // Include script/native extensions, not only the installer's migration names.
    const names = process.platform === 'win32' ? ['opencode.ps1', ...new Set((process.env.PATHEXT || '.COM;.EXE;.BAT;.CMD').split(';').map(ext => 'opencode' + ext.toLowerCase()))] : ['opencode'];
    for (const directory of searchPath.split(path.delimiter)) {
        if (!directory && process.platform === 'win32') continue;
        if (!path.isAbsolute(directory)) reject('selection-unverified');
        for (const name of names) {
            const candidate = path.join(directory, name);
            let info;
            try { info = fs.lstatSync(candidate); } catch (error) { if (error.code === 'ENOENT') continue; reject('selection-unverified'); }
            // Native shells ignore directories and non-executable regular files.
            // Do not follow foreign links just to decide whether to ignore them;
            // uncertain metadata and actual executable shadows still fail closed.
            if (info.isDirectory()) continue;
            if (process.platform !== 'win32' && info.isFile()) {
                try { fs.accessSync(candidate, fs.constants.X_OK); }
                catch (error) { if (error.code === 'EACCES') continue; reject('selection-unverified'); }
            }
            // Resolve only the trusted HOME alias, never an arbitrary command link.
            const normalized = candidate.startsWith(homeInput + path.sep)
                ? path.join(home, path.relative(homeInput, candidate)) : candidate;
            if (!samePath(normalized, expected)) reject(foreignCommand(candidate, home) ? 'foreign-command' : 'command-conflict');
            if (brewTrust && samePath(brewTrust.command, expected)) checkBrewTrust(brewTrust);
            else if (!info.isFile() || info.isSymbolicLink()) reject('selection-unverified');
            try { fs.accessSync(expected, fs.constants.X_OK); } catch { reject('selection-unverified'); }
            return;
        }
    }
    reject('unreachable');
}
function verifyFreshSelection(expected, home, homeInput) {
    const reject = reason => { throw new PolicyError(reason, 'fresh-shell-selection'); };
    const shell = process.env.SETUP_OPENCODE_SHELL;
    if (!shell || !path.isAbsolute(shell)) reject('selection-unverified');
    const env = {...process.env, HOME: homeInput, USERPROFILE: homeInput};
    for (const name of Object.keys(env)) {
        if (/^(__MISE_|FNM_)|^MISE_(SHELL|.*_VERSION|TOOL_OPTS__NODE)$|^NODE_(PATH|OPTIONS)$/.test(name) ||
            ['BASH_ENV', 'ENV', '__setup_shared_node_activation'].includes(name)) delete env[name];
    }
    env.MISE_AUTO_INSTALL = 'false'; env.MISE_NODE_COMPILE = 'false';
    let args;
    const marker = `opencode-selection-${crypto.randomBytes(16).toString('hex')}:`;
    if (process.platform === 'win32') {
        if (!['powershell.exe', 'pwsh.exe'].includes(path.basename(shell).toLowerCase()) || !env.SETUP_OPENCODE_FRESH_PATH) reject('selection-unverified');
        env.PATH = env.SETUP_OPENCODE_FRESH_PATH;
        // Load the normal native profile. Only query resolution; never run the app.
        args = ['-NoLogo', '-NonInteractive', '-Command', `$ErrorActionPreference = 'Stop'; try { $c = Get-Command opencode -ErrorAction Stop; if ($c.CommandType -ne 'Application') { exit 2 }; [Console]::WriteLine("\`n${marker}" + $c.Source + "${marker}") } catch { exit 3 }`];
    } else {
        if (path.basename(shell) !== 'fish') reject('selection-unverified');
        env.PATH = '/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin';
        args = ['-l', '-i', '-c', `if functions -q opencode; exit 2; end; set -l selected (command -s opencode); or exit 3; printf '\\n${marker}%s${marker}\\n' "$selected"`];
    }
    let output;
    try {
        output = cp.execFileSync(shell, args, {cwd: home, env, timeout: 20000, maxBuffer: 65536,
            stdio: ['ignore', 'pipe', 'ignore'], windowsHide: true}).toString();
    } catch (error) { reject(error.status === 2 ? 'command-conflict' : 'selection-unverified'); }
    // Ordinary startup banners are not evidence. Accept exactly one fresh,
    // framed query result; never surface other stdout or arbitrary stderr.
    const records = output.split(/\r?\n/).filter(line => line.startsWith(marker));
    if (records.length !== 1 || !records[0].endsWith(marker)) reject('selection-unverified');
    const selected = records[0].slice(marker.length, -marker.length);
    if (!path.isAbsolute(selected) || /[\r\n\0]/.test(selected)) reject('selection-unverified');
    const normalized = selected.startsWith(homeInput + path.sep) ? path.join(home, path.relative(homeInput, selected)) : selected;
    if (!samePath(normalized, expected)) reject('command-conflict');
}
function probe(file, release, workspace) {
    const isolated = fs.mkdtempSync(path.join(workspace, 'probe-'));
    const env = {HOME: isolated, USERPROFILE: isolated, XDG_CONFIG_HOME: isolated, XDG_DATA_HOME: isolated,
        XDG_CACHE_HOME: isolated, XDG_STATE_HOME: isolated, APPDATA: isolated, LOCALAPPDATA: isolated,
        TMPDIR: isolated, TMP: isolated, TEMP: isolated, PATH: path.dirname(file), LANG: 'C', NO_COLOR: '1'};
    if (process.platform === 'win32') env.SystemRoot = process.env.SystemRoot;
    let output;
    try { output = cp.execFileSync(file, ['--version'], {cwd: isolated, env, timeout: 20000, maxBuffer: 1024,
        stdio: ['ignore', 'pipe', 'ignore'], windowsHide: true}).toString().trim(); } catch { fail('version-probe'); }
    if (output !== release && output !== `opencode v${release}`) fail('version-probe');
}
const brewFingerprint = s => s && (s.isDirectory() ? ['dev', 'ino', 'uid', 'gid', 'mode'] :
    ['dev', 'ino', 'uid', 'gid', 'mode', 'nlink', 'size', 'mtimeMs', 'ctimeMs']).map(key => s[key]);
const sameBrew = (a, b) => JSON.stringify(brewFingerprint(a)) === JSON.stringify(brewFingerprint(b));
function brewPermissions(file, info) {
    if (![0, process.getuid()].includes(info.uid) || (!info.isSymbolicLink() && (info.mode & 0o002))) fail('brew-path');
    if (!info.isSymbolicLink() && (info.mode & 0o020)) {
        if (process.platform !== 'linux' || info.uid === 0 || info.uid !== process.getuid() ||
            !(file === '/home/linuxbrew/.linuxbrew' || file.startsWith('/home/linuxbrew/.linuxbrew/'))) fail('brew-path');
        // Scoped single-human-user policy: group privacy is not a prerequisite.
        // Keep ownership/mode/identity snapshots; do not infer exclusive access.
    }
}
function checkBrewTrust(trust, moved = false) {
    for (const [file, before] of trust.snapshots) {
        if (moved && file === trust.command) continue;
        let now = null;
        try { now = fs.lstatSync(file); } catch (error) { if (error.code !== 'ENOENT') throw error; }
        if (!sameBrew(before, now)) fail('brew-snapshot-changed');
        if (now) brewPermissions(file, now);
    }
    if (!moved && fs.readlinkSync(trust.command) !== trust.link) fail('brew-snapshot-changed');
}
function checkBrewBackup(item, backup) {
    checkBrewTrust(item.brewTrust, true);
    const before = item.brewTrust.snapshots.get(item.file), now = fs.lstatSync(backup);
    // Renaming can change ctime; every other link identity field must survive.
    if (!['dev', 'ino', 'uid', 'gid', 'mode', 'nlink', 'size', 'mtimeMs'].every(key => before[key] === now[key]) ||
        !now.isSymbolicLink() || fs.readlinkSync(backup) !== item.brewTrust.link) fail('brew-snapshot-changed');
}
function brewCopy(file) {
    try { return inspectBrewCopy(file); } catch (error) { throw nativeFailure('homebrew-preflight', error); }
}
function inspectBrewCopy(file) {
    if (process.platform === 'win32') return null;
    const prefix = ['/opt/homebrew', '/usr/local', '/home/linuxbrew/.linuxbrew'].find(p => file === `${p}/bin/opencode`);
    if (!prefix) return null;
    const snapshots = new Map();
    function inspect(candidate, kind, optional = false) {
        const chain = ['/'];
        for (const part of candidate.split('/').filter(Boolean)) chain.push(path.join(chain.at(-1), part));
        for (const current of chain) {
            let info = null;
            try { info = fs.lstatSync(current); } catch (error) { if (!optional || error.code !== 'ENOENT') throw error; }
            if (snapshots.has(current) && !sameBrew(snapshots.get(current), info)) fail('brew-snapshot-changed');
            if (!info) { snapshots.set(current, null); return false; }
            const leaf = current === candidate;
            if (leaf && kind === 'pin') fail('pinned');
            if (!(leaf && kind === 'link' ? info.isSymbolicLink() : leaf && kind === 'file' ? info.isFile() && info.nlink === 1 : info.isDirectory())) fail('brew-path');
            if (!snapshots.has(current)) brewPermissions(current, info);
            snapshots.set(current, info);
        }
        return true;
    }
    inspect(file, 'link');
    const link = fs.readlinkSync(file);
    const binary = path.resolve(path.dirname(file), link);
    const match = binary.match(new RegExp(`^${prefix.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}/Cellar/opencode/([0-9.]+)/bin/opencode$`));
    if (!match) fail('brew-command');
    version(match[1]);
    const receiptPath = path.join(path.dirname(path.dirname(binary)), 'INSTALL_RECEIPT.json');
    inspect(binary, 'file'); inspect(receiptPath, 'file');
    const receipt = json(boundedRead(receiptPath));
    if (receipt?.source?.tap !== 'anomalyco/tap') fail('brew-origin');
    inspect(path.join(prefix, 'var/homebrew/pinned/opencode'), 'pin', true);
    const trust = {command: file, link, snapshots};
    checkBrewTrust(trust);
    return {binary, release: match[1], route: 'homebrew', trust};
}
// Exact native (no-shebang) npm cmd-shim templates. Customized/older wrappers
// remain conflicts rather than being interpreted or executed to discover identity.
function windowsNpmShims() {
    const relative = 'node_modules/opencode-ai/bin/opencode.exe';
    const head = '@ECHO off\r\nGOTO start\r\n:find_dp0\r\nSET dp0=%~dp0\r\nEXIT /b\r\n:start\r\nSETLOCAL\r\nCALL :find_dp0\r\n';
    return {
        'opencode.cmd': head + `"%dp0%\\${relative.replaceAll('/', '\\')}"   %*\r\n`,
        opencode: '#!/bin/sh\n' + 'basedir=$(dirname "$(echo "$0" | sed -e \'s,\\\\,/,g\')")\n\n' +
            'case `uname` in\n    *CYGWIN*|*MINGW*|*MSYS*)\n        if command -v cygpath > /dev/null 2>&1; then\n' +
            '            basedir=`cygpath -w "$basedir"`\n        fi\n    ;;\nesac\n\n' + `exec "$basedir/${relative}"   "$@"\n`,
        'opencode.ps1': '#!/usr/bin/env pwsh\n$basedir=Split-Path $MyInvocation.MyCommand.Definition -Parent\n\n' +
            '$exe=""\nif ($PSVersionTable.PSVersion -lt "6.0" -or $IsWindows) {\n' +
            '  # Fix case when both the Windows and Linux builds of Node\n  # are installed in the same directory\n  $exe=".exe"\n}\n' +
            '# Support pipeline input\nif ($MyInvocation.ExpectingInput) {\n' + `  $input | & "$basedir/${relative}"   $args\n` +
            `} else {\n  & "$basedir/${relative}"   $args\n}\nexit $LASTEXITCODE\n`,
    };
}
function packageCommandDirectory(root, home) {
    if (process.platform !== 'win32' && samePath(root, path.join(home, '.local/lib/node_modules/opencode-ai'))) return path.join(home, '.local/bin');
    if (samePath(root, path.join(home, '.bun/install/global/node_modules/opencode-ai'))) return path.join(home, '.bun/bin');
    const relative = path.relative(home, root).replaceAll('\\', '/');
    if (process.platform !== 'win32' && /^\.local\/share\/mise\/installs\/node\/\d+(?:\.\d+){0,2}\/lib\/node_modules\/opencode-ai$/.test(relative)) {
        return path.join(path.dirname(path.dirname(path.dirname(root))), 'bin');
    }
    if (process.platform === 'win32') {
        const npm = path.join(process.env.APPDATA || path.join(home, 'AppData/Roaming'), 'npm');
        if (samePath(root, path.join(npm, 'node_modules/opencode-ai'))) return npm;
        const mise = path.join(process.env.LOCALAPPDATA || path.join(home, 'AppData/Local'), 'mise/installs/node');
        const prefix = path.dirname(path.dirname(root));
        if (/^\d+(?:\.\d+){0,2}$/.test(path.relative(mise, prefix)) && samePath(root, path.join(prefix, 'node_modules/opencode-ai'))) return prefix;
    }
    fail('custom-prefix');
}
async function identify(file, home, nativeTarget, get) {
    const brew = brewCopy(file);
    if (!brew) safePath(file, home, true);
    let binary = brew?.binary || file, release = brew?.release, route = brew?.route || 'standalone';
    const st = fs.lstatSync(file);
    let windowsShim = false;
    if (process.platform === 'win32' && !st.isSymbolicLink() && path.basename(file) !== 'opencode.exe') {
        const expected = windowsNpmShims()[path.basename(file)];
        if (!expected || !boundedRead(file).equals(Buffer.from(expected))) fail('custom-wrapper');
        binary = path.join(path.dirname(file), 'node_modules/opencode-ai/bin/opencode.exe');
        windowsShim = true;
    }
    if ((st.isSymbolicLink() && !brew) || windowsShim) {
        if (!windowsShim) binary = fs.realpathSync(file);
        const match = binary.match(/^(.*[\\/]node_modules[\\/]opencode-ai)[\\/]bin[\\/]opencode(?:\.exe)?$/);
        if (!match) fail('custom-link');
        const root = match[1]; safePath(root, home); safePath(binary, home);
        if (!samePath(path.dirname(file), packageCommandDirectory(root, home))) fail('custom-prefix');
        const packageMetadata = path.join(root, 'package.json'); safePath(packageMetadata, home);
        const pkg = json(boundedRead(packageMetadata));
        if (pkg.name !== 'opencode-ai' || version(pkg.version)[0] !== 1) fail('package-conflict');
        release = pkg.version; route = 'package';
        const manifest = path.join(path.dirname(path.dirname(root)), 'package.json');
        if (fs.existsSync(manifest)) {
            safePath(manifest, home);
            const policy = json(boundedRead(manifest));
            const selected = policy.dependencies?.['opencode-ai'];
            if (selected && !['latest', '*'].includes(selected) && !/^[~^]1\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/.test(selected)) fail('pinned');
            if (policy.overrides?.['opencode-ai'] || policy.resolutions?.['opencode-ai']) fail('pinned');
        }
        if (path.extname(binary) !== '.exe') {
            const published = await artifact('opencode-ai', release, get);
            if (!published.get(`package/bin/${path.basename(binary)}`)?.equals(boundedRead(binary))) fail('custom-wrapper');
            binary = path.join(root, 'bin/.opencode');
        }
        safePath(binary, home);
    } else if (!brew && !['.local/bin', '.opencode/bin', '.bun/bin'].some(dir => samePath(path.dirname(file), path.join(home, dir)))) {
        fail('custom-prefix');
    }
    const bytes = boundedRead(binary);
    // Package metadata is only a hint. Identity always requires official native bytes.
    const content = release ? '' : bytes.toString('latin1');
    // Official Bun builds embed this execution argument. It is only a version
    // hint: the native bytes must still match the published platform artifact.
    const hints = [...new Set([...content.matchAll(/--user-agent=opencode\/([1-9]\d*\.\d+\.\d+)(?=[\x00\s"'\\])/g)].map(match => match[1]))];
    let candidates = release ? [release] : hints.length === 1 ? hints : [...new Set(content.match(/\b[1-9]\d?\.\d{1,4}\.\d{1,4}\b/g) || [])];
    if (!release && hints.length !== 1) {
        const registry = json(await get('https://registry.npmjs.org/opencode-ai'));
        const modern = json(await get('https://registry.npmjs.org/@opencode/cli'));
        candidates = candidates.filter(v => Object.hasOwn(v.startsWith('1.') ? registry.versions || {} : modern.versions || {}, v));
        if (!candidates.length || candidates.length > 8) fail('unverified-copy');
    }
    const variants = [nativeTarget, nativeTarget.replace('-baseline', '')];
    if (nativeTarget.startsWith('linux-')) {
        for (const variant of [...variants]) variants.push(variant.endsWith('-musl') ? variant.slice(0, -5) : variant + '-musl');
    } else if (/^(darwin|windows)-arm64$/.test(nativeTarget)) {
        // Old x64 copies can be present under Rosetta/Windows ARM emulation.
        variants.push(nativeTarget.replace('arm64', 'x64-baseline'), nativeTarget.replace('arm64', 'x64'));
    }
    for (const candidate of candidates) {
        for (const variant of new Set(variants)) {
            let official;
            try { official = await artifact(`${candidate.startsWith('1.') ? 'opencode-' : '@opencode/cli-'}${variant}`, candidate, get); } catch { continue; }
            const executable = official.get(`package/bin/opencode${process.platform === 'win32' ? '.exe' : ''}`);
            if (executable?.equals(bytes)) return {file, binary, release: candidate, route, brewTrust: brew?.trust, nativeHash: digest(bytes), bytes: st.isSymbolicLink() ? null : boundedRead(file), link: st.isSymbolicLink() ? fs.readlinkSync(file) : null};
        }
    }
    fail('unverified-copy');
}
async function install(options = {}) {
    try { return await installChecked(options); } catch (error) { throw nativeFailure('installation', error); }
}
async function installChecked(options) {
    const get = options.get || fetchBytes, runProbe = options.probe || probe;
    const nativeTarget = options.target === undefined ? target() : options.target;
    if (!nativeTarget) return 'unsupported';
    const homeInput = options.home || os.homedir(), home = fs.realpathSync(homeInput);
    safePath(home, home);
    if (process.platform === 'win32' && process.env.SETUP_OPENCODE_ACL_VERIFIED !== '1') fail('windows-acl');
    const latest = json(await get('https://opencode.ai/update/api/latest/cli/npm'));
    if (latest.channel !== 'latest' || latest.name !== 'cli' || latest.distribution !== 'npm' ||
        latest.active !== true || latest.minimum !== false || latest.metadata?.package !== '@opencode/cli' || version(latest.version)[0] !== 2) fail('release-metadata');
    const release = latest.version, destination = path.join(home, '.local/bin', process.platform === 'win32' ? 'opencode.exe' : 'opencode');
    const receipt = path.join(home, '.local/bin/.setup-opencode-cli.json');
    safePath(destination, home, true); safePath(receipt, home);
    const found = (options.commands || commands(home)).filter(file => !foreignCommand(file, home));
    // Bun can publish a native hardlink rather than a symlink. Preserve its
    // explicit global selection even when command identity comes from bytes.
    if (found.some(file => samePath(path.dirname(file), path.join(home, '.bun/bin')))) {
        const manifest = path.join(home, '.bun/install/global/package.json');
        safePath(manifest, home);
        if (fs.existsSync(manifest)) {
            const policy = json(boundedRead(manifest)), selected = policy.dependencies?.['opencode-ai'];
            if (selected && !['latest', '*'].includes(selected) && !/^[~^]1\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/.test(selected)) fail('pinned');
            if (policy.overrides?.['opencode-ai'] || policy.resolutions?.['opencode-ai']) fail('pinned');
        }
    }
    const verifySelection = async (expected, brewTrust) => {
        verifySetupSelection(expected, home, homeInput, options.path ?? process.env.PATH ?? '', brewTrust);
        verifyFreshSelection(expected, home, homeInput);
        if (process.platform === 'win32') {
            // PowerShell's own session (aliases/functions and native discovery)
            // must approve before receipt commit while rollback is still live.
            let selected;
            try { selected = await options.verifySessionSelection?.(expected); } catch { /* fail closed below */ }
            if (selected !== true) throw new PolicyError(selected === false ? 'command-conflict' : 'selection-unverified', 'setup-selection');
        }
    };
    let installed = null, installedBytes = null;
    if (fs.existsSync(receipt)) {
        safePath(destination, home);
        const record = json(boundedRead(receipt)); version(record.version);
        if (Object.keys(record).some(key => !['package', 'version', 'sha512', 'pinned'].includes(key)) ||
            (Object.hasOwn(record, 'pinned') && typeof record.pinned !== 'boolean')) fail('receipt');
        if (record.package !== `@opencode/cli-${nativeTarget}` || record.sha512 !== digest(boundedRead(destination))) fail('receipt');
        if (record.pinned === true) fail('pinned');
        const files = await artifact(record.package, record.version, get);
        if (!files.get(`package/bin/${path.basename(destination)}`)?.equals(boundedRead(destination))) fail('unverified-copy');
        installed = record.version;
        installedBytes = boundedRead(destination);
    }
    const old = [];
    for (const file of found) {
        if (installed && samePath(file, destination)) continue;
        old.push(await identify(file, home, nativeTarget, get));
    }
    if (old.some(item => compare(item.release, release) > 0)) {
        if (old.length !== 1 || installed) fail('shadowed-newer');
        const item = old[0];
        const revalidate = () => {
            if (item.route === 'homebrew') checkBrewTrust(item.brewTrust);
            else safePath(item.file, home);
            if (digest(boundedRead(item.binary)) !== item.nativeHash) fail('changed-copy');
        };
        revalidate();
        await verifySelection(item.file, item.brewTrust);
        revalidate();
        return 'newer';
    }
    if (installed && compare(installed, release) >= 0) {
        if (old.length) fail('shadowed');
        await verifySelection(destination);
        safePath(destination, home);
        if (!boundedRead(destination).equals(installedBytes)) fail('changed-copy');
        // A newer official version is preserved, never rewritten or downgraded.
        if (compare(installed, release) > 0) return 'newer';
        const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'setup-opencode-'));
        let probeError;
        try { runProbe(destination, installed, temp); }
        catch (error) { probeError = nativeFailure('installation', error); throw probeError; }
        finally {
            try { fs.rmSync(temp, {recursive: true, force: true}); }
            catch (error) { throw new RecoveryError(probeError || nativeFailure('installation', error)); }
        }
        return 'current';
    }
    const files = await artifact(`@opencode/cli-${nativeTarget}`, release, get);
    const bytes = files.get(`package/bin/${path.basename(destination)}`);
    if (!bytes || !bytes.length) fail('missing-binary');
    const bin = path.dirname(destination); safePath(bin, home);
    fs.mkdirSync(bin, {recursive: true, mode: 0o755}); safePath(bin, home);
    const stage = fs.mkdtempSync(path.join(bin, '.setup-opencode-'));
    const staged = path.join(stage, path.basename(destination));
    const backups = []; let promoted = false, completed = false, locked = false, originalError;
    const lock = path.join(bin, '.setup-opencode-cli.lock');
    const previousReceipt = fs.existsSync(receipt) ? boundedRead(receipt) : null;
    try {
        fs.mkdirSync(lock, {mode: 0o700}); locked = true;
        fs.writeFileSync(staged, bytes, {mode: 0o755, flag: 'wx'});
        runProbe(staged, release, stage);
        // Preflight ALL copies before moving any commands. Never remove package stores/data.
        for (const item of old) {
            if (item.route === 'homebrew') checkBrewTrust(item.brewTrust);
            else safePath(item.file, home, !!item.link);
            if (item.link ? fs.readlinkSync(item.file) !== item.link : !boundedRead(item.file).equals(item.bytes)) fail('changed-copy');
            if (digest(boundedRead(item.binary)) !== item.nativeHash) fail('changed-copy');
        }
        if (installed) {
            safePath(destination, home);
            if (!boundedRead(destination).equals(installedBytes)) fail('changed-copy');
            old.push({file: destination});
        }
        for (const item of old) {
            if (item.route === 'homebrew') checkBrewTrust(item.brewTrust);
            const backup = item.route === 'homebrew'
                ? path.join(path.dirname(item.file), `.opencode-setup-recovery-${crypto.randomBytes(12).toString('hex')}`)
                : path.join(stage, `previous-${backups.length}`);
            // Journal each intended move before it occurs, for interruption recovery.
            fs.writeFileSync(path.join(stage, 'recovery.json'), JSON.stringify([...backups, [item.file, backup]]), {mode: 0o600});
            fs.renameSync(item.file, backup); backups.push([item.file, backup]);
        }
        // Recheck the read-only Homebrew boundaries even after command quarantine.
        for (const [original, backup] of backups) {
            const item = old.find(entry => entry.file === original);
            if (item?.route === 'homebrew') checkBrewBackup(item, backup);
        }
        // Atomic no-clobber publication: a concurrent/custom destination is never overwritten.
        fs.linkSync(staged, destination); promoted = true;
        fs.unlinkSync(staged);
        runProbe(destination, release, stage);
        // Verify the effective command, not mere PATH membership. Failure rolls back.
        await verifySelection(destination);
        safePath(destination, home);
        if (!boundedRead(destination).equals(bytes)) fail('changed-copy');
        const remaining = options.commands ? [destination] : commands(home);
        if (remaining.some(file => !samePath(file, destination) && !foreignCommand(file, home))) fail('shadowed');
        const record = JSON.stringify({package: `@opencode/cli-${nativeTarget}`, version: release, sha512: digest(bytes)}) + '\n';
        const nextReceipt = path.join(stage, 'receipt'); fs.writeFileSync(nextReceipt, record, {mode: 0o600, flag: 'wx'});
        safePath(receipt, home);
        if (previousReceipt ? !boundedRead(receipt).equals(previousReceipt) : fs.existsSync(receipt)) fail('changed-receipt');
        fs.renameSync(nextReceipt, receipt); completed = true;
        return old.length ? 'migrated' : 'installed';
    } catch (error) {
        originalError = nativeFailure('installation', error);
        throw originalError;
    } finally {
        if (!completed) {
            try {
                if (promoted) {
                    safePath(destination, home);
                    if (!boundedRead(destination).equals(bytes)) fail('changed-copy');
                    fs.unlinkSync(destination);
                }
                for (const [original, backup] of backups.reverse()) {
                    const item = old.find(entry => entry.file === original);
                    if (item?.route === 'homebrew') checkBrewBackup(item, backup);
                    try { fs.lstatSync(original); fail('recovery-occupied'); } catch (e) { if (e.code !== 'ENOENT') throw e; }
                    fs.renameSync(backup, original);
                }
            } catch { throw new RecoveryError(originalError); }
        }
        // Retain old commands privately for manual recovery after a successful migration.
        try {
            if (completed && backups.length) fs.chmodSync(stage, 0o700);
            else fs.rmSync(stage, {recursive: true, force: true});
            if (locked) fs.rmdirSync(lock);
        } catch (error) { throw new RecoveryError(originalError || nativeFailure('installation', error)); }
    }
}
module.exports = {version, compare, target, unpack, artifact, identify, install, commands, safePath, brewCopy, windowsNpmShims, probe, fetchBytes, failureResult};
if (require.main === module || process.argv[1] === '-') install().then(result => console.log(`opencode-cli:${result}`)).catch(error => {
    console.log(failureResult(error));
    process.exitCode = 1;
});
OPENCODE_CLI_JS
    result=${result%.}
    result=${result%$'\n'}
    if [[ "${status}" -ne 0 ]]; then
        if [[ "${result}" == opencode-cli:recovery-required || "${result}" == opencode-cli:recovery-required:failed ]]; then
            recovery=1
        elif [[ "${result}" =~ ^opencode-cli:(recovery-required:)?download-failed:(latest-release|package-index|package-version|artifact-download|download):http-([1-5][0-9][0-9]|unknown)$ ]]; then
            [[ -z "${BASH_REMATCH[1]}" ]] || recovery=1
            print_error "OpenCode CLI download failed (operation=${BASH_REMATCH[2]}, HTTP=${BASH_REMATCH[3]})."
        elif [[ "${result}" =~ ^opencode-cli:(recovery-required:)?policy-failed:installation:relative-path:command-discovery:([1-9][0-9]{0,5}):(empty|relative)$ ]]; then
            [[ -z "${BASH_REMATCH[1]}" ]] || recovery=1
            print_error "OpenCode CLI blocked (operation=installation, reason=relative-path, boundary=command-discovery, component=${BASH_REMATCH[2]}, kind=${BASH_REMATCH[3]})."
        elif [[ "${result}" =~ ^opencode-cli:(recovery-required:)?policy-failed:(homebrew-preflight|installation|setup-selection|fresh-shell-selection):(archive|archive-header|archive-path|archive-tail|archive-truncated|archive-type|artifact-identity|artifact-metadata|brew-command|brew-origin|brew-path|brew-snapshot-changed|changed-copy|changed-receipt|custom-link|custom-prefix|custom-wrapper|duplicate-metadata|integrity|libc|metadata|missing-binary|outside-home|package-conflict|pinned|receipt|recovery-occupied|relative-path|release-metadata|shadowed|shadowed-newer|unreachable|unsafe-file|unsafe-path|unverified-copy|url|version|version-probe|windows-acl|foreign-command|command-conflict|selection-unverified|native-(EACCES|EPERM|ENOENT|EIO|EEXIST|ENOTDIR|ELOOP|ENOSPC|EROFS|ETIMEDOUT|ENOBUFS))$ ]]; then
            [[ -z "${BASH_REMATCH[1]}" ]] || recovery=1
            print_error "OpenCode CLI blocked (operation=${BASH_REMATCH[2]}, reason=${BASH_REMATCH[3]})."
            print_error 'Inspect the identified command and filesystem evidence; preserve conflicts and recovery artifacts. Do not change unrelated permissions.'
        else
            print_error 'OpenCode CLI unverified (operation=installation, reason=unrecognized-result).'
        fi
        if [[ "${recovery}" -eq 1 ]]; then
            print_error 'OpenCode CLI rollback needs manual recovery; preserve .setup-opencode-* directories, .opencode-setup-recovery-* commands and the lock. Inspect recovery.json before restoring identified commands.'
        fi
        print_error 'OpenCode CLI installation incomplete; existing data preserved. Review command ownership, pins, metadata, prerequisites and PATH.'
        return 1
    fi
    case "${result}" in
        opencode-cli:installed|opencode-cli:current) print_success 'OpenCode CLI stable v2 installation/version verified.' ;;
        opencode-cli:migrated) print_success 'OpenCode CLI native command migrated and verified; legacy package stores and command backups retained.' ;;
        opencode-cli:newer) print_warning 'OpenCode CLI: newer official release preserved; no downgrade or migration performed.' ;;
        opencode-cli:unsupported) print_warning 'OpenCode CLI: unsupported architecture; skipping without source builds.' ;;
        *) print_error 'OpenCode CLI unverified (operation=installation, reason=unrecognized-result).'; return 1 ;;
    esac
}

# Keep retained legacy Homebrew registrations from being upgraded/relinked by the
# later blanket upgrade. Own only this temporary pin; preserve user pins.
opencode_guarded_brew_upgrade() (
    local formulae pins added=0 status=0
    formulae=$(brew list --formula -1 2>/dev/null) || return 1
    if ! grep -Eq '(^|/)opencode$' <<< "${formulae}"; then
        brew upgrade
        return $?
    fi
    pins=$(brew list --pinned 2>/dev/null) || return 1
    if ! grep -Eq '(^|/)opencode$' <<< "${pins}"; then
        trap 'if [[ "${added}" -eq 1 ]]; then brew unpin opencode >/dev/null 2>&1 || true; fi' EXIT
        brew pin opencode >/dev/null 2>&1 || return 1
        added=1
    fi
    brew upgrade || status=$?
    if [[ "${added}" -eq 1 ]]; then
        if brew unpin opencode >/dev/null 2>&1; then added=0; else status=1; fi
    fi
    return "${status}"
)

# An unrecognized distro-owned command is not ours to update or hold. This also
# runs before Pi/Ubuntu's early blanket upgrades, before native prerequisites.
opencode_apt_upgrade_safe() {
    local candidates candidate resolved owner_status
    candidates=$(type -ap opencode 2>/dev/null) || candidates=''
    for candidate in /usr/bin/opencode /bin/opencode /usr/local/bin/opencode; do
        if [[ -e "${candidate}" || -L "${candidate}" ]]; then
            candidates="${candidates}"$'\n'"${candidate}"
        fi
    done
    while IFS= read -r candidate; do
        [[ -n "${candidate}" ]] || continue
        if [[ "${candidate}" != /* ]] || ! resolved=$(readlink -f -- "${candidate}"); then
            print_warning 'Deferring blanket APT upgrades: OpenCode command ownership is unverified.'
            return 1
        fi
        for candidate in "${candidate}" "${resolved}"; do
            if dpkg-query --search -- "${candidate}" >/dev/null 2>&1; then
                print_warning 'Deferring blanket APT upgrades: a distro-owned OpenCode command is preserved; review its package and pins manually.'
                return 1
            else
                owner_status=$?
            fi
            if [[ "${owner_status}" -ne 1 ]]; then
                print_warning 'Deferring blanket APT upgrades: OpenCode package ownership could not be verified.'
                return 1
            fi
        done
    done <<< "${candidates}"
    return 0
}
# END GENERATED OPENCODE CLI

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
    if [[ "${PI_PROFILE_MUTATIONS_BLOCKED:-0}" -eq 1 ]]; then _pi_dirs=(); fi
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
        unset NODE_PATH NODE_OPTIONS BASH_ENV __setup_shared_node_activation
        # Fish, not Bash, expands $argv in this probe.
        # shellcheck disable=SC2016
        env PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" MISE_AUTO_INSTALL=false "${_fish}" -l -c '
            test "$__setup_shared_node_activation" = 1; or exit 1
            type -q mise; or exit 1
            test (mise settings get activate_aggressive) = true; or exit 1
            set -l expected_node (mise which -C "$HOME" node); or exit 1
            node -e '\''const fs = require("node:fs"); const [major, minor] = process.versions.node.split(".").map(Number); process.exit((major > 22 || (major === 22 && minor >= 20)) && typeof fs.globSync === "function" && fs.realpathSync(process.execPath) === fs.realpathSync(process.argv[1]) ? 0 : 1)'\'' "$expected_node"; or exit 1
            set -l node_pin_tools (mise settings get idiomatic_version_file_enable_tools); or exit 1
            node -e '\''const tools = JSON.parse(process.argv[1]); process.exit(Array.isArray(tools) && tools.includes("node") ? 0 : 1)'\'' "$node_pin_tools"; or exit 1
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

    # Preserve legacy fnm project pins when mise becomes the sole selector.
    # Native additive settings preserve other enabled tools and unrelated config.
    if ! MISE_AUTO_INSTALL=false mise settings add -C / idiomatic_version_file_enable_tools node < /dev/null >/dev/null 2>&1 ||
        ! MISE_AUTO_INSTALL=false mise settings set -C / activate_aggressive true < /dev/null >/dev/null 2>&1; then
        print_warning "Cannot configure mise PATH precedence and legacy Node pins; leaving dependent setup blocked."
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
        # Repair the managed profile, not this probe's PATH. Limit apply to the
        # fish file: unrelated dotfiles and run_ scripts must not run here.
        print_message "Refreshing chezmoi-managed fish activation for the shared Node runtime..."
        if ! command -v chezmoi >/dev/null 2>&1 ||
            ! chezmoi apply --force --include=files "${HOME}/.config/fish/config.fish" < /dev/null >/dev/null 2>&1; then
            print_warning "Shared Node shell repair failed: chezmoi could not apply the managed fish profile. Check dotfiles access and update the source; leaving dependent setup blocked."
            return 1
        fi
        if ! verify_shared_node_shell; then
            print_warning "Shared Node shell repair failed verification. Update the dotfiles source and review HOME overrides or custom shell hooks; leaving dependent setup blocked."
            return 1
        fi
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
    if [[ "${PI_PROFILE_MUTATIONS_BLOCKED:-0}" -eq 1 ]]; then _pi_dirs=(); fi
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

# Retire Simple English from global skill copies and skills CLI update records.
remove_simple_english_skill() {
    matt_pocock_skill_policy remove-simple-english
}

# Retire global show-me copies on the next setup run.
remove_show_me_skill() {
    matt_pocock_skill_policy remove-show-me
}

# Retire PR Lens from global skill copies and skills CLI update records.
remove_pr_lens_skill() {
    matt_pocock_skill_policy remove-pr-lens
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
        if [[ "${PI_PROFILE_MUTATIONS_BLOCKED:-0}" -eq 1 && "${_path}" == "${HOME}/.pi/"* ]]; then continue; fi
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
    if ! command -v node > /dev/null 2>&1; then
        print_warning "Pi Go setup failed: shared Node runtime unavailable."
        return 1
    fi
    # Bash 3.2 misparses quoted heredocs inside $(); redirect the group instead.
    {
        _result=$(env -u NODE_OPTIONS -u NODE_PATH node --input-type=commonjs - "${HOME}" "${PI_CODING_AGENT_DIR:-}" sync 2>/dev/null) || _status=$?
    } <<'PI_OPENCODE_GO_JS'
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
    const responses = catalog['openai-responses'];
    const model = responses?.[id] ?? responses?.['chat:' + id];
    const typed = model !== responses?.[id];
    if (matches.length !== 1 || matches[0] !== model ||
        ((typed || Object.hasOwn(model, 'type')) && model.type !== 'chat') || model.provider !== 'opencode-go' ||
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
    if [[ "${_status}" -ne 0 ]]; then
        if [[ "${_result}" =~ ^go-failure:(${_operations}):(${_reasons})$ ]]; then
            print_warning "Pi Go setup failed: ${BASH_REMATCH[1]}: ${BASH_REMATCH[2]}. Review this check locally, then rerun setup."
        else
            print_warning "Pi Go setup failed: helper-exit-${_status}: diagnostic-unavailable. No safe helper detail was received."
        fi
        return 1
    fi
    case "${_result}" in
        missing-key) print_warning "Pi Go authentication not supplied: add OPENCODE_GO_API_KEY to ~/.env.local. Existing credentials were preserved." ;;
        updated) print_success "Pi Go credential synchronized in the active Pi profile." ;;
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


is_wsl_environment() {
    grep -qiE '(microsoft|wsl)' /proc/version /proc/sys/kernel/osrelease 2>/dev/null || [[ -n "${WSL_DISTRO_NAME:-}" ]] || [[ -f /proc/sys/fs/binfmt_misc/WSLInterop ]]
}

is_container_environment() {
    [[ -f /.dockerenv ]] || { command -v systemd-detect-virt &> /dev/null && systemd-detect-virt --container --quiet 2>/dev/null; }
}

headless_platform_gate() {
    if [[ "${HEADLESS:-}" != "1" ]]; then
        return 0
    fi

    if [[ "$(uname -s 2>/dev/null || true)" != "Linux" ]]; then
        return 0
    fi

    if is_wsl_environment; then
        print_error "HEADLESS=1 setup is unsupported in WSL because WSL cannot guarantee startup after Windows host reboot without login."
        return 1
    fi

    if is_container_environment; then
        print_error "HEADLESS=1 setup requires a booting native Linux user manager; container environments are unsupported."
        return 1
    fi
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

# Retire Backlog MCP from global agent configuration. Keep this block identical in the Bash setup scripts.
retire_global_backlog_mcp() {
    local _result=""
    if ! ensure_shared_node_runtime; then
        print_error "Node.js is required to retire global Backlog MCP registrations."
        return 1
    fi
    # Bash 3.2 misparses quoted heredocs inside $(); redirect the group instead.
    if ! {
        _result=$(env -u NODE_OPTIONS -u NODE_PATH node --input-type=commonjs - "${HOME}" "${PI_CODING_AGENT_DIR:-}" "${CLAUDE_CONFIG_DIR:-}" "${CODEX_HOME:-}" "${GEMINI_CLI_HOME:-}" 2>/dev/null)
    } <<'BACKLOG_MCP_RETIREMENT_JS'
// BEGIN BACKLOG_MCP_RETIREMENT
const fs = require('node:fs');
const path = require('node:path');
const {spawnSync} = require('node:child_process');
class RetirementError extends Error {}
let phase = 'preflight';
const fail = message => { throw new RetirementError(message); };
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const own = (value, key) => Object.prototype.hasOwnProperty.call(value, key);
const same = (a, b) => a && b && a.dev === b.dev && a.ino === b.ino && a.mode === b.mode && a.uid === b.uid && a.gid === b.gid &&
    a.nlink === b.nlink && a.size === b.size && a.mtimeMs === b.mtimeMs && a.ctimeMs === b.ctimeMs;
function info(file) { try { return fs.lstatSync(file); } catch (error) { if (error.code === 'ENOENT') return null; throw error; } }
function absolute(value) {
    if (!value || !path.isAbsolute(value) || value.split(/[\\/]/).some(part => part === '..' || part === '.')) fail('unsafe-path');
    return path.resolve(value);
}
function trustedHomeAlias(file, stat) {
    return process.platform === 'linux' && file === '/home' && stat.uid === 0 &&
        ['var/home', '/var/home'].includes(fs.readlinkSync(file)) && ['/', '/var', '/var/home'].every(dir => {
            const s = info(dir); return s?.isDirectory() && !s.isSymbolicLink() && s.uid === 0 && !(s.mode & 0o022);
        });
}
function safeBoundary(file, mutate = false) {
    const entries = [];
    for (let current = file; ; current = path.dirname(current)) {
        const stat = info(current);
        if (!stat) fail('unsafe-path');
        if (stat.isSymbolicLink()) {
            if (!trustedHomeAlias(current, stat)) fail('unsafe-path');
        } else if (!stat.isDirectory()) fail('unsafe-path');
        else if (process.platform !== 'win32') {
            const stickyRoot = stat.uid === 0 && (stat.mode & 0o1000);
            if (![0, process.getuid()].includes(stat.uid) || mutate && (stat.mode & 0o022) && !stickyRoot) fail('unsafe-boundary');
        }
        entries.push({file: current, stat});
        if (current === path.dirname(current)) break;
    }
    return entries;
}
function rawRead(fd, stat) {
    if (stat.size > 2 * 1024 * 1024) fail('unsafe-metadata');
    const buffer = Buffer.alloc(stat.size); let used = 0;
    while (used < buffer.length) {
        const count = fs.readSync(fd, buffer, used, buffer.length - used, used);
        if (!count) fail('metadata-changed');
        used += count;
    }
    return buffer;
}
function jsonDocument(text) {
    let data;
    try { data = JSON.parse(text.replace(/^\uFEFF/, '')); } catch { fail('malformed-metadata'); }
    if (!object(data)) fail('malformed-metadata');
    const tokens = text.match(/"(?:[^"\\]|\\.)*"|[{}\[\]:,]/g) || [], stack = [];
    for (let i = 0; i < tokens.length; i++) {
        const token = tokens[i];
        if (token === '{' || token === '[') stack.push(token === '{' ? new Set() : null);
        else if (token === '}' || token === ']') stack.pop();
        else if (token.startsWith('"') && tokens[i + 1] === ':') {
            const name = JSON.parse(token), keys = stack[stack.length - 1];
            if (!keys || keys.has(name)) fail('duplicate-key'); keys.add(name);
        }
    }
    return data;
}
function transformJson(text, serverKey = 'mcpServers') {
    const data = jsonDocument(text);
    if (!own(data, serverKey)) return null;
    if (!object(data[serverKey])) fail('malformed-metadata');
    const selected = new Set(Object.entries(data[serverKey]).filter(([name, value]) => backlog(name, value)).map(([name]) => name));
    if (!selected.size) return null;
    // Parse only source spans after validating JSON. Do not serialize unrelated
    // values: JS numbers cannot represent every number permitted by JSON.
    const tokens = [...text.matchAll(/"(?:[^"\\]|\\.)*"|-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?|true|false|null|[{}\[\]:,]/g)];
    let cursor = 0;
    const take = expected => { const token = tokens[cursor++]; if (!token || expected && token[0] !== expected) fail('malformed-metadata'); return token; };
    const parse = () => {
        const token = take(), node = {start: token.index, end: token.index + token[0].length, members: []};
        if (token[0] === '{' || token[0] === '[') {
            const end = token[0] === '{' ? '}' : ']';
            while (tokens[cursor]?.[0] !== end) {
                let key;
                if (token[0] === '{') { key = take(); take(':'); }
                const value = parse();
                if (key) node.members.push({name: JSON.parse(key[0]), start: key.index, end: value.end, value});
                if (tokens[cursor]?.[0] === end) break;
                take(',');
            }
            node.end = take(end).index + 1;
        }
        return node;
    };
    const root = parse();
    if (cursor !== tokens.length) fail('malformed-metadata');
    const servers = root.members.find(member => member.name === serverKey).value;
    const kept = servers.members.filter(member => !selected.has(member.name));
    const output = text.slice(0, servers.start + 1) + kept.map(member => text.slice(member.start, member.end)).join(',') + text.slice(servers.end - 1);
    jsonDocument(output);
    return output;
}
function backlog(name, definition) {
    if (name.toLowerCase() === 'backlog') return true;
    if (!object(definition) || typeof definition.command !== 'string') return false;
    const command = definition.command.replace(/\\/g, '/').split('/').pop().toLowerCase().replace(/\.(cmd|exe)$/i, '');
    return command === 'backlog' && Array.isArray(definition.args) && definition.args[0] === 'mcp' && definition.args[1] === 'start';
}
const tomlProgram = String.raw`
import json, os, sys, tomllib
text=sys.stdin.buffer.read().decode('utf-8')
try: data=tomllib.loads(text)
except Exception: print(json.dumps({'error':'malformed-toml'})); raise SystemExit
servers=data.get('mcp_servers')
if servers is None: print(json.dumps({'status':'absent'})); raise SystemExit
if not isinstance(servers,dict): print(json.dumps({'error':'unsupported-toml'})); raise SystemExit
def is_backlog(name, value):
    if name.lower()=='backlog': return True
    if not isinstance(value,dict) or not isinstance(value.get('command'),str): return False
    command=value['command'].replace('\\','/').rsplit('/',1)[-1].lower()
    if command.endswith(('.cmd','.exe')): command=command.rsplit('.',1)[0]
    args=value.get('args')
    return command=='backlog' and isinstance(args,list) and args[:2]==['mcp','start']
candidates={name for name,value in servers.items() if is_backlog(name,value)}
if not candidates: print(json.dumps({'status':'absent'})); raise SystemExit
# Mask multiline strings before recognizing table-header lines. The complete
# document has already passed tomllib, so this scanner only locates source spans.
masked=list(text); i=0; quote=None
while i < len(text):
    if quote:
        if text.startswith(quote,i):
            for j in range(i,i+3): masked[j]=' '
            i+=3; quote=None; continue
        masked[i]='\n' if text[i]=='\n' else ' '
        if quote=='\"\"\"' and text[i]=='\\' and i+1<len(text):
            i+=1; masked[i]='\n' if text[i]=='\n' else ' '
        i+=1; continue
    if text.startswith('\"\"\"',i) or text.startswith("'''",i):
        quote=text[i:i+3]
        for j in range(i,i+3): masked[j]=' '
        i+=3; continue
    if text[i] in ('\"',"'"):
        q=text[i]; masked[i]=' '; i+=1
        while i<len(text) and text[i]!='\n':
            c=text[i]; masked[i]=' '
            if q=='\"' and c=='\\' and i+1<len(text): i+=1; masked[i]=' '
            elif c==q: i+=1; break
            i+=1
        continue
    if text[i]=='#':
        while i<len(text) and text[i]!='\n': masked[i]=' '; i+=1
        continue
    i+=1
masked=''.join(masked)
headers=[]; offset=0
for line, raw in zip(masked.splitlines(True), text.splitlines(True)):
    stripped=line.strip()
    if stripped.startswith('['):
        header=raw.strip()
        # Use tomllib itself to interpret quoted/dotted and array table keys.
        try: probe=tomllib.loads(header+'\n__setup_marker__=true\n')
        except Exception: print(json.dumps({'error':'unsupported-toml'})); raise SystemExit
        paths=[]
        def find(value,prefix=()):
            if isinstance(value,dict):
                if value.get('__setup_marker__') is True: paths.append(prefix)
                for key,item in value.items():
                    if key!='__setup_marker__': find(item,prefix+(key,))
            elif isinstance(value,list):
                for item in value: find(item,prefix)
        find(probe)
        if len(paths)!=1: print(json.dumps({'error':'unsupported-toml'})); raise SystemExit
        headers.append((offset,paths[0]))
    offset+=len(raw)
spans=[]; represented=set()
for index,(start,parts) in enumerate(headers):
    end=headers[index+1][0] if index+1<len(headers) else len(text)
    if len(parts)>=2 and parts[0]=='mcp_servers' and parts[1] in candidates:
        represented.add(parts[1]); spans.append((start,end))
if represented != candidates:
    print(json.dumps({'error':'unsupported-toml'})); raise SystemExit
output=text
for start,end in reversed(spans): output=output[:start]+output[end:]
try: candidate=tomllib.loads(output)
except Exception: print(json.dumps({'error':'unsafe-toml-edit'})); raise SystemExit
expected=dict(data); expected_servers=dict(servers)
for name in candidates: expected_servers.pop(name,None)
if expected_servers: expected['mcp_servers']=expected_servers
else: expected.pop('mcp_servers',None)
if candidate != expected:
    print(json.dumps({'error':'unsafe-toml-edit'})); raise SystemExit
print(json.dumps({'status':'removed','output':output}))
`;
function transformTomlNative(text) {
    // Windows uses the built-in parser in Bun, already provisioned by WinGet.
    const parse = value => { try { return Bun.TOML.parse(value); } catch { fail('malformed-toml'); } };
    const data = parse(text), servers = data.mcp_servers;
    if (servers === undefined) return {status: 'absent'};
    if (!object(servers)) fail('unsupported-toml');
    const selected = new Set(Object.entries(servers).filter(([name, value]) => backlog(name, value)).map(([name]) => name));
    if (!selected.size) return {status: 'absent'};
    // Mask strings/comments without changing offsets. Interpret header keys
    // using the real TOML parser; validate the complete edited semantic tree.
    const masked = text.split('');
    let i = 0;
    while (i < text.length) {
        if (text[i] === '#') {
            while (i < text.length && text[i] !== '\n') masked[i++] = ' ';
        } else if (text[i] === '"' || text[i] === "'") {
            const quote = text[i], triple = text.slice(i, i + 3) === quote.repeat(3);
            const delimiter = triple ? quote.repeat(3) : quote;
            for (let j = 0; j < delimiter.length; j++) masked[i++] = ' ';
            while (i < text.length) {
                if (text.startsWith(delimiter, i)) {
                    for (let j = 0; j < delimiter.length; j++) masked[i++] = ' ';
                    break;
                }
                const escaped = text[i] === '\\' && quote === '"';
                if (text[i] !== '\n') masked[i] = ' ';
                i++;
                if (escaped && i < text.length) { if (text[i] !== '\n') masked[i] = ' '; i++; }
            }
        } else i++;
    }
    const headers = []; let offset = 0;
    for (const line of masked.join('').split(/(?<=\n)/)) {
        if (line.trimStart().startsWith('[')) {
            const raw = text.slice(offset, offset + line.length).trim();
            const probe = parse(raw + '\n__setup_marker__=true\n'), paths = [];
            const find = (value, parts) => {
                if (Array.isArray(value)) { for (const item of value) find(item, parts); }
                else if (object(value)) {
                    if (value.__setup_marker__ === true) paths.push(parts);
                    for (const [name, item] of Object.entries(value)) if (name !== '__setup_marker__') find(item, [...parts, name]);
                }
            };
            find(probe, []);
            if (paths.length !== 1) fail('unsupported-toml');
            headers.push({offset, parts: paths[0]});
        }
        offset += line.length;
    }
    const ranges = [], represented = new Set();
    for (let h = 0; h < headers.length; h++) {
        const {offset: start, parts} = headers[h];
        if (parts.length >= 2 && parts[0] === 'mcp_servers' && selected.has(parts[1])) {
            represented.add(parts[1]); ranges.push([start, headers[h + 1]?.offset ?? text.length]);
        }
    }
    if (represented.size !== selected.size) fail('unsupported-toml');
    let output = text;
    for (const [start, end] of ranges.reverse()) output = output.slice(0, start) + output.slice(end);
    const expected = {...data, mcp_servers: {...servers}};
    for (const name of selected) delete expected.mcp_servers[name];
    if (!Object.keys(expected.mcp_servers).length) delete expected.mcp_servers;
    if (!require('node:util').isDeepStrictEqual(parse(output), expected)) fail('unsafe-toml-edit');
    return {status: 'removed', output};
}
let tomlInterpreter;
function pythonForToml() {
    if (tomlInterpreter) return tomlInterpreter;
    if (process.platform === 'win32') fail('toml-parser-unavailable');
    const home = absolute(process.argv[2]);
    function* candidates() {
        yield* ['/usr/bin/python3', '/opt/homebrew/bin/python3', '/usr/local/bin/python3'];
        // Inspect inventories only if system/Homebrew Python is incompatible.
        // Never execute PATH shims or consult project version files.
        for (const root of [path.join(home, '.pyenv/versions'), path.join(home, '.local/share/mise/installs/python')]) {
            if (!info(root)) continue;
            safeBoundary(root, true);
            const versions = fs.readdirSync(root);
            if (versions.length > 256) fail('toml-parser-unavailable');
            for (const version of versions.filter(name => /^3\.\d+\.\d+t?$/.test(name)).sort().reverse()) yield path.join(root, version, 'bin/python3');
        }
    }
    for (const candidate of candidates()) {
        if (!info(candidate)) continue;
        safeBoundary(path.dirname(candidate), true);
        const resolved = fs.realpathSync(candidate), target = info(resolved);
        if (!target?.isFile() || ![0, process.getuid()].includes(target.uid) || target.mode & 0o022) fail('toml-parser-unavailable');
        safeBoundary(path.dirname(resolved), true);
        // Non-root executables must stay within an expected managed prefix.
        const allowed = ['/opt/homebrew/', '/usr/local/', path.join(home, '.pyenv/versions') + '/', path.join(home, '.local/share/mise/installs/python') + '/'];
        if (target.uid !== 0 && !allowed.some(prefix => resolved.startsWith(prefix))) fail('toml-parser-unavailable');
        const probe = spawnSync(resolved, ['-I', '-S', '-B', '-c', 'import tomllib; print("ready")'], {
            encoding: 'utf8', maxBuffer: 4096, timeout: 5000, cwd: '/', env: {PATH: '/usr/bin:/bin', LANG: 'C', LC_ALL: 'C'}
        });
        if (!probe.error && probe.status === 0 && probe.stdout.trim() === 'ready' && !probe.stderr) { tomlInterpreter = resolved; return resolved; }
    }
    fail('toml-parser-unavailable');
}
function transformToml(text) {
    if (typeof Bun !== 'undefined') return transformTomlNative(text);
    const command = pythonForToml();
    const result = spawnSync(command, ['-I', '-S', '-B', '-c', tomlProgram], {
        input: text, encoding: 'utf8', maxBuffer: 3 * 1024 * 1024, timeout: 10000, windowsHide: true,
        cwd: '/', env: {PATH: '/usr/bin:/bin', LANG: 'C', LC_ALL: 'C', PYTHONHASHSEED: '0'}
    });
    if (result.error || result.status !== 0 || result.stderr || !result.stdout) fail('toml-parser-failed');
    let report; try { report = JSON.parse(result.stdout); } catch { fail('toml-parser-failed'); }
    if (report.error) fail(report.error);
    if (!['absent','removed'].includes(report.status) || report.status === 'removed' && typeof report.output !== 'string') fail('toml-parser-failed');
    return report;
}
function planRetirement(records) {
    if (!Array.isArray(records) || records.length > 64) fail('malformed-metadata');
    return records.map(record => {
        if (!object(record) || !['json', 'codex-json', 'editor-json', 'toml'].includes(record.format) || typeof record.input !== 'string' || record.input.length > 3 * 1024 * 1024) fail('malformed-metadata');
        const bytes = Buffer.from(record.input, 'base64');
        if (bytes.length > 2 * 1024 * 1024 || bytes.toString('base64') !== record.input) fail('malformed-metadata');
        const text = new TextDecoder('utf-8', {fatal: true, ignoreBOM: true}).decode(bytes);
        let output = null;
        if (record.format === 'toml') {
            const report = transformToml(text);
            if (report.status === 'removed') output = report.output;
        } else {
            output = transformJson(text);
            const extraKey = record.format === 'codex-json' ? 'mcp_servers' : record.format === 'editor-json' ? 'mcp-servers' : null;
            if (extraKey) output = transformJson(output ?? text, extraKey) ?? output;
        }
        return output === null ? null : Buffer.from(output).toString('base64');
    });
}
// END BACKLOG_PURE_PLANNER
try {
    const logicalHome = absolute(process.argv[2]);
    const logicalBoundary = safeBoundary(logicalHome);
    const homeStat = info(logicalHome);
    if (!homeStat?.isDirectory() || homeStat.isSymbolicLink()) fail('unsafe-home');
    const home = fs.realpathSync(logicalHome);
    const trustedAlias = process.platform === 'linux' && logicalHome.startsWith('/home/') && home.startsWith('/var/home/') &&
        logicalBoundary.some(entry => entry.file === '/home' && entry.stat.isSymbolicLink() && trustedHomeAlias('/home', entry.stat));
    if (home !== logicalHome && !trustedAlias) fail('unsafe-home');
    const resolvedBoundary = safeBoundary(home);
    const key = value => process.platform === 'win32' ? value.toLowerCase() : value;
    const within = (file, base) => key(file) === key(base) || key(file).startsWith(key(base + path.sep));
    const profile = (value, fallback) => {
        const logical = absolute(value || path.join(logicalHome, fallback));
        if (!within(logical, logicalHome)) fail('unsafe-profile');
        return path.join(home, path.relative(logicalHome, logical));
    };
    const pi = profile(process.argv[3], '.pi/agent');
    const claude = profile(process.argv[4], '.claude');
    const codex = profile(process.argv[5], '.codex');
    const gemini = profile(process.argv[6], '.gemini');
    const files = [...new Set([
        path.join(home, '.config/mcp/mcp.json'), path.join(home, '.agents/mcp.json'), path.join(home, '.agents/mcp/mcp.json'),
        path.join(home, '.claude.json'), path.join(claude, '.claude.json'),
        path.join(home, '.claude/mcp.json'), path.join(home, '.claude/claude_desktop_config.json'),
        path.join(claude, 'mcp.json'), path.join(claude, 'claude_desktop_config.json'),
        path.join(home, 'Library/Application Support/Claude/claude_desktop_config.json'),
        path.join(home, '.cursor/mcp.json'), path.join(home, '.windsurf/mcp.json'),
        path.join(home, '.codex/config.json'), path.join(codex, 'config.json'),
        path.join(home, '.gemini/settings.json'), path.join(gemini, 'settings.json'),
        path.join(home, '.pi/agent/mcp.json'), path.join(pi, 'mcp.json')
    ])];
    const tomlFiles = [...new Set([path.join(home, '.codex/config.toml'), path.join(codex, 'config.toml')])];
    const records = [], boundaryMap = new Map([...logicalBoundary, ...resolvedBoundary].map(entry => [entry.file, entry.stat]));
    function read(file) {
        if (!within(file, home)) fail('unsafe-path');
        const stat = info(file); if (!stat) return null;
        if (!stat.isFile() || stat.isSymbolicLink() || stat.nlink > 1 || stat.size > 2 * 1024 * 1024) fail('unsafe-metadata');
        const boundaries = safeBoundary(path.dirname(file));
        for (const entry of boundaries) boundaryMap.set(entry.file, entry.stat);
        if (process.platform === 'win32') fail('native-wrapper-required');
        const fd = fs.openSync(file, fs.constants.O_RDWR | fs.constants.O_NOFOLLOW | fs.constants.O_NONBLOCK);
        const opened = fs.fstatSync(fd);
        if (!same(stat, opened) || !opened.isFile()) { fs.closeSync(fd); fail('metadata-changed'); }
        const buffer = rawRead(fd, opened);
        if (!same(opened, fs.fstatSync(fd)) || !same(opened, info(file))) { fs.closeSync(fd); fail('metadata-changed'); }
        const record = {file, stat: opened, fd, raw: buffer, text: new TextDecoder('utf-8', {fatal: true, ignoreBOM: true}).decode(buffer), output: null, boundaries}; records.push(record); return record;
    }
    for (const file of files) {
        const record = read(file); if (!record) continue;
        record.output = transformJson(record.text);
        const extraKey = [path.join(home, '.codex/config.json'), path.join(codex, 'config.json')].includes(file) ? 'mcp_servers' :
            [path.join(home, '.cursor/mcp.json'), path.join(home, '.windsurf/mcp.json')].includes(file) ? 'mcp-servers' : null;
        if (extraKey) record.output = transformJson(record.output ?? record.text, extraKey) ?? record.output;
    }
    for (const file of tomlFiles) {
        const record = records.find(item => item.file === file) || read(file); if (!record) continue;
        const report = transformToml(record.text); if (report.status === 'removed') record.output = report.output;
    }
    const writes = records.filter(record => record.output !== null);
    function verifyAll() {
        for (const [file, stat] of boundaryMap) if (!same(stat, info(file))) fail('boundary-changed');
        for (const record of records) {
            const current = fs.fstatSync(record.fd);
            if (!same(record.stat, current) || !same(record.stat, info(record.file)) || !rawRead(record.fd, current).equals(record.raw) || !same(record.stat, fs.fstatSync(record.fd))) fail('metadata-changed');
        }
        for (const record of writes) {
            if (record.stat.uid !== process.getuid() || record.stat.mode & 0o022) fail('unsafe-metadata');
            safeBoundary(path.dirname(record.file), true);
        }
    }
    verifyAll();
    phase = 'write';
    for (const record of writes) {
        verifyAll();
        const data = Buffer.from(record.output); let offset = 0;
        while (offset < data.length) {
            const count = fs.writeSync(record.fd, data, offset, data.length - offset, offset);
            if (!count) fail('short-write');
            offset += count;
        }
        fs.ftruncateSync(record.fd, data.length); fs.fsyncSync(record.fd);
        record.stat = fs.fstatSync(record.fd); record.raw = data;
        if (!same(record.stat, info(record.file))) fail('metadata-changed');
    }
    for (const record of records) fs.closeSync(record.fd);
    console.log(writes.length ? 'removed' : 'absent');
} catch (error) {
    const reason = error instanceof RetirementError ? error.message : 'filesystem-error';
    console.log(phase === 'write' ? 'write-failed' : reason);
    process.exitCode = 1;
}
// END BACKLOG_MCP_RETIREMENT
BACKLOG_MCP_RETIREMENT_JS
    then
        case "${_result}" in
            write-failed) print_error "Global Backlog MCP retirement failed during a write; review the affected global metadata before retrying." ;;
            unsafe-path|unsafe-home|unsafe-profile|unsafe-boundary|unsafe-metadata|malformed-metadata|duplicate-key|unsupported-json-number|malformed-toml|unsupported-toml|toml-parser-failed|toml-parser-unavailable|unsafe-toml-edit|metadata-changed|boundary-changed|native-wrapper-required|filesystem-error)
                print_error "Global Backlog MCP retirement preflight failed; no changes were made." ;;
            *) print_error "Global Backlog MCP retirement failed for an unknown controlled reason; review global metadata before retrying." ;;
        esac
        return 1
    fi
    case "${_result}" in
        removed) print_success "Retired global Backlog MCP registrations; repository-local configuration and task data were preserved." ;;
        absent) print_debug "Global Backlog MCP registrations are absent." ;;
        *) print_error "Global Backlog MCP retirement returned an invalid result."; return 1 ;;
    esac
}
# End global Backlog MCP retirement.

# Pi prose retirement. Keep this block identical in the Bash setup scripts.
# Secure only managed Pi directory boundaries; metadata remains with its validators.
prepare_pi_profile_permissions() {
    local _result="" _status=0
    if ! ensure_shared_node_runtime; then
        print_warning "Pi profile permissions failed: shared-runtime-unavailable."
        return 1
    fi
    # Bash 3.2 misparses quoted heredocs inside $(); redirect the group instead.
    {
        _result=$(env -u NODE_OPTIONS -u NODE_PATH node --input-type=commonjs - "${HOME}" "${PI_CODING_AGENT_DIR:-}" 2>/dev/null) || _status=$?
    } <<'PI_PROFILE_PERMISSIONS_JS'
// BEGIN PI_PROFILE_PERMISSIONS
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const {spawnSync} = require('node:child_process');
class PermissionError extends Error {}
const fail = code => { throw new PermissionError(code); };
function absolute(value) {
    if (!value || !path.isAbsolute(value) || value.split(/[\\/]/).some(p => p === '.' || p === '..')) fail('unsafe-path');
    return path.resolve(value);
}
function info(file) {
    try { return fs.lstatSync(file); }
    catch (error) { if (error.code === 'ENOENT') return null; throw error; }
}
function chain(file) {
    const result = [];
    for (let current = file; ; current = path.dirname(current)) {
        result.unshift(current);
        if (current === path.dirname(current)) return result;
    }
}
function systemHomeAlias(file, stat) {
    if (process.platform !== 'linux' || file !== '/home' || stat.uid !== 0) return false;
    if (!['var/home', '/var/home'].includes(fs.readlinkSync(file))) return false;
    return ['/', '/var', '/var/home'].every(dir => {
        const entry = info(dir);
        return entry && entry.isDirectory() && !entry.isSymbolicLink() && entry.uid === 0 && !(entry.mode & 0o022);
    });
}
// Node has no mkdirat binding. Use only the OS Python's isolated stdlib and an
// inherited, verified parent descriptor; never fall back to path-based creation.
const mkdirAtProgram = String.raw`
import os, stat, sys
try:
    if (os.mkdir not in os.supports_dir_fd or os.open not in os.supports_dir_fd or
            not all(hasattr(os, name) for name in ('O_DIRECTORY', 'O_NOFOLLOW'))):
        sys.exit(1)
    if sys.argv[1] == 'probe':
        print('ready')
        sys.exit(0)
    if sys.argv[1] != 'create':
        sys.exit(1)
    parent = os.fstat(3)
    if not stat.S_ISDIR(parent.st_mode) or parent.st_dev != int(sys.argv[3]) or parent.st_ino != int(sys.argv[4]):
        sys.exit(1)
    leaf = sys.argv[2]
    if not leaf or leaf in ('.', '..') or '/' in leaf:
        sys.exit(1)
    os.mkdir(leaf, mode=0o700, dir_fd=3)
    fd = os.open(leaf, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=3)
    try:
        created = os.fstat(fd)
        if not stat.S_ISDIR(created.st_mode) or created.st_uid != os.getuid():
            sys.exit(1)
        print('created:%d:%d' % (created.st_dev, created.st_ino))
    finally:
        os.close(fd)
except Exception:
    sys.exit(1)
`;
function mkdirAt(args, fd) {
    return spawnSync('/usr/bin/python3', ['-I', '-S', '-c', mkdirAtProgram, ...args], {
        env: {}, encoding: 'utf8', timeout: 15000, maxBuffer: 128,
        stdio: fd === undefined ? ['ignore', 'pipe', 'pipe'] : ['ignore', 'pipe', 'pipe', fd],
    });
}
function unixPrepare(logicalHome, selected) {
    const uid = process.getuid();
    function inspect(file, managed = false) {
        const stat = info(file);
        if (!stat && managed) return null;
        if (!stat) fail('missing-ancestor');
        if (stat.isSymbolicLink() && systemHomeAlias(file, stat)) return stat;
        if (!stat.isDirectory() || stat.isSymbolicLink()) fail('linked-or-nondirectory');
        if (managed ? stat.uid !== uid : ![0, uid].includes(stat.uid)) fail('foreign-owner');
        const stickyRoot = stat.uid === 0 && (stat.mode & 0o1000);
        if (!managed && (stat.mode & 0o022) && !stickyRoot) fail('unsafe-ancestor');
        return stat;
    }
    chain(logicalHome).forEach(file => inspect(file));
    if (info(logicalHome).uid !== uid) fail('foreign-owner');
    // Resolve only the verified account boundary (Linux /home -> /var/home).
    const home = fs.realpathSync(logicalHome);
    if (selected.startsWith(logicalHome + path.sep)) selected = path.join(home, path.relative(logicalHome, selected));
    if (!selected.startsWith(home + path.sep)) fail('outside-home');
    const managed = new Set([path.join(home, '.pi'), path.join(home, '.pi/agent'), selected]);
    const plan = new Map();
    for (const target of managed) {
        for (const file of chain(target)) {
            if (!plan.has(file)) plan.set(file, inspect(file, managed.has(file)));
        }
    }
    function unchanged() {
        for (const [file, before] of plan) {
            const after = inspect(file, managed.has(file));
            if (Boolean(before) !== Boolean(after) || before && (before.dev !== after.dev || before.ino !== after.ino || before.mode !== after.mode)) fail('directory-changed');
        }
    }
    if ([...managed].some(file => !plan.get(file))) {
        const probe = mkdirAt(['probe']);
        if (probe.status !== 0 || probe.stdout !== 'ready\n') fail('directory-create-unavailable');
    }
    // All default and active boundaries pass preflight before the first mutation.
    for (const file of [...managed].sort((a, b) => chain(a).length - chain(b).length)) {
        unchanged();
        if (!plan.get(file)) {
            const parent = path.dirname(file);
            const expected = plan.get(parent);
            const fd = fs.openSync(parent, fs.constants.O_RDONLY | fs.constants.O_DIRECTORY | fs.constants.O_NOFOLLOW);
            try {
                const pinned = fs.fstatSync(fd);
                if (!expected || expected.dev !== pinned.dev || expected.ino !== pinned.ino || expected.mode !== pinned.mode) fail('directory-changed');
                unchanged();
                const result = mkdirAt(['create', path.basename(file), String(pinned.dev), String(pinned.ino)], fd);
                const identity = /^created:([0-9]+):([0-9]+)\n$/.exec(result.stdout || '');
                if (result.status !== 0 || !identity) fail('directory-create-unavailable');
                const created = inspect(file, true);
                if (!created || created.dev !== Number(identity[1]) || created.ino !== Number(identity[2])) fail('directory-changed');
                plan.set(file, created);
            } finally { fs.closeSync(fd); }
        }
        const before = plan.get(file);
        if ((before.mode & 0o7777) === 0o700) continue;
        const fd = fs.openSync(file, fs.constants.O_RDONLY | fs.constants.O_DIRECTORY | fs.constants.O_NOFOLLOW);
        try {
            const opened = fs.fstatSync(fd);
            if (!opened.isDirectory() || opened.uid !== uid || before.ino !== opened.ino || before.dev !== opened.dev) fail('directory-changed');
            fs.fchmodSync(fd, 0o700); // Only the verified directory inode, never its contents.
            const after = fs.fstatSync(fd);
            if ((after.mode & 0o7777) !== 0o700) fail('permission-unverified');
            plan.set(file, after);
        } finally { fs.closeSync(fd); }
    }
    unchanged();
}
function windowsPrepare(home, selected) {
    // Use only the inbox PowerShell host and native APIs, never custom modules.
    const script = String.raw`
$ErrorActionPreference = 'Stop'
$PSModuleAutoLoadingPreference = 'None'
$pins = @{}
try {
    Import-Module (Join-Path $PSHOME 'Modules/Microsoft.PowerShell.Management/Microsoft.PowerShell.Management.psd1') -ErrorAction Stop
    Import-Module (Join-Path $PSHOME 'Modules/Microsoft.PowerShell.Utility/Microsoft.PowerShell.Utility.psd1') -ErrorAction Stop
    Import-Module (Join-Path $PSHOME 'Modules/Microsoft.PowerShell.Security/Microsoft.PowerShell.Security.psd1') -ErrorAction Stop
    # Root-relative native creation returns the created directory handle atomically.
    # Pinned ancestors deny write/delete sharing, preventing reparse/rename races.
    # SetKernelObjectSecurity changes only the pinned directory, never child ACLs.
    Add-Type -TypeDefinition @"
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using Microsoft.Win32.SafeHandles;
public static class PiDirectoryAcl {
    const uint FILE_SHARE_READ = 1, FILE_CREATE = 2;
    [StructLayout(LayoutKind.Sequential)]
    internal struct Info {
        public uint Attributes, CreatedLow, CreatedHigh, AccessLow, AccessHigh,
            WriteLow, WriteHigh, Volume, SizeHigh, SizeLow, Links, IndexHigh, IndexLow;
    }
    [StructLayout(LayoutKind.Sequential)]
    struct UnicodeString { public ushort Length, MaximumLength; public IntPtr Buffer; }
    [StructLayout(LayoutKind.Sequential)]
    struct ObjectAttributes {
        public uint Length;
        public IntPtr RootDirectory, ObjectName;
        public uint Attributes;
        public IntPtr SecurityDescriptor, SecurityQualityOfService;
    }
    [StructLayout(LayoutKind.Sequential)]
    struct IoStatusBlock { public IntPtr Status; public UIntPtr Information; }
    public sealed class Pinned : IDisposable {
        internal SafeFileHandle Handle;
        internal Info Before;
        internal Pinned(SafeFileHandle handle) {
            Handle = handle;
            try { Before = Read(handle); } catch { handle.Dispose(); throw; }
        }
        public void Dispose() { Handle.Dispose(); }
    }
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern SafeFileHandle CreateFile(string name, uint access, uint share,
        IntPtr security, uint creation, uint flags, IntPtr template);
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern bool GetFileInformationByHandle(SafeFileHandle file, out Info info);
    [DllImport("advapi32.dll", SetLastError=true)]
    static extern bool GetKernelObjectSecurity(SafeFileHandle file, uint information,
        byte[] descriptor, uint length, out uint needed);
    [DllImport("advapi32.dll", SetLastError=true)]
    static extern bool SetKernelObjectSecurity(SafeFileHandle file, uint information, byte[] descriptor);
    [DllImport("ntdll.dll")]
    static extern int NtCreateFile(out SafeFileHandle file, uint access,
        ref ObjectAttributes attributes, out IoStatusBlock ioStatus, IntPtr allocationSize,
        uint fileAttributes, uint share, uint disposition, uint options, IntPtr eaBuffer, uint eaLength);
    static Info Read(SafeFileHandle handle) {
        Info info;
        if (handle.IsInvalid || !GetFileInformationByHandle(handle, out info)) throw new Win32Exception();
        if ((info.Attributes & 0x410) != 0x10) throw new InvalidOperationException(); // directory, not reparse
        return info;
    }
    static bool SameIdentity(Info before, Info after) {
        return before.Volume == after.Volume && before.IndexHigh == after.IndexHigh && before.IndexLow == after.IndexLow;
    }
    static uint Access(bool managed, bool parent) {
        // READ_CONTROL + LIST_DIRECTORY + TRAVERSE; only approved parents need ADD_SUBDIRECTORY.
        return 0x20021u | (managed ? 0x40000u : 0u) | (parent ? 4u : 0u);
    }
    public static Pinned Pin(string name, bool managed, bool parent, bool missing) {
        // Reject Win32 aliases that could differ from the literal rooted native name.
        if (name.StartsWith("\\\\") || name.Length < 3 || name[1] != ':') throw new InvalidOperationException();
        foreach (string part in name.Substring(3).Split('\\')) {
            if (part.EndsWith(".") || part.EndsWith(" ") || part.Contains(":")) throw new InvalidOperationException();
        }
        var handle = CreateFile(name, Access(managed, parent), FILE_SHARE_READ,
            IntPtr.Zero, 3, 0x02200000, IntPtr.Zero); // OPEN_EXISTING, BACKUP_SEMANTICS, OPEN_REPARSE_POINT
        if (handle.IsInvalid) {
            int error = Marshal.GetLastWin32Error();
            handle.Dispose();
            if (missing && (error == 2 || error == 3)) return null;
            throw new Win32Exception(error);
        }
        return new Pinned(handle);
    }
    public static string Identity(Pinned pin) {
        Info after = Read(pin.Handle);
        if (!SameIdentity(pin.Before, after)) throw new InvalidOperationException();
        return after.Volume + ":" + after.IndexHigh + ":" + after.IndexLow;
    }
    public static DirectorySecurity Security(Pinned pin) {
        Identity(pin);
        uint needed;
        GetKernelObjectSecurity(pin.Handle, 7, null, 0, out needed); // owner, group, DACL
        if (needed == 0 || needed > 65536) throw new InvalidOperationException();
        var bytes = new byte[needed];
        if (!GetKernelObjectSecurity(pin.Handle, 7, bytes, needed, out needed)) throw new Win32Exception();
        var security = new DirectorySecurity();
        security.SetSecurityDescriptorBinaryForm(bytes);
        return security;
    }
    public static void Secure(Pinned pin, string expectedIdentity, string owner, byte[] descriptor) {
        if (Identity(pin) != expectedIdentity ||
            Security(pin).GetOwner(typeof(System.Security.Principal.SecurityIdentifier)).Value != owner)
            throw new InvalidOperationException();
        // Protected DACL only. This handle API does not propagate ACEs to children.
        if (!SetKernelObjectSecurity(pin.Handle, 0x80000004, descriptor)) throw new Win32Exception();
    }
    public static Pinned CreateLeaf(Pinned parent, string leaf, byte[] descriptor, bool createParent) {
        Identity(parent);
        if (String.IsNullOrEmpty(leaf) || leaf == "." || leaf == ".." || leaf.Length > 32767 ||
            leaf.IndexOfAny(new char[] {'\\', '/', ':'}) >= 0 || leaf.EndsWith(".") || leaf.EndsWith(" "))
            throw new InvalidOperationException();
        IntPtr text = Marshal.StringToHGlobalUni(leaf);
        IntPtr name = Marshal.AllocHGlobal(Marshal.SizeOf(typeof(UnicodeString)));
        GCHandle security = GCHandle.Alloc(descriptor, GCHandleType.Pinned);
        try {
            var unicode = new UnicodeString { Length = (ushort)(leaf.Length * 2),
                MaximumLength = (ushort)(leaf.Length * 2), Buffer = text };
            Marshal.StructureToPtr(unicode, name, false);
            var attributes = new ObjectAttributes { Length = (uint)Marshal.SizeOf(typeof(ObjectAttributes)),
                RootDirectory = parent.Handle.DangerousGetHandle(), ObjectName = name,
                Attributes = 0x40, SecurityDescriptor = security.AddrOfPinnedObject() };
            SafeFileHandle handle;
            IoStatusBlock io;
            int status = NtCreateFile(out handle, Access(true, createParent), ref attributes, out io,
                IntPtr.Zero, 0x10, FILE_SHARE_READ, FILE_CREATE, 0x00200001, IntPtr.Zero, 0);
            // DIRECTORY_FILE | OPEN_REPARSE_POINT, FILE_CREATE never opens/replaces an existing leaf.
            if (status != 0) {
                if (handle != null) handle.Dispose();
                throw new InvalidOperationException();
            }
            return new Pinned(handle);
        } finally {
            security.Free();
            Marshal.FreeHGlobal(name);
            Marshal.FreeHGlobal(text);
        }
    }
}
"@
    $homePath = $env:PI_PERMISSIONS_HOME
    $selected = $env:PI_PERMISSIONS_ACTIVE
    $owner = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
    $allowed = @($owner.Value, 'S-1-5-18', 'S-1-5-32-544')
    if (-not $selected.StartsWith($homePath.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'boundary' }
    $managed = @((Join-Path $homePath '.pi'), (Join-Path $homePath '.pi/agent'), $selected)
    $creationParents = @($managed | ForEach-Object { Split-Path -Parent $_ })
    $all = @{}
    foreach ($target in $managed) {
        $current = $target
        while ($current) { $all[$current] = $true; $current = Split-Path -Parent $current }
    }
    $ordered = @($all.Keys | Sort-Object Length)
    $plan = @{}
    function Inspect-Directory($file, $repair) {
        if ($null -eq $pins[$file]) {
            $pins[$file] = [PiDirectoryAcl]::Pin($file, $repair, ($file -in $creationParents), $repair)
        }
        if ($null -eq $pins[$file]) { return $null }
        $identity = [PiDirectoryAcl]::Identity($pins[$file])
        $acl = [PiDirectoryAcl]::Security($pins[$file])
        $sid = $acl.GetOwner([System.Security.Principal.SecurityIdentifier]).Value
        if ($repair -or $file -eq $homePath) {
            if ($sid -ne $owner.Value) { throw 'owner' }
        } elseif ($sid -notin ($allowed + @('S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464'))) { throw 'owner' }
        if (-not $repair) {
            $write = [System.Security.AccessControl.FileSystemRights]::Delete -bor [System.Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles -bor [System.Security.AccessControl.FileSystemRights]::ChangePermissions -bor [System.Security.AccessControl.FileSystemRights]::TakeOwnership
            if ($file -eq $homePath -or $file.StartsWith($homePath.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
                $write = $write -bor [System.Security.AccessControl.FileSystemRights]::Write
            }
            foreach ($rule in $acl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier])) {
                if ($rule.PropagationFlags -band [System.Security.AccessControl.PropagationFlags]::InheritOnly) { continue }
                if ($rule.AccessControlType -eq 'Allow' -and $rule.IdentityReference.Value -notin $allowed -and ($rule.FileSystemRights -band $write)) { throw 'access' }
            }
        }
        return @($identity, $acl.Sddl)
    }
    # Root first: every path ancestor remains pinned until the entire transaction ends.
    foreach ($file in $ordered) { $plan[$file] = Inspect-Directory $file ($file -in $managed) }
    function Assert-Unchanged {
        foreach ($file in $ordered) {
            $after = Inspect-Directory $file ($file -in $managed)
            if (($after -join '|') -cne ($plan[$file] -join '|')) { throw 'changed' }
        }
    }
    $private = [System.Security.AccessControl.DirectorySecurity]::new()
    $private.SetOwner($owner)
    $private.SetAccessRuleProtection($true, $false)
    foreach ($sid in $allowed) {
        $private.AddAccessRule([System.Security.AccessControl.FileSystemAccessRule]::new([System.Security.Principal.SecurityIdentifier]::new($sid), 'FullControl', 'Allow'))
    }
    foreach ($file in @($managed | Sort-Object -Unique | Sort-Object Length)) {
        Assert-Unchanged
        if ($null -eq $plan[$file]) {
            $parent = Split-Path -Parent $file
            $pins[$file] = [PiDirectoryAcl]::CreateLeaf($pins[$parent], [IO.Path]::GetFileName($file),
                $private.GetSecurityDescriptorBinaryForm(), ($file -in $creationParents))
        } else {
            [PiDirectoryAcl]::Secure($pins[$file], $plan[$file][0], $owner.Value, $private.GetSecurityDescriptorBinaryForm())
        }
        $plan[$file] = Inspect-Directory $file $true
        $acl = [PiDirectoryAcl]::Security($pins[$file])
        if (-not $acl.AreAccessRulesProtected) { throw 'unverified' }
        foreach ($rule in $acl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier])) {
            if ($rule.IdentityReference.Value -notin $allowed) { throw 'unverified' }
        }
    }
    Assert-Unchanged
    [Console]::Out.Write('prepared')
} catch { exit 1 }
finally { foreach ($pin in $pins.Values) { if ($null -ne $pin) { $pin.Dispose() } } }
`;
    const systemRoot = absolute(process.env.SystemRoot || 'C:\\Windows');
    const result = spawnSync(path.join(systemRoot, 'System32/WindowsPowerShell/v1.0/powershell.exe'),
        ['-NoProfile', '-NonInteractive', '-EncodedCommand', Buffer.from('& ([scriptblock]::Create([Console]::In.ReadToEnd()))', 'utf16le').toString('base64')], {
            input: script, // Avoid the Windows command-line length limit; no temporary script file.
            env: {SystemRoot: systemRoot, WINDIR: systemRoot, PI_PERMISSIONS_HOME: home, PI_PERMISSIONS_ACTIVE: selected},
            windowsHide: true, shell: false, encoding: 'utf8', timeout: 30000, maxBuffer: 1024,
        });
    if (result.status !== 0 || result.stdout !== 'prepared') fail('acl-unverified');
}
try {
    const home = absolute(process.argv[2]);
    const selected = absolute(process.argv[3] || path.join(home, '.pi/agent'));
    if (process.platform === 'win32') windowsPrepare(home, selected);
    else unixPrepare(home, selected);
    console.log('prepared');
} catch (error) {
    const native = new Set(['EACCES', 'EPERM', 'EROFS', 'ENOSPC', 'EDQUOT', 'ENOENT', 'ENOTDIR', 'ELOOP', 'EEXIST', 'EIO']);
    const reason = error instanceof PermissionError ? error.message : native.has(error?.code) ? error.code : 'operation-failed';
    console.log('failed:' + reason);
    process.exitCode = 1;
}
// END PI_PROFILE_PERMISSIONS
PI_PROFILE_PERMISSIONS_JS
    if [[ "${_status}" -eq 0 && "${_result}" == "prepared" ]]; then
        print_debug "Pi profile directories are private."
        return 0
    fi
    # Unknown output is never logged: it may contain a path or credential.
    case "${_result}" in
        failed:unsafe-path|failed:missing-ancestor|failed:linked-or-nondirectory|failed:foreign-owner|failed:unsafe-ancestor|failed:outside-home|failed:directory-changed|failed:directory-create-unavailable|failed:permission-unverified|failed:acl-unverified|failed:operation-failed|failed:EACCES|failed:EPERM|failed:EROFS|failed:ENOSPC|failed:EDQUOT|failed:ENOENT|failed:ENOTDIR|failed:ELOOP|failed:EEXIST|failed:EIO)
            print_warning "Pi profile permissions ${_result}." ;;
        *) print_warning "Pi profile permissions failed: unverified-result." ;;
    esac
    return 1
}

# Disable only the delegation tool; retain the Claude Bridge provider and settings.
disable_pi_askclaude() {
    local _result=""
    if ! command -v node &> /dev/null; then
        print_warning "AskClaude policy failed: node-unavailable."
        return 1
    fi
    if ! _result=$(env -u NODE_OPTIONS -u NODE_PATH node --input-type=commonjs - "${HOME}" "${PI_CODING_AGENT_DIR-${HOME}/.pi/agent}" 2>/dev/null <<'PI_ASKCLAUDE_POLICY_JS'
// BEGIN PI_ASKCLAUDE_POLICY
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
class PolicyError extends Error {}
const fail = code => { throw new PolicyError(code); };
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const own = (value, key) => Object.prototype.hasOwnProperty.call(value, key);
const same = (a, b) => a && b && a.dev === b.dev && a.ino === b.ino && a.mode === b.mode && a.nlink === b.nlink;
const key = file => process.platform === 'win32' ? file.toLowerCase() : file;
function info(file) {
    try { return fs.lstatSync(file); }
    catch (error) { if (error.code === 'ENOENT') return null; throw error; }
}
function absolute(value) {
    if (!value || !path.isAbsolute(value) || value.split(/[\\/]/).some(p => p === '.' || p === '..')) fail('unsafe-path');
    return path.resolve(value);
}
function read(file) {
    const stat = info(file);
    if (!stat) return { file, stat: null, text: '', value: {} };
    if (!stat.isFile() || stat.isSymbolicLink() || stat.nlink !== 1 || stat.size > 1024 * 1024 ||
        (process.getuid && stat.uid !== process.getuid())) fail('unsafe-file');
    const fd = fs.openSync(file, fs.constants.O_RDONLY | (fs.constants.O_NOFOLLOW || 0) | (fs.constants.O_NONBLOCK || 0));
    let text;
    try {
        if (!same(stat, fs.fstatSync(fd))) fail('changed-file');
        // Bounded descriptor read also rejects a file that grows after lstat.
        const buffer = Buffer.alloc(1024 * 1024 + 1);
        let size = 0, count;
        while (size < buffer.length && (count = fs.readSync(fd, buffer, size, buffer.length - size, null))) size += count;
        if (size > 1024 * 1024 || size !== stat.size) fail('changed-file');
        text = buffer.subarray(0, size).toString('utf8');
    } finally { fs.closeSync(fd); }
    let value;
    try { value = JSON.parse(text.replace(/^\uFEFF/, '')); }
    catch { fail('invalid-json'); }
    if (!object(value) || (own(value, 'askClaude') && (!object(value.askClaude) ||
        (own(value.askClaude, 'enabled') && typeof value.askClaude.enabled !== 'boolean')))) fail('invalid-config');
    return { file, stat, text, value };
}
try {
    // Profile creation/permissions belong to the preceding permission helper.
    // Resolve only the trusted account HOME boundary, never linked profiles.
    const logicalHome = absolute(process.argv[2]);
    const home = fs.realpathSync(logicalHome);
    const within = (file, base) => key(file).startsWith(key(base + path.sep));
    const normalize = value => {
        const file = absolute(value);
        return within(file, logicalHome) ? path.join(home, path.relative(logicalHome, file)) : file;
    };
    const profiles = [...new Map([path.join(home, '.pi', 'agent'), normalize(process.argv[3])].map(p => [key(p), p])).values()];
    const directories = new Map();
    for (const profile of profiles) {
        if (!within(profile, home)) fail('unsafe-path');
        for (let current = profile; ; current = path.dirname(current)) {
            const stat = info(current);
            if (!stat || !stat.isDirectory() || stat.isSymbolicLink() ||
                (process.getuid && stat.uid !== process.getuid())) fail('unsafe-directory');
            directories.set(current, stat);
            if (key(current) === key(home)) break;
        }
    }
    const checkDirectories = () => {
        for (const [dir, stat] of directories) if (!same(stat, info(dir))) fail('changed-directory');
    };
    // Preflight both profiles before either is changed, including already-disabled files.
    const records = profiles.map(profile => read(path.join(profile, 'claude-bridge.json')));
    let changed = false;
    for (const record of records) {
        checkDirectories();
        const current = read(record.file);
        if (current.text !== record.text || (record.stat ? !same(current.stat, record.stat) : current.stat)) fail('changed-file');
        // The bridge uses JSON.parse without stripping a BOM; write plain UTF-8.
        if (record.value.askClaude?.enabled === false && !record.text.startsWith('\uFEFF')) continue;
        record.value.askClaude = { ...record.value.askClaude, enabled: false };
        const text = JSON.stringify(record.value, null, 2) + '\n';
        const temporary = record.file + '.setup-' + crypto.randomBytes(12).toString('hex');
        let fd, created = false;
        try {
            fd = fs.openSync(temporary, 'wx', record.stat ? record.stat.mode & 0o777 : 0o600);
            created = true;
            fs.writeFileSync(fd, text);
            fs.closeSync(fd);
            fd = undefined;
            checkDirectories();
            const latest = read(record.file);
            if (latest.text !== record.text || (record.stat ? !same(latest.stat, record.stat) : latest.stat)) fail('changed-file');
            if (record.stat) fs.renameSync(temporary, record.file);
            else fs.linkSync(temporary, record.file); // Do not clobber a concurrently created config.
        } finally {
            if (fd !== undefined) fs.closeSync(fd);
            if (created && info(temporary)) fs.unlinkSync(temporary);
        }
        checkDirectories();
        if (read(record.file).text !== text) fail('verification-failed');
        changed = true;
    }
    console.log(changed ? 'disabled' : 'unchanged');
} catch (error) {
    console.log('askclaude:' + (error instanceof PolicyError ? error.message : 'filesystem-failed'));
    process.exitCode = 1;
}
// END PI_ASKCLAUDE_POLICY
PI_ASKCLAUDE_POLICY_JS
    ); then
        # Do not echo arbitrary helper output, exceptions, paths, or settings.
        print_warning "AskClaude policy failed; review global claude-bridge.json paths, JSON, and permissions."
        return 1
    fi
    case "${_result}" in
        disabled) print_success "AskClaude disabled in global Pi profiles; Claude Bridge access preserved." ;;
        unchanged) print_debug "AskClaude is already disabled in global Pi profiles." ;;
        *) print_warning "AskClaude policy failed: unrecognized-result."; return 1 ;;
    esac
}
# End Pi AskClaude policy.

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
    # Bash 3.2 misparses quoted heredocs inside $(); redirect the group instead.
    if ! {
        _result=$(node --input-type=commonjs - "${HOME}" "${_active_dir}")
    } <<'PI_PROSE_RETIREMENT_JS'
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
    then
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

# Refresh packages registered in the active global Pi profile after a read-only safety preflight.
refresh_pi_packages() {
    local _agent_dir="${PI_CODING_AGENT_DIR:-${HOME}/.pi/agent}"
    local _result=""
    local _output=""

    if ! command -v node &> /dev/null || ! command -v git &> /dev/null || ! command -v pi &> /dev/null; then
        print_warning "Pi package refresh prerequisites are unavailable. Required refresh is incomplete."
        return 1
    fi
    case "${PI_OFFLINE:-}" in
        1|[Tt][Rr][Uu][Ee]|[Yy][Ee][Ss])
            print_warning "Pi offline mode is enabled. Required package refresh is incomplete."
            return 1
            ;;
        *) ;;
    esac

    if ! _result=$(node - "${_agent_dir}" <<'PI_PACKAGE_REFRESH_JS'
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const agentDir = path.resolve(process.argv[2]);
const fail = () => { console.log('unsafe'); process.exitCode = 1; };
const lstat = file => { try { return fs.lstatSync(file); } catch (error) { if (error.code === 'ENOENT') return null; throw error; } };
function parseGit(source) {
    const trimmed = source.trim();
    const prefixed = trimmed.startsWith('git:');
    let value = prefixed ? trimmed.slice(4).trim() : trimmed;
    if (!prefixed && !/^(https?|ssh|git):\/\//i.test(value)) return null;
    // Native Pi accepts many hosted-git aliases. Only derive a checkout path for a
    // deliberately narrow canonical subset; ambiguous valid aliases fail closed.
    if (!value || /[%#?\\]/.test(value) || value.endsWith('/') || /\/(?:tree|blob|commit|releases?)\//i.test(value)) return false;
    let host = '', repoPath = '';
    const scp = value.match(/^git@([a-z0-9.-]+):([^@:]+\/[^/@:]+)(?:@([^/]+))?$/);
    if (scp) {
        host = scp[1]; repoPath = scp[2];
    } else if (/^(?:https?|ssh|git):\/\//i.test(value)) {
        let url; try { url = new URL(value); } catch { return false; }
        if ((url.username && url.username !== 'git') || url.password || url.search || url.hash || url.port) return false;
        host = url.hostname;
        const pathWithRef = url.pathname.replace(/^\/+/, '');
        const match = pathWithRef.match(/^([^/@]+\/[^/@]+?)(?:@([^/]+))?$/);
        if (!match) return false;
        repoPath = match[1];
    } else {
        const match = value.match(/^([a-z0-9.-]+)\/([^/@]+\/[^/@]+?)(?:@([^/]+))?$/);
        if (!match || (!match[1].includes('.') && match[1] !== 'localhost')) return false;
        host = match[1]; repoPath = match[2];
    }
    if (host.startsWith('www.') || repoPath.endsWith('.git.git')) return false;
    repoPath = repoPath.replace(/\.git$/, '');
    if (repoPath.endsWith('.git')) return false;
    const decoded = item => { try { return decodeURIComponent(item); } catch { return null; } };
    const unsafe = (item, slash) => {
        const decodedItem = decoded(item);
        return decodedItem === null || decodedItem !== item || [item, decodedItem].some(candidate => candidate.includes('\0') || candidate.startsWith('/') || (!slash && candidate.includes('/')) || candidate.split('/').includes('..'));
    };
    if (!host || host !== host.toLowerCase() || repoPath.split('/').length !== 2 || unsafe(host, false) || unsafe(repoPath, true)) return false;
    return { host, repoPath };
    }
try {
    for (const directory of [agentDir, path.join(agentDir, 'git')]) {
        const info = lstat(directory);
        if (info && (!info.isDirectory() || info.isSymbolicLink())) throw new Error('unsafe directory');
    }
    const settingsFile = path.join(agentDir, 'settings.json');
    const info = lstat(settingsFile);
    if (!info) { console.log('ready'); process.exit(0); }
    if (!info.isFile() || info.isSymbolicLink() || info.nlink !== 1 || info.size > 10 * 1024 * 1024) throw new Error('unsafe settings');
    const settings = JSON.parse(fs.readFileSync(settingsFile, 'utf8').replace(/^\uFEFF/, ''));
    if (!settings || typeof settings !== 'object' || Array.isArray(settings) || ('packages' in settings && !Array.isArray(settings.packages))) throw new Error('invalid settings');
    for (const entry of settings.packages || []) {
        const source = typeof entry === 'string' ? entry : entry && typeof entry === 'object' && !Array.isArray(entry) ? entry.source : null;
        if (typeof source !== 'string' || !source.trim()) throw new Error('invalid package');
        const parsed = parseGit(source);
        if (parsed === false) throw new Error('invalid git source');
        if (!parsed) continue;
        for (const name of ['GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE', 'GIT_COMMON_DIR', 'GIT_OBJECT_DIRECTORY', 'GIT_ALTERNATE_OBJECT_DIRECTORIES']) {
            if (process.env[name]) throw new Error('redirected git state');
        }
        const gitRoot = path.resolve(agentDir, 'git');
        const components = [parsed.host, ...parsed.repoPath.split('/')];
        let cursor = gitRoot;
        let checkoutMissing = false;
        for (const component of components) {
            cursor = path.join(cursor, component);
            const part = lstat(cursor);
            if (!part) { checkoutMissing = true; break; }
            if (!part.isDirectory() || part.isSymbolicLink()) throw new Error('unsafe checkout path');
        }
        const checkout = path.resolve(gitRoot, ...components);
        if (!checkout.startsWith(gitRoot + path.sep)) throw new Error('unsafe checkout');
        if (checkoutMissing) continue;
        const dotGit = path.join(checkout, '.git');
        const dotGitInfo = lstat(dotGit);
        if (!dotGitInfo || !dotGitInfo.isDirectory() || dotGitInfo.isSymbolicLink()) throw new Error('unsafe git metadata');
        const gitEnv = { ...process.env, GIT_TERMINAL_PROMPT: '0', GIT_OPTIONAL_LOCKS: '0' };
        const inspect = args => spawnSync('git', ['-c', 'core.fsmonitor=false', ...args], {
            cwd: checkout, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'], timeout: 15000, env: gitEnv,
        });
        const identity = inspect(['rev-parse', '--show-toplevel', '--absolute-git-dir', '--git-common-dir']);
        if (identity.error || identity.status !== 0 || identity.signal || identity.stdout.length > 4096) throw new Error('unverified repository');
        const identityLines = identity.stdout.trim().split(/\r?\n/);
        if (identityLines.length !== 3 || path.resolve(identityLines[0]) !== checkout ||
            path.resolve(identityLines[1]) !== dotGit || path.resolve(checkout, identityLines[2]) !== dotGit) throw new Error('unexpected repository identity');
        const status = inspect(['status', '--porcelain=v1', '-z', '--untracked-files=all', '--ignored=matching']);
        if (status.error || status.status !== 0 || status.signal || status.stdout.length > 1024 * 1024 || status.stdout.length > 0) throw new Error('unverified or modified checkout');
    }
    console.log('ready');
    } catch { fail(); }
PI_PACKAGE_REFRESH_JS
    ); then
        print_warning "Pi package refresh safety preflight failed. Registered Git checkouts and active-profile metadata were left unchanged."
        return 1
    fi
    if [[ "${_result}" != "ready" ]]; then
        print_warning "Pi package refresh safety preflight returned an invalid result."
        return 1
    fi

    print_message "Refreshing packages in the active global Pi profile..."
    if _output=$(pi update --extensions --no-approve 2>&1); then
        print_success "Pi packages refreshed in the active global profile."
        return 0
    fi
    print_warning "Pi package refresh failed. Required refresh is incomplete."
    return 1
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
    [[ "${PI_PROFILE_MUTATIONS_BLOCKED:-0}" -eq 1 ]] && return 0
    matt_pocock_skill_policy ownership
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


# Shared policy for full-suite inventory, safe retirement, and Pi ownership.
matt_pocock_skill_policy() {
    if ! command -v node &> /dev/null; then
        print_warning "Node.js is unavailable; managed skill policy cannot run."
        return 1
    fi
    env -u NODE_OPTIONS -u NODE_PATH node --input-type=commonjs - \
        "${HOME}" "${PI_CODING_AGENT_DIR:-}" "${PI_PROFILE_MUTATIONS_BLOCKED:-0}" "$@" <<'MANAGED_SKILL_POLICY_JS'
    // Shared by all six standalone setup scripts. Never execute installed skills.
    const fs = require('node:fs');
    const path = require('node:path');
    const [homeInput, activePiInput, blocked, mode, reportFile] = process.argv.slice(2);
    const env = process.env;
    const fail = reason => { throw new Error(reason); };
    const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
    const nameOK = name => typeof name === 'string' && /^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(name) && name.length <= 64;
    const unique = values => [...new Set(values)];
    const known = [
        'ask-matt', 'code-review', 'codebase-design', 'diagnosing-bugs', 'domain-modeling',
        'grill-with-docs', 'implement', 'improve-codebase-architecture', 'prototype', 'research',
        'pr', 'setup-matt-pocock-skills', 'tdd', 'to-spec', 'to-tickets',
        'triage', 'wayfinder', 'wizard', 'claude-handoff', 'implement-spec', 'loop-me', 'retro',
        'setup-ts-deep-modules', 'writing-beats', 'writing-fragments', 'writing-shape',
        'git-guardrails-claude-code', 'migrate-to-shoehorn', 'scaffold-exercises', 'setup-pre-commit',
        'grill-me', 'grilling', 'handoff', 'teach', 'to-questionnaire', 'wait-what', 'writing-for-agents'
    ];
    // Upstream-retired names remain managed, but ordinary installs preserve copies.
    const historical = ['resolving-merge-conflicts'];
    const obsolete = ['diagnose', 'zoom-out'];
    function stat(file) {
        try { return fs.lstatSync(file); }
        catch (error) { if (error.code === 'ENOENT') return null; throw error; }
    }
    // The only ancestor link allowed is Bazzite's root-owned system /home alias.
    function systemHomeAlias(file, st) {
        if (process.platform !== 'linux' || file !== '/home' || st.uid !== 0) return false;
        if (!['var/home', '/var/home'].includes(fs.readlinkSync(file))) return false;
        return ['/', '/var', '/var/home'].every(dir => {
            const item = stat(dir);
            return item && item.isDirectory() && !item.isSymbolicLink() && item.uid === 0 && !(item.mode & 0o022);
        });
    }
    function absolute(file) {
        if (!file || !path.isAbsolute(file) || file.split(/[\\/]/).includes('..')) fail('unsafe-path');
        const resolved = path.resolve(file);
        if (resolved === path.parse(resolved).root) fail('unsafe-path');
        return resolved;
    }
    function directory(file) {
        const parent = path.dirname(file);
        if (parent !== file) directory(parent);
        const st = stat(file);
        if (!st) return;
        if (st.isSymbolicLink()) {
            if (!systemHomeAlias(file, st)) fail('linked-directory');
        } else if (!st.isDirectory()) fail('not-directory');
    }
    function owned(file) {
        const st = stat(file);
        if (st && process.platform !== 'win32' && st.uid !== process.getuid()) fail('wrong-owner');
    }
    function jsonFile(file) {
        directory(path.dirname(file));
        const st = stat(file);
        if (!st) return null;
        if (!st.isFile() || st.isSymbolicLink() || st.nlink !== 1) fail('unsafe-metadata');
        owned(file);
        let value;
        try { value = JSON.parse(fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, '')); }
        catch { fail('malformed-metadata'); }
        if (!object(value)) fail('malformed-metadata');
        return value;
    }
    function writeJson(file, value) {
        directory(path.dirname(file));
        jsonFile(file);
        fs.mkdirSync(path.dirname(file), {recursive: true, mode: 0o700});
        const temp = file + '.setup-' + require('node:crypto').randomUUID();
        try {
            fs.writeFileSync(temp, JSON.stringify(value, null, 2) + '\n', {flag: 'wx', mode: stat(file)?.mode & 0o777 || 0o600});
            fs.renameSync(temp, file);
        } finally { if (stat(temp)) fs.unlinkSync(temp); }
    }
    // Preflight the complete bounded tree before removal. Links are unlinked, never traversed.
    function removable(file) {
        directory(path.dirname(file));
        const st = stat(file);
        if (!st) return;
        owned(file);
        if (st.isSymbolicLink()) return;
        if (st.isDirectory()) {
            for (const entry of fs.readdirSync(file)) removable(path.join(file, entry));
        } else if (!st.isFile()) fail('unsupported-file');
    }
    function remove(file) {
        removable(file);
        const st = stat(file);
        if (!st) return;
        if (st.isDirectory() && !st.isSymbolicLink()) {
            for (const entry of fs.readdirSync(file)) remove(path.join(file, entry));
            fs.rmdirSync(file);
        } else fs.unlinkSync(file);
        if (stat(file)) fail('removal-failed');
    }
    function copiedTree(file) {
        const st = stat(file);
        if (!st || st.isSymbolicLink()) fail('invalid-skill-copy');
        owned(file);
        if (st.isDirectory()) {
            for (const entry of fs.readdirSync(file)) copiedTree(path.join(file, entry));
        } else if (!st.isFile()) fail('invalid-skill-copy');
    }
    function sameTree(left, right) {
        const a = stat(left), b = stat(right);
        if (!a || !b || a.isSymbolicLink() || b.isSymbolicLink()) return false;
        if (a.isFile() && b.isFile()) return fs.readFileSync(left).equals(fs.readFileSync(right));
        if (!a.isDirectory() || !b.isDirectory()) return false;
        const names = fs.readdirSync(left).sort(), other = fs.readdirSync(right).sort();
        return JSON.stringify(names) === JSON.stringify(other) && names.every(name => sameTree(path.join(left, name), path.join(right, name)));
    }
    try {
        if (mode === 'dispose') {
            const stage = absolute(reportFile);
            const tempRoot = fs.realpathSync(require('node:os').tmpdir());
            if (path.dirname(stage) !== tempRoot || !/^setup-matt-pocock-[a-zA-Z0-9]+$/.test(path.basename(stage))) fail('unsafe-stage');
            directory(tempRoot);
            const st = stat(stage);
            if (st) {
                owned(stage);
                if (!st.isSymbolicLink() && (!st.isDirectory() || process.platform !== 'win32' && (st.mode & 0o077))) fail('unsafe-stage');
                // Explicit unlink traversal also avoids legacy PowerShell junction
                // recursion. A replaced stage root is unlinked, never followed.
                remove(stage);
            }
            process.exit(0);
        }
        const home = absolute(homeInput);
        directory(home);
        const profile = (value, fallback) => {
            const result = absolute(value || path.join(home, fallback));
            if (result === home) fail('unsafe-path');
            return result;
        };
        const defaultPi = path.join(home, '.pi/agent');
        // Do not inspect rejected Pi profiles, including a rejected custom override.
        const piDirs = blocked === '1' ? [] : unique([defaultPi, profile(activePiInput, '.pi/agent')]);
        const claude = profile(env.CLAUDE_CONFIG_DIR, '.claude');
        const shared = path.join(home, '.agents/skills');
        const installDirs = unique([path.join(claude, 'skills'), shared]);
        const allDirs = unique([
            shared, path.join(home, '.claude/skills'), path.join(claude, 'skills'),
            path.join(home, '.codex/skills'), path.join(profile(env.CODEX_HOME, '.codex'), 'skills'),
            path.join(home, '.gemini/skills'), path.join(home, '.cursor/skills'),
            ...piDirs.map(dir => path.join(dir, 'skills'))
        ]);
        const manifestFile = path.join(home, '.agents/.setup-matt-pocock-skills.json');
        const manifest = jsonFile(manifestFile);
        if (manifest && (manifest.version !== 1 || !Array.isArray(manifest.skills) || !manifest.skills.every(nameOK))) fail('invalid-inventory');
        const lockPaths = unique([
            path.join(home, '.agents/.skill-lock.json'),
            ...(env.XDG_STATE_HOME ? [path.join(absolute(env.XDG_STATE_HOME), 'skills/.skill-lock.json')] : [])
        ]);
        const locks = lockPaths.map(file => {
            const data = jsonFile(file);
            if (data && (data.version !== 3 || !object(data.skills) || !Object.values(data.skills).every(object))) fail('invalid-skill-lock');
            return {file, data};
        });
        const tracked = locks.flatMap(({data}) => Object.entries(data?.skills || {})
            .filter(([, entry]) => entry.source === 'mattpocock/skills').map(([name]) => name));
        if (!tracked.every(nameOK)) fail('invalid-inventory');
        const inventory = unique([...known, ...historical, ...(manifest?.skills || []), ...tracked]);
        const checkDirs = dirs => dirs.forEach(dir => { directory(dir); owned(dir); });
        const preflight = names => {
            checkDirs(installDirs);
            for (const dir of installDirs) {
                for (const name of names) {
                    const target = path.join(dir, name);
                    if (stat(target)?.isSymbolicLink()) fail('linked-install-target');
                    if (stat(target)) copiedTree(target);
                }
            }
        };
        const cleanup = (names, dirs, extraPaths = []) => {
            checkDirs(dirs);
            const paths = dirs.flatMap(dir => names.map(name => path.join(dir, name))).concat(extraPaths);
            paths.forEach(removable);
            paths.forEach(remove);
            for (const {file, data} of locks) {
                if (!data) continue;
                let changed = false;
                for (const name of names) {
                    if (Object.hasOwn(data.skills, name)) { delete data.skills[name]; changed = true; }
                }
                if (changed) writeJson(file, data);
            }
        };
        if (mode === 'names') {
            process.stdout.write(inventory.join('\n') + '\n');
        } else if (['remove-pr-lens', 'remove-simple-english', 'remove-show-me'].includes(mode)) {
            const skill = mode.slice('remove-'.length);
            // Direct Markdown skills are also discoverable in Pi's own skills directory.
            cleanup([skill], allDirs, piDirs.map(dir => path.join(dir, 'skills', skill + '.md')));
            if (blocked === '1') fail('pi-profiles-blocked');
        } else if (mode === 'remove-matt' || mode === 'remove-obsolete') {
            cleanup(mode === 'remove-matt' ? unique([...inventory, ...obsolete]) : obsolete, allDirs);
            // Retain inventory for offline retries and custom profiles selected on a later run.
        } else if (mode === 'preflight') {
            // Known managed names fail early. The complete native selection, including
            // new upstream names, is checked again before promotion, never after it.
            preflight(inventory);
        } else if (mode === 'stage') {
            const tempRoot = fs.realpathSync(require('node:os').tmpdir());
            directory(tempRoot);
            process.stdout.write(fs.mkdtempSync(path.join(tempRoot, 'setup-matt-pocock-')) + '\n');
        } else if (mode === 'promote') {
            // Native --list cannot emit JSON. One isolated native install is both
            // discovery and the source snapshot: do not fetch/reselect during promotion.
            const stage = absolute(reportFile);
            directory(stage);
            owned(stage);
            if (!stat(stage)?.isDirectory() || (process.platform !== 'win32' && (stat(stage).mode & 0o077))) fail('unsafe-stage');
            if (path.dirname(stage) !== fs.realpathSync(require('node:os').tmpdir()) ||
                !/^setup-matt-pocock-[a-zA-Z0-9]+$/.test(path.basename(stage))) fail('unsafe-stage');
            const sourceDirs = [path.join(stage, '.claude/skills'), path.join(stage, '.agents/skills')];
            checkDirs(sourceDirs);
            const reportPath = path.join(stage, 'report.json');
            const reportStat = stat(reportPath);
            if (!reportStat?.isFile() || reportStat.isSymbolicLink() || reportStat.nlink !== 1) fail('invalid-install-report');
            owned(reportPath);
            let report;
            try { report = JSON.parse(fs.readFileSync(reportPath, 'utf8').replace(/^\uFEFF/, '')); }
            catch { fail('invalid-install-report'); }
            if (!Array.isArray(report) || report.length === 0) fail('invalid-install-report');
            const names = [];
            for (const entry of report) {
                if (!object(entry) || !nameOK(entry.name) || entry.status !== 'installed' || entry.source !== 'mattpocock/skills' ||
                    entry.scope !== 'global' || entry.mode !== 'copy' || !Array.isArray(entry.agents) ||
                    entry.agents.length !== 3 || !['Claude Code', 'Codex', 'Gemini CLI'].every(agent => entry.agents.includes(agent))) fail('invalid-install-report');
                if (names.includes(entry.name)) fail('invalid-install-report');
                names.push(entry.name);
                for (const dir of sourceDirs) {
                    const skill = path.join(dir, entry.name);
                    copiedTree(skill);
                    const md = stat(path.join(skill, 'SKILL.md'));
                    if (!md?.isFile() || md.size === 0) fail('invalid-skill-copy');
                }
            }
            // A validation floor, never an installation allowlist: newly discovered
            // skills are accepted too. Retired/renamed baseline skills need review.
            if (!known.every(name => names.includes(name))) fail('incomplete-suite');
            for (const dir of sourceDirs) {
                const entries = fs.readdirSync(dir);
                if (entries.length !== names.length || !entries.every(name => names.includes(name))) fail('invalid-install-report');
            }
            if (!names.every(name => sameTree(path.join(sourceDirs[0], name), path.join(sourceDirs[1], name)))) fail('invalid-skill-copy');
            const stageLock = jsonFile(path.join(stage, '.state/skills/.skill-lock.json'));
            if (!stageLock || stageLock.version !== 3 || !object(stageLock.skills) ||
                Object.keys(stageLock.skills).length !== names.length || !names.every(name => {
                    const entry = stageLock.skills[name];
                    return object(entry) && entry.source === 'mattpocock/skills' && entry.sourceType === 'github' &&
                        entry.sourceUrl === 'https://github.com/mattpocock/skills.git';
                })) fail('invalid-skill-lock');
            // All report, snapshot, metadata, and selected destinations must pass
            // before touching either real copy. Unrelated entries are never traversed.
            preflight(unique([...inventory, ...names]));
            for (const dir of installDirs) {
                directory(dir);
                fs.mkdirSync(dir, {recursive: true, mode: 0o700});
                for (const name of names) {
                    const source = path.join(sourceDirs[0], name), target = path.join(dir, name);
                    remove(target);
                    fs.cpSync(source, target, {recursive: true, dereference: false, errorOnExist: true, force: false});
                    copiedTree(target);
                    if (!sameTree(source, target)) fail('invalid-skill-copy');
                }
            }
            // Merge only this run's native records into the selected global lock;
            // retain unrelated entries, preferences, and the other legacy lock.
            const selectedLock = locks[locks.length - 1];
            const data = selectedLock.data || {version: 3, skills: {}};
            for (const name of names) {
                const entry = {...stageLock.skills[name]};
                if (data.skills[name]?.installedAt !== undefined) entry.installedAt = data.skills[name].installedAt;
                data.skills[name] = entry;
            }
            writeJson(selectedLock.file, data);
            writeJson(manifestFile, {version: 1, skills: unique([...inventory, ...names])});
        } else if (mode === 'ownership') {
            if (blocked !== '1') {
                checkDirs([shared, ...piDirs.flatMap(dir => [dir, path.join(dir, 'skills')])]);
                const settings = piDirs.map(dir => {
                    const file = path.join(dir, 'settings.json');
                    const data = jsonFile(file) || {};
                    if (data.skills !== undefined && (!Array.isArray(data.skills) || !data.skills.every(value => typeof value === 'string'))) fail('invalid-settings');
                    return {file, data};
                });
                const names = inventory;
                const duplicates = piDirs.flatMap(dir => names.map(name => ({file: path.join(dir, 'skills', name), canonical: path.join(shared, name)})));
                const equal = duplicates.filter(({file, canonical}) => sameTree(file, canonical));
                equal.forEach(({file}) => removable(file));
                equal.forEach(({file}) => remove(file));
                const excluded = ['pi-goal-writer', 'autoresearch-create', 'autoresearch-finalize', 'autoresearch-hooks']
                    .map(name => '!' + path.join(shared, name) + '/**')
                    .concat(duplicates.map(({file}) => '!' + file + '/**'));
                for (const {file, data} of settings) {
                    const before = JSON.stringify(data);
                    data.skills = unique([...(data.skills || []), ...excluded]);
                    if (JSON.stringify(data) !== before) writeJson(file, data);
                }
            }
        } else fail('unknown-operation');
    } catch (error) {
        const allowed = ['unsafe-path', 'linked-directory', 'not-directory', 'wrong-owner', 'unsafe-metadata', 'malformed-metadata',
            'unsupported-file', 'removal-failed', 'invalid-skill-copy', 'invalid-inventory', 'invalid-skill-lock',
            'pi-profiles-blocked', 'linked-install-target', 'invalid-install-report', 'incomplete-suite', 'invalid-settings', 'unsafe-stage', 'unknown-operation'];
        const reason = allowed.includes(error.message) ? error.message : ['EACCES', 'EPERM', 'ENOENT', 'ENOSPC', 'EROFS', 'EBUSY'].includes(error.code) ? error.code : 'operation-failed';
        process.stderr.write('Managed skills: ' + reason + '.\n');
        process.exitCode = 1;
    }
MANAGED_SKILL_POLICY_JS
}

# The full repository is selected by the installer. This inventory is for cleanup.
matt_pocock_skills() {
    matt_pocock_skill_policy names
}

matt_pocock_obsolete_skills() {
    printf '%s\n' diagnose zoom-out
}

matt_pocock_all_managed_skills() {
    matt_pocock_skills || return 1
    matt_pocock_obsolete_skills
}

matt_pocock_skills_disabled() {
    [[ "${BAN_MATT_POCOCK_SKILLS:-}" == "1" || "${BAN_MATT_POCKOCK_SKILLS:-}" == "1" ]]
}

remove_matt_pocock_skills() {
    matt_pocock_skill_policy remove-matt
}

remove_obsolete_matt_pocock_skills() {
    matt_pocock_skill_policy remove-obsolete
}

# Install all upstream categories, including experimental skills, for four agents.
setup_matt_pocock_skills() {
    local _stage="" _npm_userconfig="" _npm_globalconfig=""
    local _matt_failed=0
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
        return 1
    fi
    matt_pocock_skill_policy preflight || return 1
    # Preserve the effective npm policy while the native CLI writes only to a
    # disposable HOME. Keep cwd and all other npm configuration unchanged.
    if ! _npm_userconfig=$(npm config get userconfig 2>/dev/null) || [[ -z "${_npm_userconfig}" ]] ||
        ! _npm_globalconfig=$(npm config get globalconfig 2>/dev/null) || [[ -z "${_npm_globalconfig}" ]]; then
        print_warning "Cannot preserve npm configuration for staged skill installation."
        return 1
    fi
    _stage=$(matt_pocock_skill_policy stage) || return 1
    print_message "Installing/updating the full Matt Pocock skill suite for Claude Code, Codex, Gemini CLI, and Pi..."
    if ! HOME="${_stage}" USERPROFILE="${_stage}" \
        CLAUDE_CONFIG_DIR="${_stage}/.claude" CODEX_HOME="${_stage}/.codex" PI_CODING_AGENT_DIR="${_stage}/.pi/agent" \
        XDG_STATE_HOME="${_stage}/.state" XDG_CONFIG_HOME="${_stage}/.config" \
        XDG_CACHE_HOME="${_stage}/.cache" XDG_DATA_HOME="${_stage}/.local/share" \
        npm_config_userconfig="${_npm_userconfig}" NPM_CONFIG_USERCONFIG="${_npm_userconfig}" \
        npm_config_globalconfig="${_npm_globalconfig}" NPM_CONFIG_GLOBALCONFIG="${_npm_globalconfig}" \
        npx --yes skills@latest add mattpocock/skills --global \
        --agent claude-code --agent codex --agent gemini-cli \
        --skill '*' --full-depth --copy --yes --json < /dev/null > "${_stage}/report.json" 2>/dev/null; then
        print_warning "Failed to install the full Matt Pocock skill suite."
        _matt_failed=1
    elif ! matt_pocock_skill_policy promote "${_stage}"; then
        _matt_failed=1
    elif ! remove_obsolete_matt_pocock_skills; then
        _matt_failed=1
    fi
    matt_pocock_skill_policy dispose "${_stage}" || _matt_failed=1
    if [[ "${_matt_failed}" -eq 0 ]]; then
        print_success "Full Matt Pocock skill suite installed/updated through copied global skills."
    fi
    return "${_matt_failed}"
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

    if [[ "${PI_PROFILE_MUTATIONS_BLOCKED:-0}" -ne 1 && -d "${_default_agent_dir}" ]]; then
        if compound_path_is_within "${_default_agent_dir}" "${HOME}"; then
            _agent_dirs+=("${_default_agent_dir}")
        else
            print_warning "Skipping Pi cleanup outside ${HOME}: ${_default_agent_dir}"
        fi
    fi

    if [[ "${PI_PROFILE_MUTATIONS_BLOCKED:-0}" -ne 1 && "${_active_agent_dir}" != "${_default_agent_dir}" && -d "${_active_agent_dir}" ]]; then
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
    opencode_guarded_brew_upgrade > /dev/null || upgrade_status=$?
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

# BEGIN BB PLUGIN REFRESH
# Native main-server plugin refresh only; independent of preparation and Pi gates.
# Version 2 | Last changed: Report controlled BB plugin refresh refusal reasons
refresh_bb_plugins() {
    local _bb_refresh_output _bb_refresh_status=0 _bb_refresh_line
    local _bb_refresh_operation _bb_refresh_reason _bb_refresh_diagnostic=0
    print_section 'BB Plugin Refresh'
    if [[ ! -x /usr/bin/python3 ]]; then
        print_error 'BB plugin refresh failed: preflight / python-unavailable.'
        return 1
    fi
    # No inherited CLI/server URL is used, and no BB executable is invoked.
    _bb_refresh_output=$(bb_plugin_refresh_payload "${1:-ready}" 2>/dev/null) || _bb_refresh_status=$?
    if [[ ${#_bb_refresh_output} -gt 16384 || -z "${_bb_refresh_output}" ]]; then
        print_error 'BB plugin refresh failed: helper-result / unverified-result.'
        return 1
    fi
    while IFS= read -r _bb_refresh_line; do
        case "${_bb_refresh_line}" in
            'BB_PLUGIN_REFRESH absent') print_debug 'No verified local BB main server requires plugin refresh.' ;;
            'BB_PLUGIN_REFRESH readiness-deferred') print_warning 'Managed BB plugin refresh deferred because normal server readiness failed.' ;;
            'BB_PLUGIN_REFRESH stopped') print_warning 'Stopped local BB main-server plugin refresh deferred; no server was started.' ;;
            'BB_PLUGIN_REFRESH safe-mode') print_warning 'BB plugin refresh deliberately deferred: native safe mode remains enabled.' ;;
            'BB_PLUGIN_REFRESH checked') print_message 'BB native plugin check completed; pinned, local and incompatible selections preserved.' ;;
            'BB_PLUGIN_REFRESH updated') print_message 'BB native plugin updates processed; final verification determines success.' ;;
            'BB_PLUGIN_REFRESH failed') print_error 'BB plugin refresh failed: helper-result / unverified-result.'; _bb_refresh_status=1; _bb_refresh_diagnostic=1 ;;
            'BB_PLUGIN_REFRESH failed '*)
                # Validate both fields in full before displaying any helper bytes.
                if [[ ! "${_bb_refresh_line}" =~ ^BB_PLUGIN_REFRESH\ failed\ (preflight|discovery|identity|inventory|source-check|update-check|update|verification)\ ([a-z-]+)$ ]]; then
                    print_error 'BB plugin refresh failed: helper-result / unverified-result.'
                    return 1
                fi
                _bb_refresh_operation=${BASH_REMATCH[1]}
                _bb_refresh_reason=${BASH_REMATCH[2]}
                case "${_bb_refresh_reason}" in
                    activation-failed|activation-unverified|ambiguous-endpoint|ambiguous-main-server|ambiguous-process|changed-local-state|changed-plugin-intent|changed-plugin-inventory|changed-preserved-plugin|changed-process|changed-source-resolution|foreign-local-state|foreign-process|incomplete-results|malformed-result|native-request-failed|operation-timeout|process-proof-unavailable|rolled-back|server-move-in-progress|source-unavailable|unexpected-update-selection|unsupported-account|unsupported-native-contract|unsupported-platform|unverified-compatibility|unverified-home|unverified-local-state|unverified-main-server|unverified-peer|unverified-policy|unverified-result|unverified-source-intent|update-unverified|writable-local-state|unknown-failure) ;;
                    *) print_error 'BB plugin refresh failed: helper-result / unverified-result.'; return 1 ;;
                esac
                print_error "BB plugin refresh failed: ${_bb_refresh_operation} / ${_bb_refresh_reason}."
                _bb_refresh_status=1
                _bb_refresh_diagnostic=1
                ;;
            *) print_error 'BB plugin refresh failed: helper-result / unverified-result.'; return 1 ;;
        esac
    done <<< "${_bb_refresh_output}"
    if [[ "${_bb_refresh_status}" -ne 0 ]]; then
        if [[ "${_bb_refresh_diagnostic}" -eq 0 ]]; then
            print_error 'BB plugin refresh failed: helper-result / unverified-result.'
        fi
        print_error 'BB plugin refresh incomplete; unrelated setup and log finalization will continue.'
        return 1
    fi
    return 0
}

bb_plugin_refresh_payload() {
    /usr/bin/python3 -I -S - "${HOME}" "${1:-ready}" <<'BB_PLUGIN_REFRESH_PY'
"""BB native plugin refresh. Never import BB code, start a server, or select a CLI.

The HTTP peer is proved against an account-owned main-server process before each
request. Native API responses are data, not diagnostics. See the source contract
in docs/research/2026-10-01-bb-plugin-refresh-api.md.
"""
import ctypes
import http.client
import json
import os
from pathlib import Path
import re
import signal
import socket
import stat
import subprocess
import sys
import time

MAX_BYTES = 8388608
MAX_PROCESSES = 32768
MAX_PLUGINS = 1024


class Refusal(Exception):
    pass


class Diagnostics:
    """Keep the first failure, not exception text or native response contents."""
    def __init__(self):
        self.operation = 'preflight'
        self.first = None

    def record(self, error):
        if self.first is not None:
            return
        operations = ('preflight', 'discovery', 'identity', 'inventory', 'source-check',
                      'update-check', 'update', 'verification')
        reasons = ('activation-failed', 'activation-unverified', 'ambiguous-endpoint',
                   'ambiguous-main-server', 'ambiguous-process', 'changed-local-state',
                   'changed-plugin-intent', 'changed-plugin-inventory', 'changed-preserved-plugin',
                   'changed-process', 'changed-source-resolution', 'foreign-local-state',
                   'foreign-process', 'incomplete-results', 'malformed-result',
                   'native-request-failed', 'operation-timeout', 'process-proof-unavailable', 'rolled-back',
                   'server-move-in-progress', 'source-unavailable', 'unexpected-update-selection', 'unsupported-account',
                   'unsupported-native-contract', 'unsupported-platform', 'unverified-compatibility',
                   'unverified-home', 'unverified-local-state', 'unverified-main-server',
                   'unverified-peer', 'unverified-policy', 'unverified-result',
                   'unverified-source-intent', 'update-unverified', 'writable-local-state')
        reason = error.args[0] if type(error) is Refusal and len(error.args) == 1 else None
        if isinstance(error, (TimeoutError, subprocess.TimeoutExpired)):
            reason = 'operation-timeout'
        elif isinstance(error, (ConnectionError, http.client.HTTPException)):
            reason = 'native-request-failed'
        if type(reason) is not str or reason not in reasons:
            reason = 'unknown-failure'
        operation = self.operation if self.operation in operations else 'preflight'
        self.first = (operation, reason)

    def report(self):
        if self.first is not None:
            print('BB_PLUGIN_REFRESH failed ' + ' '.join(self.first))


def need(value, reason):
    if not value:
        raise Refusal(reason)


def object_json(raw):
    def pairs(items):
        result = {}
        for key, value in items:
            need(key not in result, 'malformed-result')
            result[key] = value
        return result
    try:
        return json.loads(raw, object_pairs_hook=pairs,
                          parse_constant=lambda _: (_ for _ in ()).throw(Refusal('malformed-result')))
    except (ValueError, UnicodeError):
        raise Refusal('malformed-result') from None


def bounded_read(path, limit=MAX_BYTES):
    with open(path, 'rb') as stream:
        raw = stream.read(limit + 1)
    need(len(raw) <= limit, 'unverified-local-state')
    return raw


def fingerprint(info):
    return (info.st_dev, info.st_ino, info.st_uid, info.st_gid, info.st_mode,
            info.st_size, info.st_mtime_ns, info.st_ctime_ns, info.st_nlink)


class LocalFiles:
    """Read-only, parent-first checks. Only the account HOME alias is resolved."""
    def __init__(self, home, uid):
        self.original_home = Path(home)
        self.home = self.original_home.resolve(strict=True)
        self.uid = uid
        self.seen = {}
        need(self.home.is_absolute() and self.home != Path('/'), 'unverified-home')
        need(self.home.stat().st_uid == uid, 'unverified-home')

    def normalize(self, path):
        path = Path(path)
        try:
            return self.home / path.relative_to(self.original_home)
        except ValueError:
            return path

    def inspect(self, path, directory=False, optional=False, volatile=False):
        path = self.normalize(path)
        need(path.is_absolute() and '..' not in path.parts, 'unverified-local-state')
        chain = list(reversed(path.parents)) + [path]
        for current in chain:
            try:
                info = current.lstat()
            except FileNotFoundError:
                if optional:
                    return None
                raise Refusal('unverified-local-state') from None
            need(not stat.S_ISLNK(info.st_mode), 'unverified-local-state')
            is_dir = current != path or directory
            need(stat.S_ISDIR(info.st_mode) if is_dir else stat.S_ISREG(info.st_mode),
                 'unverified-local-state')
            need(info.st_uid in (0, self.uid), 'foreign-local-state')
            # Native AppImage extraction can sit below the system sticky /tmp.
            # No other writable ancestor is accepted; descendants remain checked.
            sticky_tmp = current == Path('/tmp') and info.st_uid == 0 and bool(info.st_mode & stat.S_ISVTX)
            need(not info.st_mode & 0o022 or sticky_tmp, 'writable-local-state')
            if not is_dir:
                need(info.st_nlink == 1, 'unverified-local-state')
            previous = self.seen.get(str(current))
            # Directory mtime changes with unrelated work; pin its identity/mode.
            mark = fingerprint(info)[:5] if is_dir or volatile else fingerprint(info)
            need(previous is None or previous == mark, 'changed-local-state')
            self.seen[str(current)] = mark
        return info

    def read(self, path, optional=False, header=False):
        path = self.normalize(path)
        info = self.inspect(path, optional=optional, volatile=header)
        if info is None:
            return None
        def stable(observed):
            if header:
                return fingerprint(observed)[:5] == fingerprint(info)[:5] and observed.st_nlink == 1
            return fingerprint(observed) == fingerprint(info)
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        completed = False
        try:
            need(stable(os.fstat(fd)), 'changed-local-state')
            with os.fdopen(fd, 'rb', closefd=False) as stream:
                raw = stream.read(16 if header else MAX_BYTES + 1)
            need(len(raw) <= MAX_BYTES, 'unverified-local-state')
            need(stable(os.fstat(fd)), 'changed-local-state')
            need(stable(os.lstat(path)), 'changed-local-state')
            completed = True
            return raw
        finally:
            if completed:
                os.close(fd)
            else:
                try:
                    os.close(fd)
                except Exception:
                    pass  # Preserve the original failed observation.

    def json(self, path, optional=False):
        raw = self.read(path, optional)
        return None if raw is None else object_json(raw)


def command(args, allow_missing=False):
    """Only native inspection tools, never a caller-selected executable."""
    result = subprocess.run(args, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, timeout=10, close_fds=True,
                            env={'PATH': '/usr/bin:/bin:/usr/sbin:/sbin', 'LC_ALL': 'C'})
    if allow_missing and result.returncode == 1 and not result.stdout and not result.stderr:
        return b''
    need(result.returncode == 0 and not result.stderr and len(result.stdout) <= MAX_BYTES, 'process-proof-unavailable')
    return result.stdout


def parse_environment(raw):
    result = {}
    for item in raw.split(b'\0'):
        key, separator, value = item.partition(b'=')
        if separator and key in (b'HOME', b'BB_DATA_DIR', b'BB_SERVER_PORT', b'BB_SERVER_LAUNCH_ID'):
            name = key.decode('ascii')
            need(name not in result, 'ambiguous-process')
            result[name] = value.decode('utf-8', 'strict')
    return result


class Processes:
    def __init__(self, uid):
        self.uid = uid
        self.system = sys.platform
        need(self.system in ('linux', 'darwin'), 'unsupported-platform')

    def table(self):
        rows = command(['/bin/ps', '-axo', 'uid=,pid=']).decode('ascii').splitlines()
        need(len(rows) <= MAX_PROCESSES, 'process-proof-unavailable')
        result = []
        for row in rows:
            parts = row.split()
            need(len(parts) == 2 and all(p.isdecimal() for p in parts), 'process-proof-unavailable')
            if int(parts[0]) == self.uid:
                result.append(int(parts[1]))
        return result

    def read(self, pid):
        if self.system == 'linux':
            root = Path('/proc') / str(pid)
            try:
                need(root.stat().st_uid == self.uid, 'foreign-process')
                stamp = bounded_read(root / 'stat', 65536).rsplit(b')', 1)[1].split()[19]
                argv = [x.decode('utf-8', 'strict') for x in bounded_read(root / 'cmdline', 2097152).split(b'\0') if x]
                # Do not inventory credentials of unrelated account processes.
                env = bounded_read(root / 'environ', 2097152) if main_entry(argv) is not None else b''
                again = bounded_read(root / 'stat', 65536).rsplit(b')', 1)[1].split()[19]
            except (FileNotFoundError, ProcessLookupError):
                return None
            need(stamp == again, 'changed-process')
            return (argv, parse_environment(env), stamp)
        # KERN_PROCARGS2 preserves argv boundaries (ps eww does not). Values are
        # kept in memory, never printed or put in command arguments.
        raw_rows = command(['/bin/ps', '-p', str(pid), '-o', 'uid=,lstart='], allow_missing=True)
        if not raw_rows:
            return None
        rows = raw_rows.decode('ascii').strip().split(None, 1)
        need(len(rows) == 2 and rows[0] == str(self.uid), 'foreign-process')
        libc = ctypes.CDLL('/usr/lib/libSystem.B.dylib', use_errno=True)
        mib = (ctypes.c_int * 3)(1, 49, pid)
        size = ctypes.c_size_t(2097152)
        buffer = ctypes.create_string_buffer(size.value)
        need(libc.sysctl(mib, 3, buffer, ctypes.byref(size), None, 0) == 0, 'process-proof-unavailable')
        raw = buffer.raw[:size.value]
        argc = int.from_bytes(raw[:4], sys.byteorder, signed=True)
        need(0 < argc <= 4096, 'ambiguous-process')
        rest = raw[4:].split(b'\0', 1)
        need(len(rest) == 2, 'ambiguous-process')
        values = rest[1].lstrip(b'\0').split(b'\0')
        need(len(values) >= argc, 'ambiguous-process')
        argv = [value.decode('utf-8', 'strict') for value in values[:argc]]
        return argv, parse_environment(b'\0'.join(values[argc:])), rows[1]

    def database_open(self, path):
        # A native main server holds its bb.db connection. A stopped-data
        # deferral requires kernel evidence, not just absence of a known argv.
        if self.system == 'darwin':
            return bool(command(['/usr/sbin/lsof', '-nP', '-Fpu', '--', str(path)], allow_missing=True))
        expected = path.stat()
        for pid in self.table():
            try:
                entries = list((Path('/proc') / str(pid) / 'fd').iterdir())
            except FileNotFoundError:
                continue
            need(len(entries) <= 65536, 'process-proof-unavailable')
            for entry in entries:
                try:
                    observed = entry.stat()
                except FileNotFoundError:
                    continue
                if (observed.st_dev, observed.st_ino) == (expected.st_dev, expected.st_ino):
                    return True
        return False

    def peer_owned(self, pid, port, client_port):
        if self.system == 'darwin':
            raw = command(['/usr/sbin/lsof', '-nP', '-a', '-p', str(pid), '-iTCP', '-FpnT']).decode('utf-8')
            expected = f'n127.0.0.1:{port}->127.0.0.1:{client_port}'
            return f'p{pid}' in raw.splitlines() and expected + '\nTST=ESTABLISHED' in raw
        # Match the accepted server-side socket, not merely a listening port.
        # A same-account ssh tunnel cannot satisfy this proof for a BB process.
        expected_local = f'0100007F:{port:04X}'
        expected_peer = f'0100007F:{client_port:04X}'
        matches = set()
        for name, local, peer in (('tcp', expected_local, expected_peer),
                                 ('tcp6', '0000000000000000FFFF0000' + expected_local,
                                  '0000000000000000FFFF0000' + expected_peer)):
            for line in bounded_read(Path('/proc/net') / name).decode('ascii').splitlines()[1:]:
                values = line.split()
                need(len(values) >= 10, 'process-proof-unavailable')
                if values[1:4] == [local, peer, '01'] and values[7] == str(self.uid):
                    matches.add(values[9])
        descriptors = list((Path('/proc') / str(pid) / 'fd').iterdir())
        need(len(descriptors) <= 65536, 'process-proof-unavailable')
        for descriptor in descriptors:
            try:
                target = os.readlink(descriptor)
            except FileNotFoundError:
                continue
            if target.startswith('socket:[') and target[8:-1] in matches:
                return True
        return False


def main_entry(argv):
    entries = [arg for arg in argv[1:] if arg.endswith('/server/dist/index.js')]
    if not entries:
        return None
    if len(entries) != 1 or not Path(entries[0]).is_absolute():
        return None
    return Path(entries[0])


def verify_package(files, entry):
    root = entry.parents[2]
    try:
        metadata = files.json(root / 'package.json', optional=True)
    except (Refusal, OSError):
        if root.name != 'bb-app':
            return False  # no positive BB evidence in an unrelated application
        raise
    if not isinstance(metadata, dict) or metadata.get('name') != 'bb-app':
        need(root.name != 'bb-app', 'unverified-main-server')
        # Recognize BB's source-workspace server without treating every unrelated
        # project named server/dist/index.js as a BB installation.
        workspace = files.json(entry.parents[1] / 'package.json', optional=True)
        need(not isinstance(workspace, dict) or workspace.get('name') != '@bb/server', 'unsupported-native-contract')
        return False
    version = metadata.get('version')
    # Native contract inspected at 0.44.0. Unknown versions must be reviewed,
    # rather than silently assuming source/disabled-state semantics are stable.
    need(version == '0.44.0', 'unsupported-native-contract')
    need(metadata.get('bin', {}).get('bb-server') == 'dist/bb-server.js', 'unverified-main-server')
    files.inspect(entry)
    files.inspect(root / 'server/dist/start-server.js')
    return True


def discover(files, processes, configured_data=None, block_default=False):
    servers = []
    data_dirs = {files.home / '.bb'}
    if configured_data:
        need(Path(configured_data).is_absolute(), 'unverified-local-state')
        data_dirs.add(files.normalize(configured_data))
    for pid in processes.table():
        record = processes.read(pid)
        if record is None:
            continue
        argv, env, stamp = record
        entry = main_entry(argv)
        if entry is None:
            continue
        if not verify_package(files, entry):
            continue
        need(len(argv) == 2, 'ambiguous-process')
        # UID is the account identity; a manual server can use a custom HOME.
        home = env.get('HOME') or str(files.home)
        need(Path(home).is_absolute(), 'unverified-home')
        data = files.normalize(env.get('BB_DATA_DIR') or str(Path(home) / '.bb'))
        if block_default and data == files.home / '.bb':
            continue  # opted-in Ubuntu readiness failed; caller retains failure
        files.inspect(data, directory=True)
        need(data.stat().st_uid == files.uid, 'foreign-local-state')
        need(files.read(data / 'bb.db', header=True) == b'SQLite format 3\0'
             and (data / 'bb.db').stat().st_uid == files.uid, 'unverified-main-server')
        need(files.read(data / 'server-moved.json', optional=True) is None
             and files.read(data / 'server-import.json', optional=True) is None, 'server-move-in-progress')
        port_text = env.get('BB_SERVER_PORT', '38886')
        need(re.fullmatch(r'[0-9]{1,5}', port_text) is not None and 0 < int(port_text) < 65536,
             'ambiguous-endpoint')
        key = (data.stat().st_dev, data.stat().st_ino)
        need(not any(s['key'] == key or s['port'] == int(port_text) for s in servers), 'ambiguous-main-server')
        servers.append({'pid': pid, 'record': record, 'entry': entry, 'data': data,
                        'key': key, 'port': int(port_text), 'launch': env.get('BB_SERVER_LAUNCH_ID')})
        data_dirs.add(data)
    stopped = 0
    for data in data_dirs:
        if block_default and data == files.home / '.bb':
            continue
        info = files.inspect(data, directory=True, optional=True)
        if info is None or any(s['key'] == (info.st_dev, info.st_ino) for s in servers):
            continue
        db = files.read(data / 'bb.db', optional=True, header=True)
        if db is None:
            continue  # prepared CLI / machine daemon is not a main server
        need(info.st_uid == files.uid and (data / 'bb.db').stat().st_uid == files.uid
             and db[:16] == b'SQLite format 3\0', 'unverified-main-server')
        moved = files.json(data / 'server-moved.json', optional=True)
        if moved is not None:
            need(isinstance(moved, dict) and moved.get('version') == 1
                 and moved.get('mode') in ('connect', 'direct')
                 and all(isinstance(moved.get(k), str) and moved[k]
                         for k in ('moveId', 'fromHostId', 'toHostId', 'toHostName', 'serverUrl'))
                 and type(moved.get('movedAt')) is int and moved['movedAt'] >= 0
                 and isinstance(moved.get('oldCopyEntries'), list), 'unverified-local-state')
            continue  # historical main data now belongs to a remote server
        need(files.read(data / 'server-import.json', optional=True) is None, 'server-move-in-progress')
        runtime = files.json(data / 'bb-app-runtime.json', optional=True)
        if runtime is not None:
            need(isinstance(runtime, dict) and type(runtime.get('pid')) is int, 'unverified-local-state')
            need(processes.read(runtime['pid']) is None, 'unverified-main-server')
        need(not processes.database_open(data / 'bb.db'), 'unverified-main-server')
        stopped += 1
    return servers, stopped


class NativeApi:
    def __init__(self, files, processes, server, deadline):
        self.files, self.processes, self.server, self.deadline = files, processes, server, deadline

    def request(self, method, path, payload=None):
        need(time.monotonic() < self.deadline, 'operation-timeout')
        s = self.server
        need(self.processes.read(s['pid']) == s['record'], 'changed-process')
        need(verify_package(self.files, s['entry']), 'unverified-main-server')
        self.files.inspect(s['data'], directory=True)
        connection = http.client.HTTPConnection('127.0.0.1', s['port'],
                                               timeout=min(180, self.deadline - time.monotonic()))
        failed = True
        try:
            connection.connect()
            connection.auto_open = 0  # never reconnect after proving a socket
            client_port = connection.sock.getsockname()[1]
            until = min(self.deadline, time.monotonic() + 2)
            while not self.processes.peer_owned(s['pid'], s['port'], client_port):
                need(time.monotonic() < until, 'unverified-peer')
                time.sleep(0.025)
            need(self.processes.read(s['pid']) == s['record'], 'changed-process')
            body = None if payload is None else json.dumps(payload).encode('ascii')
            connection.request(method, path, body, {'Content-Type': 'application/json', 'Accept-Encoding': 'identity'})
            response = connection.getresponse()
            need(response.getheader('Content-Encoding') in (None, 'identity'), 'malformed-result')
            raw = response.read(MAX_BYTES + 1)
            need(len(raw) <= MAX_BYTES, 'malformed-result')
            need(self.processes.read(s['pid']) == s['record'], 'changed-process')
            result = object_json(raw)
            if response.status == 422 and method == 'POST' and path.endswith('/update'):
                identity = path.split('/')[-2]
                refusal = ('plugin safe mode is on; turn it off with `bb plugin safe-mode off` '
                           'before you update "' + identity + '"')
                if isinstance(result, dict) and result.get('error') == refusal:
                    failed = False  # A deferral cannot hide an independent close failure.
                    raise Refusal('safe-mode')
            need(response.status == 200, 'native-request-failed')  # no redirects or remote fallback
            failed = False
            return result
        except (TimeoutError, socket.timeout):
            raise Refusal('operation-timeout') from None
        finally:
            if not failed:
                connection.close()
            else:
                # Closing a failed request must not replace its causal refusal.
                try:
                    connection.close()
                except Exception:
                    pass

    def verify(self):
        health = self.request('GET', '/health')
        need(isinstance(health, dict) and health.get('ok') is True and not health.get('serverMove'),
             'unverified-main-server')
        if self.server['launch']:
            need(health.get('launchId') == self.server['launch'], 'unverified-main-server')
        config = self.request('GET', '/api/v1/system/config')
        need(isinstance(config, dict) and isinstance(config.get('dataDir'), str)
             and self.files.normalize(config['dataDir']) == self.server['data'], 'unverified-main-server')


def plugin_map(result):
    need(isinstance(result, dict) and isinstance(result.get('plugins'), list), 'malformed-result')
    need(len(result['plugins']) <= MAX_PLUGINS, 'malformed-result')
    plugins = {}
    for plugin in result['plugins']:
        need(isinstance(plugin, dict), 'malformed-result')
        identity = plugin.get('id')
        need(isinstance(identity, str) and re.fullmatch(r'[a-zA-Z0-9][a-zA-Z0-9._-]{0,199}', identity),
             'malformed-result')
        need(identity not in plugins and type(plugin.get('enabled')) is bool, 'malformed-result')
        need(plugin.get('provenance') in ('builtin', 'direct', 'catalog'), 'malformed-result')
        need(all(isinstance(plugin.get(key), str) and plugin[key] for key in ('source', 'version', 'status')),
             'malformed-result')
        need(isinstance(plugin.get('updateState'), dict), 'malformed-result')
        plugins[identity] = plugin
    return plugins


def safe_mode(api):
    state = api.request('GET', '/api/v1/plugins/safe-mode')
    need(isinstance(state, dict) and type(state.get('enabled')) is bool, 'malformed-result')
    return state['enabled']


def resolution(value):
    return (isinstance(value, dict) and isinstance(value.get('version'), str)
            and bool(value['version']) and isinstance(value.get('display'), str))


def refresh(api, diagnostics=None):
    diagnostics = diagnostics if diagnostics is not None else Diagnostics()
    diagnostics.operation = 'identity'
    api.verify()
    diagnostics.operation = 'inventory'
    if safe_mode(api):
        return 'safe-mode', False
    before = plugin_map(api.request('GET', '/api/v1/plugins'))
    sources = {}
    diagnostics.operation = 'source-check'
    for identity, plugin in before.items():
        source = api.request('GET', '/api/v1/plugins/' + identity + '/source')
        need(isinstance(source, dict) and source.get('requested') == plugin['source']
             and isinstance(source.get('resolved'), str), 'unverified-source-intent')
        sources[identity] = source
    targets = {}
    diagnostics.operation = 'update-check'
    checks = api.request('POST', '/api/v1/plugins/updates/check', {})
    need(isinstance(checks, dict) and isinstance(checks.get('results'), list), 'malformed-result')
    need(len(checks['results']) == len(before), 'incomplete-results')
    checked = {}
    failed = False
    updated = False
    for entry in checks['results']:
        need(isinstance(entry, dict) and entry.get('id') in before and entry['id'] not in checked,
             'malformed-result')
        need(resolution(entry.get('installed')), 'malformed-result')
        need(entry.get('outcome') in ('current', 'update-available', 'pinned', 'incompatible', 'unavailable'),
             'malformed-result')
        need(not entry.get('devMode'), 'unverified-compatibility')
        if entry['outcome'] == 'incompatible':
            blocked = entry.get('blocked')
            need(isinstance(blocked, dict) and isinstance(blocked.get('version'), str)
                 and isinstance(blocked.get('reasons'), list) and bool(blocked['reasons'])
                 and all(isinstance(r, str) and r for r in blocked['reasons']), 'malformed-result')
        need(sources[entry['id']]['resolved'] == entry['installed']['display'], 'changed-source-resolution')
        checked[entry['id']] = entry
    for identity, entry in checked.items():
        diagnostics.operation = 'update-check'
        plugin = before[identity]
        outcome = entry['outcome']
        if outcome == 'unavailable':
            diagnostics.record(Refusal('source-unavailable'))
            failed = True
            continue
        if outcome != 'update-available':
            continue
        need(plugin['provenance'] != 'builtin' and not plugin['source'].startswith(('path:', 'builtin:')),
             'unexpected-update-selection')
        need(resolution(entry.get('candidate')), 'malformed-result')
        diagnostics.operation = 'update'
        if safe_mode(api):
            return 'safe-mode', failed
        try:
            result = api.request('POST', '/api/v1/plugins/' + identity + '/update', {})
            need(isinstance(result, dict) and type(result.get('applied')) is bool
                 and resolution(result.get('from')), 'malformed-result')
            need(result.get('outcome') in ('current', 'updated', 'rolled-back'), 'malformed-result')
            if result['outcome'] == 'rolled-back':
                diagnostics.record(Refusal('rolled-back'))
                failed = True
            elif result['outcome'] == 'updated':
                need(result['applied'] is True and resolution(result.get('to')), 'malformed-result')
                updated = True
                targets[identity] = result['to']
            else:
                need(result['applied'] is False, 'malformed-result')
                targets[identity] = result['from']
        except Refusal as error:
            if type(error) is Refusal and error.args == ('safe-mode',):
                return 'safe-mode', failed
            # Unknown completion (including timeout) must not be retried or
            # converted to success by a later current result.
            diagnostics.record(error)
            failed = True
    diagnostics.operation = 'verification'
    after = plugin_map(api.request('GET', '/api/v1/plugins'))
    need(before.keys() == after.keys(), 'changed-plugin-inventory')
    for identity, old in before.items():
        new = after[identity]
        source = api.request('GET', '/api/v1/plugins/' + identity + '/source')
        need(isinstance(source, dict) and all(source.get(key) == sources[identity].get(key)
             for key in ('requested', 'subdirectory', 'range', 'tagPrefix', 'registry')), 'changed-plugin-intent')
        if identity in targets:
            need(source.get('resolved') == targets[identity]['display'], 'update-unverified')
        need(all(new[key] == old[key] for key in ('source', 'provenance', 'enabled')), 'changed-plugin-intent')
        if checked[identity]['outcome'] in ('pinned', 'incompatible'):
            need(new['version'] == old['version'], 'changed-preserved-plugin')
        if checked[identity]['outcome'] == 'update-available':
            need(new['status'] in (('running',) if new['enabled'] else ('disabled',)), 'activation-unverified')
        failure = new['updateState'].get('lastFailure')
        need(failure is None or failure == old['updateState'].get('lastFailure'), 'activation-failed')
    # A fresh native check catches incomplete/rolled-back results and concurrent
    # new candidates. Never treat unavailable/unknown as deliberate exclusion.
    final = api.request('POST', '/api/v1/plugins/updates/check', {})
    need(isinstance(final, dict) and isinstance(final.get('results'), list), 'malformed-result')
    remaining = final['results']
    need(len(remaining) == len(before) and {e.get('id') for e in remaining if isinstance(e, dict)} == set(before),
         'incomplete-results')
    for entry in remaining:
        need(resolution(entry.get('installed')) and not entry.get('devMode'), 'malformed-result')
        if entry['id'] in targets:
            need(entry['installed'] == targets[entry['id']], 'update-unverified')
        if entry.get('outcome') not in ('current', 'pinned', 'incompatible'):
            diagnostics.record(Refusal('source-unavailable' if entry.get('outcome') == 'unavailable'
                                      else 'update-unverified'))
            failed = True
    return ('updated' if updated else 'checked'), failed


def run():
    # Diagnostics are finite, controlled labels only. No paths, URLs, process
    # arguments, native errors, plugin output, settings or credentials escape.
    labels = {'safe-mode', 'checked', 'updated', 'stopped', 'absent', 'failed'}
    diagnostics = Diagnostics()
    try:
        need(os.getuid() != 0, 'unsupported-account')
        deadline = time.monotonic() + 1800
        signal.signal(signal.SIGALRM, lambda *_: (_ for _ in ()).throw(Refusal('operation-timeout')))
        signal.alarm(1800)  # include discovery and local filesystem inspection
        files = LocalFiles(sys.argv[1], os.getuid())
        processes = Processes(os.getuid())
        policy = sys.argv[2] if len(sys.argv) > 2 else 'ready'
        need(policy in ('ready', 'block-default'), 'unverified-policy')
        diagnostics.operation = 'discovery'
        servers, stopped = discover(files, processes, os.environ.get('BB_DATA_DIR'), policy == 'block-default')
        failed = False
        if policy == 'block-default':
            print('BB_PLUGIN_REFRESH readiness-deferred')
        if stopped:
            print('BB_PLUGIN_REFRESH stopped')
        if not stopped and not servers:
            print('BB_PLUGIN_REFRESH absent')
        for server in servers:
            try:
                diagnostics.operation = 'verification'
                state, error = refresh(NativeApi(files, processes, server, deadline), diagnostics)
                need(state in labels, 'unverified-result')
                print('BB_PLUGIN_REFRESH ' + state)
                failed = failed or error
                if error:
                    diagnostics.record(Refusal('unverified-result'))
            except Exception as error:
                failed = True
                diagnostics.record(error)
        diagnostics.report()
        return int(failed)
    except Exception as error:
        diagnostics.record(error)
        diagnostics.report()
        return 1


if __name__ == '__main__':
    raise SystemExit(run())
BB_PLUGIN_REFRESH_PY
}
# END BB PLUGIN REFRESH

# Installation only: keep this block identical in the five Bash scripts.
# A private npm prefix avoids global BB bins and the enrollment installer's fallback.
bb_machine_existing_role() {
    local _file
    [[ -z "${BB_DATA_DIR:-}" && -z "${BB_APP_NPM_PREFIX:-}" ]] || return 0
    for _file in "${HOME}/.bb" "${HOME}/.bb-machines" "${HOME}/.config/setup-bb-server" \
        "${XDG_CONFIG_HOME:-${HOME}/.config}/setup-bb-server" \
        "${HOME}"/.config/systemd/user/*bb*.service "${HOME}"/Library/LaunchAgents/*bb*.plist; do
        [[ ! -e "${_file}" && ! -L "${_file}" ]] || return 0
    done
    return 1
}

bb_machine_package_state_payload() {
    node - "$1" "${HOME}" 2>/dev/null <<'BB_MACHINE_STATE'
const fs = require('node:fs'), path = require('node:path'), {createRequire} = require('node:module');
const [mode, home] = process.argv.slice(2), uid = process.getuid();
const root = path.join(home, '.local/share/setup-bb-machine'), prefix = path.join(root, 'npm');
const pkg = path.join(prefix, 'lib/node_modules/bb-app'), marker = path.join(root, 'owner.json');
const owner = {kind: 'setup-bb-machine', schema: 1};
const bins = {bb: 'dist/bb.js', 'bb-app': 'dist/bb-app.js', 'bb-server': 'dist/bb-server.js', 'bb-host-daemon': 'dist/bb-host-daemon.js'};
let operation = 'home', location = 'home-boundary', observed = null;
const failures = [], reported = new Set();
function context(op, file, s = null) { operation = op; location = file; observed = s; }
function safeLocation(f) {
  if (f === home || f === 'home-boundary') return 'home-boundary';
  if (!inside(f, home)) return 'external-boundary';
  const rel = path.relative(home, f);
  // Suppress control characters, long/custom names and ambiguous components.
  return rel.length <= 120 && rel.split('/').every(n => /^[A-Za-z0-9_.@-]+$/.test(n) && !['.', '..'].includes(n)) ? '~/' + rel : 'path-suppressed';
}
function record(reason = 'unverified') {
  const line = ['blocked', operation, safeLocation(location), observed ? (observed.mode & 0o7777).toString(8).padStart(4, '0') : 'unknown', reason].join(':');
  if (failures.length < 8 && !reported.has(line)) { failures.push(line); reported.add(line); }
}
function inspect(fn) {
  try { fn(); } catch (e) { record(e.reason || 'unverified'); }
}
function stat(f) { try { return fs.lstatSync(f); } catch (e) { if (e.code === 'ENOENT') return null; throw e; } }
function check(ok, reason = 'unverified') { if (!ok) throw Object.assign(new Error(), {reason}); }
function inside(f, dir) { return f === dir || f.startsWith(dir + path.sep); }
const serviceSnapshots = new Map(), serviceLinks = new Map(), serviceListings = new Map(), serviceGroupCandidates = new Map();
const sameService = (a, b) => !!a && !!b && (a.isDirectory() ? ['dev', 'ino', 'uid', 'gid', 'mode'] :
  ['dev', 'ino', 'uid', 'gid', 'mode', 'nlink', 'size', 'mtimeMs', 'ctimeMs']).every(k => a[k] === b[k]);
function rememberService(file, s) {
  const previous = serviceSnapshots.get(file);
  check(!previous || sameService(previous, s));
  serviceSnapshots.set(file, s);
}
function servicePermissions(file, s, privateParent) {
  check(!(s.mode & 0o002), 'writable-boundary');
  if (!(s.mode & 0o020)) return;
  // Read-only references are not owned artifacts. On Linux a private ancestor
  // excludes other accounts even when a descendant retains group write bits.
  check(process.platform === 'linux', 'writable-boundary');
  check(!s.isFile() || s.nlink === 1, 'unsafe-file');
  if (!privateParent && !serviceGroupCandidates.has(file)) {
    // Preserve parent-before-descendant inspection even for group-write paths.
    // Cache only successful proofs; recheck the full set before package work.
    verifyServiceGroups([[file, s]]);
    serviceGroupCandidates.set(file, s);
  }
}
function chain(dir, serviceInspection = false) {
  const privateParent = dir !== path.dirname(dir) ? chain(path.dirname(dir), serviceInspection) : false;
  context('directory', dir);
  const s = stat(dir); if (!s) return privateParent;
  observed = s;
  if (serviceInspection) rememberService(dir, s);
  if (process.platform === 'linux' && dir === '/home' && s.isSymbolicLink() && s.uid === 0 && ['var/home', '/var/home'].includes(fs.readlinkSync(dir))) {
    for (const p of ['/', '/var', '/var/home']) { const t = fs.lstatSync(p); check(t.isDirectory() && t.uid === 0 && !(t.mode & 0o022)); }
    return privateParent;
  }
  check(!s.isSymbolicLink(), 'linked-path');
  check(s.isDirectory(), 'non-directory');
  check(s.uid === (inside(dir, home) ? uid : 0) || (!inside(dir, home) && s.uid === uid), 'unsafe-ownership');
  const stickyRoot = !inside(dir, home) && s.uid === 0 && (s.mode & 0o1000);
  if (!stickyRoot) {
    if (serviceInspection) servicePermissions(dir, s, privateParent);
    else check(!(s.mode & 0o022), 'writable-boundary');
  }
  return privateParent || ((s.uid === uid || s.uid === 0) && !(s.mode & 0o077));
}
function regular(f) {
  context('artifact', f);
  const s = fs.lstatSync(f); observed = s;
  check(!s.isSymbolicLink(), 'linked-path');
  check(s.uid === uid, 'unsafe-ownership');
  check(!(s.mode & 0o022), 'writable-boundary');
  check(s.isFile() && s.nlink === 1 && s.size > 0, 'unsafe-file');
  return s;
}
function json(f) {
  check(regular(f).size < 1048576, 'unsafe-file');
  try { return JSON.parse(fs.readFileSync(f, 'utf8')); } catch { check(false, 'malformed-metadata'); }
}
const serviceGroupProgram = String.raw`
import errno, json, os, stat, sys
class Untrusted(Exception): pass
def need(ok):
    if not ok: raise ValueError()
def fingerprint(s):
    return (s.st_dev, s.st_ino, s.st_uid, s.st_gid, s.st_mode, s.st_nlink, s.st_size, s.st_mtime_ns, s.st_ctime_ns)
flags = os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC
configs = {}
def read_file(file, limit, root=False):
    fd = os.open(file, flags)
    try:
        before = os.fstat(fd)
        need(stat.S_ISREG(before.st_mode))
        if root: need(before.st_uid == 0 and not before.st_mode & 0o022 and before.st_nlink == 1)
        data = bytearray()
        while len(data) <= limit:
            part = os.read(fd, min(65536, limit + 1 - len(data)))
            if not part: break
            data.extend(part)
        need(len(data) <= limit)
        if root:
            need(fingerprint(before) == fingerprint(os.fstat(fd)) == fingerprint(os.lstat(file)))
            configs[file] = before
        return data.decode('utf-8')
    finally: os.close(fd)
def main():
    global index
    request = json.loads(sys.stdin.buffer.read(4194305))
    need(set(request) == {'uid', 'paths'} and type(request['uid']) is int and request['uid'] == os.getuid())
    uid, paths = request['uid'], request['paths']
    need(isinstance(paths, list) and 0 < len(paths) <= 16384)
    for directory in ['/', '/etc', '/proc']:
        s = os.lstat(directory)
        need(stat.S_ISDIR(s.st_mode) and s.st_uid == 0 and not s.st_mode & 0o022)
    # Only locally enumerable identity sources. Unknown/directory-backed NSS
    # cannot prove an exclusive group and remains an inspection failure.
    nss = read_file('/etc/nsswitch.conf', 65536, True)
    for key in ['passwd', 'group', 'initgroups']:
        rows = [raw.partition(':')[2].split() for line in nss.splitlines() for raw in [line.split('#', 1)[0]] if raw.partition(':')[0].strip() == key]
        if key == 'initgroups' and not rows: continue
        need(len(rows) == 1 and rows[0] in [['files'], ['files', 'systemd']])
    def database(file, count):
        rows = [line.split(':') for line in read_file(file, 1048576, True).splitlines() if line and not line.startswith('#')]
        need(all(len(row) == count for row in rows))
        return rows
    users, groups = database('/etc/passwd', 7), database('/etc/group', 4)
    need(all(row[2].isascii() and row[2].isdigit() and row[3].isascii() and row[3].isdigit() for row in users))
    need(all(row[2].isascii() and row[2].isdigit() for row in groups))
    need(len({row[0] for row in users}) == len(users))
    by_name = {row[0]: int(row[2]) for row in users}
    gids = {entry['gid'] for entry in paths}
    need(all(type(gid) is int and 0 <= gid < 0xffffffff for gid in gids))
    trusted = {}
    for gid in gids:
        entries = [row for row in groups if int(row[2]) == gid]
        account = [row for row in users if int(row[2]) == uid]
        trusted[gid] = (len(account) == 1 and len(entries) == 1 and int(account[0][3]) == gid and
                        entries[0][0] == account[0][0] and all(int(row[2]) in {0, uid} for row in users if int(row[3]) == gid))
        if len(entries) == 1:
            trusted[gid] = trusted[gid] and all(by_name.get(member) in {0, uid} for member in entries[0][3].split(',') if member)
    # Account databases alone miss stale supplementary groups of live sessions.
    mounts = read_file('/proc/self/mountinfo', 1048576)
    proc_mounts = [line for line in mounts.splitlines() if len(line.split()) > 5 and line.split()[4] == '/proc']
    need(len(proc_mounts) == 1 and ' - proc ' in proc_mounts[0] and 'hidepid=' not in proc_mounts[0])
    for pid in os.listdir('/proc'):
        if not pid.isascii() or not pid.isdigit(): continue
        try: text = read_file('/proc/' + pid + '/status', 131072)
        except OSError as error:
            if error.errno not in {errno.ENOENT, errno.ESRCH}: raise
            try: os.kill(int(pid), 0)
            except ProcessLookupError: continue
            raise ValueError()
        def values(key, count=None):
            rows = [line.split(':', 1)[1].split() for line in text.splitlines() if line.startswith(key + ':')]
            need(len(rows) == 1 and (count is None or len(rows[0]) == count) and all(v.isascii() and v.isdigit() for v in rows[0]))
            result = list(map(int, rows[0])); need(all(v < 0xffffffff for v in result)); return result
        ids = values('Uid', 4)
        memberships = set(values('Gid', 4) + values('Groups'))
        if any(value not in {0, uid} for value in ids):
            for gid in gids & memberships: trusted[gid] = False
    for index, entry in enumerate(paths):
        need(set(entry) == {'path', 'dev', 'ino', 'uid', 'gid', 'mode'})
        need(isinstance(entry['path'], str) and os.path.isabs(entry['path']) and entry['uid'] in {0, uid})
        fd = os.open(entry['path'], flags)
        try:
            s = os.fstat(fd)
            need(stat.S_ISDIR(s.st_mode) or stat.S_ISREG(s.st_mode) and s.st_nlink == 1)
            need(all(getattr(s, 'st_' + key) == entry[key] for key in ['dev', 'ino', 'uid', 'gid', 'mode']))
            if not trusted[entry['gid']]: raise Untrusted()
            try:
                os.getxattr(fd, 'system.posix_acl_access')
                raise Untrusted()  # Named ACL writers are not implied by the group bits.
            except OSError as error:
                if error.errno != errno.ENODATA: raise
            need(fingerprint(s) == fingerprint(os.fstat(fd)) == fingerprint(os.lstat(entry['path'])))
        finally: os.close(fd)
    for file, before in configs.items(): need(fingerprint(before) == fingerprint(os.lstat(file)))
    print('trusted')
index = -1
try: main()
except Untrusted:
    print('blocked:' + str(index)); sys.exit(1)
except Exception:
    print('unverified'); sys.exit(1)
`;
function verifyServiceGroups(candidates = [...serviceGroupCandidates]) {
  if (candidates.length) {
    const paths = candidates.map(([file, s]) => {
      context(s.isDirectory() ? 'directory' : 'service', file, s);
      check(['dev', 'ino', 'uid', 'gid', 'mode'].every(k => Number.isSafeInteger(s[k])));
      return {path: file, dev: s.dev, ino: s.ino, uid: s.uid, gid: s.gid, mode: s.mode};
    });
    const result = require('node:child_process').spawnSync('/usr/bin/python3', ['-I', '-S', '-c', serviceGroupProgram], {
      input: JSON.stringify({uid, paths}), env: {PATH: '/usr/bin:/bin', LANG: 'C.UTF-8'}, cwd: '/', encoding: 'utf8',
      timeout: 5000, maxBuffer: 1024, shell: false, stdio: ['pipe', 'pipe', 'pipe']});
    const blocked = /^blocked:(\d+)\n$/.exec(result.stdout || '');
    if (result.status !== 0 && blocked && candidates[Number(blocked[1])]) {
      const [file, s] = candidates[Number(blocked[1])];
      context(s.isDirectory() ? 'directory' : 'service', file, s);
      check(false, 'writable-boundary');
    }
    check(!result.error && result.status === 0 && result.stdout === 'trusted\n');
  }
}
function verifyServiceInspection() {
  verifyServiceGroups();
  for (const [file, before] of serviceSnapshots) {
    context(before.isDirectory() ? 'directory' : 'service', file, before);
    check(sameService(before, stat(file)));
  }
  for (const [file, target] of serviceLinks) {
    context('service', file, serviceSnapshots.get(file));
    check(fs.readlinkSync(file) === target);
  }
  for (const [dir, names] of serviceListings) {
    context('directory', dir, serviceSnapshots.get(dir));
    check(JSON.stringify(fs.readdirSync(dir).filter(n => /\.(service|plist)$/.test(n)).sort()) === JSON.stringify(names));
  }
}
// Resolve service links one boundary at a time rather than realpath probing
// descendants before their ancestors are checked. Trusted Homebrew opt links
// and systemd masks remain read-only; bound cycles and never read a FIFO.
function serviceTarget(file) {
  let pending = file.split(path.sep).filter(Boolean), dir = path.parse(file).root, links = 0;
  while (pending.length) {
    chain(dir, true);
    const name = pending.shift();
    if (!name || name === '.') continue;
    if (name === '..') { dir = path.dirname(dir); continue; }
    const next = path.join(dir, name);
    context('service', next);
    const s = fs.lstatSync(next); observed = s;
    rememberService(next, s);
    if (s.isSymbolicLink()) {
      check(++links <= 40, 'linked-path');
      check(s.uid === uid || s.uid === 0, 'unsafe-ownership');
      const target = fs.readlinkSync(next);
      check(!serviceLinks.has(next) || serviceLinks.get(next) === target);
      serviceLinks.set(next, target);
      // Preserve POSIX ordering: resolve links before processing subsequent '..'.
      pending = target.split(path.sep).concat(pending);
      if (path.isAbsolute(target)) dir = path.parse(target).root;
    } else dir = next;
  }
  return dir;
}
// Read-only service references are not preparation-owned artifacts. Resolve
// ordinary linked registrations to a trusted regular target; never modify them.
function serviceUnreferenced(file) {
  context('service', file);
  const link = fs.lstatSync(file); observed = link;
  check(link.uid === uid || link.uid === 0, 'unsafe-ownership');
  rememberService(file, link);
  const target = link.isSymbolicLink() ? serviceTarget(file) : file;
  check(!target.includes('setup-bb-machine'), 'referenced-copy');
  const privateParent = chain(path.dirname(target), true);
  context('service', target);
  const s = fs.lstatSync(target); observed = s;
  rememberService(target, s);
  if (link.isSymbolicLink() && target === '/dev/null') {
    check(s.isCharacterDevice() && s.uid === 0); return; // Native systemd mask; no read.
  }
  check(s.uid === uid || s.uid === 0, 'unsafe-ownership');
  check(s.isFile() && !s.isSymbolicLink() && s.size < 1048576, 'unsafe-file');
  servicePermissions(target, s, privateParent);
  // Bound non-followed reads and revalidate snapshots before package work.
  const fd = fs.openSync(target, fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW | fs.constants.O_NONBLOCK);
  try {
    check(sameService(s, fs.fstatSync(fd)));
    const bytes = Buffer.alloc(s.size + 1); let used = 0;
    while (used < bytes.length) {
      const count = fs.readSync(fd, bytes, used, bytes.length - used, null);
      if (!count) break;
      used += count;
    }
    check(used === s.size && sameService(s, fs.fstatSync(fd)) && sameService(s, stat(target)));
    check(!bytes.subarray(0, used).toString('utf8').includes('setup-bb-machine'), 'referenced-copy');
  } finally { fs.closeSync(fd); }
}
// Inspect only the dedicated preparation tree, never BB data or enrollment trees.
function tree(dir) {
  chain(dir);
  for (const name of fs.readdirSync(dir)) {
    const f = path.join(dir, name);
    context('artifact', f);
    const s = fs.lstatSync(f); observed = s;
    check(s.uid === uid, 'unsafe-ownership');
    if (s.isSymbolicLink()) {
      const target = path.resolve(dir, fs.readlinkSync(f));
      check(inside(target, prefix), 'linked-path');
      // npm bin links may be dangling after an interrupted install. Never follow them.
      chain(path.dirname(target));
      context('artifact', f, s);
      const t = stat(target); check(!t || (t.isFile() && !t.isSymbolicLink()), 'linked-path');
    } else if (s.isDirectory()) tree(f);
    else {
      check(!(s.mode & 0o022), 'writable-boundary');
      check(s.isFile() && s.nlink === 1, 'unsafe-file');
    }
  }
}
try {
  check(path.isAbsolute(home) && path.normalize(home) === home && home !== '/');
  context('runtime', 'runtime');
  check(['linux', 'darwin'].includes(process.platform), 'unsupported-platform');
  const [major, minor] = process.versions.node.split('.').map(Number);
  check((major === 22 && minor >= 19) || major === 24 || major === 26, 'unsupported-runtime');
  // A custom running BB may use a non-default data directory. Read-only process
  // evidence blocks preparation rather than updating a possibly in-use copy.
  inspect(() => {
    context('process', 'process-inventory');
    const processes = require('node:child_process').execFileSync('ps', ['-U', String(uid), '-o', 'command='], {encoding: 'utf8', maxBuffer: 8 * 1024 * 1024, stdio: ['ignore', 'pipe', 'pipe']});
    check(!/(?:^|[\s/])(?:bb-app|bb-server|bb-host-daemon)(?:$|[\s/.])/m.test(processes), 'process-conflict');
  });
  // Also preserve a stopped, manually named user service referencing this copy.
  for (const dir of [path.join(home, '.config/systemd/user'), path.join(home, 'Library/LaunchAgents')]) {
    if (failures.length >= 8) break;
    inspect(() => {
      // Validate parents BEFORE probing a descendant, even if it is absent.
      chain(dir, true);
      if (!stat(dir)) return;
      const names = fs.readdirSync(dir).filter(n => /\.(service|plist)$/.test(n)).sort();
      serviceListings.set(dir, names);
      for (const name of names) {
        if (failures.length >= 8) break;
        inspect(() => serviceUnreferenced(path.join(dir, name)));
      }
    });
  }
  if (failures.length < 8) inspect(verifyServiceInspection);
  if (failures.length < 8) inspect(() => {
    chain(root);
    if (!stat(root)) return;
    check(JSON.stringify(json(marker)) === JSON.stringify(owner));
    check(!(fs.lstatSync(marker).mode & 0o077));
    context('artifact', root); observed = fs.lstatSync(root);
    check(fs.readdirSync(root).every(n => ['owner.json', 'npm'].includes(n)));
    if (stat(prefix)) {
      tree(prefix);
      for (const f of [path.join(pkg, 'package.json'), path.join(prefix, 'lib/node_modules/.package-lock.json')]) {
        if (stat(f)) { const j = json(f); check(j && typeof j === 'object' && !Array.isArray(j)); if (f === path.join(pkg, 'package.json')) check(j.name === 'bb-app'); }
      }
      for (const [dir, allowed] of [[prefix, ['bin', 'lib']], [path.join(prefix, 'lib'), ['node_modules']]]) {
        context('directory', dir); observed = stat(dir);
        if (observed) check(fs.readdirSync(dir).every(n => allowed.includes(n)));
      }
      const modules = path.join(prefix, 'lib/node_modules');
      context('directory', modules); observed = stat(modules);
      if (observed) check(fs.readdirSync(modules).every(n => n === 'bb-app' || n === '.package-lock.json' || /^\.bb-app-[A-Za-z0-9]+$/.test(n)));
      if (stat(path.join(prefix, 'bin'))) {
        for (const bin of fs.readdirSync(path.join(prefix, 'bin'))) {
          const f = path.join(prefix, 'bin', bin);
          context('artifact', f); observed = fs.lstatSync(f);
          check(Object.hasOwn(bins, bin));
          check(fs.lstatSync(f).isSymbolicLink() && path.resolve(path.dirname(f), fs.readlinkSync(f)) === path.join(pkg, bins[bin]));
        }
      }
    }
  });
  // No reserve/install/validation can follow a failed independent branch.
  if (failures.length) throw new Error();
  context('artifact', root);
  if (mode === 'reserve') {
    if (!stat(root)) {
      fs.mkdirSync(root, {recursive: true, mode: 0o700});
      fs.writeFileSync(marker, JSON.stringify(owner) + '\n', {flag: 'wx', mode: 0o600});
    }
    for (const dir of [path.join(prefix, 'lib/node_modules'), path.join(prefix, 'bin')]) fs.mkdirSync(dir, {recursive: true, mode: 0o700});
  } else if (mode === 'verify') {
    const j = json(path.join(pkg, 'package.json'));
    check(j.name === 'bb-app' && /^\d+\.\d+\.\d+$/.test(j.version));
    check(Array.isArray(j.os) && j.os.includes(process.platform));
    for (const [bin, entry] of Object.entries(bins)) {
      check(j.bin?.[bin] === entry); regular(path.join(pkg, entry));
      const f = path.join(prefix, 'bin', bin);
      context('artifact', f); observed = fs.lstatSync(f);
      check(fs.lstatSync(f).isSymbolicLink() && fs.realpathSync(f) === fs.realpathSync(path.join(pkg, entry)));
      check(fs.statSync(f).mode & 0o111);
    }
    for (const entry of ['server/dist/index.js', 'app/dist/index.html', 'host-daemon/dist/bb', 'host-daemon/dist/daemon-bundle.mjs', 'host-daemon/dist/bb-provider-bridge-worker.mjs', 'host-daemon/dist/bb-parcel-watcher-child.mjs', 'host-daemon/dist/bb-plugin-host-worker.mjs']) regular(path.join(pkg, entry));
    const chunks = path.join(pkg, 'host-daemon/dist/bb-chunks'); chain(chunks);
    check(fs.readdirSync(chunks).some(n => n.endsWith('.js') && regular(path.join(chunks, n))));
    const require = createRequire(path.join(pkg, 'package.json'));
    for (const name of ['better-sqlite3', 'node-pty', '@parcel/watcher', 'fs-native-extensions']) {
      context('artifact', path.join(pkg, 'node_modules', name));
      const entry = require.resolve(name); check(inside(entry, pkg)); regular(entry);
      const loaded = require(name);
      if (name === 'better-sqlite3') { const db = new loaded(':memory:'); db.close(); }
      if (name === 'node-pty') check(typeof loaded.spawn === 'function');
      if (name === '@parcel/watcher') check(typeof loaded.subscribe === 'function');
      if (name === 'fs-native-extensions') check(typeof loaded.tryLock === 'function' && typeof loaded.unlock === 'function');
    }
  } else check(['preflight', 'reserve'].includes(mode));
  process.stdout.write('ok\n');
} catch (e) {
  if (!failures.length) record(e.reason || 'unverified');
  // Deliberately not an exhaustive inventory: unsafe descendants are never inspected.
  process.stdout.write(failures.join('\n') + '\nfailed:incomplete\n');
  process.exitCode = 1;
}
BB_MACHINE_STATE
}

bb_machine_package_state() {
    local _mode="$1" _result _status=0 _line _op _path _observed _reason _count=0 _terminal=0 _valid=1
    local _record='^blocked:(home|runtime|process|directory|service|artifact):([^:]+):(unknown|[0-7]{4}):(unverified|linked-path|non-directory|unsafe-ownership|writable-boundary|unsafe-file|malformed-metadata|referenced-copy|unsupported-platform|unsupported-runtime|process-conflict)$'
    local _relative='^~/[A-Za-z0-9_.@/-]+$'
    case "${_mode}" in preflight|reserve|verify) ;; *) return 1 ;; esac
    # Bound even malformed/addon output before storing it. Never forward stderr.
    _result=$(set -o pipefail; bb_machine_package_state_payload "${_mode}" 2>/dev/null | head -c 4097 |
        node -e 'let text=""; process.stdin.on("data", b => { text += b; if (text.length > 4096 || /[^\x20-\x7e\n]/.test(text)) process.exit(1); }); process.stdin.on("end", () => { if (!/^(?:[ -~]+\n)+$/.test(text)) process.exit(1); process.stdout.write(text); });' 2>/dev/null) || _status=$?
    if [[ "${_status}" -eq 0 && "${_result}" == ok ]]; then return 0; fi
    if [[ "${_status}" -ne 0 && ${#_result} -le 4096 ]]; then
        while IFS= read -r _line; do
            if [[ "${_line}" == failed:incomplete && "${_count}" -gt 0 && "${_terminal}" -eq 0 ]]; then
                _terminal=1
            elif [[ "${_terminal}" -eq 0 && "${_line}" =~ ${_record} ]]; then
                _path="${BASH_REMATCH[2]}"
                case "${_path}" in home-boundary|external-boundary|path-suppressed) ;;
                    *)
                        if [[ ! "${_path}" =~ ${_relative} || ${#_path} -gt 122 || "${_path}" == *'/../'* || "${_path}" == *'/./'* || "${_path}" == */.. || "${_path}" == */. || "${_path}" == *'//'* || "${_path}" == */ ]]; then _valid=0; break; fi ;;
                esac
                _count=$((_count + 1))
                if [[ "${_count}" -gt 8 ]]; then _valid=0; break; fi
            else
                _valid=0; break
            fi
        done <<< "${_result}"
        if [[ "${_valid}" -eq 1 && "${_terminal}" -eq 1 && "${_count}" -le 8 ]]; then
            # Validate the ENTIRE protocol before logging any record.
            while IFS=: read -r _line _op _path _observed _reason; do
                [[ "${_line}" == blocked ]] || continue
                print_error "BB preparation ${_mode}: operation=${_op} path=${_path} mode=${_observed} reason=${_reason}"
            done <<< "${_result}"
            print_error 'BB preparation blocker report incomplete: unsafe descendants and remaining checks were not inspected.'
            return 1
        fi
    fi
    print_error "BB preparation ${_mode}: unverified helper result; diagnostic output suppressed."
    return 1
}

# Reuse the preparation platform gate before dotfiles, without Node/npm or lifecycle work.
bb_machine_platform_ready() {
    local _platform="$1" _kernel _release
    _kernel=$(uname -s) || return 1
    case "${_kernel}" in Darwin|Linux) ;; *) print_error 'BB preparation supports macOS/Linux only; use WSL2 on Windows.'; return 1 ;; esac
    if [[ "${_platform}" == wsl ]]; then
        _release=$(uname -r) || return 1
        case "${_kernel}:${_release}" in Linux:*[Mm]icrosoft*WSL2*) ;; *) print_error 'BB preparation requires WSL2.'; return 1 ;; esac
        [[ "${HEADLESS:-}" != 1 ]] || { print_error 'WSL HEADLESS=1 remains unsupported for BB preparation.'; return 1; }
    fi
}

# Chezmoi alone owns target convergence. Keep native config precedence and the
# caller's stricter mask; known roles receive no preparation-driven restriction.
with_bb_dotfiles_umask() {
    (
        local _platform="$1" _selection=1 _protect=0
        shift
        if [[ "${_platform}" == ubuntu ]]; then
            bb_server_selection && _selection=0 || _selection=$?
            [[ "${_selection}" -ne 0 ]] || _protect=1
        fi
        if [[ "${_selection}" -eq 1 ]] && ! bb_machine_existing_role &&
            bb_machine_platform_ready "${_platform}" >/dev/null 2>&1; then
            _protect=1
        fi
        if [[ "${_protect}" -eq 1 ]]; then
            umask go-w || exit 1
        fi
        "$@"
    )
}

setup_bb_machine() {
    local _platform="$1" _prefix="${HOME}/.local/share/setup-bb-machine/npm" _bin _found _version _policy
    local _npm_userconfig _npm_globalconfig
    local -a _npm_context
    if bb_machine_existing_role; then
        print_message 'BB preparation deferred: existing BB state, service or data/prefix override preserved. Manage that installation manually; readiness was not checked.'
        return 0
    fi
    bb_machine_platform_ready "${_platform}" || return 1
    for _bin in bb bb-app bb-server bb-host-daemon; do
        _found=$(command -v "${_bin}" 2>/dev/null || true)
        if [[ -n "${_found}" && "${_found}" != "${_prefix}/bin/${_bin}" ]]; then
            print_error 'BB preparation found an unmanaged BB command; leaving it untouched. Review existing installation ownership manually.'
            return 1
        fi
    done
    ensure_shared_node_runtime || { print_error 'BB preparation requires the shared Node/npm runtime.'; return 1; }
    bb_machine_package_state preflight || { print_error 'BB preparation preflight failed; no package changes made. Reconcile explicit Chezmoi permission overrides or unmanaged blockers manually; see README recovery guidance.'; return 1; }
    _version=$(npm --version 2>/dev/null) || return 1
    [[ "${_version}" =~ ^([0-9]+)\.([0-9]+)\.[0-9]+$ ]] || return 1
    if (( BASH_REMATCH[1] < 11 || (BASH_REMATCH[1] == 11 && BASH_REMATCH[2] < 19) )); then
        print_error 'BB preparation requires npm >=11.19 with native-addon allowlisting.'; return 1
    fi
    # npm derives its default globalconfig from prefix. Capture the original
    # global-install context BEFORE selecting our destination; retain native
    # user/environment value precedence instead of copying or replacing policy.
    if ! _npm_userconfig=$(npm --global config get userconfig 2>/dev/null) ||
        ! _npm_globalconfig=$(npm --global config get globalconfig 2>/dev/null) ||
        [[ "${_npm_userconfig}" != /* || "${_npm_globalconfig}" != /* || "${_npm_userconfig}${_npm_globalconfig}" == *$'\n'* ]]; then
        print_error 'BB preparation could not preserve the original npm configuration paths.'; return 1
    fi
    _npm_context=("--userconfig=${_npm_userconfig}" "--globalconfig=${_npm_globalconfig}")
    for _policy in ignore-scripts dangerously-allow-all-scripts; do
        _found=$(npm --global --prefix "${_prefix}" "${_npm_context[@]}" config get "${_policy}" 2>/dev/null) || return 1
        [[ "${_found}" == false ]] || { print_error 'BB preparation cannot use the explicit npm script policy; policy was preserved.'; return 1; }
    done
    _found=$(npm --global --prefix "${_prefix}" "${_npm_context[@]}" config get allow-scripts 2>/dev/null) || return 1
    if [[ -n "${_found}" ]] && ! node -e 'const a=process.argv[1].split(",").map(s=>s.trim()).sort(); process.exit(JSON.stringify(a)===JSON.stringify(["@parcel/watcher","better-sqlite3","node-pty"])?0:1)' "${_found}" >/dev/null 2>&1; then
        print_error 'BB preparation refuses to replace an explicit npm addon policy.'; return 1
    fi
    _found=$(npm --global --prefix "${_prefix}" "${_npm_context[@]}" config get strict-allow-scripts --strict-allow-scripts 2>/dev/null) || return 1
    [[ "${_found}" == true ]] || return 1
    _found=$(npm --global --prefix "${_prefix}" "${_npm_context[@]}" config get allow-scripts --allow-scripts=better-sqlite3,node-pty,@parcel/watcher 2>/dev/null) || return 1
    [[ "${_found}" == better-sqlite3,node-pty,@parcel/watcher ]] || return 1
    bb_machine_package_state reserve || return 1
    print_message 'Installing stable BB preparation software (no enrollment or service startup)...'
    if ! ( umask 077; npm install --global --prefix "${_prefix}" "${_npm_context[@]}" --engine-strict --strict-allow-scripts --allow-scripts=better-sqlite3,node-pty,@parcel/watcher bb-app@latest < /dev/null >/dev/null 2>&1 ); then
        print_error 'BB preparation npm install failed; the owned partial copy can be retried.'; return 1
    fi
    # Rebuild only native addons, including when the shared Node ABI/prefix changed.
    if ! ( umask 077; npm rebuild --global --prefix "${_prefix}" "${_npm_context[@]}" --strict-allow-scripts --allow-scripts=better-sqlite3,node-pty,@parcel/watcher better-sqlite3 node-pty @parcel/watcher < /dev/null >/dev/null 2>&1 ); then
        print_error 'BB preparation native-addon rebuild failed; no BB lifecycle command was run.'; return 1
    fi
    bb_machine_package_state verify || { print_error 'BB preparation artifacts/native dependencies failed verification; no daemon was started.'; return 1; }
    print_success 'BB software prepared; not enrolled and no BB service created.'
    print_message "Preparation CLI: ${_prefix}/bin/bb (shared Node must be on PATH)."
    print_message 'Next: open your ONE chosen BB server over private Tailscale, use its Add machine instructions, and manually run its enrollment command in this machine. Do not run bb-app to pair.'
}
# End shared BB machine preparation.

# BEGIN BB DESKTOP WRAPPER -- keep identical in all Bash entry points.
install_bb_desktop() {
    local entry="$1" platform arch kernel result status=0
    if [[ "${HEADLESS:-}" == "1" ]]; then
        print_debug "Skipping bb desktop: HEADLESS=1; existing applications untouched."
        return 0
    fi
    case "${entry}" in
        wsl|pi)
            print_debug "Skipping bb desktop: ${entry} has no supported native desktop artifact."
            return 0 ;;
        macos|ubuntu|bazzite) ;;
        *) print_error "bb desktop: invalid setup platform."; return 1 ;;
    esac
    if ! platform=$(uname -s) || ! arch=$(uname -m) || ! kernel=$(uname -r); then
        print_error "bb desktop: platform inspection failed."
        return 1
    fi
    # Rosetta reports x86_64 even on an Apple Silicon host.
    if [[ "${entry}:${platform}:${arch}" == "macos:Darwin:x86_64" ]] &&
        [[ "$(sysctl -n hw.optional.arm64 2>/dev/null || true)" == "1" ]]; then
        arch=arm64
    fi
    case "${entry}:${platform}:${arch}" in
        macos:Darwin:arm64) platform=macos ;;
        ubuntu:Linux:x86_64|bazzite:Linux:x86_64)
            case "${kernel}" in
                *[Mm]icrosoft*|*WSL*) print_debug "Skipping bb desktop: WSL is unsupported."; return 0 ;;
                *) ;;
            esac
            platform=linux ;;
        *) print_debug "Skipping bb desktop: no native artifact for this platform/architecture."; return 0 ;;
    esac
    if [[ ! -x /usr/bin/python3 ]]; then
        print_error "bb desktop requires native Python 3 (macOS Command Line Tools or Linux python3)."
        return 1
    fi
    result=$(bb_desktop_payload "${platform}" 2>/dev/null) || status=$?
    if [[ "${status}" -eq 0 ]]; then
        case "${result}" in
            installed|current|newer-preserved)
                case "${result}" in
                    installed) print_success "bb desktop installed and verified; not launched." ;;
                    current) print_debug "bb desktop is already current and verified." ;;
                    newer-preserved) print_debug "Newer verified bb desktop preserved." ;;
                    *) return 1 ;;
                esac
                if [[ "${platform}" == "linux" ]]; then
                    print_warning "bb desktop installation is verified; GUI/sandbox launch compatibility remains unverified. No launch or security-policy changes were performed."
                fi
                return 0 ;;
            deferred-running) print_warning "bb desktop update deferred: verified app is running. Quit it yourself and rerun setup."; return 0 ;;
            *) ;;
        esac
    fi
    # Only controlled diagnostic tokens cross the helper boundary, never stderr.
    if [[ "${result}" =~ ^failed:[a-z]+(-[a-z]+)*$ && "${status}" -ne 0 ]]; then
        print_error "bb desktop ${result}. Existing app/user/server state preserved; see README recovery/prerequisites."
    else
        print_error "bb desktop failed: unverified helper result. See README recovery/prerequisites."
    fi
    return 1
}
# END BB DESKTOP WRAPPER

# BEGIN BB DESKTOP PAYLOAD -- keep identical on supported platforms.
bb_desktop_payload() {
    /usr/bin/python3 -I - "$1" <<'BB_DESKTOP_PY'
# Embedded bb desktop policy. Keep copies identical; never execute desktop code.
import contextlib
import hashlib
import json
import os
from pathlib import Path
import plistlib
import pwd
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import time
import urllib.parse
import urllib.request
import zipfile

API = 'https://api.github.com/repos/get-bb/bb/releases'
WEB = 'https://github.com/get-bb/bb/releases'
VERSION = r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)'
UID = os.getuid()

class Refusal(Exception):
    pass

def require(ok, reason):
    if not ok:
        raise Refusal(reason)

def version(value):
    require(isinstance(value, str) and re.fullmatch(VERSION, value), 'invalid-version')
    return tuple(map(int, value.split('.')))

def unique_json(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, 'duplicate-metadata')
        result[key] = value
    return result

class Redirects(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        parsed = urllib.parse.urlsplit(newurl)
        require(parsed.scheme == 'https' and parsed.hostname in
                ('github.com', 'release-assets.githubusercontent.com') and
                not parsed.username and not parsed.password and parsed.port in (None, 443),
                'unsafe-redirect')
        return super().redirect_request(req, fp, code, msg, headers, newurl)

def fetch(url, target=None, maximum=16 * 1024 * 1024):
    # No credentials, curl config, custom endpoints, or unbounded redirects/downloads.
    opener = urllib.request.build_opener(Redirects())
    request = urllib.request.Request(url, headers={'User-Agent': 'machine-setup-bb-desktop',
                                                  'Accept': 'application/vnd.github+json'})
    start = time.monotonic()
    with opener.open(request, timeout=30) as response:
        require(response.status == 200, 'http-status')
        data = bytearray()
        with (open(target, 'xb') if target else contextlib.nullcontext(None)) as output:
            total = 0
            while True:
                chunk = response.read(1024 * 1024)
                if not chunk:
                    break
                total += len(chunk)
                require(total <= maximum and time.monotonic() - start < 600, 'download-limit')
                if output:
                    output.write(chunk)
                else:
                    data.extend(chunk)
        if not target:
            return json.loads(data, object_pairs_hook=unique_json)

def release_asset(release, platform, tag):
    require(isinstance(release, dict) and release.get('tag_name') == tag and
            release.get('draft') is False and release.get('prerelease') is False and
            release.get('html_url') == WEB + '/tag/' + tag, 'invalid-release')
    require(tag == 'desktop-latest' or re.fullmatch('desktop-v' + VERSION, tag), 'invalid-tag')
    assets = release.get('assets')
    require(isinstance(assets, list), 'invalid-assets')
    suffix = '-arm64.zip' if platform == 'macos' else '-x86_64.AppImage'
    candidates = [a for a in assets if isinstance(a, dict) and
                  isinstance(a.get('name'), str) and a['name'].endswith(suffix)]
    require(len(candidates) == 1, 'ambiguous-artifact')
    asset = candidates[0]
    name = asset['name']
    require(name.startswith('bb-'), 'invalid-artifact')
    number = name[3:-len(suffix)]
    version(number)
    require(tag in ('desktop-latest', 'desktop-v' + number), 'release-version-mismatch')
    require(type(asset.get('id')) is int and asset['id'] > 0 and
            type(asset.get('size')) is int and 0 < asset['size'] <= 2 * 1024**3 and
            isinstance(asset.get('digest'), str) and
            re.fullmatch(r'sha256:[0-9a-f]{64}', asset['digest']) and
            asset.get('state') == 'uploaded' and
            asset.get('browser_download_url') == WEB + '/download/' + tag + '/' + name,
            'invalid-artifact-metadata')
    return {**asset, 'version': number}

def command(args):
    result = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120,
                            env={**os.environ, 'LC_ALL': 'C'})
    require(result.returncode == 0, 'native-check-failed')
    return (result.stdout + result.stderr).decode('utf-8', errors='strict')

def linux_home_alias():
    if not Path('/home').is_symlink():
        return False
    require(os.lstat('/home').st_uid == 0 and os.readlink('/home') in ('var/home', '/var/home'),
            'unsafe-home-alias')
    for ancestor in ('/', '/var', '/var/home'):
        s = os.lstat(ancestor)
        require(stat.S_ISDIR(s.st_mode) and s.st_uid == 0 and not s.st_mode & 0o022,
                'unsafe-home-alias')
    return True

def trusted_home(raw, platform):
    require(raw and os.path.isabs(raw) and str(Path(raw)) == raw and
            not any(c in raw for c in '\n\r\x00'), 'unsafe-home')
    home = Path(raw)
    # Bazzite's one trusted system alias; no general realpath acceptance.
    if platform == 'linux' and home.parts[:2] == ('/', 'home') and linux_home_alias():
        home = Path('/var/home', *home.parts[2:])
    account = pwd.getpwuid(UID).pw_dir
    require(raw == account or str(home) == account, 'wrong-account-home')
    directory(home)
    require(home != Path('/') and home.stat().st_uid == UID, 'unsafe-home')
    return home

def checked_directory(path, macos=False):
    s = path.lstat()
    if macos and sys.platform == 'darwin' and path == Path('/Applications'):
        # Native admin (GID 80) may replace entries here. This is not a privacy
        # proof or a general group-write exception; see ADR 0006.
        require(stat.S_ISDIR(s.st_mode) and s.st_uid == 0 and s.st_gid == 80 and
                stat.S_IMODE(s.st_mode) in (0o755, 0o775), 'unsafe-directory')
    else:
        require(stat.S_ISDIR(s.st_mode) and s.st_uid in (0, UID) and
                (not s.st_mode & 0o022 or
                 (s.st_uid == 0 and s.st_mode & stat.S_ISVTX)), 'unsafe-directory')
    return s

def directory(path, create=False, macos=False):
    # Check every ancestor before creation. Root-owned sticky /tmp is fixtures-only
    # in practice; production stages beneath the verified application directory.
    for item in [*reversed(path.parents), path]:
        try:
            checked_directory(item, macos)
        except FileNotFoundError:
            require(create, 'missing-directory')
            item.mkdir(mode=0o700)
            checked_directory(item, macos)
    return path

def directory_identity(s):
    # Exclude size/times/link count: our own lock/stage/rename operations change
    # those. Ownership, group, permissions, type and filesystem identity must stay.
    return (s.st_dev, s.st_ino, s.st_mode, s.st_uid, s.st_gid)

def regular(path, macos=False):
    directory(path.parent, macos=macos)
    s = path.lstat()
    require(stat.S_ISREG(s.st_mode) and s.st_uid == UID and s.st_nlink == 1 and
            not s.st_mode & 0o022, 'unsafe-file')
    return s

def stable(s):
    return (s.st_dev, s.st_ino, s.st_mode, s.st_uid, s.st_nlink, s.st_size, s.st_mtime_ns, s.st_ctime_ns)

def fingerprint(path, macos=False):
    s = regular(path, macos)
    digest = hashlib.sha256()
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(fd, 'rb') as stream:
        require(stable(os.fstat(stream.fileno())) == stable(s), 'file-changed')
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
        require(stable(os.fstat(stream.fileno())) == stable(s) and
                stable(path.lstat()) == stable(s), 'file-changed')
    return digest.hexdigest()

def exists(path):
    return os.path.lexists(path)

def installed_linux(path, latest):
    require(regular(path).st_mode & stat.S_IXUSR, 'nonexecutable-appimage')
    digest = fingerprint(path)
    with path.open('rb') as stream:
        header = stream.read(20)
    require(header[:4] == b'\x7fELF' and header[4:6] == b'\x02\x01' and
            header[8:11] == b'AI\x02' and header[18:20] == b'\x3e\x00', 'invalid-appimage')
    if latest['digest'] == 'sha256:' + digest and latest['size'] == path.stat().st_size:
        return latest['version'], digest
    # Hash the actual self-updated bytes, then find their official release identity.
    # A bounded catalogue miss is a failure, never permission to overwrite a custom copy.
    for page in range(1, 6):
        releases = fetch(API + '?per_page=100&page=' + str(page))
        require(isinstance(releases, list), 'invalid-catalogue')
        matches = []
        for release in releases:
            tag = release.get('tag_name', '') if isinstance(release, dict) else ''
            if not re.fullmatch('desktop-v' + VERSION, tag):
                continue
            if not any(isinstance(a, dict) and a.get('digest') == 'sha256:' + digest
                       for a in release.get('assets', [])):
                continue
            asset = release_asset(release, 'linux', tag)
            if asset['digest'] == 'sha256:' + digest and asset['size'] == path.stat().st_size:
                matches.append(asset['version'])
        require(len(set(matches)) <= 1, 'ambiguous-installed-version')
        if matches:
            return matches[0], digest
        if len(releases) < 100:
            break
    raise Refusal('unverified-installed-appimage')

def bundle_root_identity(path):
    s = path.lstat()
    return (stable(s), s.st_gid)

def bundle(path):
    directory(path, macos=True)
    require(path.stat().st_uid == UID, 'foreign-bundle')
    # Framework symlinks are normal; allow only bundle-contained resolved targets.
    for root, dirs, files in os.walk(path, followlinks=False):
        for name in dirs + files:
            item = Path(root, name)
            s = item.lstat()
            require(s.st_uid == UID, 'foreign-bundle-file')
            if stat.S_ISLNK(s.st_mode):
                require(item.resolve().is_relative_to(path.resolve()) and item.exists(), 'unsafe-bundle-link')
            else:
                require((stat.S_ISDIR(s.st_mode) or stat.S_ISREG(s.st_mode)) and
                        not s.st_mode & 0o022, 'unsafe-bundle-file')
    info = path / 'Contents/Info.plist'
    regular(info, macos=True)
    data = plistlib.loads(info.read_bytes())
    require(data.get('CFBundleIdentifier') == 'dev.bb.desktop' and
            data.get('CFBundleExecutable') == 'bb', 'wrong-bundle-identity')
    number = data.get('CFBundleShortVersionString')
    version(number)
    minimum = data.get('LSMinimumSystemVersion', '')
    if minimum.count('.') == 1:
        minimum += '.0'
    current = command(['/usr/bin/sw_vers', '-productVersion']).strip()
    if current.count('.') == 1:
        current += '.0'
    require(version(current) >= version(minimum), 'macos-too-old')
    require(command(['/usr/bin/lipo', '-archs', str(path / 'Contents/MacOS/bb')]).strip() == 'arm64',
            'wrong-bundle-architecture')
    command(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(path)])
    signature = command(['/usr/bin/codesign', '-dv', '--verbose=4', str(path)])
    team = re.search(r'^TeamIdentifier=([A-Z0-9]{10})$', signature, re.M)
    require(team and re.search(r'^Identifier=dev\.bb\.desktop$', signature, re.M), 'wrong-signature')
    assessment = command(['/usr/sbin/spctl', '--assess', '--type', 'execute', '--verbose=2', str(path)])
    require('source=Notarized Developer ID' in assessment, 'not-notarized')
    return number, team[1]

def unpack_mac(archive, stage):
    # Preflight the complete ZIP before ditto restores signed bundle metadata.
    with zipfile.ZipFile(archive) as z:
        entries = z.infolist()
        require(len(entries) <= 200000 and sum(e.file_size for e in entries) <= 4 * 1024**3,
                'archive-limit')
        names, links = set(), set()
        for entry in entries:
            name = entry.filename.rstrip('/')
            parts = name.split('/')
            require(parts[0] in ('bb.app', '__MACOSX') and all(p not in ('', '.', '..') for p in parts) and
                    '\\' not in name and name not in names, 'unsafe-archive-path')
            names.add(name)
            mode = entry.external_attr >> 16
            require(stat.S_IFMT(mode) in (0, stat.S_IFREG, stat.S_IFDIR, stat.S_IFLNK), 'unsafe-archive-type')
            if stat.S_ISLNK(mode):
                require(parts[0] == 'bb.app' and entry.file_size < 4096, 'unsafe-archive-link')
                target = z.read(entry).decode('utf-8')
                resolved = os.path.normpath(os.path.join(os.path.dirname(name), target))
                require(not os.path.isabs(target) and resolved.startswith('bb.app/'), 'unsafe-archive-link')
                links.add(name)
        for name in names:
            require(not any(str(p) in links for p in Path(name).parents), 'archive-through-link')
    command(['/usr/bin/ditto', '-x', '-k', str(archive), str(stage)])
    return stage / 'bb.app'

def linux_process_snapshot(proc):
    fields = (proc / 'stat').read_text().rsplit(')', 1)[1].split()
    status = (proc / 'status').read_text()
    uids = re.search(r'^Uid:\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)$', status, re.M)
    name = re.search(r'^Name:\s+([^\n]+)$', status, re.M)
    state = re.search(r'^State:\s+([A-Z])\b', status, re.M)
    require(len(fields) > 19 and fields[19].isdigit() and uids and name and state, 'process-inspection')
    return fields[19], tuple(map(int, uids.groups())), name[1], state[1]

def desktop_process_name(name):
    # Titles are only a conservative screen when executable evidence is unavailable.
    return bool(re.fullmatch(r'bb(?:\.AppImage| Helper[^\n]*)?', name))

def linux_running(path):
    found = False
    for proc in Path('/proc').iterdir():
        if not proc.name.isdigit():
            continue
        try:
            before = linux_process_snapshot(proc)
            _, owners, name, state = before
            if state == 'Z' or (UID not in owners and not desktop_process_name(name)):
                # Exclude stable foreign processes before private exe/env reads.
                # A foreign native desktop title still needs an ownership check.
                require(linux_process_snapshot(proc)[:3] == before[:3], 'process-changed')
                continue
            try:
                exe = os.readlink(proc / 'exe')
            except PermissionError:
                raise Refusal('process-executable-unverified') from None
            clean_exe = exe.removesuffix(' (deleted)')
            require(os.path.isabs(clean_exe), 'process-executable-unverified')
            exact = clean_exe == str(path)
            native = desktop_process_name(Path(clean_exe).name)
            candidate_running = False
            if exact or native:
                require(owners == (UID,) * 4, 'process-owner')
                if exact:
                    # The AppImage runtime/controller itself is sufficient evidence;
                    # its environment is unnecessary and may be non-dumpable.
                    candidate_running = True
                else:
                    try:
                        env = (proc / 'environ').read_bytes().split(b'\0')
                    except PermissionError:
                        raise Refusal('process-environment-unverified') from None
                    image = [e[9:].decode('utf-8') for e in env if e.startswith(b'APPIMAGE=')]
                    require(len(image) == 1 and os.path.isabs(image[0]) and
                            not any(c in image[0] for c in '\n\r'), 'ambiguous-process')
                    belongs = image == [str(path)]
                    if image[0].startswith('/home/') and str(path).startswith('/var/home/'):
                        belongs = belongs or (linux_home_alias() and '/var' + image[0] == str(path))
                    if belongs:
                        # type2-runtime honors TMPDIR; do not assume /tmp or the
                        # mount prefix's filename (argv[0] can name a symlink).
                        runtime_dir = Path(clean_exe).parent.name
                        require(Path(clean_exe).name == 'bb' and re.fullmatch(
                            r'(?:\.mount_[^/]+|appimage_extracted_[^/]+)', runtime_dir),
                            'unverified-desktop-executable')
                        candidate_running = True
            # A verified unrelated executable is not made relevant by a native
            # title or inherited APPIMAGE. Never open its environment. Recheck its
            # executable too, so an exec/UID/PID change cannot become an exclusion.
            try:
                after_exe = os.readlink(proc / 'exe')
            except PermissionError:
                raise Refusal('process-executable-unverified') from None
            # R/S scheduling changes are not process identity changes.
            require(after_exe == exe and linux_process_snapshot(proc)[:3] == before[:3], 'process-changed')
            found = found or candidate_running
        except FileNotFoundError:
            require(not proc.exists(), 'process-inspection')
    return found

def running(path, platform):
    if platform == 'macos':
        rows = command(['/bin/ps', '-ww', '-axo', 'uid=,pid=,comm=']).splitlines()
        require(rows, 'process-inspection')
        found = False
        for row in rows:
            parts = row.strip().split(None, 2)
            require(len(parts) == 3 and parts[0].isdigit() and parts[1].isdigit(), 'process-inspection')
            owner, _, exe = parts
            if exe.startswith(str(path) + '/'):
                require(int(owner) == UID, 'process-owner')
                found = True
            elif re.fullmatch(r'bb(?: Helper(?: \([^)]*\))?)?', exe):
                raise Refusal('ambiguous-process')
        return found
    return linux_running(path)

def menu_text(path):
    # Desktop Exec is not a shell. Quote both Exec and desktop-string escapes;
    # refuse field-code/path ambiguities rather than silently launch something else.
    require(not any(c in str(path) for c in '\n\r\t%`$"\\'), 'unsafe-menu-path')
    return ('[Desktop Entry]\nType=Application\nName=bb\nComment=bb agentic IDE\n'
            'Exec="' + str(path) + '" --appimage-extract-and-run\n'
            'Icon=applications-development\nTerminal=false\nCategories=Development;IDE;\n'
            'X-Setup-BB-Desktop=1\n')

def promote(candidate, target, menu, text, stage, verify, unchanged, platform, boundary=None):
    # Preserve both prior objects through all validation/menu failures. No native
    # updater lock is available: recheck process state immediately before rename.
    unchanged()
    if running(target, platform):
        require(exists(target), 'unverified-desktop-process')
        if boundary:
            unchanged()
        return 'deferred-running'
    unchanged()
    objects = [(candidate, target)]
    if menu:
        staged_menu = stage / 'menu.desktop'
        staged_menu.write_text(text)
        objects.append((staged_menu, menu))
    moved = []
    try:
        for index, (source, dest) in enumerate(objects):
            if boundary:
                boundary()
            directory(dest.parent, macos=platform == 'macos')
            backup = stage / ('previous-' + str(index))
            had_old = exists(dest)
            if had_old:
                os.rename(dest, backup)
            moved.append((dest, backup, had_old))
            if boundary:
                boundary()
            os.rename(source, dest)
        if boundary:
            boundary()
        verify(target)
        if boundary:
            boundary()
        if menu:
            regular(menu)
            require(menu.read_text() == text, 'menu-verification')
    except Exception:
        for dest, backup, had_old in reversed(moved):
            if boundary:
                boundary()
            directory(dest.parent, macos=platform == 'macos')
            if exists(dest):
                os.rename(dest, stage / ('rejected-' + dest.name))
            if had_old:
                if boundary:
                    boundary()
                os.rename(backup, dest)
        raise
    return 'installed'

def install(platform):
    os.umask(0o077)
    require(UID != 0, 'root-account')
    home = trusted_home(os.environ.get('HOME'), platform)
    if platform == 'macos':
        os_version = command(['/usr/bin/sw_vers', '-productVersion']).strip()
        if os_version.count('.') == 1:
            os_version += '.0'
        require(version(os_version) >= (13, 0, 0), 'macos-too-old')
        user_app, system_app = home / 'Applications/bb.app', Path('/Applications/bb.app')
        require(not (exists(user_app) and exists(system_app)), 'ambiguous-applications')
        target = system_app if exists(system_app) else user_app
        menu = None
    else:
        target = home / '.local/opt/bb-desktop/bb.AppImage'
        data_home = os.environ.get('XDG_DATA_HOME', str(home / '.local/share'))
        raw_home = os.environ['HOME']
        if raw_home != str(home) and data_home.startswith(raw_home + '/'):
            data_home = str(home) + data_home[len(raw_home):]
        require(os.path.isabs(data_home) and Path(data_home).is_relative_to(home) and
                Path(data_home) != home and '..' not in Path(data_home).parts, 'unsafe-menu-directory')
        menu = Path(data_home) / 'applications/dev.bb.desktop.desktop'
    system_app = (platform == 'macos' and sys.platform == 'darwin' and
                  target == Path('/Applications/bb.app'))
    directory(target.parent, create=not system_app, macos=platform == 'macos')
    require(target.parent.stat().st_uid == UID or system_app, 'foreign-applications-directory')
    # Only an already-present system app selects this path. Fresh installs still
    # use ~/Applications; never elevate, repair permissions or relocate a copy.
    boundaries = []
    if system_app:
        for item in [*reversed(target.parent.parents), target.parent]:
            boundaries.append((item, directory_identity(checked_directory(item, macos=True))))
    def boundary():
        # Parent-before-descendant revalidation also guards rollback and cleanup.
        for item, identity in boundaries:
            require(directory_identity(item.lstat()) == identity, 'transaction-changed')
    def private_boundary(path):
        if system_app:
            boundary()
            s = checked_directory(path, macos=True)
            require(s.st_uid == UID and stat.S_IMODE(s.st_mode) == 0o700, 'unsafe-transaction-directory')
            boundaries.append((path, directory_identity(s)))
            boundary()
    boundary()
    text = menu_text(target) if menu else None
    old_menu = None
    if menu:
        directory(menu.parent, create=True)
        if exists(menu):
            regular(menu)
            old_menu = menu.read_bytes()
            require(old_menu == text.encode(), 'unmanaged-menu')
    lock = target.parent / '.setup-bb-desktop.lock'
    lock.mkdir(mode=0o700)  # An occupied/link/stale lock fails closed.
    lock_identity = (lock.stat().st_dev, lock.stat().st_ino)
    private_boundary(lock)
    completed = False
    transaction_ready = not system_app
    try:
        boundary()
        stage = Path(tempfile.mkdtemp(prefix='stage-', dir=lock))
        private_boundary(stage)
        transaction_ready = True
        latest = release_asset(fetch(API + '/tags/desktop-latest'), platform, 'desktop-latest')
        boundary()
        previous = None
        previous_root = bundle_root_identity(target) if system_app else None
        if exists(target):
            previous = installed_linux(target, latest) if platform == 'linux' else bundle(target)
            boundary()
            if platform == 'linux' and running(target, platform):
                completed = True
                return 'deferred-running'
        if platform == 'linux':
            # Installation-only contract: keep the required runtime baseline,
            # but do not inspect policy or probe GUI/sandbox launch compatibility.
            # The wrapper warns only after a strictly validated successful result.
            libc = re.fullmatch(r'glibc ([0-9]+)\.([0-9]+)', os.confstr('CS_GNU_LIBC_VERSION') or '')
            require(libc and tuple(map(int, libc.groups())) >= (2, 35), 'glibc-too-old')
            if previous and version(previous[0]) >= version(latest['version']):
                if menu and not exists(menu):
                    # Menu-only convergence also needs the process/destination recheck.
                    require(installed_linux(target, latest) == previous and not running(target, platform),
                            'installation-changed')
                    staged_menu = stage / 'menu.desktop'
                    staged_menu.write_text(text)
                    directory(menu.parent)
                    # Exclusive publication: preserve a menu created concurrently.
                    os.link(staged_menu, menu, follow_symlinks=False)
                    staged_menu.unlink()
                    regular(menu)
                    require(menu.read_text() == text, 'menu-verification')
                completed = True
                return 'current' if previous[0] == latest['version'] else 'newer-preserved'
        archive = stage / 'download'
        boundary()
        fetch(latest['browser_download_url'], archive, latest['size'])
        boundary()
        require(archive.stat().st_size == latest['size'] and
                fingerprint(archive, macos=platform == 'macos') == latest['digest'][7:], 'integrity-mismatch')
        if platform == 'macos':
            boundary()
            candidate = unpack_mac(archive, stage)
            boundary()
            identity = bundle(candidate)
            boundary()
            require(identity[0] == latest['version'], 'bundle-version-mismatch')
            if previous:
                require(previous[1] == identity[1], 'different-signing-team')
                is_running = running(target, platform)
                if system_app:
                    boundary()
                    require(bundle(target) == previous and
                            bundle_root_identity(target) == previous_root,
                            'installation-changed')
                    boundary()
                if is_running:
                    completed = True
                    return 'deferred-running'
                if version(previous[0]) >= version(identity[0]):
                    completed = True
                    return 'current' if previous[0] == identity[0] else 'newer-preserved'
            verify = lambda path: require(bundle(path) == identity, 'bundle-changed')
        else:
            candidate = archive
            candidate.chmod(0o700)
            require(installed_linux(candidate, latest)[0] == latest['version'], 'invalid-appimage')
            verify = lambda path: require(fingerprint(path) == latest['digest'][7:], 'integrity-mismatch')
        def unchanged():
            boundary()
            directory(target.parent, macos=platform == 'macos')
            actual = (installed_linux(target, latest) if platform == 'linux' else bundle(target)) if exists(target) else None
            require(actual == previous, 'installation-changed')
            if system_app:
                require(bundle_root_identity(target) == previous_root, 'installation-changed')
            boundary()
            if menu:
                regular(menu) if exists(menu) else directory(menu.parent)
                require((menu.read_bytes() if exists(menu) else None) == old_menu, 'menu-changed')
        result = promote(candidate, target, menu, text, stage, verify, unchanged, platform,
                         boundary if system_app else None)
        completed = True
        return result
    finally:
        # Retain an interrupted/failed rollback for manual recovery. Ordinary
        # preflight/download failures and completed rollbacks can be retried.
        boundary()
        directory(lock, macos=platform == 'macos')
        require((lock.stat().st_dev, lock.stat().st_ino) == lock_identity, 'transaction-changed')
        # A system stage that never passed private-boundary validation is not
        # ours to traverse/delete. Preserve it along with the lock on uncertainty.
        if transaction_ready:
            backups = list(lock.glob('stage-*/previous-*'))
            if completed or not backups:
                require(shutil.rmtree.avoids_symlink_attacks, 'unsafe-cleanup-runtime')
                shutil.rmtree(lock)

def main():
    try:
        print(install(sys.argv[1]))
    except Refusal as error:
        print('failed:' + str(error))
        return 1
    except Exception:
        # Native/network exceptions can include paths, environment, or credentials.
        print('failed:operation-error')
        return 1
    return 0

if __name__ == '__main__':
    sys.exit(main())
BB_DESKTOP_PY
}
# END BB DESKTOP PAYLOAD

run_setup_tasks() {
    local _setup_had_errors=0
    local _pi_go_ready=0
    local PI_PROFILE_MUTATIONS_BLOCKED=0
    echo -e "\n${BOLD}🎮 Bazzite Development Environment Setup${NC}"
    echo -e "${GRAY}Version 149 | Last changed: Report bounded secret-safe evidence at real PATH discovery"

    if ! acquire_setup_lock; then
        return 1
    fi

    # Create placeholder env file early (migrates old token files if present)
    create_env_local

    # Read flags as literal data, never executable shell input.
    setup_load_environment || return 1

    headless_platform_gate || return 1

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

    print_section "bb Desktop"
    install_bb_desktop bazzite || _setup_had_errors=1

    install_secrets_manager || _setup_had_errors=1
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
        if ! with_bb_dotfiles_umask bazzite chezmoi apply --force; then
            print_error "Failed to apply chezmoi dotfiles."
            _setup_had_errors=1
        fi
        # The apply may replace ~/.ssh/config; leave the deploy alias durable.
        bootstrap_ssh_config
    else
        print_warning "Skipping dotfiles management - no access to repository."
    fi

    if ! retire_global_backlog_mcp; then
        _setup_had_errors=1
    fi

    print_section "Shell Configuration"
    install_tmux_plugins
    enable_user_lingering

    print_section "Development Tools"
    install_gitea_client || return 1
    install_bun || return 1
    install_opencode_cli || _setup_had_errors=1
    install_sfw
    install_claude_code
    install_gemini_cli
    install_codex_cli || return 1
    install_portless_cli
    install_ntn_cli
    setup_bb_machine bazzite || { print_error 'BB machine preparation incomplete; existing BB state was preserved.'; _setup_had_errors=1; }
    refresh_bb_plugins ready || _setup_had_errors=1
    if ! prepare_pi_profile_permissions; then
        PI_PROFILE_MUTATIONS_BLOCKED=1
        _setup_had_errors=1
    fi
    remove_rtk_resources || return 1
    remove_attention_span_resources || return 1
    setup_matt_pocock_skills || _setup_had_errors=1
    if [[ "${PI_PROFILE_MUTATIONS_BLOCKED}" -eq 1 ]]; then
        print_warning "Skipping Pi setup because profile permission preparation failed."
    elif ! disable_pi_askclaude; then
        PI_PROFILE_MUTATIONS_BLOCKED=1
        print_warning "Skipping Pi package setup because the AskClaude policy failed."
        _setup_had_errors=1
    elif ! remove_pi_prose; then
        PI_PROFILE_MUTATIONS_BLOCKED=1
        print_warning "Skipping Pi package setup because prose retirement failed."
        _setup_had_errors=1
    elif install_pi_cli; then
        configure_pi_defaults
        remove_pi_synthetic_models
        seed_pi_zai_models
        if configure_pi_opencode_go; then
            _pi_go_ready=1
        else
            PI_PROFILE_MUTATIONS_BLOCKED=1
            _setup_had_errors=1
        fi
        # Re-pin the adapter before any operation resolves the shared npm tree.
        if [[ "${_pi_go_ready}" -eq 1 ]] && prepare_pi_mcp_adapter; then
            local _pi_package_maintenance_ok=1
            setup_pi_mcp_adapter || { _setup_had_errors=1; _pi_package_maintenance_ok=0; }
            remove_pi_subagents || { _setup_had_errors=1; _pi_package_maintenance_ok=0; }
            remove_pi_rpiv_packages || { _setup_had_errors=1; _pi_package_maintenance_ok=0; }
            setup_pi_claude_bridge || { _setup_had_errors=1; _pi_package_maintenance_ok=0; }
            setup_pi_companion_packages || { _setup_had_errors=1; _pi_package_maintenance_ok=0; }
            setup_pi_goal_autoresearch || { _setup_had_errors=1; _pi_package_maintenance_ok=0; }
            if [[ "${_pi_package_maintenance_ok}" -eq 1 ]]; then
                refresh_pi_packages || _setup_had_errors=1
            else
                print_warning "Skipping Pi package refresh because prerequisite package maintenance failed."
            fi
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

    remove_simple_english_skill || _setup_had_errors=1
    remove_show_me_skill || _setup_had_errors=1
    remove_pr_lens_skill || _setup_had_errors=1
    configure_pi_skill_ownership || _setup_had_errors=1

    verify_fish_development_tools || return 1
    remove_impeccable_resources

    remove_compound_engineering_resources

    print_section "Final Updates"
    update_brew || _setup_had_errors=1

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
