$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $repoRoot 'win.ps1'), [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw "win.ps1 parse errors: $parseErrors" }
$definitions = @{}
foreach ($definition in $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)) {
    $definitions[$definition.Name] = $definition.Extent.Text
}
foreach ($name in 'Remove-GeminiCli', 'Invoke-WindowsSetupTasks') {
    if (-not $definitions.ContainsKey($name)) { throw "win.ps1 does not define $name" }
}
if ($definitions.ContainsKey('Install-GeminiCli')) { throw 'win.ps1 still defines Install-GeminiCli' }
. ([scriptblock]::Create($definitions['Remove-GeminiCli']))

function Write-Message { param($Message) $script:Log += "MESSAGE: $Message" }
function Write-Success { param($Message) $script:Log += "SUCCESS: $Message" }
function Write-Warning { param($Message) $script:Log += "WARNING: $Message" }
function Write-Debug { param($Message) $script:Log += "DEBUG: $Message" }

$fakeBun = Join-Path (Join-Path $PSScriptRoot 'fixtures') 'fake-bun-global.py'
$package = '@google/gemini-cli'
$savedEnvironment = @{}
foreach ($name in 'USERPROFILE', 'HOME', 'PATH', 'TEST_CAPTURE', 'TEST_LS_FAILS', 'TEST_REMOVE_FAILS', 'TEST_REMOVE_NOOP', 'TEST_LEAVE_LINK', 'TEST_BIN_FAILS') {
    $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}
$testRoot = Join-Path ([IO.Path]::GetTempPath()) "gemini retire fixture $([guid]::NewGuid())"
New-Item -ItemType Directory -Path $testRoot | Out-Null

function Assert-That {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAILED: $Message" }
}

function Write-TestFile {
    param([string]$Path, [string]$Content, [switch]$Executable)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    [IO.File]::WriteAllBytes($Path, [Text.Encoding]::UTF8.GetBytes($Content))
    if ($Executable) { & /bin/chmod 755 $Path }
}

