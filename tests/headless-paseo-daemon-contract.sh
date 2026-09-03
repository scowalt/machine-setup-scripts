#!/usr/bin/env bash
# Dynamic source-based harnesses intentionally override functions and globals.
# shellcheck disable=SC1090,SC1091,SC2030,SC2031,SC2034,SC2154,SC2310,SC2312,SC2317
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
    awk '/PASEO_MANAGED_MARKER=/{in_block=1} /# Remove Pi subagents extension/{in_block=0} in_block {print}' "${file}"
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
        PASEO_LISTEN_TARGET=127.0.0.1:6767
        pid_tree=$(paseo_service_process_pids 100 | paste -sd, -)
        [[ "${pid_tree}" == "100,101,102" ]] || fail "ubuntu.sh: listener audit process tree was ${pid_tree}, expected 100,101,102"
        paseo_listener_audit 100 >/dev/null
    )
}

assert_spawned_agent_listener_is_ignored() {
    local tmp_dir

    tmp_dir=$(mktemp -d)
    trap 'rm -rf "${tmp_dir}"' RETURN

    cat > "${tmp_dir}/ps" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == "-eo pid=,ppid=" ]]; then
    cat <<'ROWS'
100 1
101 100
102 101
103 102
ROWS
    exit 0
fi
exit 1
EOF

    cat > "${tmp_dir}/ss" <<'EOF'
#!/usr/bin/env bash
cat <<'ROWS'
LISTEN 0 511 127.0.0.1:6767 0.0.0.0:* users:(("Paseo Daemon",pid=102,fd=23))
LISTEN 0 511 0.0.0.0:4026 0.0.0.0:* users:(("agent server",pid=103,fd=24))
ROWS
EOF

    chmod 700 "${tmp_dir}/ps" "${tmp_dir}/ss"

    (
        PATH="${tmp_dir}:${PATH}"
        # shellcheck source=../ubuntu.sh
        source ./ubuntu.sh
        PASEO_LISTEN_TARGET=127.0.0.1:6767
        paseo_listener_audit 100 >/dev/null
    )
}

