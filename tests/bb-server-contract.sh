#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf -- "${tmp}"' EXIT
python_bin=$(python3 -c 'import sys; print(sys.executable)')
mkdir -p "${tmp}/interpreters"
ln -s "${python_bin}" "${tmp}/interpreters/python3"
export PATH="${tmp}/interpreters:${PATH}"
python3 - "${tmp}" <<'PY'
import pathlib, sys
sys.path.insert(0, str(pathlib.Path('tests').resolve()))
from extract_setup_fixture import definitions
source = pathlib.Path('ubuntu.sh').read_text()
pathlib.Path(sys.argv[1], 'helpers.sh').write_text(definitions(source))
PY

python3 tests/test_bb_server_diagnostics.py
python3 tests/test_bb_directory_preflight.py
python3 tests/test_bb_service_preflight.py
PYTHONDONTWRITEBYTECODE=1 python3 tests/test_bb_dotfiles_umask.py

for value in '' 0 1 invalid; do
    case "${value}" in ''|0) expected=1;; 1) expected=0;; *) expected=2;; esac
    result=0
    BB_SERVER="${value}" bash -c 'source "$1"; bb_server_selection' _ "${tmp}/helpers.sh" || result=$?
    [[ "${result}" -eq "${expected}" ]] || exit 1
done
HOME="/home/fixture" BB_TEST_HELPERS="${tmp}/helpers.sh" bash -c '
    source "$BB_TEST_HELPERS"
    bb_package_owner_path_valid "$HOME/.local/share/mise/installs/node/24.20.0/lib/node_modules/bb-app"
    ! bb_package_owner_path_valid "$HOME/.local/share/mise/installs/node/../../escape/lib/node_modules/bb-app"
    ! bb_package_owner_path_valid "$HOME/.local/share/mise/installs/node/24.20.0/nested/lib/node_modules/bb-app"
'
BB_TEST_HELPERS="${tmp}/helpers.sh" bash -c '
    source "$BB_TEST_HELPERS"
    print_error() { :; }
    systemctl() { printf "FragmentPath=%s\nDropInPaths=%s\n" "${BB_TEST_FRAGMENT:-}" "${BB_TEST_DROPINS:-}"; }
    bb_unit_preflight bb-app.service /home/fixture/.config/systemd/user/bb-app.service
    BB_TEST_FRAGMENT=/etc/systemd/user/bb-app.service
    ! bb_unit_preflight bb-app.service /home/fixture/.config/systemd/user/bb-app.service
    unset BB_TEST_FRAGMENT
    BB_TEST_DROPINS=/etc/systemd/user/bb-app.service.d/override.conf
    ! bb_unit_preflight bb-app.service /home/fixture/.config/systemd/user/bb-app.service
'
BB_TEST_HELPERS="${tmp}/helpers.sh" bash -c '
    source "$BB_TEST_HELPERS"
    uname() { printf "Linux\n"; }
    id() { printf "1000\n"; }
    bb_native_ubuntu_id() { printf "ubuntu\n"; }
    bb_server_platform_ready
    bb_native_ubuntu_id() { printf "debian\n"; }
    ! bb_server_platform_ready
    bb_native_ubuntu_id() { printf "ubuntu\n"; }
    id() { printf "0\n"; }
    ! bb_server_platform_ready
    id() { printf "1000\n"; }
    grep() { return 0; }
    ! bb_server_platform_ready
'
printf 'BB_SERVER=1\n' > "${tmp}/env.local"
for process in '' 0 1 bogus; do
    effective=$(BB_TEST_HELPERS="${tmp}/helpers.sh" BB_TEST_ENV="${tmp}/env.local" BB_SERVER="${process}" bash -c '
        source "$BB_TEST_HELPERS"; original="${BB_SERVER:-}"; source "$BB_TEST_ENV"; bb_server_restore_process_override "$original"; printf "%s" "$BB_SERVER"
    ')
    [[ "${effective}" == "${process:-1}" ]] || exit 1
done

mkdir -p "${tmp}/bin" "${tmp}/proc"
printf 'sl\n' > "${tmp}/proc/tcp"
printf 'sl\n' > "${tmp}/proc/tcp6"
cat > "${tmp}/bin/tailscale" <<'MOCK'
#!/usr/bin/env bash
case "$1 $2" in
    'version --daemon') printf '{"short":"%s","daemonLong":"%s-fixture"}\n' "${BB_TEST_VERSION:-1.102.4}" "${BB_TEST_VERSION:-1.102.4}";;
    'status --json') dns="$(<"${BB_TEST_DNS_FILE:-/dev/null}")"; printf '{"BackendState":"%s","Self":{"DNSName":"%s."}}\n' "${BB_TEST_BACKEND:-Running}" "${dns:-test.example.ts.net}";;
    serve\ *) shift; printf 'serve %s\n' "$*" >> "${BB_TEST_SERVE_LOG}"; if [[ "${BB_TEST_LONG_SERVE:-0}" == 1 ]]; then trap 'printf "killed\n" >> "${BB_TEST_SERVE_LOG}"; exit 0' TERM INT; while :; do /bin/sleep 1; done; fi;;
    *) exit 1;;
esac
MOCK
cat > "${tmp}/bin/curl" <<'MOCK'
#!/usr/bin/env bash
url="${*: -1}"
if [[ -n "${BB_TEST_CURL_FAIL_ONCE_FILE:-}" && -e "${BB_TEST_CURL_FAIL_ONCE_FILE}" ]]; then rm -f -- "${BB_TEST_CURL_FAIL_ONCE_FILE}"; exit 22; fi
[[ "${BB_TEST_CURL_FAIL:-0}" != 1 ]] || exit 22
case "${url}" in
    http://127.0.0.1:38886/health) printf 'native-health\n' >> "${BB_TEST_EVENTS}"; printf '{"ok":%s,"launchId":"%s"}\n' "${BB_TEST_HEALTH_OK:-true}" "${BB_TEST_LAUNCH_ID:-fixture-launch}";;
    http://127.0.0.1:38887/status) printf 'native-host-status\n' >> "${BB_TEST_EVENTS}"; host_id="${BB_TEST_HOST_ID:-}"; if [[ -z "${host_id}" && -f "${HOME}/.bb/host-id" ]]; then host_id=$(<"${HOME}/.bb/host-id"); fi; printf '{"connected":%s,"hostId":"%s","serverUrl":"%s"}\n' "${BB_TEST_HOST_CONNECTED:-true}" "${host_id:-fixture-host}" "${BB_TEST_HOST_URL:-http://127.0.0.1:38886}";;
    *) exit 0;;
esac
MOCK
cat > "${tmp}/bin/systemctl" <<'MOCK'
#!/usr/bin/env bash
args=" $* "
if [[ "${args}" == *' show '*MainPID* ]]; then cat "${BB_TEST_MAIN_PID_FILE}"; exit; fi
if [[ "${args}" == *' is-active '* ]]; then
    if [[ "${args}" == *' setup-bb-app.service '* ]]; then [[ -e "${BB_TEST_ROOT}/app-active" ]]; exit; fi
    if [[ "${args}" == *' setup-bb-ingress.service '* ]]; then [[ -e "${BB_TEST_ROOT}/ingress-active" ]]; exit; fi
    exit 1
fi
if [[ "${args}" == *' start --no-block setup-bb-ingress.service '* ]]; then
    printf 'ingress-queued\n' >> "${BB_TEST_EVENTS}"
    if [[ -n "${BB_TEST_UNIT_HOME:-}" ]]; then
        "${BB_TEST_RUNNER:-${BB_TEST_ROOT}/bin/run-systemd-unit}" ingress ExecStart || exit 1
    fi
    touch "${BB_TEST_ROOT}/ingress-active"
    exit 0
fi
exit 0
MOCK
cat > "${tmp}/bin/bb-app" <<'MOCK'
#!/usr/bin/env bash
printf 'bb-app %s\n' "$*" >> "${BB_TEST_APP_LOG}"
if [[ -n "${TMPDIR:-}" ]]; then printf 'tmpdir:%s\n' "${TMPDIR}" >> "${BB_TEST_APP_LOG}"; fi
if [[ "${BB_TEST_REQUIRE_INHERITED:-0}" == 1 ]]; then
    # New harmless child, not the app/provider: prove inheritance without values.
    /bin/bash --noprofile --norc -c '[[ ${BB_FIXTURE_INPUT:-} == "${BB_TEST_EXPECT_INPUT}" ]] && printf "inherited-child-ready\n"' >> "${BB_TEST_APP_LOG}" || exit 1
fi
if [[ "${BB_TEST_GENERATE_ID:-0}" == 1 ]]; then
    mkdir -p "${HOME}/.bb"; chmod 700 "${HOME}/.bb"
    if [[ ! -e "${HOME}/.bb/host-id" ]]; then (umask 077; set -C; printf 'fresh-fixture-host-id\n' > "${HOME}/.bb/host-id") 2>/dev/null || [[ -f "${HOME}/.bb/host-id" ]]; fi
