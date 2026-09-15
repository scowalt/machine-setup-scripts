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

# Retired RTK cleanup removes the managed footprint and preserves unrelated state.
$originalRtkUserProfile = $env:USERPROFILE
$originalRtkLocalAppData = $env:LOCALAPPDATA
$originalRtkAppData = $env:APPDATA
$originalRtkClaudeConfigDir = $env:CLAUDE_CONFIG_DIR
$originalRtkCodexHome = $env:CODEX_HOME
$originalRtkPiCodingAgentDir = $env:PI_CODING_AGENT_DIR
$originalRtkProcessPath = $env:PATH
$originalRtkUserPath = [Environment]::GetEnvironmentVariable("PATH", "User")
$rtkTestRoot = Join-Path ([System.IO.Path]::GetTempPath()) "rtk-cleanup-$([guid]::NewGuid())"
$env:USERPROFILE = Join-Path $rtkTestRoot "home"
$env:LOCALAPPDATA = Join-Path $rtkTestRoot "local-app-data"
$env:APPDATA = Join-Path $rtkTestRoot "app-data"
$env:CLAUDE_CONFIG_DIR = Join-Path $rtkTestRoot "custom-claude"
$env:CODEX_HOME = Join-Path $rtkTestRoot "custom-codex"
$env:PI_CODING_AGENT_DIR = Join-Path $rtkTestRoot "custom-pi"
$rtkDir = Join-Path $env:LOCALAPPDATA "rtk\bin"
$managedRtkBinary = Join-Path $rtkDir "rtk.exe"

function global:Test-RtkTokenKiller { return $true }
function global:Invoke-RtkUpstreamUninstall { }

function Set-RtkTestFile {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Content
    )

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    [System.IO.File]::WriteAllText($Path, $Content)
}

function Set-RtkTestPiFile {
    param([Parameter(Mandatory=$true)][string]$Path)

    Set-RtkTestFile -Path $Path -Content @'
# Global

## RTK token-optimized commands

- RTK (`rtk-ai/rtk`) is installed by the machine setup scripts when available. Prefer `rtk <command>` for noisy shell commands with supported filters (`git`, `gh`, tests, build/lint tools, package managers, file/search commands) unless full raw output is required.
- Bypass RTK for one command with `RTK_DISABLED=1 <command>` or by running the raw command directly when exact output formatting matters.

## Keep

Keep this.
'@
}