assert_daemon_secondary_nonloopback_listener_is_rejected() {
    local tmp_dir

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
LISTEN 0 511 0.0.0.0:4026 0.0.0.0:* users:(("Paseo Daemon",pid=102,fd=24))
ROWS
EOF

    chmod 700 "${tmp_dir}/ps" "${tmp_dir}/ss"

    (
        PATH="${tmp_dir}:${PATH}"
        # shellcheck source=../ubuntu.sh
        source ./ubuntu.sh
        PASEO_LISTEN_TARGET=127.0.0.1:6767
        print_error() { :; }
        if paseo_listener_audit 100 >/dev/null; then
            fail "ubuntu.sh: accepted a non-loopback listener owned by the Paseo daemon process"
        fi
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

assert_systemctl_user_environment() {
    (
        # shellcheck source=../ubuntu.sh
        source ./ubuntu.sh
        unset XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS

        id() {
            [[ "${1:-}" == "-u" ]] || fail "ubuntu.sh: unexpected id invocation: $*"
            printf '4242\n'
        }
        systemctl() {
            [[ "${XDG_RUNTIME_DIR:-}" == "/run/user/4242" ]] || fail "ubuntu.sh: did not set the canonical user runtime directory"
            [[ "${DBUS_SESSION_BUS_ADDRESS:-}" == "unix:path=/run/user/4242/bus" ]] || fail "ubuntu.sh: did not set the canonical user bus address"
            [[ "$*" == "--user show-environment" ]] || fail "ubuntu.sh: unexpected systemctl invocation: $*"
        }

        paseo_systemctl_user show-environment
    )
}

assert_bun_global_paseo_identity_check() {
    local tmp_dir

    tmp_dir=$(mktemp -d)
    trap 'rm -rf "${tmp_dir}"' RETURN
    mkdir -p "${tmp_dir}/bun-bin" "${tmp_dir}/cache-layout-without-package-name"
    printf '#!/usr/bin/env bash\n' > "${tmp_dir}/cache-layout-without-package-name/paseo-entry"
    chmod 700 "${tmp_dir}/cache-layout-without-package-name/paseo-entry"
    ln -s "../cache-layout-without-package-name/paseo-entry" "${tmp_dir}/bun-bin/paseo"

    (
        # shellcheck source=../ubuntu.sh
        source ./ubuntu.sh
        paseo_command_matches_bun_global \
            "${tmp_dir}/cache-layout-without-package-name/paseo-entry" \
            "${tmp_dir}/bun-bin" || fail "ubuntu.sh: rejected Bun's Paseo executable when its resolved path omitted the package name"

        if paseo_command_matches_bun_global /bin/true "${tmp_dir}/bun-bin"; then
            fail "ubuntu.sh: accepted an executable outside Bun's global paseo command"
        fi
    )
}

assert_untrusted_optional_service_path_is_filtered() {
    local tmp_dir

    tmp_dir=$(mktemp -d)
    trap 'rm -rf "${tmp_dir}"' RETURN
    mkdir -p "${tmp_dir}/trusted-bin" "${tmp_dir}/other-user-brew-bin"

    (
        # shellcheck source=../ubuntu.sh
        source ./ubuntu.sh

        paseo_path_is_group_or_world_writable() {
            return 1
        }
        paseo_path_owner_is_trusted() {
            [[ "$1" != "${tmp_dir}/other-user-brew-bin" ]]
        }

        filtered_path=$(paseo_trusted_service_path \
            "${tmp_dir}/trusted-bin:${tmp_dir}/other-user-brew-bin" 2>/dev/null)
        [[ "${filtered_path}" == "${tmp_dir}/trusted-bin" ]] || \
            fail "ubuntu.sh: did not filter an optional service PATH component owned by another user"
    )
}

assert_configured_paseo_listener_is_preserved() {
    local tmp_dir
    local wrapper

    tmp_dir=$(mktemp -d)
    trap 'rm -rf "${tmp_dir}"' RETURN
    mkdir -p "${tmp_dir}/home/.paseo" "${tmp_dir}/bin"

    printf '%s\n' '{"daemon":{"listen":"127.0.0.1:6768"}}' > "${tmp_dir}/home/.paseo/config.json"
    cat > "${tmp_dir}/bin/paseo" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == "daemon status --json" ]]; then
    printf '%s\n' '{"localDaemon":"running","connectedDaemon":"reachable","listen":"127.0.0.1:6767"}'
    exit 0
fi
exit 1
EOF
    chmod 700 "${tmp_dir}/bin/paseo"

    (
        # shellcheck source=../ubuntu.sh
        source ./ubuntu.sh
        HOME="${tmp_dir}/home"
        PASEO_VALIDATED_CMD="${tmp_dir}/bin/paseo"
        PASEO_VALIDATED_NODE=/bin/bash
        PASEO_SERVICE_PATH="${tmp_dir}/bin:/usr/bin:/bin"
        PASEO_LISTEN_TARGET=""

        write_paseo_daemon_wrapper >/dev/null
        wrapper="${HOME}/.local/bin/paseo-daemon-start"
        grep -qF "daemon start --foreground --listen '127.0.0.1:6768'" "${wrapper}" || \
            fail 'ubuntu.sh: generated wrapper did not preserve daemon.listen from Paseo configuration'
        if grep -qF -- "--listen '127.0.0.1:6767'" "${wrapper}"; then
            fail 'ubuntu.sh: generated wrapper replaced the configured Paseo listener with the default port'
        fi
    )
}

assert_occupied_configured_listener_is_rejected_before_service_start() {
    local tmp_dir

    tmp_dir=$(mktemp -d)
    trap 'rm -rf "${tmp_dir}"' RETURN
    mkdir -p "${tmp_dir}/home/.paseo" "${tmp_dir}/bin"

    printf '%s\n' '{"daemon":{"listen":"127.0.0.1:6768"}}' > "${tmp_dir}/home/.paseo/config.json"
    cat > "${tmp_dir}/bin/paseo" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == "daemon status --json" ]]; then
    printf '%s\n' '{"localDaemon":"stopped","connectedDaemon":"unreachable","listen":"127.0.0.1:6768"}'
    exit 0
