#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "${repo_root}"

bash_setup_scripts=(mac.sh ubuntu.sh wsl.sh pi.sh bazzite.sh)
source_without_main='s/^main "\$@"$/:/'
declare -A expected_versions=(
    [mac.sh]=207
    [ubuntu.sh]=230
    [wsl.sh]=174
    [pi.sh]=190
    [bazzite.sh]=89
)
declare -A expected_banners=(
    [mac.sh]='Warn at end of setup when a reboot is pending'
    [ubuntu.sh]='Warn at end of setup when a reboot is pending'
    [wsl.sh]='Warn at end of setup when a reboot is pending'
    [pi.sh]='Warn at end of setup when a reboot is pending'
    [bazzite.sh]='Warn at end of setup when a reboot is pending'
)

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

function_body() {
    local file=$1
    local function_name=$2

    sed -n "/^${function_name}()/,/^}/p" "${file}"
}

assert_function_contains() {
    local file=$1
    local function_name=$2
    local pattern=$3
    local description=$4
    local body

    body=$(function_body "${file}" "${function_name}")
    grep -Eq "${pattern}" <<< "${body}" || fail "${file}: ${function_name}() missing ${description}"
}

assert_function_not_contains() {
    local file=$1
    local function_name=$2
    local pattern=$3
    local description=$4
    local body

    body=$(function_body "${file}" "${function_name}")
    if grep -Eq "${pattern}" <<< "${body}"; then
        fail "${file}: ${function_name}() unexpectedly contains ${description}"
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

for file in "${bash_setup_scripts[@]}"; do
    bash -n "${file}"
    assert_contains "${file}" '^skills_cli_node_runtime_ready\(\)' 'skills CLI Node.js runtime check'
    assert_contains "${file}" '^ensure_skills_cli_node_runtime\(\)' 'skills CLI Node.js runtime setup'
    assert_contains "${file}" '^setup_simple_english_skill\(\)' 'Simple English installer function'
    assert_function_contains "${file}" skills_cli_node_runtime_ready 'major > 22.*major === 22 && minor >= 20' 'Node.js 22.20 minimum'
    assert_function_contains "${file}" ensure_skills_cli_node_runtime 'local _runtime="node@24"' 'mise Node.js 24 runtime'
    assert_function_contains "${file}" ensure_skills_cli_node_runtime 'mise use -g -y "\$\{_runtime\}"' 'global mise activation'
    assert_function_contains "${file}" setup_simple_english_skill 'npx --yes skills@latest add AminBlg/SimpleEnglish' 'latest upstream skills CLI install'
    assert_function_contains "${file}" setup_simple_english_skill '^        --global [\\]$' 'global installation flag'
    assert_function_contains "${file}" setup_simple_english_skill '^        --agent claude-code [\\]$' 'Claude Code target'
    assert_function_contains "${file}" setup_simple_english_skill '^        --agent codex [\\]$' 'Codex target'
    assert_function_contains "${file}" setup_simple_english_skill '^        --agent gemini-cli [\\]$' 'Gemini CLI target'
    assert_function_not_contains "${file}" setup_simple_english_skill '^        --agent pi [\\]$' 'redundant direct Pi target'
    if [[ "${file}" != "pi.sh" ]]; then
        assert_function_contains "${file}" setup_simple_english_skill '^        --agent opencode [\\]$' 'opencode target'
        assert_function_contains "${file}" setup_simple_english_skill '\$\{HOME\}/\.config/opencode/skills/simple-english/SKILL\.md' 'opencode skill validation'
    fi
    assert_function_contains "${file}" setup_simple_english_skill '^        --skill simple-english [\\]$' 'specific skill selection'
    assert_function_contains "${file}" setup_simple_english_skill '^        --copy [\\]$' 'copied installation mode'
    assert_function_contains "${file}" setup_simple_english_skill '^        --yes < /dev/null' 'non-interactive confirmation and stdin'
    assert_function_contains "${file}" setup_simple_english_skill 'CLAUDE_CONFIG_DIR:-\$\{HOME\}/\.claude' 'CLAUDE_CONFIG_DIR support'
    assert_function_not_contains "${file}" setup_simple_english_skill 'PI_CODING_AGENT_DIR' 'redundant custom Pi copy'
    assert_function_contains "${file}" setup_simple_english_skill '\$\{HOME\}/\.agents/skills/simple-english/SKILL\.md' 'shared Codex and Gemini skill validation'
    assert_function_contains "${file}" setup_simple_english_skill 'skills/simple-english/SKILL\.md' 'installed artifact validation'
    assert_function_not_contains "${file}" setup_simple_english_skill '\.codex/skills/simple-english|\.gemini/skills/simple-english' 'obsolete agent-specific validation path'
    assert_function_not_contains "${file}" setup_simple_english_skill 'cursor|plugin|output-style|BAN_SIMPLE' 'unrequested target or opt-out'
    assert_contains "${file}" '^[[:space:]]+(if ! )?setup_simple_english_skill' 'Simple English main wiring'
    assert_order "${file}" '^[[:space:]]+if install_pi_cli; then$' '^[[:space:]]+(if ! )?setup_simple_english_skill' 'Simple English installation after agent provisioning'
    assert_order "${file}" '^[[:space:]]+(if ! )?setup_simple_english_skill' '^[[:space:]]+remove_impeccable_resources$' 'Simple English validation before cleanup'
    assert_contains "${file}" "Version ${expected_versions[${file}]} \\| Last changed: ${expected_banners[${file}]}" 'updated version banner'
done

assert_contains win.ps1 '^function Test-SkillsCliNodeRuntimeReady' 'PowerShell Node.js runtime check'
assert_contains win.ps1 '^function Enable-SkillsCliNodeRuntime' 'PowerShell Node.js runtime setup'
assert_contains win.ps1 '^function Install-SimpleEnglishSkill' 'PowerShell Simple English installer'
assert_contains win.ps1 '"skills@latest"' 'PowerShell latest skills CLI package'
assert_contains win.ps1 '"AminBlg/SimpleEnglish"' 'PowerShell upstream skill source'
for agent in claude-code codex gemini-cli; do
    assert_contains win.ps1 '"--agent", "'"${agent}"'"' "PowerShell ${agent} target"
done
assert_contains win.ps1 '"--skill", "simple-english"' 'PowerShell specific skill selection'
assert_contains win.ps1 '"--global"' 'PowerShell global installation'
assert_contains win.ps1 '"--copy"' 'PowerShell copied installation mode'
# shellcheck disable=SC2016 # Preserve literal PowerShell variable syntax.
assert_contains win.ps1 '\$env:CLAUDE_CONFIG_DIR' 'PowerShell CLAUDE_CONFIG_DIR support'
# shellcheck disable=SC2016 # Preserve literal PowerShell variable syntax.
assert_contains win.ps1 '\$env:PI_CODING_AGENT_DIR' 'PowerShell PI_CODING_AGENT_DIR support'
assert_contains win.ps1 '\.agents\\skills\\simple-english\\SKILL\.md' 'PowerShell shared Codex and Gemini skill validation'
assert_contains win.ps1 'Required Simple English skill setup failed' 'PowerShell fatal failure propagation'
assert_contains win.ps1 'Version 128 \| Last changed: Warn at end of setup when a reboot is pending' 'PowerShell version banner'
assert_order win.ps1 '^[[:space:]]+if \(Install-PiCli\) \{$' '^[[:space:]]+if \(-not \(Install-SimpleEnglishSkill\)\) \{$' 'PowerShell install after agent provisioning'
assert_order win.ps1 '^[[:space:]]+if \(-not \(Install-SimpleEnglishSkill\)\) \{$' '^[[:space:]]+Remove-ImpeccableResources$' 'PowerShell validation before cleanup'

# Mock the upstream installer to prove repeatability, all target paths, and custom Pi synchronization.
for file in "${bash_setup_scripts[@]}"; do
    test_root=$(mktemp -d)
    test_home="${test_root}/home"
    claude_home="${test_root}/claude-home"
    codex_home="${test_root}/codex-home"
    pi_home="${test_root}/custom-pi"
    mkdir -p "${pi_home}/skills/keep-me"
    printf '%s\n' keep > "${pi_home}/skills/keep-me/SKILL.md"

    SETUP_SCRIPT="${repo_root}/${file}" SOURCE_WITHOUT_MAIN="${source_without_main}" \
        HOME="${test_home}" CLAUDE_CONFIG_DIR="${claude_home}" CODEX_HOME="${codex_home}" \
        PI_CODING_AGENT_DIR="${pi_home}" CALL_LOG="${test_root}/calls" bash -c '
            source <(sed "${SOURCE_WITHOUT_MAIN}" "${SETUP_SCRIPT}")
            ensure_skills_cli_node_runtime() { return 0; }
            npx() {
                printf "%s\n" "$*" >> "${CALL_LOG}"
                local skill_file
                for skill_file in \
                    "${CLAUDE_CONFIG_DIR}/skills/simple-english/SKILL.md" \
                    "${HOME}/.agents/skills/simple-english/SKILL.md" \
                    "${HOME}/.config/opencode/skills/simple-english/SKILL.md"; do
                    mkdir -p "$(dirname "${skill_file}")"
                    printf "%s\n" "---" "name: simple-english" "---" > "${skill_file}"
                done
                printf "%s\n" "mock install complete"
            }
            setup_simple_english_skill > /dev/null
            setup_simple_english_skill > /dev/null
        '

    call_count=$(wc -l < "${test_root}/calls")
    [[ "${call_count}" -eq 2 ]] || fail "${file}: installer did not update on both setup runs"
    expected_args='--yes skills@latest add AminBlg/SimpleEnglish --global --agent claude-code --agent codex --agent gemini-cli --skill simple-english --copy --yes'
    skill_files=(
        "${claude_home}/skills/simple-english/SKILL.md"
        "${test_home}/.agents/skills/simple-english/SKILL.md"
    )
    if [[ "${file}" != "pi.sh" ]]; then
        expected_args='--yes skills@latest add AminBlg/SimpleEnglish --global --agent claude-code --agent codex --agent gemini-cli --agent opencode --skill simple-english --copy --yes'
        skill_files+=("${test_home}/.config/opencode/skills/simple-english/SKILL.md")
    fi
    if grep -Fvx -- "${expected_args}" "${test_root}/calls" > /dev/null; then
        fail "${file}: installer used unexpected arguments"
    fi
    for skill_file in "${skill_files[@]}"; do
        [[ -f "${skill_file}" ]] || fail "${file}: missing mocked artifact ${skill_file}"
        [[ ! -L "$(dirname "${skill_file}")" ]] || fail "${file}: ${skill_file} was installed as a symlink"
    done
    [[ -f "${pi_home}/skills/keep-me/SKILL.md" ]] || fail "${file}: custom Pi sync removed a sibling skill"

    SETUP_SCRIPT="${repo_root}/${file}" SOURCE_WITHOUT_MAIN="${source_without_main}" \
        HOME="${test_home}" bash -c '
            source <(sed "${SOURCE_WITHOUT_MAIN}" "${SETUP_SCRIPT}")
            ensure_skills_cli_node_runtime() { return 0; }
            npx() { return 1; }
            if setup_simple_english_skill > /dev/null; then
                exit 91
            fi
        ' || fail "${file}: installer failure was not propagated"

    rm -rf "${test_root}"
done

assert_contains README.md 'Every setup run installs the latest.*Simple English' 'latest-release setup documentation'
assert_contains README.md 'Simple English is required on personal and work machines and has no setup opt-out' 'required all-machine behavior documentation'
assert_contains CLAUDE.md 'always installs the latest Simple English skill globally' 'repository guidance'

printf '✓ Simple English skill contract checks passed\n'
