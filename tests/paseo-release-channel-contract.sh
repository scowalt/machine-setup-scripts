#!/usr/bin/env bash
# Contract version 2: cover the trusted Linux system home alias in offline fixtures.
# shellcheck disable=SC1090,SC2030,SC2031,SC2034,SC2310,SC2312,SC2317
set -euo pipefail
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "${repo_root}"
tmp=$(mktemp -d)
trap 'rm -rf "${tmp}"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
extract_function() { awk -v name="$2" '$0 == name "() {" {copy=1} copy {print} copy && /^}$/ {exit}' "$1"; }
extract_channels() { awk '/^# Paseo release channels\./ {copy=1} copy {print} /^# End Paseo release channels\./ {exit}' "$1"; }

for script in mac.sh ubuntu.sh pi.sh bazzite.sh wsl.sh; do
    (
        HOME="${tmp}/${script}"
        mkdir -p "${HOME}"
        unset PASEO_CHANNEL HEADLESS XDG_CONFIG_HOME PASEO_ELECTRON_USER_DATA_DIR _paseo_setup_channel
        source <(extract_function "${script}" read_env_local_value)
        source <(extract_channels "${script}")
        print_error() { printf '%s\n' "$*" >&2; }
        print_warning() { :; }
        print_success() { :; }
        print_debug() { :; }
        print_message() { :; }
        # Test the process guard without inspecting or stopping a real app.
        for process_status in 0 1 2; do
            pgrep() { printf '%s\n' "$*" > "${HOME}/pgrep-call"; return "${process_status}"; }
            actual_status=0
            paseo_desktop_is_running || actual_status=$?
            [[ "${actual_status}" == "${process_status}" ]] || fail "${script}: process guard status"
            [[ "$(< "${HOME}/pgrep-call")" == "-u $(id -u) -x Paseo|paseo" ]] || fail "${script}: process guard scope"
        done
        unset -f pgrep
        paseo_desktop_is_running() { return 1; }
        uname() { printf 'x86_64\n'; }
        [[ "$(paseo_release_channel)" == beta ]] || fail "${script}: default"
        [[ "$(paseo_package_spec)" == @getpaseo/cli@beta ]] || fail "${script}: default package"
        printf 'export PASEO_CHANNEL="stable"\n' > "${HOME}/.env.local"
        cp "${HOME}/.env.local" "${HOME}/env-before"
        [[ "$(paseo_package_spec)" == @getpaseo/cli@latest ]] || fail "${script}: env-local stable"
        PASEO_CHANNEL=beta
        [[ "$(paseo_release_channel)" == beta ]] || fail "${script}: process override"
        (
            _paseo_setup_channel=$(paseo_release_channel)
            # shellcheck source=/dev/null
            source "${HOME}/.env.local"
            [[ "$(paseo_package_spec)" == @getpaseo/cli@beta ]] || fail "${script}: later env load lost process override"
        )
        PASEO_CHANNEL=stable
        [[ "$(paseo_package_spec)" == @getpaseo/cli@latest ]] || fail "${script}: stable package"
        for bad in Beta latest nightly 'fixture-private-value'; do
            PASEO_CHANNEL="${bad}"
            if configure_paseo_desktop_channel linux > "${HOME}/invalid-log" 2>&1; then fail "${script}: invalid channel"; fi
            [[ ! -e "${HOME}/.config" ]] || fail "${script}: invalid channel changed state"
            if grep -qF "${bad}" "${HOME}/invalid-log"; then fail "${script}: invalid value was logged"; fi
        done
        PASEO_CHANNEL=beta
        for platform in macos linux; do
            case "${platform}" in
                macos) directory="${HOME}/Library/Application Support/Paseo" ;;
                linux) XDG_CONFIG_HOME="${HOME}/custom config"; directory="${XDG_CONFIG_HOME}/Paseo" ;;
                *) fail "Unexpected fixture platform" ;;
            esac
            file="${directory}/desktop-settings.json"
            configure_paseo_desktop_channel "${platform}"
            jq -e '.version == 1 and .settings.releaseChannel == "beta" and .migrations.legacyRendererSettingsImported' "${file}" > /dev/null
            [[ "$(stat -c %a "${file}")" == 600 ]] || fail "${script}: file privacy"
            cp "${file}" "${HOME}/before"
            touch -t 202001010000 "${file}"
            before_time=$(stat -c %Y "${file}")
            paseo_desktop_is_running() { return 0; }
            configure_paseo_desktop_channel "${platform}"
            cmp "${file}" "${HOME}/before"
            [[ "$(stat -c %Y "${file}")" == "${before_time}" ]] || fail "${script}: no-op rewrote file"
            PASEO_CHANNEL=stable
            if configure_paseo_desktop_channel "${platform}" 2>/dev/null; then fail "${script}: edited running app"; fi
            cmp "${file}" "${HOME}/before"
            paseo_desktop_is_running() { return 2; }
            if configure_paseo_desktop_channel "${platform}" 2>/dev/null; then fail "${script}: process query failed open"; fi
            cmp "${file}" "${HOME}/before"
            paseo_desktop_is_running() { return 1; }
            printf '%s\n' '{"version":1,"settings":{"releaseChannel":"beta","daemon":{"manageBuiltInDaemon":false,"keepRunningAfterQuit":true},"notifications":{"playSound":false},"unknown":"keep café"},"migrations":{"legacyRendererSettingsImported":false,"daemonStopOnQuitDefaultApplied":true,"future":42},"other":[1,2]}' > "${file}"
            configure_paseo_desktop_channel "${platform}"
            jq -e '.settings.releaseChannel == "stable" and .settings.daemon == {manageBuiltInDaemon:false,keepRunningAfterQuit:true} and .settings.notifications.playSound == false and .settings.unknown == "keep café" and .migrations == {legacyRendererSettingsImported:true,daemonStopOnQuitDefaultApplied:true,future:42} and .other == [1,2]' "${file}" > /dev/null
            cp "${file}" "${HOME}/before"
            PASEO_CHANNEL=beta
            (
                mv() { return 1; }
                if configure_paseo_desktop_channel "${platform}" 2>/dev/null; then fail "${script}: failed write accepted"; fi
            )
            cmp "${file}" "${HOME}/before"
            [[ -z "$(find "${directory}" -name '*.tmp.*' -print)" ]] || fail "${script}: temp file leaked"
            for invalid in '' '{private malformed' '{}' 'null' '[]' '{"version":2,"settings":{}}' '{"version":1,"settings":[]}' '{"version":1,"settings":{},"migrations":null}' '{"version":1,"settings":{}} {}'; do
                printf '%s' "${invalid}" > "${file}"
                cp "${file}" "${HOME}/before"
                if configure_paseo_desktop_channel "${platform}" 2> "${HOME}/error"; then fail "${script}: invalid settings accepted"; fi
                cmp "${file}" "${HOME}/before"
                if grep -q 'private malformed' "${HOME}/error"; then fail "${script}: parser leaked settings"; fi
            done
            rm "${file}"
            ln -s "${HOME}/before" "${file}"
            if configure_paseo_desktop_channel "${platform}" 2>/dev/null; then fail "${script}: symlink accepted"; fi
            [[ -L "${file}" ]] || fail "${script}: symlink replaced"
            rm "${file}"
            mkdir "${file}"
            if configure_paseo_desktop_channel "${platform}" 2>/dev/null; then fail "${script}: directory file accepted"; fi
            rmdir "${file}" "${directory}"
            ln -s "${HOME}/missing" "${directory}"
            if configure_paseo_desktop_channel "${platform}" 2>/dev/null; then fail "${script}: linked directory accepted"; fi
            [[ ! -e "${HOME}/missing" ]] || fail "${script}: wrote through link"
            rm "${directory}"
        done
        PASEO_ELECTRON_USER_DATA_DIR="${HOME}/custom desktop"
        HEADLESS=1
        configure_paseo_desktop_channel linux
        [[ ! -e "${PASEO_ELECTRON_USER_DATA_DIR}" ]] || fail "${script}: seeded headless client"
        HEADLESS=0
        configure_paseo_desktop_channel wsl
        [[ ! -e "${PASEO_ELECTRON_USER_DATA_DIR}" ]] || fail "${script}: WSL changed client"
        uname() { printf 'aarch64\n'; }
        configure_paseo_desktop_channel linux
        [[ ! -e "${PASEO_ELECTRON_USER_DATA_DIR}" ]] || fail "${script}: seeded unsupported ARM desktop"
        mkdir "${PASEO_ELECTRON_USER_DATA_DIR}"
        HEADLESS=1
        configure_paseo_desktop_channel linux
        jq -e '.settings.releaseChannel == "beta"' "${PASEO_ELECTRON_USER_DATA_DIR}/desktop-settings.json" > /dev/null
        for work in 0 1; do
            WORK_MACHINE="${work}"
            for channel in stable beta; do
                PASEO_CHANNEL="${channel}"
                configure_paseo_desktop_channel linux
                jq -e --arg channel "${channel}" '.settings.releaseChannel == $channel' "${PASEO_ELECTRON_USER_DATA_DIR}/desktop-settings.json" > /dev/null
            done
        done
        cmp "${HOME}/.env.local" "${HOME}/env-before"
        [[ ! -e "${HOME}/.paseo" ]] || fail "${script}: desktop changed daemon state"

        if [[ "${script}" != wsl.sh ]]; then
            source <(extract_function "${script}" install_paseo_cli)
            PASEO_PACKAGE=@getpaseo/cli
            paseo_service_path() { printf '/usr/bin\n'; }
            paseo_command_target() { return 1; }
            ensure_pi_node_runtime() { return 0; }
            bun() { printf '%s\n' "$*" > "${HOME}/bun-call"; return 1; }
            for channel in beta stable; do
                PASEO_CHANNEL="${channel}"
                spec=$(paseo_package_spec)
                if install_paseo_cli 2>/dev/null; then fail "${script}: install failure hidden"; fi
                [[ "$(< "${HOME}/bun-call")" == "install -g ${spec}" ]] || fail "${script}: wrong install tag"
            done
            rm "${HOME}/bun-call"
            PASEO_CHANNEL=invalid
            if install_paseo_cli 2>/dev/null; then fail "${script}: invalid installer channel"; fi
            [[ ! -e "${HOME}/bun-call" ]] || fail "${script}: installed invalid channel"
            for headless in '' 0 true; do
                HEADLESS="${headless}"
                install_paseo_cli
                [[ ! -e "${HOME}/bun-call" ]] || fail "${script}: non-headless daemon install"
            done
        fi
        printf 'PASS: %s release channel and client fixtures\n' "${script}"
    )
