#!/usr/bin/env bash
# Exercise only environment-file functions. Never run full setup or contact Telegram.
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "${repo_root}"
tmp_root=$(mktemp -d)
trap 'rm -rf "${tmp_root}"' EXIT

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

function_body() {
    local file=$1
    local name=$2
    awk -v start="${name}() {" '$0 == start { printing=1 } printing { print } printing && /^}$/ { exit }' "${file}"
}

assert_placeholders() {
    local file=$1
    local key count
    for key in TELEGRAM_ALERTS_BOT_TOKEN TELEGRAM_ALERTS_CHAT_ID; do
        count=$(grep -c "^# ${key}=$" "${file}" || true)
        [[ ${count} == 1 ]] || fail "${file}: missing or duplicate ${key} placeholder"
        if grep -Eq "^[[:space:]]*${key}=" "${file}"; then
            fail "${file}: active alert credential in template"
        fi
    done
    # The tilde is literal documentation text, not a shell path.
    # shellcheck disable=SC2088
    grep -Fq '~/.config/agent-docs/telegram-alerts.md' "${file}" || fail "${file}: missing guide reference"
    grep -Fq "Work-machine alerts require Scott's explicit permission" "${file}" || fail "${file}: missing work permission policy"
}

for file in mac.sh ubuntu.sh wsl.sh pi.sh bazzite.sh; do
    bash -n "${file}"
    assert_placeholders "${file}"
    home="${tmp_root}/${file}"
    mkdir -p "${home}"
    migrate_body=$(function_body "${file}" migrate_token_files)
    create_body=$(function_body "${file}" create_env_local)
    [[ -n "${migrate_body}" && -n "${create_body}" ]] || fail "${file}: cannot extract environment functions"

    (
        export HOME="${home}"
        # These callbacks are used by the extracted setup functions.
        # shellcheck disable=SC2317
        print_debug() { :; }
        # shellcheck disable=SC2317
        print_message() { :; }
        # Only trusted functions from the repository are evaluated, never credential files.
        eval "${migrate_body}"
        eval "${create_body}"
        create_env_local
        assert_placeholders "${HOME}/.env.local"
        permissions=$(stat -c '%a' "${HOME}/.env.local" 2>/dev/null || stat -f '%Lp' "${HOME}/.env.local")
        [[ ${permissions} == 600 ]] || fail "${file}: environment file permissions"
        cp "${HOME}/.env.local" "${home}/first-run"
        create_env_local
        cmp -s "${HOME}/.env.local" "${home}/first-run" || fail "${file}: rerun changed generated file"

        printf '%s\n' 'EXISTING=preserve-me' 'TELEGRAM_ALERTS_BOT_TOKEN=local-test-value' 'TELEGRAM_ALERTS_CHAT_ID=123' > "${HOME}/.env.local"
        cp "${HOME}/.env.local" "${home}/before"
        create_env_local
        cmp -s "${HOME}/.env.local" "${home}/before" || fail "${file}: changed existing credentials"

        printf '%s\n' 'EXISTING=preserve-me' > "${HOME}/.env.local"
        cp "${HOME}/.env.local" "${home}/before"
        create_env_local
        cmp -s "${HOME}/.env.local" "${home}/before" || fail "${file}: modified old file without alert keys"
    )
    printf 'PASS: %s environment creation and preservation\n' "${file}"
done

# Always inspect the Windows template; execute its function when PowerShell is available.
awk '/^function New-TokenPlaceholders \{/ { printing=1 } printing { print } printing && /^}$/ { exit }' win.ps1 > "${tmp_root}/windows-function"
assert_placeholders "${tmp_root}/windows-function"
# Match literal PowerShell syntax.
# shellcheck disable=SC2016
grep -Fq 'if (-not (Test-Path $envLocalPath))' "${tmp_root}/windows-function" || fail 'Windows: missing create-only guard'
if command -v pwsh >/dev/null 2>&1; then
    pwsh -NoProfile -NonInteractive -File tests/telegram-alerts-powershell.ps1
else
    printf '%s\n' 'SKIP: PowerShell execution unavailable; Windows template contract passed.'
fi

printf '%s\n' 'PASS: Telegram alert environment contracts'
