refresh_bb_plugins() {
    local _bb_refresh_output _bb_refresh_status=0 _bb_refresh_line
    local _bb_refresh_operation _bb_refresh_reason _bb_refresh_diagnostic=0
    print_section 'BB Plugin Refresh'
    if [[ ! -x /usr/bin/python3 ]]; then
        print_error 'BB plugin refresh failed: preflight / python-unavailable.'
        return 1
    fi
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
@@PYTHON@@
BB_PLUGIN_REFRESH_PY
}