done
python3 - <<'PY'
from pathlib import Path
scripts = ['mac.sh', 'ubuntu.sh', 'pi.sh', 'bazzite.sh', 'wsl.sh']
blocks = []
for name in scripts:
    text = Path(name).read_text()
    blocks.append(text.split('# Paseo release channels.')[1].split('# End Paseo release channels.')[0])
    assert '# PASEO_CHANNEL=beta' in text
    assert 'PASEO_CHANNEL="${_paseo_channel_override}"' in text
    assert '    _paseo_setup_channel=$(paseo_release_channel) || return 1' in text
    platform = 'macos' if name == 'mac.sh' else 'wsl' if name == 'wsl.sh' else 'linux'
    assert f'    configure_paseo_desktop_channel {platform} || return 1' in text
    if name != 'wsl.sh':
        assert 'bun install -g "${_package_spec}"' in text
assert len(set(blocks)) == 1, 'Bash channel blocks drifted'
windows = Path('win.ps1').read_text()
assert '# PASEO_CHANNEL=beta' in windows
assert 'if (-not (Set-PaseoDesktopChannel)) { throw' in windows
assert '$null = Get-PaseoReleaseChannel' in windows
print('PASS: setup wiring and identical Bash channel blocks')
PY
python3 tests/test_paseo_system_home_alias.py
if command -v pwsh > /dev/null; then
    pwsh -NoProfile -File tests/paseo-release-channel-powershell.ps1
else
    printf 'SKIP: PowerShell runtime unavailable; Windows fixtures not run\n'
fi
