# Version 9 | Last changed: Report bounded secret-safe evidence at real PATH discovery
function Test-OpenCodeCliAcl {
    param([string]$HomePath)
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $trusted = @($identity, 'S-1-5-18', 'S-1-5-32-544')
    $writeRights = [System.Security.AccessControl.FileSystemRights]'Write,Delete,DeleteSubdirectoriesAndFiles,ChangePermissions,TakeOwnership'
    $paths = @($HomePath, (Join-Path $HomePath '.local'), (Join-Path $HomePath '.local\bin'),
        (Join-Path $HomePath '.opencode'), (Join-Path $HomePath '.opencode\bin'),
        (Join-Path $HomePath '.bun'), (Join-Path $HomePath '.bun\bin'),
        (Join-Path $HomePath '.bun\install'), (Join-Path $HomePath '.bun\install\global'))
    foreach ($entry in ($env:PATH -split ';')) {
        if ($entry.StartsWith($HomePath + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
            foreach ($leaf in @('opencode', 'opencode.exe', 'opencode.cmd', 'opencode.ps1')) {
                if (Test-Path -LiteralPath (Join-Path $entry $leaf)) { $paths += $entry; break }
            }
        }
    }
    $commandPaths = @($paths)
    foreach ($directory in $commandPaths) {
        $paths += (Join-Path $directory 'node_modules')
        $paths += (Join-Path $directory 'node_modules\opencode-ai')
        $paths += (Join-Path $directory 'node_modules\opencode-ai\bin')
    }
    foreach ($candidate in $paths) {
        $current = $candidate
        while ($current.Length -ge $HomePath.Length) {
            if (Test-Path -LiteralPath $current) {
                $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
                if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { return $false }
                $acl = Get-Acl -LiteralPath $current -ErrorAction Stop
                if ($acl.GetOwner([System.Security.Principal.SecurityIdentifier]).Value -ne $identity) { return $false }
                foreach ($rule in $acl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier])) {
                    if ($rule.AccessControlType -eq 'Allow' -and $trusted -notcontains $rule.IdentityReference.Value -and
                        ($rule.FileSystemRights -band $writeRights)) { return $false }
                }
                if ($item.PSIsContainer) {
                    foreach ($leaf in @('opencode', 'opencode.exe', 'opencode.cmd', 'opencode.ps1', '.setup-opencode-cli.json', 'package.json')) {
                        $file = Join-Path $current $leaf
                        if (Test-Path -LiteralPath $file) {
                            $entry = Get-Item -LiteralPath $file -Force -ErrorAction Stop
                            if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) { return $false }
                            $fileAcl = Get-Acl -LiteralPath $file -ErrorAction Stop
                            if ($fileAcl.GetOwner([System.Security.Principal.SecurityIdentifier]).Value -ne $identity) { return $false }
                            foreach ($rule in $fileAcl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier])) {
                                if ($rule.AccessControlType -eq 'Allow' -and $trusted -notcontains $rule.IdentityReference.Value -and
                                    ($rule.FileSystemRights -band $writeRights)) { return $false }
                            }
                        }
                    }
                }
            }
            if ($current -eq $HomePath) { break }
            $current = Split-Path -Parent $current
        }
    }
    return $true
}

