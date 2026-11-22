#!/usr/bin/env bash
set -euo pipefail
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
python3 "${repo_root}/tests/test_gemini_cli_retirement.py"
if [[ -n "${PWSH_BIN:-}" ]]; then
    "${PWSH_BIN}" -NoProfile -File "${repo_root}/tests/gemini-cli-retirement-windows.ps1"
else
    printf 'SKIP: Gemini CLI retirement PowerShell fixtures (set PWSH_BIN).\n'
fi