fi
exit 1
EOF
    cat > "${tmp_dir}/bin/ss" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' 'LISTEN 0 511 127.0.0.1:6768 0.0.0.0:*'
EOF
    chmod 700 "${tmp_dir}/bin/paseo" "${tmp_dir}/bin/ss"

    (
        # shellcheck source=../ubuntu.sh
        source ./ubuntu.sh
        HOME="${tmp_dir}/home"
        PATH="${tmp_dir}/bin:${PATH}"
        HEADLESS=1

        uname() { printf 'Linux\n'; }
        paseo_native_linux_preflight() { return 0; }
        paseo_existing_managed_service_check() { return 0; }
        install_paseo_cli() {
            PASEO_VALIDATED_CMD="${tmp_dir}/bin/paseo"
            PASEO_VALIDATED_NODE=/bin/bash
            PASEO_SERVICE_PATH="${tmp_dir}/bin:/usr/bin:/bin"
        }
        stop_existing_paseo_daemon() { return 0; }
        install_paseo_systemd_user_service() { touch "${tmp_dir}/service-started"; }
        paseo_linux_service_pid() { return 0; }
        paseo_service_owner_check() { return 0; }
        wait_for_paseo_health() { return 0; }
        paseo_listener_audit() { return 0; }
        cleanup_paseo_managed_service() { return 0; }
        print_error() { :; }

        if setup_headless_paseo_daemon; then
            fail 'ubuntu.sh: accepted an occupied configured Paseo listener target'
        fi
        [[ ! -e "${tmp_dir}/service-started" ]] || \
            fail 'ubuntu.sh: started the managed service before rejecting its occupied listener target'
        [[ ! -e "${HOME}/.local/bin/paseo-daemon-start" ]] || \
            fail 'ubuntu.sh: replaced the managed wrapper before rejecting its occupied listener target'
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

assert_wedged_service_is_recovered() {
    local tmp_dir
    local reset_count
    local kill_count
    local restart_line
    local start_line

    tmp_dir=$(mktemp -d)
    trap 'rm -rf "${tmp_dir}"' RETURN

    (
        # shellcheck source=../ubuntu.sh
        source ./ubuntu.sh
        HOME="${tmp_dir}/home"
        PASEO_SERVICE_PATH=/usr/bin
        PASEO_ACTIVE_CHECK_ATTEMPTS=1
        PASEO_TEST_ACTIVE=1
        PASEO_TEST_SYSTEMCTL_LOG="${tmp_dir}/recovery-systemctl.log"

        paseo_enable_lingering_strict() { return 0; }
        sleep() { :; }
        paseo_systemctl_user() {
            printf '%s\n' "$*" >> "${PASEO_TEST_SYSTEMCTL_LOG}"
            case "$*" in
                "is-active ${PASEO_SERVICE_NAME}") [[ "${PASEO_TEST_ACTIVE}" == "1" ]] ;;
                "restart ${PASEO_SERVICE_NAME}") PASEO_TEST_ACTIVE=0; return 1 ;;
                "start ${PASEO_SERVICE_NAME}") PASEO_TEST_ACTIVE=1 ;;
                "is-enabled ${PASEO_SERVICE_NAME}") return 0 ;;
                *) return 0 ;;
            esac
        }

        install_paseo_systemd_user_service

        assert_order "${PASEO_TEST_SYSTEMCTL_LOG}" \
            "reset-failed ${PASEO_SERVICE_NAME}" \
            "kill ${PASEO_SERVICE_NAME} --kill-whom=all" \
            'wedged-service reset before orphan-cgroup cleanup'
        assert_order "${PASEO_TEST_SYSTEMCTL_LOG}" \
            "kill ${PASEO_SERVICE_NAME} --kill-whom=all" \
            "restart ${PASEO_SERVICE_NAME}" \
            'orphan-cgroup cleanup before changed-service restart'
        restart_line=$(grep -nFx "restart ${PASEO_SERVICE_NAME}" "${PASEO_TEST_SYSTEMCTL_LOG}" | head -n 1 | cut -d: -f1)
        start_line=$(grep -nFx "start ${PASEO_SERVICE_NAME}" "${PASEO_TEST_SYSTEMCTL_LOG}" | head -n 1 | cut -d: -f1)
        [[ "${restart_line}" -lt "${start_line}" ]] || fail 'ubuntu.sh: fallback start did not follow the inactive changed-service restart'

        reset_count=$(grep -cF "reset-failed ${PASEO_SERVICE_NAME}" "${PASEO_TEST_SYSTEMCTL_LOG}")
        kill_count=$(grep -cF "kill ${PASEO_SERVICE_NAME} --kill-whom=all" "${PASEO_TEST_SYSTEMCTL_LOG}")
        [[ "${reset_count}" -eq 2 ]] || fail "ubuntu.sh: expected two reset-failed recovery attempts, saw ${reset_count}"
        [[ "${kill_count}" -eq 2 ]] || fail "ubuntu.sh: expected two orphan-cgroup sweeps, saw ${kill_count}"
        [[ "${PASEO_TEST_ACTIVE}" == "1" ]] || fail 'ubuntu.sh: fallback recovery did not activate the Paseo service'
    )
}

