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

$scriptText = Get-Content -Raw $scriptPath
$scriptText = $scriptText -replace '(?m)^Initialize-WindowsEnvironment\r?$', ''
. ([scriptblock]::Create($scriptText))

$script:Messages = [System.Collections.Generic.List[string]]::new()
function global:Write-Message($message) { $script:Messages.Add("MESSAGE: $message") }
function global:Write-Success($message) { $script:Messages.Add("SUCCESS: $message") }
function global:Write-Warning($message) { $script:Messages.Add("WARNING: $message") }
function global:Write-Debug($message) { $script:Messages.Add("DEBUG: $message") }

function Set-AttentionTestFile {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][AllowEmptyString()][string]$Content
    )

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    [System.IO.File]::WriteAllText($Path, $Content)
}

function Set-AttentionManagedFile {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [string]$Prefix = "",
        [string]$Suffix = ""
    )

    Set-AttentionTestFile -Path $Path -Content "$Prefix`n<!-- attention-span:start -->`n<!-- attention-span v0.7 -->`nmanaged guidance`n<!-- attention-span:end -->`n$Suffix`n"
}

$originalUserProfile = $env:USERPROFILE
$originalClaudeConfigDir = $env:CLAUDE_CONFIG_DIR
$originalCodexHome = $env:CODEX_HOME
$originalPiCodingAgentDir = $env:PI_CODING_AGENT_DIR
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) "attention-cleanup-$([guid]::NewGuid())"

