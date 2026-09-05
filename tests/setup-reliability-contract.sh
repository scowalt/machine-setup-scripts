#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "${repo_root}"

bash_setup_scripts=(mac.sh ubuntu.sh wsl.sh pi.sh bazzite.sh)
linux_apt_scripts=(ubuntu.sh wsl.sh pi.sh)
github_key_bash_scripts=(mac.sh ubuntu.sh wsl.sh pi.sh bazzite.sh)

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

# GitHub key downloads must retry transient/empty responses without confusing
# transport failures with a successfully fetched list that lacks the local key.
for file in "${github_key_bash_scripts[@]}"; do
    assert_contains "${file}" '^fetch_github_ssh_keys\(\)' 'bounded GitHub SSH-key fetch helper'
    assert_contains "${file}" 'curl --fail --silent --show-error --location' 'failing GitHub key curl request'
    assert_contains "${file}" '\--connect-timeout 10 --max-time 20' 'bounded GitHub key request timeouts'
    assert_not_contains "${file}" 'curl -s https://github\.com/scowalt\.keys' 'unhardened GitHub key download'

    key_test_root=$(mktemp -d)
    retry_output=$(SETUP_SCRIPT="${repo_root}/${file}" SOURCE_WITHOUT_MAIN="${source_without_main}" \
        FETCH_CALLS="${key_test_root}/retry-calls" bash -c '
            source <(sed "${SOURCE_WITHOUT_MAIN}" "${SETUP_SCRIPT}")
            sleep() { :; }
            curl() {
                local call_count=0
                printf "%s\n" "$*" >> "${FETCH_CALLS}"
                call_count=$(wc -l < "${FETCH_CALLS}")
                if [[ "${call_count}" -lt 3 ]]; then
                    return 22
                fi
                printf "%s\n" "ssh-ed25519 expected-key fixture@example"
            }
            fetch_github_ssh_keys
        ')
    [[ "${retry_output}" == 'ssh-ed25519 expected-key fixture@example' ]] || fail "${file}: GitHub key fetch did not recover on the third attempt"
    retry_count=$(wc -l < "${key_test_root}/retry-calls")
    [[ "${retry_count}" -eq 3 ]] || fail "${file}: GitHub key fetch made ${retry_count} attempts instead of three"

    SETUP_SCRIPT="${repo_root}/${file}" SOURCE_WITHOUT_MAIN="${source_without_main}" \
        FETCH_CALLS="${key_test_root}/failure-calls" bash -c '
            source <(sed "${SOURCE_WITHOUT_MAIN}" "${SETUP_SCRIPT}")
            sleep() { :; }
            curl() {
                printf "%s\n" "$*" >> "${FETCH_CALLS}"
                return 22
            }
            if fetch_github_ssh_keys; then
                exit 90
            fi
        ' || fail "${file}: persistent GitHub transport failure was accepted"
    failure_count=$(wc -l < "${key_test_root}/failure-calls")
    [[ "${failure_count}" -eq 3 ]] || fail "${file}: persistent GitHub failure made ${failure_count} attempts instead of three"

    SETUP_SCRIPT="${repo_root}/${file}" SOURCE_WITHOUT_MAIN="${source_without_main}" \
        FETCH_CALLS="${key_test_root}/empty-calls" bash -c '
            source <(sed "${SOURCE_WITHOUT_MAIN}" "${SETUP_SCRIPT}")
            sleep() { :; }
            curl() {
                printf "%s\n" "$*" >> "${FETCH_CALLS}"
                printf " \n"
            }
            if fetch_github_ssh_keys; then
                exit 90
            fi
        ' || fail "${file}: empty GitHub key response was accepted"
    empty_count=$(wc -l < "${key_test_root}/empty-calls")
    [[ "${empty_count}" -eq 3 ]] || fail "${file}: empty GitHub response made ${empty_count} attempts instead of three"
    rm -rf "${key_test_root}"
done

key_test_root=$(mktemp -d)
mkdir -p "${key_test_root}/home/.ssh"
printf '%s\n' 'ssh-rsa expected-key fixture@example' > "${key_test_root}/home/.ssh/id_rsa.pub"
transport_output=$(SETUP_SCRIPT="${repo_root}/ubuntu.sh" SOURCE_WITHOUT_MAIN="${source_without_main}" \
    HOME="${key_test_root}/home" OPEN_MARKER="${key_test_root}/transport-opened" bash -c '
        source <(sed "${SOURCE_WITHOUT_MAIN}" "${SETUP_SCRIPT}")
        can_sudo() { return 0; }
        detect_machine_type() { printf "physical\n"; }
        fetch_github_ssh_keys() { return 1; }
        xdg-open() { touch "${OPEN_MARKER}"; }
        setup_ssh_key || true
    ')
grep -q 'Failed to download SSH keys from GitHub after three attempts' <<< "${transport_output}" || fail 'ubuntu.sh: GitHub transport failure lacked a distinct error'
if grep -q 'SSH key not recognized by GitHub' <<< "${transport_output}"; then
    fail 'ubuntu.sh: GitHub transport failure was reported as a key mismatch'
fi
[[ ! -e "${key_test_root}/transport-opened" ]] || fail 'ubuntu.sh: transport failure opened GitHub key settings'

mismatch_output=$(SETUP_SCRIPT="${repo_root}/ubuntu.sh" SOURCE_WITHOUT_MAIN="${source_without_main}" \
    HOME="${key_test_root}/home" OPEN_MARKER="${key_test_root}/mismatch-opened" bash -c '
        source <(sed "${SOURCE_WITHOUT_MAIN}" "${SETUP_SCRIPT}")
        can_sudo() { return 0; }
        detect_machine_type() { printf "physical\n"; }
        fetch_github_ssh_keys() { printf "%s\n" "ssh-rsa another-key fixture@example"; }
        xdg-open() { touch "${OPEN_MARKER}"; }
        setup_ssh_key || true
    ')
grep -q 'SSH key not recognized by GitHub' <<< "${mismatch_output}" || fail 'ubuntu.sh: valid nonmatching GitHub response lacked the key-mismatch error'
[[ -e "${key_test_root}/mismatch-opened" ]] || fail 'ubuntu.sh: valid key mismatch did not open GitHub key settings'
rm -rf "${key_test_root}"

# Completion colors must be emitted as actual escape bytes, never literal \033.
for file in "${bash_setup_scripts[@]}"; do
    completion_line=$(grep '✨ Setup complete' "${file}" | tail -n 1)
    completion_output=$(GREEN='\033[0;32m' BOLD='\033[1m' NC='\033[0m' bash -c "${completion_line}")
    [[ "${completion_output}" == *$'\033[0;32m'* ]] || fail "${file}: completion output did not interpret ANSI colors"
    if grep -Fq '\033' <<< "${completion_output}"; then
        fail "${file}: completion output contained literal ANSI escape text"
    fi
done

# Every Bash entry point must flush and upload a failed run exactly once while
# preserving the setup task's original status.
for file in "${bash_setup_scripts[@]}"; do
    log_test_root=$(mktemp -d)
    mkdir -p "${log_test_root}/home"
    failure_output=$(SETUP_SCRIPT="${repo_root}/${file}" SOURCE_WITHOUT_MAIN="${source_without_main}" \
        HOME="${log_test_root}/home" UPLOAD_CALLS="${log_test_root}/upload-calls" TEST_FILE="${file}" bash -c '
            source <(sed "${SOURCE_WITHOUT_MAIN}" "${SETUP_SCRIPT}")
            run_setup_tasks() {
                print_error "simulated setup failure"
                if [[ "${TEST_FILE}" == "bazzite.sh" ]]; then
                    (exec sleep 30) &
                    SUDO_KEEPALIVE_PID=$!
                    trap stop_sudo_keepalive EXIT
                fi
                return 23
            }
            curl() {
                local argument=""
                local uploaded_log=""
                for argument in "$@"; do
                    case "${argument}" in
                        file=@*) uploaded_log="${argument#file=@}" ;;
                    esac
                done
                [[ -n "${uploaded_log}" ]] || return 90
                grep -q "simulated setup failure" "${uploaded_log}" || return 91
                printf "%s\n" "${uploaded_log}" >> "${UPLOAD_CALLS}"
            }
            setup_status=0
            main || setup_status=$?
            printf "status=%s\n" "${setup_status}"
        ')
    grep -q '^status=23$' <<< "${failure_output}" || fail "${file}: log finalization changed the failure status"
    grep -q 'Run log saved to:' <<< "${failure_output}" || fail "${file}: failed run did not report the local log path"
    [[ -f "${log_test_root}/upload-calls" ]] || fail "${file}: failed run did not attempt a log upload"
    upload_count=$(wc -l < "${log_test_root}/upload-calls") || fail "${file}: could not count failed-run uploads"
    [[ "${upload_count}" -eq 1 ]] || fail "${file}: failed run attempted more than one log upload"
    rm -rf "${log_test_root}"
done

# Successful runs use the same single finalization path.
log_test_root=$(mktemp -d)
mkdir -p "${log_test_root}/home"
success_output=$(SETUP_SCRIPT="${repo_root}/wsl.sh" SOURCE_WITHOUT_MAIN="${source_without_main}" \
    HOME="${log_test_root}/home" UPLOAD_CALLS="${log_test_root}/upload-calls" bash -c '
        source <(sed "${SOURCE_WITHOUT_MAIN}" "${SETUP_SCRIPT}")
        run_setup_tasks() {
            print_success "simulated setup success"
        }
        curl() {
            local argument=""
            local uploaded_log=""
            for argument in "$@"; do
                case "${argument}" in
                    file=@*) uploaded_log="${argument#file=@}" ;;
                esac
            done
            grep -q "simulated setup success" "${uploaded_log}" || return 91
            printf "%s\n" "${uploaded_log}" >> "${UPLOAD_CALLS}"
        }
        setup_status=0
        main || setup_status=$?
        printf "status=%s\n" "${setup_status}"
    ')
grep -q '^status=0$' <<< "${success_output}" || fail 'wsl.sh: successful log finalization returned failure'
upload_count=$(wc -l < "${log_test_root}/upload-calls") || fail 'wsl.sh: could not count successful-run uploads'
[[ "${upload_count}" -eq 1 ]] || fail 'wsl.sh: successful run did not upload exactly once'
rm -rf "${log_test_root}"

# Collector failures warn with the local fallback without masking setup status.
log_test_root=$(mktemp -d)
mkdir -p "${log_test_root}/home"
upload_failure_output=$(SETUP_SCRIPT="${repo_root}/mac.sh" SOURCE_WITHOUT_MAIN="${source_without_main}" \
    HOME="${log_test_root}/home" UPLOAD_CALLS="${log_test_root}/upload-calls" bash -c '
        source <(sed "${SOURCE_WITHOUT_MAIN}" "${SETUP_SCRIPT}")
        run_setup_tasks() {
            print_error "simulated setup failure"
            return 23
        }
        curl() {
            printf "attempt\n" >> "${UPLOAD_CALLS}"
            return 7
        }
        setup_status=0
        main || setup_status=$?
        printf "status=%s\n" "${setup_status}"
    ')
grep -q '^status=23$' <<< "${upload_failure_output}" || fail 'mac.sh: collector failure masked the setup status'
grep -q 'Failed to upload setup log. Local log remains at ' <<< "${upload_failure_output}" || fail 'mac.sh: collector failure lacked the local log fallback'
upload_count=$(wc -l < "${log_test_root}/upload-calls") || fail 'mac.sh: could not count failed upload attempts'
[[ "${upload_count}" -eq 1 ]] || fail 'mac.sh: collector failure triggered multiple attempts'
rm -rf "${log_test_root}"

# Apt-managed gcloud installations must skip the slow Python CLI startup. The
# system package upgrade earlier in each script already updates this package.
for file in "${linux_apt_scripts[@]}"; do
    output=$(SETUP_SCRIPT="${repo_root}/${file}" SOURCE_WITHOUT_MAIN="${source_without_main}" bash -c '
        source <(sed "${SOURCE_WITHOUT_MAIN}" "${SETUP_SCRIPT}")
        dpkg-query() {
            if [[ "${*: -1}" == "google-cloud-cli" ]]; then
                printf "%s" "install ok installed"
                return 0
            fi
            return 1
        }
        gcloud() {
            sleep 1
            printf "%s\n" "unexpected gcloud invocation"
            return 1
        }
        update_gcloud_components
    ')
    grep -q 'managed by apt; skipping component update' <<< "${output}" || fail "${file}: apt-managed gcloud did not use the fast skip path"
    if grep -q 'unexpected gcloud invocation' <<< "${output}"; then
        fail "${file}: apt-managed gcloud launched the slow component manager"
    fi
done

# Reproduce gcloud's wrapped package-manager message at the real function seam.
for file in "${bash_setup_scripts[@]}"; do
    output=$(SETUP_SCRIPT="${repo_root}/${file}" SOURCE_WITHOUT_MAIN="${source_without_main}" bash -c '
        source <(sed "${SOURCE_WITHOUT_MAIN}" "${SETUP_SCRIPT}")
        dpkg-query() { return 1; }
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

# Completed macOS policy and SSH setup must not request sudo again.
upload_output=$(SETUP_SCRIPT="${repo_root}/mac.sh" SOURCE_WITHOUT_MAIN="${source_without_main}" bash -c '
    source <(sed "${SOURCE_WITHOUT_MAIN}" "${SETUP_SCRIPT}")
    WORK_MACHINE=1
    grep() {
        if [[ "${*: -1}" == "/etc/hosts" ]]; then
            return 0
        fi
        command grep "$@"
    }
    can_sudo() { printf "%s\n" "unexpected can_sudo"; return 90; }
    sudo() { printf "%s\n" "unexpected sudo: $*"; return 90; }
    block_public_upload_services
')
grep -q 'Public upload services already blocked' <<< "${upload_output}" || fail 'mac.sh: existing upload block marker was not recognized'
if grep -q 'unexpected' <<< "${upload_output}"; then
    fail 'mac.sh: existing upload block marker still requested sudo'
fi

ssh_output=$(SETUP_SCRIPT="${repo_root}/mac.sh" SOURCE_WITHOUT_MAIN="${source_without_main}" bash -c '
    source <(sed "${SOURCE_WITHOUT_MAIN}" "${SETUP_SCRIPT}")
    launchctl() { [[ "$*" == "print system/com.openssh.sshd" ]]; }
    grep() {
        if [[ "${*: -1}" == "/etc/ssh/sshd_config" ]]; then
            return 0
        fi
        command grep "$@"
    }
    can_sudo() { printf "%s\n" "unexpected can_sudo"; return 90; }
    sudo() { printf "%s\n" "unexpected sudo: $*"; return 90; }
    enable_ssh
')
grep -q 'enabled and configured for key-only auth' <<< "${ssh_output}" || fail 'mac.sh: completed SSH setup was not recognized'
if grep -q 'unexpected' <<< "${ssh_output}"; then
    fail 'mac.sh: completed SSH setup still requested sudo'
fi

# Missing state still follows the existing privilege and mutation paths.
upload_tmp=$(mktemp -d)
upload_missing_output=$(SETUP_SCRIPT="${repo_root}/mac.sh" SOURCE_WITHOUT_MAIN="${source_without_main}" CALL_LOG="${upload_tmp}/calls" bash -c '
    source <(sed "${SOURCE_WITHOUT_MAIN}" "${SETUP_SCRIPT}")
    WORK_MACHINE=1
    grep() {
        if [[ "${*: -1}" == "/etc/hosts" ]]; then
            return 1
        fi
        command grep "$@"
    }
    can_sudo() { printf "%s\n" "can_sudo" >> "${CALL_LOG}"; return 0; }
    sudo() {
        printf "%s\n" "$*" >> "${CALL_LOG}"
        [[ "$1" == "tee" ]] && command cat >/dev/null
        return 0
    }
    block_public_upload_services
')
grep -q 'Blocked blocked public upload services' <<< "${upload_missing_output}" || fail 'mac.sh: missing upload block did not run the mutation path'
upload_sudo_checks=$(grep -c '^can_sudo$' "${upload_tmp}/calls" || true)
[[ "${upload_sudo_checks}" -eq 1 ]] || fail 'mac.sh: missing upload block did not request sudo exactly once'
grep -q '^tee -a /etc/hosts$' "${upload_tmp}/calls" || fail 'mac.sh: missing upload block did not update /etc/hosts'
rm -rf "${upload_tmp}"

ssh_tmp=$(mktemp -d)
ssh_missing_output=$(SETUP_SCRIPT="${repo_root}/mac.sh" SOURCE_WITHOUT_MAIN="${source_without_main}" CALL_LOG="${ssh_tmp}/calls" bash -c '
    source <(sed "${SOURCE_WITHOUT_MAIN}" "${SETUP_SCRIPT}")
    launchctl() { return 1; }
    grep() {
        if [[ "${*: -1}" == "/etc/ssh/sshd_config" ]]; then
            return 1
        fi
        command grep "$@"
    }
    can_sudo() { printf "%s\n" "can_sudo" >> "${CALL_LOG}"; return 0; }
    sudo() {
        printf "%s\n" "$*" >> "${CALL_LOG}"
        case "$1" in
            launchctl)
                [[ "$2" == "print" ]] && return 1
                return 0
                ;;
            systemsetup) return 0 ;;
            tee) command cat >/dev/null; return 0 ;;
            sed) return 0 ;;
        esac
        return 0
    }
    enable_ssh
')
grep -q 'SSH configured for key-only authentication' <<< "${ssh_missing_output}" || fail 'mac.sh: missing SSH state did not run the mutation path'
ssh_sudo_checks=$(grep -c '^can_sudo$' "${ssh_tmp}/calls" || true)
[[ "${ssh_sudo_checks}" -eq 1 ]] || fail 'mac.sh: missing SSH state did not request sudo exactly once'
grep -q '^systemsetup -setremotelogin on$' "${ssh_tmp}/calls" || fail 'mac.sh: missing SSH service was not enabled'
grep -q '^launchctl stop com.openssh.sshd$' "${ssh_tmp}/calls" || fail 'mac.sh: changed SSH configuration was not restarted'
rm -rf "${ssh_tmp}"

no_sudo_output=$(SETUP_SCRIPT="${repo_root}/mac.sh" SOURCE_WITHOUT_MAIN="${source_without_main}" bash -c '
    source <(sed "${SOURCE_WITHOUT_MAIN}" "${SETUP_SCRIPT}")
    WORK_MACHINE=1
    launchctl() { return 1; }
    grep() {
        case "${*: -1}" in
            /etc/hosts|/etc/ssh/sshd_config) return 1 ;;
        esac
        command grep "$@"
    }
    can_sudo() { return 1; }
    sudo() { printf "%s\n" "unexpected sudo: $*"; return 90; }
    block_public_upload_services
    enable_ssh
')
grep -q 'No sudo access — cannot block upload services' <<< "${no_sudo_output}" || fail 'mac.sh: missing upload block without sudo lacked its warning'
grep -q 'No sudo access — cannot enable SSH' <<< "${no_sudo_output}" || fail 'mac.sh: missing SSH state without sudo lacked its warning'
if grep -q 'unexpected sudo' <<< "${no_sudo_output}"; then
    fail 'mac.sh: unavailable sudo still attempted a privileged mutation'
fi

# These regexes intentionally use single quotes to preserve PowerShell variable syntax.
# shellcheck disable=SC2016
assert_contains win.ps1 '\$normalizedUpdateText[[:space:]]*=' 'normalized gcloud update output'
# shellcheck disable=SC2016
assert_contains win.ps1 '\$normalizedUpdateText -match "component manager is disabled\|managed by an external package manager"' 'normalized package-manager detection'
assert_not_contains win.ps1 '^[[:space:]]*exit 1[[:space:]]*$' 'host-terminating setup failure that bypasses log finalization'

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

# Homebrew can return success while skipping packages that remain outdated.
# Ignore setup's temporary tmux pin and user-pinned packages, but report every
# other residual item instead of printing a false success.
residual_brew_output=$(SETUP_SCRIPT="${repo_root}/mac.sh" SOURCE_WITHOUT_MAIN="${source_without_main}" bash -c '
    source <(sed "${SOURCE_WITHOUT_MAIN}" "${SETUP_SCRIPT}")
    brew() {
        case "$*" in
            update|upgrade|"pin tmux"|"unpin tmux") return 0 ;;
            untrust) printf "%s\n" "No untrusted taps, formulae, casks or commands." ;;
            "outdated --quiet") printf "%s\n" "tmux" "example/pinned/tool" "docker-desktop" ;;
            "list --pinned") printf "%s\n" "example/pinned/tool" ;;
        esac
        return 0
    }
    update_brew
')
grep -q 'Homebrew packages remain outdated after upgrade: docker-desktop' <<< "${residual_brew_output}" || fail 'mac.sh: residual Homebrew package lacked an actionable warning'
if grep -q 'Homebrew updated\.' <<< "${residual_brew_output}"; then
    fail 'mac.sh: residual outdated Homebrew package was reported as successful'
fi
if grep -q 'remain outdated.*\(tmux\|example/pinned/tool\)' <<< "${residual_brew_output}"; then
    fail 'mac.sh: intentionally pinned Homebrew package was reported as incomplete'
fi

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

# Bazzite trusts only managed formulae and recognizes casks idempotently.
assert_contains bazzite.sh 'brew trust --formula "\$\{item\}"' 'Bazzite item-level formula trust'
assert_contains bazzite.sh 'ensure_brew_formula_trusted "libsql/sqld/sqld"' 'Bazzite libsql trust'
assert_contains bazzite.sh 'ensure_brew_formula_trusted "tursodatabase/tap/turso"' 'Bazzite Turso trust'
assert_contains bazzite.sh 'ensure_brew_formula_trusted "dopplerhq/doppler/doppler"' 'Bazzite Doppler trust'
assert_not_contains bazzite.sh 'brew trust (dopplerhq|libsql|tursodatabase)/' 'Bazzite whole-tap trust'
assert_contains bazzite.sh 'HOMEBREW_NO_AUTO_UPDATE=1' 'Bazzite install-time auto-update suppression'
assert_contains bazzite.sh 'HOMEBREW_NO_INSTALL_CLEANUP=1' 'Bazzite install-time cleanup suppression'

bazzite_core_output=$(SETUP_SCRIPT="${repo_root}/bazzite.sh" SOURCE_WITHOUT_MAIN="${source_without_main}" bash -c '
    source <(sed "${SOURCE_WITHOUT_MAIN}" "${SETUP_SCRIPT}")
    ensure_brew_formula_trusted() { return 0; }
    brew() {
        case "$1 $2" in
            "list --formula")
                printf "%s\n" git curl wget jq unzip tmux starship gh chezmoi opentofu go uv fswatch tailscale act cloudflared turso shellcheck gitleaks lefthook mise poppler bubblewrap
                ;;
            "list --cask") printf "%s\n" 1password-cli ;;
            install*) printf "unexpected install: %s\n" "$*"; return 1 ;;
        esac
    }
    install_core_packages
')
grep -q '1password-cli cask is already installed' <<< "${bazzite_core_output}" || fail 'bazzite.sh: installed 1Password cask was not recognized'
if grep -q 'unexpected install' <<< "${bazzite_core_output}"; then
    fail 'bazzite.sh: idempotent core package check attempted an install'
fi

bazzite_trust_output=$(SETUP_SCRIPT="${repo_root}/bazzite.sh" SOURCE_WITHOUT_MAIN="${source_without_main}" bash -c '
    source <(sed "${SOURCE_WITHOUT_MAIN}" "${SETUP_SCRIPT}")
    brew() {
        if [[ "$1" == "tap" && "$#" -eq 1 ]]; then
            printf "%s\n" dopplerhq/doppler
        else
            printf "%s\n" "$*" >> "${BREW_CALL_LOG}"
        fi
    }
    BREW_CALL_LOG=$(mktemp)
    export BREW_CALL_LOG
    ensure_brew_formula_trusted dopplerhq/doppler/doppler dopplerhq/doppler
    cat "${BREW_CALL_LOG}"
    rm -f "${BREW_CALL_LOG}"
')
grep -q '^trust --formula dopplerhq/doppler/doppler$' <<< "${bazzite_trust_output}" || fail 'bazzite.sh: Doppler trust was not formula-scoped'

# The native Codex migration removes Bun ownership, installs a per-user
# standalone binary, and executes successfully with a PATH that cannot resolve
# Node.js.
codex_tmp=$(mktemp -d)
mkdir -p "${codex_tmp}/home"
cat > "${codex_tmp}/codex-binary" <<'EOF'
#!/bin/sh
command -v node >/dev/null 2>&1 && exit 42
printf '%s\n' 'codex-cli 9.9.9'
EOF
chmod +x "${codex_tmp}/codex-binary"
cat > "${codex_tmp}/installer" <<'EOF'
#!/bin/sh
[ "${CODEX_NON_INTERACTIVE:-}" = "1" ] || exit 43
mkdir -p "${HOME}/.local/bin"
cp "${CODEX_TMP}/codex-binary" "${HOME}/.local/bin/codex"
chmod +x "${HOME}/.local/bin/codex"
printf '%s\n' "standalone ${CODEX_NON_INTERACTIVE}" >> "${CODEX_TMP}/calls"
EOF
chmod +x "${codex_tmp}/installer"
codex_output=$(SETUP_SCRIPT="${repo_root}/bazzite.sh" SOURCE_WITHOUT_MAIN="${source_without_main}" CODEX_TMP="${codex_tmp}" HOME="${codex_tmp}/home" bash -c '
    source <(sed "${SOURCE_WITHOUT_MAIN}" "${SETUP_SCRIPT}")
    bun() {
        printf "%s\n" "$*" >> "${CODEX_TMP}/calls"
        [[ "$1 $2 $3" == "pm ls -g" ]] && printf "%s\n" "@openai/codex@9.9.9"
        return 0
    }
    claude_code_trusted_curl() {
        printf "%s\n" /mock/curl
    }
    claude_code_run_safely() {
        if [[ "$1" == "/mock/curl" ]]; then
            local output=""
            while [[ "$#" -gt 0 ]]; do
                if [[ "$1" == "-o" ]]; then
                    output="$2"
                    break
                fi
                shift
            done
            cp "${CODEX_TMP}/installer" "${output}"
            printf "%s\n" download >> "${CODEX_TMP}/calls"
            return 0
        fi
        "$@"
    }
    install_codex_cli
')
grep -q 'Codex CLI installed/updated (codex-cli 9.9.9)' <<< "${codex_output}" || fail 'bazzite.sh: native Codex smoke test did not succeed'
grep -q '^remove -g @openai/codex$' "${codex_tmp}/calls" || fail 'bazzite.sh: legacy Bun Codex was not removed'
grep -q '^download$' "${codex_tmp}/calls" || fail 'bazzite.sh: official Codex installer was not downloaded'
grep -q '^standalone 1$' "${codex_tmp}/calls" || fail 'bazzite.sh: Codex installer was not run non-interactively'

cat > "${codex_tmp}/codex-binary" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod +x "${codex_tmp}/codex-binary"
if SETUP_SCRIPT="${repo_root}/bazzite.sh" SOURCE_WITHOUT_MAIN="${source_without_main}" CODEX_TMP="${codex_tmp}" HOME="${codex_tmp}/home" bash -c '
    source <(sed "${SOURCE_WITHOUT_MAIN}" "${SETUP_SCRIPT}")
    bun() {
        return 0
    }
    claude_code_trusted_curl() {
        printf "%s\n" /mock/curl
    }
    claude_code_run_safely() {
        if [[ "$1" == "/mock/curl" ]]; then
            local output=""
            while [[ "$#" -gt 0 ]]; do
                if [[ "$1" == "-o" ]]; then
                    output="$2"
                    break
                fi
                shift
            done
            cp "${CODEX_TMP}/installer" "${output}"
            return 0
        fi
        "$@"
    }
    install_codex_cli
' > "${codex_tmp}/failure-output" 2>&1; then
    fail 'bazzite.sh: failed Codex smoke test returned success'
fi
grep -q 'smoke test failed without Node.js' "${codex_tmp}/failure-output" || fail 'bazzite.sh: failed Codex smoke test lacked diagnosis'
rm -rf "${codex_tmp}"

# Bazzite path aliases are canonicalized before Pi provenance checks.
path_tmp=$(mktemp -d)
mkdir -p "${path_tmp}/var/home/tester/.local/bin"
touch "${path_tmp}/var/home/tester/.local/bin/pi"
ln -s var/home "${path_tmp}/home"
SETUP_SCRIPT="${repo_root}/bazzite.sh" SOURCE_WITHOUT_MAIN="${source_without_main}" PATH_TMP="${path_tmp}" bash -c '
    source <(sed "${SOURCE_WITHOUT_MAIN}" "${SETUP_SCRIPT}")
    path_is_within_prefix "${PATH_TMP}/home/tester/.local/bin/pi" "${PATH_TMP}/home/tester/.local"
    ! path_is_within_prefix /bin/true "${PATH_TMP}/home/tester/.local"
' || fail 'bazzite.sh: /home and /var/home aliases were not treated as the same Pi prefix'
rm -rf "${path_tmp}"

# Tailscale preference parsing accepts formatted JSON and verifies the mutation.
tailscale_output=$(SETUP_SCRIPT="${repo_root}/bazzite.sh" SOURCE_WITHOUT_MAIN="${source_without_main}" bash -c '
    source <(sed "${SOURCE_WITHOUT_MAIN}" "${SETUP_SCRIPT}")
    TAILSCALE_ENABLED=false
    can_sudo() { return 0; }
    tailscale() {
        if [[ "$1 $2" == "debug prefs" ]]; then
            printf "{\n  \"RunSSH\": %s\n}\n" "${TAILSCALE_ENABLED}"
        elif [[ "$1 $2" == "set --ssh" ]]; then
            TAILSCALE_ENABLED=true
        fi
    }
    sudo() { shift; tailscale "$@"; }
    setup_tailscale_ssh
')
grep -q 'Tailscale SSH enabled' <<< "${tailscale_output}" || fail 'bazzite.sh: Tailscale SSH was not verified after mutation'

# Failed Bazzite Brew upgrades are fatal, truthful, and still unpin tmux.
bazzite_brew_output=$(SETUP_SCRIPT="${repo_root}/bazzite.sh" SOURCE_WITHOUT_MAIN="${source_without_main}" bash -c '
    source <(sed "${SOURCE_WITHOUT_MAIN}" "${SETUP_SCRIPT}")
    brew() {
        printf "%s\n" "$*" >> "${BREW_CALL_LOG}"
        [[ "$1" == "upgrade" ]] && return 1
        return 0
    }
    BREW_CALL_LOG=$(mktemp)
    export BREW_CALL_LOG
    status=0
    update_brew || status=$?
    printf "status=%s\n" "${status}"
    cat "${BREW_CALL_LOG}"
    rm -f "${BREW_CALL_LOG}"
')
grep -q 'Homebrew update/upgrade incomplete' <<< "${bazzite_brew_output}" || fail 'bazzite.sh: Brew failure lacks truthful error'
grep -q '^status=1$' <<< "${bazzite_brew_output}" || fail 'bazzite.sh: Brew failure was not fatal'
grep -q '^unpin tmux$' <<< "${bazzite_brew_output}" || fail 'bazzite.sh: tmux was not unpinned after Brew failure'
if grep -q 'Homebrew updated\.' <<< "${bazzite_brew_output}"; then
    fail 'bazzite.sh: failed Brew upgrade was reported as successful'
fi

assert_contains bazzite.sh 'command -v usermod' 'Bazzite usermod shell fallback'
assert_contains bazzite.sh 'getent passwd.*user_name' 'Bazzite post-change shell verification'
assert_contains bazzite.sh 'install_codex_cli \|\| return 1' 'fatal Codex main wiring'
assert_contains bazzite.sh 'verify_fish_development_tools \|\| return 1' 'fresh Fish toolchain verification'
assert_contains bazzite.sh 'Fresh Fish login smoke test failed for Node.js, Pi, or Codex' 'fresh-shell smoke diagnosis'
assert_contains bazzite.sh "printf '\\\\n%b%b✨ Setup complete!%b" 'interpreted ANSI completion output'

shell_tmp=$(mktemp -d)
cut_command=$(command -v cut)
grep_command=$(command -v grep)
ln -s "${cut_command}" "${shell_tmp}/cut"
ln -s "${grep_command}" "${shell_tmp}/grep"
shell_output=$(SETUP_SCRIPT="${repo_root}/bazzite.sh" SOURCE_WITHOUT_MAIN="${source_without_main}" SHELL_TMP="${shell_tmp}" bash -c '
    source <(sed "${SOURCE_WITHOUT_MAIN}" "${SETUP_SCRIPT}")
    SHELL_STATE=/bin/bash
    PATH="${SHELL_TMP}"
    whoami() { printf "%s\n" tester; }
    getent() { printf "tester:x:1000:1000::/home/tester:%s\n" "${SHELL_STATE}"; }
    can_sudo() { return 0; }
    usermod() { return 0; }
    sudo() {
        printf "%s\n" "$*" >> "${SHELL_TMP}/calls"
        [[ "$1" == "usermod" ]] && SHELL_STATE=/usr/bin/fish
        return 0
    }
    set_fish_as_default_shell
')
grep -q 'Fish shell set as default' <<< "${shell_output}" || fail 'bazzite.sh: usermod shell fallback did not verify successfully'
grep -q '^usermod --shell /usr/bin/fish tester$' "${shell_tmp}/calls" || fail 'bazzite.sh: missing-chsh path did not use usermod'

if SETUP_SCRIPT="${repo_root}/bazzite.sh" SOURCE_WITHOUT_MAIN="${source_without_main}" SHELL_TMP="${shell_tmp}" bash -c '
    source <(sed "${SOURCE_WITHOUT_MAIN}" "${SETUP_SCRIPT}")
    PATH="${SHELL_TMP}"
    whoami() { printf "%s\n" tester; }
    getent() { printf "%s\n" "tester:x:1000:1000::/home/tester:/bin/bash"; }
    can_sudo() { return 0; }
    usermod() { return 0; }
    sudo() { return 0; }
    set_fish_as_default_shell
' > "${shell_tmp}/failure-output" 2>&1; then
    fail 'bazzite.sh: unverified shell mutation returned success'
fi
grep -q 'Login shell verification failed' "${shell_tmp}/failure-output" || fail 'bazzite.sh: shell verification failure lacked diagnosis'
rm -rf "${shell_tmp}"

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
