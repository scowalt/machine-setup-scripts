function Write-ImpeccableFailure {
    param([string]$Phase, [string]$Reason, $Status = $null)
    if ($Phase -cnotin @('prerequisites','preflight','npm-configuration','staging','environment-isolation','installer','promotion','cleanup','removal')) { $Phase = 'prerequisites' }
    if ($Reason -cnotin @(@IMPECCABLE_REASONS@)) { $Reason = 'unknown' }
    $exit = if ($null -ne $Status -and [string]$Status -cmatch '^-?[0-9]{1,10}$') { [string]$Status } else { 'unavailable' }
    Write-Warning "Impeccable: phase=$Phase reason=$Reason exit=$exit."
}

function Invoke-ImpeccableCapture {
    param([scriptblock]$Command)
    $buffer = [System.Text.StringBuilder]::new()
    $overflow = $false
    $status = $null
    $ErrorActionPreference = 'Continue'
    $PSNativeCommandUseErrorActionPreference = $false
    $global:LASTEXITCODE = $null
    try {
        & $Command 2>&1 | ForEach-Object {
            if (-not $overflow) {
                $line = [string]$_
                if ($line.Length -gt 65536 - $buffer.Length - 1) {
                    $overflow = $true
                    $null = $buffer.Clear()
                } else { $null = $buffer.Append($line).Append("`n") }
            }
        }
        $status = $LASTEXITCODE
    } catch {
        $status = $null
        $overflow = $true
        $null = $buffer.Clear()
    }
    return [pscustomobject]@{ Output = $buffer.ToString(); Overflow = $overflow; Status = $status }
}

function Invoke-ImpeccableSkillPolicy {
    param([string]$Mode, [string]$Stage = '', [string]$DiagnosticText = '', [switch]$Overflow)
    $phase = switch ($Mode) { stage { 'staging' } promote { 'promotion' } dispose { 'cleanup' } remove { 'removal' } default { 'preflight' } }
    if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
        if ($Mode -eq 'diagnostic') { return 'reason:unknown' }
        Write-ImpeccableFailure $phase 'shared-runtime-unavailable'
        return $false
    }
    $code = @'
@IMPECCABLE_CORE@
'@
    $savedOptions = $env:NODE_OPTIONS
    $savedPath = $env:NODE_PATH
    try {
        $env:NODE_OPTIONS = $null; $env:NODE_PATH = $null
        if ($Mode -eq 'diagnostic') {
            if ($Overflow) { return 'reason:unknown' }
            $code = $code.Split(@("void 'BEGIN_IMPECCABLE_DIAGNOSTICS';"), [StringSplitOptions]::None)[1].Split(@("void 'END_IMPECCABLE_DIAGNOSTICS';"), [StringSplitOptions]::None)[0]
            $code += '; impeccableReadDiagnostic(process.argv[1]);'
            $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($code))
            $bootstrap = "eval(Buffer.from('$encoded','base64').toString('utf8'))"
            $capture = Invoke-ImpeccableCapture { $DiagnosticText | & node --input-type=commonjs --eval $bootstrap -- $Stage }
            if ($capture.Status -ne 0 -or $capture.Overflow) { return 'reason:unknown' }
            $result = $capture.Output.TrimEnd("`r", "`n")
            if ($result -ceq 'ok') { return $result }
            if ($result.StartsWith('reason:') -and $result.Substring(7) -cin @(@IMPECCABLE_REASONS@)) { return $result }
            if ($Stage -eq 'stage' -and $result -cmatch '^stage:[^\r\n]+$') { return $result }
            return 'reason:unknown'
        }
        $blocked = if ($script:PiProfileMutationsBlocked) { '1' } else { '0' }
        $piInput = if ($env:PI_CODING_AGENT_DIR) { $env:PI_CODING_AGENT_DIR } else { Join-Path $env:USERPROFILE '.pi/agent' }
        $capture = Invoke-ImpeccableCapture { $code | & node --input-type=commonjs - $env:USERPROFILE $piInput $blocked $Mode $Stage }
        $result = Invoke-ImpeccableSkillPolicy -Mode diagnostic -Stage $Mode -DiagnosticText $capture.Output -Overflow:$capture.Overflow
        if ($null -eq $capture.Status) {
            Write-ImpeccableFailure $phase 'launch-failed'
        } elseif ($capture.Status -eq 0) {
            if ($Mode -eq 'stage' -and $result.StartsWith('stage:')) { return $result.Substring(6) }
            if ($Mode -ne 'stage' -and $result -ceq 'ok') { return $true }
            Write-ImpeccableFailure $phase 'invalid-result' $capture.Status
        } else {
            $reason = if ($result.StartsWith('reason:')) { $result.Substring(7) } else { 'unknown' }
            Write-ImpeccableFailure $phase $reason $capture.Status
        }
        return $false
    } catch {
        if ($Mode -eq 'diagnostic') { return 'reason:unknown' }
        Write-ImpeccableFailure $phase 'unknown'
        return $false
    } finally {
        $env:NODE_OPTIONS = $savedOptions; $env:NODE_PATH = $savedPath
    }
}

