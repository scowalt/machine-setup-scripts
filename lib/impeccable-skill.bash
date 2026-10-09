impeccable_skill_failure() {
    local _phase="${1}" _reason="${2}" _status="${3:-unavailable}"
    case "${_phase}" in
        prerequisites|preflight|npm-configuration|staging|environment-isolation|installer|promotion|cleanup|removal) ;;
        *) _phase=prerequisites ;;
    esac
    case "${_reason}" in
        @IMPECCABLE_REASONS@) ;;
        *) _reason=unknown ;;
    esac
    [[ "${_status}" =~ ^[0-9]{1,3}$ ]] || _status=unavailable
    print_warning "Impeccable: phase=${_phase} reason=${_reason} exit=${_status}."
}

impeccable_skill_policy() {
    local _code='' _result='' _status=0 _phase=preflight _kind="${1:-}" _reason=unknown
    local -a _pipe_status=()
    IFS= read -r -d '' _code <<'IMPECCABLE_SKILL_JS' || :
@IMPECCABLE_CORE@
IMPECCABLE_SKILL_JS
    if [[ "${_kind}" == diagnostic ]]; then
        local _begin="void 'BEGIN_IMPECCABLE_DIAGNOSTICS';" _end="void 'END_IMPECCABLE_DIAGNOSTICS';"
        _code="${_code#*"${_begin}"}"
        _code="${_code%%"${_end}"*}"
        if ! _result=$(env -u NODE_OPTIONS -u NODE_PATH node --input-type=commonjs --eval \
            "${_code}; impeccableReadDiagnostic(process.argv[1]);" -- "${2:-}" 2>/dev/null); then
            cat > /dev/null
            _result=reason:unknown
        fi
        case "${_result}" in
            reason:*)
                _reason="${_result#reason:}"
                case "${_reason}" in
                    @IMPECCABLE_REASONS@) ;;
                    *) _reason=unknown ;;
                esac
                printf 'reason:%s\n' "${_reason}"
                ;;
            ok) printf 'ok\n' ;;
            stage:*)
                if [[ "${2:-}" == stage && "${_result}" != *$'\n'* ]]; then
                    printf '%s\n' "${_result}"
                else
                    printf 'reason:unknown\n'
                fi
                ;;
            *) printf 'reason:unknown\n' ;;
        esac
        return 0
    fi
    case "${_kind}" in
        stage) _phase=staging ;;
        promote) _phase=promotion ;;
        dispose) _phase=cleanup ;;
        remove) _phase=removal ;;
        *) _phase=preflight ;;
    esac
    if ! command -v node > /dev/null 2>&1; then
        impeccable_skill_failure "${_phase}" shared-runtime-unavailable
        return 1
    fi
    _result=$(
        # shellcheck disable=SC2312
        if env -u NODE_OPTIONS -u NODE_PATH node --input-type=commonjs - \
            "${HOME}" "${PI_CODING_AGENT_DIR:-}" "${PI_PROFILE_MUTATIONS_BLOCKED:-0}" "$@" \
            <<< "${_code}" 2>&1 | impeccable_skill_policy diagnostic "${_kind}"; then
            _pipe_status=("${PIPESTATUS[@]}")
        else
            _pipe_status=("${PIPESTATUS[@]}")
        fi
        printf '%s\n' "${_pipe_status[0]}"
    )
    _status="${_result##*$'\n'}"
    _result="${_result%$'\n'*}"
    if [[ "${_status}" == 0 ]]; then
        if [[ "${_kind}" == stage && "${_result}" == stage:* ]]; then
            printf '%s\n' "${_result#stage:}"
            return 0
        elif [[ "${_kind}" != stage && "${_result}" == ok ]]; then
            return 0
        fi
        _reason=invalid-result
    elif [[ "${_result}" == reason:* ]]; then
        _reason="${_result#reason:}"
    fi
    impeccable_skill_failure "${_phase}" "${_reason}" "${_status}"
    return 1
}

