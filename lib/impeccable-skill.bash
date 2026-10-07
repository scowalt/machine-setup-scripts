impeccable_skill_policy() {
    if ! command -v node > /dev/null 2>&1; then
        print_warning 'Impeccable: shared-runtime-unavailable.'
        return 1
    fi
    env -u NODE_OPTIONS -u NODE_PATH node --input-type=commonjs - \
        "${HOME}" "${PI_CODING_AGENT_DIR:-}" "${PI_PROFILE_MUTATIONS_BLOCKED:-0}" "$@" <<'IMPECCABLE_SKILL_JS'
@IMPECCABLE_CORE@
IMPECCABLE_SKILL_JS
}

converge_impeccable_skill() {
    local _stage='' _npm_userconfig='' _npm_globalconfig='' _failed=0
    if [[ "${BAN_IMPECCABLE:-}" == 1 ]]; then
        impeccable_skill_policy remove
        return
    fi
    if ! ensure_skills_cli_node_runtime || ! command -v npx > /dev/null 2>&1; then
        print_warning 'Impeccable: installer-runtime-unavailable.'
        return 1
    fi
    impeccable_skill_policy preflight || return 1
    if ! _npm_userconfig=$(npm config get userconfig 2>/dev/null) || [[ -z "${_npm_userconfig}" ]] ||
        ! _npm_globalconfig=$(npm config get globalconfig 2>/dev/null) || [[ -z "${_npm_globalconfig}" ]]; then
        print_warning 'Impeccable: npm-configuration-unverified.'
        return 1
    fi
    _stage=$(impeccable_skill_policy stage) || return 1
    print_message 'Installing/updating official global Impeccable skills without hooks...'
    if ! (
        cd "${_stage}" || exit 1
        unset NODE_OPTIONS NODE_PATH IMPECCABLE_BIN IMPECCABLE_BUNDLE_PATH IMPECCABLE_DOWNLOAD_BASE \
            IMPECCABLE_SKILL_DIR IMPECCABLE_SELF IMPECCABLE_LAUNCHER_PROBE
        HOME="${_stage}" USERPROFILE="${_stage}" \
            CLAUDE_CONFIG_DIR="${_stage}/.claude" CODEX_HOME="${_stage}/.codex" PI_CODING_AGENT_DIR="${_stage}/.pi/agent" \
            XDG_STATE_HOME="${_stage}/.state" XDG_CONFIG_HOME="${_stage}/.config" \
            XDG_CACHE_HOME="${_stage}/.cache" XDG_DATA_HOME="${_stage}/.local/share" \
            APPDATA="${_stage}/.appdata" LOCALAPPDATA="${_stage}/.localappdata" IMPECCABLE_HOME="${_stage}/.impeccable" \
            TMPDIR="${_stage}/.tmp" TMP="${_stage}/.tmp" TEMP="${_stage}/.tmp" \
            npm_config_userconfig="${_npm_userconfig}" NPM_CONFIG_USERCONFIG="${_npm_userconfig}" \
            npm_config_globalconfig="${_npm_globalconfig}" NPM_CONFIG_GLOBALCONFIG="${_npm_globalconfig}" \
            npx --yes impeccable@latest install --yes --scope=global \
                --providers=claude,codex,cursor,gemini,pi --no-hooks < /dev/null > /dev/null 2>&1
    ); then
        print_warning 'Impeccable: installer-failed.'
        _failed=1
    elif ! impeccable_skill_policy promote "${_stage}"; then
        _failed=1
    fi
    impeccable_skill_policy dispose "${_stage}" || _failed=1
    if [[ "${_failed}" -eq 0 ]]; then
        print_success 'Impeccable global payload and Pi discovery input verified; hooks unchanged.'
    fi
    return "${_failed}"
}
