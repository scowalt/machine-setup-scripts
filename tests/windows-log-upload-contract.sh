#!/usr/bin/env bash
# Version 1 | Last changed: Guard recoverable Windows setup log uploads
# Offline fixtures only. Never run full setup or upload test logs.
set -euo pipefail
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "${repo_root}"

python3 - <<'PY'
from pathlib import Path

script = Path('win.ps1').read_text()
logging = script[script.index('function Get-SetupLogDirectory {'):script.index('function Invoke-WindowsSetupTasks {')]
assert '-Form ' not in logging, 'Uploader must work without PowerShell 7 web parameters'
assert 'MultipartFormDataContent' in logging and 'StreamContent' in logging, 'Upload must preserve multipart file bytes'
assert '$handler.AllowAutoRedirect = $false' in logging, 'Do not send logs to redirect destinations'
assert 'ServerCertificateValidationCallback' not in logging and 'ServerCertificateCustomValidationCallback' not in logging, 'Preserve TLS verification'
assert 'ResponseHeadersRead' in logging, 'Do not consume or print collector response bodies'
assert 'ReparsePoint' in logging and 'FileShare]::None' in logging, 'Reject links and simultaneous state mutations'
assert 'Invoke-PendingSetupLogUploads' in script, 'Next runs must recover pending uploads'
fixture = Path('tests/windows-log-upload-powershell.ps1').read_text()
assert 'Parser]::ParseFile' in fixture and '$node.Extent.Text' in fixture, 'Extract functions rather than source setup'
print('PASS: Windows uploader static contracts')
PY

pwsh_bin=${PWSH_BIN:-}
if [[ -z "${pwsh_bin}" ]] && command -v pwsh >/dev/null 2>&1; then
    pwsh_bin=$(command -v pwsh)
fi
if [[ -n "${pwsh_bin}" ]]; then
    "${pwsh_bin}" -NoLogo -NoProfile -NonInteractive -File tests/windows-log-upload-powershell.ps1
else
    printf '%s\n' 'SKIP: Set PWSH_BIN to run the offline PowerShell logging fixtures.'
fi
