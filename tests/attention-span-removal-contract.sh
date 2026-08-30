#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "${repo_root}"

bash_setup_scripts=(mac.sh ubuntu.sh wsl.sh pi.sh bazzite.sh)
source_without_main='s/^main "\$@"$/:/'

fail() {
    printf '✗ %s\n' "$1" >&2
    exit 1
}

assert_contains() {
    local file="$1"
    local pattern="$2"
    local description="$3"

    grep -Eq "${pattern}" "${file}" || fail "${file}: missing ${description}"
}

assert_not_contains() {
    local file="$1"
    local pattern="$2"
    local description="$3"

    if grep -Eq "${pattern}" "${file}"; then
        fail "${file}: unexpectedly contains ${description}"
    fi
}

for file in "${bash_setup_scripts[@]}"; do
    assert_contains "${file}" '^remove_attention_span_resources\(\)' 'retired Attention-kind cleanup interface'
    assert_contains "${file}" '^[[:space:]]+remove_attention_span_resources[[:space:]]+\|\|[[:space:]]+return 1$' 'strict Attention-kind cleanup call'
    assert_contains "${file}" 'CLAUDE_CONFIG_DIR:-' 'custom Claude directory cleanup'
    assert_contains "${file}" 'CODEX_HOME:-' 'custom Codex directory cleanup'
    assert_contains "${file}" 'PI_CODING_AGENT_DIR:-' 'custom Pi directory cleanup'
    assert_contains "${file}" 'output-styles/attention-kind\.md' 'Claude output-style cleanup target'
    assert_contains "${file}" 'attention-span:start' 'managed begin marker cleanup'
    assert_contains "${file}" 'attention-span:end' 'managed end marker cleanup'
    assert_not_contains "${file}" 'setup_attention_span_style|raw\.githubusercontent\.com/alexgreensh/attention-span' 'active Attention-kind installation support'

    apply_line=$(grep -En 'chezmoi apply|apply_chezmoi_config' "${file}" | tail -n 1 | cut -d: -f1)
    cleanup_line=$(grep -En '^[[:space:]]+remove_attention_span_resources[[:space:]]+\|\|[[:space:]]+return 1$' "${file}" | tail -n 1 | cut -d: -f1)
    [[ -n "${apply_line}" && -n "${cleanup_line}" && "${apply_line}" -lt "${cleanup_line}" ]] ||
        fail "${file}: Attention-kind cleanup does not run after dotfiles"
done

assert_contains win.ps1 '^function Remove-AttentionSpanResources' 'PowerShell retired Attention-kind cleanup interface'
assert_contains win.ps1 '^[[:space:]]+Remove-AttentionSpanResources$' 'strict PowerShell Attention-kind cleanup call'
# shellcheck disable=SC2016
assert_contains win.ps1 '\$env:CLAUDE_CONFIG_DIR' 'PowerShell custom Claude directory cleanup'
# shellcheck disable=SC2016
assert_contains win.ps1 '\$env:CODEX_HOME' 'PowerShell custom Codex directory cleanup'
# shellcheck disable=SC2016
assert_contains win.ps1 '\$env:PI_CODING_AGENT_DIR' 'PowerShell custom Pi directory cleanup'
assert_not_contains win.ps1 'Install-AttentionSpanStyle|raw\.githubusercontent\.com/alexgreensh/attention-span' 'active PowerShell Attention-kind installation support'
windows_dotfiles_line=$(grep -En '^[[:space:]]+Update-Chezmoi$' win.ps1 | tail -n 1 | cut -d: -f1)
windows_cleanup_line=$(grep -En '^[[:space:]]+Remove-AttentionSpanResources$' win.ps1 | tail -n 1 | cut -d: -f1)
[[ -n "${windows_dotfiles_line}" && -n "${windows_cleanup_line}" && "${windows_dotfiles_line}" -lt "${windows_cleanup_line}" ]] ||
    fail 'win.ps1: Attention-kind cleanup does not run after dotfiles'

