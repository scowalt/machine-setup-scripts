#!/usr/bin/env bash
# Dynamic source-based harnesses intentionally override functions and globals.
# shellcheck disable=SC1090,SC1091,SC2034,SC2154,SC2312,SC2317
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "${repo_root}"

supported_linux=(ubuntu.sh pi.sh bazzite.sh)
supported_bash=(mac.sh "${supported_linux[@]}")
all_setup_bash=(mac.sh ubuntu.sh pi.sh bazzite.sh wsl.sh)

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

assert_order() {
    local file=$1
    local first=$2
    local second=$3
    local description=$4
    local first_line
    local second_line

    first_line=$(grep -nF "${first}" "${file}" | head -n 1 | cut -d: -f1 || true)
    second_line=$(grep -nF "${second}" "${file}" | head -n 1 | cut -d: -f1 || true)
    [[ -n "${first_line}" && -n "${second_line}" ]] || fail "${file}: cannot check order for ${description}"
    [[ "${first_line}" -lt "${second_line}" ]] || fail "${file}: wrong order for ${description}"
}

extract_paseo_block() {
    local file=$1
    awk '/PASEO_MANAGED_MARKER=/{in_block=1} /# Update Pi settings for the tintinweb subagents extension/{in_block=0} in_block {print}' "${file}"
}

assert_child_listener_audit() {
    local tmp_dir
    local pid_tree

    tmp_dir=$(mktemp -d)
    trap 'rm -rf "${tmp_dir}"' RETURN

    cat > "${tmp_dir}/ps" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == "-eo pid=,ppid=" ]]; then
    cat <<'ROWS'
100 1
101 100
102 101
ROWS
    exit 0
fi
exit 1
EOF

    cat > "${tmp_dir}/ss" <<'EOF'
#!/usr/bin/env bash
cat <<'ROWS'
LISTEN 0 511 127.0.0.1:6767 0.0.0.0:* users:(("Paseo Daemon",pid=102,fd=23))
ROWS
EOF

    chmod 700 "${tmp_dir}/ps" "${tmp_dir}/ss"

    (
        PATH="${tmp_dir}:${PATH}"
        # shellcheck source=../ubuntu.sh
        source ./ubuntu.sh
        pid_tree=$(paseo_service_process_pids 100 | paste -sd, -)
        [[ "${pid_tree}" == "100,101,102" ]] || fail "ubuntu.sh: listener audit process tree was ${pid_tree}, expected 100,101,102"
        paseo_listener_audit 100 >/dev/null
    )
}

assert_lingering_sudo_gate() {
    local tmp_dir

    tmp_dir=$(mktemp -d)
    trap 'rm -rf "${tmp_dir}"' RETURN
    mkdir -p "${tmp_dir}/home"

    (
        # shellcheck source=../ubuntu.sh
        source ./ubuntu.sh
        HOME="${tmp_dir}/home"

        whoami() { printf 'ScoBot\n'; }
        uname() { printf 'Linux\n'; }
        paseo_is_wsl_environment() { return 1; }
        paseo_is_container_environment() { return 1; }
        can_sudo() {
            touch "${tmp_dir}/sudo-checked"
            return 1
        }
        loginctl() {
            if [[ "$*" == *"--property=Linger"* ]]; then
                printf 'Linger=yes\n'
            fi
            return 0
        }
        systemctl() { return 0; }
        sudo() { fail "ubuntu.sh: invoked sudo when ScoBot lingering was already enabled"; }

        paseo_native_linux_preflight
        paseo_enable_lingering_strict
        [[ ! -e "${tmp_dir}/sudo-checked" ]] || fail "ubuntu.sh: checked sudo when ScoBot lingering was already enabled"
    )

    (
        # shellcheck source=../ubuntu.sh
        source ./ubuntu.sh
        HOME="${tmp_dir}/home"

        whoami() { printf 'ScoBot\n'; }
        uname() { printf 'Linux\n'; }
        paseo_is_wsl_environment() { return 1; }
        paseo_is_container_environment() { return 1; }
        can_sudo() {
            touch "${tmp_dir}/sudo-required"
            return 1
        }
        loginctl() {
            if [[ "$*" == *"--property=Linger"* ]]; then
                printf 'Linger=no\n'
            fi
            return 0
        }
        systemctl() { return 0; }
        print_error() { :; }

        if paseo_native_linux_preflight; then
            fail "ubuntu.sh: accepted disabled lingering without sudo"
        fi
        [[ -e "${tmp_dir}/sudo-required" ]] || fail "ubuntu.sh: did not check sudo when lingering needed enablement"
    )

    (
        # shellcheck source=../ubuntu.sh
        source ./ubuntu.sh
        HOME="${tmp_dir}/home"
        PASEO_TEST_LINGER=no

        whoami() { printf 'ScoBot\n'; }
        uname() { printf 'Linux\n'; }
        paseo_is_wsl_environment() { return 1; }
        paseo_is_container_environment() { return 1; }
        can_sudo() { return 0; }
        loginctl() {
            if [[ "$*" == *"--property=Linger"* ]]; then
                printf 'Linger=%s\n' "${PASEO_TEST_LINGER}"
            fi
            return 0
        }
        systemctl() { return 0; }
        sudo() {
            [[ "$*" == "loginctl enable-linger ScoBot" ]] || fail "ubuntu.sh: unexpected lingering sudo command: $*"
            PASEO_TEST_LINGER=yes
        }

        paseo_native_linux_preflight
        paseo_enable_lingering_strict
        [[ "${PASEO_TEST_LINGER}" == "yes" ]] || fail "ubuntu.sh: did not enable lingering when sudo was available"
    )
}

