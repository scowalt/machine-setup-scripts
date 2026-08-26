#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "${repo_root}"

bash_setup_scripts=(mac.sh ubuntu.sh wsl.sh pi.sh bazzite.sh)
source_without_main='s/^main "\$@"$/:/'

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

assert_min_count() {
    local file=$1
    local pattern=$2
    local minimum=$3
    local description=$4
    local count

    count=$(grep -cE "${pattern}" "${file}" || true)
    [[ "${count}" -ge "${minimum}" ]] || fail "${file}: expected at least ${minimum} ${description}, saw ${count}"
}

for file in "${bash_setup_scripts[@]}"; do
    bash -n "${file}"

    # Regression guard: the retired RPIV packages are gone for good.
    assert_not_contains "${file}" 'pi install npm:@juicesharp/rpiv-ask-user-question' 'install of npm:@juicesharp/rpiv-ask-user-question'
    assert_not_contains "${file}" 'pi install npm:@juicesharp/rpiv-todo' 'install of npm:@juicesharp/rpiv-todo'

    # The companion install array must stay free of retired RPIV packages.
    if awk '/local -a _packages=\(/,/\)/' "${file}" | grep -q 'rpiv'; then
        fail "${file}: setup_pi_companion_packages install array mentions a retired RPIV package"
    fi

    # Removal must run unconditionally in both main() branches.
    assert_contains "${file}" '^remove_pi_rpiv_packages\(\)' 'Pi RPIV packages removal function'
    assert_contains "${file}" 'npm:@juicesharp/rpiv-ask-user-question' 'RPIV ask-user-question removal source'
    assert_contains "${file}" 'npm:@juicesharp/rpiv-todo' 'RPIV todo removal source'
    assert_contains "${file}" 'pi remove' 'pi remove uninstall path'
    assert_min_count "${file}" '^[[:space:]]+remove_pi_rpiv_packages$' 2 'remove_pi_rpiv_packages call sites'
done

assert_contains win.ps1 '^function Remove-PiRpivPackages' 'PowerShell Pi RPIV packages removal function'
assert_contains win.ps1 'npm:@juicesharp/rpiv-ask-user-question' 'PowerShell RPIV ask-user-question removal source'
assert_contains win.ps1 'npm:@juicesharp/rpiv-todo' 'PowerShell RPIV todo removal source'
assert_contains win.ps1 'pi remove' 'PowerShell pi remove uninstall path'
assert_min_count win.ps1 '^\s+Remove-PiRpivPackages$' 2 'Remove-PiRpivPackages call sites'
assert_not_contains win.ps1 'pi install npm:@juicesharp/rpiv-ask-user-question' 'install of npm:@juicesharp/rpiv-ask-user-question'
assert_not_contains win.ps1 'pi install npm:@juicesharp/rpiv-todo' 'install of npm:@juicesharp/rpiv-todo'

if awk '/\$packages = @\(/,/\)/' win.ps1 | grep -q 'rpiv'; then
    fail "win.ps1: Setup-PiCompanionPackages install array mentions a retired RPIV package"
fi

# Functional check: the removal function uninstalls both retired packages,
# keeps unrelated packages, and is idempotent on repeat runs.
for file in "${bash_setup_scripts[@]}"; do
    test_root=$(mktemp -d)
    mock_bin="${test_root}/bin"
    package_state="${test_root}/packages"
    command_log="${test_root}/commands"
    mkdir -p "${mock_bin}" "${test_root}/home"
    printf 'npm:@juicesharp/rpiv-ask-user-question\nnpm:pi-web-access\nnpm:@juicesharp/rpiv-todo\n' > "${package_state}"
    : > "${command_log}"

    cat > "${mock_bin}/pi" <<'MOCK_PI'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "${PI_MOCK_COMMAND_LOG}"

case "${1:-}" in
    list)
        printf 'User packages:\n'
        while IFS= read -r package; do
            [[ -n "${package}" ]] && printf '  %s\n' "${package}"
        done < "${PI_MOCK_PACKAGE_STATE}"
        ;;
    remove)
        package=${2:?missing package source}
        if grep -Fxq -- "${package}" "${PI_MOCK_PACKAGE_STATE}"; then
            tmp=$(mktemp)
            grep -Fxv -- "${package}" "${PI_MOCK_PACKAGE_STATE}" > "${tmp}" || :
            mv "${tmp}" "${PI_MOCK_PACKAGE_STATE}"
        else
            printf 'No matching package found\n' >&2
            exit 1
        fi
        ;;
    install)
        package=${2:?missing package source}
        if ! grep -Fxq -- "${package}" "${PI_MOCK_PACKAGE_STATE}"; then
            printf '%s\n' "${package}" >> "${PI_MOCK_PACKAGE_STATE}"
        fi
        ;;
    *)
        printf 'Unexpected pi command: %s\n' "$*" >&2
        exit 1
        ;;
esac
MOCK_PI
    chmod +x "${mock_bin}/pi"

    SETUP_SCRIPT="${repo_root}/${file}" \
        SOURCE_WITHOUT_MAIN="${source_without_main}" \
        HOME="${test_root}/home" \
        PATH="${mock_bin}:${PATH}" \
        PI_MOCK_PACKAGE_STATE="${package_state}" \
        PI_MOCK_COMMAND_LOG="${command_log}" \
        bash -c '
            source <(sed "${SOURCE_WITHOUT_MAIN}" "${SETUP_SCRIPT}")
            remove_pi_rpiv_packages > /dev/null
            remove_pi_rpiv_packages > /dev/null
        '

    for package in \
        'npm:@juicesharp/rpiv-ask-user-question' \
        'npm:@juicesharp/rpiv-todo'; do
        if grep -Fxq -- "${package}" "${package_state}"; then
            fail "${file}: retired RPIV package ${package} remains installed"
        fi
    done

    grep -Fxq 'npm:pi-web-access' "${package_state}" || fail "${file}: removal deleted npm:pi-web-access"

    # jq fallback: when the pi CLI is unavailable, the function strips both
    # retired package sources directly from settings.json.
    settings_home="${test_root}/settings-home"
    mkdir -p "${settings_home}/.pi/agent"
    cat > "${settings_home}/.pi/agent/settings.json" <<'JSON'
{
  "defaultProvider": "synthetic",
  "packages": [
    "npm:@juicesharp/rpiv-ask-user-question",
    { "source": "npm:@juicesharp/rpiv-todo" },
    "npm:pi-web-access"
  ]
}
JSON

    SETUP_SCRIPT="${repo_root}/${file}" \
        SOURCE_WITHOUT_MAIN="${source_without_main}" \
        HOME="${settings_home}" \
        PATH="/usr/bin:/bin" \
        bash -c '
            source <(sed "${SOURCE_WITHOUT_MAIN}" "${SETUP_SCRIPT}")
            remove_pi_rpiv_packages > /dev/null
            remove_pi_rpiv_packages > /dev/null
        '

    jq -e '.packages == ["npm:pi-web-access"]' "${settings_home}/.pi/agent/settings.json" > /dev/null ||
        fail "${file}: settings fallback did not strip exactly the retired RPIV packages"

    rm -rf "${test_root}"
done

printf '✓ Pi RPIV packages removal contract holds across all setup scripts\n'
