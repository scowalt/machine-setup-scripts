# Native Windows contract for global Backlog MCP retirement.
# On non-Windows hosts this parses the production/prototype helper and compiles
# its native C# only. Native handle and ACL operations are explicitly skipped.
[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Split-Path -Parent $PSScriptRoot)
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "ASSERT: $Message" }
}
function Parse-Source([string]$Path) {
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw "PowerShell parse failed: $Path" }
    return $ast
}
function Find-Function([System.Management.Automation.Language.Ast]$Ast, [string]$Name) {
    return $Ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $Name }, $true)
}
function Extract-Between([string]$Text, [string]$Begin, [string]$End) {
    $start = $Text.IndexOf($Begin, [StringComparison]::Ordinal)
    $finish = if ($start -ge 0) { $Text.IndexOf($End, $start + $Begin.Length, [StringComparison]::Ordinal) } else { -1 }
    if ($start -lt 0 -or $finish -lt 0) { throw "Required managed source markers are absent" }
    return $Text.Substring($start + $Begin.Length, $finish - ($start + $Begin.Length)).Trim()
}

$winPath = Join-Path $RepositoryRoot 'win.ps1'
$winAst = Parse-Source $winPath
$winText = [IO.File]::ReadAllText($winPath)
$functionAst = Find-Function $winAst 'Invoke-BacklogMcpWindowsRetirement'
Assert-True ($null -ne $functionAst) 'Invoke-BacklogMcpWindowsRetirement is not integrated in win.ps1'
$functionSource = $functionAst.Extent.Text
$nativeSource = Extract-Between $functionSource '// BEGIN BACKLOG_WINDOWS_NATIVE' '// END BACKLOG_WINDOWS_NATIVE'
Assert-True ($nativeSource -match 'public static class BacklogNativeFiles') 'native helper class missing'
foreach ($member in @('Canonical','Open','Verify','CheckAcl','Snapshot','Write','Plan')) {
    Assert-True ($nativeSource -match ("\b" + [regex]::Escape($member) + "\s*\(")) "native member $member missing"
}
Assert-True ($nativeSource -match 'CreateFile\(name,access,1,') 'native opens do not deny write/delete sharing'
Assert-True ($nativeSource.Contains('GetKernelObjectSecurity')) 'native ACL snapshot missing'
Assert-True ($nativeSource.Contains('Links != 1')) 'native hardlink rejection missing'
Assert-True ($nativeSource.Contains('WriteFile')) 'native same-handle write missing'
Assert-True ($functionSource -match "phase\s*=\s*'preflight'") 'controlled phase tracking missing'
Assert-True ($functionSource -match "native-preflight-failed") 'controlled preflight diagnostic missing'
Assert-True ($functionSource -match "write-failed") 'controlled write diagnostic missing'
Assert-True ($functionSource -notmatch ('Write-(Host|Warning|Error).*' + [regex]::Escape('$_'))) 'raw exception logging is forbidden'

# Add-Type compilation catches C# drift on Linux without invoking any P/Invoke.
if (-not ('BacklogNativeFiles' -as [type])) { Add-Type -TypeDefinition $nativeSource -ErrorAction Stop }

$runningOnWindows = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
if (-not $runningOnWindows) {
    Write-Host 'SKIP: native Windows handle/ACL operations require Windows; AST and BacklogNativeFiles C# compilation passed.'
    exit 0
}

$program = "// BEGIN BACKLOG_MCP_RETIREMENT`n" + (Extract-Between $winText '// BEGIN BACKLOG_MCP_RETIREMENT' '// END BACKLOG_MCP_RETIREMENT')
Assert-True ($program -match '// END BACKLOG_PURE_PLANNER') 'pure planner marker missing'
Invoke-Expression $functionSource
Assert-True ($null -ne (Get-Command node.exe -CommandType Application -ErrorAction SilentlyContinue)) 'node.exe is required'
Assert-True ($null -ne (Get-Command bun.exe -CommandType Application -ErrorAction SilentlyContinue)) 'bun.exe is required'