fi
if [[ "${BB_TEST_LONG_BB:-0}" == 1 ]]; then trap 'exit 0' TERM INT; while :; do /bin/sleep 1; done; fi
MOCK
cat > "${tmp}/bin/sleep" <<'MOCK'
#!/usr/bin/env bash
if [[ "${1:-}" == 5 && -n "${BB_TEST_DNS_FILE:-}" && -e "${BB_TEST_RECONNECT_CHANGE:-}" ]]; then
    printf 'changed.example.ts.net\n' > "${BB_TEST_DNS_FILE}"
    rm -f -- "${BB_TEST_RECONNECT_CHANGE}"
fi
/bin/sleep 0.02
MOCK
cat > "${tmp}/bin/run-systemd-unit" <<'RUN_UNIT'
#!/usr/bin/env bash
set -euo pipefail
kind="$1" directive="$2"
unit_home="${HOME}"
unit_file="${unit_home}/.config/systemd/user/setup-bb-${kind}.service"
parsed=$(python3 - "${unit_file}" "${directive}" "${kind}" <<'PY'
import re, sys
from pathlib import Path
unit, directive, kind = sys.argv[1:]
env = {}
command = None
for line in open(unit, encoding="utf-8"):
    line = line.rstrip("\n")
    if line.startswith("Environment="):
        assignment = line[len("Environment="):]
        if any(char.isspace() for char in assignment) or any(char in assignment for char in "\"'`$\\"):
            raise SystemExit("unsupported generated systemd Environment syntax")
        key, separator, value = assignment.partition("=")
        if not separator or not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", key) or key in env or not value:
            raise SystemExit("invalid generated systemd Environment assignment")
        env[key] = value
    elif line.startswith(directive + "="):
        if command is not None:
            raise SystemExit("duplicate generated systemd command")
        command = line[len(directive) + 1:].split()
if command is None or len(command) != 2:
    raise SystemExit("missing or unsupported generated systemd command")
expected_mode = {("app", "ExecStart"): "app-start", ("app", "ExecStartPost"): "app-ready", ("ingress", "ExecStart"): "ingress-start"}.get((kind, directive))
if expected_mode is None or command[1] != expected_mode:
    raise SystemExit("unexpected generated systemd command")
for key in ("HOME", "PATH", "BB_PACKAGE_BINARY", "BB_TAILSCALE_BIN"):
    if not env.get(key):
        raise SystemExit("missing generated systemd environment: " + key)
if command[0] != env["HOME"] + "/.config/setup-bb-server/bb-guard":
    raise SystemExit("generated command does not use the managed guard")
override = Path(unit + '.d/10-tmpdir.conf')
if override.exists():
    expected = '[Service]\nEnvironment=TMPDIR=' + env['HOME'] + '/.cache/bb/tmp\n'
    if kind != 'app' or override.read_text() != expected:
        raise SystemExit('unsupported fixture drop-in')
    env['TMPDIR'] = env['HOME'] + '/.cache/bb/tmp'
references = [Path(unit + '.d/' + name) for name in ('env.conf', '20-env-local.conf')
              if Path(unit + '.d/' + name).exists()]
if references:
    if kind != 'app' or len(references) != 1 or references[0].read_bytes() != b'[Service]\nEnvironmentFile=%h/.env.local\n':
        raise SystemExit('unsupported fixture environment reference')
    # Only the path crosses the parser pipe. Source values are never printed.
    print('R\t' + env['HOME'] + '/.env.local')
for key, value in env.items():
    print("E\t" + key + "\t" + value)
for value in command:
    print("C\t" + value)
PY
) || exit 1
declare -a unit_env=() command=() fixture_env=()
unit_path='' unit_binary='' unit_home_value='' reference_source=''
while IFS=$'\t' read -r record key value; do
    case "${record}" in
        E)
            case "${key}" in
                HOME) unit_home_value="${value}"; unit_env+=("HOME=${value}");;
                PATH) unit_path="${value}";;
                BB_PACKAGE_BINARY) unit_binary="${value}"; unit_env+=("${key}=${value}");;
                BB_TAILSCALE_BIN) unit_env+=("${key}=${BB_TEST_TOOLS_DIR:-${BB_TEST_ROOT}/bin}/tailscale");;
                *) unit_env+=("${key}=${value}");;
            esac;;
        C) command+=("${key}");;
        R) reference_source="${key}";;
        *) exit 1;;
    esac
