#!/usr/bin/env bash
# Version 1 | Retire the Claude Code installation opt-out
# Run only extracted functions with mocked installers. Never install or authenticate Claude Code.
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "${repo_root}"
tmp_root=$(mktemp -d)
trap 'rm -rf "${tmp_root}"' EXIT

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

assert_command_count() {
    local command=$1
    local expected=$2
    local description=$3
    local count
    count=$(grep -Fxc -- "${command}" "${command_log}" || true)
    [[ "${count}" == "${expected}" ]] || fail "${file}: ${description}"
}

for file in mac.sh ubuntu.sh wsl.sh pi.sh bazzite.sh; do
    installer_body=$(awk '/^install_claude_code\(\) \{/ { printing=1 } printing { print } printing && /^}$/ { exit }' "${file}")
    [[ -n "${installer_body}" ]] || fail "${file}: missing Claude Code installer"
    (
        export HOME="${tmp_root}/${file}"
        export BAN_CLAUDE_CODE=1
        export SETUP_ORIGINAL_PATH="${PATH}"
        export SETUP_ORIGINAL_CLAUDE_COMMAND="${HOME}/.local/bin/claude"
        mkdir -p "${HOME}"
        command_log="${HOME}/commands"
        touch "${command_log}"
        supported=1

        # These callbacks are called by the extracted installer function.
        # shellcheck disable=SC2317
        print_debug() { :; }
        # shellcheck disable=SC2317
        print_message() { :; }
        # shellcheck disable=SC2317
        print_success() { :; }
        # shellcheck disable=SC2317
        print_warning() { fail "${file}: unexpected warning: $1"; }
        # shellcheck disable=SC2317
        claude_code_supported_platform() { [[ "${supported}" == 1 ]]; }
        # shellcheck disable=SC2317
        claude_code_native_path() { printf '%s\n' "${HOME}/.local/bin/claude"; }
        # shellcheck disable=SC2317
        claude_code_path_has_native_provenance() { [[ -f "$1" ]]; }
        # shellcheck disable=SC2317
        claude_code_warn_if_shadowed() { :; }
        # shellcheck disable=SC2317
        claude_code_run_installer() {
            printf 'install\n' >> "${command_log}"
            touch "${HOME}/.local/bin/claude"
        }
        # shellcheck disable=SC2317
        claude_code_run_safely() {
            printf '%s\n' "$2" >> "${command_log}"
            printf 'mock claude 1.0\n'
        }
        eval "${installer_body}"
        # Exercise the real create-only environment functions without sourcing user files.
        env_body=$(awk '/^(migrate_token_files|create_env_local)\(\) \{/ { printing=1 } printing { print } printing && /^}$/ { printing=0 }' "${file}")
        eval "${env_body}"
        create_env_local
        if grep -q 'BAN_CLAUDE_CODE' "${HOME}/.env.local"; then
            fail "${file}: new environment template contains retired flag"
        fi
        printf 'BAN_CLAUDE_CODE=1\nKEEP=unchanged\n' > "${HOME}/.env.local"
        cp "${HOME}/.env.local" "${HOME}/original-env"
        create_env_local

        install_claude_code
        assert_command_count install 1 'BAN_CLAUDE_CODE blocked fresh install'
        assert_command_count --version 1 'fresh install was not verified'

        install_claude_code
        assert_command_count install 1 'rerun reinstalled a working native binary'
        assert_command_count update 1 'BAN_CLAUDE_CODE blocked update'
        assert_command_count --version 3 'update was not verified'

        supported=0
        cp "${command_log}" "${HOME}/before-unsupported"
        install_claude_code
        cmp -s "${command_log}" "${HOME}/before-unsupported" || fail "${file}: unsupported platform invoked installer or binary"
        cmp -s "${HOME}/.env.local" "${HOME}/original-env" || fail "${file}: changed an existing environment file"
    )
    printf 'PASS: %s installs and updates with the retired flag set; platform guard remains\n' "${file}"
done

# Inspect all scripts, including Windows, for retired checks and template entries.
for file in mac.sh ubuntu.sh wsl.sh pi.sh bazzite.sh win.ps1; do
    if grep -q 'BAN_CLAUDE_CODE' "${file}"; then
        fail "${file}: still contains the retired Claude Code opt-out"
    fi
done
# Match literal PowerShell syntax.
# shellcheck disable=SC2016
grep -Fq 'if (-not (Test-ClaudeCodeSupportedPlatform))' win.ps1 || fail 'Windows: missing platform guard'
printf '%s\n' 'PASS: Windows static installation contract (PowerShell execution not covered by this test)'

for file in README.md CLAUDE.md; do
    # Match literal Markdown code formatting.
    # shellcheck disable=SC2016
    grep -Fq 'Setup ignores `BAN_CLAUDE_CODE`' "${file}" || fail "${file}: missing retired-flag guidance"
done
printf '%s\n' 'PASS: Claude Code installation contracts'
