#!/usr/bin/env bash
# Version 1 | Last changed: Test private native Go credentials without setup
set -euo pipefail
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
python3 "${repo_root}/tests/test_pi_opencode_go_setup.py"
if [[ -z "${PWSH_BIN:-}" ]] && ! command -v pwsh > /dev/null 2>&1; then
    printf 'SKIP: Go PowerShell wrapper fixtures (set PWSH_BIN).\n'
fi
