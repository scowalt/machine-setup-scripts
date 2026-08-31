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
$originalManagedSkillUserProfile = $env:USERPROFILE
$originalClaudeConfigDir = $env:CLAUDE_CONFIG_DIR
$originalCodexHome = $env:CODEX_HOME
$originalPiCodingAgentDir = $env:PI_CODING_AGENT_DIR
$managedSkillTestRoot = Join-Path ([System.IO.Path]::GetTempPath()) "managed-skills-$([guid]::NewGuid())"
$env:USERPROFILE = Join-Path $managedSkillTestRoot "home"
$env:CLAUDE_CONFIG_DIR = Join-Path $managedSkillTestRoot "claude-home"
$env:CODEX_HOME = Join-Path $managedSkillTestRoot "codex-home"
$env:PI_CODING_AGENT_DIR = Join-Path $managedSkillTestRoot "custom-pi"
$script:ManagedSkillCalls = [System.Collections.Generic.List[string]]::new()

function global:Enable-SkillsCliNodeRuntime { return $true }
function global:npx {
    param([Parameter(ValueFromRemainingArguments = $true)][object[]]$Arguments)

    $script:ManagedSkillCalls.Add(($Arguments -join " "))
    $skillIndex = [Array]::IndexOf($Arguments, "--skill")
    $skillName = [string]$Arguments[$skillIndex + 1]
    $skillFiles = @(
        (Join-Path $env:CLAUDE_CONFIG_DIR "skills\$skillName\SKILL.md"),
        (Join-Path $env:USERPROFILE ".agents\skills\$skillName\SKILL.md")
    )
    foreach ($skillFile in $skillFiles) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $skillFile) | Out-Null
        Set-Content -LiteralPath $skillFile -Value "---`nname: $skillName`n---"
    }
    $global:LASTEXITCODE = 0
    Write-Output "mock install complete"
}

