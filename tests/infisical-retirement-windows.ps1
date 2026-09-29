# Run the extracted native-record fixtures, then actual Windows caller/log seams.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'infisical-retirement-native-windows.ps1')
$tokens=$null; $parseErrors=$null
$setupAst=[System.Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$parseErrors)
if ($parseErrors.Count) { throw 'Setup source parse failed' }
$definitions=@{}
foreach ($statement in $setupAst.EndBlock.Statements) {
    if ($statement -is [System.Management.Automation.Language.FunctionDefinitionAst]) { $definitions[$statement.Name]=$statement }
}
if (-not $definitions['Invoke-WindowsSetupTasks'] -or -not $definitions['Initialize-WindowsEnvironment']) { throw 'Windows caller boundary missing' }
$body = $definitions['Invoke-WindowsSetupTasks'].Body.Extent.Text
$body = $body.Substring(1,$body.Length-2)
$entry = $body.Substring(0, $body.IndexOf('    Install-GcloudCli') + '    Install-GcloudCli'.Length)
$tail = $body.Substring($body.IndexOf('    Write-Section "System Updates"'))
$caller = "function Invoke-WindowsSetupTasks {`n$entry`nWrite-Host 'unrelated-stage'`n$tail`n}"
. ([scriptblock]::Create($caller))
. ([scriptblock]::Create($definitions['Initialize-WindowsEnvironment'].Extent.Text))
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib/setup-policy.ps1')
$env:BB_THREAD_ID=$null; $env:BB_ENVIRONMENT_ID=$null; $env:BB_TERMINAL_ID=$null
function Assert-SetupSafeDirectory { param($Path) }
function Get-SetupLogDirectory { [IO.Path]::GetTempPath() }
function Assert-SetupLogPath { param($Path, [switch]$AllowMissing) }
function New-Item { param($ItemType, [switch]$Force, $Path, $ErrorAction) }
function Invoke-PendingSetupLogUploads { }
function Start-Transcript { param($Path, [switch]$NoClobber, $ErrorAction) }
function Complete-SetupLog { Write-Host 'log-finalized' }
function Assert-HeadlessUnsupported { }
function New-TokenPlaceholders { }
# Desktop setup is outside this retirement/finalization fixture.
function Install-BbDesktop { return $true }
function Write-Section { param($Message) }
function Install-WingetPackages { }
if (-not $definitions['Install-SecretsManager']) { throw 'Native secrets-manager caller missing' }
. ([scriptblock]::Create($definitions['Install-SecretsManager'].Extent.Text))
function Test-EnvLocalFlag { param($Name) $script:workMachine }
function Install-GcloudCli { }
function Install-WingetUpdates { Write-Host 'winget-updates' }
function Install-WindowsUpdates { Write-Host 'windows-updates' }
function Test-PendingReboot { }
function Get-Command {
    param($Name, $ErrorAction)
    if ($Name -eq 'doppler') { return $null }
    Microsoft.PowerShell.Core\Get-Command -Name $Name -ErrorAction SilentlyContinue
}
foreach ($work in @($false, $true)) {
    $script:workMachine = $work
    $script:deny = $true
    $script:records.Clear()
    $output = & { try { Initialize-WindowsEnvironment -Maintenance } catch { Write-Host 'setup-failed' } } 6>&1 | Out-String
    if ($output -notmatch 'unrelated-stage' -or $output -notmatch 'log-finalized' -or
        $output -notmatch 'setup-failed' -or $output -match 'winget-updates|windows-updates') {
        throw 'Windows retirement failure did not reach log/final-result boundary'
    }
    if (($output -match 'Installing Doppler CLI') -eq $work) { throw 'Doppler classification changed' }
}
$script:deny = $false
foreach ($work in @($false, $true)) {
    $script:workMachine = $work
    $script:records.Clear(); $script:calls.Clear()
    $output = & { Initialize-WindowsEnvironment -Maintenance } 6>&1 | Out-String
    if ($output -notmatch 'unrelated-stage' -or $output -notmatch 'log-finalized' -or $output -match 'setup-failed' -or
        $output -notmatch 'winget-updates' -or $script:calls.Count -gt 1) {
        throw 'Verified absent Windows run failed'
    }
}
Write-Host 'Windows native retirement and caller boundaries passed (native Windows validation pending)'
