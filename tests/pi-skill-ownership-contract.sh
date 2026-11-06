#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "${repo_root}"

repo_root=$(python3 tests/extract_setup_fixture.py "${repo_root}") || exit 1

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

    mkdir -p "${shared}/pr/agents" "${shared}/tdd" "${default_pi}/tdd" "${custom_pi}"
    printf 'dotfiles pr\n' > "${shared}/pr/SKILL.md"
    printf 'dotfiles pr metadata\n' > "${shared}/pr/agents/openai.yaml"
    cp -R "${shared}/pr" "${default_pi}/pr"
    cp -R "${shared}/pr" "${custom_pi}/pr"
    printf 'user-modified metadata\n' > "${custom_pi}/pr/agents/openai.yaml"
    printf 'retired\n' > "${shared}/tdd/SKILL.md"
    cp "${shared}/tdd/SKILL.md" "${default_pi}/tdd/SKILL.md"
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

    [[ ! -e "${default_pi}/pr" ]] || fail "${file}: identical default Pi pr duplicate remains"
    [[ $(< "${custom_pi}/pr/agents/openai.yaml") == 'user-modified metadata' ]] || fail "${file}: modified pr copy changed"
    [[ -s "${shared}/pr/SKILL.md" ]] || fail "${file}: canonical pr copy was removed"
    for direct_pi in "${default_pi}" "${custom_pi}"; do
        exclusion="!${direct_pi}/pr/**"
        count=$(jq --arg entry "${exclusion}" '[.skills[] | select(. == $entry)] | length' "${active_pi}/settings.json")
        [[ "${count}" -eq 1 ]] || fail "${file}: pr exclusion missing or repeated at ${direct_pi}"
    done
    jq -e --arg entry "!${shared}/pr/**" '.skills | index($entry) == null' "${active_pi}/settings.json" > /dev/null || fail "${file}: canonical pr copy was excluded"
    [[ -f "${default_pi}/tdd/SKILL.md" ]] || fail "${file}: ownership removed a retired-name copy"
    jq -e '[.skills[] | select(contains("/tdd/"))] | length == 0' "${active_pi}/settings.json" > /dev/null || fail "${file}: ownership excluded a retired name"

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
grep -q 'Invoke-MattPocockSkillPolicy -Mode ownership' win.ps1 || fail 'win.ps1: missing shared ownership policy'
if sed -n '/^function Setup-MattPocockSkills/,/^}/p' win.ps1 | grep -q '"--agent", "pi"'; then
    fail 'win.ps1: Matt Pocock skills still target direct Pi installation'
fi

printf '✓ Pi skill ownership contract checks passed\n'
