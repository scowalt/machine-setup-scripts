#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "${repo_root}"

bash_setup_scripts=(mac.sh ubuntu.sh wsl.sh pi.sh bazzite.sh)
source_without_main='s/^main "\$@"$/:/'
declare -A expected_versions=(
    [mac.sh]=211
    [ubuntu.sh]=234
    [wsl.sh]=178
    [pi.sh]=193
    [bazzite.sh]=93
)
expected_banner='Manage show-me agent skill'

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

powershell_function_body() {
    local file=$1
    local function_name=$2

    sed -n "/^function ${function_name}/,/^}/p" "${file}"
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

assert_powershell_function_contains() {
    local file=$1
    local function_name=$2
    local pattern=$3
    local description=$4
    local body

    body=$(powershell_function_body "${file}" "${function_name}")
    grep -Eq "${pattern}" <<< "${body}" || fail "${file}: ${function_name} missing ${description}"
}

assert_powershell_function_not_contains() {
    local file=$1
    local function_name=$2
    local pattern=$3
    local description=$4
    local body

    body=$(powershell_function_body "${file}" "${function_name}")
    if grep -Eq "${pattern}" <<< "${body}"; then
        fail "${file}: ${function_name} unexpectedly contains ${description}"
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
    assert_contains "${file}" '^install_managed_agent_skill\(\)' 'reusable managed skill installer'
    assert_contains "${file}" '^setup_simple_english_skill\(\)' 'Simple English installer wrapper'
    assert_contains "${file}" '^setup_show_me_skill\(\)' 'show-me installer wrapper'
    assert_function_contains "${file}" skills_cli_node_runtime_ready 'major > 22.*major === 22 && minor >= 20' 'Node.js 22.20 minimum'
    assert_function_contains "${file}" ensure_skills_cli_node_runtime 'local _runtime="node@24"' 'mise Node.js 24 runtime'
    assert_function_contains "${file}" ensure_skills_cli_node_runtime 'mise use -g -y "\$\{_runtime\}"' 'global mise activation'
    assert_function_contains "${file}" install_managed_agent_skill 'npx --yes skills@latest add "\$\{_repository\}"' 'latest upstream skills CLI install'
    assert_function_contains "${file}" install_managed_agent_skill '^        --global [\\]$' 'global installation flag'
    assert_function_contains "${file}" install_managed_agent_skill '^        --agent claude-code [\\]$' 'Claude Code target'
    assert_function_contains "${file}" install_managed_agent_skill '^        --agent codex [\\]$' 'Codex target'
    assert_function_contains "${file}" install_managed_agent_skill '^        --agent gemini-cli [\\]$' 'Gemini CLI target'
    assert_function_not_contains "${file}" install_managed_agent_skill '^        --agent pi [\\]$' 'redundant direct Pi target'
    assert_function_not_contains "${file}" install_managed_agent_skill 'opencode' 'retired opencode target'
    assert_function_contains "${file}" install_managed_agent_skill '^        --skill "\$\{_skill_name\}" [\\]$' 'specific skill selection'
    assert_function_contains "${file}" install_managed_agent_skill '^        --copy [\\]$' 'copied installation mode'
    assert_function_contains "${file}" install_managed_agent_skill '^        --yes < /dev/null' 'non-interactive confirmation and stdin'
    assert_function_contains "${file}" install_managed_agent_skill 'CLAUDE_CONFIG_DIR:-\$\{HOME\}/\.claude' 'CLAUDE_CONFIG_DIR support'
    assert_function_contains "${file}" install_managed_agent_skill '\$\{HOME\}/\.agents/skills/\$\{_skill_name\}/SKILL\.md' 'canonical shared skill validation'
    assert_function_contains "${file}" install_managed_agent_skill '\[\[ -L "\$\{_skill_dir\}" \|\| -L "\$\{_skill_file\}" \]\]' 'directory and file symlink rejection'
    assert_function_not_contains "${file}" install_managed_agent_skill 'PI_CODING_AGENT_DIR|\.codex/skills|\.gemini/skills' 'obsolete agent-specific installation path'
    assert_function_contains "${file}" setup_simple_english_skill 'install_managed_agent_skill "AminBlg/SimpleEnglish" "simple-english" "Simple English"' 'unchanged Simple English source and name'
    assert_function_contains "${file}" setup_show_me_skill 'install_managed_agent_skill "humanlayer/skills" "show-me" "show-me"' 'HumanLayer show-me source and name'
    assert_function_not_contains "${file}" setup_show_me_skill 'BAN_|WORK_MACHINE|cursor|plugin|output-style' 'show-me opt-out or unrequested target'
    assert_contains "${file}" '^[[:space:]]+(if ! )?setup_simple_english_skill( \|\| return 1|; then)$' 'Simple English main wiring'
    assert_contains "${file}" '^[[:space:]]+(if ! )?setup_show_me_skill( \|\| return 1|; then)$' 'show-me main wiring'
    assert_order "${file}" '^[[:space:]]+if install_pi_cli; then$' '^[[:space:]]+(if ! )?setup_simple_english_skill' 'managed skill installation after agent provisioning'
    assert_order "${file}" '^[[:space:]]+(if ! )?setup_simple_english_skill' '^[[:space:]]+(if ! )?setup_show_me_skill' 'Simple English before show-me'
    assert_order "${file}" '^[[:space:]]+(if ! )?setup_show_me_skill' '^[[:space:]]+(if ! )?configure_pi_skill_ownership' 'show-me validation before Pi ownership'
    assert_order "${file}" '^[[:space:]]+(if ! )?setup_show_me_skill' '^[[:space:]]+remove_impeccable_resources$' 'show-me validation before cleanup'
    assert_function_contains "${file}" configure_pi_skill_ownership 'simple-english show-me setup-matt-pocock-skills' 'show-me canonical shared ownership'
    assert_contains "${file}" "Version ${expected_versions[${file}]} \\| Last changed: ${expected_banner}" 'updated version banner'
done

assert_contains win.ps1 '^function Test-SkillsCliNodeRuntimeReady' 'PowerShell Node.js runtime check'
assert_contains win.ps1 '^function Enable-SkillsCliNodeRuntime' 'PowerShell Node.js runtime setup'
assert_contains win.ps1 '^function Install-ManagedAgentSkill' 'PowerShell reusable managed skill installer'
assert_contains win.ps1 '^function Install-SimpleEnglishSkill' 'PowerShell Simple English wrapper'
assert_contains win.ps1 '^function Install-ShowMeSkill' 'PowerShell show-me wrapper'
assert_powershell_function_contains win.ps1 Install-ManagedAgentSkill '"skills@latest"' 'latest skills CLI package'
for agent in claude-code codex gemini-cli; do
    assert_powershell_function_contains win.ps1 Install-ManagedAgentSkill '"--agent", "'"${agent}"'"' "${agent} target"
done
assert_powershell_function_not_contains win.ps1 Install-ManagedAgentSkill '"--agent", "pi"|opencode' 'redundant or retired target'
assert_powershell_function_contains win.ps1 Install-ManagedAgentSkill '"--global"' 'global installation'
# shellcheck disable=SC2016 # Preserve literal PowerShell variable syntax.
assert_powershell_function_contains win.ps1 Install-ManagedAgentSkill '"--skill", \$SkillName' 'specific skill selection'
assert_powershell_function_contains win.ps1 Install-ManagedAgentSkill '"--copy"' 'copied installation mode'
# shellcheck disable=SC2016 # Preserve literal PowerShell variable syntax.
assert_powershell_function_contains win.ps1 Install-ManagedAgentSkill '\$env:CLAUDE_CONFIG_DIR' 'CLAUDE_CONFIG_DIR support'
# shellcheck disable=SC2016 # Preserve literal PowerShell variable syntax.
assert_powershell_function_contains win.ps1 Install-ManagedAgentSkill '\.agents\\skills\\\$SkillName\\SKILL\.md' 'shared artifact validation'
assert_powershell_function_contains win.ps1 Install-ManagedAgentSkill 'FileAttributes]::ReparsePoint' 'directory and file symlink rejection'
assert_powershell_function_contains win.ps1 Install-ManagedAgentSkill 'Test-Path .*PathType Leaf' 'missing artifact rejection'
assert_powershell_function_contains win.ps1 Install-SimpleEnglishSkill 'AminBlg/SimpleEnglish.*simple-english.*Simple English' 'unchanged Simple English source and name'
assert_powershell_function_contains win.ps1 Install-ShowMeSkill 'humanlayer/skills.*show-me.*show-me' 'HumanLayer show-me source and name'
assert_powershell_function_contains win.ps1 Set-PiSkillOwnership '"simple-english", "show-me"' 'show-me canonical shared ownership'
assert_contains win.ps1 'Required Simple English skill setup failed' 'PowerShell fatal Simple English failure propagation'
assert_contains win.ps1 'Required show-me skill setup failed' 'PowerShell fatal show-me failure propagation'
assert_contains win.ps1 'Version 131 \| Last changed: Manage show-me agent skill' 'PowerShell version banner'
assert_order win.ps1 '^[[:space:]]+if \(Install-PiCli\) \{$' '^[[:space:]]+if \(-not \(Install-SimpleEnglishSkill\)\) \{$' 'PowerShell install after agent provisioning'
assert_order win.ps1 '^[[:space:]]+if \(-not \(Install-SimpleEnglishSkill\)\) \{$' '^[[:space:]]+if \(-not \(Install-ShowMeSkill\)\) \{$' 'PowerShell Simple English before show-me'
assert_order win.ps1 '^[[:space:]]+if \(-not \(Install-ShowMeSkill\)\) \{$' '^[[:space:]]+if \(-not \(Set-PiSkillOwnership\)\) \{$' 'PowerShell show-me before Pi ownership'

# Mock the upstream installer. This proves repeat updates, exact targets, custom
# Claude paths, failure propagation, artifact validation, and copy enforcement.
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
                local argument=""
                local previous=""
                local skill_name=""
                for argument in "$@"; do
                    if [[ "${previous}" == "--skill" ]]; then
                        skill_name=${argument}
                        break
                    fi
                    previous=${argument}
                done
                local skill_file=""
                for skill_file in \
                    "${CLAUDE_CONFIG_DIR}/skills/${skill_name}/SKILL.md" \
                    "${HOME}/.agents/skills/${skill_name}/SKILL.md"; do
                    mkdir -p "$(dirname "${skill_file}")"
                    printf "%s\n" "---" "name: ${skill_name}" "---" > "${skill_file}"
                done
                printf "%s\n" "mock install complete"
            }
            setup_simple_english_skill > /dev/null
            setup_show_me_skill > /dev/null
            setup_simple_english_skill > /dev/null
            setup_show_me_skill > /dev/null
        '

    simple_args='--yes skills@latest add AminBlg/SimpleEnglish --global --agent claude-code --agent codex --agent gemini-cli --skill simple-english --copy --yes'
    show_me_args='--yes skills@latest add humanlayer/skills --global --agent claude-code --agent codex --agent gemini-cli --skill show-me --copy --yes'
    simple_count=$(grep -Fxc -- "${simple_args}" "${test_root}/calls" || true)
    show_me_count=$(grep -Fxc -- "${show_me_args}" "${test_root}/calls" || true)
    [[ "${simple_count}" -eq 2 ]] || fail "${file}: Simple English did not update on both setup runs"
    [[ "${show_me_count}" -eq 2 ]] || fail "${file}: show-me did not update on both setup runs"
    call_count=$(wc -l < "${test_root}/calls")
    [[ "${call_count}" -eq 4 ]] || fail "${file}: installer used unexpected arguments"

    for skill in simple-english show-me; do
        for skill_file in \
            "${claude_home}/skills/${skill}/SKILL.md" \
            "${test_home}/.agents/skills/${skill}/SKILL.md"; do
            [[ -f "${skill_file}" ]] || fail "${file}: missing mocked artifact ${skill_file}"
            [[ ! -L "$(dirname "${skill_file}")" && ! -L "${skill_file}" ]] || fail "${file}: ${skill_file} was installed as a symlink"
        done
        [[ ! -e "${codex_home}/skills/${skill}" ]] || fail "${file}: used custom CODEX_HOME instead of the shared path"
        [[ ! -e "${pi_home}/skills/${skill}" ]] || fail "${file}: created a redundant direct Pi copy"
    done
    [[ -f "${pi_home}/skills/keep-me/SKILL.md" ]] || fail "${file}: custom Pi handling removed a sibling skill"

    failure_root=$(mktemp -d)
    SETUP_SCRIPT="${repo_root}/${file}" SOURCE_WITHOUT_MAIN="${source_without_main}" \
        HOME="${failure_root}/home" CLAUDE_CONFIG_DIR="${failure_root}/claude-home" \
        EMPTY_PATH="${failure_root}/empty-path" CALL_LOG="${failure_root}/calls" bash -c '
            source <(sed "${SOURCE_WITHOUT_MAIN}" "${SETUP_SCRIPT}")
            mkdir -p "${EMPTY_PATH}"
            ensure_skills_cli_node_runtime() { return 0; }

            npx() { return 1; }
            if setup_show_me_skill > /dev/null; then
                exit 91
            fi

            npx() { return 0; }
            if setup_show_me_skill > /dev/null; then
                exit 92
            fi

            mkdir -p "${CLAUDE_CONFIG_DIR}/skills" "${HOME}/.agents/skills/show-me" "${HOME}/directory-link-target"
            printf "show-me\n" > "${HOME}/.agents/skills/show-me/SKILL.md"
            printf "show-me\n" > "${HOME}/directory-link-target/SKILL.md"
            ln -s "${HOME}/directory-link-target" "${CLAUDE_CONFIG_DIR}/skills/show-me"
            if setup_show_me_skill > /dev/null; then
                exit 93
            fi

            rm -rf "${CLAUDE_CONFIG_DIR}/skills/show-me" "${HOME}/.agents/skills/simple-english"
            mkdir -p "${CLAUDE_CONFIG_DIR}/skills/simple-english" "${HOME}/.agents/skills/simple-english"
            printf "simple-english\n" > "${HOME}/simple-english-target.md"
            ln -s "${HOME}/simple-english-target.md" "${CLAUDE_CONFIG_DIR}/skills/simple-english/SKILL.md"
            printf "simple-english\n" > "${HOME}/.agents/skills/simple-english/SKILL.md"
            if setup_simple_english_skill > /dev/null; then
                exit 94
            fi

            ensure_skills_cli_node_runtime() { return 1; }
            npx() { printf "called\n" >> "${CALL_LOG}"; return 0; }
            if setup_show_me_skill > /dev/null; then
                exit 95
            fi
            [[ ! -e "${CALL_LOG}" ]] || exit 96

            ensure_skills_cli_node_runtime() { return 0; }
            unset -f npx
            PATH=${EMPTY_PATH}
            if setup_show_me_skill > /dev/null; then
                exit 97
            fi
        ' || fail "${file}: a required managed skill failure was not propagated"

    rm -rf "${failure_root}" "${test_root}"
done

assert_contains README.md 'Every setup run installs the latest.*Simple English.*HumanLayer.*show-me' 'latest managed skill documentation'
# shellcheck disable=SC2016 # Preserve literal Markdown code spans.
assert_contains README.md 'Simple English and `show-me` are required on personal and work machines and have no setup opt-out' 'required all-machine behavior documentation'
# shellcheck disable=SC2016 # Preserve literal Markdown code spans.
assert_contains CLAUDE.md 'always installs the latest Simple English and HumanLayer `show-me` skills globally' 'repository guidance'
assert_contains CONTEXT.md '^\*\*Managed agent skill\*\*:' 'managed agent skill glossary term'

printf '✓ Managed Simple English and show-me skill contract checks passed\n'
