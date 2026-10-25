function Invoke-PiVisualExplainerPolicy {
    param([string]$Mode, [string]$Source = '')
    $code = @'
@PI_VISUAL_EXPLAINER_CORE@
'@
    $homePath = $env:USERPROFILE
    $agentPath = if ($env:PI_CODING_AGENT_DIR) { $env:PI_CODING_AGENT_DIR } else { Join-Path $homePath '.pi/agent' }
    $savedOptions = $env:NODE_OPTIONS; $savedPath = $env:NODE_PATH
    $result = ''; $status = $null
    try {
        $env:NODE_OPTIONS = $null; $env:NODE_PATH = $null
        $ErrorActionPreference = 'Continue'; $PSNativeCommandUseErrorActionPreference = $false
        $output = @($code | & node --input-type=commonjs - $Mode $homePath $agentPath $Source 2>$null)
        $status = $LASTEXITCODE
        $result = ($output -join "`n").TrimEnd("`r", "`n")
    } catch { $result = 'failed:unknown' }
    finally { $env:NODE_OPTIONS = $savedOptions; $env:NODE_PATH = $savedPath }
    if ($status -eq 0) {
        if ($Mode -ceq 'plan' -and $result.StartsWith('source:')) { return $result.Substring(7) }
        if ($Mode -cne 'plan' -and $result -ceq 'ok') { return 'ok' }
    }
    if ($result -cnotmatch '^failed:(unsafe-profile|unsafe-directory|unsafe-file|unsafe-acl|invalid-metadata|source-conflict|redirected-git|unverified-checkout|modified-checkout|invalid-payload|legacy-conflict|changed-input|unverified-install|invalid-mode|dependency-conflict|dependency-recovery|native-command)$') {
        $result = 'failed:unknown'
    }
    if ($result -ceq 'failed:dependency-recovery') {
        Write-Warning 'Visual Explainer: failed:dependency-recovery. Inspect .setup-visual-explainer-dependencies in the active Pi profile; saved dependencies were not deleted or overwritten.'
    } else {
        Write-Warning "Visual Explainer: $result. Existing custom resources and diagrams were preserved; reconcile conflicts before retrying."
    }
    return $null
}

function Setup-PiVisualExplainer {
    if ($script:PiProfileMutationsBlocked) {
        Write-Warning 'Skipping Visual Explainer because Pi profile mutations are blocked.'
        return $false
    }
    foreach ($command in @('node', 'npm', 'git', 'pi')) {
        if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
            Write-Warning 'Visual Explainer: required Pi/shared-runtime/Git prerequisites are unavailable.'
            return $false
        }
    }
    if ($env:PI_OFFLINE -match '^(1|true|yes)$') {
        Write-Warning 'Visual Explainer: offline mode prevents required package maintenance.'
        return $false
    }
    $source = Invoke-PiVisualExplainerPolicy -Mode plan
    if (-not $source) { return $false }
    Write-Message 'Installing/updating the native Visual Explainer Pi package...'
    if ((Invoke-PiVisualExplainerPolicy -Mode install -Source $source) -cne 'ok') { return $false }
    if ((Invoke-PiVisualExplainerPolicy -Mode finish -Source $source) -cne 'ok') { return $false }
    Write-Success 'Visual Explainer Pi package installed/updated; existing pins and resource selections preserved.'
    return $true
}
