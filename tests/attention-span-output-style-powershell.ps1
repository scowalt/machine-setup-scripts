Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $repoRoot "win.ps1"
$styleSource = Join-Path (Join-Path (Join-Path $repoRoot "vendor") "attention-span") "attention-kind.md"

$tokens = $null
$parseErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile(
    $scriptPath,
    [ref]$tokens,
    [ref]$parseErrors
) | Out-Null
if ($parseErrors.Count -gt 0) {
    throw "win.ps1 parse failed: $($parseErrors[0].Message)"
}

$scriptText = Get-Content -LiteralPath $scriptPath -Raw
$scriptText = $scriptText -replace '(?m)^Initialize-WindowsEnvironment\s*$', ''
Invoke-Expression $scriptText

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Assert-ManagedBody {
    param([string]$Path)
    [string[]]$lines = @(Get-Content -LiteralPath $Path)
    Assert-True (@($lines | Where-Object { $_ -ceq "<!-- attention-span:start -->" }).Count -eq 1) "$Path has the wrong begin-marker count"
    Assert-True (@($lines | Where-Object { $_ -ceq "<!-- attention-span:end -->" }).Count -eq 1) "$Path has the wrong end-marker count"
    $content = $lines -join "`n"
    Assert-True ($content.Contains("<!-- attention-span v0.7")) "$Path is missing the reviewed style"
    Assert-True (-not $content.Contains("<!-- body-start -->")) "$Path contains Claude frontmatter"
}

$originalUserProfile = $env:USERPROFILE
$originalClaudeDir = $env:CLAUDE_CONFIG_DIR
$originalCodexHome = $env:CODEX_HOME
$originalPiDir = $env:PI_CODING_AGENT_DIR
$testRoots = [System.Collections.Generic.List[string]]::new()