# Test-only native identity reader. Production mutation remains exclusively in
# BacklogNativeFiles; this helper proves the same file ID survives the write.
if (-not ('BacklogTestIdentity' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class BacklogTestIdentity {
    [StructLayout(LayoutKind.Sequential)] struct Info {
        public uint Attributes, CreatedLow, CreatedHigh, AccessLow, AccessHigh,
            WriteLow, WriteHigh, Volume, SizeHigh, SizeLow, Links, IndexHigh, IndexLow;
    }
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern SafeFileHandle CreateFile(string name, uint access, uint share, IntPtr security, uint creation, uint flags, IntPtr template);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool GetFileInformationByHandle(SafeFileHandle file, out Info info);
    public static string Read(string path) {
        using (var handle=CreateFile(path,0x80u,7u,IntPtr.Zero,3u,0x00200000u,IntPtr.Zero)) {
            Info value; if (handle.IsInvalid || !GetFileInformationByHandle(handle,out value)) throw new Win32Exception();
            return value.Volume+":"+value.IndexHigh+":"+value.IndexLow;
        }
    }
}
'@ -ErrorAction Stop
}

$root = Join-Path ([IO.Path]::GetTempPath()) ('backlog-mcp-windows-' + [Guid]::NewGuid().ToString('N'))
$fixtureHome = Join-Path $root 'home'
$owner = [Security.Principal.WindowsIdentity]::GetCurrent().User
$system = [Security.Principal.SecurityIdentifier]::new('S-1-5-18')
$admins = [Security.Principal.SecurityIdentifier]::new('S-1-5-32-544')
function Set-PrivateAcl([string]$Path, [bool]$Directory) {
    $acl = if ($Directory) { [Security.AccessControl.DirectorySecurity]::new() } else { [Security.AccessControl.FileSecurity]::new() }
    $acl.SetOwner($owner); $acl.SetAccessRuleProtection($true, $false)
    $inheritance = if ($Directory) { 'ContainerInherit,ObjectInherit' } else { 'None' }
    foreach ($sid in @($owner,$system,$admins)) {
        $rule = [Security.AccessControl.FileSystemAccessRule]::new($sid, 'FullControl', $inheritance, 'None', 'Allow')
        $null = $acl.AddAccessRule($rule)
    }
    Set-Acl -LiteralPath $Path -AclObject $acl
}
function New-PrivateDirectory([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    $parent = [IO.Path]::GetDirectoryName($full)
    if ($parent -and $root -and $full -ne $root -and $parent.StartsWith($root + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -and -not (Test-Path -LiteralPath $parent)) {
        New-PrivateDirectory $parent
    }
    if (-not (Test-Path -LiteralPath $full)) { $null = New-Item -ItemType Directory -Path $full }
    Set-PrivateAcl $full $true
}
function Write-PrivateFile([string]$Path, [string]$Text) {
    New-PrivateDirectory ([IO.Path]::GetDirectoryName($Path))
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
    Set-PrivateAcl $Path $false
}
function Invoke-Fixture([string[]]$Profiles = @($fixtureHome,'','','','')) {
    return Invoke-BacklogMcpWindowsRetirement -Program $program -Profiles $Profiles
}
function Assert-Controlled($Result) {
    Assert-True ($Result.Code -in @(0,1)) 'invalid result code'
    Assert-True ($Result.Status -in @('absent','removed','native-preflight-failed','write-failed')) 'uncontrolled diagnostic'
    Assert-True (($Result | ConvertTo-Json -Compress) -notmatch 'SENTINEL-SECRET') 'secret leaked in result'
}
$fixtureLinks = [Collections.Generic.List[object]]::new()
function Remove-FixtureLinks {
    foreach ($link in @($fixtureLinks)) {
        if (Test-Path -LiteralPath $link.Path) {
            if ($link.Directory) { [IO.Directory]::Delete($link.Path) } else { [IO.File]::Delete($link.Path) }
        }
    }
    $fixtureLinks.Clear()
}
function Reset-Home {
    Remove-FixtureLinks
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
    New-PrivateDirectory $root; New-PrivateDirectory $fixtureHome
}
try {
    # Ordinary absent configuration is a successful no-op.
    Reset-Home
    Write-PrivateFile (Join-Path $fixtureHome '.config\mcp\mcp.json') '{"mcpServers":{"keep":{"env":{"TOKEN":"SENTINEL-SECRET"}}}}'
    $result = Invoke-Fixture; Assert-Controlled $result
    Assert-True ($result.Code -eq 0 -and $result.Status -eq 'absent') 'normal absent case failed'
    # An unrelated project/PATH executable must never receive private snapshots.
    $shadow = Join-Path $root 'shadow'; New-PrivateDirectory $shadow
    Write-PrivateFile (Join-Path $shadow 'bun.exe') 'inert non-executable fixture; never launch'
    $originalPath = $env:PATH
    try {
        $env:PATH = $shadow + [IO.Path]::PathSeparator + $originalPath
        $result = Invoke-Fixture
        Assert-True ($result.Code -eq 0 -and $result.Status -eq 'absent') 'PATH shadow selected as planner runtime'
    } finally { $env:PATH = $originalPath }

    # Multi-file JSON/TOML retirement preserves unrelated/project/credential/task content.
    Reset-Home
    $json = Join-Path $fixtureHome '.config\mcp\mcp.json'
    $toml = Join-Path $fixtureHome '.codex\config.toml'
    $claude = Join-Path $fixtureHome '.claude.json'
    $task = Join-Path $fixtureHome 'backlog\config.yml'
    Write-PrivateFile $json '{"credential":"SENTINEL-SECRET","mcpServers":{"backlog":{"command":"backlog"},"keep":{"url":"https://example.invalid"}}}'
    Write-PrivateFile $toml "[mcp_servers.backlog]`ncommand=`"backlog`"`nargs=[`"mcp`",`"start`"]`n[other]`nkeep=true`n"
    Write-PrivateFile $claude '{"mcpServers":{"backlog":{}},"projects":{"C:\\repo":{"mcpServers":{"backlog":{"keep":true}}}}}'
    Write-PrivateFile $task "keep: true`n"
    $jsonAcl = (Get-Acl -LiteralPath $json).Sddl
    $jsonIdentity = [BacklogTestIdentity]::Read($json)
    $result = Invoke-Fixture; Assert-Controlled $result
    Assert-True ($result.Code -eq 0 -and $result.Status -eq 'removed') 'retirement failed'
    $jsonData = Get-Content -LiteralPath $json -Raw | ConvertFrom-Json
    Assert-True ($null -eq $jsonData.mcpServers.PSObject.Properties['backlog'] -and $null -ne $jsonData.mcpServers.PSObject.Properties['keep']) 'JSON plan incorrect'
    Assert-True ($jsonData.credential -eq 'SENTINEL-SECRET') 'credential changed'
    Assert-True ((Get-Content -LiteralPath $toml -Raw) -match '\[other\]') 'unrelated TOML removed'
    $claudeData = Get-Content -LiteralPath $claude -Raw | ConvertFrom-Json
    Assert-True ($claudeData.projects.'C:\repo'.mcpServers.backlog.keep) 'project record changed'
    Assert-True ((Get-Content -LiteralPath $task -Raw) -eq "keep: true`n") 'task content changed'
    Assert-True ((Get-Acl -LiteralPath $json).Sddl -eq $jsonAcl) 'file ACL changed'
    Assert-True ([BacklogTestIdentity]::Read($json) -eq $jsonIdentity) 'file identity was replaced'
    $again = Invoke-Fixture; Assert-True ($again.Code -eq 0 -and $again.Status -eq 'absent') 'repeat run not idempotent'

    # Explicit selected profiles are covered alongside defaults.
    Reset-Home
    $selected = Join-Path $fixtureHome 'profiles\pi'; New-PrivateDirectory $selected
    Write-PrivateFile (Join-Path $selected 'mcp.json') '{"mcpServers":{"backlog":{},"keep":{}}}'
    $result = Invoke-Fixture -Profiles @($fixtureHome,$selected,'','',''); Assert-True ($result.Status -eq 'removed') 'selected profile not retired'

    # Malformed second file blocks every write.
    Reset-Home
    $first = Join-Path $fixtureHome '.config\mcp\mcp.json'; $bad = Join-Path $fixtureHome '.agents\mcp.json'
    $before = '{"mcpServers":{"backlog":{},"keep":{}}}'; Write-PrivateFile $first $before; Write-PrivateFile $bad '{malformed SENTINEL-SECRET'
    $result = Invoke-Fixture; Assert-Controlled $result
    Assert-True ($result.Code -eq 1 -and (Get-Content -LiteralPath $first -Raw) -eq $before) 'malformed preflight wrote another file'

    # Unsafe ACLs are tolerated for an absent read-only identification, but a
    # positive removal refuses with no write and no secret in diagnostics.
    foreach ($unsafeAncestor in @($false,$true)) {
        Reset-Home
        $file = Join-Path $fixtureHome '.config\mcp\mcp.json'
        $absentText = '{"secret":"SENTINEL-SECRET","mcpServers":{"keep":{}}}'
        Write-PrivateFile $file $absentText
        $target = if ($unsafeAncestor) { Join-Path $fixtureHome '.config' } else { $file }
        $acl = Get-Acl -LiteralPath $target
        $everyone = [Security.Principal.SecurityIdentifier]::new('S-1-1-0')
        $rule = [Security.AccessControl.FileSystemAccessRule]::new($everyone,'Modify','Allow'); $null = $acl.AddAccessRule($rule); Set-Acl -LiteralPath $target -AclObject $acl
        $result = Invoke-Fixture; Assert-Controlled $result
        Assert-True ($result.Code -eq 0 -and $result.Status -eq 'absent' -and (Get-Content -LiteralPath $file -Raw) -eq $absentText) 'unsafe absent no-op failed'
        $selectedText = '{"secret":"SENTINEL-SECRET","mcpServers":{"backlog":{},"keep":{}}}'
        [IO.File]::WriteAllText($file,$selectedText,[Text.UTF8Encoding]::new($false))
        $result = Invoke-Fixture; Assert-Controlled $result
        Assert-True ($result.Code -eq 1 -and (Get-Content -LiteralPath $file -Raw) -eq $selectedText) 'unsafe writable ACL mutated selected metadata'
    }

    # Reparse ancestors/leaves and hardlinks are rejected.
    Reset-Home
    $outside = Join-Path $root 'outside'; New-PrivateDirectory $outside
    $junction = Join-Path $fixtureHome '.config'; $null = New-Item -ItemType Junction -Path $junction -Target $outside
    $fixtureLinks.Add([pscustomobject]@{Path=$junction;Directory=$true})
    $result = Invoke-Fixture; Assert-True ($result.Code -eq 1) 'junction accepted'
    Reset-Home
    $outsideFile = Join-Path $root 'outside.json'; Write-PrivateFile $outsideFile '{"mcpServers":{"backlog":{}}}'
    $linkParent = Join-Path $fixtureHome '.agents'; New-PrivateDirectory $linkParent
    $fileLink = Join-Path $linkParent 'mcp.json'; $null = New-Item -ItemType SymbolicLink -Path $fileLink -Target $outsideFile
    $fixtureLinks.Add([pscustomobject]@{Path=$fileLink;Directory=$false})
    $result = Invoke-Fixture; Assert-True ($result.Code -eq 1) 'file symlink accepted'
    Reset-Home
    $file = Join-Path $fixtureHome '.config\mcp\mcp.json'; Write-PrivateFile $file '{"mcpServers":{"backlog":{}}}'
    $null = New-Item -ItemType HardLink -Path (Join-Path $fixtureHome 'linked.json') -Target $file
    $result = Invoke-Fixture; Assert-True ($result.Code -eq 1) 'hardlink accepted'

    # A concurrently open writer prevents the transaction from pinning the file.
    Reset-Home
    $file = Join-Path $fixtureHome '.config\mcp\mcp.json'; Write-PrivateFile $file '{"mcpServers":{"backlog":{}}}'
    $held = [IO.File]::Open($file,[IO.FileMode]::Open,[IO.FileAccess]::Write,[IO.FileShare]::Read)
    try { $result = Invoke-Fixture; Assert-True ($result.Code -eq 1) 'open writer accepted' } finally { $held.Dispose() }

    Write-Host 'PASS: native Windows Backlog MCP retirement fixtures passed.'
}
finally {
    Remove-FixtureLinks
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
