#!/usr/bin/env bash
# Offline contract only: never source setup scripts or call real Paseo/services.
# Optional PASEO_MUSE_PID_LOCK_MODULE: explicit @getpaseo/server 0.8.0
# dist/src/server/pid-lock.js, for temporary native lock contenders (no daemon).
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
python3 "${ROOT}/tests/test_paseo_muse_profile.py"
pwsh_bin="${PWSH_BIN:-}"
if [[ -z "${pwsh_bin}" ]]; then
    pwsh_bin=$(command -v pwsh || true)
fi
if [[ -n "${pwsh_bin}" ]]; then
    "${pwsh_bin}" -NoLogo -NoProfile -NonInteractive -File "${ROOT}/tests/paseo-muse-profile-powershell.ps1" -RepositoryRoot "${ROOT}"
else
    printf '%s\n' 'SKIP: PowerShell wrapper fixtures (set PWSH_BIN to enable).'
fi
