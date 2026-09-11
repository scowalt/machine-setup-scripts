# Offline only: AST-extracted setup functions, temporary homes, mocked tools and
# persisted environment storage. Child probes run with -NoProfile and fixture
# activation, never a user's profile. No real Pi, mise installs, or registry writes.
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
$realNode = (Get-Command node -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$realMise = (Get-Command mise -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source
$realPowerShell = (Get-Process -Id $PID).Path
$originalEnvironment = @{}
Get-ChildItem Env: | ForEach-Object { $originalEnvironment[$_.Name] = $_.Value }
$testRoot = Join-Path ([IO.Path]::GetTempPath()) "shared node fixture $([guid]::NewGuid())"
New-Item -ItemType Directory -Path $testRoot | Out-Null

# Static Environment calls are redirected before extracting any installer code.
# Process changes are real and restored. User/Machine changes are only recorded.
Add-Type @'
using System;
using System.Collections.Generic;
public static class SharedNodeFixtureEnvironment {
    public static OperatingSystem OSVersion = new OperatingSystem(PlatformID.Win32NT, new Version(10, 0));
    public static Dictionary<string, string> Persisted = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
    public static List<string> Writes = new List<string>();
    public static string GetEnvironmentVariable(string name, string target) {
        if (target == "Process") return Environment.GetEnvironmentVariable(name);
        string result;
        return Persisted.TryGetValue(target + ":" + name, out result) ? result : null;
    }
    public static void SetEnvironmentVariable(string name, string value, string target) {
        if (target == "Process") { Environment.SetEnvironmentVariable(name, value); return; }
        Writes.Add(target + ":" + name);
        Persisted[target + ":" + name] = value;
    }
    public static string ExpandEnvironmentVariables(string value) { return Environment.ExpandEnvironmentVariables(value); }
}
'@
$loadedNames = @(
    'Test-PiNodeRuntimeReady', 'Test-SharedNodeRuntimeReady', 'Get-SharedNodeFallback',
    'Get-SharedNodePowerShellHost', 'Invoke-SharedNodeShellProcess', 'Test-SharedNodeShell',
    'Enable-SharedNodeRuntime', 'Enable-PiNodeRuntime', 'Test-SkillsCliNodeRuntimeReady',
    'Enable-SkillsCliNodeRuntime', 'Install-PiCli', 'Repair-NpmConfiguration'
)
foreach ($name in $loadedNames) {
    if (-not $definitions.ContainsKey($name)) { throw "Missing function: $name" }
    . ([scriptblock]::Create($definitions[$name].Replace('[Environment]::', '[SharedNodeFixtureEnvironment]::')))
}
# Keep the real process runner for safe, explicitly profile-free fixture children.
. ([scriptblock]::Create($definitions['Invoke-SharedNodeShellProcess'].Replace('function Invoke-SharedNodeShellProcess', 'function Invoke-FixtureProcess')))
$script:Assertions = 0
$script:AssertionFailures = [Collections.Generic.List[string]]::new()
function Assert($Condition, [string]$Message) {
    $script:Assertions++
    if (-not $Condition) { $script:AssertionFailures.Add($Message); throw $Message }
}
function Assert-Boolean($Result, [bool]$Expected, [string]$Message) {
    $values = @($Result)
    Assert ($values.Count -eq 1 -and $values[0] -is [bool] -and $values[0] -eq $Expected) "$Message (expected exactly one $Expected Boolean; got $values)"
}
$script:Messages = [Collections.Generic.List[string]]::new()
function Write-Message($Message) { $script:Messages.Add($Message) }
function Write-Warning($Message) { $script:Messages.Add($Message) }
function Write-Debug($Message) { $script:Messages.Add($Message) }
function Write-Success($Message) { $script:Messages.Add($Message) }
function Write-Host { } # Keep fixture output quiet; the final result uses Write-Output.

# Run each real JavaScript readiness expression in a VM with a fixture Node/API.
# This tests its logic, not a reimplementation of the version predicate in a mock.
$nodeMock = {
function node {
    if ($args[0] -eq '--version') { $global:LASTEXITCODE = 0; return "v$($script:State.ActiveVersion)" }
    if ($args[0] -ne '-e') { throw "Unexpected node invocation: $args" }
    $program = @'
const vm = require('node:vm');
const [code, version, glob, executable, expected] = process.argv.slice(1);
let status = 99;
const fs = { globSync: glob === 'true' ? () => [] : undefined, realpathSync: p => p };
vm.runInNewContext(code, { process: { versions: { node: version }, execPath: executable, argv: ['node', expected], exit: c => { status = c; } }, require: () => fs });
process.exit(status);
'@
    $savedOptions = $env:NODE_OPTIONS
    try {
        $env:NODE_OPTIONS = $null
        & $script:RealNode -e $program $args[1] $script:State.ActiveVersion ([string]$script:State.ActiveGlob).ToLowerInvariant() $script:State.ActiveIdentity ([string]$args[2])
    }
    finally { $env:NODE_OPTIONS = $savedOptions }
}
}.ToString()
. ([scriptblock]::Create($nodeMock))
$script:RealNode = $realNode
$script:RealPowerShell = $realPowerShell
$script:Calls = [Collections.Generic.List[string]]::new()
$script:Mutations = [Collections.Generic.List[string]]::new()
$script:Children = [Collections.Generic.List[object]]::new()
function Reset-Fixture {
    $script:Calls.Clear()
    $script:Mutations.Clear()
    $script:Messages.Clear()
    $script:Children.Clear()
    [SharedNodeFixtureEnvironment]::Writes.Clear()
    $env:USERPROFILE = Join-Path $testRoot 'home'
    $env:LOCALAPPDATA = Join-Path $testRoot 'local app data'
    $env:HOME = $env:USERPROFILE
    $env:PATH = 'inherited-runtime-path'
    $env:PROCESSOR_ARCHITECTURE = 'AMD64'
    $env:PROCESSOR_ARCHITEW6432 = $null
    $env:MISE_NODE_COMPILE = 'original-compile'
    $env:MISE_AUTO_INSTALL = 'original-auto'
    $env:__MISE_DIFF = 'inherited-diff'
    $env:__MISE_ORIG_PATH = 'inherited-runtime-path'
    $env:MISE_SHELL = 'pwsh'
    $env:MISE_NODE_VERSION = '18'
    $env:MISE_TOOL_OPTS__NODE = 'inherited-tool-opts'
    $env:FNM_MULTISHELL_PATH = 'inherited-fnm-path'
    $env:FNM_VERSION_FILE_STRATEGY = 'recursive'
    $env:NODE_PATH = 'inherited-modules'
    $env:NODE_OPTIONS = '--invalid-inherited-option'
    [SharedNodeFixtureEnvironment]::Persisted.Clear()
    [SharedNodeFixtureEnvironment]::Persisted['Machine:Path'] = 'persisted-machine-path'
    [SharedNodeFixtureEnvironment]::Persisted['User:Path'] = 'persisted-user-path'
    [SharedNodeFixtureEnvironment]::OSVersion = [OperatingSystem]::new([PlatformID]::Win32NT, [version]'10.0')
    New-Item -ItemType Directory -Force -Path $env:USERPROFILE, $env:LOCALAPPDATA | Out-Null
    $script:State = @{
        Inventory = '[]'; InventoryReads = 0; InventoryFailAt = 0; KeepInventory = $false
        GlobalVersion = '24.20.0'; GlobalGlob = $true; Installed = $true
        ActiveVersion = '24.20.0'; ActiveGlob = $true; ActiveIdentity = 'inherited-node'
        EffectiveVersion = '24.20.0'; EffectiveGlob = $true
        FreshVersion = '24.20.0'; FreshGlob = $true; FreshIdentity = 'mise-node'
        MiseMissing = $false; FreshMiseMissing = $false; WhichFail = $false
        ProvisionFail = $false; EnvFail = $false; EnvThrow = $false
        NpmFail = $false; FreshNpmFail = $false; NpmInstallFail = $false; RepairFail = $false
        FreshPiFail = $false; FreshPiShadow = $false; EmptyPiVersion = $false
    }
    $script:PiRuntimePreflightPassed = $false
}
function Set-Inventory([string]$Version = '24.20.0', [bool]$Installed = $true, [bool]$Glob = $true, [switch]$OldShape) {
    $script:State.GlobalVersion = $Version
    $script:State.GlobalGlob = $Glob
    $script:State.Installed = $Installed
    $row = @{ version = $Version; install_path = (Join-Path $testRoot 'mise install') }
    $script:State.Inventory = if ($OldShape) { @{ node = @($row) } | ConvertTo-Json -Depth 4 -Compress } else { ConvertTo-Json -InputObject @($row) -Depth 4 -Compress }
}
# Mock command discovery. No uncontrolled application can satisfy a setup probe.
function Get-Command {
    param([string]$Name, [switch]$All, $ErrorAction)
    if ($Name -eq 'mise') { if (-not $script:State.MiseMissing) { return [pscustomobject]@{ Source = 'fixture-mise' } }; return }
    if ($Name -eq 'npm') { return [pscustomobject]@{ Source = 'fixture-npm' } }
    if ($Name -eq 'pi') { return [pscustomobject]@{ Source = (Join-Path $env:USERPROFILE '.local/pi.ps1') } }
    throw "Unexpected command discovery: $Name"
}
# Explicit installed paths are intercepted, not executed (Windows node.exe cannot
# run on the Linux test host). The original JS predicate still runs via node mock.
$originalSharedReady = ${function:Test-SharedNodeRuntimeReady}
function Test-SharedNodeRuntimeReady {
    param([string]$Node = 'node')
    if ($Node -eq 'node') { return (& $script:originalSharedReady) }
    Assert ($Node -eq (Join-Path $testRoot 'mise install/node.exe')) 'Readiness used a private or non-mise Node path.'
    $previousVersion = $script:State.ActiveVersion
    $previousGlob = $script:State.ActiveGlob
    try {
        $script:State.ActiveVersion = $script:State.GlobalVersion
        $script:State.ActiveGlob = $script:State.GlobalGlob
        return (& $script:originalSharedReady)
    }
    finally { $script:State.ActiveVersion = $previousVersion; $script:State.ActiveGlob = $previousGlob }
}
function Test-Path {
    param([string]$Path, [string]$LiteralPath, [string]$PathType)
    $target = if ($LiteralPath) { $LiteralPath } else { $Path }
    if ($target -eq (Join-Path $testRoot 'mise install/node.exe')) { return $script:State.Installed }
    return (Microsoft.PowerShell.Management\Test-Path -LiteralPath $target)
}
function mise {
    $script:Calls.Add("mise $($args -join ' ')")
    Assert ($env:MISE_NODE_COMPILE -eq 'false' -and $env:MISE_AUTO_INSTALL -eq 'false') 'mise was allowed compilation or automatic installation.'
    $global:LASTEXITCODE = 0
    switch ($args[0]) {
        'ls' {
            Assert (($args -join '|') -eq "ls|-C|$([IO.Path]::GetPathRoot($env:USERPROFILE))|--global|--json|node") 'Inventory was not isolated from HOME/project overrides.'
            $script:State.InventoryReads++
            if ($script:State.InventoryReads -eq $script:State.InventoryFailAt) { $global:LASTEXITCODE = 1; return }
            return $script:State.Inventory
        }
        { $_ -in 'use', 'install' } {
            Assert (($args -join '|') -match ([regex]::Escape("-C|$env:USERPROFILE|node@"))) 'Provisioning did not use HOME and an explicit install target.'
            if ($script:State.ProvisionFail) { $global:LASTEXITCODE = 1; return }
            if (-not $script:State.KeepInventory) {
                if ($args[0] -eq 'install') {
                    $resolvedVersion = if ($script:State.GlobalVersion -eq '22') { '22.22.0' } else { $script:State.GlobalVersion }
                    Set-Inventory -Version $resolvedVersion
                }
                else { Set-Inventory }
            }
            return 'noisy mise output must not pollute Boolean results'
        }
        'env' {
            Assert (($args -join '|') -eq "env|-C|$env:USERPROFILE|-s|pwsh") 'mise env forced a runtime instead of HOME resolution.'
            if ($script:State.EnvFail) { $global:LASTEXITCODE = 1; return }
            if ($script:State.EnvThrow) { return "throw 'fixture activation failed'" }
            return '$script:State.ActiveVersion = $script:State.EffectiveVersion; $script:State.ActiveGlob = $script:State.EffectiveGlob; "noisy activation"'
        }
        default { throw "Unexpected mise invocation: $args" }
    }
}
function npm {
    $script:Calls.Add("npm $($args -join ' ')")
    $global:LASTEXITCODE = 0
    if ($args[0] -eq '--version') { if ($script:State.NpmFail) { $global:LASTEXITCODE = 1 }; return '10.0.0' }
    $script:Mutations.Add("npm $($args -join ' ')")
    Assert $script:PiRuntimePreflightPassed 'npm mutation preceded runtime preflight.'
    if ($script:State.RepairFail -and $args[0] -eq 'config') { $global:LASTEXITCODE = 1 }
    if ($args[0] -eq 'install') {
        if ($script:State.NpmInstallFail) { $global:LASTEXITCODE = 1 }
        else { [IO.File]::WriteAllText((Join-Path $env:USERPROFILE '.local/pi.ps1'), '# canonical fixture npm shim') }
    }
    return 'noisy npm output'
}
function pi {
    Assert (($args -join ' ') -eq '--version') 'Fixture attempted a Pi/model request.'
    $global:LASTEXITCODE = 0
    if (-not $script:State.EmptyPiVersion) { return 'fixture-pi-version' }
}
function Remove-NonCanonicalPiInstalls { $script:Mutations.Add('Bun cleanup') }
function Remove-Item {
    param([string]$LiteralPath, [switch]$Force, $ErrorAction)
    $script:Mutations.Add("delete $LiteralPath")
    Assert $script:PiRuntimePreflightPassed 'Repair deletion preceded runtime preflight.'
    Assert ($LiteralPath.StartsWith($testRoot)) 'Deletion escaped the temporary home.'
    Microsoft.PowerShell.Management\Remove-Item -LiteralPath $LiteralPath -Force
}
function Invoke-SharedNodeShellProcess {
    param([Diagnostics.ProcessStartInfo]$StartInfo)
    $script:Children.Add($StartInfo)
    Assert ($StartInfo.FileName -eq $script:RealPowerShell) 'Fresh shell did not use the current PowerShell host.'
    Assert ($StartInfo.WorkingDirectory -eq $env:USERPROFILE) 'Fresh shell did not start at HOME.'
    Assert ($StartInfo.Arguments -notmatch '-NoProfile') 'Production verification skipped chezmoi activation.'
    $expectedPath = [SharedNodeFixtureEnvironment]::Persisted['Machine:Path'] + ';' + [SharedNodeFixtureEnvironment]::Persisted['User:Path']
    Assert ($StartInfo.EnvironmentVariables['PATH'] -eq $expectedPath) 'Fresh shell retained inherited runtime PATH or lost persisted PATH.'
    foreach ($name in @('__MISE_DIFF', '__MISE_ORIG_PATH', 'MISE_SHELL', 'MISE_NODE_VERSION', 'MISE_TOOL_OPTS__NODE', 'FNM_MULTISHELL_PATH', 'FNM_VERSION_FILE_STRATEGY', 'NODE_PATH', 'NODE_OPTIONS')) {
        Assert (-not $StartInfo.EnvironmentVariables.ContainsKey($name)) "Fresh shell retained transient $name."
    }
    Assert ($StartInfo.EnvironmentVariables['MISE_AUTO_INSTALL'] -eq 'false' -and $StartInfo.EnvironmentVariables['MISE_NODE_COMPILE'] -eq 'false') 'Fresh shell can download or compile a runtime.'
    $probe = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String(($StartInfo.Arguments -split ' ')[-1]))
    $childState = $script:State.Clone()
    $childState.ActiveVersion = $script:State.FreshVersion
    $childState.ActiveGlob = $script:State.FreshGlob
    $childState.ActiveIdentity = $script:State.FreshIdentity
    $state64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($childState | ConvertTo-Json -Compress)))
    $node64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($script:RealNode))
    $bootstrap = @'
