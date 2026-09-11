#!/usr/bin/env bash
# Contract version 1: isolated shared-runtime fixtures, never full setup entry points.
set -euo pipefail
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "${repo_root}"
for tool in python3 node fish jq; do
    if ! command -v "${tool}" >/dev/null 2>&1; then
        printf 'Shared Node fixtures require %s.\n' "${tool}" >&2
        exit 1
    fi
done
python3 tests/test_shared_node_runtime.py
pwsh_bin="${PWSH_BIN:-}"
if [[ -z "${pwsh_bin}" ]]; then
    pwsh_bin=$(command -v pwsh || true)
fi
if [[ -n "${pwsh_bin}" ]]; then
    "${pwsh_bin}" -NoProfile -File tests/shared-node-runtime-powershell.ps1
else
    printf 'PowerShell runtime fixtures not run: set PWSH_BIN or install pwsh.\n' >&2
fi
