# Version 1 | Last changed: Separate ordinary setup from explicit maintenance
$script:SetupMaintenanceAuthorized = $false
$script:SetupPolicyReady = $false
$script:SetupPolicyFailed = $false
$script:SetupPolicyDeferred = $false

function Initialize-SetupPolicy {
    param([switch]$Maintenance)
    $script:SetupMaintenanceAuthorized = $false
    $script:SetupPolicyReady = $false
    $script:SetupPolicyFailed = $false
    $script:SetupPolicyDeferred = $false
    if ($Maintenance) {
        if ($env:BB_THREAD_ID -or $env:BB_ENVIRONMENT_ID -or $env:BB_TERMINAL_ID) {
            throw 'Maintenance refused in a BB session. Use a separate non-BB terminal.'
        }
        $script:SetupMaintenanceAuthorized = $true
    }
    $script:SetupPolicyReady = $true
}

function Write-SetupDeferred {
    param([string]$Operation, [string]$Dependencies = 'Update availability was not checked.')
    $script:SetupPolicyDeferred = $true
    Write-Message "Deferred: $Operation; maintenance required to preserve ongoing work. $Dependencies"
}

function Assert-SetupMaintenance {
    param([string]$Operation)
    if (-not ($script:SetupPolicyReady -and $script:SetupMaintenanceAuthorized)) {
        Write-SetupDeferred $Operation
        throw 'Setup operation deferred (maintenance required); readiness not established.'
    }
}

function ConvertFrom-SetupEnvironmentValue {
    param([string]$Value)
    if ($Value.StartsWith('"') -or $Value.StartsWith("'")) {
        $quote = $Value[0]
        $end = $Value.IndexOf($quote, 1)
        if ($end -lt 0) { throw 'Unsupported environment-file value' }
        $suffix = $Value.Substring($end + 1)
        if ($suffix -and ($suffix -notmatch '^\s' -or ($suffix.Trim() -and -not $suffix.Trim().StartsWith('#')))) {
            throw 'Unsupported environment-file value'
        }
        return $Value.Substring(1, $end - 1)
    }
    $Value = ($Value -replace '(^|\s)#.*$', '').Trim()
    if ($Value -match '[\s''"]') { throw 'Unsupported environment-file value' }
    # Backslashes and command-looking text are literal data, never evaluated.
    return $Value
}

function Read-SetupEnvironment {
    $file = Join-Path $env:USERPROFILE '.env.local'
    if (-not [IO.File]::Exists($file) -and -not [IO.Directory]::Exists($file)) { return }
    if ([IO.File]::GetAttributes($file) -band ([IO.FileAttributes]::ReparsePoint -bor [IO.FileAttributes]::Directory)) {
        throw 'Unsafe environment-file boundary'
    }
    $keys = @('HEADLESS','HEADLESS_PASSWORDLESS_SUDO','BB_SERVER','BB_DATA_DIR','BB_APP_NPM_PREFIX','WORK_MACHINE','MACHINE_TYPE',
        'BAN_PI_MCP_ADAPTER','BAN_PI_GOAL_AUTORESEARCH','BAN_MATT_POCOCK_SKILLS','BAN_MATT_POCKOCK_SKILLS',
        'GH_TOKEN','GH_TOKEN_SCOWALT','OP_SERVICE_ACCOUNT_TOKEN','ZAI_API_KEY','OPENCODE_GO_API_KEY',
        'CLAUDE_CONFIG_DIR','CODEX_HOME','PI_CODING_AGENT_DIR')
    foreach ($line in [IO.File]::ReadAllLines($file)) {
        $clean = $line.Trim()
        if (-not $clean -or $clean.StartsWith('#')) { continue }
        $clean = $clean -replace '^export ', ''
        if (-not $clean.Contains('=')) { throw 'Unsupported environment-file statement' }
        $parts = $clean.Split(@('='), 2)
        $key = $parts[0].Trim()
        if ($key -cnotmatch '^[A-Za-z_][A-Za-z_0-9]*$') { throw 'Unsupported environment-file key' }
        if ($keys -cnotcontains $key) { continue }
        $value = ConvertFrom-SetupEnvironmentValue $parts[1].Trim()
        # Windows retains its exact-1 OR policy across process and file flags.
        if ($key -eq 'HEADLESS' -and $env:HEADLESS -eq '1') { continue }
        [Environment]::SetEnvironmentVariable($key, $value, 'Process')
    }
}