try {
    $siblingSkill = Join-Path $env:PI_CODING_AGENT_DIR "skills\keep-me\SKILL.md"
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $siblingSkill) | Out-Null
    Set-Content -LiteralPath $siblingSkill -Value "keep"

    if (-not (Install-SimpleEnglishSkill) -or -not (Install-ShowMeSkill) -or
        -not (Install-SimpleEnglishSkill) -or -not (Install-ShowMeSkill)) {
        throw "Required managed skill mocked installation failed"
    }

    $expectedSimpleEnglishArguments = "--yes skills@latest add AminBlg/SimpleEnglish --global --agent claude-code --agent codex --agent gemini-cli --skill simple-english --copy --yes"
    $expectedShowMeArguments = "--yes skills@latest add humanlayer/skills --global --agent claude-code --agent codex --agent gemini-cli --skill show-me --copy --yes"
    if (@($script:ManagedSkillCalls | Where-Object { $_ -eq $expectedSimpleEnglishArguments }).Count -ne 2) {
        throw "Simple English installer did not update twice with the exact targets: $($script:ManagedSkillCalls -join '; ')"
    }
    if (@($script:ManagedSkillCalls | Where-Object { $_ -eq $expectedShowMeArguments }).Count -ne 2) {
        throw "show-me installer did not update twice with the exact targets: $($script:ManagedSkillCalls -join '; ')"
    }
    if ($script:ManagedSkillCalls.Count -ne 4) {
        throw "Managed skill installer made unexpected calls: $($script:ManagedSkillCalls -join '; ')"
    }

    foreach ($skillName in @("simple-english", "show-me")) {
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

    $canonicalShowMe = Join-Path $env:USERPROFILE ".agents\skills\show-me"
    $defaultPiShowMe = Join-Path $env:USERPROFILE ".pi\agent\skills\show-me"
    $customPiShowMe = Join-Path $env:PI_CODING_AGENT_DIR "skills\show-me"
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $defaultPiShowMe) | Out-Null
    Copy-Item -LiteralPath $canonicalShowMe -Destination $defaultPiShowMe -Recurse
    New-Item -ItemType Directory -Force -Path $customPiShowMe | Out-Null
    Set-Content -LiteralPath (Join-Path $customPiShowMe "SKILL.md") -Value "user-modified"
    if (-not (Set-PiSkillOwnership) -or -not (Set-PiSkillOwnership)) {
        throw "Pi managed skill ownership setup failed"
    }
    if (Test-Path -LiteralPath $defaultPiShowMe) {
        throw "Pi ownership left an identical direct show-me duplicate"
    }
    if ((Get-Content -LiteralPath (Join-Path $customPiShowMe "SKILL.md") -Raw).Trim() -ne "user-modified") {
        throw "Pi ownership removed or changed a user-modified show-me copy"
    }

    function global:npx {
        $global:LASTEXITCODE = 1
        Write-Output "simulated install failure"
    }
    if (Install-ShowMeSkill) {
        throw "show-me installer failure was not propagated"
    }

    $showMePaths = @((Join-Path $env:CLAUDE_CONFIG_DIR "skills\show-me"), $canonicalShowMe)
    Remove-Item -LiteralPath $showMePaths -Recurse -Force
    function global:npx { $global:LASTEXITCODE = 0 }
    if (Install-ShowMeSkill) {
        throw "show-me missing-artifact failure was not propagated"
    }

    $linkTarget = Join-Path $managedSkillTestRoot "show-me-link-target"
    $claudeSkillsDir = Join-Path $env:CLAUDE_CONFIG_DIR "skills"
    New-Item -ItemType Directory -Force -Path $linkTarget, $claudeSkillsDir, $canonicalShowMe | Out-Null
    Set-Content -LiteralPath (Join-Path $linkTarget "SKILL.md") -Value "show-me"
    Set-Content -LiteralPath (Join-Path $canonicalShowMe "SKILL.md") -Value "show-me"
    $claudeShowMe = Join-Path $claudeSkillsDir "show-me"
    try {
        New-Item -ItemType SymbolicLink -Path $claudeShowMe -Target $linkTarget -ErrorAction Stop | Out-Null
    }
    catch {
        New-Item -ItemType Junction -Path $claudeShowMe -Target $linkTarget -ErrorAction Stop | Out-Null
    }
    if (Install-ShowMeSkill) {
        throw "show-me symlink validation failure was not propagated"
    }

    $script:ManagedSkillRuntimeNpxCalled = $false
    function global:Enable-SkillsCliNodeRuntime { return $false }
    function global:npx { $script:ManagedSkillRuntimeNpxCalled = $true; $global:LASTEXITCODE = 0 }
    if ((Install-ShowMeSkill) -or $script:ManagedSkillRuntimeNpxCalled) {
        throw "show-me runtime failure was not propagated before installer execution"
    }

    function global:Enable-SkillsCliNodeRuntime { return $true }
    Remove-Item Function:\npx -ErrorAction SilentlyContinue
    $managedSkillPath = $env:PATH
    $env:PATH = Join-Path $managedSkillTestRoot "empty-path"
    try {
        if (Install-ShowMeSkill) {
            throw "show-me accepted an unavailable skills installer"
        }
    }
    finally {
        $env:PATH = $managedSkillPath
    }
}
finally {
    $env:USERPROFILE = $originalManagedSkillUserProfile
    $env:CLAUDE_CONFIG_DIR = $originalClaudeConfigDir
    $env:CODEX_HOME = $originalCodexHome
    $env:PI_CODING_AGENT_DIR = $originalPiCodingAgentDir
    Remove-Item -Recurse -Force $managedSkillTestRoot -ErrorAction SilentlyContinue
}

