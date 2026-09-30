# Non-disruptive scheduling. Embedded verbatim; no Node, package manager or app dependency.
# Version 1 | Last changed: Separate ordinary setup from explicit maintenance
SETUP_MAINTENANCE_AUTHORIZED=0
SETUP_POLICY_READY=0
SETUP_POLICY_FAILED=0
SETUP_POLICY_DEFERRED=0
export -n SETUP_MAINTENANCE_AUTHORIZED SETUP_POLICY_READY SETUP_POLICY_FAILED SETUP_POLICY_DEFERRED

setup_policy_init() {
    SETUP_MAINTENANCE_AUTHORIZED=0
    SETUP_POLICY_READY=0
    SETUP_POLICY_FAILED=0
    SETUP_POLICY_DEFERRED=0
    case "$#:$*" in
        0:) ;;
        1:--maintenance)
            if [[ -n "${BB_THREAD_ID:-}${BB_ENVIRONMENT_ID:-}${BB_TERMINAL_ID:-}" ]]; then
                print_error 'Maintenance refused in a BB session. Use a separate non-BB terminal.'
                return 1
            fi
            SETUP_MAINTENANCE_AUTHORIZED=1 ;;
        *) print_error 'Unknown setup arguments. Use no arguments, or --maintenance outside BB.'; return 1 ;;
    esac
    SETUP_POLICY_READY=1
}

setup_policy_failure() {
    SETUP_POLICY_FAILED=1
    print_error "Failed: $1. Existing state was preserved; no automatic repair."
    return 1
}

setup_policy_defer() {
    SETUP_POLICY_DEFERRED=1
    print_message "Deferred: $1; maintenance required to preserve ongoing work. ${2:-Update availability was not checked.}"
}

# 75 means policy deferral, never readiness, current, or a failed inspection.
setup_require_maintenance() {
    if [[ "${SETUP_POLICY_READY:-0}" == 1 && "${SETUP_MAINTENANCE_AUTHORIZED:-0}" == 1 ]]; then
        return 0
    fi
    setup_policy_defer "$1"
    return 75
}