run_cleanup_fixture() {
    local file="$1"
    local test_root=""

    test_root=$(mktemp -d)
    SETUP_SCRIPT="${repo_root}/${file}" SOURCE_WITHOUT_MAIN="${source_without_main}" TEST_ROOT="${test_root}" bash -c '
        set -euo pipefail
        home="${TEST_ROOT}/home"
        default_claude="${home}/.claude"
        custom_claude="${TEST_ROOT}/custom-claude"
        default_codex="${home}/.codex"
        custom_codex="${TEST_ROOT}/custom-codex"
        default_pi="${home}/.pi/agent"
        custom_pi="${TEST_ROOT}/custom-pi"
        symlink_target="${TEST_ROOT}/style-target.md"

        mkdir -p \
            "${default_claude}/output-styles" \
            "${custom_claude}/output-styles" \
            "${default_codex}" \
            "${custom_codex}" \
            "${home}/.gemini" \
            "${default_pi}" \
            "${custom_pi}"

        printf "%s\n" "managed style" > "${default_claude}/output-styles/attention-kind.md"
        printf "%s\n" "keep target" > "${symlink_target}"
        ln -s "${symlink_target}" "${custom_claude}/output-styles/attention-kind.md"
        printf "%s\n" "{\"outputStyle\":\"Attention-kind\",\"keep\":\"default\"}" > "${default_claude}/settings.json"
        printf "%s\n" "{\"outputStyle\":\"Other\",\"keep\":\"custom\"}" > "${custom_claude}/settings.json"

        write_managed_file() {
            local path="$1"
            local prefix="$2"
            local suffix="$3"
            printf "%s\n" \
                "${prefix}" \
                "<!-- attention-span:start -->" \
                "<!-- attention-span v0.7 -->" \
                "managed guidance" \
                "<!-- attention-span:end -->" \
                "${suffix}" > "${path}"
        }

        write_managed_file "${default_codex}/AGENTS.md" "keep default codex" "after default codex"
        write_managed_file "${custom_codex}/AGENTS.md" "" ""
        write_managed_file "${home}/.gemini/GEMINI.md" "keep gemini" "after gemini"
        write_managed_file "${default_pi}/APPEND_SYSTEM.md" "keep default pi" "after default pi"
        write_managed_file "${custom_pi}/APPEND_SYSTEM.md" "keep custom pi" "after custom pi"

        export HOME="${home}"
        export CLAUDE_CONFIG_DIR="${custom_claude}"
        export CODEX_HOME="${custom_codex}"
        export PI_CODING_AGENT_DIR="${custom_pi}"
        source <(sed "${SOURCE_WITHOUT_MAIN}" "${SETUP_SCRIPT}")

        remove_attention_span_resources
        remove_attention_span_resources

        for style in \
            "${default_claude}/output-styles/attention-kind.md" \
            "${custom_claude}/output-styles/attention-kind.md"; do
            [[ ! -e "${style}" && ! -L "${style}" ]] || { printf "left Attention-kind style: %s\n" "${style}" >&2; exit 91; }
        done
        [[ -f "${symlink_target}" ]] && grep -Fq "keep target" "${symlink_target}"

        jq -e ".keep == \"default\" and (has(\"outputStyle\") | not)" "${default_claude}/settings.json" > /dev/null
        jq -e ".keep == \"custom\" and .outputStyle == \"Other\"" "${custom_claude}/settings.json" > /dev/null

        for managed_file in \
            "${default_codex}/AGENTS.md" \
            "${custom_codex}/AGENTS.md" \
            "${home}/.gemini/GEMINI.md" \
            "${default_pi}/APPEND_SYSTEM.md" \
            "${custom_pi}/APPEND_SYSTEM.md"; do
            [[ -f "${managed_file}" ]] || { printf "removed shared file: %s\n" "${managed_file}" >&2; exit 92; }
            ! grep -Fq "attention-span" "${managed_file}"
            ! grep -Fq "managed guidance" "${managed_file}"
        done
        grep -Fq "keep default codex" "${default_codex}/AGENTS.md"
        grep -Fq "after default codex" "${default_codex}/AGENTS.md"
        grep -Fq "keep gemini" "${home}/.gemini/GEMINI.md"
        grep -Fq "keep default pi" "${default_pi}/APPEND_SYSTEM.md"
        grep -Fq "keep custom pi" "${custom_pi}/APPEND_SYSTEM.md"
    ' || fail "${file}: Attention-kind fixture cleanup failed"
    rm -rf "${test_root}"
}

for file in "${bash_setup_scripts[@]}"; do
    run_cleanup_fixture "${file}"
done

