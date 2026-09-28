# Version 1 | Last changed: Install verified stable OpenCode v2 native commands
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

function Install-OpenCodeCli {
    $saved = @{}
    foreach ($name in @('NODE_OPTIONS', 'NODE_PATH', 'SETUP_OPENCODE_ACL_VERIFIED')) {
        $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
    }
    try {
        $machine = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
        if ($machine -notin @('AMD64', 'ARM64')) {
            Write-Warning 'OpenCode CLI: unsupported architecture; skipping without source builds.'
            return $true
        }
        $resolved = Get-Command opencode -ErrorAction SilentlyContinue
        if ($resolved -and $resolved.CommandType -notin @('Application', 'ExternalScript')) { throw 'command-conflict' }
        if (-not (Test-OpenCodeCliAcl $env:USERPROFILE)) { throw 'unsafe-path' }
        $node = Get-Command node -CommandType Application -ErrorAction Stop
        $env:NODE_OPTIONS = $null
        $env:NODE_PATH = $null
        $env:SETUP_OPENCODE_ACL_VERIFIED = '1'
        & $node.Source -e 'require("node:https"); require("node:zlib"); require("node:crypto"); if (Number(process.versions.node.split(".")[0]) < 22) process.exit(1)' 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'prerequisite' }
        $code = @'
// @OPENCODE_CORE@
'@
        $output = @($code | & $node.Source - 2>$null)
        if ($LASTEXITCODE -ne 0 -or $output.Count -ne 1) {
            if ($output.Count -eq 1 -and $output[0] -ceq 'opencode-cli:recovery-required') {
                Write-Warning 'OpenCode CLI rollback needs manual recovery; preserve .setup-opencode-* backups, recovery.json and the lock. See README.'
            }
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
        Write-Warning 'OpenCode CLI installation incomplete; existing data preserved. Review ownership, pins, metadata, prerequisites and PATH.'
        return $false
    } finally {
        foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process') }
    }
}
