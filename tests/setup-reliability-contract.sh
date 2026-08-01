#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "${repo_root}"

bash_setup_scripts=(mac.sh ubuntu.sh wsl.sh pi.sh bazzite.sh)
linux_apt_scripts=(ubuntu.sh wsl.sh pi.sh)

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

    if grep -Eq "${pattern}" "${file}"; then
        fail "${file}: unexpectedly contains ${description}"
    fi
}

source_without_main='s/^main "\$@"$/:/'

# Reproduce gcloud's wrapped package-manager message at the real function seam.
for file in "${bash_setup_scripts[@]}"; do
    output=$(SETUP_SCRIPT="${repo_root}/${file}" SOURCE_WITHOUT_MAIN="${source_without_main}" bash -c '
        source <(sed "${SOURCE_WITHOUT_MAIN}" "${SETUP_SCRIPT}")
        gcloud() {
            printf "%s\n" "ERROR: The Google Cloud CLI" "component manager" "is disabled for this installation."
            return 1
        }
        update_gcloud_components
    ')
    grep -q 'managed by the package manager; skipping' <<< "${output}" || fail "${file}: wrapped gcloud output was not treated as a package-manager skip"
    if grep -q 'Failed to update Google Cloud CLI components' <<< "${output}"; then
        fail "${file}: wrapped gcloud output emitted a failure warning"
    fi
done

# These regexes intentionally use single quotes to preserve PowerShell variable syntax.
# shellcheck disable=SC2016
assert_contains win.ps1 '\$normalizedUpdateText[[:space:]]*=' 'normalized gcloud update output'
# shellcheck disable=SC2016
assert_contains win.ps1 '\$normalizedUpdateText -match "component manager is disabled\|managed by an external package manager"' 'normalized package-manager detection'

if command -v pwsh &>/dev/null; then
    pwsh -NoLogo -NoProfile -File tests/setup-reliability-powershell.ps1
fi

# Obsolete virtual package names must not re-enter apt package inventories.
for file in "${linux_apt_scripts[@]}"; do
    assert_not_contains "${file}" 'libncurses5-dev|libncursesw5-dev' 'deprecated ncurses package names'
    assert_contains "${file}" 'libncurses-dev' 'canonical ncurses development package'
done

# A failed brew phase must not produce success, and tmux must always be unpinned.
brew_output=$(SETUP_SCRIPT="${repo_root}/mac.sh" SOURCE_WITHOUT_MAIN="${source_without_main}" bash -c '
    source <(sed "${SOURCE_WITHOUT_MAIN}" "${SETUP_SCRIPT}")
    brew() {
        printf "%s\n" "$*" >> "${BREW_CALL_LOG}"
        case "$1" in
            update) return 0 ;;
            upgrade) return 1 ;;
            untrust) printf "%s\n" "No untrusted taps, formulae, casks or commands." ;;
        esac
        return 0
    }
    BREW_CALL_LOG=$(mktemp)
    export BREW_CALL_LOG
    update_brew
    printf "%s\n" "--- calls ---"
    cat "${BREW_CALL_LOG}"
    rm -f "${BREW_CALL_LOG}"
')
grep -q 'Homebrew update/upgrade incomplete' <<< "${brew_output}" || fail 'mac.sh: brew failure lacks a concise warning'
grep -q 'brew reinstall --cask --force bartender' <<< "${brew_output}" || fail 'mac.sh: brew failure lacks cask remediation'
if grep -q 'Homebrew updated\.' <<< "${brew_output}"; then
    fail 'mac.sh: failed brew upgrade was reported as successful'
fi
grep -q '^unpin tmux$' <<< "${brew_output}" || fail 'mac.sh: tmux was not unpinned after brew failure'

