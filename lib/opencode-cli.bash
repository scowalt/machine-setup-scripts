# Version 7 | Last changed: Verify account-local OpenCode command selection
install_opencode_cli() {
    local result status=0 brew_ready=0 machine kind native_shell cached_command recovery=0
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
    if declare -F macos_existing_prerequisites >/dev/null; then
        if ! macos_existing_prerequisites 'OpenCode native download/extraction' node; then
            print_error 'OpenCode CLI blocked (operation=prerequisites, reason=unverified).'
            return 1
        fi
        if [[ "${MACOS_DEVELOPER_TOOLS_STATE:-unverified}" == ready ]]; then brew_ready=1; fi
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
        result=$(SETUP_OPENCODE_BREW_READY="${brew_ready}" SETUP_OPENCODE_SHELL="${native_shell}" SETUP_OPENCODE_HASHED="${cached_command}" env -u NODE_OPTIONS -u NODE_PATH node - 2>/dev/null) || status=$?
    } <<'OPENCODE_CLI_JS'
// @OPENCODE_CORE@
OPENCODE_CLI_JS
    if [[ "${status}" -ne 0 ]]; then
        if [[ "${result}" == opencode-cli:recovery-required || "${result}" == opencode-cli:recovery-required:failed ]]; then
            recovery=1
        elif [[ "${result}" =~ ^opencode-cli:(recovery-required:)?download-failed:(latest-release|package-index|package-version|artifact-download|download):http-([1-5][0-9][0-9]|unknown)$ ]]; then
            [[ -z "${BASH_REMATCH[1]}" ]] || recovery=1
            print_error "OpenCode CLI download failed (operation=${BASH_REMATCH[2]}, HTTP=${BASH_REMATCH[3]})."
        elif [[ "${result}" =~ ^opencode-cli:(recovery-required:)?policy-failed:(homebrew-preflight|installation|setup-selection|fresh-shell-selection):(archive|archive-header|archive-path|archive-tail|archive-truncated|archive-type|artifact-identity|artifact-metadata|brew-command|brew-origin|brew-path|brew-readiness|brew-snapshot-changed|changed-copy|changed-receipt|custom-link|custom-prefix|custom-wrapper|duplicate-metadata|integrity|libc|metadata|missing-binary|outside-home|package-conflict|pinned|receipt|recovery-occupied|relative-path|release-metadata|shadowed|shadowed-newer|unreachable|unsafe-file|unsafe-path|unverified-copy|url|version|version-probe|windows-acl|foreign-command|command-conflict|selection-unverified|native-(EACCES|EPERM|ENOENT|EIO|EEXIST|ENOTDIR|ELOOP|ENOSPC|EROFS|ETIMEDOUT|ENOBUFS))$ ]]; then
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
