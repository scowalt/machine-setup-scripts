$wingetPackages = (
    "tailscale.tailscale",
    "Readdle.Spark",
    "Google.Chrome",
    "jdx.mise",
    "twpayne.chezmoi",
    "Git.Git",
    "Tyrrrz.LightBulb",
    "Microsoft.PowerToys",
    "File-New-Project.EarTrumpet",
    "AgileBits.1Password",
    "AgileBits.1Password.CLI",
    "Starship.Starship",
    "mulaRahul.Keyviz",
    "GitHub.cli",
    "Oven-sh.Bun",
    "Beeper.Beeper",
    "Flow-Launcher.Flow-Launcher",
    "gerardog.gsudo",
    "strayge.tray-monitor",
    "DEVCOM.JetBrainsMonoNerdFont",
    "nektos.act",
    "OpenTofu.Tofu",
    "astral-sh.uv",
    "jqlang.jq",
    "GoLang.Go",
    "Cloudflare.cloudflared",
    "Kubernetes.kubectl",
    "Notion.ntn"
)

$arrow = [char]0xf0a9       
$success = [char]0xf00c     
$warnIcon = [char]0xf071    
$failIcon = [char]0xf00d    
$sparkles = [char]0x2728    

$script:SetupOriginalPath = $env:PATH
$script:SetupOriginalClaudeCommand = $null
$script:SetupOriginalTeaCommand = $null
$script:SetupLogFile = $null
$script:SetupTranscriptStarted = $false
$script:SetupLogClosed = $false
try {
    $setupOriginalClaude = Get-Command claude -ErrorAction SilentlyContinue
    if ($setupOriginalClaude) {
        $script:SetupOriginalClaudeCommand = $setupOriginalClaude.Source
    }
}
catch {}
try {
    $setupOriginalTea = Get-Command tea -CommandType Application -ErrorAction SilentlyContinue
    if ($setupOriginalTea) {
        $script:SetupOriginalTeaCommand = if ($setupOriginalTea.Source) { $setupOriginalTea.Source } else { $setupOriginalTea.Path }
    }
}
catch {}

function Write-Section($message) {
    Write-Host "`n=== $message ===" -ForegroundColor White -BackgroundColor DarkBlue
    Write-Host ""
}

function Write-Message($message) {
    Write-Host "$arrow $message" -ForegroundColor Cyan
}

function Write-Success($message) {
    Write-Host "$success $message" -ForegroundColor Green
}

function Write-Warning($message) {
    Write-Host "$warnIcon $message" -ForegroundColor Yellow
}

function Write-Error($message) {
    Write-Host "$failIcon $message" -ForegroundColor Red
}

function Write-Debug($message) {
    Write-Host "  $message" -ForegroundColor DarkGray
}

$null = 'BEGIN_SETUP_ENVIRONMENT_POLICY'
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
        'BAN_PI_MCP_ADAPTER','BAN_PI_GOAL_AUTORESEARCH','BAN_MATT_POCOCK_SKILLS','BAN_MATT_POCKOCK_SKILLS','BAN_IMPECCABLE',
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
$null = 'END_SETUP_ENVIRONMENT_POLICY'

$null = 'BEGIN_SETUP_ENVIRONMENT_FILE'
function New-TokenPlaceholders {
    $envLocalPath = Join-Path $env:USERPROFILE ".env.local"

    $oldTokenFiles = @(".gh_token", ".op_token")
    foreach ($oldFile in $oldTokenFiles) {
        $oldPath = Join-Path $env:USERPROFILE $oldFile
        if (Test-Path $oldPath) {
            Write-Debug "Migrating ~/$oldFile to ~/.env.local..."
            $lines = Get-Content $oldPath
            foreach ($line in $lines) {
                $cleaned = $line -replace '^export\s+', ''
                if ($cleaned -match '^[A-Z_]+=.+') {
                    Add-Content -Path $envLocalPath -Value $cleaned
                }
            }
            Remove-Item $oldPath -Force
            Write-Debug "Removed old ~/$oldFile"
        }
    }

    if (-not (Test-Path $envLocalPath)) {
        @"
# Machine-specific environment variables
# Format: KEY=VALUE (one per line)

# GitHub Personal Access Tokens
# Get tokens from: https://github.com/settings/tokens
# GH_TOKEN=github_pat_xxx
# GH_TOKEN_SCOWALT=github_pat_yyy

# 1Password Service Account Token
# Create a service account at: https://my.1password.com/integrations/infrastructure-secrets
# OP_SERVICE_ACCOUNT_TOKEN=ops_xxx

# Scott's Telegram alerts (optional, direct Bot API requests)
# See ~/.config/agent-docs/telegram-alerts.md after chezmoi apply
# TELEGRAM_ALERTS_BOT_TOKEN=
# TELEGRAM_ALERTS_CHAT_ID=
# Work-machine alerts require Scott's explicit permission

# Machine/setup guards
# HEADLESS=1
# WORK_MACHINE=1
# BAN_PI_MCP_ADAPTER=1
# BAN_PI_GOAL_AUTORESEARCH=1
# BAN_MATT_POCOCK_SKILLS=1
# BAN_IMPECCABLE=1
# ZAI_API_KEY=<your z.ai API key>
# OpenCode Go console key (Go subscription; keep Use balance disabled in the console)
# OPENCODE_GO_API_KEY=<your OpenCode Go API key>
"@ | Set-Content -Path $envLocalPath
        Write-Debug "Created placeholder ~/.env.local"
    }
}

function Test-EnvLocalFlag {
    param([Parameter(Mandatory=$true)][string]$Name)

    $envValue = [Environment]::GetEnvironmentVariable($Name)
    if ($envValue -eq "1") {
        return $true
    }

    $envLocalFile = Join-Path $env:USERPROFILE ".env.local"
    if (Test-Path $envLocalFile) {
        foreach ($line in Get-Content $envLocalFile) {
            $cleaned = $line -replace '^\s*export\s+', ''
            $parts = $cleaned -split '=', 2
            if ($parts.Count -eq 2 -and $parts[0].Trim() -eq $Name) {
                $value = $parts[1].Trim()
                $value = $value.Trim('"')
                $value = $value.Trim("'")
                if ($value -eq "1") {
                    return $true
                }
            }
        }
    }

    return $false
}


function Assert-HeadlessUnsupported {
    if (-not (Test-EnvLocalFlag "HEADLESS")) {
        return
    }

    Write-Error "HEADLESS=1 requested, but native Windows cannot guarantee no-login headless operation."
    Write-Error "Use a supported native Linux setup script for headless support, or unset HEADLESS for Windows setup."
    throw "Unsupported HEADLESS=1 setup on Windows"
}

function Install-GiteaClient {
    if (-not (Test-EnvLocalFlag "WORK_MACHINE")) {
        Write-Debug "Skipping Gitea client (not a work machine)."
        return
    }

    $installDir = Join-Path $env:USERPROFILE ".local\bin"
    $managedPath = Join-Path $installDir "tea.exe"
    if (-not [string]::IsNullOrWhiteSpace($script:SetupOriginalTeaCommand)) {
        $originalTeaPath = [System.IO.Path]::GetFullPath($script:SetupOriginalTeaCommand)
        $managedTeaPath = [System.IO.Path]::GetFullPath($managedPath)
        if (-not $originalTeaPath.Equals($managedTeaPath, [System.StringComparison]::OrdinalIgnoreCase)) {
            Write-Error "A conflicting tea executable is earlier on PATH: $($script:SetupOriginalTeaCommand)"
            Write-Debug "Remove it from PATH or move $installDir ahead of it, then rerun setup."
            throw "Conflicting tea executable on PATH"
        }
    }

    $processorArchitecture = $env:PROCESSOR_ARCHITEW6432
    if ([string]::IsNullOrWhiteSpace($processorArchitecture)) {
        $processorArchitecture = $env:PROCESSOR_ARCHITECTURE
    }
    $releaseArch = switch -Regex ($processorArchitecture) {
        '^(AMD64|x86_64)$' { "amd64"; break }
        '^(ARM64|aarch64)$' { "arm64"; break }
        default { throw "No official Gitea client binary is available for Windows architecture $processorArchitecture." }
    }

    $apiUrl = "https://gitea.com/api/v1/repos/gitea/tea/releases/latest"
    Write-Message "Finding the latest stable Gitea client release..."
    $release = Invoke-RestMethod -Uri $apiUrl -TimeoutSec 30 -ErrorAction Stop
    $tag = [string]$release.tag_name
    if ($tag -notmatch '^v[0-9]+\.[0-9]+\.[0-9]+$') {
        throw "The latest Gitea client release did not contain a stable semantic version."
    }

    $version = $tag.Substring(1)
    $asset = "tea-$version-windows-$releaseArch.exe"
    $downloadRoot = "https://dl.gitea.com/tea/$version"
    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "tea-install-$([guid]::NewGuid())"
    $downloadedBinary = Join-Path $tempDir $asset
    $checksumsPath = Join-Path $tempDir "checksums.txt"

    try {
        New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
        Write-Message "Downloading Gitea client $version..."
        Invoke-WebRequest -Uri "$downloadRoot/$asset" -OutFile $downloadedBinary -TimeoutSec 120 -ErrorAction Stop
        Invoke-WebRequest -Uri "$downloadRoot/checksums.txt" -OutFile $checksumsPath -TimeoutSec 30 -ErrorAction Stop

        $checksumText = Get-Content -LiteralPath $checksumsPath -Raw -ErrorAction Stop
        $assetPattern = [regex]::Escape($asset)
        $checksumMatch = [regex]::Match($checksumText, "(?m)^([A-Fa-f0-9]{64})\s+$assetPattern\s*$")
        if (-not $checksumMatch.Success) {
            throw "Published SHA-256 checksum not found for $asset."
        }
        $expectedHash = $checksumMatch.Groups[1].Value
        $actualHash = (Get-FileHash -LiteralPath $downloadedBinary -Algorithm SHA256 -ErrorAction Stop).Hash
        if (-not $actualHash.Equals($expectedHash, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Gitea client SHA-256 verification failed for $asset."
        }

        New-Item -ItemType Directory -Force -Path $installDir | Out-Null
        Copy-Item -LiteralPath $downloadedBinary -Destination $managedPath -Force -ErrorAction Stop
    }
    finally {
        Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    $processEntries = @($env:PATH -split ';' | Where-Object { $_ })
    if (-not ($processEntries | Where-Object { [System.IO.Path]::GetFullPath($_).Equals([System.IO.Path]::GetFullPath($installDir), [System.StringComparison]::OrdinalIgnoreCase) })) {
        $env:PATH = "$installDir;$env:PATH"
    }
    $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    $userEntries = @()
    if ($userPath) {
        $userEntries = @($userPath -split ';' | Where-Object { $_ })
    }
    if (-not ($userEntries | Where-Object { [System.IO.Path]::GetFullPath($_).Equals([System.IO.Path]::GetFullPath($installDir), [System.StringComparison]::OrdinalIgnoreCase) })) {
        $newUserPath = if ($userPath) { "$($userPath.TrimEnd(';'));$installDir" } else { $installDir }
        [Environment]::SetEnvironmentVariable("PATH", $newUserPath, "User")
        Write-Success "Added the Gitea client directory to PATH."
    }

    $versionOutput = & $managedPath --version 2>&1
    if ($LASTEXITCODE -ne 0 -or ($versionOutput -join "`n") -notmatch '[0-9]+\.[0-9]+') {
        throw "Gitea client verification failed at $managedPath."
    }
    $resolvedTea = Get-Command tea -CommandType Application -ErrorAction SilentlyContinue
    if ($null -eq $resolvedTea -or -not ([System.IO.Path]::GetFullPath($resolvedTea.Source)).Equals([System.IO.Path]::GetFullPath($managedPath), [System.StringComparison]::OrdinalIgnoreCase)) {
        $resolvedPath = if ($null -eq $resolvedTea) { "<missing>" } else { $resolvedTea.Source }
        throw "The tea command resolves to $resolvedPath instead of $managedPath."
    }

    Write-Success "Gitea client is ready ($($versionOutput -join ' '))."
}

function Install-SecretsManager {
    if (-not (Test-EnvLocalFlag "WORK_MACHINE")) {
        if (Get-Command doppler -ErrorAction SilentlyContinue) {
            Write-Host "  Doppler CLI already installed." -ForegroundColor DarkGray
            return
        }
        Write-Host "$arrow Installing Doppler CLI..." -ForegroundColor Cyan
        winget install -e --id "doppler.doppler" --silent --accept-package-agreements --accept-source-agreements
        if ($LASTEXITCODE -eq 0) {
            Write-Host "$success Doppler CLI installed." -ForegroundColor Green
        } else {
            Write-Host "$failIcon Failed to install Doppler CLI." -ForegroundColor Red
        }
    }
}

function Update-GcloudComponents {
    if (-not (Get-Command gcloud -ErrorAction SilentlyContinue)) {
        Write-Debug "Google Cloud CLI not installed; skipping component update."
        return
    }

    Write-Message "Updating Google Cloud CLI components..."
    $updateOutput = & gcloud components update --quiet 2>&1
    $updateExitCode = $LASTEXITCODE
    $updateText = $updateOutput -join "`n"
    $normalizedUpdateText = (($updateOutput -join " ") -replace "\s+", " ").Trim()

    if ($updateExitCode -eq 0) {
        Write-Success "Google Cloud CLI components updated."
    }
    elseif ($normalizedUpdateText -match "component manager is disabled|managed by an external package manager") {
        Write-Debug "Google Cloud CLI components are managed by the package manager; skipping component update."
    }
    else {
        Write-Warning "Failed to update Google Cloud CLI components."
        if ($updateText) {
            Write-Debug $updateText
        }
    }
}

function Install-GcloudCli {
    if (-not (Test-EnvLocalFlag "WORK_MACHINE")) {
        Write-Debug "Skipping Google Cloud CLI (not a work machine)."
        return
    }

    if (Get-Command gcloud -ErrorAction SilentlyContinue) {
        Write-Debug "Google Cloud CLI already installed."
        Update-GcloudComponents
        return
    }

    Write-Message "Installing Google Cloud CLI..."
    winget install -e --id "Google.CloudSDK" --silent --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Google Cloud CLI installed."
        Update-GcloudComponents
    }
    else {
        Write-Warning "Failed to install Google Cloud CLI."
    }
}

function Install-Chezmoi {
    if (-not (Get-Command chezmoi -ErrorAction SilentlyContinue)) {
        Write-Host "$failIcon Failed to install chezmoi." -ForegroundColor Red
        throw "Failed to install chezmoi"
    }
    else {
        Write-Debug "chezmoi is already installed."
    }

    $chezmoiConfigPath = "$HOME\AppData\Local\chezmoi"
    if (-not (Test-Path $chezmoiConfigPath)) {
        Write-Host "$arrow Initializing chezmoi with scowalt/dotfiles..." -ForegroundColor Cyan
        chezmoi init --apply --force scowalt/dotfiles --ssh
        Write-Host "$success chezmoi initialized with scowalt/dotfiles." -ForegroundColor Green
    }
    else {
        Write-Debug "chezmoi is already initialized."
    }

    $chezmoiTomlPath = "$HOME\.config\chezmoi\chezmoi.toml"
    if (-not (Test-Path $chezmoiTomlPath)) {
        Write-Host "$arrow Configuring chezmoi with auto-commit, auto-push, and auto-pull..." -ForegroundColor Cyan
        New-Item -ItemType Directory -Force -Path (Split-Path $chezmoiTomlPath)
        @"
[git]
autoCommit = true
autoPush = true
autoPull = true
"@ | Set-Content -Path $chezmoiTomlPath
        Write-Host "$success chezmoi configuration set." -ForegroundColor Green
    }
    else {
        Write-Debug "chezmoi configuration already exists."
    }

    Write-Host "$arrow Applying chezmoi dotfiles..." -ForegroundColor Cyan
    chezmoi apply --force
    Write-Host "$success chezmoi dotfiles applied." -ForegroundColor Green
}

function Update-Chezmoi {
    $chezmoiConfigPath = "$HOME\AppData\Local\chezmoi"
    if (Test-Path $chezmoiConfigPath) {
        Write-Host "$arrow Updating chezmoi dotfiles repository..." -ForegroundColor Cyan
        if (Test-Path "$chezmoiConfigPath\.git") {
            git -C $chezmoiConfigPath reset --hard HEAD 2>$null | Out-Null
            git -C $chezmoiConfigPath merge --abort 2>$null | Out-Null
            git -C $chezmoiConfigPath clean -fd 2>$null | Out-Null
        }
        $updateOutput = chezmoi update --force 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "$success chezmoi dotfiles repository updated." -ForegroundColor Green
        }
        else {
            Write-Host "$warnIcon Failed to update chezmoi dotfiles repository. Continuing anyway." -ForegroundColor Yellow
        }
    }
    else {
        Write-Debug "chezmoi not initialized yet, skipping update."
    }
}

$githubUsername = "scowalt"
$githubKeysUrl = "https://github.com/$githubUsername.keys"
$localKeyPath = "$HOME\.ssh\id_rsa.pub"

function Test-GithubSSHKeyAlreadyAdded {
    try {
        $githubKeys = Invoke-RestMethod -Uri $githubKeysUrl -ErrorAction Stop
        $githubKeyPortions = $githubKeys -split "`n" | ForEach-Object { ($_ -split " ")[1] }
    }
    catch {
        Write-Host "$failIcon Failed to fetch SSH keys from GitHub." -ForegroundColor Red
        throw "Failed to fetch SSH keys from GitHub"
    }

    $localKeyContent = Get-Content -Path $localKeyPath

    $localKeyValue = ($localKeyContent -split " ")[1]

    if ($githubKeyPortions -contains $localKeyValue) {
        Write-Host "$success Existing SSH key is recognized by GitHub." -ForegroundColor Green
        return $true
    }
    else {
        Write-Host "$failIcon SSH key not recognized by GitHub. Please add it manually." -ForegroundColor Red
        Write-Host "Public key content to add:" -ForegroundColor Yellow
        Write-Host $localKeyContent -ForegroundColor Yellow
        Write-Host "$arrow Opening GitHub SSH keys page..." -ForegroundColor Cyan
        Start-Process "https://github.com/settings/keys"
        return $false
    }
}

function Test-GitHubSSHKey {
    Write-Host "$arrow Checking for existing SSH key associated with GitHub..." -ForegroundColor Cyan

    if (Test-Path $localKeyPath) {
    }
    else {
        Write-Host "$warnIcon No SSH key found. Generating a new SSH key..." -ForegroundColor Yellow

        if (-not (Test-Path "$HOME\.ssh")) {
            New-Item -ItemType Directory -Force -Path "$HOME\.ssh"
        }

        & ssh-keygen -t rsa -b 4096 -f $localKeyPath.Replace(".pub", "") -N `"`" -C "$githubUsername@windows"
        Write-Host "$success SSH key generated." -ForegroundColor Green
        Write-Host "Please add the following SSH key to GitHub:" -ForegroundColor Cyan
        Get-Content -Path $localKeyPath
        Write-Host "$arrow Opening GitHub SSH keys page..." -ForegroundColor Cyan
        Start-Process "https://github.com/settings/keys"
    }

    $keyadded = $false

    do {
        $keyadded = Test-GithubSSHKeyAlreadyAdded
        if ($keyadded -eq $false) {
            Write-Host "Press Enter to check if the key has been added to GitHub..."
            [void][System.Console]::ReadLine()
        }
    } while ($keyadded -eq $false)
}

function Install-SocketFirewall {
    $envLocalFile = Join-Path $env:USERPROFILE ".env.local"
    $isWorkMachine = $false
    if (Test-Path $envLocalFile) {
        foreach ($line in Get-Content $envLocalFile) {
            if ($line -match '^\s*WORK_MACHINE\s*=\s*1\s*$') {
                $isWorkMachine = $true
                break
            }
        }
    }
    if (-not $isWorkMachine) {
        Write-Debug "Skipping Socket Firewall (not a work machine)."
        return
    }

    if (Get-Command sfw -ErrorAction SilentlyContinue) {
        Write-Debug "sfw is already installed."
        return
    }

    $bunPath = "$env:USERPROFILE\.bun\bin"
    if (Test-Path $bunPath) {
        $env:PATH = "$bunPath;$env:PATH"
    }

    if (-not (Get-Command bun -ErrorAction SilentlyContinue)) {
        Write-Host "$warnIcon Bun not found. Cannot install Socket Firewall." -ForegroundColor Yellow
        Write-Host "  Install Bun first, then run: bun install -g sfw" -ForegroundColor DarkGray
        return
    }

    Write-Host "$arrow Installing Socket Firewall..." -ForegroundColor Cyan
    try {
        bun install -g sfw
        if ($?) {
            Write-Host "$success Socket Firewall installed." -ForegroundColor Green
        }
        else {
            Write-Host "$failIcon Failed to install Socket Firewall." -ForegroundColor Red
        }
    }
    catch {
        Write-Host "$failIcon Failed to install Socket Firewall: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Set-SfwWrappers {
    $profilePath = $PROFILE
    $markerPattern = '# Socket Firewall wrappers'

    if (Select-String -Path $profilePath -Pattern ([regex]::Escape($markerPattern)) -Quiet -ErrorAction SilentlyContinue) {
        Write-Debug "Socket Firewall wrappers already in PowerShell profile."
        return
    }

    Write-Host "$arrow Adding Socket Firewall wrappers to PowerShell profile..." -ForegroundColor Cyan

    $sfwBlock = @"

# Socket Firewall wrappers - route package managers through sfw for supply chain security.
# Bypass: call the original exe directly, e.g. & (Get-Command npm -CommandType Application).Source install <pkg>
`$sfwPath = "`$env:USERPROFILE\.bun\bin\sfw.exe"
if (Test-Path `$sfwPath) {
    function npm   { & `$sfwPath npm @args }
    function yarn  { & `$sfwPath yarn @args }
    function pnpm  { & `$sfwPath pnpm @args }
    function pip   { & `$sfwPath pip @args }
    function uv    { & `$sfwPath uv @args }
    function cargo { & `$sfwPath cargo @args }
}
"@

    Add-Content -Path $profilePath -Value $sfwBlock
    Write-Host "$success Socket Firewall wrappers added to PowerShell profile." -ForegroundColor Green
}

function Set-StarshipInit {
    $profilePath = $PROFILE
    $starshipInitCommand = 'Invoke-Expression (&starship init powershell)'
    $escapedPattern = [regex]::Escape($starshipInitCommand)

    if (-not (Select-String -Path $profilePath -Pattern $escapedPattern -Quiet)) {
        Add-Content -Path $profilePath -Value "`n$starshipInitCommand"
        Write-Host "$success Starship initialization command added to PowerShell profile." -ForegroundColor Green
    }
    else {
        Write-Debug "Starship initialization command is already in PowerShell profile."
    }
}


function Install-TursoCli {
    if (Get-Command turso -ErrorAction SilentlyContinue) {
        Write-Debug "Turso CLI is already installed."
        return
    }

    Write-Host "$arrow Installing Turso CLI..." -ForegroundColor Cyan

    $tursoPath = "$env:LOCALAPPDATA\turso"
    if (-not (Test-Path $tursoPath)) {
        New-Item -ItemType Directory -Force -Path $tursoPath | Out-Null
    }

    $downloadUrl = "https://github.com/tursodatabase/turso-cli/releases/latest/download/turso_cli-windows-amd64.exe"
    $binaryPath = "$tursoPath\turso.exe"

    try {
        Write-Host "$arrow Downloading Turso CLI binary..." -ForegroundColor Cyan
        Invoke-WebRequest -Uri $downloadUrl -OutFile $binaryPath

        $currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
        if ($currentPath -notlike "*$tursoPath*") {
            [Environment]::SetEnvironmentVariable("PATH", "$currentPath;$tursoPath", "User")
            Write-Host "$success Added Turso CLI to PATH." -ForegroundColor Green
        }

        Write-Host "$success Turso CLI installed." -ForegroundColor Green
    }
    catch {
        Write-Host "$failIcon Failed to download Turso CLI: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Get-ClaudeCodeNativePath {
    return (Join-Path (Join-Path $env:USERPROFILE ".local\bin") "claude.exe")
}

function Test-ClaudeCodeSamePath {
    param(
        [Parameter(Mandatory=$true)][string]$First,
        [Parameter(Mandatory=$true)][string]$Second
    )

    try {
        $expandedFirst = [Environment]::ExpandEnvironmentVariables($First)
        $expandedSecond = [Environment]::ExpandEnvironmentVariables($Second)
        $firstFull = [System.IO.Path]::GetFullPath($expandedFirst).TrimEnd('\')
        $secondFull = [System.IO.Path]::GetFullPath($expandedSecond).TrimEnd('\')
        return ($firstFull -ieq $secondFull)
    }
    catch {
        return ($First -ieq $Second)
    }
}

function Test-ClaudeCodeSupportedPlatform {
    if (-not [Environment]::Is64BitProcess) {
        Write-Warning "Claude Code native installer does not support 32-bit Windows."
        return $false
    }

    if ($env:PROCESSOR_ARCHITECTURE -notin @("AMD64", "ARM64")) {
        Write-Warning "Claude Code native installer may not support architecture $env:PROCESSOR_ARCHITECTURE."
        return $false
    }

    return $true
}

function Test-ClaudeCodePackageManagedPath {
    param([Parameter(Mandatory=$true)][string]$Path)

    return ($Path -match '(?i)(node_modules|pnpm|mise|asdf|volta|yarn|fnm|nvm|npm|\\.bun|AppData\\Roaming\\npm|scoop|chocolatey|Homebrew|Caskroom|WinGet)')
}

function Test-ClaudeCodeNativeProvenance {
    param([Parameter(Mandatory=$true)][string]$Path)

    if (-not (Test-Path $Path)) {
        return $false
    }

    if (Test-ClaudeCodePackageManagedPath $Path) {
        return $false
    }

    try {
        $signature = Get-AuthenticodeSignature -FilePath $Path
        if ($signature.Status -eq "Valid" -and $signature.SignerCertificate.Subject -like "*Anthropic*") {
            return $true
        }

        return $false
    }
    catch {
        return $false
    }
}

function Test-ClaudeCodeTrustedPowerShellHost {
    param([Parameter(Mandatory=$true)][string]$Path)

    if (-not (Test-Path $Path)) {
        return $false
    }

    try {
        $signature = Get-AuthenticodeSignature -FilePath $Path
        return ($signature.Status -eq "Valid" -and $signature.SignerCertificate.Subject -like "*Microsoft*")
    }
    catch {
        return $false
    }
}

function Get-ClaudeCodePowerShellHost {
    $currentProcessPath = $null
    try {
        $currentProcessPath = (Get-Process -Id $PID).Path
    }
    catch {}

    if (-not [string]::IsNullOrWhiteSpace($currentProcessPath) -and (Test-Path $currentProcessPath)) {
        return $currentProcessPath
    }

    $systemRoot = [Environment]::GetEnvironmentVariable("SystemRoot", "Process")
    if ([string]::IsNullOrWhiteSpace($systemRoot)) {
        $systemRoot = "C:\Windows"
    }
    return (Join-Path $systemRoot "System32\WindowsPowerShell\v1.0\powershell.exe")
}

function Get-ClaudeCodeCandidates {
    $commands = @(Get-Command claude -All -ErrorAction SilentlyContinue)
    return @($commands | ForEach-Object {
        if ($_.Source) {
            $_.Source
        }
        elseif ($_.Path) {
            $_.Path
        }
        else {
            $_.Name
        }
    } | Where-Object { $_ })
}

function Format-ClaudeCodeArgument {
    param([Parameter(Mandatory=$true)][string]$Argument)

    if ($Argument -match '[\s"]') {
        return ('"' + ($Argument -replace '"', '\\"') + '"')
    }

    return $Argument
}

function Invoke-ClaudeCodeCommandSafely {
    param(
        [Parameter(Mandatory=$true)][string]$FilePath,
        [string[]]$Arguments = @()
    )

    $allowedEnvNames = @(
        "ALLUSERSPROFILE",
        "APPDATA",
        "COMSPEC",
        "HOMEDRIVE",
        "HOMEPATH",
        "LOCALAPPDATA",
        "PATH",
        "PATHEXT",
        "PROCESSOR_ARCHITECTURE",
        "PROCESSOR_ARCHITEW6432",
        "ProgramData",
        "ProgramFiles",
        "ProgramFiles(x86)",
        "ProgramW6432",
        "PSModulePath",
        "SystemDrive",
        "SystemRoot",
        "TEMP",
        "TMP",
        "USERDOMAIN",
        "USERNAME",
        "USERPROFILE",
        "WINDIR",
        "HTTP_PROXY",
        "HTTPS_PROXY",
        "ALL_PROXY",
        "NO_PROXY",
        "http_proxy",
        "https_proxy",
        "all_proxy",
        "no_proxy",
        "SSL_CERT_FILE",
        "SSL_CERT_DIR",
        "CURL_CA_BUNDLE"
    )
    $allowedEnvLookup = @{}
    foreach ($allowedName in $allowedEnvNames) {
        $allowedEnvLookup[$allowedName.ToUpperInvariant()] = $true
    }
    $savedEnv = @{}
    $allEnvNames = @(Get-ChildItem Env: | ForEach-Object { $_.Name })
    $stdoutPath = Join-Path ([System.IO.Path]::GetTempPath()) "claude-code-stdout-$([guid]::NewGuid()).log"
    $stderrPath = Join-Path ([System.IO.Path]::GetTempPath()) "claude-code-stderr-$([guid]::NewGuid()).log"
    $timeoutSeconds = 300
    $timeoutValue = [Environment]::GetEnvironmentVariable("CLAUDE_CODE_COMMAND_TIMEOUT_SECONDS")
    if ($timeoutValue -match '^\d+$') {
        $timeoutSeconds = [int]$timeoutValue
    }

    foreach ($name in $allEnvNames) {
        $savedEnv[$name] = [Environment]::GetEnvironmentVariable($name, "Process")
        if (-not $allowedEnvLookup.ContainsKey($name.ToUpperInvariant())) {
            Remove-Item -Path "Env:$name" -ErrorAction SilentlyContinue
        }
    }

    $systemRoot = [Environment]::GetEnvironmentVariable("SystemRoot", "Process")
    if ([string]::IsNullOrWhiteSpace($systemRoot)) {
        $systemRoot = "C:\Windows"
        [Environment]::SetEnvironmentVariable("SystemRoot", $systemRoot, "Process")
    }
    $safePath = "$systemRoot\System32;$systemRoot;$systemRoot\System32\WindowsPowerShell\v1.0"
    [Environment]::SetEnvironmentVariable("PATH", $safePath, "Process")

    try {
        $argumentLine = ($Arguments | ForEach-Object { Format-ClaudeCodeArgument $_ }) -join ' '
        $process = Start-Process -FilePath $FilePath `
            -ArgumentList $argumentLine `
            -NoNewWindow `
            -PassThru `
            -RedirectStandardOutput $stdoutPath `
            -RedirectStandardError $stderrPath

        if (-not $process.WaitForExit($timeoutSeconds * 1000)) {
            try {
                $process.Kill($true)
            }
            catch {
                try {
                    & taskkill.exe /PID $process.Id /T /F *> $null
                }
                catch {
                    try {
                        $process.Kill()
                    }
                    catch {}
                }
            }
            try {
                $process.WaitForExit(5000) | Out-Null
            }
            catch {}
            $exitCode = 124
        }
        else {
            $exitCode = $process.ExitCode
        }

        $stdout = ""
        $stderr = ""
        if (Test-Path $stdoutPath) {
            $stdout = Get-Content -Path $stdoutPath -Raw -ErrorAction SilentlyContinue
        }
        if (Test-Path $stderrPath) {
            $stderr = Get-Content -Path $stderrPath -Raw -ErrorAction SilentlyContinue
        }
        $output = (($stdout, $stderr) | Where-Object { $_ }) -join "`n"
    }
    catch {
        $output = $_.Exception.Message
        $exitCode = 1
    }
    finally {
        foreach ($name in $savedEnv.Keys) {
            if ($null -ne $savedEnv[$name]) {
                [Environment]::SetEnvironmentVariable($name, $savedEnv[$name], "Process")
            }
            else {
                Remove-Item -Path "Env:$name" -ErrorAction SilentlyContinue
            }
        }
        Remove-Item -Path $stdoutPath -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $stderrPath -Force -ErrorAction SilentlyContinue
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = $output
    }
}

function Invoke-ClaudeCodeInstaller {
    $installerPath = Join-Path ([System.IO.Path]::GetTempPath()) "claude-code-install-$([guid]::NewGuid()).ps1"

    try {
        Microsoft.PowerShell.Utility\Invoke-WebRequest -Uri "https://claude.ai/install.ps1" -OutFile $installerPath -TimeoutSec 120 -ErrorAction Stop
    }
    catch {
        Write-Warning "Failed to download Claude Code installer."
        Remove-Item -Path $installerPath -Force -ErrorAction SilentlyContinue
        return $false
    }

    $powerShellHost = Get-ClaudeCodePowerShellHost
    if (-not (Test-ClaudeCodeTrustedPowerShellHost $powerShellHost)) {
        Write-Warning "Trusted Microsoft-signed PowerShell executable not found for Claude Code installer."
        Remove-Item -Path $installerPath -Force -ErrorAction SilentlyContinue
        return $false
    }

    $result = Invoke-ClaudeCodeCommandSafely -FilePath $powerShellHost -Arguments @(
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        $installerPath,
        "latest"
    )
    Remove-Item -Path $installerPath -Force -ErrorAction SilentlyContinue

    if ($result.ExitCode -ne 0) {
        Write-Warning "Claude Code installer failed with exit code $($result.ExitCode)."
        return $false
    }

    return $true
}

function Add-ClaudeCodeNativePath {
    param([Parameter(Mandatory=$true)][string]$NativeDir)

    $processEntries = @($env:PATH -split ';' | Where-Object { $_ })
    $processHasPath = $processEntries | Where-Object { Test-ClaudeCodeSamePath $_ $NativeDir }
    if (-not $processHasPath) {
        $env:PATH = "$NativeDir;$env:PATH"
    }

    $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    $userEntries = @()
    if ($userPath) {
        $userEntries = @($userPath -split ';' | Where-Object { $_ })
    }
    $userHasPath = $userEntries | Where-Object { Test-ClaudeCodeSamePath $_ $NativeDir }
    if (-not $userHasPath) {
        try {
            if ($userPath) {
                [Environment]::SetEnvironmentVariable("PATH", "$userPath;$NativeDir", "User")
            }
            else {
                [Environment]::SetEnvironmentVariable("PATH", $NativeDir, "User")
            }
            Write-Success "Added Claude Code CLI to PATH."
        }
        catch {
            Write-Warning "Failed to add Claude Code CLI to user PATH; use $NativeDir directly or add it manually."
        }
    }
}

function Warn-ClaudeCodeShadowing {
    param(
        [string]$OriginalCommand,
        [Parameter(Mandatory=$true)][string]$NativePath
    )

    if ([string]::IsNullOrWhiteSpace($OriginalCommand)) {
        return
    }

    if (Test-ClaudeCodeSamePath $OriginalCommand $NativePath) {
        return
    }

    Write-Warning "The 'claude' command currently resolves to $OriginalCommand, not $NativePath."
    Write-Warning "Do not use bare 'claude' for Fable login until PATH/package shadowing is resolved; use $NativePath directly."
}

function Install-ClaudeCode {
    if (-not (Test-ClaudeCodeSupportedPlatform)) {
        return
    }

    $nativePath = Get-ClaudeCodeNativePath
    $nativeDir = Split-Path $nativePath -Parent
    $originalCommand = $script:SetupOriginalClaudeCommand
    if ([string]::IsNullOrWhiteSpace($originalCommand)) {
        $savedPath = $env:PATH
        try {
            $env:PATH = $script:SetupOriginalPath
            $originalCandidates = @(Get-ClaudeCodeCandidates)
            if ($originalCandidates.Count -gt 0) {
                $originalCommand = $originalCandidates[0]
            }
        }
        finally {
            $env:PATH = $savedPath
        }
    }
    $needsInstall = $true

    Write-Message "Installing/updating Claude Code CLI..."
    New-Item -ItemType Directory -Force -Path $nativeDir | Out-Null

    if (Test-ClaudeCodeNativeProvenance $nativePath) {
        $versionResult = Invoke-ClaudeCodeCommandSafely -FilePath $nativePath -Arguments @("--version")
        if ($versionResult.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($versionResult.Output)) {
            $needsInstall = $false
            $currentVersion = (($versionResult.Output -split '\r?\n') | Select-Object -First 1).Trim()
            Write-Debug "Current Claude Code version: $currentVersion"
            $updateResult = Invoke-ClaudeCodeCommandSafely -FilePath $nativePath -Arguments @("update")
            if ($updateResult.ExitCode -eq 0) {
                Write-Debug "Claude Code update completed."
            }
            else {
                Write-Warning "Claude Code update failed; keeping existing install."
            }
        }
        else {
            Write-Warning "Claude Code native binary exists but did not run; reinstalling."
        }
    }
    elseif (Test-Path $nativePath) {
        Write-Warning "Claude Code native path appears to be package-managed or invalid; reinstalling native Claude Code."
    }

    if ($needsInstall) {
        if (-not (Invoke-ClaudeCodeInstaller)) {
            return
        }
    }

    Add-ClaudeCodeNativePath -NativeDir $nativeDir
    $verifyResult = Invoke-ClaudeCodeCommandSafely -FilePath $nativePath -Arguments @("--version")
    if ($verifyResult.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($verifyResult.Output)) {
        $versionText = (($verifyResult.Output -split '\r?\n') | Select-Object -First 1).Trim()
        Write-Success "Claude Code CLI installed/updated ($versionText)."
        Warn-ClaudeCodeShadowing -OriginalCommand $originalCommand -NativePath $nativePath
    }
    else {
        Write-Warning "Claude Code CLI install completed, but $nativePath did not verify."
    }
}

function Install-GeminiCli {
    if (Get-Command gemini -ErrorAction SilentlyContinue) {
        Write-Debug "Gemini CLI is already installed."
        return
    }

    Write-Host "$arrow Installing Gemini CLI..." -ForegroundColor Cyan

    $bunPath = "$env:USERPROFILE\.bun\bin"
    if (Test-Path $bunPath) {
        $env:PATH = "$bunPath;$env:PATH"
    }

    if (-not (Get-Command bun -ErrorAction SilentlyContinue)) {
        Write-Host "$warnIcon Bun not found. Cannot install Gemini CLI." -ForegroundColor Yellow
        Write-Host "  Install Bun first, then run: bun install -g @google/gemini-cli" -ForegroundColor DarkGray
        return
    }

    try {
        bun install -g @google/gemini-cli
        if ($?) {
            Write-Host "$success Gemini CLI installed." -ForegroundColor Green
        }
        else {
            Write-Host "$failIcon Failed to install Gemini CLI." -ForegroundColor Red
        }
    }
    catch {
        Write-Host "$failIcon Failed to install Gemini CLI: $($_.Exception.Message)" -ForegroundColor Red
    }
}

$null = 'BEGIN_GENERATED_OPENCODE_CLI'
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

function Invoke-OpenCodeCliCore {
    param([string]$NodePath, [string]$Code)
    $bootstrap = @'
const rl = require('node:readline').createInterface({input: process.stdin, crlfDelay: Infinity});
rl.once('line', source => {
    try { eval(Buffer.from(source, 'base64').toString('utf8')); }
    catch { console.log('opencode-cli:failed'); process.exitCode = 1; rl.close(); process.stdin.destroy(); return; }
    const api = module.exports;
    api.install({verifySessionSelection: expected => new Promise(resolve => {
        const finish = value => { clearTimeout(timer); rl.removeListener('line', reply); rl.removeListener('close', closed); resolve(value); };
        const reply = line => finish(line === 'verified' ? true : line === 'refused' ? false : undefined);
        const closed = () => finish(undefined);
        const timer = setTimeout(closed, 20000);
        rl.once('line', reply); rl.once('close', closed);
        console.log('opencode-cli:verify-selection:' + Buffer.from(expected).toString('base64'));
    })}).then(result => console.log('opencode-cli:' + result)).catch(error => {
        console.log(api.failureResult(error)); process.exitCode = 1;
    }).finally(() => { rl.close(); process.stdin.destroy(); });
});
'@
    $process = New-Object System.Diagnostics.Process
    $started = $false
    try {
        $process.StartInfo.FileName = $NodePath
        $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($bootstrap))
        $process.StartInfo.Arguments = '-e "eval(Buffer.from(''' + $encoded + ''',''base64'').toString(''utf8''))"'
        $process.StartInfo.UseShellExecute = $false
        $process.StartInfo.CreateNoWindow = $true
        $process.StartInfo.RedirectStandardInput = $true
        $process.StartInfo.RedirectStandardOutput = $true
        $process.StartInfo.RedirectStandardError = $true
        $started = $process.Start()
        if (-not $started) { throw 'start' }
        $discard = $process.StandardError.BaseStream.CopyToAsync([IO.Stream]::Null)
        $process.StandardInput.WriteLine([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Code)))
        $process.StandardInput.Flush()
        $output = @(); $requested = $false; $verified = $false
        while ($true) {
            $read = $process.StandardOutput.ReadLineAsync()
            if (-not $read.Wait(600000)) { throw 'timeout' }
            $line = $read.Result
            if ($null -eq $line) { break }
            if ($line.Length -gt 4096) { throw 'output' }
            if ($line -cmatch '\Aopencode-cli:verify-selection:([A-Za-z0-9+/]+={0,2})\z') {
                if ($requested -or $output.Count) { throw 'protocol' }
                $requested = $true
                $expected = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Matches[1]))
                $allowed = @('.local/bin/opencode.exe', '.opencode/bin/opencode.exe', '.bun/bin/opencode.exe') |
                    ForEach-Object { Join-Path $env:USERPROFILE $_ }
                if ($expected -notin $allowed) { throw 'selection' }
                try {
                    $selected = Get-Command opencode -ErrorAction Stop
                    $verified = $selected -and $selected.CommandType -eq 'Application' -and $selected.Source -eq $expected
                } catch { $verified = $false }
                $process.StandardInput.WriteLine($(if ($verified) { 'verified' } else { 'refused' }))
                $process.StandardInput.Flush()
            } else {
                $output += $line
                if ($output.Count -gt 1) { throw 'output' }
            }
        }
        if (-not $process.WaitForExit(25000)) { throw 'exit' }
        if ($process.ExitCode -eq 0 -and -not $verified -and $output[0] -cne 'opencode-cli:unsupported') { throw 'selection' }
        return @{ Status = $process.ExitCode; Output = $output }
    } catch {
        if ($started) {
            try { $process.StandardInput.Close() } catch { }
            if (-not $process.WaitForExit(25000)) { $process.Kill(); $process.WaitForExit() }
        }
        return @{ Status = 1; Output = @('opencode-cli:recovery-required:failed') }
    } finally { $process.Dispose() }
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
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const https = require('node:https');
const crypto = require('node:crypto');
const zlib = require('node:zlib');
const cp = require('node:child_process');
const {isNativeError} = require('node:util').types;
const policyReasons = new Set(('archive archive-header archive-path archive-tail archive-truncated archive-type artifact-identity artifact-metadata ' +
    'brew-command brew-origin brew-path brew-snapshot-changed ' +
    'changed-copy changed-receipt custom-link custom-prefix custom-wrapper duplicate-metadata integrity libc metadata missing-binary outside-home package-conflict pinned receipt ' +
    'recovery-occupied relative-path release-metadata shadowed shadowed-newer unreachable unsafe-file unsafe-path unverified-copy url version version-probe windows-acl foreign-command command-conflict selection-unverified').split(' '));
const nativeCodes = new Set('EACCES EPERM ENOENT EIO EEXIST ENOTDIR ELOOP ENOSPC EROFS ETIMEDOUT ENOBUFS'.split(' '));
const diagnosticErrors = new WeakSet();
class PolicyError extends Error {
    constructor(reason, operation = reason.startsWith('brew-') ? 'homebrew-preflight' : 'installation') {
        super(reason); this.reason = reason; this.operation = operation; diagnosticErrors.add(this);
    }
}
const pathRefusals = new WeakMap();
function rejectPathComponent(index, kind) {
    const error = new PolicyError('relative-path');
    try {
        if (Number.isInteger(index) && index >= 1 && index <= 999999 && ['empty', 'relative'].includes(kind)) {
            pathRefusals.set(error, Object.freeze({index, kind}));
        }
    } catch {   }
    throw error;
}
const fail = reason => { throw new PolicyError(reason); };
const nativeFailure = (operation, error) => nativeCodes.has(error?.code) ? new PolicyError(`native-${error.code}`, operation) : error;
const version = value => {
    if (typeof value !== 'string' || !/^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/.test(value)) fail('version');
    const parts = value.split('.').map(Number);
    if (parts.some(n => !Number.isSafeInteger(n))) fail('version');
    return parts;
};
const compare = (a, b) => {
    const aa = version(a), bb = version(b);
    for (let i = 0; i < 3; i++) if (aa[i] !== bb[i]) return Math.sign(aa[i] - bb[i]);
    return 0;
};
const samePath = (a, b) => process.platform === 'win32' ? a.toLowerCase() === b.toLowerCase() : a === b;
const digest = bytes => crypto.createHash('sha512').update(bytes).digest('base64');
function json(bytes) {
    const text = bytes.toString(); let value;
    try { value = JSON.parse(text); } catch { fail('metadata'); }
    const stack = [];
    for (const match of text.matchAll(/"(?:\\.|[^"\\])*"|[{}[\],:]|[^\s{}[\],:]+/g)) {
        const token = match[0];
        if (token === '{') stack.push({keys: new Set(), expectingKey: true});
        else if (token === '[') stack.push(null);
        else if (token === '}' || token === ']') stack.pop();
        else if (token === ',' && stack.at(-1)) stack.at(-1).expectingKey = true;
        else if (token.startsWith('"') && stack.at(-1)?.expectingKey) {
            const top = stack.at(-1), key = JSON.parse(token);
            if (top.keys.has(key)) fail('duplicate-metadata');
            top.keys.add(key); top.expectingKey = false;
        }
    }
    return value;
}
function target(platform = process.platform, machine = os.machine(), glibc = process.report.getReport().header.glibcVersionRuntime) {
    const arch = {x86_64: 'x64', AMD64: 'x64', x64: 'x64', arm64: 'arm64', ARM64: 'arm64', aarch64: 'arm64'}[machine];
    if (!arch || !['linux', 'darwin', 'win32'].includes(platform)) return null;
    let result = `${platform === 'win32' ? 'windows' : platform}-${arch}${arch === 'x64' ? '-baseline' : ''}`;
    if (platform === 'linux' && !glibc) {
        if (!fs.readdirSync('/lib').some(n => /^ld-musl-(x86_64|aarch64)\.so\.1$/.test(n))) fail('libc');
        result += '-musl';
    }
    return result;
}
class DownloadError extends Error {
    constructor(operation, status) { super('download'); this.operation = operation; this.status = status; diagnosticErrors.add(this); }
}
class RecoveryError extends Error {
    constructor(original) { super('recovery-required'); this.original = original; diagnosticErrors.add(this); }
}
function failureResult(error, recovering = false) {
    try { return formatFailure(error, recovering); } catch { return 'opencode-cli:failed'; }
}
function formatFailure(error, recovering) {
    const typed = diagnosticErrors.has(error);
    if (typed && error instanceof RecoveryError) {
        if (recovering) return 'opencode-cli:failed';
        return `opencode-cli:recovery-required:${failureResult(error.original, true).slice('opencode-cli:'.length)}`;
    }
    if (isNativeError(error) && error.message === 'recovery-required') return 'opencode-cli:recovery-required';
    if (typed && error instanceof DownloadError && ['latest-release', 'package-index', 'package-version', 'artifact-download', 'download'].includes(error.operation)) {
        const status = Number.isInteger(error.status) && error.status >= 100 && error.status <= 599 ? error.status : 'unknown';
        return `opencode-cli:download-failed:${error.operation}:http-${status}`;
    }
    if (typed && error instanceof PolicyError && typeof error.reason === 'string' && ['homebrew-preflight', 'installation', 'setup-selection', 'fresh-shell-selection'].includes(error.operation) &&
        (policyReasons.has(error.reason) || (error.reason.startsWith('native-') && nativeCodes.has(error.reason.slice(7))))) {
        const generic = `opencode-cli:policy-failed:${error.operation}:${error.reason}`;
        try {
            const context = pathRefusals.get(error);
            if (error.operation === 'installation' && error.reason === 'relative-path' && context &&
                Number.isInteger(context.index) && context.index >= 1 && context.index <= 999999 && ['empty', 'relative'].includes(context.kind)) {
                return `${generic}:command-discovery:${context.index}:${context.kind}`;
            }
        } catch {   }
        return generic;
    }
    return 'opencode-cli:failed';
}
function downloadOperation(parsed) {
    if (parsed.hostname === 'opencode.ai') return parsed.pathname === '/update/api/latest/cli/npm' ? 'latest-release' : 'download';
    let pathname;
    try { pathname = decodeURIComponent(parsed.pathname); } catch { fail('url'); }
    if (/^\/(?:@[A-Za-z0-9_.-]+\/)?[A-Za-z0-9_.-]+\/?$/.test(pathname)) return 'package-index';
    if (/^\/(?:@[A-Za-z0-9_.-]+\/)?[A-Za-z0-9_.-]+\/-\/[A-Za-z0-9_.-]+\.tgz$/.test(pathname)) return 'artifact-download';
    if (/^\/(?:@[A-Za-z0-9_.-]+\/)?[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+\/?$/.test(pathname)) return 'package-version';
    return 'download';
}
function fetchBytes(url, limit = 32 * 1024 * 1024) {
    const parsed = new URL(url);
    if (parsed.protocol !== 'https:' || parsed.username || parsed.password || parsed.port ||
        !['registry.npmjs.org', 'opencode.ai'].includes(parsed.hostname)) fail('url');
    const operation = downloadOperation(parsed);
    const accept = operation === 'package-index' ? 'application/vnd.npm.install-v1+json' : operation === 'artifact-download' ? 'application/octet-stream' : 'application/json';
    return new Promise((resolve, reject) => {
        let status;
        const request = https.get(url, {rejectUnauthorized: true, headers: {'User-Agent': 'curl/8.0', Accept: accept}}, response => {
            status = response.statusCode;
            if (status !== 200) { response.resume(); reject(new DownloadError(operation, status)); return; }
            const chunks = []; let length = 0;
            response.on('data', data => {
                length += data.length;
                if (length > limit) request.destroy(new Error('download-size'));
                else chunks.push(data);
            });
            response.on('end', () => resolve(Buffer.concat(chunks)));
            response.on('error', () => reject(new DownloadError(operation, status)));
        });
        const deadline = setTimeout(() => request.destroy(new Error('download-timeout')), 90000);
        request.on('close', () => clearTimeout(deadline));
        request.setTimeout(60000, () => request.destroy(new Error('download-timeout')));
        request.on('error', () => reject(new DownloadError(operation, status)));
    });
}
function unpack(bytes) {
    let tar;
    try { tar = zlib.gunzipSync(bytes, {maxOutputLength: 512 * 1024 * 1024}); } catch { fail('archive'); }
    const files = new Map(); let ended = false;
    for (let offset = 0; offset + 512 <= tar.length;) {
        const header = tar.subarray(offset, offset + 512); offset += 512;
        if (header.every(b => b === 0)) { ended = true; if (tar.subarray(offset).some(b => b !== 0)) fail('archive-tail'); break; }
        const text = (start, end) => header.subarray(start, end).toString().replace(/\0.*$/s, '');
        const name = text(0, 100), sizeText = text(124, 136).trim(), checksum = text(148, 156).trim();
        if (!/^[0-7]+$/.test(sizeText) || !/^[0-7]+$/.test(checksum)) fail('archive-header');
        const sum = header.reduce((n, b, i) => n + (i >= 148 && i < 156 ? 32 : b), 0);
        if (sum !== parseInt(checksum, 8) || text(345, 500) || text(157, 257)) fail('archive-header');
        if (!/^package\/(?:[A-Za-z0-9_@.-]+\/)*[A-Za-z0-9_.-]+\/?$/.test(name) ||
            name.split('/').some(p => p === '..' || p === '.') || files.has(name)) fail('archive-path');
        const size = parseInt(sizeText, 8), type = text(156, 157);
        if (!['', '0', '5'].includes(type) || (type === '5' && size) || offset + size > tar.length) fail('archive-type');
        files.set(name, tar.subarray(offset, offset + size));
        offset += Math.ceil(size / 512) * 512;
    }
    if (!ended) fail('archive-truncated');
    return files;
}
async function artifact(name, release, get = fetchBytes) {
    version(release);
    const metadata = json(await get(`https://registry.npmjs.org/${name}/${release}`));
    const basename = name.split('/').pop();
    if (metadata.name !== name || metadata.version !== release ||
        metadata.dist?.tarball !== `https://registry.npmjs.org/${name}/-/${basename}-${release}.tgz` ||
        !/^sha512-[A-Za-z0-9+/]{86}==$/.test(metadata.dist?.integrity || '')) fail('artifact-metadata');
    const bytes = await get(metadata.dist.tarball, 256 * 1024 * 1024);
    if (`sha512-${digest(bytes)}` !== metadata.dist.integrity) fail('integrity');
    const files = unpack(bytes), manifest = json(files.get('package/package.json') || 'null');
    if (manifest?.name !== name || manifest.version !== release) fail('artifact-identity');
    return files;
}
function safePath(file, home, leafLink = false, directories) {
    const relative = path.relative(home, file);
    if (relative.startsWith('..') || path.isAbsolute(relative)) fail('outside-home');
    const chain = [home];
    for (const part of relative.split(path.sep).filter(Boolean)) chain.push(path.join(chain.at(-1), part));
    for (const item of chain) {
        let st;
        try { st = fs.lstatSync(item); } catch (e) { if (e.code === 'ENOENT') continue; throw e; }
        if ((st.isSymbolicLink() && !(leafLink && item === file)) ||
            (!st.isSymbolicLink() && !st.isDirectory() && !st.isFile()) ||
            (process.platform !== 'win32' && (st.uid !== process.getuid() ||
                (!st.isSymbolicLink() && (st.mode & (st.isDirectory() && st.uid !== 0 ? 0o002 : 0o022)))))) fail('unsafe-path');
        if (directories && st.isDirectory()) {
            if (directories.has(item) && !sameBrew(directories.get(item), st)) fail('changed-copy');
            directories.set(item, st);
        }
    }
}
function checkAccountDirectories(directories) {
    for (const [file, before] of directories || []) {
        if (!sameBrew(before, fs.lstatSync(file))) fail('changed-copy');
    }
}
function boundedRead(file) {
    const before = fs.lstatSync(file);
    if (!before.isFile() || before.size > 512 * 1024 * 1024) fail('unsafe-file');
    const fd = fs.openSync(file, fs.constants.O_RDONLY | fs.constants.O_NONBLOCK | (fs.constants.O_NOFOLLOW || 0));
    try {
        const opened = fs.fstatSync(fd);
        if (!opened.isFile() || opened.dev !== before.dev || opened.ino !== before.ino || opened.size !== before.size) fail('changed-copy');
        const bytes = fs.readFileSync(fd), after = fs.fstatSync(fd);
        if (bytes.length !== before.size || after.size !== before.size || after.mtimeMs !== before.mtimeMs) fail('changed-copy');
        return bytes;
    } finally { fs.closeSync(fd); }
}
function commands(home, env = process.env) {
    const dirs = new Set([path.join(home, '.local/bin'), path.join(home, '.opencode/bin'), path.join(home, '.bun/bin')]);
    for (const [offset, dir] of (env.PATH || '').split(path.delimiter).entries()) {
        if (!dir && process.platform === 'win32') continue;
        if (!dir || !path.isAbsolute(dir)) rejectPathComponent(offset + 1, dir ? 'relative' : 'empty');
        dirs.add(dir.startsWith(env.HOME + path.sep) ? path.join(home, path.relative(env.HOME, dir)) : dir);
    }
    const names = process.platform === 'win32' ? ['opencode.exe', 'opencode.cmd', 'opencode.ps1', 'opencode'] : ['opencode'];
    const result = [];
    for (const dir of dirs) for (const name of names) {
        const file = path.join(dir, name);
        try { fs.lstatSync(file); result.push(file); } catch (e) { if (e.code !== 'ENOENT') throw e; }
    }
    return [...new Map(result.map(file => [process.platform === 'win32' ? file.toLowerCase() : file, file])).values()];
}
function foreignCommand(file, home) {
    const relative = path.relative(home, file);
    if (!relative.startsWith('..') && !path.isAbsolute(relative)) return false;
    if (!path.isAbsolute(file)) fail('relative-path');
    if (process.platform === 'win32') return true;
    const chain = [path.parse(file).root];
    for (const part of file.slice(chain[0].length).split(path.sep).filter(Boolean)) chain.push(path.join(chain.at(-1), part));
    for (const item of chain) {
        const info = fs.lstatSync(item);
        if (![0, process.getuid()].includes(info.uid) || (item === file && info.uid !== process.getuid())) return true;
        if (item !== file && (!info.isDirectory() || (info.mode & 0o002))) fail('unsafe-path');
    }
    return false;
}
function verifySetupSelection(expected, home, homeInput, searchPath, brewTrust) {
    const reject = reason => { throw new PolicyError(reason, 'setup-selection'); };
    const cached = process.env.SETUP_OPENCODE_HASHED;
    if (cached) {
        const normalized = cached.startsWith(homeInput + path.sep) ? path.join(home, path.relative(homeInput, cached)) : cached;
        if (!samePath(normalized, expected)) reject('command-conflict');
    }
    const names = process.platform === 'win32' ? ['opencode.ps1', ...new Set((process.env.PATHEXT || '.COM;.EXE;.BAT;.CMD').split(';').map(ext => 'opencode' + ext.toLowerCase()))] : ['opencode'];
    for (const directory of searchPath.split(path.delimiter)) {
        if (!directory && process.platform === 'win32') continue;
        if (!path.isAbsolute(directory)) reject('selection-unverified');
        for (const name of names) {
            const candidate = path.join(directory, name);
            let info;
            try { info = fs.lstatSync(candidate); } catch (error) { if (error.code === 'ENOENT') continue; reject('selection-unverified'); }
            if (info.isDirectory()) continue;
            if (process.platform !== 'win32' && info.isFile()) {
                try { fs.accessSync(candidate, fs.constants.X_OK); }
                catch (error) { if (error.code === 'EACCES') continue; reject('selection-unverified'); }
            }
            const normalized = candidate.startsWith(homeInput + path.sep)
                ? path.join(home, path.relative(homeInput, candidate)) : candidate;
            if (!samePath(normalized, expected)) reject(foreignCommand(candidate, home) ? 'foreign-command' : 'command-conflict');
            if (brewTrust && samePath(brewTrust.command, expected)) checkBrewTrust(brewTrust);
            else if (!info.isFile() || info.isSymbolicLink()) reject('selection-unverified');
            try { fs.accessSync(expected, fs.constants.X_OK); } catch { reject('selection-unverified'); }
            return;
        }
    }
    reject('unreachable');
}
function verifyFreshSelection(expected, home, homeInput) {
    const reject = reason => { throw new PolicyError(reason, 'fresh-shell-selection'); };
    const shell = process.env.SETUP_OPENCODE_SHELL;
    if (!shell || !path.isAbsolute(shell)) reject('selection-unverified');
    const env = {...process.env, HOME: homeInput, USERPROFILE: homeInput};
    for (const name of Object.keys(env)) {
        if (/^(__MISE_|FNM_)|^MISE_(SHELL|.*_VERSION|TOOL_OPTS__NODE)$|^NODE_(PATH|OPTIONS)$/.test(name) ||
            ['BASH_ENV', 'ENV', '__setup_shared_node_activation'].includes(name)) delete env[name];
    }
    env.MISE_AUTO_INSTALL = 'false'; env.MISE_NODE_COMPILE = 'false';
    let args;
    const marker = `opencode-selection-${crypto.randomBytes(16).toString('hex')}:`;
    if (process.platform === 'win32') {
        if (!['powershell.exe', 'pwsh.exe'].includes(path.basename(shell).toLowerCase()) || !env.SETUP_OPENCODE_FRESH_PATH) reject('selection-unverified');
        env.PATH = env.SETUP_OPENCODE_FRESH_PATH;
        args = ['-NoLogo', '-NonInteractive', '-Command', `$ErrorActionPreference = 'Stop'; try { $c = Get-Command opencode -ErrorAction Stop; if ($c.CommandType -ne 'Application') { exit 2 }; [Console]::WriteLine("\`n${marker}" + $c.Source + "${marker}") } catch { exit 3 }`];
    } else {
        if (path.basename(shell) !== 'fish') reject('selection-unverified');
        env.PATH = '/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin';
        args = ['-l', '-i', '-c', `if functions -q opencode; exit 2; end; set -l selected (command -s opencode); or exit 3; printf '\\n${marker}%s${marker}\\n' "$selected"`];
    }
    let output;
    try {
        output = cp.execFileSync(shell, args, {cwd: home, env, timeout: 20000, maxBuffer: 65536,
            stdio: ['ignore', 'pipe', 'ignore'], windowsHide: true}).toString();
    } catch (error) { reject(error.status === 2 ? 'command-conflict' : 'selection-unverified'); }
    const records = output.split(/\r?\n/).filter(line => line.startsWith(marker));
    if (records.length !== 1 || !records[0].endsWith(marker)) reject('selection-unverified');
    const selected = records[0].slice(marker.length, -marker.length);
    if (!path.isAbsolute(selected) || /[\r\n\0]/.test(selected)) reject('selection-unverified');
    const normalized = selected.startsWith(homeInput + path.sep) ? path.join(home, path.relative(homeInput, selected)) : selected;
    if (!samePath(normalized, expected)) reject('command-conflict');
}
function probe(file, release, workspace) {
    const isolated = fs.mkdtempSync(path.join(workspace, 'probe-'));
    const env = {HOME: isolated, USERPROFILE: isolated, XDG_CONFIG_HOME: isolated, XDG_DATA_HOME: isolated,
        XDG_CACHE_HOME: isolated, XDG_STATE_HOME: isolated, APPDATA: isolated, LOCALAPPDATA: isolated,
        TMPDIR: isolated, TMP: isolated, TEMP: isolated, PATH: path.dirname(file), LANG: 'C', NO_COLOR: '1'};
    if (process.platform === 'win32') env.SystemRoot = process.env.SystemRoot;
    let output;
    try { output = cp.execFileSync(file, ['--version'], {cwd: isolated, env, timeout: 20000, maxBuffer: 1024,
        stdio: ['ignore', 'pipe', 'ignore'], windowsHide: true}).toString().trim(); } catch { fail('version-probe'); }
    if (output !== release && output !== `opencode v${release}`) fail('version-probe');
}
const brewFingerprint = s => s && (s.isDirectory() ? ['dev', 'ino', 'uid', 'gid', 'mode'] :
    ['dev', 'ino', 'uid', 'gid', 'mode', 'nlink', 'size', 'mtimeMs', 'ctimeMs']).map(key => s[key]);
const sameBrew = (a, b) => JSON.stringify(brewFingerprint(a)) === JSON.stringify(brewFingerprint(b));
function brewPermissions(file, info) {
    if (![0, process.getuid()].includes(info.uid) || (!info.isSymbolicLink() && (info.mode & 0o002))) fail('brew-path');
    if (!info.isSymbolicLink() && (info.mode & 0o020)) {
        const linuxBrew = process.platform === 'linux' &&
            (file === '/home/linuxbrew/.linuxbrew' || file.startsWith('/home/linuxbrew/.linuxbrew/'));
        const accountDirectory = ['linux', 'darwin'].includes(process.platform) && info.isDirectory();
        if (info.uid === 0 || info.uid !== process.getuid() || !(linuxBrew || accountDirectory)) fail('brew-path');
    }
}
function checkBrewTrust(trust, moved = false) {
    for (const [file, before] of trust.snapshots) {
        if (moved && file === trust.command) continue;
        let now = null;
        try { now = fs.lstatSync(file); } catch (error) { if (error.code !== 'ENOENT') throw error; }
        if (!sameBrew(before, now)) fail('brew-snapshot-changed');
        if (now) brewPermissions(file, now);
    }
    if (!moved && fs.readlinkSync(trust.command) !== trust.link) fail('brew-snapshot-changed');
}
function checkBrewBackup(item, backup) {
    checkBrewTrust(item.brewTrust, true);
    const before = item.brewTrust.snapshots.get(item.file), now = fs.lstatSync(backup);
    if (!['dev', 'ino', 'uid', 'gid', 'mode', 'nlink', 'size', 'mtimeMs'].every(key => before[key] === now[key]) ||
        !now.isSymbolicLink() || fs.readlinkSync(backup) !== item.brewTrust.link) fail('brew-snapshot-changed');
}
function brewCopy(file) {
    try { return inspectBrewCopy(file); } catch (error) { throw nativeFailure('homebrew-preflight', error); }
}
function inspectBrewCopy(file) {
    if (process.platform === 'win32') return null;
    const prefix = ['/opt/homebrew', '/usr/local', '/home/linuxbrew/.linuxbrew'].find(p => file === `${p}/bin/opencode`);
    if (!prefix) return null;
    const snapshots = new Map();
    function inspect(candidate, kind, optional = false) {
        const chain = ['/'];
        for (const part of candidate.split('/').filter(Boolean)) chain.push(path.join(chain.at(-1), part));
        for (const current of chain) {
            let info = null;
            try { info = fs.lstatSync(current); } catch (error) { if (!optional || error.code !== 'ENOENT') throw error; }
            if (snapshots.has(current) && !sameBrew(snapshots.get(current), info)) fail('brew-snapshot-changed');
            if (!info) { snapshots.set(current, null); return false; }
            const leaf = current === candidate;
            if (leaf && kind === 'pin') fail('pinned');
            if (!(leaf && kind === 'link' ? info.isSymbolicLink() : leaf && kind === 'file' ? info.isFile() && info.nlink === 1 : info.isDirectory())) fail('brew-path');
            if (!snapshots.has(current)) brewPermissions(current, info);
            snapshots.set(current, info);
        }
        return true;
    }
    inspect(file, 'link');
    const link = fs.readlinkSync(file);
    const binary = path.resolve(path.dirname(file), link);
    const match = binary.match(new RegExp(`^${prefix.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}/Cellar/opencode/([0-9.]+)(?:_([1-9][0-9]*))?/bin/opencode$`));
    if (!match || (match[2] !== undefined && !Number.isSafeInteger(Number(match[2])))) fail('brew-command');
    version(match[1]);
    const receiptPath = path.join(path.dirname(path.dirname(binary)), 'INSTALL_RECEIPT.json');
    inspect(binary, 'file'); inspect(receiptPath, 'file');
    const receipt = json(boundedRead(receiptPath));
    if (!['anomalyco/tap', 'homebrew/core'].includes(receipt?.source?.tap)) fail('brew-origin');
    inspect(path.join(prefix, 'var/homebrew/pinned/opencode'), 'pin', true);
    const trust = {command: file, link, snapshots};
    checkBrewTrust(trust);
    return {binary, release: match[1], route: 'homebrew', trust};
}
function windowsNpmShims() {
    const relative = 'node_modules/opencode-ai/bin/opencode.exe';
    const head = '@ECHO off\r\nGOTO start\r\n:find_dp0\r\nSET dp0=%~dp0\r\nEXIT /b\r\n:start\r\nSETLOCAL\r\nCALL :find_dp0\r\n';
    return {
        'opencode.cmd': head + `"%dp0%\\${relative.replaceAll('/', '\\')}"   %*\r\n`,
        opencode: '#!/bin/sh\n' + 'basedir=$(dirname "$(echo "$0" | sed -e \'s,\\\\,/,g\')")\n\n' +
            'case `uname` in\n    *CYGWIN*|*MINGW*|*MSYS*)\n        if command -v cygpath > /dev/null 2>&1; then\n' +
            '            basedir=`cygpath -w "$basedir"`\n        fi\n    ;;\nesac\n\n' + `exec "$basedir/${relative}"   "$@"\n`,
        'opencode.ps1': '#!/usr/bin/env pwsh\n$basedir=Split-Path $MyInvocation.MyCommand.Definition -Parent\n\n' +
            '$exe=""\nif ($PSVersionTable.PSVersion -lt "6.0" -or $IsWindows) {\n' +
            '  # Fix case when both the Windows and Linux builds of Node\n  # are installed in the same directory\n  $exe=".exe"\n}\n' +
            '# Support pipeline input\nif ($MyInvocation.ExpectingInput) {\n' + `  $input | & "$basedir/${relative}"   $args\n` +
            `} else {\n  & "$basedir/${relative}"   $args\n}\nexit $LASTEXITCODE\n`,
    };
}
function packageCommandDirectory(root, home) {
    if (process.platform !== 'win32' && samePath(root, path.join(home, '.local/lib/node_modules/opencode-ai'))) return path.join(home, '.local/bin');
    if (samePath(root, path.join(home, '.bun/install/global/node_modules/opencode-ai'))) return path.join(home, '.bun/bin');
    const relative = path.relative(home, root).replaceAll('\\', '/');
    if (process.platform !== 'win32' && /^\.local\/share\/mise\/installs\/node\/\d+(?:\.\d+){0,2}\/lib\/node_modules\/opencode-ai$/.test(relative)) {
        return path.join(path.dirname(path.dirname(path.dirname(root))), 'bin');
    }
    if (process.platform === 'win32') {
        const npm = path.join(process.env.APPDATA || path.join(home, 'AppData/Roaming'), 'npm');
        if (samePath(root, path.join(npm, 'node_modules/opencode-ai'))) return npm;
        const mise = path.join(process.env.LOCALAPPDATA || path.join(home, 'AppData/Local'), 'mise/installs/node');
        const prefix = path.dirname(path.dirname(root));
        if (/^\d+(?:\.\d+){0,2}$/.test(path.relative(mise, prefix)) && samePath(root, path.join(prefix, 'node_modules/opencode-ai'))) return prefix;
    }
    fail('custom-prefix');
}
async function identify(file, home, nativeTarget, get, directories) {
    const checkPath = (file, leafLink = false) => safePath(file, home, leafLink, directories);
    const brew = brewCopy(file);
    if (!brew) checkPath(file, true);
    let binary = brew?.binary || file, release = brew?.release, route = brew?.route || 'standalone';
    const st = fs.lstatSync(file);
    let windowsShim = false;
    if (process.platform === 'win32' && !st.isSymbolicLink() && path.basename(file) !== 'opencode.exe') {
        const expected = windowsNpmShims()[path.basename(file)];
        if (!expected || !boundedRead(file).equals(Buffer.from(expected))) fail('custom-wrapper');
        binary = path.join(path.dirname(file), 'node_modules/opencode-ai/bin/opencode.exe');
        windowsShim = true;
    }
    if ((st.isSymbolicLink() && !brew) || windowsShim) {
        if (!windowsShim) binary = fs.realpathSync(file);
        const match = binary.match(/^(.*[\\/]node_modules[\\/]opencode-ai)[\\/]bin[\\/]opencode(?:\.exe)?$/);
        if (!match) fail('custom-link');
        const root = match[1]; checkPath(root); checkPath(binary);
        if (!samePath(path.dirname(file), packageCommandDirectory(root, home))) fail('custom-prefix');
        const packageMetadata = path.join(root, 'package.json'); checkPath(packageMetadata);
        const pkg = json(boundedRead(packageMetadata));
        if (pkg.name !== 'opencode-ai' || version(pkg.version)[0] !== 1) fail('package-conflict');
        release = pkg.version; route = 'package';
        const manifest = path.join(path.dirname(path.dirname(root)), 'package.json');
        if (fs.existsSync(manifest)) {
            checkPath(manifest);
            const policy = json(boundedRead(manifest));
            const selected = policy.dependencies?.['opencode-ai'];
            if (selected && !['latest', '*'].includes(selected) && !/^[~^]1\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/.test(selected)) fail('pinned');
            if (policy.overrides?.['opencode-ai'] || policy.resolutions?.['opencode-ai']) fail('pinned');
        }
        if (path.extname(binary) !== '.exe') {
            const published = await artifact('opencode-ai', release, get);
            if (!published.get(`package/bin/${path.basename(binary)}`)?.equals(boundedRead(binary))) fail('custom-wrapper');
            binary = path.join(root, 'bin/.opencode');
        }
        checkPath(binary);
    } else if (!brew && !['.local/bin', '.opencode/bin', '.bun/bin'].some(dir => samePath(path.dirname(file), path.join(home, dir)))) {
        fail('custom-prefix');
    }
    const bytes = boundedRead(binary);
    const content = release ? '' : bytes.toString('latin1');
    const hints = [...new Set([...content.matchAll(/--user-agent=opencode\/([1-9]\d*\.\d+\.\d+)(?=[\x00\s"'\\])/g)].map(match => match[1]))];
    let candidates = release ? [release] : hints.length === 1 ? hints : [...new Set(content.match(/\b[1-9]\d?\.\d{1,4}\.\d{1,4}\b/g) || [])];
    if (!release && hints.length !== 1) {
        const registry = json(await get('https://registry.npmjs.org/opencode-ai'));
        const modern = json(await get('https://registry.npmjs.org/@opencode/cli'));
        candidates = candidates.filter(v => Object.hasOwn(v.startsWith('1.') ? registry.versions || {} : modern.versions || {}, v));
        if (!candidates.length || candidates.length > 8) fail('unverified-copy');
    }
    const variants = [nativeTarget, nativeTarget.replace('-baseline', '')];
    if (nativeTarget.startsWith('linux-')) {
        for (const variant of [...variants]) variants.push(variant.endsWith('-musl') ? variant.slice(0, -5) : variant + '-musl');
    } else if (/^(darwin|windows)-arm64$/.test(nativeTarget)) {
        variants.push(nativeTarget.replace('arm64', 'x64-baseline'), nativeTarget.replace('arm64', 'x64'));
    }
    for (const candidate of candidates) {
        for (const variant of new Set(variants)) {
            let official;
            try { official = await artifact(`${candidate.startsWith('1.') ? 'opencode-' : '@opencode/cli-'}${variant}`, candidate, get); } catch { continue; }
            const executable = official.get(`package/bin/opencode${process.platform === 'win32' ? '.exe' : ''}`);
            if (executable?.equals(bytes)) return {file, binary, release: candidate, route, brewTrust: brew?.trust, nativeHash: digest(bytes), bytes: st.isSymbolicLink() ? null : boundedRead(file), link: st.isSymbolicLink() ? fs.readlinkSync(file) : null};
        }
    }
    fail('unverified-copy');
}
async function install(options = {}) {
    try { return await installChecked(options); } catch (error) { throw nativeFailure('installation', error); }
}
async function installChecked(options) {
    const get = options.get || fetchBytes, runProbe = options.probe || probe;
    const nativeTarget = options.target === undefined ? target() : options.target;
    if (!nativeTarget) return 'unsupported';
    const homeInput = options.home || os.homedir(), home = fs.realpathSync(homeInput);
    const directories = process.platform === 'win32' ? null : new Map();
    const checkPath = (file, leafLink = false) => safePath(file, home, leafLink, directories);
    checkPath(home);
    if (process.platform === 'win32' && process.env.SETUP_OPENCODE_ACL_VERIFIED !== '1') fail('windows-acl');
    const latest = json(await get('https://opencode.ai/update/api/latest/cli/npm'));
    if (latest.channel !== 'latest' || latest.name !== 'cli' || latest.distribution !== 'npm' ||
        latest.active !== true || latest.minimum !== false || latest.metadata?.package !== '@opencode/cli' || version(latest.version)[0] !== 2) fail('release-metadata');
    const release = latest.version, destination = path.join(home, '.local/bin', process.platform === 'win32' ? 'opencode.exe' : 'opencode');
    const receipt = path.join(home, '.local/bin/.setup-opencode-cli.json');
    checkPath(destination, true); checkPath(receipt);
    const found = (options.commands || commands(home)).filter(file => !foreignCommand(file, home));
    if (found.some(file => samePath(path.dirname(file), path.join(home, '.bun/bin')))) {
        const manifest = path.join(home, '.bun/install/global/package.json');
        checkPath(manifest);
        if (fs.existsSync(manifest)) {
            const policy = json(boundedRead(manifest)), selected = policy.dependencies?.['opencode-ai'];
            if (selected && !['latest', '*'].includes(selected) && !/^[~^]1\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/.test(selected)) fail('pinned');
            if (policy.overrides?.['opencode-ai'] || policy.resolutions?.['opencode-ai']) fail('pinned');
        }
    }
    const verifySelection = async (expected, brewTrust) => {
        verifySetupSelection(expected, home, homeInput, options.path ?? process.env.PATH ?? '', brewTrust);
        verifyFreshSelection(expected, home, homeInput);
        if (process.platform === 'win32') {
            let selected;
            try { selected = await options.verifySessionSelection?.(expected); } catch {   }
            if (selected !== true) throw new PolicyError(selected === false ? 'command-conflict' : 'selection-unverified', 'setup-selection');
        }
    };
    let installed = null, installedBytes = null;
    if (fs.existsSync(receipt)) {
        checkPath(destination);
        const record = json(boundedRead(receipt)); version(record.version);
        if (Object.keys(record).some(key => !['package', 'version', 'sha512', 'pinned'].includes(key)) ||
            (Object.hasOwn(record, 'pinned') && typeof record.pinned !== 'boolean')) fail('receipt');
        if (record.package !== `@opencode/cli-${nativeTarget}` || record.sha512 !== digest(boundedRead(destination))) fail('receipt');
        if (record.pinned === true) fail('pinned');
        const files = await artifact(record.package, record.version, get);
        if (!files.get(`package/bin/${path.basename(destination)}`)?.equals(boundedRead(destination))) fail('unverified-copy');
        installed = record.version;
        installedBytes = boundedRead(destination);
    }
    const old = [];
    for (const file of found) {
        if (installed && samePath(file, destination)) continue;
        old.push(await identify(file, home, nativeTarget, get, directories));
    }
    if (old.some(item => compare(item.release, release) > 0)) {
        if (old.length !== 1 || installed) fail('shadowed-newer');
        const item = old[0];
        const revalidate = () => {
            checkAccountDirectories(directories);
            if (item.route === 'homebrew') checkBrewTrust(item.brewTrust);
            else checkPath(item.file);
            if (digest(boundedRead(item.binary)) !== item.nativeHash) fail('changed-copy');
        };
        revalidate();
        await verifySelection(item.file, item.brewTrust);
        revalidate();
        return 'newer';
    }
    if (installed && compare(installed, release) >= 0) {
        if (old.length) fail('shadowed');
        checkAccountDirectories(directories);
        await verifySelection(destination);
        checkAccountDirectories(directories);
        checkPath(destination);
        if (!boundedRead(destination).equals(installedBytes)) fail('changed-copy');
        if (compare(installed, release) > 0) return 'newer';
        const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'setup-opencode-'));
        let probeError;
        try { runProbe(destination, installed, temp); checkAccountDirectories(directories); }
        catch (error) { probeError = nativeFailure('installation', error); throw probeError; }
        finally {
            try { fs.rmSync(temp, {recursive: true, force: true}); }
            catch (error) { throw new RecoveryError(probeError || nativeFailure('installation', error)); }
        }
        return 'current';
    }
    const files = await artifact(`@opencode/cli-${nativeTarget}`, release, get);
    const bytes = files.get(`package/bin/${path.basename(destination)}`);
    if (!bytes || !bytes.length) fail('missing-binary');
    checkAccountDirectories(directories);
    const bin = path.dirname(destination); checkPath(bin);
    fs.mkdirSync(bin, {recursive: true, mode: 0o755}); checkPath(bin);
    const stage = fs.mkdtempSync(path.join(bin, '.setup-opencode-'));
    const staged = path.join(stage, path.basename(destination));
    const backups = []; let promoted = false, completed = false, locked = false, originalError;
    const lock = path.join(bin, '.setup-opencode-cli.lock');
    const previousReceipt = fs.existsSync(receipt) ? boundedRead(receipt) : null;
    try {
        fs.mkdirSync(lock, {mode: 0o700}); locked = true;
        fs.writeFileSync(staged, bytes, {mode: 0o755, flag: 'wx'});
        runProbe(staged, release, stage);
        checkAccountDirectories(directories);
        for (const item of old) {
            if (item.route === 'homebrew') checkBrewTrust(item.brewTrust);
            else checkPath(item.file, !!item.link);
            if (item.link ? fs.readlinkSync(item.file) !== item.link : !boundedRead(item.file).equals(item.bytes)) fail('changed-copy');
            if (digest(boundedRead(item.binary)) !== item.nativeHash) fail('changed-copy');
        }
        if (installed) {
            checkPath(destination);
            if (!boundedRead(destination).equals(installedBytes)) fail('changed-copy');
            old.push({file: destination});
        }
        for (const item of old) {
            checkAccountDirectories(directories);
            if (item.route === 'homebrew') checkBrewTrust(item.brewTrust);
            const backup = item.route === 'homebrew'
                ? path.join(path.dirname(item.file), `.opencode-setup-recovery-${crypto.randomBytes(12).toString('hex')}`)
                : path.join(stage, `previous-${backups.length}`);
            fs.writeFileSync(path.join(stage, 'recovery.json'), JSON.stringify([...backups, [item.file, backup]]), {mode: 0o600});
            fs.renameSync(item.file, backup); backups.push([item.file, backup]);
        }
        for (const [original, backup] of backups) {
            const item = old.find(entry => entry.file === original);
            if (item?.route === 'homebrew') checkBrewBackup(item, backup);
        }
        checkAccountDirectories(directories);
        fs.linkSync(staged, destination); promoted = true;
        fs.unlinkSync(staged);
        runProbe(destination, release, stage);
        await verifySelection(destination);
        checkAccountDirectories(directories);
        checkPath(destination);
        if (!boundedRead(destination).equals(bytes)) fail('changed-copy');
        const remaining = options.commands ? [destination] : commands(home);
        if (remaining.some(file => !samePath(file, destination) && !foreignCommand(file, home))) fail('shadowed');
        const record = JSON.stringify({package: `@opencode/cli-${nativeTarget}`, version: release, sha512: digest(bytes)}) + '\n';
        const nextReceipt = path.join(stage, 'receipt'); fs.writeFileSync(nextReceipt, record, {mode: 0o600, flag: 'wx'});
        checkAccountDirectories(directories);
        checkPath(receipt);
        if (previousReceipt ? !boundedRead(receipt).equals(previousReceipt) : fs.existsSync(receipt)) fail('changed-receipt');
        fs.renameSync(nextReceipt, receipt); completed = true;
        return old.length ? 'migrated' : 'installed';
    } catch (error) {
        originalError = nativeFailure('installation', error);
        throw originalError;
    } finally {
        if (!completed) {
            try {
                checkAccountDirectories(directories);
                if (promoted) {
                    checkPath(destination);
                    if (!boundedRead(destination).equals(bytes)) fail('changed-copy');
                    fs.unlinkSync(destination);
                }
                for (const [original, backup] of backups.reverse()) {
                    const item = old.find(entry => entry.file === original);
                    if (item?.route === 'homebrew') checkBrewBackup(item, backup);
                    try { fs.lstatSync(original); fail('recovery-occupied'); } catch (e) { if (e.code !== 'ENOENT') throw e; }
                    fs.renameSync(backup, original);
                }
            } catch { throw new RecoveryError(originalError); }
        }
        try {
            if (completed && backups.length) fs.chmodSync(stage, 0o700);
            else fs.rmSync(stage, {recursive: true, force: true});
            if (locked) fs.rmdirSync(lock);
        } catch (error) { throw new RecoveryError(originalError || nativeFailure('installation', error)); }
    }
}
module.exports = {version, compare, target, unpack, artifact, identify, install, commands, safePath, brewCopy, windowsNpmShims, probe, fetchBytes, failureResult};
if (require.main === module || process.argv[1] === '-') install().then(result => console.log(`opencode-cli:${result}`)).catch(error => {
    console.log(failureResult(error));
    process.exitCode = 1;
});
'@
        $operation = 'installation'; $reason = 'unrecognized-result'
        $run = Invoke-OpenCodeCliCore -NodePath $node.Source -Code $code
        $output = @($run.Output)
        if ($run.Status -ne 0 -or $output.Count -ne 1) {
            $recovery = $false
            if ($output.Count -eq 1 -and $output[0] -cin @('opencode-cli:recovery-required', 'opencode-cli:recovery-required:failed')) {
                $recovery = $true
            } elseif ($run.Status -ne 0 -and $output.Count -eq 1 -and
                $output[0] -cmatch '\Aopencode-cli:(?:recovery-required:)?download-failed:(latest-release|package-index|package-version|artifact-download|download):http-([1-5][0-9][0-9]|unknown)\z') {
                $recovery = $output[0].StartsWith('opencode-cli:recovery-required:')
                Write-Warning "OpenCode CLI download failed (operation=$($Matches[1]), HTTP=$($Matches[2]))."
            } elseif ($run.Status -ne 0 -and $output.Count -eq 1 -and
                $output[0] -cmatch '\Aopencode-cli:(?:recovery-required:)?policy-failed:installation:relative-path:command-discovery:([1-9][0-9]{0,5}):(empty|relative)\z') {
                $recovery = $output[0].StartsWith('opencode-cli:recovery-required:')
                Write-Warning "OpenCode CLI blocked (operation=installation, reason=relative-path, boundary=command-discovery, component=$($Matches[1]), kind=$($Matches[2]))."
            } elseif ($run.Status -ne 0 -and $output.Count -eq 1 -and
                $output[0] -cmatch '\Aopencode-cli:(?:recovery-required:)?policy-failed:(homebrew-preflight|installation|setup-selection|fresh-shell-selection):(archive|archive-header|archive-path|archive-tail|archive-truncated|archive-type|artifact-identity|artifact-metadata|brew-command|brew-origin|brew-path|brew-snapshot-changed|changed-copy|changed-receipt|custom-link|custom-prefix|custom-wrapper|duplicate-metadata|integrity|libc|metadata|missing-binary|outside-home|package-conflict|pinned|receipt|recovery-occupied|relative-path|release-metadata|shadowed|shadowed-newer|unreachable|unsafe-file|unsafe-path|unverified-copy|url|version|version-probe|windows-acl|foreign-command|command-conflict|selection-unverified|native-(EACCES|EPERM|ENOENT|EIO|EEXIST|ENOTDIR|ELOOP|ENOSPC|EROFS|ETIMEDOUT|ENOBUFS))\z') {
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
$null = 'END_GENERATED_OPENCODE_CLI'

function Install-CodexCli {
    Write-Host "$arrow Installing/updating Codex CLI..." -ForegroundColor Cyan

    $bunPath = "$env:USERPROFILE\.bun\bin"
    if (Test-Path $bunPath) {
        $env:PATH = "$bunPath;$env:PATH"
    }
    if (Get-Command bun -ErrorAction SilentlyContinue) {
        $bunPackages = ''
        try { $bunPackages = (bun pm ls -g 2>$null) -join "`n" } catch { $bunPackages = '' }
        if ($bunPackages -match [regex]::Escape('@openai/codex')) {
            Write-Host "$arrow Removing Node-dependent Bun Codex package..." -ForegroundColor Cyan
            try {
                bun remove -g '@openai/codex' | Out-Null
            }
            catch {
                Write-Host "$failIcon Failed to remove Bun's @openai/codex package: $($_.Exception.Message)" -ForegroundColor Red
                return
            }
        }
    }

    $installDir = "$env:USERPROFILE\.local\bin"
    $codexExe = Join-Path $installDir 'codex.exe'
    New-Item -ItemType Directory -Force -Path $installDir | Out-Null

    $tmp = New-Item -ItemType Directory -Force -Path (Join-Path $env:TEMP ("codex-install-" + [guid]::NewGuid()))
    try {
        $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'aarch64' } else { 'x86_64' }
        $asset = "codex-$arch-pc-windows-msvc.exe.zip"
        $url = "https://github.com/openai/codex/releases/latest/download/$asset"
        $archive = Join-Path $tmp.FullName $asset

        Write-Debug "Downloading Codex CLI from $url"
        Invoke-WebRequest -Uri $url -OutFile $archive -UseBasicParsing
        Expand-Archive -Path $archive -DestinationPath $tmp.FullName -Force

        $downloaded = Get-ChildItem "$tmp.FullName\codex-*.exe" | Select-Object -First 1
        if (-not $downloaded) {
            Write-Host "$failIcon Downloaded Codex release archive is missing its executable." -ForegroundColor Red
            return
        }
        Copy-Item $downloaded.FullName $codexExe -Force

        $userPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
        $userEntries = @()
        if ($userPath) {
            $userEntries = @($userPath -split ';' | Where-Object { $_ })
        }
        if (-not ($userEntries -contains $installDir)) {
            if ($userPath) {
                [Environment]::SetEnvironmentVariable('PATH', ($userPath.TrimEnd(';') + ';' + $installDir), 'User')
            }
            else {
                [Environment]::SetEnvironmentVariable('PATH', $installDir, 'User')
            }
        }
        $env:PATH = "$installDir;$env:PATH"

        $env:NODE_OPTIONS = $null
        $env:NODE_PATH = $null
        $versionOutput = & $codexExe --version 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $versionOutput) {
            Write-Host "$failIcon Codex CLI installed, but its smoke test failed." -ForegroundColor Red
            return
        }
        Write-Host "$success Codex CLI installed/updated ($($versionOutput -join ' ') => $codexExe)." -ForegroundColor Green
    }
    catch {
        Write-Host "$failIcon Failed to install Codex CLI: $($_.Exception.Message)" -ForegroundColor Red
    }
    finally {
        Remove-Item $tmp.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }
}



function Install-PortlessCli {
    if (Get-Command portless -ErrorAction SilentlyContinue) {
        Write-Debug "Portless CLI is already installed."
        return
    }

    Write-Host "$arrow Installing Portless CLI..." -ForegroundColor Cyan

    $bunPath = "$env:USERPROFILE\.bun\bin"
    if (Test-Path $bunPath) {
        $env:PATH = "$bunPath;$env:PATH"
    }

    if (-not (Get-Command bun -ErrorAction SilentlyContinue)) {
        Write-Host "$warnIcon Bun not found. Cannot install Portless CLI." -ForegroundColor Yellow
        Write-Host "  Install Bun first, then run: bun install -g portless" -ForegroundColor DarkGray
        return
    }

    if (-not (Get-Command tailscale -ErrorAction SilentlyContinue)) {
        Write-Host "$warnIcon Tailscale not found. Portless requires Tailscale to create tunnels." -ForegroundColor Yellow
    }

    try {
        bun install -g portless
        if ($?) {
            Write-Host "$success Portless CLI installed." -ForegroundColor Green
        }
        else {
            Write-Host "$failIcon Failed to install Portless CLI." -ForegroundColor Red
        }
    }
    catch {
        Write-Host "$failIcon Failed to install Portless CLI: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Test-RtkTokenKiller {
    param([Parameter(Mandatory=$true)][string]$Binary)

    if (-not (Test-Path -LiteralPath $Binary -PathType Leaf)) {
        return $false
    }

    try {
        & $Binary gain *> $null
        if ($LASTEXITCODE -eq 0) {
            return $true
        }

        $output = (& $Binary --help 2>&1 | Out-String)
        return ($output -match 'Rust Token Killer|token-optimized|Initialize rtk instructions')
    }
    catch {
        try {
            $content = [System.IO.File]::ReadAllText($Binary)
            return ($content -match 'Rust Token Killer|rtk-ai/rtk')
        }
        catch {
            return $false
        }
    }
}

function Test-RtkPathExists {
    param([Parameter(Mandatory=$true)][string]$Path)

    return ($null -ne (Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue))
}

function Remove-RtkPathStrict {
    param([Parameter(Mandatory=$true)][string]$Path)

    if (-not (Test-RtkPathExists -Path $Path)) {
        return
    }

    try {
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
        }
        else {
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
        }
    }
    catch {
        throw "Failed to remove retired RTK path: $Path. $($_.Exception.Message)"
    }

    if (Test-RtkPathExists -Path $Path) {
        throw "Retired RTK path remains after cleanup: $Path"
    }

    $script:RtkCleanupHadResources = $true
}

function Set-RtkFileContent {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Content
    )

    $current = [System.IO.File]::ReadAllText($Path)
    if ($current -ceq $Content) {
        return
    }

    try {
        [System.IO.File]::WriteAllText(
            $Path,
            $Content,
            [System.Text.UTF8Encoding]::new($false)
        )
    }
    catch {
        throw "Failed to update shared agent file during RTK cleanup: $Path. $($_.Exception.Message)"
    }

    $script:RtkCleanupHadResources = $true
}

function Test-RtkGeneratedGeminiMd {
    param([Parameter(Mandatory=$true)][string]$Path)

    $inCode = $false
    $sawTitle = $false
    foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
        if ($line -match '^```') {
            $inCode = -not $inCode
            continue
        }
        if ($inCode) {
            if ($line -match '^\s*$|^\s*(rtk|which\s+rtk)(\s|$)') {
                continue
            }
            return $false
        }
        if ($line -match '^\s*$') {
            continue
        }
        if ($line -match '^# RTK([\s-]|$)') {
            $sawTitle = $true
            continue
        }
        if ($line -match '^## (Meta Commands|Installation Verification|Hook-Based Usage)') {
            continue
        }
        if ($line -match '^\*\*Usage\*\*:|^⚠️ \*\*Name collision\*\*:') {
            continue
        }
        if ($line -match '^(All other commands|Example:|Refer to CLAUDE\.md)') {
            continue
        }
        return $false
    }

    return ($sawTitle -and -not $inCode)
}

function Assert-RtkGeminiMdSafe {
    param([Parameter(Mandatory=$true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return
    }

    $content = [System.IO.File]::ReadAllText($Path)
    if ($content -notmatch '(?i)(^|[^A-Za-z0-9_])rtk([^A-Za-z0-9_]|$)|Rust Token Killer') {
        return
    }

    $script:RtkCleanupHadResources = $true
    if (Test-RtkGeneratedGeminiMd -Path $Path) {
        $script:RtkCleanupRemoveGeminiMd = $true
        return
    }

    throw "RTK cleanup found mixed user and RTK content in shared file: $Path. Move the user content out of this file, then run setup again."
}

function Remove-RtkInstructionText {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$ManagedReference
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return
    }

    $content = [System.IO.File]::ReadAllText($Path)
    if ($content -notmatch '(?m)^\s*@RTK\.md\s*$|^\s*@.*[/\\]RTK\.md\s*$|<!--\s*rtk-instructions') {
        return
    }

    $output = [System.Collections.Generic.List[string]]::new()
    $inRtkBlock = $false
    $normalizedReference = $ManagedReference -replace '\\', '/'
    foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
        $trimmed = $line.Trim()
        $normalizedLine = $trimmed -replace '\\', '/'
        if ($trimmed -match '^<!--\s*rtk-instructions') {
            $inRtkBlock = $true
            continue
        }
        if ($inRtkBlock) {
            if ($trimmed -eq '<!-- /rtk-instructions -->') {
                $inRtkBlock = $false
            }
            continue
        }
        if ($trimmed -eq '@RTK.md' -or $normalizedLine -eq $normalizedReference) {
            continue
        }
        $output.Add($line)
    }

    if ($inRtkBlock) {
        throw "RTK cleanup found an incomplete managed block in: $Path"
    }

    $newContent = $output -join [Environment]::NewLine
    if ($content.EndsWith("`n")) {
        $newContent += [Environment]::NewLine
    }
    Set-RtkFileContent -Path $Path -Content $newContent
}

function Remove-RtkPiInstructions {
    param([Parameter(Mandatory=$true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return
    }

    $lines = [System.IO.File]::ReadAllLines($Path)
    $heading = '## RTK token-optimized commands'
    $start = [Array]::IndexOf($lines, $heading)
    if ($start -lt 0) {
        return
    }

    $end = $lines.Count
    for ($index = $start + 1; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -match '^## ') {
            $end = $index
            break
        }
    }

    $expected = @(
        '## RTK token-optimized commands',
        '',
        '- RTK (`rtk-ai/rtk`) is installed by the machine setup scripts when available. Prefer `rtk <command>` for noisy shell commands with supported filters (`git`, `gh`, tests, build/lint tools, package managers, file/search commands) unless full raw output is required.',
        '- Bypass RTK for one command with `RTK_DISABLED=1 <command>` or by running the raw command directly when exact output formatting matters.',
        ''
    )
    $section = @($lines[$start..($end - 1)])
    if (($section -join "`n") -cne ($expected -join "`n")) {
        throw "RTK cleanup found mixed user and RTK content in shared file: $Path. Move the user content out of the RTK section, then run setup again."
    }

    $output = [System.Collections.Generic.List[string]]::new()
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($index -ge $start -and $index -lt $end) {
            continue
        }
        $output.Add($lines[$index])
    }

    $content = [System.IO.File]::ReadAllText($Path)
    $newContent = $output -join [Environment]::NewLine
    if ($content.EndsWith("`n")) {
        $newContent += [Environment]::NewLine
    }
    Set-RtkFileContent -Path $Path -Content $newContent
}

function Remove-RtkJsonHooks {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$HookKey,
        [Parameter(Mandatory=$true)][string]$CommandPattern
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return
    }

    $content = [System.IO.File]::ReadAllText($Path)
    if ($content -notmatch $CommandPattern) {
        return
    }

    try {
        $settings = $content | ConvertFrom-Json
    }
    catch {
        throw "Failed to parse shared agent settings during RTK cleanup: $Path. $($_.Exception.Message)"
    }

    $hooksProperty = $settings.PSObject.Properties['hooks']
    if ($null -eq $hooksProperty) {
        return
    }
    $hookEntriesProperty = $settings.hooks.PSObject.Properties[$HookKey]
    if ($null -eq $hookEntriesProperty) {
        return
    }

    $kept = [System.Collections.Generic.List[object]]::new()
    $removed = $false
    foreach ($entry in @($hookEntriesProperty.Value)) {
        $managed = $false
        foreach ($hook in @($entry.hooks)) {
            if ($null -ne $hook.command -and [string]$hook.command -match $CommandPattern) {
                $managed = $true
                break
            }
        }
        if ($managed) {
            $removed = $true
        }
        else {
            $kept.Add($entry)
        }
    }

    if (-not $removed) {
        return
    }

    if ($kept.Count -eq 0) {
        $settings.hooks.PSObject.Properties.Remove($HookKey)
    }
    else {
        $settings.hooks.$HookKey = @($kept)
    }
    if ($settings.hooks.PSObject.Properties.Count -eq 0) {
        $settings.PSObject.Properties.Remove('hooks')
    }

    $newContent = $settings | ConvertTo-Json -Depth 100
    $newContent += [Environment]::NewLine
    Set-RtkFileContent -Path $Path -Content $newContent
}

function Invoke-RtkUpstreamUninstall {
    param(
        [Parameter(Mandatory=$true)][string]$Binary,
        [Parameter(Mandatory=$true)][ValidateSet('codex', 'gemini')][string]$Mode,
        [string]$ConfigDir
    )

    $originalCodexHome = $env:CODEX_HOME
    try {
        if ($Mode -eq 'codex') {
            $env:CODEX_HOME = $ConfigDir
            $output = & $Binary init -g --codex --uninstall 2>&1
        }
        else {
            $output = & $Binary init -g --gemini --uninstall 2>&1
        }
        if ($LASTEXITCODE -ne 0) {
            Write-Debug "RTK $Mode uninstall was not available; using deterministic cleanup. $($output | Out-String)"
        }
    }
    catch {
        Write-Debug "RTK $Mode uninstall was not available; using deterministic cleanup. $($_.Exception.Message)"
    }
    finally {
        $env:CODEX_HOME = $originalCodexHome
    }
}

function Remove-RtkPathEntry {
    param([Parameter(Mandatory=$true)][string]$RtkDir)

    $normalizedRtkDir = $RtkDir.TrimEnd('\', '/')
    $processEntries = @($env:PATH -split ';' | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_) -and $_.TrimEnd('\', '/') -ine $normalizedRtkDir
    })
    $newProcessPath = $processEntries -join ';'
    if ($newProcessPath -cne $env:PATH) {
        $env:PATH = $newProcessPath
        $script:RtkCleanupHadResources = $true
    }

    $userPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
    if ([string]::IsNullOrWhiteSpace($userPath)) {
        return
    }
    $userEntries = @($userPath -split ';' | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_) -and $_.TrimEnd('\', '/') -ine $normalizedRtkDir
    })
    $newUserPath = $userEntries -join ';'
    if ($newUserPath -cne $userPath) {
        [Environment]::SetEnvironmentVariable('PATH', $newUserPath, 'User')
        $script:RtkCleanupHadResources = $true
    }
}

function Remove-RtkResources {
    $profileRoot = [System.IO.Path]::GetFullPath($env:USERPROFILE)
    $rtkDir = Join-Path $env:LOCALAPPDATA 'rtk\bin'
    $managedBinary = Join-Path $rtkDir 'rtk.exe'
    $binaryIsRtk = $false
    $script:RtkCleanupHadResources = $false
    $script:RtkCleanupRemoveGeminiMd = $false

    $claudeDirs = @((Join-Path $profileRoot '.claude'))
    if (-not [string]::IsNullOrWhiteSpace($env:CLAUDE_CONFIG_DIR)) {
        $claudeDirs += $env:CLAUDE_CONFIG_DIR
    }
    $claudeDirs = @($claudeDirs | Select-Object -Unique)

    $codexDirs = @((Join-Path $profileRoot '.codex'))
    if (-not [string]::IsNullOrWhiteSpace($env:CODEX_HOME)) {
        $codexDirs += $env:CODEX_HOME
    }
    $codexDirs = @($codexDirs | Select-Object -Unique)

    $piDirs = @((Join-Path $profileRoot '.pi\agent'))
    if (-not [string]::IsNullOrWhiteSpace($env:PI_CODING_AGENT_DIR)) {
        $piDirs += $env:PI_CODING_AGENT_DIR
    }
    $piDirs = @($piDirs | Select-Object -Unique)

    $geminiDir = Join-Path $profileRoot '.gemini'
    $geminiMd = Join-Path $geminiDir 'GEMINI.md'
    Assert-RtkGeminiMdSafe -Path $geminiMd
    if ($script:PiProfileMutationsBlocked) { $piDirs = @() }
    foreach ($piDir in $piDirs) {
        Remove-RtkPiInstructions -Path (Join-Path $piDir 'AGENTS.md')
    }

    if (Test-RtkPathExists -Path $managedBinary) {
        if (Test-RtkTokenKiller -Binary $managedBinary) {
            $binaryIsRtk = $true
            $script:RtkCleanupHadResources = $true
        }
        else {
            Write-Warning "Preserving unrelated or unverified rtk command at $managedBinary."
        }
    }

    if ($binaryIsRtk) {
        foreach ($codexDir in $codexDirs) {
            Invoke-RtkUpstreamUninstall -Binary $managedBinary -Mode codex -ConfigDir $codexDir
        }
        if (-not (Test-Path -LiteralPath $geminiMd -PathType Leaf) -or $script:RtkCleanupRemoveGeminiMd) {
            Invoke-RtkUpstreamUninstall -Binary $managedBinary -Mode gemini
        }
        else {
            Write-Debug 'Preserving unrelated Gemini instructions and using deterministic RTK cleanup.'
        }
    }

    foreach ($claudeDir in $claudeDirs) {
        Remove-RtkInstructionText -Path (Join-Path $claudeDir 'CLAUDE.md') -ManagedReference '@RTK.md'
        Remove-RtkJsonHooks -Path (Join-Path $claudeDir 'settings.json') -HookKey 'PreToolUse' -CommandPattern 'rtk hook claude|rtk-rewrite\.sh'
        Remove-RtkPathStrict -Path (Join-Path $claudeDir 'RTK.md')
        Remove-RtkPathStrict -Path (Join-Path $claudeDir 'hooks\rtk-rewrite.sh')
        Remove-RtkPathStrict -Path (Join-Path $claudeDir 'hooks\.rtk-hook.sha256')
    }

    foreach ($codexDir in $codexDirs) {
        Remove-RtkInstructionText -Path (Join-Path $codexDir 'AGENTS.md') -ManagedReference "@$codexDir\RTK.md"
        Remove-RtkPathStrict -Path (Join-Path $codexDir 'RTK.md')
    }

    Remove-RtkJsonHooks -Path (Join-Path $geminiDir 'settings.json') -HookKey 'BeforeTool' -CommandPattern 'rtk hook gemini|rtk-hook-gemini\.sh'
    Remove-RtkPathStrict -Path (Join-Path $geminiDir 'hooks\rtk-hook-gemini.sh')
    Remove-RtkPathStrict -Path (Join-Path $geminiDir 'hooks\.rtk-hook.sha256')
    if ($script:RtkCleanupRemoveGeminiMd) {
        Remove-RtkPathStrict -Path $geminiMd
    }

    if (-not [string]::IsNullOrWhiteSpace($env:APPDATA)) {
        Remove-RtkPathStrict -Path (Join-Path $env:APPDATA 'rtk')
    }
    if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        $localRtkRoot = Join-Path $env:LOCALAPPDATA 'rtk'
        if ($binaryIsRtk) {
            Remove-RtkPathStrict -Path $localRtkRoot
        }
        elseif (Test-RtkPathExists -Path $localRtkRoot) {
            $children = @(Get-ChildItem -LiteralPath $localRtkRoot -Force -ErrorAction SilentlyContinue | Where-Object { $_.FullName -ne $rtkDir })
            foreach ($child in $children) {
                Remove-RtkPathStrict -Path $child.FullName
            }
        }
    }
    Remove-RtkPathEntry -RtkDir $rtkDir

    if ($script:RtkCleanupHadResources) {
        Write-Success 'Legacy RTK resources removed.'
    }
    else {
        Write-Debug 'No legacy RTK resources found.'
    }
}

function Test-PiNodeRuntimeReady {
    try {
        & node -e 'const [major, minor] = process.versions.node.split(''.'').map(Number); process.exit((major > 22 || (major === 22 && minor >= 19)) && typeof require(''node:fs'').globSync === ''function'' ? 0 : 1)' *> $null
        return ($LASTEXITCODE -eq 0)
    }
    catch { return $false }
}

function Test-SharedNodeRuntimeReady {
    param([string]$Node = 'node')
    try {
        & $Node -e 'const [major, minor] = process.versions.node.split(''.'').map(Number); process.exit((major > 22 || (major === 22 && minor >= 20)) && typeof require(''node:fs'').globSync === ''function'' ? 0 : 1)' *> $null
        return ($LASTEXITCODE -eq 0)
    }
    catch { return $false }
}

function Get-SharedNodeFallback {
    $architecture = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
    if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT -and $architecture -in @('AMD64', 'ARM64')) {
        return 'node@24'
    }
    return $null
}

function Get-SharedNodePowerShellHost {
    return (Get-Process -Id $PID -ErrorAction Stop).Path
}

function Invoke-SharedNodeShellProcess {
    param([System.Diagnostics.ProcessStartInfo]$StartInfo)
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $StartInfo
    try {
        if (-not $process.Start()) { return $false }
        $process.StandardInput.Close()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(60000)) {
            $process.Kill()
            $process.WaitForExit()
            return $false
        }
        $null = $stdout.GetAwaiter().GetResult()
        $null = $stderr.GetAwaiter().GetResult()
        return ($process.ExitCode -eq 0)
    }
    catch { return $false }
    finally { $process.Dispose() }
}

function Test-SharedNodeShell {
    param([string]$CanonicalPi = '')
    try {
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = Get-SharedNodePowerShellHost
        $startInfo.WorkingDirectory = $env:USERPROFILE
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardInput = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $persistedPath = @(
            [Environment]::GetEnvironmentVariable('Path', 'Machine'),
            [Environment]::GetEnvironmentVariable('Path', 'User')
        ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        $savedPath = $env:PATH
        try {
            $env:PATH = ''
            $startInfo.EnvironmentVariables['PATH'] = [Environment]::ExpandEnvironmentVariables(($persistedPath -join ';'))
        }
        finally { $env:PATH = $savedPath }
        foreach ($name in @($startInfo.EnvironmentVariables.Keys)) {
            if ($name -match '^(__MISE_|FNM_)|^MISE_(SHELL|.*_VERSION|TOOL_OPTS__NODE)$|^NODE_(PATH|OPTIONS)$') {
                $startInfo.EnvironmentVariables.Remove($name)
            }
        }
        $startInfo.EnvironmentVariables['MISE_AUTO_INSTALL'] = 'false'
        $startInfo.EnvironmentVariables['MISE_NODE_COMPILE'] = 'false'
        $encodedPi = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($CanonicalPi))
        $probe = @'
$ErrorActionPreference = 'Stop'
try {
    if ((Get-Variable __SetupSharedNodeActivation -Scope Global -ValueOnly -ErrorAction SilentlyContinue) -ne 1) { exit 1 }
    if (-not (Get-Command mise -ErrorAction SilentlyContinue)) { exit 1 }
    $pathPolicy = (& mise settings get activate_aggressive 2>$null | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $pathPolicy -ne 'true') { exit 1 }
    $expectedNode = (& mise which -C $env:USERPROFILE node 2>$null | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or -not $expectedNode) { exit 1 }
    & node -e 'const fs = require(''node:fs''); const [major, minor] = process.versions.node.split(''.'').map(Number); process.exit((major > 22 || (major === 22 && minor >= 20)) && typeof fs.globSync === ''function'' && fs.realpathSync(process.execPath) === fs.realpathSync(process.argv[1]) ? 0 : 1)' $expectedNode *> $null
    if ($LASTEXITCODE -ne 0) { exit 1 }
    $nodePinTools = (& mise settings get idiomatic_version_file_enable_tools 2>$null | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) { exit 1 }
    # Base64 data and single-quoted JS literals survive PowerShell 5.1's native
    # argument transport, which strips embedded double quotes from raw JSON.
    $encodedPinTools = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($nodePinTools))
    & node -e 'const tools = JSON.parse(Buffer.from(process.argv[1], ''base64'').toString()); process.exit(Array.isArray(tools) && tools.includes(''node'') ? 0 : 1)' $encodedPinTools *> $null
    if ($LASTEXITCODE -ne 0) { exit 1 }
    & npm --version *> $null
    if ($LASTEXITCODE -ne 0) { exit 1 }
    $canonicalPi = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__CANONICAL_PI__'))
    if ($canonicalPi) {
        $piCommand = Get-Command pi -ErrorAction Stop
        if ($piCommand.Source -ne $canonicalPi) { exit 1 }
        $piVersion = (& pi --version 2>$null | Out-String).Trim()
        if ($LASTEXITCODE -ne 0 -or -not $piVersion) { exit 1 }
    }
    exit 0
}
catch { exit 1 }
'@
        $probe = $probe.Replace('__CANONICAL_PI__', $encodedPi)
        $startInfo.Arguments = '-NoLogo -NonInteractive -EncodedCommand ' + [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($probe))
        return (Invoke-SharedNodeShellProcess -StartInfo $startInfo)
    }
    catch { return $false }
}

function Enable-SharedNodeRuntime {
    $savedCompile = [Environment]::GetEnvironmentVariable('MISE_NODE_COMPILE', 'Process')
    $savedAutoInstall = [Environment]::GetEnvironmentVariable('MISE_AUTO_INSTALL', 'Process')
    try {
        $env:MISE_NODE_COMPILE = 'false'
        $env:MISE_AUTO_INSTALL = 'false'
        $pathCandidates = @(
            [Environment]::GetEnvironmentVariable('Path', 'User'),
            [Environment]::GetEnvironmentVariable('Path', 'Machine'),
            (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links'),
            (Join-Path $env:USERPROFILE '.local\bin')
        ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        $env:PATH = (($pathCandidates + @($env:PATH)) -join ';')
        if (-not (Get-Command mise -ErrorAction SilentlyContinue)) {
            Write-Warning 'mise is required to verify the shared Node runtime.'
            return $false
        }
        $inventoryRoot = [System.IO.Path]::GetPathRoot($env:USERPROFILE)
        if (-not $inventoryRoot) { throw 'USERPROFILE must be an absolute path.' }
        & mise settings add -C $inventoryRoot idiomatic_version_file_enable_tools node *> $null
        if ($LASTEXITCODE -ne 0) { throw 'Cannot enable mise support for .node-version/.nvmrc pins.' }
        & mise settings set -C $inventoryRoot activate_aggressive true *> $null
        if ($LASTEXITCODE -ne 0) { throw 'Cannot configure mise PATH precedence.' }
        for ($attempt = 1; $attempt -le 2; $attempt++) {
            $inventoryText = (& mise ls -C $inventoryRoot --global --json node 2>$null | Out-String).Trim()
            if ($LASTEXITCODE -ne 0 -or -not $inventoryText) { throw 'Cannot read global mise Node inventory.' }
            $parsed = ConvertFrom-Json -InputObject ('{"inventory":' + $inventoryText + '}') -ErrorAction Stop
            $inventoryObject = $parsed.inventory
            if ($inventoryObject -is [array]) {
                $inventory = @($inventoryObject)
            }
            elseif ($inventoryObject -is [System.Management.Automation.PSCustomObject]) {
                if ($null -eq $inventoryObject.node) { $inventory = @() }
                elseif ($inventoryObject.node -is [array]) { $inventory = @($inventoryObject.node) }
                else { throw 'Invalid global mise Node inventory.' }
            }
            else { throw 'Invalid global mise Node inventory.' }
            if ($inventory.Count -gt 1) { throw 'Multiple global Node versions are configured; select one compatible default.' }
            $selection = if ($inventory.Count) { $inventory[0] } else { $null }
            if ($inventory.Count -and ($selection -isnot [System.Management.Automation.PSCustomObject] -or [string]::IsNullOrWhiteSpace($selection.version))) {
                throw 'Invalid global mise Node inventory row.'
            }
            $nodePath = if ($selection.install_path) { Join-Path $selection.install_path 'node.exe' } else { $null }
            $installed = $nodePath -and (Test-Path -LiteralPath $nodePath -PathType Leaf)
            if ($installed -and (Test-SharedNodeRuntimeReady -Node $nodePath)) { break }
            if ($attempt -eq 2) { throw 'Global mise Node is still unavailable or incompatible after installation.' }
            $runtime = Get-SharedNodeFallback
            if (-not $runtime) { throw 'No supported prebuilt Node runtime for this platform.' }
            $version = [string]$selection.version
            $compatibleVersion = $false
            if ($version -match '^\d+(\.\d+){0,2}$') {
                $parts = $version.Split('.')
                $compatibleVersion = [int]$parts[0] -gt 22 -or ([int]$parts[0] -eq 22 -and ($parts.Count -eq 1 -or [int]$parts[1] -ge 20))
            }
            if (-not $installed -and $compatibleVersion) {
                Write-Message "Installing the configured shared Node runtime ($version)..."
                & mise install -C $env:USERPROFILE "node@$version" *> $null
            }
            else {
                Write-Message "Selecting shared $runtime for Pi and the skills CLI..."
                & mise use -g -y -C $env:USERPROFILE $runtime *> $null
            }
            if ($LASTEXITCODE -ne 0) { throw 'Failed to install/select the shared Node runtime.' }
        }
        $miseEnv = (& mise env -C $env:USERPROFILE -s pwsh 2>$null | Out-String)
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($miseEnv)) { throw 'Failed to activate the shared mise environment.' }
        Invoke-Expression -Command $miseEnv -ErrorAction Stop | Out-Null
        if (-not (Test-SharedNodeRuntimeReady)) { throw 'HOME does not select Node >=22.20 with fs.globSync; review mise overrides.' }
        & npm --version *> $null
        if ($LASTEXITCODE -ne 0) { throw 'npm is unavailable under the shared Node runtime.' }
        if (-not (Test-SharedNodeShell)) {
            Write-Message 'Refreshing chezmoi-managed PowerShell activation for the shared Node runtime...'
            $shellRepaired = $false
            try {
                if (Get-Command chezmoi -ErrorAction SilentlyContinue) {
                    $source = (& chezmoi source-path 2>$null | Out-String).Trim()
                    if ($LASTEXITCODE -eq 0 -and [IO.Path]::IsPathRooted($source)) {
                        $updater = Join-Path $source '.chezmoiscripts/run_before_powershell-mise.cmd.tmpl'
                        & chezmoi apply --force --include=scripts --source-path $updater *> $null
                        $shellRepaired = $LASTEXITCODE -eq 0
                    }
                }
            }
            catch { $shellRepaired = $false }
            if (-not $shellRepaired) {
                throw 'Shared Node shell repair failed: chezmoi could not apply the managed PowerShell profiles. Check dotfiles access and update the source.'
            }
            if (-not (Test-SharedNodeShell)) {
                throw 'Shared Node shell repair failed verification. Update the dotfiles source and review HOME overrides or custom profile hooks.'
            }
        }
        Write-Debug 'Shared Node is ready in setup and a fresh PowerShell.'
        return $true
    }
    catch {
        Write-Warning "$($_.Exception.Message) Leaving Pi unchanged."
        return $false
    }
    finally {
        $env:MISE_NODE_COMPILE = $savedCompile
        $env:MISE_AUTO_INSTALL = $savedAutoInstall
    }
}

function Enable-PiNodeRuntime {
    return ((Enable-SharedNodeRuntime) -and (Test-PiNodeRuntimeReady))
}

function Get-AttentionSpanCleanupDirectories {
    param(
        [Parameter(Mandatory=$true)][string]$DefaultDirectory,
        [AllowEmptyString()][string]$ActiveDirectory
    )

    $directories = [System.Collections.Generic.List[string]]::new()
    foreach ($candidate in @($DefaultDirectory, $ActiveDirectory)) {
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            continue
        }
        try {
            $resolved = [System.IO.Path]::GetFullPath($candidate)
        }
        catch {
            throw "Could not safely resolve an Attention-kind cleanup directory: $candidate"
        }
        if (-not $directories.Contains($resolved)) {
            $directories.Add($resolved)
        }
    }
    return $directories.ToArray()
}

function Assert-AttentionSpanStyleIsSafe {
    param([Parameter(Mandatory=$true)][string]$Path)

    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if ($null -eq $item) {
        return
    }
    if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        return
    }
    if ($item.PSIsContainer) {
        throw "Attention-kind style target is not a file or symlink: $Path"
    }
}

function Assert-AttentionSpanSettingsAreSafe {
    param([Parameter(Mandatory=$true)][string]$Path)

    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if ($null -eq $item) {
        return
    }
    if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Cannot safely remove Attention-kind from symlinked Claude settings: $Path"
    }
    if ($item.PSIsContainer) {
        throw "Claude settings target is not a regular file: $Path"
    }

    try {
        $content = [System.IO.File]::ReadAllText($Path)
        if ([string]::IsNullOrWhiteSpace($content)) {
            throw "empty settings"
        }
        $settings = $content | ConvertFrom-Json -ErrorAction Stop
        if ($settings -isnot [System.Management.Automation.PSCustomObject]) {
            throw "settings are not an object"
        }
    }
    catch {
        throw "Claude settings are not a valid JSON object: $Path"
    }
}

function Assert-AttentionSpanManagedFileIsSafe {
    param([Parameter(Mandatory=$true)][string]$Path)

    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if ($null -eq $item) {
        return
    }
    if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Cannot safely remove Attention-kind from symlinked shared instructions: $Path"
    }
    if ($item.PSIsContainer) {
        throw "Shared instruction target is not a regular file: $Path"
    }

    [string[]]$lines = @([System.IO.File]::ReadAllLines($Path))
    $beginMarker = "<!-- attention-span:start -->"
    $endMarker = "<!-- attention-span:end -->"
    $beginIndexes = @($lines | ForEach-Object -Begin { $index = 0 } -Process {
        $current = $index
        $index++
        if ($_ -ceq $beginMarker) { $current }
    })
    $endIndexes = @($lines | ForEach-Object -Begin { $index = 0 } -Process {
        $current = $index
        $index++
        if ($_ -ceq $endMarker) { $current }
    })

    if ($beginIndexes.Count -eq 0 -and $endIndexes.Count -eq 0) {
        return
    }
    if ($beginIndexes.Count -ne 1 -or $endIndexes.Count -ne 1 -or $beginIndexes[0] -ge $endIndexes[0]) {
        throw "Attention-kind markers are malformed in $Path; leaving it unchanged."
    }
}

function Set-AttentionSpanCleanupFile {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][AllowEmptyString()][string]$Content
    )

    $temporaryPath = Join-Path (Split-Path -Parent $Path) ".attention-cleanup-$([guid]::NewGuid()).tmp"
    try {
        $encoding = [System.Text.UTF8Encoding]::new($false)
        [System.IO.File]::WriteAllText($temporaryPath, $Content, $encoding)
        Move-Item -LiteralPath $temporaryPath -Destination $Path -Force -ErrorAction Stop
    }
    catch {
        Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
        throw "Failed to atomically update Attention-kind cleanup target: $Path. $($_.Exception.Message)"
    }
}

function Remove-AttentionSpanStyle {
    param([Parameter(Mandatory=$true)][string]$Path)

    Assert-AttentionSpanStyleIsSafe -Path $Path
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if ($null -eq $item) {
        return
    }
    try {
        Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
    }
    catch {
        throw "Failed to remove retired Attention-kind style: $Path. $($_.Exception.Message)"
    }
    if ($null -ne (Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue)) {
        throw "Retired Attention-kind style remains after cleanup: $Path"
    }
    $script:AttentionSpanCleanupRemoved = $true
}

function Remove-AttentionSpanSetting {
    param([Parameter(Mandatory=$true)][string]$Path)

    Assert-AttentionSpanSettingsAreSafe -Path $Path
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return
    }
    $settings = [System.IO.File]::ReadAllText($Path) | ConvertFrom-Json -ErrorAction Stop
    $property = @($settings.PSObject.Properties | Where-Object { $_.Name -ceq "outputStyle" } | Select-Object -First 1)
    if ($property.Count -eq 0 -or $property[0].Value -cne "Attention-kind") {
        return
    }

    $settings.PSObject.Properties.Remove("outputStyle")
    $json = ($settings | ConvertTo-Json -Depth 100) + [Environment]::NewLine
    Set-AttentionSpanCleanupFile -Path $Path -Content $json
    $script:AttentionSpanCleanupRemoved = $true
}

function Remove-AttentionSpanManagedBlock {
    param([Parameter(Mandatory=$true)][string]$Path)

    Assert-AttentionSpanManagedFileIsSafe -Path $Path
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return
    }
    [string[]]$lines = @([System.IO.File]::ReadAllLines($Path))
    $beginMarker = "<!-- attention-span:start -->"
    $endMarker = "<!-- attention-span:end -->"
    $beginIndex = [Array]::IndexOf($lines, $beginMarker)
    if ($beginIndex -lt 0) {
        return
    }
    $endIndex = [Array]::IndexOf($lines, $endMarker)
    $updatedLines = [System.Collections.Generic.List[string]]::new()
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($index -lt $beginIndex -or $index -gt $endIndex) {
            $updatedLines.Add($lines[$index])
        }
    }

    $content = if ($updatedLines.Count -eq 0) {
        ""
    }
    else {
        [string]::Join([Environment]::NewLine, $updatedLines) + [Environment]::NewLine
    }
    Set-AttentionSpanCleanupFile -Path $Path -Content $content
    $script:AttentionSpanCleanupRemoved = $true
}

function Remove-AttentionSpanResources {
    $defaultClaudeDir = Join-Path $env:USERPROFILE ".claude"
    $defaultCodexDir = Join-Path $env:USERPROFILE ".codex"
    $defaultPiDir = Join-Path $env:USERPROFILE ".pi\agent"
    $claudeDirs = @(Get-AttentionSpanCleanupDirectories -DefaultDirectory $defaultClaudeDir -ActiveDirectory $env:CLAUDE_CONFIG_DIR)
    $codexDirs = @(Get-AttentionSpanCleanupDirectories -DefaultDirectory $defaultCodexDir -ActiveDirectory $env:CODEX_HOME)
    $piDirs = @(Get-AttentionSpanCleanupDirectories -DefaultDirectory $defaultPiDir -ActiveDirectory $env:PI_CODING_AGENT_DIR)
    $managedFiles = @()
    foreach ($directory in $codexDirs) {
        $managedFiles += Join-Path $directory "AGENTS.md"
    }
    $managedFiles += Join-Path (Join-Path $env:USERPROFILE ".gemini") "GEMINI.md"
    if ($script:PiProfileMutationsBlocked) { $piDirs = @() }
    foreach ($directory in $piDirs) {
        $managedFiles += Join-Path $directory "APPEND_SYSTEM.md"
    }
    $script:AttentionSpanCleanupRemoved = $false

    foreach ($directory in $claudeDirs) {
        Assert-AttentionSpanStyleIsSafe -Path (Join-Path $directory "output-styles\attention-kind.md")
        Assert-AttentionSpanSettingsAreSafe -Path (Join-Path $directory "settings.json")
    }
    foreach ($managedFile in $managedFiles) {
        Assert-AttentionSpanManagedFileIsSafe -Path $managedFile
    }

    foreach ($directory in $claudeDirs) {
        Remove-AttentionSpanStyle -Path (Join-Path $directory "output-styles\attention-kind.md")
        Remove-AttentionSpanSetting -Path (Join-Path $directory "settings.json")
    }
    foreach ($managedFile in $managedFiles) {
        Remove-AttentionSpanManagedBlock -Path $managedFile
    }

    if ($script:AttentionSpanCleanupRemoved) {
        Write-Success "Retired Attention-kind guidance removed."
    }
    else {
        Write-Debug "No retired Attention-kind guidance found."
    }
}

function Test-SkillsCliNodeRuntimeReady {
    return (Test-SharedNodeRuntimeReady)
}

function Enable-SkillsCliNodeRuntime {
    return (Enable-SharedNodeRuntime)
}

$null = 'BEGIN_GENERATED_IMPECCABLE_SKILL'
function Write-ImpeccableFailure {
    param([string]$Phase, [string]$Reason, $Status = $null)
    if ($Phase -cnotin @('prerequisites','preflight','npm-configuration','staging','environment-isolation','installer','promotion','cleanup','removal')) { $Phase = 'prerequisites' }
    if ($Reason -cnotin @('unknown','shared-runtime-unavailable','installer-runtime-unavailable','npm-configuration-unverified','environment-isolation-failed','stage-directory-unavailable','launch-failed','invalid-result','dns-resolution-failed','download-http-failed','download-failed','unsafe-path','linked-directory','not-directory','unsafe-owner-or-mode','unsafe-metadata','malformed-metadata','unsupported-file','removal-failed','invalid-skill-copy','incomplete-payload','invalid-skill-identity','invalid-engine-version','nonexecutable-payload','unsupported-artifact','unsafe-stage','pi-profiles-blocked','invalid-settings','invalid-inventory','pi-discovery-conflict','unverified-resource-selection','invalid-resource-json','inconsistent-snapshot','checksum-unavailable','engine-checksum-mismatch','modified-pi-copy','unverified-pi-copy','changed-copy','changed-directory','recovery-required','unsafe-file','outside-home','windows-acl-unverified','conflicting-profile-scope','unknown-operation','EACCES','EPERM','ENOENT','ENOSPC','EROFS','EBUSY')) { $Reason = 'unknown' }
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
'use strict';
void 'BEGIN_IMPECCABLE_DIAGNOSTICS';
const impeccableReasons = ["unknown", "shared-runtime-unavailable", "installer-runtime-unavailable",
    "npm-configuration-unverified", "environment-isolation-failed", "stage-directory-unavailable",
    "launch-failed", "invalid-result", "dns-resolution-failed", "download-http-failed", "download-failed",
    "unsafe-path", "linked-directory", "not-directory", "unsafe-owner-or-mode", "unsafe-metadata",
    "malformed-metadata", "unsupported-file", "removal-failed", "invalid-skill-copy", "incomplete-payload",
    "invalid-skill-identity", "invalid-engine-version", "nonexecutable-payload", "unsupported-artifact",
    "unsafe-stage", "pi-profiles-blocked", "invalid-settings", "invalid-inventory", "pi-discovery-conflict",
    "unverified-resource-selection", "invalid-resource-json", "inconsistent-snapshot", "checksum-unavailable",
    "engine-checksum-mismatch", "modified-pi-copy", "unverified-pi-copy", "changed-copy", "changed-directory",
    "recovery-required", "unsafe-file", "outside-home", "windows-acl-unverified", "conflicting-profile-scope",
    "unknown-operation", "EACCES", "EPERM", "ENOENT", "ENOSPC", "EROFS", "EBUSY"];
function impeccableDiagnostic(text, kind) {
    text = text.replace(/\u001b\[[0-?]*[ -/]*[@-~]/g, '').replace(/\r\n?/g, '\n');
    if (/[\x00-\x08\x0b-\x1f\x7f\ufffd]/.test(text)) return 'reason:unknown';
    if (kind !== 'installer') {
        const trimmed = text.trim();
        if (!trimmed) return 'ok';
        const reason = trimmed.match(/^Impeccable: ([a-zA-Z0-9-]+)\.$/)?.[1];
        if (impeccableReasons.includes(reason)) return 'reason:' + reason;
        if (kind === 'stage' && /^(?:\/|[A-Za-z]:[\\/])[^\n]*[\\/]setup-impeccable-[A-Za-z0-9]+$/.test(trimmed)) return 'stage:' + trimmed;
        return 'reason:unknown';
    }
    const reasons = new Set();
    for (const line of text.split('\n')) {
        if (/^npm (?:ERR!|error) code (?:EAI_AGAIN|ENOTFOUND)$/.test(line)) reasons.add('dns-resolution-failed');
        if (/^npm (?:ERR!|error) code E[45][0-9]{2}$/.test(line)) reasons.add('download-http-failed');
        if (line.startsWith('Download failed: ')) {
            reasons.add(line.includes('Dns Failed: resolve dns name ') ? 'dns-resolution-failed' : 'download-failed');
        }
    }
    return 'reason:' + (reasons.size === 1 ? [...reasons][0] : 'unknown');
}
function impeccableReadDiagnostic(kind) {
    let text = '', size = 0, overflow = false, finished = false;
    const finish = () => {
        if (finished) return;
        finished = true;
        process.stdout.write((overflow ? 'reason:unknown' : impeccableDiagnostic(text, kind)) + '\n');
        text = '';
    };
    process.stdin.on('data', bytes => {
        if (overflow) return;
        size += bytes.length;
        if (size > 65536) { overflow = true; text = ''; }
        else text += bytes.toString('utf8');
    });
    process.stdin.on('error', () => { overflow = true; finish(); });
    process.stdin.on('end', finish);
}
void 'END_IMPECCABLE_DIAGNOSTICS';
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const crypto = require('node:crypto');
const https = require('node:https');
const fail = reason => { throw new Error(reason); };
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const unique = values => [...new Set(values)];
const semver = value => typeof value === 'string' && /^\d+\.\d+\.\d+$/.test(value);
const [homeInput, activePiInput, blocked, mode, stageInput] = process.argv.slice(2);
const windowsPaths = new Map();
function windowsRecord(file, account = false, link = false) {
    if (process.platform !== 'win32') return;
    const before = windowsPaths.get(file);
    windowsPaths.set(file, {file, account: account || before?.account || file === homeInput || file.startsWith(homeInput + path.sep), link: link && (!before || before.link)});
}
function windowsTrust() {
    if (process.platform !== 'win32') return;
    const program = String.raw`
$ErrorActionPreference='Stop'
$PSModuleAutoLoadingPreference='None'
$pins=@()
try {
    foreach ($name in @('Management','Utility','Security')) {
        Import-Module (Join-Path $PSHOME ('Modules/Microsoft.PowerShell.'+$name+'/Microsoft.PowerShell.'+$name+'.psd1')) -ErrorAction Stop
    }
    Add-Type -TypeDefinition @"
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using Microsoft.Win32.SafeHandles;
public static class ImpeccablePathTrust {
    [StructLayout(LayoutKind.Sequential)]
    public struct Info {
        public uint Attributes, CreatedLow, CreatedHigh, AccessLow, AccessHigh,
            WriteLow, WriteHigh, Volume, SizeHigh, SizeLow, Links, IndexHigh, IndexLow;
    }
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern SafeFileHandle CreateFile(string name, uint access, uint share,
        IntPtr security, uint creation, uint flags, IntPtr template);
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern bool GetFileInformationByHandle(SafeFileHandle file, out Info info);
    [DllImport("advapi32.dll", SetLastError=true)]
    static extern bool GetKernelObjectSecurity(SafeFileHandle file, uint information,
        byte[] descriptor, uint length, out uint needed);
    public static SafeFileHandle Pin(string name) {
        if (name.StartsWith("\\\\") || name.Length < 3 || name[1] != ':') throw new InvalidOperationException();
        foreach (string part in name.Substring(3).Split('\\')) {
            if (part.EndsWith(".") || part.EndsWith(" ") || part.Contains(":")) throw new InvalidOperationException();
        }
        var handle=CreateFile(name, 0x20080, 7, IntPtr.Zero, 3, 0x02200000, IntPtr.Zero);
        if (handle.IsInvalid) {
            int error=Marshal.GetLastWin32Error(); handle.Dispose();
            if (error == 2 || error == 3) return null;
            throw new Win32Exception(error);
        }
        return handle;
    }
    public static Info Read(SafeFileHandle handle) {
        Info info;
        if (!GetFileInformationByHandle(handle, out info)) throw new Win32Exception();
        return info;
    }
    public static string Identity(Info info) {
        return info.Volume+":"+info.IndexHigh+":"+info.IndexLow+":"+info.Attributes+":"+info.Links;
    }
    public static FileSystemSecurity Security(SafeFileHandle handle, bool directory) {
        uint needed;
        GetKernelObjectSecurity(handle, 7, null, 0, out needed);
        if (needed == 0 || needed > 65536) throw new InvalidOperationException();
        var bytes=new byte[needed];
        if (!GetKernelObjectSecurity(handle, 7, bytes, needed, out needed)) throw new Win32Exception();
        FileSystemSecurity security=directory ? (FileSystemSecurity)new DirectorySecurity() : new FileSecurity();
        security.SetSecurityDescriptorBinaryForm(bytes);
        return security;
    }
}
"@
    $owner=[System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $allowed=@($owner,'S-1-5-18','S-1-5-32-544')
    $systemOwners=$allowed+@('S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464')
    $paths=@(ConvertFrom-Json ([Console]::In.ReadToEnd()))
    foreach ($entry in @($paths | Sort-Object { $_.file.Length })) {
        $handle=[ImpeccablePathTrust]::Pin($entry.file)
        if ($null -eq $handle) { continue }
        $pins+=,$handle
        $before=[ImpeccablePathTrust]::Read($handle)
        if (($before.Attributes -band 0x400) -and -not $entry.link) { throw 'reparse' }
        $acl=[ImpeccablePathTrust]::Security($handle,[bool]($before.Attributes -band 0x10))
        $sid=$acl.GetOwner([System.Security.Principal.SecurityIdentifier]).Value
        if ($entry.account) { if ($sid -ne $owner) { throw 'owner' } }
        elseif ($systemOwners -notcontains $sid) { throw 'owner' }
        $write=[System.Security.AccessControl.FileSystemRights]'Delete,DeleteSubdirectoriesAndFiles,ChangePermissions,TakeOwnership'
        if ($entry.account) { $write=$write -bor [System.Security.AccessControl.FileSystemRights]::Write }
        foreach ($rule in $acl.GetAccessRules($true,$true,[System.Security.Principal.SecurityIdentifier])) {
            if ($rule.PropagationFlags -band [System.Security.AccessControl.PropagationFlags]::InheritOnly) { continue }
            if ($rule.AccessControlType -eq 'Allow' -and $allowed -notcontains $rule.IdentityReference.Value -and ($rule.FileSystemRights -band $write)) { throw 'access' }
        }
        $after=[ImpeccablePathTrust]::Read($handle)
        $again=[ImpeccablePathTrust]::Security($handle,[bool]($after.Attributes -band 0x10))
        if ([ImpeccablePathTrust]::Identity($before) -cne [ImpeccablePathTrust]::Identity($after) -or $again.GetSecurityDescriptorSddlForm([System.Security.AccessControl.AccessControlSections]::All) -cne $acl.GetSecurityDescriptorSddlForm([System.Security.AccessControl.AccessControlSections]::All)) { throw 'changed' }
    }
    [Console]::Out.Write('trusted')
} catch { exit 1 }
finally { foreach ($handle in $pins) { $handle.Dispose() } }
`;
    const root = process.env.SystemRoot || 'C:\\Windows';
    if (!/^[A-Za-z]:\\Windows$/i.test(root)) fail('windows-acl-unverified');
    const result = require('node:child_process').spawnSync(path.win32.join(root, 'System32/WindowsPowerShell/v1.0/powershell.exe'),
        ['-NoProfile', '-NonInteractive', '-EncodedCommand', Buffer.from(program, 'utf16le').toString('base64')], {
            input: JSON.stringify([...windowsPaths.values()]), env: {SystemRoot: root, WINDIR: root},
            encoding: 'utf8', windowsHide: true, shell: false, timeout: 30000, maxBuffer: 1024,
        });
    if (result.status !== 0 || result.stdout !== 'trusted') fail('windows-acl-unverified');
}

function stat(file) {
    try { return fs.lstatSync(file); }
    catch (error) { if (error.code === 'ENOENT') return null; throw error; }
}
function systemHomeAlias(file, st) {
    if (process.platform !== 'linux' || file !== '/home' || st.uid !== 0) return false;
    if (!['var/home', '/var/home'].includes(fs.readlinkSync(file))) return false;
    return ['/', '/var', '/var/home'].every(dir => {
        const item = stat(dir);
        return item && item.isDirectory() && !item.isSymbolicLink() && item.uid === 0 && !(item.mode & 0o022);
    });
}
function absolute(file) {
    if (!file || !path.isAbsolute(file) || file.split(/[\\/]/).includes('..')) fail('unsafe-path');
    const resolved = path.resolve(file);
    if (resolved === path.parse(resolved).root) fail('unsafe-path');
    return resolved;
}
function directory(file) {
    const parent = path.dirname(file);
    if (parent !== file) directory(parent);
    const st = stat(file);
    if (!st) return;
    windowsRecord(file);
    if (st.isSymbolicLink()) {
        if (!systemHomeAlias(file, st)) fail('linked-directory');
    } else {
        if (!st.isDirectory()) fail('not-directory');
        if (process.platform !== 'win32') {
            const uid = process.getuid();
            const writeMask = st.uid === uid && uid !== 0 ? 0o002 : 0o022;
            if (![0, uid].includes(st.uid) || (st.mode & writeMask) && !(st.uid === 0 && (st.mode & 0o1000))) fail('unsafe-owner-or-mode');
            if (homeInput && path.isAbsolute(homeInput) && (file === path.resolve(homeInput) || file.startsWith(path.resolve(homeInput) + path.sep)) && st.uid !== uid) fail('unsafe-owner-or-mode');
        }
    }
}
function owned(file, privateDirectory = false) {
    const st = stat(file);
    if (st) windowsRecord(file, true, st.isSymbolicLink() && ['remove', 'dispose'].includes(mode));
    const writeMask = st?.isDirectory() && st.uid !== 0 && !privateDirectory ? 0o002 : 0o022;
    if (st && process.platform !== 'win32' && (st.uid !== process.getuid() || !st.isSymbolicLink() && (st.mode & writeMask))) fail('unsafe-owner-or-mode');
}
function jsonFile(file) {
    directory(path.dirname(file));
    const st = stat(file);
    if (!st) return null;
    if (!st.isFile() || st.isSymbolicLink() || st.nlink !== 1 || st.size > 1024 * 1024) fail('unsafe-metadata');
    owned(file);
    windowsTrust();
    let value;
    try { value = JSON.parse(readRegular(file).toString('utf8').replace(/^\uFEFF/, '')); }
    catch { fail('malformed-metadata'); }
    if (!object(value)) fail('malformed-metadata');
    return value;
}
function readRegular(file) {
    directory(path.dirname(file));
    const before = stat(file);
    if (!before?.isFile() || before.isSymbolicLink() || before.nlink !== 1 || before.size > 256 * 1024 * 1024) fail('unsafe-file');
    owned(file);
    const fd = fs.openSync(file, fs.constants.O_RDONLY | fs.constants.O_NONBLOCK | (fs.constants.O_NOFOLLOW || 0));
    try {
        const opened = fs.fstatSync(fd);
        if (opened.dev !== before.dev || opened.ino !== before.ino || !opened.isFile() || opened.nlink !== 1) fail('changed-copy');
        const bytes = fs.readFileSync(fd), after = fs.fstatSync(fd);
        if (after.size !== before.size || after.mtimeMs !== before.mtimeMs || bytes.length !== before.size) fail('changed-copy');
        return bytes;
    } finally { fs.closeSync(fd); }
}
function fingerprint(file) {
    directory(path.dirname(file));
    const st = stat(file);
    if (!st) return null;
    owned(file);
    const identity = [st.dev, st.ino, st.mode, st.uid, st.gid, st.nlink, st.mtimeMs];
    if (st.isSymbolicLink()) identity.push(fs.readlinkSync(file));
    else if (st.isDirectory()) identity.push(fs.readdirSync(file).sort().map(name => [name, fingerprint(path.join(file, name))]));
    else if (st.isFile()) identity.push(crypto.createHash('sha256').update(readRegular(file)).digest('hex'));
    else fail('unsupported-file');
    return JSON.stringify(identity);
}
function copySnapshot(source, target) {
    copiedTree(source);
    const st = stat(source);
    if (st.isDirectory()) {
        fs.mkdirSync(target, {mode: st.mode & 0o777});
        for (const name of fs.readdirSync(source)) copySnapshot(path.join(source, name), path.join(target, name));
    } else fs.writeFileSync(target, readRegular(source), {flag: 'wx', mode: st.mode & 0o777});
}
function ensureDirectory(file, created) {
    directory(file);
    if (stat(file)) { owned(file); return; }
    ensureDirectory(path.dirname(file), created);
    fs.mkdirSync(file, {mode: 0o700});
    created.push({file, dev: stat(file).dev, ino: stat(file).ino});
}
function snapshotDirectories(files) {
    const result = new Map();
    for (const file of files) {
        let dir = path.dirname(file);
        while (true) {
            const st = stat(dir);
            result.set(dir, st ? JSON.stringify([st.dev, st.ino, st.mode, st.uid, st.gid, st.isSymbolicLink() ? fs.readlinkSync(dir) : null]) : null);
            if (dir === path.dirname(dir)) break;
            dir = path.dirname(dir);
        }
    }
    return result;
}
function unchangedDirectories(previous) {
    for (const [dir, identity] of previous) {
        directory(dir);
        if (snapshotDirectories([path.join(dir, 'unused')]).get(dir) !== identity) fail('changed-directory');
    }
}
function transaction(home, changes, verify) {
    const records = changes.map(change => ({...change, before: Object.hasOwn(change, 'before') ? change.before : fingerprint(change.file)}));
    const created = [], lock = path.join(home, '.agents/.setup-impeccable.lock');
    let locked = false, committed = false, recovering = false;
    const parents = new Map();
    const recheckParents = file => {
        directory(path.dirname(file));
        for (const [dir, previous] of parents) {
            const current = stat(dir);
            if (!current || current.dev !== previous.dev || current.ino !== previous.ino || current.mode !== previous.mode ||
                current.uid !== previous.uid || current.gid !== previous.gid || !current.isDirectory() && !systemHomeAlias(dir, current)) fail('changed-directory');
        }
    };
    try {
        ensureDirectory(path.dirname(lock), created);
        const fd = fs.openSync(lock, 'wx', 0o600);
        fs.closeSync(fd); locked = true;
        for (const record of records) {
            ensureDirectory(path.dirname(record.file), created);
            let dir = path.dirname(record.file);
            while (dir !== path.dirname(dir)) {
                if (!parents.has(dir)) parents.set(dir, stat(dir));
                dir = path.dirname(dir);
            }
            if (fs.readdirSync(path.dirname(record.file)).some(name => /^\.setup-impeccable-[a-f0-9-]+\.(?:old|new)$/.test(name))) fail('recovery-required');
        }
        for (const record of records) {
            recheckParents(record.file);
            if (fingerprint(record.file) !== record.before) fail('changed-copy');
            const stem = path.join(path.dirname(record.file), '.setup-impeccable-' + crypto.randomUUID());
            record.backup = stem + '.old'; record.temporary = stem + '.new';
            if (record.source) {
                record.sourceBefore = fingerprint(record.source);
                copySnapshot(record.source, record.temporary);
                if (fingerprint(record.source) !== record.sourceBefore || !sameTree(record.source, record.temporary)) fail('changed-copy');
            } else if (record.bytes) {
                fs.writeFileSync(record.temporary, record.bytes, {flag: 'wx', mode: stat(record.file)?.mode & 0o777 || 0o600});
            }
            record.expectedAfter = fingerprint(record.temporary);
        }
        windowsTrust();
        for (const record of records) {
            recheckParents(record.file);
            if (fingerprint(record.file) !== record.before || record.source && fingerprint(record.source) !== record.sourceBefore) fail('changed-copy');
            if (record.before !== null) { fs.renameSync(record.file, record.backup); record.saved = true; }
            if (record.expectedAfter !== null) {
                fs.renameSync(record.temporary, record.file); record.promoted = true;
                if (fingerprint(record.file) !== record.expectedAfter) fail('changed-copy');
            }
        }
        if (verify) verify();
        windowsTrust();
        committed = true;
        for (const record of records) if (record.saved) remove(record.backup);
    } catch (error) {
        if (!committed) for (const record of records.toReversed()) {
            try {
                recheckParents(record.file);
                if (record.promoted) {
                    if (fingerprint(record.file) !== record.expectedAfter) fail('changed-copy');
                    remove(record.file);
                }
                if (record.saved) {
                    if (stat(record.file) || fingerprint(record.backup) !== record.before) fail('changed-copy');
                    fs.renameSync(record.backup, record.file);
                }
            } catch { recovering = true; }
        }
        else recovering = true;
        if (recovering) fail('recovery-required');
        throw error;
    } finally {
        for (const record of records) if (record.temporary && stat(record.temporary)) {
            try { remove(record.temporary); } catch { recovering = true; }
        }
        if (locked && !recovering) fs.unlinkSync(lock);
        if (!committed && !recovering) for (const {file, dev, ino} of created.toReversed()) {
            const st = stat(file);
            if (st?.dev === dev && st.ino === ino && fs.readdirSync(file).length === 0) fs.rmdirSync(file);
        }
        if (recovering) fail('recovery-required');
    }
}
function jsonChange(file, value) {
    const bytes = Buffer.from(JSON.stringify(value, null, 2) + '\n');
    return stat(file) && readRegular(file).equals(bytes) ? [] : [{file, bytes}];
}
function removable(file) {
    directory(path.dirname(file));
    const st = stat(file);
    if (!st) return;
    owned(file);
    if (st.isSymbolicLink()) return;
    if (st.isDirectory()) {
        for (const entry of fs.readdirSync(file)) removable(path.join(file, entry));
    } else if (!st.isFile()) fail('unsupported-file');
}
function remove(file) {
    removable(file);
    const st = stat(file);
    if (!st) return;
    if (st.isDirectory() && !st.isSymbolicLink()) {
        for (const entry of fs.readdirSync(file)) remove(path.join(file, entry));
        fs.rmdirSync(file);
    } else fs.unlinkSync(file);
    if (stat(file)) fail('removal-failed');
}
function copiedTree(file) {
    directory(path.dirname(file));
    const st = stat(file);
    if (!st || st.isSymbolicLink()) fail('invalid-skill-copy');
    owned(file);
    if (st.isDirectory()) {
        for (const entry of fs.readdirSync(file)) copiedTree(path.join(file, entry));
    } else if (!st.isFile() || st.nlink !== 1) fail('invalid-skill-copy');
}
function sameTree(left, right) {
    const a = stat(left), b = stat(right);
    if (!a || !b || a.isSymbolicLink() || b.isSymbolicLink()) return false;
    if (a.isFile() && b.isFile()) return readRegular(left).equals(readRegular(right));
    if (!a.isDirectory() || !b.isDirectory()) return false;
    const names = fs.readdirSync(left).sort(), other = fs.readdirSync(right).sort();
    return JSON.stringify(names) === JSON.stringify(other) && names.every(name => sameTree(path.join(left, name), path.join(right, name)));
}
function payloadDigest(file) {
    copiedTree(file);
    windowsTrust();
    const hash = crypto.createHash('sha256');
    const walk = (item, relative) => {
        if (stat(item).isDirectory()) {
            hash.update(JSON.stringify(['directory', relative]));
            for (const name of fs.readdirSync(item).sort()) walk(path.join(item, name), relative + '/' + name);
        } else {
            const bytes = readRegular(item);
            hash.update(JSON.stringify(['file', relative, bytes.length])); hash.update(bytes);
        }
    };
    walk(file, '');
    return hash.digest('hex');
}
const officialHelperNames = ['manual-edit-applier', 'asset-producer', 'documenter', 'finish-reviewer'];
function helperPath(profile, name) {
    return path.join(profile, 'agents', 'impeccable-' + name + '.md');
}
const references = ['routing', 'init', 'craft', 'critique', 'layout', 'typeset', 'colorize', 'polish', 'audit',
    'audit.native', 'adapt', 'adapt.native', 'animate', 'bolder', 'clarify', 'delight', 'distill', 'document',
    'extract', 'generate', 'harden', 'onboard', 'optimize', 'quieter', 'shape', 'visualize', 'overdrive',
    'doctor', 'live', 'live-setup', 'operate', 'new-work', 'craft-floor', 'component-review', 'region-map',
    'mode-operate', 'mode-persuade', 'mode-read', 'ios', 'android', 'hooks',
    ...officialHelperNames.map(name => 'degraded/' + name)];
const resources = ['scripts/impeccable', 'scripts/impeccable.cmd', 'scripts/VERSION', 'scripts/command-metadata.json',
    'scripts/live-browser.js', 'scripts/live-browser-session.js', 'scripts/live-browser-ignores.js',
    'scripts/live-browser-dom.js', 'scripts/modern-screenshot.umd.js', 'scripts/data/font-index.json', 'scripts/data/font-index-failures.json'];
function nativeTarget() {
    if (!['linux', 'darwin', 'win32'].includes(process.platform) || !['x64', 'arm64'].includes(process.arch) ||
        process.platform === 'win32' && process.arch !== 'x64') fail('unsupported-artifact');
    return (process.platform === 'win32' ? 'windows' : process.platform) + '-' + process.arch;
}
function skillIdentity(md) {
    const normalized = md.replace(/^\uFEFF/, '').replace(/\r\n?/g, '\n');
    const frontmatter = normalized.match(/^---\n([\s\S]*?)\n---(?:\n|$)/)?.[1];
    if (!frontmatter || frontmatter.length > 65536 || /[\x00-\x09\x0b\x0c\x0e-\x1f\x7f-\x9f\uFEFF]/.test(frontmatter)) fail('invalid-skill-identity');
    const fields = new Map();
    let parent = '';
    const scalar = input => {
        const value = input.trim();
        if (!value) fail('invalid-skill-identity');
        if (value.startsWith('"')) {
            try {
                const parsed = JSON.parse(value);
                if (typeof parsed === 'string') return parsed;
            } catch {}
            fail('invalid-skill-identity');
        }
        if (value.startsWith("'")) {
            if (!/^'(?:[^']|'')*'$/.test(value)) fail('invalid-skill-identity');
            return value.slice(1, -1).replaceAll("''", "'");
        }
        if (/^[-?:,\[\]{}#&*!|>%@`]|:(?:\s|$)|\s#/.test(value)) fail('invalid-skill-identity');
        if (/^(?:null|Null|NULL|~)$/.test(value)) return null;
        if (/^(?:true|True|TRUE)$/.test(value)) return true;
        if (/^(?:false|False|FALSE)$/.test(value)) return false;
        if (/^\+?0[box]/i.test(value)) fail('invalid-skill-identity');
        if (/^\+?(?:\d+(?:\.\d*)?|\.\d+)(?:e[+-]?\d+)?$/i.test(value) || /^\+?\.(?:inf|nan)$/i.test(value)) return Number(value);
        return value;
    };
    for (const line of frontmatter.split('\n')) {
        if (!line.trim() || line.trim().startsWith('#')) continue;
        const top = line.match(/^([A-Za-z][A-Za-z0-9_-]*):(?: +(.*))?$/);
        if (top) {
            const [, name, value] = top;
            if (fields.has(name)) fail('invalid-skill-identity');
            parent = name;
            if (name === 'metadata' || name === 'allowed-tools') {
                if (value?.trim()) fail('invalid-skill-identity');
                fields.set(name, name === 'metadata' ? new Map() : []);
            } else fields.set(name, scalar(value || ''));
            continue;
        }
        const metadata = parent === 'metadata' && line.match(/^  ([A-Za-z][A-Za-z0-9_-]*): +(.+)$/);
        if (metadata) {
            const record = fields.get(parent);
            if (record.has(metadata[1])) fail('invalid-skill-identity');
            record.set(metadata[1], scalar(metadata[2]));
            continue;
        }
        const tool = parent === 'allowed-tools' && line.match(/^  - +(.+)$/);
        if (tool) {
            const value = scalar(tool[1]);
            if (typeof value !== 'string' || !value.trim()) fail('invalid-skill-identity');
            fields.get(parent).push(value);
            continue;
        }
        fail('invalid-skill-identity');
    }
    const description = fields.get('description');
    const nestedVersion = fields.get('metadata')?.get('version');
    const version = fields.has('version') ? fields.get('version') : nestedVersion;
    if (fields.get('name') !== 'impeccable' || typeof description !== 'string' || !description.trim() || description.length > 1024 ||
        !semver(version) || fields.has('version') && nestedVersion !== undefined && version !== nestedVersion) fail('invalid-skill-identity');
    return version;
}
function validateSkill(skill, target, provider) {
    copiedTree(skill);
    windowsTrust();
    const binary = 'scripts/bin/' + target + '/impeccable' + (process.platform === 'win32' ? '.exe' : '');
    const agentFiles = provider === 'codex' ? ['agents/openai.yaml', ...officialHelperNames
        .map(name => 'agents/impeccable_' + name.replaceAll('-', '_') + '.toml')] : [];
    const files = ['SKILL.md', ...references.map(name => 'reference/' + name + '.md'), ...resources, ...agentFiles, binary];
    for (const file of files) {
        const item = stat(path.join(skill, file));
        if (!item?.isFile() || item.size === 0 || item.nlink !== 1) fail('incomplete-payload');
    }
    const md = readRegular(path.join(skill, 'SKILL.md')).toString('utf8');
    const version = skillIdentity(md);
    const engine = readRegular(path.join(skill, 'scripts/VERSION')).toString('utf8').trim();
    if (!semver(engine)) fail('invalid-engine-version');
    for (const resource of resources.filter(file => file.endsWith('.json'))) {
        try { JSON.parse(readRegular(path.join(skill, resource)).toString('utf8')); }
        catch { fail('invalid-resource-json'); }
    }
    if (process.platform !== 'win32' && [path.join(skill, 'scripts/impeccable'), path.join(skill, 'scripts/bin', target, 'impeccable')]
        .some(file => !(stat(file).mode & 0o100))) fail('nonexecutable-payload');
    return {engine, version,
        checksum: crypto.createHash('sha256').update(readRegular(path.join(skill, binary))).digest('hex')};
}
function engineChecksum(version, target) {
    const asset = 'impeccable-' + target + (process.platform === 'win32' ? '.exe' : '');
    const original = 'https://github.com/pbakaus/impeccable/releases/download/engine-v' + version + '/' + asset + '.sha256';
    const fetch = (url, redirects = 0) => new Promise((resolve, reject) => {
        const parsed = new URL(url);
        if (parsed.protocol !== 'https:' || parsed.username || parsed.password || parsed.port ||
            !(url === original || redirects === 1 && parsed.hostname === 'release-assets.githubusercontent.com')) {
            reject(new Error('checksum-unavailable')); return;
        }
        const request = https.get(url, {rejectUnauthorized: true}, response => {
            if ([301, 302, 303, 307, 308].includes(response.statusCode) && redirects === 0 && response.headers.location) {
                response.resume(); fetch(new URL(response.headers.location, url).href, 1).then(resolve, reject); return;
            }
            if (response.statusCode !== 200) { response.resume(); reject(new Error('checksum-unavailable')); return; }
            let text = '';
            response.on('data', bytes => {
                text += bytes.toString('utf8');
                if (text.length > 4096) request.destroy(new Error('checksum-unavailable'));
            });
            response.on('error', () => reject(new Error('checksum-unavailable')));
            response.on('end', () => {
                const match = text.trim().match(/^([a-f0-9]{64})(?:\s+\*?([a-zA-Z0-9.-]+))?$/i);
                if (!match || match[2] && match[2] !== asset) reject(new Error('checksum-unavailable'));
                else resolve(match[1].toLowerCase());
            });
        });
        const timer = setTimeout(() => request.destroy(new Error('checksum-unavailable')), 30000);
        request.on('close', () => clearTimeout(timer));
        request.on('error', () => reject(new Error('checksum-unavailable')));
    });
    return fetch(original);
}
function stagePath(input) {
    const stage = absolute(input), tempRoot = fs.realpathSync(os.tmpdir());
    if (path.dirname(stage) !== tempRoot || !/^setup-impeccable-[a-zA-Z0-9]+$/.test(path.basename(stage))) fail('unsafe-stage');
    directory(tempRoot);
    return stage;
}
function matchesSkill(file, pattern, base, exact = false) {
    const posix = value => value.split(path.sep).join('/');
    const parent = path.dirname(file);
    const candidates = [file, parent, path.relative(base, file), path.relative(base, parent)].map(posix);
    if (exact) return candidates.includes(posix(pattern.replace(/^\.[\\/]/, '')));
    candidates.push('SKILL.md', path.basename(parent));
    const value = posix(pattern);
    if (/[\\\[\]{}()]/.test(value) || value.startsWith('!') || value.length > 4096) fail('unverified-resource-selection');
    if (!value || value.startsWith('#')) return false;
    const parts = value.split(/\/+/);
    if (parts.includes('..') || parts.length > 256) fail('unverified-resource-selection');
    const expressions = parts.map(part => part === '**' ? null : new RegExp('^' + part
        .replace(/[.+^$|]/g, '\\$&').replace(/\*+/g, '.*').replace(/\?/g, '.') + '$'));
    return candidates.some(candidate => {
        const segments = candidate.split(/\/+/);
        const match = (pi, fi) => {
            if (pi === parts.length) return fi === segments.length;
            if (parts[pi] === '**') {
                if (pi === parts.length - 1) return fi < segments.length && segments.slice(fi).every(segment => !segment.startsWith('.'));
                return match(pi + 1, fi) || fi < segments.length && !segments[fi].startsWith('.') && match(pi, fi + 1);
            }
            if (fi === segments.length || segments[fi].startsWith('.') && !parts[pi].startsWith('.') ||
                !segments[fi] && /[*?]/.test(parts[pi])) return false;
            return expressions[pi].test(segments[fi]) && match(pi + 1, fi + 1);
        };
        return match(0, 0);
    });
}
function enabledSkill(file, entries, profile) {
    let enabled = !entries.filter(entry => entry.startsWith('!')).some(entry => matchesSkill(file, entry.slice(1), profile));
    if (entries.filter(entry => entry.startsWith('+')).some(entry => matchesSkill(file, entry.slice(1), profile, true))) enabled = true;
    if (entries.filter(entry => entry.startsWith('-')).some(entry => matchesSkill(file, entry.slice(1), profile, true))) enabled = false;
    return enabled;
}
function ignoredPiDescriptor(file, profile, skillDirectory = path.dirname(file)) {
    const rules = [];
    const addRules = (directoryPath, prefix) => {
        for (const name of ['.gitignore', '.ignore', '.fdignore']) {
            const policy = path.join(directoryPath, name);
            if (!stat(policy)) continue;
            for (let line of readRegular(policy).toString('utf8').split(/\r?\n/)) {
                if (!line.trim() || line.trim().startsWith('#')) continue;
                const negated = line.startsWith('!');
                if (negated) line = line.slice(1);
                line = line.replace(/^\//, '').replace(/ +$/, '');
                if (!line) continue;
                if (/[\\\[\]]/.test(line) || line.startsWith('!') || line.length > 4096) fail('unverified-resource-selection');
                const directoryOnly = line.endsWith('/');
                const pattern = prefix + line.replace(/\/$/, '');
                const anchored = pattern.includes('/');
                const parts = pattern.split('/');
                if (parts.includes('..') || parts.includes('.') || parts.length > 256) fail('unverified-resource-selection');
                let expression = '';
                for (let index = 0; index < parts.length; index++) {
                    const part = parts[index];
                    if (part === '**') {
                        expression += index === parts.length - 1 ? '.*' : '(?:[^/]+/)*';
                    } else {
                        expression += part.replace(/[.+^$|(){}]/g, '\\$&').replace(/\*+/g, '[^/]*').replace(/\?/g, '[^/]');
                        if (index < parts.length - 1) expression += '/';
                    }
                }
                rules.push({negated, directoryOnly, expression: new RegExp((anchored ? '^' : '(?:^|/)') + expression + '$', 'i')});
            }
        }
    };
    const ignored = (relative, isDirectory) => {
        let result = false;
        for (const rule of rules) if ((!rule.directoryOnly || isDirectory) && rule.expression.test(relative)) result = !rule.negated;
        return result;
    };
    const root = path.join(profile, 'skills');
    addRules(root, '');
    const rootDescriptor = stat(path.join(root, 'SKILL.md'));
    if ((rootDescriptor?.isFile() || rootDescriptor?.isSymbolicLink()) && !ignored('SKILL.md', false)) return true;
    if (ignored('impeccable', true)) return true;
    addRules(skillDirectory, 'impeccable/');
    return ignored('impeccable/SKILL.md', false);
}
function discoveryIntent(home, selected, skillDirectory) {
    const direct = path.join(selected.profile, 'skills/impeccable/SKILL.md');
    const shared = path.join(home, '.agents/skills/impeccable/SKILL.md');
    const exclusion = '!' + path.dirname(shared) + '/**';
    const entries = [...(selected.data.skills || []), exclusion];
    if (!enabledSkill(direct, entries, selected.profile) || enabledSkill(shared, entries, path.join(home, '.agents')) ||
        ignoredPiDescriptor(direct, selected.profile, skillDirectory)) fail('pi-discovery-conflict');
    return exclusion;
}
function context(excluded = false) {
    if (blocked === '1') fail('pi-profiles-blocked');
    const home = absolute(homeInput);
    directory(home); owned(home);
    const lock = path.join(home, '.agents/.setup-impeccable.lock');
    directory(path.dirname(lock));
    if (stat(lock)) fail('recovery-required');
    const profile = (value, fallback) => {
        const result = absolute(value || path.join(home, fallback));
        if (result === home) fail('unsafe-path');
        directory(result); owned(result);
        return result;
    };
    const activePi = absolute(activePiInput || path.join(home, '.pi/agent'));
    const piRelative = path.relative(home, activePi);
    if (!piRelative || piRelative === '..' || piRelative.startsWith('..' + path.sep) || path.isAbsolute(piRelative)) fail('outside-home');
    const pi = unique([path.join(home, '.pi/agent'), profile(activePi, '.pi/agent')]);
    for (const dir of unique([path.join(home, '.pi'), ...pi])) {
        directory(dir); owned(dir, true);
    }
    const claude = profile(process.env.CLAUDE_CONFIG_DIR, '.claude');
    const bindings = [
        {provider: 'claude', source: '.claude/skills/impeccable', destination: path.join(claude, 'skills/impeccable')},
        {provider: 'codex', source: '.agents/skills/impeccable', destination: path.join(home, '.agents/skills/impeccable')},
        {provider: 'cursor', source: '.cursor/skills/impeccable', destination: path.join(home, '.cursor/skills/impeccable')},
        {provider: 'gemini', source: '.gemini/skills/impeccable', destination: path.join(home, '.gemini/skills/impeccable')},
        {provider: 'pi', source: '.pi/agent/skills/impeccable', destination: path.join(pi.at(-1), 'skills/impeccable')},
    ];
    const helperBindings = [{source: '.claude', destination: claude}, {source: '.cursor', destination: path.join(home, '.cursor')}]
        .flatMap(binding => officialHelperNames.map(name => ({source: helperPath(binding.source, name), destination: helperPath(binding.destination, name)})));
    const removalDirs = unique([...bindings.map(binding => path.dirname(binding.destination)), path.join(home, '.claude/skills'), path.join(home, '.codex/skills'),
        path.join(profile(process.env.CODEX_HOME, '.codex'), 'skills'), ...pi.map(dir => path.join(dir, 'skills'))]);
    const removalHelpers = unique([path.join(home, '.claude'), claude, path.join(home, '.cursor')])
        .flatMap(dir => officialHelperNames.map(name => helperPath(dir, name)));
    const removals = removalDirs.map(dir => path.join(dir, 'impeccable'))
        .concat(pi.map(dir => path.join(dir, 'skills/impeccable.md')), removalHelpers);
    if (excluded) removals.forEach(removable);
    else for (const {destination} of [...bindings, ...helperBindings]) {
        const directoryPath = path.dirname(destination);
        directory(directoryPath); owned(directoryPath);
        if (stat(destination)) copiedTree(destination);
    }
    const settings = pi.map(dir => {
        directory(dir); owned(dir);
        const file = path.join(dir, 'settings.json');
        const data = jsonFile(file) || {};
        if (data.skills !== undefined && (!Array.isArray(data.skills) || !data.skills.every(value => typeof value === 'string'))) fail('invalid-settings');
        return {file, data, profile: dir};
    });
    const manifestFile = path.join(home, '.agents/.setup-impeccable.json');
    if (!excluded) {
        const scopes = [...bindings, ...helperBindings].map(binding => binding.destination).concat(settings.map(record => record.file), manifestFile)
            .map(file => process.platform === 'win32' ? file.replaceAll('\\', '/').toLowerCase() : file);
        if (new Set(scopes).size !== scopes.length || scopes.some((left, index) => scopes.some((right, other) => index !== other && left.startsWith(right + '/')))) fail('conflicting-profile-scope');
    }
    const manifest = jsonFile(manifestFile) || {version: 1, source: 'pbakaus/impeccable', ownedExclusions: {}};
    if (manifest.version !== 1 || manifest.source !== 'pbakaus/impeccable' || !object(manifest.ownedExclusions) ||
        !Object.entries(manifest.ownedExclusions).every(([dir, items]) => {
            if (typeof dir !== 'string' || !path.isAbsolute(dir) || dir.split(/[\\/]/).includes('..') || !dir.startsWith(home + path.sep)) return false;
            const allowed = ['!' + path.join(home, '.agents/skills/impeccable') + '/**', '!' + path.join(dir, 'skills/impeccable') + '/**'];
            return Array.isArray(items) && items.every(item => allowed.includes(item));
        })) fail('invalid-inventory');
    if (manifest.piCopy !== undefined && (!object(manifest.piCopy) || typeof manifest.piCopy.profile !== 'string' ||
        !manifest.piCopy.profile.startsWith(home + path.sep) || !/^[a-f0-9]{64}$/.test(manifest.piCopy.snapshot))) fail('invalid-inventory');
    const directPi = bindings.find(binding => binding.provider === 'pi').destination;
    if (!excluded && manifest.piCopy?.profile === pi.at(-1) && stat(directPi) && payloadDigest(directPi) !== manifest.piCopy.snapshot) fail('modified-pi-copy');
    for (const dir of unique([...bindings, ...helperBindings].map(binding => path.dirname(binding.destination))
        .concat(settings.map(record => path.dirname(record.file)), path.dirname(manifestFile)))) {
        directory(dir);
        if (stat(dir) && fs.readdirSync(dir).some(name => /^\.setup-impeccable-[a-f0-9-]+\.(?:old|new)$/.test(name))) fail('recovery-required');
    }
    if (!excluded) discoveryIntent(home, settings.at(-1));
    windowsTrust();
    return {home, pi, bindings, helperBindings, removals, settings, manifestFile, manifest};
}
async function run() {
    if (mode === 'dispose') {
        const stage = stagePath(stageInput);
        const st = stat(stage);
        if (st) {
            if (!st.isSymbolicLink() && (!st.isDirectory() || process.platform !== 'win32' && (st.mode & 0o077))) fail('unsafe-stage');
            remove(stage);
        }
    } else if (mode === 'stage') {
        const tempRoot = fs.realpathSync(os.tmpdir());
        directory(tempRoot);
        const stage = fs.mkdtempSync(path.join(tempRoot, 'setup-impeccable-'));
        for (const child of ['.tmp', '.appdata', '.localappdata', '.git']) fs.mkdirSync(path.join(stage, child), {mode: 0o700});
        process.stdout.write(stage + '\n');
    } else if (mode === 'preflight') {
        context(); nativeTarget();
    } else if (mode === 'remove') {
        const {home, removals, settings, manifestFile, manifest} = context(true);
        const changes = [];
        for (const record of settings) {
            const ownedEntries = manifest.ownedExclusions[record.profile] || [];
            if (ownedEntries.length && record.data.skills) {
                const updated = record.data.skills.filter(entry => !ownedEntries.includes(entry));
                if (updated.length !== record.data.skills.length) {
                    record.data.skills = updated;
                    changes.push(...jsonChange(record.file, record.data));
                }
            }
            delete manifest.ownedExclusions[record.profile];
        }
        changes.push(...removals.filter(file => stat(file)).map(file => ({file})));
        if (stat(manifestFile)) changes.push(...jsonChange(manifestFile, manifest));
        if (changes.length) transaction(home, changes, () => {
            if (removals.some(file => stat(file))) fail('removal-failed');
        });
    } else if (mode === 'promote') {
        const {home, bindings, helperBindings, settings, manifestFile, manifest} = context(), target = nativeTarget();
        const stage = stagePath(stageInput);
        directory(stage); owned(stage);
        if (!stat(stage)?.isDirectory() || process.platform !== 'win32' && (stat(stage).mode & 0o077)) fail('unsafe-stage');
        const skills = bindings.map(binding => {
            const source = path.join(stage, binding.source);
            return {...binding, source, payload: validateSkill(source, target, binding.provider)};
        });
        const piSkill = skills.find(binding => binding.provider === 'pi');
        const directPi = piSkill.destination;
        const sharedPi = skills.find(binding => binding.provider === 'codex').destination;
        if (manifest.piCopy?.profile !== settings.at(-1).profile && stat(directPi) &&
            !(stat(sharedPi) && sameTree(directPi, sharedPi)) && !skills.some(binding => sameTree(directPi, binding.source))) fail('unverified-pi-copy');
        const {engine, version} = piSkill.payload;
        if (skills.some(({payload}) => payload.engine !== engine || payload.version !== version)) fail('inconsistent-snapshot');
        const helpers = helperBindings.map(binding => ({...binding, source: path.join(stage, binding.source)}));
        for (const {source} of helpers) {
            copiedTree(source);
            if (!stat(source)?.isFile() || stat(source).size === 0) fail('incomplete-payload');
        }
        const artifacts = [...skills, ...helpers];
        const sourceSnapshots = new Map(artifacts.map(({source}) => [source, fingerprint(source)]));
        const destinationFiles = artifacts.map(binding => binding.destination).concat(settings.map(record => record.file), manifestFile);
        const destinationSnapshots = new Map(destinationFiles.map(file => [file, fingerprint(file)]));
        const parentSnapshots = snapshotDirectories([...sourceSnapshots.keys(), ...destinationSnapshots.keys()]);
        const checksum = await engineChecksum(engine, target);
        if (skills.some(({payload}) => payload.checksum !== checksum)) fail('engine-checksum-mismatch');
        unchangedDirectories(parentSnapshots);
        for (const [file, before] of [...sourceSnapshots, ...destinationSnapshots]) if (fingerprint(file) !== before) fail('changed-copy');
        const changes = artifacts.map(({source, destination}) => ({file: destination, source}));
        const selected = settings.at(-1);
        const exclusion = discoveryIntent(home, selected, piSkill.source);
        if (!(selected.data.skills || []).includes(exclusion)) {
            selected.data.skills = [...(selected.data.skills || []), exclusion];
            manifest.ownedExclusions[selected.profile] = unique([...(manifest.ownedExclusions[selected.profile] || []), exclusion]);
            changes.push(...jsonChange(selected.file, selected.data));
        }
        manifest.piCopy = {profile: selected.profile, snapshot: payloadDigest(piSkill.source)};
        manifest.skillVersion = version;
        manifest.engineVersion = engine;
        manifest.snapshot = crypto.createHash('sha256').update(skills.map(({source}) => readRegular(path.join(source, 'SKILL.md'))).join('\n')).digest('hex');
        changes.push(...jsonChange(manifestFile, manifest));
        for (const change of changes) change.before = destinationSnapshots.get(change.file);
        transaction(home, changes, () => {
            for (const {provider, source, destination} of skills) {
                if (validateSkill(destination, target, provider).checksum !== checksum) fail('engine-checksum-mismatch');
                if (!sameTree(source, destination)) fail('changed-copy');
            }
            for (const {source, destination} of helpers) {
                copiedTree(destination);
                if (!sameTree(source, destination)) fail('changed-copy');
            }
            discoveryIntent(home, {...selected, data: jsonFile(selected.file)});
        });
    } else fail('unknown-operation');
}
run().catch(error => {
    const reason = impeccableReasons.includes(error.message) ? error.message : ['EACCES', 'EPERM', 'ENOENT', 'ENOSPC', 'EROFS', 'EBUSY'].includes(error.code) ? error.code : 'unknown';
    process.stderr.write('Impeccable: ' + reason + '.\n');
    process.exitCode = 1;
});
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
            if ($result.StartsWith('reason:') -and $result.Substring(7) -cin @('unknown','shared-runtime-unavailable','installer-runtime-unavailable','npm-configuration-unverified','environment-isolation-failed','stage-directory-unavailable','launch-failed','invalid-result','dns-resolution-failed','download-http-failed','download-failed','unsafe-path','linked-directory','not-directory','unsafe-owner-or-mode','unsafe-metadata','malformed-metadata','unsupported-file','removal-failed','invalid-skill-copy','incomplete-payload','invalid-skill-identity','invalid-engine-version','nonexecutable-payload','unsupported-artifact','unsafe-stage','pi-profiles-blocked','invalid-settings','invalid-inventory','pi-discovery-conflict','unverified-resource-selection','invalid-resource-json','inconsistent-snapshot','checksum-unavailable','engine-checksum-mismatch','modified-pi-copy','unverified-pi-copy','changed-copy','changed-directory','recovery-required','unsafe-file','outside-home','windows-acl-unverified','conflicting-profile-scope','unknown-operation','EACCES','EPERM','ENOENT','ENOSPC','EROFS','EBUSY')) { return $result }
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
$null = 'END_GENERATED_IMPECCABLE_SKILL'

function Install-ManagedAgentSkill {
    param(
        [Parameter(Mandatory = $true)][string]$Repository,
        [Parameter(Mandatory = $true)][string]$SkillName,
        [Parameter(Mandatory = $true)][string]$DisplayName,
        [string[]]$AdditionalFiles = @()
    )

    if (-not (Enable-SkillsCliNodeRuntime)) {
        return $false
    }

    if (-not (Get-Command npx -ErrorAction SilentlyContinue)) {
        Write-Warning "npx is not available; cannot install the $DisplayName skill."
        return $false
    }

    $installArguments = @(
        "--yes",
        "skills@latest",
        "add",
        $Repository,
        "--global",
        "--agent", "claude-code",
        "--agent", "codex",
        "--agent", "gemini-cli",
        "--skill", $SkillName,
        "--copy",
        "--yes"
    )

    Write-Message "Installing/updating $DisplayName across AI harnesses..."
    $global:LASTEXITCODE = 0
    $installOutput = & npx @installArguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Failed to install/update the $DisplayName skill."
        if ($installOutput) { Write-Debug ($installOutput | Out-String) }
        return $false
    }

    $claudeDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $env:USERPROFILE ".claude" }
    $skillDirs = @(
        (Join-Path $claudeDir "skills\$SkillName"),
        (Join-Path $env:USERPROFILE ".agents\skills\$SkillName")
    )
    $requiredFiles = @("SKILL.md") + $AdditionalFiles

    foreach ($skillDir in $skillDirs) {
        foreach ($relativeFile in $requiredFiles) {
            $skillFile = Join-Path $skillDir $relativeFile
            $artifactPath = $skillFile
            while ($true) {
                $artifactItem = Get-Item -LiteralPath $artifactPath -Force -ErrorAction SilentlyContinue
                if ($null -ne $artifactItem -and (($artifactItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)) {
                    Write-Warning "$DisplayName validation failed: copied artifact is a symlink at $artifactPath."
                    return $false
                }
                if ($artifactPath -eq $skillDir) { break }
                $artifactPath = Split-Path -Parent $artifactPath
            }
            $skillFileItem = Get-Item -LiteralPath $skillFile -Force -ErrorAction SilentlyContinue
            if ($skillFileItem -isnot [System.IO.FileInfo] -or $skillFileItem.Length -le 0) {
                Write-Warning "$DisplayName validation failed: missing, empty, or non-regular file at $skillFile."
                return $false
            }
        }
    }

    Write-Success "$DisplayName installed/updated for Claude Code, Codex, Gemini CLI, and Pi through the shared skill path."
    if ($installOutput) { Write-Debug ($installOutput | Out-String) }
    return $true
}

function Remove-SimpleEnglishSkill {
    return (Invoke-MattPocockSkillPolicy -Mode remove-simple-english)
}

function Remove-ShowMeSkill {
    return (Invoke-MattPocockSkillPolicy -Mode remove-show-me)
}

function Remove-PrLensSkill {
    return (Invoke-MattPocockSkillPolicy -Mode remove-pr-lens)
}

function Remove-NonCanonicalPiInstalls {
    param(
        [Parameter(Mandatory=$true)][string]$NewPackage,
        [Parameter(Mandatory=$true)][string]$OldPackage
    )

    $removed = $false
    $bunCandidates = @()
    $bunCommand = Get-Command bun -ErrorAction SilentlyContinue
    if ($bunCommand) {
        $bunCandidates += $bunCommand.Source
    }
    $bunCandidates += @(
        (Join-Path $env:USERPROFILE ".bun\bin\bun.exe"),
        (Join-Path $env:USERPROFILE ".bun\bin\bun"),
        (Join-Path $env:USERPROFILE ".cache\.bun\bin\bun.exe"),
        (Join-Path $env:USERPROFILE ".cache\.bun\bin\bun")
    )
    $bunCandidates = $bunCandidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique

    foreach ($bun in $bunCandidates) {
        $globalPackages = (& $bun pm ls -g 2>$null | Out-String)
        foreach ($package in @($NewPackage, $OldPackage)) {
            if ($globalPackages.Contains($package)) {
                Write-Message "Removing non-canonical Bun Pi package $package..."
                & $bun remove -g $package *> $null
                if ($LASTEXITCODE -eq 0) {
                    $removed = $true
                }
                else {
                    Write-Warning "Failed to remove Bun Pi package $package."
                }
            }
        }
        break
    }

    $paths = @(
        (Join-Path $env:USERPROFILE ".bun\bin\pi"),
        (Join-Path $env:USERPROFILE ".bun\bin\pi.cmd"),
        (Join-Path $env:USERPROFILE ".bun\bin\pi.ps1"),
        (Join-Path $env:USERPROFILE ".cache\.bun\bin\pi"),
        (Join-Path $env:USERPROFILE ".cache\.bun\bin\pi.cmd"),
        (Join-Path $env:USERPROFILE ".cache\.bun\bin\pi.ps1"),
        (Join-Path $env:USERPROFILE ".bun\install\global\node_modules\@earendil-works\pi-coding-agent"),
        (Join-Path $env:USERPROFILE ".bun\install\global\node_modules\@earendil-works\pi-agent-core"),
        (Join-Path $env:USERPROFILE ".bun\install\global\node_modules\@earendil-works\pi-ai"),
        (Join-Path $env:USERPROFILE ".bun\install\global\node_modules\@earendil-works\pi-tui"),
        (Join-Path $env:USERPROFILE ".bun\install\global\node_modules\@mariozechner\pi-coding-agent"),
        (Join-Path $env:USERPROFILE ".bun\install\global\node_modules\@mariozechner\pi-agent-core"),
        (Join-Path $env:USERPROFILE ".bun\install\global\node_modules\@mariozechner\pi-ai"),
        (Join-Path $env:USERPROFILE ".bun\install\global\node_modules\@mariozechner\pi-tui"),
        (Join-Path $env:USERPROFILE ".cache\.bun\install\global\node_modules\@earendil-works\pi-coding-agent"),
        (Join-Path $env:USERPROFILE ".cache\.bun\install\global\node_modules\@earendil-works\pi-agent-core"),
        (Join-Path $env:USERPROFILE ".cache\.bun\install\global\node_modules\@earendil-works\pi-ai"),
        (Join-Path $env:USERPROFILE ".cache\.bun\install\global\node_modules\@earendil-works\pi-tui"),
        (Join-Path $env:USERPROFILE ".cache\.bun\install\global\node_modules\@mariozechner\pi-coding-agent"),
        (Join-Path $env:USERPROFILE ".cache\.bun\install\global\node_modules\@mariozechner\pi-agent-core"),
        (Join-Path $env:USERPROFILE ".cache\.bun\install\global\node_modules\@mariozechner\pi-ai"),
        (Join-Path $env:USERPROFILE ".cache\.bun\install\global\node_modules\@mariozechner\pi-tui")
    )

    foreach ($path in $paths) {
        if (Test-Path $path) {
            try {
                Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
                $removed = $true
            }
            catch {
                Write-Warning "Failed to remove non-canonical Pi path: $path"
            }
        }
    }

    if ($removed) {
        Write-Success "Removed non-canonical Bun Pi installs."
    }
    else {
        Write-Debug "No non-canonical Bun Pi installs found."
    }
}

function Repair-NpmConfiguration {
    if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
        Write-Warning "npm not found. Cannot validate npm configuration."
        return $false
    }

    & npm config fix *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "$failIcon npm configuration is invalid and automatic repair failed." -ForegroundColor Red
        Write-Debug "Run 'npm config fix', review the user npmrc, and rerun setup."
        return $false
    }

    & npm config list --location=user *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "$failIcon npm configuration remains invalid after automatic repair." -ForegroundColor Red
        Write-Debug "Run 'npm config fix', review the user npmrc, and rerun setup."
        return $false
    }

    Write-Debug "npm configuration validated."
    return $true
}

function Install-PiCli {
    $script:PiRuntimePreflightPassed = $false
    $newPackage = "@earendil-works/pi-coding-agent"
    $oldPackage = "@mariozechner/pi-coding-agent"
    $localPrefix = Join-Path $env:USERPROFILE ".local"
    $canonicalCandidates = @(
        (Join-Path $localPrefix "pi.ps1"),
        (Join-Path $localPrefix "pi.cmd"),
        (Join-Path $localPrefix "pi")
    )

    Write-Host "$arrow Installing/updating Pi coding agent..." -ForegroundColor Cyan

    try {
        if (-not (Enable-PiNodeRuntime)) {
            Write-Warning "Skipping Pi installation and extension setup because the Pi Node.js runtime is not ready."
            return $false
        }
        $script:PiRuntimePreflightPassed = $true

        if (-not (Test-Path $localPrefix)) {
            New-Item -ItemType Directory -Force -Path $localPrefix | Out-Null
        }
        $env:PATH = "$localPrefix;$env:PATH"
        $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
        if (-not ($userPath -split ';' | Where-Object { $_ -eq $localPrefix })) {
            [Environment]::SetEnvironmentVariable("Path", "$localPrefix;$userPath", "User")
        }

        if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
            Write-Warning "npm not found. Cannot install Pi coding agent."
            Write-Debug "Install Node.js/npm, then run: npm install -g --ignore-scripts --prefix `"$localPrefix`" $newPackage@latest"
            return $false
        }

        if (-not (Repair-NpmConfiguration)) {
            return $false
        }

        & npm uninstall -g --prefix $localPrefix $oldPackage *> $null
        foreach ($candidate in $canonicalCandidates) {
            if (Test-Path $candidate) {
                $candidateText = Get-Content -LiteralPath $candidate -Raw -ErrorAction SilentlyContinue
                if ($candidateText -match "\\.bun" -or $candidateText -match "@mariozechner") {
                    Remove-Item -LiteralPath $candidate -Force -ErrorAction SilentlyContinue
                }
            }
        }

        Write-Message "Installing Pi with npm into $localPrefix..."
        $npmInstallOutput = & npm install -g --ignore-scripts --prefix $localPrefix "$newPackage@latest" 2>&1
        $npmInstallStatus = $LASTEXITCODE
        foreach ($npmInstallLine in $npmInstallOutput) {
            Write-Host $npmInstallLine
        }
        if ($npmInstallStatus -ne 0) {
            Write-Host "$failIcon Failed to install Pi coding agent." -ForegroundColor Red
            return $false
        }

        & npm uninstall -g --prefix $localPrefix $oldPackage *> $null
        Remove-NonCanonicalPiInstalls -NewPackage $newPackage -OldPackage $oldPackage

        $piCommand = Get-Command pi -ErrorAction SilentlyContinue
        if (-not $piCommand) {
            Write-Host "$warnIcon Pi migration incomplete: pi command is not available after installing $newPackage." -ForegroundColor Yellow
            return $false
        }

        $canonicalPi = $canonicalCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
        if (-not $canonicalPi) {
            Write-Host "$warnIcon Pi migration incomplete: canonical npm Pi shim is missing in $localPrefix." -ForegroundColor Yellow
            return $false
        }

        if ($piCommand.Source -ne $canonicalPi) {
            Write-Host "$warnIcon Pi migration incomplete: PATH resolves pi to $($piCommand.Source) instead of $canonicalPi." -ForegroundColor Yellow
            $allPi = Get-Command pi -All -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -Unique
            if ($allPi) {
                Write-Debug "pi commands on PATH: $($allPi -join ' ')"
            }
            return $false
        }

        if ($piCommand.Source.Contains("\.bun\") -or $piCommand.Source.Contains("\.cache\.bun\") -or $piCommand.Source.Contains($oldPackage)) {
            Write-Host "$warnIcon Pi migration incomplete: pi resolves to non-canonical path $($piCommand.Source)." -ForegroundColor Yellow
            return $false
        }

        $allPiCommands = Get-Command pi -All -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -Unique
        foreach ($piPath in $allPiCommands) {
            if ($piPath -ne $canonicalPi) {
                Write-Warning "Additional pi command remains on PATH: $piPath"
            }
        }

        $piVersion = (& pi --version 2>$null | Out-String).Trim()
        $piVersionStatus = $LASTEXITCODE
        if ($piVersionStatus -ne 0 -or [string]::IsNullOrWhiteSpace($piVersion)) {
            Write-Host "$warnIcon Pi migration incomplete: canonical pi failed its version smoke test." -ForegroundColor Yellow
            return $false
        }
        if (-not (Test-SharedNodeShell -CanonicalPi $canonicalPi)) {
            Write-Warning 'Pi failed in a fresh PowerShell at HOME; review chezmoi activation and PATH before rerunning setup.'
            return $false
        }
        Write-Host "$success Pi coding agent $piVersion installed/updated at $canonicalPi." -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "$failIcon Failed to install Pi coding agent: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Set-PiOpenCodeGoProvider {
    param([switch]$CheckCatalog)
    $operations = 'preflight|home|pi-package|pi-dependency|go-catalog|environment-file|active-profile|models-json|auth-lock|lock-dependency|auth-preflight|profile-create|lock-acquire|auth-read|auth-write|auth-cleanup|lock-release'
    $reasons = 'acl-timeout|acl-unavailable|acl-unsafe|catalog-incompatible|concurrent-metadata-change|duplicate-json-key|file-changed|go-provider-overridden|invalid-credential|invalid-json|invalid-json-object|invalid-key-format|invalid-mode|invalid-providers|linked-directory|linked-or-nonregular-file|lock-compromised|lock-unavailable|lock-unverified|lock-version-unsupported|missing-directory|node-incompatible|oversized-metadata|pi-dependency-unavailable|pi-package-unavailable|unexpected-dependency|unowned-auth-file|unowned-home|unsafe-file-permissions|unsafe-json-number|unsafe-lock|unsafe-lock-dependency|unsafe-path|unsafe-profile|untrusted-directory|operation-failed|EACCES|EPERM|EROFS|ENOSPC|EDQUOT|ENOENT|ENOTDIR|EISDIR|ELOOP|EEXIST|EIO|ELOCKED|ECOMPROMISED|MODULE_NOT_FOUND|ERR_PACKAGE_PATH_NOT_EXPORTED'
    $node = Get-Command node -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $node) {
        Write-Warning "Pi Go setup failed: shared Node runtime unavailable."
        return $false
    }
    $code = @'
// BEGIN PI_OPENCODE_GO_SETUP
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const {createRequire} = require('node:module');
const {spawn} = require('node:child_process');
const crypto = require('node:crypto');
let operation = 'preflight';
class GoSetupError extends Error {
    constructor(code) { super(code); this.operation = operation; }
}
// Only controlled codes cross stdout. Never serialize an exception or a path.
const nativeErrors = new Set('EACCES EPERM EROFS ENOSPC EDQUOT ENOENT ENOTDIR EISDIR ELOOP EEXIST EIO ELOCKED ECOMPROMISED MODULE_NOT_FOUND ERR_PACKAGE_PATH_NOT_EXPORTED'.split(' '));
const failureReason = error => error instanceof GoSetupError ? error.message :
    nativeErrors.has(error?.code) ? error.code : 'operation-failed';
const fail = code => { throw new GoSetupError(code); };
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const windows = process.platform === 'win32';
const uid = windows ? null : process.getuid();
const within = (file, base) => {
    const key = value => windows ? value.toLowerCase() : value;
    return key(file) === key(base) || key(file).startsWith(key(base + path.sep));
};
function info(file) {
    try { return fs.lstatSync(file); }
    catch (error) { if (error.code === 'ENOENT') return null; throw error; }
}
function absolute(value) {
    if (!value || !path.isAbsolute(value) || value.split(/[\\/]/).some(part => part === '.' || part === '..')) fail('unsafe-path');
    return path.resolve(value);
}
function systemHomeAlias(file, stat) {
    if (process.platform !== 'linux' || file !== '/home' || stat.uid !== 0) return false;
    if (!['var/home', '/var/home'].includes(fs.readlinkSync(file))) return false;
    return ['/', '/var', '/var/home'].every(dir => {
        const entry = info(dir);
        return entry && entry.isDirectory() && !entry.isSymbolicLink() && entry.uid === 0 && !(entry.mode & 0o022);
    });
}
const directorySnapshots = new Map();
function directoryChain(directory, missing = false, installed = false, credentialBoundary = false) {
    const chain = [];
    for (let current = directory; ; current = path.dirname(current)) {
        chain.unshift(current);
        if (current === path.dirname(current)) break;
    }
    for (const current of chain) {
        const stat = info(current);
        if (!stat && missing) continue;
        if (!stat) fail('missing-directory');
        if (stat.isSymbolicLink() && systemHomeAlias(current, stat)) continue;
        if (!stat.isDirectory() || stat.isSymbolicLink()) fail('linked-directory');
        // A root-owned sticky temporary ancestor cannot replace this user's child.
        const stickyRoot = stat.uid === 0 && (stat.mode & 0o1000);
        // Ordinary account ancestors retain their modes. The direct credential
        // writer stays non-writable; installed-code and system rules are unchanged.
        const ordinary = stat.uid === uid && uid !== 0 && !(credentialBoundary && current === directory);
        const mask = installed || ordinary ? 0o002 : 0o022;
        if (!windows) {
            if (![0, uid].includes(stat.uid) || ((stat.mode & mask) && !stickyRoot)) fail('untrusted-directory');
            const before = directorySnapshots.get(current);
            if (before && ['dev', 'ino', 'mode', 'uid', 'gid'].some(field => before[field] !== stat[field])) fail('concurrent-metadata-change');
            directorySnapshots.set(current, stat);
        }
    }
}
function regular(file, privateFile = false, installed = false) {
    directoryChain(path.dirname(file), false, installed);
    const stat = info(file);
    if (!stat) return null;
    if (!stat.isFile() || stat.isSymbolicLink() || stat.nlink !== 1) fail('linked-or-nonregular-file');
    if (!windows && (stat.uid !== uid && stat.uid !== 0 || stat.mode & (privateFile ? 0o077 : installed ? 0o002 : 0o022))) fail('unsafe-file-permissions');
    if (privateFile && !windows && stat.uid !== uid) fail('unowned-auth-file');
    if (stat.size > 2 * 1024 * 1024) fail('oversized-metadata');
    return stat;
}
function readText(file, privateFile = false, installed = false) {
    const before = regular(file, privateFile, installed);
    if (!before) return null;
    const fd = fs.openSync(file, fs.constants.O_RDONLY | (fs.constants.O_NOFOLLOW || 0));
    try {
        const opened = fs.fstatSync(fd);
        if (opened.ino !== before.ino || opened.dev !== before.dev || opened.nlink !== 1) fail('file-changed');
        return fs.readFileSync(fd, 'utf8');
    } finally { fs.closeSync(fd); }
}
function json(text) {
    let value;
    try {
        value = JSON.parse(text.replace(/^\uFEFF/, ''), (_key, item) => {
            if (typeof item === 'number' && (!Number.isFinite(item) || Number.isInteger(item) && !Number.isSafeInteger(item))) fail('unsafe-json-number');
            return item;
        });
    } catch { fail('invalid-json'); }
    // JSON.parse silently discards duplicate keys, which could discard credentials.
    const tokens = text.match(/"(?:[^"\\]|\\.)*"|[{}\[\]:,]/g) || [];
    const stack = [];
    for (let i = 0; i < tokens.length; i++) {
        const token = tokens[i];
        if (token === '{' || token === '[') stack.push(token === '{' ? new Set() : null);
        else if (token === '}' || token === ']') stack.pop();
        else if (token.startsWith('"') && tokens[i + 1] === ':') {
            const name = JSON.parse(token);
            const names = stack[stack.length - 1];
            if (!names || names.has(name)) fail('duplicate-json-key');
            names.add(name);
        }
    }
    if (!object(value)) fail('invalid-json-object');
    return value;
}
// No provider SDK, auth resolver, extension, or model process is loaded here.
function installedPackages(home) {
    operation = 'pi-package';
    const prefix = path.join(home, '.local', ...(windows ? [] : ['lib']), 'node_modules');
    const manifest = path.join(prefix, '@earendil-works/pi-coding-agent/package.json');
    // npm inherits the account umask. This already-installed/executed code is trusted
    // like Pi itself; credential paths still require private, non-writable boundaries.
    const metadata = json(readText(manifest, false, true) || 'null');
    if (metadata.name !== '@earendil-works/pi-coding-agent') fail('pi-package-unavailable');
    const request = createRequire(manifest);
    function dependency(name) {
        for (const search of request.resolve.paths(name) || []) {
            if (!within(search, prefix)) continue;
            const root = path.join(search, name);
            directoryChain(root, true, true);
            const contents = info(path.join(root, 'package.json')) ? readText(path.join(root, 'package.json'), false, true) : null;
            if (contents !== null) {
                const data = json(contents);
                if (data.name !== name) fail('unexpected-dependency');
                return {root, data};
            }
        }
        fail('pi-dependency-unavailable');
    }
    operation = 'pi-dependency';
    const ai = dependency('@earendil-works/pi-ai');
    operation = 'go-catalog';
    const catalog = json(readText(path.join(ai.root, 'dist/providers/data/opencode-go.json'), false, true) || 'null');
    const id = 'muse-spark-1.3-contributor';
    const matches = Object.values(catalog).flatMap(group => object(group) ? Object.values(group).filter(model => model?.id === id) : []);
    const responses = catalog['openai-responses'];
    const model = responses?.[id] ?? responses?.['chat:' + id];
    const typed = model !== responses?.[id];
    if (matches.length !== 1 || matches[0] !== model ||
        ((typed || Object.hasOwn(model, 'type')) && model.type !== 'chat') || model.provider !== 'opencode-go' ||
        model.api !== 'openai-responses' || model.baseUrl !== 'https://opencode.ai/zen/go/v1' ||
        model.reasoning !== true || model.thinkingLevelMap?.xhigh !== 'xhigh') fail('catalog-incompatible');
    return {request, dependency, prefix};
}
// PowerShell receives only a path/action, never credentials, via its environment.
// Async execution keeps the native lock heartbeat alive while Windows checks ACLs.
async function acl(file, action) {
    if (!windows) return;
    const script = String.raw`$ErrorActionPreference = 'Stop'
$env:PSModulePath = "$PSHOME\Modules"
try {
    $file = $env:PI_GO_ACL_PATH
    $action = $env:PI_GO_ACL_ACTION
    $owner = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
    $allowed = @($owner.Value, 'S-1-5-18', 'S-1-5-32-544')
    $target = Get-Item -LiteralPath $file -Force -ErrorAction Stop
    $boundary = if ($target.PSIsContainer) { $file } else { Split-Path -Parent $file }
    $current = $file
    while ($current) {
        $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'linked' }
        $security = Get-Acl -LiteralPath $current
        $owners = $allowed
        if ($current -ne $file -and $current -ne $boundary) {
            # TrustedInstaller can own system ancestors, never the secret or its parent.
            $owners += 'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464'
        }
        if ($security.GetOwner([System.Security.Principal.SecurityIdentifier]).Value -notin $owners) { throw 'owner' }
        $write = [System.Security.AccessControl.FileSystemRights]::Delete -bor [System.Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles -bor [System.Security.AccessControl.FileSystemRights]::ChangePermissions -bor [System.Security.AccessControl.FileSystemRights]::TakeOwnership
        if ($current -eq $file -or $current -eq $boundary) { $write = $write -bor [System.Security.AccessControl.FileSystemRights]::Write }
        foreach ($rule in $security.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier])) {
            if ($rule.PropagationFlags -band [System.Security.AccessControl.PropagationFlags]::InheritOnly) { continue }
            if ($rule.AccessControlType -eq 'Allow' -and $rule.IdentityReference.Value -notin $allowed) {
                if (($rule.FileSystemRights -band $write) -or ($current -eq $file -and $action -eq 'private')) { throw 'access' }
            }
        }
        $current = Split-Path -Parent $current
    }
    if ($action -eq 'secure') {
        $security = [System.Security.AccessControl.FileSecurity]::new()
        $security.SetOwner($owner)
        $security.SetAccessRuleProtection($true, $false)
        foreach ($sid in $allowed) {
            $security.AddAccessRule([System.Security.AccessControl.FileSystemAccessRule]::new([System.Security.Principal.SecurityIdentifier]::new($sid), 'FullControl', 'Allow'))
        }
        Set-Acl -LiteralPath $file -AclObject $security
    }
    [Console]::Out.Write('ok')
} catch { exit 1 }`;
    const systemRoot = absolute(process.env.SystemRoot || 'C:\\Windows');
    const executable = path.join(systemRoot, 'System32/WindowsPowerShell/v1.0/powershell.exe');
    await new Promise((resolve, reject) => {
        const child = spawn(executable, ['-NoProfile', '-NonInteractive', '-EncodedCommand', Buffer.from(script, 'utf16le').toString('base64')], {
            env: {SystemRoot: systemRoot, WINDIR: systemRoot, PI_GO_ACL_PATH: file, PI_GO_ACL_ACTION: action},
            windowsHide: true, shell: false, stdio: ['ignore', 'pipe', 'pipe'],
        });
        let output = '';
        const timer = setTimeout(() => { child.kill(); reject(new GoSetupError('acl-timeout')); }, 15000);
        child.stdout.on('data', data => { if (output.length < 32) output += data.toString(); });
        child.stderr.resume();
        child.on('error', () => { clearTimeout(timer); reject(new GoSetupError('acl-unavailable')); });
        child.on('close', code => {
            clearTimeout(timer);
            if (code === 0 && output === 'ok') resolve(); else reject(new GoSetupError('acl-unsafe'));
        });
    });
}
function envKey(home) {
    const text = readText(path.join(home, '.env.local'));
    if (text === null) return '';
    let result = '';
    for (const line of text.replace(/^\uFEFF/, '').split(/\r?\n/)) {
        const match = line.match(/^[ \t]*(?:export[ \t]+)?OPENCODE_GO_API_KEY[ \t]*=[ \t]*(.*)$/);
        if (!match) continue;
        result = match[1].trim();
        if (result.length >= 2 && ['"', "'"].includes(result[0]) && result.at(-1) === result[0]) result = result.slice(1, -1).trim();
    }
    // Accept plain token syntax, never Pi's $ interpolation or ! command syntax.
    if (result && !/^[A-Za-z0-9._~+/=-]{1,4096}$/.test(result)) fail('invalid-key-format');
    if (result) regular(path.join(home, '.env.local'), true);
    return result;
}
function authDocument(text) {
    const document = json(text);
    for (const credential of Object.values(document)) {
        if (!object(credential) || typeof credential.type !== 'string' || !credential.type) fail('invalid-credential');
        if (credential.type === 'api_key' &&
            (credential.key !== undefined && typeof credential.key !== 'string' || credential.env !== undefined &&
                (!object(credential.env) || Object.values(credential.env).some(value => typeof value !== 'string')))) fail('invalid-credential');
    }
    return document;
}
async function main() {
    process.umask(0o077);
    if (!['sync', 'check-catalog'].includes(process.argv[4] || 'sync')) fail('invalid-mode');
    const [major, minor] = process.versions.node.split('.').map(Number);
    if (major < 22 || major === 22 && minor < 20 || typeof fs.globSync !== 'function') fail('node-incompatible');
    operation = 'home';
    const logicalHome = absolute(process.argv[2]);
    directoryChain(logicalHome);
    const home = fs.realpathSync(logicalHome); // Only the verified account HOME boundary is resolved.
    if (!windows && fs.statSync(home).uid !== uid) fail('unowned-home');
    await acl(home, 'directory');
    const packages = installedPackages(home);
    if (process.argv[4] === 'check-catalog') return 'catalog-ready';
    operation = 'environment-file';
    const envFile = path.join(home, '.env.local');
    if (info(envFile)) await acl(envFile, 'directory');
    const key = envKey(home);
    if (key) await acl(envFile, 'private');
    operation = 'active-profile';
    let selected = process.argv[3] || path.join(logicalHome, '.pi/agent');
    if (selected === '~' || selected.startsWith('~/') || windows && selected.startsWith('~\\')) selected = path.join(logicalHome, selected.slice(2));
    selected = absolute(selected);
    const profile = within(selected, logicalHome) ? path.join(home, path.relative(logicalHome, selected)) : selected;
    if (profile === path.parse(profile).root || profile === home) fail('unsafe-profile');
    directoryChain(profile, true, false, true);
    if (info(profile)) {
        operation = 'models-json';
        const modelsText = readText(path.join(profile, 'models.json'));
        if (modelsText !== null) {
            const models = json(modelsText);
            if (models.providers !== undefined && !object(models.providers)) fail('invalid-providers');
            if (models.providers && Object.hasOwn(models.providers, 'opencode-go')) fail('go-provider-overridden');
        }
    }
    if (!key) return 'missing-key'; // Never open auth.json or create a profile for absent input.
    operation = 'auth-lock';
    const auth = path.join(profile, 'auth.json');
    const lockPath = auth + '.lock';
    function inspectLock() {
        const stat = info(lockPath);
        if (stat && (!stat.isDirectory() || stat.isSymbolicLink() || !windows && (stat.uid !== uid || stat.mode & 0o002) || fs.readdirSync(lockPath).length)) fail('unsafe-lock');
        return stat;
    }
    inspectLock();
    operation = 'lock-dependency';
    const dependency = packages.dependency('proper-lockfile');
    if (dependency.data.version !== '4.1.2') fail('lock-version-unsupported');
    const expectedEntry = path.join(dependency.root, 'index.js');
    if (!regular(expectedEntry, false, true)) fail('unsafe-lock-dependency');
    const lockEntry = packages.request.resolve('proper-lockfile');
    if (lockEntry !== expectedEntry) fail('unsafe-lock-dependency');
    await acl(lockEntry, 'directory');
    const lockfile = packages.request(lockEntry); // Only Pi's installed native lock dependency executes.
    if (typeof lockfile.lock !== 'function') fail('lock-unavailable');
    // Preflight existing metadata before creating directories or lock files.
    operation = 'auth-preflight';
    if (info(profile)) {
        await acl(profile, 'directory');
        if (regular(auth, true)) {
            await acl(auth, 'private');
            // Actual content is read only after locking; OAuth may be writing now.
        }
    }
    operation = 'profile-create';
    fs.mkdirSync(profile, {recursive: true, mode: 0o700});
    directoryChain(profile, false, false, true);
    await acl(profile, 'directory');
    let compromised = false;
    let release;
    let temporary;
    try {
        // realpath:false matches Pi; locking by pathname also survives atomic rename.
        // A short update interval interoperates with Pi's synchronous 10s stale timeout.
        operation = 'lock-acquire';
        release = await lockfile.lock(auth, {realpath: false, stale: 30000, update: 1000,
            retries: {retries: 30, minTimeout: 100, maxTimeout: 1000, factor: 1.2},
            onCompromised: () => { compromised = true; }});
        operation = 'auth-read';
        const held = inspectLock();
        if (!held) fail('lock-unverified');
        directoryChain(profile, false, false, true);
        const before = readText(auth, true);
        if (before !== null) await acl(auth, 'private');
        const document = before === null ? {} : authDocument(before);
        if (compromised) fail('lock-compromised');
        const replacement = {type: 'api_key', key};
        if (JSON.stringify(document['opencode-go']) === JSON.stringify(replacement)) return 'unchanged';
        document['opencode-go'] = replacement;
        operation = 'auth-write';
        temporary = path.join(profile, '.opencode-go-' + crypto.randomBytes(16).toString('hex'));
        // Empty file first: inherited Windows ACLs are secured before any secret write.
        const fd = fs.openSync(temporary, 'wx', 0o600);
        try {
            await acl(temporary, 'secure');
            await acl(temporary, 'private');
            directoryChain(profile, false, false, true);
            const currentLock = inspectLock();
            if (compromised || !currentLock || held.ino !== currentLock.ino || held.dev !== currentLock.dev) fail('lock-compromised');
            if (readText(auth, true) !== before) fail('concurrent-metadata-change');
            fs.writeFileSync(fd, (before?.startsWith('\uFEFF') ? '\uFEFF' : '') + JSON.stringify(document, null, 2) + '\n');
            fs.fsyncSync(fd);
        } finally { fs.closeSync(fd); }
        fs.renameSync(temporary, auth);
        temporary = null;
        if (!windows) {
            const fd = fs.openSync(profile, 'r');
            try { fs.fsyncSync(fd); } finally { fs.closeSync(fd); }
        }
        if (compromised) fail('lock-compromised');
        return 'updated';
    } catch (error) {
        // Preserve the failing phase when finally advances to cleanup/release.
        throw error instanceof GoSetupError ? error : new GoSetupError(failureReason(error));
    } finally {
        operation = 'auth-cleanup';
        if (temporary && info(temporary)) fs.unlinkSync(temporary);
        operation = 'lock-release';
        if (release) await release();
    }
}
main().then(result => console.log(result)).catch(error => {
    const phase = error instanceof GoSetupError ? error.operation : operation;
    console.log('go-failure:' + phase + ':' + failureReason(error));
    process.exitCode = 1;
});
// END PI_OPENCODE_GO_SETUP
'@
    $previousNodeOptions = $env:NODE_OPTIONS
    $previousNodePath = $env:NODE_PATH
    try {
        $env:NODE_OPTIONS = $null
        $env:NODE_PATH = $null
        $mode = if ($CheckCatalog) { 'check-catalog' } else { 'sync' }
        $active = if ($env:PI_CODING_AGENT_DIR) { $env:PI_CODING_AGENT_DIR } else { Join-Path $env:USERPROFILE '.pi/agent' }
        $global:LASTEXITCODE = 0
        $PSNativeCommandUseErrorActionPreference = $false
        $result = ($code | & $node.Source --input-type=commonjs - $env:USERPROFILE $active $mode 2>$null | Out-String).Trim()
        $helperExit = $LASTEXITCODE
        if ($helperExit -ne 0) {
            if ($result -cmatch "\Ago-failure:($operations):($reasons)\z") {
                Write-Warning "Pi Go setup failed: $($Matches[1]): $($Matches[2]). Review this check locally, then rerun setup."
            } else {
                Write-Warning "Pi Go setup failed: helper-exit-${helperExit}: diagnostic-unavailable. No safe helper detail was received."
            }
            return $false
        }
        switch ($result) {
            'missing-key' { Write-Warning "Pi Go authentication not supplied: add OPENCODE_GO_API_KEY to ~/.env.local. Existing credentials were preserved." }
            'updated' { Write-Success "Pi Go credential synchronized in the active Pi profile." }
            'unchanged' { Write-Debug "Pi Go credential is unchanged." }
            'catalog-ready' { Write-Debug "Installed Pi supports Go Muse Contributor with native Responses/xhigh." }
            default {
                Write-Warning "Pi Go setup failed: invalid-helper-result. No safe helper detail was received."
                return $false
            }
        }
        return $true
    } catch {
        Write-Warning "Pi Go setup failed: helper-execution: diagnostic-unavailable. No safe helper detail was received."
        return $false
    } finally {
        $env:NODE_OPTIONS = $previousNodeOptions
        $env:NODE_PATH = $previousNodePath
    }
}

function Set-PiDefaults {
    if ($env:PI_CODING_AGENT_DIR) {
        $agentDir = $env:PI_CODING_AGENT_DIR
    }
    else {
        $agentDir = Join-Path $env:USERPROFILE ".pi\agent"
    }

    $settingsPath = Join-Path $agentDir "settings.json"

    if (-not (Test-Path $agentDir)) {
        New-Item -ItemType Directory -Force -Path $agentDir | Out-Null
    }

    $settingsJson = "{}"
    if (Test-Path $settingsPath) {
        $settingsJson = Get-Content -Path $settingsPath -Raw
        if ([string]::IsNullOrWhiteSpace($settingsJson)) {
            $settingsJson = "{}"
        }
    }

    try {
        $settings = $settingsJson | ConvertFrom-Json
        if ($null -eq $settings) {
            $settings = New-Object PSObject
        }
        Set-JsonProperty -Object $settings -Name "defaultProvider" -Value "openai-codex"
        Set-JsonProperty -Object $settings -Name "defaultModel" -Value "gpt-6-astra"
        Set-JsonProperty -Object $settings -Name "defaultThinkingLevel" -Value "xhigh"
        if ($null -eq $settings.modelThinkingLevels) {
            Set-JsonProperty -Object $settings -Name "modelThinkingLevels" -Value ([PSCustomObject]@{})
        }
        Set-JsonProperty -Object $settings.modelThinkingLevels -Name "openai-codex/gpt-6-astra" -Value "xhigh"
        $settings | ConvertTo-Json -Depth 20 | Set-Content -Path $settingsPath -Encoding UTF8
        Write-Host "$success Pi default model set to GPT-6 Astra (OpenAI Codex) with xhigh thinking." -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "$failIcon Failed to write Pi defaults to $settingsPath : $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Get-EnvLocalValue {
    param([Parameter(Mandatory=$true)][string]$Name)

    $envValue = [Environment]::GetEnvironmentVariable($Name)
    if (-not [string]::IsNullOrWhiteSpace($envValue)) {
        return $envValue
    }

    $envLocalFile = Join-Path $env:USERPROFILE ".env.local"
    if (Test-Path $envLocalFile) {
        $match = Get-Content $envLocalFile | Where-Object { $_ -match "^\s*(export\s+)?$Name=" } | Select-Object -Last 1
        if ($match) {
            $value = ($match -replace "^\s*(export\s+)?$Name=", "").Trim()
            $value = $value.Trim('"').Trim("'")
            if (-not [string]::IsNullOrWhiteSpace($value)) {
                return $value
            }
        }
    }
    return $null
}

function Remove-PiSyntheticModels {
    if ($env:PI_CODING_AGENT_DIR) {
        $agentDir = $env:PI_CODING_AGENT_DIR
    }
    else {
        $agentDir = Join-Path $env:USERPROFILE ".pi\agent"
    }
    $modelsPath = Join-Path $agentDir "models.json"
    if (-not (Test-Path -LiteralPath $modelsPath)) {
        return $true
    }

    try {
        $modelsJson = Get-Content -LiteralPath $modelsPath -Raw -ErrorAction Stop
        $models = $modelsJson | ConvertFrom-Json -ErrorAction Stop
        if ($models -isnot [PSCustomObject] -or -not $modelsJson.TrimStart().StartsWith('{') -or
            ($null -ne $models.providers -and $models.providers -isnot [PSCustomObject])) {
            Write-Warning "Invalid Pi models at $modelsPath; leaving the file unchanged."
            return $false
        }
        if ($null -eq $models.providers -or -not $models.providers.PSObject.Properties['synthetic']) {
            return $true
        }
        $models.providers.PSObject.Properties.Remove('synthetic')
        $models | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $modelsPath -Encoding UTF8 -ErrorAction Stop
        Write-Host "$success Removed the Synthetic provider from $modelsPath." -ForegroundColor Green
        return $true
    }
    catch {
        Write-Warning "Failed to remove the Synthetic provider from $modelsPath."
        return $false
    }
}

function Seed-PiZaiModels {
    if ($env:PI_CODING_AGENT_DIR) {
        $agentDir = $env:PI_CODING_AGENT_DIR
    }
    else {
        $agentDir = Join-Path $env:USERPROFILE ".pi\agent"
    }

    $modelsPath = Join-Path $agentDir "models.json"

    $modelsJson = '{"providers":{}}'
    if (Test-Path $modelsPath) {
        $modelsJson = Get-Content -Path $modelsPath -Raw
        if ([string]::IsNullOrWhiteSpace($modelsJson)) {
            $modelsJson = '{"providers":{}}'
        }
    }

    try {
        $models = $modelsJson | ConvertFrom-Json
        if ($null -eq $models) {
            $models = [PSCustomObject]@{ providers = [PSCustomObject]@{} }
        }
        if ($null -eq $models.providers) {
            $models | Add-Member -NotePropertyName "providers" -NotePropertyValue ([PSCustomObject]@{}) -Force
        }

        $existingKey = $null
        if ($models.providers.PSObject.Properties.Name -contains "zai") {
            $existingKey = $models.providers.zai.apiKey
        }
        if (-not [string]::IsNullOrWhiteSpace($existingKey)) {
            Write-Debug "z.ai provider with an API key already configured in $modelsPath."
            return $true
        }

        $apiKey = Get-EnvLocalValue "ZAI_API_KEY"
        if ([string]::IsNullOrWhiteSpace($apiKey)) {
            if (Test-EnvLocalFlag "WORK_MACHINE") {
                Write-Warning "ZAI_API_KEY not set in ~/.env.local. Add the key and rerun setup to enable the optional z.ai provider."
                return $false
            }
            Write-Debug "ZAI_API_KEY not set in ~/.env.local; skipping z.ai provider seeding."
            return $true
        }

        $zaiProvider = [PSCustomObject]@{
            baseUrl = "https://api.z.ai/api/coding/paas/v4"
            api     = "openai-completions"
            apiKey  = $apiKey
            compat  = [PSCustomObject]@{
                supportsDeveloperRole = $false
                supportsStore         = $false
                maxTokensField        = "max_tokens"
                supportsStrictMode    = $false
            }
            models  = @(
                [PSCustomObject]@{
                    id               = "glm-5.3"
                    name             = "GLM-5.3 (z.ai)"
                    reasoning        = $true
                    thinkingLevelMap = [PSCustomObject]@{
                        off     = $null
                        minimal = $null
                        low     = "low"
                        medium  = $null
                        high    = "high"
                        xhigh   = $null
                        max     = "max"
                    }
                    input            = @("text")
                    contextWindow    = 1000000
                    maxTokens        = 131072
                    cost             = [PSCustomObject]@{ input = 0; output = 0; cacheRead = 0; cacheWrite = 0 }
                    compat           = [PSCustomObject]@{
                        supportsReasoningEffort = $true
                        thinkingFormat          = "openai"
                    }
                },
                [PSCustomObject]@{
                    id               = "glm-5-turbo"
                    name             = "GLM-5-Turbo (z.ai)"
                    reasoning        = $true
                    thinkingLevelMap = [PSCustomObject]@{
                        off     = "none"
                        minimal = "minimal"
                        low     = "low"
                        medium  = "medium"
                        high    = "high"
                        xhigh   = "xhigh"
                        max     = "max"
                    }
                    input            = @("text")
                    contextWindow    = 200000
                    maxTokens        = 131072
                    cost             = [PSCustomObject]@{ input = 0; output = 0; cacheRead = 0; cacheWrite = 0 }
                    compat           = [PSCustomObject]@{
                        supportsReasoningEffort = $true
                        thinkingFormat          = "openai"
                    }
                },
                [PSCustomObject]@{
                    id            = "glm-4.7"
                    name          = "GLM-4.7 (z.ai)"
                    reasoning     = $true
                    input         = @("text")
                    contextWindow = 200000
                    maxTokens     = 131072
                    cost          = [PSCustomObject]@{ input = 0; output = 0; cacheRead = 0; cacheWrite = 0 }
                    compat        = [PSCustomObject]@{
                        supportsReasoningEffort = $false
                        thinkingFormat          = "openai"
                    }
                }
            )
        }

        if ($models.providers.PSObject.Properties.Name -contains "zai") {
            $models.providers.zai = $zaiProvider
        }
        else {
            $models.providers | Add-Member -NotePropertyName "zai" -NotePropertyValue $zaiProvider
        }

        $models | ConvertTo-Json -Depth 20 | Set-Content -Path $modelsPath -Encoding UTF8
        Write-Host "$success z.ai provider (GLM Coding Plan) seeded in $modelsPath." -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "$failIcon Failed to seed z.ai provider in $modelsPath : $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Set-JsonProperty {
    param(
        [Parameter(Mandatory=$true)]$Object,
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)]
        [AllowNull()]
        [AllowEmptyCollection()]$Value
    )

    $property = $Object.PSObject.Properties[$Name]
    if ($property) {
        $property.Value = $Value
    }
    else {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    }
}

function Remove-JsonProperty {
    param(
        [Parameter(Mandatory=$true)]$Object,
        [Parameter(Mandatory=$true)][string]$Name
    )

    if ($Object.PSObject.Properties[$Name]) {
        $Object.PSObject.Properties.Remove($Name)
    }
}

function Remove-PiSubagents {
    $hadFailure = $false
    if (Get-Command pi -ErrorAction SilentlyContinue) {
        foreach ($package in @("npm:@tintinweb/pi-subagents", "npm:pi-subagents")) {
            $output = & pi remove $package 2>&1
            $removeExitCode = $LASTEXITCODE
            $outputText = ($output | Out-String)
            if ($removeExitCode -eq 0) {
                Write-Success "Removed Pi subagents extension ($package)."
            }
            elseif ($outputText -match "no matching package found") {
                Write-Debug "Pi subagents extension not installed ($package)."
            }
            else {
                Write-Warning "Failed to remove Pi subagents extension ($package): $outputText"
                $hadFailure = $true
            }
        }
        return (-not $hadFailure)
    }

    if ($env:PI_CODING_AGENT_DIR) {
        $agentDir = $env:PI_CODING_AGENT_DIR
    }
    else {
        $agentDir = Join-Path $env:USERPROFILE ".pi\agent"
    }

    $settingsPath = Join-Path $agentDir "settings.json"

    if (-not (Test-Path $settingsPath)) {
        Write-Debug "Pi settings not found; Pi subagents extension not installed."
        return $true
    }

    $settingsJson = Get-Content -Path $settingsPath -Raw
    if ([string]::IsNullOrWhiteSpace($settingsJson)) {
        $settingsJson = "{}"
    }

    try {
        $settings = $settingsJson | ConvertFrom-Json
        if ($null -eq $settings) {
            $settings = New-Object PSObject
        }
    }
    catch {
        Write-Warning "Failed to parse Pi settings at $settingsPath. Leaving settings unchanged."
        return $false
    }

    $packages = @()
    if ($settings.PSObject.Properties["packages"]) {
        $packages = @($settings.packages)
    }

    $filteredPackages = @()
    foreach ($package in $packages) {
        $source = ""
        if ($package -is [string]) {
            $source = $package
        }
        elseif ($null -ne $package -and $package.PSObject.Properties["source"]) {
            $source = [string]$package.source
        }

        if ($source -ne "npm:pi-subagents" -and $source -ne "npm:@tintinweb/pi-subagents") {
            $filteredPackages += $package
        }
    }

    if ($filteredPackages.Count -eq 0) {
        Remove-JsonProperty -Object $settings -Name "packages"
    }
    else {
        Set-JsonProperty -Object $settings -Name "packages" -Value ([object[]]$filteredPackages)
    }

    try {
        $settings | ConvertTo-Json -Depth 20 | Set-Content -Path $settingsPath -Encoding UTF8
        Write-Success "Removed Pi subagents extension from Pi settings."
    }
    catch {
        Write-Warning "Failed to write Pi settings at $settingsPath."
        return $false
    }
    return $true
}

function Invoke-BacklogMcpWindowsRetirement {
    param([string]$Program, [string[]]$Profiles)
    $ErrorActionPreference = 'Stop'
    $phase = 'preflight'
    $pins = @{}
    $records = @()
    try {
        $PSModuleAutoLoadingPreference = 'None'
        Import-Module (Join-Path $PSHOME 'Modules/Microsoft.PowerShell.Utility/Microsoft.PowerShell.Utility.psd1') -ErrorAction Stop
        if (-not ('BacklogNativeFiles' -as [type])) {
            Add-Type -TypeDefinition @'
// BEGIN BACKLOG_WINDOWS_NATIVE
using System;
using System.IO;
using System.Text;
using System.Collections.Generic;
using System.Diagnostics;
using System.Threading.Tasks;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Principal;
using Microsoft.Win32.SafeHandles;
public static class BacklogNativeFiles {
    const int Limit = 2 * 1024 * 1024;
    [StructLayout(LayoutKind.Sequential)]
    struct Info {
        public uint Attributes, CreatedLow, CreatedHigh, AccessLow, AccessHigh,
            WriteLow, WriteHigh, Volume, SizeHigh, SizeLow, Links, IndexHigh, IndexLow;
    }
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern SafeFileHandle CreateFile(string name, uint access, uint share, IntPtr security, uint creation, uint flags, IntPtr template);
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern bool GetFileInformationByHandle(SafeFileHandle file, out Info info);
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern uint GetFileType(SafeFileHandle file);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern uint GetFinalPathNameByHandle(SafeFileHandle file, StringBuilder name, uint length, uint flags);
    [DllImport("advapi32.dll", SetLastError=true)]
    static extern bool GetKernelObjectSecurity(SafeFileHandle file, uint information, byte[] descriptor, uint length, out uint needed);
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern bool SetFilePointerEx(SafeFileHandle file, long distance, out long position, uint method);
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern bool ReadFile(SafeFileHandle file, byte[] data, uint length, out uint read, IntPtr overlapped);
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern bool WriteFile(SafeFileHandle file, byte[] data, uint length, out uint written, IntPtr overlapped);
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern bool SetEndOfFile(SafeFileHandle file);
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern bool FlushFileBuffers(SafeFileHandle file);
    static Exception Refuse() { return new InvalidOperationException("native-preflight"); }
    public static string Canonical(string name) {
        if (String.IsNullOrEmpty(name) || name.Length < 3 || !Char.IsLetter(name[0]) || name[1] != ':' || name[2] != '\\' || name.Contains("/")) throw Refuse();
        foreach (string part in name.Substring(3).Split('\\')) {
            if (part == "." || part == ".." || part.EndsWith(".") || part.EndsWith(" ") || part.IndexOfAny(new char[]{':','*','?','"','<','>','|'}) >= 0) throw Refuse();
            string stem = part.Split('.')[0].ToUpperInvariant();
            if (stem == "CON" || stem == "PRN" || stem == "AUX" || stem == "NUL" || stem == "CONIN$" || stem == "CONOUT$" ||
                (stem.Length == 4 && (stem.StartsWith("COM") || stem.StartsWith("LPT")) && Char.IsDigit(stem[3]))) throw Refuse();
        }
        string full = Path.GetFullPath(name);
        if (!String.Equals(full.TrimEnd('\\'), name.TrimEnd('\\'), StringComparison.OrdinalIgnoreCase)) throw Refuse();
        return full.Length == 3 ? full : full.TrimEnd('\\');
    }
    public static bool Below(string name, string home) {
        return name.StartsWith(home.TrimEnd('\\') + "\\", StringComparison.OrdinalIgnoreCase);
    }
    public static string ResolveRuntime(string name) {
        // Only the trusted tool's executable alias may be resolved. Metadata
        // paths always use OPEN_REPARSE_POINT and reject every reparse entry.
        Canonical(name);
        using (var file=CreateFile(name,0x80020000u,1,IntPtr.Zero,3,0,IntPtr.Zero)) {
            if (file.IsInvalid || GetFileType(file) != 1) throw Refuse();
            return FinalPath(file);
        }
    }
    static string FinalPath(SafeFileHandle file) {
        var text=new StringBuilder(32768);
        uint count=GetFinalPathNameByHandle(file,text,(uint)text.Capacity,0);
        if (count == 0 || count >= text.Capacity) throw Refuse();
        string full=text.ToString();
        if (!full.StartsWith("\\\\?\\",StringComparison.Ordinal)) throw Refuse();
        return Canonical(full.Substring(4));
    }
    static bool BytesEqual(byte[] a, byte[] b) {
        if (a.Length != b.Length) return false;
        for (int i=0; i<a.Length; i++) if (a[i] != b[i]) return false;
        return true;
    }
    static bool SameIdentity(Info a, Info b) {
        return a.Volume == b.Volume && a.IndexHigh == b.IndexHigh && a.IndexLow == b.IndexLow && a.CreatedHigh == b.CreatedHigh && a.CreatedLow == b.CreatedLow;
    }
    static bool SameFile(Info a, Info b) {
        return SameIdentity(a,b) && a.Attributes == b.Attributes && a.Links == b.Links && a.SizeHigh == b.SizeHigh && a.SizeLow == b.SizeLow && a.WriteHigh == b.WriteHigh && a.WriteLow == b.WriteLow;
    }
    public sealed class Pin : IDisposable {
        readonly SafeFileHandle handle;
        readonly bool directory, executable;
        Info before;
        readonly byte[] security;
        byte[] snapshot;
        public readonly string Name;
        internal Pin(string name, SafeFileHandle file, bool isDirectory, bool isExecutable) {
            Name=name; handle=file; directory=isDirectory; executable=isExecutable;
            try { before=Inspect(); security=Descriptor(); if (!directory && !executable) snapshot=ReadBytes(); }
            catch { handle.Dispose(); throw; }
        }
        Info Inspect() {
            Info value;
            if (handle.IsInvalid || GetFileType(handle) != 1 || !GetFileInformationByHandle(handle,out value)) throw Refuse();
            if ((value.Attributes & 0x400) != 0 || ((value.Attributes & 0x10) != 0) != directory ||
                !String.Equals(Name,FinalPath(handle),StringComparison.OrdinalIgnoreCase)) throw Refuse();
            if (!directory && !executable && (value.Links != 1 || value.SizeHigh != 0 || value.SizeLow > Limit)) throw Refuse();
            return value;
        }
        byte[] Descriptor() {
            uint needed;
            GetKernelObjectSecurity(handle,7,null,0,out needed);
            if (needed == 0 || needed > 65536) throw Refuse();
            var bytes=new byte[needed];
            if (!GetKernelObjectSecurity(handle,7,bytes,needed,out needed)) throw Refuse();
            return bytes;
        }
        public void CheckAcl(string owner, string home, bool mutate) {
            var acl=new RawSecurityDescriptor(Descriptor(),0);
            string sid=acl.Owner == null ? "" : acl.Owner.Value;
            var allowed=new HashSet<string>(StringComparer.OrdinalIgnoreCase) {owner,"S-1-5-18","S-1-5-32-544"};
            const string installer="S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464";
            bool inside=String.Equals(Name,home,StringComparison.OrdinalIgnoreCase) || Below(Name,home);
            if ((mutate && !directory && !executable || String.Equals(Name,home,StringComparison.OrdinalIgnoreCase)) ? sid != owner : !allowed.Contains(sid) && sid != installer) throw Refuse();
            if (!mutate) return;
            // NULL DACL grants everyone full access. Unknown/object/callback ACEs are not guessed at.
            if (acl.DiscretionaryAcl == null) throw Refuse();
            int forbidden=0x10000 | 0x40000 | 0x80000 | 0x40; // delete, DACL/owner, delete-child
            if (inside || !directory) forbidden |= 0x2 | 0x4 | 0x10 | 0x100; // data, append, EA, attributes
            foreach (GenericAce ace in acl.DiscretionaryAcl) {
                var rule=ace as CommonAce;
                if (rule == null || rule.IsCallback) throw Refuse();
                if ((rule.AceFlags & AceFlags.InheritOnly) != 0 || rule.AceQualifier != AceQualifier.AccessAllowed) continue;
                if (!allowed.Contains(rule.SecurityIdentifier.Value) && rule.SecurityIdentifier.Value != installer && (rule.AccessMask & (forbidden | unchecked((int)0x50000000))) != 0) throw Refuse();
            }
        }
        byte[] ReadBytes() {
            Info value=Inspect();
            if (directory || executable || value.SizeHigh != 0 || value.SizeLow > Limit) throw Refuse();
            long position;
            if (!SetFilePointerEx(handle,0,out position,0)) throw Refuse();
            byte[] bytes=new byte[value.SizeLow]; int offset=0;
            while (offset<bytes.Length) {
                byte[] part=new byte[Math.Min(65536,bytes.Length-offset)]; uint count;
                if (!ReadFile(handle,part,(uint)part.Length,out count,IntPtr.Zero) || count == 0 || count > part.Length) throw Refuse();
                Buffer.BlockCopy(part,0,bytes,offset,(int)count); offset+=(int)count;
            }
            if (!SameFile(value,Inspect())) throw Refuse();
            return bytes;
        }
        public string Snapshot() { Verify(); return Convert.ToBase64String(snapshot); }
        public void Verify() {
            Info now=Inspect();
            if (!(directory ? SameIdentity(before,now) && before.Attributes == now.Attributes : SameFile(before,now)) || !BytesEqual(security,Descriptor())) throw Refuse();
            if (!directory && !executable && !BytesEqual(snapshot,ReadBytes())) throw Refuse();
        }
        public void Write(string encoded) {
            Verify(); byte[] bytes=Convert.FromBase64String(encoded);
            if (bytes.Length > Limit) throw Refuse();
            long position;
            if (!SetFilePointerEx(handle,0,out position,0)) throw Refuse();
            int offset=0;
            while (offset<bytes.Length) {
                byte[] part=new byte[Math.Min(65536,bytes.Length-offset)]; Buffer.BlockCopy(bytes,offset,part,0,part.Length); uint count;
                if (!WriteFile(handle,part,(uint)part.Length,out count,IntPtr.Zero) || count == 0 || count > part.Length) throw Refuse();
                offset+=(int)count;
            }
            if (!SetEndOfFile(handle) || !FlushFileBuffers(handle)) throw Refuse();
            Info now=Inspect();
            if (!SameIdentity(before,now) || !BytesEqual(security,Descriptor()) || !BytesEqual(bytes,ReadBytes())) throw Refuse();
            before=now; snapshot=bytes;
        }
        public void Dispose() { handle.Dispose(); }
    }
    public static Pin Open(string name, bool directory, bool executable, bool missing) {
        Canonical(name);
        // Ancestors remain pinned; never follow a reparse leaf. Deny write/delete sharing.
        uint access=directory ? 0x20021u : executable ? 0x80020000u : 0xC0020000u;
        var handle=CreateFile(name,access,1,IntPtr.Zero,3,0x00200000u | (directory ? 0x02000000u : 0u),IntPtr.Zero);
        if (handle.IsInvalid) {
            int error=Marshal.GetLastWin32Error(); handle.Dispose();
            if (missing && (error == 2 || error == 3)) return null;
            throw Refuse();
        }
        return new Pin(name,handle,directory,executable);
    }
    static string Drain(TextReader reader, int limit) {
        var text=new StringBuilder(); char[] buffer=new char[8192]; int count;
        while ((count=reader.Read(buffer,0,buffer.Length)) > 0) {
            if (text.Length+count>limit) throw Refuse(); text.Append(buffer,0,count);
        }
        return text.ToString();
    }
    public static string Plan(string bun, string request, string systemRoot) {
        const string launcher="const q=JSON.parse(require('node:fs').readFileSync(0,'utf8'));const records=q.records;eval(q.program);";
        var start=new ProcessStartInfo(bun,"--no-env-file --no-install --config=NUL --eval \""+launcher+"\"");
        start.UseShellExecute=false; start.CreateNoWindow=true; start.RedirectStandardInput=true; start.RedirectStandardOutput=true; start.RedirectStandardError=true;
        start.StandardOutputEncoding=new UTF8Encoding(false,true); start.StandardErrorEncoding=new UTF8Encoding(false,true);
        start.WorkingDirectory=Path.Combine(systemRoot,"System32"); start.EnvironmentVariables.Clear();
        foreach (string key in new string[]{"HOME","USERPROFILE","APPDATA","LOCALAPPDATA","XDG_CONFIG_HOME"}) start.EnvironmentVariables[key]=start.WorkingDirectory;
        start.EnvironmentVariables["SystemRoot"]=systemRoot; start.EnvironmentVariables["WINDIR"]=systemRoot;
        start.EnvironmentVariables["BUN_RUNTIME_TRANSPILER_CACHE_PATH"]="0";
        // No inherited PATH, NODE_OPTIONS, BUN_OPTIONS, preload, profile, dotenv, or npm controls.
        using (var process=new Process()) {
            process.StartInfo=start; if (!process.Start()) throw Refuse();
            var output=Task.Run(()=>Drain(process.StandardOutput,64*1024*1024));
            var errors=Task.Run(()=>Drain(process.StandardError,4096));
            var input=Task.Run(()=>{byte[] bytes=new UTF8Encoding(false,true).GetBytes(request); process.StandardInput.BaseStream.Write(bytes,0,bytes.Length); process.StandardInput.Close();});
            try {
                if (!process.WaitForExit(30000)) throw Refuse();
                if (!Task.WaitAll(new Task[]{input,output,errors},5000) || process.ExitCode != 0 || errors.Result.Length != 0) throw Refuse();
                return output.Result;
            } finally { if (!process.HasExited) { process.Kill(); process.WaitForExit(); } }
        }
    }
}
// END BACKLOG_WINDOWS_NATIVE
'@ -ErrorAction Stop
        }
        $homePath = [BacklogNativeFiles]::Canonical($Profiles[0])
        if ($homePath.Length -le 3) { throw 'home' }
        $owner = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        $systemRoot = [BacklogNativeFiles]::Canonical([Environment]::GetFolderPath([Environment+SpecialFolder]::Windows))
        function Select-BacklogProfile([string]$value, [string]$fallback) {
            if (-not $value) { $value = [IO.Path]::Combine($homePath, $fallback) }
            $value = [BacklogNativeFiles]::Canonical($value)
            if (-not [BacklogNativeFiles]::Below($value, $homePath)) { throw 'profile' }
            return $value
        }
        $pi = Select-BacklogProfile $Profiles[1] '.pi\agent'
        $claude = Select-BacklogProfile $Profiles[2] '.claude'
        $codex = Select-BacklogProfile $Profiles[3] '.codex'
        $gemini = Select-BacklogProfile $Profiles[4] '.gemini'
        $targets = @{}
        foreach ($relative in @('.config\mcp\mcp.json', '.agents\mcp.json', '.agents\mcp\mcp.json', '.claude.json', '.claude\mcp.json', '.claude\claude_desktop_config.json', '.cursor\mcp.json', '.windsurf\mcp.json', '.codex\config.json', '.gemini\settings.json', '.pi\agent\mcp.json')) {
            $targets[[IO.Path]::Combine($homePath, $relative)] = 'json'
        }
        foreach ($pair in @(@($pi,'mcp.json'), @($claude,'.claude.json'), @($claude,'mcp.json'), @($claude,'claude_desktop_config.json'), @($codex,'config.json'), @($gemini,'settings.json'))) {
            $targets[[IO.Path]::Combine($pair[0],$pair[1])] = 'json'
        }
        $targets[[IO.Path]::Combine($homePath,'.codex\config.json')] = 'codex-json'
        $targets[[IO.Path]::Combine($codex,'config.json')] = 'codex-json'
        $targets[[IO.Path]::Combine($homePath,'.cursor\mcp.json')] = 'editor-json'
        $targets[[IO.Path]::Combine($homePath,'.windsurf\mcp.json')] = 'editor-json'
        $appData = [Environment]::GetFolderPath([Environment+SpecialFolder]::ApplicationData)
        if ($appData -and [BacklogNativeFiles]::Below($appData,$homePath)) {
            $targets[[IO.Path]::Combine($appData,'Claude\claude_desktop_config.json')] = 'json'
        }
        $targets[[IO.Path]::Combine($homePath,'.codex\config.toml')] = 'toml'
        $targets[[IO.Path]::Combine($codex,'config.toml')] = 'toml'
        function Pin-BacklogDirectory([string]$directory, [bool]$missing) {
            if ($pins.ContainsKey($directory)) { return $true }
            $parent = [IO.Path]::GetDirectoryName($directory)
            if ($parent -and -not (Pin-BacklogDirectory $parent $missing)) { return $false }
            $pin = [BacklogNativeFiles]::Open($directory,$true,$false,$missing)
            if ($null -eq $pin) { return $false }
            $pins[$directory] = $pin
            $pin.CheckAcl($owner,$homePath,$false)
            return $true
        }
        if (-not (Pin-BacklogDirectory $homePath $false)) { throw 'home' }
        $total = 0
        foreach ($file in @($targets.Keys | Sort-Object)) {
            $file = [BacklogNativeFiles]::Canonical($file)
            if (-not [BacklogNativeFiles]::Below($file,$homePath)) { throw 'profile' }
            if (-not (Pin-BacklogDirectory ([IO.Path]::GetDirectoryName($file)) $true)) { continue }
            $pin = [BacklogNativeFiles]::Open($file,$false,$false,$true)
            if ($null -eq $pin) { continue }
            $pins[$file] = $pin
            $pin.CheckAcl($owner,$homePath,$false)
            $snapshot = $pin.Snapshot()
            $total += $snapshot.Length
            if ($total -gt 32MB) { throw 'size' }
            $records += [pscustomobject]@{ format=$targets[$file]; input=$snapshot; pin=$pin; file=$file }
        }
        if ($records.Count -eq 0) { return [pscustomobject]@{ Status='absent'; Code=0 } }
        $workingDirectory = [IO.Path]::Combine($systemRoot,'System32')
        if (-not (Pin-BacklogDirectory $workingDirectory $false)) { throw 'runtime' }
        $directory = $workingDirectory
        while ($directory) { $pins[$directory].CheckAcl($owner,$systemRoot,$true); $directory=[IO.Path]::GetDirectoryName($directory) }
        $runtimeHome = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
        $runtimeRoots = @(
            [IO.Path]::Combine([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData),'Microsoft\WinGet'),
            [IO.Path]::Combine([Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles),'WinGet'),
            [IO.Path]::Combine($runtimeHome,'.bun'))
        $bun = $null
        foreach ($candidate in @([IO.Path]::Combine($runtimeRoots[0],'Links\bun.exe'), [IO.Path]::Combine($runtimeRoots[1],'Links\bun.exe'), [IO.Path]::Combine($runtimeRoots[2],'bin\bun.exe'))) {
            if ([IO.File]::Exists($candidate)) { $bun = [BacklogNativeFiles]::ResolveRuntime($candidate); break }
        }
        if (-not $bun -or [IO.Path]::GetFileName($bun) -ine 'bun.exe') { throw 'parser' }
        $trustedRuntime = $false
        foreach ($root in $runtimeRoots) { if ([BacklogNativeFiles]::Below($bun,$root)) { $trustedRuntime=$true } }
        if (-not $trustedRuntime) { throw 'parser' }
        if (-not (Pin-BacklogDirectory ([IO.Path]::GetDirectoryName($bun)) $false)) { throw 'parser' }
        $binary = [BacklogNativeFiles]::Open($bun,$false,$true,$false); $pins[$bun] = $binary
        $binary.CheckAcl($owner,$runtimeHome,$true)
        $directory = [IO.Path]::GetDirectoryName($bun)
        while ($directory) { $pins[$directory].CheckAcl($owner,$runtimeHome,$true); $directory=[IO.Path]::GetDirectoryName($directory) }
        $marker = '// END BACKLOG_PURE_PLANNER'
        $end = $Program.IndexOf($marker,[StringComparison]::Ordinal)
        if ($end -lt 0) { throw 'planner' }
        $planner = $Program.Substring(0,$end) + "`ntry { process.stdout.write(JSON.stringify(planRetirement(records))); } catch { process.exitCode=1; }"
        $snapshots = @($records | ForEach-Object { [pscustomobject]@{format=$_.format; input=$_.input} })
        $request = ConvertTo-Json -InputObject @{program=$planner; records=$snapshots} -Depth 5 -Compress
        $response = [BacklogNativeFiles]::Plan($bun,$request,$systemRoot)
        $plan = @(ConvertFrom-Json -InputObject $response -ErrorAction Stop)
        if ($plan.Count -ne $records.Count) { throw 'planner' }
        $writes = @()
        for ($i=0; $i -lt $records.Count; $i++) {
            if ($null -ne $plan[$i]) {
                if ($plan[$i] -isnot [string]) { throw 'planner' }
                $data = [Convert]::FromBase64String($plan[$i])
                if ($data.Length -gt 2MB) { throw 'size' }
                $writes += [pscustomobject]@{ record=$records[$i]; output=$plan[$i] }
            }
        }
        foreach ($write in $writes) {
            $write.record.pin.CheckAcl($owner,$homePath,$true)
            $directory = [IO.Path]::GetDirectoryName($write.record.file)
            while ($directory) { $pins[$directory].CheckAcl($owner,$homePath,$true); $directory=[IO.Path]::GetDirectoryName($directory) }
        }
        foreach ($pin in $pins.Values) { $pin.Verify() }
        $phase = 'write'
        foreach ($write in $writes) {
            foreach ($pin in $pins.Values) { $pin.Verify() }
            $write.record.pin.Write($write.output)
        }
        foreach ($pin in $pins.Values) { $pin.Verify() }
        $status = if ($writes.Count) { 'removed' } else { 'absent' }
        return [pscustomobject]@{ Status=$status; Code=0 }
    } catch {
        $status = if ($phase -eq 'write') { 'write-failed' } else { 'native-preflight-failed' }
        return [pscustomobject]@{ Status=$status; Code=1 }
    } finally {
        foreach ($pin in $pins.Values) { if ($null -ne $pin) { $pin.Dispose() } }
    }
}

function Remove-GlobalBacklogMcp {
    if (-not (Enable-SharedNodeRuntime)) { Write-Error "Node.js is required to retire global Backlog MCP registrations."; return $false }
    $program = @'
// BEGIN BACKLOG_MCP_RETIREMENT
const fs = require('node:fs');
const path = require('node:path');
const {spawnSync} = require('node:child_process');
class RetirementError extends Error {}
let phase = 'preflight';
const fail = message => { throw new RetirementError(message); };
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const own = (value, key) => Object.prototype.hasOwnProperty.call(value, key);
const same = (a, b) => a && b && a.dev === b.dev && a.ino === b.ino && a.mode === b.mode && a.uid === b.uid && a.gid === b.gid &&
    (a.isDirectory() && b.isDirectory() ||
        a.nlink === b.nlink && a.size === b.size && a.mtimeMs === b.mtimeMs && a.ctimeMs === b.ctimeMs);
function info(file) { try { return fs.lstatSync(file); } catch (error) { if (error.code === 'ENOENT') return null; throw error; } }
function absolute(value) {
    if (!value || !path.isAbsolute(value) || value.split(/[\\/]/).some(part => part === '..' || part === '.')) fail('unsafe-path');
    return path.resolve(value);
}
function trustedHomeAlias(file, stat) {
    return process.platform === 'linux' && file === '/home' && stat.uid === 0 &&
        ['var/home', '/var/home'].includes(fs.readlinkSync(file)) && ['/', '/var', '/var/home'].every(dir => {
            const s = info(dir); return s?.isDirectory() && !s.isSymbolicLink() && s.uid === 0 && !(s.mode & 0o022);
        });
}
function safeBoundary(file, mutate = false) {
    const entries = [];
    for (let current = file; ; current = path.dirname(current)) {
        const stat = info(current);
        if (!stat) fail('unsafe-path');
        if (stat.isSymbolicLink()) {
            if (!trustedHomeAlias(current, stat)) fail('unsafe-path');
        } else if (!stat.isDirectory()) fail('unsafe-path');
        else if (process.platform !== 'win32') {
            const stickyRoot = stat.uid === 0 && (stat.mode & 0o1000);
            const directoryMask = stat.uid === 0 ? 0o022 : 0o002;
            if (![0, process.getuid()].includes(stat.uid) || mutate && (stat.mode & directoryMask) && !stickyRoot) fail('unsafe-boundary');
        }
        entries.push({file: current, stat});
        if (current === path.dirname(current)) break;
    }
    return entries;
}
function rawRead(fd, stat) {
    if (stat.size > 2 * 1024 * 1024) fail('unsafe-metadata');
    const buffer = Buffer.alloc(stat.size); let used = 0;
    while (used < buffer.length) {
        const count = fs.readSync(fd, buffer, used, buffer.length - used, used);
        if (!count) fail('metadata-changed');
        used += count;
    }
    return buffer;
}
function jsonDocument(text) {
    let data;
    try { data = JSON.parse(text.replace(/^\uFEFF/, '')); } catch { fail('malformed-metadata'); }
    if (!object(data)) fail('malformed-metadata');
    const tokens = text.match(/"(?:[^"\\]|\\.)*"|[{}\[\]:,]/g) || [], stack = [];
    for (let i = 0; i < tokens.length; i++) {
        const token = tokens[i];
        if (token === '{' || token === '[') stack.push(token === '{' ? new Set() : null);
        else if (token === '}' || token === ']') stack.pop();
        else if (token.startsWith('"') && tokens[i + 1] === ':') {
            const name = JSON.parse(token), keys = stack[stack.length - 1];
            if (!keys || keys.has(name)) fail('duplicate-key'); keys.add(name);
        }
    }
    return data;
}
function transformJson(text, serverKey = 'mcpServers') {
    const data = jsonDocument(text);
    if (!own(data, serverKey)) return null;
    if (!object(data[serverKey])) fail('malformed-metadata');
    const selected = new Set(Object.entries(data[serverKey]).filter(([name, value]) => backlog(name, value)).map(([name]) => name));
    if (!selected.size) return null;
    // Parse only source spans after validating JSON. Do not serialize unrelated
    // values: JS numbers cannot represent every number permitted by JSON.
    const tokens = [...text.matchAll(/"(?:[^"\\]|\\.)*"|-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?|true|false|null|[{}\[\]:,]/g)];
    let cursor = 0;
    const take = expected => { const token = tokens[cursor++]; if (!token || expected && token[0] !== expected) fail('malformed-metadata'); return token; };
    const parse = () => {
        const token = take(), node = {start: token.index, end: token.index + token[0].length, members: []};
        if (token[0] === '{' || token[0] === '[') {
            const end = token[0] === '{' ? '}' : ']';
            while (tokens[cursor]?.[0] !== end) {
                let key;
                if (token[0] === '{') { key = take(); take(':'); }
                const value = parse();
                if (key) node.members.push({name: JSON.parse(key[0]), start: key.index, end: value.end, value});
                if (tokens[cursor]?.[0] === end) break;
                take(',');
            }
            node.end = take(end).index + 1;
        }
        return node;
    };
    const root = parse();
    if (cursor !== tokens.length) fail('malformed-metadata');
    const servers = root.members.find(member => member.name === serverKey).value;
    const kept = servers.members.filter(member => !selected.has(member.name));
    const output = text.slice(0, servers.start + 1) + kept.map(member => text.slice(member.start, member.end)).join(',') + text.slice(servers.end - 1);
    jsonDocument(output);
    return output;
}
function backlog(name, definition) {
    if (name.toLowerCase() === 'backlog') return true;
    if (!object(definition) || typeof definition.command !== 'string') return false;
    const command = definition.command.replace(/\\/g, '/').split('/').pop().toLowerCase().replace(/\.(cmd|exe)$/i, '');
    return command === 'backlog' && Array.isArray(definition.args) && definition.args[0] === 'mcp' && definition.args[1] === 'start';
}
const tomlProgram = String.raw`
import json, os, sys, tomllib
text=sys.stdin.buffer.read().decode('utf-8')
try: data=tomllib.loads(text)
except Exception: print(json.dumps({'error':'malformed-toml'})); raise SystemExit
servers=data.get('mcp_servers')
if servers is None: print(json.dumps({'status':'absent'})); raise SystemExit
if not isinstance(servers,dict): print(json.dumps({'error':'unsupported-toml'})); raise SystemExit
def is_backlog(name, value):
    if name.lower()=='backlog': return True
    if not isinstance(value,dict) or not isinstance(value.get('command'),str): return False
    command=value['command'].replace('\\','/').rsplit('/',1)[-1].lower()
    if command.endswith(('.cmd','.exe')): command=command.rsplit('.',1)[0]
    args=value.get('args')
    return command=='backlog' and isinstance(args,list) and args[:2]==['mcp','start']
candidates={name for name,value in servers.items() if is_backlog(name,value)}
if not candidates: print(json.dumps({'status':'absent'})); raise SystemExit
# Mask multiline strings before recognizing table-header lines. The complete
# document has already passed tomllib, so this scanner only locates source spans.
masked=list(text); i=0; quote=None
while i < len(text):
    if quote:
        if text.startswith(quote,i):
            for j in range(i,i+3): masked[j]=' '
            i+=3; quote=None; continue
        masked[i]='\n' if text[i]=='\n' else ' '
        if quote=='\"\"\"' and text[i]=='\\' and i+1<len(text):
            i+=1; masked[i]='\n' if text[i]=='\n' else ' '
        i+=1; continue
    if text.startswith('\"\"\"',i) or text.startswith("'''",i):
        quote=text[i:i+3]
        for j in range(i,i+3): masked[j]=' '
        i+=3; continue
    if text[i] in ('\"',"'"):
        q=text[i]; masked[i]=' '; i+=1
        while i<len(text) and text[i]!='\n':
            c=text[i]; masked[i]=' '
            if q=='\"' and c=='\\' and i+1<len(text): i+=1; masked[i]=' '
            elif c==q: i+=1; break
            i+=1
        continue
    if text[i]=='#':
        while i<len(text) and text[i]!='\n': masked[i]=' '; i+=1
        continue
    i+=1
masked=''.join(masked)
headers=[]; offset=0
for line, raw in zip(masked.splitlines(True), text.splitlines(True)):
    stripped=line.strip()
    if stripped.startswith('['):
        header=raw.strip()
        # Use tomllib itself to interpret quoted/dotted and array table keys.
        try: probe=tomllib.loads(header+'\n__setup_marker__=true\n')
        except Exception: print(json.dumps({'error':'unsupported-toml'})); raise SystemExit
        paths=[]
        def find(value,prefix=()):
            if isinstance(value,dict):
                if value.get('__setup_marker__') is True: paths.append(prefix)
                for key,item in value.items():
                    if key!='__setup_marker__': find(item,prefix+(key,))
            elif isinstance(value,list):
                for item in value: find(item,prefix)
        find(probe)
        if len(paths)!=1: print(json.dumps({'error':'unsupported-toml'})); raise SystemExit
        headers.append((offset,paths[0]))
    offset+=len(raw)
spans=[]; represented=set()
for index,(start,parts) in enumerate(headers):
    end=headers[index+1][0] if index+1<len(headers) else len(text)
    if len(parts)>=2 and parts[0]=='mcp_servers' and parts[1] in candidates:
        represented.add(parts[1]); spans.append((start,end))
if represented != candidates:
    print(json.dumps({'error':'unsupported-toml'})); raise SystemExit
output=text
for start,end in reversed(spans): output=output[:start]+output[end:]
try: candidate=tomllib.loads(output)
except Exception: print(json.dumps({'error':'unsafe-toml-edit'})); raise SystemExit
expected=dict(data); expected_servers=dict(servers)
for name in candidates: expected_servers.pop(name,None)
if expected_servers: expected['mcp_servers']=expected_servers
else: expected.pop('mcp_servers',None)
if candidate != expected:
    print(json.dumps({'error':'unsafe-toml-edit'})); raise SystemExit
print(json.dumps({'status':'removed','output':output}))
`;
function transformTomlNative(text) {
    // Windows uses the built-in parser in Bun, already provisioned by WinGet.
    const parse = value => { try { return Bun.TOML.parse(value); } catch { fail('malformed-toml'); } };
    const data = parse(text), servers = data.mcp_servers;
    if (servers === undefined) return {status: 'absent'};
    if (!object(servers)) fail('unsupported-toml');
    const selected = new Set(Object.entries(servers).filter(([name, value]) => backlog(name, value)).map(([name]) => name));
    if (!selected.size) return {status: 'absent'};
    // Mask strings/comments without changing offsets. Interpret header keys
    // using the real TOML parser; validate the complete edited semantic tree.
    const masked = text.split('');
    let i = 0;
    while (i < text.length) {
        if (text[i] === '#') {
            while (i < text.length && text[i] !== '\n') masked[i++] = ' ';
        } else if (text[i] === '"' || text[i] === "'") {
            const quote = text[i], triple = text.slice(i, i + 3) === quote.repeat(3);
            const delimiter = triple ? quote.repeat(3) : quote;
            for (let j = 0; j < delimiter.length; j++) masked[i++] = ' ';
            while (i < text.length) {
                if (text.startsWith(delimiter, i)) {
                    for (let j = 0; j < delimiter.length; j++) masked[i++] = ' ';
                    break;
                }
                const escaped = text[i] === '\\' && quote === '"';
                if (text[i] !== '\n') masked[i] = ' ';
                i++;
                if (escaped && i < text.length) { if (text[i] !== '\n') masked[i] = ' '; i++; }
            }
        } else i++;
    }
    const headers = []; let offset = 0;
    for (const line of masked.join('').split(/(?<=\n)/)) {
        if (line.trimStart().startsWith('[')) {
            const raw = text.slice(offset, offset + line.length).trim();
            const probe = parse(raw + '\n__setup_marker__=true\n'), paths = [];
            const find = (value, parts) => {
                if (Array.isArray(value)) { for (const item of value) find(item, parts); }
                else if (object(value)) {
                    if (value.__setup_marker__ === true) paths.push(parts);
                    for (const [name, item] of Object.entries(value)) if (name !== '__setup_marker__') find(item, [...parts, name]);
                }
            };
            find(probe, []);
            if (paths.length !== 1) fail('unsupported-toml');
            headers.push({offset, parts: paths[0]});
        }
        offset += line.length;
    }
    const ranges = [], represented = new Set();
    for (let h = 0; h < headers.length; h++) {
        const {offset: start, parts} = headers[h];
        if (parts.length >= 2 && parts[0] === 'mcp_servers' && selected.has(parts[1])) {
            represented.add(parts[1]); ranges.push([start, headers[h + 1]?.offset ?? text.length]);
        }
    }
    if (represented.size !== selected.size) fail('unsupported-toml');
    let output = text;
    for (const [start, end] of ranges.reverse()) output = output.slice(0, start) + output.slice(end);
    const expected = {...data, mcp_servers: {...servers}};
    for (const name of selected) delete expected.mcp_servers[name];
    if (!Object.keys(expected.mcp_servers).length) delete expected.mcp_servers;
    if (!require('node:util').isDeepStrictEqual(parse(output), expected)) fail('unsafe-toml-edit');
    return {status: 'removed', output};
}
let tomlInterpreter;
function pythonForToml() {
    if (tomlInterpreter) return tomlInterpreter;
    if (process.platform === 'win32') fail('toml-parser-unavailable');
    const home = absolute(process.argv[2]);
    function* candidates() {
        yield* ['/usr/bin/python3', '/opt/homebrew/bin/python3', '/usr/local/bin/python3'];
        // Inspect inventories only if system/Homebrew Python is incompatible.
        // Never execute PATH shims or consult project version files.
        for (const root of [path.join(home, '.pyenv/versions'), path.join(home, '.local/share/mise/installs/python')]) {
            if (!info(root)) continue;
            safeBoundary(root, true);
            const versions = fs.readdirSync(root);
            if (versions.length > 256) fail('toml-parser-unavailable');
            for (const version of versions.filter(name => /^3\.\d+\.\d+t?$/.test(name)).sort().reverse()) yield path.join(root, version, 'bin/python3');
        }
    }
    for (const candidate of candidates()) {
        if (!info(candidate)) continue;
        safeBoundary(path.dirname(candidate), true);
        const resolved = fs.realpathSync(candidate), target = info(resolved);
        if (!target?.isFile() || ![0, process.getuid()].includes(target.uid) || target.mode & 0o022) fail('toml-parser-unavailable');
        safeBoundary(path.dirname(resolved), true);
        // Non-root executables must stay within an expected managed prefix.
        const allowed = ['/opt/homebrew/', '/usr/local/', path.join(home, '.pyenv/versions') + '/', path.join(home, '.local/share/mise/installs/python') + '/'];
        if (target.uid !== 0 && !allowed.some(prefix => resolved.startsWith(prefix))) fail('toml-parser-unavailable');
        const probe = spawnSync(resolved, ['-I', '-S', '-B', '-c', 'import tomllib; print("ready")'], {
            encoding: 'utf8', maxBuffer: 4096, timeout: 5000, cwd: '/', env: {PATH: '/usr/bin:/bin', LANG: 'C', LC_ALL: 'C'}
        });
        if (!probe.error && probe.status === 0 && probe.stdout.trim() === 'ready' && !probe.stderr) { tomlInterpreter = resolved; return resolved; }
    }
    fail('toml-parser-unavailable');
}
function transformToml(text) {
    if (typeof Bun !== 'undefined') return transformTomlNative(text);
    const command = pythonForToml();
    const result = spawnSync(command, ['-I', '-S', '-B', '-c', tomlProgram], {
        input: text, encoding: 'utf8', maxBuffer: 3 * 1024 * 1024, timeout: 10000, windowsHide: true,
        cwd: '/', env: {PATH: '/usr/bin:/bin', LANG: 'C', LC_ALL: 'C', PYTHONHASHSEED: '0'}
    });
    if (result.error || result.status !== 0 || result.stderr || !result.stdout) fail('toml-parser-failed');
    let report; try { report = JSON.parse(result.stdout); } catch { fail('toml-parser-failed'); }
    if (report.error) fail(report.error);
    if (!['absent','removed'].includes(report.status) || report.status === 'removed' && typeof report.output !== 'string') fail('toml-parser-failed');
    return report;
}
function planRetirement(records) {
    if (!Array.isArray(records) || records.length > 64) fail('malformed-metadata');
    return records.map(record => {
        if (!object(record) || !['json', 'codex-json', 'editor-json', 'toml'].includes(record.format) || typeof record.input !== 'string' || record.input.length > 3 * 1024 * 1024) fail('malformed-metadata');
        const bytes = Buffer.from(record.input, 'base64');
        if (bytes.length > 2 * 1024 * 1024 || bytes.toString('base64') !== record.input) fail('malformed-metadata');
        const text = new TextDecoder('utf-8', {fatal: true, ignoreBOM: true}).decode(bytes);
        let output = null;
        if (record.format === 'toml') {
            const report = transformToml(text);
            if (report.status === 'removed') output = report.output;
        } else {
            output = transformJson(text);
            const extraKey = record.format === 'codex-json' ? 'mcp_servers' : record.format === 'editor-json' ? 'mcp-servers' : null;
            if (extraKey) output = transformJson(output ?? text, extraKey) ?? output;
        }
        return output === null ? null : Buffer.from(output).toString('base64');
    });
}
// END BACKLOG_PURE_PLANNER
try {
    const logicalHome = absolute(process.argv[2]);
    const logicalBoundary = safeBoundary(logicalHome);
    const homeStat = info(logicalHome);
    if (!homeStat?.isDirectory() || homeStat.isSymbolicLink()) fail('unsafe-home');
    const home = fs.realpathSync(logicalHome);
    const trustedAlias = process.platform === 'linux' && logicalHome.startsWith('/home/') && home.startsWith('/var/home/') &&
        logicalBoundary.some(entry => entry.file === '/home' && entry.stat.isSymbolicLink() && trustedHomeAlias('/home', entry.stat));
    if (home !== logicalHome && !trustedAlias) fail('unsafe-home');
    const resolvedBoundary = safeBoundary(home);
    const key = value => process.platform === 'win32' ? value.toLowerCase() : value;
    const within = (file, base) => key(file) === key(base) || key(file).startsWith(key(base + path.sep));
    const profile = (value, fallback) => {
        const logical = absolute(value || path.join(logicalHome, fallback));
        if (!within(logical, logicalHome)) fail('unsafe-profile');
        return path.join(home, path.relative(logicalHome, logical));
    };
    const pi = profile(process.argv[3], '.pi/agent');
    const claude = profile(process.argv[4], '.claude');
    const codex = profile(process.argv[5], '.codex');
    const gemini = profile(process.argv[6], '.gemini');
    const files = [...new Set([
        path.join(home, '.config/mcp/mcp.json'), path.join(home, '.agents/mcp.json'), path.join(home, '.agents/mcp/mcp.json'),
        path.join(home, '.claude.json'), path.join(claude, '.claude.json'),
        path.join(home, '.claude/mcp.json'), path.join(home, '.claude/claude_desktop_config.json'),
        path.join(claude, 'mcp.json'), path.join(claude, 'claude_desktop_config.json'),
        path.join(home, 'Library/Application Support/Claude/claude_desktop_config.json'),
        path.join(home, '.cursor/mcp.json'), path.join(home, '.windsurf/mcp.json'),
        path.join(home, '.codex/config.json'), path.join(codex, 'config.json'),
        path.join(home, '.gemini/settings.json'), path.join(gemini, 'settings.json'),
        path.join(home, '.pi/agent/mcp.json'), path.join(pi, 'mcp.json')
    ])];
    const tomlFiles = [...new Set([path.join(home, '.codex/config.toml'), path.join(codex, 'config.toml')])];
    const records = [], boundaryMap = new Map([...logicalBoundary, ...resolvedBoundary].map(entry => [entry.file, entry.stat]));
    function read(file) {
        if (!within(file, home)) fail('unsafe-path');
        const stat = info(file); if (!stat) return null;
        if (!stat.isFile() || stat.isSymbolicLink() || stat.nlink > 1 || stat.size > 2 * 1024 * 1024) fail('unsafe-metadata');
        const boundaries = safeBoundary(path.dirname(file));
        for (const entry of boundaries) boundaryMap.set(entry.file, entry.stat);
        if (process.platform === 'win32') fail('native-wrapper-required');
        const fd = fs.openSync(file, fs.constants.O_RDWR | fs.constants.O_NOFOLLOW | fs.constants.O_NONBLOCK);
        const opened = fs.fstatSync(fd);
        if (!same(stat, opened) || !opened.isFile()) { fs.closeSync(fd); fail('metadata-changed'); }
        const buffer = rawRead(fd, opened);
        if (!same(opened, fs.fstatSync(fd)) || !same(opened, info(file))) { fs.closeSync(fd); fail('metadata-changed'); }
        const record = {file, stat: opened, fd, raw: buffer, text: new TextDecoder('utf-8', {fatal: true, ignoreBOM: true}).decode(buffer), output: null, boundaries}; records.push(record); return record;
    }
    for (const file of files) {
        const record = read(file); if (!record) continue;
        record.output = transformJson(record.text);
        const extraKey = [path.join(home, '.codex/config.json'), path.join(codex, 'config.json')].includes(file) ? 'mcp_servers' :
            [path.join(home, '.cursor/mcp.json'), path.join(home, '.windsurf/mcp.json')].includes(file) ? 'mcp-servers' : null;
        if (extraKey) record.output = transformJson(record.output ?? record.text, extraKey) ?? record.output;
    }
    for (const file of tomlFiles) {
        const record = records.find(item => item.file === file) || read(file); if (!record) continue;
        const report = transformToml(record.text); if (report.status === 'removed') record.output = report.output;
    }
    const writes = records.filter(record => record.output !== null);
    function verifyAll() {
        for (const [file, stat] of boundaryMap) if (!same(stat, info(file))) fail('boundary-changed');
        for (const record of records) {
            const current = fs.fstatSync(record.fd);
            if (!same(record.stat, current) || !same(record.stat, info(record.file)) || !rawRead(record.fd, current).equals(record.raw) || !same(record.stat, fs.fstatSync(record.fd))) fail('metadata-changed');
        }
        for (const record of writes) {
            if (record.stat.uid !== process.getuid() || record.stat.mode & 0o022) fail('unsafe-metadata');
            safeBoundary(path.dirname(record.file), true);
        }
    }
    verifyAll();
    phase = 'write';
    for (const record of writes) {
        verifyAll();
        const data = Buffer.from(record.output); let offset = 0;
        while (offset < data.length) {
            const count = fs.writeSync(record.fd, data, offset, data.length - offset, offset);
            if (!count) fail('short-write');
            offset += count;
        }
        fs.ftruncateSync(record.fd, data.length); fs.fsyncSync(record.fd);
        record.stat = fs.fstatSync(record.fd); record.raw = data;
        if (!same(record.stat, info(record.file))) fail('metadata-changed');
    }
    for (const record of records) fs.closeSync(record.fd);
    console.log(writes.length ? 'removed' : 'absent');
} catch (error) {
    const reason = error instanceof RetirementError ? error.message : 'filesystem-error';
    console.log(phase === 'write' ? 'write-failed' : reason);
    process.exitCode = 1;
}
// END BACKLOG_MCP_RETIREMENT
'@
    $arguments = @('--input-type=commonjs', '-', $HOME, [string]$env:PI_CODING_AGENT_DIR, [string]$env:CLAUDE_CONFIG_DIR, [string]$env:CODEX_HOME, [string]$env:GEMINI_CLI_HOME)
    $oldNodeOptions = $env:NODE_OPTIONS; $oldNodePath = $env:NODE_PATH
    try {
        Remove-Item Env:NODE_OPTIONS -ErrorAction SilentlyContinue; Remove-Item Env:NODE_PATH -ErrorAction SilentlyContinue
        if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
            $native = Invoke-BacklogMcpWindowsRetirement -Program $program -Profiles @(
                $HOME, [string]$env:PI_CODING_AGENT_DIR, [string]$env:CLAUDE_CONFIG_DIR,
                [string]$env:CODEX_HOME, [string]$env:GEMINI_CLI_HOME)
            $result = $native.Status
            $retirementExitCode = $native.Code
        } else {
            $result = $program | & node @arguments 2>$null
            $retirementExitCode = $LASTEXITCODE
        }
    } finally {
        if ($null -eq $oldNodeOptions) { Remove-Item Env:NODE_OPTIONS -ErrorAction SilentlyContinue } else { $env:NODE_OPTIONS = $oldNodeOptions }
        if ($null -eq $oldNodePath) { Remove-Item Env:NODE_PATH -ErrorAction SilentlyContinue } else { $env:NODE_PATH = $oldNodePath }
    }
    $retirementResult = ($result | Out-String).Trim()
    if ($retirementExitCode -ne 0) {
        if ($retirementResult -eq 'write-failed') { Write-Error "Global Backlog MCP retirement failed during a write; review the affected global metadata before retrying." }
        elseif ($retirementResult -in @('unsafe-path','unsafe-home','unsafe-profile','unsafe-boundary','unsafe-metadata','malformed-metadata','duplicate-key','unsupported-json-number','malformed-toml','unsupported-toml','toml-parser-failed','toml-parser-unavailable','unsafe-toml-edit','metadata-changed','boundary-changed','native-wrapper-required','native-preflight-failed','filesystem-error')) { Write-Error "Global Backlog MCP retirement preflight failed; no changes were made." }
        else { Write-Error "Global Backlog MCP retirement failed for an unknown controlled reason; review global metadata before retrying." }
        return $false
    }
    switch ($retirementResult) {
        'removed' { Write-Success "Retired global Backlog MCP registrations; repository-local configuration and task data were preserved."; return $true }
        'absent' { Write-Debug "Global Backlog MCP registrations are absent."; return $true }
        default { Write-Error "Global Backlog MCP retirement returned an invalid result."; return $false }
    }
}
$null = 'END_GLOBAL_BACKLOG_MCP_RETIREMENT'

$null = 'BEGIN_PI_PROSE_RETIREMENT'
function Prepare-PiProfilePermissions {
    if (-not (Enable-SharedNodeRuntime)) {
        Write-Warning 'Pi profile permissions failed: shared-runtime-unavailable.'
        return $false
    }
    $code = @'
// BEGIN PI_PROFILE_PERMISSIONS
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const {spawnSync} = require('node:child_process');
class PermissionError extends Error {}
const fail = code => { throw new PermissionError(code); };
function absolute(value) {
    if (!value || !path.isAbsolute(value) || value.split(/[\\/]/).some(p => p === '.' || p === '..')) fail('unsafe-path');
    return path.resolve(value);
}
function info(file) {
    try { return fs.lstatSync(file); }
    catch (error) { if (error.code === 'ENOENT') return null; throw error; }
}
function chain(file) {
    const result = [];
    for (let current = file; ; current = path.dirname(current)) {
        result.unshift(current);
        if (current === path.dirname(current)) return result;
    }
}
function systemHomeAlias(file, stat) {
    if (process.platform !== 'linux' || file !== '/home' || stat.uid !== 0) return false;
    if (!['var/home', '/var/home'].includes(fs.readlinkSync(file))) return false;
    return ['/', '/var', '/var/home'].every(dir => {
        const entry = info(dir);
        return entry && entry.isDirectory() && !entry.isSymbolicLink() && entry.uid === 0 && !(entry.mode & 0o022);
    });
}
// Node has no mkdirat binding. Use only the OS Python's isolated stdlib and an
// inherited, verified parent descriptor; never fall back to path-based creation.
const mkdirAtProgram = String.raw`
import os, stat, sys
try:
    if (os.mkdir not in os.supports_dir_fd or os.open not in os.supports_dir_fd or
            not all(hasattr(os, name) for name in ('O_DIRECTORY', 'O_NOFOLLOW'))):
        sys.exit(1)
    if sys.argv[1] == 'probe':
        print('ready')
        sys.exit(0)
    if sys.argv[1] != 'create':
        sys.exit(1)
    parent = os.fstat(3)
    if not stat.S_ISDIR(parent.st_mode) or parent.st_dev != int(sys.argv[3]) or parent.st_ino != int(sys.argv[4]):
        sys.exit(1)
    leaf = sys.argv[2]
    if not leaf or leaf in ('.', '..') or '/' in leaf:
        sys.exit(1)
    os.mkdir(leaf, mode=0o700, dir_fd=3)
    fd = os.open(leaf, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=3)
    try:
        created = os.fstat(fd)
        if not stat.S_ISDIR(created.st_mode) or created.st_uid != os.getuid():
            sys.exit(1)
        print('created:%d:%d' % (created.st_dev, created.st_ino))
    finally:
        os.close(fd)
except Exception:
    sys.exit(1)
`;
function mkdirAt(args, fd) {
    return spawnSync('/usr/bin/python3', ['-I', '-S', '-c', mkdirAtProgram, ...args], {
        env: {}, encoding: 'utf8', timeout: 15000, maxBuffer: 128,
        stdio: fd === undefined ? ['ignore', 'pipe', 'pipe'] : ['ignore', 'pipe', 'pipe', fd],
    });
}
function unixPrepare(logicalHome, selected) {
    const uid = process.getuid();
    function inspect(file, managed = false) {
        const stat = info(file);
        if (!stat && managed) return null;
        if (!stat) fail('missing-ancestor');
        if (stat.isSymbolicLink() && systemHomeAlias(file, stat)) return stat;
        if (!stat.isDirectory() || stat.isSymbolicLink()) fail('linked-or-nondirectory');
        if (managed ? stat.uid !== uid : ![0, uid].includes(stat.uid)) fail('foreign-owner');
        const stickyRoot = stat.uid === 0 && (stat.mode & 0o1000);
        // Ordinary account directories may retain group access; private profile
        // leaves are prepared separately below. System boundaries stay strict.
        const mask = stat.uid === uid && uid !== 0 ? 0o002 : 0o022;
        if (!managed && (stat.mode & mask) && !stickyRoot) fail('unsafe-ancestor');
        return stat;
    }
    chain(logicalHome).forEach(file => inspect(file));
    if (info(logicalHome).uid !== uid) fail('foreign-owner');
    // Resolve only the verified account boundary (Linux /home -> /var/home).
    const home = fs.realpathSync(logicalHome);
    if (selected.startsWith(logicalHome + path.sep)) selected = path.join(home, path.relative(logicalHome, selected));
    if (!selected.startsWith(home + path.sep)) fail('outside-home');
    const managed = new Set([path.join(home, '.pi'), path.join(home, '.pi/agent'), selected]);
    const plan = new Map();
    for (const target of managed) {
        for (const file of chain(target)) {
            if (!plan.has(file)) plan.set(file, inspect(file, managed.has(file)));
        }
    }
    const sameDirectory = (a, b) => a && b && a.dev === b.dev && a.ino === b.ino &&
        a.mode === b.mode && a.uid === b.uid && a.gid === b.gid;
    function unchanged() {
        for (const [file, before] of plan) {
            const after = inspect(file, managed.has(file));
            if (Boolean(before) !== Boolean(after) || before && !sameDirectory(before, after)) fail('directory-changed');
        }
    }
    if ([...managed].some(file => !plan.get(file))) {
        const probe = mkdirAt(['probe']);
        if (probe.status !== 0 || probe.stdout !== 'ready\n') fail('directory-create-unavailable');
    }
    // All default and active boundaries pass preflight before the first mutation.
    for (const file of [...managed].sort((a, b) => chain(a).length - chain(b).length)) {
        unchanged();
        if (!plan.get(file)) {
            const parent = path.dirname(file);
            const expected = plan.get(parent);
            const fd = fs.openSync(parent, fs.constants.O_RDONLY | fs.constants.O_DIRECTORY | fs.constants.O_NOFOLLOW);
            try {
                const pinned = fs.fstatSync(fd);
                if (!sameDirectory(expected, pinned)) fail('directory-changed');
                unchanged();
                const result = mkdirAt(['create', path.basename(file), String(pinned.dev), String(pinned.ino)], fd);
                const identity = /^created:([0-9]+):([0-9]+)\n$/.exec(result.stdout || '');
                if (result.status !== 0 || !identity) fail('directory-create-unavailable');
                const created = inspect(file, true);
                if (!created || created.dev !== Number(identity[1]) || created.ino !== Number(identity[2])) fail('directory-changed');
                plan.set(file, created);
            } finally { fs.closeSync(fd); }
        }
        const before = plan.get(file);
        if ((before.mode & 0o7777) === 0o700) continue;
        const fd = fs.openSync(file, fs.constants.O_RDONLY | fs.constants.O_DIRECTORY | fs.constants.O_NOFOLLOW);
        try {
            const opened = fs.fstatSync(fd);
            if (!opened.isDirectory() || opened.uid !== uid || !sameDirectory(before, opened)) fail('directory-changed');
            fs.fchmodSync(fd, 0o700); // Only the verified directory inode, never its contents.
            const after = fs.fstatSync(fd);
            if ((after.mode & 0o7777) !== 0o700) fail('permission-unverified');
            plan.set(file, after);
        } finally { fs.closeSync(fd); }
    }
    unchanged();
}
function windowsPrepare(home, selected) {
    // Use only the inbox PowerShell host and native APIs, never custom modules.
    const script = String.raw`
$ErrorActionPreference = 'Stop'
$PSModuleAutoLoadingPreference = 'None'
$pins = @{}
try {
    Import-Module (Join-Path $PSHOME 'Modules/Microsoft.PowerShell.Management/Microsoft.PowerShell.Management.psd1') -ErrorAction Stop
    Import-Module (Join-Path $PSHOME 'Modules/Microsoft.PowerShell.Utility/Microsoft.PowerShell.Utility.psd1') -ErrorAction Stop
    Import-Module (Join-Path $PSHOME 'Modules/Microsoft.PowerShell.Security/Microsoft.PowerShell.Security.psd1') -ErrorAction Stop
    # Root-relative native creation returns the created directory handle atomically.
    # Pinned ancestors deny write/delete sharing, preventing reparse/rename races.
    # SetKernelObjectSecurity changes only the pinned directory, never child ACLs.
    Add-Type -TypeDefinition @"
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using Microsoft.Win32.SafeHandles;
public static class PiDirectoryAcl {
    const uint FILE_SHARE_READ = 1, FILE_CREATE = 2;
    [StructLayout(LayoutKind.Sequential)]
    internal struct Info {
        public uint Attributes, CreatedLow, CreatedHigh, AccessLow, AccessHigh,
            WriteLow, WriteHigh, Volume, SizeHigh, SizeLow, Links, IndexHigh, IndexLow;
    }
    [StructLayout(LayoutKind.Sequential)]
    struct UnicodeString { public ushort Length, MaximumLength; public IntPtr Buffer; }
    [StructLayout(LayoutKind.Sequential)]
    struct ObjectAttributes {
        public uint Length;
        public IntPtr RootDirectory, ObjectName;
        public uint Attributes;
        public IntPtr SecurityDescriptor, SecurityQualityOfService;
    }
    [StructLayout(LayoutKind.Sequential)]
    struct IoStatusBlock { public IntPtr Status; public UIntPtr Information; }
    public sealed class Pinned : IDisposable {
        internal SafeFileHandle Handle;
        internal Info Before;
        internal Pinned(SafeFileHandle handle) {
            Handle = handle;
            try { Before = Read(handle); } catch { handle.Dispose(); throw; }
        }
        public void Dispose() { Handle.Dispose(); }
    }
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern SafeFileHandle CreateFile(string name, uint access, uint share,
        IntPtr security, uint creation, uint flags, IntPtr template);
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern bool GetFileInformationByHandle(SafeFileHandle file, out Info info);
    [DllImport("advapi32.dll", SetLastError=true)]
    static extern bool GetKernelObjectSecurity(SafeFileHandle file, uint information,
        byte[] descriptor, uint length, out uint needed);
    [DllImport("advapi32.dll", SetLastError=true)]
    static extern bool SetKernelObjectSecurity(SafeFileHandle file, uint information, byte[] descriptor);
    [DllImport("ntdll.dll")]
    static extern int NtCreateFile(out SafeFileHandle file, uint access,
        ref ObjectAttributes attributes, out IoStatusBlock ioStatus, IntPtr allocationSize,
        uint fileAttributes, uint share, uint disposition, uint options, IntPtr eaBuffer, uint eaLength);
    static Info Read(SafeFileHandle handle) {
        Info info;
        if (handle.IsInvalid || !GetFileInformationByHandle(handle, out info)) throw new Win32Exception();
        if ((info.Attributes & 0x410) != 0x10) throw new InvalidOperationException(); // directory, not reparse
        return info;
    }
    static bool SameIdentity(Info before, Info after) {
        return before.Volume == after.Volume && before.IndexHigh == after.IndexHigh && before.IndexLow == after.IndexLow;
    }
    static uint Access(bool managed, bool parent) {
        // READ_CONTROL + LIST_DIRECTORY + TRAVERSE; only approved parents need ADD_SUBDIRECTORY.
        return 0x20021u | (managed ? 0x40000u : 0u) | (parent ? 4u : 0u);
    }
    public static Pinned Pin(string name, bool managed, bool parent, bool missing) {
        // Reject Win32 aliases that could differ from the literal rooted native name.
        if (name.StartsWith("\\\\") || name.Length < 3 || name[1] != ':') throw new InvalidOperationException();
        foreach (string part in name.Substring(3).Split('\\')) {
            if (part.EndsWith(".") || part.EndsWith(" ") || part.Contains(":")) throw new InvalidOperationException();
        }
        var handle = CreateFile(name, Access(managed, parent), FILE_SHARE_READ,
            IntPtr.Zero, 3, 0x02200000, IntPtr.Zero); // OPEN_EXISTING, BACKUP_SEMANTICS, OPEN_REPARSE_POINT
        if (handle.IsInvalid) {
            int error = Marshal.GetLastWin32Error();
            handle.Dispose();
            if (missing && (error == 2 || error == 3)) return null;
            throw new Win32Exception(error);
        }
        return new Pinned(handle);
    }
    public static string Identity(Pinned pin) {
        Info after = Read(pin.Handle);
        if (!SameIdentity(pin.Before, after)) throw new InvalidOperationException();
        return after.Volume + ":" + after.IndexHigh + ":" + after.IndexLow;
    }
    public static DirectorySecurity Security(Pinned pin) {
        Identity(pin);
        uint needed;
        GetKernelObjectSecurity(pin.Handle, 7, null, 0, out needed); // owner, group, DACL
        if (needed == 0 || needed > 65536) throw new InvalidOperationException();
        var bytes = new byte[needed];
        if (!GetKernelObjectSecurity(pin.Handle, 7, bytes, needed, out needed)) throw new Win32Exception();
        var security = new DirectorySecurity();
        security.SetSecurityDescriptorBinaryForm(bytes);
        return security;
    }
    public static void Secure(Pinned pin, string expectedIdentity, string owner, byte[] descriptor) {
        if (Identity(pin) != expectedIdentity ||
            Security(pin).GetOwner(typeof(System.Security.Principal.SecurityIdentifier)).Value != owner)
            throw new InvalidOperationException();
        // Protected DACL only. This handle API does not propagate ACEs to children.
        if (!SetKernelObjectSecurity(pin.Handle, 0x80000004, descriptor)) throw new Win32Exception();
    }
    public static Pinned CreateLeaf(Pinned parent, string leaf, byte[] descriptor, bool createParent) {
        Identity(parent);
        if (String.IsNullOrEmpty(leaf) || leaf == "." || leaf == ".." || leaf.Length > 32767 ||
            leaf.IndexOfAny(new char[] {'\\', '/', ':'}) >= 0 || leaf.EndsWith(".") || leaf.EndsWith(" "))
            throw new InvalidOperationException();
        IntPtr text = Marshal.StringToHGlobalUni(leaf);
        IntPtr name = Marshal.AllocHGlobal(Marshal.SizeOf(typeof(UnicodeString)));
        GCHandle security = GCHandle.Alloc(descriptor, GCHandleType.Pinned);
        try {
            var unicode = new UnicodeString { Length = (ushort)(leaf.Length * 2),
                MaximumLength = (ushort)(leaf.Length * 2), Buffer = text };
            Marshal.StructureToPtr(unicode, name, false);
            var attributes = new ObjectAttributes { Length = (uint)Marshal.SizeOf(typeof(ObjectAttributes)),
                RootDirectory = parent.Handle.DangerousGetHandle(), ObjectName = name,
                Attributes = 0x40, SecurityDescriptor = security.AddrOfPinnedObject() };
            SafeFileHandle handle;
            IoStatusBlock io;
            int status = NtCreateFile(out handle, Access(true, createParent), ref attributes, out io,
                IntPtr.Zero, 0x10, FILE_SHARE_READ, FILE_CREATE, 0x00200001, IntPtr.Zero, 0);
            // DIRECTORY_FILE | OPEN_REPARSE_POINT, FILE_CREATE never opens/replaces an existing leaf.
            if (status != 0) {
                if (handle != null) handle.Dispose();
                throw new InvalidOperationException();
            }
            return new Pinned(handle);
        } finally {
            security.Free();
            Marshal.FreeHGlobal(name);
            Marshal.FreeHGlobal(text);
        }
    }
}
"@
    $homePath = $env:PI_PERMISSIONS_HOME
    $selected = $env:PI_PERMISSIONS_ACTIVE
    $owner = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
    $allowed = @($owner.Value, 'S-1-5-18', 'S-1-5-32-544')
    if (-not $selected.StartsWith($homePath.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'boundary' }
    $managed = @((Join-Path $homePath '.pi'), (Join-Path $homePath '.pi/agent'), $selected)
    $creationParents = @($managed | ForEach-Object { Split-Path -Parent $_ })
    $all = @{}
    foreach ($target in $managed) {
        $current = $target
        while ($current) { $all[$current] = $true; $current = Split-Path -Parent $current }
    }
    $ordered = @($all.Keys | Sort-Object Length)
    $plan = @{}
    function Inspect-Directory($file, $repair) {
        if ($null -eq $pins[$file]) {
            $pins[$file] = [PiDirectoryAcl]::Pin($file, $repair, ($file -in $creationParents), $repair)
        }
        if ($null -eq $pins[$file]) { return $null }
        $identity = [PiDirectoryAcl]::Identity($pins[$file])
        $acl = [PiDirectoryAcl]::Security($pins[$file])
        $sid = $acl.GetOwner([System.Security.Principal.SecurityIdentifier]).Value
        if ($repair -or $file -eq $homePath) {
            if ($sid -ne $owner.Value) { throw 'owner' }
        } elseif ($sid -notin ($allowed + @('S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464'))) { throw 'owner' }
        if (-not $repair) {
            $write = [System.Security.AccessControl.FileSystemRights]::Delete -bor [System.Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles -bor [System.Security.AccessControl.FileSystemRights]::ChangePermissions -bor [System.Security.AccessControl.FileSystemRights]::TakeOwnership
            if ($file -eq $homePath -or $file.StartsWith($homePath.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
                $write = $write -bor [System.Security.AccessControl.FileSystemRights]::Write
            }
            foreach ($rule in $acl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier])) {
                if ($rule.PropagationFlags -band [System.Security.AccessControl.PropagationFlags]::InheritOnly) { continue }
                if ($rule.AccessControlType -eq 'Allow' -and $rule.IdentityReference.Value -notin $allowed -and ($rule.FileSystemRights -band $write)) { throw 'access' }
            }
        }
        return @($identity, $acl.Sddl)
    }
    # Root first: every path ancestor remains pinned until the entire transaction ends.
    foreach ($file in $ordered) { $plan[$file] = Inspect-Directory $file ($file -in $managed) }
    function Assert-Unchanged {
        foreach ($file in $ordered) {
            $after = Inspect-Directory $file ($file -in $managed)
            if (($after -join '|') -cne ($plan[$file] -join '|')) { throw 'changed' }
        }
    }
    $private = [System.Security.AccessControl.DirectorySecurity]::new()
    $private.SetOwner($owner)
    $private.SetAccessRuleProtection($true, $false)
    foreach ($sid in $allowed) {
        $private.AddAccessRule([System.Security.AccessControl.FileSystemAccessRule]::new([System.Security.Principal.SecurityIdentifier]::new($sid), 'FullControl', 'Allow'))
    }
    foreach ($file in @($managed | Sort-Object -Unique | Sort-Object Length)) {
        Assert-Unchanged
        if ($null -eq $plan[$file]) {
            $parent = Split-Path -Parent $file
            $pins[$file] = [PiDirectoryAcl]::CreateLeaf($pins[$parent], [IO.Path]::GetFileName($file),
                $private.GetSecurityDescriptorBinaryForm(), ($file -in $creationParents))
        } else {
            [PiDirectoryAcl]::Secure($pins[$file], $plan[$file][0], $owner.Value, $private.GetSecurityDescriptorBinaryForm())
        }
        $plan[$file] = Inspect-Directory $file $true
        $acl = [PiDirectoryAcl]::Security($pins[$file])
        if (-not $acl.AreAccessRulesProtected) { throw 'unverified' }
        foreach ($rule in $acl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier])) {
            if ($rule.IdentityReference.Value -notin $allowed) { throw 'unverified' }
        }
    }
    Assert-Unchanged
    [Console]::Out.Write('prepared')
} catch { exit 1 }
finally { foreach ($pin in $pins.Values) { if ($null -ne $pin) { $pin.Dispose() } } }
`;
    const systemRoot = absolute(process.env.SystemRoot || 'C:\\Windows');
    const result = spawnSync(path.join(systemRoot, 'System32/WindowsPowerShell/v1.0/powershell.exe'),
        ['-NoProfile', '-NonInteractive', '-EncodedCommand', Buffer.from('& ([scriptblock]::Create([Console]::In.ReadToEnd()))', 'utf16le').toString('base64')], {
            input: script, // Avoid the Windows command-line length limit; no temporary script file.
            env: {SystemRoot: systemRoot, WINDIR: systemRoot, PI_PERMISSIONS_HOME: home, PI_PERMISSIONS_ACTIVE: selected},
            windowsHide: true, shell: false, encoding: 'utf8', timeout: 30000, maxBuffer: 1024,
        });
    if (result.status !== 0 || result.stdout !== 'prepared') fail('acl-unverified');
}
try {
    const home = absolute(process.argv[2]);
    const selected = absolute(process.argv[3] || path.join(home, '.pi/agent'));
    if (process.platform === 'win32') windowsPrepare(home, selected);
    else unixPrepare(home, selected);
    console.log('prepared');
} catch (error) {
    const native = new Set(['EACCES', 'EPERM', 'EROFS', 'ENOSPC', 'EDQUOT', 'ENOENT', 'ENOTDIR', 'ELOOP', 'EEXIST', 'EIO']);
    const reason = error instanceof PermissionError ? error.message : native.has(error?.code) ? error.code : 'operation-failed';
    console.log('failed:' + reason);
    process.exitCode = 1;
}
// END PI_PROFILE_PERMISSIONS
'@
    $oldOptions = $env:NODE_OPTIONS
    $oldPath = $env:NODE_PATH
    $PSNativeCommandUseErrorActionPreference = $false
    try {
        Remove-Item Env:NODE_OPTIONS, Env:NODE_PATH -ErrorAction SilentlyContinue
        $result = ($code | & node --input-type=commonjs - $env:USERPROFILE "$env:PI_CODING_AGENT_DIR" 2>$null) -join "`n"
        if ($LASTEXITCODE -eq 0 -and $result -eq 'prepared') {
            Write-Debug 'Pi profile directories are private.'
            return $true
        }
        if ($result -cmatch '^failed:(unsafe-path|missing-ancestor|linked-or-nondirectory|foreign-owner|unsafe-ancestor|outside-home|directory-changed|directory-create-unavailable|permission-unverified|acl-unverified|operation-failed|EACCES|EPERM|EROFS|ENOSPC|EDQUOT|ENOENT|ENOTDIR|ELOOP|EEXIST|EIO)$') {
            Write-Warning "Pi profile permissions $result."
        } else { Write-Warning 'Pi profile permissions failed: unverified-result.' }
        return $false
    } catch {
        Write-Warning 'Pi profile permissions failed: operation-failed.'
        return $false
    } finally {
        $env:NODE_OPTIONS = $oldOptions
        $env:NODE_PATH = $oldPath
    }
}

function Disable-PiAskClaude {
    if (-not $env:USERPROFILE -or -not (Get-Command node -ErrorAction SilentlyContinue)) {
        Write-Warning 'AskClaude policy failed: home-or-node-unavailable.'
        return $false
    }
    $activeDir = if ($null -ne $env:PI_CODING_AGENT_DIR) { $env:PI_CODING_AGENT_DIR } else { Join-Path $env:USERPROFILE '.pi/agent' }
    $code = @'
// BEGIN PI_ASKCLAUDE_POLICY
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
class PolicyError extends Error {}
const fail = code => { throw new PolicyError(code); };
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const own = (value, key) => Object.prototype.hasOwnProperty.call(value, key);
const same = (a, b) => a && b && a.dev === b.dev && a.ino === b.ino && a.mode === b.mode && a.nlink === b.nlink;
const key = file => process.platform === 'win32' ? file.toLowerCase() : file;
function info(file) {
    try { return fs.lstatSync(file); }
    catch (error) { if (error.code === 'ENOENT') return null; throw error; }
}
function absolute(value) {
    if (!value || !path.isAbsolute(value) || value.split(/[\\/]/).some(p => p === '.' || p === '..')) fail('unsafe-path');
    return path.resolve(value);
}
function read(file) {
    const stat = info(file);
    if (!stat) return { file, stat: null, text: '', value: {} };
    if (!stat.isFile() || stat.isSymbolicLink() || stat.nlink !== 1 || stat.size > 1024 * 1024 ||
        (process.getuid && stat.uid !== process.getuid())) fail('unsafe-file');
    const fd = fs.openSync(file, fs.constants.O_RDONLY | (fs.constants.O_NOFOLLOW || 0) | (fs.constants.O_NONBLOCK || 0));
    let text;
    try {
        if (!same(stat, fs.fstatSync(fd))) fail('changed-file');
        // Bounded descriptor read also rejects a file that grows after lstat.
        const buffer = Buffer.alloc(1024 * 1024 + 1);
        let size = 0, count;
        while (size < buffer.length && (count = fs.readSync(fd, buffer, size, buffer.length - size, null))) size += count;
        if (size > 1024 * 1024 || size !== stat.size) fail('changed-file');
        text = buffer.subarray(0, size).toString('utf8');
    } finally { fs.closeSync(fd); }
    let value;
    try { value = JSON.parse(text.replace(/^\uFEFF/, '')); }
    catch { fail('invalid-json'); }
    if (!object(value) || (own(value, 'askClaude') && (!object(value.askClaude) ||
        (own(value.askClaude, 'enabled') && typeof value.askClaude.enabled !== 'boolean')))) fail('invalid-config');
    return { file, stat, text, value };
}
try {
    // Profile creation/permissions belong to the preceding permission helper.
    // Resolve only the trusted account HOME boundary, never linked profiles.
    const logicalHome = absolute(process.argv[2]);
    const home = fs.realpathSync(logicalHome);
    const within = (file, base) => key(file).startsWith(key(base + path.sep));
    const normalize = value => {
        const file = absolute(value);
        return within(file, logicalHome) ? path.join(home, path.relative(logicalHome, file)) : file;
    };
    const profiles = [...new Map([path.join(home, '.pi', 'agent'), normalize(process.argv[3])].map(p => [key(p), p])).values()];
    const directories = new Map();
    for (const profile of profiles) {
        if (!within(profile, home)) fail('unsafe-path');
        for (let current = profile; ; current = path.dirname(current)) {
            const stat = info(current);
            if (!stat || !stat.isDirectory() || stat.isSymbolicLink() ||
                (process.getuid && stat.uid !== process.getuid())) fail('unsafe-directory');
            directories.set(current, stat);
            if (key(current) === key(home)) break;
        }
    }
    const checkDirectories = () => {
        for (const [dir, stat] of directories) if (!same(stat, info(dir))) fail('changed-directory');
    };
    // Preflight both profiles before either is changed, including already-disabled files.
    const records = profiles.map(profile => read(path.join(profile, 'claude-bridge.json')));
    let changed = false;
    for (const record of records) {
        checkDirectories();
        const current = read(record.file);
        if (current.text !== record.text || (record.stat ? !same(current.stat, record.stat) : current.stat)) fail('changed-file');
        // The bridge uses JSON.parse without stripping a BOM; write plain UTF-8.
        if (record.value.askClaude?.enabled === false && !record.text.startsWith('\uFEFF')) continue;
        record.value.askClaude = { ...record.value.askClaude, enabled: false };
        const text = JSON.stringify(record.value, null, 2) + '\n';
        const temporary = record.file + '.setup-' + crypto.randomBytes(12).toString('hex');
        let fd, created = false;
        try {
            fd = fs.openSync(temporary, 'wx', record.stat ? record.stat.mode & 0o777 : 0o600);
            created = true;
            fs.writeFileSync(fd, text);
            fs.closeSync(fd);
            fd = undefined;
            checkDirectories();
            const latest = read(record.file);
            if (latest.text !== record.text || (record.stat ? !same(latest.stat, record.stat) : latest.stat)) fail('changed-file');
            if (record.stat) fs.renameSync(temporary, record.file);
            else fs.linkSync(temporary, record.file); // Do not clobber a concurrently created config.
        } finally {
            if (fd !== undefined) fs.closeSync(fd);
            if (created && info(temporary)) fs.unlinkSync(temporary);
        }
        checkDirectories();
        if (read(record.file).text !== text) fail('verification-failed');
        changed = true;
    }
    console.log(changed ? 'disabled' : 'unchanged');
} catch (error) {
    console.log('askclaude:' + (error instanceof PolicyError ? error.message : 'filesystem-failed'));
    process.exitCode = 1;
}
// END PI_ASKCLAUDE_POLICY
'@
    $oldOptions = $env:NODE_OPTIONS
    $oldPath = $env:NODE_PATH
    $oldEncoding = $OutputEncoding
    try {
        $env:NODE_OPTIONS = $null
        $env:NODE_PATH = $null
        $OutputEncoding = New-Object System.Text.UTF8Encoding($false)
        $result = $code | & node --input-type=commonjs - $env:USERPROFILE $activeDir 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Warning 'AskClaude policy failed; review global claude-bridge.json paths, JSON, and permissions.'
            return $false
        }
        switch (($result -join "`n").Trim()) {
            'disabled' { Write-Success 'AskClaude disabled in global Pi profiles; Claude Bridge access preserved.'; return $true }
            'unchanged' { Write-Debug 'AskClaude is already disabled in global Pi profiles.'; return $true }
            default { Write-Warning 'AskClaude policy failed: unrecognized-result.'; return $false }
        }
    }
    catch {
        Write-Warning 'AskClaude policy failed; review global claude-bridge.json paths, JSON, and permissions.'
        return $false
    }
    finally {
        $env:NODE_OPTIONS = $oldOptions
        $env:NODE_PATH = $oldPath
        $OutputEncoding = $oldEncoding
    }
}
$null = 'END_PI_ASKCLAUDE_POLICY'

function Remove-PiProse {
    if (-not $env:USERPROFILE) {
        Write-Warning "USERPROFILE is required to retire pi-prose."
        return $false
    }
    $defaultDir = Join-Path $env:USERPROFILE ".pi\agent"
    $activeDir = if ($env:PI_CODING_AGENT_DIR) { $env:PI_CODING_AGENT_DIR } else { $defaultDir }
    $profiles = @($defaultDir, $activeDir) | Where-Object { Get-Item -LiteralPath $_ -Force -ErrorAction SilentlyContinue }
    if (-not $profiles) {
        Write-Debug "No global Pi profiles; pi-prose is absent."
        return $true
    }
    if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
        Write-Warning "Node.js is required to retire pi-prose from existing Pi profiles."
        return $false
    }
    $program = @'
// BEGIN PI_PROSE_RETIREMENT
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
class RetirementError extends Error {}
const fail = message => { throw new RetirementError(message); };
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const own = (value, key) => Object.prototype.hasOwnProperty.call(value, key);
const prose = source => typeof source === 'string' && (source === 'npm:pi-prose' || source.startsWith('npm:pi-prose@'));
const packageKey = key => key === 'pi-prose' || key.startsWith('pi-prose@');
function info(file) {
    try { return fs.lstatSync(file); }
    catch (error) { if (error.code === 'ENOENT') return null; throw error; }
}
function absolute(value) {
    if (!value || !path.isAbsolute(value) || value.split(/[\\/]/).some(part => part === '..' || part === '.')) {
        fail('Pi prose retirement requires absolute profile paths without dot segments.');
    }
    return path.resolve(value);
}
function readJson(file) {
    const stat = info(file);
    if (!stat) return null;
    if (!stat.isFile() || stat.isSymbolicLink() || stat.nlink > 1) fail('Pi prose metadata must be regular, unlinked JSON files.');
    const text = fs.readFileSync(file, 'utf8');
    let value;
    try { value = JSON.parse(text.replace(/^\uFEFF/, '')); }
    catch { fail('Invalid JSON in Pi prose retirement metadata; leaving it unchanged.'); }
    if (!object(value)) fail('Pi prose retirement metadata must contain a JSON object.');
    return { file, stat, text, value };
}
function stripDependencies(value) {
    let changed = false;
    for (const field of ['dependencies', 'devDependencies', 'optionalDependencies', 'peerDependencies', 'peerDependenciesMeta', 'overrides']) {
        if (!own(value, field)) continue;
        if (!object(value[field])) fail('Invalid dependency map in Pi prose retirement metadata.');
        for (const key of Object.keys(value[field])) {
            if (key === 'pi-prose' || (field === 'overrides' && packageKey(key))) {
                delete value[field][key];
                changed = true;
            }
        }
    }
    return changed;
}
try {
    // HOME is the trusted account boundary. Resolve only HOME, not Pi-owned paths,
    // so OS home aliases work without following linked profiles or package stores.
    const logicalHome = absolute(process.argv[2]);
    const home = fs.realpathSync(logicalHome);
    if (!fs.statSync(home).isDirectory()) fail('Pi prose retirement requires a home directory.');
    const key = value => process.platform === 'win32' ? value.toLowerCase() : value;
    const within = (file, base) => key(file) === key(base) || key(file).startsWith(key(base + path.sep));
    const normalize = value => {
        const file = absolute(value);
        return within(file, logicalHome) ? path.join(home, path.relative(logicalHome, file)) : file;
    };
    const directories = [...new Map([path.join(home, '.pi', 'agent'), process.argv[3] || path.join(home, '.pi', 'agent')]
        .map(normalize).map(dir => [key(dir), dir])).values()];
    function safeDirectory(dir) {
        const stop = within(dir, home) ? home : path.parse(dir).root;
        for (let current = dir; current !== stop; current = path.dirname(current)) {
            const stat = info(current);
            if (stat && (!stat.isDirectory() || stat.isSymbolicLink())) fail('Linked or non-directory Pi profile paths are not changed.');
        }
    }
    const writes = [];
    const removals = [];
    for (const dir of directories) {
        if (dir === path.parse(dir).root) fail('The filesystem root cannot be a Pi profile.');
        safeDirectory(dir);
        const npm = path.join(dir, 'npm');
        const modules = path.join(npm, 'node_modules');
        safeDirectory(modules);
        const settings = readJson(path.join(dir, 'settings.json'));
        if (settings && own(settings.value, 'packages')) {
            if (!Array.isArray(settings.value.packages)) fail('Pi settings packages must be an array.');
            if (settings.value.packages.some(entry => typeof entry !== 'string' && (!object(entry) || typeof entry.source !== 'string'))) {
                fail('Invalid package declaration in Pi settings; leaving it unchanged.');
            }
            const filtered = settings.value.packages.filter(entry => !prose(typeof entry === 'string' ? entry : entry.source));
            if (filtered.length !== settings.value.packages.length) {
                settings.value.packages = filtered;
                writes.push(settings);
            }
        }
        const manifest = readJson(path.join(npm, 'package.json'));
        if (manifest && stripDependencies(manifest.value)) writes.push(manifest);
        for (const file of [path.join(npm, 'package-lock.json'), path.join(npm, 'npm-shrinkwrap.json'), path.join(modules, '.package-lock.json')]) {
            const lock = readJson(file);
            if (!lock) continue;
            const value = lock.value;
            if (![1, 2, 3].includes(value.lockfileVersion)) fail('Unsupported Pi npm lockfile version; leaving it unchanged.');
            let changed = stripDependencies(value);
            if (own(value, 'packages')) {
                if (!object(value.packages)) fail('Invalid packages map in Pi npm lockfile.');
                if (own(value.packages, '')) {
                    if (!object(value.packages[''])) fail('Invalid root record in Pi npm lockfile.');
                    changed = stripDependencies(value.packages['']) || changed;
                }
                for (const name of Object.keys(value.packages)) {
                    if (name === 'node_modules/pi-prose' || name.startsWith('node_modules/pi-prose/')) {
                        delete value.packages[name];
                        changed = true;
                    }
                }
            }
            if (changed) writes.push(lock);
        }
        const target = path.join(modules, 'pi-prose');
        const stat = info(target);
        if (stat) {
            if (directories.some(profile => within(profile, target))) fail('A Pi profile overlaps the retired package directory; manual review is required.');
            // A linked package is unlinked, never followed into a user's source tree.
            if (!stat.isSymbolicLink()) {
                if (!stat.isDirectory()) fail('The installed pi-prose path is not a package directory.');
                const installed = readJson(path.join(target, 'package.json'));
                if (!installed || installed.value.name !== 'pi-prose') fail('Cannot verify the installed pi-prose package; leaving it unchanged.');
            }
            removals.push({ file: target, stat });
        }
    }
    // Preflight every profile before changing any of them. Remove declarations
    // before package files, without running npm, Pi, or lifecycle scripts.
    for (const record of writes) {
        safeDirectory(path.dirname(record.file));
        const current = info(record.file);
        if (!current || current.isSymbolicLink() || current.ino !== record.stat.ino || current.dev !== record.stat.dev ||
            fs.readFileSync(record.file, 'utf8') !== record.text) fail('Pi metadata changed during retirement; rerun setup after reviewing it.');
        const temporary = record.file + '.retire-' + crypto.randomBytes(12).toString('hex');
        try {
            const bom = record.text.startsWith('\uFEFF') ? '\uFEFF' : '';
            fs.writeFileSync(temporary, bom + JSON.stringify(record.value, null, 2) + '\n', { flag: 'wx', mode: record.stat.mode & 0o777 });
            fs.renameSync(temporary, record.file);
        } finally {
            if (info(temporary)) fs.unlinkSync(temporary);
        }
    }
    for (const record of removals) {
        safeDirectory(path.dirname(record.file));
        const current = info(record.file);
        if (!current || current.ino !== record.stat.ino || current.dev !== record.stat.dev ||
            current.isSymbolicLink() !== record.stat.isSymbolicLink()) fail('The pi-prose package changed during retirement; review it before retrying.');
        if (current.isSymbolicLink()) fs.unlinkSync(record.file);
        else fs.rmSync(record.file, { recursive: true });
        if (info(record.file)) fail('The pi-prose package still exists after retirement.');
    }
    console.log(writes.length || removals.length ? 'removed' : 'absent');
} catch (error) {
    console.error(error instanceof RetirementError ? error.message : 'Pi prose retirement failed during a filesystem operation; check permissions and retry.');
    process.exitCode = 1;
}
// END PI_PROSE_RETIREMENT
'@
    try {
        $output = $program | & node --input-type=commonjs - $env:USERPROFILE $activeDir 2>&1
        $status = $LASTEXITCODE
        $result = ($output | Out-String).Trim()
        if ($status -ne 0 -or $result -notin @("removed", "absent")) {
            Write-Warning "Required pi-prose retirement failed. Check profile paths, JSON files, and permissions; npm security settings were not changed."
            return $false
        }
        if ($result -eq "removed") {
            Write-Success "Retired pi-prose from global Pi profiles; custom prose files preserved."
        }
        else {
            Write-Debug "pi-prose is absent from global Pi profiles."
        }
        return $true
    }
    catch {
        Write-Warning "Required pi-prose retirement failed; global Pi profiles need review."
        return $false
    }
}
$null = 'END_PI_PROSE_RETIREMENT'

function Remove-PiRpivPackages {
    $hadFailure = $false
    if (Get-Command pi -ErrorAction SilentlyContinue) {
        foreach ($package in @("npm:@juicesharp/rpiv-ask-user-question", "npm:@juicesharp/rpiv-todo")) {
            $output = & pi remove $package 2>&1
            $removeExitCode = $LASTEXITCODE
            $outputText = ($output | Out-String)
            if ($removeExitCode -eq 0) {
                Write-Success "Removed Pi RPIV package ($package)."
            }
            elseif ($outputText -match "no matching package found") {
                Write-Debug "Pi RPIV package not installed ($package)."
            }
            else {
                Write-Warning "Failed to remove Pi RPIV package ($package): $outputText"
                $hadFailure = $true
            }
        }
        return (-not $hadFailure)
    }

    if ($env:PI_CODING_AGENT_DIR) {
        $agentDir = $env:PI_CODING_AGENT_DIR
    }
    else {
        $agentDir = Join-Path $env:USERPROFILE ".pi\agent"
    }

    $settingsPath = Join-Path $agentDir "settings.json"

    if (-not (Test-Path $settingsPath)) {
        Write-Debug "Pi settings not found; Pi RPIV packages not installed."
        return $true
    }

    $settingsJson = Get-Content -Path $settingsPath -Raw
    if ([string]::IsNullOrWhiteSpace($settingsJson)) {
        $settingsJson = "{}"
    }

    try {
        $settings = $settingsJson | ConvertFrom-Json
        if ($null -eq $settings) {
            $settings = New-Object PSObject
        }
    }
    catch {
        Write-Warning "Failed to parse Pi settings at $settingsPath. Leaving settings unchanged."
        return $false
    }

    $packages = @()
    if ($settings.PSObject.Properties["packages"]) {
        $packages = @($settings.packages)
    }

    $filteredPackages = @()
    foreach ($package in $packages) {
        $source = ""
        if ($package -is [string]) {
            $source = $package
        }
        elseif ($null -ne $package -and $package.PSObject.Properties["source"]) {
            $source = [string]$package.source
        }

        if ($source -ne "npm:@juicesharp/rpiv-ask-user-question" -and $source -ne "npm:@juicesharp/rpiv-todo") {
            $filteredPackages += $package
        }
    }

    if ($filteredPackages.Count -eq 0) {
        Remove-JsonProperty -Object $settings -Name "packages"
    }
    else {
        Set-JsonProperty -Object $settings -Name "packages" -Value ([object[]]$filteredPackages)
    }

    try {
        $settings | ConvertTo-Json -Depth 20 | Set-Content -Path $settingsPath -Encoding UTF8
        Write-Success "Removed Pi RPIV packages from Pi settings."
    }
    catch {
        Write-Warning "Failed to write Pi settings at $settingsPath."
        return $false
    }
    return $true
}

function Update-PiPackages {
    $agentDir = if ($env:PI_CODING_AGENT_DIR) { $env:PI_CODING_AGENT_DIR } else { Join-Path $HOME '.pi\agent' }
    if (-not (Get-Command node -ErrorAction SilentlyContinue) -or -not (Get-Command git -ErrorAction SilentlyContinue) -or -not (Get-Command pi -ErrorAction SilentlyContinue)) {
        Write-Warning 'Pi package refresh prerequisites are unavailable. Required refresh is incomplete.'
        return $false
    }
    if ($env:PI_OFFLINE -and $env:PI_OFFLINE.ToLowerInvariant() -in @('1', 'true', 'yes')) {
        Write-Warning 'Pi offline mode is enabled. Required package refresh is incomplete.'
        return $false
    }
    $code = @'
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const agentDir = path.resolve(process.argv[2]);
const fail = () => { console.log('unsafe'); process.exitCode = 1; };
const lstat = file => { try { return fs.lstatSync(file); } catch (error) { if (error.code === 'ENOENT') return null; throw error; } };
function parseGit(source) {
    const trimmed = source.trim();
    const prefixed = trimmed.startsWith('git:');
    let value = prefixed ? trimmed.slice(4).trim() : trimmed;
    if (!prefixed && !/^(https?|ssh|git):\/\//i.test(value)) return null;
    // Native Pi accepts many hosted-git aliases. Only derive a checkout path for a
    // deliberately narrow canonical subset; ambiguous valid aliases fail closed.
    if (!value || /[%#?\\]/.test(value) || value.endsWith('/') || /\/(?:tree|blob|commit|releases?)\//i.test(value)) return false;
    let host = '', repoPath = '';
    const scp = value.match(/^git@([a-z0-9.-]+):([^@:]+\/[^/@:]+)(?:@([^/]+))?$/);
    if (scp) {
        host = scp[1]; repoPath = scp[2];
    } else if (/^(?:https?|ssh|git):\/\//i.test(value)) {
        let url; try { url = new URL(value); } catch { return false; }
        if ((url.username && url.username !== 'git') || url.password || url.search || url.hash || url.port) return false;
        host = url.hostname;
        const pathWithRef = url.pathname.replace(/^\/+/, '');
        const match = pathWithRef.match(/^([^/@]+\/[^/@]+?)(?:@([^/]+))?$/);
        if (!match) return false;
        repoPath = match[1];
    } else {
        const match = value.match(/^([a-z0-9.-]+)\/([^/@]+\/[^/@]+?)(?:@([^/]+))?$/);
        if (!match || (!match[1].includes('.') && match[1] !== 'localhost')) return false;
        host = match[1]; repoPath = match[2];
    }
    if (host.startsWith('www.') || repoPath.endsWith('.git.git')) return false;
    repoPath = repoPath.replace(/\.git$/, '');
    if (repoPath.endsWith('.git')) return false;
    const decoded = item => { try { return decodeURIComponent(item); } catch { return null; } };
    const unsafe = (item, slash) => {
        const decodedItem = decoded(item);
        return decodedItem === null || decodedItem !== item || [item, decodedItem].some(candidate => candidate.includes('\0') || candidate.startsWith('/') || (!slash && candidate.includes('/')) || candidate.split('/').includes('..'));
    };
    if (!host || host !== host.toLowerCase() || repoPath.split('/').length !== 2 || unsafe(host, false) || unsafe(repoPath, true)) return false;
    return { host, repoPath };
    }
try {
    for (const directory of [agentDir, path.join(agentDir, 'git')]) {
        const info = lstat(directory);
        if (info && (!info.isDirectory() || info.isSymbolicLink())) throw new Error('unsafe directory');
    }
    const settingsFile = path.join(agentDir, 'settings.json');
    const info = lstat(settingsFile);
    if (!info) { console.log('ready'); process.exit(0); }
    if (!info.isFile() || info.isSymbolicLink() || info.nlink !== 1 || info.size > 10 * 1024 * 1024) throw new Error('unsafe settings');
    const settings = JSON.parse(fs.readFileSync(settingsFile, 'utf8').replace(/^\uFEFF/, ''));
    if (!settings || typeof settings !== 'object' || Array.isArray(settings) || ('packages' in settings && !Array.isArray(settings.packages))) throw new Error('invalid settings');
    for (const entry of settings.packages || []) {
        const source = typeof entry === 'string' ? entry : entry && typeof entry === 'object' && !Array.isArray(entry) ? entry.source : null;
        if (typeof source !== 'string' || !source.trim()) throw new Error('invalid package');
        const parsed = parseGit(source);
        if (parsed === false) throw new Error('invalid git source');
        if (!parsed) continue;
        for (const name of ['GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE', 'GIT_COMMON_DIR', 'GIT_OBJECT_DIRECTORY', 'GIT_ALTERNATE_OBJECT_DIRECTORIES']) {
            if (process.env[name]) throw new Error('redirected git state');
        }
        const gitRoot = path.resolve(agentDir, 'git');
        const components = [parsed.host, ...parsed.repoPath.split('/')];
        let cursor = gitRoot;
        let checkoutMissing = false;
        for (const component of components) {
            cursor = path.join(cursor, component);
            const part = lstat(cursor);
            if (!part) { checkoutMissing = true; break; }
            if (!part.isDirectory() || part.isSymbolicLink()) throw new Error('unsafe checkout path');
        }
        const checkout = path.resolve(gitRoot, ...components);
        if (!checkout.startsWith(gitRoot + path.sep)) throw new Error('unsafe checkout');
        if (checkoutMissing) continue;
        const dotGit = path.join(checkout, '.git');
        const dotGitInfo = lstat(dotGit);
        if (!dotGitInfo || !dotGitInfo.isDirectory() || dotGitInfo.isSymbolicLink()) throw new Error('unsafe git metadata');
        const gitEnv = { ...process.env, GIT_TERMINAL_PROMPT: '0', GIT_OPTIONAL_LOCKS: '0' };
        const inspect = args => spawnSync('git', ['-c', 'core.fsmonitor=false', ...args], {
            cwd: checkout, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'], timeout: 15000, env: gitEnv,
        });
        const identity = inspect(['rev-parse', '--show-toplevel', '--absolute-git-dir', '--git-common-dir']);
        if (identity.error || identity.status !== 0 || identity.signal || identity.stdout.length > 4096) throw new Error('unverified repository');
        const identityLines = identity.stdout.trim().split(/\r?\n/);
        if (identityLines.length !== 3 || path.resolve(identityLines[0]) !== checkout ||
            path.resolve(identityLines[1]) !== dotGit || path.resolve(checkout, identityLines[2]) !== dotGit) throw new Error('unexpected repository identity');
        const status = inspect(['status', '--porcelain=v1', '-z', '--untracked-files=all', '--ignored=matching']);
        if (status.error || status.status !== 0 || status.signal || status.stdout.length > 1024 * 1024 || status.stdout.length > 0) throw new Error('unverified or modified checkout');
    }
    console.log('ready');
    } catch { fail(); }
'@
    $result = $code | & node - $agentDir 2>$null
    if ($LASTEXITCODE -ne 0 -or ($result -join "`n").Trim() -ne 'ready') {
        Write-Warning 'Pi package refresh safety preflight failed. Registered Git checkouts and active-profile metadata were left unchanged.'
        return $false
    }
    Write-Message 'Refreshing packages in the active global Pi profile...'
    $null = & pi update --extensions --no-approve 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Success 'Pi packages refreshed in the active global profile.'
        return $true
    }
    Write-Warning 'Pi package refresh failed. Required refresh is incomplete.'
    return $false
}

function Prepare-PiMcpAdapter {
    param([ValidateSet('prepare', 'verify')][string]$Mode = 'prepare')
    if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
        Write-Warning "Node.js not found. Cannot safely prepare Pi package metadata."
        return $false
    }
    $agentDir = if ($env:PI_CODING_AGENT_DIR) { $env:PI_CODING_AGENT_DIR } else { Join-Path $env:USERPROFILE '.pi\agent' }
    $disabled = if (Test-EnvLocalFlag 'BAN_PI_MCP_ADAPTER') { '1' } else { '0' }
    $code = @'
    // Only the active profile's managed adapter records are changed. npm owns locks.
    const fs = require('node:fs');
    const path = require('node:path');
    const [agentDir, disabled, mode] = process.argv.slice(2);
    const version = '2.32.1';
    const source = `npm:pi-mcp-adapter@${version}`;
    const isObject = value => value !== null && typeof value === 'object' && !Array.isArray(value);
    const isAdapter = value => typeof value === 'string' && /^npm:pi-mcp-adapter(?:@[^\s]+)?$/.test(value);
    function stat(file) {
        try { return fs.lstatSync(file); }
        catch (error) { if (error.code === 'ENOENT') return null; throw error; }
    }
    function read(file) {
        const info = stat(file);
        if (!info) return { file, data: null };
        if (!info.isFile() || info.isSymbolicLink() || info.nlink !== 1) throw new Error('unsafe file');
        const original = fs.readFileSync(file, 'utf8');
        const data = JSON.parse(original.replace(/^\uFEFF/, ''));
        if (!isObject(data)) throw new Error('invalid object');
        return { file, data, original, info };
    }
    try {
        if (!['prepare', 'verify'].includes(mode)) throw new Error('invalid mode');
        const store = path.join(agentDir, 'npm');
        // Reject linked managed directories, but allow platform aliases above agentDir.
        for (const directory of [agentDir, store, path.join(store, 'node_modules'), path.join(store, 'node_modules/pi-mcp-adapter')]) {
            const info = stat(directory);
            if (info && (!info.isDirectory() || info.isSymbolicLink())) throw new Error('unsafe directory');
        }
        const settings = read(path.join(agentDir, 'settings.json'));
        const manifest = read(path.join(store, 'package.json'));
        const installed = read(path.join(store, 'node_modules/pi-mcp-adapter/package.json'));
        read(path.join(store, 'package-lock.json'));
        read(path.join(store, 'node_modules/.package-lock.json'));
        if (settings.data && 'packages' in settings.data && !Array.isArray(settings.data.packages)) throw new Error('invalid packages');
        const packages = settings.data?.packages ?? [];
        if (packages.some(entry => typeof entry !== 'string' && (!isObject(entry) || typeof entry.source !== 'string'))) throw new Error('invalid package');
        const adapters = packages.filter(entry => isAdapter(typeof entry === 'string' ? entry : entry.source));
        for (const entry of adapters) {
            if (typeof entry === 'string') continue;
            if (('extensions' in entry && (!Array.isArray(entry.extensions) || entry.extensions.some(item => typeof item !== 'string'))) ||
                ('autoload' in entry && typeof entry.autoload !== 'boolean')) throw new Error('adapter activation');
        }
        for (const field of ['dependencies', 'devDependencies', 'optionalDependencies']) {
            if (manifest.data && field in manifest.data && !isObject(manifest.data[field])) throw new Error('invalid dependencies');
        }
        if (mode === 'verify') {
            if (disabled !== '1' && (installed.data?.name !== 'pi-mcp-adapter' || installed.data?.version !== version ||
                manifest.data?.dependencies?.['pi-mcp-adapter'] !== version ||
                !packages.some(entry => (typeof entry === 'string' ? entry : entry.source) === source))) throw new Error('unverified adapter');
            if (disabled !== '1') {
                // 2.32.1 declares one extension. Do not execute it during live setup:
                // extension startup can connect MCP servers or run configured commands.
                const resources = installed.data.pi?.extensions;
                const entryPoint = stat(path.join(store, 'node_modules/pi-mcp-adapter/index.ts'));
                if (!Array.isArray(resources) || resources.length !== 1 || resources[0] !== './index.ts' ||
                    !entryPoint?.isFile() || entryPoint.isSymbolicLink() || entryPoint.nlink !== 1 || entryPoint.size === 0) {
                    throw new Error('unverified adapter resource');
                }
                if (adapters.length !== 1) throw new Error('adapter activation');
                const entry = adapters[0];
                if (typeof entry !== 'string') {
                    // Accept Pi's defaults or explicit entry-point selections.
                    // A force-include overrides globs, but never a force-exclude.
                    // Preserve other complex filters without guessing their meaning.
                    const filters = entry.extensions;
                    const exact = value => {
                        const normalized = value.replaceAll('\\', '/').replace(/^\.\//, '');
                        return normalized === 'index.ts' || normalized ===
                            path.resolve(store, 'node_modules/pi-mcp-adapter/index.ts').replaceAll('\\', '/');
                    };
                    let enabled = filters === undefined && entry.autoload !== false;
                    if (filters?.length) {
                        const last = filters[filters.length - 1];
                        enabled = entry.autoload === false
                            ? last === 'index.ts' || (last.startsWith('+') && exact(last.slice(1)))
                            : (filters.length === 1 && filters[0] === 'index.ts' ||
                                filters.some(item => item.startsWith('+') && exact(item.slice(1)))) &&
                                !filters.some(item => item.startsWith('-') && exact(item.slice(1)));
                    }
                    if (!enabled) throw new Error('adapter activation');
                }
            }
        } else {
            const changes = [];
            if (settings.data && 'packages' in settings.data) {
                const next = packages.flatMap(entry => {
                    const current = typeof entry === 'string' ? entry : entry.source;
                    if (!isAdapter(current)) return [entry];
                    if (disabled === '1') return [];
                    return [typeof entry === 'string' ? source : { ...entry, source }];
                });
                if (JSON.stringify(next) !== JSON.stringify(packages)) {
                    settings.data.packages = next;
                    changes.push(settings);
                }
            }
            if (manifest.data) {
                let changed = false;
                for (const field of ['dependencies', 'devDependencies', 'optionalDependencies']) {
                    const deps = manifest.data[field];
                    if (!deps || !Object.hasOwn(deps, 'pi-mcp-adapter')) continue;
                    if (disabled === '1') { delete deps['pi-mcp-adapter']; changed = true; }
                    else if (deps['pi-mcp-adapter'] !== version) { deps['pi-mcp-adapter'] = version; changed = true; }
                }
                if (changed) changes.push(manifest);
            }
            // Validate every input before writing. Replace only changed files, atomically.
            for (const record of changes) {
                const temporary = `${record.file}.setup-${process.pid}.tmp`;
                let created = false;
                try {
                    const current = fs.lstatSync(record.file);
                    if (current.ino !== record.info.ino || current.dev !== record.info.dev || current.nlink !== 1 ||
                        current.isSymbolicLink() || fs.readFileSync(record.file, 'utf8') !== record.original) throw new Error('concurrent edit');
                    fs.writeFileSync(temporary, JSON.stringify(record.data, null, 2) + '\n', { flag: 'wx', mode: record.info.mode & 0o777 });
                    created = true;
                    fs.renameSync(temporary, record.file);
                } finally {
                    if (created && fs.existsSync(temporary)) fs.unlinkSync(temporary);
                }
            }
        }
    } catch (error) {
        if (error.message === 'adapter activation') {
            console.error('Pi MCP adapter enablement could not be verified. Existing filters were preserved. Use pi config in the active global profile to enable index.ts, or set BAN_PI_MCP_ADAPTER=1 for an intentional opt-out.');
        } else {
            console.error('Pi MCP adapter metadata/resource validation failed; inspect the active profile and reinstall the pinned package if needed. npm security settings were not changed.');
        }
        process.exitCode = 1;
    }
'@
    $output = $code | & node - $agentDir $disabled $Mode 2>&1
    if ($LASTEXITCODE -ne 0) {
        $activationMessage = 'Pi MCP adapter enablement could not be verified. Existing filters were preserved. Use pi config in the active global profile to enable index.ts, or set BAN_PI_MCP_ADAPTER=1 for an intentional opt-out.'
        if (@($output | ForEach-Object { $_.ToString() }) -contains $activationMessage) {
            Write-Warning $activationMessage
        }
        else {
            Write-Warning "Pi MCP adapter metadata/resource validation failed; inspect the active profile and reinstall the pinned package if needed. npm security settings were not changed."
        }
        return $false
    }
    return $true
}

function Setup-PiMcpAdapter {
    $package = "npm:pi-mcp-adapter@2.32.1"

    if (-not (Prepare-PiMcpAdapter)) { return $false }
    if (Test-EnvLocalFlag "BAN_PI_MCP_ADAPTER") {
        Write-Success "Pi MCP adapter extension disabled in Pi settings."
        return $true
    }

    if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
        Write-Warning "npm not found. Cannot install Pi MCP adapter."
        Write-Debug "Install Node.js/npm, then run: pi install npm:pi-mcp-adapter@2.32.1"
        return $false
    }

    if (-not (Get-Command pi -ErrorAction SilentlyContinue)) {
        Write-Warning "Pi coding agent not found. Cannot install Pi MCP adapter."
        return $false
    }

    Write-Message "Installing/updating Pi MCP adapter..."
    $savedExact = $env:npm_config_save_exact
    try {
        $env:npm_config_save_exact = 'true'
        $output = & pi install $package 2>&1
        $installStatus = $LASTEXITCODE
    }
    finally { $env:npm_config_save_exact = $savedExact }
    if ($installStatus -eq 0) {
        $listOutput = & pi list 2>&1
        $listText = ($listOutput | Out-String)
        if ($LASTEXITCODE -eq 0 -and $listText.Contains($package)) {
            if (-not (Prepare-PiMcpAdapter -Mode verify)) { return $false }
            Write-Success "Pi MCP adapter installed/updated and enabled in the active global profile (restart Pi or /reload to load it)."
        }
        else {
            Write-Warning "Pi MCP adapter install completed, but package validation was inconclusive: $listText"
            return $false
        }
    }
    else {
        Write-Warning "Failed to install Pi MCP adapter: $output"
        return $false
    }
    return $true
}

function Setup-PiClaudeBridge {
    $package = "npm:pi-claude-bridge"

    if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
        Write-Warning "npm not found. Cannot install Pi Claude bridge."
        Write-Debug "Install Node.js/npm, then run: pi install npm:pi-claude-bridge"
        return $false
    }

    if (-not (Get-Command pi -ErrorAction SilentlyContinue)) {
        Write-Warning "Pi coding agent not found. Cannot install Pi Claude bridge."
        return $false
    }

    Write-Message "Installing/updating Pi Claude bridge..."
    $output = & pi install $package 2>&1
    if ($LASTEXITCODE -eq 0) {
        $listOutput = & pi list 2>&1
        $listText = ($listOutput | Out-String)
        if ($LASTEXITCODE -eq 0 -and $listText.Contains($package)) {
            Write-Success "Pi Claude bridge installed/updated."
        }
        else {
            Write-Warning "Pi Claude bridge install completed, but package validation was inconclusive: $listText"
            return $false
        }
    }
    else {
        Write-Warning "Failed to install Pi Claude bridge: $output"
        return $false
    }
    return $true
}

function Setup-PiCompanionPackages {
    $hadFailure = $false
    $legacyPackage = "npm:pi-ask-user"
    $packages = @(
        "npm:pi-web-access"
    )

    if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
        Write-Warning "npm not found. Cannot install Pi companion packages."
        Write-Debug "Install Node.js/npm, then install these Pi packages manually: $($packages -join ', ')"
        return $false
    }

    if (-not (Get-Command pi -ErrorAction SilentlyContinue)) {
        Write-Warning "Pi coding agent not found. Cannot install Pi companion packages."
        return $false
    }

    $listOutput = & pi list 2>&1
    $listExitCode = $LASTEXITCODE
    $listText = ($listOutput | Out-String)
    if ($listExitCode -eq 0) {
        if ($listText.Contains($legacyPackage)) {
            Write-Message "Removing legacy Pi Ask User package..."
            $output = & pi remove $legacyPackage 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Success "Legacy Pi Ask User package removed."
            }
            else {
                Write-Warning "Failed to remove legacy Pi Ask User package: $output"
                $hadFailure = $true
            }
        }
    }
    else {
        Write-Warning "Cannot inspect Pi packages before legacy cleanup: $listText"
        $hadFailure = $true
    }

    foreach ($package in $packages) {
        Write-Message "Installing/updating Pi package $package..."
        $output = & pi install $package 2>&1
        if ($LASTEXITCODE -eq 0) {
            $listOutput = & pi list 2>&1
            $listExitCode = $LASTEXITCODE
            $listText = ($listOutput | Out-String)
            if ($listExitCode -eq 0 -and $listText.Contains($package)) {
                Write-Success "Pi package $package installed/updated."
            }
            else {
                Write-Warning "Pi package $package install completed, but validation was inconclusive: $listText"
                $hadFailure = $true
            }
        }
        else {
            Write-Warning "Failed to install Pi package ${package}: $output"
            $hadFailure = $true
        }
    }
    return (-not $hadFailure)
}

function Set-PiSkillOwnership {
    if ($script:PiProfileMutationsBlocked) { return $true }
    return (Invoke-MattPocockSkillPolicy -Mode ownership)
}

function Set-PiAutoresearchShortcut {
    $agentDir = if ($env:PI_CODING_AGENT_DIR) { $env:PI_CODING_AGENT_DIR } else { Join-Path $env:USERPROFILE ".pi\agent" }
    $configDir = Join-Path $agentDir "extensions"
    $configPath = Join-Path $configDir "pi-autoresearch.json"
    New-Item -ItemType Directory -Force -Path $configDir | Out-Null
    $configJson = if (Test-Path $configPath) { Get-Content -LiteralPath $configPath -Raw } else { "{}" }
    try { $config = $configJson | ConvertFrom-Json } catch {
        Write-Warning "Failed to parse pi-autoresearch config at $configPath."
        return $false
    }
    if ($null -eq $config) { $config = New-Object PSObject }
    $shortcuts = if ($config.PSObject.Properties["shortcuts"] -and $null -ne $config.shortcuts) { $config.shortcuts } else { New-Object PSObject }
    Set-JsonProperty -Object $shortcuts -Name "fullscreenDashboard" -Value "ctrl+shift+r"
    Set-JsonProperty -Object $config -Name "shortcuts" -Value $shortcuts
    try { $config | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $configPath -Encoding UTF8 } catch {
        Write-Warning "Failed to write pi-autoresearch config at $configPath."
        return $false
    }
    Write-Success "pi-autoresearch dashboard shortcut set to Ctrl+Shift+R."
    return $true
}

function Remove-PiGoalAutoresearchSettings {
    if ($env:PI_CODING_AGENT_DIR) {
        $agentDir = $env:PI_CODING_AGENT_DIR
    }
    else {
        $agentDir = Join-Path $env:USERPROFILE ".pi\agent"
    }

    $settingsPath = Join-Path $agentDir "settings.json"

    if (-not (Test-Path $agentDir)) {
        New-Item -ItemType Directory -Force -Path $agentDir | Out-Null
    }

    $settingsJson = "{}"
    if (Test-Path $settingsPath) {
        $settingsJson = Get-Content -Path $settingsPath -Raw
        if ([string]::IsNullOrWhiteSpace($settingsJson)) {
            $settingsJson = "{}"
        }
    }

    try {
        $settings = $settingsJson | ConvertFrom-Json
        if ($null -eq $settings) {
            $settings = New-Object PSObject
        }
    }
    catch {
        Write-Warning "Failed to parse Pi settings at $settingsPath. Leaving settings unchanged."
        return $false
    }

    $packages = @()
    if ($settings.PSObject.Properties["packages"]) {
        $packages = @($settings.packages)
    }

    $filteredPackages = @()
    foreach ($package in $packages) {
        $source = ""
        if ($package -is [string]) {
            $source = $package
        }
        elseif ($null -ne $package -and $package.PSObject.Properties["source"]) {
            $source = [string]$package.source
        }

        if ($source -ne "npm:pi-goal" -and $source -ne "npm:pi-autoresearch") {
            $filteredPackages += $package
        }
    }

    if ($filteredPackages.Count -eq 0) {
        Remove-JsonProperty -Object $settings -Name "packages"
    }
    else {
        Set-JsonProperty -Object $settings -Name "packages" -Value ([object[]]$filteredPackages)
    }

    try {
        $settings | ConvertTo-Json -Depth 20 | Set-Content -Path $settingsPath -Encoding UTF8
    }
    catch {
        Write-Warning "Failed to write Pi settings at $settingsPath."
        return $false
    }

    return $true
}

function Setup-PiGoalAutoresearch {
    $packages = @("npm:pi-goal", "npm:pi-autoresearch")
    $hadFailure = $false

    if (Test-EnvLocalFlag "BAN_PI_GOAL_AUTORESEARCH") {
        if (-not (Remove-PiGoalAutoresearchSettings)) { return $false }
        Write-Success "Pi goal/autoresearch extensions disabled in Pi settings."
        return $true
    }

    if (-not (Get-Command pi -ErrorAction SilentlyContinue)) {
        Write-Warning "Pi coding agent not found. Cannot install Pi goal/autoresearch extensions."
        return $false
    }

    foreach ($package in $packages) {
        Write-Message "Installing/updating $package..."
        $output = & pi install $package 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Success "$package installed/updated."
        }
        else {
            $hadFailure = $true
            Write-Warning "Failed to install ${package}: $output"
        }
    }

    $listOutput = & pi list 2>&1
    $listText = ($listOutput | Out-String)
    $hasGoal = $listText.Contains("npm:pi-goal")
    $hasAutoresearch = $listText.Contains("npm:pi-autoresearch")

    if (-not $hadFailure) {
        if ($LASTEXITCODE -eq 0 -and $hasGoal -and $hasAutoresearch) {
            Write-Success "Pi goal/autoresearch extensions are active."
        }
        else {
            Write-Warning "Pi goal/autoresearch install completed, but package validation was inconclusive: $listText"
            $hadFailure = $true
        }
    }

    if (-not (Set-PiAutoresearchShortcut)) { $hadFailure = $true }
    return (-not $hadFailure)
}


function Test-MattPocockSkillsDisabled {
    return ((Test-EnvLocalFlag "BAN_MATT_POCOCK_SKILLS") -or (Test-EnvLocalFlag "BAN_MATT_POCKOCK_SKILLS"))
}

function Invoke-MattPocockSkillPolicy {
    param([Parameter(Mandatory = $true)][string]$Mode, [string]$ReportFile = "")
    if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
        Write-Warning "Node.js is unavailable; managed skill policy cannot run."
        return $false
    }
    $helper = @'
    // Shared by all six standalone setup scripts. Never execute installed skills.
    const fs = require('node:fs');
    const path = require('node:path');
    const [homeInput, activePiInput, blocked, mode, reportFile] = process.argv.slice(2);
    const env = process.env;
    const fail = reason => { throw new Error(reason); };
    const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
    const nameOK = name => typeof name === 'string' && /^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(name) && name.length <= 64;
    const unique = values => [...new Set(values)];
    const known = [
        'ask-matt', 'code-review', 'codebase-design', 'diagnosing-bugs', 'domain-modeling',
        'grill-with-docs', 'implement', 'improve-codebase-architecture', 'prototype', 'research',
        'pr', 'setup-matt-pocock-skills', 'tdd', 'to-spec', 'to-tickets',
        'triage', 'wayfinder', 'wizard', 'claude-handoff', 'implement-spec', 'loop-me', 'retro',
        'setup-ts-deep-modules', 'writing-beats', 'writing-fragments', 'writing-shape',
        'git-guardrails-claude-code', 'migrate-to-shoehorn', 'scaffold-exercises', 'setup-pre-commit',
        'grill-me', 'grilling', 'handoff', 'teach', 'to-questionnaire', 'wait-what', 'writing-for-agents'
    ];
    // Upstream-retired names remain managed, but ordinary installs preserve copies.
    const historical = ['resolving-merge-conflicts'];
    const obsolete = ['diagnose', 'zoom-out'];
    function stat(file) {
        try { return fs.lstatSync(file); }
        catch (error) { if (error.code === 'ENOENT') return null; throw error; }
    }
    // The only ancestor link allowed is Bazzite's root-owned system /home alias.
    function systemHomeAlias(file, st) {
        if (process.platform !== 'linux' || file !== '/home' || st.uid !== 0) return false;
        if (!['var/home', '/var/home'].includes(fs.readlinkSync(file))) return false;
        return ['/', '/var', '/var/home'].every(dir => {
            const item = stat(dir);
            return item && item.isDirectory() && !item.isSymbolicLink() && item.uid === 0 && !(item.mode & 0o022);
        });
    }
    function absolute(file) {
        if (!file || !path.isAbsolute(file) || file.split(/[\\/]/).includes('..')) fail('unsafe-path');
        const resolved = path.resolve(file);
        if (resolved === path.parse(resolved).root) fail('unsafe-path');
        return resolved;
    }
    function directory(file) {
        const parent = path.dirname(file);
        if (parent !== file) directory(parent);
        const st = stat(file);
        if (!st) return;
        if (st.isSymbolicLink()) {
            if (!systemHomeAlias(file, st)) fail('linked-directory');
        } else if (!st.isDirectory()) fail('not-directory');
    }
    function owned(file) {
        const st = stat(file);
        if (st && process.platform !== 'win32' && st.uid !== process.getuid()) fail('wrong-owner');
    }
    function jsonFile(file) {
        directory(path.dirname(file));
        const st = stat(file);
        if (!st) return null;
        if (!st.isFile() || st.isSymbolicLink() || st.nlink !== 1) fail('unsafe-metadata');
        owned(file);
        let value;
        try { value = JSON.parse(fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, '')); }
        catch { fail('malformed-metadata'); }
        if (!object(value)) fail('malformed-metadata');
        return value;
    }
    function writeJson(file, value) {
        directory(path.dirname(file));
        jsonFile(file);
        fs.mkdirSync(path.dirname(file), {recursive: true, mode: 0o700});
        const temp = file + '.setup-' + require('node:crypto').randomUUID();
        try {
            fs.writeFileSync(temp, JSON.stringify(value, null, 2) + '\n', {flag: 'wx', mode: stat(file)?.mode & 0o777 || 0o600});
            fs.renameSync(temp, file);
        } finally { if (stat(temp)) fs.unlinkSync(temp); }
    }
    // Preflight the complete bounded tree before removal. Links are unlinked, never traversed.
    function removable(file) {
        directory(path.dirname(file));
        const st = stat(file);
        if (!st) return;
        owned(file);
        if (st.isSymbolicLink()) return;
        if (st.isDirectory()) {
            for (const entry of fs.readdirSync(file)) removable(path.join(file, entry));
        } else if (!st.isFile()) fail('unsupported-file');
    }
    function remove(file) {
        removable(file);
        const st = stat(file);
        if (!st) return;
        if (st.isDirectory() && !st.isSymbolicLink()) {
            for (const entry of fs.readdirSync(file)) remove(path.join(file, entry));
            fs.rmdirSync(file);
        } else fs.unlinkSync(file);
        if (stat(file)) fail('removal-failed');
    }
    function copiedTree(file) {
        const st = stat(file);
        if (!st || st.isSymbolicLink()) fail('invalid-skill-copy');
        owned(file);
        if (st.isDirectory()) {
            for (const entry of fs.readdirSync(file)) copiedTree(path.join(file, entry));
        } else if (!st.isFile()) fail('invalid-skill-copy');
    }
    function sameTree(left, right) {
        const a = stat(left), b = stat(right);
        if (!a || !b || a.isSymbolicLink() || b.isSymbolicLink()) return false;
        if (a.isFile() && b.isFile()) return fs.readFileSync(left).equals(fs.readFileSync(right));
        if (!a.isDirectory() || !b.isDirectory()) return false;
        const names = fs.readdirSync(left).sort(), other = fs.readdirSync(right).sort();
        return JSON.stringify(names) === JSON.stringify(other) && names.every(name => sameTree(path.join(left, name), path.join(right, name)));
    }
    try {
        if (mode === 'dispose') {
            const stage = absolute(reportFile);
            const tempRoot = fs.realpathSync(require('node:os').tmpdir());
            if (path.dirname(stage) !== tempRoot || !/^setup-matt-pocock-[a-zA-Z0-9]+$/.test(path.basename(stage))) fail('unsafe-stage');
            directory(tempRoot);
            const st = stat(stage);
            if (st) {
                owned(stage);
                if (!st.isSymbolicLink() && (!st.isDirectory() || process.platform !== 'win32' && (st.mode & 0o077))) fail('unsafe-stage');
                // Explicit unlink traversal also avoids legacy PowerShell junction
                // recursion. A replaced stage root is unlinked, never followed.
                remove(stage);
            }
            process.exit(0);
        }
        const home = absolute(homeInput);
        directory(home);
        const profile = (value, fallback) => {
            const result = absolute(value || path.join(home, fallback));
            if (result === home) fail('unsafe-path');
            return result;
        };
        const defaultPi = path.join(home, '.pi/agent');
        // Do not inspect rejected Pi profiles, including a rejected custom override.
        const piDirs = blocked === '1' ? [] : unique([defaultPi, profile(activePiInput, '.pi/agent')]);
        const claude = profile(env.CLAUDE_CONFIG_DIR, '.claude');
        const shared = path.join(home, '.agents/skills');
        const installDirs = unique([path.join(claude, 'skills'), shared]);
        const allDirs = unique([
            shared, path.join(home, '.claude/skills'), path.join(claude, 'skills'),
            path.join(home, '.codex/skills'), path.join(profile(env.CODEX_HOME, '.codex'), 'skills'),
            path.join(home, '.gemini/skills'), path.join(home, '.cursor/skills'),
            ...piDirs.map(dir => path.join(dir, 'skills'))
        ]);
        const manifestFile = path.join(home, '.agents/.setup-matt-pocock-skills.json');
        const manifest = jsonFile(manifestFile);
        if (manifest && (manifest.version !== 1 || !Array.isArray(manifest.skills) || !manifest.skills.every(nameOK))) fail('invalid-inventory');
        const lockPaths = unique([
            path.join(home, '.agents/.skill-lock.json'),
            ...(env.XDG_STATE_HOME ? [path.join(absolute(env.XDG_STATE_HOME), 'skills/.skill-lock.json')] : [])
        ]);
        const locks = lockPaths.map(file => {
            const data = jsonFile(file);
            if (data && (data.version !== 3 || !object(data.skills) || !Object.values(data.skills).every(object))) fail('invalid-skill-lock');
            return {file, data};
        });
        const tracked = locks.flatMap(({data}) => Object.entries(data?.skills || {})
            .filter(([, entry]) => entry.source === 'mattpocock/skills').map(([name]) => name));
        if (!tracked.every(nameOK)) fail('invalid-inventory');
        const inventory = unique([...known, ...historical, ...(manifest?.skills || []), ...tracked]);
        const checkDirs = dirs => dirs.forEach(dir => { directory(dir); owned(dir); });
        const preflight = names => {
            checkDirs(installDirs);
            for (const dir of installDirs) {
                for (const name of names) {
                    const target = path.join(dir, name);
                    if (stat(target)?.isSymbolicLink()) fail('linked-install-target');
                    if (stat(target)) copiedTree(target);
                }
            }
        };
        const cleanup = (names, dirs, extraPaths = []) => {
            checkDirs(dirs);
            const paths = dirs.flatMap(dir => names.map(name => path.join(dir, name))).concat(extraPaths);
            paths.forEach(removable);
            paths.forEach(remove);
            for (const {file, data} of locks) {
                if (!data) continue;
                let changed = false;
                for (const name of names) {
                    if (Object.hasOwn(data.skills, name)) { delete data.skills[name]; changed = true; }
                }
                if (changed) writeJson(file, data);
            }
        };
        if (mode === 'names') {
            process.stdout.write(inventory.join('\n') + '\n');
        } else if (['remove-pr-lens', 'remove-simple-english', 'remove-show-me'].includes(mode)) {
            const skill = mode.slice('remove-'.length);
            // Direct Markdown skills are also discoverable in Pi's own skills directory.
            cleanup([skill], allDirs, piDirs.map(dir => path.join(dir, 'skills', skill + '.md')));
            if (blocked === '1') fail('pi-profiles-blocked');
        } else if (mode === 'remove-matt' || mode === 'remove-obsolete') {
            cleanup(mode === 'remove-matt' ? unique([...inventory, ...obsolete]) : obsolete, allDirs);
            // Retain inventory for offline retries and custom profiles selected on a later run.
        } else if (mode === 'preflight') {
            // Known managed names fail early. The complete native selection, including
            // new upstream names, is checked again before promotion, never after it.
            preflight(inventory);
        } else if (mode === 'stage') {
            const tempRoot = fs.realpathSync(require('node:os').tmpdir());
            directory(tempRoot);
            process.stdout.write(fs.mkdtempSync(path.join(tempRoot, 'setup-matt-pocock-')) + '\n');
        } else if (mode === 'promote') {
            // Native --list cannot emit JSON. One isolated native install is both
            // discovery and the source snapshot: do not fetch/reselect during promotion.
            const stage = absolute(reportFile);
            directory(stage);
            owned(stage);
            if (!stat(stage)?.isDirectory() || (process.platform !== 'win32' && (stat(stage).mode & 0o077))) fail('unsafe-stage');
            if (path.dirname(stage) !== fs.realpathSync(require('node:os').tmpdir()) ||
                !/^setup-matt-pocock-[a-zA-Z0-9]+$/.test(path.basename(stage))) fail('unsafe-stage');
            const sourceDirs = [path.join(stage, '.claude/skills'), path.join(stage, '.agents/skills')];
            checkDirs(sourceDirs);
            const reportPath = path.join(stage, 'report.json');
            const reportStat = stat(reportPath);
            if (!reportStat?.isFile() || reportStat.isSymbolicLink() || reportStat.nlink !== 1) fail('invalid-install-report');
            owned(reportPath);
            let report;
            try { report = JSON.parse(fs.readFileSync(reportPath, 'utf8').replace(/^\uFEFF/, '')); }
            catch { fail('invalid-install-report'); }
            if (!Array.isArray(report) || report.length === 0) fail('invalid-install-report');
            const names = [];
            for (const entry of report) {
                if (!object(entry) || !nameOK(entry.name) || entry.status !== 'installed' || entry.source !== 'mattpocock/skills' ||
                    entry.scope !== 'global' || entry.mode !== 'copy' || !Array.isArray(entry.agents) ||
                    entry.agents.length !== 3 || !['Claude Code', 'Codex', 'Gemini CLI'].every(agent => entry.agents.includes(agent))) fail('invalid-install-report');
                if (names.includes(entry.name)) fail('invalid-install-report');
                names.push(entry.name);
                for (const dir of sourceDirs) {
                    const skill = path.join(dir, entry.name);
                    copiedTree(skill);
                    const md = stat(path.join(skill, 'SKILL.md'));
                    if (!md?.isFile() || md.size === 0) fail('invalid-skill-copy');
                }
            }
            // A validation floor, never an installation allowlist: newly discovered
            // skills are accepted too. Retired/renamed baseline skills need review.
            if (!known.every(name => names.includes(name))) fail('incomplete-suite');
            for (const dir of sourceDirs) {
                const entries = fs.readdirSync(dir);
                if (entries.length !== names.length || !entries.every(name => names.includes(name))) fail('invalid-install-report');
            }
            if (!names.every(name => sameTree(path.join(sourceDirs[0], name), path.join(sourceDirs[1], name)))) fail('invalid-skill-copy');
            const stageLock = jsonFile(path.join(stage, '.state/skills/.skill-lock.json'));
            if (!stageLock || stageLock.version !== 3 || !object(stageLock.skills) ||
                Object.keys(stageLock.skills).length !== names.length || !names.every(name => {
                    const entry = stageLock.skills[name];
                    return object(entry) && entry.source === 'mattpocock/skills' && entry.sourceType === 'github' &&
                        entry.sourceUrl === 'https://github.com/mattpocock/skills.git';
                })) fail('invalid-skill-lock');
            // All report, snapshot, metadata, and selected destinations must pass
            // before touching either real copy. Unrelated entries are never traversed.
            preflight(unique([...inventory, ...names]));
            for (const dir of installDirs) {
                directory(dir);
                fs.mkdirSync(dir, {recursive: true, mode: 0o700});
                for (const name of names) {
                    const source = path.join(sourceDirs[0], name), target = path.join(dir, name);
                    remove(target);
                    fs.cpSync(source, target, {recursive: true, dereference: false, errorOnExist: true, force: false});
                    copiedTree(target);
                    if (!sameTree(source, target)) fail('invalid-skill-copy');
                }
            }
            // Merge only this run's native records into the selected global lock;
            // retain unrelated entries, preferences, and the other legacy lock.
            const selectedLock = locks[locks.length - 1];
            const data = selectedLock.data || {version: 3, skills: {}};
            for (const name of names) {
                const entry = {...stageLock.skills[name]};
                if (data.skills[name]?.installedAt !== undefined) entry.installedAt = data.skills[name].installedAt;
                data.skills[name] = entry;
            }
            writeJson(selectedLock.file, data);
            writeJson(manifestFile, {version: 1, skills: unique([...inventory, ...names])});
        } else if (mode === 'ownership') {
            if (blocked !== '1') {
                checkDirs([shared, ...piDirs.flatMap(dir => [dir, path.join(dir, 'skills')])]);
                const settings = piDirs.map(dir => {
                    const file = path.join(dir, 'settings.json');
                    const data = jsonFile(file) || {};
                    if (data.skills !== undefined && (!Array.isArray(data.skills) || !data.skills.every(value => typeof value === 'string'))) fail('invalid-settings');
                    return {file, data};
                });
                const names = inventory;
                const duplicates = piDirs.flatMap(dir => names.map(name => ({file: path.join(dir, 'skills', name), canonical: path.join(shared, name)})));
                const equal = duplicates.filter(({file, canonical}) => sameTree(file, canonical));
                equal.forEach(({file}) => removable(file));
                equal.forEach(({file}) => remove(file));
                const excluded = ['pi-goal-writer', 'autoresearch-create', 'autoresearch-finalize', 'autoresearch-hooks']
                    .map(name => '!' + path.join(shared, name) + '/**')
                    .concat(duplicates.map(({file}) => '!' + file + '/**'));
                for (const {file, data} of settings) {
                    const before = JSON.stringify(data);
                    data.skills = unique([...(data.skills || []), ...excluded]);
                    if (JSON.stringify(data) !== before) writeJson(file, data);
                }
            }
        } else fail('unknown-operation');
    } catch (error) {
        const allowed = ['unsafe-path', 'linked-directory', 'not-directory', 'wrong-owner', 'unsafe-metadata', 'malformed-metadata',
            'unsupported-file', 'removal-failed', 'invalid-skill-copy', 'invalid-inventory', 'invalid-skill-lock',
            'pi-profiles-blocked', 'linked-install-target', 'invalid-install-report', 'incomplete-suite', 'invalid-settings', 'unsafe-stage', 'unknown-operation'];
        const reason = allowed.includes(error.message) ? error.message : ['EACCES', 'EPERM', 'ENOENT', 'ENOSPC', 'EROFS', 'EBUSY'].includes(error.code) ? error.code : 'operation-failed';
        process.stderr.write('Managed skills: ' + reason + '.\n');
        process.exitCode = 1;
    }
'@
    $nodeOptions = $env:NODE_OPTIONS
    $nodePath = $env:NODE_PATH
    $blocked = if ($script:PiProfileMutationsBlocked) { '1' } else { '0' }
    try {
        $env:NODE_OPTIONS = $null
        $env:NODE_PATH = $null
        $global:LASTEXITCODE = 0
        $result = $helper | & node --input-type=commonjs - $env:USERPROFILE "$env:PI_CODING_AGENT_DIR" $blocked $Mode $ReportFile 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Managed skill policy failed ($Mode). Review profile paths, skill files, and metadata."
            return $false
        }
        if ($Mode -eq 'names') { return @($result) }
        if ($Mode -eq 'stage') { return [string]$result }
        return $true
    }
    catch {
        Write-Warning "Managed skill policy could not run."
        return $false
    }
    finally {
        $env:NODE_OPTIONS = $nodeOptions
        $env:NODE_PATH = $nodePath
    }
}

function Remove-MattPocockSkills {
    return (Invoke-MattPocockSkillPolicy -Mode remove-matt)
}

function Setup-MattPocockSkills {
    if (Test-MattPocockSkillsDisabled) { return (Remove-MattPocockSkills) }
    if (-not (Enable-SkillsCliNodeRuntime)) {
        Write-Warning "Cannot install Matt Pocock skills because the skills CLI runtime is not ready."
        return $false
    }
    if (-not (Get-Command npx -ErrorAction SilentlyContinue)) {
        Write-Warning "npx is not available; cannot install Matt Pocock skills."
        return $false
    }
    if (-not (Invoke-MattPocockSkillPolicy -Mode preflight)) { return $false }
    $stage = $null
    $success = $false
    $savedEnvironment = [System.Collections.Generic.Dictionary[string,object]]::new([System.StringComparer]::Ordinal)
    try {
        $global:LASTEXITCODE = 0
        $npmUserConfig = & npm config get userconfig 2>$null
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($npmUserConfig)) { throw 'npm-config' }
        $npmGlobalConfig = & npm config get globalconfig 2>$null
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($npmGlobalConfig)) { throw 'npm-config' }
        $stage = Invoke-MattPocockSkillPolicy -Mode stage
        if (-not ($stage -is [string]) -or [string]::IsNullOrWhiteSpace($stage)) { $stage = $null; return $false }
        $isolatedEnvironment = @{
            HOME = $stage; USERPROFILE = $stage
            CLAUDE_CONFIG_DIR = (Join-Path $stage '.claude'); CODEX_HOME = (Join-Path $stage '.codex')
            PI_CODING_AGENT_DIR = (Join-Path $stage '.pi/agent'); XDG_STATE_HOME = (Join-Path $stage '.state')
            XDG_CONFIG_HOME = (Join-Path $stage '.config'); XDG_CACHE_HOME = (Join-Path $stage '.cache')
            XDG_DATA_HOME = (Join-Path $stage '.local/share')
            npm_config_userconfig = [string]$npmUserConfig; npm_config_globalconfig = [string]$npmGlobalConfig
        }
        if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
            foreach ($key in @('NPM_CONFIG_USERCONFIG', 'NPM_CONFIG_GLOBALCONFIG')) {
                $savedEnvironment[$key] = [Environment]::GetEnvironmentVariable($key)
                [Environment]::SetEnvironmentVariable($key, [NullString]::Value)
            }
        }
        foreach ($key in $isolatedEnvironment.Keys) {
            $savedEnvironment[$key] = [Environment]::GetEnvironmentVariable($key)
            [Environment]::SetEnvironmentVariable($key, $isolatedEnvironment[$key])
        }
        Write-Message "Installing/updating the full Matt Pocock skill suite for Claude Code, Codex, Gemini CLI, and Pi..."
        $npxArgs = @(
            "--yes", "skills@latest", "add", "mattpocock/skills", "--global",
            "--agent", "claude-code", "--agent", "codex", "--agent", "gemini-cli",
            "--skill", "*", "--full-depth", "--copy", "--yes", "--json"
        )
        $global:LASTEXITCODE = 0
        $output = & npx @npxArgs 2>$null
        $installExitCode = $LASTEXITCODE
        foreach ($key in $savedEnvironment.Keys) {
            if ($null -eq $savedEnvironment[$key]) { [Environment]::SetEnvironmentVariable($key, [NullString]::Value) }
            else { [Environment]::SetEnvironmentVariable($key, $savedEnvironment[$key]) }
        }
        $savedEnvironment.Clear()
        if ($installExitCode -ne 0) {
            Write-Warning "Failed to install the full Matt Pocock skill suite."
            return $false
        }
        [System.IO.File]::WriteAllText((Join-Path $stage 'report.json'), ($output -join "`n"))
        if (-not (Invoke-MattPocockSkillPolicy -Mode promote -ReportFile $stage)) { return $false }
        if (-not (Invoke-MattPocockSkillPolicy -Mode remove-obsolete)) { return $false }
        $success = $true
    }
    catch {
        Write-Warning "Full Matt Pocock skill setup failed."
        return $false
    }
    finally {
        foreach ($key in $savedEnvironment.Keys) {
            if ($null -eq $savedEnvironment[$key]) { [Environment]::SetEnvironmentVariable($key, [NullString]::Value) }
            else { [Environment]::SetEnvironmentVariable($key, $savedEnvironment[$key]) }
        }
        if ($stage -and -not (Invoke-MattPocockSkillPolicy -Mode dispose -ReportFile $stage)) { $success = $false }
    }
    if ($success) { Write-Success "Full Matt Pocock skill suite installed/updated through copied global skills." }
    return $success
}


function Test-PathWithin {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Root
    )

    try {
        $trimCharacters = [char[]]@([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
        $canonicalRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd($trimCharacters)
        $canonicalPath = [System.IO.Path]::GetFullPath($Path)
        return $canonicalPath.StartsWith("${canonicalRoot}$([System.IO.Path]::DirectorySeparatorChar)", [System.StringComparison]::OrdinalIgnoreCase)
    }
    catch {
        return $false
    }
}

function Test-SafeProfileDirectory {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$ProfileRoot
    )

    if (-not (Test-PathWithin -Path $Path -Root $ProfileRoot)) {
        return $false
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        return $true
    }

    try {
        $canonicalRoot = [System.IO.Path]::GetFullPath($ProfileRoot).TrimEnd([char[]]@([char]92, [char]47))
        $canonicalPath = [System.IO.Path]::GetFullPath($Path)
        $relativePath = $canonicalPath.Substring($canonicalRoot.Length).TrimStart([char[]]@([char]92, [char]47))
        $currentPath = $canonicalRoot
        foreach ($segment in ($relativePath -split '[\\/]')) {
            if ([string]::IsNullOrWhiteSpace($segment)) {
                continue
            }
            $currentPath = Join-Path $currentPath $segment
            $item = Get-Item -LiteralPath $currentPath -Force -ErrorAction Stop
            if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                return $false
            }
        }
        return $true
    }
    catch {
        return $false
    }
}

function Remove-PiCompoundSettings {
    param([Parameter(Mandatory=$true)][string]$AgentDir)

    $settingsPath = Join-Path $AgentDir "settings.json"
    if (-not (Test-Path -LiteralPath $settingsPath -PathType Leaf)) {
        return $false
    }

    try {
        $settingsItem = Get-Item -LiteralPath $settingsPath -Force -ErrorAction Stop
        if ($settingsItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            Write-Warning "Skipping Compound Engineering settings cleanup in symlinked $settingsPath."
            return $false
        }
        $settingsJson = Get-Content -LiteralPath $settingsPath -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($settingsJson)) {
            return $false
        }
        $settings = $settingsJson | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Write-Warning "Failed to parse Pi settings at $settingsPath; leaving it unchanged."
        return $false
    }

    if ($null -eq $settings -or -not $settings.PSObject.Properties["packages"] -or $settings.packages -is [string] -or $settings.packages -isnot [System.Collections.IEnumerable]) {
        return $false
    }

    $filteredPackages = @()
    $changed = $false
    foreach ($package in @($settings.packages)) {
        $source = if ($package -is [string]) { $package } elseif ($null -ne $package -and $package.PSObject.Properties["source"]) { [string]$package.source } else { "" }
        $normalizedSource = $source.ToLowerInvariant()
        if ($normalizedSource -in @("npm:@every-env/compound-plugin", "npm:@every-env/compound-engineering-plugin", "https://github.com/everyinc/compound-engineering-plugin.git")) {
            $changed = $true
        }
        else {
            $filteredPackages += $package
        }
    }

    if (-not $changed) {
        return $false
    }

    if ($filteredPackages.Count -eq 0) {
        Remove-JsonProperty -Object $settings -Name "packages"
    }
    else {
        Set-JsonProperty -Object $settings -Name "packages" -Value ([object[]]$filteredPackages)
    }

    try {
        $settings | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $settingsPath -Encoding UTF8 -ErrorAction Stop
        return $true
    }
    catch {
        Write-Warning "Failed to write Pi settings after Compound Engineering cleanup at $settingsPath."
        return $false
    }
}

function Get-CompoundSkillLinkTarget {
    param([Parameter(Mandatory=$true)][string]$Path)

    try {
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if (-not ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
            return $null
        }
        $target = $item.Target
        if ($target -is [System.Array]) {
            $target = $target | Select-Object -First 1
        }
        if ([string]::IsNullOrWhiteSpace([string]$target)) {
            return $null
        }
        if (-not [System.IO.Path]::IsPathRooted($target)) {
            $target = Join-Path $item.DirectoryName $target
        }
        return [System.IO.Path]::GetFullPath($target)
    }
    catch {
        return $null
    }
}

function Remove-CompoundEngineeringResources {
    $profileRoot = [System.IO.Path]::GetFullPath($env:USERPROFILE)
    $defaultAgentDir = Join-Path $profileRoot ".pi\agent"
    $agentDirs = @()
    $compoundSkillPattern = '^(ce-agent-native-architecture|ce-agent-native-audit|ce-brainstorm|ce-clean-gone-branches|ce-code-review|ce-commit|ce-commit-push-pr|ce-compound|ce-compound-refresh|ce-debug|ce-demo-reel|ce-dhh-rails-style|ce-doc-review|ce-frontend-design|ce-gemini-imagegen|ce-ideate|ce-optimize|ce-plan|ce-polish-beta|ce-product-pulse|ce-proof|ce-release-notes|ce-report-bug|ce-resolve-pr-feedback|ce-riffrec-feedback-analysis|ce-sessions|ce-setup|ce-simplify-code|ce-slack-research|ce-strategy|ce-test-browser|ce-test-xcode|ce-work|ce-work-beta|ce-worktree|lfg)$'
    $compoundAgentPattern = '^(ce-adversarial-document-reviewer|ce-adversarial-reviewer|ce-agent-native-reviewer|ce-ankane-readme-writer|ce-api-contract-reviewer|ce-architecture-strategist|ce-best-practices-researcher|ce-code-simplicity-reviewer|ce-coherence-reviewer|ce-correctness-reviewer|ce-data-integrity-guardian|ce-data-migration-expert|ce-data-migrations-reviewer|ce-deployment-verification-agent|ce-design-implementation-reviewer|ce-design-iterator|ce-design-lens-reviewer|ce-dhh-rails-reviewer|ce-feasibility-reviewer|ce-figma-design-sync|ce-framework-docs-researcher|ce-git-history-analyzer|ce-issue-intelligence-analyst|ce-julik-frontend-races-reviewer|ce-kieran-python-reviewer|ce-kieran-rails-reviewer|ce-kieran-typescript-reviewer|ce-learnings-researcher|ce-maintainability-reviewer|ce-pattern-recognition-specialist|ce-performance-oracle|ce-performance-reviewer|ce-pr-comment-resolver|ce-previous-comments-reviewer|ce-product-lens-reviewer|ce-project-standards-reviewer|ce-reliability-reviewer|ce-repo-research-analyst|ce-schema-drift-detector|ce-scope-guardian-reviewer|ce-security-lens-reviewer|ce-security-reviewer|ce-security-sentinel|ce-session-historian|ce-slack-researcher|ce-spec-flow-analyzer|ce-swift-ios-reviewer|ce-testing-reviewer|ce-web-researcher)$'
    $compoundRepo = Join-Path $profileRoot ".local\share\compound-engineering-plugin"
    $sharedSkillsDir = Join-Path $profileRoot ".agents\skills"
    $removed = $false
    $failed = @()

    foreach ($candidate in @($defaultAgentDir, $env:PI_CODING_AGENT_DIR)) {
        if ($script:PiProfileMutationsBlocked) { break }
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            continue
        }
        try {
            $agentDir = [System.IO.Path]::GetFullPath($candidate)
            if ($agentDirs -contains $agentDir -or -not (Test-Path -LiteralPath $agentDir -PathType Container)) {
                continue
            }
            if (Test-SafeProfileDirectory -Path $agentDir -ProfileRoot $profileRoot) {
                $agentDirs += $agentDir
            }
            else {
                Write-Debug "Skipping Pi cleanup through a reparse point or outside the Windows user profile: $agentDir"
            }
        }
        catch {
            Write-Warning "Could not safely resolve PI_CODING_AGENT_DIR; leaving it unchanged."
        }
    }

    if ((Test-Path -LiteralPath $sharedSkillsDir -PathType Container) -and (Test-SafeProfileDirectory -Path $sharedSkillsDir -ProfileRoot $profileRoot) -and (Test-SafeProfileDirectory -Path $compoundRepo -ProfileRoot $profileRoot)) {
        try {
            $canonicalRepo = [System.IO.Path]::GetFullPath($compoundRepo).TrimEnd([char[]]@([char]92, [char]47))
            foreach ($skill in Get-ChildItem -LiteralPath $sharedSkillsDir -Force -ErrorAction Stop) {
                $target = Get-CompoundSkillLinkTarget -Path $skill.FullName
                if ($null -ne $target -and (Test-PathWithin -Path $target -Root $canonicalRepo)) {
                    try {
                        Remove-Item -LiteralPath $skill.FullName -Force -ErrorAction Stop
                        $removed = $true
                    }
                    catch {
                        $failed += $skill.FullName
                    }
                }
            }
        }
        catch {
            Write-Warning "Could not safely inspect shared skills for Compound Engineering links."
        }
    }

    foreach ($agentDir in $agentDirs) {
        if (Remove-PiCompoundSettings -AgentDir $agentDir) {
            $removed = $true
        }

        foreach ($entry in @(@{ Name = "extensions"; Pattern = '^compound-engineering' }, @{ Name = "skills"; Pattern = $compoundSkillPattern }, @{ Name = "agents"; Pattern = $compoundAgentPattern })) {
            $resourceDir = Join-Path $agentDir $entry.Name
            if (-not (Test-Path -LiteralPath $resourceDir -PathType Container) -or -not (Test-SafeProfileDirectory -Path $resourceDir -ProfileRoot $profileRoot)) {
                continue
            }
            foreach ($resource in Get-ChildItem -LiteralPath $resourceDir -Force -ErrorAction SilentlyContinue) {
                if ($entry.Name -eq "agents") {
                    if ($resource.PSIsContainer -or ($resource.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
                        $resourceName = $resource.Name
                    }
                    elseif ($resource.Extension -eq ".md") {
                        $resourceName = [System.IO.Path]::GetFileNameWithoutExtension($resource.Name)
                    }
                    else {
                        continue
                    }
                }
                else {
                    $resourceName = $resource.Name
                }
                if ($resourceName -notmatch $entry.Pattern) {
                    continue
                }
                if ($entry.Name -eq "skills" -and -not ($resource.PSIsContainer -or ($resource.Attributes -band [System.IO.FileAttributes]::ReparsePoint))) {
                    continue
                }
                try {
                    Remove-Item -LiteralPath $resource.FullName -Recurse -Force -ErrorAction Stop
                    $removed = $true
                }
                catch {
                    $failed += $resource.FullName
                }
            }
        }

        $manifestDir = Join-Path $agentDir "compound-engineering"
        if (Test-Path -LiteralPath $manifestDir) {
            try {
                $manifestItem = Get-Item -LiteralPath $manifestDir -Force -ErrorAction Stop
                if ($manifestItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                    Remove-Item -LiteralPath $manifestDir -Force -ErrorAction Stop
                    $removed = $true
                }
                elseif ($manifestItem.PSIsContainer -and (Test-SafeProfileDirectory -Path $manifestDir -ProfileRoot $profileRoot)) {
                    Remove-Item -LiteralPath $manifestDir -Recurse -Force -ErrorAction Stop
                    $removed = $true
                }
                elseif (-not $manifestItem.PSIsContainer) {
                    Remove-Item -LiteralPath $manifestDir -Force -ErrorAction Stop
                    $removed = $true
                }
                else {
                    Write-Warning "Skipping Compound Engineering manifest cleanup through a reparse point or outside the Windows user profile: $manifestDir"
                }
            }
            catch {
                $failed += $manifestDir
            }
        }

        $agentsPath = Join-Path $agentDir "AGENTS.md"
        if (Test-Path -LiteralPath $agentsPath -PathType Leaf) {
            try {
                $agentsItem = Get-Item -LiteralPath $agentsPath -Force -ErrorAction Stop
                if ($agentsItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                    Write-Warning "Skipping Compound Engineering block cleanup in symlinked $agentsPath."
                    continue
                }
                $lines = @(Get-Content -LiteralPath $agentsPath -ErrorAction Stop)
                $beginMarker = "<!-- BEGIN COMPOUND PI TOOL MAP -->"
                $endMarker = "<!-- END COMPOUND PI TOOL MAP -->"
                $beginIndexes = @($lines | ForEach-Object -Begin { $index = 0 } -Process { $current = $index; $index++; if ($_ -ceq $beginMarker) { $current } })
                $endIndexes = @($lines | ForEach-Object -Begin { $index = 0 } -Process { $current = $index; $index++; if ($_ -ceq $endMarker) { $current } })
                if ($beginIndexes.Count -eq 1 -and $endIndexes.Count -eq 1) {
                    if ($beginIndexes[0] -gt $endIndexes[0]) {
                        Write-Warning "Compound Engineering markers are malformed in $agentsPath; leaving it unchanged."
                    }
                    else {
                        $updatedLines = for ($index = 0; $index -lt $lines.Count; $index++) {
                            if ($index -lt $beginIndexes[0] -or $index -gt $endIndexes[0]) {
                                $lines[$index]
                            }
                        }
                        Set-Content -LiteralPath $agentsPath -Value $updatedLines -Encoding UTF8 -ErrorAction Stop
                        $removed = $true
                    }
                }
                elseif ($beginIndexes.Count -ne 0 -or $endIndexes.Count -ne 0) {
                    Write-Warning "Compound Engineering markers are malformed in $agentsPath; leaving it unchanged."
                }
            }
            catch {
                Write-Warning "Failed to safely remove the Compound Engineering block from $agentsPath."
            }
        }
    }

    if (Test-Path -LiteralPath $compoundRepo) {
        try {
            $repoItem = Get-Item -LiteralPath $compoundRepo -Force -ErrorAction Stop
            if ($repoItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                Remove-Item -LiteralPath $compoundRepo -Force -ErrorAction Stop
                $removed = $true
            }
            elseif (Test-SafeProfileDirectory -Path $compoundRepo -ProfileRoot $profileRoot) {
                Remove-Item -LiteralPath $compoundRepo -Recurse -Force -ErrorAction Stop
                $removed = $true
            }
            else {
                Write-Warning "Skipping Compound Engineering checkout cleanup through a reparse point or outside the Windows user profile: $compoundRepo"
            }
        }
        catch {
            $failed += $compoundRepo
        }
    }

    if ($failed.Count -gt 0) {
        Write-Warning "Failed to remove legacy Compound Engineering resources: $($failed -join ', ')"
    }
    elseif ($removed) {
        Write-Success "Legacy Compound Engineering resources removed."
    }
    else {
        Write-Debug "No legacy Compound Engineering resources found."
    }
}

function Install-WingetPackages {
    Write-Host "$arrow Checking for missing winget packages..." -ForegroundColor Cyan

    $installedPackages = @()
    try {
        $tempFile = [System.IO.Path]::GetTempFileName()
        $null = winget export -o $tempFile --accept-source-agreements 2>&1
        
        if (Test-Path $tempFile) {
            $jsonContent = Get-Content $tempFile -Raw | ConvertFrom-Json
            $installedPackages = $jsonContent.Sources.Packages | ForEach-Object { $_.PackageIdentifier }
            Remove-Item $tempFile -Force
            
            Write-Host "$success Found $($installedPackages.Count) installed packages." -ForegroundColor Green
        }
    }
    catch {
        Write-Host "$warnIcon Could not get list of installed packages: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "$arrow Will check each package individually..." -ForegroundColor Cyan
    }

    foreach ($package in $wingetPackages) {
        if ($package -eq "Notion.ntn" -and $env:PROCESSOR_ARCHITECTURE -ne "AMD64") {
            Write-Warning "Notion CLI supports Windows x64 only; skipping on $env:PROCESSOR_ARCHITECTURE."
            continue
        }

        $isInstalled = $false
        
        if ($installedPackages -contains $package) {
            $isInstalled = $true
        }
        else {
            $searchResult = winget list --id $package --exact --accept-source-agreements
            $isInstalled = $searchResult -like "*$package*"
        }

        if (-not $isInstalled) {
            Write-Host "$arrow Installing $package..." -ForegroundColor Cyan
            winget install -e --id $package --silent --accept-package-agreements --accept-source-agreements
            if ($?) {
                Write-Host "$success $package installed." -ForegroundColor Green
            } else {
                Write-Host "$failIcon Failed to install $package." -ForegroundColor Red
            }
        }
    }
}

function Install-WingetUpdates {
    winget list --id AnomalyCo.OpenCode --exact --accept-source-agreements --disable-interactivity 2>$null | Out-Null
    if ($LASTEXITCODE -ne -1978335212) {
        $script:OpenCodeWingetConflict = $true
        Write-Warning 'Deferring blanket WinGet upgrades: OpenCode absence is unverified. Review the existing registration/pins; unrelated setup continues.'
        return
    }
    Write-Host "$arrow Checking for available WinGet updates..." -ForegroundColor Cyan
    gsudo winget upgrade --all
    if ($?) {
        Write-Host "$success WinGet updates installed." -ForegroundColor Green
    }
    else {
        Write-Host "$failIcon Error installing WinGet updates" -ForegroundColor Yellow
    }
}

function Install-WindowsUpdates {
    Write-Host "$arrow Installing Windows updates..." -ForegroundColor Cyan
    gsudo {
        Install-Module -Name PSWindowsUpdate;
        Import-Module PSWindowsUpdate;
        Get-WindowsUpdate;
        Install-WindowsUpdate -AcceptAll
    }
}

function Test-PendingReboot {
    $reasons = @()
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') {
        $reasons += 'Component Based Servicing'
    }
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') {
        $reasons += 'Windows Update'
    }
    $pendingRename = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name 'PendingFileRenameOperations' -ErrorAction SilentlyContinue
    if ($null -ne $pendingRename -and $null -ne $pendingRename.PendingFileRenameOperations) {
        $reasons += 'pending file rename operations'
    }
    if ($reasons.Count -gt 0) {
        Write-Warning "Machine reboot pending ($($reasons -join ', ')). Restart this PC for applied updates to take effect."
    }
    else {
        Write-Debug "No reboot pending."
    }
}

function Setup-CodeDirectory {
    $codeDir = "$env:USERPROFILE\Code"

    Write-Host "$arrow Setting up ~/Code directory..." -ForegroundColor Cyan

    if (-not (Test-Path $codeDir)) {
        New-Item -ItemType Directory -Force -Path $codeDir | Out-Null
        Write-Host "$success Created ~/Code directory." -ForegroundColor Green
    }
    else {
        Write-Debug "~/Code directory already exists."
    }
}

function Set-WindowsTerminalConfiguration {
    Write-Host "$arrow Configuring Windows Terminal settings..." -ForegroundColor Cyan
    $settingsPath = "$env:LocalAppData\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
    $settings = Get-Content -Path $settingsPath | ConvertFrom-Json
    if (-not $settings.profiles) {
        $settings | Add-Member -MemberType NoteProperty -Name profiles -Value @{}
    }
    if (-not $settings.profiles.defaults) {
        $settings.profiles | Add-Member -MemberType NoteProperty -Name defaults -Value @{}
    }
    if (-not $settings.profiles.defaults.font) {
        $settings.profiles.defaults | Add-Member -MemberType NoteProperty -Name font -Value @{}
    }

    $settings.profiles.defaults.font.face = "JetBrainsMono Nerd Font Mono"

    $settings | ConvertTo-Json -Depth 10 | Set-Content -Path $settingsPath
    Write-Host "$success Windows Terminal settings updated." -ForegroundColor Green
}



function Get-SetupLogDirectory {
    return [IO.Path]::GetFullPath((Join-Path $env:USERPROFILE '.local\log\machine-setup'))
}

function Assert-SetupLogPath {
    param([string]$Path, [switch]$AllowMissing)
    $directory = Get-SetupLogDirectory
    $fullPath = [IO.Path]::GetFullPath($Path)
    if ($fullPath -ne $directory -and
        ([IO.Path]::GetDirectoryName($fullPath) -ne $directory -or
         [IO.Path]::GetFileName($fullPath) -cnotmatch '^\d{4}-\d{2}-\d{2}-\d{6}-[0-9a-f]{32}\.log(?:\.upload\.json)?$')) {
        throw 'Unmanaged setup log path'
    }
    $cursor = $fullPath
    while ($cursor) {
        try {
            $attributes = [IO.File]::GetAttributes($cursor)
            if ($attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Linked setup log path' }
            $isDirectory = [bool]($attributes -band [IO.FileAttributes]::Directory)
            if (($cursor -ne $fullPath -or $fullPath -eq $directory) -ne $isDirectory) {
                throw 'Unexpected setup log path type'
            }
        }
        catch {
            $cause = $_.Exception.GetBaseException()
            if (-not $AllowMissing -or
                ($cause -isnot [IO.FileNotFoundException] -and $cause -isnot [IO.DirectoryNotFoundException])) { throw }
        }
        $cursor = [IO.Path]::GetDirectoryName($cursor)
    }
}

function New-SetupLogHttpClient {
    Add-Type -AssemblyName System.Net.Http
    $handler = [Net.Http.HttpClientHandler]::new()
    $handler.AllowAutoRedirect = $false
    return [Net.Http.HttpClient]::new($handler)
}

function Send-SetupLogRequest {
    param([string]$LogPath, [string]$Hostname, [ValidateRange(1, 30)][int]$TimeoutSeconds)
    $file = $client = $request = $response = $null
    $originalProtocol = [Net.ServicePointManager]::SecurityProtocol
    try {
        Assert-SetupLogPath $LogPath
        $file = [IO.File]::Open($LogPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        $client = New-SetupLogHttpClient
        $client.Timeout = [TimeSpan]::FromSeconds($TimeoutSeconds)
        if ($PSVersionTable.PSVersion.Major -le 5 -and [int]$originalProtocol -ne 0) {
            [Net.ServicePointManager]::SecurityProtocol = $originalProtocol -bor [Net.SecurityProtocolType]::Tls12
        }
        $uri = 'https://logs.scowalt.com/upload?hostname=' + [Uri]::EscapeDataString($Hostname)
        $request = [Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::Post, $uri)
        $request.Content = [Net.Http.MultipartFormDataContent]::new()
        $request.Content.Add([Net.Http.StreamContent]::new($file), 'file', [IO.Path]::GetFileName($LogPath))
        $response = $client.SendAsync($request, [Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
        return [int]$response.StatusCode
    }
    finally {
        if ($response) { $response.Dispose() }
        if ($request) { $request.Dispose() }
        if ($client) { $client.Dispose() }
        if ($file) { $file.Dispose() }
        [Net.ServicePointManager]::SecurityProtocol = $originalProtocol
    }
}

function Get-SetupLogFailureCategory {
    param([Exception]$Exception)
    $category = 'local-file-or-client-error'
    for ($cause = $Exception; $null -ne $cause; $cause = $cause.InnerException) {
        if ($cause -is [Security.Authentication.AuthenticationException]) { return 'tls-validation' }
        if ($cause -is [OperationCanceledException] -or $cause -is [TimeoutException]) { $category = 'timeout' }
        elseif ($cause.GetType().FullName -eq 'System.Net.Http.HttpRequestException' -and $category -ne 'timeout') { $category = 'network' }
        if ($cause -is [Net.WebException]) {
            if ($cause.Status -in @([Net.WebExceptionStatus]::TrustFailure, [Net.WebExceptionStatus]::SecureChannelFailure)) {
                return 'tls-validation'
            }
            if ($cause.Status -eq [Net.WebExceptionStatus]::Timeout) { $category = 'timeout' }
            elseif ($cause.Status -in @([Net.WebExceptionStatus]::ConnectFailure, [Net.WebExceptionStatus]::NameResolutionFailure,
                [Net.WebExceptionStatus]::ProxyNameResolutionFailure, [Net.WebExceptionStatus]::ConnectionClosed,
                [Net.WebExceptionStatus]::ReceiveFailure, [Net.WebExceptionStatus]::SendFailure, [Net.WebExceptionStatus]::KeepAliveFailure)) {
                if ($category -ne 'timeout') { $category = 'network' }
            }
        }
    }
    return $category
}

function Read-SetupLogUploadState {
    param([IO.FileStream]$Stream)
    if ($Stream.Length -eq 0 -or $Stream.Length -gt 4096) { throw 'Invalid upload state size' }
    $Stream.Position = 0
    $reader = [IO.StreamReader]::new($Stream, [Text.Encoding]::UTF8, $true, 1024, $true)
    try { $state = $reader.ReadToEnd() | ConvertFrom-Json -ErrorAction Stop }
    finally { $reader.Dispose() }
    if ($state -isnot [pscustomobject] -or
        ($state.schema -isnot [int] -and $state.schema -isnot [long]) -or $state.schema -ne 1 -or
        $state.state -isnot [string] -or $state.state -notin @('pending', 'uploaded') -or
        $state.hostname -isnot [string] -or $state.hostname -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,62}$') {
        throw 'Invalid upload state'
    }
    foreach ($property in $state.PSObject.Properties.Name) {
        if ($property -notin @('schema', 'state', 'hostname', 'attempts', 'reason', 'statusCode', 'updatedUtc')) {
            throw 'Unrecognized upload state'
        }
    }
    return $state
}

function Write-SetupLogUploadState {
    param([IO.FileStream]$Stream, [string]$Hostname, [string]$State, [int]$Attempts, [string]$Reason, [int]$StatusCode)
    $record = [ordered]@{
        schema = 1; state = $State; hostname = $Hostname; attempts = $Attempts
        reason = $Reason; statusCode = $StatusCode; updatedUtc = [DateTime]::UtcNow.ToString('o')
    }
    $bytes = [Text.Encoding]::UTF8.GetBytes(($record | ConvertTo-Json -Compress))
    $Stream.Position = 0
    $Stream.SetLength(0)
    $Stream.Write($bytes, 0, $bytes.Length)
    $Stream.Flush($true)
}

function Upload-Log {
    param([string]$LogPath = $script:SetupLogFile, [switch]$Recovery, [ValidateRange(1, 96)][int]$MaxDurationSeconds = 96)
    if (-not $LogPath) { return }
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $stateStream = $null
    try {
        if ($script:SetupTranscriptStarted -and $LogPath -eq $script:SetupLogFile) { throw 'Transcript still active' }
        Assert-SetupLogPath $LogPath
        $statePath = "$LogPath.upload.json"
        Assert-SetupLogPath $statePath -AllowMissing:(-not $Recovery)
        $existing = [IO.File]::Exists($statePath)
        $mode = if ($existing -or $Recovery) { [IO.FileMode]::Open } else { [IO.FileMode]::CreateNew }
        $stateStream = [IO.File]::Open($statePath, $mode, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        if ($existing -or $Recovery) {
            $state = Read-SetupLogUploadState $stateStream
            if ($state.state -eq 'uploaded') { return }
            $hostname = $state.hostname
        }
        else {
            $hostname = $env:COMPUTERNAME
            if (-not $hostname) { $hostname = [Environment]::MachineName }
            if ($hostname -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,62}$') { throw 'Invalid hostname' }
            Write-SetupLogUploadState $stateStream $hostname 'pending' 0 'not-attempted' 0
        }
        for ($attempt = 1; $attempt -le 3; $attempt++) {
            $remaining = [int][Math]::Floor($MaxDurationSeconds - $watch.Elapsed.TotalSeconds)
            if ($remaining -lt 1) { break }
            $status = 0
            $reason = 'local-file-or-client-error'
            $retryable = $false
            try {
                Write-Debug "Uploading setup log (attempt $attempt/3; PowerShell $($PSVersionTable.PSVersion))..."
                $status = Send-SetupLogRequest $LogPath $hostname ([Math]::Min(30, $remaining))
                if ($status -ge 200 -and $status -lt 300) {
                    Write-SetupLogUploadState $stateStream $hostname 'uploaded' $attempt 'uploaded' $status
                    Write-Debug "Setup log uploaded. Local log remains at $LogPath."
                    return
                }
                $reason = "http-$status"
                $retryable = $status -in @(408, 429) -or ($status -ge 500 -and $status -le 599)
            }
            catch {
                $reason = Get-SetupLogFailureCategory $_.Exception
                $retryable = $reason -in @('network', 'timeout')
            }
            Write-SetupLogUploadState $stateStream $hostname 'pending' $attempt $reason $status
            Write-Warning "Setup log upload failed ($reason; attempt $attempt/3)."
            if (-not $retryable -or $attempt -eq 3) { break }
            $delay = 2 * $attempt
            if ($watch.Elapsed.TotalSeconds + $delay + 1 -ge $MaxDurationSeconds) { break }
            Start-Sleep -Seconds $delay
        }
        Write-Warning "Failed to upload setup log. Local log remains at $LogPath."
        Write-Warning "Upload status: $statePath. A later setup run will retry this pending log."
    }
    catch {
        Write-Warning "Setup log upload deferred (local-file-or-metadata). Local log remains at $LogPath."
        Write-Warning 'Check log permissions, linked paths, and upload state files. No unsafe file was replaced.'
    }
    finally {
        if ($stateStream) { $stateStream.Dispose() }
    }
}

function Invoke-PendingSetupLogUploads {
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $count = 0
    try {
        $directory = Get-SetupLogDirectory
        Assert-SetupLogPath $directory
        foreach ($path in [IO.Directory]::EnumerateFiles($directory, '*.log.upload.json')) {
            $remaining = [int][Math]::Floor(60 - $watch.Elapsed.TotalSeconds)
            if ($count -ge 3 -or $remaining -lt 1) { break }
            $stream = $null
            try {
                Assert-SetupLogPath $path
                $stream = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
                $state = Read-SetupLogUploadState $stream
            }
            catch { continue }  
            finally { if ($stream) { $stream.Dispose() } }
            if ($state.state -ne 'pending') { continue }
            $count++
            $logPath = $path.Substring(0, $path.Length - '.upload.json'.Length)
            Upload-Log -LogPath $logPath -Recovery -MaxDurationSeconds $remaining
        }
    }
    catch { Write-Warning 'Pending setup logs could not be inspected. Local files were preserved.' }
}

function Complete-SetupLog {
    if (-not $script:SetupLogFile) { return }
    Write-Host "Run log saved to: $script:SetupLogFile" -ForegroundColor DarkGray
    if ($script:SetupTranscriptStarted) {
        try {
            Stop-Transcript -ErrorAction Stop | Out-Null
            $script:SetupTranscriptStarted = $false
            $script:SetupLogClosed = $true
        }
        catch {
            Write-Warning 'Setup transcript could not close. Upload skipped to avoid sending an incomplete or active log.'
            return
        }
    }
    if ($script:SetupLogClosed) { Upload-Log }
}

function Install-BbDesktop {
    if (Test-EnvLocalFlag "HEADLESS") {
        Write-Debug "Skipping bb desktop: HEADLESS=1; existing applications untouched."
    }
    else {
        Write-Debug "Skipping bb desktop: Windows has no supported native desktop artifact."
    }
    return $true
}

function Invoke-WindowsSetupTasks {
    $piSetupFailed = $false
    $bbDesktopSetupFailed = $false
    $openCodeSetupFailed = $false
    $script:OpenCodeWingetConflict = $false
    $piOpenCodeGoReady = $false
    $script:PiProfileMutationsBlocked = $false
    $mattPocockSetupFailed = $false
    $impeccableSetupFailed = $false
    $simpleEnglishSetupFailed = $false
    $showMeSetupFailed = $false
    $prLensSetupFailed = $false
    $windowsIcon = [char]0xf17a   
    Write-Host "`n$windowsIcon Windows Development Environment Setup" -ForegroundColor White -BackgroundColor DarkBlue
    Write-Host "Version 191 | Last changed: Ignore unrelated Backlog directory activity"

    Assert-HeadlessUnsupported

    New-TokenPlaceholders
    Read-SetupEnvironment

    if (-not (Install-BbDesktop)) { $bbDesktopSetupFailed = $true }

    Write-Section "Package Installation"
    Install-WingetPackages
    Install-SecretsManager
    Install-GcloudCli

    Write-Section "SSH Configuration"
    Test-GitHubSSHKey  

    if ($env:USERNAME -eq "scowalt") {
        Write-Section "Code Directory Setup"
        Setup-CodeDirectory

        Write-Section "Dotfiles Management"
        Install-Chezmoi
        Update-Chezmoi
    }

    if (-not (Remove-GlobalBacklogMcp)) { $piSetupFailed = $true }

    Write-Section "Terminal Configuration"
    Set-StarshipInit
    Set-SfwWrappers
    Set-WindowsTerminalConfiguration
    
    Write-Section "Additional Development Tools"
    if (-not (Install-OpenCodeCli)) { $openCodeSetupFailed = $true }
    Install-GiteaClient
    Install-SocketFirewall
    Install-ClaudeCode
    Install-GeminiCli
    Install-CodexCli
    Install-PortlessCli
    Write-Message 'BB does not support native Windows. Run wsl.sh inside an existing WSL2 distro to prepare its CLI/daemon software, then manually enroll with one chosen BB server over private Tailscale. This script does not install BB or provision WSL.'
    if (-not (Prepare-PiProfilePermissions)) {
        $script:PiProfileMutationsBlocked = $true
        $piSetupFailed = $true
    }
    Remove-RtkResources
    Remove-AttentionSpanResources
    if (-not (Setup-MattPocockSkills)) {
        $mattPocockSetupFailed = $true
    }
    if ($script:PiProfileMutationsBlocked) {
        Write-Warning 'Skipping Pi setup because profile permission preparation failed.'
    }
    elseif (-not (Disable-PiAskClaude)) {
        $script:PiProfileMutationsBlocked = $true
        Write-Warning 'Skipping Pi package setup because the AskClaude policy failed.'
        $piSetupFailed = $true
    }
    elseif (-not (Remove-PiProse)) {
        $script:PiProfileMutationsBlocked = $true
        Write-Warning "Skipping Pi package setup because prose retirement failed."
        $piSetupFailed = $true
    }
    elseif (Install-PiCli) {
        Set-PiDefaults
        Remove-PiSyntheticModels
        Seed-PiZaiModels
        if (Set-PiOpenCodeGoProvider) { $piOpenCodeGoReady = $true }
        else { $script:PiProfileMutationsBlocked = $true; $piSetupFailed = $true }
        if ($piOpenCodeGoReady -and (Prepare-PiMcpAdapter)) {
            $piPackageMaintenanceOk = $true
            if (-not (Setup-PiMcpAdapter)) { $piSetupFailed = $true; $piPackageMaintenanceOk = $false }
            if (-not (Remove-PiSubagents)) { $piSetupFailed = $true; $piPackageMaintenanceOk = $false }
            if (-not (Remove-PiRpivPackages)) { $piSetupFailed = $true; $piPackageMaintenanceOk = $false }
            if (-not (Setup-PiClaudeBridge)) { $piSetupFailed = $true; $piPackageMaintenanceOk = $false }
            if (-not (Setup-PiCompanionPackages)) { $piSetupFailed = $true; $piPackageMaintenanceOk = $false }
            if (-not (Setup-PiGoalAutoresearch)) { $piSetupFailed = $true; $piPackageMaintenanceOk = $false }
            if ($piPackageMaintenanceOk) {
                if (-not (Update-PiPackages)) { $piSetupFailed = $true }
            }
            else { Write-Warning 'Skipping Pi package refresh because prerequisite package maintenance failed.' }
        }
        else { $piSetupFailed = $true }
    }
    else {
        if ($script:PiRuntimePreflightPassed -and (Prepare-PiMcpAdapter)) {
            if (Test-EnvLocalFlag "BAN_PI_MCP_ADAPTER") {
                if (-not (Setup-PiMcpAdapter)) { $piSetupFailed = $true }
            }
            if (-not (Remove-PiSubagents)) { $piSetupFailed = $true }
            if (-not (Remove-PiRpivPackages)) { $piSetupFailed = $true }
            if (Test-EnvLocalFlag "BAN_PI_GOAL_AUTORESEARCH") {
                if (-not (Setup-PiGoalAutoresearch)) { $piSetupFailed = $true }
            }
        }
        Write-Warning "Skipping Pi extension setup because Pi migration failed."
        $piSetupFailed = $true
    }
    if (-not (Remove-SimpleEnglishSkill)) {
        $simpleEnglishSetupFailed = $true
    }
    if (-not (Remove-ShowMeSkill)) {
        $showMeSetupFailed = $true
    }
    if (-not (Remove-PrLensSkill)) {
        $prLensSetupFailed = $true
    }
    if (-not (Set-PiSkillOwnership)) {
        $piSetupFailed = $true
    }
    if (-not (Invoke-ImpeccableConvergence)) { $impeccableSetupFailed = $true }
    Remove-CompoundEngineeringResources
    Install-TursoCli

    Write-Section "System Updates"
    if ($openCodeSetupFailed) {
        Write-Warning 'Deferring blanket WinGet upgrades because OpenCode command ownership or installation is unresolved.'
    } else {
        Install-WingetUpdates
    }
    Install-WindowsUpdates  

    Test-PendingReboot

    if ($openCodeSetupFailed -or $script:OpenCodeWingetConflict) {
        throw 'OpenCode CLI setup or upgrade preservation was incomplete.'
    }
    if ($piSetupFailed) {
        throw "Required Pi coding agent setup failed."
    }
    if ($mattPocockSetupFailed) {
        throw "Required Matt Pocock skill setup failed."
    }
    if ($impeccableSetupFailed) {
        throw 'Required Impeccable skill convergence failed.'
    }
    if ($simpleEnglishSetupFailed) {
        throw "Required Simple English skill removal failed."
    }
    if ($showMeSetupFailed) {
        throw "Required show-me skill removal failed."
    }
    if ($prLensSetupFailed) {
        throw "Required PR Lens skill removal failed."
    }
    if ($bbDesktopSetupFailed) {
        throw "bb desktop setup was incomplete."
    }

    Write-Host "`n$sparkles Setup complete!" -ForegroundColor Green -BackgroundColor DarkGreen
}

function Initialize-WindowsEnvironment {
    $script:SetupLogFile = $null
    $script:SetupTranscriptStarted = $false
    $script:SetupLogClosed = $false
    $setupError = $null
    try {
        $logDir = Get-SetupLogDirectory
        Assert-SetupLogPath $logDir -AllowMissing
        New-Item -ItemType Directory -Force -Path $logDir -ErrorAction Stop | Out-Null
        Invoke-PendingSetupLogUploads
        $script:SetupLogFile = Join-Path $logDir "$(Get-Date -Format 'yyyy-MM-dd-HHmmss')-$([guid]::NewGuid().ToString('N')).log"
        Assert-SetupLogPath $script:SetupLogFile -AllowMissing
        Start-Transcript -Path $script:SetupLogFile -NoClobber -ErrorAction Stop | Out-Null
        $script:SetupTranscriptStarted = $true
        Write-Debug "Logging to $script:SetupLogFile"
        Invoke-WindowsSetupTasks
    }
    catch {
        $setupError = $_
    }
    finally {
        try { Complete-SetupLog }
        catch { Write-Warning 'Setup log finalization failed. The original setup result and local files were preserved.' }
    }
    if ($null -ne $setupError) { throw $setupError }
}

Initialize-WindowsEnvironment