untrusted_brew_output=$(SETUP_SCRIPT="${repo_root}/mac.sh" SOURCE_WITHOUT_MAIN="${source_without_main}" bash -c '
    source <(sed "${SOURCE_WITHOUT_MAIN}" "${SETUP_SCRIPT}")
    brew() {
        if [[ "$1" == "untrust" ]]; then
            printf "%s\n" "Untrusted formulae:" "  example/unmanaged/tool" "  tursodatabase/tap/extra-tool"
        elif [[ "$1 $2" == "list --formula" ]]; then
            printf "%s\n" "example/unmanaged/tool" "tursodatabase/tap/extra-tool"
        fi
        return 0
    }
    update_brew
')
grep -q 'Unmanaged Homebrew formula example/unmanaged/tool remains untrusted' <<< "${untrusted_brew_output}" || fail 'mac.sh: unmanaged tap item warning missing'
grep -q 'Unmanaged Homebrew formula tursodatabase/tap/extra-tool remains untrusted' <<< "${untrusted_brew_output}" || fail 'mac.sh: partially trusted managed tap warning missing'
if grep -q 'Homebrew updated\.' <<< "${untrusted_brew_output}"; then
    fail 'mac.sh: skipped unmanaged tap was reported as a complete success'
fi

assert_contains mac.sh 'brew trust "\$\{_trust_flag\}" "\$\{_item\}"' 'item-level trust command'
assert_contains mac.sh 'ensure_brew_item_trusted formula "libsql/sqld/sqld"' 'item-level libsql trust'
assert_contains mac.sh 'ensure_brew_item_trusted formula "tursodatabase/tap/turso"' 'item-level Turso trust'
assert_contains mac.sh 'ensure_brew_item_trusted formula "infisical/get-cli/infisical"' 'item-level Infisical trust'
assert_contains mac.sh 'ensure_brew_item_trusted formula "dopplerhq/cli/doppler"' 'item-level Doppler trust'
assert_contains mac.sh 'ensure_brew_item_trusted cask "soren-starck/tap/sessionwatcher"' 'item-level SessionWatcher trust'
assert_not_contains mac.sh 'brew trust "\$\{tap\}"' 'whole-tap trust'
assert_contains mac.sh 'Unmanaged Homebrew .* remains untrusted and may be skipped' 'actionable unmanaged-tap item warning'

# Prove the portable lock uses one namespace and rejects a second process.
assert_not_contains mac.sh 'command -v flock' 'PATH-dependent split lock namespace'
lock_root=$(mktemp -d)
mock_bin=$(mktemp -d)
first_log=$(mktemp)
second_log=$(mktemp)
cleanup_lock_test() {
    if [[ -n "${holder_pid:-}" ]]; then
        kill "${holder_pid}" 2>/dev/null || true
        wait "${holder_pid}" 2>/dev/null || true
    fi
    rm -rf "${lock_root}" "${mock_bin}" "${first_log}" "${second_log}"
}
trap cleanup_lock_test EXIT
for command_name in bash cat date mkdir ps rm rmdir sed sleep stat touch; do
    command_path=$(command -v "${command_name}")
    ln -s "${command_path}" "${mock_bin}/${command_name}"
done

PATH="${mock_bin}" XDG_RUNTIME_DIR="${lock_root}" SETUP_SCRIPT="${repo_root}/mac.sh" SOURCE_WITHOUT_MAIN="${source_without_main}" \
    bash -c '
        source <(sed "${SOURCE_WITHOUT_MAIN}" "${SETUP_SCRIPT}")
        acquire_setup_lock
        touch "${XDG_RUNTIME_DIR}/ready"
        sleep 30
    ' > "${first_log}" 2>&1 &
holder_pid=$!
for _ in {1..50}; do
    [[ -f "${lock_root}/ready" ]] && break
    sleep 0.05
done
[[ -f "${lock_root}/ready" ]] || fail 'mac.sh: fallback lock holder did not start'

if PATH="${mock_bin}" XDG_RUNTIME_DIR="${lock_root}" SETUP_SCRIPT="${repo_root}/mac.sh" SOURCE_WITHOUT_MAIN="${source_without_main}" \
    bash -c '
        source <(sed "${SOURCE_WITHOUT_MAIN}" "${SETUP_SCRIPT}")
        acquire_setup_lock
    ' > "${second_log}" 2>&1; then
    fail 'mac.sh: mkdir fallback allowed concurrent lock acquisition'
fi
grep -q 'Another machine setup run is already in progress' "${second_log}" || fail 'mac.sh: lock contention warning missing'
kill "${holder_pid}" 2>/dev/null || true
wait "${holder_pid}" 2>/dev/null || true
holder_pid=''
[[ ! -d "${lock_root}/machine-setup.lock.d" ]] || fail 'mac.sh: mkdir fallback lock was not cleaned up by trap'

mkdir "${lock_root}/machine-setup.lock.d"
printf '%s\n' '99999999' > "${lock_root}/machine-setup.lock.d/pid"
mkdir "${lock_root}/machine-setup.lock.d.reclaim"
printf '%s\n' '99999999' > "${lock_root}/machine-setup.lock.d.reclaim/pid"
if PATH="${mock_bin}" XDG_RUNTIME_DIR="${lock_root}" SETUP_SCRIPT="${repo_root}/mac.sh" SOURCE_WITHOUT_MAIN="${source_without_main}" \
    bash -c '
        source <(sed "${SOURCE_WITHOUT_MAIN}" "${SETUP_SCRIPT}")
        acquire_setup_lock
    ' > "${second_log}" 2>&1; then
    fail 'mac.sh: stale recovery marker should require a safe retry'
fi
grep -q 'Removed a stale setup-lock recovery marker' "${second_log}" || fail 'mac.sh: stale recovery marker cleanup was not reported'
[[ ! -d "${lock_root}/machine-setup.lock.d.reclaim" ]] || fail 'mac.sh: stale recovery marker was not removed'

PATH="${mock_bin}" XDG_RUNTIME_DIR="${lock_root}" SETUP_SCRIPT="${repo_root}/mac.sh" SOURCE_WITHOUT_MAIN="${source_without_main}" \
    bash -c '
        source <(sed "${SOURCE_WITHOUT_MAIN}" "${SETUP_SCRIPT}")
        acquire_setup_lock
    ' > "${second_log}" 2>&1 || fail 'mac.sh: stale PID lock was not recovered'
grep -q 'Removing stale setup lock' "${second_log}" || fail 'mac.sh: stale PID lock recovery was not reported'
[[ ! -d "${lock_root}/machine-setup.lock.d" ]] || fail 'mac.sh: recovered stale lock was not cleaned up on exit'

mkdir "${lock_root}/machine-setup.lock.d"
printf '%s\n' '99999999' > "${lock_root}/machine-setup.lock.d/pid"
contender_pids=()
shopt -s nullglob
for contender in 1 2; do
    PATH="${mock_bin}" XDG_RUNTIME_DIR="${lock_root}" SETUP_SCRIPT="${repo_root}/mac.sh" SOURCE_WITHOUT_MAIN="${source_without_main}" \
        bash -c '
            source <(sed "${SOURCE_WITHOUT_MAIN}" "${SETUP_SCRIPT}")
            touch "${XDG_RUNTIME_DIR}/contender.$$"
            while [[ ! -f "${XDG_RUNTIME_DIR}/start-recovery" ]]; do sleep 0.01; done
            if acquire_setup_lock; then
                touch "${XDG_RUNTIME_DIR}/winner.$$"
                sleep 0.2
            fi
        ' > "${lock_root}/contender-${contender}.log" 2>&1 &
    contender_pids+=("$!")
done
for _ in {1..50}; do
    contender_files=("${lock_root}"/contender.*)
    [[ "${#contender_files[@]}" -eq 2 ]] && break
    sleep 0.02
done
touch "${lock_root}/start-recovery"
for contender_pid in "${contender_pids[@]}"; do
    wait "${contender_pid}" || true
done
winner_files=("${lock_root}"/winner.*)
[[ "${#winner_files[@]}" -eq 1 ]] || fail 'mac.sh: concurrent stale-lock recovery produced multiple owners'
[[ ! -d "${lock_root}/machine-setup.lock.d" ]] || fail 'mac.sh: concurrent stale-lock recovery left the lock behind'

trap - EXIT
cleanup_lock_test
printf '✓ Setup reliability contract checks passed\n'