assert_failed_initial_start_is_recovered() {
    local tmp_dir
    local start_count

    tmp_dir=$(mktemp -d)
    trap 'rm -rf "${tmp_dir}"' RETURN

    (
        # shellcheck source=../ubuntu.sh
        source ./ubuntu.sh
        HOME="${tmp_dir}/home"
        PASEO_SERVICE_PATH=/usr/bin
        PASEO_ACTIVE_CHECK_ATTEMPTS=1
        PASEO_TEST_ACTIVE=0
        PASEO_TEST_START_COUNT=0
        PASEO_TEST_SYSTEMCTL_LOG="${tmp_dir}/initial-start-systemctl.log"

        paseo_enable_lingering_strict() { return 0; }
        sleep() { :; }
        paseo_systemctl_user() {
            printf '%s\n' "$*" >> "${PASEO_TEST_SYSTEMCTL_LOG}"
            case "$*" in
                "is-active ${PASEO_SERVICE_NAME}") [[ "${PASEO_TEST_ACTIVE}" == "1" ]] ;;
                "start ${PASEO_SERVICE_NAME}")
                    PASEO_TEST_START_COUNT=$((PASEO_TEST_START_COUNT + 1))
                    if [[ "${PASEO_TEST_START_COUNT}" -eq 1 ]]; then
                        return 1
                    fi
                    PASEO_TEST_ACTIVE=1
                    ;;
                "is-enabled ${PASEO_SERVICE_NAME}") return 0 ;;
                *) return 0 ;;
            esac
        }

        install_paseo_systemd_user_service

        start_count=$(grep -cFx "start ${PASEO_SERVICE_NAME}" "${PASEO_TEST_SYSTEMCTL_LOG}")
        [[ "${start_count}" -eq 2 ]] || fail "ubuntu.sh: expected recovery after a failed initial start, saw ${start_count} start attempts"
        grep -qF "reset-failed ${PASEO_SERVICE_NAME}" "${PASEO_TEST_SYSTEMCTL_LOG}" || \
            fail 'ubuntu.sh: failed initial start did not reset the unit before retrying'
        grep -qF "kill ${PASEO_SERVICE_NAME} --kill-whom=all" "${PASEO_TEST_SYSTEMCTL_LOG}" || \
            fail 'ubuntu.sh: failed initial start did not sweep the orphan cgroup before retrying'
        [[ "${PASEO_TEST_ACTIVE}" == "1" ]] || fail 'ubuntu.sh: failed initial start was not recovered'
    )
}

