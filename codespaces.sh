#!/bin/bash

# GitHub Codespaces setup script
# Sources ubuntu.sh for shared functions, calls only the subset appropriate
# for ephemeral Codespaces containers (Ubuntu 24.04 based).

# Resolve the directory this script lives in
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source ubuntu.sh for shared functions
# When run via curl|bash, ubuntu.sh won't be adjacent — fetch it
if [[ -f "${SCRIPT_DIR}/ubuntu.sh" ]]; then
    # shellcheck source=ubuntu.sh
    source "${SCRIPT_DIR}/ubuntu.sh"
elif [[ -f "./ubuntu.sh" ]]; then
    # shellcheck source=ubuntu.sh
    source "./ubuntu.sh"
else
    # Fetch ubuntu.sh for curl|bash execution
    _ubuntu_tmp=$(mktemp)
    if ! curl -fsSL "https://scripts.scowalt.com/setup/ubuntu.sh" -o "${_ubuntu_tmp}"; then
        echo "ERROR: Failed to download ubuntu.sh. Cannot continue."
        rm -f "${_ubuntu_tmp}"
        exit 1
    fi
    # shellcheck source=/dev/null
    source "${_ubuntu_tmp}"
    rm -f "${_ubuntu_tmp}"
fi

main() {
    echo -e "\n${BOLD}☁️ GitHub Codespaces Development Environment Setup${NC}"
    echo -e "${GRAY}Version 1 | Last changed: Initial codespaces setup script${NC}"

    # Create placeholder env file early (migrates old token files if present)
    create_env_local

    print_section "System Setup"
    fix_dpkg_and_broken_dependencies
    update_and_install_core

    print_section "Code Directory Setup"
    setup_code_directory

    print_section "Development Tools"
    install_starship
    install_lefthook
    install_mise
    install_uv

    print_section "Shared Directories"
    setup_claude_shared_directory

    print_section "Dotfiles Management"

    # Bridge Codespaces GITHUB_TOKEN to GH_TOKEN for chezmoi HTTPS access
    if [[ -n "${GITHUB_TOKEN}" ]] && [[ -z "${GH_TOKEN}" ]]; then
        export GH_TOKEN="${GITHUB_TOKEN}"
        print_debug "Bridged GITHUB_TOKEN to GH_TOKEN for dotfiles access."
    fi

    if check_dotfiles_access; then
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
        initialize_chezmoi
        configure_chezmoi_git
        update_chezmoi
        (chezmoi apply --force) || true
        tmux source ~/.tmux.conf 2>/dev/null || true
    else
        print_warning "Skipping dotfiles management - no access to repository."
    fi

    print_section "Shell Configuration"
    set_fish_as_default_shell
    install_tmux_plugins

    print_section "Additional Development Tools"
    install_bun
    install_sfw
    install_claude_code
    setup_rube_mcp
    setup_compound_plugin
    install_gemini_cli

    print_section "Final Updates"
    upgrade_npm_global_packages

    echo -e "\n${GREEN}${BOLD}✨ Codespaces setup complete!${NC}\n"
}

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"