done <<< "${parsed}"
[[ -n "${unit_home_value}" && -n "${unit_path}" && -n "${unit_binary}" && ${#command[@]} -eq 2 ]] || exit 1
fixture_env=("PATH=${BB_TEST_TOOLS_DIR:-${BB_TEST_ROOT}/bin}:${unit_path}" "BB_TEST_UNIT_HOME=${unit_home_value}" "BB_TEST_RUNNER=${BB_TEST_RUNNER:-${BB_TEST_ROOT}/bin/run-systemd-unit}" "BB_TEST_TOOLS_DIR=${BB_TEST_TOOLS_DIR:-${BB_TEST_ROOT}/bin}" "BB_TEST_ROOT=${BB_TEST_ROOT}" "BB_TEST_DNS_FILE=${BB_TEST_DNS_FILE}" "BB_TEST_APP_LOG=${BB_TEST_APP_LOG}" "BB_TEST_SERVE_LOG=${BB_TEST_SERVE_LOG}" "BB_TEST_EVENTS=${BB_TEST_EVENTS}" "BB_TEST_MAIN_PID_FILE=${BB_TEST_ROOT}/main-pid" "BB_PROC_NET_ROOT=${BB_TEST_ROOT}/proc" "BB_TEST_LONG_BB=1")
for key in BB_READY_ATTEMPTS BB_READY_INTERVAL BB_TEST_CURL_FAIL BB_TEST_CURL_FAIL_ONCE_FILE BB_TEST_HEALTH_OK BB_TEST_LAUNCH_ID BB_TEST_HOST_CONNECTED BB_TEST_HOST_ID BB_TEST_HOST_URL BB_TEST_LONG_SERVE BB_TEST_RECONNECT_CHANGE BB_TEST_GENERATE_ID BB_TEST_REQUIRE_INHERITED BB_TEST_EXPECT_INPUT; do
    if [[ -n "${!key:-}" ]]; then fixture_env+=("${key}=${!key}"); fi
done
if [[ -n "${reference_source}" ]]; then
    [[ "${reference_source}" == "${unit_home_value}/.env.local" && "${unit_home_value}" == "${BB_TEST_ROOT}/"* ]] || exit 1
    # This fixture implements only a synthetic literal assignment, not a shell
    # source or a general EnvironmentFile parser. exec keeps MainPID identity.
    exec env -i "${unit_env[@]}" "${fixture_env[@]}" python3 - "${reference_source}" "${command[@]}" <<'INHERITED_INPUT'
import os, re, sys
from pathlib import Path
try:
    content = Path(sys.argv[1]).read_text()
except OSError:
    raise SystemExit('fixture required environment source unavailable') from None
match = re.fullmatch(r'BB_FIXTURE_INPUT=([A-Za-z0-9_-]+)\n', content)
if not match:
    raise SystemExit('unsupported fixture environment syntax')
environment = dict(os.environ, BB_FIXTURE_INPUT=match[1])
os.execvpe(sys.argv[2], sys.argv[2:], environment)
INHERITED_INPUT
fi
exec env -i "${unit_env[@]}" "${fixture_env[@]}" "${command[@]}"
RUN_UNIT
chmod +x "${tmp}/bin/"*

BB_TEST_ROOT="${tmp}" BB_TEST_HELPERS="${tmp}/helpers.sh" PATH="${tmp}/bin:${PATH}" bash <<'GUARD_FIXTURE'
set -euo pipefail
source "$BB_TEST_HELPERS"
export HOME="$BB_TEST_ROOT/guard-home" BB_TEST_ROOT
mkdir -p "$HOME/.bb" "$HOME/.config/setup-bb-server" "$BB_TEST_ROOT/proc"
chmod 700 "$HOME" "$HOME/.bb" "$HOME/.config" "$HOME/.config/setup-bb-server"
printf 'fixture-host\n' > "$HOME/.bb/host-id"; chmod 600 "$HOME/.bb/host-id"
printf 'test.example.ts.net 38443 https://test.example.ts.net:38443\n' > "$HOME/.config/setup-bb-server/endpoint"; chmod 600 "$HOME/.config/setup-bb-server/endpoint"
printf 'sl\n' > "$BB_TEST_ROOT/proc/tcp"; printf 'sl\n' > "$BB_TEST_ROOT/proc/tcp6"
export BB_TEST_DNS_FILE="$BB_TEST_ROOT/dns" BB_TEST_APP_LOG="$BB_TEST_ROOT/app.log" BB_TEST_SERVE_LOG="$BB_TEST_ROOT/serve.log" BB_TEST_EVENTS="$BB_TEST_ROOT/events" BB_TEST_MAIN_PID_FILE="$BB_TEST_ROOT/main-pid"
printf 'test.example.ts.net\n' > "$BB_TEST_DNS_FILE"
BB_TEST_LONG_BB=1 "$BB_TEST_ROOT/bin/bb-app" main-process >/dev/null 2>&1 & managed_pid=$!
printf '%s\n' "$managed_pid" > "$BB_TEST_MAIN_PID_FILE"
trap 'kill "$managed_pid" 2>/dev/null || true; wait "$managed_pid" 2>/dev/null || true' EXIT
bb_write_bb_guard "$HOME/.config/setup-bb-server/bb-guard"
guard="$HOME/.config/setup-bb-server/bb-guard"
run_guard() { env HOME="$HOME" PATH="$PATH" BB_TEST_ROOT="$BB_TEST_ROOT" BB_TEST_DNS_FILE="$BB_TEST_DNS_FILE" BB_TEST_APP_LOG="$BB_TEST_APP_LOG" BB_TEST_SERVE_LOG="$BB_TEST_SERVE_LOG" BB_TEST_EVENTS="$BB_TEST_EVENTS" BB_TEST_MAIN_PID_FILE="$BB_TEST_MAIN_PID_FILE" BB_PROC_NET_ROOT="$BB_TEST_ROOT/proc" BB_PACKAGE_BINARY="$BB_TEST_ROOT/bin/bb-app" BB_TAILSCALE_BIN="$BB_TEST_ROOT/bin/tailscale" "$guard" "$@"; }
run_guard app-start
[[ "$(grep -c '^bb-app start --bundled --data-dir ' "$BB_TEST_APP_LOG")" == 1 ]]
[[ "$(grep -c -- '--server-bind-host 127.0.0.1 --server-port 38886 --host-daemon-port 38887' "$BB_TEST_APP_LOG")" == 1 ]]
# A too-old daemon or changed DNS refuses to invoke the full launcher.
if env HOME="$HOME" PATH="$PATH" BB_TEST_DNS_FILE="$BB_TEST_DNS_FILE" BB_TEST_APP_LOG="$BB_TEST_APP_LOG" BB_TEST_SERVE_LOG="$BB_TEST_SERVE_LOG" BB_TEST_EVENTS="$BB_TEST_EVENTS" BB_PROC_NET_ROOT="$BB_TEST_ROOT/proc" BB_PACKAGE_BINARY="$BB_TEST_ROOT/bin/bb-app" BB_TAILSCALE_BIN="$BB_TEST_ROOT/bin/tailscale" BB_TEST_VERSION=1.102.3 "$guard" app-start; then exit 1; fi
printf 'other.example.ts.net\n' > "$BB_TEST_DNS_FILE"
if run_guard app-start; then exit 1; fi
printf 'test.example.ts.net\n' > "$BB_TEST_DNS_FILE"
# A known foreign local listener is detected before app execution.
printf 'sl\n  0: 0100007F:97E6 00000000:0000 0A 00000000:00000000 00:00000000 00000000 1000 0 1\n' > "$BB_TEST_ROOT/proc/tcp"
if run_guard app-start; then exit 1; fi
[[ "$(grep -c '^bb-app start --bundled' "$BB_TEST_APP_LOG")" == 1 ]]
printf 'sl\n' > "$BB_TEST_ROOT/proc/tcp"
# No ingress activation until both native BB readiness checks pass.
export BB_TEST_CURL_FAIL=1 BB_READY_ATTEMPTS=2 BB_READY_INTERVAL=0
if run_guard app-ready; then exit 1; fi
[[ ! -e "$BB_TEST_ROOT/ingress-active" ]]
unset BB_TEST_CURL_FAIL
export BB_TEST_HOST_CONNECTED=false
if run_guard app-ready; then exit 1; fi
[[ ! -e "$BB_TEST_ROOT/ingress-active" ]]
unset BB_TEST_HOST_CONNECTED
export BB_TEST_HEALTH_OK=false
if run_guard app-ready; then exit 1; fi
unset BB_TEST_HEALTH_OK
managed_pid=$(<"$BB_TEST_MAIN_PID_FILE")
printf '%s\n' "$BASHPID" > "$BB_TEST_MAIN_PID_FILE"
if run_guard app-ready; then exit 1; fi
[[ ! -e "$BB_TEST_ROOT/ingress-active" ]]
printf '%s\n' "$managed_pid" > "$BB_TEST_MAIN_PID_FILE"
run_guard app-ready
[[ -e "$BB_TEST_ROOT/ingress-active" ]]
# Ingress requires its app unit, native readiness, and Tailscale identity.
rm -f "$BB_TEST_ROOT/app-active" "$BB_TEST_ROOT/serve.log"
if run_guard ingress-start; then exit 1; fi
[[ ! -e "$BB_TEST_ROOT/serve.log" ]]
touch "$BB_TEST_ROOT/app-active"
printf '%s\n' "$BASHPID" > "$BB_TEST_MAIN_PID_FILE"
if run_guard ingress-start; then exit 1; fi
[[ ! -e "$BB_TEST_ROOT/serve.log" ]]
printf '%s\n' "$managed_pid" > "$BB_TEST_MAIN_PID_FILE"
run_guard ingress-start
[[ "$(<"$BB_TEST_ROOT/serve.log")" == 'serve --https=38443 http://127.0.0.1:38886' ]]
# The foreground watcher rechecks identity after reconnect and terminates its
# old Serve session instead of publishing a changed origin.
: > "$BB_TEST_ROOT/serve.log"
touch "$BB_TEST_ROOT/reconnect-change"
export BB_TEST_LONG_SERVE=1 BB_TEST_RECONNECT_CHANGE="$BB_TEST_ROOT/reconnect-change"
run_guard ingress-start & guard_pid=$!
for _ in {1..100}; do [[ -e "$BB_TEST_ROOT/serve.log" ]] && break; /bin/sleep 0.02; done
[[ -e "$BB_TEST_ROOT/serve.log" ]]
result=0; wait "$guard_pid" || result=$?
[[ "$result" -ne 0 ]]
grep -qx 'killed' "$BB_TEST_ROOT/serve.log"
GUARD_FIXTURE

BB_TEST_ROOT="${tmp}" BB_TEST_HELPERS="${tmp}/helpers.sh" PATH="${tmp}/bin:${PATH}" bash <<'SETUP_FIXTURE'
set -euo pipefail
source "$BB_TEST_HELPERS"
export BB_TEST_ROOT HOME="$BB_TEST_ROOT/setup-home" BB_TEST_EVENTS="$BB_TEST_ROOT/events" BB_TEST_APP_LOG="$BB_TEST_ROOT/app.log" BB_TEST_SERVE_LOG="$BB_TEST_ROOT/serve.log" BB_TEST_DNS_FILE="$BB_TEST_ROOT/dns"
export BB_TEST_RUNNER="${BB_TEST_RUNNER:-$BB_TEST_ROOT/bin/run-systemd-unit}"
trap 'if [[ -s "$BB_TEST_ROOT/main-pid" ]]; then app_pid=$(<"$BB_TEST_ROOT/main-pid"); kill "$app_pid" 2>/dev/null || true; wait "$app_pid" 2>/dev/null || true; fi' EXIT
mkdir -p "$HOME/.bb" "$HOME/.config/systemd/user" "$HOME/.local/share/mise/installs/node/24.20.0/bin" "$HOME/.local/share/mise/installs/node/24.20.0/lib/node_modules/bb-app/node_modules/fs-native-extensions" "$HOME/.local/bin"
chmod 700 "$HOME" "$HOME/.bb" "$HOME/.config" "$HOME/.config/systemd" "$HOME/.config/systemd/user" "$HOME/.local" "$HOME/.local/share" "$HOME/.local/share/mise" "$HOME/.local/share/mise/installs" "$HOME/.local/share/mise/installs/node" "$HOME/.local/share/mise/installs/node/24.20.0" "$HOME/.local/share/mise/installs/node/24.20.0/bin" "$HOME/.local/share/mise/installs/node/24.20.0/lib" "$HOME/.local/share/mise/installs/node/24.20.0/lib/node_modules" "$HOME/.local/share/mise/installs/node/24.20.0/lib/node_modules/bb-app" "$HOME/.local/share/mise/installs/node/24.20.0/lib/node_modules/bb-app/node_modules" "$HOME/.local/share/mise/installs/node/24.20.0/lib/node_modules/bb-app/node_modules/fs-native-extensions"
ln -s "$BB_TEST_ROOT/bin/bb-app" "$HOME/.local/share/mise/installs/node/24.20.0/bin/bb-app"
printf '{"name":"bb-app","version":"0.44.0"}\n' > "$HOME/.local/share/mise/installs/node/24.20.0/lib/node_modules/bb-app/package.json"
cat > "$HOME/.local/share/mise/installs/node/24.20.0/lib/node_modules/bb-app/node_modules/fs-native-extensions/index.js" <<'NODE'
const fs = require("fs");
let writerDone = false;
exports.tryLock = () => {
  if (process.env.BB_TEST_NATIVE_LOCK_FAIL !== "1") return true;
  if (!writerDone) {
    for (const file of [process.env.HOME + "/.bb/config.json", process.env.HOME + "/.bb/env.json"]) {
      const value = JSON.parse(fs.readFileSync(file, "utf8"));
      value.concurrentEditor = "latest";
      const temporary = file + ".fixture-tmp";
      fs.writeFileSync(temporary, JSON.stringify(value), { mode: 0o600 });
      fs.renameSync(temporary, file);
    }
    writerDone = true;
  }
  return false;
};
exports.unlock = () => {};
NODE
chmod 600 "$HOME/.local/share/mise/installs/node/24.20.0/lib/node_modules/bb-app/package.json" "$HOME/.local/share/mise/installs/node/24.20.0/lib/node_modules/bb-app/node_modules/fs-native-extensions/index.js"
printf 'fixture-host\n' > "$HOME/.bb/host-id"; chmod 600 "$HOME/.bb/host-id"
printf '{"config":{"BB_APP_URL":"https://old.example.ts.net"},"customModels":[{"name":"keep"}]}\n' > "$HOME/.bb/config.json"; chmod 600 "$HOME/.bb/config.json"
printf '{"env":{"OPENAI_API_KEY":"fixture-secret","BB_APP_URL":"https://old.example.ts.net"}}\n' > "$HOME/.bb/env.json"; chmod 600 "$HOME/.bb/env.json"
printf 'test.example.ts.net\n' > "$BB_TEST_DNS_FILE"
: > "$BB_TEST_EVENTS"; rm -f "$BB_TEST_ROOT/app-active" "$BB_TEST_ROOT/ingress-active"
print_error() { :; }; print_success() { :; }; can_sudo() { return 1; }; ensure_shared_node_runtime() { return 0; }
command() { if [[ "$1" == -v && "$2" == tailscale ]]; then printf '/usr/bin/tailscale\n'; else builtin command "$@"; fi; }
npm() { [[ "$1" == prefix && "$2" == -g ]] && printf '%s\n' "$HOME/.local/share/mise/installs/node/24.20.0"; }
bb_package_preflight() {
    BB_PACKAGE_PREFIX="$HOME/.local/share/mise/installs/node/24.20.0"
    BB_PACKAGE_PATH="$BB_PACKAGE_PREFIX/lib/node_modules/bb-app"
    BB_PACKAGE_OWNER=''
    [[ ! -f "$HOME/.config/setup-bb-server/package-owner" ]] || BB_PACKAGE_OWNER=$(<"$HOME/.config/setup-bb-server/package-owner")
}
bb_install_package() {
    [[ ! -e "$BB_TEST_ROOT/app-active" && ! -e "$BB_TEST_ROOT/ingress-active" ]] || return 97
    printf 'install\n' >> "$BB_TEST_EVENTS"
    [[ "${BB_TEST_INSTALL_FAIL:-0}" != 1 ]] || return 1
    if [[ "${BB_PACKAGE_OWNER}" != "$BB_PACKAGE_PATH" && ! -e "$HOME/.config/setup-bb-server/package-owner.next" ]]; then printf '%s\n' "$BB_PACKAGE_PATH" > "$HOME/.config/setup-bb-server/package-owner.next"; fi
}
bb_package_artifacts_ready() { return 0; }
bb_local_ports_free() { [[ ! -e "$BB_TEST_ROOT/local-port-occupied" ]]; }
tailscale() {
    case "$1 $2" in
        'version --daemon') printf '{"short":"1.102.4","daemonLong":"1.102.4-fixture"}\n';;
        'status --json') printf '{"BackendState":"Running","Self":{"DNSName":"%s."}}\n' "$(<"$BB_TEST_DNS_FILE")";;
        'serve status')
            if [[ -e "$BB_TEST_ROOT/route-occupied" ]]; then printf '{"TCP":{"443":{"HTTPS":true},"38443":{"HTTPS":true},"38444":{"HTTPS":true},"38445":{"HTTPS":true}}}\n'
            elif [[ -e "$BB_TEST_ROOT/occupy-443" ]]; then printf '{"TCP":{"443":{"HTTPS":true}}}\n'
            elif [[ -e "$BB_TEST_ROOT/occupy-38443" ]]; then printf '{"TCP":{"38443":{"HTTPS":true}}}\n'
            elif [[ -e "$BB_TEST_ROOT/ingress-active" ]]; then read -r dns port _ < "$HOME/.config/setup-bb-server/endpoint"; node -e 'const p=process.argv[1],d=process.argv[2];console.log(JSON.stringify({Foreground:{managed:{TCP:{[p]:{HTTPS:true}},Web:{[d+":"+p]:{Handlers:{"/":{"Proxy":"http://127.0.0.1:38886"}}}}}}}))' "$port" "$dns"
            else printf '{}\n'; fi;;
        *) return 1;;
    esac
}
systemctl() {
    case " $* " in
        *' show '*MainPID*) cat "$BB_TEST_ROOT/main-pid";;
        *' show '*)
            if [[ "$3" == setup-bb-app.service && -n "${BB_TEST_REFERENCE_NAME:-}" ]]; then
                selected="$HOME/.config/systemd/user/$3.d/${BB_TEST_REFERENCE_NAME}"
                if [[ -f "$HOME/.config/systemd/user/$3.d/10-tmpdir.conf" ]]; then selected="$HOME/.config/systemd/user/$3.d/10-tmpdir.conf ${selected}"; fi
                printf 'FragmentPath=%s\nDropInPaths=%s\n' "$HOME/.config/systemd/user/$3" "${selected}"
            elif [[ "$3" == setup-bb-app.service && -f "$HOME/.config/systemd/user/$3.d/10-tmpdir.conf" ]]; then
                printf 'FragmentPath=%s\nDropInPaths=%s\n' "$HOME/.config/systemd/user/$3" "$HOME/.config/systemd/user/$3.d/10-tmpdir.conf"
            else
                printf 'FragmentPath=\nDropInPaths=\n'
            fi;;
        *' is-active '*setup-bb-app.service*) [[ -e "$BB_TEST_ROOT/app-active" ]];;
        *' is-active '*setup-bb-ingress.service*) [[ -e "$BB_TEST_ROOT/ingress-active" ]];;
        *' stop setup-bb-ingress.service '*) printf 'stop-ingress\n' >> "$BB_TEST_EVENTS"; rm -f "$BB_TEST_ROOT/ingress-active";;
        *' stop setup-bb-app.service '*) printf 'stop-app\n' >> "$BB_TEST_EVENTS"; rm -f "$BB_TEST_ROOT/app-active"; if [[ -s "$BB_TEST_ROOT/main-pid" ]]; then app_pid=$(<"$BB_TEST_ROOT/main-pid"); kill "$app_pid" 2>/dev/null || true; wait "$app_pid" 2>/dev/null || true; fi; rm -f "$BB_TEST_ROOT/main-pid";;
        *' daemon-reload '*) printf 'daemon-reload\n' >> "$BB_TEST_EVENTS";;
        *' enable setup-bb-app.service '*) printf 'enable-app\n' >> "$BB_TEST_EVENTS";;
        *' start setup-bb-app.service '*)
            printf 'start-app\n' >> "$BB_TEST_EVENTS"
            if [[ "${BB_TEST_ARM_START_FAILURE:-0}" == 1 ]]; then
                : > "${BB_TEST_CURL_FAIL_ONCE_FILE}"
                unset BB_TEST_ARM_START_FAILURE
            fi
            "$BB_TEST_RUNNER" app ExecStart & app_pid=$!
            printf '%s\n' "$app_pid" > "$BB_TEST_ROOT/main-pid"
            for _ in {1..100}; do
                [[ -r "/proc/${app_pid}/cmdline" ]] || return 1
                process_args=$(tr '\0' ' ' < "/proc/${app_pid}/cmdline")
                [[ "${process_args}" == *"$HOME/.local/share/mise/installs/node/24.20.0/bin/bb-app"* ]] && break
                /bin/sleep 0.01
            done
            [[ "${process_args}" == *"$HOME/.local/share/mise/installs/node/24.20.0/bin/bb-app"* ]] || return 1
            touch "$BB_TEST_ROOT/app-active"
            "$BB_TEST_RUNNER" app ExecStartPost;;
        *) return 0;;
    esac
}
loginctl() { printf 'yes\n'; }
curl() {
    case "${*: -1}" in
        http://127.0.0.1:38886/health|http://127.0.0.1:38887/status) "$BB_TEST_ROOT/bin/curl" "$@";;
        *)
            [[ "$*" == *'https://test.example.ts.net:38443/ -o /dev/null' ]] || return 97
            printf 'private-https\n' >> "$BB_TEST_EVENTS"
            [[ "${BB_TEST_HTTPS_FAIL:-0}" != 1 ]];;
    esac
}
sleep() { :; }