assert_failed_recovery_captures_status() {
    local tmp_dir

    tmp_dir=$(mktemp -d)
    trap 'rm -rf "${tmp_dir}"' RETURN

    (
        # shellcheck source=../ubuntu.sh
        source ./ubuntu.sh
        HOME="${tmp_dir}/home"
        PASEO_SERVICE_PATH=/usr/bin
        PASEO_ACTIVE_CHECK_ATTEMPTS=1
        PASEO_TEST_SYSTEMCTL_LOG="${tmp_dir}/failed-recovery-systemctl.log"

        paseo_enable_lingering_strict() { return 0; }
        paseo_managed_service_is_active() { return 0; }
        sleep() { :; }
        paseo_systemctl_user() {
            printf '%s\n' "$*" >> "${PASEO_TEST_SYSTEMCTL_LOG}"
            case "$*" in
                "is-active ${PASEO_SERVICE_NAME}") return 1 ;;
                "is-enabled ${PASEO_SERVICE_NAME}") return 0 ;;
                "status ${PASEO_SERVICE_NAME} --no-pager") printf 'failed\n' ;;
                *) return 0 ;;
            esac
        }

        if install_paseo_systemd_user_service; then
            fail 'ubuntu.sh: accepted a Paseo service that stayed inactive after recovery'
        fi
        grep -qF "status ${PASEO_SERVICE_NAME} --no-pager" "${PASEO_TEST_SYSTEMCTL_LOG}" || \
            fail 'ubuntu.sh: failed Paseo recovery did not capture systemd status'
    )
}

