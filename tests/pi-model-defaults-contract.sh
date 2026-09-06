#!/usr/bin/env bash
# Contract version 1: GPT-6 Astra defaults and Synthetic removal.
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
python3 "${repo_root}/tests/test_pi_model_defaults.py"
if command -v pwsh > /dev/null 2>&1; then
    pwsh -NoProfile -File "${repo_root}/tests/pi-model-defaults-powershell.ps1"
else
    printf 'SKIP: PowerShell runtime tests (pwsh not installed)\n'
fi
