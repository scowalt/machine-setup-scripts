#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "${repo_root}"

bash_setup_scripts=(mac.sh ubuntu.sh wsl.sh pi.sh bazzite.sh)

fail() {
    printf '✗ %s\n' "$1" >&2
    exit 1
}

assert_contains() {
    local file=$1
    local pattern=$2
    local description=$3

    if ! grep -Eq "${pattern}" "${file}"; then
        fail "${file}: missing ${description} (${pattern})"
    fi
}

assert_not_contains() {
    local file=$1
    local pattern=$2
    local description=$3

    if grep -Eq "${pattern}" "${file}"; then
        fail "${file}: forbidden ${description} (${pattern})"
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
    [[ -n "${first_line}" && -n "${second_line}" ]] || fail "${file}: cannot check order for ${description}"
    [[ "${first_line}" -lt "${second_line}" ]] || fail "${file}: wrong order for ${description}"
}

for file in "${bash_setup_scripts[@]}"; do
    bash -n "${file}"
    assert_contains "${file}" '^configure_pi_defaults\(\)' 'Pi defaults function'
    assert_contains "${file}" '^seed_pi_synthetic_models\(\)' 'Pi Synthetic models seeding function'
    assert_contains "${file}" '^[[:space:]]+configure_pi_defaults$' 'Pi defaults main wiring'
    assert_contains "${file}" '^[[:space:]]+seed_pi_synthetic_models$' 'Pi Synthetic models main wiring'
    assert_order "${file}" '^\s+configure_pi_defaults$' '^\s+remove_pi_subagents$' 'Pi defaults before extension setup'
    assert_contains "${file}" '\.defaultProvider = "synthetic"' 'forced Synthetic default provider'
    assert_contains "${file}" '\.defaultModel = "hf:moonshotai/Kimi-K3"' 'forced Kimi K3 default model'
    assert_contains "${file}" '\.defaultThinkingLevel = "high"' 'forced high thinking level'
    assert_contains "${file}" 'https://api\.synthetic\.new/v1' 'Synthetic base URL'
    assert_contains "${file}" 'read_env_local_value "SYNTHETIC_API_KEY"' 'API key read from ~/.env.local'
    assert_contains "${file}" 'deferredToolsMode: "kimi"' 'Synthetic deferred-tools compat flag'
    assert_not_contains "${file}" 'syn_[A-Za-z0-9]' 'hardcoded Synthetic API key'
done

assert_contains win.ps1 '^function Set-PiDefaults' 'PowerShell Pi defaults function'
assert_contains win.ps1 '^function Seed-PiSyntheticModels' 'PowerShell Synthetic models seeding function'
assert_contains win.ps1 '^\s+Set-PiDefaults$' 'PowerShell Pi defaults main wiring'
assert_contains win.ps1 '^\s+Seed-PiSyntheticModels$' 'PowerShell Synthetic models main wiring'
# shellcheck disable=SC2016 # Preserve literal PowerShell variable syntax.
assert_contains win.ps1 '"defaultProvider", "synthetic"|"defaultProvider" -Value "synthetic"|Set-JsonProperty -Object \$settings -Name "defaultProvider"' 'PowerShell forced Synthetic default provider'
assert_contains win.ps1 'hf:moonshotai/Kimi-K3' 'PowerShell Kimi K3 model id'
assert_contains win.ps1 'SYNTHETIC_API_KEY' 'PowerShell API key lookup'
assert_not_contains win.ps1 'syn_[A-Za-z0-9]' 'hardcoded Synthetic API key'

printf '✓ Pi Synthetic defaults contract holds across all setup scripts\n'
