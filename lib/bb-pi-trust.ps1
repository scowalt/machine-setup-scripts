function Invoke-BbPiTrustPolicy {
    param([string]$Mode, [string[]]$Targets = @())
    if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
        Write-Warning 'BB/Pi trust: shared Node runtime unavailable.'
        return $false
    }
    $code = @'
@BB_PI_TRUST_CORE@
'@
    $homePath = if ($env:HOME) { $env:HOME } else { $env:USERPROFILE }
    $dataPath = if ($env:BB_DATA_DIR) { $env:BB_DATA_DIR } else { Join-Path $homePath '.bb' }
    $agentPath = if ($env:PI_CODING_AGENT_DIR) { $env:PI_CODING_AGENT_DIR } else { Join-Path $homePath '.pi/agent' }
    $savedOptions = $env:NODE_OPTIONS
    $savedPath = $env:NODE_PATH
    $result = ''; $status = $null
    try {
        $env:NODE_OPTIONS = $null; $env:NODE_PATH = $null
        $ErrorActionPreference = 'Continue'
        $PSNativeCommandUseErrorActionPreference = $false
        $output = @($code | & node --input-type=commonjs - $Mode $homePath $dataPath $agentPath @Targets 2>$null)
        $status = $LASTEXITCODE
        $result = ($output -join "`n").TrimEnd("`r", "`n")
    } catch {
        $result = 'failed:unknown'
    } finally {
        $env:NODE_OPTIONS = $savedOptions; $env:NODE_PATH = $savedPath
    }
    if ($status -eq 0 -and $result -ceq 'ok') { return $true }
    if ($result -cnotmatch '^failed:(unsafe-path|unsafe-directory|unsafe-home|unsafe-profile|unsafe-acl|unsafe-metadata|invalid-trust|trust-locked|changed-input|unsafe-cli|doctor-failed|invalid-doctor-report|doctor-blocked|doctor-unhealthy|doctor-missing-server|invalid-mode)$') {
        $result = 'failed:unknown'
    }
    Write-Warning "BB/Pi trust: $result. Existing decisions and MCP approvals were not replaced."
    return $false
}

function Configure-BbPiTrust {
    if ($script:PiProfileMutationsBlocked) {
        Write-Warning 'Skipping BB/Pi trust because Pi profile mutations are blocked.'
        return $false
    }
    if ($env:BAN_PI_MCP_ADAPTER -ceq '1') { return $true }
    if (-not (Invoke-BbPiTrustPolicy -Mode merge)) { return $false }
    Write-Debug 'Pi workspace trust merged; existing decisions and MCP definition approvals preserved.'
    return $true
}

function Test-BbPiMcpHealth {
    param([Parameter(Mandatory=$true)][string]$WorkingDirectory, [string[]]$RequiredServers = @())
    return (Invoke-BbPiTrustPolicy -Mode health -Targets (@($WorkingDirectory) + $RequiredServers))
}