# Matt Pocock provisioning uses the canonical shared Codex/Pi path on all
# machines and does not create a custom direct Pi copy.
$originalMattUserProfile = $env:USERPROFILE
$originalMattCodexHome = $env:CODEX_HOME
$originalMattPiCodingAgentDir = $env:PI_CODING_AGENT_DIR
$originalWorkMachine = $env:WORK_MACHINE
$originalMattBan = $env:BAN_MATT_POCOCK_SKILLS
$originalMattBanAlias = $env:BAN_MATT_POCKOCK_SKILLS
$mattTestRoot = Join-Path ([System.IO.Path]::GetTempPath()) "matt-pocock-$([guid]::NewGuid())"
$env:USERPROFILE = Join-Path $mattTestRoot "home"
$env:CODEX_HOME = Join-Path $mattTestRoot "codex-home"
$env:PI_CODING_AGENT_DIR = Join-Path $mattTestRoot "custom-pi"
$env:WORK_MACHINE = "1"
$env:BAN_MATT_POCOCK_SKILLS = $null
$env:BAN_MATT_POCKOCK_SKILLS = $null
$script:MattPocockCalls = [System.Collections.Generic.List[string]]::new()
$mattSkills = @(
    "setup-matt-pocock-skills",
    "diagnosing-bugs",
    "tdd",
    "improve-codebase-architecture",
    "grill-with-docs",
    "grilling",
    "domain-modeling",
    "codebase-design"
)
$script:MattPocockTestSkills = $mattSkills
$mattManagedSkills = $mattSkills + @("diagnose", "zoom-out")
$defaultMattPiSkills = Join-Path $env:USERPROFILE ".pi\agent\skills"
$codexMattSkills = Join-Path $env:USERPROFILE ".agents\skills"
$customMattPiSkills = Join-Path $env:PI_CODING_AGENT_DIR "skills"
$mattSkillsDirs = @($defaultMattPiSkills, $codexMattSkills, $customMattPiSkills)
$mattSymlinkTarget = Join-Path $mattTestRoot "managed-target"

function global:Enable-SkillsCliNodeRuntime { return $true }
function global:npx {
    param([Parameter(ValueFromRemainingArguments = $true)][object[]]$Arguments)

    $script:MattPocockCalls.Add(($Arguments -join " "))
    $mockSkillsDirs = @(
        (Join-Path $env:USERPROFILE ".pi\agent\skills"),
        (Join-Path $env:USERPROFILE ".agents\skills")
    )
    foreach ($skillsDir in $mockSkillsDirs) {
        foreach ($skill in $script:MattPocockTestSkills) {
            $skillFile = Join-Path $skillsDir "$skill\SKILL.md"
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $skillFile) | Out-Null
            Set-Content -LiteralPath $skillFile -Value "---`nname: $skill`n---"
        }
    }
    $global:LASTEXITCODE = 0
    Write-Output "mock install complete"
}

