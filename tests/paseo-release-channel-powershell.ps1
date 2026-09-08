# Contract version 1: extracted Windows functions and temporary fixtures only.
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$source = Get-Content -Raw (Join-Path $repoRoot 'win.ps1')
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) { throw 'Windows setup contains syntax errors.' }
foreach ($name in @('Get-EnvLocalValue', 'Test-EnvLocalFlag', 'Get-PaseoReleaseChannel', 'Test-PaseoDesktopRunning', 'Set-PaseoDesktopChannel')) {
    $function = $ast.Find({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
    }, $false)
    if (-not $function) { throw "Missing function: $name" }
    . ([scriptblock]::Create($function.Extent.Text))
}
function Write-Success($Message) {}
function Write-Debug($Message) {}
function Write-Warning($Message) { $script:lastWarning = $Message }
function Get-Bytes($Path) { [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($Path)) }
function Assert-Channel($Path, $Channel) {
    $document = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
    if ($document.version -ne 1 -or $document.settings.releaseChannel -cne $Channel -or
        $document.migrations.legacyRendererSettingsImported -isnot [bool] -or -not $document.migrations.legacyRendererSettingsImported) {
        throw 'Incorrect Desktop channel document.'
    }
}
$names = @('USERPROFILE', 'APPDATA', 'PASEO_CHANNEL', 'PASEO_ELECTRON_USER_DATA_DIR', 'HEADLESS', 'WORK_MACHINE')
$oldEnvironment = @{}
foreach ($name in $names) { $oldEnvironment[$name] = [Environment]::GetEnvironmentVariable($name) }
$tempHome = Join-Path ([System.IO.Path]::GetTempPath()) ('paseo-channel-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $tempHome | Out-Null
try {
    $env:USERPROFILE = $tempHome
    $env:APPDATA = Join-Path $tempHome 'Roaming'
    $env:PASEO_CHANNEL = $null
    $env:HEADLESS = $null
    $env:PASEO_ELECTRON_USER_DATA_DIR = $null
    if ((Get-PaseoReleaseChannel) -cne 'beta') { throw 'Wrong default channel.' }
    $envPath = Join-Path $tempHome '.env.local'
    Set-Content -LiteralPath $envPath 'export PASEO_CHANNEL="stable"'
    $envBefore = Get-Bytes $envPath
    if ((Get-PaseoReleaseChannel) -cne 'stable') { throw 'Ignored env-local channel.' }
    $env:PASEO_CHANNEL = 'beta'
    if ((Get-PaseoReleaseChannel) -cne 'beta') { throw 'Ignored process override.' }
    foreach ($bad in @('Beta', 'latest', 'nightly', 'fixture-private-value')) {
        $env:PASEO_CHANNEL = $bad
        $threw = $false
        try { Set-PaseoDesktopChannel | Out-Null } catch {
            $threw = $true
            if ($_.Exception.Message.Contains($bad)) { throw 'Logged invalid channel value.' }
        }
        if (-not $threw -or (Test-Path $env:APPDATA)) { throw 'Invalid channel changed state.' }
    }
    $env:PASEO_CHANNEL = 'beta'
    $script:running = $false
    function Test-PaseoDesktopRunning { return $script:running }
    foreach ($work in @('0', '1')) {
        $env:WORK_MACHINE = $work
        foreach ($custom in @($false, $true)) {
            $env:PASEO_ELECTRON_USER_DATA_DIR = if ($custom) { Join-Path $tempHome "custom desktop $work" } else { $null }
            $directory = if ($custom) { $env:PASEO_ELECTRON_USER_DATA_DIR } else { Join-Path $env:APPDATA 'Paseo' }
            $file = Join-Path $directory 'desktop-settings.json'
            $env:PASEO_CHANNEL = 'beta'
            if (-not (Set-PaseoDesktopChannel)) { throw 'Fresh client channel failed.' }
            Assert-Channel $file 'beta'
            $before = Get-Bytes $file
            (Get-Item $file).LastWriteTimeUtc = [datetime]'2020-01-01'
            $beforeTime = (Get-Item $file).LastWriteTimeUtc
            $script:running = $true
            if (-not (Set-PaseoDesktopChannel)) { throw 'Running no-op failed.' }
            if ((Get-Bytes $file) -cne $before -or (Get-Item $file).LastWriteTimeUtc -ne $beforeTime) { throw 'No-op rewrote file.' }
            $env:PASEO_CHANNEL = 'stable'
            if (Set-PaseoDesktopChannel) { throw 'Edited running client.' }
            if ((Get-Bytes $file) -cne $before) { throw 'Changed running client settings.' }
            $script:running = $false
            Set-Content -LiteralPath $file '{"version":1,"settings":{"releaseChannel":"beta","daemon":{"manageBuiltInDaemon":false,"keepRunningAfterQuit":true},"notifications":{"playSound":false},"unknown":"keep café"},"migrations":{"legacyRendererSettingsImported":false,"daemonStopOnQuitDefaultApplied":true,"future":42},"other":[1,2]}'
            if (-not (Set-PaseoDesktopChannel)) { throw 'Stable channel change failed.' }
            Assert-Channel $file 'stable'
            $document = Get-Content -Raw $file | ConvertFrom-Json
            if ($document.settings.daemon.manageBuiltInDaemon -or -not $document.settings.daemon.keepRunningAfterQuit -or
                $document.settings.notifications.playSound -or $document.settings.unknown -cne 'keep café' -or
                $document.migrations.future -ne 42 -or -not $document.migrations.daemonStopOnQuitDefaultApplied -or
                ($document.other -join ',') -ne '1,2') { throw 'Changed unrelated client data.' }
            $env:PASEO_CHANNEL = 'beta'
            $before = Get-Bytes $file
            function Test-PaseoDesktopRunning { throw 'Process inspection failure' }
            if (Set-PaseoDesktopChannel) { throw 'Process inspection failed open.' }
            if ((Get-Bytes $file) -cne $before) { throw 'Process failure changed settings.' }
            function Test-PaseoDesktopRunning { return $script:running }
            foreach ($invalid in @('', '{private malformed', '{}', 'null', '[]', '[{"version":1,"settings":{}}]', '{"version":2,"settings":{}}', '{"version":"1","settings":{}}', '{"version":1,"settings":[]}', '{"version":1,"settings":{},"migrations":null}', '{"version":1,"settings":{}} {}')) {
                Set-Content -LiteralPath $file $invalid
                $before = Get-Bytes $file
                if (Set-PaseoDesktopChannel) { throw 'Invalid settings accepted.' }
                if ((Get-Bytes $file) -cne $before) { throw 'Invalid settings changed.' }
                if ($script:lastWarning.Contains('private malformed')) { throw 'Parser leaked private settings.' }
            }
            Remove-Item -LiteralPath $file
            New-Item -ItemType Directory -Path $file | Out-Null
            if (Set-PaseoDesktopChannel) { throw 'Directory settings accepted.' }
            Remove-Item -LiteralPath $file
            if (-not (Set-PaseoDesktopChannel)) { throw 'Client fixture restore failed.' }
            if (@(Get-ChildItem $directory -Filter '*.tmp.*').Count) { throw 'Temporary settings leaked.' }
        }
    }
    $env:PASEO_ELECTRON_USER_DATA_DIR = Join-Path $tempHome 'headless desktop'
    $env:HEADLESS = '1'
    if (-not (Set-PaseoDesktopChannel) -or (Test-Path $env:PASEO_ELECTRON_USER_DATA_DIR)) { throw 'Headless setup created client state.' }
    New-Item -ItemType Directory -Path $env:PASEO_ELECTRON_USER_DATA_DIR | Out-Null
    if (-not (Set-PaseoDesktopChannel)) { throw 'Existing headless client not configured.' }
    $env:HEADLESS = '0'
    $env:PASEO_ELECTRON_USER_DATA_DIR = 'relative-client'
    if (Set-PaseoDesktopChannel) { throw 'Relative client path accepted.' }
    if ((Get-Bytes $envPath) -cne $envBefore) { throw 'Changed existing environment file.' }
    if (Test-Path (Join-Path $tempHome '.paseo')) { throw 'Changed standalone daemon state.' }
    # Windows symlinks need Developer Mode or elevation. Run wherever supported.
    $target = Join-Path $tempHome 'link-target'
    New-Item -ItemType Directory -Path $target | Out-Null
    $link = Join-Path $tempHome 'linked-client'
    try { New-Item -ItemType SymbolicLink -Path $link -Target $target -ErrorAction Stop | Out-Null } catch {
        Write-Output 'SKIP: symlink fixtures require filesystem support and Windows symlink permission.'
    }
    if (Test-Path -LiteralPath $link) {
        $env:PASEO_ELECTRON_USER_DATA_DIR = $link
        if (Set-PaseoDesktopChannel) { throw 'Linked client directory accepted.' }
        if (@(Get-ChildItem $target).Count) { throw 'Wrote through client directory link.' }
        $env:PASEO_ELECTRON_USER_DATA_DIR = $target
        $file = Join-Path $target 'desktop-settings.json'
        New-Item -ItemType SymbolicLink -Path $file -Target $envPath | Out-Null
        if (Set-PaseoDesktopChannel) { throw 'Linked client file accepted.' }
        if ((Get-Bytes $envPath) -cne $envBefore) { throw 'Wrote through client file link.' }
    }
    Write-Output 'PASS: Windows Paseo channel selection, client settings, preservation, and safety fixtures'
} finally {
    foreach ($name in $names) { [Environment]::SetEnvironmentVariable($name, $oldEnvironment[$name]) }
    Remove-Item -Recurse -Force -LiteralPath $tempHome
}
