$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$source = Get-Content -Raw (Join-Path $repoRoot 'win.ps1')
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) { throw 'Windows setup contains syntax errors.' }
foreach ($name in @('Remove-PiSyntheticModels', 'Seed-PiZaiModels', 'Get-EnvLocalValue')) {
    $function = $ast.Find({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
    }, $false)
    if (-not $function) { throw "Missing function: $name" }
    . ([scriptblock]::Create($function.Extent.Text))
}
function Test-EnvLocalFlag { param($Name) [Environment]::GetEnvironmentVariable($Name) -eq '1' }
$dotfilesSettings = '{"defaultProvider":"openai","defaultModel":"gpt-6.1-sol","defaultThinkingLevel":"xhigh","modelThinkingLevels":{"openai/gpt-6.1-sol":"max","openai-codex/gpt-6-astra":"xhigh"}}'
function Get-Bytes($Path) { [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($Path)) }
$success = 'PASS'
$failIcon = 'FAIL'
$names = @('USERPROFILE', 'PI_CODING_AGENT_DIR', 'WORK_MACHINE', 'ZAI_API_KEY')
$oldEnvironment = @{}
foreach ($name in $names) { $oldEnvironment[$name] = [Environment]::GetEnvironmentVariable($name) }
$tempHome = Join-Path ([System.IO.Path]::GetTempPath()) ('pi-defaults-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $tempHome | Out-Null
try {
    $env:USERPROFILE = $tempHome
    $env:ZAI_API_KEY = $null
    foreach ($custom in @($false, $true)) {
        $env:PI_CODING_AGENT_DIR = if ($custom) { Join-Path $tempHome 'custom agent' } else { $null }
        $agent = if ($custom) { $env:PI_CODING_AGENT_DIR } else { Join-Path $tempHome '.pi\agent' }
        $settingsPath = Join-Path $agent 'settings.json'
        $modelsPath = Join-Path $agent 'models.json'
        if (-not (Remove-PiSyntheticModels)) { throw 'Absent models cleanup failed.' }
        if (Test-Path $modelsPath) { throw 'Cleanup created absent models file.' }
        New-Item -ItemType Directory -Force -Path $agent | Out-Null
        foreach ($work in @('0', '1')) {
            $env:WORK_MACHINE = $work
            foreach ($key in @('', 'fixture-zai')) {
                $envPath = Join-Path $tempHome '.env.local'
                Set-Content $envPath "SYNTHETIC_API_KEY=fixture-retired`nZAI_API_KEY=$key"
                $envBefore = Get-Bytes $envPath
                $authPath = Join-Path $agent 'auth.json'
                Set-Content $authPath '{"openai-codex":{"type":"oauth","fixture":true}}'
                $authBefore = Get-Bytes $authPath
                Set-Content $settingsPath $dotfilesSettings
                $settingsBefore = Get-Bytes $settingsPath
                Set-Content $modelsPath '{"providers":{"synthetic":{"apiKey":"fixture-retired"},"zai":{"apiKey":"fixture-existing"},"custom":{"models":[{"id":"keep"}]}},"keep":true}'
                foreach ($iteration in 1..2) {
                    if (-not (Remove-PiSyntheticModels)) { throw 'Provider removal failed.' }
                    $models = Get-Content -Raw $modelsPath | ConvertFrom-Json
                    if ($models.providers.PSObject.Properties['synthetic'] -or
                        $models.providers.zai.apiKey -ne 'fixture-existing' -or
                        $models.providers.custom.models[0].id -ne 'keep' -or -not $models.keep) { throw 'Wrong provider cleanup.' }
                    $before = Get-Bytes $modelsPath
                    if (-not (Remove-PiSyntheticModels)) { throw 'Repeat provider removal failed.' }
                    if ((Get-Bytes $modelsPath) -cne $before) { throw 'No-op cleanup rewrote models.' }
                    if (-not (Seed-PiZaiModels)) { throw 'Existing z.ai key not preserved.' }
                    if ((Get-Bytes $modelsPath) -cne $before) { throw 'Existing z.ai provider changed.' }
                    if ((Get-Bytes $settingsPath) -cne $settingsBefore) { throw 'Dotfiles Pi defaults changed.' }
                }
                if ((Get-Bytes $envPath) -cne $envBefore -or (Get-Bytes $authPath) -cne $authBefore) {
                    throw 'Local credentials changed.'
                }
                if ($key) {
                    Set-Content $modelsPath '{"providers":{"custom":{"models":[{"id":"keep"}]}}}'
                    if (-not (Seed-PiZaiModels)) { throw 'Optional z.ai seeding failed.' }
                    $models = Get-Content -Raw $modelsPath | ConvertFrom-Json
                    if ($models.providers.zai.apiKey -ne $key -or $models.providers.zai.models.Count -ne 3 -or
                        $models.providers.custom.models[0].id -ne 'keep') { throw 'Wrong z.ai seeding.' }
                }
            }
        }
        foreach ($invalid in @('{not-json', '', 'null', '[]', '[{"providers":{"synthetic":{}}}]', '{"providers":[]}')) {
            Set-Content $modelsPath $invalid
            $before = Get-Bytes $modelsPath
            if (Remove-PiSyntheticModels) { throw 'Invalid models accepted.' }
            if ((Get-Bytes $modelsPath) -cne $before) { throw 'Invalid models changed.' }
        }
        foreach ($valid in @('{}', '{"providers":null}', '{"providers":{"custom":{}}}')) {
            Set-Content $modelsPath $valid
            $before = Get-Bytes $modelsPath
            if (-not (Remove-PiSyntheticModels)) { throw 'Valid no-op cleanup failed.' }
            if ((Get-Bytes $modelsPath) -cne $before) { throw 'No-op cleanup changed file.' }
        }
    }
    Write-Output 'PASS: Windows Synthetic removal and optional z.ai provider, with dotfiles Pi defaults preserved'
} finally {
    foreach ($name in $names) { [Environment]::SetEnvironmentVariable($name, $oldEnvironment[$name]) }
    Remove-Item -Recurse -Force $tempHome
}
