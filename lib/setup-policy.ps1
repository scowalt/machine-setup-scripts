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
        if ($key -eq 'HEADLESS' -and $env:HEADLESS -eq '1') { continue }
        [Environment]::SetEnvironmentVariable($key, $value, 'Process')
    }
}
