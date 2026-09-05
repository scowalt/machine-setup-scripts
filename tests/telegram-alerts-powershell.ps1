# Exercise only the placeholder function, never the full Windows setup script.
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$source = Get-Content -Raw (Join-Path $repoRoot 'win.ps1')
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) { throw 'Windows setup contains syntax errors.' }
$function = $ast.Find({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'New-TokenPlaceholders'
}, $false)
if (-not $function) { throw 'Missing New-TokenPlaceholders function.' }
. ([scriptblock]::Create($function.Extent.Text))

$oldProfile = $env:USERPROFILE
$tempHome = Join-Path ([System.IO.Path]::GetTempPath()) ('telegram-alerts-test-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $tempHome | Out-Null
try {
    $env:USERPROFILE = $tempHome
    $path = Join-Path $tempHome '.env.local'
    New-TokenPlaceholders
    $initial = Get-Content -Raw $path
    foreach ($key in @('TELEGRAM_ALERTS_BOT_TOKEN', 'TELEGRAM_ALERTS_CHAT_ID')) {
        if ([regex]::Matches($initial, "(?m)^# ${key}=\r?$").Count -ne 1) {
            throw "Missing or duplicate placeholder: $key"
        }
    }
    New-TokenPlaceholders
    if ((Get-Content -Raw $path) -cne $initial) { throw 'Rerun changed the generated file.' }

    foreach ($content in @(
        'EXISTING=preserve-me',
        "EXISTING=preserve-me`nTELEGRAM_ALERTS_BOT_TOKEN=local-test-value`nTELEGRAM_ALERTS_CHAT_ID=123"
    )) {
        Set-Content -Path $path -Value $content
        $before = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($path))
        New-TokenPlaceholders
        $after = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($path))
        if ($before -cne $after) { throw 'Existing environment file changed.' }
    }
    Write-Output 'PASS: Windows environment creation and preservation'
} finally {
    $env:USERPROFILE = $oldProfile
    Remove-Item -Recurse -Force $tempHome
}