$script:State = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__STATE__')) | ConvertFrom-Json
$script:RealNode = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__NODE__'))
function mise {
    if (($args -join '|') -ne "which|-C|$env:USERPROFILE|node") { throw 'Wrong child mise query' }
    $global:LASTEXITCODE = if ($script:State.WhichFail) { 1 } else { 0 }
    'mise-node'
}
function npm {
    if (($args -join ' ') -ne '--version') { throw 'Child tried npm mutation' }
    $global:LASTEXITCODE = if ($script:State.FreshNpmFail) { 1 } else { 0 }
}
function Get-Command {
    param($Name, $ErrorAction)
    if ($Name -eq 'mise') { if (-not $script:State.FreshMiseMissing) { 'fixture-mise' }; return }
    if ($Name -eq 'pi') {
        $path = if ($script:State.FreshPiShadow) { 'wrong-pi' } else { Join-Path $env:USERPROFILE '.local/pi.ps1' }
        return [pscustomobject]@{ Source = $path }
    }
    throw "Unexpected child command: $Name"
}
function pi {
    if (($args -join ' ') -ne '--version') { throw 'Child attempted a Pi/model request' }
    $global:LASTEXITCODE = if ($script:State.FreshPiFail) { 1 } else { 0 }
    if (-not $script:State.EmptyPiVersion) { 'fixture-pi-version' }
}
'@.Replace('__STATE__', $state64).Replace('__NODE__', $node64)
    # Test hygiene: only this fixture bootstrap replaces profile activation. The
    # production encoded probe and its sanitized environment execute unchanged.
    $StartInfo.Arguments = '-NoLogo -NoProfile -NonInteractive -EncodedCommand ' + [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes("$bootstrap`n$nodeMock`n$probe"))
    return (Invoke-FixtureProcess -StartInfo $StartInfo)
}
function Assert-Restored {
    Assert ($env:MISE_NODE_COMPILE -eq 'original-compile' -and $env:MISE_AUTO_INSTALL -eq 'original-auto') 'mise safety environment leaked from the helper.'
}
function Assert-NoProvision {
    Assert (@($script:Calls | Where-Object { $_ -match '^mise (use|install) ' }).Count -eq 0) 'Compatible or ambiguous global selection was rewritten.'
}

