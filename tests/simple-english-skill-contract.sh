#!/usr/bin/env bash
# Contract version 19: verify legacy PID retirement version banners.
# Historical filename retained for existing test runners.
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "${repo_root}"

bash_setup_scripts=(mac.sh ubuntu.sh wsl.sh pi.sh bazzite.sh)
source_without_main='s/^main "\$@"$/:/'
declare -A expected_versions=(
    [mac.sh]=237
    [ubuntu.sh]=259
    [wsl.sh]=201
    [pi.sh]=218
    [bazzite.sh]=118
)
declare -A expected_banners=(
    [mac.sh]='Handle legacy PID permissions during Plain retirement'
    [ubuntu.sh]='Handle legacy PID permissions during Plain retirement'
    [wsl.sh]='Handle legacy PID permissions during Plain retirement'
    [pi.sh]='Handle legacy PID permissions during Plain retirement'
    [bazzite.sh]='Handle legacy PID permissions during Plain retirement'
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
    assert_contains "${file}" '^remove_simple_english_skill\(\)' 'Simple English removal wrapper'
    assert_contains "${file}" '^remove_show_me_skill\(\)' 'show-me removal wrapper'
    assert_function_contains "${file}" skills_cli_node_runtime_ready 'shared_node_runtime_ready' 'shared readiness check'
    assert_function_contains "${file}" shared_node_runtime_ready 'major > 22.*major === 22 && minor >= 20' 'Node.js 22.20 minimum'
    assert_function_contains "${file}" ensure_skills_cli_node_runtime 'ensure_shared_node_runtime' 'durable shared runtime selection'
    assert_function_contains "${file}" ensure_shared_node_runtime 'mise use -g -y -C "\$\{HOME\}" "\$\{_runtime\}"' 'global mise selection'
    assert_function_contains "${file}" shared_node_fallback 'node@22' 'official ARMv7 fallback'
    assert_function_contains "${file}" shared_node_fallback 'node@24' 'supported Node.js 24 fallback'
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
    assert_function_contains "${file}" install_managed_agent_skill '\$\{HOME\}/\.agents/skills/\$\{_skill_name\}' 'canonical shared skill validation'
    assert_function_contains "${file}" install_managed_agent_skill '\[\[ -L "\$\{_artifact_path\}" \]\]' 'directory and file symlink rejection'
    assert_function_not_contains "${file}" install_managed_agent_skill 'PI_CODING_AGENT_DIR|\.codex/skills|\.gemini/skills' 'obsolete agent-specific installation path'
    assert_function_contains "${file}" remove_simple_english_skill 'matt_pocock_skill_policy remove-simple-english' 'Simple English retirement'
    assert_function_contains "${file}" remove_show_me_skill 'matt_pocock_skill_policy remove-show-me' 'show-me retirement'
    assert_function_not_contains "${file}" remove_show_me_skill 'BAN_|WORK_MACHINE|cursor|plugin|output-style' 'show-me opt-out or unrequested target'
    assert_contains "${file}" '^[[:space:]]+(if ! )?remove_simple_english_skill( \|\| _setup_had_errors=1|; then)$' 'Simple English removal main wiring'
    assert_contains "${file}" '^[[:space:]]+(if ! )?remove_show_me_skill( \|\| _setup_had_errors=1|; then)$' 'show-me main wiring'
    assert_order "${file}" '^[[:space:]]+elif install_pi_cli; then$' '^[[:space:]]+(if ! )?remove_simple_english_skill' 'managed skill installation after agent provisioning'
    assert_order "${file}" '^[[:space:]]+(if ! )?remove_simple_english_skill' '^[[:space:]]+(if ! )?remove_show_me_skill' 'Simple English before show-me'
    assert_order "${file}" '^[[:space:]]+(if ! )?remove_show_me_skill' '^[[:space:]]+(if ! )?configure_pi_skill_ownership' 'show-me removal before Pi ownership'
    assert_order "${file}" '^[[:space:]]+(if ! )?remove_show_me_skill' '^[[:space:]]+remove_impeccable_resources$' 'show-me removal before cleanup'
    assert_function_contains "${file}" configure_pi_skill_ownership 'matt_pocock_skill_policy ownership' 'shared ownership policy'
    assert_function_contains "${file}" remove_pr_lens_skill 'matt_pocock_skill_policy remove-pr-lens' 'PR Lens retirement'
    for shared_function in install_managed_agent_skill remove_simple_english_skill remove_show_me_skill remove_pr_lens_skill configure_pi_skill_ownership; do
        shared_body=$(function_body "${file}" "${shared_function}")
        canonical_body=$(function_body mac.sh "${shared_function}")
        [[ "${shared_body}" == "${canonical_body}" ]] || fail "${file}: ${shared_function} drifted from the shared Bash implementation"
    done
    assert_contains "${file}" "Version ${expected_versions[${file}]} \\| Last changed: ${expected_banners[${file}]}" 'updated version banner'
done

assert_contains win.ps1 '^function Test-SkillsCliNodeRuntimeReady' 'PowerShell Node.js runtime check'
assert_contains win.ps1 '^function Enable-SkillsCliNodeRuntime' 'PowerShell Node.js runtime setup'
assert_contains win.ps1 '^function Install-ManagedAgentSkill' 'PowerShell reusable managed skill installer'
assert_contains win.ps1 '^function Remove-SimpleEnglishSkill' 'PowerShell Simple English wrapper'
assert_contains win.ps1 '^function Remove-ShowMeSkill' 'PowerShell show-me wrapper'
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
assert_powershell_function_contains win.ps1 Install-ManagedAgentSkill '\.agents\\skills\\\$SkillName' 'shared artifact validation'
assert_powershell_function_contains win.ps1 Install-ManagedAgentSkill 'FileAttributes]::ReparsePoint' 'directory and file symlink rejection'
assert_powershell_function_contains win.ps1 Install-ManagedAgentSkill 'FileInfo.*Length -le 0' 'missing, empty, and non-regular artifact rejection'
assert_powershell_function_contains win.ps1 Remove-SimpleEnglishSkill 'Invoke-MattPocockSkillPolicy -Mode remove-simple-english' 'Simple English retirement'
assert_powershell_function_contains win.ps1 Remove-ShowMeSkill 'Invoke-MattPocockSkillPolicy -Mode remove-show-me' 'show-me retirement'
assert_powershell_function_contains win.ps1 Set-PiSkillOwnership 'Invoke-MattPocockSkillPolicy -Mode ownership' 'shared ownership policy'
assert_contains win.ps1 'Required Simple English skill removal failed' 'PowerShell fatal Simple English failure propagation'
assert_contains win.ps1 'Required show-me skill removal failed' 'PowerShell fatal show-me failure propagation'
assert_contains win.ps1 'Version 154 \| Last changed: Handle legacy PID permissions during Plain retirement' 'PowerShell version banner'
assert_powershell_function_contains win.ps1 Remove-PrLensSkill 'Invoke-MattPocockSkillPolicy -Mode remove-pr-lens' 'PR Lens retirement'
assert_contains win.ps1 'Required PR Lens skill removal failed' 'PowerShell fatal PR Lens failure propagation'
assert_order win.ps1 '^[[:space:]]+elseif \(Install-PiCli\) \{$' '^[[:space:]]+if \(-not \(Remove-SimpleEnglishSkill\)\) \{$' 'PowerShell install after agent provisioning'
assert_order win.ps1 '^[[:space:]]+if \(-not \(Remove-SimpleEnglishSkill\)\) \{$' '^[[:space:]]+if \(-not \(Remove-ShowMeSkill\)\) \{$' 'PowerShell Simple English before show-me'
assert_order win.ps1 '^[[:space:]]+if \(-not \(Remove-ShowMeSkill\)\) \{$' '^[[:space:]]+if \(-not \(Set-PiSkillOwnership\)\) \{$' 'PowerShell show-me before Pi ownership'

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
                local skill_dir=""
                local relative_file=""
                local -a required_files=(SKILL.md)
                for skill_dir in \
                    "${CLAUDE_CONFIG_DIR}/skills/${skill_name}" \
                    "${HOME}/.agents/skills/${skill_name}"; do
                    for relative_file in "${required_files[@]}"; do
                        mkdir -p "$(dirname "${skill_dir}/${relative_file}")"
                        printf "%s\n" "mock ${skill_name} ${relative_file}" > "${skill_dir}/${relative_file}"
                    done
                done
                printf "%s\n" "mock install complete"
            }
            for WORK_MACHINE in 0 1; do
                export WORK_MACHINE
                install_managed_agent_skill example/fixture tdd "Copy fixture" > /dev/null || exit 1
            done
        '

    copy_fixture_args='--yes skills@latest add example/fixture --global --agent claude-code --agent codex --agent gemini-cli --skill tdd --copy --yes'
    copy_fixture_count=$(grep -Fxc -- "${copy_fixture_args}" "${test_root}/calls" || true)
    [[ "${copy_fixture_count}" -eq 2 ]] || fail "${file}: tdd did not update on both setup runs"
    call_count=$(wc -l < "${test_root}/calls")
    [[ "${call_count}" -eq 2 ]] || fail "${file}: installer used unexpected arguments"

    for skill_file in \
        "${claude_home}/skills/tdd/SKILL.md" \
        "${test_home}/.agents/skills/tdd/SKILL.md"; do
        [[ -f "${skill_file}" ]] || fail "${file}: missing mocked artifact ${skill_file}"
        [[ ! -L "$(dirname "${skill_file}")" && ! -L "${skill_file}" ]] || fail "${file}: ${skill_file} was installed as a symlink"
    done
    [[ ! -e "${codex_home}/skills/tdd" ]] || fail "${file}: used custom CODEX_HOME instead of the shared path"
    [[ ! -e "${pi_home}/skills/tdd" ]] || fail "${file}: created a redundant direct Pi copy"
    [[ -f "${pi_home}/skills/keep-me/SKILL.md" ]] || fail "${file}: custom Pi handling removed a sibling skill"

    failure_root=$(mktemp -d)
    SETUP_SCRIPT="${repo_root}/${file}" SOURCE_WITHOUT_MAIN="${source_without_main}" \
        HOME="${failure_root}/home" CLAUDE_CONFIG_DIR="${failure_root}/claude-home" \
        EMPTY_PATH="${failure_root}/empty-path" CALL_LOG="${failure_root}/calls" bash -c '
            source <(sed "${SOURCE_WITHOUT_MAIN}" "${SETUP_SCRIPT}")
            mkdir -p "${EMPTY_PATH}"
            ensure_skills_cli_node_runtime() { return 0; }

            npx() { return 1; }
            if install_managed_agent_skill example/fixture tdd "Copy fixture" > /dev/null; then
                exit 91
            fi

            npx() { return 0; }
            if install_managed_agent_skill example/fixture tdd "Copy fixture" > /dev/null; then
                exit 92
            fi

            mkdir -p "${CLAUDE_CONFIG_DIR}/skills" "${HOME}/.agents/skills/tdd" "${HOME}/directory-link-target"
            printf "tdd\n" > "${HOME}/.agents/skills/tdd/SKILL.md"
            printf "tdd\n" > "${HOME}/directory-link-target/SKILL.md"
            ln -s "${HOME}/directory-link-target" "${CLAUDE_CONFIG_DIR}/skills/tdd"
            if install_managed_agent_skill example/fixture tdd "Copy fixture" > /dev/null; then
                exit 93
            fi

            rm -rf "${CLAUDE_CONFIG_DIR}/skills/tdd" "${HOME}/.agents/skills/tdd"
            mkdir -p "${CLAUDE_CONFIG_DIR}/skills/tdd" "${HOME}/.agents/skills/tdd"
            printf "tdd\n" > "${HOME}/tdd-target.md"
            ln -s "${HOME}/tdd-target.md" "${CLAUDE_CONFIG_DIR}/skills/tdd/SKILL.md"
            printf "tdd\n" > "${HOME}/.agents/skills/tdd/SKILL.md"
            if install_managed_agent_skill example/fixture tdd "Copy fixture" > /dev/null; then
                exit 94
            fi

            ensure_skills_cli_node_runtime() { return 1; }
            npx() { printf "called\n" >> "${CALL_LOG}"; return 0; }
            if install_managed_agent_skill example/fixture tdd "Copy fixture" > /dev/null; then
                exit 95
            fi
            [[ ! -e "${CALL_LOG}" ]] || exit 96

            ensure_skills_cli_node_runtime() { return 0; }
            unset -f npx
            PATH=${EMPTY_PATH}
            if install_managed_agent_skill example/fixture tdd "Copy fixture" > /dev/null; then
                exit 97
            fi
        ' || fail "${file}: a required managed skill failure was not propagated"

    SETUP_SCRIPT="${repo_root}/${file}" SOURCE_WITHOUT_MAIN="${source_without_main}" \
        HOME="${failure_root}/reference-fixture-home" CLAUDE_CONFIG_DIR="${failure_root}/custom claude" bash -c '
            source <(sed "${SOURCE_WITHOUT_MAIN}" "${SETUP_SCRIPT}")
            setup_reference_fixture_skill() {
                install_managed_agent_skill example/fixture reference-fixture "Reference fixture" \
                    LICENSE references/graph-document.md references/config.md references/example.graph.json
            }
            ensure_skills_cli_node_runtime() { return 0; }
            npx() { return 0; }
            required_files=(SKILL.md LICENSE references/graph-document.md references/config.md references/example.graph.json)
            fixture="${HOME}/fixture"
            for relative_file in "${required_files[@]}"; do
                mkdir -p "$(dirname "${fixture}/${relative_file}")"
                printf "fixture %s\n" "${relative_file}" > "${fixture}/${relative_file}"
            done
            for claude_mode in custom default; do
                [[ "${claude_mode}" == custom ]] || unset CLAUDE_CONFIG_DIR
                skill_dirs=("${CLAUDE_CONFIG_DIR:-${HOME}/.claude}/skills/reference-fixture" "${HOME}/.agents/skills/reference-fixture")
                reset_copies() {
                    local dir=""
                    for dir in "${skill_dirs[@]}"; do
                        rm -rf "${dir}"
                        mkdir -p "$(dirname "${dir}")"
                        cp -R "${fixture}" "${dir}"
                    done
                }
                expect_failure() {
                    local output=""
                    if output=$(setup_reference_fixture_skill); then
                        printf "Accepted invalid Reference fixture artifact: %s\n" "$*" >&2
                        exit 1
                    fi
                    [[ "${output}" == *"Reference fixture validation failed:"* ]] || exit 2
                }
                reset_copies
                setup_reference_fixture_skill > /dev/null || exit 3
                for dir in "${skill_dirs[@]}"; do
                    diff -qr "${fixture}" "${dir}" || exit 4
                    for relative_file in "${required_files[@]}"; do
                        for defect in missing empty directory symlink dangling; do
                            reset_copies
                            artifact="${dir}/${relative_file}"
                            rm "${artifact}"
                            case "${defect}" in
                                missing) : ;;
                                empty) : > "${artifact}" ;;
                                directory) mkdir "${artifact}" ;;
                                symlink) ln -s "${fixture}/${relative_file}" "${artifact}" ;;
                                dangling) ln -s "${fixture}/not-present" "${artifact}" ;;
                            esac
                            expect_failure "${artifact}: ${defect}"
                        done
                    done
                    for relative_dir in . references; do
                        reset_copies
                        artifact=${dir}
                        target=${fixture}
                        if [[ "${relative_dir}" == references ]]; then
                            artifact="${dir}/references"
                            target="${fixture}/references"
                        fi
                        rm -rf "${artifact}"
                        ln -s "${target}" "${artifact}"
                        expect_failure "${artifact}: linked directory"
                    done
                done
                reset_copies
                npx() { return 1; }
                if setup_reference_fixture_skill > /dev/null; then exit 5; fi
                ensure_skills_cli_node_runtime() { return 1; }
                npx() { printf "unexpected call\n" > "${HOME}/unexpected-call"; }
                if setup_reference_fixture_skill > /dev/null; then exit 6; fi
                [[ ! -e "${HOME}/unexpected-call" ]] || exit 7
                ensure_skills_cli_node_runtime() { return 0; }
                unset -f npx
                saved_path=${PATH}
                PATH="${HOME}/empty-path"
                if setup_reference_fixture_skill > /dev/null; then exit 8; fi
                PATH=${saved_path}
                npx() { return 0; }
            done
        ' || fail "${file}: Reference fixture complete-file validation failed"

    rm -rf "${failure_root}" "${test_root}"
done

assert_contains README.md 'Setup installs the full.*Matt Pocock skill suite' 'managed skill documentation'
assert_contains README.md 'Removal applies to personal and work machines and has no opt-out' 'retired skill all-machine behavior'
assert_contains CLAUDE.md 'full Matt Pocock suite is the managed global skill suite' 'repository guidance'
assert_contains CONTEXT.md '^\*\*Managed agent skill\*\*:' 'managed agent skill glossary term'

assert_contains README.md 'Setup removes PR Lens, Simple English, and HumanLayer' 'all retired skills documented'
assert_contains README.md 'next setup run' 'next-run rollout'
printf '✓ Managed and retired-skill contract checks passed\n'