# Known foreign backend listener or Serve route: no package/config/service write.
touch "$BB_TEST_ROOT/local-port-occupied"
! setup_bb_server
! grep -q '^install$' "$BB_TEST_EVENTS"
rm "$BB_TEST_ROOT/local-port-occupied"
BB_TEST_BACKEND=Stopped
: > "$BB_TEST_EVENTS"
! setup_bb_server
! grep -q '^install$' "$BB_TEST_EVENTS"
unset BB_TEST_BACKEND
touch "$BB_TEST_ROOT/route-occupied"
! setup_bb_server
! grep -q '^install$' "$BB_TEST_EVENTS"
rm "$BB_TEST_ROOT/route-occupied"
chmod 620 "$HOME/.bb/config.json"
: > "$BB_TEST_EVENTS"
! setup_bb_server
! grep -q '^install$' "$BB_TEST_EVENTS"
chmod 600 "$HOME/.bb/config.json"
# Start with a saved non-default private endpoint, not a fresh-port selection.
mkdir -p "$HOME/.config/setup-bb-server"
printf 'test.example.ts.net 38443 https://test.example.ts.net:38443\n' > "$HOME/.config/setup-bb-server/endpoint"
chmod 600 "$HOME/.config/setup-bb-server/endpoint"
setup_bb_server
[[ "$(<"$HOME/.config/setup-bb-server/endpoint")" == 'test.example.ts.net 38443 https://test.example.ts.net:38443' ]]
node - "$HOME/.bb/config.json" "$HOME/.bb/env.json" <<'NODE'
const fs=require('fs'),c=JSON.parse(fs.readFileSync(process.argv[2])),e=JSON.parse(fs.readFileSync(process.argv[3]));if(c.config.BB_APP_URL!=='https://test.example.ts.net:38443'||c.customModels[0].name!=='keep'||e.env.OPENAI_API_KEY!=='fixture-secret'||Object.hasOwn(e.env,'BB_APP_URL'))process.exit(1)
NODE
grep -q 'bb-guard app-start' "$HOME/.config/systemd/user/setup-bb-app.service"
grep -q 'bb-guard app-ready' "$HOME/.config/systemd/user/setup-bb-app.service"
grep -q '^BindsTo=setup-bb-app.service$' "$HOME/.config/systemd/user/setup-bb-ingress.service"
grep -q '^After=setup-bb-app.service$' "$HOME/.config/systemd/user/setup-bb-ingress.service"
grep -qx 'Restart=always' "$HOME/.config/systemd/user/setup-bb-app.service"
grep -qx 'Restart=always' "$HOME/.config/systemd/user/setup-bb-ingress.service"
grep -qx 'StartLimitIntervalSec=0' "$HOME/.config/systemd/user/setup-bb-app.service"
grep -qx 'StartLimitIntervalSec=0' "$HOME/.config/systemd/user/setup-bb-ingress.service"
grep -qx 'WantedBy=default.target' "$HOME/.config/systemd/user/setup-bb-app.service"
grep -qx 'TimeoutStartSec=180' "$HOME/.config/systemd/user/setup-bb-app.service"
! grep -Eq -- '--bg|serve off|serve reset|Funnel' "$HOME/.config/systemd/user/setup-bb-ingress.service"
[[ "$(<"$HOME/.config/setup-bb-server/package-owner")" == "$HOME/.local/share/mise/installs/node/24.20.0/lib/node_modules/bb-app" ]]

