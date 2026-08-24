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
    local file=$1
    local pattern=$2
    local description=$3
    grep -Eq "${pattern}" "${file}" || fail "${file}: missing ${description}"
}

assert_not_contains() {
    local file=$1
    local pattern=$2
    local description=$3
    if grep -Eq "${pattern}" "${file}"; then
        fail "${file}: unexpectedly contains ${description}"
    fi
}

first_line_matching() {
    local file=$1
    local pattern=$2
    grep -nE "${pattern}" "${file}" | head -n 1 | cut -d: -f1 || true
}

assert_order() {
    local file=$1
    local first_pattern=$2
    local second_pattern=$3
    local description=$4
    local first_line
    local second_line

    first_line=$(first_line_matching "${file}" "${first_pattern}")
    second_line=$(first_line_matching "${file}" "${second_pattern}")
    [[ -n "${first_line}" && -n "${second_line}" ]] || fail "${file}: cannot check ${description}"
    [[ "${first_line}" -lt "${second_line}" ]] || fail "${file}: wrong order for ${description}"
}

assert_style_artifact() {
    local file=$1
    grep -Fqx 'name: Attention-kind' "${file}" || fail "${file}: missing Attention-kind name"
    grep -Fqx 'keep-coding-instructions: true' "${file}" || fail "${file}: missing coding-instruction preservation"
    grep -Fq '<!-- attention-span v0.7' "${file}" || fail "${file}: missing reviewed fallback version"
    grep -Fq '## How to protect their attention' "${file}" || fail "${file}: missing expected style body"
}

assert_managed_body() {
    local file=$1
    local begin_count
    local end_count
    begin_count=$(grep -Fxc '<!-- attention-span:start -->' "${file}" || true)
    end_count=$(grep -Fxc '<!-- attention-span:end -->' "${file}" || true)
    [[ ${begin_count} -eq 1 ]] ||
        fail "${file}: expected exactly one begin marker"
    [[ ${end_count} -eq 1 ]] ||
        fail "${file}: expected exactly one end marker"
    grep -Fq '<!-- attention-span v0.7' "${file}" || fail "${file}: missing style body"
    if grep -Fq '<!-- body-start -->' "${file}" || grep -Fq 'name: Attention-kind' "${file}"; then
        fail "${file}: Claude-only frontmatter leaked into managed body"
    fi
}

assert_style_artifact vendor/attention-span/attention-kind.md
grep -Fq 'GNU AFFERO GENERAL PUBLIC LICENSE' vendor/attention-span/LICENSE ||
    fail 'vendored Attention Span license is missing'

declare -A expected_versions=(
    [mac.sh]=196
    [ubuntu.sh]=218
    [wsl.sh]=162
    [pi.sh]=179
    [bazzite.sh]=78
)

for file in "${bash_setup_scripts[@]}"; do
    bash -n "${file}"
    assert_contains "${file}" '^attention_span_style_is_valid\(\)' 'Attention-kind validation'
    assert_contains "${file}" '^attention_span_prepare_file_mode\(\)' 'existing mode preservation'
    assert_contains "${file}" '^attention_span_resolve_style\(\)' 'Attention-kind source resolution'
    assert_contains "${file}" '^setup_attention_span_style\(\)' 'Attention-kind installer'
    assert_contains "${file}" 'raw\.githubusercontent\.com/alexgreensh/attention-span/main/output-styles/attention-kind\.md' 'latest upstream URL'
    assert_contains "${file}" 'scripts\.scowalt\.com/setup/vendor/attention-span/attention-kind\.md' 'hosted fallback URL'
    assert_contains "${file}" 'CLAUDE_CONFIG_DIR:-\$\{HOME\}/\.claude' 'CLAUDE_CONFIG_DIR support'
    assert_contains "${file}" 'CODEX_HOME:-\$\{HOME\}/\.codex' 'CODEX_HOME support'
    assert_contains "${file}" 'PI_CODING_AGENT_DIR:-\$\{HOME\}/\.pi/agent' 'PI_CODING_AGENT_DIR support'
    assert_contains "${file}" 'output-styles/attention-kind\.md' 'Claude output-style target'
    assert_contains "${file}" '\.outputStyle = "Attention-kind"' 'Claude style activation'
    assert_contains "${file}" '\.gemini/GEMINI\.md' 'Gemini global context target'
    assert_contains "${file}" 'APPEND_SYSTEM\.md' 'Pi append-system target'
    assert_contains "${file}" '<!-- attention-span:start -->' 'managed begin marker'
    assert_contains "${file}" '<!-- attention-span:end -->' 'managed end marker'
    assert_contains "${file}" '^[[:space:]]+(if ! )?setup_attention_span_style' 'required setup wiring'
    assert_order "${file}" '^[[:space:]]+(if ! )?setup_attention_span_style' '^[[:space:]]+(if ! )?setup_simple_english_skill' 'Attention-kind before Simple English'
    assert_contains "${file}" "Version ${expected_versions[${file}]} \\| Last changed: Fix Simple English shared skill validation" 'updated version banner'
    assert_not_contains "${file}" 'BAN_ATTENTION' 'Attention-kind opt-out'
