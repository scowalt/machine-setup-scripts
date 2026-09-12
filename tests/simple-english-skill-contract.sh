#!/usr/bin/env bash
# Contract version 8: preserve shared Node coverage with the Pi prose retirement banners.
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "${repo_root}"

bash_setup_scripts=(mac.sh ubuntu.sh wsl.sh pi.sh bazzite.sh)
source_without_main='s/^main "\$@"$/:/'
declare -A expected_versions=(
    [mac.sh]=226
    [ubuntu.sh]=248
    [wsl.sh]=190
    [pi.sh]=207
    [bazzite.sh]=107
)
declare -A expected_banners=(
    [mac.sh]='Retire pi-prose from global Pi profiles'
    [ubuntu.sh]='Retire pi-prose from global Pi profiles'
    [wsl.sh]='Retire pi-prose from global Pi profiles'
    [pi.sh]='Retire pi-prose from global Pi profiles'
    [bazzite.sh]='Retire pi-prose from global Pi profiles'
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
    assert_contains "${file}" '^setup_simple_english_skill\(\)' 'Simple English installer wrapper'
    assert_contains "${file}" '^setup_show_me_skill\(\)' 'show-me installer wrapper'
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
    assert_function_contains "${file}" setup_simple_english_skill 'install_managed_agent_skill "AminBlg/SimpleEnglish" "simple-english" "Simple English"' 'unchanged Simple English source and name'
    assert_function_contains "${file}" setup_show_me_skill 'install_managed_agent_skill "humanlayer/skills" "show-me" "show-me"' 'HumanLayer show-me source and name'
    assert_function_not_contains "${file}" setup_show_me_skill 'BAN_|WORK_MACHINE|cursor|plugin|output-style' 'show-me opt-out or unrequested target'
    assert_contains "${file}" '^[[:space:]]+(if ! )?setup_simple_english_skill( \|\| return 1|; then)$' 'Simple English main wiring'
    assert_contains "${file}" '^[[:space:]]+(if ! )?setup_show_me_skill( \|\| return 1|; then)$' 'show-me main wiring'
    assert_order "${file}" '^[[:space:]]+if install_pi_cli; then$' '^[[:space:]]+(if ! )?setup_simple_english_skill' 'managed skill installation after agent provisioning'
    assert_order "${file}" '^[[:space:]]+(if ! )?setup_simple_english_skill' '^[[:space:]]+(if ! )?setup_show_me_skill' 'Simple English before show-me'
    assert_order "${file}" '^[[:space:]]+(if ! )?setup_show_me_skill' '^[[:space:]]+(if ! )?configure_pi_skill_ownership' 'show-me validation before Pi ownership'
    assert_order "${file}" '^[[:space:]]+(if ! )?setup_show_me_skill' '^[[:space:]]+remove_impeccable_resources$' 'show-me validation before cleanup'
    assert_function_contains "${file}" configure_pi_skill_ownership 'simple-english show-me pr-lens setup-matt-pocock-skills' 'canonical shared ownership'
    assert_function_contains "${file}" setup_pr_lens_skill 'install_managed_agent_skill "coldteadotai/pr-lens" "pr-lens" "PR Lens"' 'PR Lens source and specific skill'
    assert_function_not_contains "${file}" setup_pr_lens_skill 'BAN_|WORK_MACHINE|cursor|plugin|output-style|canvas|npx' 'PR Lens opt-out, policy, or runtime workflow'
    for artifact in LICENSE references/graph-document.md references/config.md references/example.graph.json; do
        assert_function_contains "${file}" setup_pr_lens_skill "\"${artifact}\"" 'complete PR Lens footprint'
    done
    assert_contains "${file}" '^[[:space:]]+(if ! )?setup_pr_lens_skill( \|\| return 1|; then)$' 'required PR Lens main wiring'
    assert_order "${file}" '^[[:space:]]+(if ! )?setup_show_me_skill' '^[[:space:]]+(if ! )?setup_pr_lens_skill' 'PR Lens after other managed skills'
    assert_order "${file}" '^[[:space:]]+(if ! )?setup_pr_lens_skill' '^[[:space:]]+(if ! )?configure_pi_skill_ownership' 'PR Lens before ownership cleanup'
    if [[ "${file}" != bazzite.sh ]]; then
        setup_body=$(function_body "${file}" run_setup_tasks)
        [[ "${setup_body}" == *$'if ! setup_pr_lens_skill; then\n        _setup_had_errors=1\n    fi'* ]] || fail "${file}: PR Lens failure is not recorded by setup"
    fi
    for shared_function in install_managed_agent_skill setup_pr_lens_skill configure_pi_skill_ownership; do
        shared_body=$(function_body "${file}" "${shared_function}")
        canonical_body=$(function_body mac.sh "${shared_function}")
        [[ "${shared_body}" == "${canonical_body}" ]] || fail "${file}: ${shared_function} drifted from the shared Bash implementation"
    done
    assert_contains "${file}" "Version ${expected_versions[${file}]} \\| Last changed: ${expected_banners[${file}]}" 'updated version banner'
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
assert_powershell_function_contains win.ps1 Install-ManagedAgentSkill '\.agents\\skills\\\$SkillName' 'shared artifact validation'
assert_powershell_function_contains win.ps1 Install-ManagedAgentSkill 'FileAttributes]::ReparsePoint' 'directory and file symlink rejection'
assert_powershell_function_contains win.ps1 Install-ManagedAgentSkill 'FileInfo.*Length -le 0' 'missing, empty, and non-regular artifact rejection'
assert_powershell_function_contains win.ps1 Install-SimpleEnglishSkill 'AminBlg/SimpleEnglish.*simple-english.*Simple English' 'unchanged Simple English source and name'
assert_powershell_function_contains win.ps1 Install-ShowMeSkill 'humanlayer/skills.*show-me.*show-me' 'HumanLayer show-me source and name'
assert_powershell_function_contains win.ps1 Set-PiSkillOwnership '"simple-english", "show-me"' 'show-me canonical shared ownership'
assert_contains win.ps1 'Required Simple English skill setup failed' 'PowerShell fatal Simple English failure propagation'
assert_contains win.ps1 'Required show-me skill setup failed' 'PowerShell fatal show-me failure propagation'
assert_contains win.ps1 'Version 143 \| Last changed: Make Windows setup log uploads recoverable' 'PowerShell version banner'
assert_powershell_function_contains win.ps1 Install-PrLensSkill 'coldteadotai/pr-lens.*pr-lens.*PR Lens' 'PR Lens source and specific skill'
assert_powershell_function_not_contains win.ps1 Install-PrLensSkill 'BAN_|WORK_MACHINE|cursor|plugin|output-style|canvas|npx' 'PR Lens opt-out, policy, or runtime workflow'
for artifact in LICENSE references/graph-document.md references/config.md references/example.graph.json; do
    assert_powershell_function_contains win.ps1 Install-PrLensSkill "\"${artifact}\"" 'complete PR Lens footprint'
done
assert_powershell_function_contains win.ps1 Set-PiSkillOwnership '"simple-english", "show-me", "pr-lens"' 'PR Lens canonical shared ownership'
assert_contains win.ps1 'Required PR Lens skill setup failed' 'PowerShell fatal PR Lens failure propagation'
windows_setup_body=$(powershell_function_body win.ps1 Invoke-WindowsSetupTasks)
# shellcheck disable=SC2016 # Preserve literal PowerShell variable syntax.
[[ "${windows_setup_body}" == *$'if (-not (Install-PrLensSkill)) {\n        $prLensSetupFailed = $true\n    }'* && "${windows_setup_body}" == *$'if ($prLensSetupFailed) {\n        throw "Required PR Lens skill setup failed."\n    }'* ]] || fail 'win.ps1: PR Lens failure does not reach the setup error'
assert_order win.ps1 '^[[:space:]]+if \(-not \(Install-ShowMeSkill\)\) \{$' '^[[:space:]]+if \(-not \(Install-PrLensSkill\)\) \{$' 'PowerShell PR Lens after other skills'
assert_order win.ps1 '^[[:space:]]+if \(-not \(Install-PrLensSkill\)\) \{$' '^[[:space:]]+if \(-not \(Set-PiSkillOwnership\)\) \{$' 'PowerShell PR Lens before ownership cleanup'
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
                local skill_dir=""
                local relative_file=""
                local -a required_files=(SKILL.md)
                if [[ "${skill_name}" == pr-lens ]]; then
                    required_files+=(LICENSE references/graph-document.md references/config.md references/example.graph.json)
                fi
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
                setup_simple_english_skill > /dev/null || exit 1
                setup_show_me_skill > /dev/null || exit 1
                setup_pr_lens_skill > /dev/null || exit 1
                setup_pr_lens_skill > /dev/null || exit 1
            done
        '

    simple_args='--yes skills@latest add AminBlg/SimpleEnglish --global --agent claude-code --agent codex --agent gemini-cli --skill simple-english --copy --yes'
    show_me_args='--yes skills@latest add humanlayer/skills --global --agent claude-code --agent codex --agent gemini-cli --skill show-me --copy --yes'
    simple_count=$(grep -Fxc -- "${simple_args}" "${test_root}/calls" || true)
    show_me_count=$(grep -Fxc -- "${show_me_args}" "${test_root}/calls" || true)
    [[ "${simple_count}" -eq 2 ]] || fail "${file}: Simple English did not update on both setup runs"
    [[ "${show_me_count}" -eq 2 ]] || fail "${file}: show-me did not update on both setup runs"
    pr_lens_args='--yes skills@latest add coldteadotai/pr-lens --global --agent claude-code --agent codex --agent gemini-cli --skill pr-lens --copy --yes'
    pr_lens_count=$(grep -Fxc -- "${pr_lens_args}" "${test_root}/calls" || true)
    [[ "${pr_lens_count}" -eq 4 ]] || fail "${file}: PR Lens did not update twice on personal and work machines"
    call_count=$(wc -l < "${test_root}/calls")
    [[ "${call_count}" -eq 8 ]] || fail "${file}: installer used unexpected arguments"

    for skill in simple-english show-me pr-lens; do
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

    SETUP_SCRIPT="${repo_root}/${file}" SOURCE_WITHOUT_MAIN="${source_without_main}" \
        HOME="${failure_root}/pr-lens-home" CLAUDE_CONFIG_DIR="${failure_root}/custom claude" bash -c '
            source <(sed "${SOURCE_WITHOUT_MAIN}" "${SETUP_SCRIPT}")
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
                skill_dirs=("${CLAUDE_CONFIG_DIR:-${HOME}/.claude}/skills/pr-lens" "${HOME}/.agents/skills/pr-lens")
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
                    if output=$(setup_pr_lens_skill); then
                        printf "Accepted invalid PR Lens artifact: %s\n" "$*" >&2
                        exit 1
                    fi
                    [[ "${output}" == *"PR Lens validation failed:"* ]] || exit 2
                }
                reset_copies
                setup_pr_lens_skill > /dev/null || exit 3
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
                if setup_pr_lens_skill > /dev/null; then exit 5; fi
                ensure_skills_cli_node_runtime() { return 1; }
                npx() { printf "unexpected call\n" > "${HOME}/unexpected-call"; }
                if setup_pr_lens_skill > /dev/null; then exit 6; fi
                [[ ! -e "${HOME}/unexpected-call" ]] || exit 7
                ensure_skills_cli_node_runtime() { return 0; }
                unset -f npx
                saved_path=${PATH}
                PATH="${HOME}/empty-path"
                if setup_pr_lens_skill > /dev/null; then exit 8; fi
                PATH=${saved_path}
                npx() { return 0; }
            done
        ' || fail "${file}: PR Lens complete-file validation failed"

    rm -rf "${failure_root}" "${test_root}"
done

assert_contains README.md 'Every setup run installs the latest.*Simple English.*HumanLayer.*show-me' 'latest managed skill documentation'
# shellcheck disable=SC2016 # Preserve literal Markdown code spans.
assert_contains README.md 'Simple English, `show-me`, and PR Lens are required on personal and work machines and have no setup opt-out' 'required all-machine behavior documentation'
# shellcheck disable=SC2016 # Preserve literal Markdown code spans.
assert_contains CLAUDE.md 'always installs the latest Simple English, HumanLayer `show-me`, and PR Lens skills globally' 'repository guidance'
assert_contains CONTEXT.md '^\*\*Managed agent skill\*\*:' 'managed agent skill glossary term'

assert_contains README.md 'Default hosted uploads remain enabled, including on work machines' 'approved hosted-upload behavior'
assert_contains README.md 'next setup run' 'next-run rollout'
assert_contains README.md 'gh.*2\.99' 'attachment runtime limitation'
printf '✓ Managed Simple English, show-me, and PR Lens skill contract checks passed\n'
