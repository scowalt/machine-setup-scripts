pi_visual_explainer_policy() {
    local _mode="${1:?missing mode}" _result='' _status=0
    shift
    {
        _result=$(env -u NODE_OPTIONS -u NODE_PATH node --input-type=commonjs - "${_mode}" \
            "${HOME}" "${PI_CODING_AGENT_DIR:-${HOME}/.pi/agent}" "$@" 2>/dev/null) || _status=$?
    } <<'PI_VISUAL_EXPLAINER_JS'
@PI_VISUAL_EXPLAINER_CORE@
PI_VISUAL_EXPLAINER_JS
    if [[ "${_status}" -eq 0 ]]; then
        if [[ "${_mode}" == plan && "${_result}" == source:* ]]; then
            printf '%s\n' "${_result#source:}"
            return 0
        elif [[ "${_mode}" != plan && "${_result}" == ok ]]; then
            return 0
        fi
    fi
    case "${_result}" in
        failed:unsafe-profile|failed:unsafe-directory|failed:unsafe-file|failed:unsafe-acl|failed:invalid-metadata|failed:source-conflict|failed:redirected-git|failed:unverified-checkout|failed:modified-checkout|failed:invalid-payload|failed:legacy-conflict|failed:changed-input|failed:unverified-install|failed:invalid-mode|failed:dependency-conflict|failed:dependency-recovery|failed:native-command) ;;
        *) _result=failed:unknown ;;
    esac
    if [[ "${_result}" == failed:dependency-recovery ]]; then
        print_warning 'Visual Explainer: failed:dependency-recovery. Inspect .setup-visual-explainer-dependencies in the active Pi profile; saved dependencies were not deleted or overwritten.' >&2
    else
        print_warning "Visual Explainer: ${_result}. Existing custom resources and diagrams were preserved; reconcile conflicts before retrying." >&2
    fi
    return 1
}

setup_pi_visual_explainer() {
    local _source=''
    if [[ "${PI_PROFILE_MUTATIONS_BLOCKED:-0}" == 1 ]]; then
        print_warning 'Skipping Visual Explainer because Pi profile mutations are blocked.'
        return 1
    fi
    if ! command -v node > /dev/null 2>&1 || ! command -v npm > /dev/null 2>&1 || \
        ! command -v git > /dev/null 2>&1 || ! command -v pi > /dev/null 2>&1; then
        print_warning 'Visual Explainer: required Pi/shared-runtime/Git prerequisites are unavailable.'
        return 1
    fi
    case "${PI_OFFLINE:-}" in
        1|[Tt][Rr][Uu][Ee]|[Yy][Ee][Ss])
            print_warning 'Visual Explainer: offline mode prevents required package maintenance.'
            return 1 ;;
        *) ;;
    esac
    _source=$(pi_visual_explainer_policy plan) || return 1
    print_message 'Installing/updating the native Visual Explainer Pi package...'
    pi_visual_explainer_policy install "${_source}" || return 1
    pi_visual_explainer_policy finish "${_source}" || return 1
    print_success 'Visual Explainer Pi package installed/updated; existing pins and resource selections preserved.'
}
