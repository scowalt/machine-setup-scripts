$ErrorActionPreference = 'Stop'
$source = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../win.ps1') -Raw
$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$errors)
if ($errors.Count -ne 0) { throw 'Windows setup parse failure' }
$function = $ast.Find({ param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Install-BbDesktop'
}, $true)
if (-not $function) { throw 'Missing desktop wrapper' }
Invoke-Expression $function.Extent.Text
function Write-Debug($message) { $script:Result = $message }
function Test-EnvLocalFlag($name) {
    if ($name -ne 'HEADLESS') { throw 'Unexpected flag access' }
    return $script:FixtureHeadless -eq '1'
}
foreach ($flag in @('', '0', 'true', '1')) {
    $script:FixtureHeadless = $flag
    if (-not (Install-BbDesktop)) { throw 'Intentional skip failed' }
    if ($flag -eq '1') {
        if ($script:Result -notmatch 'HEADLESS=1') { throw 'Missing headless skip' }
    } elseif ($script:Result -notmatch 'Windows') { throw 'Missing platform skip' }
}
Write-Host 'bb desktop Windows wrapper passed (no installer invoked).'