assert_managed_daemon_is_preserved() {
    local tmp_dir

    tmp_dir=$(mktemp -d)
    trap 'rm -rf "${tmp_dir}"' RETURN

    (
        # shellcheck source=../ubuntu.sh
        source ./ubuntu.sh
        PASEO_VALIDATED_CMD=/bin/true

        paseo_managed_service_is_active() {
            return 0
        }
        paseo_local_daemon_state() {
            fail "ubuntu.sh: queried daemon state even though the managed service was active"
        }
        paseo_run_with_timeout() {
            touch "${tmp_dir}/daemon-stopped"
        }

        stop_existing_paseo_daemon
        [[ ! -e "${tmp_dir}/daemon-stopped" ]] || fail "ubuntu.sh: stopped an already managed Paseo daemon"
    )
}

assert_unchanged_service_is_not_restarted() {
    local tmp_dir

    tmp_dir=$(mktemp -d)
    trap 'rm -rf "${tmp_dir}"' RETURN

    (
        # shellcheck source=../ubuntu.sh
        source ./ubuntu.sh
        HOME="${tmp_dir}/home"
        PASEO_SERVICE_PATH=/usr/bin
        PASEO_TEST_ACTIVE=0
        PASEO_TEST_SYSTEMCTL_LOG="${tmp_dir}/systemctl.log"

        paseo_enable_lingering_strict() {
            return 0
        }
        systemctl() {
            printf '%s\n' "$*" >> "${PASEO_TEST_SYSTEMCTL_LOG}"
            case "$*" in
                "--user is-active ${PASEO_SERVICE_NAME}") [[ "${PASEO_TEST_ACTIVE}" == "1" ]] ;;
                "--user start ${PASEO_SERVICE_NAME}") PASEO_TEST_ACTIVE=1 ;;
                "--user is-enabled ${PASEO_SERVICE_NAME}") return 0 ;;
                *) return 0 ;;
            esac
        }

        install_paseo_systemd_user_service
        : > "${PASEO_TEST_SYSTEMCTL_LOG}"
        PASEO_MANAGED_SERVICE_TOUCHED=0
        PASEO_PACKAGE_CHANGED=0
        PASEO_DAEMON_WRAPPER_CHANGED=0
        PASEO_SYSTEMD_SERVICE_CHANGED=0

        install_paseo_systemd_user_service

        if grep -Eq -- '--user (daemon-reload|start|restart)' "${PASEO_TEST_SYSTEMCTL_LOG}"; then
            fail "ubuntu.sh: reloaded or restarted an unchanged active Paseo service"
        fi
        [[ "${PASEO_MANAGED_SERVICE_TOUCHED}" == "0" ]] || fail "ubuntu.sh: marked an unchanged active Paseo service as touched"

        : > "${PASEO_TEST_SYSTEMCTL_LOG}"
        PASEO_PACKAGE_CHANGED=1
        install_paseo_systemd_user_service
        grep -qF -- "--user restart ${PASEO_SERVICE_NAME}" "${PASEO_TEST_SYSTEMCTL_LOG}" || fail "ubuntu.sh: did not restart Paseo after a package change"
    )
}

