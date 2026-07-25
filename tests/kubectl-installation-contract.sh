#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "${repo_root}"

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

    if grep -Eiq "${pattern}" "${file}"; then
        fail "${file}: unexpectedly contains ${description} (${pattern})"
    fi
}

assert_function_contains() {
    local file=$1
    local function_name=$2
    local pattern=$3
    local description=$4

    if ! sed -n "/^${function_name}()/,/^}/p" "${file}" | grep -Eq "${pattern}"; then
        fail "${file}: ${function_name}() missing ${description} (${pattern})"
    fi
}

bash_targets=(mac.sh ubuntu.sh wsl.sh pi.sh)
for file in "${bash_targets[@]}"; do
    bash -n "${file}"
done

assert_function_contains mac.sh install_core_packages '"kubernetes-cli"' 'kubectl Homebrew formula'
for file in ubuntu.sh wsl.sh pi.sh; do
    assert_function_contains "${file}" install_brew_packages '"kubernetes-cli"' 'kubectl Homebrew formula'
done

assert_contains win.ps1 '"Kubernetes\.kubectl"' 'kubectl WinGet package'
assert_not_contains bazzite.sh 'kubectl|kubernetes-cli' 'kubectl installation'

printf '✓ Kubectl installation contract checks passed\n'