try {
    New-Item -ItemType Directory -Force -Path $mattSymlinkTarget | Out-Null
    Set-Content -LiteralPath (Join-Path $mattSymlinkTarget "sentinel") -Value "keep"
    foreach ($skillsDir in $mattSkillsDirs) {
        $siblingSkill = Join-Path $skillsDir "keep-me\SKILL.md"
        $obsoleteSkill = Join-Path $skillsDir "diagnose\SKILL.md"
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $siblingSkill) | Out-Null
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $obsoleteSkill) | Out-Null
        Set-Content -LiteralPath $siblingSkill -Value "keep"
        Set-Content -LiteralPath $obsoleteSkill -Value "obsolete"
        try {
            New-Item -ItemType SymbolicLink -Path (Join-Path $skillsDir "zoom-out") -Target $mattSymlinkTarget -ErrorAction Stop | Out-Null
        }
        catch {
            New-Item -ItemType Directory -Force -Path (Join-Path $skillsDir "zoom-out") | Out-Null
        }
    }

    if (-not (Setup-MattPocockSkills) -or -not (Setup-MattPocockSkills)) {
        throw "Matt Pocock mocked installation failed"
    }

    $expectedMattArguments = "--yes skills@latest add mattpocock/skills --global --agent codex --copy --yes --skill setup-matt-pocock-skills --skill diagnosing-bugs --skill tdd --skill improve-codebase-architecture --skill grill-with-docs --skill grilling --skill domain-modeling --skill codebase-design"
    if ($script:MattPocockCalls.Count -ne 2 -or ($script:MattPocockCalls | Where-Object { $_ -ne $expectedMattArguments })) {
        throw "Matt Pocock installer did not update twice with the exact targets: $($script:MattPocockCalls -join '; ')"
    }
    foreach ($skillsDir in @($codexMattSkills)) {
        foreach ($skill in $mattSkills) {
            if (-not (Test-Path -LiteralPath (Join-Path $skillsDir "$skill\SKILL.md") -PathType Leaf)) {
                throw "Matt Pocock validation missed $skill in $skillsDir"
            }
        }
        if (-not (Test-Path -LiteralPath (Join-Path $skillsDir "keep-me\SKILL.md") -PathType Leaf)) {
            throw "Matt Pocock setup removed a sibling in $skillsDir"
        }
        foreach ($obsoleteSkill in @("diagnose", "zoom-out")) {
            if (Test-Path -LiteralPath (Join-Path $skillsDir $obsoleteSkill)) {
                throw "Matt Pocock setup left $obsoleteSkill in $skillsDir"
            }
        }
    }
    if (Test-Path -LiteralPath (Join-Path $env:CODEX_HOME "skills\setup-matt-pocock-skills")) {
        throw "Matt Pocock setup used CODEX_HOME instead of the canonical shared path"
    }
    if (-not (Test-Path -LiteralPath (Join-Path $mattSymlinkTarget "sentinel") -PathType Leaf)) {
        throw "Matt Pocock obsolete cleanup followed a symlink target"
    }

    foreach ($banName in @("BAN_MATT_POCOCK_SKILLS", "BAN_MATT_POCKOCK_SKILLS")) {
        foreach ($skillsDir in $mattSkillsDirs) {
            foreach ($skill in $mattManagedSkills) {
                $skillFile = Join-Path $skillsDir "$skill\SKILL.md"
                New-Item -ItemType Directory -Force -Path (Split-Path -Parent $skillFile) | Out-Null
                Set-Content -LiteralPath $skillFile -Value "managed"
            }
        }
        [Environment]::SetEnvironmentVariable($banName, "1")
        if (-not (Setup-MattPocockSkills) -or -not (Setup-MattPocockSkills)) {
            throw "$banName cleanup failed"
        }
        [Environment]::SetEnvironmentVariable($banName, $null)

        foreach ($skillsDir in $mattSkillsDirs) {
            foreach ($skill in $mattManagedSkills) {
                if (Test-Path -LiteralPath (Join-Path $skillsDir $skill)) {
                    throw "$banName left $skill in $skillsDir"
                }
            }
            if (-not (Test-Path -LiteralPath (Join-Path $skillsDir "keep-me\SKILL.md") -PathType Leaf)) {
                throw "$banName removed a sibling skill"
            }
        }
    }
    if ($script:MattPocockCalls.Count -ne 2) {
        throw "A Matt Pocock ban still ran the installer"
    }
}
finally {
    $env:USERPROFILE = $originalMattUserProfile
    $env:CODEX_HOME = $originalMattCodexHome
    $env:PI_CODING_AGENT_DIR = $originalMattPiCodingAgentDir
    $env:WORK_MACHINE = $originalWorkMachine
    $env:BAN_MATT_POCOCK_SKILLS = $originalMattBan
    $env:BAN_MATT_POCKOCK_SKILLS = $originalMattBanAlias
    Remove-Item -Recurse -Force $mattTestRoot -ErrorAction SilentlyContinue
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
