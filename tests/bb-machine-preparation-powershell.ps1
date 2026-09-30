$ErrorActionPreference = 'Stop'
# Parse the real runner, replacing every referenced setup command with an inert
# function. Never dot-source win.ps1 or provision/install anything on the host.
$source = Get-Content (Join-Path $PSScriptRoot '../win.ps1') -Raw
$tokens = $null; $errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'Windows setup syntax failed' }
$runner = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Invoke-WindowsSetupTasks' }, $true)[0]
$gate = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Assert-HeadlessUnsupported' }, $true)[0]
$commands = $runner.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true) | ForEach-Object { $_.GetCommandName() } | Sort-Object -Unique
$stubs = @()
foreach ($command in $commands) {
    if ($command -like 'Write-*') { continue }
    if ($command -match '^bb' -or $command -eq 'wsl' -or $command -eq 'npm') { throw 'Unexpected native BB operation' }
    $stubs += "function $command { return `$true }"
}
$code = '$ErrorActionPreference = "Stop"' + "`n" + ($stubs -join "`n") + "`n" + $runner.Extent.Text + "`n" + $gate.Extent.Text + @'
function Write-Message { param($Message) $script:Messages += $Message }
function Write-Host { }
function Write-Section { }
function Write-Debug { }
function Write-Warning { }
function Write-Error { }
function Test-EnvLocalFlag { param($Name) return [Environment]::GetEnvironmentVariable($Name) -eq '1' }
$script:Messages = @()
$env:HEADLESS = '0'
$null = Invoke-WindowsSetupTasks
if (-not ($script:Messages -match 'BB does not support native Windows.*WSL2.*manually enroll')) { throw 'Missing manual WSL2 guidance' }
$env:HEADLESS = '1'
$script:Messages = @()
$blocked = $false
try { $null = Invoke-WindowsSetupTasks } catch { $blocked = $true }
if (-not $blocked -or $script:Messages.Count) { throw 'HEADLESS rejection must precede BB guidance' }
exit 0
'@
# Isolated child process: avoid changing the caller's environment/functions.
& (Get-Process -Id $PID).Path -NoProfile -Command $code
if ($LASTEXITCODE -ne 0) { throw 'BB Windows guidance fixture failed' }
Write-Output 'BB Windows guidance and early HEADLESS gate passed (no native install).'