mkdir -p "$HOME/.config/systemd/user/setup-bb-app.service.d" "$HOME/.cache/bb/tmp"
chmod 700 "$HOME/.config/systemd/user/setup-bb-app.service.d" "$HOME/.cache" "$HOME/.cache/bb" "$HOME/.cache/bb/tmp"
printf '[Service]\nEnvironment=TMPDIR=%s/.cache/bb/tmp\n' "$HOME" > "$HOME/.config/systemd/user/setup-bb-app.service.d/10-tmpdir.conf"
chmod 600 "$HOME/.config/systemd/user/setup-bb-app.service.d/10-tmpdir.conf"
printf 'preserved temporary data\n' > "$HOME/.cache/bb/tmp/keep"
cp "$HOME/.config/systemd/user/setup-bb-app.service.d/10-tmpdir.conf" "$BB_TEST_ROOT/prior-tmpdir"
print_message() { :; }
: > "$BB_TEST_EVENTS"
setup_bb_server
stop_ingress=$(grep -n '^stop-ingress$' "$BB_TEST_EVENTS" | head -1 | cut -d: -f1)
stop_app=$(grep -n '^stop-app$' "$BB_TEST_EVENTS" | head -1 | cut -d: -f1)
install=$(grep -n '^install$' "$BB_TEST_EVENTS" | head -1 | cut -d: -f1)
start_app=$(grep -n '^start-app$' "$BB_TEST_EVENTS" | head -1 | cut -d: -f1)
(( stop_ingress < stop_app && stop_app < install && install < start_app ))
grep -Fx "tmpdir:${HOME}/.cache/bb/tmp" "$BB_TEST_APP_LOG"
cmp "$BB_TEST_ROOT/prior-tmpdir" "$HOME/.config/systemd/user/setup-bb-app.service.d/10-tmpdir.conf"
[[ "$(<"$HOME/.cache/bb/tmp/keep")" == 'preserved temporary data' ]]
# Generated unit/guard seam: both names, repeats, private reference and combined
# TMPDIR. This is an inert child and native readiness JSON, never BB execution.
export BB_TEST_REQUIRE_INHERITED=1
printf '{"hostId":"fixture-host","private":"DO-NOT-LOG-INHERITED-FIXTURE"}\n' > "$HOME/.bb/auth.json"
chmod 600 "$HOME/.bb/auth.json"
printf 'unrelated projects\n' > "$HOME/.bb/project-data"
printf 'unrelated service\n' > "$HOME/.config/systemd/user/unrelated.service"
snapshot_inputs() {
    python3 - "$HOME" <<'PRESERVED_INPUTS'
import hashlib, json, sys
from pathlib import Path
home = Path(sys.argv[1])
paths = [home / name for name in ('.env.local', '.bb/host-id', '.bb/auth.json',
         '.bb/config.json', '.bb/env.json', '.bb/project-data',
         '.config/systemd/user/unrelated.service', '.config/setup-bb-server/endpoint',
         '.config/setup-bb-server/package-owner', '.cache/bb/tmp', '.cache/bb/tmp/keep')]
directory = home / '.config/systemd/user/setup-bb-app.service.d'
paths += [directory, *directory.iterdir()]
result = {}
for path in sorted(paths):
    stat = path.lstat()
    result[str(path.relative_to(home))] = [stat.st_dev, stat.st_ino, stat.st_uid,
        stat.st_gid, stat.st_mode, stat.st_nlink,
        hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else None]
print(json.dumps(result, sort_keys=True))
PRESERVED_INPUTS
}
for selection in env.conf:664:alone 20-env-local.conf:664:alone env.conf:600:alone env.conf:664:combined 20-env-local.conf:600:combined; do
    IFS=: read -r BB_TEST_REFERENCE_NAME reference_mode combination <<< "${selection}"
    export BB_TEST_REFERENCE_NAME
    rm -f "$HOME/.config/systemd/user/setup-bb-app.service.d/env.conf" "$HOME/.config/systemd/user/setup-bb-app.service.d/20-env-local.conf" "$HOME/.config/systemd/user/setup-bb-app.service.d/10-tmpdir.conf"
    if [[ "${combination}" == combined ]]; then cp "$BB_TEST_ROOT/prior-tmpdir" "$HOME/.config/systemd/user/setup-bb-app.service.d/10-tmpdir.conf"; fi
    printf '[Service]\nEnvironmentFile=%%h/.env.local\n' > "$HOME/.config/systemd/user/setup-bb-app.service.d/${BB_TEST_REFERENCE_NAME}"
    chmod 775 "$HOME/.config/systemd/user/setup-bb-app.service.d"
    chmod "${reference_mode}" "$HOME/.config/systemd/user/setup-bb-app.service.d/${BB_TEST_REFERENCE_NAME}"
    for attempt in 1 2; do
        # A changed synthetic source must reach the *new* child, not a cached
        # input or inherited environment of the setup/fixture parent.
        export BB_TEST_EXPECT_INPUT="DO-NOT-LOG-INHERITED-FIXTURE-${attempt}"
        unset BB_FIXTURE_INPUT
        printf 'BB_FIXTURE_INPUT=%s\n' "${BB_TEST_EXPECT_INPUT}" > "$HOME/.env.local"
        chmod 600 "$HOME/.env.local"
        snapshot_inputs > "$BB_TEST_ROOT/inherited-before"
        : > "${BB_TEST_APP_LOG}"; : > "${BB_TEST_EVENTS}"; : > "${BB_TEST_SERVE_LOG}"
        setup_bb_server
        snapshot_inputs > "$BB_TEST_ROOT/inherited-after"
        cmp "$BB_TEST_ROOT/inherited-before" "$BB_TEST_ROOT/inherited-after"
        [[ "$(grep -c '^inherited-child-ready$' "${BB_TEST_APP_LOG}")" == 1 ]]
        ! grep -q 'DO-NOT-LOG-INHERITED-FIXTURE' "${BB_TEST_APP_LOG}" "${BB_TEST_EVENTS}" "${BB_TEST_SERVE_LOG}"
        [[ -e "$BB_TEST_ROOT/app-active" && -e "$BB_TEST_ROOT/ingress-active" ]]
        grep -qx 'serve --https=38443 http://127.0.0.1:38886' "${BB_TEST_SERVE_LOG}"
        python3 - "${BB_TEST_EVENTS}" <<'AUTOMATIC_READINESS'
from pathlib import Path
import sys
events = Path(sys.argv[1]).read_text().splitlines()
order = [events.index(name) for name in ('stop-ingress', 'stop-app', 'install', 'start-app', 'ingress-queued', 'private-https')]
assert order == sorted(order)
assert events.count('install') == 1
assert events[-1] == 'private-https'
ready = events[events.index('start-app') + 1:]
assert ready.index('native-health') < ready.index('native-host-status') < ready.index('ingress-queued')
assert 'native-host-status' in ready[ready.index('ingress-queued') + 1:]
AUTOMATIC_READINESS
    done
