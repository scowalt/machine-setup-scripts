# Version 1 | Extract only the approved task/logging/secrets-manager caller seam.
param([string]$SourcePath)
$ErrorActionPreference = 'Stop'
$tokens = $null; $errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($SourcePath, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'Setup parse failed' }
$definitions = @($ast.EndBlock.Statements | Where-Object { $_ -is [System.Management.Automation.Language.FunctionDefinitionAst] })
$required = @('Invoke-WindowsSetupTasks', 'Initialize-WindowsEnvironment', 'Install-SecretsManager', 'Assert-HeadlessUnsupported')
foreach ($name in $required) {
    $selected = @($definitions | Where-Object Name -eq $name)
    if ($selected.Count -ne 1) { throw 'Caller selection failed' }
    $part = [System.Management.Automation.Language.Parser]::ParseInput($selected[0].Extent.Text, [ref]$tokens, [ref]$errors)
    if ($errors.Count -or $part.EndBlock.Statements.Count -ne 1 -or $part.EndBlock.Statements[0] -isnot [System.Management.Automation.Language.FunctionDefinitionAst]) { throw 'Non-definition selected' }
    . ([scriptblock]::Create($selected[0].Extent.Text))
}
# Stub all unrelated dependencies before intentional wrapper invocation. Obsolete
# retirement calls on red source are recorded and fail, never inspect a registry.
foreach ($definition in $definitions) {
    $name = $definition.Name
    if ($name -in $required) { continue }
    $result = if ($name -match 'Infisical') { '$false' } else { '$true' }
    Set-Item "function:$name" ([scriptblock]::Create("Record 'request:$name'; return $result"))
}
function Record { param($Message) Add-Content -LiteralPath $env:EVENTS -Value $Message }
function Test-EnvLocalFlag { param($Name) [Environment]::GetEnvironmentVariable($Name) -eq '1' }
function Get-Command {
    param($Name, $ErrorAction)
    Record "command:$Name"
    if ($Name -eq 'doppler') {
        if ($env:DOPPLER_PRESENT -eq '1') { return 'fixture-doppler' }
        return
    }
    throw 'Unexpected command inventory'
}
function winget { Record "winget:$args"; $global:LASTEXITCODE = 0 }
function Install-OpenCodeCli { Record 'opencode'; return ($env:FAILURE -ne 'opencode') }
function Prepare-PiProfilePermissions { return ($env:FAILURE -ne 'permissions') }
function Install-WingetUpdates { Record 'winget-update' }
function Install-WindowsUpdates { Record 'windows-update' }
function Remove-CompoundEngineeringResources { Record 'unrelated' }
function Test-PendingReboot { Record 'pending-reboot' }
function Get-SetupLogDirectory { return $env:FIXTURE_LOG_DIR }
function Assert-SetupLogPath { param($Path, [switch]$AllowMissing) }
function Invoke-PendingSetupLogUploads { }
function Start-Transcript { param($Path, [switch]$NoClobber, $ErrorAction) Record 'log-start' }
function Complete-SetupLog { Record 'finalized' }
function Write-Debug { param($Message) }
function Write-Warning { param($Message) Record "warning:$Message" }
function Write-Error { param($Message) Record "error:$Message" }
try { Initialize-WindowsEnvironment }
catch { Record 'failed'; exit 1 }
