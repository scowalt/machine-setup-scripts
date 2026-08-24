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
        fail "${file}: unexpectedly contains ${description} (${pattern})"
    fi
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
    if ! grep -Eq "${pattern}" <<< "${body}"; then
        fail "${file}: ${function_name}() missing ${description} (${pattern})"
    fi
}

assert_function_not_contains() {
    local file=$1
    local function_name=$2
    local pattern=$3
    local description=$4

    local body
    body=$(function_body "${file}" "${function_name}")
    if grep -Eq "${pattern}" <<< "${body}"; then
        fail "${file}: ${function_name}() unexpectedly contains ${description} (${pattern})"
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
    assert_contains "${file}" '^install_ntn_cli\(\)' 'Notion CLI installer function'
    assert_contains "${file}" '^[[:space:]]+install_ntn_cli$' 'Notion CLI main wiring'
    assert_function_contains "${file}" install_ntn_cli 'Darwin:x86_64.*Linux:aarch64' 'x64 and ARM64 support matrix'
    assert_function_contains "${file}" install_ntn_cli 'Notion CLI does not support.*skipping' 'unsupported-architecture warning'
    assert_function_contains "${file}" install_ntn_cli 'mktemp.*ntn-install' 'temporary installer file'
    assert_function_contains "${file}" install_ntn_cli 'https://ntn\.dev' 'official installer URL'
    assert_function_contains "${file}" install_ntn_cli 'install_dir="\$\{HOME\}/\.local/bin"' 'canonical user-local install directory'
    assert_function_contains "${file}" install_ntn_cli 'NTN_INSTALL_DIR="\$\{install_dir\}" bash' 'native installer execution'
    assert_function_contains "${file}" install_ntn_cli '"\$\{install_dir\}/ntn" --version' 'absolute-path verification'
    assert_function_contains "${file}" install_ntn_cli 'Failed to download the Notion CLI installer' 'non-fatal download warning'
    assert_function_contains "${file}" install_ntn_cli 'Failed to install/update Notion CLI' 'non-fatal install warning'
    assert_function_contains "${file}" install_ntn_cli 'rm -f "\$\{installer_path\}"' 'temporary file cleanup'
    assert_function_not_contains "${file}" install_ntn_cli 'command -v ntn' 'presence-only early return'
    assert_function_not_contains "${file}" install_ntn_cli 'bun|npm' 'Node package-manager dependency'
    assert_function_not_contains "${file}" install_ntn_cli 'ntn login|ntn completions' 'authentication or completion automation'
    assert_order "${file}" '^[[:space:]]+install_codex_cli([[:space:]]+\|\|[[:space:]]+return 1)?$' '^[[:space:]]+install_ntn_cli$' 'Codex before Notion CLI'
    assert_order "${file}" '^[[:space:]]+install_ntn_cli$' '^[[:space:]]+install_rtk_cli$' 'Notion CLI before RTK'
done

assert_contains win.ps1 '"Notion\.ntn"' 'official Notion CLI WinGet package'
# These regexes intentionally use single quotes to preserve literal shell and Markdown syntax.
# shellcheck disable=SC2016
assert_contains win.ps1 '\$package -eq "Notion\.ntn" -and \$env:PROCESSOR_ARCHITECTURE -ne "AMD64"' 'Windows x64 architecture guard'
assert_contains win.ps1 'Notion CLI supports Windows x64 only; skipping' 'unsupported Windows architecture warning'
assert_order win.ps1 '^[[:space:]]+Install-WingetPackages$' '^[[:space:]]+Install-WingetUpdates$' 'WinGet install before update'
assert_not_contains win.ps1 'npm (install|i).*(--global|-g).*ntn' 'npm-based Notion CLI installation'
assert_not_contains win.ps1 'ntn (login|completions)' 'Notion authentication or completion automation'

assert_contains README.md 'macOS, Ubuntu, WSL, Raspberry Pi, Bazzite, and Windows' 'all-machine platform statement'
# shellcheck disable=SC2016
assert_contains README.md 'Notion CLI \(`ntn`\)' 'managed Notion CLI statement'
# shellcheck disable=SC2016
assert_contains README.md 'Run `ntn login` manually' 'manual authentication guidance'
assert_contains README.md 'Windows package supports x64 only' 'Windows architecture limitation'
# shellcheck disable=SC2016
assert_contains CLAUDE.md 'Notion CLI \(`ntn`\)' 'Notion CLI repository guidance'
assert_not_contains README.md 'BAN_NTN' 'unplanned Notion CLI opt-out'
assert_not_contains CLAUDE.md 'BAN_NTN' 'unplanned Notion CLI opt-out'

printf '✓ Notion CLI installation contract checks passed\n'
