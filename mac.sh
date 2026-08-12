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

SETUP_ORIGINAL_PATH="${PATH}"
SETUP_ORIGINAL_CLAUDE_COMMAND=$(command -v claude 2>/dev/null || true)
SETUP_MKDIR_LOCK_DIR=""
SETUP_LOCK_RECLAIM_DIR=""
SETUP_TMUX_PINNED=0
SETUP_BREW_TRUST_FAILURES=0
SETUP_LOG_FILE=""
SETUP_LOG_TEE_PID=""
SETUP_LOGGING_ACTIVE=0

release_setup_reclaim() {
    if [[ -n "${SETUP_LOCK_RECLAIM_DIR}" ]]; then
        rm -f "${SETUP_LOCK_RECLAIM_DIR}/pid" "${SETUP_LOCK_RECLAIM_DIR}/process-start"
        rmdir "${SETUP_LOCK_RECLAIM_DIR}" 2>/dev/null || true
        SETUP_LOCK_RECLAIM_DIR=""
    fi
}

release_setup_lock() {
    if [[ -n "${SETUP_MKDIR_LOCK_DIR}" ]] && [[ -d "${SETUP_MKDIR_LOCK_DIR}" ]]; then
        local _owner_pid=""
        if [[ -f "${SETUP_MKDIR_LOCK_DIR}/pid" ]]; then
            _owner_pid=$(cat "${SETUP_MKDIR_LOCK_DIR}/pid" 2>/dev/null || true)
        fi
        if [[ -z "${_owner_pid}" ]] || [[ "${_owner_pid}" == "$$" ]]; then
            rm -f "${SETUP_MKDIR_LOCK_DIR}/pid" "${SETUP_MKDIR_LOCK_DIR}/process-start"
            rmdir "${SETUP_MKDIR_LOCK_DIR}" 2>/dev/null || true
        fi
    fi
    SETUP_MKDIR_LOCK_DIR=""
    release_setup_reclaim
}

setup_cleanup() {
    if [[ "${SETUP_TMUX_PINNED}" == "1" ]] && command -v brew &>/dev/null; then
        if brew unpin tmux > /dev/null 2>&1; then
            SETUP_TMUX_PINNED=0
        fi
    fi
    release_setup_lock
}

install_setup_cleanup_traps() {
    trap setup_cleanup EXIT
    trap 'setup_cleanup; exit 129' HUP
    trap 'setup_cleanup; exit 130' INT
    trap 'setup_cleanup; exit 143' TERM
}

# Acquire a non-blocking per-user setup lock so overlapping setup runs don't
# corrupt shared global package directories (npm, Bun, Homebrew, etc.). Always
# use the same atomic mkdir namespace so PATH differences cannot split the lock.
acquire_setup_lock() {
    local _lock_root="${XDG_RUNTIME_DIR:-${HOME}/.local/state}"
    local _lock_dir="${_lock_root}/machine-setup.lock.d"
    local _reclaim_dir="${_lock_dir}.reclaim"

    if [[ "${MACHINE_SETUP_ALLOW_CONCURRENT:-}" == "1" ]]; then
        print_warning "MACHINE_SETUP_ALLOW_CONCURRENT=1, skipping concurrent setup guard."
        return 0
    fi

    if ! mkdir -p "${_lock_root}"; then
        print_warning "Could not create setup lock directory at ${_lock_root}; continuing without a lock."
        return 0
    fi

    if [[ -d "${_reclaim_dir}" ]]; then
        local _reclaim_pid=""
        local _reclaim_start=""
        local _reclaim_current_start=""
        local _reclaim_alive=0
        local _reclaim_mtime=""
        local _reclaim_age=0
        if [[ -f "${_reclaim_dir}/pid" ]]; then
            _reclaim_pid=$(cat "${_reclaim_dir}/pid" 2>/dev/null || true)
        fi
        if [[ -f "${_reclaim_dir}/process-start" ]]; then
            _reclaim_start=$(cat "${_reclaim_dir}/process-start" 2>/dev/null || true)
        fi
        if [[ "${_reclaim_pid}" =~ ^[0-9]+$ ]] && kill -0 "${_reclaim_pid}" 2>/dev/null; then
            _reclaim_alive=1
            _reclaim_current_start=$(LC_ALL=C TZ=UTC ps -p "${_reclaim_pid}" -o lstart= 2>/dev/null || true)
            if [[ -n "${_reclaim_start}" ]] && [[ "${_reclaim_start}" == "${_reclaim_current_start}" ]]; then
                print_warning "Another machine setup run is recovering a stale lock; exiting before making changes."
                print_debug "Recovery directory: ${_reclaim_dir} (PID ${_reclaim_pid})"
                return 1
            fi
        fi
        if [[ -z "${_reclaim_pid}" ]] || { [[ "${_reclaim_alive}" -eq 1 ]] && [[ -z "${_reclaim_start}" ]]; }; then
            _reclaim_mtime=$(stat -f '%m' "${_reclaim_dir}" 2>/dev/null || stat -c '%Y' "${_reclaim_dir}" 2>/dev/null || true)
            if [[ "${_reclaim_mtime}" =~ ^[0-9]+$ ]]; then
                _reclaim_age=$(( $(date +%s) - _reclaim_mtime ))
            fi
            if [[ "${_reclaim_age}" -lt 300 ]]; then
                print_warning "Another machine setup run may be starting stale-lock recovery; exiting before making changes."
                print_debug "Recovery directory: ${_reclaim_dir}"
                return 1
            fi
        fi

        rm -rf "${_reclaim_dir}"
        print_warning "Removed a stale setup-lock recovery marker; rerun setup to acquire the lock safely."
        return 1
    fi

    if ! mkdir "${_lock_dir}" 2>/dev/null; then
        if ! mkdir "${_reclaim_dir}" 2>/dev/null; then
            print_warning "Another machine setup run is already in progress; exiting before making changes."
            print_debug "Lock directory: ${_lock_dir}"
            return 1
        fi
        SETUP_LOCK_RECLAIM_DIR="${_reclaim_dir}"
        install_setup_cleanup_traps
        if ! LC_ALL=C TZ=UTC ps -p "$$" -o lstart= > "${_reclaim_dir}/process-start" || ! printf '%s\n' "$$" > "${_reclaim_dir}/pid"; then
            release_setup_reclaim
            print_warning "Could not record stale-lock recovery ownership; exiting before making changes."
            return 1
        fi

        local _owner_pid=""
        local _owner_start=""
        local _current_start=""
        local _owner_alive=0
        local _lock_mtime=""
        local _lock_age=0
        if [[ -f "${_lock_dir}/pid" ]]; then
            _owner_pid=$(cat "${_lock_dir}/pid" 2>/dev/null || true)
        fi
        if [[ -f "${_lock_dir}/process-start" ]]; then
            _owner_start=$(cat "${_lock_dir}/process-start" 2>/dev/null || true)
        fi

        if [[ "${_owner_pid}" =~ ^[0-9]+$ ]] && kill -0 "${_owner_pid}" 2>/dev/null; then
            _owner_alive=1
            _current_start=$(LC_ALL=C TZ=UTC ps -p "${_owner_pid}" -o lstart= 2>/dev/null || true)
            if [[ -n "${_owner_start}" ]] && [[ "${_owner_start}" == "${_current_start}" ]]; then
                release_setup_reclaim
                print_warning "Another machine setup run is already in progress; exiting before making changes."
                print_debug "Lock directory: ${_lock_dir} (PID ${_owner_pid})"
                return 1
            fi
        fi

        if [[ -z "${_owner_pid}" ]] || { [[ "${_owner_alive}" -eq 1 ]] && [[ -z "${_owner_start}" ]]; }; then
            _lock_mtime=$(stat -f '%m' "${_lock_dir}" 2>/dev/null || stat -c '%Y' "${_lock_dir}" 2>/dev/null || true)
            if [[ "${_lock_mtime}" =~ ^[0-9]+$ ]]; then
                _lock_age=$(( $(date +%s) - _lock_mtime ))
            fi
            if [[ "${_lock_age}" -lt 300 ]]; then
                release_setup_reclaim
                print_warning "Another machine setup run may be starting; exiting before making changes."
                print_debug "Lock directory: ${_lock_dir}"
                return 1
            fi
        fi

        print_debug "Removing stale setup lock at ${_lock_dir}${_owner_pid:+ (PID ${_owner_pid})}."
        rm -rf "${_lock_dir}"
        if ! mkdir "${_lock_dir}" 2>/dev/null; then
            release_setup_reclaim
            print_warning "Another machine setup run acquired the lock first; exiting before making changes."
            return 1
        fi
        SETUP_MKDIR_LOCK_DIR="${_lock_dir}"
        release_setup_reclaim
    else
        SETUP_MKDIR_LOCK_DIR="${_lock_dir}"
        install_setup_cleanup_traps
    fi

    if ! LC_ALL=C TZ=UTC ps -p "$$" -o lstart= > "${_lock_dir}/process-start" || ! printf '%s\n' "$$" > "${_lock_dir}/pid"; then
        release_setup_lock
        print_warning "Could not record setup lock ownership at ${_lock_dir}; continuing without a lock."
        return 0
    fi

    print_debug "Acquired portable setup lock at ${_lock_dir}."
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

# Machine/setup guards
# HEADLESS=1
# WORK_MACHINE=1
# BAN_PI_SUBAGENTS=1
# BAN_PI_MCP_ADAPTER=1
# BAN_PI_GOAL_AUTORESEARCH=1
# BAN_MATT_POCOCK_SKILLS=1
# BAN_RTK=1
# SYNTHETIC_API_KEY=<your Synthetic API key>
# BAN_CLAUDE_CODE=1
EOF
        chmod 600 "${HOME}/.env.local"
        print_debug "Created placeholder ~/.env.local"
    fi
}

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

    # Copy to clipboard if pbcopy is available
    if command -v pbcopy &>/dev/null; then
        pbcopy < "${key_file}.pub"
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
        local _ssh_output
        _ssh_output=$(ssh -i "${key_file}" -o StrictHostKeyChecking=accept-new -T git@github.com < /dev/null 2>&1) || true
        if echo "${_ssh_output}" | grep -q "successfully authenticated"; then
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
        local _ssh_output
        _ssh_output=$(ssh -T git@github.com < /dev/null 2>&1) || true
        if echo "${_ssh_output}" | grep -q "successfully authenticated"; then
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
        local _deploy_ssh_output
        _deploy_ssh_output=$(ssh -i ~/.ssh/dotfiles-deploy-key -T git@github.com < /dev/null 2>&1) || true
        if echo "${_deploy_ssh_output}" | grep -q "successfully authenticated"; then
            print_debug "Access via deploy key"
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

    # Ensure user owns the Homebrew zsh directories (required for brew upgrade)
    # This may need sudo if root currently owns them
    local current_user
    current_user=$(whoami || true)
    local zsh_dir="/opt/homebrew/share/zsh"
    local zsh_completions="/opt/homebrew/share/zsh-completions"

    for dir in "${zsh_dir}" "${zsh_completions}"; do
        if [[ -d "${dir}" ]]; then
            local owner
            owner=$(stat -f "%Su" "${dir}" 2>/dev/null)
            if [[ "${owner}" != "${current_user}" ]]; then
                print_debug "Fixing ownership of ${dir} (currently owned by ${owner})..."
                if can_sudo; then
                    sudo chown -R "${current_user}:admin" "${dir}" 2>/dev/null || true
                fi
            fi
        fi
    done

    # Fix permissions (remove group/other write) - this satisfies compaudit
    chmod -R go-w /opt/homebrew/share/zsh 2>/dev/null || true
    chmod -R go-w /opt/homebrew/share/zsh-completions 2>/dev/null || true
    chmod -R go-w /usr/local/share/zsh 2>/dev/null || true

    zsh -c 'compaudit 2>/dev/null | xargs -I {} chmod go-w {} 2>/dev/null' || true
    print_success "zsh directory permissions fixed."
}