done
# The unit runner models a required, not optional source at child startup.
# Removing only this synthetic source cannot silently launch an empty child.
mv "$HOME/.env.local" "$BB_TEST_ROOT/required-source"
: > "${BB_TEST_APP_LOG}"
if "$BB_TEST_RUNNER" app ExecStart > "$BB_TEST_ROOT/missing-source.log" 2>&1; then exit 1; fi
[[ ! -s "${BB_TEST_APP_LOG}" ]]
grep -qx 'fixture required environment source unavailable' "$BB_TEST_ROOT/missing-source.log"
mv "$BB_TEST_ROOT/required-source" "$HOME/.env.local"
printf 'inherited generated-unit/child/readiness cases passed\n'

# A native-lock timeout during an update leaves metadata byte-for-byte intact,
# then restores the formerly running app and ingress without a stale rollback.
cp "$HOME/.bb/config.json" "$BB_TEST_ROOT/locked-config"
cp "$HOME/.bb/env.json" "$BB_TEST_ROOT/locked-env"
: > "$BB_TEST_EVENTS"
export BB_TEST_NATIVE_LOCK_FAIL=1
! setup_bb_server
unset BB_TEST_NATIVE_LOCK_FAIL
node - "$HOME/.bb/config.json" "$HOME/.bb/env.json" <<'NODE'
const fs = require("fs"), c = JSON.parse(fs.readFileSync(process.argv[2])), e = JSON.parse(fs.readFileSync(process.argv[3]));
if (c.concurrentEditor !== "latest" || e.concurrentEditor !== "latest" || c.config.BB_APP_URL !== "https://test.example.ts.net:38443" || c.customModels[0].name !== "keep" || e.env.OPENAI_API_KEY !== "fixture-secret") process.exit(1);
NODE
[[ -e "$BB_TEST_ROOT/app-active" && -e "$BB_TEST_ROOT/ingress-active" ]]
grep -q '^start-app$' "$BB_TEST_EVENTS"
grep -q '^ingress-queued$' "$BB_TEST_EVENTS"
export BB_TEST_HOST_CONNECTED=false
: > "$BB_TEST_EVENTS"
! setup_bb_server
! grep -q '^stop-' "$BB_TEST_EVENTS"
! grep -q '^install$' "$BB_TEST_EVENTS"
unset BB_TEST_HOST_CONNECTED
# An npm failure retains the old package owner and restores its active service.
: > "$BB_TEST_EVENTS"
BB_TEST_INSTALL_FAIL=1
! setup_bb_server
unset BB_TEST_INSTALL_FAIL
[[ -e "$BB_TEST_ROOT/app-active" && -e "$BB_TEST_ROOT/ingress-active" ]]
[[ "$(grep -c '^install$' "$BB_TEST_EVENTS")" == 1 ]]
# A private HTTPS health failure restores the prior service and fixed endpoint.
BB_TEST_HTTPS_FAIL=1
! setup_bb_server
unset BB_TEST_HTTPS_FAIL
[[ -e "$BB_TEST_ROOT/app-active" && -e "$BB_TEST_ROOT/ingress-active" ]]
[[ "$(<"$HOME/.config/setup-bb-server/endpoint")" == 'test.example.ts.net 38443 https://test.example.ts.net:38443' ]]
# A one-shot generated readiness failure restores the prior active service and ingress.
cp "$HOME/.config/systemd/user/setup-bb-app.service" "$BB_TEST_ROOT/prior-app-unit"
cp "$HOME/.config/setup-bb-server/bb-guard" "$BB_TEST_ROOT/prior-bb-guard"
: > "$BB_TEST_EVENTS"
export BB_TEST_CURL_FAIL_ONCE_FILE="$BB_TEST_ROOT/fail-next-health" BB_READY_ATTEMPTS=1 BB_TEST_ARM_START_FAILURE=1
! setup_bb_server
unset BB_TEST_CURL_FAIL_ONCE_FILE BB_READY_ATTEMPTS BB_TEST_ARM_START_FAILURE
[[ "$(grep -c '^install$' "$BB_TEST_EVENTS")" == 1 ]]
[[ "$(grep -c '^start-app$' "$BB_TEST_EVENTS")" == 2 ]]
cmp "$BB_TEST_ROOT/prior-app-unit" "$HOME/.config/systemd/user/setup-bb-app.service"
cmp "$BB_TEST_ROOT/prior-bb-guard" "$HOME/.config/setup-bb-server/bb-guard"
[[ -e "$BB_TEST_ROOT/app-active" && -e "$BB_TEST_ROOT/ingress-active" ]]
# A tailnet rename cannot change the saved endpoint or trigger an update.
printf 'renamed.example.ts.net\n' > "$BB_TEST_DNS_FILE"
: > "$BB_TEST_EVENTS"
! setup_bb_server
! grep -q '^install$' "$BB_TEST_EVENTS"
[[ "$(<"$HOME/.config/setup-bb-server/endpoint")" == 'test.example.ts.net 38443 https://test.example.ts.net:38443' ]]
SETUP_FIXTURE