assert_managed_launchdaemon_is_preserved() {
    local tmp_dir

    tmp_dir=$(mktemp -d)
    trap 'rm -rf "${tmp_dir}"' RETURN

    (
        # Source only the Paseo definitions because mac.sh invokes main unconditionally.
        source <(extract_paseo_block mac.sh)
        PASEO_VALIDATED_CMD=/bin/true

        print_debug() { :; }

        paseo_managed_service_is_loaded() {
            return 0
        }
        paseo_local_daemon_state() {
            fail "mac.sh: queried daemon state even though the managed LaunchDaemon was loaded"
        }
        paseo_run_with_timeout() {
            touch "${tmp_dir}/daemon-stopped"
        }

        stop_existing_paseo_daemon
        [[ ! -e "${tmp_dir}/daemon-stopped" ]] || fail "mac.sh: stopped an already managed Paseo LaunchDaemon"
    )
}

assert_unchanged_launchdaemon_is_not_restarted() {
    local tmp_dir

    tmp_dir=$(mktemp -d)
    trap 'rm -rf "${tmp_dir}"' RETURN

    (
        # Source only the Paseo definitions because mac.sh invokes main unconditionally.
        source <(extract_paseo_block mac.sh)
        HOME="${tmp_dir}/home"
        PASEO_SERVICE_PATH=/usr/bin
        PASEO_TEST_LOADED=0
        PASEO_TEST_LAUNCHCTL_LOG="${tmp_dir}/launchctl.log"
        PASEO_TEST_PLIST="${tmp_dir}/paseo.plist"

        print_debug() { :; }
        print_success() { :; }
        print_error() { fail "$*"; }
        paseo_launchd_plist_path() {
            printf '%s\n' "${PASEO_TEST_PLIST}"
        }
        launchctl() {
            printf '%s\n' "$*" >> "${PASEO_TEST_LAUNCHCTL_LOG}"
            case "$*" in
                "print system/${PASEO_LAUNCHD_LABEL}") [[ "${PASEO_TEST_LOADED}" == "1" ]] ;;
                "bootstrap system ${PASEO_TEST_PLIST}") PASEO_TEST_LOADED=1 ;;
                "bootout system/${PASEO_LAUNCHD_LABEL}") PASEO_TEST_LOADED=0 ;;
                *) return 0 ;;
            esac
        }
        sudo() {
            local source_path=""
            local target_path=""

            case "$1" in
                launchctl)
                    shift
                    launchctl "$@"
                    ;;
                grep|cmp|chmod)
                    command "$@"
                    ;;
                chown)
                    return 0
                    ;;
                install)
                    source_path="${*: -2:1}"
                    target_path="${*: -1}"
                    command cp "${source_path}" "${target_path}"
                    command chmod 0644 "${target_path}"
                    ;;
                *)
                    fail "mac.sh test: unexpected sudo command: $*"
                    ;;
            esac
        }

        install_paseo_launchdaemon
        : > "${PASEO_TEST_LAUNCHCTL_LOG}"
        PASEO_MANAGED_SERVICE_TOUCHED=0
        PASEO_PACKAGE_CHANGED=0
        PASEO_DAEMON_WRAPPER_CHANGED=0
        PASEO_LAUNCHD_SERVICE_CHANGED=0

        install_paseo_launchdaemon

        if grep -Eq '^(bootout|bootstrap|kickstart)' "${PASEO_TEST_LAUNCHCTL_LOG}"; then
            fail "mac.sh: restarted an unchanged loaded Paseo LaunchDaemon"
        fi
        [[ "${PASEO_MANAGED_SERVICE_TOUCHED}" == "0" ]] || fail "mac.sh: marked an unchanged loaded Paseo LaunchDaemon as touched"

        : > "${PASEO_TEST_LAUNCHCTL_LOG}"
        PASEO_PACKAGE_CHANGED=1
        install_paseo_launchdaemon
        grep -qF "kickstart -k system/${PASEO_LAUNCHD_LABEL}" "${PASEO_TEST_LAUNCHCTL_LOG}" || fail "mac.sh: did not restart Paseo after a package change"

        : > "${PASEO_TEST_LAUNCHCTL_LOG}"
        PASEO_PACKAGE_CHANGED=0
        PASEO_SERVICE_PATH=/bin
        install_paseo_launchdaemon
        grep -qF "bootout system/${PASEO_LAUNCHD_LABEL}" "${PASEO_TEST_LAUNCHCTL_LOG}" || fail "mac.sh: did not unload Paseo after a plist change"
        grep -qF "bootstrap system ${PASEO_TEST_PLIST}" "${PASEO_TEST_LAUNCHCTL_LOG}" || fail "mac.sh: did not reload Paseo after a plist change"
    )
}

