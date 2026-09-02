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

for file in "${bash_setup_scripts[@]}"; do
    test_root=$(mktemp -d)
    mock_bin="${test_root}/bin"
    package_state="${test_root}/packages"
    command_log="${test_root}/commands"
    mkdir -p "${mock_bin}" "${test_root}/home"
    printf 'npm:pi-ask-user\n' > "${package_state}"
    : > "${command_log}"

    printf '#!/usr/bin/env bash\nexit 0\n' > "${mock_bin}/npm"
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
    chmod +x "${mock_bin}/npm" "${mock_bin}/pi"

    SETUP_SCRIPT="${repo_root}/${file}" \
        SOURCE_WITHOUT_MAIN="${source_without_main}" \
        HOME="${test_root}/home" \
        PATH="${mock_bin}:${PATH}" \
        PI_MOCK_PACKAGE_STATE="${package_state}" \
        PI_MOCK_COMMAND_LOG="${command_log}" \
        bash -c '
            source <(sed "${SOURCE_WITHOUT_MAIN}" "${SETUP_SCRIPT}")
            setup_pi_companion_packages > /dev/null
            setup_pi_companion_packages > /dev/null
        '

    if grep -Fxq 'npm:pi-ask-user' "${package_state}"; then
        fail "${file}: legacy Pi Ask User package remains installed"
    fi

    for package in 'npm:pi-web-access' 'npm:pi-prose'; do
        count=$(grep -Fxc -- "${package}" "${package_state}" || true)
        [[ "${count}" -eq 1 ]] || fail "${file}: expected one installed entry for ${package}, found ${count}"

        install_count=$(grep -Fxc -- "install ${package}" "${command_log}" || true)
        [[ "${install_count}" -eq 2 ]] || fail "${file}: expected ${package} to update on both setup runs, found ${install_count} installs"
    done

    # Regression guard: the retired RPIV packages must never be installed.
    for package in \
        'npm:@juicesharp/rpiv-ask-user-question' \
        'npm:@juicesharp/rpiv-todo'; do
        if grep -Fxq -- "${package}" "${package_state}"; then
            fail "${file}: retired RPIV package ${package} is installed"
        fi
        if grep -Fxq "install ${package}" "${command_log}"; then
            fail "${file}: attempted to install retired RPIV package ${package}"
        fi
    done

    remove_count=$(grep -Fxc 'remove npm:pi-ask-user' "${command_log}" || true)
    [[ "${remove_count}" -eq 1 ]] || fail "${file}: expected one legacy package removal, found ${remove_count}"

    remove_line=$(grep -nFx 'remove npm:pi-ask-user' "${command_log}" | cut -d: -f1)
    install_line=$(grep -nFx 'install npm:pi-web-access' "${command_log}" | head -n 1 | cut -d: -f1)
    [[ "${remove_line}" -lt "${install_line}" ]] || fail "${file}: installed the replacement before removing the legacy package"

    rm -rf "${test_root}"
done

printf '✓ Pi companion package contract checks passed\n'
