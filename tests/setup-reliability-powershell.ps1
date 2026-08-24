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

# Legacy Impeccable cleanup removes only setup-owned paths and is idempotent.
$originalCleanupUserProfile = $env:USERPROFILE
$cleanupTestRoot = Join-Path ([System.IO.Path]::GetTempPath()) "impeccable-cleanup-$([guid]::NewGuid())"
$env:USERPROFILE = Join-Path $cleanupTestRoot "home"
$skillPaths = @(
    (Join-Path $env:USERPROFILE ".claude\skills\impeccable"),
    (Join-Path $env:USERPROFILE ".agents\skills\impeccable"),
    (Join-Path $env:USERPROFILE ".cursor\skills\impeccable"),
    (Join-Path $env:USERPROFILE ".gemini\skills\impeccable"),
    (Join-Path $env:USERPROFILE ".pi\agent\skills\impeccable")
)
$agentPaths = @(
    (Join-Path $env:USERPROFILE ".cursor\agents\impeccable-manual-edit-applier.md"),
    (Join-Path $env:USERPROFILE ".cursor\agents\impeccable-asset-producer.md"),
    (Join-Path $env:USERPROFILE ".cursor\agents\impeccable-documenter.md"),
    (Join-Path $env:USERPROFILE ".cursor\agents\impeccable-finish-reviewer.md")
)
$symlinkTarget = Join-Path $cleanupTestRoot "symlink-target"
$symlinkCreated = $false

try {
    New-Item -ItemType Directory -Force -Path $symlinkTarget | Out-Null
    Set-Content -Path (Join-Path $symlinkTarget "sentinel") -Value "keep"
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $skillPaths[0]) | Out-Null
    try {
        New-Item -ItemType SymbolicLink -Path $skillPaths[0] -Target $symlinkTarget -ErrorAction Stop | Out-Null
        $symlinkCreated = $true
    }
    catch {
        New-Item -ItemType Directory -Force -Path $skillPaths[0] | Out-Null
        Set-Content -Path (Join-Path $skillPaths[0] "SKILL.md") -Value "legacy"
    }

    foreach ($skillPath in $skillPaths[1..4]) {
        New-Item -ItemType Directory -Force -Path $skillPath | Out-Null
        Set-Content -Path (Join-Path $skillPath "SKILL.md") -Value "legacy"
    }
    foreach ($agentPath in $agentPaths) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $agentPath) | Out-Null
        Set-Content -Path $agentPath -Value "legacy"
    }

    $siblingSkill = Join-Path $env:USERPROFILE ".agents\skills\keep-me\SKILL.md"
    $siblingAgent = Join-Path $env:USERPROFILE ".cursor\agents\keep-me.md"
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $siblingSkill) | Out-Null
    Set-Content -Path $siblingSkill -Value "keep"
    Set-Content -Path $siblingAgent -Value "keep"

    Remove-ImpeccableResources
    Remove-ImpeccableResources

    foreach ($path in @($skillPaths + $agentPaths)) {
        if (Test-Path -LiteralPath $path) {
            throw "Legacy Impeccable cleanup left $path"
        }
    }
    if (-not (Test-Path -LiteralPath $siblingSkill) -or -not (Test-Path -LiteralPath $siblingAgent)) {
        throw "Legacy Impeccable cleanup removed an unrelated sibling"
    }
    if ($symlinkCreated -and -not (Test-Path -LiteralPath (Join-Path $symlinkTarget "sentinel"))) {
        throw "Legacy Impeccable cleanup followed a symlink target"
    }
}
finally {
    $env:USERPROFILE = $originalCleanupUserProfile
    Remove-Item -Recurse -Force $cleanupTestRoot -ErrorAction SilentlyContinue
}

