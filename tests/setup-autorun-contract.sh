#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf -- "${tmp}"' EXIT
python3 - "${tmp}" <<'PY'
import pathlib, sys
sys.path.insert(0, str(pathlib.Path('tests').resolve()))
from extract_setup_fixture import definitions, validate_function
source = pathlib.Path('ubuntu.sh').read_text()
root = pathlib.Path(sys.argv[1])
root.joinpath('helpers.sh').write_text(definitions(source))
start = source.index("    : 'BEGIN_BB_SERVER_CALLER'")
end = source.index('    if ! prepare_pi_profile_permissions; then', start)
caller = 'bb_caller() {\n' + source[start:end] + '}\n'
validate_function(caller)
root.joinpath('caller.sh').write_text(caller)
PY
fail() { printf 'setup-autorun contract: %s\n' "$1" >&2; exit 1; }
export SETUP_AUTORUN_TEST_ROOT="${tmp}"
home="${tmp}/home"
runner="${home}/.local/bin/setup-autorun"
units="${home}/.config/systemd/user"
mkdir -p "${tmp}/bin" "${home}"

cat > "${tmp}/bin/systemctl" <<'MOCK'
#!/bin/sh
printf '%s\n' "$*" >> "${SETUP_AUTORUN_TEST_ROOT}/systemctl.log"
exit "${SYSTEMCTL_STATUS:-0}"
MOCK
cat > "${tmp}/install" <<'MOCK'
#!/usr/bin/env bash
: > "${SETUP_AUTORUN_TEST_ROOT}/systemctl.log"
HOME="${SETUP_AUTORUN_TEST_ROOT}/home" PATH="${SETUP_AUTORUN_TEST_ROOT}/bin:${PATH}" \
    bash -c 'source "$1"; install_setup_autorun' _ "${SETUP_AUTORUN_TEST_ROOT}/helpers.sh"
MOCK
chmod +x "${tmp}/bin/systemctl" "${tmp}/install"

"${tmp}/install" > /dev/null
modes=$(stat -c %a "${runner}" "${units}/setup-autorun.service" "${units}/setup-autorun.timer")
[[ "${modes}" == $'755\n644\n644' ]] || fail 'first install modes'
calls=$(<"${tmp}/systemctl.log")
[[ "${calls}" == $'--user daemon-reload\n--user enable --now setup-autorun.timer' ]] || fail 'first install enables the timer'
grep -q "exec %h/.local/bin/setup-autorun" "${units}/setup-autorun.service" || fail 'service runs the runner'
grep -q '^Unit=setup-autorun.service$' "${units}/setup-autorun.timer" || fail 'timer starts the service'

out=$("${tmp}/install")
[[ "${out}" == *'already installed'* && ! -s "${tmp}/systemctl.log" ]] || fail 'unchanged rerun touches nothing'
leftovers=$(find "${home}" -name '*.setup-new')
[[ -z "${leftovers}" ]] || fail 'temporary files are removed'

printf '#!/bin/sh\necho stale\n' > "${runner}"
chmod 775 "${runner}"
exec 3< "${runner}"
"${tmp}/install" > /dev/null
held=$(cat <&3)
exec 3<&-
[[ "${held}" == *stale* ]] || fail 'running copy keeps its bytes'
mode=$(stat -c %a "${runner}")
grep -q 'bb thread list' "${runner}" && [[ "${mode}" == 755 ]] || fail 'stale runner is replaced'
calls=$(<"${tmp}/systemctl.log")
[[ "${calls}" == '--user daemon-reload' ]] || fail 'update reloads without enabling'

chmod 664 "${units}/setup-autorun.timer"
"${tmp}/install" > /dev/null
mode=$(stat -c %a "${units}/setup-autorun.timer")
[[ "${mode}" == 644 ]] || fail 'mode drift is repaired'

rm "${units}/setup-autorun.timer"
status=0
SYSTEMCTL_STATUS=1 "${tmp}/install" > /dev/null 2>&1 || status=$?
[[ "${status}" -ne 0 ]] || fail 'systemctl failure is reported'

cat > "${tmp}/caller" <<'MOCK'
#!/usr/bin/env bash
print_error() { printf 'ERROR: %s\n' "$1"; }
bb_server_platform_ready() { return "${PLATFORM_STATUS:-0}"; }
install_setup_autorun() { echo INSTALL; return "${INSTALL_STATUS:-0}"; }
setup_bb_server() { echo SERVER; }
refresh_bb_plugins() { :; }
check_setup_log_watcher() { :; }
setup_bb_machine() { echo MACHINE; }
source "${SETUP_AUTORUN_TEST_ROOT}/caller.sh"
_setup_had_errors=0
_bb_selection_status=$1
bb_caller
echo "ERRORS=${_setup_had_errors}"
MOCK
chmod +x "${tmp}/caller"
out=$("${tmp}/caller" 0)
[[ "${out}" == *INSTALL*SERVER*ERRORS=0* ]] || fail 'BB_SERVER=1 installs the rerun before the server'
out=$(INSTALL_STATUS=1 "${tmp}/caller" 0)
[[ "${out}" == *'Could not install the idle-bb setup rerun.'*SERVER*ERRORS=1* ]] || fail 'install failure is aggregated and the server still runs'
out=$(PLATFORM_STATUS=1 "${tmp}/caller" 0)
[[ "${out}" != *INSTALL* && "${out}" == *ERRORS=1* ]] || fail 'unready platform skips the rerun'
out=$("${tmp}/caller" 1)
[[ "${out}" != *INSTALL* && "${out}" == *MACHINE* ]] || fail 'BB_SERVER=0 skips the rerun'