try {
    Set-RtkTestFile -Path $managedRtkBinary -Content "managed"
    Set-RtkTestFile -Path (Join-Path $env:APPDATA "rtk\history.db") -Content "history"
    Set-RtkTestFile -Path (Join-Path $env:USERPROFILE ".env.local") -Content "BAN_RTK=1`n"

    $defaultClaude = Join-Path $env:USERPROFILE ".claude"
    foreach ($claudeDir in @($defaultClaude, $env:CLAUDE_CONFIG_DIR)) {
        Set-RtkTestFile -Path (Join-Path $claudeDir "RTK.md") -Content "legacy"
        Set-RtkTestFile -Path (Join-Path $claudeDir "hooks\rtk-rewrite.sh") -Content "legacy"
        Set-RtkTestFile -Path (Join-Path $claudeDir "hooks\.rtk-hook.sha256") -Content "hash"
        Set-RtkTestFile -Path (Join-Path $claudeDir "CLAUDE.md") -Content "# Keep`n`n@RTK.md`n"
    }
    $rtkSymlinkTarget = Join-Path $rtkTestRoot "rtk-symlink-target"
    $rtkSymlinkSentinel = Join-Path $rtkSymlinkTarget "sentinel"
    Set-RtkTestFile -Path $rtkSymlinkSentinel -Content "keep"
    $defaultClaudeRtk = Join-Path $defaultClaude "RTK.md"
    Remove-Item -LiteralPath $defaultClaudeRtk -Force
    try {
        New-Item -ItemType SymbolicLink -Path $defaultClaudeRtk -Target $rtkSymlinkTarget -ErrorAction Stop | Out-Null
    }
    catch {
        Set-RtkTestFile -Path $defaultClaudeRtk -Content "legacy"
    }
    $claudeSettings = @{
        model = "keep"
        hooks = @{
            PreToolUse = @(
                @{ matcher = "Bash"; hooks = @(@{ type = "command"; command = "rtk hook claude" }) },
                @{ matcher = "Keep"; hooks = @(@{ type = "command"; command = "keep hook" }) }
            )
        }
    } | ConvertTo-Json -Depth 10
    Set-RtkTestFile -Path (Join-Path $defaultClaude "settings.json") -Content $claudeSettings

    $defaultCodex = Join-Path $env:USERPROFILE ".codex"
    foreach ($codexDir in @($defaultCodex, $env:CODEX_HOME)) {
        Set-RtkTestFile -Path (Join-Path $codexDir "RTK.md") -Content "legacy"
        Set-RtkTestFile -Path (Join-Path $codexDir "AGENTS.md") -Content "# Keep`n`n@$codexDir\RTK.md`n"
    }
    $customCodexReference = "@$(($env:CODEX_HOME -replace '\\', '/'))/RTK.md"
    Set-RtkTestFile -Path (Join-Path $env:CODEX_HOME "AGENTS.md") -Content "# Keep`n`n$customCodexReference`n"

    $geminiDir = Join-Path $env:USERPROFILE ".gemini"
    $geminiHook = Join-Path $geminiDir "hooks\rtk-hook-gemini.sh"
    Set-RtkTestFile -Path (Join-Path $geminiDir "GEMINI.md") -Content @'
# RTK - Rust Token Killer

**Usage**: Token-optimized CLI proxy (cuts up to 90% of bash output)

## Meta Commands (always use rtk directly)

```bash
rtk gain
rtk proxy git status
```

## Installation Verification

```bash
rtk --version
which rtk
```

## Hook-Based Usage

All other commands are automatically rewritten by the Claude Code hook.
Example: `git status` → `rtk git status`
Refer to CLAUDE.md for full command reference.
'@
    Set-RtkTestFile -Path $geminiHook -Content "#!/bin/bash`nexec rtk hook gemini`n"
    Set-RtkTestFile -Path (Join-Path $geminiDir "hooks\.rtk-hook.sha256") -Content "hash"
    $geminiSettings = @{
        theme = "keep"
        hooks = @{
            BeforeTool = @(
                @{ matcher = "run_shell_command"; hooks = @(@{ type = "command"; command = $geminiHook }) },
                @{ matcher = "keep"; hooks = @(@{ type = "command"; command = "keep hook" }) }
            )
        }
    } | ConvertTo-Json -Depth 10
    Set-RtkTestFile -Path (Join-Path $geminiDir "settings.json") -Content $geminiSettings

    Set-RtkTestPiFile -Path (Join-Path $env:USERPROFILE ".pi\agent\AGENTS.md")
    Set-RtkTestPiFile -Path (Join-Path $env:PI_CODING_AGENT_DIR "AGENTS.md")
    $projectFilter = Join-Path $rtkTestRoot "project\.rtk\filters.toml"
    Set-RtkTestFile -Path $projectFilter -Content "keep"

    $env:PATH = "$rtkDir;$env:PATH"
    [Environment]::SetEnvironmentVariable("PATH", "$rtkDir;$originalRtkUserPath", "User")

    Remove-RtkResources
    Remove-RtkResources

    $removedRtkPaths = @(
        $managedRtkBinary,
        (Join-Path $env:APPDATA "rtk"),
        (Join-Path $defaultClaude "RTK.md"),
        (Join-Path $env:CLAUDE_CONFIG_DIR "RTK.md"),
        (Join-Path $defaultCodex "RTK.md"),
        (Join-Path $env:CODEX_HOME "RTK.md"),
        (Join-Path $geminiDir "GEMINI.md"),
        $geminiHook
    )
    foreach ($path in $removedRtkPaths) {
        if (Test-RtkPathExists -Path $path) {
            throw "Retired RTK cleanup left $path"
        }
    }

    $cleanClaudeSettings = Get-Content -Raw (Join-Path $defaultClaude "settings.json") | ConvertFrom-Json
    if ($cleanClaudeSettings.model -ne "keep" -or @($cleanClaudeSettings.hooks.PreToolUse).Count -ne 1 -or $cleanClaudeSettings.hooks.PreToolUse.matcher -ne "Keep") {
        throw "Retired RTK cleanup damaged unrelated Claude settings"
    }
    $cleanGeminiSettings = Get-Content -Raw (Join-Path $geminiDir "settings.json") | ConvertFrom-Json
    if ($cleanGeminiSettings.theme -ne "keep" -or @($cleanGeminiSettings.hooks.BeforeTool).Count -ne 1 -or $cleanGeminiSettings.hooks.BeforeTool.matcher -ne "keep") {
        throw "Retired RTK cleanup damaged unrelated Gemini settings"
    }
    foreach ($piFile in @((Join-Path $env:USERPROFILE ".pi\agent\AGENTS.md"), (Join-Path $env:PI_CODING_AGENT_DIR "AGENTS.md"))) {
        $piContent = Get-Content -Raw $piFile
        if ($piContent -match "RTK|Rust Token Killer" -or $piContent -notmatch "Keep this") {
            throw "Retired RTK cleanup damaged shared Pi instructions: $piFile"
        }
    }
    if (-not (Test-Path -LiteralPath $projectFilter -PathType Leaf)) {
        throw "Retired RTK cleanup removed a project-local filter"
    }
    if (-not (Test-Path -LiteralPath $rtkSymlinkSentinel -PathType Leaf)) {
        throw "Retired RTK cleanup followed a symlink target"
    }
    if ((Get-Content -Raw (Join-Path $env:USERPROFILE ".env.local")) -notmatch "BAN_RTK=1") {
        throw "Retired RTK cleanup changed the user environment file"
    }
    if (($env:PATH -split ";") -contains $rtkDir) {
        throw "Retired RTK cleanup left the process PATH entry"
    }
    if (([Environment]::GetEnvironmentVariable("PATH", "User") -split ";") -contains $rtkDir) {
        throw "Retired RTK cleanup left the user PATH entry"
    }
}
finally {
    $env:USERPROFILE = $originalRtkUserProfile
    $env:LOCALAPPDATA = $originalRtkLocalAppData
    $env:APPDATA = $originalRtkAppData
    $env:CLAUDE_CONFIG_DIR = $originalRtkClaudeConfigDir
    $env:CODEX_HOME = $originalRtkCodexHome
    $env:PI_CODING_AGENT_DIR = $originalRtkPiCodingAgentDir
    $env:PATH = $originalRtkProcessPath
    [Environment]::SetEnvironmentVariable("PATH", $originalRtkUserPath, "User")
    Remove-Item -Recurse -Force $rtkTestRoot -ErrorAction SilentlyContinue
}

