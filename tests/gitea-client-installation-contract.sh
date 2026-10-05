#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "${repo_root}"

repo_root=$(python3 tests/extract_setup_fixture.py "${repo_root}") || exit 1

bash_setup_scripts=(mac.sh ubuntu.sh wsl.sh pi.sh bazzite.sh)

fail() {
    printf '✗ %s\n' "$1" >&2
    exit 1
}

assert_contains() {
    local file=$1
    local pattern=$2
    local description=$3

    grep -Eq "${pattern}" "${file}" || fail "${file}: missing ${description}"
}

assert_not_contains() {
    local file=$1
    local pattern=$2
    local description=$3

    if grep -Eiq "${pattern}" "${file}"; then
        fail "${file}: unexpectedly contains ${description}"
    fi
}

for file in "${bash_setup_scripts[@]}"; do
    assert_contains "${file}" '^install_gitea_client\(\)' 'Gitea client installer'
    if [[ "${file}" == mac.sh ]]; then
        assert_contains "${file}" '^[[:space:]]*install_gitea_client \|\| _setup_had_errors=1$' 'aggregated Gitea client setup failure'
    else
        assert_contains "${file}" '^[[:space:]]*install_gitea_client \|\| return 1$' 'fatal Gitea client setup call'
    fi
done

assert_contains win.ps1 '^function Install-GiteaClient \{' 'Windows Gitea client installer'
assert_contains win.ps1 '^[[:space:]]*Install-GiteaClient$' 'Windows Gitea client setup call'

for file in "${bash_setup_scripts[@]}"; do
    test_root=$(mktemp -d)
    mutation_log="${test_root}/mutations"
    SETUP_SCRIPT="${repo_root}/${file}" MUTATION_LOG="${mutation_log}" bash -c '
        source <(sed '\''s/^main "\$@"$/:/'\'' "${SETUP_SCRIPT}")
        unset WORK_MACHINE
        brew() { printf "%s\n" "$*" >> "${MUTATION_LOG}"; }
        curl() { printf "%s\n" "$*" >> "${MUTATION_LOG}"; }
        install_gitea_client
    '
    [[ ! -e "${mutation_log}" ]] || fail "${file}: non-work run attempted Gitea client installation"
    rm -rf "${test_root}"
done

for file in mac.sh ubuntu.sh wsl.sh bazzite.sh; do
    test_root=$(mktemp -d)
    mkdir -p "${test_root}/brew/bin"
    brew_log="${test_root}/brew-calls"
    SETUP_SCRIPT="${repo_root}/${file}" TEST_ROOT="${test_root}" BREW_LOG="${brew_log}" bash -c '
        source <(sed '\''s/^main "\$@"$/:/'\'' "${SETUP_SCRIPT}")
        WORK_MACHINE=1
        SETUP_ORIGINAL_PATH=/usr/bin:/bin
        brew() {
            printf "%s\n" "$*" >> "${BREW_LOG}"
            case "$*" in
                --prefix) printf "%s\n" "${TEST_ROOT}/brew" ;;
                "list --formula tea") return 1 ;;
                "install tea")
                    printf '\''#!/usr/bin/env bash\nprintf "Version: 0.15.1\\n"\n'\'' > "${TEST_ROOT}/brew/bin/tea"
                    chmod +x "${TEST_ROOT}/brew/bin/tea"
                    ;;
            esac
        }
        install_gitea_client
    ' || fail "${file}: Homebrew Gitea client installation failed"
    grep -Fxq 'install tea' "${brew_log}" || fail "${file}: work run did not install the Tea formula"
    [[ -x "${test_root}/brew/bin/tea" ]] || fail "${file}: managed Tea executable was not verified"
    rm -rf "${test_root}"
done

for file in mac.sh ubuntu.sh wsl.sh bazzite.sh; do
    test_root=$(mktemp -d)
    mkdir -p "${test_root}/brew/bin"
    printf '#!/usr/bin/env bash\nprintf "Version: 0.15.0\\n"\n' > "${test_root}/brew/bin/tea"
    chmod +x "${test_root}/brew/bin/tea"
    brew_log="${test_root}/brew-calls"
    PATH="${test_root}/brew/bin:/usr/bin:/bin" SETUP_SCRIPT="${repo_root}/${file}" TEST_ROOT="${test_root}" BREW_LOG="${brew_log}" bash -c '
        source <(sed '\''s/^main "\$@"$/:/'\'' "${SETUP_SCRIPT}")
        WORK_MACHINE=1
        brew() {
            printf "%s\n" "$*" >> "${BREW_LOG}"
            case "$*" in
                --prefix) printf "%s\n" "${TEST_ROOT}/brew" ;;
                "list --formula tea") return 0 ;;
                "upgrade tea") return 0 ;;
            esac
        }
        install_gitea_client
    ' || fail "${file}: Homebrew Gitea client update failed"
    grep -Fxq 'upgrade tea' "${brew_log}" || fail "${file}: existing Tea formula was not updated"
    rm -rf "${test_root}"
done

