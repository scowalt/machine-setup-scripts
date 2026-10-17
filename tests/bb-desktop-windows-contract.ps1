$ErrorActionPreference = 'Stop'
$source = Join-Path $PSScriptRoot '../win.ps1'
$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($source, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'Windows setup parse failure' }
$definitions = @($ast.EndBlock.Statements | Where-Object { $_ -is [System.Management.Automation.Language.FunctionDefinitionAst] })
$required = @('Invoke-WindowsSetupTasks', 'Initialize-WindowsEnvironment', 'Assert-HeadlessUnsupported')
foreach ($name in $required) {
    $selected = @($definitions | Where-Object Name -eq $name)
    if ($selected.Count -ne 1) { throw 'Caller selection failed' }
    $part = [System.Management.Automation.Language.Parser]::ParseInput($selected[0].Extent.Text, [ref]$tokens, [ref]$errors)
    if ($errors.Count -or $part.EndBlock.Statements.Count -ne 1 -or $part.EndBlock.Statements[0] -isnot [System.Management.Automation.Language.FunctionDefinitionAst]) { throw 'Non-definition selected' }
    . ([scriptblock]::Create($selected[0].Extent.Text))
}
foreach ($definition in $definitions) {
    if ($definition.Name -in $required) { continue }
    Set-Item "function:$($definition.Name)" { return $true }
}
function Record { param($Message) Add-Content -LiteralPath $env:EVENTS -Value $Message }
function Test-EnvLocalFlag { param($Name) [Environment]::GetEnvironmentVariable($Name) -eq '1' }
function Install-BbDesktop { Record 'FORBIDDEN:desktop-installer'; throw 'Desktop installer invoked' }
function Install-OpenCodeCli { return ($env:FAILURE -ne 'independent') }
function Remove-CompoundEngineeringResources { Record 'independent-work' }
function Test-PendingReboot { Record 'reboot-reported' }
function Get-SetupLogDirectory { return $env:FIXTURE_LOG_DIR }
function Assert-SetupLogPath { param($Path, [switch]$AllowMissing) }
function Invoke-PendingSetupLogUploads { }
function Start-Transcript { param($Path, [switch]$NoClobber, $ErrorAction) Record 'logging' }
function Complete-SetupLog { Record 'finalized' }
function Write-Debug { param($Message) }
function Write-Warning { param($Message) }
function Write-Error { param($Message) }
foreach ($name in @('bb', 'winget', 'npm', 'bun', 'curl', 'Invoke-WebRequest', 'Start-Process', 'Stop-Process', 'Start-Service', 'Stop-Service')) {
    Set-Item "function:$name" { Record 'FORBIDDEN:native-operation'; throw 'Unmocked native operation' }
}
try { Initialize-WindowsEnvironment }
catch { Record 'failed'; exit 1 }