try {
    $testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("attention-span-" + [guid]::NewGuid().ToString("N"))
    $testRoots.Add($testRoot)
    $env:USERPROFILE = Join-Path $testRoot "home"
    $env:CLAUDE_CONFIG_DIR = Join-Path $testRoot "claude"
    $env:CODEX_HOME = Join-Path $testRoot "codex"
    $env:PI_CODING_AGENT_DIR = Join-Path $testRoot "pi"
    New-Item -ItemType Directory -Force -Path $env:CLAUDE_CONFIG_DIR, $env:CODEX_HOME, (Join-Path $env:USERPROFILE ".gemini"), $env:PI_CODING_AGENT_DIR | Out-Null
    '{"keep":"claude"}' | Set-Content -LiteralPath (Join-Path $env:CLAUDE_CONFIG_DIR "settings.json")
    "keep codex" | Set-Content -LiteralPath (Join-Path $env:CODEX_HOME "AGENTS.md")
    "keep gemini" | Set-Content -LiteralPath (Join-Path (Join-Path $env:USERPROFILE ".gemini") "GEMINI.md")
    "keep pi" | Set-Content -LiteralPath (Join-Path $env:PI_CODING_AGENT_DIR "APPEND_SYSTEM.md")

    function Invoke-WebRequest {
        param(
            [switch]$UseBasicParsing,
            [string]$Uri,
            [string]$OutFile,
            [int]$TimeoutSec,
            $ErrorAction
        )
        Copy-Item -LiteralPath $styleSource -Destination $OutFile -Force
    }

    Assert-True (Install-AttentionSpanStyle) "PowerShell Attention-kind install failed"
    Assert-True (Install-AttentionSpanStyle) "PowerShell Attention-kind repeat install failed"

    $claudeStyle = Join-Path (Join-Path $env:CLAUDE_CONFIG_DIR "output-styles") "attention-kind.md"
    Assert-True (Test-AttentionSpanStyleFile -Path $claudeStyle) "Claude style artifact is invalid"
    $settings = Get-Content -LiteralPath (Join-Path $env:CLAUDE_CONFIG_DIR "settings.json") -Raw | ConvertFrom-Json
    Assert-True ($settings.outputStyle -eq "Attention-kind") "Claude outputStyle was not activated"
    Assert-True ($settings.keep -eq "claude") "Claude setting was not preserved"
    Assert-ManagedBody (Join-Path $env:CODEX_HOME "AGENTS.md")
    Assert-ManagedBody (Join-Path (Join-Path $env:USERPROFILE ".gemini") "GEMINI.md")
    Assert-ManagedBody (Join-Path $env:PI_CODING_AGENT_DIR "APPEND_SYSTEM.md")

    function Invoke-WebRequest { throw "network unavailable" }
    Assert-True (Install-AttentionSpanStyle) "Installed Attention-kind fallback failed"

    $malformedRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("attention-span-malformed-" + [guid]::NewGuid().ToString("N"))
    $testRoots.Add($malformedRoot)
    $env:USERPROFILE = Join-Path $malformedRoot "home"
    $env:CLAUDE_CONFIG_DIR = Join-Path $malformedRoot "claude"
    $env:CODEX_HOME = Join-Path $malformedRoot "codex"
    $env:PI_CODING_AGENT_DIR = Join-Path $malformedRoot "pi"
    New-Item -ItemType Directory -Force -Path $env:CODEX_HOME | Out-Null
    $malformedPath = Join-Path $env:CODEX_HOME "AGENTS.md"
    @("<!-- attention-span:start -->", "keep malformed") | Set-Content -LiteralPath $malformedPath
    $before = [System.IO.File]::ReadAllBytes($malformedPath)

    function Invoke-WebRequest {
        param(
            [switch]$UseBasicParsing,
            [string]$Uri,
            [string]$OutFile,
            [int]$TimeoutSec,
            $ErrorAction
        )
        Copy-Item -LiteralPath $styleSource -Destination $OutFile -Force
    }
    Assert-True (-not (Install-AttentionSpanStyle)) "Malformed markers were accepted"
    $after = [System.IO.File]::ReadAllBytes($malformedPath)
    Assert-True ([Convert]::ToBase64String($before) -eq [Convert]::ToBase64String($after)) "Malformed target was changed"
    Assert-True (-not (Test-Path -LiteralPath (Join-Path (Join-Path $env:CLAUDE_CONFIG_DIR "output-styles") "attention-kind.md"))) "Another target changed before malformed-marker failure"

    $invalidJsonRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("attention-span-json-" + [guid]::NewGuid().ToString("N"))
    $testRoots.Add($invalidJsonRoot)
    $env:USERPROFILE = Join-Path $invalidJsonRoot "home"
    $env:CLAUDE_CONFIG_DIR = Join-Path $invalidJsonRoot "claude"
    $env:CODEX_HOME = Join-Path $invalidJsonRoot "codex"
    $env:PI_CODING_AGENT_DIR = Join-Path $invalidJsonRoot "pi"
    New-Item -ItemType Directory -Force -Path $env:CLAUDE_CONFIG_DIR | Out-Null
    $invalidSettings = Join-Path $env:CLAUDE_CONFIG_DIR "settings.json"
    "{not-json" | Set-Content -LiteralPath $invalidSettings
    $before = [System.IO.File]::ReadAllBytes($invalidSettings)
    Assert-True (-not (Install-AttentionSpanStyle)) "Invalid Claude JSON was accepted"
    $after = [System.IO.File]::ReadAllBytes($invalidSettings)
    Assert-True ([Convert]::ToBase64String($before) -eq [Convert]::ToBase64String($after)) "Invalid Claude JSON was overwritten"

    $unavailableRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("attention-span-none-" + [guid]::NewGuid().ToString("N"))
    $testRoots.Add($unavailableRoot)
    $env:USERPROFILE = Join-Path $unavailableRoot "home"
    $env:CLAUDE_CONFIG_DIR = Join-Path $unavailableRoot "claude"
    $env:CODEX_HOME = Join-Path $unavailableRoot "codex"
    $env:PI_CODING_AGENT_DIR = Join-Path $unavailableRoot "pi"
    function Invoke-WebRequest { throw "network unavailable" }
    Assert-True (-not (Install-AttentionSpanStyle)) "Missing all style sources did not fail"
}
finally {
    $env:USERPROFILE = $originalUserProfile
    $env:CLAUDE_CONFIG_DIR = $originalClaudeDir
    $env:CODEX_HOME = $originalCodexHome
    $env:PI_CODING_AGENT_DIR = $originalPiDir
    foreach ($root in $testRoots) {
        Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "✓ PowerShell Attention-kind contract checks passed"