done

assert_contains win.ps1 '^function Test-AttentionSpanStyleFile' 'PowerShell style validation'
assert_contains win.ps1 '^function Resolve-AttentionSpanStyle' 'PowerShell source resolution'
assert_contains win.ps1 '^function Install-AttentionSpanStyle' 'PowerShell installer'
# shellcheck disable=SC2016
assert_contains win.ps1 '\$env:CLAUDE_CONFIG_DIR' 'PowerShell CLAUDE_CONFIG_DIR support'
# shellcheck disable=SC2016
assert_contains win.ps1 '\$env:CODEX_HOME' 'PowerShell CODEX_HOME support'
# shellcheck disable=SC2016
assert_contains win.ps1 '\$env:PI_CODING_AGENT_DIR' 'PowerShell PI_CODING_AGENT_DIR support'
assert_contains win.ps1 'output-styles.*attention-kind\.md' 'PowerShell Claude output-style target'
assert_contains win.ps1 'outputStyle.*Attention-kind' 'PowerShell Claude style activation'
assert_contains win.ps1 '\.gemini.*GEMINI\.md' 'PowerShell Gemini context target'
assert_contains win.ps1 'APPEND_SYSTEM\.md' 'PowerShell Pi target'
assert_contains win.ps1 'Required Attention-kind setup failed' 'PowerShell required failure'
assert_contains win.ps1 'Version 118 \| Last changed: Fix Simple English shared skill validation' 'PowerShell version banner'
assert_order win.ps1 '^[[:space:]]+if \(-not \(Install-AttentionSpanStyle\)\) \{$' '^[[:space:]]+if \(-not \(Install-SimpleEnglishSkill\)\) \{$' 'PowerShell Attention-kind before Simple English'
assert_not_contains win.ps1 'BAN_ATTENTION' 'PowerShell Attention-kind opt-out'

