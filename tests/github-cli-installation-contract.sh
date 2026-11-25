#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "${repo_root}"
keyring_fixture="${repo_root}/tests/fixtures/github-cli/githubcli-archive-keyring.gpg"

repo_root=$(python3 tests/extract_setup_fixture.py "${repo_root}") || exit 1

apt_setup_scripts=(ubuntu.sh wsl.sh pi.sh)
expected_source='deb [arch=arm64 signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main'

fail() {
    printf '✗ %s\n' "$1" >&2
    exit 1
}

reference_body=$(sed -n '/^install_github_cli()/,/^}/p' ubuntu.sh)
[[ -n "${reference_body}" ]] || fail "ubuntu.sh: missing install_github_cli"

for file in "${apt_setup_scripts[@]}"; do
    body=$(sed -n '/^install_github_cli()/,/^}/p' "${file}")
    [[ "${body}" == "${reference_body}" ]] || fail "${file}: install_github_cli differs from ubuntu.sh"
    if sed -n '/^update_and_install_core()/,/^}/p' "${file}" | grep -Fq '"gh"'; then
        fail "${file}: core packages still install the distribution's gh"
    fi
    grep -A1 -E '^[[:space:]]*update_and_install_core$' "${file}" \
        | grep -Eq '^[[:space:]]*install_github_cli \|\| _setup_had_errors=1$' \
        || fail "${file}: install_github_cli does not follow core packages with an aggregated failure"
done

run_install() {
    local file=$1
    local keyring_source=$2
    local installed_version=$3
    local status=0

    SETUP_SCRIPT="${repo_root}/${file}" TEST_ROOT="${test_root}" KEYRING_SOURCE="${keyring_source}" \
        INSTALLED_VERSION="${installed_version}" bash -c '
        source <(sed -e '\''s/^main "\$@"$/:/'\'' -e "s#^    local _dir=/etc/apt/sources.list.d\$#    local _dir=${TEST_ROOT}/root/etc/apt/sources.list.d#" "${SETUP_SCRIPT}")
        can_sudo() { return 0; }
        apt-mark() { [[ ! -e "${TEST_ROOT}/held" ]] || printf "gh\n"; }
        curl() {
            while [[ $# -gt 0 ]]; do
                if [[ "$1" == -o ]]; then cp "${KEYRING_SOURCE}" "$2"; return; fi
                shift
            done
            return 1
        }
        sudo() {
            printf "%s\n" "$*" >> "${TEST_ROOT}/sudo.log"
            while [[ "$1" == *=* ]]; do shift; done
            case "$1" in
                install) mkdir -p "$(dirname "${TEST_ROOT}/root$6")"; cp "$5" "${TEST_ROOT}/root$6" ;;
                tee) mkdir -p "$(dirname "${TEST_ROOT}/root$2")"; cat > "${TEST_ROOT}/root$2" ;;
                rm) rm -f "${TEST_ROOT}/root$3" ;;
                apt-get) [[ " $* " != *" install "* ]] || printf "%s" "${INSTALLED_VERSION}" > "${TEST_ROOT}/version" ;;
                *) return 1 ;;
            esac
        }
        dpkg() {
            if [[ "$1" == --print-architecture ]]; then echo arm64; else command dpkg "$@"; fi
        }
        dpkg-query() { cat "${TEST_ROOT}/version" 2> /dev/null; }
        install_github_cli
    ' > "${test_root}/output" 2>&1 || status=$?
    printf '%s' "${status}" > "${test_root}/status"
}

for file in "${apt_setup_scripts[@]}"; do
    test_root=$(mktemp -d)
    run_install "${file}" "${keyring_fixture}" 2.105.0
    [[ "$(< "${test_root}/status")" == 0 ]] || fail "${file}: verified installation failed: $(< "${test_root}/output")"
    cmp -s "${keyring_fixture}" "${test_root}/root/etc/apt/keyrings/githubcli-archive-keyring.gpg" \
        || fail "${file}: signing keyring was not installed"
    [[ "$(< "${test_root}/root/etc/apt/sources.list.d/github-cli.list")" == "${expected_source}" ]] \
        || fail "${file}: unexpected GitHub CLI apt source"
    grep -Fq 'apt-get update -qq -o Dir::Etc::sourcelist=/etc/apt/sources.list.d/github-cli.list -o Dir::Etc::sourceparts=-' \
        "${test_root}/sudo.log" || fail "${file}: GitHub CLI source was not refreshed on its own"
    grep -Eq 'apt-get .* install -qq -y gh$' "${test_root}/sudo.log" || fail "${file}: gh was not installed"
    rm -rf "${test_root}"

    test_root=$(mktemp -d)
    other_source="${test_root}/root/etc/apt/sources.list.d/extrepo_github-cli.sources"
    mkdir -p "${other_source%/*}"
    printf 'URIs: https://cli.github.com/packages\nSigned-By: /var/lib/extrepo/keys/github-cli.asc\n' > "${other_source}"
    printf '%s\n' "${expected_source}" > "${test_root}/root/etc/apt/sources.list.d/github-cli.list"
    run_install "${file}" "${keyring_fixture}" 2.105.0
    [[ "$(< "${test_root}/status")" == 0 ]] || fail "${file}: existing GitHub source elsewhere failed: $(< "${test_root}/output")"
    [[ ! -e "${test_root}/root/etc/apt/sources.list.d/github-cli.list" ]] \
        || fail "${file}: kept a GitHub CLI source that conflicts with ${other_source##*/}"
    [[ ! -e "${test_root}/root/etc/apt/keyrings/githubcli-archive-keyring.gpg" ]] \
        || fail "${file}: installed a second keyring next to an existing GitHub source"
    grep -Fq "Dir::Etc::sourcelist=${other_source} " "${test_root}/sudo.log" \
        || fail "${file}: did not refresh the existing GitHub source"
    rm -rf "${test_root}"

    test_root=$(mktemp -d)
    touch "${test_root}/held"
    run_install "${file}" "${keyring_fixture}" 2.46.0-4
    [[ "$(< "${test_root}/status")" == 0 ]] || fail "${file}: a held gh failed setup"
    [[ ! -e "${test_root}/sudo.log" ]] || fail "${file}: changed the system while gh is held"
    rm -rf "${test_root}"

    test_root=$(mktemp -d)
    printf 'not the GitHub CLI keyring\n' > "${test_root}/tampered.gpg"
    run_install "${file}" "${test_root}/tampered.gpg" 2.105.0
    [[ "$(< "${test_root}/status")" != 0 ]] || fail "${file}: accepted a keyring with the wrong checksum"
    [[ ! -e "${test_root}/sudo.log" ]] || fail "${file}: changed the system after a keyring checksum mismatch"
    rm -rf "${test_root}"

    test_root=$(mktemp -d)
    run_install "${file}" "${keyring_fixture}" 2.46.0-4
    [[ "$(< "${test_root}/status")" != 0 ]] || fail "${file}: accepted the distribution's gh 2.46.0-4"
    grep -Fq '2.102 or later is required' "${test_root}/output" || fail "${file}: old gh failure did not name the minimum"
    rm -rf "${test_root}"
done

printf '✓ GitHub CLI installation contract checks passed\n'