function Install-TestPackage {
    param([string]$Account, [string]$Name, [string]$Bin, [string]$Version = '1.0.0')
    $packageDir = $Account
    foreach ($part in @('.bun', 'install', 'global', 'node_modules') + $Name.Split('/')) { $packageDir = Join-Path $packageDir $part }
    Write-TestFile (Join-Path $packageDir 'package.json') (@{ name = $Name; version = $Version; bin = @{ $Bin = 'bin.js' } } | ConvertTo-Json -Compress)
    Write-TestFile (Join-Path $packageDir 'bin.js') "#!/usr/bin/env node`n" -Executable
    $binDir = Join-Path (Join-Path $Account '.bun') 'bin'
    New-Item -ItemType Directory -Force -Path $binDir | Out-Null
    New-Bunx (Join-Path $binDir "$Bin.bunx") ('install\global\node_modules\' + $Name.Replace('/', '\') + '\bin.js')
    Write-TestFile (Join-Path $binDir "$Bin.exe") "exe $Name"
    $manifest = Join-Path (Join-Path (Join-Path (Join-Path $Account '.bun') 'install') 'global') 'package.json'
    $dependencies = [ordered]@{}
    if (Test-Path -LiteralPath $manifest) {
        foreach ($property in (Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json).dependencies.PSObject.Properties) { $dependencies[$property.Name] = $property.Value }
    }
    $dependencies[$Name] = $Version
    Write-TestFile $manifest (@{ dependencies = $dependencies } | ConvertTo-Json -Compress)
}

function Get-Snapshot {
    param([string]$Base, [string[]]$Skip = @())
    $entries = [ordered]@{}
    foreach ($item in Get-ChildItem -LiteralPath $Base -Recurse -Force | Sort-Object FullName) {
        $relative = $item.FullName.Substring($Base.Length).TrimStart([IO.Path]::DirectorySeparatorChar)
        if ($Skip -contains $relative.Split([IO.Path]::DirectorySeparatorChar)[0]) { continue }
        $content = ''
        if ($item.LinkTarget) { $content = "-> $($item.LinkTarget)" }
        elseif (-not $item.PSIsContainer) { $content = [Convert]::ToBase64String([IO.File]::ReadAllBytes($item.FullName)) }
        $entries[$relative] = "$($item.UnixFileMode)|$($item.PSIsContainer)|$content"
    }
    return ($entries.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "`n"
}

function New-Case {
    param([switch]$WithBun, [switch]$WithGemini, [switch]$WithBunOnPath)
    $caseRoot = Join-Path $testRoot ([guid]::NewGuid().ToString())
    $account = Join-Path $caseRoot 'account'
    New-Item -ItemType Directory -Path $account | Out-Null
    $empty = Join-Path $caseRoot 'empty'
    New-Item -ItemType Directory -Path $empty | Out-Null
    $bunDirectory = Join-Path (Join-Path $account '.bun') 'bin'
    $bunName = 'bun.exe'
    if ($WithBunOnPath) {
        $bunDirectory = Join-Path $caseRoot 'pathbin'
        $bunName = 'bun'
    }
    if ($WithBun -or $WithBunOnPath) {
        New-Item -ItemType Directory -Force -Path $bunDirectory | Out-Null
        Copy-Item -LiteralPath $fakeBun -Destination (Join-Path $bunDirectory $bunName)
        & /bin/chmod 755 (Join-Path $bunDirectory $bunName)
        Install-TestPackage -Account $account -Name 'keep-tool' -Bin 'keep'
        if ($WithGemini) { Install-TestPackage -Account $account -Name $package -Bin 'gemini' -Version '0.52.0' }
    }
    Write-TestFile (Join-Path $account '.gemini/antigravity-cli/state.db') 'agy state'
    Write-TestFile (Join-Path $account '.gemini/config/skills.json') '{"skills": []}'
    Write-TestFile (Join-Path $account '.gemini/AGENTS.md') '# Agents'
    Write-TestFile (Join-Path $account '.gemini/settings.json') '{"mcpServers": {}}'
    Write-TestFile (Join-Path $account '.gemini/oauth_creds.json') '{"refresh_token": "fake-secret"}'
    Write-TestFile (Join-Path $account '.gemini/gemini-credentials.json') '{"token": "fake-secret"}'
    Write-TestFile (Join-Path $account '.gemini/skills/pr/SKILL.md') 'pr skill'
    New-Item -ItemType Directory -Path (Join-Path $account '.gemini/empty') | Out-Null
    New-Item -ItemType SymbolicLink -Path (Join-Path $account '.gemini/link') -Target 'settings.json' | Out-Null
    Write-TestFile (Join-Path $account '.agents/skills/pr/SKILL.md') 'canonical pr skill'
    Write-TestFile (Join-Path $account '.local/bin/agy') "#!/bin/sh`necho 1.5.14" -Executable
    return [pscustomobject]@{ Root = $caseRoot; Account = $account; Empty = $empty; BunDirectory = $bunDirectory; Bin = (Join-Path (Join-Path $account '.bun') 'bin'); PathExtra = @() }
}

function Invoke-Case {
    param($Case, [hashtable]$Flags = @{})
    $script:Log = @()
    $env:USERPROFILE = $Case.Account
    $env:HOME = $Case.Account
    $env:TEST_CAPTURE = Join-Path $Case.Root 'capture'
    $env:PATH = (@($Case.PathExtra) + @($Case.BunDirectory, $Case.Empty) | Where-Object { $_ }) -join [IO.Path]::PathSeparator
    foreach ($name in 'TEST_LS_FAILS', 'TEST_REMOVE_FAILS', 'TEST_REMOVE_NOOP', 'TEST_LEAVE_LINK', 'TEST_BIN_FAILS') {
        [Environment]::SetEnvironmentVariable($name, $(if ($Flags.ContainsKey($name)) { '1' } else { $null }), 'Process')
    }
    $result = @(Remove-GeminiCli)
    $callsFile = "$($env:TEST_CAPTURE).calls"
    $calls = @()
    if (Test-Path -LiteralPath $callsFile) { $calls = @(Get-Content -LiteralPath $callsFile) }
    return [pscustomobject]@{ Results = $result; Log = ($script:Log -join "`n"); Calls = $calls }
}

function Test-Gone {
    param($Case)
    $globalDir = Join-Path (Join-Path $Case.Account '.bun') 'install'
    $manifest = Get-Content -LiteralPath (Join-Path (Join-Path $globalDir 'global') 'package.json') -Raw
    return (-not (Test-Path -LiteralPath (Join-Path (Join-Path (Join-Path (Join-Path $globalDir 'global') 'node_modules') '@google') 'gemini-cli'))) -and
        ($manifest -notmatch 'gemini-cli') -and
        (-not (Test-Path -LiteralPath (Join-Path $Case.Bin 'gemini.bunx'))) -and
        (-not (Test-Path -LiteralPath (Join-Path $Case.Bin 'gemini.exe')))
}

function Assert-Result {
    param($Run, [bool]$Expected, [string]$What)
    Assert-That ($Run.Results.Count -eq 1 -and $Run.Results[0] -eq $Expected) "$What must return exactly `$$Expected, got '$($Run.Results -join ',')'`n$($Run.Log)"
}

function New-Bunx {
    param([string]$Path, [string]$Target)
    [IO.File]::WriteAllBytes($Path, [Text.Encoding]::Unicode.GetBytes($Target + '"' + "`0`0`0"))
}

try {
    $case = New-Case -WithBun -WithGemini
    $before = Get-Snapshot $case.Account -Skip '.bun'
    $run = Invoke-Case $case
    Assert-Result $run $true 'removing the managed install'
    Assert-That (Test-Gone $case) "package, manifest entry and shims must be gone`n$($run.Log)"
    Assert-That (Test-Path -LiteralPath (Join-Path $case.Bin 'keep.bunx')) 'another Bun global keeps its shim'
    Assert-That (Test-Path -LiteralPath (Join-Path (Join-Path (Join-Path (Join-Path (Join-Path (Join-Path $case.Account '.bun') 'install') 'global') 'node_modules') 'keep-tool') 'bin.js')) 'another Bun global keeps its files'
    Assert-That ($run.Log -match 'SUCCESS: Gemini CLI removed\.') "success names the removal`n$($run.Log)"
    Assert-That ($run.Log -notmatch 'WARNING') "removal must not warn`n$($run.Log)"
    Assert-That ((($run.Calls | Sort-Object -Unique) -join '|') -eq 'pm bin -g|pm ls -g|remove -g @google/gemini-cli') "only listing, removal and bin lookup may reach Bun: $($run.Calls -join ';')"
    Assert-That ((Get-Snapshot $case.Account -Skip '.bun') -eq $before) '~/.gemini, ~/.agents and agy must survive byte for byte'

    Remove-Item -LiteralPath "$($env:TEST_CAPTURE).calls", "$($env:TEST_CAPTURE).removed" -Force
    $whole = Get-Snapshot $case.Account
    $run = Invoke-Case $case
    Assert-Result $run $true 'the second run'
    Assert-That (-not ($run.Calls -match '^remove')) "second run must not call remove: $($run.Calls -join ';')"
    Assert-That ((Get-Snapshot $case.Account) -eq $whole) 'second run must change nothing'
    Assert-That ($run.Log -match 'DEBUG: Gemini CLI was not installed by setup\.') "second run says there was nothing to retire`n$($run.Log)"

    $case = New-Case -WithBun -WithGemini -WithBunOnPath
    $run = Invoke-Case $case
    Assert-Result $run $true 'a Bun found on PATH'
    Assert-That (Test-Gone $case) "package must be gone with Bun from PATH`n$($run.Log)"

    $case = New-Case
    $before = Get-Snapshot $case.Account
    $run = Invoke-Case $case
    Assert-Result $run $true 'no Bun at all'
    Assert-That ($run.Calls.Count -eq 0 -and (Get-Snapshot $case.Account) -eq $before) 'no Bun means no calls and no change'
    Assert-That ($run.Log -match 'DEBUG: Gemini CLI was not installed by setup\.') 'no Bun says there was nothing to retire'

    $failures = [ordered]@{
        'listing fails'        = @{ Flags = @{ TEST_LS_FAILS = 1 }; Message = 'Could not list Bun' }
        'removal fails'        = @{ Flags = @{ TEST_REMOVE_FAILS = 1 }; Message = 'remove exploded' }
        'package still listed' = @{ Flags = @{ TEST_REMOVE_NOOP = 1 }; Message = 'Could not confirm' }
        'bin directory unknown' = @{ Flags = @{ TEST_BIN_FAILS = 1 }; Message = 'global bin directory' }
    }
    foreach ($name in $failures.Keys) {
        $case = New-Case -WithBun -WithGemini
        $before = Get-Snapshot $case.Account -Skip '.bun'
        $run = Invoke-Case $case $failures[$name].Flags
        Assert-Result $run $false $name
        Assert-That ($run.Log -match [regex]::Escape($failures[$name].Message)) "$name must say '$($failures[$name].Message)'`n$($run.Log)"
        Assert-That ($run.Log -notmatch 'SUCCESS') "$name must not report success`n$($run.Log)"
        Assert-That ((Get-Snapshot $case.Account -Skip '.bun') -eq $before) "$name must leave ~/.gemini untouched"
    }

    $case = New-Case -WithBun
    New-Bunx (Join-Path $case.Bin 'gemini.bunx') 'install\global\node_modules\@google\gemini-cli\bundle\gemini.js'
    Write-TestFile (Join-Path $case.Bin 'gemini.exe') 'exe'
    $before = Get-Snapshot $case.Account -Skip '.bun'
    $run = Invoke-Case $case
    Assert-Result $run $true 'a dangling .bunx'
    Assert-That (Test-Gone $case) 'the dangling gemini.bunx and gemini.exe must be removed'
    Assert-That ($run.Log -match 'SUCCESS: Gemini CLI removed\.') 'the shim cleanup is reported'
    Assert-That (-not ($run.Calls -match '^remove')) 'a leftover shim alone must not call remove'
    Assert-That (Test-Path -LiteralPath (Join-Path $case.Bin 'keep.bunx')) 'the other Bun global keeps its shim'
    Assert-That ((Get-Snapshot $case.Account -Skip '.bun') -eq $before) '~/.gemini must survive the shim cleanup'

    $case = New-Case -WithBun
    $absolute = Join-Path (Join-Path $case.Account 'gone') 'node_modules/@google/gemini-cli/bundle/gemini.js'
    New-Bunx (Join-Path $case.Bin 'gemini.bunx') $absolute
    Write-TestFile (Join-Path $case.Bin 'gemini.exe') 'exe'
    $run = Invoke-Case $case
    Assert-Result $run $true 'a dangling .bunx with an absolute path'
    Assert-That (Test-Gone $case) 'an absolute dangling .bunx must be removed too'

    $case = New-Case -WithBun -WithGemini
    $run = Invoke-Case $case @{ TEST_LEAVE_LINK = 1 }
    Assert-Result $run $true 'shims left behind by an older Bun'
    Assert-That (Test-Gone $case) "an older Bun's leftovers must be removed after the package`n$($run.Log)"

    $case = New-Case -WithBun
    New-Bunx (Join-Path $case.Bin 'gemini.bunx') 'install\global\node_modules\@google\gemini-cli\bundle\gemini.js'
    Write-TestFile (Join-Path $case.Bin 'gemini.exe') 'exe'
    Write-TestFile (Join-Path (Join-Path (Join-Path (Join-Path (Join-Path (Join-Path (Join-Path $case.Account '.bun') 'install') 'global') 'node_modules') '@google') 'gemini-cli') 'bundle/gemini.js') 'still here'
    $before = Get-Snapshot $case.Account
    $run = Invoke-Case $case
    Assert-Result $run $true 'a .bunx whose target exists'
    Assert-That ((Get-Snapshot $case.Account) -eq $before) 'a .bunx whose target still exists must be preserved'

    $case = New-Case -WithBun
    New-Bunx (Join-Path $case.Bin 'gemini.bunx') 'somewhere\else\gemini.js'
    Write-TestFile (Join-Path $case.Bin 'gemini.exe') 'exe'
    $before = Get-Snapshot $case.Account
    $run = Invoke-Case $case
    Assert-Result $run $true 'an unrelated .bunx'
    Assert-That ((Get-Snapshot $case.Account) -eq $before) 'an unrelated dangling .bunx must be preserved'

    foreach ($managed in @($true, $false)) {
        $case = New-Case -WithBun -WithGemini:$managed
        $foreign = Join-Path (Join-Path $case.Root 'other') 'bin'
        Write-TestFile (Join-Path $foreign 'gemini') "#!/bin/sh`necho foreign" -Executable
        $foreignBefore = [IO.File]::ReadAllBytes((Join-Path $foreign 'gemini'))
        $case.PathExtra = @($foreign)
        $run = Invoke-Case $case
        Assert-Result $run $true "a foreign gemini (managed=$managed)"
        Assert-That ([Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $foreign 'gemini'))) -eq [Convert]::ToBase64String($foreignBefore)) 'the foreign gemini must be preserved byte for byte'
        Assert-That ($run.Log.Contains("WARNING: Preserving a Gemini CLI that setup did not install: $(Join-Path $foreign 'gemini').")) "the warning names the foreign gemini`n$($run.Log)"
        Assert-That (($run.Log -match 'SUCCESS: Gemini CLI removed\.') -eq $managed) "removal is reported only when setup removed something`n$($run.Log)"
    }

    $runner = $definitions['Invoke-WindowsSetupTasks']
    Assert-That ($runner -match '(?m)^\s*\$geminiRetirementFailed = \$false\s*$') 'caller initializes $geminiRetirementFailed'
    Assert-That ($runner -match '(?m)^\s*if \(-not \(Remove-GeminiCli\)\) \{ \$geminiRetirementFailed = \$true \}\s*\r?\n\s*if \(-not \(Install-AgyCli\)\)') 'caller runs Remove-GeminiCli right before Install-AgyCli and records failure'
    Assert-That ($runner -match "(?s)if \(\`$geminiRetirementFailed\) \{\s*throw 'Gemini CLI retirement failed\.'\s*\}\s*if \(\`$agySetupFailed\)") 'caller throws on $geminiRetirementFailed before the Antigravity CLI check'
    Assert-That (([regex]::Matches((Get-Content -LiteralPath (Join-Path $repoRoot 'win.ps1') -Raw), 'Remove-GeminiCli')).Count -eq 2) 'Remove-GeminiCli is defined once and called once'
}
finally {
    foreach ($name in $savedEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], 'Process')
    }
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Output 'Gemini CLI retirement Windows fixtures passed.'