# Exercise repeatable installation, custom locations, content preservation, and installed fallback.
for file in "${bash_setup_scripts[@]}"; do
    test_root=$(mktemp -d)
    test_home="${test_root}/home"
    claude_home="${test_root}/claude"
    codex_home="${test_root}/codex"
    pi_home="${test_root}/pi"
    mkdir -p "${claude_home}" "${codex_home}" "${test_home}/.gemini" "${pi_home}"
    printf '%s\n' '{"keep":"claude"}' > "${claude_home}/settings.json"
    printf '%s\n' 'keep codex' > "${codex_home}/AGENTS.md"
    printf '%s\n' 'keep gemini' > "${test_home}/.gemini/GEMINI.md"
    printf '%s\n' 'keep pi' > "${pi_home}/APPEND_SYSTEM.md"
    chmod 640 "${claude_home}/settings.json" "${codex_home}/AGENTS.md"

    SETUP_SCRIPT="${repo_root}/${file}" SOURCE_WITHOUT_MAIN="${source_without_main}" \
        ATTENTION_SOURCE="${repo_root}/vendor/attention-span/attention-kind.md" \
        HOME="${test_home}" CLAUDE_CONFIG_DIR="${claude_home}" CODEX_HOME="${codex_home}" \
        PI_CODING_AGENT_DIR="${pi_home}" bash -c '
            source <(sed "${SOURCE_WITHOUT_MAIN}" "${SETUP_SCRIPT}")
            curl() {
                local output=""
                while [[ "$#" -gt 0 ]]; do
                    case "$1" in
                        -o) output=$2; shift 2 ;;
                        *) shift ;;
                    esac
                done
                [[ -n "${output}" ]] || return 1
                cp "${ATTENTION_SOURCE}" "${output}"
            }
            setup_attention_span_style > /dev/null
            setup_attention_span_style > /dev/null
            curl() { return 1; }
            setup_attention_span_style > /dev/null
        '

    assert_style_artifact "${claude_home}/output-styles/attention-kind.md"
    [[ $(jq -r '.outputStyle' "${claude_home}/settings.json" || true) == "Attention-kind" ]] ||
        fail "${file}: Claude outputStyle was not activated"
    [[ $(jq -r '.keep' "${claude_home}/settings.json" || true) == "claude" ]] ||
        fail "${file}: Claude settings were not preserved"
    [[ $(stat -c '%a' "${claude_home}/settings.json" || true) == 640 ]] ||
        fail "${file}: Claude settings mode was not preserved"
    [[ $(stat -c '%a' "${codex_home}/AGENTS.md" || true) == 640 ]] ||
        fail "${file}: Codex instructions mode was not preserved"
    for managed_file in "${codex_home}/AGENTS.md" "${test_home}/.gemini/GEMINI.md" "${pi_home}/APPEND_SYSTEM.md"; do
        assert_managed_body "${managed_file}"
    done
    grep -Fq 'keep codex' "${codex_home}/AGENTS.md" || fail "${file}: Codex content was lost"
    grep -Fq 'keep gemini' "${test_home}/.gemini/GEMINI.md" || fail "${file}: Gemini content was lost"
    grep -Fq 'keep pi' "${pi_home}/APPEND_SYSTEM.md" || fail "${file}: Pi content was lost"

    rm -rf "${test_root}"
done

# Reject malformed markers before changing any target.
for file in "${bash_setup_scripts[@]}"; do
    test_root=$(mktemp -d)
    test_home="${test_root}/home"
    claude_home="${test_root}/claude"
    codex_home="${test_root}/codex"
    pi_home="${test_root}/pi"
    mkdir -p "${claude_home}" "${codex_home}" "${test_home}/.gemini" "${pi_home}"
    printf '%s\n' '<!-- attention-span:start -->' 'keep malformed' > "${codex_home}/AGENTS.md"
    before_hash=$(sha256sum "${codex_home}/AGENTS.md" | awk '{print $1}')

    SETUP_SCRIPT="${repo_root}/${file}" SOURCE_WITHOUT_MAIN="${source_without_main}" \
        ATTENTION_SOURCE="${repo_root}/vendor/attention-span/attention-kind.md" \
        HOME="${test_home}" CLAUDE_CONFIG_DIR="${claude_home}" CODEX_HOME="${codex_home}" \
        PI_CODING_AGENT_DIR="${pi_home}" bash -c '
            source <(sed "${SOURCE_WITHOUT_MAIN}" "${SETUP_SCRIPT}")
            curl() {
                local output=""
                while [[ "$#" -gt 0 ]]; do
                    case "$1" in
                        -o) output=$2; shift 2 ;;
                        *) shift ;;
                    esac
                done
                cp "${ATTENTION_SOURCE}" "${output}"
            }
            if setup_attention_span_style > /dev/null; then
                exit 91
            fi
        '
    after_hash=$(sha256sum "${codex_home}/AGENTS.md" | awk '{print $1}')
    [[ "${before_hash}" == "${after_hash}" ]] || fail "${file}: malformed file changed"
    [[ ! -e "${claude_home}/output-styles/attention-kind.md" ]] ||
        fail "${file}: another target changed before malformed-marker failure"
    rm -rf "${test_root}"
