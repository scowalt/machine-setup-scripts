#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
PYTHONDONTWRITEBYTECODE=1 python3 tests/test_bb_desktop.py

pwsh_bin="${PWSH_BIN:-}"
if [[ -z "${pwsh_bin}" ]]; then
    pwsh_bin=$(command -v pwsh || command -v powershell || true)
fi
if [[ -n "${pwsh_bin}" && -x "${pwsh_bin}" ]]; then
    "${pwsh_bin}" -NoProfile -NonInteractive -File tests/bb-desktop-windows-contract.ps1
else
    printf 'SKIP: PowerShell unavailable; Windows desktop wrapper has static coverage only.\n'
fi
printf 'bb desktop contract passed (native macOS/Linux GUI rollout not exercised).\n'