# Mixed Gemini instructions stop cleanup and retain the shared file.
$mixedRtkUserProfile = $env:USERPROFILE
$mixedRtkLocalAppData = $env:LOCALAPPDATA
$mixedRtkAppData = $env:APPDATA
$mixedRtkRoot = Join-Path ([System.IO.Path]::GetTempPath()) "rtk-mixed-$([guid]::NewGuid())"
$env:USERPROFILE = Join-Path $mixedRtkRoot "home"
$env:LOCALAPPDATA = Join-Path $mixedRtkRoot "local-app-data"
$env:APPDATA = Join-Path $mixedRtkRoot "app-data"
$mixedGeminiFile = Join-Path $env:USERPROFILE ".gemini\GEMINI.md"
try {
    Set-RtkTestFile -Path $mixedGeminiFile -Content "# RTK - Rust Token Killer`n`n## Personal instructions`n`nKeep this user text.`n"
    $mixedFailure = $null
    try {
        Remove-RtkResources
    }
    catch {
        $mixedFailure = $_
    }
    if ($null -eq $mixedFailure -or $mixedFailure.Exception.Message -notmatch "mixed user and RTK content") {
        throw "Retired RTK cleanup accepted mixed Gemini instructions"
    }
    if ((Get-Content -Raw $mixedGeminiFile) -notmatch "Keep this user text") {
        throw "Retired RTK cleanup deleted mixed Gemini instructions"
    }
}
finally {
    $env:USERPROFILE = $mixedRtkUserProfile
    $env:LOCALAPPDATA = $mixedRtkLocalAppData
    $env:APPDATA = $mixedRtkAppData
    Remove-Item -Recurse -Force $mixedRtkRoot -ErrorAction SilentlyContinue
}

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