done

# Reject invalid Claude JSON without overwriting it.
test_root=$(mktemp -d)
mkdir -p "${test_root}/claude"
printf '%s\n' '{not-json' > "${test_root}/claude/settings.json"
before_hash=$(sha256sum "${test_root}/claude/settings.json" | awk '{print $1}')
SETUP_SCRIPT="${repo_root}/mac.sh" SOURCE_WITHOUT_MAIN="${source_without_main}" \
    ATTENTION_SOURCE="${repo_root}/vendor/attention-span/attention-kind.md" \
    HOME="${test_root}/home" CLAUDE_CONFIG_DIR="${test_root}/claude" \
    CODEX_HOME="${test_root}/codex" PI_CODING_AGENT_DIR="${test_root}/pi" bash -c '
        source <(sed "${SOURCE_WITHOUT_MAIN}" "${SETUP_SCRIPT}")
        curl() {
            local output=""
            while [[ "$#" -gt 0 ]]; do
                case "$1" in
                    -o) output=$2; shift 2 ;;
                    *) shift ;;
                esac
            done
            cp "${ATTENTION_SOURCE}" "${output}"
        }
        if setup_attention_span_style > /dev/null; then
            exit 91
        fi
    '
after_hash=$(sha256sum "${test_root}/claude/settings.json" | awk '{print $1}')
[[ "${before_hash}" == "${after_hash}" ]] || fail 'invalid Claude JSON was overwritten'
rm -rf "${test_root}"

# Reject an invalid latest download and use the local reviewed fallback.
test_root=$(mktemp -d)
mkdir -p "${test_root}/vendor/attention-span"
sed "${source_without_main}" mac.sh > "${test_root}/setup.sh"
cp vendor/attention-span/attention-kind.md "${test_root}/vendor/attention-span/attention-kind.md"
printf '%s\n' 'invalid latest response' > "${test_root}/invalid.md"
HOME="${test_root}/home" CLAUDE_CONFIG_DIR="${test_root}/claude" CODEX_HOME="${test_root}/codex" \
    PI_CODING_AGENT_DIR="${test_root}/pi" LOCAL_SCRIPT="${test_root}/setup.sh" \
    INVALID_STYLE="${test_root}/invalid.md" bash -c '
        source "${LOCAL_SCRIPT}"
        curl() {
            local output=""
            while [[ "$#" -gt 0 ]]; do
                case "$1" in
                    -o) output=$2; shift 2 ;;
                    *) shift ;;
                esac
            done
            cp "${INVALID_STYLE}" "${output}"
        }
        setup_attention_span_style > /dev/null
    '
assert_style_artifact "${test_root}/claude/output-styles/attention-kind.md"
rm -rf "${test_root}"

# Fail when latest, installed, local, and hosted sources are all unavailable.
test_root=$(mktemp -d)
SETUP_SCRIPT="${repo_root}/mac.sh" SOURCE_WITHOUT_MAIN="${source_without_main}" \
    HOME="${test_root}/home" CLAUDE_CONFIG_DIR="${test_root}/claude" \
    CODEX_HOME="${test_root}/codex" PI_CODING_AGENT_DIR="${test_root}/pi" bash -c '
        source <(sed "${SOURCE_WITHOUT_MAIN}" "${SETUP_SCRIPT}")
        curl() { return 1; }
        if setup_attention_span_style > /dev/null; then
            exit 91
        fi
    '
rm -rf "${test_root}"

if command -v pwsh > /dev/null 2>&1; then
    pwsh -NoLogo -NoProfile -File tests/attention-span-output-style-powershell.ps1
fi

printf '✓ Attention-kind output-style contract checks passed\n'
