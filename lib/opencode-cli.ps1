# Version 6 | Last changed: Verify account-local OpenCode command selection
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
        $output = @($code | & $node.Source - 2>$null)
        if ($LASTEXITCODE -ne 0 -or $output.Count -ne 1) {
            $recovery = $false
            if ($output.Count -eq 1 -and $output[0] -cin @('opencode-cli:recovery-required', 'opencode-cli:recovery-required:failed')) {
                $recovery = $true
            } elseif ($LASTEXITCODE -ne 0 -and $output.Count -eq 1 -and
                $output[0] -cmatch '\Aopencode-cli:(?:recovery-required:)?download-failed:(latest-release|package-index|package-version|artifact-download|download):http-([1-5][0-9][0-9]|unknown)\z') {
                $recovery = $output[0].StartsWith('opencode-cli:recovery-required:')
                Write-Warning "OpenCode CLI download failed (operation=$($Matches[1]), HTTP=$($Matches[2]))."
            } elseif ($LASTEXITCODE -ne 0 -and $output.Count -eq 1 -and
                $output[0] -cmatch '\Aopencode-cli:(?:recovery-required:)?policy-failed:(homebrew-preflight|installation|setup-selection|fresh-shell-selection):(archive|archive-header|archive-path|archive-tail|archive-truncated|archive-type|artifact-identity|artifact-metadata|brew-command|brew-origin|brew-path|brew-readiness|brew-snapshot-changed|changed-copy|changed-receipt|custom-link|custom-prefix|custom-wrapper|duplicate-metadata|integrity|libc|metadata|missing-binary|outside-home|package-conflict|pinned|receipt|recovery-occupied|relative-path|release-metadata|shadowed|shadowed-newer|unreachable|unsafe-file|unsafe-path|unverified-copy|url|version|version-probe|windows-acl|foreign-command|command-conflict|selection-unverified|native-(EACCES|EPERM|ENOENT|EIO|EEXIST|ENOTDIR|ELOOP|ENOSPC|EROFS|ETIMEDOUT|ENOBUFS))\z') {
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
        if ($output[0] -cin @('opencode-cli:installed', 'opencode-cli:current', 'opencode-cli:migrated', 'opencode-cli:newer')) {
            $operation = 'setup-selection'; $reason = 'command-conflict'
            $selected = Get-Command opencode -ErrorAction Stop
            $expected = @((Join-Path $env:USERPROFILE '.local/bin/opencode.exe'))
            if ($output[0] -ceq 'opencode-cli:newer') {
                $expected += (Join-Path $env:USERPROFILE '.opencode/bin/opencode.exe')
                $expected += (Join-Path $env:USERPROFILE '.bun/bin/opencode.exe')
            }
            if (-not $selected -or $selected.CommandType -ne 'Application' -or $selected.Source -notin $expected) { throw 'selection' }
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
