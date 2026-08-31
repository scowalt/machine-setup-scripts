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

for file in "${bash_setup_scripts[@]}"; do
    test_root=$(mktemp -d)
    test_home="${test_root}/home"
    active_pi="${test_root}/custom-pi"
    shared="${test_home}/.agents/skills"
    default_pi="${test_home}/.pi/agent/skills"
    custom_pi="${active_pi}/skills"

    mkdir -p "${shared}/simple-english" "${default_pi}/simple-english" \
        "${custom_pi}/simple-english" "${shared}/show-me" "${default_pi}/show-me" \
        "${custom_pi}/show-me" "${shared}/diagnosing-bugs" \
        "${default_pi}/diagnosing-bugs" "${custom_pi}/diagnosing-bugs"
    printf 'canonical\n' > "${shared}/simple-english/SKILL.md"
    cp "${shared}/simple-english/SKILL.md" "${default_pi}/simple-english/SKILL.md"
    cp "${shared}/simple-english/SKILL.md" "${custom_pi}/simple-english/SKILL.md"
    printf 'canonical-show-me\n' > "${shared}/show-me/SKILL.md"
    cp "${shared}/show-me/SKILL.md" "${default_pi}/show-me/SKILL.md"
    printf 'user-modified-show-me\n' > "${custom_pi}/show-me/SKILL.md"
    printf 'canonical\n' > "${shared}/diagnosing-bugs/SKILL.md"
    printf 'user-modified\n' > "${default_pi}/diagnosing-bugs/SKILL.md"
    cp "${shared}/diagnosing-bugs/SKILL.md" "${custom_pi}/diagnosing-bugs/SKILL.md"
    mkdir -p "${active_pi}/extensions"
    printf '%s\n' '{"theme":"keep","skills":["user-skill"]}' > "${active_pi}/settings.json"
    printf '%s\n' '{"display":{"keep":true},"shortcuts":{"another":"ctrl+x"}}' > "${active_pi}/extensions/pi-autoresearch.json"

    SETUP_SCRIPT="${repo_root}/${file}" SOURCE_WITHOUT_MAIN="${source_without_main}" \
        HOME="${test_home}" PI_CODING_AGENT_DIR="${active_pi}" bash -c '
            source <(sed "${SOURCE_WITHOUT_MAIN}" "${SETUP_SCRIPT}")
            configure_pi_skill_ownership > /dev/null
            configure_pi_skill_ownership > /dev/null
            configure_pi_autoresearch_shortcut > /dev/null
            configure_pi_autoresearch_shortcut > /dev/null
        '

    [[ ! -e "${default_pi}/simple-english" ]] || fail "${file}: identical default Pi duplicate remains"
    [[ ! -e "${custom_pi}/simple-english" ]] || fail "${file}: identical custom Pi duplicate remains"
    [[ ! -e "${default_pi}/show-me" ]] || fail "${file}: identical default show-me duplicate remains"
    [[ -f "${custom_pi}/show-me/SKILL.md" ]] || fail "${file}: modified show-me copy was removed"
    [[ $(< "${custom_pi}/show-me/SKILL.md") == user-modified-show-me ]] || fail "${file}: modified show-me copy changed"
    [[ ! -e "${custom_pi}/diagnosing-bugs" ]] || fail "${file}: identical custom Matt Pocock duplicate remains"
    [[ -f "${default_pi}/diagnosing-bugs/SKILL.md" ]] || fail "${file}: modified user copy was removed"
    [[ $(< "${default_pi}/diagnosing-bugs/SKILL.md") == user-modified ]] || fail "${file}: modified user copy changed"

    jq -e '.theme == "keep" and (.skills | index("user-skill"))' "${active_pi}/settings.json" > /dev/null || fail "${file}: existing Pi settings changed"
    for skill in pi-goal-writer autoresearch-create autoresearch-finalize autoresearch-hooks; do
        exclusion="!${shared}/${skill}/**"
        count=$(jq --arg entry "${exclusion}" '[.skills[] | select(. == $entry)] | length' "${active_pi}/settings.json")
        [[ "${count}" -eq 1 ]] || fail "${file}: package skill exclusion is not idempotent for ${skill}"
    done
    jq -e '.display.keep == true and .shortcuts.another == "ctrl+x" and .shortcuts.fullscreenDashboard == "ctrl+shift+r"' \
        "${active_pi}/extensions/pi-autoresearch.json" > /dev/null || fail "${file}: autoresearch settings were not merged"

    rm -rf "${test_root}"
done

grep -q '^function Set-PiSkillOwnership' win.ps1 || fail 'win.ps1: missing Pi skill ownership function'
grep -q '^function Set-PiAutoresearchShortcut' win.ps1 || fail 'win.ps1: missing autoresearch shortcut function'
grep -q 'fullscreenDashboard.*ctrl+shift+r' win.ps1 || fail 'win.ps1: missing Ctrl+Shift+R binding'
if sed -n '/^function Install-ManagedAgentSkill/,/^}/p' win.ps1 | grep -q '"--agent", "pi"'; then
    fail 'win.ps1: managed agent skills still target direct Pi installation'
fi
grep -q '"simple-english", "show-me"' win.ps1 || fail 'win.ps1: show-me is not a canonical shared Pi skill'
if sed -n '/^function Setup-MattPocockSkills/,/^}/p' win.ps1 | grep -q '"--agent", "pi"'; then
    fail 'win.ps1: Matt Pocock skills still target direct Pi installation'
fi

printf '✓ Pi skill ownership contract checks passed\n'