function Assert-SetupSafeDirectory {
    param([string]$Path)
    $homePath = [IO.Path]::GetFullPath($env:USERPROFILE)
    $full = [IO.Path]::GetFullPath($Path)
    if (-not $full.StartsWith($homePath + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Unmanaged safe-directory target'
    }
    $ancestors = @()
    for ($ancestor = $homePath; $ancestor; $ancestor = [IO.Path]::GetDirectoryName($ancestor)) {
        $ancestors = @($ancestor) + $ancestors
    }
    foreach ($ancestor in $ancestors) {
        if ([IO.File]::GetAttributes($ancestor) -band [IO.FileAttributes]::ReparsePoint) {
            throw 'Linked account HOME ancestor'
        }
    }
    # Parent-before-descendant checks; never traverse a reparse point or change
    # an existing object's attributes/ACL just to make creation eligible.
    $chain = @($homePath)
    $relative = $full.Substring($homePath.Length + 1)
    $cursor = $homePath
    foreach ($part in $relative.Split([IO.Path]::DirectorySeparatorChar)) {
        $cursor = Join-Path $cursor $part
        $chain += $cursor
    }
    foreach ($directory in $chain) {
        try { $attributes = [IO.File]::GetAttributes($directory) }
        catch {
            $cause = $_.Exception.GetBaseException()
            if ($cause -isnot [IO.FileNotFoundException] -and $cause -isnot [IO.DirectoryNotFoundException]) { throw }
            if ($directory -eq $homePath) { throw 'Missing account HOME' }
            # CreateDirectory never replaces an existing file; recheck any race.
            [IO.Directory]::CreateDirectory($directory) | Out-Null
            $attributes = [IO.File]::GetAttributes($directory)
        }
        if (($attributes -band [IO.FileAttributes]::ReparsePoint) -or
            -not ($attributes -band [IO.FileAttributes]::Directory)) { throw 'Unsafe directory boundary' }
        if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
            $acl = Get-Acl -LiteralPath $directory -ErrorAction Stop
            $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
            if ($acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -ne $sid) { throw 'Foreign directory owner' }
            foreach ($rule in $acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier])) {
                if ($rule.AccessControlType -eq 'Allow' -and
                    $rule.IdentityReference.Value -notin @($sid, 'S-1-5-18', 'S-1-5-32-544') -and
                    ($rule.FileSystemRights -band ([Security.AccessControl.FileSystemRights]::Write -bor
                        [Security.AccessControl.FileSystemRights]::Delete -bor
                        [Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles -bor
                        [Security.AccessControl.FileSystemRights]::ChangePermissions -bor
                        [Security.AccessControl.FileSystemRights]::TakeOwnership))) {
                    throw 'Shared directory write permission'
                }
            }
        }
    }
}

function Invoke-SetupSafeTasks {
    Assert-HeadlessUnsupported
    try { Read-SetupEnvironment }
    catch { $script:SetupPolicyFailed = $true; Write-Error 'Failed: environment-file inspection. File preserved.' }
    Write-Section 'Non-disruptive setup'
    Write-SetupDeferred 'system packages, WinGet/Windows updates and bootstrap' 'Dependent tool installations are deferred; update availability was not checked.'
    Write-SetupDeferred 'network, security and service configuration'
    # Get-Service is observation only. Do not call app CLIs or repair a stopped service.
    try {
        foreach ($name in @('Tailscale','sshd')) {
            $services = @(Get-Service -Name $name -ErrorAction SilentlyContinue -ErrorVariable serviceError)
            if ($serviceError -and $serviceError[0].FullyQualifiedErrorId -notlike 'NoServiceFoundForGivenName*') {
                throw 'Service inspection unavailable'
            }
            foreach ($service in $services) {
                if ($service.StartType -eq 'Automatic' -and $service.Status -ne 'Running') {
                    $script:SetupPolicyFailed = $true
                    Write-Error "Failed: configured service health ($name); no restart attempted."
                }
                elseif ($service.Status -eq 'Running') {
                    Write-Success "Verified current: $name service is running (not update freshness)."
                }
            }
        }
    }
    catch { $script:SetupPolicyFailed = $true; Write-Error 'Failed: service health inspection; no repair attempted.' }
    Write-SetupDeferred 'dotfiles init/update/apply, token migration and credential bootstrap' 'Dependent shell activation/repair is deferred.'
    Write-SetupDeferred 'shared runtimes, npm policy and runtime-dependent tools' 'Pi/skills and targeted dotfile repairs are deferred.'
    Write-Message 'BB native Windows is unsupported; existing state is unchanged. WSL2 enrollment remains manual.'
    Write-SetupDeferred 'agent executables, Pi profiles/auth/packages, skills and retirements'
    Write-SetupDeferred 'terminal settings, user PATH, shell changes and new automatic updaters' 'Existing independent updater policy remains unchanged.'
    if ($env:USERNAME -eq 'scowalt') {
        try {
            $code = Join-Path $env:USERPROFILE 'Code'
            $existed = [IO.Directory]::Exists($code)
            Assert-SetupSafeDirectory $code
            if ($existed) { Write-Success 'Verified current: Code directory exists; contents unchanged.' }
            else { Write-Success 'Applied: missing Code directory created; existing files unchanged.' }
        }
        catch { $script:SetupPolicyFailed = $true; Write-Error 'Failed: Code directory safety/creation; no repair attempted.' }
    }
    Test-PendingReboot
}

function Complete-SetupPolicy {
    if ($script:SetupPolicyFailed) {
        if ($script:SetupPolicyDeferred) { Write-Warning 'Maintenance pending; deferred changes are not verified current.' }
        throw 'Setup completed with errors; required work/inspection failed.'
    }
    if ($script:SetupPolicyDeferred) {
        Write-Success 'Safe work completed; maintenance pending.'
        Write-Warning 'Freshness, including security updates, may be delayed. Run -Maintenance from a separate non-BB terminal.'
    }
}