BB_TEST_ROOT="${tmp}/fresh-setup" BB_TEST_TOOLS_DIR="${tmp}/bin" BB_TEST_RUNNER="${tmp}/bin/run-systemd-unit" BB_TEST_HELPERS="${tmp}/helpers.sh" PATH="${tmp}/bin:${PATH}" BB_READY_ATTEMPTS=5 BB_READY_INTERVAL=0 bash <<'FRESH_SETUP_FIXTURE'
set -euo pipefail
source "$BB_TEST_HELPERS"
export BB_TEST_ROOT HOME="$BB_TEST_ROOT/home" BB_TEST_EVENTS="$BB_TEST_ROOT/events" BB_TEST_APP_LOG="$BB_TEST_ROOT/app.log" BB_TEST_SERVE_LOG="$BB_TEST_ROOT/serve.log" BB_TEST_DNS_FILE="$BB_TEST_ROOT/dns" BB_TEST_GENERATE_ID=1
export BB_TEST_RUNNER="${BB_TEST_RUNNER:-$BB_TEST_ROOT/bin/run-systemd-unit}"
trap 'if [[ -s "$BB_TEST_ROOT/main-pid" ]]; then app_pid=$(<"$BB_TEST_ROOT/main-pid"); kill "$app_pid" 2>/dev/null || true; wait "$app_pid" 2>/dev/null || true; fi' EXIT
mkdir -p "$HOME" "$BB_TEST_ROOT/proc" "$HOME/.local/share/mise/installs/node/24.20.0/bin"
chmod 700 "$HOME" "$BB_TEST_ROOT" "$BB_TEST_ROOT/proc" "$HOME/.local" "$HOME/.local/share" "$HOME/.local/share/mise" "$HOME/.local/share/mise/installs" "$HOME/.local/share/mise/installs/node" "$HOME/.local/share/mise/installs/node/24.20.0" "$HOME/.local/share/mise/installs/node/24.20.0/bin"
ln -s "$BB_TEST_ROOT/../bin/bb-app" "$HOME/.local/share/mise/installs/node/24.20.0/bin/bb-app"
[[ ! -e "$HOME/.bb" && ! -e "$HOME/.bb/host-id" && ! -e "$HOME/.bb/auth.json" && ! -e "$HOME/.bb/env.json" ]]
printf 'test.example.ts.net\n' > "$BB_TEST_DNS_FILE"
printf 'sl\n' > "$BB_TEST_ROOT/proc/tcp"; printf 'sl\n' > "$BB_TEST_ROOT/proc/tcp6"
print_error() { :; }; print_success() { :; }; can_sudo() { return 1; }; ensure_shared_node_runtime() { return 0; }
command() { if [[ "$1" == -v && "$2" == tailscale ]]; then printf '/usr/bin/tailscale\n'; else builtin command "$@"; fi; }
npm() { [[ "$1" == prefix && "$2" == -g ]] && printf '%s\n' "$HOME/.local/share/mise/installs/node/24.20.0"; }
bb_package_preflight() {
    BB_PACKAGE_PREFIX="$HOME/.local/share/mise/installs/node/24.20.0"
    BB_PACKAGE_PATH="$BB_PACKAGE_PREFIX/lib/node_modules/bb-app"
    BB_PACKAGE_OWNER=''
    [[ ! -f "$HOME/.config/setup-bb-server/package-owner" ]] || BB_PACKAGE_OWNER=$(<"$HOME/.config/setup-bb-server/package-owner")
}
bb_install_package() {
    printf 'install\n' >> "$BB_TEST_EVENTS"
    if [[ -z "${BB_PACKAGE_OWNER}" && ! -e "$HOME/.config/setup-bb-server/package-owner.next" ]]; then (umask 077; printf '%s\n' "$BB_PACKAGE_PATH" > "$HOME/.config/setup-bb-server/package-owner.next"); fi
}
bb_package_artifacts_ready() { return 0; }
bb_local_ports_free() { [[ ! -e "$BB_TEST_ROOT/local-port-occupied" ]]; }
bb_config_merge_native() { return 0; }
tailscale() {
    case "$1 $2" in
        'version --daemon') printf '{"short":"1.102.4","daemonLong":"1.102.4-fixture"}\n';;
        'status --json') printf '{"BackendState":"Running","Self":{"DNSName":"%s."}}\n' "$(<"$BB_TEST_DNS_FILE")";;
        'serve status')
            if [[ -e "$BB_TEST_ROOT/ingress-active" ]]; then read -r dns port _ < "$HOME/.config/setup-bb-server/endpoint"; node -e 'const p=process.argv[1],d=process.argv[2];console.log(JSON.stringify({Foreground:{managed:{TCP:{[p]:{HTTPS:true}},Web:{[d+":"+p]:{Handlers:{"/":{"Proxy":"http://127.0.0.1:38886"}}}}}}}))' "$port" "$dns"
            else printf '{}\n'; fi;;
        *) return 1;;
    esac
}
systemctl() {
    case " $* " in
        *' show '*MainPID*) cat "$BB_TEST_ROOT/main-pid";;
        *' show '*) printf 'FragmentPath=\nDropInPaths=\n';;
        *' is-active '*setup-bb-app.service*) [[ -e "$BB_TEST_ROOT/app-active" ]];;
        *' is-active '*setup-bb-ingress.service*) [[ -e "$BB_TEST_ROOT/ingress-active" ]];;
        *' stop setup-bb-ingress.service '*) rm -f "$BB_TEST_ROOT/ingress-active";;
        *' stop setup-bb-app.service '*) rm -f "$BB_TEST_ROOT/app-active"; if [[ -s "$BB_TEST_ROOT/main-pid" ]]; then app_pid=$(<"$BB_TEST_ROOT/main-pid"); kill "$app_pid" 2>/dev/null || true; wait "$app_pid" 2>/dev/null || true; fi; rm -f "$BB_TEST_ROOT/main-pid";;
        *' start setup-bb-app.service '*)
            "$BB_TEST_RUNNER" app ExecStart & app_pid=$!
            printf '%s\n' "$app_pid" > "$BB_TEST_ROOT/main-pid"
            for _ in {1..100}; do
                [[ -r "/proc/${app_pid}/cmdline" ]] || return 1
                process_args=$(tr '\0' ' ' < "/proc/${app_pid}/cmdline")
                [[ "${process_args}" == *"$HOME/.local/share/mise/installs/node/24.20.0/bin/bb-app"* ]] && break
                /bin/sleep 0.01
            done
            [[ "${process_args}" == *"$HOME/.local/share/mise/installs/node/24.20.0/bin/bb-app"* ]] || return 1
            touch "$BB_TEST_ROOT/app-active"
            "$BB_TEST_RUNNER" app ExecStartPost;;
        *' stop setup-bb-app.service '*) return 0;;
        *) return 0;;
    esac
}
loginctl() { printf 'yes\n'; }
curl() {
    case "${*: -1}" in
        http://127.0.0.1:38886/health|http://127.0.0.1:38887/status) "$BB_TEST_TOOLS_DIR/curl" "$@";;
        *) [[ "${BB_TEST_HTTPS_FAIL:-0}" != 1 ]];;
    esac
}
sleep() { :; }
# Do not stub either function whose missing prelaunch-identity assumption is
# under regression: bb_host_identity_ready and bb_native_app_ready.
setup_bb_server
[[ "$(<"$HOME/.bb/host-id")" == fresh-fixture-host-id ]]
[[ "$(stat -c '%a' "$HOME/.bb/host-id")" == 600 ]]
[[ ! -e "$HOME/.bb/auth.json" && ! -e "$HOME/.bb/env.json" ]]
[[ -e "$BB_TEST_ROOT/app-active" && -e "$BB_TEST_ROOT/ingress-active" ]]
[[ "$(<"$HOME/.config/setup-bb-server/package-owner")" == "$HOME/.local/share/mise/installs/node/24.20.0/lib/node_modules/bb-app" ]]
identity_home="$BB_TEST_ROOT/identity-check"
mkdir -p "$identity_home/.bb"; chmod 700 "$identity_home" "$identity_home/.bb"
saved_home="$HOME"; HOME="$identity_home"
printf '{broken\n' > "$HOME/.bb/auth.json"; chmod 600 "$HOME/.bb/auth.json"
! bb_host_identity_ready
rm "$HOME/.bb/auth.json"
printf 'fixture-host\n' > "$HOME/.bb/host-id"; chmod 600 "$HOME/.bb/host-id"
printf '{"hostId":"different-host"}\n' > "$HOME/.bb/auth.json"; chmod 600 "$HOME/.bb/auth.json"
! bb_host_identity_ready
rm "$HOME/.bb/auth.json" "$HOME/.bb/host-id"
printf 'fixture-host\n' > "$BB_TEST_ROOT/identity-target"; chmod 600 "$BB_TEST_ROOT/identity-target"
ln -s "$BB_TEST_ROOT/identity-target" "$HOME/.bb/auth.json"
! bb_host_identity_ready
HOME="$saved_home"
FRESH_SETUP_FIXTURE

BB_TEST_ROOT="${tmp}" BB_TEST_HELPERS="${tmp}/helpers.sh" PATH="${tmp}/bin:${PATH}" bash <<'NATIVE_CONFIG_FIXTURE'
set -euo pipefail
source "$BB_TEST_HELPERS"
print_error() { printf 'ERROR: %s\n' "$1"; }
export HOME="$BB_TEST_ROOT/native-home"
prefix="$HOME/.local/share/mise/installs/node/24.20.0"
package="$prefix/lib/node_modules/bb-app"
mkdir -p "$HOME/.config/setup-bb-server" "$HOME/.bb" "$package/node_modules/fs-native-extensions"
chmod 700 "$HOME" "$HOME/.config" "$HOME/.config/setup-bb-server" "$HOME/.bb"
printf '{"name":"bb-app","version":"0.44.0"}\n' > "$package/package.json"; chmod 600 "$package/package.json"
cat > "$package/node_modules/fs-native-extensions/index.js" <<'NODE'
const fs=require('fs');let denied=false;
exports.tryLock=fd=>{if(!denied&&process.env.BB_TEST_NATIVE_WRITER){denied=true;const c=process.env.HOME+'/.bb/config.json',e=process.env.HOME+'/.bb/env.json';const cv=JSON.parse(fs.readFileSync(c));cv.concurrentEditor='latest';fs.writeFileSync(c,JSON.stringify(cv),{mode:0o600});const ev=JSON.parse(fs.readFileSync(e));ev.concurrentEditor='latest';fs.writeFileSync(e,JSON.stringify(ev),{mode:0o600});fs.writeFileSync(process.env.BB_TEST_NATIVE_WRITER,'writer-ran');return false}return true};
exports.unlock=()=>{};
NODE
printf '{"config":{"BB_APP_URL":"https://old.example.ts.net"},"customModels":[{"name":"keep"}]}\n' > "$HOME/.bb/config.json"
printf '{"env":{"OPENAI_API_KEY":"keep-secret","BB_APP_URL":"https://old.example.ts.net"},"custom":"keep"}\n' > "$HOME/.bb/env.json"
chmod 600 "$HOME/.bb/config.json" "$HOME/.bb/env.json"
export BB_PACKAGE_PATH="$package" BB_TEST_NATIVE_WRITER="$BB_TEST_ROOT/writer-ran"
bb_config_merge_native 'https://fixture.example.ts.net:38443'
[[ -e "$BB_TEST_NATIVE_WRITER" ]]
node - "$HOME/.bb/config.json" "$HOME/.bb/env.json" <<'NODE'
const fs=require('fs'),c=JSON.parse(fs.readFileSync(process.argv[2])),e=JSON.parse(fs.readFileSync(process.argv[3]));if(c.config.BB_APP_URL!=='https://fixture.example.ts.net:38443'||c.customModels[0].name!=='keep'||c.concurrentEditor!=='latest'||e.env.OPENAI_API_KEY!=='keep-secret'||Object.hasOwn(e.env,'BB_APP_URL')||e.custom!=='keep'||e.concurrentEditor!=='latest')process.exit(1)
NODE
for lock in "$HOME/.bb/.config.json.lock" "$HOME/.bb/.env.json.lock"; do [[ -f "$lock" && ! -L "$lock" ]]; done
config_mtime=$(stat -c %Y "$HOME/.bb/config.json"); env_mtime=$(stat -c %Y "$HOME/.bb/env.json")
sleep 1
unset BB_TEST_NATIVE_WRITER
bb_config_merge_native 'https://fixture.example.ts.net:38443'
[[ "$(stat -c %Y "$HOME/.bb/config.json")" == "$config_mtime" ]]
[[ "$(stat -c %Y "$HOME/.bb/env.json")" == "$env_mtime" ]]
node -e 'const fs=require("fs"),p=process.argv[1],v=JSON.parse(fs.readFileSync(p));v.config.BB_SERVER_PORT="9999";fs.writeFileSync(p,JSON.stringify(v),{mode:0o600})' "$HOME/.bb/config.json"
cp "$HOME/.bb/config.json" "$BB_TEST_ROOT/conflicting-config"
if bb_config_merge_native 'https://fixture.example.ts.net:38443'; then exit 1; fi
cmp "$BB_TEST_ROOT/conflicting-config" "$HOME/.bb/config.json"
rm "$HOME/.bb/config.json"; ln -s "$BB_TEST_ROOT/conflicting-config" "$HOME/.bb/config.json"
if bb_config_merge_native 'https://fixture.example.ts.net:38443'; then exit 1; fi
rm "$HOME/.bb/config.json"; printf '{broken\n' > "$HOME/.bb/config.json"; chmod 600 "$HOME/.bb/config.json"
if bb_config_merge_native 'https://fixture.example.ts.net:38443'; then exit 1; fi
NATIVE_CONFIG_FIXTURE