try {
    $env:USERPROFILE = Join-Path $testRoot "home"
    $env:CLAUDE_CONFIG_DIR = Join-Path $testRoot "custom-claude"
    $env:CODEX_HOME = Join-Path $testRoot "custom-codex"
    $env:PI_CODING_AGENT_DIR = Join-Path $testRoot "custom-pi"

    $defaultClaude = Join-Path $env:USERPROFILE ".claude"
    $defaultCodex = Join-Path $env:USERPROFILE ".codex"
    $defaultPi = Join-Path $env:USERPROFILE ".pi\agent"
    $geminiFile = Join-Path $env:USERPROFILE ".gemini\GEMINI.md"
    $defaultStyle = Join-Path $defaultClaude "output-styles\attention-kind.md"
    $customStyle = Join-Path $env:CLAUDE_CONFIG_DIR "output-styles\attention-kind.md"
    $symlinkTarget = Join-Path $testRoot "style-target.md"

    Set-AttentionTestFile -Path $defaultStyle -Content "managed style`n"
    Set-AttentionTestFile -Path $symlinkTarget -Content "keep target`n"
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $customStyle) | Out-Null
    $styleWasSymlink = $false
    try {
        New-Item -ItemType SymbolicLink -Path $customStyle -Target $symlinkTarget -ErrorAction Stop | Out-Null
        $styleWasSymlink = $true
    }
    catch {
        Set-AttentionTestFile -Path $customStyle -Content "managed style`n"
    }

    Set-AttentionTestFile -Path (Join-Path $defaultClaude "settings.json") -Content '{"outputStyle":"Attention-kind","keep":"default"}'
    Set-AttentionTestFile -Path (Join-Path $env:CLAUDE_CONFIG_DIR "settings.json") -Content '{"outputStyle":"Other","keep":"custom"}'
    Set-AttentionManagedFile -Path (Join-Path $defaultCodex "AGENTS.md") -Prefix "keep default codex" -Suffix "after default codex"
    Set-AttentionManagedFile -Path (Join-Path $env:CODEX_HOME "AGENTS.md")
    Set-AttentionManagedFile -Path $geminiFile -Prefix "keep gemini" -Suffix "after gemini"
    Set-AttentionManagedFile -Path (Join-Path $defaultPi "APPEND_SYSTEM.md") -Prefix "keep default pi" -Suffix "after default pi"
    Set-AttentionManagedFile -Path (Join-Path $env:PI_CODING_AGENT_DIR "APPEND_SYSTEM.md") -Prefix "keep custom pi" -Suffix "after custom pi"

    Remove-AttentionSpanResources
    Remove-AttentionSpanResources

    foreach ($style in @($defaultStyle, $customStyle)) {
        if ($null -ne (Get-Item -LiteralPath $style -Force -ErrorAction SilentlyContinue)) {
            throw "Attention-kind cleanup left style path: $style"
        }
    }
    if ($styleWasSymlink -and -not (Test-Path -LiteralPath $symlinkTarget -PathType Leaf)) {
        throw "Attention-kind cleanup followed a style symlink target"
    }

    $defaultSettings = Get-Content -Raw (Join-Path $defaultClaude "settings.json") | ConvertFrom-Json
    if ($defaultSettings.keep -ne "default" -or $defaultSettings.PSObject.Properties["outputStyle"]) {
        throw "Attention-kind cleanup damaged default Claude settings"
    }
    $customSettings = Get-Content -Raw (Join-Path $env:CLAUDE_CONFIG_DIR "settings.json") | ConvertFrom-Json
    if ($customSettings.keep -ne "custom" -or $customSettings.outputStyle -ne "Other") {
        throw "Attention-kind cleanup changed an unrelated Claude output style"
    }

    foreach ($sharedFile in @(
        (Join-Path $defaultCodex "AGENTS.md"),
        (Join-Path $env:CODEX_HOME "AGENTS.md"),
        $geminiFile,
        (Join-Path $defaultPi "APPEND_SYSTEM.md"),
        (Join-Path $env:PI_CODING_AGENT_DIR "APPEND_SYSTEM.md")
    )) {
        if (-not (Test-Path -LiteralPath $sharedFile -PathType Leaf)) {
            throw "Attention-kind cleanup removed shared file: $sharedFile"
        }
        $content = Get-Content -Raw $sharedFile
        if ($content -match 'attention-span|managed guidance') {
            throw "Attention-kind cleanup left managed guidance in $sharedFile"
        }
    }

    if ((Get-Content -Raw (Join-Path $defaultCodex "AGENTS.md")) -notmatch "keep default codex" -or
        (Get-Content -Raw $geminiFile) -notmatch "keep gemini" -or
        (Get-Content -Raw (Join-Path $defaultPi "APPEND_SYSTEM.md")) -notmatch "keep default pi" -or
        (Get-Content -Raw (Join-Path $env:PI_CODING_AGENT_DIR "APPEND_SYSTEM.md")) -notmatch "keep custom pi") {
        throw "Attention-kind cleanup removed unrelated shared instructions"
    }
}
finally {
    $env:USERPROFILE = $originalUserProfile
    $env:CLAUDE_CONFIG_DIR = $originalClaudeConfigDir
    $env:CODEX_HOME = $originalCodexHome
    $env:PI_CODING_AGENT_DIR = $originalPiCodingAgentDir
    Remove-Item -Recurse -Force $testRoot -ErrorAction SilentlyContinue
}

