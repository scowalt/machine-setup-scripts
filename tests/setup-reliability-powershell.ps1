$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $repoRoot "win.ps1"
$tokens = $null
$parseErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile(
    $scriptPath,
    [ref]$tokens,
    [ref]$parseErrors
) | Out-Null

if ($parseErrors.Count -gt 0) {
    throw "win.ps1 parse errors:`n$($parseErrors -join "`n")"
}

# Load definitions without running the full machine setup entry point.
$scriptText = Get-Content -Raw $scriptPath
$scriptText = $scriptText -replace '(?m)^Initialize-WindowsEnvironment\r?$', ''
. ([scriptblock]::Create($scriptText))

$script:Messages = [System.Collections.Generic.List[string]]::new()
function global:Write-Message($message) { $script:Messages.Add("MESSAGE: $message") }
function global:Write-Success($message) { $script:Messages.Add("SUCCESS: $message") }
function global:Write-Warning($message) { $script:Messages.Add("WARNING: $message") }
function global:Write-Debug($message) { $script:Messages.Add("DEBUG: $message") }
function global:gcloud {
    Write-Output "ERROR: The Google Cloud CLI"
    Write-Output "component manager"
    Write-Output "is disabled for this installation."
    $global:LASTEXITCODE = 1
}

Update-GcloudComponents
$joinedMessages = $script:Messages -join "`n"
if ($joinedMessages -notmatch 'managed by the package manager; skipping') {
    throw "Wrapped gcloud output was not treated as a package-manager skip:`n$joinedMessages"
}
if ($joinedMessages -match 'Failed to update Google Cloud CLI components') {
    throw "Wrapped gcloud output emitted a failure warning:`n$joinedMessages"
}

# A terminating setup failure must close the transcript, upload the flushed
# log exactly once, and preserve the original exception.
$originalUserProfile = $env:USERPROFILE
$logTestRoot = Join-Path ([System.IO.Path]::GetTempPath()) "machine-setup-log-$([guid]::NewGuid())"
$env:USERPROFILE = Join-Path $logTestRoot "home"
New-Item -ItemType Directory -Force -Path $env:USERPROFILE | Out-Null
$script:UploadCount = 0
$script:UploadedContent = ""
$script:MockUploadFailure = $false

function global:Invoke-RestMethod {
    [CmdletBinding()]
    param(
        $Uri,
        $Method,
        $Form,
        $TimeoutSec
    )

    $script:UploadCount++
    $script:UploadedContent = Get-Content -Raw $Form.file.FullName
    if ($script:MockUploadFailure) {
        throw "simulated collector failure"
    }
}

function global:Invoke-WindowsSetupTasks {
    Write-Host "simulated Windows setup failure"
    throw "simulated Windows setup exception"
}

try {
    $caughtSetupError = $null
    try {
        Initialize-WindowsEnvironment
    }
    catch {
        $caughtSetupError = $_
    }

    if ($null -eq $caughtSetupError -or $caughtSetupError.Exception.Message -notmatch 'simulated Windows setup exception') {
        throw "Windows finalization did not preserve the setup exception"
    }
    if ($script:UploadCount -ne 1) {
        throw "Windows failed run attempted $script:UploadCount uploads instead of one"
    }
    if ($script:UploadedContent -notmatch 'simulated Windows setup failure') {
        throw "Windows upload began before the transcript was flushed"
    }
    if ($script:SetupTranscriptStarted) {
        throw "Windows setup transcript remained active after failure"
    }

    # Collector failure is a warning and must not replace the setup exception.
    $script:Messages.Clear()
    $script:MockUploadFailure = $true
    $caughtSetupError = $null
    try {
        Initialize-WindowsEnvironment
    }
    catch {
        $caughtSetupError = $_
    }

    if ($null -eq $caughtSetupError -or $caughtSetupError.Exception.Message -notmatch 'simulated Windows setup exception') {
        throw "Windows collector failure masked the setup exception"
    }
    if ($script:UploadCount -ne 2) {
        throw "Windows collector failure triggered an unexpected upload count: $script:UploadCount"
    }
    if (($script:Messages -join "`n") -notmatch 'Failed to upload setup log. Local log remains at ') {
        throw "Windows collector failure lacked the local log fallback"
    }
}
finally {
    $env:USERPROFILE = $originalUserProfile
    Remove-Item -Recurse -Force $logTestRoot -ErrorAction SilentlyContinue
}

Write-Output "✓ PowerShell setup reliability checks passed"
