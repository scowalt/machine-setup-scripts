#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
PYTHONDONTWRITEBYTECODE=1 python3 tests/test_bb_machine_preparation.py
PYTHONDONTWRITEBYTECODE=1 python3 tests/test_bb_dotfiles_umask.py

pwsh_bin="${PWSH_BIN:-}"
if [[ -z "${pwsh_bin}" ]]; then pwsh_bin=$(command -v pwsh || true); fi
if [[ -n "${pwsh_bin}" ]]; then
    "${pwsh_bin}" -NoProfile -File tests/bb-machine-preparation-powershell.ps1
else
    printf 'SKIP: PowerShell BB guidance fixture (set PWSH_BIN).\n'
fi
printf 'BB machine preparation contract passed. Native platform installation/enrollment is a rollout check.\n'
