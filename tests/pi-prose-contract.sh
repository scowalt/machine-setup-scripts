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

    grep -Eq -- "${pattern}" "${file}" || fail "${file}: missing ${description}"
}

assert_not_contains() {
    local file=$1
    local pattern=$2
    local description=$3

    if grep -Eq -- "${pattern}" "${file}"; then
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

for file in "${bash_setup_scripts[@]}"; do
    bash -n "${file}"
    assert_contains "${file}" '^[[:space:]]+"npm:pi-prose"$' 'the unpinned pi-prose package'
    assert_contains "${file}" '^seed_pi_prose_default\(\)' 'the pi-prose default seed function'
    assert_contains "${file}" '^[[:space:]]+seed_pi_prose_default$' 'pi-prose default setup wiring'
    assert_contains "${file}" '"default": "matter-of-fact"' 'the matter-of-fact initial default'
    assert_contains "${file}" 'PI_CODING_AGENT_DIR:-\$\{HOME\}/\.pi/agent' 'custom Pi agent directory support'
    assert_not_contains "${file}" 'BAN_PI_PROSE' 'a pi-prose opt-out'
    assert_order "${file}" '^[[:space:]]+setup_pi_companion_packages$' '^[[:space:]]+seed_pi_prose_default$' 'pi-prose configuration after package setup'

    test_root=$(mktemp -d)
    custom_agent_dir="${test_root}/custom-pi"
    SETUP_SCRIPT="${repo_root}/${file}" SOURCE_WITHOUT_MAIN="${source_without_main}" \
        HOME="${test_root}/home" PI_CODING_AGENT_DIR="${custom_agent_dir}" bash -c '
            source <(sed "${SOURCE_WITHOUT_MAIN}" "${SETUP_SCRIPT}")
            config_file="${PI_CODING_AGENT_DIR}/prose/config.json"

            seed_pi_prose_default > /dev/null
            jq -e '\''. == {"default": "matter-of-fact"}'\'' "${config_file}" > /dev/null

            seed_pi_prose_default > /dev/null
            jq -e '\''. == {"default": "matter-of-fact"}'\'' "${config_file}" > /dev/null

            printf '\''{\n  "default": "concise",\n  "keep": true\n}\n'\'' > "${config_file}"
            seed_pi_prose_default > /dev/null
            jq -e '\''.default == "concise" and .keep == true'\'' "${config_file}" > /dev/null

            printf '\''{}\n'\'' > "${config_file}"
            seed_pi_prose_default > /dev/null
            jq -e '\''. == {}'\'' "${config_file}" > /dev/null

            printf '\''{not-json\n'\'' > "${config_file}"
            before=$(sha256sum "${config_file}" | cut -d" " -f1)
            seed_pi_prose_default > /dev/null
            after=$(sha256sum "${config_file}" | cut -d" " -f1)
            [[ "${before}" == "${after}" ]]

            rm -f "${config_file}"
            mkdir "${config_file}"
            seed_pi_prose_default > /dev/null
            [[ -d "${config_file}" ]]
        '
    rm -rf "${test_root}"
done

assert_contains win.ps1 '^function Initialize-PiProseDefault' 'the PowerShell pi-prose default seed function'
assert_contains win.ps1 '^[[:space:]]+"npm:pi-prose"$' 'the PowerShell unpinned pi-prose package'
assert_contains win.ps1 '^[[:space:]]+Initialize-PiProseDefault$' 'PowerShell pi-prose default setup wiring'
assert_contains win.ps1 'matter-of-fact' 'the PowerShell matter-of-fact initial default'
# shellcheck disable=SC2016 # Preserve literal PowerShell variable syntax.
assert_contains win.ps1 'UTF8Encoding]::new\(\$false\)' 'UTF-8 output without a byte order mark'
assert_not_contains win.ps1 'BAN_PI_PROSE' 'a PowerShell pi-prose opt-out'
assert_order win.ps1 '^[[:space:]]+Setup-PiCompanionPackages$' '^[[:space:]]+Initialize-PiProseDefault$' 'PowerShell pi-prose configuration after package setup'

# shellcheck disable=SC2016 # Preserve literal Markdown backticks.
assert_contains README.md 'unpinned `npm:pi-prose`' 'pi-prose update policy documentation'
# shellcheck disable=SC2016 # Preserve literal Markdown backticks.
assert_contains README.md '`matter-of-fact` user default only when the file does not exist' 'pi-prose seed policy documentation'
assert_contains CLAUDE.md 'Existing files remain unchanged' 'pi-prose ownership guidance'
assert_contains CONTEXT.md '^\*\*Pi output style\*\*:' 'the Pi output style glossary term'

printf '✓ pi-prose package and default contract holds across all setup scripts\n'
