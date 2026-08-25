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

assert_min_count() {
    local file=$1
    local pattern=$2
    local minimum=$3
    local description=$4
    local count

    count=$(grep -cE "${pattern}" "${file}" || true)
    [[ "${count}" -ge "${minimum}" ]] || fail "${file}: expected at least ${minimum} ${description}, saw ${count}"
}

for file in "${bash_setup_scripts[@]}"; do
    bash -n "${file}"

    # Regression guard: the tintinweb Pi subagents extension is gone for good.
    assert_not_contains "${file}" 'pi install npm:@tintinweb/pi-subagents' 'install of npm:@tintinweb/pi-subagents'
    assert_not_contains "${file}" 'pi install npm:pi-subagents' 'install of npm:pi-subagents'
    assert_not_contains "${file}" 'BAN_PI_SUBAGENTS' 'legacy opt-out flag'
    assert_not_contains "${file}" 'setup_pi_subagents' 'legacy install function'
    assert_not_contains "${file}" 'update_pi_subagents_settings' 'legacy settings helper'

    # Removal must run unconditionally in both main() branches.
    assert_contains "${file}" '^remove_pi_subagents\(\)' 'Pi subagents removal function'
    assert_contains "${file}" 'pi remove' 'pi remove uninstall path'
    assert_min_count "${file}" '^[[:space:]]+remove_pi_subagents$' 2 'remove_pi_subagents call sites'
done

assert_contains win.ps1 '^function Remove-PiSubagents' 'PowerShell Pi subagents removal function'
assert_contains win.ps1 'pi remove' 'PowerShell pi remove uninstall path'
assert_min_count win.ps1 '^\s+Remove-PiSubagents$' 2 'Remove-PiSubagents call sites'
assert_not_contains win.ps1 'pi install npm:@tintinweb/pi-subagents' 'install of npm:@tintinweb/pi-subagents'
assert_not_contains win.ps1 'pi install npm:pi-subagents' 'install of npm:pi-subagents'
assert_not_contains win.ps1 'BAN_PI_SUBAGENTS' 'legacy opt-out flag'
assert_not_contains win.ps1 'Setup-PiSubagents' 'legacy install function'
assert_not_contains win.ps1 'Update-PiSubagentsSettings' 'legacy settings helper'

printf '✓ Pi subagents removal contract holds across all setup scripts\n'