# Trust only Homebrew items that this setup script explicitly manages.
ensure_brew_item_trusted() {
    local _type=$1
    local _item=$2
    local _tap=$3
    local _trust_flag

    case "${_type}" in
        formula) _trust_flag="--formula" ;;
        cask) _trust_flag="--cask" ;;
        *)
            SETUP_BREW_TRUST_FAILURES=1
            print_warning "Unsupported Homebrew trust type: ${_type}"
            return 1
            ;;
    esac

    if ! { brew tap || true; } | grep -q "^${_tap}$"; then
        print_message "Adding Homebrew tap ${_tap}..."
        if ! brew tap "${_tap}"; then
            SETUP_BREW_TRUST_FAILURES=1
            print_warning "Failed to tap ${_tap}; cannot manage ${_item}."
            return 1
        fi
    fi

    if brew trust "${_trust_flag}" "${_item}" > /dev/null; then
        print_debug "Trusted managed Homebrew ${_type}: ${_item}"
        return 0
    fi

    SETUP_BREW_TRUST_FAILURES=1
    print_warning "Failed to trust managed Homebrew ${_type} ${_item}; Homebrew may skip it."
    return 1
}

report_unmanaged_untrusted_brew_items() {
    local _untrusted_output
    local _installed_formulae
    local _installed_casks
    local _section=""
    local _item
    local _short_name
    local _tap
    local _unmanaged_count=0

    _untrusted_output=$(brew untrust 2>/dev/null) || return
    _installed_formulae=$(brew list --formula --full-name 2>/dev/null || true)
    _installed_casks=$(brew list --cask -1 2>/dev/null || true)

    while IFS= read -r _item; do
        case "${_item}" in
            "Untrusted formulae:")
                _section="formula"
                continue
                ;;
            "Untrusted casks:")
                _section="cask"
                continue
                ;;
            "Untrusted "*)
                _section=""
                continue
                ;;
            *) ;;
        esac
        if [[ -z "${_section}" ]] || [[ "${_item}" != "  "* ]]; then
            continue
        fi
        _item=${_item#  }

        case "${_item}" in
            libsql/sqld/sqld|tursodatabase/tap/turso|infisical/get-cli/infisical|dopplerhq/cli/doppler|soren-starck/tap/sessionwatcher)
                continue
                ;;
            *) ;;
        esac

        if [[ "${_section}" == "formula" ]]; then
            grep -Fxq "${_item}" <<< "${_installed_formulae}" || continue
        else
            _short_name=${_item##*/}
            if ! grep -Fxq "${_item}" <<< "${_installed_casks}" && ! grep -Fxq "${_short_name}" <<< "${_installed_casks}"; then
                continue
            fi
        fi

        _tap=${_item%/*}
        print_warning "Unmanaged Homebrew ${_section} ${_item} remains untrusted and may be skipped; run brew trust --${_section} ${_item}, or uninstall it and run brew untap ${_tap}."
        ((_unmanaged_count++))
    done <<< "${_untrusted_output}"

    [[ "${_unmanaged_count}" -eq 0 ]]
}

# Install core packages with Homebrew if missing
install_core_packages() {
    print_message "Checking and installing core packages as needed..."

    # Turso has a cross-tap sqld dependency. Trust only these two formulae.
    ensure_brew_item_trusted formula "libsql/sqld/sqld" "libsql/sqld" || true
    ensure_brew_item_trusted formula "tursodatabase/tap/turso" "tursodatabase/tap" || true

    # Define an array of required packages
    # NOTE: starship installed via Homebrew for consistent macOS binary management
    # NOTE: tailscale installed as a cask (GUI app) separately by setup_tailscale()
    local packages=("git" "curl" "jq" "fish" "tmux" "1password-cli" "gh" "chezmoi" "starship" "mise" "act" "terminal-notifier" "hammerspoon" "switchaudio-osx" "opentofu" "uv" "go" "cloudflared" "tursodatabase/tap/turso" "fswatch" "shellcheck" "gitleaks" "lefthook" "poppler" "ffmpeg" "kubernetes-cli")
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
    # For tap packages (e.g., dopplerhq/cli/doppler), also check the short name (doppler)
    for package in "${packages[@]}"; do
        local short_name="${package##*/}"
        if [[ "${all_installed}" =~ \ ${package}\  ]] || [[ "${all_installed}" =~ \ ${short_name}\  ]]; then
            print_debug "${package} is already installed."
        else
            to_install+=("${package}")
        fi
    done

    # Install packages individually so one failure doesn't block everything
    if [[ "${#to_install[@]}" -gt 0 ]]; then
        print_message "Installing ${#to_install[@]} missing packages..."
        local failed=()
        for package in "${to_install[@]}"; do
            if ! brew install "${package}" 2>&1; then
                print_warning "Failed to install ${package}"
                failed+=("${package}")
            fi
        done
        if [[ "${#failed[@]}" -gt 0 ]]; then
            print_warning "Failed packages: ${failed[*]}"
        else
            print_success "All core packages installed."
        fi
    else
        print_success "All core packages are already installed."
    fi
}

# Install SessionWatcher while trusting only its managed cask.
install_sessionwatcher() {
    if ! ensure_brew_item_trusted cask "soren-starck/tap/sessionwatcher" "soren-starck/tap"; then
        print_warning "SessionWatcher cask is not trusted; skipping SessionWatcher."
        return
    fi

    if brew list --cask sessionwatcher &>/dev/null 2>&1; then
        print_debug "SessionWatcher is already installed."
        return
    fi

    print_message "Installing SessionWatcher..."
    if brew install --cask soren-starck/tap/sessionwatcher; then
        print_success "SessionWatcher installed."
    else
        print_warning "Failed to install SessionWatcher."
    fi
}