assert_failed_cleanup_preserves_enablement() {
    local tmp_dir

    tmp_dir=$(mktemp -d)
    trap 'rm -rf "${tmp_dir}"' RETURN

    (
        # shellcheck source=../ubuntu.sh
        source ./ubuntu.sh
        PASEO_MANAGED_SERVICE_TOUCHED=1
        PASEO_TEST_SYSTEMCTL_LOG="${tmp_dir}/cleanup-systemctl.log"

        paseo_systemctl_user() {
            printf '%s\n' "$*" >> "${PASEO_TEST_SYSTEMCTL_LOG}"
        }

        cleanup_paseo_managed_service Linux
        grep -qF "stop ${PASEO_SERVICE_NAME}" "${PASEO_TEST_SYSTEMCTL_LOG}" || \
            fail 'ubuntu.sh: failed verification cleanup did not stop the touched service'
        if grep -qF "disable ${PASEO_SERVICE_NAME}" "${PASEO_TEST_SYSTEMCTL_LOG}"; then
            fail 'ubuntu.sh: failed verification cleanup disabled the Paseo service'
        fi
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
    assert_contains "${file}" 'PASEO_DEFAULT_LISTEN_TARGET="127\.0\.0\.1:6767"' 'default loopback daemon listener target'
    assert_contains "${file}" 'PASEO_LISTEN_TARGET=""' 'runtime-resolved managed listener target'
    assert_contains "${file}" 'paseo_resolve_listen_target' 'configured listener resolution'
    assert_contains "${file}" 'paseo_listener_target_available' 'pre-start listener collision check'
    assert_contains "${file}" 'daemon start --foreground --listen' 'foreground daemon supervision command with explicit listener'
    # shellcheck disable=SC2016 # Match the literal variable reference in each setup script.
    assert_order "${file}" 'paseo_listener_target_available "${_service_pid}" || return 1' 'write_paseo_daemon_wrapper || return 1' 'listener collision check before wrapper replacement'
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
    assert_contains "${file}" 'paseo_command_matches_bun_global' 'Bun global command identity validation'
    assert_contains "${file}" 'paseo_run_with_timeout' 'bounded Paseo health checks'
    assert_contains "${file}" 'cannot audit listeners' 'fail-closed listener audit'
    assert_contains "${file}" 'cannot verify managed service ownership' 'fail-closed owner check'
    assert_contains "${file}" 'group/world-writable' 'unsafe executable path guard'
    assert_contains "${file}" 'paseo_harden_user_path_chain' 'user-owned install path permission hardening'
    assert_contains "${file}" 'paseo_existing_service_path' 'service PATH filters missing components'
    assert_contains "${file}" 'paseo_trusted_service_path' 'service PATH filters untrusted optional components'
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
    assert_contains "${file}" 'paseo_systemctl_user\(\)' 'session-independent systemd user manager helper'
    assert_contains "${file}" 'DBUS_SESSION_BUS_ADDRESS="unix:path=\$\{_runtime_dir\}/bus"' 'canonical systemd user bus address'
    assert_contains "${file}" 'paseo_systemctl_user show-environment' 'systemd user manager preflight'
    assert_contains "${file}" 'paseo_systemctl_user daemon-reload' 'strict systemd reload'
    assert_contains "${file}" 'paseo_systemctl_user enable' 'systemd service enablement'
    assert_contains "${file}" 'paseo_systemctl_user restart' 'systemd service start/restart'
    assert_contains "${file}" 'paseo_managed_service_is_active' 'managed service activity detection'
    assert_contains "${file}" 'paseo_managed_service_is_active_strict' 'is-active verification with retry'
    assert_contains "${file}" 'paseo_systemctl_user reset-failed' 'failed-unit state reset'
    assert_contains "${file}" 'paseo_systemctl_user kill.*--kill-whom=all' 'orphan-cgroup cleanup'
    assert_contains "${file}" 'paseo_systemctl_user status.*--no-pager' 'failed-recovery systemd diagnostics'
    assert_not_contains "${file}" 'paseo_systemctl_user disable' 'failure cleanup that disables the managed service'
    assert_contains "${file}" '\--machine=.*@' 'machined-mediated user manager fallback'
    assert_contains "${file}" 'cmp -s.*_service_file' 'idempotent service definition comparison'
    assert_contains "${file}" 'leaving the active daemon running' 'unchanged active daemon preservation'
    assert_contains "${file}" 'WantedBy=default.target' 'systemd user-service boot target'
    assert_not_contains "${file}" 'network-online\.target' 'invalid user-unit dependency on system network target'
done

assert_contains mac.sh 'PASEO_MACOS_HEADLESS_CANARY' 'macOS canary gate'
assert_contains mac.sh 'Skipping headless Paseo daemon setup: macOS support is pending no-login validation' 'macOS non-canary HEADLESS=1 skip warning'
assert_order mac.sh 'Skipping headless Paseo daemon setup: macOS support is pending no-login validation' 'paseo_macos_preflight || return 1' 'canary skip happens before the preflight in setup_headless_paseo_daemon'
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

assert_macos_headless_noncanary_is_nonfatal() {
    (
        # Source mac.sh without invoking its entry point (main "$@").
        # shellcheck source=../mac.sh
        source <(sed 's/^main "\$@"$/:/' ./mac.sh)

        HEADLESS=1
        PASEO_MACOS_HEADLESS_CANARY=0
        uname() { printf 'Darwin\n'; }
        paseo_macos_preflight() {
            fail 'mac.sh: ran the macOS Paseo preflight when the canary gate was not set'
        }
        install_paseo_cli() {
            fail 'mac.sh: mutated the Paseo install when the canary gate was not set'
        }

        setup_headless_paseo_daemon
    )
}

assert_contains README.md 'Headless Paseo daemon' 'README headless Paseo section'
assert_contains README.md 'ubuntu\.sh.*pi\.sh.*bazzite\.sh' 'README supported native Linux scripts'
assert_contains README.md 'macOS.*PASEO_MACOS_HEADLESS_CANARY=1' 'README macOS canary status'
assert_contains README.md 'WSL.*native Windows fail early' 'README unsupported WSL/Windows status'
assert_contains README.md 'does not run or print pairing material' 'README no-pairing contract'

assert_child_listener_audit
assert_spawned_agent_listener_is_ignored
assert_daemon_secondary_nonloopback_listener_is_rejected
assert_lingering_sudo_gate
assert_systemctl_user_environment
assert_bun_global_paseo_identity_check
assert_untrusted_optional_service_path_is_filtered
assert_configured_paseo_listener_is_preserved
assert_occupied_configured_listener_is_rejected_before_service_start
assert_managed_daemon_is_preserved
assert_unchanged_service_is_not_restarted
assert_wedged_service_is_recovered
assert_failed_initial_start_is_recovered
assert_failed_recovery_captures_status
assert_failed_cleanup_preserves_enablement
assert_managed_launchdaemon_is_preserved
assert_unchanged_launchdaemon_is_not_restarted
assert_macos_headless_noncanary_is_nonfatal

printf '✓ headless Paseo daemon contract checks passed\n'
