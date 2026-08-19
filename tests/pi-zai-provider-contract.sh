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

# NOTE: unlike syn_ prefixed Synthetic keys, z.ai API keys have no stable
# public prefix, so there is no hardcoded-key guard here.

for file in "${bash_setup_scripts[@]}"; do
    bash -n "${file}"
    assert_contains "${file}" '^pi_zai_key_available\(\)' 'Pi z.ai key check function'
    assert_contains "${file}" '^seed_pi_zai_models\(\)' 'Pi z.ai models seeding function'
    assert_contains "${file}" '^[[:space:]]+seed_pi_zai_models$' 'Pi z.ai models main wiring'
    assert_order "${file}" '^\s+seed_pi_synthetic_models$' '^\s+seed_pi_zai_models$' 'z.ai seeding after synthetic seeding'
    assert_contains "${file}" 'https://api\.z\.ai/api/coding/paas/v4' 'z.ai GLM Coding Plan base URL'
    assert_contains "${file}" 'read_env_local_value "ZAI_API_KEY"' 'z.ai API key read from ~/.env.local'
    assert_contains "${file}" '# ZAI_API_KEY=<your z\.ai API key>' 'env.local placeholder comment'
    assert_contains "${file}" '\.defaultProvider = "zai"' 'forced z.ai default provider on work machines'
    assert_contains "${file}" '\.defaultModel = "glm-5\.3"' 'forced GLM-5.3 default model on work machines'
    assert_contains "${file}" 'id: "glm-5\.3"' 'GLM-5.3 model definition'
    assert_contains "${file}" 'id: "glm-5-turbo"' 'GLM-5-Turbo model definition'
    assert_contains "${file}" 'id: "glm-4\.7"' 'GLM-4.7 model definition'
    assert_contains "${file}" 'WORK_MACHINE' 'work-machine gating'
done

assert_contains win.ps1 '^function Test-PiZaiKeyAvailable' 'PowerShell z.ai key check function'
assert_contains win.ps1 '^function Seed-PiZaiModels' 'PowerShell z.ai models seeding function'
assert_contains win.ps1 '^\s+Seed-PiZaiModels$' 'PowerShell z.ai models main wiring'
assert_contains win.ps1 'ZAI_API_KEY' 'PowerShell z.ai key lookup'
assert_contains win.ps1 'https://api\.z\.ai/api/coding/paas/v4' 'PowerShell z.ai GLM Coding Plan base URL'
assert_contains win.ps1 '"defaultProvider" -Value "zai"' 'PowerShell forced z.ai default provider on work machines'
assert_contains win.ps1 '"defaultModel" -Value "glm-5\.3"' 'PowerShell forced GLM-5.3 default model on work machines'
assert_contains win.ps1 'id\s+=\s+"glm-5\.3"' 'PowerShell GLM-5.3 model definition'
assert_contains win.ps1 'id\s+=\s+"glm-5-turbo"' 'PowerShell GLM-5-Turbo model definition'
assert_contains win.ps1 'id\s+=\s+"glm-4\.7"' 'PowerShell GLM-4.7 model definition'

printf '✓ Pi z.ai provider contract holds across all setup scripts\n'
