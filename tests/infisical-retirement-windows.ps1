# Run the extracted native-record fixtures, then actual Windows caller/log seams.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'infisical-retirement-native-windows.ps1')
$callerSource = [regex]::Match($source, '(?s)function Invoke-WindowsSetupTasks \{(.*?)\n\}\s*\n# Main setup function')
$initializer = [regex]::Match($source, '(?s)function Initialize-WindowsEnvironment \{.*?\n\}\s*\n# Run the main setup function')
if (-not $callerSource.Success -or -not $initializer.Success) { throw 'Windows caller boundary missing' }
$body = $callerSource.Groups[1].Value
$entry = $body.Substring(0, $body.IndexOf('    Install-GcloudCli') + '    Install-GcloudCli'.Length)
$tail = $body.Substring($body.IndexOf('    Write-Section "System Updates"'))
$caller = "function Invoke-WindowsSetupTasks {`n$entry`nWrite-Host 'unrelated-stage'`n$tail`n}"
. ([scriptblock]::Create($caller))
. ([scriptblock]::Create($initializer.Value.Substring(0, $initializer.Value.LastIndexOf('# Run the main setup function'))))
function Get-SetupLogDirectory { [IO.Path]::GetTempPath() }
function Assert-SetupLogPath { param($Path, [switch]$AllowMissing) }
function New-Item { param($ItemType, [switch]$Force, $Path, $ErrorAction) }
function Invoke-PendingSetupLogUploads { }
function Start-Transcript { param($Path, [switch]$NoClobber, $ErrorAction) }
function Complete-SetupLog { Write-Host 'log-finalized' }
function Assert-HeadlessPaseoUnsupported { }
function Get-PaseoReleaseChannel { 'beta' }
function New-TokenPlaceholders { }
# Desktop setup is unrelated to this extracted retirement/logging seam.
function Install-BbDesktop { $true }
function Write-Section { param($Message) }
function Install-WingetPackages { }
$secretsManager = [regex]::Match($source, '(?s)function Install-SecretsManager \{.*?\n\}')
if (-not $secretsManager.Success) { throw 'Native secrets-manager caller missing' }
. ([scriptblock]::Create($secretsManager.Value))
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
    $output = & { try { Initialize-WindowsEnvironment } catch { Write-Host 'setup-failed' } } 6>&1 | Out-String
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
    $output = & { Initialize-WindowsEnvironment } 6>&1 | Out-String
    if ($output -notmatch 'unrelated-stage' -or $output -notmatch 'log-finalized' -or $output -match 'setup-failed' -or
        $output -notmatch 'winget-updates' -or $script:calls.Count -gt 1) {
        throw 'Verified absent Windows run failed'
    }
}
Write-Host 'Windows native retirement and caller boundaries passed (native Windows validation pending)'