# One private pipe exchange keeps the existing Node transaction/rollback live
# while this PowerShell session performs authoritative command discovery. No
# installer files, second transaction, shell repair or application invocation.
function Invoke-OpenCodeCliCore {
    param([string]$NodePath, [string]$Code)
    $bootstrap = @'
const rl = require('node:readline').createInterface({input: process.stdin, crlfDelay: Infinity});
rl.once('line', source => {
    try { eval(Buffer.from(source, 'base64').toString('utf8')); }
    catch { console.log('opencode-cli:failed'); process.exitCode = 1; rl.close(); process.stdin.destroy(); return; }
    const api = module.exports;
    api.install({verifySessionSelection: expected => new Promise(resolve => {
        const finish = value => { clearTimeout(timer); rl.removeListener('line', reply); rl.removeListener('close', closed); resolve(value); };
        const reply = line => finish(line === 'verified' ? true : line === 'refused' ? false : undefined);
        const closed = () => finish(undefined);
        const timer = setTimeout(closed, 20000);
        rl.once('line', reply); rl.once('close', closed);
        console.log('opencode-cli:verify-selection:' + Buffer.from(expected).toString('base64'));
    })}).then(result => console.log('opencode-cli:' + result)).catch(error => {
        console.log(api.failureResult(error)); process.exitCode = 1;
    }).finally(() => { rl.close(); process.stdin.destroy(); });
});
'@
    $process = New-Object System.Diagnostics.Process
    $started = $false
    try {
        $process.StartInfo.FileName = $NodePath
        # Compatible with Windows PowerShell 5.1 (no ArgumentList property).
        $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($bootstrap))
        $process.StartInfo.Arguments = '-e "eval(Buffer.from(''' + $encoded + ''',''base64'').toString(''utf8''))"'
        $process.StartInfo.UseShellExecute = $false
        $process.StartInfo.CreateNoWindow = $true
        $process.StartInfo.RedirectStandardInput = $true
        $process.StartInfo.RedirectStandardOutput = $true
        $process.StartInfo.RedirectStandardError = $true
        $started = $process.Start()
        if (-not $started) { throw 'start' }
        $discard = $process.StandardError.BaseStream.CopyToAsync([IO.Stream]::Null)
        $process.StandardInput.WriteLine([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Code)))
        $process.StandardInput.Flush()
        $output = @(); $requested = $false; $verified = $false
        while ($true) {
            $read = $process.StandardOutput.ReadLineAsync()
            if (-not $read.Wait(600000)) { throw 'timeout' }
            $line = $read.Result
            if ($null -eq $line) { break }
            if ($line.Length -gt 4096) { throw 'output' }
            if ($line -cmatch '\Aopencode-cli:verify-selection:([A-Za-z0-9+/]+={0,2})\z') {
                if ($requested -or $output.Count) { throw 'protocol' }
                $requested = $true
                $expected = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Matches[1]))
                $allowed = @('.local/bin/opencode.exe', '.opencode/bin/opencode.exe', '.bun/bin/opencode.exe') |
                    ForEach-Object { Join-Path $env:USERPROFILE $_ }
                if ($expected -notin $allowed) { throw 'selection' }
                try {
                    $selected = Get-Command opencode -ErrorAction Stop
                    $verified = $selected -and $selected.CommandType -eq 'Application' -and $selected.Source -eq $expected
                } catch { $verified = $false }
                $process.StandardInput.WriteLine($(if ($verified) { 'verified' } else { 'refused' }))
                $process.StandardInput.Flush()
            } else {
                $output += $line
                if ($output.Count -gt 1) { throw 'output' }
            }
        }
        if (-not $process.WaitForExit(25000)) { throw 'exit' }
        if ($process.ExitCode -eq 0 -and -not $verified -and $output[0] -cne 'opencode-cli:unsupported') { throw 'selection' }
        return @{ Status = $process.ExitCode; Output = $output }
    } catch {
        # EOF rejects a pending approval so the core can restore commands itself.
        # Never attempt a second, less-informed rollback or print process output.
        if ($started) {
            try { $process.StandardInput.Close() } catch { }
            if (-not $process.WaitForExit(25000)) { $process.Kill(); $process.WaitForExit() }
        }
        return @{ Status = 1; Output = @('opencode-cli:recovery-required:failed') }
    } finally { $process.Dispose() }
}

function Install-OpenCodeCli {
    $saved = @{}
    $operation = 'prerequisites'; $reason = 'unverified'
    foreach ($name in @('NODE_OPTIONS', 'NODE_PATH', 'SETUP_OPENCODE_ACL_VERIFIED', 'SETUP_OPENCODE_SHELL', 'SETUP_OPENCODE_FRESH_PATH', 'SETUP_OPENCODE_HASHED')) {
        $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
    }
    try {
        $machine = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
        if ($machine -notin @('AMD64', 'ARM64')) {
            Write-Warning 'OpenCode CLI: unsupported architecture; skipping without source builds.'
            return $true
        }
        $operation = 'setup-selection'; $reason = 'command-conflict'
        $resolved = Get-Command opencode -ErrorAction SilentlyContinue
        if ($resolved -and $resolved.CommandType -notin @('Application', 'ExternalScript')) { throw 'command-conflict' }
        $operation = 'filesystem-preflight'; $reason = 'windows-acl'
        if (-not (Test-OpenCodeCliAcl $env:USERPROFILE)) { throw 'unsafe-path' }
        $operation = 'prerequisites'; $reason = 'unverified'
        $node = Get-Command node -CommandType Application -ErrorAction Stop
        $env:NODE_OPTIONS = $null
        $env:NODE_PATH = $null
        $env:SETUP_OPENCODE_ACL_VERIFIED = '1'
        $env:SETUP_OPENCODE_HASHED = $null
        $env:SETUP_OPENCODE_SHELL = Join-Path $PSHOME $(if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh.exe' } else { 'powershell.exe' })
        $persistedPath = @([Environment]::GetEnvironmentVariable('Path', 'Machine'),
            [Environment]::GetEnvironmentVariable('Path', 'User')) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        $savedPath = $env:PATH
        try {
            $env:PATH = ''
            $env:SETUP_OPENCODE_FRESH_PATH = [Environment]::ExpandEnvironmentVariables(($persistedPath -join ';'))
        } finally { $env:PATH = $savedPath }
        & $node.Source -e 'require("node:https"); require("node:zlib"); require("node:crypto"); if (Number(process.versions.node.split(".")[0]) < 22) process.exit(1)' 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'prerequisite' }
        $code = @'
// @OPENCODE_CORE@
'@
        $operation = 'installation'; $reason = 'unrecognized-result'
        $run = Invoke-OpenCodeCliCore -NodePath $node.Source -Code $code
        $output = @($run.Output)
        if ($run.Status -ne 0 -or $output.Count -ne 1) {
            $recovery = $false
            if ($output.Count -eq 1 -and $output[0] -cin @('opencode-cli:recovery-required', 'opencode-cli:recovery-required:failed')) {
                $recovery = $true
            } elseif ($run.Status -ne 0 -and $output.Count -eq 1 -and
                $output[0] -cmatch '\Aopencode-cli:(?:recovery-required:)?download-failed:(latest-release|package-index|package-version|artifact-download|download):http-([1-5][0-9][0-9]|unknown)\z') {
                $recovery = $output[0].StartsWith('opencode-cli:recovery-required:')
                Write-Warning "OpenCode CLI download failed (operation=$($Matches[1]), HTTP=$($Matches[2]))."
            } elseif ($run.Status -ne 0 -and $output.Count -eq 1 -and
                $output[0] -cmatch '\Aopencode-cli:(?:recovery-required:)?policy-failed:installation:relative-path:command-discovery:([1-9][0-9]{0,5}):(empty|relative)\z') {
                $recovery = $output[0].StartsWith('opencode-cli:recovery-required:')
                Write-Warning "OpenCode CLI blocked (operation=installation, reason=relative-path, boundary=command-discovery, component=$($Matches[1]), kind=$($Matches[2]))."
            } elseif ($run.Status -ne 0 -and $output.Count -eq 1 -and
                $output[0] -cmatch '\Aopencode-cli:(?:recovery-required:)?policy-failed:(homebrew-preflight|installation|setup-selection|fresh-shell-selection):(archive|archive-header|archive-path|archive-tail|archive-truncated|archive-type|artifact-identity|artifact-metadata|brew-command|brew-origin|brew-path|brew-snapshot-changed|changed-copy|changed-receipt|custom-link|custom-prefix|custom-wrapper|duplicate-metadata|integrity|libc|metadata|missing-binary|outside-home|package-conflict|pinned|receipt|recovery-occupied|relative-path|release-metadata|shadowed|shadowed-newer|unreachable|unsafe-file|unsafe-path|unverified-copy|url|version|version-probe|windows-acl|foreign-command|command-conflict|selection-unverified|native-(EACCES|EPERM|ENOENT|EIO|EEXIST|ENOTDIR|ELOOP|ENOSPC|EROFS|ETIMEDOUT|ENOBUFS))\z') {
                $recovery = $output[0].StartsWith('opencode-cli:recovery-required:')
                Write-Warning "OpenCode CLI blocked (operation=$($Matches[1]), reason=$($Matches[2]))."
                Write-Warning 'Inspect the identified command and filesystem evidence; preserve conflicts and recovery artifacts. Do not change unrelated permissions.'
            } else {
                Write-Warning 'OpenCode CLI unverified (operation=installation, reason=unrecognized-result).'
            }
            if ($recovery) {
                Write-Warning 'OpenCode CLI rollback needs manual recovery; preserve .setup-opencode-* directories, .opencode-setup-recovery-* commands and the lock. Inspect recovery.json before restoring identified commands.'
            }
            $operation = $null
            throw 'installation'
        }
        switch -Exact ($output[0]) {
            'opencode-cli:installed' { Write-Success 'OpenCode CLI stable v2 installation/version verified.' }
            'opencode-cli:current' { Write-Success 'OpenCode CLI stable v2 installation/version verified.' }
            'opencode-cli:migrated' { Write-Success 'OpenCode CLI native command migrated; legacy stores and command backups retained.' }
            'opencode-cli:newer' { Write-Warning 'OpenCode CLI: newer official release preserved; no downgrade or migration performed.' }
            'opencode-cli:unsupported' { Write-Warning 'OpenCode CLI: unsupported architecture; skipping without source builds.' }
            default { throw 'unexpected-result' }
        }
        return $true
    } catch {
        if ($operation -eq 'installation') {
            Write-Warning 'OpenCode CLI unverified (operation=installation, reason=unrecognized-result).'
        } elseif ($operation) { Write-Warning "OpenCode CLI blocked (operation=$operation, reason=$reason)." }
        Write-Warning 'OpenCode CLI installation incomplete; existing data preserved. Review ownership, pins, metadata, prerequisites and PATH.'
        return $false
    } finally {
        foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process') }
    }
}