# Required managed agent skills update on every run, use the canonical shared
# path, honor custom harness locations, and reject incomplete or linked copies.
$originalManagedSkillWorkMachine = $env:WORK_MACHINE
$originalManagedSkillXdgStateHome = $env:XDG_STATE_HOME
$originalManagedSkillUserProfile = $env:USERPROFILE
$originalClaudeConfigDir = $env:CLAUDE_CONFIG_DIR
$originalCodexHome = $env:CODEX_HOME
$originalPiCodingAgentDir = $env:PI_CODING_AGENT_DIR
$managedSkillTestRoot = Join-Path ([System.IO.Path]::GetTempPath()) "managed-skills-$([guid]::NewGuid())"
$env:USERPROFILE = Join-Path $managedSkillTestRoot "home"
$env:XDG_STATE_HOME = Join-Path $managedSkillTestRoot "state"
$env:CLAUDE_CONFIG_DIR = Join-Path $managedSkillTestRoot "claude-home"
$env:CODEX_HOME = Join-Path $managedSkillTestRoot "codex-home"
$env:PI_CODING_AGENT_DIR = Join-Path $managedSkillTestRoot "custom-pi"
$script:ManagedSkillCalls = [System.Collections.Generic.List[string]]::new()

# Inert generic skill fixture retains five-file validation and new-name ownership coverage.
function Install-CopyFixtureSkill {
    return (Install-ManagedAgentSkill -Repository "example/fixture" -SkillName "tdd" -DisplayName "Copy fixture")
}
function Install-ReferenceFixtureSkill {
    return (Install-ManagedAgentSkill -Repository "example/fixture" -SkillName "code-review" -DisplayName "Reference fixture" -AdditionalFiles @(
        "LICENSE", "references/graph-document.md", "references/config.md", "references/example.graph.json"
    ))
}
function global:Enable-SkillsCliNodeRuntime { return $true }
function global:npx {
    param([Parameter(ValueFromRemainingArguments = $true)][object[]]$Arguments)

    $script:ManagedSkillCalls.Add(($Arguments -join " "))
    $skillIndex = [Array]::IndexOf($Arguments, "--skill")
    $skillName = [string]$Arguments[$skillIndex + 1]
    $skillDirs = @(
        (Join-Path $env:CLAUDE_CONFIG_DIR "skills\$skillName"),
        (Join-Path $env:USERPROFILE ".agents\skills\$skillName")
    )
    $requiredFiles = @("SKILL.md")
    if ($skillName -eq "code-review") {
        $requiredFiles += @("LICENSE", "references/graph-document.md", "references/config.md", "references/example.graph.json")
    }
    foreach ($skillDir in $skillDirs) {
        foreach ($relativeFile in $requiredFiles) {
            $skillFile = Join-Path $skillDir $relativeFile
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $skillFile) | Out-Null
            Set-Content -LiteralPath $skillFile -Value "mock $skillName $relativeFile"
        }
    }
    $global:LASTEXITCODE = 0
    Write-Output "mock install complete"
}