# Malformed markers must fail before any managed target changes.
malformed_root=$(mktemp -d)
mkdir -p "${malformed_root}/home/.claude/output-styles" "${malformed_root}/custom-codex"
printf '%s\n' style > "${malformed_root}/home/.claude/output-styles/attention-kind.md"
printf '%s\n' '{"outputStyle":"Attention-kind","keep":true}' > "${malformed_root}/home/.claude/settings.json"
printf '%s\n' '<!-- attention-span:start -->' 'keep malformed' > "${malformed_root}/custom-codex/AGENTS.md"
SETUP_SCRIPT="${repo_root}/ubuntu.sh" SOURCE_WITHOUT_MAIN="${source_without_main}" TEST_ROOT="${malformed_root}" bash -c '
    set -euo pipefail
    export HOME="${TEST_ROOT}/home"
    export CODEX_HOME="${TEST_ROOT}/custom-codex"
    source <(sed "${SOURCE_WITHOUT_MAIN}" "${SETUP_SCRIPT}")
    if remove_attention_span_resources; then
        exit 90
    fi
    [[ -f "${HOME}/.claude/output-styles/attention-kind.md" ]]
    jq -e ".outputStyle == \"Attention-kind\" and .keep == true" "${HOME}/.claude/settings.json" > /dev/null
    grep -Fq "keep malformed" "${CODEX_HOME}/AGENTS.md"
' || fail 'ubuntu.sh: malformed markers did not produce a safe preflight failure'
rm -rf "${malformed_root}"

# Invalid Claude JSON is unsafe and remains unchanged.
invalid_json_root=$(mktemp -d)
mkdir -p "${invalid_json_root}/home/.claude"
printf '%s\n' '{not-json' > "${invalid_json_root}/home/.claude/settings.json"
SETUP_SCRIPT="${repo_root}/ubuntu.sh" SOURCE_WITHOUT_MAIN="${source_without_main}" TEST_ROOT="${invalid_json_root}" bash -c '
    set -euo pipefail
    export HOME="${TEST_ROOT}/home"
    source <(sed "${SOURCE_WITHOUT_MAIN}" "${SETUP_SCRIPT}")
    if remove_attention_span_resources; then
        exit 90
    fi
    grep -Fq "{not-json" "${HOME}/.claude/settings.json"
' || fail 'ubuntu.sh: invalid Claude JSON was not preserved with strict failure'
rm -rf "${invalid_json_root}"

# A symlinked shared file is unsafe. Cleanup does not follow or remove it.
shared_link_root=$(mktemp -d)
mkdir -p "${shared_link_root}/home/.gemini"
printf '%s\n' 'keep target' > "${shared_link_root}/gemini-target.md"
ln -s "${shared_link_root}/gemini-target.md" "${shared_link_root}/home/.gemini/GEMINI.md"
SETUP_SCRIPT="${repo_root}/ubuntu.sh" SOURCE_WITHOUT_MAIN="${source_without_main}" TEST_ROOT="${shared_link_root}" bash -c '
    set -euo pipefail
    export HOME="${TEST_ROOT}/home"
    source <(sed "${SOURCE_WITHOUT_MAIN}" "${SETUP_SCRIPT}")
    if remove_attention_span_resources; then
        exit 90
    fi
    [[ -L "${HOME}/.gemini/GEMINI.md" ]]
    grep -Fq "keep target" "${TEST_ROOT}/gemini-target.md"
' || fail 'ubuntu.sh: symlinked shared instructions were not preserved with strict failure'
rm -rf "${shared_link_root}"

# A directory at the managed Claude style path fails without recursive deletion.
style_dir_root=$(mktemp -d)
mkdir -p "${style_dir_root}/home/.claude/output-styles/attention-kind.md"
printf '%s\n' keep > "${style_dir_root}/home/.claude/output-styles/attention-kind.md/sentinel"
SETUP_SCRIPT="${repo_root}/ubuntu.sh" SOURCE_WITHOUT_MAIN="${source_without_main}" TEST_ROOT="${style_dir_root}" bash -c '
    set -euo pipefail
    export HOME="${TEST_ROOT}/home"
    source <(sed "${SOURCE_WITHOUT_MAIN}" "${SETUP_SCRIPT}")
    if remove_attention_span_resources; then
        exit 90
    fi
    grep -Fq keep "${HOME}/.claude/output-styles/attention-kind.md/sentinel"
' || fail 'ubuntu.sh: directory at the style path was not preserved with strict failure'
rm -rf "${style_dir_root}"

if command -v pwsh > /dev/null 2>&1; then
    pwsh -NoLogo -NoProfile -File tests/attention-span-removal-powershell.ps1
fi

printf '✓ Attention-kind retirement contract checks passed\n'
