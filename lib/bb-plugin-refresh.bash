# Native main-server plugin refresh only; independent of preparation and Pi gates.
# Version 1 | Last changed: Refresh verified local BB plugins through native APIs
refresh_bb_plugins() {
    local _bb_refresh_output _bb_refresh_status=0 _bb_refresh_line
    print_section 'BB Plugin Refresh'
    if [[ ! -x /usr/bin/python3 ]]; then
        print_error 'BB plugin refresh unverified: native Python 3 is unavailable.'
        return 1
    fi
    # No inherited CLI/server URL is used, and no BB executable is invoked.
    _bb_refresh_output=$(bb_plugin_refresh_payload "${1:-ready}" 2>/dev/null) || _bb_refresh_status=$?
    if [[ ${#_bb_refresh_output} -gt 16384 || -z "${_bb_refresh_output}" ]]; then
        print_error 'BB plugin refresh failed: unverified helper result.'
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
            'BB_PLUGIN_REFRESH failed') print_error 'BB plugin refresh failed or remains unverified; no lifecycle recovery was attempted.'; _bb_refresh_status=1 ;;
            *) print_error 'BB plugin refresh failed: unverified helper result.'; return 1 ;;
        esac
    done <<< "${_bb_refresh_output}"
    if [[ "${_bb_refresh_status}" -ne 0 ]]; then
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
