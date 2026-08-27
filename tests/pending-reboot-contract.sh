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

    grep -Eq "${pattern}" "${file}" || fail "${file}: missing ${description}"
}

assert_not_contains() {
    local file=$1
    local pattern=$2
    local description=$3

    if grep -Eiq "${pattern}" "${file}"; then
        fail "${file}: unexpectedly contains ${description}"
    fi
}

assert_order() {
    local file=$1
    local first=$2
    local second=$3
    local description=$4

    local first_line second_line
    first_line=$(grep -En "${first}" "${file}" | head -n 1 | cut -d: -f1)
    second_line=$(grep -En "${second}" "${file}" | head -n 1 | cut -d: -f1)
    [[ -n "${first_line}" && -n "${second_line}" ]] || fail "${file}: could not verify ${description}"
    [[ "${first_line}" -lt "${second_line}" ]] || fail "${file}: ${description}"
}

# Every entry point defines and runs a pending-reboot report at the end of the
# setup task list, after the final update stage and before the success banner.
for file in "${bash_setup_scripts[@]}"; do
    assert_contains "${file}" '^check_pending_reboot\(\)' 'pending-reboot checker'
    assert_contains "${file}" '^[[:space:]]+check_pending_reboot$' 'pending-reboot call site'
    assert_order "${file}" 'print_section "Final Updates"' '^[[:space:]]+check_pending_reboot$' 'pending-reboot check after Final Updates'
    assert_order "${file}" '^[[:space:]]+check_pending_reboot$' 'Setup complete' 'pending-reboot check before success banner'

    # The report is informational only: a pending reboot is machine state, and
    # must never flip the run into a failure.
    assert_not_contains "${file}" 'check_pending_reboot \|\| return 1' 'fatal pending-reboot wiring'
    assert_not_contains "${file}" 'if ! check_pending_reboot' 'error-accumulating pending-reboot wiring'
done

# Debian family: the /var/run/reboot-required sentinel with capped package detail.
for file in ubuntu.sh wsl.sh pi.sh; do
    assert_contains "${file}" '/var/run/reboot-required' 'Debian reboot-required sentinel'
    assert_contains "${file}" '/var/run/reboot-required\.pkgs' 'triggering package list'
    assert_contains "${file}" 'head -n 5' 'capped package detail'
done
assert_contains ubuntu.sh 'Restart this machine for applied updates to take effect' 'reboot action text'
assert_contains pi.sh 'Restart this machine for applied updates to take effect' 'reboot action text'

# WSL restarts the instance, not the Windows host, and says so explicitly.
assert_contains wsl.sh 'WSL instance restart pending' 'WSL instance wording'
assert_contains wsl.sh 'wsl --shutdown' 'WSL instance restart command'

# macOS detection is best-effort: staged updates plus restart-marked updates.
assert_contains mac.sh '/Library/Updates/index\.plist' 'staged macOS update detection'
assert_contains mac.sh 'InstallAtLogout' 'deferred restart marker'
assert_contains mac.sh 'softwareupdate --list' 'restart-marked update detection'
assert_contains mac.sh 'A restart appears to be needed' 'hedged macOS wording'

# Bazzite is rpm-ostree based: a staged deployment means a reboot is pending.
assert_contains bazzite.sh 'rpm-ostree status --json' 'staged deployment detection'
assert_contains bazzite.sh 'staged system deployment' 'staged deployment wording'
assert_contains bazzite.sh '/var/run/reboot-required' 'sentinel fallback'

# Windows checks the standard pending-reboot registry locations after
# installing updates and reports which one triggered.
assert_contains win.ps1 '^function Test-PendingReboot \{' 'pending-reboot checker'
assert_contains win.ps1 '^[[:space:]]+Test-PendingReboot$' 'pending-reboot call site'
assert_contains win.ps1 'Component Based Servicing\\RebootPending' 'CBS pending key'
assert_contains win.ps1 'Auto Update\\RebootRequired' 'Windows Update required key'
assert_contains win.ps1 'PendingFileRenameOperations' 'pending file rename check'
assert_order win.ps1 'Install-WindowsUpdates # this should always be LAST' '^[[:space:]]+Test-PendingReboot$' 'pending-reboot check after Windows updates'
assert_not_contains win.ps1 'Test-PendingReboot.*throw' 'fatal pending-reboot wiring'

# The check documents a known machine state in the shared vocabulary.
assert_contains CONTEXT.md '\*\*Pending reboot\*\*' 'glossary entry'

printf '✓ Pending reboot contract passed\n'