# Ensure Tailscale is installed as the cask (GUI app), not the formula (CLI-only).
# The formula's daemon management is broken on macOS — brew services can't handle
# privileged network daemons properly. The cask installs the same app as a direct
# download from tailscale.com and manages the daemon natively.
setup_tailscale() {
    # If the formula is installed (not the cask), replace it with the cask
    if brew list --formula tailscale &>/dev/null 2>&1; then
        print_message "Replacing Tailscale formula with cask (GUI app)..."
        brew services stop tailscale 2>/dev/null || true
        brew uninstall tailscale 2>/dev/null || true
    fi

    # Install the cask if not already present
    if ! brew list --cask tailscale &>/dev/null 2>&1; then
        print_message "Installing Tailscale (cask)..."
        brew install --cask tailscale
        print_success "Tailscale cask installed."
    else
        print_debug "Tailscale cask is already installed."
    fi

    # Launch the app if not running (starts the daemon automatically)
    # Check if the Tailscale process is already running, not tailscale status
    # (which fails if not logged in even when the daemon is running)
    if pgrep -q "Tailscale" 2>/dev/null; then
        print_debug "Tailscale app is already running."
    else
        print_message "Starting Tailscale..."
        open -a Tailscale 2>/dev/null || true
        sleep 3
        print_success "Tailscale started."
    fi
}

# Install the appropriate secrets manager based on machine type
install_secrets_manager() {
    if [[ "${WORK_MACHINE:-}" == "1" ]]; then
        if ! ensure_brew_item_trusted formula "infisical/get-cli/infisical" "infisical/get-cli"; then
            print_warning "Infisical formula is not trusted; skipping Infisical CLI."
            return
        fi
        if command -v infisical &>/dev/null; then
            print_debug "Infisical CLI already installed."
            return
        fi
        print_message "Installing Infisical CLI..."
        if brew install infisical/get-cli/infisical; then
            print_success "Infisical CLI installed."
        else
            print_error "Failed to install Infisical CLI."
        fi
    else
        if ! ensure_brew_item_trusted formula "dopplerhq/cli/doppler" "dopplerhq/cli"; then
            print_warning "Doppler formula is not trusted; skipping Doppler CLI."
            return
        fi
        if command -v doppler &>/dev/null; then
            print_debug "Doppler CLI already installed."
            return
        fi
        print_message "Installing Doppler CLI..."
        if brew install dopplerhq/cli/doppler; then
            print_success "Doppler CLI installed."
        else
            print_error "Failed to install Doppler CLI."
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

# Enable SSH (Remote Login) with key-only auth, no password
# Block public file upload services on work machines to prevent accidental data leaks.
# AI coding agents may upload screenshots/code to these services.
# Only applies when WORK_MACHINE=1 is set in ~/.env.local.
block_public_upload_services() {
    if [[ "${WORK_MACHINE:-}" != "1" ]]; then
        print_debug "Not a work machine, skipping upload service blocks."
        return
    fi

    if ! can_sudo; then
        print_warning "No sudo access — cannot block upload services."
        return
    fi

    local hosts_file="/etc/hosts"
    local marker="# WORK_MACHINE: blocked public upload services"

    # Check if already configured
    if grep -q "${marker}" "${hosts_file}" 2>/dev/null; then
        print_debug "Public upload services already blocked."
        return
    fi

    print_message "Blocking public file upload services (work machine policy)..."

    sudo tee -a "${hosts_file}" > /dev/null << EOF

${marker}
# Image/file upload services (prevent AI agents from leaking data)
127.0.0.1 0x0.st
::1 0x0.st
127.0.0.1 catbox.moe
::1 catbox.moe
127.0.0.1 files.catbox.moe
::1 files.catbox.moe
127.0.0.1 litterbox.catbox.moe
::1 litterbox.catbox.moe
127.0.0.1 pixhost.to
::1 pixhost.to
127.0.0.1 imagebin.ca
::1 imagebin.ca
127.0.0.1 beeimg.com
::1 beeimg.com
# Paste services
127.0.0.1 pastebin.com
::1 pastebin.com
127.0.0.1 hastebin.com
::1 hastebin.com
127.0.0.1 paste.rs
::1 paste.rs
127.0.0.1 dpaste.org
::1 dpaste.org
127.0.0.1 ix.io
::1 ix.io
127.0.0.1 sprunge.us
::1 sprunge.us
127.0.0.1 clbin.com
::1 clbin.com
127.0.0.1 termbin.com
::1 termbin.com
# Temporary file sharing
127.0.0.1 transfer.sh
::1 transfer.sh
127.0.0.1 file.io
::1 file.io
127.0.0.1 tmpfiles.org
::1 tmpfiles.org
127.0.0.1 uguu.se
::1 uguu.se
127.0.0.1 pomf.cat
::1 pomf.cat
EOF

    # Flush DNS cache on macOS
    sudo dscacheutil -flushcache 2>/dev/null
    sudo killall -HUP mDNSResponder 2>/dev/null

    print_success "Blocked ${marker##*: } on this work machine."
}

enable_ssh() {
    if ! can_sudo; then
        print_warning "No sudo access — cannot enable SSH."
        return
    fi

    # Enable Remote Login (SSH)
    # Check if sshd is already running
    if sudo launchctl list com.openssh.sshd &>/dev/null; then
        print_debug "SSH (Remote Login) is already enabled."
    else
        print_message "Enabling SSH (Remote Login)..."
        # Try systemsetup first (works if terminal has Full Disk Access)
        if sudo systemsetup -setremotelogin on 2>/dev/null; then
            print_success "SSH enabled via systemsetup."
        # Fallback: load the SSH launch daemon directly (avoids FDA requirement)
        elif sudo launchctl load -w /System/Library/LaunchDaemons/ssh.plist 2>/dev/null; then
            print_success "SSH enabled via launchctl."
        else
            print_warning "Could not enable SSH. Enable manually: System Settings → General → Sharing → Remote Login"
        fi
    fi

    # Configure key-only auth (disable password auth for SSH)
    local sshd_config="/etc/ssh/sshd_config"
    local needs_restart=false

    # Disable password authentication
    if ! grep -q "^PasswordAuthentication no" "${sshd_config}" 2>/dev/null; then
        print_message "Disabling SSH password authentication (key-only)..."
        # Remove any existing PasswordAuthentication lines and add our own
        sudo sed -i '' '/^#*PasswordAuthentication/d' "${sshd_config}"
        echo "PasswordAuthentication no" | sudo tee -a "${sshd_config}" > /dev/null
        needs_restart=true
    fi

    # Disable keyboard-interactive auth
    if ! grep -q "^KbdInteractiveAuthentication no" "${sshd_config}" 2>/dev/null; then
        sudo sed -i '' '/^#*KbdInteractiveAuthentication/d' "${sshd_config}"
        echo "KbdInteractiveAuthentication no" | sudo tee -a "${sshd_config}" > /dev/null
        needs_restart=true
    fi

    # Disable challenge-response auth
    if ! grep -q "^ChallengeResponseAuthentication no" "${sshd_config}" 2>/dev/null; then
        sudo sed -i '' '/^#*ChallengeResponseAuthentication/d' "${sshd_config}"
        echo "ChallengeResponseAuthentication no" | sudo tee -a "${sshd_config}" > /dev/null
        needs_restart=true
    fi

    if [[ "${needs_restart}" == true ]]; then
        # Restart SSH to apply changes
        sudo launchctl stop com.openssh.sshd 2>/dev/null || true
        sudo launchctl start com.openssh.sshd 2>/dev/null || true
        print_success "SSH configured for key-only authentication."
    else
        print_debug "SSH already configured for key-only auth."
    fi
}

# Install a Nerd Font for terminal icons (Starship, tmux, etc.)
install_nerd_font() {
    if brew list --cask font-jetbrains-mono-nerd-font &>/dev/null 2>&1; then
        print_debug "JetBrains Mono Nerd Font is already installed."
        return
    fi

    print_message "Installing JetBrains Mono Nerd Font..."
    if ! brew install --cask font-jetbrains-mono-nerd-font; then
        print_warning "Failed to install Nerd Font."
        return
    fi
    print_success "JetBrains Mono Nerd Font installed."

    # Set as default font in Terminal.app
    local font_name="JetBrainsMonoNFM-Regular"
    local font_size=14
    defaults write com.apple.Terminal "Default Window Settings" -string "Basic"
    defaults write com.apple.Terminal "Startup Window Settings" -string "Basic"
    /usr/libexec/PlistBuddy -c "Set :Window\ Settings:Basic:Font $(python3 -c "
import plistlib, sys
font_data = plistlib.dumps({'NSFontNameAttribute': '${font_name}', 'NSFontSizeAttribute': ${font_size}}, fmt=plistlib.FMT_BINARY)
sys.stdout.buffer.write(font_data)
" | base64)" ~/Library/Preferences/com.apple.Terminal.plist 2>/dev/null || true
    print_debug "Terminal.app font configuration attempted."

    # Set as default font in iTerm2 (if installed)
    if [[ -d "/Applications/iTerm.app" ]]; then
        # Set font for the Default profile
        defaults write com.googlecode.iterm2 "New Bookmarks" -array-add 2>/dev/null || true
        /usr/libexec/PlistBuddy -c "Set ':New Bookmarks:0:Normal Font' 'JetBrainsMonoNFM-Regular 14'" \
            ~/Library/Preferences/com.googlecode.iterm2.plist 2>/dev/null || \
        /usr/libexec/PlistBuddy -c "Add ':New Bookmarks:0:Normal Font' string 'JetBrainsMonoNFM-Regular 14'" \
            ~/Library/Preferences/com.googlecode.iterm2.plist 2>/dev/null || true
        # Also set the non-ASCII font to match
        /usr/libexec/PlistBuddy -c "Set ':New Bookmarks:0:Non Ascii Font' 'JetBrainsMonoNFM-Regular 14'" \
            ~/Library/Preferences/com.googlecode.iterm2.plist 2>/dev/null || \
        /usr/libexec/PlistBuddy -c "Add ':New Bookmarks:0:Non Ascii Font' string 'JetBrainsMonoNFM-Regular 14'" \
            ~/Library/Preferences/com.googlecode.iterm2.plist 2>/dev/null || true
        print_debug "iTerm2 font set to JetBrains Mono Nerd Font."
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
            return 1
        fi
    else
        print_warning "No SSH key found. Generating a new SSH key..."
        ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
        print_success "SSH key generated."
        print_message "Please add the following SSH key to GitHub:"
        cat ~/.ssh/id_rsa.pub
        print_message "Opening GitHub SSH keys page..."
        open "https://github.com/settings/keys"
        return 1
    fi
}

# Install Xcode CLT headlessly via softwareupdate (no GUI dialog)
# xcode-select --install opens a GUI prompt that hangs on headless machines.
# Instead, we create the /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
# sentinel file and use softwareupdate to find and install the CLT package directly.
install_xcode_cli_tools() {
    if xcode-select -p &>/dev/null; then
        # CLT is installed — check if it needs updating
        local updates
        updates=$(softwareupdate --list 2>&1)
        if echo "${updates}" | grep -qi "Command Line Tools"; then
            print_message "Xcode Command Line Tools update available. Installing..."
            sudo rm -rf /Library/Developer/CommandLineTools 2>/dev/null
            _install_clt_via_softwareupdate
            print_success "Xcode Command Line Tools updated."
        else
            print_debug "Xcode Command Line Tools are already installed and up to date."
        fi
        return 0
    fi

    print_message "Installing Xcode Command Line Tools..."
    _install_clt_via_softwareupdate
    print_success "Xcode Command Line Tools installed."
}

# Helper: install CLT non-interactively using softwareupdate
_install_clt_via_softwareupdate() {
    # This sentinel file makes softwareupdate list the CLT package
    local placeholder="/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress"
    sudo touch "${placeholder}"

    # Find the latest Command Line Tools package label
    local clt_label
    clt_label=$(softwareupdate --list 2>&1 \
        | grep -o 'Label: Command Line Tools.*' \
        | sed 's/^Label: //' \
        | sort -V \
        | tail -n1 || true)

    if [[ -z "${clt_label}" ]]; then
        # Fallback: try the '*' wildcard format (older macOS)
        clt_label=$(softwareupdate --list 2>&1 \
            | grep '\* .*Command Line Tools' \
            | sed 's/^[[:space:]]*\* //' \
            | sort -V \
            | tail -n1 || true)
    fi

    if [[ -z "${clt_label}" ]]; then
        sudo rm -f "${placeholder}"
        print_error "Could not find Command Line Tools package in softwareupdate."
        return 1
    fi

    print_message "Installing '${clt_label}' via softwareupdate..."
    sudo softwareupdate --install "${clt_label}" --verbose

    sudo rm -f "${placeholder}"
}

# Install Homebrew if not installed
install_homebrew() {
    if ! command -v brew &> /dev/null && [[ ! -x "/opt/homebrew/bin/brew" ]]; then
        print_message "Installing Homebrew..."
        # Cache sudo credentials before running installer (Homebrew needs sudo)
        # shellcheck disable=SC2024 # sudo must read from the terminal when setup is run via curl|bash.
        sudo -v < /dev/tty 2>/dev/null || true
        # Download the install script first, then run it with stdin from /dev/tty
        # so sudo can prompt if needed. NONINTERACTIVE prevents Homebrew's own
        # "press RETURN" prompt but still allows sudo to work.
        local install_script
        install_script=$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh || true)
        NONINTERACTIVE=1 /bin/bash -c "${install_script}" < /dev/tty
        if [[ ! -x "/opt/homebrew/bin/brew" ]]; then
            print_error "Homebrew installation failed."
            return 1
        fi
        print_success "Homebrew installed."
    else
        print_debug "Homebrew is already installed."
    fi

    # Always source brew shellenv to ensure PATH is set for the rest of the script
    local brew_shellenv
    brew_shellenv=$(/opt/homebrew/bin/brew shellenv || true)
    eval "${brew_shellenv}"
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
    local chez_src="${HOME}/.local/share/chezmoi"
    if [[ -d "${chez_src}/.git" ]]; then
        print_message "Updating chezmoi dotfiles repository..."
        # Reset any dirty state (merge conflicts, uncommitted changes) before pulling.
        # The remote repo is the source of truth — local edits in the chezmoi source dir
        # should never exist and are safe to discard.
        git -C "${chez_src}" reset --hard HEAD > /dev/null 2>&1
        git -C "${chez_src}" merge --abort > /dev/null 2>&1
        git -C "${chez_src}" clean -fd > /dev/null 2>&1
        if chezmoi update --force > /dev/null; then
            print_success "chezmoi dotfiles repository updated."
        else
            print_warning "Failed to update chezmoi dotfiles repository. Continuing anyway."
        fi
    elif [[ -d "${chez_src}" ]]; then
        # Directory exists but no .git - broken state, clean up
        print_warning "Broken chezmoi directory detected, reinitializing..."
        rm -rf "${chez_src}"
        initialize_chezmoi
    else
        print_debug "chezmoi not initialized yet, skipping update."
    fi
}