try {
    Reset-Fixture
    # Version/API bounds use the actual production JS, under simulated runtimes.
    foreach ($version in @('18.19.1', '20.6.0', '22.0.0', '22.18.0', '22.19.0', '22.20.0', '24.0.0', '26.0.0')) {
        $script:State.ActiveVersion = $version
        Assert-Boolean (Test-PiNodeRuntimeReady) ([version]$version -ge [version]'22.19.0') "Pi bound: $version"
        Assert-Boolean (Test-SkillsCliNodeRuntimeReady) ([version]$version -ge [version]'22.20.0') "Shared bound: $version"
    }
    $script:State.ActiveGlob = $false
    Assert-Boolean (Test-PiNodeRuntimeReady) $false 'Pi accepted missing globSync'
    Assert-Boolean (Test-SkillsCliNodeRuntimeReady) $false 'Shared runtime accepted missing globSync'
    Assert-Boolean (& $originalSharedReady -Node (Join-Path $testRoot 'missing-node.exe')) $false 'Missing Node accepted'

    foreach ($shape in @('array', 'old')) {
        Reset-Fixture
        if ($shape -eq 'old') { $script:State.Inventory = '{}' }
        Assert-Boolean (Enable-PiNodeRuntime) $true 'Inherited Node hid missing global selection'
        Assert ($script:State.InventoryReads -eq 2) 'Inventory was not re-read after provisioning.'
        Assert (@($script:Calls | Where-Object { $_ -match '^mise use ' }).Count -eq 1) 'Missing selection was not persisted once.'
        Assert-Restored
        if ($shape -eq 'old') { Set-Inventory -OldShape }
        $script:Calls.Clear()
        Assert-Boolean (Enable-SkillsCliNodeRuntime) $true 'Skills could not reuse shared runtime'
        Assert-NoProvision
        Assert-Restored
    }
    foreach ($version in @('22.20.0', '22.21.1', '24.0.0', '26.1.0')) {
        Reset-Fixture
        Set-Inventory -Version $version
        $script:State.EffectiveVersion = $version
        $script:State.FreshVersion = $version
        Assert-Boolean (Enable-SharedNodeRuntime) $true "Compatible global $version not preserved"
        Assert-NoProvision
    }
    Reset-Fixture
    Set-Inventory -Version '22.21.1' -Installed $false -OldShape
    $script:State.EffectiveVersion = '22.21.1'
    $script:State.FreshVersion = '22.21.1'
    Assert-Boolean (Enable-SharedNodeRuntime) $true 'Configured absent runtime failed'
    Assert (@($script:Calls | Where-Object { $_ -match '^mise install .*node@22\.21\.1$' }).Count -eq 1) 'Absent compatible selection was not installed without rewriting it.'
    Assert (@($script:Calls | Where-Object { $_ -match '^mise use ' }).Count -eq 0) 'Absent compatible selection was changed.'
    Reset-Fixture
    Set-Inventory -Version '22' -Installed $false
    Assert-Boolean (Enable-SharedNodeRuntime) $true 'Absent fuzzy Node 22 selection failed'
    Assert (@($script:Calls | Where-Object { $_ -match '^mise install .*node@22$' }).Count -eq 1) 'Absent fuzzy Node 22 selection was rewritten.'
    Assert ($script:State.InventoryReads -eq 2) 'Fuzzy Node 22 install was not re-inventoried.'
    foreach ($version in @('18.19.1', '22.19.0', '24.0.0')) {
        Reset-Fixture
        Set-Inventory -Version $version -Glob ($version -ne '24.0.0')
        Assert-Boolean (Enable-SharedNodeRuntime) $true "Incompatible installed $version was not replaced"
        Assert (@($script:Calls | Where-Object { $_ -match '^mise use .*node@24$' }).Count -eq 1) 'Incompatible runtime did not select official Node 24.'
    }
    foreach ($architecture in @('AMD64', 'ARM64', 'x86', 'ARM')) {
        Reset-Fixture
        $env:PROCESSOR_ARCHITECTURE = $architecture
        Assert ((Get-SharedNodeFallback) -eq $(if ($architecture -in @('AMD64', 'ARM64')) { 'node@24' } else { $null })) "Wrong Windows fallback for $architecture"
    }
    Reset-Fixture
    $env:PROCESSOR_ARCHITECTURE = 'x86'
    $env:PROCESSOR_ARCHITEW6432 = 'ARM64'
    Assert ((Get-SharedNodeFallback) -eq 'node@24') 'WOW64 ignored native architecture.'
    [SharedNodeFixtureEnvironment]::OSVersion = [OperatingSystem]::new([PlatformID]::Unix, [version]'1.0')
    Assert ($null -eq (Get-SharedNodeFallback)) 'Windows installer selected runtime on non-Windows.'

    # Every preflight failure reaches the real Install-PiCli call site, with old
    # Pi shims and preferences as sentinels. Mutators and registry storage are spies.
    $failures = @('inventory-error', 'reread-error', 'multiple', 'old-multiple', 'malformed', 'scalar', 'old-invalid', 'bad-row', 'null-row', 'empty-row', 'mise-missing', 'unsupported', 'download', 'not-installed', 'env-error', 'env-throw', 'home-conflict', 'effective-glob', 'npm', 'fresh-old', 'fresh-glob', 'fresh-system', 'fresh-mise', 'fresh-which', 'fresh-npm')
    foreach ($failure in $failures) {
        Reset-Fixture
        Set-Inventory
        $localPrefix = Join-Path $env:USERPROFILE '.local'
        New-Item -ItemType Directory -Force -Path $localPrefix | Out-Null
        $oldPi = Join-Path $localPrefix 'pi.ps1'
        [IO.File]::WriteAllText($oldPi, '# @mariozechner old Pi must remain')
        $preferences = Join-Path $env:USERPROFILE 'settings.json'
        [IO.File]::WriteAllText($preferences, '{"npmCommand":"keep","model":"keep"}')
        $homePin = Join-Path $env:USERPROFILE '.mise.toml'
        [IO.File]::WriteAllText($homePin, '[tools] node = "18"')
        switch ($failure) {
            'inventory-error' { $script:State.InventoryFailAt = 1 }
            'reread-error' { $script:State.Inventory = '[]'; $script:State.InventoryFailAt = 2 }
            'multiple' { $script:State.Inventory = '[{"version":"24.0.0"},{"version":"22.20.0"}]' }
            'old-multiple' { $script:State.Inventory = '{"node":[{"version":"24.0.0"},{"version":"22.20.0"}]}' }
            'malformed' { $script:State.Inventory = '{' }
            'scalar' { $script:State.Inventory = '42' }
            'old-invalid' { $script:State.Inventory = '{"node":{}}' }
            'bad-row' { $script:State.Inventory = '["node24"]' }
            'null-row' { $script:State.Inventory = '[null]' }
            'empty-row' { $script:State.Inventory = '[{}]' }
            'mise-missing' { $script:State.MiseMissing = $true }
            'unsupported' { $script:State.Inventory = '[]'; $env:PROCESSOR_ARCHITECTURE = 'x86' }
            'download' { $script:State.Inventory = '[]'; $script:State.ProvisionFail = $true }
            'not-installed' { $script:State.Inventory = '[]'; $script:State.KeepInventory = $true }
            'env-error' { $script:State.EnvFail = $true }
            'env-throw' { $script:State.EnvThrow = $true }
            'home-conflict' { $script:State.EffectiveVersion = '18.19.1' }
            'effective-glob' { $script:State.EffectiveGlob = $false }
            'npm' { $script:State.NpmFail = $true }
            'fresh-old' { $script:State.FreshVersion = '18.19.1' }
            'fresh-glob' { $script:State.FreshGlob = $false }
            'fresh-system' { $script:State.FreshIdentity = 'modern-system-node' }
            'fresh-mise' { $script:State.FreshMiseMissing = $true }
            'fresh-which' { $script:State.WhichFail = $true }
            'fresh-npm' { $script:State.FreshNpmFail = $true }
        }
        Assert-Boolean (Install-PiCli) $false "Preflight failure $failure did not stop Pi"
        Assert (-not $script:PiRuntimePreflightPassed) "Preflight flag passed on $failure."
        Assert ($script:Mutations.Count -eq 0) "Pi mutation after $failure`: $($script:Mutations -join ', ')"
        Assert ([SharedNodeFixtureEnvironment]::Writes.Count -eq 0) "Persisted environment changed before preflight: $failure"
        Assert ([IO.File]::ReadAllText($oldPi) -eq '# @mariozechner old Pi must remain') "Pi repair deleted the old shim after $failure."
        Assert ([IO.File]::ReadAllText($preferences) -eq '{"npmCommand":"keep","model":"keep"}') 'Pi preferences changed.'
        Assert ([IO.File]::ReadAllText($homePin) -eq '[tools] node = "18"') 'HOME override changed.'
        if ($failure -eq 'home-conflict') { Assert-NoProvision }
        Assert-Restored
    }

    Reset-Fixture
    Set-Inventory
    $env:MISE_NODE_COMPILE = $null
    $env:MISE_AUTO_INSTALL = $null
    Assert-Boolean (Enable-SharedNodeRuntime) $true 'Absent safety variables broke activation'
    Assert ($null -eq [Environment]::GetEnvironmentVariable('MISE_NODE_COMPILE') -and $null -eq [Environment]::GetEnvironmentVariable('MISE_AUTO_INSTALL')) 'Absent safety variables were not restored.'

    foreach ($failure in @('none', 'npm-install', 'fresh-pi', 'fresh-shadow', 'empty-version')) {
        Reset-Fixture
        Set-Inventory
        $script:State.NpmInstallFail = $failure -eq 'npm-install'
        $script:State.FreshPiFail = $failure -eq 'fresh-pi'
        $script:State.FreshPiShadow = $failure -eq 'fresh-shadow'
        $script:State.EmptyPiVersion = $failure -eq 'empty-version'
        Assert-Boolean (Install-PiCli) ($failure -eq 'none') "Post-install check: $failure"
        Assert $script:PiRuntimePreflightPassed 'Healthy preflight flag was lost on later install failure.'
        Assert (@($script:Mutations | Where-Object { $_ -match '^npm install -g --ignore-scripts --prefix .*@earendil-works/pi-coding-agent@latest$' }).Count -eq 1) 'Pi lost canonical npm installation.'
        if ($failure -in @('none', 'fresh-pi', 'fresh-shadow')) { Assert ($script:Children.Count -eq 2) 'Missing fresh canonical Pi check after install.' }
        Assert-Restored
    }

    # Execute only the main Pi if/else AST, never the setup function or entrypoint.
    $piBranch = $ast.FindAll({ param($node) $node -is [Management.Automation.Language.IfStatementAst] -and $node.Clauses[0].Item1.Extent.Text -eq 'Install-PiCli' }, $true)
    Assert ($piBranch.Count -eq 1) 'Cannot isolate the main Pi failure boundary.'
    foreach ($name in @('Set-PiDefaults', 'Remove-PiSyntheticModels', 'Seed-PiZaiModels', 'Remove-PiSubagents', 'Remove-PiRpivPackages', 'Setup-PiMcpAdapter', 'Setup-PiClaudeBridge', 'Setup-PiCompanionPackages', 'Setup-PiGoalAutoresearch')) {
        Set-Item -Path "function:$name" -Value ([scriptblock]::Create("`$script:Mutations.Add('$name')"))
    }
    function Test-EnvLocalFlag { return $true }
    Reset-Fixture
    $script:State.InventoryFailAt = 1
    . ([scriptblock]::Create($piBranch[0].Extent.Text))
    Assert ($script:Mutations.Count -eq 0) 'Main failure branch mutated Pi after failed runtime preflight.'
    Reset-Fixture
    Set-Inventory
    $script:State.RepairFail = $true
    . ([scriptblock]::Create($piBranch[0].Extent.Text))
    foreach ($name in @('Remove-PiSubagents', 'Remove-PiRpivPackages', 'Setup-PiMcpAdapter', 'Setup-PiGoalAutoresearch')) {
        Assert ($script:Mutations.Contains($name)) "Healthy-runtime migration failure lost legacy cleanup $name."
    }
    # Optional real mise inventory regression. Only `ls` runs, with every mise/XDG
    # location isolated. There are no installs, activation, plugins, or downloads.
    if ($realMise) {
        $nativeRoot = Join-Path $testRoot 'native mise'
        $nativeHome = Join-Path $nativeRoot 'home'
        $nativeConfig = Join-Path $nativeRoot 'config'
        New-Item -ItemType Directory -Force -Path $nativeHome, $nativeConfig | Out-Null
        $globalConfig = Join-Path $nativeConfig 'config.toml'
        $homeConfig = Join-Path $nativeHome '.mise.toml'
        [IO.File]::WriteAllText($globalConfig, "[tools]`nnode = '24.0.0'`n")
        [IO.File]::WriteAllText($homeConfig, "[tools]`nnode = '18.19.1'`n")
        $globalBefore = [IO.File]::ReadAllText($globalConfig)
        function Invoke-IsolatedMiseInventory([string]$Directory) {
            $info = [Diagnostics.ProcessStartInfo]::new()
            $info.FileName = $realMise
            $info.Arguments = 'ls -C "' + $Directory.Replace('\', '/') + '" --global --json node'
            $info.WorkingDirectory = $nativeHome
            $info.UseShellExecute = $false
            $info.RedirectStandardInput = $true
            $info.RedirectStandardOutput = $true
            $info.RedirectStandardError = $true
            foreach ($name in @($info.EnvironmentVariables.Keys)) {
                if ($name -match '^(MISE_|__MISE_|FNM_|XDG_|NODE_)') { $info.EnvironmentVariables.Remove($name) }
            }
            $info.EnvironmentVariables['HOME'] = $nativeHome
            $info.EnvironmentVariables['USERPROFILE'] = $nativeHome
            $info.EnvironmentVariables['PATH'] = ''
            foreach ($name in @('CONFIG', 'DATA', 'CACHE', 'STATE')) {
                $info.EnvironmentVariables["MISE_${name}_DIR"] = Join-Path $nativeRoot $name.ToLowerInvariant()
                $info.EnvironmentVariables["XDG_${name}_HOME"] = Join-Path $nativeRoot "xdg-$($name.ToLowerInvariant())"
            }
            $info.EnvironmentVariables['MISE_GLOBAL_CONFIG_FILE'] = $globalConfig
            $info.EnvironmentVariables['MISE_SYSTEM_CONFIG_FILE'] = Join-Path $nativeRoot 'absent-system.toml'
            $info.EnvironmentVariables['MISE_TRUSTED_CONFIG_PATHS'] = $nativeRoot
            $info.EnvironmentVariables['MISE_AUTO_INSTALL'] = 'false'
            $info.EnvironmentVariables['MISE_NODE_COMPILE'] = 'false'
            $info.EnvironmentVariables['MISE_OFFLINE'] = 'true'
            $process = [Diagnostics.Process]::new()
            $process.StartInfo = $info
            try {
                $null = $process.Start()
                $process.StandardInput.Close()
                $output = $process.StandardOutput.ReadToEndAsync()
                $errors = $process.StandardError.ReadToEndAsync()
                if (-not $process.WaitForExit(30000)) { $process.Kill(); $process.WaitForExit(); throw 'Isolated mise inventory timed out.' }
                $text = $output.GetAwaiter().GetResult()
                $errorText = $errors.GetAwaiter().GetResult()
                Assert ($process.ExitCode -eq 0) "Isolated mise inventory failed: $errorText"
                $parsedInventory = ConvertFrom-Json -InputObject ('{"rows":' + $text + '}')
                if ($parsedInventory.rows -is [Management.Automation.PSCustomObject]) { return $parsedInventory.rows.node }
                return $parsedInventory.rows
            }
            finally { $process.Dispose() }
        }
        $homeInventory = @(Invoke-IsolatedMiseInventory -Directory $nativeHome)
        $rootInventory = @(Invoke-IsolatedMiseInventory -Directory ([IO.Path]::GetPathRoot($nativeHome)))
        Assert ($homeInventory.Count -eq 0) 'Real mise no longer reproduces HOME override hiding the global row; review inventory assumptions.'
        Assert ($rootInventory.Count -eq 1 -and $rootInventory[0].version -eq '24.0.0') "Drive-root query did not preserve the real global Node selection: $($rootInventory | ConvertTo-Json -Depth 5 -Compress)"
        Assert ([IO.File]::ReadAllText($globalConfig) -eq $globalBefore) 'Real inventory query changed the global selection.'
        Assert ([IO.File]::ReadAllText($homeConfig) -eq "[tools]`nnode = '18.19.1'`n") 'Real inventory query changed the HOME override.'
        Write-Output 'Real mise inventory fixture passed with isolated HOME/global configuration.'
    }
    else { Write-Output 'Real mise inventory fixture skipped: mise is not installed.' }
    Assert ($script:AssertionFailures.Count -eq 0) "Setup swallowed a fixture assertion: $($script:AssertionFailures -join '; ')"
    Write-Output "Shared Node PowerShell fixtures passed ($script:Assertions assertions). No live profiles, setup, Pi, downloads, or registry writes."
}
finally {
    Microsoft.PowerShell.Management\Remove-Item -LiteralPath $testRoot -Recurse -Force
    foreach ($entry in @(Get-ChildItem Env:)) {
        if (-not $originalEnvironment.ContainsKey($entry.Name)) { Microsoft.PowerShell.Management\Remove-Item -LiteralPath "Env:$($entry.Name)" }
    }
    foreach ($name in $originalEnvironment.Keys) { [Environment]::SetEnvironmentVariable($name, $originalEnvironment[$name], 'Process') }
}