# Simple English provisioning updates on every run, validates custom harness
# locations, and synchronizes Pi without removing sibling skills.
$originalSimpleEnglishUserProfile = $env:USERPROFILE
$originalClaudeConfigDir = $env:CLAUDE_CONFIG_DIR
$originalCodexHome = $env:CODEX_HOME
$originalPiCodingAgentDir = $env:PI_CODING_AGENT_DIR
$simpleEnglishTestRoot = Join-Path ([System.IO.Path]::GetTempPath()) "simple-english-$([guid]::NewGuid())"
$env:USERPROFILE = Join-Path $simpleEnglishTestRoot "home"
$env:CLAUDE_CONFIG_DIR = Join-Path $simpleEnglishTestRoot "claude-home"
$env:CODEX_HOME = Join-Path $simpleEnglishTestRoot "codex-home"
$env:PI_CODING_AGENT_DIR = Join-Path $simpleEnglishTestRoot "custom-pi"
$script:SimpleEnglishCalls = [System.Collections.Generic.List[string]]::new()

function global:Enable-SimpleEnglishNodeRuntime { return $true }
function global:npx {
    param([Parameter(ValueFromRemainingArguments = $true)][object[]]$Arguments)

    $script:SimpleEnglishCalls.Add(($Arguments -join " "))
    $skillFiles = @(
        (Join-Path $env:CLAUDE_CONFIG_DIR "skills\simple-english\SKILL.md"),
        (Join-Path $env:CODEX_HOME "skills\simple-english\SKILL.md"),
        (Join-Path $env:USERPROFILE ".gemini\skills\simple-english\SKILL.md"),
        (Join-Path $env:USERPROFILE ".pi\agent\skills\simple-english\SKILL.md")
    )
    foreach ($skillFile in $skillFiles) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $skillFile) | Out-Null
        Set-Content -LiteralPath $skillFile -Value "---`nname: simple-english`n---"
    }
    $global:LASTEXITCODE = 0
    Write-Output "mock install complete"
}

try {
    $siblingSkill = Join-Path $env:PI_CODING_AGENT_DIR "skills\keep-me\SKILL.md"
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $siblingSkill) | Out-Null
    Set-Content -LiteralPath $siblingSkill -Value "keep"

    if (-not (Install-SimpleEnglishSkill) -or -not (Install-SimpleEnglishSkill)) {
        throw "Simple English mocked installation failed"
    }

    $expectedArguments = "--yes skills@latest add AminBlg/SimpleEnglish --global --agent claude-code --agent codex --agent gemini-cli --agent pi --skill simple-english --copy --yes"
    if ($script:SimpleEnglishCalls.Count -ne 2 -or ($script:SimpleEnglishCalls | Where-Object { $_ -ne $expectedArguments })) {
        throw "Simple English installer did not update twice with the exact targets: $($script:SimpleEnglishCalls -join '; ')"
    }

    $installedSkillFiles = @(
        (Join-Path $env:CLAUDE_CONFIG_DIR "skills\simple-english\SKILL.md"),
        (Join-Path $env:CODEX_HOME "skills\simple-english\SKILL.md"),
        (Join-Path $env:USERPROFILE ".gemini\skills\simple-english\SKILL.md"),
        (Join-Path $env:PI_CODING_AGENT_DIR "skills\simple-english\SKILL.md")
    )
    foreach ($skillFile in $installedSkillFiles) {
        if (-not (Test-Path -LiteralPath $skillFile -PathType Leaf)) {
            throw "Simple English validation missed $skillFile"
        }
    }
    if (-not (Test-Path -LiteralPath $siblingSkill -PathType Leaf)) {
        throw "Simple English custom Pi sync removed a sibling skill"
    }

    function global:npx {
        $global:LASTEXITCODE = 1
        Write-Output "simulated install failure"
    }
    if (Install-SimpleEnglishSkill) {
        throw "Simple English installer failure was not propagated"
    }
}
finally {
    $env:USERPROFILE = $originalSimpleEnglishUserProfile
    $env:CLAUDE_CONFIG_DIR = $originalClaudeConfigDir
    $env:CODEX_HOME = $originalCodexHome
    $env:PI_CODING_AGENT_DIR = $originalPiCodingAgentDir
    Remove-Item -Recurse -Force $simpleEnglishTestRoot -ErrorAction SilentlyContinue
}

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