converge_impeccable_skill() {
    local _stage='' _npm_userconfig='' _npm_globalconfig='' _failed=0 _status=0 _result='' _reason=unknown
    local -a _pipe_status=()
    if [[ "${BAN_IMPECCABLE:-}" == 1 ]]; then
        impeccable_skill_policy remove
        return
    fi
    if ! ensure_skills_cli_node_runtime || ! command -v npx > /dev/null 2>&1; then
        impeccable_skill_failure prerequisites installer-runtime-unavailable
        return 1
    fi
    impeccable_skill_policy preflight || return 1
    _npm_userconfig=$(npm config get userconfig 2>/dev/null) || _status=$?
    if [[ "${_status}" == 0 && -n "${_npm_userconfig}" ]]; then
        _npm_globalconfig=$(npm config get globalconfig 2>/dev/null) || _status=$?
    fi
    if [[ "${_status}" != 0 || -z "${_npm_userconfig}" || -z "${_npm_globalconfig}" ]]; then
        impeccable_skill_failure npm-configuration npm-configuration-unverified "${_status}"
        return 1
    fi
    _stage=$(impeccable_skill_policy stage) || return 1
    print_message 'Installing/updating official global Impeccable skills without hooks...'
    if (
        _status=0
        umask 077 2>/dev/null || _status=$?
        if [[ "${_status}" != 0 ]]; then
            impeccable_skill_failure environment-isolation environment-isolation-failed "${_status}"
            exit 1
        fi
        cd "${_stage}" 2>/dev/null || _status=$?
        if [[ "${_status}" != 0 ]]; then
            impeccable_skill_failure staging stage-directory-unavailable "${_status}"
            exit 1
        fi
        unset NODE_OPTIONS NODE_PATH IMPECCABLE_BIN IMPECCABLE_BUNDLE_PATH IMPECCABLE_DOWNLOAD_BASE \
            IMPECCABLE_SKILL_DIR IMPECCABLE_SELF IMPECCABLE_LAUNCHER_PROBE 2>/dev/null || _status=$?
        if [[ "${_status}" != 0 ]]; then
            impeccable_skill_failure environment-isolation environment-isolation-failed "${_status}"
            exit 1
        fi
        _result=$(
            # shellcheck disable=SC2312
            if HOME="${_stage}" USERPROFILE="${_stage}" \
                CLAUDE_CONFIG_DIR="${_stage}/.claude" CODEX_HOME="${_stage}/.codex" PI_CODING_AGENT_DIR="${_stage}/.pi/agent" \
                XDG_STATE_HOME="${_stage}/.state" XDG_CONFIG_HOME="${_stage}/.config" \
                XDG_CACHE_HOME="${_stage}/.cache" XDG_DATA_HOME="${_stage}/.local/share" \
                APPDATA="${_stage}/.appdata" LOCALAPPDATA="${_stage}/.localappdata" IMPECCABLE_HOME="${_stage}/.impeccable" \
                TMPDIR="${_stage}/.tmp" TMP="${_stage}/.tmp" TEMP="${_stage}/.tmp" \
                npm_config_userconfig="${_npm_userconfig}" NPM_CONFIG_USERCONFIG="${_npm_userconfig}" \
                npm_config_globalconfig="${_npm_globalconfig}" NPM_CONFIG_GLOBALCONFIG="${_npm_globalconfig}" \
                npx --yes impeccable@latest install --yes --scope=global \
                    --providers=claude,codex,cursor,gemini,pi --no-hooks < /dev/null 2>&1 | \
                impeccable_skill_policy diagnostic installer; then
                _pipe_status=("${PIPESTATUS[@]}")
            else
                _pipe_status=("${PIPESTATUS[@]}")
            fi
            printf '%s\n' "${_pipe_status[0]}"
        )
        _status="${_result##*$'\n'}"
        _reason="${_result%$'\n'*}"
        if [[ "${_status}" != 0 ]]; then
            impeccable_skill_failure installer "${_reason#reason:}" "${_status}"
            exit 1
        fi
    ); then
        impeccable_skill_policy promote "${_stage}" || _failed=1
    else
        _failed=1
    fi
    impeccable_skill_policy dispose "${_stage}" || _failed=1
    if [[ "${_failed}" -eq 0 ]]; then
        print_success 'Impeccable global payload and Pi discovery input verified; hooks unchanged.'
    fi
    return "${_failed}"
}
