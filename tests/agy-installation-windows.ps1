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
foreach ($name in 'Install-AgyCli', 'Invoke-ClaudeCodeCommandSafely', 'Format-ClaudeCodeArgument', 'Get-ClaudeCodePowerShellHost', 'Test-ClaudeCodeSamePath', 'Invoke-WindowsSetupTasks') {
    if (-not $definitions.ContainsKey($name)) { throw "win.ps1 does not define $name" }
}

$loaded = ($definitions['Install-AgyCli'], $definitions['Invoke-ClaudeCodeCommandSafely'], $definitions['Format-ClaudeCodeArgument'],
    $definitions['Get-ClaudeCodePowerShellHost'], $definitions['Test-ClaudeCodeSamePath']) -join "`n"
. ([scriptblock]::Create($loaded))

function Test-ClaudeCodeTrustedPowerShellHost { param([string]$Path) return $true }
function Write-Message { param($Message) $script:Log += "MESSAGE: $Message" }
function Write-Success { param($Message) $script:Log += "SUCCESS: $Message" }
function Write-Warning { param($Message) $script:Log += "WARNING: $Message" }
function Write-Debug { param($Message) $script:Log += "DEBUG: $Message" }
function Write-Host { param([Parameter(ValueFromRemainingArguments = $true)]$Rest) $script:Log += "HOST: $($Rest -join ' ')" }
function Invoke-WebRequest {
    param($Uri, $OutFile, [switch]$UseBasicParsing, $TimeoutSec, $ErrorAction)
    $script:Downloads += $Uri
    if ($script:DownloadFails) { throw 'download failed' }
    $exeBody = "#!/bin/sh`necho 1.5.14"
    if ($script:InstallerMode -eq 'broken') { $exeBody = "#!/bin/sh`necho agy: probe failure >&2`nexit 17" }
    $body = @"
`$argLog = Join-Path `$env:LOCALAPPDATA 'installer-args.txt'
Add-Content -LiteralPath `$argLog -Value (`$args -join ' ')
if ('$($script:InstallerMode)' -eq 'fail') { Write-Output 'installer exploded'; exit 3 }
if ('$($script:InstallerMode)' -eq 'missing') { exit 0 }
`$dir = Join-Path (Join-Path `$env:LOCALAPPDATA 'agy') 'bin'
New-Item -ItemType Directory -Force -Path `$dir | Out-Null
`$exe = Join-Path `$dir 'agy.exe'
Set-Content -LiteralPath `$exe -Value "$exeBody"
& /bin/chmod 755 `$exe
"@
    Set-Content -LiteralPath $OutFile -Value $body
}

$savedEnvironment = @{}
foreach ($name in 'LOCALAPPDATA', 'PATH', 'PROCESSOR_ARCHITECTURE', 'PROCESSOR_ARCHITEW6432') {
    $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}
$testRoot = Join-Path ([IO.Path]::GetTempPath()) "agy fixture $([guid]::NewGuid())"
New-Item -ItemType Directory -Path $testRoot | Out-Null

function Invoke-Case {
    param([string]$Mode = 'working', [string]$Architecture = 'AMD64', [string]$Wow64Architecture = $null,
          [switch]$Existing, [switch]$DownloadFails, [string]$ExistingBody = "#!/bin/sh`necho 1.5.14")
    $script:Log = @()
    $script:Downloads = @()
    $script:InstallerMode = $Mode
    $script:DownloadFails = [bool]$DownloadFails
    $caseRoot = Join-Path $testRoot ([guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $caseRoot | Out-Null
    $env:LOCALAPPDATA = $caseRoot
    $env:PROCESSOR_ARCHITECTURE = $Architecture
    $env:PROCESSOR_ARCHITEW6432 = $Wow64Architecture
    $env:PATH = $savedEnvironment['PATH']
    $exe = Join-Path (Join-Path (Join-Path $caseRoot 'agy') 'bin') 'agy.exe'
    if ($Existing) {
        New-Item -ItemType Directory -Force -Path (Split-Path $exe -Parent) | Out-Null
        Set-Content -LiteralPath $exe -Value $ExistingBody
        & /bin/chmod 755 $exe
    }
    $result = @(Install-AgyCli)
    return [pscustomobject]@{
        Results = $result
        Log = ($script:Log -join "`n")
        Downloads = $script:Downloads.Count
        Exe = $exe
        Root = $caseRoot
        ProcessPath = $env:PATH
    }
}

function Assert-That {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAILED: $Message" }
}

try {
    $case = Invoke-Case
    Assert-That ($case.Results.Count -eq 1 -and $case.Results[0] -eq $true) "fresh install must return exactly `$true: $($case.Results -join ',')`n$($case.Log)"
    Assert-That ($case.Downloads -eq 1) 'fresh install downloads the installer once'
    Assert-That (Test-Path $case.Exe) 'fresh install creates agy.exe'
    $installerArgs = (Get-Content -LiteralPath (Join-Path $case.Root 'installer-args.txt') -Raw).Trim()
    Assert-That ($installerArgs -eq '--skip-path --skip-aliases') "installer must get --skip-path --skip-aliases, got '$installerArgs'"
    Assert-That ($case.Log -match 'SUCCESS: Antigravity CLI ready \(1\.5\.14\)\.') "success line names the version`n$($case.Log)"
    Assert-That ($case.Log -notmatch 'WARNING') "fresh install must not warn`n$($case.Log)"
    Assert-That ($case.ProcessPath.StartsWith((Split-Path $case.Exe -Parent) + ';')) 'install directory is prepended to the process PATH'

    $case = Invoke-Case -Existing
    Assert-That ($case.Results.Count -eq 1 -and $case.Results[0] -eq $true) "existing install must return `$true`n$($case.Log)"
    Assert-That ($case.Downloads -eq 0) 'existing agy.exe must skip the download'
    Assert-That ($case.Log -match 'DEBUG: Antigravity CLI is already installed; it updates itself\.') 'existing install says it updates itself'
    Assert-That ($case.Log -match 'SUCCESS: Antigravity CLI ready') 'existing install is still smoke-tested'

    $case = Invoke-Case -Mode fail
    Assert-That ($case.Results.Count -eq 1 -and $case.Results[0] -eq $false) "installer exit 3 must return `$false`n$($case.Log)"
    Assert-That ($case.Log -match 'WARNING: Antigravity CLI installer failed with exit code 3\.') "warning names exit code 3`n$($case.Log)"
    Assert-That ($case.Log -match 'installer exploded') 'failed installer output is shown'
    Assert-That (-not (Test-Path $case.Exe)) 'failed installer leaves no agy.exe'

    $case = Invoke-Case -Mode missing
    Assert-That ($case.Results.Count -eq 1 -and $case.Results[0] -eq $false) "installer without agy.exe must return `$false`n$($case.Log)"
    Assert-That ($case.Log -match 'installer completed, but .* is missing\.') "missing exe warning`n$($case.Log)"

    $case = Invoke-Case -DownloadFails
    Assert-That ($case.Results.Count -eq 1 -and $case.Results[0] -eq $false) 'failed download must return $false'
    Assert-That ($case.Log -match 'WARNING: Failed to download the Antigravity CLI installer\.') 'download failure warning'

    $case = Invoke-Case -Architecture x86
    Assert-That ($case.Results.Count -eq 1 -and $case.Results[0] -eq $true) "x86 must warn and return `$true`n$($case.Log)"
    Assert-That ($case.Downloads -eq 0) 'x86 must not download anything'
    Assert-That ($case.Log -match 'WARNING: Antigravity CLI has no Windows x86 build; skipping\.') "x86 warning`n$($case.Log)"
    Assert-That (-not (Test-Path $case.Exe)) 'x86 installs nothing'

    $case = Invoke-Case -Architecture x86 -Wow64Architecture ARM64
    Assert-That ($case.Results.Count -eq 1 -and $case.Results[0] -eq $true -and $case.Downloads -eq 1) 'a 32-bit process on ARM64 installs through PROCESSOR_ARCHITEW6432'

    $case = Invoke-Case -Existing -ExistingBody "#!/bin/sh`necho agy: probe failure >&2`nexit 17"
    Assert-That ($case.Results.Count -eq 1 -and $case.Results[0] -eq $false) "broken agy.exe must return `$false`n$($case.Log)"
    Assert-That ($case.Log -match 'WARNING: Antigravity CLI smoke test failed \(exit code 17\)\.') "smoke warning names exit code 17`n$($case.Log)"

    $case = Invoke-Case -Mode broken
    Assert-That ($case.Results.Count -eq 1 -and $case.Results[0] -eq $false) 'a freshly installed broken agy.exe must return $false'

    $runner = $definitions['Invoke-WindowsSetupTasks']
    Assert-That ($runner -match '(?m)^\s*\$agySetupFailed = \$false\s*$') 'caller initializes $agySetupFailed'
    Assert-That ($runner -match '(?m)^\s*Install-GeminiCli\s*\r?\n\s*if \(-not \(Install-AgyCli\)\) \{ \$agySetupFailed = \$true \}\s*$') 'caller runs Install-AgyCli right after Install-GeminiCli and records failure'
    Assert-That ($runner -match "(?s)if \(\`$agySetupFailed\) \{\s*throw 'Antigravity CLI installation failed\.'\s*\}") 'caller throws on $agySetupFailed'
}
finally {
    foreach ($name in $savedEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], 'Process')
    }
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Output 'Antigravity CLI Windows installation fixtures passed.'
