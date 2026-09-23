#!/usr/bin/env bash
# Version 1 | Last changed: Run isolated Infisical retirement fixtures
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "${repo_root}"

# These tests extract only helpers/caller seams into temporary or in-memory
# fixtures. Never source or execute any complete setup script.
python3 -m unittest \
    tests.test_infisical_apt_retirement \
    tests.test_infisical_native_retirement \
    tests.test_infisical_callers

pwsh_bin=${PWSH_BIN:-}
if [[ -z "${pwsh_bin}" ]]; then
    pwsh_bin=$(command -v pwsh || true)
fi
if [[ -n "${pwsh_bin}" ]]; then
    if ! command -v "${pwsh_bin}" >/dev/null 2>&1; then
        printf '✗ PowerShell fixture runtime unavailable: PWSH_BIN is invalid.\n' >&2
        exit 1
    fi
    "${pwsh_bin}" -NoLogo -NoProfile -NonInteractive -File tests/infisical-retirement-windows.ps1
else
    printf 'SKIP: Infisical PowerShell fixtures (set PWSH_BIN or install pwsh).\n'
fi
printf '✓ Infisical retirement offline contract passed\n'