setup_trim() {
    SETUP_TRIMMED="${1#"${1%%[![:space:]]*}"}"
    SETUP_TRIMMED="${SETUP_TRIMMED%"${SETUP_TRIMMED##*[![:space:]]}"}"
}

setup_environment_value() {
    local value="$1" quote rest suffix index character previous=''
    quote="${value:0:1}"
    if [[ "${quote}" == '"' || "${quote}" == "'" ]]; then
        rest="${value:1}"
        [[ "${rest}" == *"${quote}"* ]] || return 1
        value="${rest%%"${quote}"*}"
        suffix="${rest#*"${quote}"}"
        if [[ -n "${suffix}" ]]; then
            [[ "${suffix}" == [[:space:]]* ]] || return 1
            setup_trim "${suffix}"
            [[ -z "${SETUP_TRIMMED}" || "${SETUP_TRIMMED}" == \#* ]] || return 1
        fi
    else
        for ((index=0; index<${#value}; index++)); do
            character="${value:index:1}"
            if [[ "${character}" == '#' && ( ${index} == 0 || "${previous}" == [[:space:]] ) ]]; then
                value="${value:0:index}"
                break
            fi
            previous="${character}"
        done
        setup_trim "${value}"; value="${SETUP_TRIMMED}"
        case "${value}" in *[[:space:]]*|*\"*|*\'*) return 1 ;; *) ;; esac
    fi
    # No escapes, interpolation, concatenation or multiline values. Backslashes
    # are literal data; quoted command-looking text is never evaluated.
    SETUP_ENV_VALUE="${value}"
}

# The documented dotenv format is data, not shell code. No eval/source or expansion.
# Unknown keys (including any purported saved maintenance permission) are ignored.
setup_load_environment() {
    local environment_file="${HOME}/.env.local" line key value
    [[ -e "${environment_file}" || -L "${environment_file}" ]] || return 0
    [[ -f "${environment_file}" && ! -L "${environment_file}" && -r "${environment_file}" ]] || { setup_policy_failure 'environment-file inspection'; return 1; }
    while IFS= read -r line || [[ -n "${line}" ]]; do
        setup_trim "${line%$'\r'}"; line="${SETUP_TRIMMED}"
        case "${line}" in ''|\#*) continue ;; *) ;; esac
        line="${line#export }"
        [[ "${line}" == *=* ]] || { setup_policy_failure 'unsupported environment-file statement'; return 1; }
        setup_trim "${line%%=*}"; key="${SETUP_TRIMMED}"
        [[ "${key}" =~ ^[A-Za-z_][A-Za-z_0-9]*$ ]] || { setup_policy_failure 'unsupported environment-file key'; return 1; }
        case "${key}" in
            HEADLESS|HEADLESS_PASSWORDLESS_SUDO|BB_SERVER|BB_DATA_DIR|BB_APP_NPM_PREFIX|WORK_MACHINE|MACHINE_TYPE|BAN_PI_MCP_ADAPTER|BAN_PI_GOAL_AUTORESEARCH|BAN_MATT_POCOCK_SKILLS|BAN_MATT_POCKOCK_SKILLS|GH_TOKEN|GH_TOKEN_SCOWALT|OP_SERVICE_ACCOUNT_TOKEN|ZAI_API_KEY|OPENCODE_GO_API_KEY|CLAUDE_CONFIG_DIR|CODEX_HOME|PI_CODING_AGENT_DIR) ;;
            *) continue ;;
        esac
        setup_trim "${line#*=}"; value="${SETUP_TRIMMED}"
        setup_environment_value "${value}" || { setup_policy_failure 'unsupported environment-file value'; return 1; }
        value="${SETUP_ENV_VALUE}"
        # BB_SERVER's explicit process value wins, including 0. HEADLESS's
        # WSL/Windows OR gate is checked independently before loading this file.
        [[ "${key}" != BB_SERVER || "${SETUP_ENTRY_PLATFORM:-}" != ubuntu || -z "${BB_SERVER:-}" ]] || continue
        export "${key}=${value}"
    done < "${environment_file}"
}

# Refuse linked descendants and writable/foreign boundaries. Only the established
# root-owned Linux /home -> /var/home alias is eligible; never normalize arbitrary links.
setup_safe_home() {
    local component path='' metadata owner mode uid kernel target
    local -a _setup_components=()
    [[ "${HOME}" == /* && "${HOME}" != / && "${HOME}" != *'/../'* && "${HOME}" != */.. ]] || return 1
    uid=$(id -u) || return 1
    local old_ifs="${IFS}"; IFS=/
    read -r -a _setup_components <<< "${HOME#/}"
    IFS="${old_ifs}"
    for component in "${_setup_components[@]}"; do
        [[ -n "${component}" && "${component}" != . ]] || return 1
        path="${path}/${component}"
        if [[ -L "${path}" ]]; then
            kernel=$(uname -s) || return 1
            target=$(readlink /home) || return 1
            [[ "${path}" == /home && "${kernel}" == Linux && "${target}" == /var/home ]] || return 1
            metadata=$(stat -c '%u %a' /home) || return 1
            [[ "${metadata%% *}" == 0 ]] || return 1
            for target in /var /var/home; do
                [[ -d "${target}" && ! -L "${target}" ]] || return 1
                metadata=$(stat -c '%u %a' "${target}") || return 1
                read -r owner mode <<< "${metadata}"
                [[ "${owner}" == 0 && "${mode}" =~ ^[0-7]{3,4}$ ]] || return 1
                (( (8#${mode} & 8#022) == 0 )) || return 1
            done
        fi
        [[ -d "${path}" ]] || return 1
        metadata=$(stat -Lc '%u %a' "${path}" 2>/dev/null || stat -Lf '%u %Lp' "${path}" 2>/dev/null) || return 1
        read -r owner mode <<< "${metadata}"
        [[ ( "${owner}" == 0 || "${owner}" == "${uid}" ) && "${mode}" =~ ^[0-7]{3,4}$ ]] || return 1
        if (( (8#${mode} & 8#022) != 0 )); then
            # Root-owned sticky temporary roots protect account-owned fixture/HOME entries.
            [[ "${owner}" == 0 ]] && (( (8#${mode} & 8#1000) != 0 )) || return 1
        fi
    done
    metadata=$(stat -c '%u %a' "${HOME}" 2>/dev/null || stat -f '%u %Lp' "${HOME}" 2>/dev/null) || return 1
    read -r owner mode <<< "${metadata}"
    [[ "${owner}" == "${uid}" && "${mode}" =~ ^[0-7]{3,4}$ ]] || return 1
    (( (8#${mode} & 8#022) == 0 ))
}

setup_safe_directory() {
    local target="$1" path="${HOME}" component metadata owner mode uid
    local -a _setup_components=()
    setup_safe_home || return 1
    [[ "${target}" == "${HOME}/"* ]] || return 1
    uid=$(id -u) || return 1
    local old_ifs="${IFS}"; IFS=/
    read -r -a _setup_components <<< "${target#"${HOME}/"}"
    IFS="${old_ifs}"
    for component in "${_setup_components[@]}"; do
        [[ -n "${component}" && "${component}" != . && "${component}" != .. ]] || return 1
        path="${path}/${component}"
        [[ ! -L "${path}" ]] || return 1
        if [[ ! -e "${path}" ]]; then
            (umask 077; mkdir -- "${path}") || return 1
        fi
        [[ -d "${path}" && ! -L "${path}" ]] || return 1
        metadata=$(stat -c '%u %a' "${path}" 2>/dev/null || stat -f '%u %Lp' "${path}" 2>/dev/null) || return 1
        read -r owner mode <<< "${metadata}"
        [[ "${owner}" == "${uid}" && "${mode}" =~ ^[0-7]{3,4}$ ]] || return 1
        (( (8#${mode} & 8#022) == 0 )) || return 1
    done
}

setup_safe_lock() {
    local XDG_RUNTIME_DIR="${HOME}/.local/state" lock_path metadata uid links mode
    setup_safe_directory "${XDG_RUNTIME_DIR}" || return 1
    for lock_path in "${XDG_RUNTIME_DIR}/machine-setup.lock" "${XDG_RUNTIME_DIR}/machine-setup.lock.d" "${XDG_RUNTIME_DIR}/machine-setup.lock.d.reclaim"; do
        [[ ! -L "${lock_path}" ]] || return 1
        [[ -e "${lock_path}" ]] || continue
        metadata=$(stat -c '%u %h %a' "${lock_path}" 2>/dev/null || stat -f '%u %l %Lp' "${lock_path}" 2>/dev/null) || return 1
        read -r uid links mode <<< "${metadata}"
        [[ -O "${lock_path}" && "${mode}" =~ ^[0-7]{3,4}$ ]] || return 1
        (( (8#${mode} & 8#022) == 0 )) || return 1
        [[ -d "${lock_path}" || ( -f "${lock_path}" && "${links}" == 1 ) ]] || return 1
    done
    acquire_setup_lock
}

setup_safe_code_directory() {
    local existed=0
    [[ ! -e "${HOME}/Code" ]] || existed=1
    setup_safe_directory "${HOME}/Code" || { setup_policy_failure 'Code directory safety/creation'; return 1; }
    if [[ "${existed}" == 1 ]]; then
        print_success 'Verified current: Code directory exists; contents unchanged.'
    else
        print_success 'Applied: created the missing Code directory; no existing files changed.'
    fi
}

# Query only named services setup actually configures. Never inventory or operate
# on unrelated services, never use enable/start/restart.
setup_observe_systemd_service() {
    local scope="$1" unit="$2" required="${3:-0}" state key value load='' active='' enabled='' result=''
    local -a args=()
    SETUP_SERVICE_EXPECTED_ACTIVE=0
    [[ "${scope}" != user ]] || args+=(--user)
    if ! state=$(systemctl "${args[@]}" show "${unit}" --property=LoadState,ActiveState,UnitFileState,Result 2>/dev/null); then
        setup_policy_failure 'service health inspection unavailable'; return 1
    fi
    while IFS='=' read -r key value; do
        case "${key}" in
            LoadState) load="${value}" ;; ActiveState) active="${value}" ;;
            UnitFileState) enabled="${value}" ;; Result) result="${value}" ;;
            '') ;; *) setup_policy_failure 'unrecognized service health response'; return 1 ;;
        esac
    done <<< "${state}"
    if [[ "${load}" == not-found ]]; then
        [[ "${required}" != 1 ]] || { setup_policy_failure 'existing managed service absent'; return 1; }
        return 0
    fi
    [[ "${load}" == loaded || "${load}" == masked ]] || { setup_policy_failure 'service load-state inspection'; return 1; }
    if [[ "${enabled}" == enabled || "${active}" == active ]]; then SETUP_SERVICE_EXPECTED_ACTIVE=1; fi
    if [[ "${active}" == failed || ( "${enabled}" == enabled && "${active}" != active ) || ( -n "${result}" && "${result}" != success ) ]]; then
        setup_policy_failure "service health (${unit})"; return 1
    fi
    case "${active}" in
        active) print_success "Verified current: ${unit} is active (not update freshness)." ;;
        inactive) print_debug "${unit} is intentionally inactive/disabled; unchanged." ;;
        *) setup_policy_failure 'unverified service activity'; return 1 ;;
    esac
}

setup_systemd_available() {
    [[ -d /run/systemd/system ]]
}

setup_readonly_python() {
    # Never resolve an account PATH/shim or trigger interpreter installation.
    local python path metadata owner mode magic
    python=$(/usr/bin/readlink -f /usr/bin/python3) || return 1
    [[ "${python}" =~ ^/usr/bin/python3\.[0-9]+$ && -f "${python}" && -x "${python}" ]] || return 1
    for path in / /usr /usr/bin "${python}"; do
        metadata=$(/usr/bin/stat -Lc '%u %a' -- "${path}") || return 1
        read -r owner mode <<< "${metadata}"
        [[ "${owner}" == 0 && "${mode}" =~ ^[0-7]{3,4}$ ]] || return 1
        (( (8#${mode} & 8#022) == 0 )) || return 1
    done
    magic=$(/usr/bin/od -An -tx1 -N4 "${python}") || return 1
    [[ "${magic//[[:space:]]/}" == 7f454c46 ]] || return 1
    "${python}" -I -S "$@"
}

setup_observe_bb_readiness() {
    setup_readonly_python - "${HOME}" >/dev/null 2>&1 <<'SETUP_READONLY_BB_PY'
import http.client
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys


def readiness(home):
    uid = os.getuid()

    def private_file(relative):
        descriptors = []
        try:
            parent = os.open(home, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
            descriptors.append(parent)
            for component in Path(relative).parts[:-1]:
                parent = os.open(component, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent)
                descriptors.append(parent)
            for descriptor in descriptors:
                info = os.fstat(descriptor)
                if info.st_uid != uid or info.st_mode & 0o022:
                    raise ValueError('directory boundary')
            descriptor = os.open(Path(relative).name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=parent)
            descriptors.append(descriptor)
            info = os.fstat(descriptor)
            if not stat.S_ISREG(info.st_mode) or info.st_uid != uid or info.st_nlink != 1 or info.st_mode & 0o077:
                raise ValueError('metadata boundary')
            with os.fdopen(os.dup(descriptor), 'rb') as stream:
                content = stream.read(1048577)
            after = os.fstat(descriptor)
            if len(content) > 1048576 or (info.st_size, info.st_mtime_ns, info.st_ctime_ns) != (after.st_size, after.st_mtime_ns, after.st_ctime_ns):
                raise ValueError('changed metadata')
            return content.decode('utf-8').strip()
        finally:
            for descriptor in reversed(descriptors):
                os.close(descriptor)

    bins = []
    root = str(home / '.local/share/mise/installs/node') + '/'
    for name in ('package-owner', 'package-owner.next'):
        try:
            owner = private_file('.config/setup-bb-server/' + name)
        except FileNotFoundError:
            continue
        if not owner.startswith(root) or not owner.endswith('/lib/node_modules/bb-app'):
            raise ValueError('owner record')
        version = owner[len(root):-len('/lib/node_modules/bb-app')]
        if not re.fullmatch(r'[A-Za-z0-9._+-]+', version) or version in ('.', '..'):
            raise ValueError('owner version')
        bins.append(str(Path(owner).parents[2] / 'bin/bb-app'))
    if not bins:
        raise ValueError('missing owner')
    result = subprocess.run(['/usr/bin/systemctl', '--user', 'show', 'setup-bb-app.service', '--property=MainPID', '--value'],
                            env={'PATH': '/usr/bin:/bin', 'LANG': 'C', 'XDG_RUNTIME_DIR': '/run/user/' + str(uid)},
                            stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=3, check=True)
    pid = result.stdout.strip()
    if not re.fullmatch(r'[1-9][0-9]*', pid):
        raise ValueError('process id')
    process = Path('/proc') / pid
    if process.stat().st_uid != uid:
        raise ValueError('process owner')
    arguments = (process / 'cmdline').read_bytes().decode().split('\0')
    expected = {str(Path(binary).resolve(strict=True)) for binary in bins}
    if not any(argument in bins or (argument and str(Path(argument).resolve()) in expected) for argument in arguments):
        raise ValueError('process identity')
    host_id = ''
    for name in ('host-id', 'auth.json', 'env.json'):
        try:
            content = private_file('.bb/' + name)
        except FileNotFoundError:
            continue
        if name == 'host-id':
            host_id = content
        else:
            data = json.loads(content)
            host_id = host_id or data.get('hostId') or data.get('env', {}).get('BB_HOST_ID', '')
    if not isinstance(host_id, str) or not host_id:
        raise ValueError('missing host identity')

    def response(port, endpoint):
        # Fixed numeric loopback, no proxy, redirects, authentication or app CLI.
        connection = http.client.HTTPConnection('127.0.0.1', port, timeout=2)
        try:
            connection.request('GET', endpoint)
            received = connection.getresponse()
            body = received.read(65537)
            if received.status != 200 or len(body) > 65536:
                raise ValueError('health response')
            return json.loads(body)
        finally:
            connection.close()

    health = response(38886, '/health')
    local = response(38887, '/status')
    if (health.get('ok') is not True or not isinstance(health.get('launchId'), str) or not health['launchId']
            or local.get('connected') is not True or local.get('hostId') != host_id
            or local.get('serverUrl', '').rstrip('/') not in ('http://127.0.0.1:38886', 'http://localhost:38886')):
        raise ValueError('unhealthy app or local execution')


if __name__ == '__main__':
    try:
        readiness(Path(sys.argv[1]))
    except Exception:
        sys.exit(1)  # No arbitrary exceptions, metadata, credentials or paths.
SETUP_READONLY_BB_PY
}

setup_observe_services() {
    local platform="$1" unit status=0 app_expected=0 SETUP_SERVICE_EXPECTED_ACTIVE=0
    case "${platform}" in
        ubuntu|pi|bazzite|wsl)
            # Non-systemd fresh/WSL systems have no manager to repair. An existing
            # managed BB deployment still requires a readable health inspection.
            if ! setup_systemd_available; then
                if [[ -e "${HOME}/.config/setup-bb-server" ]]; then
                    setup_policy_failure 'existing BB service manager unavailable'; return 1
                fi
                print_debug 'No systemd manager; service health not applicable.'
                return 0
            fi
            for unit in ssh.service tailscaled.service fail2ban.service; do
                setup_observe_systemd_service system "${unit}" || status=1
            done
            if [[ -e "${HOME}/.config/systemd/user/tmux.service" ]]; then
                setup_observe_systemd_service user tmux.service || status=1
            fi
            if [[ -e "${HOME}/.config/setup-bb-server" ]]; then
                for unit in setup-bb-app.service setup-bb-ingress.service; do
                    setup_observe_systemd_service user "${unit}" 1 || status=1
                    if [[ "${unit}" == setup-bb-app.service ]]; then app_expected="${SETUP_SERVICE_EXPECTED_ACTIVE}"; fi
                done
                # Do not execute Node, mise shims, app CLIs or package managers.
                # Missing trusted system Python is a failed observation, not repair.
                if [[ "${app_expected}" == 1 ]] && ! setup_observe_bb_readiness; then
                    setup_policy_failure 'existing BB app/local execution health' || true
                    status=1
                fi
            fi ;;
        mac)
            # No app launch and no sudo authorization just to observe launchd.
            if [[ -f /Library/LaunchDaemons/com.tailscale.tailscaled.plist ]]; then
                if ! launchctl print system/com.tailscale.tailscaled >/dev/null 2>&1; then
                    setup_policy_failure 'configured Tailscale launchd health'; status=1
                fi
            fi ;;
        *) setup_policy_failure 'unknown platform'; return 1 ;;
    esac
    return "${status}"
}

setup_safe_tasks() {
    local platform="$1" status=0 user
    print_section 'Non-disruptive setup'
    case "${platform}" in
        wsl) fail_unsupported_headless || return 1 ;;
        *) ;;
    esac
    setup_load_environment || status=1
    case "${platform}" in
        ubuntu|pi|bazzite) headless_platform_gate || return 1 ;;
        *) ;;
    esac
    case "${platform}" in
        mac) ;;
        *) ensure_not_root || return 1 ;;
    esac
    [[ "${platform}" != bazzite ]] || verify_bazzite_system || return 1
    if [[ "${platform}" == ubuntu ]]; then
        case "${BB_SERVER:-}" in ''|0|1) ;; *) setup_policy_failure 'invalid BB_SERVER selection' || true; status=1 ;; esac
    fi
    setup_safe_lock || { setup_policy_failure 'setup lock inspection/acquisition' || true; status=1; }
    # Each group owns its entire transitive effect boundary, including bootstrap
    # and verification commands that could load a shell hook or update a cache.
    setup_policy_defer 'system packages, CLT, package-manager bootstrap and cleanup' 'Dependent tool installations are deferred; update availability was not checked.'
    setup_policy_defer 'network, DNS, Tailscale, SSH, security, power and service changes'
    setup_observe_services "${platform}" || status=1
    setup_policy_defer 'dotfiles init/update/apply, credential bootstrap and token migration' 'Dependent shell activation and repair are deferred.'
    setup_policy_defer 'shared runtimes, npm policy and runtime-dependent tools' 'BB/Pi/skills and targeted dotfile repairs are deferred.'
    setup_policy_defer 'BB server, machine preparation and desktop installation' 'Existing sessions, endpoints, packages and configuration remain untouched.'
    setup_policy_defer 'agent executables, Pi profiles/auth/packages, skills and retirements' 'Opt-outs/retirements remain desired state, not completed cleanup.'
    setup_policy_defer 'terminal configuration, plugins, shell changes and user-service enablement'
    setup_policy_defer 'new automatic-updater configuration' 'Existing independent updater policy remains unchanged.'
    user=$(whoami) || { setup_policy_failure 'account inspection'; status=1; }
    [[ -n "${user}" ]] || { setup_policy_failure 'account identity unavailable' || true; status=1; }
    if [[ "${platform}" == mac ]]; then
        if is_main_user; then setup_safe_code_directory || status=1; fi
    elif [[ "${user}" == scowalt ]]; then
        setup_safe_code_directory || status=1
    fi
    check_pending_reboot
    return "${status}"
}

setup_policy_summary() {
    local status="$1"
    if [[ "${status}" != 0 || "${SETUP_POLICY_FAILED:-0}" != 0 ]]; then
        print_warning 'Setup completed with errors; required work/inspection failed.'
        [[ "${SETUP_POLICY_DEFERRED:-0}" != 1 ]] || print_warning 'Maintenance pending; deferred changes are not verified current.'
        return 1
    fi
    if [[ "${SETUP_POLICY_DEFERRED:-0}" == 1 ]]; then
        print_success 'Safe work completed; maintenance pending.'
        print_warning 'Freshness, including security updates, may be delayed. Run --maintenance from a separate non-BB terminal.'
    fi
}