# Set Fish as the default shell if it isn't already
set_fish_as_default_shell() {
    # Guard: don't set fish as default if it isn't installed yet
    if [[ ! -x "/opt/homebrew/bin/fish" ]]; then
        print_warning "Fish shell not found at /opt/homebrew/bin/fish — skipping default shell change."
        print_debug "Install fish first with: brew install fish"
        return
    fi

    # Check the actual configured login shell from the system (not $SHELL which
    # reflects the current session, not the configured default)
    local current_shell
    current_shell=$(dscl . -read /Users/"$(whoami || true)" UserShell 2>/dev/null | awk '{print $2}' || true)
    if [[ "${current_shell}" == "/opt/homebrew/bin/fish" ]]; then
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
    chsh -s /opt/homebrew/bin/fish < /dev/tty
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
            return 1
        fi
        print_success "GitHub's SSH key added."
    else
        print_debug "GitHub's SSH key already exists in known_hosts."
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

# Install/update Codex CLI using Homebrew's native, zero-Node-dependency cask.
install_codex_cli() {
    local bun_packages=""
    local brew_prefix=""
    local brew_codex=""
    local resolved_codex=""
    local version_output=""
    local safe_path=""
    local installed_casks=""

    print_message "Installing/updating Codex CLI..."

    if ! command -v brew &> /dev/null; then
        print_error "Homebrew not found. Cannot install the native Codex CLI."
        return 1
    fi

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

    installed_casks=$(brew list --cask -1 2>/dev/null || true)
    if grep -Fxq codex <<< "${installed_casks}"; then
        if ! brew upgrade --cask codex; then
            print_error "Failed to upgrade the native Codex CLI cask."
            return 1
        fi
    elif ! brew install --cask codex; then
        print_error "Failed to install the native Codex CLI cask."
        return 1
    fi

    hash -r 2>/dev/null || true
    brew_prefix=$(brew --prefix 2>/dev/null || true)
    brew_codex="${brew_prefix}/bin/codex"
    resolved_codex=$(command -v codex 2>/dev/null || true)
    if [[ -z "${brew_prefix}" || ! -x "${brew_codex}" ]]; then
        print_error "Homebrew completed, but its Codex binary is missing."
        return 1
    fi
    if [[ -z "${resolved_codex}" || ! "${resolved_codex}" -ef "${brew_codex}" ]]; then
        print_error "Codex is shadowed by ${resolved_codex:-<missing>}; expected ${brew_codex}."
        return 1
    fi

    safe_path="/nonexistent"
    if ! version_output=$(env -u NODE_PATH -u NODE_OPTIONS HOME="${HOME}" PATH="${safe_path}" "${brew_codex}" --version 2>/dev/null) || [[ -z "${version_output}" ]]; then
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


# Verify the installed rtk is Rust Token Killer, not the unrelated Rust Type Kit.
rtk_cli_ready() {
    command -v rtk &> /dev/null && rtk gain > /dev/null 2>&1
}

# Install RTK (Rust Token Killer) for token-optimized agent command output.
install_rtk_cli() {
    if [[ "${BAN_RTK:-}" == "1" ]]; then
        print_debug "BAN_RTK=1, skipping RTK setup."
        return
    fi

    export PATH="${HOME}/.local/bin:${PATH}"

    local had_rtk=0
    if rtk_cli_ready; then
        had_rtk=1
        print_message "Updating RTK CLI..."
    elif command -v rtk &> /dev/null; then
        print_warning "An rtk command exists, but it does not look like Rust Token Killer. Installing the rtk-ai binary to ~/.local/bin."
    else
        print_message "Installing RTK CLI..."
    fi

    local install_script
    if ! install_script=$(curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh 2>&1); then
        if [[ "${had_rtk}" == "1" ]]; then
            print_warning "Failed to update RTK CLI; existing install remains available."
        else
            print_warning "Failed to download RTK installer."
        fi
        print_debug "${install_script}"
        return
    fi

    local install_output
    if install_output=$(RTK_INSTALL_DIR="${HOME}/.local/bin" sh -c "${install_script}" 2>&1); then
        hash -r 2>/dev/null || true
        if rtk_cli_ready; then
            print_success "RTK CLI installed/updated."
        else
            print_warning "RTK installer completed, but 'rtk gain' did not verify the expected binary."
            print_debug "${install_output}"
        fi
    else
        if [[ "${had_rtk}" == "1" ]]; then
            print_warning "Failed to update RTK CLI; existing install remains available."
        else
            print_warning "Failed to install RTK CLI."
        fi
        print_debug "${install_output}"
    fi
}

# Configure RTK integrations for installed AI agents. Non-fatal by design.
setup_rtk_integrations() {
    if [[ "${BAN_RTK:-}" == "1" ]]; then
        print_debug "BAN_RTK=1, skipping RTK integrations."
        return
    fi

    export PATH="${HOME}/.local/bin:${PATH}"

    if ! rtk_cli_ready; then
        print_warning "RTK CLI is not available; skipping RTK integrations."
        return
    fi

    # Automated setup should not prompt for telemetry consent. Users can opt in later with `rtk telemetry enable`.
    rtk telemetry disable > /dev/null 2>&1 || true

    local init_output

    if command -v gemini &> /dev/null; then
        print_message "Configuring RTK for Gemini CLI..."
        if init_output=$(rtk init -g --gemini --auto-patch < /dev/null 2>&1); then
            print_success "RTK configured for Gemini CLI."
        else
            print_warning "Failed to configure RTK for Gemini CLI."
            print_debug "${init_output}"
        fi
    else
        print_debug "Gemini CLI not installed; skipping RTK Gemini integration."
    fi

    if command -v codex &> /dev/null; then
        print_message "Configuring RTK for Codex CLI..."
        if init_output=$(rtk init -g --codex < /dev/null 2>&1); then
            print_success "RTK configured for Codex CLI."
        else
            print_warning "Failed to configure RTK for Codex CLI."
            print_debug "${init_output}"
        fi
    else
        print_debug "Codex CLI not installed; skipping RTK Codex integration."
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

# Force Pi defaults: Synthetic provider with Kimi K3 as the default model.
# Chezmoi owns ~/.pi/agent/settings.json long-term; this seeds the desired
# state on fresh machines and repairs drift where dotfiles are not applied.
configure_pi_defaults() {
    local _agent_dir="${PI_CODING_AGENT_DIR:-${HOME}/.pi/agent}"
    local _settings_file="${_agent_dir}/settings.json"
    local _tmp=""

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

    if jq '
        .defaultProvider = "synthetic"
        | .defaultModel = "hf:moonshotai/Kimi-K3"
        | .defaultThinkingLevel = "high"
    ' "${_settings_file}" > "${_tmp}"; then
        if cat "${_tmp}" > "${_settings_file}"; then
            rm -f "${_tmp}"
            print_success "Pi default model set to Kimi K3 (Synthetic) with high thinking."
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


# shellcheck disable=SC2312
# Managed marker used to distinguish setup-owned Paseo service artifacts from user-managed ones.
PASEO_MANAGED_MARKER="Managed by scowalt machine setup: headless-paseo-daemon"
PASEO_PACKAGE="@getpaseo/cli"
PASEO_LAUNCHD_LABEL="com.scowalt.paseo-daemon"
PASEO_VALIDATED_CMD=""
PASEO_VALIDATED_NODE=""
PASEO_SERVICE_PATH=""
PASEO_MANAGED_SERVICE_TOUCHED=0
PASEO_PACKAGE_VERSION="unknown"
PASEO_PACKAGE_CHANGED=0
PASEO_DAEMON_WRAPPER_CHANGED=0
PASEO_LAUNCHD_SERVICE_CHANGED=0
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

    if [[ "${HEADLESS:-}" != "1" ]]; then
        return 0
    fi

    PASEO_PACKAGE_CHANGED=0
    print_message "Installing/updating Paseo CLI for headless daemon setup..."

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
        print_error "Node.js >=20.6 is required before installing ${PASEO_PACKAGE}."
        return 1
    fi

    if ! bun install -g "${PASEO_PACKAGE}"; then
        print_error "Failed to install ${PASEO_PACKAGE}."
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
    local _service_path=""

    if [[ -z "${PASEO_VALIDATED_CMD}" ]]; then
        print_error "Cannot write Paseo daemon wrapper before validating the paseo command."
        return 1
    fi

    PASEO_DAEMON_WRAPPER_CHANGED=0
    mkdir -p "${HOME}/.local/bin" "${_log_dir}"
    chmod 700 "${HOME}/.local/bin" "${_log_dir}"

    _service_path=$(paseo_effective_service_path)
    _home_q=$(paseo_shell_quote "${HOME}")
    _path_q=$(paseo_shell_quote "${_service_path}")
    _cmd_q=$(paseo_shell_quote "${PASEO_VALIDATED_CMD}")
    _node_q=$(paseo_shell_quote "${PASEO_VALIDATED_NODE}")
    _tmp=$(mktemp)
    if ! cat > "${_tmp}" << EOF
#!/bin/bash
# ${PASEO_MANAGED_MARKER}
set -euo pipefail
export HOME=${_home_q}
export PATH=${_path_q}
[[ -x ${_node_q} ]] || exit 127
[[ -x ${_cmd_q} ]] || exit 127
exec ${_cmd_q} daemon start --foreground
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

paseo_managed_service_is_loaded() {
    sudo launchctl print "system/${PASEO_LAUNCHD_LABEL}" >/dev/null 2>&1
}

stop_existing_paseo_daemon() {
    local _service_path=""
    local _state=""

    if [[ -z "${PASEO_VALIDATED_CMD}" ]]; then
        return 0
    fi

    if paseo_managed_service_is_loaded; then
        print_debug "Existing Paseo daemon is already managed by ${PASEO_LAUNCHD_LABEL}; leaving it running until change detection completes."
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
        if ! _listeners=$(printf '%s
' "${_listener_source}" | awk -v pids="${_pid_list}" '
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
                        print $4
                        next
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
        if ! _listeners=$(printf '%s
' "${_listener_source}" | awk '$1 != "COMMAND" && $9 != "" {print $9}'); then
            print_error "Failed to parse Paseo listeners from lsof output."
            return 1
        fi
    else
        print_error "No listener-audit tool found (ss/lsof); cannot verify Paseo is loopback-only."
        return 1
    fi

    if [[ -z "${_listeners}" ]]; then
        print_error "No TCP listeners could be associated with the managed Paseo service process tree; refusing to let another daemon satisfy health checks."
        return 1
    fi

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

paseo_macos_preflight() {
    if [[ "$(uname -s 2>/dev/null || true)" != "Darwin" ]]; then
        print_error "macOS Paseo LaunchDaemon setup requires Darwin."
        return 1
    fi

    if [[ "${PASEO_MACOS_HEADLESS_CANARY:-}" != "1" ]]; then
        # Not an error: HEADLESS=1 runs without the canary skip the daemon
        # entirely (see setup_headless_paseo_daemon). This only fails if a
        # canary run reaches the preflight without the flag set.
        print_warning "macOS Paseo headless daemon support is pending no-login validation. Set PASEO_MACOS_HEADLESS_CANARY=1 only for an approved canary run."
        return 1
    fi

    if [[ -z "${HOME}" || ! -d "${HOME}" || -z "$(whoami || true)" ]]; then
        print_error "Cannot resolve target user/home for macOS Paseo daemon setup."
        return 1
    fi

    if ! can_sudo; then
        print_error "sudo/admin access is required to install the Paseo LaunchDaemon."
        return 1
    fi

    if ! command -v launchctl &> /dev/null; then
        print_error "launchctl is required for macOS Paseo LaunchDaemon setup."
        return 1
    fi
}

paseo_launchd_plist_path() {
    printf '%s\n' "/Library/LaunchDaemons/${PASEO_LAUNCHD_LABEL}.plist"
}

paseo_existing_managed_service_check() {
    local _plist=""
    local _wrapper="${HOME}/.local/bin/paseo-daemon-start"

    _plist=$(paseo_launchd_plist_path)

    if [[ -f "${_plist}" ]] && ! sudo grep -qF "${PASEO_MANAGED_MARKER}" "${_plist}"; then
        print_error "Existing unmanaged ${_plist} found. Remove or rename it before rerunning the macOS Paseo canary."
        return 1
    fi

    if [[ -f "${_wrapper}" ]] && ! grep -qF "${PASEO_MANAGED_MARKER}" "${_wrapper}"; then
        print_error "Existing unmanaged ${_wrapper} found. Remove or rename it before rerunning the macOS Paseo canary."
        return 1
    fi
}

paseo_macos_service_pid() {
    sudo launchctl print "system/${PASEO_LAUNCHD_LABEL}" 2>/dev/null | awk -F'= ' '/pid =/ {print $2; exit}' | tr -cd '[:digit:]' || true
}

cleanup_paseo_managed_service() {
    local _platform="$1"

    if [[ "${PASEO_MANAGED_SERVICE_TOUCHED}" != "1" ]]; then
        return 0
    fi

    case "${_platform}" in
        Darwin)
            sudo launchctl bootout "system/${PASEO_LAUNCHD_LABEL}" >/dev/null 2>&1 || true
            sudo launchctl disable "system/${PASEO_LAUNCHD_LABEL}" >/dev/null 2>&1 || true
            ;;
        *) ;;
    esac
    print_debug "Stopped managed Paseo service after failed verification; managed files and logs remain for inspection."
}

install_paseo_launchdaemon() {
    local _plist=""
    local _tmp=""
    local _user=""
    local _wrapper="${HOME}/.local/bin/paseo-daemon-start"
    local _service_path=""

    _plist=$(paseo_launchd_plist_path)
    _service_path=$(paseo_effective_service_path)
    PASEO_LAUNCHD_SERVICE_CHANGED=0
    _user=$(whoami || true)
    if [[ -f "${_plist}" ]] && ! sudo grep -qF "${PASEO_MANAGED_MARKER}" "${_plist}"; then
        print_error "Existing unmanaged ${_plist} found. Remove or rename it before rerunning the macOS Paseo canary."
        return 1
    fi

    _tmp=$(mktemp)
    if ! cat > "${_tmp}" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!-- ${PASEO_MANAGED_MARKER} -->
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${PASEO_LAUNCHD_LABEL}</string>
    <key>UserName</key>
    <string>${_user}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${_wrapper}</string>
    </array>
    <key>WorkingDirectory</key>
    <string>${HOME}</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>HOME</key>
        <string>${HOME}</string>
        <key>PATH</key>
        <string>${_service_path}</string>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
EOF
    then
        rm -f "${_tmp}"
        print_error "Failed to write Paseo LaunchDaemon plist."
        return 1
    fi

    if [[ -f "${_plist}" ]] && sudo cmp -s "${_tmp}" "${_plist}"; then
        rm -f "${_tmp}"
        if ! sudo chown root:wheel "${_plist}" || ! sudo chmod 0644 "${_plist}"; then
            print_error "Failed to secure Paseo LaunchDaemon plist."
            return 1
        fi
        print_debug "Paseo LaunchDaemon plist is unchanged."
    else
        if ! sudo install -o root -g wheel -m 0644 "${_tmp}" "${_plist}"; then
            rm -f "${_tmp}"
            print_error "Failed to install Paseo LaunchDaemon plist."
            return 1
        fi
        rm -f "${_tmp}"
        PASEO_LAUNCHD_SERVICE_CHANGED=1
    fi

    if ! sudo launchctl enable "system/${PASEO_LAUNCHD_LABEL}"; then
        print_error "Failed to enable ${PASEO_LAUNCHD_LABEL}."
        return 1
    fi

    if ! paseo_managed_service_is_loaded; then
        PASEO_MANAGED_SERVICE_TOUCHED=1
        if ! sudo launchctl bootstrap system "${_plist}"; then
            print_error "Failed to bootstrap ${PASEO_LAUNCHD_LABEL}."
            return 1
        fi
    elif [[ "${PASEO_LAUNCHD_SERVICE_CHANGED}" == "1" ]]; then
        PASEO_MANAGED_SERVICE_TOUCHED=1
        if ! sudo launchctl bootout "system/${PASEO_LAUNCHD_LABEL}"; then
            if paseo_managed_service_is_loaded; then
                print_error "Failed to unload ${PASEO_LAUNCHD_LABEL} before applying its changed plist."
                return 1
            fi
        fi
        if ! sudo launchctl bootstrap system "${_plist}"; then
            print_error "Failed to bootstrap changed ${PASEO_LAUNCHD_LABEL}."
            return 1
        fi
    elif [[ "${PASEO_PACKAGE_CHANGED}" == "1" || "${PASEO_DAEMON_WRAPPER_CHANGED}" == "1" ]]; then
        PASEO_MANAGED_SERVICE_TOUCHED=1
        if ! sudo launchctl kickstart -k "system/${PASEO_LAUNCHD_LABEL}"; then
            print_error "Failed to restart ${PASEO_LAUNCHD_LABEL} after a Paseo package or wrapper change."
            return 1
        fi
    else
        print_debug "Paseo package, wrapper, and LaunchDaemon plist are unchanged; leaving the loaded daemon running."
    fi
    if ! sudo launchctl print "system/${PASEO_LAUNCHD_LABEL}" >/dev/null 2>&1; then
        print_error "${PASEO_LAUNCHD_LABEL} is not loaded after setup."
        return 1
    fi

    print_success "Paseo LaunchDaemon loaded for canary validation."
}

setup_headless_paseo_daemon() {
    local _platform=""
    local _service_pid=""

    if [[ "${HEADLESS:-}" != "1" ]]; then
        return 0
    fi

    _platform=$(uname -s 2>/dev/null || true)
    if [[ "${_platform}" != "Darwin" ]]; then
        print_error "HEADLESS=1 Paseo daemon setup is unsupported on ${_platform:-this platform}."
        return 1
    fi

    if [[ "${PASEO_MACOS_HEADLESS_CANARY:-}" != "1" ]]; then
        print_warning "Skipping headless Paseo daemon setup: macOS support is pending no-login validation. Set PASEO_MACOS_HEADLESS_CANARY=1 for an approved canary run."
        return 0
    fi

    paseo_macos_preflight || return 1
    paseo_existing_managed_service_check || return 1

    install_paseo_cli || return 1
    write_paseo_daemon_wrapper || return 1
    stop_existing_paseo_daemon || return 1

    if ! install_paseo_launchdaemon; then
        cleanup_paseo_managed_service "${_platform}"
        return 1
    fi
    _service_pid=$(paseo_macos_service_pid || true)

    if ! paseo_service_owner_check "${_service_pid}" || ! wait_for_paseo_health || ! paseo_listener_audit "${_service_pid}"; then
        cleanup_paseo_managed_service "${_platform}"
        return 1
    fi

    print_success "Headless Paseo daemon is service-managed and locally reachable. Use Paseo's normal pairing flow later if needed."
}

# Update Pi settings for the tintinweb subagents extension
update_pi_subagents_settings() {
    local _mode="${1:-install}"
    local _settings_dir="${PI_CODING_AGENT_DIR:-${HOME}/.pi/agent}"
    local _settings_file="${_settings_dir}/settings.json"
    local _tmp=""

    if ! command -v jq &> /dev/null; then
        print_warning "jq not found. Cannot update Pi subagents settings."
        return 1
    fi

    mkdir -p "${_settings_dir}"

    if [[ ! -f "${_settings_file}" ]]; then
        printf '{}\n' > "${_settings_file}"
    fi

    _tmp=$(mktemp)
    if [[ "${_mode}" == "remove" ]]; then
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
        else
            rm -f "${_tmp}"
            print_warning "Failed to update Pi settings at ${_settings_file}."
            return 1
        fi
    else
        if jq '
            def package_source:
                if type == "string" then .
                elif type == "object" then (.source // "")
                else ""
                end;
            def packages_array:
                if (.packages | type) == "array" then .packages else [] end;
            .packages = (packages_array | map(select(package_source != "npm:pi-subagents")))
        ' "${_settings_file}" > "${_tmp}"; then
            mv "${_tmp}" "${_settings_file}"
        else
            rm -f "${_tmp}"
            print_warning "Failed to update Pi settings at ${_settings_file}."
            return 1
        fi
    fi
}

# Install/update tintinweb Pi subagents extension
setup_pi_subagents() {
    local _package="npm:@tintinweb/pi-subagents"
    local _output=""

    if [[ "${BAN_PI_SUBAGENTS:-}" == "1" ]]; then
        if update_pi_subagents_settings remove; then
            print_success "Pi subagents extension disabled in Pi settings."
        fi
        return 0
    fi

    if ! command -v npm &> /dev/null; then
        print_warning "npm not found. Cannot install Pi subagents."
        print_debug "Install Node.js/npm, then run: pi install npm:@tintinweb/pi-subagents"
        return 0
    fi

    if ! command -v pi &> /dev/null; then
        print_warning "Pi coding agent not found. Cannot install Pi subagents."
        return 0
    fi

    if ! update_pi_subagents_settings install; then
        return 0
    fi

    print_message "Installing/updating tintinweb Pi subagents..."
    if _output=$(pi install "${_package}" 2>&1); then
        if _output=$(pi list 2>&1) && grep -q "npm:@tintinweb/pi-subagents" <<< "${_output}" && ! grep -q "npm:pi-subagents" <<< "${_output}"; then
            print_success "tintinweb Pi subagents installed/updated."
        else
            print_warning "Pi subagents install completed, but package validation was inconclusive: ${_output}"
        fi
    else
        print_warning "Failed to install tintinweb Pi subagents: ${_output}"
    fi
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
}


# Matt Pocock skills to install for Pi.
matt_pocock_pi_skills() {
    printf '%s\n' \
        setup-matt-pocock-skills \
        diagnose \
        tdd \
        improve-codebase-architecture \
        zoom-out \
        grill-with-docs
}

matt_pocock_pi_skills_disabled() {
    [[ "${WORK_MACHINE:-}" == "1" || "${BAN_MATT_POCOCK_SKILLS:-}" == "1" || "${BAN_MATT_POCKOCK_SKILLS:-}" == "1" ]]
}

# Remove Matt Pocock skill copies from Pi when disabled.
remove_matt_pocock_pi_skills() {
    local _default_agent_dir="${HOME}/.pi/agent"
    local _active_agent_dir="${PI_CODING_AGENT_DIR:-${_default_agent_dir}}"
    local _skills_dir=""
    local _skill=""
    local _skill_path=""
    local _removed=0
    local _failed=()
    local _skills_dirs=("${_default_agent_dir}/skills")

    if [[ "${_active_agent_dir}" != "${_default_agent_dir}" ]]; then
        _skills_dirs+=("${_active_agent_dir}/skills")
    fi

    for _skills_dir in "${_skills_dirs[@]}"; do
        while IFS= read -r _skill; do
            _skill_path="${_skills_dir}/${_skill}"
            if [[ -e "${_skill_path}" ]]; then
                if rm -rf -- "${_skill_path:?}" && [[ ! -e "${_skill_path}" ]]; then
                    _removed=1
                else
                    _failed+=("${_skill}")
                fi
            fi
        done < <(matt_pocock_pi_skills || true)
    done

    if [[ "${#_failed[@]}" -gt 0 ]]; then
        print_warning "Failed to remove Matt Pocock Pi skills: ${_failed[*]}"
        return 1
    elif [[ "${_removed}" -eq 1 ]]; then
        print_success "Matt Pocock Pi skills disabled."
    else
        print_debug "Matt Pocock Pi skills disabled; no installed copies found."
    fi
}

# Install/update Matt Pocock engineering skills for Pi.
setup_matt_pocock_pi_skills() {
    local _repo="mattpocock/skills"
    local _default_agent_dir="${HOME}/.pi/agent"
    local _agent_dir="${PI_CODING_AGENT_DIR:-${_default_agent_dir}}"
    local _default_skills_dir="${_default_agent_dir}/skills"
    local _skills_dir="${_agent_dir}/skills"
    local _skill=""
    local _output=""
    local _source_path=""
    local _dest_path=""
    local _args=(--yes skills@latest add "${_repo}" --global --agent pi --copy -y)
    local _missing=()
    local _sync_failed=()

    if matt_pocock_pi_skills_disabled; then
        if [[ "${WORK_MACHINE:-}" == "1" ]]; then
            print_debug "WORK_MACHINE=1, skipping Matt Pocock Pi skills."
        fi
        remove_matt_pocock_pi_skills
        return 0
    fi

    if ! command -v pi &> /dev/null; then
        print_warning "Pi coding agent not found. Cannot install Matt Pocock Pi skills."
        return 0
    fi

    if ! ensure_pi_node_runtime; then
        print_warning "Skipping Matt Pocock Pi skills because the Pi Node.js runtime is not ready."
        return 0
    fi

    if ! command -v npx &> /dev/null; then
        print_warning "npx not found. Cannot install Matt Pocock Pi skills."
        print_debug "Install Node.js >=20.6, then run: npx --yes skills@latest add mattpocock/skills --global --agent pi --copy"
        return 0
    fi

    while IFS= read -r _skill; do
        _args+=(--skill "${_skill}")
    done < <(matt_pocock_pi_skills || true)

    print_message "Installing/updating Matt Pocock Pi skills..."
    if _output=$(npx "${_args[@]}" 2>&1); then
        if [[ "${_agent_dir}" != "${_default_agent_dir}" ]]; then
            mkdir -p "${_skills_dir}"
            while IFS= read -r _skill; do
                _source_path="${_default_skills_dir}/${_skill}"
                _dest_path="${_skills_dir}/${_skill}"
                if [[ -d "${_source_path}" ]]; then
                    if rm -rf -- "${_dest_path:?}" && cp -a "${_source_path}" "${_dest_path}"; then
                        true
                    else
                        _sync_failed+=("${_skill}")
                    fi
                else
                    _sync_failed+=("${_skill}")
                fi
            done < <(matt_pocock_pi_skills || true)
        fi

        while IFS= read -r _skill; do
            if [[ ! -f "${_skills_dir}/${_skill}/SKILL.md" ]]; then
                _missing+=("${_skill}")
            fi
        done < <(matt_pocock_pi_skills || true)

        if [[ "${#_sync_failed[@]}" -gt 0 ]]; then
            print_warning "Matt Pocock Pi skills installed, but failed to sync to active Pi dir ${_agent_dir}: ${_sync_failed[*]}"
        elif [[ "${#_missing[@]}" -eq 0 ]]; then
            print_success "Matt Pocock Pi skills installed/updated."
        else
            print_warning "Matt Pocock Pi skills install completed, but missing expected skills: ${_missing[*]}"
        fi
    else
        print_warning "Failed to install Matt Pocock Pi skills: ${_output}"
    fi
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
        ce-worktree
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

update_brew() {
    local update_status
    local upgrade_status
    local unpin_status=0
    local unmanaged_taps_status=0

    print_message "Updating Homebrew..."
    if brew update > /dev/null; then
        update_status=0
    else
        update_status=$?
    fi

    # Pin tmux during upgrades to prevent killing existing sessions. The cleanup
    # trap also unpins it if the script is interrupted during brew upgrade.
    SETUP_TMUX_PINNED=1
    install_setup_cleanup_traps
    brew pin tmux 2>/dev/null || true
    print_message "Upgrading outdated packages..."
    if brew upgrade > /dev/null; then
        upgrade_status=0
    else
        upgrade_status=$?
    fi
    if brew unpin tmux 2>/dev/null; then
        SETUP_TMUX_PINNED=0
    else
        unpin_status=$?
        print_warning "Could not unpin tmux; retry with: brew unpin tmux"
    fi

    if ! report_unmanaged_untrusted_brew_items; then
        unmanaged_taps_status=1
    fi

    if [[ "${update_status}" -eq 0 ]] && [[ "${upgrade_status}" -eq 0 ]] && [[ "${unpin_status}" -eq 0 ]] && [[ "${unmanaged_taps_status}" -eq 0 ]] && [[ "${SETUP_BREW_TRUST_FAILURES}" -eq 0 ]]; then
        print_success "Homebrew updated."
    elif [[ "${update_status}" -eq 0 ]] && [[ "${upgrade_status}" -eq 0 ]] && [[ "${unpin_status}" -eq 0 ]]; then
        print_warning "Homebrew commands completed, but tap-trust warnings may have skipped packages; resolve the warnings above."
    else
        print_warning "Homebrew update/upgrade incomplete (update=${update_status}, upgrade=${upgrade_status}, unpin=${unpin_status}); fix the errors above, then run: brew update && brew upgrade"
        print_warning "For a missing Bartender app, run: brew reinstall --cask --force bartender"
    fi
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

install_betterdisplay() {
    if [[ "${HEADLESS:-}" != "1" ]]; then
        return
    fi

    if brew list --cask betterdisplay &>/dev/null 2>&1; then
        print_debug "BetterDisplay is already installed."
        return
    fi

    print_message "Installing BetterDisplay for headless display management..."
    if brew install --cask betterdisplay; then
        print_success "BetterDisplay installed."
    else
        print_error "Failed to install BetterDisplay."
    fi
}

configure_power_settings() {
    if [[ "${HEADLESS:-}" != "1" ]]; then
        return
    fi

    if ! can_sudo; then
        print_warning "No sudo access — cannot configure power settings."
        return
    fi

    print_message "Configuring power settings for headless operation..."

    local changed=false

    # Disable system sleep (0 = never sleep)
    if [[ "$(sudo pmset -g custom 2>/dev/null | awk '/^ sleep/{print $2; exit}' || true)" != "0" ]]; then
        sudo pmset -a sleep 0
        changed=true
    fi

    # Disable display sleep
    if [[ "$(sudo pmset -g custom 2>/dev/null | awk '/^ displaysleep/{print $2; exit}' || true)" != "0" ]]; then
        sudo pmset -a displaysleep 0
        changed=true
    fi

    # Disable hard disk sleep
    if [[ "$(sudo pmset -g custom 2>/dev/null | awk '/^ disksleep/{print $2; exit}' || true)" != "0" ]]; then
        sudo pmset -a disksleep 0
        changed=true
    fi

    # Restart automatically after a power failure
    if [[ "$(sudo pmset -g custom 2>/dev/null | awk '/^ autorestart/{print $2; exit}' || true)" != "1" ]]; then
        sudo pmset -a autorestart 1
        changed=true
    fi

    # Wake on network access (for SSH/remote access)
    if [[ "$(sudo pmset -g custom 2>/dev/null | awk '/^ womp/{print $2; exit}' || true)" != "1" ]]; then
        sudo pmset -a womp 1
        changed=true
    fi

    if [[ "${changed}" == "true" ]]; then
        print_success "Power settings configured for headless operation (never sleep, auto-restart on power loss)."
    else
        print_debug "Power settings already configured for headless operation."
    fi
}

enable_screen_sharing() {
    if [[ "${HEADLESS:-}" != "1" ]]; then
        return
    fi

    if ! can_sudo; then
        print_warning "No sudo access — cannot enable Screen Sharing."
        return
    fi

    # Ensure the screensharing launchd job is loaded
    if ! sudo launchctl list com.apple.screensharing &>/dev/null; then
        print_message "Loading Screen Sharing launchd job..."
        sudo launchctl load -w /System/Library/LaunchDaemons/com.apple.screensharing.plist 2>/dev/null
        sudo launchctl enable system/com.apple.screensharing 2>/dev/null
    fi

    # Verify Screen Sharing is properly enabled via System Settings.
    # The launchd job can be loaded and VNC port listening, but connections get rejected
    # if Screen Sharing was never toggled on in System Settings. The kickstart command
    # prints "must be enabled from System Settings" when this is the case.
    local kickstart="/System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart"
    local tmpfile
    tmpfile=$(mktemp)
    # shellcheck disable=SC2024 # Capture kickstart output in a user-writable temp file.
    sudo "${kickstart}" -activate &>"${tmpfile}" &
    local pid=$!
    ( sleep 10 && kill "${pid}" 2>/dev/null ) &
    local watchdog=$!
    wait "${pid}" 2>/dev/null
    kill "${watchdog}" 2>/dev/null
    wait "${watchdog}" 2>/dev/null
    local kickstart_output
    kickstart_output=$(cat "${tmpfile}")
    rm -f "${tmpfile}"
    if echo "${kickstart_output}" | grep -q "must be enabled from System Settings"; then
        print_error "Screen Sharing is NOT properly enabled."
        print_error "The launchd job is loaded but macOS requires manual GUI enablement:"
        print_error "  1. Open System Settings → General → Sharing"
        print_error "  2. Toggle ON 'Screen Sharing'"
        print_error "  3. Re-run this setup script to verify"
        print_error "If you cannot access the GUI, connect a monitor/keyboard temporarily."
        return
    fi

    # Grant all remote management privileges (observe, control, etc.) to all users.
    # Without this, authentication succeeds but authorization fails with privilege level 0,
    # which macOS displays as an incorrect password shake.
    print_message "Configuring Screen Sharing privileges..."
    # shellcheck disable=SC2024 # Capture kickstart output in a user-writable temp file.
    sudo "${kickstart}" -configure -allowAccessFor -allUsers -privs -all -restart -agent &>"${tmpfile}" &
    pid=$!
    ( sleep 10 && kill "${pid}" 2>/dev/null ) &
    watchdog=$!
    wait "${pid}" 2>/dev/null
    kill "${watchdog}" 2>/dev/null
    wait "${watchdog}" 2>/dev/null
    rm -f "${tmpfile}"
    print_debug "Screen Sharing is enabled and accepting connections."
}

run_setup_tasks() {
    # Run the setup tasks
    current_user=$(whoami || true)
    echo -e "\n${BOLD}🍎 macOS Development Environment Setup${NC}"
    echo -e "${GRAY}Version 189 | Last changed: Remove Impeccable from machine setup${NC}"

    if ! acquire_setup_lock; then
        return 1
    fi

    # Create ~/.env.local (migrating old token files if needed)
    create_env_local

    # Source env vars early so optional setup flags are available
    if [[ -f "${HOME}/.env.local" ]]; then
        set -a
        # shellcheck source=/dev/null
        source "${HOME}/.env.local"
        set +a
    fi

    print_section "Xcode Command Line Tools"
    install_xcode_cli_tools

    if is_main_user; then
        echo -e "${CYAN}Running full setup for main user (scowalt)${NC}"

        print_section "Package Manager Setup"
        install_homebrew

        print_section "Core Packages"
        install_core_packages
        install_sessionwatcher
        install_secrets_manager
        install_gcloud_cli

        # Block public upload services on work machines
        block_public_upload_services

        # Enable SSH with key-only auth
        enable_ssh

        # Install Tailscale as cask (GUI app) and start daemon
        setup_tailscale

        # Install Nerd Font for terminal icons (Starship prompt, etc.)
        install_nerd_font

        # Install BetterDisplay for headless machines with dummy HDMI
        install_betterdisplay

        # Prevent sleep on headless machines
        configure_power_settings

        # Enable Screen Sharing on headless machines (VNC access)
        enable_screen_sharing

        # Fix zsh permissions early (before any tool might invoke zsh)
        fix_zsh_compaudit

        print_section "SSH Configuration"
        setup_ssh_key || return 1
        add_github_to_known_hosts || return 1

        print_section "Code Directory Setup"
        setup_code_directory

    else
        echo -e "${CYAN}Running secondary user setup for ${current_user}${NC}"

        # Ensure Homebrew is in PATH (already installed by main user)
        local brew_env
        brew_env=$(/opt/homebrew/bin/brew shellenv) || true
        eval "${brew_env}"

        # Fix zsh permissions early (before any tool might invoke zsh)
        fix_zsh_compaudit

        print_section "SSH Configuration"
        add_github_to_known_hosts || return 1
    fi

    # Common setup for all users
    print_section "Shared Directories"
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
        # chezmoi init --apply overwrites ~/.ssh/config, removing the
        # github-dotfiles host alias needed for deploy key access.
        # Re-bootstrap it before any further chezmoi network operations.
        bootstrap_ssh_config
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
    install_bun
    setup_headless_paseo_daemon || return 1
    install_sfw
    install_claude_code
    install_gemini_cli
    install_codex_cli
    install_portless_cli
    install_ntn_cli
    install_rtk_cli
    setup_rtk_integrations
    if matt_pocock_pi_skills_disabled; then
        setup_matt_pocock_pi_skills
    fi
    if install_pi_cli; then
        configure_pi_defaults
        seed_pi_synthetic_models
        setup_pi_subagents
        setup_pi_mcp_adapter
        setup_pi_claude_bridge
        setup_pi_goal_autoresearch
        if ! matt_pocock_pi_skills_disabled; then
            setup_matt_pocock_pi_skills
        fi
    else
        if [[ "${BAN_PI_SUBAGENTS:-}" == "1" ]]; then
            setup_pi_subagents
        fi
        if [[ "${BAN_PI_MCP_ADAPTER:-}" == "1" ]]; then
            setup_pi_mcp_adapter
        fi
        if [[ "${BAN_PI_GOAL_AUTORESEARCH:-}" == "1" ]]; then
            setup_pi_goal_autoresearch
        fi
        print_warning "Skipping Pi extension setup because Pi migration failed."
    fi

    remove_impeccable_resources

    remove_compound_engineering_resources

    if is_main_user; then
        print_section "Final Updates"
        update_brew
    fi

    upgrade_npm_global_packages

    printf '\n%s%s✨ Setup complete!%s\n\n' "${GREEN}" "${BOLD}" "${NC}"
}

main() {
    local setup_status=0

    start_setup_log || true
    run_setup_tasks "$@" || setup_status=$?
    finish_setup_log "${setup_status}"
}

main "$@"