BB_TEST_ROOT="${tmp}" BB_TEST_HELPERS="${tmp}/helpers.sh" PATH="${tmp}/bin:${PATH}" bash <<'PACKAGE_FIXTURE'
set -euo pipefail
source "$BB_TEST_HELPERS"
print_error() { printf 'ERROR: %s\n' "$1"; }
export HOME="$BB_TEST_ROOT/package-home"
prefix="$HOME/.local/share/mise/installs/node/24.20.0"
package="$prefix/lib/node_modules/bb-app"
mkdir -p "$HOME/.config/setup-bb-server" "$prefix/bin" "$prefix/lib/node_modules"
chmod 700 "$HOME" "$HOME/.config" "$HOME/.config/setup-bb-server"
chmod 755 "$HOME/.local" "$HOME/.local/share" "$HOME/.local/share/mise" "$HOME/.local/share/mise/installs" "$HOME/.local/share/mise/installs/node" "$prefix" "$prefix/bin" "$prefix/lib" "$prefix/lib/node_modules"
ensure_shared_node_runtime() { return 0; }
make_package() {
    mkdir -p "$package/dist" "$package/node_modules/better-sqlite3" "$package/node_modules/node-pty" "$package/node_modules/@parcel/watcher" "$package/node_modules/fs-native-extensions" "$package/app/dist" "$package/server/dist" "$package/host-daemon/dist/bb-chunks"
    printf '{"name":"bb-app","version":"%s"}\n' "${BB_TEST_VERSION:-0.44.0}" > "$package/package.json"
    printf 'module.exports = class { close(){} }\n' > "$package/node_modules/better-sqlite3/index.js"
    printf 'module.exports = {}\n' > "$package/node_modules/node-pty/index.js"
    printf 'module.exports = {}\n' > "$package/node_modules/@parcel/watcher/index.js"
    printf 'exports.tryLock = () => true; exports.unlock = () => {};\n' > "$package/node_modules/fs-native-extensions/index.js"
    for name in bb-app bb-server bb-host-daemon; do printf '// inert\n' > "$package/dist/$name.js"; done
    printf 'fixture\n' > "$package/app/dist/index.html"; printf '// inert\n' > "$package/server/dist/index.js"
    for name in daemon-bundle.mjs bb bb-provider-bridge-worker.mjs bb-parcel-watcher-child.mjs bb-plugin-host-worker.mjs; do printf '// inert\n' > "$package/host-daemon/dist/$name"; done
    printf '// inert\n' > "$package/host-daemon/dist/bb-chunks/a.js"
    ln -sfn ../lib/node_modules/bb-app/dist/bb-app.js "$prefix/bin/bb-app"
}
npm() {
    case "$1" in
        --version) printf '11.19.0\n';;
        config)
            case "${3:-}" in
                ignore-scripts) printf '%s\n' "${BB_TEST_IGNORE_SCRIPTS:-false}";;
                dangerously-allow-all-scripts) printf 'false\n';;
                allow-scripts) if [[ "${4:-}" == --allow-scripts=* ]]; then printf '%s\n' "${4#--allow-scripts=}"; else printf '%s\n' "${BB_TEST_USER_POLICY:-}"; fi;;
                strict-allow-scripts) printf 'true\n';;
                *) return 1;;
            esac;;
        prefix) [[ "${2:-}" == -g ]] && printf '%s\n' "${BB_TEST_PREFIX:-$prefix}";;
        install)
            [[ "$*" == *'--strict-allow-scripts'* && "$*" == *'--allow-scripts=better-sqlite3,node-pty,@parcel/watcher'* && "$*" == *'bb-app@latest'* ]] || return 1
            printf 'install\n' >> "$BB_TEST_ROOT/npm-events"
            [[ "${BB_TEST_NPM_FAIL:-0}" != 1 ]] || return 1
            [[ "${BB_TEST_SKIP_PACKAGE:-0}" == 1 ]] || { ( umask 077; make_package ); return 0; };;
        *) return 1;;
    esac
}
# Effective npm policy and unowned existing package block before install.
BB_TEST_USER_POLICY='node-pty@1.2.0-beta.15'
! bb_install_package
[[ ! -e "$BB_TEST_ROOT/npm-events" ]]
unset BB_TEST_USER_POLICY
BB_TEST_IGNORE_SCRIPTS=true
! bb_install_package
[[ ! -e "$BB_TEST_ROOT/npm-events" ]]
unset BB_TEST_IGNORE_SCRIPTS
mkdir -p "$package"
printf 'unowned\n' > "$package/package.json"
! bb_install_package
[[ ! -e "$BB_TEST_ROOT/npm-events" ]]
rm -rf "$package"
# The exact stable install is verified by package identity, bundle artifacts,
# and actual loading of inert native addons; package-owner promotion is left to
# the successful systemd health transaction.
bb_install_package
[[ "$(grep -c '^install$' "$BB_TEST_ROOT/npm-events")" == 1 ]]
[[ "$([[ -f "$HOME/.config/setup-bb-server/package-owner.next" ]] && echo yes)" == yes ]]
[[ ! -e "$HOME/.config/setup-bb-server/package-owner" ]]
old_prefix="$prefix"
old_owner="$package"
mv "$HOME/.config/setup-bb-server/package-owner.next" "$HOME/.config/setup-bb-server/package-owner"
# An owned but incomplete stable package remains repairable without weakening
# rejection of a replacement link at its recorded target.
rm "$package/dist/bb-server.js"
BB_TEST_SKIP_PACKAGE=1
! bb_install_package
unset BB_TEST_SKIP_PACKAGE
[[ "$(<"$HOME/.config/setup-bb-server/package-owner")" == "$package" ]]
[[ ! -e "$HOME/.config/setup-bb-server/package-owner.next" ]]
bb_install_package
[[ "$(<"$HOME/.config/setup-bb-server/package-owner")" == "$package" ]]
[[ ! -e "$HOME/.config/setup-bb-server/package-owner.next" ]]
mv "$package" "$BB_TEST_ROOT/package-saved"
ln -s "$BB_TEST_ROOT/package-saved" "$package"
! bb_install_package
rm "$package"
mv "$BB_TEST_ROOT/package-saved" "$package"
new_prefix="$HOME/.local/share/mise/installs/node/24.21.0"
mkdir -p "$new_prefix/bin" "$new_prefix/lib/node_modules"
chmod 755 "$new_prefix" "$new_prefix/bin" "$new_prefix/lib" "$new_prefix/lib/node_modules"
BB_TEST_PREFIX="$new_prefix"
bb_package_preflight
[[ "$BB_PACKAGE_OWNER" == "$old_owner" && "$BB_PACKAGE_PATH" == "$new_prefix/lib/node_modules/bb-app" ]]
unset BB_TEST_PREFIX
mv "$HOME/.config/setup-bb-server/package-owner" "$HOME/.config/setup-bb-server/package-owner.next"
# A prerelease, missing native dependency, or failed npm command is not
# accepted because a previous registration or partial directory exists.
BB_TEST_VERSION=0.45.0-rc.1
! bb_install_package
unset BB_TEST_VERSION
BB_TEST_SKIP_PACKAGE=1
! bb_install_package
BB_TEST_SKIP_PACKAGE=1
rm "$package/node_modules/node-pty/index.js"
! bb_install_package
NPM_FAIL_BEFORE="$BB_TEST_ROOT/npm-events"
BB_TEST_NPM_FAIL=1
! bb_install_package
[[ "$(grep -c '^install$' "$NPM_FAIL_BEFORE")" == 7 ]]
PACKAGE_FIXTURE

python3 <<'RACE_FIXTURE'
class Daemon:
    def __init__(self): self.ports, self.etag = {}, 0
    def claim(self, port, owner, expected):
        if expected != self.etag: return 'etag-conflict'
        if port in self.ports: return 'occupied'
        self.ports[port] = owner; self.etag += 1; return 'ok'
node = Daemon()
assert node.claim(443, 'other', 0) == 'ok'
assert node.claim(443, 'bb', 1) == 'occupied'
assert node.claim(443, 'bb', 0) == 'etag-conflict'
assert node.ports[443] == 'other'
node = Daemon()
assert node.claim(443, 'bb', 0) == 'ok'
assert node.claim(443, 'rival', 0) == 'etag-conflict'
assert node.ports[443] == 'bb'
RACE_FIXTURE

echo 'bb-server generated-command, lifecycle, npm and native-lock fixtures passed'
