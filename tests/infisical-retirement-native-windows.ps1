# Offline extracted-helper fixture: in-memory native registration and inert winget.
$ErrorActionPreference = 'Stop'
$source = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../win.ps1') -Raw
$match = [regex]::Match($source, '(?s)# BEGIN INFISICAL WINGET RETIREMENT\r?\n(.*?)# END INFISICAL WINGET RETIREMENT')
if (-not $match.Success) { throw 'Missing retirement helper' }
. ([scriptblock]::Create($match.Groups[1].Value))
$script:records = @{}
$script:calls = New-Object System.Collections.ArrayList
$script:lookups = New-Object System.Collections.ArrayList
$script:sourceJson = '{"Name":"winget","Type":"Microsoft.PreIndexed.Package","Arg":"https://cdn.winget.microsoft.com/cache","Data":"Microsoft.Winget.Source_8wekyb3d8bbwe","Identifier":"Microsoft.Winget.Source_8wekyb3d8bbwe"}'
$script:sourceExit = 0
$script:uninstallExit = 0
$script:leaveRecord = $false
$script:deny = $false
function Open-InfisicalPortableRegistryKey {
    param($Hive, $View, $Path)
    [void]$script:lookups.Add("$Hive|$View|$Path")
    if ($script:deny -or $script:denyAfter) { throw 'access denied' }
    $key = "$Hive|$View|$Path"
    if (-not $script:records.ContainsKey($key)) { return $null }
    $values = $script:records[$key]
    $obj = [pscustomobject]@{ Values = $values }
    $obj | Add-Member ScriptMethod GetValueKind { param($name) $this.Values[$name].Kind }
    $obj | Add-Member ScriptMethod GetValue { param($name) $this.Values[$name].Value }
    $obj | Add-Member ScriptMethod Close { }
    return $obj
}
function winget {
    $argsText = @($args) -join ' '
    [void]$script:calls.Add($argsText)
    if ($argsText -match '^install -e --id doppler\.doppler ') { $global:LASTEXITCODE = 0; return }
    if ($script:timedOut) { throw [TimeoutException]::new('mock native timeout') }
    if ($argsText -eq 'source export --name winget') {
        $global:LASTEXITCODE = $script:sourceExit
        return $script:sourceJson
    }
    if ($argsText -notmatch '^uninstall --product-code (Infisical\.CLI|infisical\.infisical)_Microsoft\.Winget\.Source_8wekyb3d8bbwe --exact --source winget --scope (user|machine) --silent --preserve --accept-source-agreements --disable-interactivity$') {
        throw 'Unverified uninstall arguments'
    }
    $global:LASTEXITCODE = $script:uninstallExit
    if (($script:uninstallExit -eq 0 -or $script:removeOnFailure) -and -not $script:leaveRecord) {
        foreach ($key in @($script:records.Keys)) {
            if ($key.EndsWith(($args[2]).ToString()) -and
                (($argsText -match '--scope user' -and $key.StartsWith('CurrentUser|')) -or
                 ($argsText -match '--scope machine' -and $key.StartsWith('LocalMachine|')))) {
                $script:records.Remove($key)
            }
        }
    }
    if ($script:denyPostcheck) { $script:denyAfter = $true }
}
function New-Record($id, $scope = 'CurrentUser', $view = 'Registry64', $sourceId = 'Microsoft.Winget.Source_8wekyb3d8bbwe', $type = 'portable') {
    $code = "${id}_Microsoft.Winget.Source_8wekyb3d8bbwe"
    $path = "Software\Microsoft\Windows\CurrentVersion\Uninstall\$code"
    $values = @{
        WinGetPackageIdentifier = @{ Kind = 'String'; Value = $id }
        WinGetSourceIdentifier = @{ Kind = 'String'; Value = $sourceId }
        WinGetInstallerType = @{ Kind = 'String'; Value = $type }
        UninstallString = @{ Kind = 'String'; Value = "winget uninstall --product-code $code" }
    }
    $script:records["$scope|$view|$path"] = $values
}
function Assert-Case($condition, $message) { if (-not $condition) { throw $message } }
# No optional module. The complete bounded absent set must not invoke winget.
Assert-Case (Remove-InfisicalCli) 'WinGet-only verified absence failed'
Assert-Case ($script:calls.Count -eq 0) 'Absent package contacted winget'
Assert-Case ($script:lookups.Count -eq 6) 'Native bounded inventory did not inspect six exact registrations'
Assert-Case (@($script:lookups | Where-Object { $_ -like 'CurrentUser|Registry32|*' }).Count -eq 0) 'Shared HKCU was double-counted'
Assert-Case (@($script:lookups | Where-Object { $_ -like 'LocalMachine|Registry32|Software\Microsoft\Windows\CurrentVersion\Uninstall\*' }).Count -eq 2) '32-bit logical view was not inspected'
function Get-Command { param($Name, $ErrorAction) if ($Name -eq 'infisical') { 'custom-copy' } }
$warningText = (& { Remove-InfisicalCli } 3>&1 | Out-String)
Assert-Case ($warningText -match 'manual') 'Preserved custom PATH copy was not reported'
Assert-Case ($script:calls.Count -eq 0) 'Custom PATH copy authorized removal'
Remove-Item function:Get-Command
foreach ($id in @('Infisical.CLI', 'infisical.infisical')) {
    $script:records.Clear(); $script:calls.Clear()
    New-Record $id
    Assert-Case (Remove-InfisicalCli) "Verified $id did not retire"
    Assert-Case ($script:records.Count -eq 0) 'Registration remains'
    Assert-Case (Remove-InfisicalCli) 'Rerun failed'
    Assert-Case ($script:calls.Count -eq 2) 'Unexpected native calls'
}
$script:records.Clear(); $script:calls.Clear()
New-Record 'infisical.infisical' 'CurrentUser' 'Registry64' 'private-source'
Assert-Case (-not (Remove-InfisicalCli)) 'Conflicting source was accepted'
Assert-Case ($script:calls.Count -eq 0) 'Conflicting source triggered native action'
# Native HKCU is a shared 64-bit view; HKLM's 32-bit view maps to Wow6432Node.
foreach ($location in @(@('LocalMachine', 'Registry64'), @('LocalMachine', 'Registry32'))) {
    $script:records.Clear(); $script:calls.Clear()
    New-Record 'infisical.infisical' $location[0] $location[1]
    Assert-Case (Remove-InfisicalCli) 'Machine-view package failed'
    Assert-Case ($script:records.Count -eq 0) 'Machine-view registration remains'
}
$script:records.Clear(); $script:calls.Clear()
New-Record 'infisical.infisical' 'LocalMachine' 'Registry64'
New-Record 'infisical.infisical' 'LocalMachine' 'Registry32'
Assert-Case (-not (Remove-InfisicalCli)) 'Ambiguous machine registration accepted'
Assert-Case ($script:calls.Count -eq 0) 'Ambiguous registration triggered native command'
$script:records.Clear(); $script:calls.Clear()
New-Record 'infisical.infisical' 'CurrentUser' 'Registry64'
New-Record 'Infisical.CLI' 'LocalMachine' 'Registry64'
Assert-Case (Remove-InfisicalCli) 'Independent approved identities did not retire'
Assert-Case ($script:records.Count -eq 0) 'Independent registration remains'
foreach ($broken in @('garbage', '[]', ('[' + $script:sourceJson + ']'), "{}" + [Environment]::NewLine + "{}",  '{"Name":"winget","Type":"Microsoft.PreIndexed.Package","Arg":"https://evil.invalid","Data":"Microsoft.Winget.Source_8wekyb3d8bbwe","Identifier":"Microsoft.Winget.Source_8wekyb3d8bbwe"}',
                    '{"Name":"winget","Type":"Microsoft.PreIndexed.Package","Arg":"https://cdn.winget.microsoft.com/cache","Data":"wrong","Identifier":"Microsoft.Winget.Source_8wekyb3d8bbwe"}')) {
    $script:records.Clear(); $script:calls.Clear()
    New-Record 'infisical.infisical'
    $script:sourceJson = $broken
    Assert-Case (-not (Remove-InfisicalCli)) 'Malformed/substituted source accepted'
    Assert-Case ($script:records.Count -eq 1) 'Malformed source changed registration'
    Assert-Case ($script:calls.Count -eq 1) 'Malformed source triggered uninstall'
}
$script:sourceJson = '{"Name":"winget","Type":"Microsoft.PreIndexed.Package","Arg":"https://cdn.winget.microsoft.com/cache","Data":"Microsoft.Winget.Source_8wekyb3d8bbwe","Identifier":"Microsoft.Winget.Source_8wekyb3d8bbwe"}'
$script:records.Clear(); $script:calls.Clear()
New-Record 'infisical.infisical'
$script:sourceExit = 1
Assert-Case (-not (Remove-InfisicalCli)) 'Failed source export was accepted'
Assert-Case ($script:calls.Count -eq 1) 'Failed source export triggered uninstall'
$script:sourceExit = 0
$script:timedOut = $true
Assert-Case (-not (Remove-InfisicalCli)) 'Native timeout was accepted'
$script:timedOut = $false
foreach ($exitCode in @(1, -1978335212)) {
    $script:records.Clear(); $script:calls.Clear()
    New-Record 'Infisical.CLI'
    $script:uninstallExit = $exitCode
    Assert-Case (-not (Remove-InfisicalCli)) 'Native nonzero was treated as absence'
    Assert-Case ($script:records.Count -eq 1) 'Native error removed unrelated data'
}
$script:uninstallExit = -1978335212
$script:removeOnFailure = $true
Assert-Case (-not (Remove-InfisicalCli)) 'Removal error was cleared by missing postcheck record'
$script:removeOnFailure = $false
$script:uninstallExit = 0
$script:records.Clear(); $script:calls.Clear()
New-Record 'infisical.infisical'
$script:leaveRecord = $true
Assert-Case (-not (Remove-InfisicalCli)) 'Lingering registration was accepted'
$script:leaveRecord = $false
$script:denyPostcheck = $true
Assert-Case (-not (Remove-InfisicalCli)) 'Unreadable postcheck was accepted'
$script:denyPostcheck = $false; $script:denyAfter = $false
foreach ($malformation in @('type', 'missing', 'id', 'source', 'installer')) {
    $script:records.Clear(); $script:calls.Clear()
    New-Record 'Infisical.CLI'
    $value = @($script:records.Values)[0]
    switch ($malformation) {
        type { $value.WinGetPackageIdentifier.Kind = 'ExpandString' }
        missing { $value.Remove('WinGetInstallerType') }
        id { $value.WinGetPackageIdentifier.Value = 'other.product' }
        source { $value.WinGetSourceIdentifier.Value = 'private-source' }
        installer { $value.WinGetInstallerType.Value = 'msi' }
    }
    Assert-Case (-not (Remove-InfisicalCli)) 'Unsafe registry metadata accepted'
    Assert-Case ($script:calls.Count -eq 0) 'Malformed record triggered native command'
}
$script:records.Clear(); $script:calls.Clear()
New-Record 'Infisical.CLI'
New-Record 'infisical.infisical' 'LocalMachine' 'Registry64'
$values = $script:records['LocalMachine|Registry64|Software\Microsoft\Windows\CurrentVersion\Uninstall\infisical.infisical_Microsoft.Winget.Source_8wekyb3d8bbwe']
$values.WinGetInstallerType.Value = 'exe'
Assert-Case (-not (Remove-InfisicalCli)) 'Partial preflight uninstalled valid sibling'
Assert-Case ($script:calls.Count -eq 0) 'Unverified sibling triggered native command'
$script:records.Clear(); $script:calls.Clear()
Write-Host 'Native WinGet portable mock passed'