for file in mac.sh ubuntu.sh wsl.sh bazzite.sh; do
    test_root=$(mktemp -d)
    mkdir -p "${test_root}/brew/bin"
    brew_log="${test_root}/brew-calls"
    curl_log="${test_root}/curl-calls"
    if SETUP_SCRIPT="${repo_root}/${file}" TEST_ROOT="${test_root}" BREW_LOG="${brew_log}" CURL_LOG="${curl_log}" bash -c '
        source <(sed '\''s/^main "\$@"$/:/'\'' "${SETUP_SCRIPT}")
        WORK_MACHINE=1
        SETUP_ORIGINAL_PATH=/usr/bin:/bin
        brew() {
            printf "%s\n" "$*" >> "${BREW_LOG}"
            case "$*" in
                --prefix) printf "%s\n" "${TEST_ROOT}/brew" ;;
                "list --formula tea") return 1 ;;
                "install tea") return 23 ;;
            esac
        }
        curl() { printf "%s\n" "$*" >> "${CURL_LOG}"; }
        install_gitea_client
    '; then
        fail "${file}: accepted a failed Homebrew Tea install"
    fi
    [[ ! -e "${curl_log}" ]] || fail "${file}: Homebrew failure fell back to a standalone download"
    rm -rf "${test_root}"
done

for file in mac.sh ubuntu.sh wsl.sh bazzite.sh; do
    test_root=$(mktemp -d)
    mkdir -p "${test_root}/foreign/bin" "${test_root}/brew/bin"
    foreign_tea="${test_root}/foreign/bin/tea"
    printf '#!/usr/bin/env bash\nprintf "foreign tea\\n"\n' > "${foreign_tea}"
    chmod +x "${foreign_tea}"
    brew_log="${test_root}/brew-calls"
    conflict_output=$(PATH="${test_root}/foreign/bin:/usr/bin:/bin" SETUP_SCRIPT="${repo_root}/${file}" TEST_ROOT="${test_root}" BREW_LOG="${brew_log}" bash -c '
        source <(sed '\''s/^main "\$@"$/:/'\'' "${SETUP_SCRIPT}")
        WORK_MACHINE=1
        brew() {
            printf "%s\n" "$*" >> "${BREW_LOG}"
            case "$*" in
                --prefix) printf "%s\n" "${TEST_ROOT}/brew" ;;
                "list --formula tea") return 1 ;;
                "install tea") return 0 ;;
            esac
        }
        install_gitea_client
    ' 2>&1) && fail "${file}: accepted a conflicting tea executable"
    grep -Fq "${foreign_tea}" <<< "${conflict_output}" || fail "${file}: conflict error did not identify the executable"
    [[ -x "${foreign_tea}" ]] || fail "${file}: conflict handling removed the foreign executable"
    if [[ -e "${brew_log}" ]] && grep -Fxq 'install tea' "${brew_log}"; then
        fail "${file}: conflict handling mutated Homebrew"
    fi
    rm -rf "${test_root}"
done

test_root=$(mktemp -d)
mkdir -p "${test_root}/brew/bin"
brew_log="${test_root}/brew-calls"
SETUP_SCRIPT="${repo_root}/pi.sh" TEST_ROOT="${test_root}" BREW_LOG="${brew_log}" bash -c '
    source <(sed '\''s/^main "\$@"$/:/'\'' "${SETUP_SCRIPT}")
    WORK_MACHINE=1
    SETUP_ORIGINAL_PATH=/usr/bin:/bin
    uname() { printf "%s\n" aarch64; }
    brew() {
        printf "%s\n" "$*" >> "${BREW_LOG}"
        case "$*" in
            --prefix) printf "%s\n" "${TEST_ROOT}/brew" ;;
            "list --formula tea") return 1 ;;
            "install tea")
                printf '\''#!/usr/bin/env bash\nprintf "Version: 0.15.1\\n"\n'\'' > "${TEST_ROOT}/brew/bin/tea"
                chmod +x "${TEST_ROOT}/brew/bin/tea"
                ;;
        esac
    }
    install_gitea_client
' || fail 'pi.sh: supported architecture did not use Homebrew for Tea'
grep -Fxq 'install tea' "${brew_log}" || fail 'pi.sh: supported architecture did not install the Tea formula'
rm -rf "${test_root}"