try {
    $siblingSkill = Join-Path $env:PI_CODING_AGENT_DIR "skills\keep-me\SKILL.md"
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $siblingSkill) | Out-Null
    Set-Content -LiteralPath $siblingSkill -Value "keep"

    foreach ($workMachine in @("0", "1")) {
        $env:WORK_MACHINE = $workMachine
        if (-not (Install-CopyFixtureSkill) -or
            -not (Install-ReferenceFixtureSkill) -or -not (Install-ReferenceFixtureSkill)) {
            throw "Required managed skill mocked installation failed"
        }
    }

    $expectedCopyFixtureArguments = "--yes skills@latest add example/fixture --global --agent claude-code --agent codex --agent gemini-cli --skill tdd --copy --yes"
    if (@($script:ManagedSkillCalls | Where-Object { $_ -eq $expectedCopyFixtureArguments }).Count -ne 2) {
        throw "tdd installer did not update twice with the exact targets: $($script:ManagedSkillCalls -join '; ')"
    }
    $expectedReferenceFixtureArguments = "--yes skills@latest add example/fixture --global --agent claude-code --agent codex --agent gemini-cli --skill code-review --copy --yes"
    if (@($script:ManagedSkillCalls | Where-Object { $_ -eq $expectedReferenceFixtureArguments }).Count -ne 4) {
        throw "Reference fixture did not update twice on personal and work machines with the exact targets"
    }
    if ($script:ManagedSkillCalls.Count -ne 6) {
        throw "Managed skill installer made unexpected calls: $($script:ManagedSkillCalls -join '; ')"
    }

    foreach ($skillName in @("tdd", "code-review")) {
        $installedSkillFiles = @(
            (Join-Path $env:CLAUDE_CONFIG_DIR "skills\$skillName\SKILL.md"),
            (Join-Path $env:USERPROFILE ".agents\skills\$skillName\SKILL.md")
        )
        foreach ($skillFile in $installedSkillFiles) {
            if (-not (Test-Path -LiteralPath $skillFile -PathType Leaf)) {
                throw "Managed skill validation missed $skillFile"
            }
        }
        if (Test-Path -LiteralPath (Join-Path $env:CODEX_HOME "skills\$skillName")) {
            throw "Managed skill installer used CODEX_HOME instead of the canonical shared path"
        }
        if (Test-Path -LiteralPath (Join-Path $env:PI_CODING_AGENT_DIR "skills\$skillName")) {
            throw "Managed skill installer created a redundant direct Pi copy"
        }
    }
    if (-not (Test-Path -LiteralPath $siblingSkill -PathType Leaf)) {
        throw "Managed skill setup removed a custom Pi sibling"
    }

    $canonicalCopyFixture = Join-Path $env:USERPROFILE ".agents\skills\tdd"
    $defaultPiCopyFixture = Join-Path $env:USERPROFILE ".pi\agent\skills\tdd"
    $customPiCopyFixture = Join-Path $env:PI_CODING_AGENT_DIR "skills\tdd"
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $defaultPiCopyFixture) | Out-Null
    Copy-Item -LiteralPath $canonicalCopyFixture -Destination $defaultPiCopyFixture -Recurse
    New-Item -ItemType Directory -Force -Path $customPiCopyFixture | Out-Null
    Set-Content -LiteralPath (Join-Path $customPiCopyFixture "SKILL.md") -Value "user-modified"
    if (-not (Set-PiSkillOwnership) -or -not (Set-PiSkillOwnership)) {
        throw "Pi managed skill ownership setup failed"
    }
    if (Test-Path -LiteralPath $defaultPiCopyFixture) {
        throw "Pi ownership left an identical direct tdd duplicate"
    }
    if ((Get-Content -LiteralPath (Join-Path $customPiCopyFixture "SKILL.md") -Raw).Trim() -ne "user-modified") {
        throw "Pi ownership removed or changed a user-modified tdd copy"
    }

    $canonicalReferenceFixture = Join-Path $env:USERPROFILE ".agents\skills\code-review"
    $defaultPiReferenceFixture = Join-Path $env:USERPROFILE ".pi\agent\skills\code-review"
    $customPiReferenceFixture = Join-Path $env:PI_CODING_AGENT_DIR "skills\code-review"
    Copy-Item -LiteralPath $canonicalReferenceFixture -Destination $defaultPiReferenceFixture -Recurse
    Copy-Item -LiteralPath $canonicalReferenceFixture -Destination $customPiReferenceFixture -Recurse
    Set-Content -LiteralPath (Join-Path $customPiReferenceFixture "references/config.md") -Value "user-modified reference"
    if (-not (Set-PiSkillOwnership) -or -not (Set-PiSkillOwnership)) {
        throw "Reference fixture ownership setup failed"
    }
    if (Test-Path -LiteralPath $defaultPiReferenceFixture) {
        throw "Pi ownership left an identical direct Reference fixture duplicate"
    }
    if ((Get-Content -LiteralPath (Join-Path $customPiReferenceFixture "references/config.md") -Raw).Trim() -ne "user-modified reference") {
        throw "Pi ownership removed or changed a user-modified Reference fixture reference"
    }
    $piSettings = Get-Content -LiteralPath (Join-Path $env:PI_CODING_AGENT_DIR "settings.json") -Raw | ConvertFrom-Json
    foreach ($directPi in @($defaultPiReferenceFixture, $customPiReferenceFixture)) {
        if (@($piSettings.skills | Where-Object { $_ -eq "!$directPi/**" }).Count -ne 1) {
            throw "Reference fixture direct-copy exclusion missing or repeated: $directPi"
        }
    }
    if ($piSettings.skills -contains "!$canonicalReferenceFixture/**" -or -not (Test-Path -LiteralPath $canonicalReferenceFixture)) {
        throw "Pi ownership removed or excluded canonical Reference fixture"
    }

    function global:npx {
        $global:LASTEXITCODE = 1
        Write-Output "simulated install failure"
    }
    if (Install-ReferenceFixtureSkill) {
        throw "Reference fixture installer failure was not propagated"
    }
    if (Install-CopyFixtureSkill) {
        throw "tdd installer failure was not propagated"
    }

    $copyFixturePaths = @((Join-Path $env:CLAUDE_CONFIG_DIR "skills\tdd"), $canonicalCopyFixture)
    Remove-Item -LiteralPath $copyFixturePaths -Recurse -Force
    function global:npx { $global:LASTEXITCODE = 0 }
    if (Install-CopyFixtureSkill) {
        throw "tdd missing-artifact failure was not propagated"
    }

    $linkTarget = Join-Path $managedSkillTestRoot "tdd-link-target"
    $claudeSkillsDir = Join-Path $env:CLAUDE_CONFIG_DIR "skills"
    New-Item -ItemType Directory -Force -Path $linkTarget, $claudeSkillsDir, $canonicalCopyFixture | Out-Null
    Set-Content -LiteralPath (Join-Path $linkTarget "SKILL.md") -Value "tdd"
    Set-Content -LiteralPath (Join-Path $canonicalCopyFixture "SKILL.md") -Value "tdd"
    $claudeCopyFixture = Join-Path $claudeSkillsDir "tdd"
    try {
        New-Item -ItemType SymbolicLink -Path $claudeCopyFixture -Target $linkTarget -ErrorAction Stop | Out-Null
    }
    catch {
        New-Item -ItemType Junction -Path $claudeCopyFixture -Target $linkTarget -ErrorAction Stop | Out-Null
    }
    if (Install-CopyFixtureSkill) {
        throw "tdd symlink validation failure was not propagated"
    }

    # Every required file, in both copies, must be regular, nonempty, and unlinked.
    # Fixtures are inert text. Neither the real skills CLI nor Reference fixture runs here.
    $referenceFixtureFiles = @("SKILL.md", "LICENSE", "references/graph-document.md", "references/config.md", "references/example.graph.json")
    $referenceFixtureFixture = Join-Path $managedSkillTestRoot "code-review-fixture"
    foreach ($relativeFile in $referenceFixtureFiles) {
        $fixtureFile = Join-Path $referenceFixtureFixture $relativeFile
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $fixtureFile) | Out-Null
        Set-Content -LiteralPath $fixtureFile -Value "fixture $relativeFile"
    }
    function Reset-ReferenceFixtureCopies {
        foreach ($dir in $referenceFixtureDirs) {
            Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dir) | Out-Null
            Copy-Item -LiteralPath $referenceFixtureFixture -Destination $dir -Recurse
        }
    }
    function Assert-ReferenceFixtureValidationFailure([string]$Artifact) {
        $script:Messages.Clear()
        if (Install-ReferenceFixtureSkill) { throw "Accepted invalid Reference fixture artifact: $Artifact" }
        if (-not ($script:Messages | Where-Object { $_ -like "WARNING: Reference fixture validation failed:*" })) {
            throw "Missing Reference fixture validation warning: $Artifact"
        }
    }
    foreach ($claudeMode in @("custom", "default")) {
        if ($claudeMode -eq "default") { $env:CLAUDE_CONFIG_DIR = $null }
        $claudeDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $env:USERPROFILE ".claude" }
        $referenceFixtureDirs = @((Join-Path $claudeDir "skills\code-review"), $canonicalReferenceFixture)
        Reset-ReferenceFixtureCopies
        if (-not (Install-ReferenceFixtureSkill)) { throw "Reference fixture complete fixture failed: $claudeMode" }
        foreach ($dir in $referenceFixtureDirs) {
            foreach ($relativeFile in $referenceFixtureFiles) {
                $artifact = Join-Path $dir $relativeFile
                if ((Get-FileHash -LiteralPath $artifact).Hash -ne (Get-FileHash -LiteralPath (Join-Path $referenceFixtureFixture $relativeFile)).Hash) {
                    throw "Reference fixture changed upstream fixture content: $artifact"
                }
                foreach ($defect in @("missing", "empty", "directory", "symlink", "dangling")) {
                    Reset-ReferenceFixtureCopies
                    Remove-Item -LiteralPath $artifact -Force
                    switch ($defect) {
                        "empty" { [System.IO.File]::WriteAllText($artifact, "") }
                        "directory" { New-Item -ItemType Directory -Path $artifact | Out-Null }
                        "symlink" {
                            New-Item -ItemType SymbolicLink -Path $artifact -Target (Join-Path $referenceFixtureFixture $relativeFile) -ErrorAction Stop | Out-Null
                        }
                        "dangling" {
                            New-Item -ItemType SymbolicLink -Path $artifact -Target (Join-Path $referenceFixtureFixture "not-present") -ErrorAction Stop | Out-Null
                        }
                    }
                    Assert-ReferenceFixtureValidationFailure "$artifact ($defect)"
                }
                Reset-ReferenceFixtureCopies
            }
            foreach ($relativeDir in @(".", "references")) {
                foreach ($linkType in @("SymbolicLink", "Junction")) {
                    if ($linkType -eq "Junction" -and [Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { continue }
                    Reset-ReferenceFixtureCopies
                    $artifact = if ($relativeDir -eq ".") { $dir } else { Join-Path $dir $relativeDir }
                    $target = if ($relativeDir -eq ".") { $referenceFixtureFixture } else { Join-Path $referenceFixtureFixture $relativeDir }
                    Remove-Item -LiteralPath $artifact -Recurse -Force
                    New-Item -ItemType $linkType -Path $artifact -Target $target -ErrorAction Stop | Out-Null
                    Assert-ReferenceFixtureValidationFailure "$artifact ($linkType directory)"
                }
            }
            Reset-ReferenceFixtureCopies
        }
    }

    $script:ManagedSkillRuntimeNpxCalled = $false
    function global:Enable-SkillsCliNodeRuntime { return $false }
    function global:npx { $script:ManagedSkillRuntimeNpxCalled = $true; $global:LASTEXITCODE = 0 }
    if ((Install-CopyFixtureSkill) -or (Install-ReferenceFixtureSkill) -or $script:ManagedSkillRuntimeNpxCalled) {
        throw "Managed skill runtime failure was not propagated before installer execution"
    }

    function global:Enable-SkillsCliNodeRuntime { return $true }
    Remove-Item Function:\npx -ErrorAction SilentlyContinue
    $managedSkillPath = $env:PATH
    $env:PATH = Join-Path $managedSkillTestRoot "empty-path"
    try {
        if ((Install-CopyFixtureSkill) -or (Install-ReferenceFixtureSkill)) {
            throw "Managed skill accepted an unavailable skills installer"
        }
    }
    finally {
        $env:PATH = $managedSkillPath
    }
}
finally {
    $env:WORK_MACHINE = $originalManagedSkillWorkMachine
    $env:XDG_STATE_HOME = $originalManagedSkillXdgStateHome
    $env:USERPROFILE = $originalManagedSkillUserProfile
    $env:CLAUDE_CONFIG_DIR = $originalClaudeConfigDir
    $env:CODEX_HOME = $originalCodexHome
    $env:PI_CODING_AGENT_DIR = $originalPiCodingAgentDir
    Remove-Item -Recurse -Force $managedSkillTestRoot -ErrorAction SilentlyContinue
}

# Full-suite, opt-out, and retirement Windows wrappers are exercised by
# test_managed_skill_suite.py with PWSH_BIN, including the real embedded policy.

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

# Run the standalone logging fixture too. It extracts production functions and
# exercises real multipart construction rather than a PowerShell-7-only -Form mock.
# Its separate contract wrapper runs even when an earlier fixture here fails.
& (Join-Path $PSScriptRoot 'windows-log-upload-powershell.ps1')

Write-Output "✓ PowerShell setup reliability checks passed"
