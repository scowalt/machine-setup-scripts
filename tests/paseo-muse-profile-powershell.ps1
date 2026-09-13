# Offline wrapper fixtures. Parse win.ps1; execute only the extracted function.
param([string]$RepositoryRoot = (Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $RepositoryRoot 'win.ps1'), [ref]$tokens, [ref]$errors)
if ($errors.Count -gt 0) { throw 'win.ps1 parse failed' }
$definition = $ast.Find({ param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Set-PaseoMuseProfile'
}, $true)
if ($null -eq $definition) { throw 'Set-PaseoMuseProfile missing' }
. ([scriptblock]::Create($definition.Extent.Text))
function Write-Success { param([string]$Message) }
function Write-Debug { param([string]$Message) }
function Assert-Fixture { param([bool]$Condition, [string]$Label)
    if (-not $Condition) { throw "Muse PowerShell fixture failed: $Label" }
}
$script:MockOutput = 'PASEO_MUSE_UPDATED'
$script:MockStatus = 0
$script:CapturedChanged = ''
$script:CapturedCode = ''
$script:CapturedNodeOptions = $null
$script:CapturedNodePath = $null
# This shadows the real executable. Never run a live Node/Paseo/Pi/service command.
function node {
    process { $script:CapturedCode = [string]$_ }
    end {
        $script:CapturedChanged = $env:PASEO_MUSE_GO_CHANGED
        $script:CapturedNodeOptions = $env:NODE_OPTIONS
        $script:CapturedNodePath = $env:NODE_PATH
        $global:LASTEXITCODE = $script:MockStatus
        $script:MockOutput
    }
}
$previous = $env:PASEO_MUSE_GO_CHANGED
$previousNodeOptions = $env:NODE_OPTIONS
$previousNodePath = $env:NODE_PATH
$oldWarningPreference = $WarningPreference
try {
    $WarningPreference = 'SilentlyContinue'
    $env:PASEO_MUSE_GO_CHANGED = 'previous-fixture-value'
    $env:NODE_OPTIONS = '--require=poison-fixture'
    $env:NODE_PATH = 'poison-fixture-directory'
    $script:PiOpenCodeGoChanged = $true
    $value = Set-PaseoMuseProfile
    Assert-Fixture ($value -is [bool] -and $value) 'success bool only'
    Assert-Fixture ($script:CapturedChanged -eq '1') 'changed input forwarded'
    Assert-Fixture ($env:PASEO_MUSE_GO_CHANGED -eq 'previous-fixture-value') 'environment restored'
    Assert-Fixture ($null -eq $script:CapturedNodeOptions -and $null -eq $script:CapturedNodePath) 'Node loader environment cleared'
    Assert-Fixture ($env:NODE_OPTIONS -ceq '--require=poison-fixture' -and $env:NODE_PATH -ceq 'poison-fixture-directory') 'Node loader environment restored'
    Assert-Fixture ($script:CapturedCode.Contains('// BEGIN PASEO MUSE PROFILE')) 'embedded code piped'
    Assert-Fixture ($script:CapturedCode.Contains('setup:pi:opencode-go:muse-spark-1.3-contributor')) 'stable ID present'

    $script:PiOpenCodeGoChanged = $false
    $script:MockOutput = 'PASEO_MUSE_UNCHANGED'
    $value = Set-PaseoMuseProfile
    Assert-Fixture ($value -is [bool] -and $value) 'unchanged success'
    Assert-Fixture ($script:CapturedChanged -eq '0') 'unchanged input forwarded'

    $script:MockOutput = @('PASEO_MUSE_DEFER_DAEMON_SETUP=1', 'Paseo Muse deferred: desktop-owned.', 'Quit Paseo Desktop and rerun outside Paseo.')
    $value = Set-PaseoMuseProfile
    Assert-Fixture ($value -is [bool] -and $value) 'unsafe owner is warning not failure'

    $script:MockStatus = 1
    $script:MockOutput = @('PASEO_MUSE_DEFER_DAEMON_SETUP=1', 'Paseo Muse failed: invalid-json.')
    $value = Set-PaseoMuseProfile
    Assert-Fixture ($value -is [bool] -and -not $value) 'failure bool only'
    Assert-Fixture ($env:PASEO_MUSE_GO_CHANGED -eq 'previous-fixture-value') 'failure restores environment'
    Assert-Fixture ($null -eq $script:CapturedNodeOptions -and $null -eq $script:CapturedNodePath) 'failure clears Node loader environment'
    Assert-Fixture ($env:NODE_OPTIONS -ceq '--require=poison-fixture' -and $env:NODE_PATH -ceq 'poison-fixture-directory') 'failure restores Node loader environment'

    function Get-Command { param([string]$Name, [object]$ErrorAction) return $null }
    $value = Set-PaseoMuseProfile
    Assert-Fixture ($value -is [bool] -and $value) 'missing Node defers'
    Remove-Item Function:Get-Command
    Write-Host 'Paseo Muse PowerShell wrapper fixtures passed.'
} finally {
    $env:PASEO_MUSE_GO_CHANGED = $previous
    $env:NODE_OPTIONS = $previousNodeOptions
    $env:NODE_PATH = $previousNodePath
    $WarningPreference = $oldWarningPreference
    Remove-Item Function:node -ErrorAction SilentlyContinue
}

