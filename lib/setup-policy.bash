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
