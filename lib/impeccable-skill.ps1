function Invoke-ImpeccableSkillPolicy {
    param([string]$Mode, [string]$Stage = '')
    if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
        Write-Warning 'Impeccable: shared-runtime-unavailable.'
        return $false
    }
    $code = @'
@IMPECCABLE_CORE@
'@
    $savedOptions = $env:NODE_OPTIONS
    $savedPath = $env:NODE_PATH
    try {
        $env:NODE_OPTIONS = $null; $env:NODE_PATH = $null
        $blocked = if ($script:PiProfileMutationsBlocked) { '1' } else { '0' }
        $output = @($code | & node --input-type=commonjs - $env:USERPROFILE "$env:PI_CODING_AGENT_DIR" $blocked $Mode $Stage 2>$null)
        if ($LASTEXITCODE -ne 0) {
            Write-Warning 'Impeccable: policy-failed.'
            return $false
        }
        if ($Mode -eq 'stage') {
            if ($output.Count -ne 1 -or [string]::IsNullOrWhiteSpace($output[0])) { return $false }
            return [string]$output[0]
        }
        if ($output.Count -ne 0) { return $false }
        return $true
    } catch {
        Write-Warning 'Impeccable: policy-failed.'
        return $false
    } finally {
        $env:NODE_OPTIONS = $savedOptions; $env:NODE_PATH = $savedPath
    }
}

function Invoke-ImpeccableConvergence {
    if ($env:BAN_IMPECCABLE -ceq '1') { return (Invoke-ImpeccableSkillPolicy -Mode remove) }
    if (-not (Enable-SkillsCliNodeRuntime) -or -not (Get-Command npx -ErrorAction SilentlyContinue)) {
        Write-Warning 'Impeccable: installer-runtime-unavailable.'
        return $false
    }
    if (-not (Invoke-ImpeccableSkillPolicy -Mode preflight)) { return $false }
    $stage = $null
    $success = $false
    $operation = 'npm-configuration'
    $location = (Get-Location).Path
    $comparer = if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) { [StringComparer]::OrdinalIgnoreCase } else { [StringComparer]::Ordinal }
    $saved = [System.Collections.Generic.Dictionary[string,object]]::new($comparer)
    try {
        $global:LASTEXITCODE = 0
        $userconfig = & npm config get userconfig 2>$null
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($userconfig)) { throw 'npm-config' }
        $globalconfig = & npm config get globalconfig 2>$null
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($globalconfig)) { throw 'npm-config' }
        $operation = 'staging'
        $stage = Invoke-ImpeccableSkillPolicy -Mode stage
        if (-not ($stage -is [string]) -or [string]::IsNullOrWhiteSpace($stage)) { $stage = $null; throw 'stage' }
        $isolated = @{
            HOME = $stage; USERPROFILE = $stage
            CLAUDE_CONFIG_DIR = (Join-Path $stage '.claude'); CODEX_HOME = (Join-Path $stage '.codex')
            PI_CODING_AGENT_DIR = (Join-Path $stage '.pi/agent')
            XDG_STATE_HOME = (Join-Path $stage '.state'); XDG_CONFIG_HOME = (Join-Path $stage '.config')
            XDG_CACHE_HOME = (Join-Path $stage '.cache'); XDG_DATA_HOME = (Join-Path $stage '.local/share')
            APPDATA = (Join-Path $stage '.appdata'); LOCALAPPDATA = (Join-Path $stage '.localappdata')
            IMPECCABLE_HOME = (Join-Path $stage '.impeccable')
            TMPDIR = (Join-Path $stage '.tmp'); TMP = (Join-Path $stage '.tmp'); TEMP = (Join-Path $stage '.tmp')
            npm_config_userconfig = [string]$userconfig; npm_config_globalconfig = [string]$globalconfig
            NODE_OPTIONS = $null; NODE_PATH = $null; IMPECCABLE_BIN = $null; IMPECCABLE_BUNDLE_PATH = $null
            IMPECCABLE_DOWNLOAD_BASE = $null; IMPECCABLE_SKILL_DIR = $null; IMPECCABLE_SELF = $null; IMPECCABLE_LAUNCHER_PROBE = $null
        }
        if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
            foreach ($key in @('NPM_CONFIG_USERCONFIG', 'NPM_CONFIG_GLOBALCONFIG')) {
                $saved[$key] = [Environment]::GetEnvironmentVariable($key)
                [Environment]::SetEnvironmentVariable($key, [NullString]::Value)
            }
        }
        $operation = 'environment-isolation'
        foreach ($key in $isolated.Keys) {
            $saved[$key] = [Environment]::GetEnvironmentVariable($key)
            [Environment]::SetEnvironmentVariable($key, $(if ($null -eq $isolated[$key]) { [NullString]::Value } else { $isolated[$key] }))
        }
        Set-Location -LiteralPath $stage
        Write-Message 'Installing/updating official global Impeccable skills without hooks...'
        $operation = 'installer'
        $global:LASTEXITCODE = 0
        $npxArgs = @('--yes', 'impeccable@latest', 'install', '--yes', '--scope=global', '--providers=claude,codex,cursor,gemini,pi', '--no-hooks')
        & npx @npxArgs 2>$null | Out-Null
        $status = $LASTEXITCODE
        Set-Location -LiteralPath $location
        foreach ($key in $saved.Keys) {
            [Environment]::SetEnvironmentVariable($key, $(if ($null -eq $saved[$key]) { [NullString]::Value } else { $saved[$key] }))
        }
        $saved.Clear()
        if ($status -ne 0) { throw 'installer' }
        if (Invoke-ImpeccableSkillPolicy -Mode promote -Stage $stage) { $success = $true }
    } catch {
        Write-Warning "Impeccable: $operation-failed."
    } finally {
        Set-Location -LiteralPath $location
        foreach ($key in $saved.Keys) {
            [Environment]::SetEnvironmentVariable($key, $(if ($null -eq $saved[$key]) { [NullString]::Value } else { $saved[$key] }))
        }
        if ($stage -and -not (Invoke-ImpeccableSkillPolicy -Mode dispose -Stage $stage)) { $success = $false }
    }
    if ($success) { Write-Success 'Impeccable global payload and Pi discovery input verified; hooks unchanged.' }
    return $success
}