function Invoke-ImpeccableConvergence {
    if ($env:BAN_IMPECCABLE -ceq '1') { return (Invoke-ImpeccableSkillPolicy -Mode remove) }
    if (-not (Enable-SkillsCliNodeRuntime) -or -not (Get-Command npx -ErrorAction SilentlyContinue)) {
        Write-ImpeccableFailure 'prerequisites' 'installer-runtime-unavailable'
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
        $capture = Invoke-ImpeccableCapture { & npm config get userconfig 2>$null }
        $userconfig = $capture.Output.Trim()
        if ($capture.Status -ne 0 -or $capture.Overflow -or [string]::IsNullOrWhiteSpace($userconfig)) {
            Write-ImpeccableFailure $operation 'npm-configuration-unverified' $capture.Status
            return $false
        }
        $capture = Invoke-ImpeccableCapture { & npm config get globalconfig 2>$null }
        $globalconfig = $capture.Output.Trim()
        if ($capture.Status -ne 0 -or $capture.Overflow -or [string]::IsNullOrWhiteSpace($globalconfig)) {
            Write-ImpeccableFailure $operation 'npm-configuration-unverified' $capture.Status
            return $false
        }
        $operation = 'staging'
        $stage = Invoke-ImpeccableSkillPolicy -Mode stage
        if (-not ($stage -is [string]) -or [string]::IsNullOrWhiteSpace($stage)) { $stage = $null; return $false }
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
        $operation = 'environment-isolation'
        if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
            foreach ($key in @('NPM_CONFIG_USERCONFIG', 'NPM_CONFIG_GLOBALCONFIG')) {
                $saved[$key] = [Environment]::GetEnvironmentVariable($key)
                [Environment]::SetEnvironmentVariable($key, [NullString]::Value)
            }
        }
        foreach ($key in $isolated.Keys) {
            $saved[$key] = [Environment]::GetEnvironmentVariable($key)
            [Environment]::SetEnvironmentVariable($key, $(if ($null -eq $isolated[$key]) { [NullString]::Value } else { $isolated[$key] }))
        }
        $operation = 'staging'
        Set-Location -LiteralPath $stage
        Write-Message 'Installing/updating official global Impeccable skills without hooks...'
        $operation = 'installer'
        $npxArgs = @('--yes', 'impeccable@latest', 'install', '--yes', '--scope=global', '--providers=claude,codex,cursor,gemini,pi', '--no-hooks')
        $capture = Invoke-ImpeccableCapture { & npx @npxArgs }
        $status = $capture.Status
        if ($null -eq $status) { Write-ImpeccableFailure 'installer' 'launch-failed' }
        elseif ($status -ne 0) {
            $result = Invoke-ImpeccableSkillPolicy -Mode diagnostic -Stage installer -DiagnosticText $capture.Output -Overflow:$capture.Overflow
            Write-ImpeccableFailure 'installer' $result.Substring(7) $status
        }
        $operation = 'environment-isolation'
        Set-Location -LiteralPath $location
        foreach ($key in $saved.Keys) {
            [Environment]::SetEnvironmentVariable($key, $(if ($null -eq $saved[$key]) { [NullString]::Value } else { $saved[$key] }))
        }
        $saved.Clear()
        if ($null -ne $status -and $status -eq 0) {
            $operation = 'promotion'
            if (Invoke-ImpeccableSkillPolicy -Mode promote -Stage $stage) { $success = $true }
        }
    } catch {
        Write-ImpeccableFailure $operation 'unknown'
    } finally {
        try {
            Set-Location -LiteralPath $location
            foreach ($key in $saved.Keys) {
                [Environment]::SetEnvironmentVariable($key, $(if ($null -eq $saved[$key]) { [NullString]::Value } else { $saved[$key] }))
            }
        } catch {
            Write-ImpeccableFailure 'environment-isolation' 'environment-isolation-failed'
            $success = $false
        }
        if ($stage -and -not (Invoke-ImpeccableSkillPolicy -Mode dispose -Stage $stage)) { $success = $false }
    }
    if ($success) { Write-Success 'Impeccable global payload and Pi discovery input verified; hooks unchanged.' }
    return $success
}