# Execute the extracted ACL policy against in-memory Windows ACLs. Replace only
# WindowsIdentity and process-result plumbing; all ACL comparisons remain real
# PowerShell/.NET enum operations. No real Get-Acl/Get-Item calls are possible.
$aclMatch = [regex]::Match($definition.Extent.Text,
    '(?s)function checkWindowsMetadataAcl\(file\).*?const command = String.raw`(.*?)`;')
Assert-Fixture $aclMatch.Success 'embedded Windows ACL policy present'
$aclCode = $aclMatch.Groups[1].Value
$identityLine = '$owner = [System.Security.Principal.WindowsIdentity]::GetCurrent().User'
Assert-Fixture ($aclCode.Contains($identityLine)) 'ACL identity seam present'
$aclCode = $aclCode.Replace($identityLine, '$owner = [pscustomobject]@{Value=''S-1-5-21-fixture''}')
$aclCode = $aclCode.Replace('[Console]::Out.Write(''ok'')', 'return $true').Replace('catch { exit 1 }', 'catch { return $false }')
$aclPolicy = [scriptblock]::Create($aclCode)
$script:AclPaths = @('/fixture/home/.paseo/config.json', '/fixture/home/.paseo', '/fixture/home')
$script:AclFixtures = @{}
function Reset-AclFixtures {
    $script:AclFixtures = @{}
    foreach ($path in $script:AclPaths) {
        $script:AclFixtures[$path] = [pscustomobject]@{ Owner='S-1-5-21-fixture'; Rules=@(); NullDacl=$false; Linked=$false }
    }
}
function New-AclFixtureRule {
    param([string]$Sid, [System.Security.AccessControl.FileSystemRights]$Rights,
        [System.Security.AccessControl.PropagationFlags]$Propagation = 'None')
    return [pscustomobject]@{ IdentityReference=[pscustomobject]@{Value=$Sid}; AccessControlType='Allow';
        FileSystemRights=$Rights; PropagationFlags=$Propagation }
}
function Get-Item {
    param([string]$LiteralPath, [switch]$Force, [object]$ErrorAction)
    if (-not $script:AclFixtures.ContainsKey($LiteralPath)) { throw 'non-fixture path' }
    return [pscustomobject]@{ Attributes = if ($script:AclFixtures[$LiteralPath].Linked) {
        [IO.FileAttributes]::ReparsePoint
    } else { [IO.FileAttributes]::Normal } }
}
function Get-Acl {
    param([string]$LiteralPath)
    if (-not $script:AclFixtures.ContainsKey($LiteralPath)) { throw 'non-fixture ACL' }
    $security = [pscustomobject]@{ Fixture=$script:AclFixtures[$LiteralPath] }
    $security | Add-Member ScriptMethod GetOwner { param($Type) return [pscustomobject]@{Value=$this.Fixture.Owner} }
    $security | Add-Member ScriptMethod GetAccessRules {
        param($Explicit, $Inherited, $Type)
        if (-not $Explicit -or -not $Inherited) { throw 'incomplete ACL inspection' }
        return $this.Fixture.Rules
    }
    $security | Add-Member ScriptMethod GetSecurityDescriptorSddlForm {
        param($Sections)
        if ($this.Fixture.NullDacl) { return 'D:NO_ACCESS_CONTROL' }
        return 'D:'
    }
    return $security
}
$aclEnvironment = @{}
foreach ($name in @('PSModulePath', 'PASEO_MUSE_ACL_PATHS', 'PASEO_MUSE_ACCOUNT_HOME')) {
    $aclEnvironment[$name] = [Environment]::GetEnvironmentVariable($name)
}
try {
    $env:PASEO_MUSE_ACL_PATHS = $script:AclPaths | ConvertTo-Json -Compress
    $env:PASEO_MUSE_ACCOUNT_HOME = '/fixture/home'
    Reset-AclFixtures
    Assert-Fixture ([bool](& $aclPolicy)) 'safe ACLs accepted'
    foreach ($path in $script:AclPaths) {
        Reset-AclFixtures
        $script:AclFixtures[$path].Owner = 'S-1-1-0'
        Assert-Fixture (-not (& $aclPolicy)) 'untrusted owner rejected'
        Reset-AclFixtures
        $script:AclFixtures[$path].NullDacl = $true
        Assert-Fixture (-not (& $aclPolicy)) 'null DACL rejected'
        Reset-AclFixtures
        $script:AclFixtures[$path].Linked = $true
        Assert-Fixture (-not (& $aclPolicy)) 'late reparse point rejected'
        foreach ($right in @('Write','Delete','DeleteSubdirectoriesAndFiles','ChangePermissions','TakeOwnership')) {
            Reset-AclFixtures
            $script:AclFixtures[$path].Rules = @(New-AclFixtureRule 'S-1-1-0' $right)
            Assert-Fixture (-not (& $aclPolicy)) 'untrusted writer rejected'
        }
        Reset-AclFixtures
        $script:AclFixtures[$path].Rules = @(New-AclFixtureRule 'S-1-1-0' 'Write' 'InheritOnly')
        Assert-Fixture ([bool](& $aclPolicy)) 'inherit-only ACE does not apply to current item'
        foreach ($owner in @('S-1-5-18', 'S-1-5-32-544')) {
            Reset-AclFixtures
            $script:AclFixtures[$path].Owner = $owner
            $script:AclFixtures[$path].Rules = @(New-AclFixtureRule $owner 'FullControl')
            Assert-Fixture ([bool](& $aclPolicy)) 'trusted system/admin accepted'
        }
    }
    Reset-AclFixtures
    $script:AclFixtures[$script:AclPaths[0]].Rules = @(New-AclFixtureRule 'S-1-1-0' 'ReadAndExecute')
    Assert-Fixture ([bool](& $aclPolicy)) 'existing read-only customization retained'
    $env:PASEO_MUSE_ACCOUNT_HOME = '/different-home'
    Assert-Fixture (-not (& $aclPolicy)) 'unverified HOME boundary rejected'
    Write-Host 'Paseo Muse simulated Windows ACL policy fixtures passed.'
} finally {
    foreach ($name in $aclEnvironment.Keys) { [Environment]::SetEnvironmentVariable($name, $aclEnvironment[$name]) }
    Remove-Item Function:Get-Item, Function:Get-Acl -ErrorAction SilentlyContinue
}
