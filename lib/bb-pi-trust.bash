bb_pi_trust_policy() {
    local _mode="${1:-merge}" _result='' _status=0
    shift || return 1
    if ! command -v node > /dev/null 2>&1; then
        print_warning "BB/Pi trust: shared Node runtime unavailable."
        return 1
    fi
    _result=$(env -u NODE_OPTIONS -u NODE_PATH node --input-type=commonjs - "${_mode}" \
        "${HOME}" "${BB_DATA_DIR:-${HOME}/.bb}" "${PI_CODING_AGENT_DIR:-${HOME}/.pi/agent}" "$@" \
        2>/dev/null <<'BB_PI_TRUST_JS'
@BB_PI_TRUST_CORE@
BB_PI_TRUST_JS
    ) || _status=$?
    if [[ "${_status}" -eq 0 && "${_result}" == ok ]]; then
        return 0
    fi
    case "${_result}" in
        failed:unsafe-path|failed:unsafe-directory|failed:unsafe-home|failed:unsafe-profile|failed:unsafe-acl|failed:unsafe-metadata|failed:invalid-trust|failed:trust-locked|failed:changed-input|failed:unsafe-cli|failed:doctor-failed|failed:invalid-doctor-report|failed:doctor-blocked|failed:doctor-unhealthy|failed:doctor-missing-server|failed:invalid-mode) ;;
        *) _result=failed:unknown ;;
    esac
    print_warning "BB/Pi trust: ${_result}. Existing decisions and MCP approvals were not replaced."
    return 1
}

configure_bb_pi_trust() {
    if [[ "${PI_PROFILE_MUTATIONS_BLOCKED:-0}" == 1 ]]; then
        print_warning "Skipping BB/Pi trust because Pi profile mutations are blocked."
        return 1
    fi
    if [[ "${BAN_PI_MCP_ADAPTER:-0}" == 1 ]]; then
        return 0
    fi
    bb_pi_trust_policy merge || return 1
    print_debug "Pi workspace trust merged; existing decisions and MCP definition approvals preserved."
}

check_bb_pi_mcp_health() {
    bb_pi_trust_policy health "$@"
}