for file in "${all_setup_bash[@]}"; do
    bash -n "${file}"
    assert_contains "${file}" '# HEADLESS=1' 'HEADLESS env-local placeholder'
    assert_contains "${file}" 'Version [0-9]+' 'version banner'
done

for file in "${supported_bash[@]}"; do
    assert_contains "${file}" 'PASEO_MANAGED_MARKER="Managed by scowalt machine setup: headless-paseo-daemon"' 'managed artifact marker'
    assert_contains "${file}" 'PASEO_PACKAGE="@getpaseo/cli"' 'scoped Paseo package'
    assert_contains "${file}" 'daemon start --foreground' 'foreground daemon supervision command'
    assert_contains "${file}" 'daemon status --json' 'JSON health check'
    assert_contains "${file}" 'setup_headless_paseo_daemon \|\| return 1' 'fail-fast main wiring'
    assert_contains "${file}" '\$\{HEADLESS:-\}" != "1"' 'exact HEADLESS=1 no-op guard'
    assert_contains "${file}" 'stop_existing_paseo_daemon' 'manual daemon stop before managed service start'
    assert_contains "${file}" 'paseo_existing_managed_service_check' 'early unmanaged-service guard'
    assert_order "${file}" 'paseo_existing_managed_service_check || return 1' 'install_paseo_cli || return 1' 'unmanaged-service guard before package/service mutation'
    assert_contains "${file}" 'connectedDaemon.*reachable\|auth_required|reachable\|auth_required' 'local reachability acceptance contract'
    assert_contains "${file}" 'relayDisabled|relayEnabled|relayStatus' 'relay-not-disabled health guard'
    assert_contains "${file}" 'paseo_listener_audit' 'non-loopback listener audit'
    assert_contains "${file}" 'paseo_service_process_pids' 'listener audit checks service process tree'
    assert_contains "${file}" 'children\[_ppid\]' 'listener audit discovers child processes'
    assert_contains "${file}" 'paseo_effective_service_path\(\)' 'defined effective service PATH helper'
    assert_contains "${file}" 'paseo_run_with_timeout' 'bounded Paseo health checks'
    assert_contains "${file}" 'cannot audit listeners' 'fail-closed listener audit'
    assert_contains "${file}" 'cannot verify managed service ownership' 'fail-closed owner check'
    assert_contains "${file}" 'group/world-writable' 'unsafe executable path guard'
    assert_contains "${file}" 'paseo_harden_user_path_chain' 'user-owned install path permission hardening'
    assert_contains "${file}" 'paseo_existing_service_path' 'service PATH filters missing components'
    assert_contains "${file}" 'chmod go-w' 'permission hardening removes group/world write bits'
    assert_contains "${file}" 'perm -020.*perm -002|perm -002.*perm -020' 'group-or-world writable detection'

    paseo_block=$(extract_paseo_block "${file}")
    if grep -Eq 'paseo daemon pair|daemon pair' <<< "${paseo_block}"; then
        fail "${file}: Paseo setup block must not run or print pairing commands"
    fi
    if grep -Eq -- '--no-relay|--disable-relay|PASEO_.*RELAY.*=0|PASEO_.*RELAY.*=false' <<< "${paseo_block}"; then
        fail "${file}: Paseo setup block must not disable relay behavior"
    fi
    if grep -Eq '\.env\.local|source ' <<< "${paseo_block}"; then
        fail "${file}: Paseo service block must not source or copy ~/.env.local"
    fi
    if grep -Ei 'paseo|PASEO' <<< "${paseo_block}" | grep -Eiq 'ufw|firewall|iptables|0\.0\.0\.0|--host|--listen'; then
        fail "${file}: Paseo setup block must not open inbound ports or public listeners"
    fi
