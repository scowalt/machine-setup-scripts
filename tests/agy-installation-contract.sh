#!/usr/bin/env bash
set -euo pipefail
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
python3 "${repo_root}/tests/test_agy_installation.py"
if [[ -n "${PWSH_BIN:-}" ]]; then
    "${PWSH_BIN}" -NoProfile -File "${repo_root}/tests/agy-installation-windows.ps1"
else
    printf 'SKIP: Antigravity CLI PowerShell fixtures (set PWSH_BIN).\n'
fi