# Malformed markers fail during preflight, before another target changes.
$malformedRoot = Join-Path ([System.IO.Path]::GetTempPath()) "attention-malformed-$([guid]::NewGuid())"
try {
    $env:USERPROFILE = Join-Path $malformedRoot "home"
    $env:CLAUDE_CONFIG_DIR = $null
    $env:CODEX_HOME = Join-Path $malformedRoot "custom-codex"
    $env:PI_CODING_AGENT_DIR = $null
    $stylePath = Join-Path $env:USERPROFILE ".claude\output-styles\attention-kind.md"
    $settingsPath = Join-Path $env:USERPROFILE ".claude\settings.json"
    $malformedPath = Join-Path $env:CODEX_HOME "AGENTS.md"
    Set-AttentionTestFile -Path $stylePath -Content "managed style`n"
    Set-AttentionTestFile -Path $settingsPath -Content '{"outputStyle":"Attention-kind","keep":true}'
    Set-AttentionTestFile -Path $malformedPath -Content "<!-- attention-span:start -->`nkeep malformed`n"

    $failed = $false
    try {
        Remove-AttentionSpanResources
    }
    catch {
        $failed = $true
    }
    if (-not $failed) {
        throw "Malformed Attention-kind markers did not fail cleanup"
    }
    if (-not (Test-Path -LiteralPath $stylePath -PathType Leaf)) {
        throw "Attention-kind preflight changed a style before malformed-marker failure"
    }
    $settings = Get-Content -Raw $settingsPath | ConvertFrom-Json
    if ($settings.outputStyle -ne "Attention-kind" -or -not $settings.keep) {
        throw "Attention-kind preflight changed settings before malformed-marker failure"
    }
    if ((Get-Content -Raw $malformedPath) -notmatch "keep malformed") {
        throw "Attention-kind cleanup changed malformed shared instructions"
    }
}
finally {
    $env:USERPROFILE = $originalUserProfile
    $env:CLAUDE_CONFIG_DIR = $originalClaudeConfigDir
    $env:CODEX_HOME = $originalCodexHome
    $env:PI_CODING_AGENT_DIR = $originalPiCodingAgentDir
    Remove-Item -Recurse -Force $malformedRoot -ErrorAction SilentlyContinue
}

function Invoke-AttentionUnsafeFixture {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][scriptblock]$Arrange,
        [Parameter(Mandatory=$true)][scriptblock]$AssertPreserved
    )

    $unsafeRoot = Join-Path ([System.IO.Path]::GetTempPath()) "attention-unsafe-$([guid]::NewGuid())"
    try {
        $env:USERPROFILE = Join-Path $unsafeRoot "home"
        $env:CLAUDE_CONFIG_DIR = $null
        $env:CODEX_HOME = $null
        $env:PI_CODING_AGENT_DIR = $null
        & $Arrange $unsafeRoot

        $failed = $false
        try {
            Remove-AttentionSpanResources
        }
        catch {
            $failed = $true
        }
        if (-not $failed) {
            throw "$Name did not fail Attention-kind cleanup"
        }
        & $AssertPreserved $unsafeRoot
    }
    finally {
        $env:USERPROFILE = $originalUserProfile
        $env:CLAUDE_CONFIG_DIR = $originalClaudeConfigDir
        $env:CODEX_HOME = $originalCodexHome
        $env:PI_CODING_AGENT_DIR = $originalPiCodingAgentDir
        Remove-Item -Recurse -Force $unsafeRoot -ErrorAction SilentlyContinue
    }
}

Invoke-AttentionUnsafeFixture -Name "Invalid Claude JSON" -Arrange {
    param($root)
    Set-AttentionTestFile -Path (Join-Path $env:USERPROFILE ".claude\settings.json") -Content '{not-json'
} -AssertPreserved {
    param($root)
    if ((Get-Content -Raw (Join-Path $env:USERPROFILE ".claude\settings.json")) -notmatch '\{not-json') {
        throw "Attention-kind cleanup changed invalid Claude JSON"
    }
}

Invoke-AttentionUnsafeFixture -Name "Directory at the Claude style path" -Arrange {
    param($root)
    $styleDirectory = Join-Path $env:USERPROFILE ".claude\output-styles\attention-kind.md"
    New-Item -ItemType Directory -Force -Path $styleDirectory | Out-Null
    Set-AttentionTestFile -Path (Join-Path $styleDirectory "sentinel") -Content "keep`n"
} -AssertPreserved {
    param($root)
    $sentinel = Join-Path $env:USERPROFILE ".claude\output-styles\attention-kind.md\sentinel"
    if (-not (Test-Path -LiteralPath $sentinel -PathType Leaf)) {
        throw "Attention-kind cleanup recursively removed a directory at the style path"
    }
}

Write-Host "✓ PowerShell Attention-kind retirement checks passed"