done

for file in "${supported_linux[@]}"; do
    assert_contains "${file}" 'paseo_native_linux_preflight' 'native Linux capability preflight'
    assert_contains "${file}" 'paseo_headless_platform_gate \|\| return 1' 'early native Linux WSL/container gate'
    assert_contains "${file}" 'paseo_is_wsl_environment' 'WSL rejection for native Linux scripts'
    assert_contains "${file}" 'paseo_is_container_environment' 'container rejection for native Linux scripts'
    assert_contains "${file}" 'paseo_user_lingering_enabled' 'existing lingering detection'
    assert_contains "${file}" 'loginctl enable-linger' 'strict linger enablement'
    assert_contains "${file}" 'systemctl --user daemon-reload' 'strict systemd reload'
    assert_contains "${file}" 'systemctl --user enable' 'systemd service enablement'
    assert_contains "${file}" 'systemctl --user restart' 'systemd service start/restart'
    assert_contains "${file}" 'paseo_managed_service_is_active' 'managed service activity detection'
    assert_contains "${file}" 'cmp -s.*_service_file' 'idempotent service definition comparison'
    assert_contains "${file}" 'leaving the active daemon running' 'unchanged active daemon preservation'
    assert_contains "${file}" 'WantedBy=default.target' 'systemd user-service boot target'
    assert_not_contains "${file}" 'network-online\.target' 'invalid user-unit dependency on system network target'
done

assert_contains mac.sh 'PASEO_MACOS_HEADLESS_CANARY' 'macOS canary gate'
assert_contains mac.sh '/Library/LaunchDaemons/\$\{PASEO_LAUNCHD_LABEL\}\.plist' 'macOS LaunchDaemon path'
assert_contains mac.sh '<key>UserName</key>' 'LaunchDaemon target user'
assert_contains mac.sh 'launchctl bootstrap system' 'LaunchDaemon bootstrap'
assert_contains mac.sh 'launchctl kickstart -k' 'LaunchDaemon kickstart'
assert_contains mac.sh 'paseo_managed_service_is_loaded' 'managed LaunchDaemon activity detection'
assert_contains mac.sh 'cmp -s.*_plist' 'idempotent LaunchDaemon plist comparison'
assert_contains mac.sh 'leaving the loaded daemon running' 'unchanged loaded LaunchDaemon preservation'
assert_not_contains mac.sh 'StandardOutPath|StandardErrorPath' 'root-domain LaunchDaemon logs in user-writable paths'

assert_contains ubuntu.sh 'HEADLESS_PASSWORDLESS_SUDO' 'explicit Ubuntu passwordless sudo opt-in'

assert_contains wsl.sh 'fail_unsupported_headless_paseo_daemon' 'WSL unsupported HEADLESS=1 guard'
assert_contains wsl.sh 'WSL cannot guarantee a no-login Paseo daemon' 'WSL clear unsupported message'
assert_order wsl.sh 'fail_unsupported_headless_paseo_daemon || return 1' '    create_env_local' 'WSL fails before env placeholder mutation'

assert_contains win.ps1 'Assert-HeadlessPaseoUnsupported' 'Windows unsupported HEADLESS=1 guard'
assert_contains win.ps1 'native Windows cannot guarantee a no-login Paseo daemon' 'Windows clear unsupported message'
assert_order win.ps1 '    Assert-HeadlessPaseoUnsupported' '    New-TokenPlaceholders' 'Windows fails before env placeholder mutation'

assert_contains README.md 'Headless Paseo daemon' 'README headless Paseo section'
assert_contains README.md 'ubuntu\.sh.*pi\.sh.*bazzite\.sh' 'README supported native Linux scripts'
assert_contains README.md 'macOS.*PASEO_MACOS_HEADLESS_CANARY=1' 'README macOS canary status'
assert_contains README.md 'WSL.*native Windows fail early' 'README unsupported WSL/Windows status'
assert_contains README.md 'does not run or print pairing material' 'README no-pairing contract'

assert_child_listener_audit
assert_lingering_sudo_gate
assert_managed_daemon_is_preserved
assert_unchanged_service_is_not_restarted
assert_managed_launchdaemon_is_preserved
assert_unchanged_launchdaemon_is_not_restarted

printf '✓ headless Paseo daemon contract checks passed\n'