cat > "${tmp}/bin/curl" <<'MOCK'
#!/bin/sh
[ "${CURL_STATUS:-0}" = 0 ] || exit 22
while [ "$#" -gt 1 ]; do [ "$1" = -o ] && out=$2; shift; done
cp "${CURL_BODY}" "${out}"
MOCK
cat > "${tmp}/bin/bb" <<'MOCK'
#!/bin/sh
[ "${BB_STATUS:-0}" = 0 ] || exit 1
printf '%s\n' "${BB_THREADS}"
MOCK
cat > "${tmp}/setup-v1.sh" <<'MOCK'
#!/bin/sh
echo ran >> "${SETUP_AUTORUN_TEST_ROOT}/ran"
exit "${SETUP_FIXTURE_STATUS:-0}"
MOCK
cat > "${tmp}/setup-v2.sh" <<'MOCK'
#!/bin/sh
echo ran >> "${SETUP_AUTORUN_TEST_ROOT}/ran"
MOCK
printf 'not a script\n' > "${tmp}/html"
cat > "${tmp}/autorun" <<'MOCK'
#!/usr/bin/env bash
root="${SETUP_AUTORUN_TEST_ROOT}"
idle='[{"status":"idle"},{"status":"error"}]'
CURL_BODY="${CURL_BODY:-${root}/setup-v1.sh}" BB_THREADS="${BB_THREADS:-${idle}}" \
    SETUP_AUTORUN_STATE_DIR="${root}/state" PATH="${root}/bin:${PATH}" "${root}/home/.local/bin/setup-autorun" "$@"
MOCK
chmod +x "${tmp}/bin/curl" "${tmp}/bin/bb" "${tmp}/autorun"
state="${tmp}/state"
runs() { [[ ! -f "${tmp}/ran" ]] || wc -l < "${tmp}/ran"; }

out=$(BB_THREADS='[{"status":"active"},{"status":"pending"},{"status":"idle"}]' "${tmp}/autorun")
[[ "${out}" == 'skip: 2 bb thread(s) running' ]] || fail 'busy threads skip'
out=$(BB_STATUS=1 "${tmp}/autorun" 2> /dev/null)
[[ "${out}" == 'skip: could not list bb threads' ]] || fail 'bb failure skips'
out=$(CURL_STATUS=1 "${tmp}/autorun")
[[ "${out}" == 'skip: could not download'* ]] || fail 'download failure skips'
out=$(CURL_BODY="${tmp}/html" "${tmp}/autorun")
[[ "${out}" == 'skip: download is not a script' ]] || fail 'non-script skips'
out=$("${tmp}/autorun" --dry-run)
[[ "${out}" == 'would run: new version'* ]] || fail 'dry run reports a new version'
[[ ! -e "${tmp}/ran" ]] || fail 'nothing ran before an idle real check'

status=0
out=$(SETUP_FIXTURE_STATUS=3 "${tmp}/autorun") || status=$?
count=$(runs)
[[ "${status}" == 3 && "${out}" == *'run: new version'*'done: exit 3'* && "${count}" == 1 ]] || fail 'idle new version runs and returns its status'
recorded=$(cut -f3,4 "${state}/runs.tsv")
[[ "${recorded}" == $'new version\t3' ]] || fail 'run is recorded'
out=$("${tmp}/autorun")
count=$(runs)
[[ "${out}" == 'skip: version '*' already ran and last run was 0m ago' && "${count}" == 1 ]] || fail 'same version waits an hour'
out=$(CURL_BODY="${tmp}/setup-v2.sh" "${tmp}/autorun")
count=$(runs)
[[ "${out}" == *'run: new version'* && "${count}" == 2 ]] || fail 'new version runs at once'
now=$(date +%s)
echo $(( now - 3601 )) > "${state}/last-run"
out=$("${tmp}/autorun")
count=$(runs)
[[ "${out}" == *'run: hourly rerun'* && "${count}" == 3 ]] || fail 'hourly rerun after an hour'

exec 9> "${state}/lock"
flock -n 9
out=$("${tmp}/autorun")
exec 9>&-
[[ "${out}" == 'skip: another setup-autorun holds the lock' ]] || fail 'lock prevents overlap'

echo 'setup-autorun installer, caller and runner fixtures passed'