test_root=$(mktemp -d)
mkdir -p "${test_root}/home" "${test_root}/tmp"
fixture="${test_root}/tea-fixture"
printf '#!/usr/bin/env bash\nprintf "Version: 0.15.1\\n"\n' > "${fixture}"
fixture_hash=$(sha256sum "${fixture}" | awk '{print $1}')
curl_log="${test_root}/curl-calls"
HOME="${test_root}/home" TMPDIR="${test_root}/tmp" SETUP_SCRIPT="${repo_root}/pi.sh" TEST_ROOT="${test_root}" FIXTURE_HASH="${fixture_hash}" CURL_LOG="${curl_log}" bash -c '
    source <(sed '\''s/^main "\$@"$/:/'\'' "${SETUP_SCRIPT}")
    WORK_MACHINE=1
    SETUP_ORIGINAL_PATH=/usr/bin:/bin
    uname() { printf "%s\n" armv7l; }
    curl() {
        local argument=""
        local output=""
        local url="${*: -1}"
        printf "%s\n" "${url}" >> "${CURL_LOG}"
        while [[ "$#" -gt 0 ]]; do
            argument=$1
            shift
            if [[ "${argument}" == "-o" ]]; then
                output=$1
                shift
            fi
        done
        case "${url}" in
            */api/v1/repos/gitea/tea/releases/latest)
                printf '\''{"tag_name":"v0.15.1"}\n'\''
                ;;
            */checksums.txt)
                printf "%s  tea-0.15.1-linux-arm-7\n" "${FIXTURE_HASH}" > "${output}"
                ;;
            */tea-0.15.1-linux-arm-7)
                command cp "${TEST_ROOT}/tea-fixture" "${output}"
                ;;
            *) return 22 ;;
        esac
    }
    install_gitea_client
' || fail 'pi.sh: official Tea binary installation failed'
[[ -x "${test_root}/home/.local/bin/tea" ]] || fail 'pi.sh: official Tea binary was not installed'
grep -Fq '/api/v1/repos/gitea/tea/releases/latest' "${curl_log}" || fail 'pi.sh: latest stable Tea release was not queried'
grep -Fq '/checksums.txt' "${curl_log}" || fail 'pi.sh: published Tea checksums were not downloaded'
temp_entry=$(find "${test_root}/tmp" -mindepth 1 -print -quit) || fail 'pi.sh: could not inspect standalone temporary files'
[[ -z "${temp_entry}" ]] || fail 'pi.sh: standalone install left temporary files'
rm -rf "${test_root}"

test_root=$(mktemp -d)
mkdir -p "${test_root}/home/.local/bin" "${test_root}/tmp"
curl_log="${test_root}/curl-calls"
if HOME="${test_root}/home" TMPDIR="${test_root}/tmp" SETUP_SCRIPT="${repo_root}/pi.sh" TEST_ROOT="${test_root}" CURL_LOG="${curl_log}" bash -c '
    source <(sed '\''s/^main "\$@"$/:/'\'' "${SETUP_SCRIPT}")
    WORK_MACHINE=1
    SETUP_ORIGINAL_PATH=/usr/bin:/bin
    uname() { printf "%s\n" armv7l; }
    curl() {
        local argument=""
        local output=""
        local url="${*: -1}"
        printf "%s\n" "${url}" >> "${CURL_LOG}"
        while [[ "$#" -gt 0 ]]; do
            argument=$1
            shift
            if [[ "${argument}" == "-o" ]]; then
                output=$1
                shift
            fi
        done
        case "${url}" in
            */api/v1/repos/gitea/tea/releases/latest) printf '\''{"tag_name":"v0.15.1"}\n'\'' ;;
            */checksums.txt) printf "%064d  tea-0.15.1-linux-arm-7\n" 0 > "${output}" ;;
            */tea-0.15.1-linux-arm-7) printf '\''not the signed fixture\n'\'' > "${output}" ;;
            *) return 22 ;;
        esac
    }
    install_gitea_client
'; then
    fail 'pi.sh: accepted an invalid Tea checksum'
fi
[[ ! -e "${test_root}/home/.local/bin/tea" ]] || fail 'pi.sh: checksum failure changed the managed executable'
temp_entry=$(find "${test_root}/tmp" -mindepth 1 -print -quit) || fail 'pi.sh: could not inspect checksum-failure temporary files'
[[ -z "${temp_entry}" ]] || fail 'pi.sh: checksum failure left temporary files'
rm -rf "${test_root}"

assert_contains win.ps1 'https://gitea\.com/api/v1/repos/gitea/tea/releases/latest' 'latest stable Tea release query'
# shellcheck disable=SC2016
assert_contains win.ps1 'tea-\$version-windows-\$releaseArch\.exe' 'architecture-specific official Tea asset'
assert_contains win.ps1 'checksums\.txt' 'published Tea checksum download'
assert_contains win.ps1 'Get-FileHash .*Algorithm SHA256' 'Tea SHA-256 verification'
assert_contains win.ps1 '\.local[\\/]bin' 'user-local Tea install directory'
assert_contains win.ps1 'SetupOriginalTeaCommand' 'original PATH conflict capture'
assert_contains win.ps1 'Remove-Item .*tempDir.*Recurse.*Force' 'Tea temporary download cleanup'

for file in "${bash_setup_scripts[@]}" win.ps1; do
    assert_not_contains "${file}" 'BAN_TEA|BAN_GITEA' 'Gitea client opt-out flag'
    assert_not_contains "${file}" 'tea[[:space:]]+login|tea[.]exe[[:space:]]+login' 'automated Tea authentication'
done

for file in "${bash_setup_scripts[@]}" win.ps1; do
    assert_contains "${file}" 'Version [0-9]+ \| Last changed: .+' 'current version banner'
done

printf '✓ Gitea client installation contract passed\n'
