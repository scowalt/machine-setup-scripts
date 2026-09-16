# NOTE: starship installed via WinGet for Windows ecosystem integration
# DO NOT change to other methods - WinGet provides automatic updates and system integration
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

# Define Nerd Font symbols using Unicode code points
$arrow = [char]0xf0a9      # Arrow icon for actions
$success = [char]0xf00c    # Checkmark icon for success
$warnIcon = [char]0xf071   # Warning icon for warnings
$failIcon = [char]0xf00d   # Cross icon for errors
$sparkles = [char]0x2728   # Sparkles for completion

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

# Define print functions for consistency
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

# Create consolidated environment file (~/.env.local) and migrate old token files
function New-TokenPlaceholders {
    $envLocalPath = Join-Path $env:USERPROFILE ".env.local"

    # Migrate old token files into ~/.env.local
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

    # Create placeholder ~/.env.local if it doesn't exist
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
# Paseo release channel (beta by default; use stable to follow stable releases)
# PASEO_CHANNEL=beta
# WORK_MACHINE=1
# BAN_PI_MCP_ADAPTER=1
# BAN_PI_GOAL_AUTORESEARCH=1
# BAN_MATT_POCOCK_SKILLS=1
# ZAI_API_KEY=<your z.ai API key>
# OpenCode Go console key (Go subscription; keep Use balance disabled in the console)
# OPENCODE_GO_API_KEY=<your OpenCode Go API key>
"@ | Set-Content -Path $envLocalPath
        Write-Debug "Created placeholder ~/.env.local"
    }
}

# Read KEY=1 guards from the process environment or ~/.env.local.
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


function Assert-HeadlessPaseoUnsupported {
    if (-not (Test-EnvLocalFlag "HEADLESS")) {
        return
    }

    Write-Error "HEADLESS=1 requested, but native Windows cannot guarantee a no-login Paseo daemon with the foreground CLI."
    Write-Error "Use a supported native Linux setup script for strict Paseo headless support, or unset HEADLESS for Windows setup."
    throw "Unsupported HEADLESS=1 Paseo daemon setup on Windows"
}

# Install the Tea workstation client on work machines.
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

# Install the appropriate secrets manager based on machine type
function Install-SecretsManager {
    if (Test-EnvLocalFlag "WORK_MACHINE") {
        if (Get-Command infisical -ErrorAction SilentlyContinue) {
            Write-Host "  Infisical CLI already installed." -ForegroundColor DarkGray
            return
        }
        Write-Host "$arrow Installing Infisical CLI..." -ForegroundColor Cyan
        winget install -e --id "Infisical.CLI" --silent --accept-package-agreements --accept-source-agreements
        if ($LASTEXITCODE -eq 0) {
            Write-Host "$success Infisical CLI installed." -ForegroundColor Green
        } else {
            Write-Host "$failIcon Failed to install Infisical CLI." -ForegroundColor Red
        }
    } else {
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

# Update Google Cloud CLI components when the component manager is available.
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

# Install Google Cloud CLI on work machines.
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

    # Initialize chezmoi if not already initialized
    $chezmoiConfigPath = "$HOME\AppData\Local\chezmoi"
    if (-not (Test-Path $chezmoiConfigPath)) {
        Write-Host "$arrow Initializing chezmoi with scowalt/dotfiles..." -ForegroundColor Cyan
        chezmoi init --apply --force scowalt/dotfiles --ssh
        Write-Host "$success chezmoi initialized with scowalt/dotfiles." -ForegroundColor Green
    }
    else {
        Write-Debug "chezmoi is already initialized."
    }

    # Configure chezmoi for auto-commit, auto-push, and auto-pull
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

# Function to update chezmoi dotfiles repository to latest version
function Update-Chezmoi {
    $chezmoiConfigPath = "$HOME\AppData\Local\chezmoi"
    if (Test-Path $chezmoiConfigPath) {
        Write-Host "$arrow Updating chezmoi dotfiles repository..." -ForegroundColor Cyan
        # Reset any dirty state (merge conflicts, uncommitted changes) before pulling.
        # The remote repo is the source of truth — local edits are safe to discard.
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
    # Fetch existing GitHub SSH keys
    try {
        $githubKeys = Invoke-RestMethod -Uri $githubKeysUrl -ErrorAction Stop
        $githubKeyPortions = $githubKeys -split "`n" | ForEach-Object { ($_ -split " ")[1] }
    }
    catch {
        Write-Host "$failIcon Failed to fetch SSH keys from GitHub." -ForegroundColor Red
        throw "Failed to fetch SSH keys from GitHub"
    }

    $localKeyContent = Get-Content -Path $localKeyPath

    # Extract the actual key portion (second field in the file)
    $localKeyValue = ($localKeyContent -split " ")[1]

    # Compare local key with each GitHub key portion
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

# Function to check and set up SSH key for GitHub
function Test-GitHubSSHKey {
    Write-Host "$arrow Checking for existing SSH key associated with GitHub..." -ForegroundColor Cyan

    # Check for existing SSH key locally
    if (Test-Path $localKeyPath) {
        # no need to generate
    }
    else {
        # Generate a new SSH key if none exists
        Write-Host "$warnIcon No SSH key found. Generating a new SSH key..." -ForegroundColor Yellow

        # Create the .ssh folder if it doesn't exist
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

# Function to add Starship initialization to PowerShell profile
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

    # Ensure bun is available
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


# Function to install Turso CLI (libSQL database platform)
function Install-TursoCli {
    if (Get-Command turso -ErrorAction SilentlyContinue) {
        Write-Debug "Turso CLI is already installed."
        return
    }

    Write-Host "$arrow Installing Turso CLI..." -ForegroundColor Cyan

    # Create directory for turso if it doesn't exist
    $tursoPath = "$env:LOCALAPPDATA\turso"
    if (-not (Test-Path $tursoPath)) {
        New-Item -ItemType Directory -Force -Path $tursoPath | Out-Null
    }

    # Download the latest Windows binary
    $downloadUrl = "https://github.com/tursodatabase/turso-cli/releases/latest/download/turso_cli-windows-amd64.exe"
    $binaryPath = "$tursoPath\turso.exe"

    try {
        Write-Host "$arrow Downloading Turso CLI binary..." -ForegroundColor Cyan
        Invoke-WebRequest -Uri $downloadUrl -OutFile $binaryPath

        # Add to PATH if not already there
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

# Function to install/update Claude Code CLI (Anthropic's AI coding agent)
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

# Function to install Gemini CLI (Google's AI coding agent)
function Install-GeminiCli {
    if (Get-Command gemini -ErrorAction SilentlyContinue) {
        Write-Debug "Gemini CLI is already installed."
        return
    }

    Write-Host "$arrow Installing Gemini CLI..." -ForegroundColor Cyan

    # Ensure bun is available
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

# Function to install/update Codex CLI from OpenAI's native GitHub release
# binary, so codex does not depend on Node.js/Bun being present at runtime.
function Install-CodexCli {
    Write-Host "$arrow Installing/updating Codex CLI..." -ForegroundColor Cyan

    # Remove the legacy Bun package so the node_modules symlink can no
    # longer shadow the native binary (or vanish in a broken state).
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

        # Ensure the user-local bin directory is on the persistent user PATH
        # without duplicating it.
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



# Function to install Portless CLI (Tailscale HTTPS tunnel helper)
# Standalone installer shared verbatim with the Bash setup entry points.
# Managed Muse profile: same offline transaction as the standalone Bash scripts.
function Set-PaseoMuseProfile {
    if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
        Write-Warning "Paseo Muse deferred: Node.js is unavailable. Rerun setup outside Paseo after installing Node.js."
        return $true
    }
    $previous = $env:PASEO_MUSE_GO_CHANGED
    $previousNodeOptions = $env:NODE_OPTIONS
    $previousNodePath = $env:NODE_PATH
    try {
        $env:NODE_OPTIONS = $null
        $env:NODE_PATH = $null
        $env:PASEO_MUSE_GO_CHANGED = if ($script:PiOpenCodeGoChanged) { "1" } else { "0" }
        $result = @'
// BEGIN PASEO MUSE PROFILE
// Paseo 0.8 AgentProfileSchema uses z.string() for IDs (not PluginIdSchema).
// pid-lock.js reserves <home>/paseo.pid before starting its config-owning worker.
// Do not replace this offline transaction with a live whole-array config patch.
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { spawnSync } = require('node:child_process');
const { randomUUID } = require('node:crypto');
const id = 'setup:pi:opencode-go:muse-spark-1.3-contributor';
const core = {provider: 'pi', model: 'opencode-go/muse-spark-1.3-contributor', thinkingOptionId: 'xhigh'};
const marker = 'Managed by scowalt machine setup: headless-paseo-daemon';
const service = 'paseo.service';
const label = 'com.scowalt.paseo-daemon';
const platform = process.platform;
const uid = process.getuid?.() ?? 0;
const headless = process.env.HEADLESS === '1';
const refresh = process.env.PASEO_MUSE_GO_CHANGED === '1';
const mode = process.argv[2] || 'sync';
const verifyOnly = mode === 'verify-owner';
const record = v => v !== null && typeof v === 'object' && !Array.isArray(v);
class Refusal extends Error { constructor(code, failed = false) { super(code); this.code = code; this.failed = failed; } }
const refuse = code => { throw new Refusal(code); };
const fail = code => { throw new Refusal(code, true); };
const maxSnapshotBytes = 4 * 1024 * 1024;
const maxPidBytes = 64 * 1024;
let home, logicalHome, paseoHome, configPath, pidPath, accountRoots, customHome;
let heldLock = null, restore = null, temporary = null, interrupted = false;
// This read-only exception exists only while proving a repairable Linux owner.
// It is cleared before service control or profile writes; verify-owner stays read-only.
let permissionInspection = null;
for (const signal of ['SIGINT', 'SIGTERM', 'SIGHUP']) process.on(signal, () => { interrupted = true; });
const checkpoint = async () => { await new Promise(resolve => setImmediate(resolve)); if (interrupted) fail('interrupted'); };
function stat(file) {
    try { return fs.lstatSync(file); } catch (error) { if (error.code === 'ENOENT') return null; throw error; }
}
function same(a, b) { return a === null ? b === null : b !== null && a.dev === b.dev && a.ino === b.ino && a.size === b.size && a.mtimeMs === b.mtimeMs && a.ctimeMs === b.ctimeMs; }
function rootDirectory(file) {
    const s = stat(file);
    return s && s.isDirectory() && !s.isSymbolicLink() && s.uid === 0 && !(s.mode & 0o022);
}
function trustedSystemHomeAlias() {
    const s = stat('/home');
    return platform === 'linux' && s?.isSymbolicLink() && s.uid === 0 &&
        ['var/home', '/var/home'].includes(fs.readlinkSync('/home')) &&
        ['/', '/var', '/var/home'].every(rootDirectory);
}
function checkedPath(file, directory = false) {
    const absolute = path.resolve(file);
    let current = path.parse(absolute).root;
    const parts = absolute.slice(current.length).split(path.sep).filter(Boolean);
    for (let n = 0; n < parts.length; n++) {
        current = path.join(current, parts[n]);
        const s = stat(current);
        if (!s) continue;
        if (s.isSymbolicLink()) {
            // Only Bazzite's root-owned system alias; never a linked user/profile.
            if (current === '/home' && trustedSystemHomeAlias()) continue;
            fail('linked-path');
        }
        const dir = n < parts.length - 1 || directory;
        if (dir ? !s.isDirectory() : !s.isFile() || s.nlink !== 1) fail('unsafe-file-type');
        if ((current === home || current.startsWith(home + path.sep)) && platform !== 'win32' &&
            (s.uid !== uid || (s.mode & 0o022))) {
            if (s.uid !== uid || (s.mode & 0o002) || !permissionInspection?.allowed.has(current)) fail('unsafe-owner-or-mode');
            // A writable native PID may only be inspected inside an already private home.
            if (current === pidPath && (stat(paseoHome).mode & 0o077)) fail('permission-recovery-private-home-required');
            const prior = permissionInspection.paths.get(current);
            if (prior && !same(prior, s)) fail('permission-path-changed');
            permissionInspection.paths.set(current, s);
        }
    }
    return stat(absolute);
}
function beginPermissionInspection(pidOnly = false) {
    if (verifyOnly || !headless || platform !== 'linux' || /microsoft/i.test(os.release()) || customHome) return;
    const dirs = pidOnly ? [] : ['.config', '.config/systemd', '.config/systemd/user'].map(p => path.join(home, p));
    permissionInspection = {allowed: new Set([...dirs, pidPath]), paths: new Map()};
    // Preflight every candidate before repairing anything. No recursion, links,
    // ownership changes, world-writable paths or user/custom home repairs.
    for (const dir of dirs) checkedPath(dir, true);
    checkedPath(pidPath);
}
function repairInspectedPermissions() {
    const planned = permissionInspection?.paths;
    if (!planned?.size) { permissionInspection = null; return; }
    const handles = new Map();
    try {
        if (!fs.constants.O_NOFOLLOW || !fs.constants.O_DIRECTORY) fail('permission-handles-unavailable');
        const directoryFlags = fs.constants.O_RDONLY | fs.constants.O_DIRECTORY | fs.constants.O_NOFOLLOW;
        const pin = (file, directory) => {
            if (handles.has(file)) return handles.get(file);
            const parent = file === home ? null : pin(path.dirname(file), true);
            const before = checkedPath(file, directory);
            if (!before || planned.has(file) && !same(planned.get(file), before)) fail('permission-path-changed');
            // Linux descriptor-relative traversal: only the verified HOME spelling
            // is opened by absolute path. Never follow a replaced ancestor.
            const target = parent ? `/proc/self/fd/${parent.fd}/${path.basename(file)}` : file;
            const fd = fs.openSync(target, directory ? directoryFlags : fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW | fs.constants.O_NONBLOCK);
            const entry = {fd, s: before};
            handles.set(file, entry);
            if (!same(before, fs.fstatSync(fd)) || !same(before, stat(file))) fail('permission-path-changed');
            return entry;
        };
        for (const file of planned.keys()) pin(file, file !== pidPath);
        const unchanged = () => {
            for (const [file, entry] of handles) {
                if (!same(entry.s, fs.fstatSync(entry.fd)) || !same(entry.s, stat(file))) fail('permission-path-changed');
            }
        };
        unchanged();
        for (const file of planned.keys()) {
            unchanged();
            const entry = handles.get(file);
            const nextMode = (entry.s.mode & 0o7777) & ~0o022;
            fs.fchmodSync(entry.fd, nextMode);
            const after = fs.fstatSync(entry.fd);
            if (after.uid !== uid || after.dev !== entry.s.dev || after.ino !== entry.s.ino ||
                (after.mode & 0o7777) !== nextMode) fail('permission-repair-unverified');
            entry.s = after;
        }
        unchanged();
        permissionInspection = null;
        for (const file of planned.keys()) checkedPath(file, file !== pidPath);
        console.log('PASEO_MUSE_PERMISSIONS_REPAIRED');
    } finally {
        permissionInspection = null;
        for (const {fd} of handles.values()) fs.closeSync(fd);
    }
}
function checkWindowsMetadataAcl(file) {
    if (platform !== 'win32') return;
    let current = path.resolve(file);
    const relative = path.relative(home, current);
    if (relative === '..' || relative.startsWith('..' + path.sep) || path.isAbsolute(relative)) fail('windows-acl-unverified');
    const existing = [];
    while (true) {
        if (stat(current)) existing.push(current);
        if (current === home) break;
        const parent = path.dirname(current);
        if (parent === current) fail('windows-acl-unverified');
        current = parent;
    }
    // Include HOME even when the default directory/file does not exist yet.
    // Repeat for every snapshot, including native PID and staged JSON metadata.
    const command = String.raw`$ErrorActionPreference='Stop'
$env:PSModulePath = "$PSHOME\Modules"
try {
    $owner = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
    $trusted = @($owner.Value, 'S-1-5-18', 'S-1-5-32-544')
    $paths = @($env:PASEO_MUSE_ACL_PATHS | ConvertFrom-Json)
    if ($paths.Count -eq 0 -or $paths[-1] -ne $env:PASEO_MUSE_ACCOUNT_HOME) { throw 'unverified-boundary' }
    $writes = [System.Security.AccessControl.FileSystemRights]'Write,Delete,DeleteSubdirectoriesAndFiles,ChangePermissions,TakeOwnership'
    foreach ($current in $paths) {
        $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'linked' }
        $acl = Get-Acl -LiteralPath $current
        $sddl = $acl.GetSecurityDescriptorSddlForm([System.Security.AccessControl.AccessControlSections]::Access)
        if (-not $sddl.StartsWith('D:') -or $sddl.Contains('NO_ACCESS_CONTROL')) { throw 'unverified-access' }
        if ($acl.GetOwner([System.Security.Principal.SecurityIdentifier]).Value -notin $trusted) { throw 'unverified-owner' }
        foreach ($rule in $acl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier])) {
            if ($rule.PropagationFlags -band [System.Security.AccessControl.PropagationFlags]::InheritOnly) { continue }
            if ($rule.AccessControlType -eq 'Allow' -and $rule.IdentityReference.Value -notin $trusted -and
                ($rule.FileSystemRights -band $writes)) { throw 'unverified-writer' }
        }
    }
    [Console]::Out.Write('ok')
} catch { exit 1 }`;
    const result = run('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', command], true,
        {PASEO_MUSE_ACL_PATHS: JSON.stringify(existing), PASEO_MUSE_ACCOUNT_HOME: home});
    if (result?.trim() !== 'ok') fail('windows-acl-unverified');
}
function snapshot(file) {
    const s = checkedPath(file);
    checkWindowsMetadataAcl(file);
    if (!s) return {s: null, text: null};
    const limit = file === pidPath ? maxPidBytes : maxSnapshotBytes;
    if (!Number.isSafeInteger(s.size) || s.size < 0 || s.size > limit) fail('metadata-too-large');
    // Nonblocking open prevents a FIFO replacement from hanging read-only inspection.
    const fd = fs.openSync(file, fs.constants.O_RDONLY | (fs.constants.O_NOFOLLOW || 0) | (fs.constants.O_NONBLOCK || 0));
    try {
        const opened = fs.fstatSync(fd);
        if (!opened.isFile() || opened.nlink !== 1 || !same(s, opened)) fail('file-changed');
        // Read at most the checked size plus one byte, even if a writer grows it.
        const bytes = Buffer.alloc(s.size + 1);
        let used = 0;
        while (used < bytes.length) {
            const count = fs.readSync(fd, bytes, used, bytes.length - used, null);
            if (count === 0) break;
            used += count;
        }
        if (used !== s.size || !same(s, fs.fstatSync(fd)) || !same(s, checkedPath(file))) fail('file-changed');
        return {s, text: bytes.subarray(0, used).toString('utf8')};
    } finally { fs.closeSync(fd); }
}
function json(snap) {
    if (snap.text === null) return null;
    // JSON.parse silently discards duplicate keys. Refuse that ambiguous input.
    const text = snap.text;
    let at = 0;
    const space = () => { while (/\s/.test(text[at] || '') && at < text.length) at++; };
    function string() {
        const start = at++;
        while (at < text.length) { if (text[at++] === '"') return JSON.parse(text.slice(start, at)); if (text[at - 1] === '\\') at++; }
        throw new Error();
    }
    function value() {
        space();
        if (text[at] === '"') { string(); return; }
        if (text[at] === '{' || text[at] === '[') {
            const object = text[at++] === '{', end = object ? '}' : ']';
            const keys = new Set();
            space();
            if (text[at] === end) { at++; return; }
            do {
                space();
                if (object) {
                    if (text[at] !== '"') throw new Error();
                    const key = string();
                    if (keys.has(key)) fail('duplicate-json-key');
                    keys.add(key); space(); if (text[at++] !== ':') throw new Error();
                }
                value(); space();
                if (text[at] === end) { at++; return; }
            } while (text[at++] === ',');
            throw new Error();
        }
        const token = text.slice(at).match(/^(?:true|false|null|-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)/);
        if (!token) throw new Error();
        at += token[0].length;
    }
    try {
        const parsed = JSON.parse(text, (_key, item) => {
            if (typeof item === 'number' && (!Number.isFinite(item) || Number.isInteger(item) && !Number.isSafeInteger(item))) fail('unsafe-json-number');
            return item;
        });
        value(); space(); if (at !== text.length) throw new Error(); return parsed;
    } catch (error) { if (error instanceof Refusal) throw error; fail('invalid-json'); }
}
function merge(snap) {
    const config = snap.text === null ? {} : json(snap);
    if (!record(config) || ('daemon' in config && !record(config.daemon))) fail('invalid-config');
    const daemon = config.daemon || {};
    const profiles = daemon.agentProfiles === undefined ? [] : daemon.agentProfiles;
    if (!Array.isArray(profiles)) fail('invalid-profiles');
    const ids = new Set();
    for (const p of profiles) {
        if (!record(p) || typeof p.id !== 'string' || typeof p.name !== 'string' || typeof p.provider !== 'string' || ids.has(p.id)) fail('invalid-profiles');
        ids.add(p.id);
        for (const key of ['model', 'modeId', 'thinkingOptionId', 'icon', 'color', 'notes']) {
            if (key in p && typeof p[key] !== 'string') fail('invalid-profiles');
        }
        if ('featureValues' in p && !record(p.featureValues)) fail('invalid-profiles');
    }
    const managed = profiles.find(p => p.id === id);
    if (managed && Object.entries(core).every(([key, value]) => managed[key] === value)) return null;
    // A same-name user profile is not setup-owned. ID is the only ownership key.
    const next = managed ? profiles.map(p => p.id === id ? {...p, ...core} : p) :
        [...profiles, {id, name: 'Muse 1.3 Contributor', ...core}];
    return JSON.stringify({...config, daemon: {...daemon, agentProfiles: next}}, null, 2) + '\n';
}
function run(command, args, optional = false, env = {}) {
    if (platform === 'win32' && command === 'powershell.exe') {
        const at = args.indexOf('-Command');
        if (at >= 0) args = args.map((arg, n) => n === at + 1 ? '$env:PSModulePath = "$PSHOME\\Modules"; ' + arg : arg);
    }
    const result = spawnSync(command, args, {encoding: 'utf8', timeout: 30000, maxBuffer: 8 * 1024 * 1024,
        windowsHide: true, shell: false, stdio: ['ignore', 'pipe', 'pipe'],
        env: {...process.env, ...env, HOME: logicalHome, PASEO_HOME: paseoHome}});
    if (result.error || result.status !== 0) {
        if (optional) return null;
        refuse('command-unverified');
    }
    return result.stdout;
}
function systemctl(args) {
    const env = {XDG_RUNTIME_DIR: `/run/user/${uid}`, DBUS_SESSION_BUS_ADDRESS: `unix:path=/run/user/${uid}/bus`};
    const direct = run('systemctl', ['--user', ...args], true, env);
    if (direct !== null) return direct;
    return run('systemctl', [`--machine=${os.userInfo().username}@`, '--user', ...args], false, env);
}
function properties(text) {
    const result = {};
    for (const line of text.trim().split('\n')) {
        const at = line.indexOf('=');
        if (at <= 0 || Object.hasOwn(result, line.slice(0, at))) refuse('invalid-service-state');
        result[line.slice(0, at)] = line.slice(at + 1);
    }
    return result;
}
function serviceState() {
    return properties(systemctl(['show', service, '--property=Id,LoadState,ActiveState,SubState,MainPID,FragmentPath,DropInPaths,NeedDaemonReload,ControlGroup,User,ExecStart,Environment,EnvironmentFiles,KillMode']));
}
function live(pid) {
    try { process.kill(pid, 0); return true; } catch (error) { if (error.code === 'ESRCH') return false; refuse('pid-unverified'); }
}
function pidInfo() {
    const snap = snapshot(pidPath);
    if (!snap.s) return {snap, info: null};
    const info = json(snap);
    if (!record(info) || !Number.isInteger(info.pid) || info.pid <= 1 ||
        info.hostname !== os.hostname() || info.uid !== uid || typeof info.startedAt !== 'string' ||
        !Number.isFinite(Date.parse(info.startedAt)) || !(info.listen === null || typeof info.listen === 'string') ||
        ('desktopManaged' in info && typeof info.desktopManaged !== 'boolean')) refuse('pid-metadata-unverified');
    return {snap, info};
}
function inventory() {
    const processes = [];
    if (platform === 'linux') {
        for (const entry of fs.readdirSync('/proc')) {
            if (!/^\d+$/.test(entry)) continue;
            const dir = `/proc/${entry}`;
            try {
                const processUid = fs.statSync(dir).uid;
                const raw = fs.readFileSync(`${dir}/stat`, 'utf8');
                const fields = raw.slice(raw.lastIndexOf(')') + 2).split(' ');
                const command = fs.readFileSync(`${dir}/cmdline`, 'utf8').replace(/\0/g, ' ');
                const owned = processUid === uid;
                const env = owned ? Object.fromEntries(fs.readFileSync(`${dir}/environ`, 'utf8').split('\0').filter(v => v.includes('=')).map(v => [v.slice(0, v.indexOf('=')), v.slice(v.indexOf('=') + 1)])) : {};
                const cgroup = owned ? fs.readFileSync(`${dir}/cgroup`, 'utf8') : '';
                processes.push({pid: Number(entry), parent: Number(fields[1]), command, env, cgroup, owned});
            } catch (error) { if (error.code !== 'ENOENT' && error.code !== 'ESRCH') refuse('process-inventory-unverified'); }
        }
    } else if (platform === 'darwin') {
        const text = run('ps', ['-axww', '-o', 'pid=,ppid=,uid=,command=']);
        for (const line of text.trim().split('\n')) {
            const match = line.trim().match(/^(\d+)\s+(\d+)\s+(\d+)\s+(.*)$/);
            if (!match) refuse('process-inventory-unverified');
            processes.push({pid: Number(match[1]), parent: Number(match[2]), command: match[4], owned: Number(match[3]) === uid});
        }
    } else if (platform === 'win32') {
        const text = run('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command',
            '$ErrorActionPreference="Stop"; @(Get-CimInstance Win32_Process | Select-Object ProcessId,ParentProcessId,Name,ExecutablePath,CommandLine) | ConvertTo-Json -Compress']);
        let rows;
        try { rows = JSON.parse(text); } catch { refuse('process-inventory-unverified'); }
        if (!Array.isArray(rows)) refuse('process-inventory-unverified');
        for (const row of rows) {
            if (!Number.isInteger(row.ProcessId) || !Number.isInteger(row.ParentProcessId)) refuse('process-inventory-unverified');
            processes.push({pid: row.ProcessId, parent: row.ParentProcessId,
                command: `${row.Name || ''} ${row.ExecutablePath || ''} ${row.CommandLine || ''}`});
        }
    } else refuse('unsupported-platform');
    if (!processes.some(p => p.pid === process.pid)) refuse('process-inventory-unverified');
    return processes;
}
function descends(pid, parent, rows) {
    const seen = new Set();
    while (pid > 1 && !seen.has(pid)) {
        if (pid === parent) return true;
        seen.add(pid);
        const p = rows.find(row => row.pid === pid);
        if (!p) return false;
        pid = p.parent;
    }
    return false;
}
function verifySetupAncestry(rows) {
    let pid = process.pid;
    const seen = new Set();
    while (pid > 1) {
        if (seen.has(pid)) refuse('ancestry-unverified');
        seen.add(pid);
        const row = rows.find(p => p.pid === pid);
        if (!row || !Number.isInteger(row.parent) || row.parent < 0) refuse('ancestry-unverified');
        pid = row.parent;
    }
}
function inGroup(p, group) {
    return !!group && (p.cgroup || '').split('\n').some(line => {
        const value = line.slice(line.indexOf(':', line.indexOf(':') + 1) + 1);
        return value === group || value.startsWith(group + '/');
    });
}
function candidates(rows) {
    return rows.filter(p => p.pid !== process.pid && p.owned !== false && (
        /(?:@getpaseo[\\/]|paseo(?:\.exe|\.app|[\\/\s]|$)|supervisor-entrypoint|daemon-worker|node-entrypoint-runner)/i.test(p.command) ||
        p.env?.PASEO_DESKTOP_MANAGED === '1' ||
        (p.env?.PASEO_HOME && samePaseoHome(p.env.PASEO_HOME) && !descends(process.pid, p.pid, rows))));
}
function ensureNoWriters(owner = null) {
    const rows = inventory();
    if (candidates(rows).length || (owner && rows.some(p => inGroup(p, owner.group) || descends(p.pid, owner.pid, rows)))) refuse('writer-still-present');
    if (owner && live(owner.pid)) refuse('owner-still-present');
    return rows;
}
function checkWrapper() {
    const file = path.join(home, '.local/bin/paseo-daemon-start');
    const snap = snapshot(file);
    const lines = snap.text?.trimEnd().split('\n');
    // Accept the exact legacy shape and the new restrictive launch shape only.
    if (lines?.length === 10 && lines[3] === 'umask 077') lines.splice(3, 1);
    // Match setup's shell-quoted HOME without executing the wrapper or sourcing it.
    const quoted = "'" + logicalHome.replace(/'/g, "'\\''") + "'";
    const exec = lines?.at(-1)?.match(/^exec ('[^'\r\n]+') daemon start --foreground --listen '[^'\r\n]+'$/);
    if (!lines || ![8, 9].includes(lines.length) || lines[0] !== '#!/bin/bash' || lines[1] !== `# ${marker}` ||
        lines[2] !== 'set -euo pipefail' || lines[3] !== `export HOME=${quoted}` ||
        !/^export PATH='[^'\r\n]*'$/.test(lines[4]) ||
        !/^\[\[ -x '[^'\r\n]+' \]\] \|\| exit 127$/.test(lines[5]) ||
        !exec || lines[6] !== `[[ -x ${exec[1]} ]] || exit 127` ||
        lines.length === 9 && lines[7] !== `export PASEO_SETUP_CLI=${exec[1]}`) refuse('unmanaged-wrapper');
    return {file, snap};
}
function sameHome(value) { return accountRoots.includes(value); }
function accountPath(value) {
    if (typeof value !== 'string' || !path.isAbsolute(value) || value.includes('\0') || value.split(path.sep).includes('..')) return null;
    const absolute = path.resolve(value);
    for (const root of accountRoots) {
        const relative = path.relative(root, absolute);
        if (relative && relative !== '..' && !relative.startsWith('..' + path.sep) && !path.isAbsolute(relative)) return path.join(home, relative);
    }
    return null;
}
function samePaseoHome(value) { return accountPath(value) === paseoHome; }
function daemonHomeMatches(value) {
    // Upstream treats an explicitly empty PASEO_HOME as cwd, not as unset.
    return value === undefined ? !customHome : samePaseoHome(value);
}
function checkCustomHome() {
    if (!customHome) return;
    const s = checkedPath(paseoHome, true);
    // Only pre-existing, private custom directories have an established boundary.
    if (!s) refuse('custom-home-unverified');
    if (platform !== 'win32') {
        if (s.uid !== uid || (s.mode & 0o077)) refuse('custom-home-permissions-unverified');
        return;
    }
    const command = `$ErrorActionPreference='Stop';
$sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$trusted = @($sid, 'S-1-5-18', 'S-1-5-32-544')
$directory = $env:PASEO_HOME
while ($true) {
    $acl = Get-Acl -LiteralPath $directory
    if ($acl.GetOwner([System.Security.Principal.SecurityIdentifier]).Value -ne $sid) { throw 'unverified-owner' }
    foreach ($rule in $acl.Access) {
        if ($rule.AccessControlType -ne 'Allow') { continue }
        $identity = $rule.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value
        if ($identity -in $trusted) { continue }
        $writes = [System.Security.AccessControl.FileSystemRights]'Write,Delete,DeleteSubdirectoriesAndFiles,ChangePermissions,TakeOwnership'
        if ($directory -eq $env:PASEO_HOME -or ($rule.FileSystemRights -band $writes)) { throw 'unverified-access' }
    }
    if ($directory -eq $env:PASEO_MUSE_ACCOUNT_HOME) { break }
    $parent = [System.IO.Path]::GetDirectoryName($directory)
    if (-not $parent -or $parent -eq $directory) { throw 'unverified-boundary' }
    $directory = $parent
}`;
    if (run('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', command], true,
        {PASEO_MUSE_ACCOUNT_HOME: home}) === null) refuse('custom-home-permissions-unverified');
}
function verifyOwnerProcess(info, mainPid, group, rows) {
    if (info.desktopManaged) refuse('desktop-owned');
    if (!descends(info.pid, mainPid, rows)) refuse('service-pid-mismatch');
    if (process.env.PASEO_AGENT_ID || descends(process.pid, mainPid, rows) ||
        rows.some(p => p.pid === process.pid && inGroup(p, group))) refuse('self-hosted-setup');
    if (candidates(rows).some(p => !descends(p.pid, mainPid, rows))) refuse('unknown-writer');
    const owner = rows.find(p => p.pid === info.pid);
    if (!owner || owner.owned === false) refuse('owner-unverified');
    if (platform === 'linux') {
        if (!inGroup(owner, group) || !sameHome(owner.env?.HOME) ||
            !daemonHomeMatches(owner.env?.PASEO_HOME)) refuse('service-home-mismatch');
    } else {
        // ps supplies the actual owner's environment; don't trust only the plist.
        if (/\s/.test(logicalHome) || /\s/.test(paseoHome)) refuse('service-home-unverified');
        const env = run('ps', ['eww', '-p', String(info.pid), '-o', 'command=']);
        const account = [...env.matchAll(/(?:^|\s)HOME=([^\s]*)/g)];
        const overrides = [...env.matchAll(/(?:^|\s)PASEO_HOME=([^\s]*)/g)];
        if (account.length !== 1 || !sameHome(account[0][1]) || overrides.length > 1 ||
            !daemonHomeMatches(overrides[0]?.[1])) refuse('service-home-mismatch');
    }
}
function safeToRestore() {
    // A new owner must not be masked by starting a replacement supervisor.
    if (snapshot(pidPath).s) fail('restore-owner-conflict');
    ensureNoWriters();
}
function linuxManagerHome() {
    const environment = systemctl(['show-environment']);
    const overrides = environment.split('\n').filter(line => line.startsWith('PASEO_HOME='));
    if (overrides.length > 1 || !daemonHomeMatches(overrides[0]?.slice('PASEO_HOME='.length))) refuse('service-home-mismatch');
}
function linuxOwner(info, rows) {
    if (!headless || /microsoft/i.test(os.release())) refuse('headless-control-not-authorized');
    const file = path.join(home, '.config/systemd/user', service);
    const unit = snapshot(file), wrapper = checkWrapper();
    // Disallow user edits, extra directives, drop-ins and a stale loaded definition.
    const expected = `# ${marker}\n[Unit]\nDescription=Paseo headless daemon\nDocumentation=https://www.getpaseo.com/\n\n[Service]\nType=simple\nExecStart=${logicalHome}/.local/bin/paseo-daemon-start\nWorkingDirectory=${logicalHome}\nEnvironment=HOME=${logicalHome}\nEnvironment=PATH=`;
    const tail = '\nRestart=on-failure\nRestartSec=5\n\n[Install]\nWantedBy=default.target\n';
    if (!unit.text?.startsWith(expected) || !unit.text.endsWith(tail) || unit.text.slice(expected.length, -tail.length).includes('\n')) refuse('unmanaged-service');
    const state = serviceState();
    if (state.Id !== service || state.LoadState !== 'loaded' || state.ActiveState !== 'active' || state.SubState !== 'running' ||
        state.FragmentPath !== path.join(logicalHome, '.config/systemd/user', service) || state.DropInPaths !== '' ||
        state.NeedDaemonReload !== 'no' || state.EnvironmentFiles !== '' || !['', os.userInfo().username].includes(state.User) ||
        state.KillMode !== 'control-group' || !state.ControlGroup?.startsWith(`/user.slice/user-${uid}.slice/`) ||
        !state.ExecStart?.includes(`path=${logicalHome}/.local/bin/paseo-daemon-start ;`) ||
        !state.Environment?.includes(`HOME=${logicalHome}`)) refuse('service-state-unverified');
    linuxManagerHome();
    const pid = Number(state.MainPID);
    if (!Number.isInteger(pid) || pid <= 1) refuse('service-pid-unverified');
    verifyOwnerProcess(info, pid, state.ControlGroup, rows);
    return {pid, group: state.ControlGroup, file, unit, wrapper,
        stop() { systemctl(['stop', service]); },
        stopped() { const s = serviceState(); if (s.ActiveState !== 'inactive' || s.SubState !== 'dead' || s.MainPID !== '0') refuse('stopped-state-unverified'); },
        start() {
            const before = serviceState();
            if (before.ActiveState === 'active' && before.SubState === 'running' && Number(before.MainPID) === pid) return;
            safeToRestore(); linuxManagerHome(); systemctl(['start', service]);
            const s = serviceState();
            if (s.ActiveState !== 'active' || s.SubState !== 'running' || Number(s.MainPID) <= 1) fail('restore-unverified');
        }};
}
async function finishRestoredPermissions(owner) {
    if (platform !== 'linux' || customHome) return;
    // Type=simple can report active before the native PID exists or is fully
    // written. Do not let that race bypass the strict later ownership preflight.
    for (let attempt = 0; attempt < 50; attempt++) {
        try {
            beginPermissionInspection(true);
            const restarted = pidInfo();
            if (!restarted.info) refuse('restart-pid-pending');
            if (!live(restarted.info.pid)) refuse('pid-unverified');
            const verified = linuxOwner(restarted.info, inventory());
            if (!same(owner.unit.s, verified.unit.s) || !same(owner.wrapper.snap.s, verified.wrapper.snap.s)) refuse('ownership-changed');
            if (snapshot(pidPath).text !== restarted.snap.text) fail('file-changed');
            repairInspectedPermissions();
            if (snapshot(pidPath).text !== restarted.snap.text) fail('file-changed');
            return;
        } catch (error) {
            const pending = error instanceof Refusal && ['restart-pid-pending', 'invalid-json', 'file-changed', 'permission-path-changed'].includes(error.code);
            if (!pending && error.code !== 'ENOENT') throw error;
        } finally { permissionInspection = null; }
        await new Promise(resolve => setTimeout(resolve, 100));
    }
    fail('restart-pid-not-ready');
}
function launchList() {
    const text = run('sudo', ['-n', 'launchctl', 'list']);
    const rows = text.trim().split('\n');
    if (!/^PID\s+Status\s+Label$/.test(rows.shift())) refuse('launchd-state-unverified');
    return rows.map(line => { const m = line.match(/^(\d+|-)\s+(-?\d+)\s+(\S+)$/); if (!m) refuse('launchd-state-unverified'); return {pid: m[1] === '-' ? 0 : Number(m[1]), label: m[3]}; });
}
function macManagerHome() {
    const domain = run('sudo', ['-n', 'launchctl', 'print', 'system']);
    const environment = domain.match(/\benvironment = \{([^}]*?)\}/);
    if (!environment) refuse('service-environment-unverified');
    const overrides = environment[1].split('\n').map(line => line.trim()).filter(line => /^PASEO_HOME\s+=>/.test(line));
    if (overrides.length > 1 || !daemonHomeMatches(overrides[0]?.replace(/^PASEO_HOME\s+=>\s*/, ''))) refuse('service-home-mismatch');
}
function macOwner(info, rows) {
    if (!headless || process.env.PASEO_MACOS_HEADLESS_CANARY !== '1') refuse('headless-control-not-authorized');
    const file = `/Library/LaunchDaemons/${label}.plist`;
    const unit = snapshot(file), wrapper = checkWrapper();
    if (!['/', '/Library', '/Library/LaunchDaemons'].every(rootDirectory) || !unit.s || unit.s.uid !== 0 ||
        unit.s.mode & 0o022 || !unit.text.includes(`<!-- ${marker} -->`)) refuse('unmanaged-service');
    let plist;
    try { plist = JSON.parse(run('plutil', ['-convert', 'json', '-o', '-', file])); } catch (error) { if (error instanceof Refusal) throw error; refuse('invalid-service-state'); }
    if (plist.Label !== label || plist.UserName !== os.userInfo().username || plist.WorkingDirectory !== logicalHome ||
        JSON.stringify(plist.ProgramArguments) !== JSON.stringify([path.join(logicalHome, '.local/bin/paseo-daemon-start')]) ||
        plist.EnvironmentVariables?.HOME !== logicalHome || typeof plist.EnvironmentVariables?.PATH !== 'string' ||
        Object.keys(plist.EnvironmentVariables).some(key => !['HOME', 'PATH'].includes(key)) ||
        plist.RunAtLoad !== true || plist.KeepAlive !== true ||
        Object.keys(plist).some(key => !['Label', 'UserName', 'ProgramArguments', 'WorkingDirectory', 'EnvironmentVariables', 'RunAtLoad', 'KeepAlive'].includes(key))) refuse('service-state-unverified');
    const entry = launchList().find(p => p.label === label);
    if (!entry || entry.pid <= 1) refuse('service-pid-unverified');
    const printed = run('sudo', ['-n', 'launchctl', 'print', `system/${label}`]);
    if (!printed.includes(`path = ${file}\n`) || !printed.includes(`program = ${logicalHome}/.local/bin/paseo-daemon-start\n`)) refuse('service-state-unverified');
    verifyOwnerProcess(info, entry.pid, null, rows);
    macManagerHome();
    return {pid: entry.pid, group: null, file, unit, wrapper,
        stop() { run('sudo', ['-n', 'launchctl', 'bootout', `system/${label}`]); },
        stopped() { if (launchList().some(p => p.label === label)) refuse('stopped-state-unverified'); },
        start() {
            const loaded = launchList().find(p => p.label === label);
            if (loaded?.pid === entry.pid) return;
            if (loaded) fail('restore-owner-conflict');
            safeToRestore(); macManagerHome(); run('sudo', ['-n', 'launchctl', 'bootstrap', 'system', file]);
            if (!launchList().some(p => p.label === label && p.pid > 1)) fail('restore-unverified');
        }};
}
function reservePid() {
    // Never unlink a stale/foreign native lock: its owner may be racing startup.
    if (snapshot(pidPath).s) refuse('pid-lock-present');
    const text = JSON.stringify({pid: process.pid, startedAt: new Date().toISOString(), hostname: os.hostname(), uid, listen: null, heartbeat: true});
    const fd = fs.openSync(pidPath, 'wx', 0o600);
    heldLock = {fd, text, initial: fs.fstatSync(fd)};
    fs.writeFileSync(fd, text);
    fs.fsyncSync(fd);
    heldLock.s = fs.fstatSync(fd);
}
function releasePid() {
    if (!heldLock) return;
    const held = heldLock;
    heldLock = null;
    try {
        const current = snapshot(pidPath);
        // A failed initial write still owns this inode; remove only our partial lock.
        if (!current.s || held.initial.dev !== current.s.dev || held.initial.ino !== current.s.ino ||
            !same(fs.fstatSync(held.fd), current.s) || (held.s && current.text !== held.text)) fail('pid-lock-changed');
        fs.unlinkSync(pidPath);
    } finally { fs.closeSync(held.fd); }
}
function secureTemporary(file, existing) {
    if (platform !== 'win32') return;
    const command = `$ErrorActionPreference='Stop';
if ($env:PASEO_MUSE_EXISTING -eq '1') { $acl = Get-Acl -LiteralPath $env:PASEO_MUSE_CONFIG }
else {
    $sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
    $acl = New-Object System.Security.AccessControl.FileSecurity
    $acl.SetOwner($sid)
    $acl.SetAccessRuleProtection($true, $false)
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($sid, 'FullControl', 'Allow')))
    $system = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-18')
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($system, 'FullControl', 'Allow')))
}
Set-Acl -LiteralPath $env:PASEO_MUSE_TEMP -AclObject $acl`;
    run('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', command], false,
        {PASEO_MUSE_EXISTING: existing ? '1' : '0', PASEO_MUSE_CONFIG: configPath, PASEO_MUSE_TEMP: file});
}
function lockUnchanged() {
    const current = snapshot(pidPath);
    if (!heldLock || !same(heldLock.s, current.s) || current.text !== heldLock.text) fail('pid-lock-changed');
}
async function main() {
    if (!['sync', 'verify-owner'].includes(mode)) fail('invalid-mode');
    logicalHome = path.resolve(os.homedir());
    // HOME is trusted only for the effective account, not an arbitrary profile link.
    const accountHome = path.resolve(os.userInfo().homedir);
    if (fs.realpathSync(logicalHome) !== fs.realpathSync(accountHome)) refuse('account-home-mismatch');
    home = fs.realpathSync(logicalHome);
    checkedPath(logicalHome, true);
    checkedPath(home, true);
    accountRoots = [...new Set([home, logicalHome])];
    if (platform === 'linux' && home.startsWith('/var/home/') && trustedSystemHomeAlias()) {
        accountRoots.push(path.join('/home', path.relative('/var/home', home)));
    }
    const requested = process.env.PASEO_HOME;
    if (requested !== undefined && (requested === '' || !path.isAbsolute(requested))) refuse('invalid-home-override');
    paseoHome = requested === undefined ? path.join(home, '.paseo') : accountPath(requested);
    if (!paseoHome) refuse('custom-home-unverified');
    // Validate the supplied spelling too; only the trusted account aliases map.
    if (requested !== undefined) checkedPath(requested, true);
    customHome = paseoHome !== path.join(home, '.paseo');
    configPath = path.join(paseoHome, 'config.json');
    pidPath = path.join(paseoHome, 'paseo.pid');
    checkedPath(paseoHome, true);
    checkCustomHome();
    if (customHome) {
        // The later legacy service installer assumes the default home. It must
        // not undo this transaction's verified custom-home owner selection.
        console.log('PASEO_MUSE_DEFER_DAEMON_SETUP=1');
        console.log('Paseo Muse custom home: later managed-daemon setup is skipped. Keep this owner\'s launch environment and update that owner separately.');
        if (verifyOnly) return;
    }
    if (verifyOnly && (!headless || !['linux', 'darwin'].includes(platform) ||
        platform === 'linux' && /microsoft/i.test(os.release()) ||
        platform === 'darwin' && process.env.PASEO_MACOS_HEADLESS_CANARY !== '1')) refuse('headless-control-not-authorized');
    let unchanged = false;
    if (!verifyOnly) {
        const initial = snapshot(configPath);
        unchanged = merge(initial) === null && !refresh;
        beginPermissionInspection();
        if (unchanged && !permissionInspection?.paths.size) {
            permissionInspection = null;
            console.log('PASEO_MUSE_UNCHANGED'); return;
        }
    }
    if (process.env.PASEO_AGENT_ID) refuse('self-hosted-setup');
    const existing = pidInfo();
    const rows = inventory();
    verifySetupAncestry(rows);
    let owner = null;
    if (existing.info) {
        if (!live(existing.info.pid)) refuse('stale-pid-lock');
        if (existing.info.desktopManaged) refuse('desktop-owned');
        owner = platform === 'linux' ? linuxOwner(existing.info, rows) : platform === 'darwin' ? macOwner(existing.info, rows) : null;
        if (!owner) refuse('unknown-owner');
        if (!same(existing.snap.s, snapshot(pidPath).s) || !same(owner.unit.s, snapshot(owner.file).s) ||
            !same(owner.wrapper.snap.s, snapshot(owner.wrapper.file).s)) refuse('ownership-changed');
    } else if (candidates(rows).length) refuse('unknown-writer');
    if (permissionInspection?.paths.size) {
        // No chmod until PID, process ancestry, exact wrapper/unit, loaded service,
        // home selection and lack of drop-ins/other writers all agree on the owner.
        if (!owner) refuse('permission-recovery-owner-unverified');
        repairInspectedPermissions();
        const secured = pidInfo();
        if (secured.snap.text !== existing.snap.text) fail('permission-path-changed');
        existing.snap = secured.snap;
        const verified = linuxOwner(secured.info, inventory());
        if (verified.pid !== owner.pid || !same(owner.unit.s, verified.unit.s) ||
            !same(owner.wrapper.snap.s, verified.wrapper.snap.s)) refuse('ownership-changed');
    } else permissionInspection = null;
    if (unchanged) { console.log('PASEO_MUSE_UNCHANGED'); return; }
    // This read-only preflight must not depend on whether the profile needs a merge.
    // The caller retains the existing lifecycle implementation; no locks or files here.
    if (verifyOnly) {
        // A missing PID file is not evidence that the native service stopped.
        if (!existing.info) {
            if (platform === 'linux') {
                const state = serviceState();
                const stopped = state.ActiveState === 'inactive' && state.SubState === 'dead' ||
                    state.ActiveState === 'failed' && state.SubState === 'failed';
                if (!['loaded', 'not-found'].includes(state.LoadState) || !stopped || state.MainPID !== '0' ||
                    rows.some(row => inGroup(row, state.ControlGroup))) refuse('service-owner-unresolved');
            } else if (platform === 'darwin' && launchList().some(entry => entry.label === label)) {
                // A loaded launchd job can relaunch without a current PID. Do not replace its owner.
                refuse('service-owner-unresolved');
            }
        }
        console.log('PASEO_MUSE_OWNER_VERIFIED'); return;
    }
    if (owner) {
        console.log('PASEO_MUSE_RESTARTING');
        await checkpoint();
        // Arm restoration BEFORE stop: a timeout/failure can still have stopped it.
        restore = owner;
        owner.stop();
        await checkpoint();
        owner.stopped();
    }
    ensureNoWriters(owner);
    checkedPath(paseoHome, true);
    fs.mkdirSync(paseoHome, {recursive: true, mode: 0o700});
    reservePid();
    await checkpoint();
    ensureNoWriters(owner);
    if (owner) owner.stopped();
    // Re-read AFTER shutdown. Daemon shutdown and concurrent unrelated updates win.
    const before = snapshot(configPath);
    const next = merge(before);
    if (next !== null) {
        if (Buffer.byteLength(next, 'utf8') > maxSnapshotBytes) fail('metadata-too-large');
        temporary = path.join(paseoHome, `.config.setup-muse-${randomUUID()}.tmp`);
        const fd = fs.openSync(temporary, 'wx', before.s ? before.s.mode & 0o777 : 0o600);
        try {
            if (before.s && platform !== 'win32') {
                if (fs.fstatSync(fd).gid !== before.s.gid) fs.fchownSync(fd, before.s.uid, before.s.gid);
                fs.fchmodSync(fd, before.s.mode & 0o777);
            }
            secureTemporary(temporary, !!before.s);
            fs.writeFileSync(fd, next); fs.fsyncSync(fd);
        } finally { fs.closeSync(fd); }
        const pending = snapshot(temporary);
        await checkpoint();
        ensureNoWriters(owner);
        if (owner) owner.stopped();
        lockUnchanged();
        const current = snapshot(configPath);
        if (!same(before.s, current.s) || before.text !== current.text) fail('concurrent-config-change');
        const ready = snapshot(temporary);
        if (!same(pending.s, ready.s) || ready.text !== next) fail('temporary-file-changed');
        fs.renameSync(temporary, configPath);
        temporary = null;
        console.log('PASEO_MUSE_UPDATED');
    } else console.log('PASEO_MUSE_UNCHANGED');
}
(async () => {
    let failure = null;
    try { await main(); } catch (error) { failure = error; }
    finally {
        permissionInspection = null;
        try { if (temporary) fs.unlinkSync(temporary); } catch { failure = new Refusal('temporary-cleanup-failed', true); }
        try { releasePid(); } catch { failure = new Refusal('pid-release-failed', true); }
        if (restore) {
            try {
                if (!same(restore.unit.s, snapshot(restore.file).s) || !same(restore.wrapper.snap.s, snapshot(restore.wrapper.file).s)) fail('service-changed-before-restore');
                restore.start();
                // The old wrapper may inherit umask 002 on this intermediate
                // restart. Re-prove its ready PID owner and secure the new inode;
                // the later headless installer migrates the wrapper to umask 077.
                await finishRestoredPermissions(restore);
                console.log('PASEO_MUSE_RESTORED');
            }
            catch (error) {
                if (error instanceof Refusal && error.code === 'restart-pid-not-ready') console.log('Paseo Muse recovery: the restarted service did not provide a verified native PID within the retry limit. Inspect that service privately before rerunning setup.');
                failure = new Refusal('service-restore-failed', true);
            }
        }
    }
    if (failure) {
        const controlled = failure instanceof Refusal;
        const failed = !controlled || failure.failed;
        console.log(`PASEO_MUSE_DEFER_DAEMON_SETUP=1`);
        console.log(`Paseo Muse ${failed ? 'failed' : 'deferred'}: ${controlled ? failure.code : 'operation-failed'}.`);
        if (controlled && failure.code === 'stale-pid-lock') console.log('Paseo Muse recovery: inspect the stale paseo.pid privately; remove it manually only after every local owner is confirmed stopped.');
        if (controlled && (failure.code === 'unsafe-owner-or-mode' || failure.code.startsWith('permission-'))) console.log('Paseo Muse permissions: inspect ownership and write permissions on the selected home, PID and service paths. Automatic repair requires a verified default-home Linux setup-managed owner. Do not use recursive chmod or chown.');
        if (controlled && ['custom-home-unverified', 'custom-home-permissions-unverified', 'invalid-home-override'].includes(failure.code)) console.log('Paseo Muse home: PASEO_HOME must be unset or an absolute directory below the account HOME, not HOME itself. Custom directories must already exist, be private and account-owned, and contain no linked paths.');
        console.log('Quit Paseo Desktop or stop the owning local daemon, then rerun setup from a terminal outside Paseo. Keep Desktop closed during setup. If Go authentication changed, restart that owner to refresh its model catalog.');
        // Deferred lifecycle cases are warnings, not a claim that a profile was saved.
        process.exitCode = failed ? 1 : 0;
    }
})();
// END PASEO MUSE PROFILE
'@ | & node --input-type=commonjs - 2>$null
        $status = $LASTEXITCODE
        foreach ($line in $result) {
            switch -Exact ($line) {
                "PASEO_MUSE_UPDATED" { Write-Success "Paseo Muse managed profile synchronized." }
                "PASEO_MUSE_UNCHANGED" { Write-Debug "Paseo Muse managed profile is unchanged." }
                "PASEO_MUSE_PERMISSIONS_REPAIRED" { Write-Debug "Paseo Muse repaired verified managed-path permissions." }
                "PASEO_MUSE_RESTARTING" { Write-Warning "Restarting the setup-managed local Paseo daemon to refresh Muse. Active agents may be interrupted." }
                "PASEO_MUSE_RESTORED" { Write-Debug "Paseo Muse restored the local managed service." }
                default { if ($line -like 'Paseo Muse *' -or $line -like 'Quit Paseo Desktop *') { Write-Warning $line } }
            }
        }
        if ($status -ne 0) { Write-Warning "Paseo Muse profile setup failed. Inspect the local owner privately and rerun outside Paseo."; return $false }
        return $true
    } catch {
        Write-Warning "Paseo Muse profile setup failed. Rerun setup from a terminal outside Paseo."
        return $false
    } finally {
        $env:PASEO_MUSE_GO_CHANGED = $previous
        $env:NODE_OPTIONS = $previousNodeOptions
        $env:NODE_PATH = $previousNodePath
    }
}

function Remove-PaseoPlain {
    if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
        Write-Warning "Paseo Plain removal not confirmed: Node.js >=22.19 is required. Rerun setup or remove paseo-plain in the local daemon's Settings > Plugins."
        return $false
    }
    $result = @'
// BEGIN PASEO PLAIN RETIREMENT
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { spawnSync } = require('node:child_process');
const { createHash } = require('node:crypto');
const { isDeepStrictEqual } = require('node:util');
const id = 'paseo-plain';
let operation = 'preflight';
class SetupFailure extends Error {}
function deferred(reason) {
    console.log(`Paseo Plain removal deferred: ${reason}. Start the intended compatible local daemon and rerun setup, or remove paseo-plain in its Settings > Plugins. Do not enable plugins just for removal.`);
    process.exitCode = 1;
}
// BEGIN PASEO CLI IDENTITY
// Inspect package metadata before executing a CLI. A PATH hit is not proof of identity.
function cliInfo(file) {
    try { return fs.lstatSync(file); } catch (error) { if (error.code === 'ENOENT') return null; throw error; }
}
function cliHomeAlias(file, stat) {
    return process.platform === 'linux' && file === '/home' && stat.uid === 0 &&
        ['var/home', '/var/home'].includes(fs.readlinkSync(file)) && ['/', '/var', '/var/home'].every(dir => {
            const s = cliInfo(dir);
            return s?.isDirectory() && !s.isSymbolicLink() && s.uid === 0 && !(s.mode & 0o022);
        });
}
function cliDirectory(directory) {
    for (let current = path.resolve(directory); ; current = path.dirname(current)) {
        const s = cliInfo(current);
        if (!s) return false;
        if (s.isSymbolicLink() && cliHomeAlias(current, s)) continue;
        if (!s.isDirectory() || s.isSymbolicLink()) return false;
        if (process.platform !== 'win32' && (![0, process.getuid()].includes(s.uid) || s.mode & 0o002 && !(s.uid === 0 && s.mode & 0o1000))) return false;
        if (current === path.dirname(current)) return true;
    }
}
function cliRegular(file) {
    const s = cliInfo(file);
    return s?.isFile() && !s.isSymbolicLink() && s.size <= 2 * 1024 * 1024 &&
        cliDirectory(path.dirname(file)) && (process.platform === 'win32' || [0, process.getuid()].includes(s.uid) && !(s.mode & 0o002));
}
function cliPackage(root) {
    const metadata = path.join(root, 'package.json');
    if (!cliRegular(metadata)) return null;
    const text = fs.readFileSync(metadata, 'utf8');
    const data = JSON.parse(text);
    // Reject duplicate keys rather than guessing which package declaration is authoritative.
    const tokens = text.match(/"(?:[^"\\]|\\.)*"|[{}\[\]:,]/g) || [];
    const stack = [];
    for (let i = 0; i < tokens.length; i++) {
        const token = tokens[i];
        if (token === '{' || token === '[') stack.push(token === '{' ? new Set() : null);
        else if (token === '}' || token === ']') stack.pop();
        else if (token.startsWith('"') && tokens[i + 1] === ':') {
            const key = JSON.parse(token), names = stack[stack.length - 1];
            if (!names || names.has(key)) return null;
            names.add(key);
        }
    }
    const bin = typeof data?.bin === 'string' ? data.bin : data?.bin?.paseo;
    if (data?.name !== '@getpaseo/cli' || typeof data.version !== 'string' ||
        !/^\d+\.\d+\.\d+(?:[-+][\w.-]+)?$/.test(data.version) || typeof bin !== 'string' || path.isAbsolute(bin) ||
        bin.split(/[\\/]/).some(p => p === '..')) return null;
    const entry = path.resolve(root, bin);
    if (!entry.startsWith(root + path.sep) || !cliRegular(entry)) return null;
    return {root, entry, version: data.version};
}
function cliIdentity(command) {
    try {
        if (!path.isAbsolute(command) || !cliDirectory(path.dirname(command))) return null;
        if (process.platform === 'win32' && command.endsWith('.cmd')) {
            if (!cliRegular(command)) return null;
            for (const base of [path.join(path.dirname(command), 'node_modules'), path.resolve(path.dirname(command), '../install/global/node_modules')]) {
                const pkg = cliPackage(path.join(base, '@getpaseo/cli'));
                if (pkg) return pkg;
            }
            return null;
        }
        const s = cliInfo(command);
        if (!s || !s.isFile() && !s.isSymbolicLink()) return null;
        // Only the command symlink is allowed. Neither its ancestors nor target directories can be links.
        const target = s.isSymbolicLink() ? path.resolve(path.dirname(command), fs.readlinkSync(command)) : command;
        if (!cliRegular(target)) return null;
        for (let root = path.dirname(target); root !== path.dirname(root); root = path.dirname(root)) {
            if (!cliInfo(path.join(root, 'package.json'))) continue;
            const pkg = cliPackage(root);
            return pkg?.entry === target ? pkg : null;
        }
    } catch { /* Invalid or unverified candidates remain untouched and are never executed. */ }
    return null;
}
function selectPaseoCli(explicit = '') {
    const names = process.platform === 'win32' ? ['paseo.cmd', 'paseo.exe'] : ['paseo'];
    const candidates = explicit ? [explicit] : [
        ...names.map(name => path.join(os.homedir(), '.bun/bin', name)),
        ...(process.env.PATH || '').split(path.delimiter).filter(dir => path.isAbsolute(dir))
            .flatMap(dir => names.map(name => path.join(dir, name))),
    ];
    for (const candidate of new Set(candidates)) {
        const pkg = cliIdentity(candidate);
        if (pkg && /^0\.8\.\d+(?:[-+][\w.-]+)?$/.test(pkg.version)) return [process.execPath, pkg.entry];
        // A verified managed release owns selection even when Plain does not support it.
        if (pkg && (explicit || path.dirname(candidate) === path.join(os.homedir(), '.bun/bin'))) return null;
    }
    return null;
}
// END PASEO CLI IDENTITY
const info = cliInfo;
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const owns = (value, key) => Object.prototype.hasOwnProperty.call(value, key);
function checkedPath(file, directory = false) {
    // Validate every ancestor before reading metadata or asking Paseo to delete anything.
    if (!cliDirectory(path.dirname(file))) throw new SetupFailure('unsafe-path');
    const stat = info(file);
    if (stat && (stat.isSymbolicLink() || (directory ? !stat.isDirectory() : !stat.isFile()) ||
        process.platform !== 'win32' && (stat.uid !== process.getuid() || stat.mode & 0o022))) throw new SetupFailure('unsafe-path');
    return stat;
}
function jsonFile(file, fallback = null) {
    const stat = checkedPath(file);
    if (!stat) return fallback;
    if (stat.size > 2 * 1024 * 1024) throw new SetupFailure('metadata-limit');
    return jsonDocument(fs.readFileSync(file, 'utf8'));
}
function jsonDocument(text) {
    const data = JSON.parse(text);
    if (!object(data)) throw new SetupFailure('invalid-metadata');
    // Duplicate keys can conceal a source or endpoint from a different JSON reader.
    const tokens = text.match(/"(?:[^"\\]|\\.)*"|[{}\[\]:,]/g) || [];
    const stack = [];
    for (let i = 0; i < tokens.length; i++) {
        const token = tokens[i];
        if (token === '{' || token === '[') stack.push(token === '{' ? new Set() : null);
        else if (token === '}' || token === ']') stack.pop();
        else if (token.startsWith('"') && tokens[i + 1] === ':') {
            const key = JSON.parse(token), keys = stack[stack.length - 1];
            if (!keys || keys.has(key)) throw new SetupFailure('duplicate-key');
            keys.add(key);
        }
    }
    return data;
}
function legacyPidBoundary(home) {
    // A private home prevents group access to its native 0664 PID. This is a
    // read-only exception, not permission repair or authority to manage a service.
    const directory = checkedPath(home, true);
    if (!directory || directory.mode & 0o077) throw new SetupFailure('legacy-pid-requires-private-home');
    for (let current = path.dirname(home); ; current = path.dirname(current)) {
        const stat = info(current);
        if (stat?.isSymbolicLink() && cliHomeAlias(current, stat)) continue;
        const trustedStickyRoot = stat?.uid === 0 && Boolean(stat.mode & 0o1000);
        if (!stat?.isDirectory() || ![0, process.getuid()].includes(stat.uid) ||
            stat.mode & 0o022 && !trustedStickyRoot) throw new SetupFailure('legacy-pid-unsafe-ancestor');
        if (current === path.dirname(current)) break;
    }
}
function readPidState(home) {
    operation = 'pid preflight';
    const identity = stat => stat && ({dev: stat.dev, ino: stat.ino, uid: stat.uid, mode: stat.mode});
    const directory = checkedPath(home, true);
    if (!directory) throw new SetupFailure('pid-home-changed');
    const file = path.join(home, 'paseo.pid');
    const initial = info(file);
    if (!initial) return {home: identity(directory), pid: null, data: null};
    const validate = stat => {
        if (!stat || stat.isSymbolicLink() || !stat.isFile()) throw new SetupFailure('unsafe-path');
        if (stat.nlink !== 1) throw new SetupFailure('linked-pid-file');
        if (process.platform !== 'win32') {
            if (stat.uid !== process.getuid()) throw new SetupFailure('foreign-pid-owner');
            if (stat.mode & 0o022) {
                if ((stat.mode & 0o7777) !== 0o664) throw new SetupFailure('unsafe-pid-permissions');
                legacyPidBoundary(home);
            }
        }
        if (stat.size > 2 * 1024 * 1024) throw new SetupFailure('metadata-limit');
    };
    validate(initial);
    let fd;
    try {
        // Reject leaf swaps without following links or blocking on a substituted FIFO.
        const flags = fs.constants.O_RDONLY | (process.platform === 'win32' ? 0 : fs.constants.O_NOFOLLOW | fs.constants.O_NONBLOCK);
        try { fd = fs.openSync(file, flags); }
        catch (error) { if (error.code === 'ELOOP') throw new SetupFailure('pid-state-changed'); throw error; }
        const opened = fs.fstatSync(fd);
        validate(opened);
        if (!isDeepStrictEqual(identity(initial), identity(opened)) || opened.size !== initial.size) throw new SetupFailure('pid-state-changed');
        const buffer = Buffer.alloc(initial.size + 1);
        let length = 0;
        while (length < buffer.length) {
            const count = fs.readSync(fd, buffer, length, buffer.length - length, length);
            if (!count) break;
            length += count;
        }
        const after = fs.fstatSync(fd), current = info(file);
        validate(after);
        validate(current);
        if (!isDeepStrictEqual(identity(initial), identity(after)) || !isDeepStrictEqual(identity(initial), identity(current)) ||
            after.size !== initial.size || current.size !== initial.size || length !== initial.size ||
            !isDeepStrictEqual(identity(directory), identity(checkedPath(home, true)))) throw new SetupFailure('pid-state-changed');
        return {home: identity(directory), pid: {...identity(after), size: after.size}, data: jsonDocument(buffer.subarray(0, length).toString('utf8'))};
    } finally { if (fd !== undefined) fs.closeSync(fd); }
}
function childDirectory(parent, name) {
    if (!checkedPath(parent, true)) return null;
    const file = path.join(parent, name);
    return checkedPath(file, true) ? file : null;
}
function tree(root) {
    const entries = [];
    let bytes = 0;
    function visit(file, relative) {
        const stat = info(file);
        if (!stat || stat.isSymbolicLink() || !(stat.isDirectory() || stat.isFile()) ||
            process.platform !== 'win32' && stat.uid !== process.getuid()) throw new SetupFailure('unsafe-settings');
        if (entries.length >= 20000 || (bytes += stat.size) > 256 * 1024 * 1024) throw new SetupFailure('backup-limit');
        entries.push([relative, stat.isDirectory() ? null : createHash('sha256').update(fs.readFileSync(file)).digest('hex')]);
        if (stat.isDirectory()) for (const name of fs.readdirSync(file).sort()) visit(path.join(file, name), path.join(relative, name));
    }
    visit(root, '');
    return entries;
}
function privateDirectory(directory) {
    fs.mkdirSync(directory, {mode: 0o700});
    if (process.platform !== 'win32') return;
    const script = `$ErrorActionPreference = 'Stop'
$env:PSModulePath = "$PSHOME\\Modules"
$owner = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
$acl = [System.Security.AccessControl.DirectorySecurity]::new()
$acl.SetOwner($owner)
$acl.SetAccessRuleProtection($true, $false)
foreach ($sid in @($owner, [System.Security.Principal.SecurityIdentifier]::new('S-1-5-18'), [System.Security.Principal.SecurityIdentifier]::new('S-1-5-32-544'))) {
    $acl.AddAccessRule([System.Security.AccessControl.FileSystemAccessRule]::new($sid, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow'))
}
Set-Acl -LiteralPath $env:PASEO_PLAIN_RECOVERY_DIRECTORY -AclObject $acl`;
    const result = spawnSync(path.join(process.env.SystemRoot || 'C:\\Windows', 'System32/WindowsPowerShell/v1.0/powershell.exe'),
        ['-NoProfile', '-NonInteractive', '-EncodedCommand', Buffer.from(script, 'utf16le').toString('base64')], {
            env: {...process.env, PASEO_PLAIN_RECOVERY_DIRECTORY: directory}, shell: false, windowsHide: true,
            timeout: 15000, maxBuffer: 16384, stdio: ['ignore', 'pipe', 'pipe'],
        });
    if (result.error || result.status !== 0) throw new SetupFailure('private-backup-unavailable');
}
function backupSettings(home, native) {
    if (!native) return;
    operation = 'settings backup';
    const snapshot = tree(native);
    const parent = path.join(home, 'setup-recovery');
    if (!checkedPath(parent, true)) privateDirectory(parent);
    // Exclusive creation: an interrupted or previous retirement is never overwritten.
    const backup = path.join(parent, 'paseo-plain-retirement');
    if (checkedPath(backup, true)) throw new SetupFailure('retirement-backup-needs-review');
    privateDirectory(backup);
    const destination = path.join(backup, 'plugin-settings');
    for (const [relative, hash] of snapshot) {
        const target = path.join(destination, relative);
        if (hash === null) fs.mkdirSync(target, {mode: 0o700});
        else {
            const fd = fs.openSync(target, 'wx', 0o600);
            try { fs.writeFileSync(fd, fs.readFileSync(path.join(native, relative))); fs.fsyncSync(fd); }
            finally { fs.closeSync(fd); }
        }
    }
    if (!isDeepStrictEqual(snapshot, tree(native)) || !isDeepStrictEqual(snapshot, tree(destination))) throw new SetupFailure('settings-changed');
    if (process.platform !== 'win32') {
        // Persist directory entries as well as file contents before native removal.
        const directories = snapshot.filter(([, hash]) => hash === null).map(([relative]) => path.join(destination, relative)).reverse();
        for (const directory of [...directories, backup, parent, home]) {
            const fd = fs.openSync(directory, 'r');
            try { fs.fsyncSync(fd); } finally { fs.closeSync(fd); }
        }
    }
    return snapshot;
}
function withoutPlain(data) {
    const result = {...data};
    delete result[id];
    return result;
}
function otherConfig(config) {
    return {...config, plugins: withoutPlain(config.plugins || {})};
}
function sourcesAt(home) {
    const directory = childDirectory(home, 'plugins');
    const sources = directory ? jsonFile(path.join(directory, 'sources.json'), {}) : {};
    for (const record of Object.values(sources)) {
        if (!object(record) || typeof record.remote !== 'string' || !record.remote ||
            !(record.requestedRef === null || typeof record.requestedRef === 'string' && record.requestedRef) ||
            !(record.trackingBranch === null || typeof record.trackingBranch === 'string' && record.trackingBranch) ||
            !/^[0-9a-f]{40,64}$/.test(record.commit) || typeof record.pluginPath !== 'string' ||
            typeof record.checkoutRoot !== 'string' || !path.isAbsolute(record.checkoutRoot) ||
            Object.keys(record).some(key => !['remote', 'requestedRef', 'trackingBranch', 'commit', 'pluginPath', 'checkoutRoot'].includes(key))) {
            throw new SetupFailure('invalid-source-metadata');
        }
    }
    return sources;
}
function catalog(value) {
    if (!Array.isArray(value) || value.some(item => !object(item) || typeof item.id !== 'string') ||
        new Set(value.map(item => item.id)).size !== value.length) throw new SetupFailure('invalid-catalog');
    return value;
}
function main() {
    const [major, minor] = process.versions.node.split('.').map(Number);
    if (major < 22 || (major === 22 && minor < 19)) return deferred('node-version');
    const account = os.homedir();
    const override = process.env.PASEO_HOME;
    if (override !== undefined && (!override || !path.isAbsolute(override))) throw new SetupFailure('invalid-home');
    const home = path.resolve(override === undefined ? path.join(account, '.paseo') : override);
    const relative = path.relative(account, home);
    if (!relative || relative === '..' || relative.startsWith('..' + path.sep) || path.isAbsolute(relative)) throw new SetupFailure('outside-home');
    if (!cliDirectory(account)) throw new SetupFailure('unsafe-home');
    // Missing parents mean no installation; never create a daemon home for retirement.
    let current = account;
    for (const part of relative.split(path.sep)) {
        current = path.join(current, part);
        if (!checkedPath(current, true)) { console.log('Paseo Plain already absent.'); return; }
    }
    const configFile = path.join(home, 'config.json');
    const config = jsonFile(configFile);
    if (config?.plugins !== undefined && !object(config.plugins)) throw new SetupFailure('invalid-plugins');
    const sources = sourcesAt(home);
    if (!config || !owns(config.plugins || {}, id)) {
        if (owns(sources, id)) throw new SetupFailure('orphan-source-needs-review');
        console.log('Paseo Plain already absent.');
        return;
    }
    if (!object(config.plugins[id]) || config.plugins[id].source !== 'directory' ||
        typeof config.plugins[id].path !== 'string' || !path.isAbsolute(config.plugins[id].path)) throw new SetupFailure('invalid-registration');
    const managed = path.join(home, 'plugins', id);
    const nativeParent = childDirectory(home, 'plugin-settings');
    const native = nativeParent ? childDirectory(nativeParent, id) : null;
    if (owns(sources, id)) checkedPath(managed, true);
    const within = (parent, file) => file === parent || file.startsWith(parent + path.sep);
    const canonical = file => fs.existsSync(file) ? fs.realpathSync(file) : path.resolve(file);
    const deleted = file => owns(sources, id) && within(path.join(fs.realpathSync(home), 'plugins', id), canonical(file)) ||
        native && within(fs.realpathSync(native), canonical(file));
    // Native removal deletes the managed ID directory and settings, not external sources.
    // Refuse registrations/source records that share either deletion tree, including aliases.
    for (const [key, source] of Object.entries(config.plugins)) {
        if (!object(source) || typeof source.path !== 'string' || !path.isAbsolute(source.path)) throw new SetupFailure('invalid-registration');
        if (key !== id && deleted(source.path) || key === id && native && within(fs.realpathSync(native), canonical(source.path))) {
            throw new SetupFailure('shared-source-needs-review');
        }
    }
    for (const [key, source] of Object.entries(sources)) {
        if (key !== id && deleted(source.checkoutRoot)) throw new SetupFailure('shared-source-needs-review');
    }
    for (const preserved of ['plugin-data', 'setup-recovery']) {
        if (deleted(path.join(home, preserved))) throw new SetupFailure('shared-source-needs-review');
    }
    const recoveryParent = childDirectory(home, 'setup-recovery');
    const migration = recoveryParent ? childDirectory(recoveryParent, 'paseo-plain-release-to-main') : null;
    if (migration && jsonFile(path.join(migration, 'state.json'))?.phase !== 'complete') throw new SetupFailure('migration-needs-review');
    const localTarget = value => typeof value === 'string' && /^(127\.0\.0\.1|localhost|\[::1\]):[1-9][0-9]{0,4}$/.test(value) && Number(value.split(':').pop()) <= 65535;
    if (config.daemon !== undefined && !object(config.daemon)) throw new SetupFailure('invalid-daemon');
    if (config.daemon?.listen !== undefined && !localTarget(config.daemon.listen)) return deferred('nonlocal-endpoint');
    const pidState = readPidState(home);
    const pid = pidState.data;
    if (pid && [pid.listen, pid.sockPath].some(value => value !== undefined && !localTarget(value))) return deferred('nonlocal-pid-endpoint');
    const paseo = selectPaseoCli(process.argv[2] || '');
    if (!paseo) return deferred('compatible-cli-unavailable');
    const run = (args, timeout = 20000) => {
        // Native heartbeats change timestamps, not identity, permissions or contents.
        // Recheck before status can probe an endpoint and before every plugin command.
        if (!isDeepStrictEqual(pidState, readPidState(home))) throw new SetupFailure('pid-state-changed');
        operation = args[0] === 'daemon' ? 'daemon status' : `plugin ${args[3]}`;
        const env = {...process.env, PASEO_HOME: home};
        delete env.PASEO_HOST;
        const result = spawnSync(paseo[0], [...paseo.slice(1), ...args], {
            env, cwd: account, encoding: 'utf8', timeout, maxBuffer: 2 * 1024 * 1024,
            stdio: ['ignore', 'pipe', 'pipe'], shell: false,
        });
        if (result.error) throw new SetupFailure(result.error.code === 'ETIMEDOUT' ? 'timeout' : 'spawn-failed');
        if (result.status !== 0) throw new SetupFailure(Number.isInteger(result.status) ? `exit-${result.status}` : 'terminated');
        try { return JSON.parse(result.stdout); } catch { throw new SetupFailure('invalid-response-json'); }
    };
    const status = run(['daemon', 'status', '--json']);
    if (!object(status) || status.localDaemon !== 'running' || status.connectedDaemon !== 'reachable' ||
        typeof status.home !== 'string' || fs.realpathSync(status.home) !== fs.realpathSync(home) || !localTarget(status.listen)) return deferred('local-daemon-unavailable');
    if (![status.cliVersion, status.daemonVersion].every(v => typeof v === 'string' && /^0\.8\.\d+(?:[-+][\w.-]+)?$/.test(v))) return deferred('incompatible-daemon');
    const args = ['--host', status.listen, 'plugin'];
    const before = catalog(run([...args, 'ls', '--json']));
    if (!before.some(item => item.id === id)) throw new SetupFailure('registration-catalog-mismatch');
    const snapshot = backupSettings(home, native);
    operation = 'removal preflight';
    if (!isDeepStrictEqual(config, jsonFile(configFile)) || !isDeepStrictEqual(sources, sourcesAt(home)) ||
        native && !isDeepStrictEqual(snapshot, tree(native))) throw new SetupFailure('state-changed');
    if (owns(sources, id)) checkedPath(managed, true);
    if (native) checkedPath(native, true);
    run([...args, 'remove', id, '--json'], 180000);
    const after = catalog(run([...args, 'ls', '--json']));
    operation = 'removal verification';
    const afterConfig = jsonFile(configFile);
    const afterSources = sourcesAt(home);
    if (!afterConfig || owns(afterConfig.plugins || {}, id) || owns(afterSources, id) || after.some(item => item.id === id) ||
        !isDeepStrictEqual(otherConfig(config), otherConfig(afterConfig)) ||
        !isDeepStrictEqual(withoutPlain(sources), afterSources) ||
        !isDeepStrictEqual(before.filter(item => item.id !== id).map(item => item.id).sort(), after.map(item => item.id).sort()) ||
        owns(sources, id) && info(managed) || native && info(native)) throw new SetupFailure('removal-not-confirmed');
    console.log('Paseo Plain removed; saved plugin-data, external sources, and recovery backups preserved. Native settings, when present, were backed up under setup-recovery/paseo-plain-retirement.');
}
try { main(); } catch (error) {
    const reason = error instanceof SetupFailure ? error.message : error instanceof SyntaxError ? 'invalid-json' :
        ['EACCES', 'EPERM', 'ENOENT', 'EEXIST', 'ENOSPC', 'EROFS'].includes(error?.code) ? error.code : 'unexpected-error';
    console.log(`Paseo Plain removal failure: ${operation}: ${reason}.`);
    console.log('Removal is not confirmed. Inspect the intended local daemon in Settings > Plugins and review setup-recovery before retrying. Keep backups; do not reinstall the retired plugin.');
    process.exitCode = 1;
}
// END PASEO PLAIN RETIREMENT

'@ | & node --input-type=commonjs - "$env:PASEO_VALIDATED_CMD" 2>$null
    $status = $LASTEXITCODE
    $message = $result -join "`n"
    if ($status -ne 0) {
        if ($message.StartsWith("Paseo Plain removal failure:") -or $message.StartsWith("Paseo Plain removal deferred:")) { Write-Warning $message }
        else { Write-Warning "Paseo Plain removal not confirmed: helper failed. Inspect the local daemon's Settings > Plugins before retrying." }
        return $false
    }
    if ($message.StartsWith("Paseo Plain removed;") -or $message -eq "Paseo Plain already absent.") { Write-Success $message }
    else {
        Write-Warning "Paseo Plain removal not confirmed: unexpected helper response."
        return $false
    }
    return $true
}

function Install-PortlessCli {
    if (Get-Command portless -ErrorAction SilentlyContinue) {
        Write-Debug "Portless CLI is already installed."
        return
    }

    Write-Host "$arrow Installing Portless CLI..." -ForegroundColor Cyan

    # Ensure bun is available
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

# Remove the managed footprint of the retired RTK tool.
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

# Pi's package minimum is lower than the shared skills CLI minimum.
function Test-PiNodeRuntimeReady {
    try {
        & node -e 'const [major, minor] = process.versions.node.split(".").map(Number); process.exit((major > 22 || (major === 22 && minor >= 19)) && typeof require("node:fs").globSync === "function" ? 0 : 1)' *> $null
        return ($LASTEXITCODE -eq 0)
    }
    catch { return $false }
}

function Test-SharedNodeRuntimeReady {
    param([string]$Node = 'node')
    try {
        & $Node -e 'const [major, minor] = process.versions.node.split(".").map(Number); process.exit((major > 22 || (major === 22 && minor >= 20)) && typeof require("node:fs").globSync === "function" ? 0 : 1)' *> $null
        return ($LASTEXITCODE -eq 0)
    }
    catch { return $false }
}

# New selections must have an official Windows binary. Never compile a fallback.
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

# Kept separate so offline fixtures can inspect the child without loading live profiles.
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

# Test chezmoi-owned activation with the persisted Windows PATH, not setup's PATH.
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
        # Expand registry PATH entries only after removing the inherited runtime PATH.
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
        # Encode the optional path separately so it cannot become PowerShell source.
        $encodedPi = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($CanonicalPi))
        $probe = @'
$ErrorActionPreference = 'Stop'
try {
    if (-not (Get-Command mise -ErrorAction SilentlyContinue)) { exit 1 }
    $expectedNode = (& mise which -C $env:USERPROFILE node 2>$null | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or -not $expectedNode) { exit 1 }
    & node -e 'const fs = require("node:fs"); const [major, minor] = process.versions.node.split(".").map(Number); process.exit((major > 22 || (major === 22 && minor >= 20)) && typeof fs.globSync === "function" && fs.realpathSync(process.execPath) === fs.realpathSync(process.argv[1]) ? 0 : 1)' $expectedNode *> $null
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

# Inherited Node is not evidence of a durable global mise selection.
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
        # mise ls --global filters active sources. HOME overrides hide global rows,
        # so inventory at the drive root, but activate and verify at HOME below.
        $inventoryRoot = [System.IO.Path]::GetPathRoot($env:USERPROFILE)
        if (-not $inventoryRoot) { throw 'USERPROFILE must be an absolute path.' }
        for ($attempt = 1; $attempt -le 2; $attempt++) {
            $inventoryText = (& mise ls -C $inventoryRoot --global --json node 2>$null | Out-String).Trim()
            if ($LASTEXITCODE -ne 0 -or -not $inventoryText) { throw 'Cannot read global mise Node inventory.' }
            # Wrap the JSON so PowerShell does not flatten empty or one-row arrays.
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
        # No explicit node@ override: preserve and detect conflicting HOME pins.
        $miseEnv = (& mise env -C $env:USERPROFILE -s pwsh 2>$null | Out-String)
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($miseEnv)) { throw 'Failed to activate the shared mise environment.' }
        Invoke-Expression -Command $miseEnv -ErrorAction Stop | Out-Null
        if (-not (Test-SharedNodeRuntimeReady)) { throw 'HOME does not select Node >=22.20 with fs.globSync; review mise overrides.' }
        & npm --version *> $null
        if ($LASTEXITCODE -ne 0) { throw 'npm is unavailable under the shared Node runtime.' }
        if (-not (Test-SharedNodeShell)) {
            throw 'A fresh PowerShell cannot use the shared mise Node/npm runtime. Apply the chezmoi mise activation and review HOME overrides.'
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

# Remove the managed footprint of the retired Attention-kind guidance.
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

    # Preflight every target before changing any file.
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

# Skills and Pi must agree on the same durable shared Node selection.
function Test-SkillsCliNodeRuntimeReady {
    return (Test-SharedNodeRuntimeReady)
}

function Enable-SkillsCliNodeRuntime {
    return (Enable-SharedNodeRuntime)
}

# Install/update one copied global skill for every supported AI coding harness.
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
    # Codex, Gemini CLI, and Pi discover the skills CLI's shared user copy.
    $skillDirs = @(
        (Join-Path $claudeDir "skills\$SkillName"),
        (Join-Path $env:USERPROFILE ".agents\skills\$SkillName")
    )
    $requiredFiles = @("SKILL.md") + $AdditionalFiles

    foreach ($skillDir in $skillDirs) {
        foreach ($relativeFile in $requiredFiles) {
            $skillFile = Join-Path $skillDir $relativeFile
            $artifactPath = $skillFile
            # Reject links in the file and every directory inside the skill copy.
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

# Retire Simple English from global skill copies and skills CLI update records.
function Remove-SimpleEnglishSkill {
    return (Invoke-MattPocockSkillPolicy -Mode remove-simple-english)
}

# Retire global show-me copies on the next setup run.
function Remove-ShowMeSkill {
    return (Invoke-MattPocockSkillPolicy -Mode remove-show-me)
}

# Retire PR Lens from global skill copies and skills CLI update records.
function Remove-PrLensSkill {
    return (Invoke-MattPocockSkillPolicy -Mode remove-pr-lens)
}

# Remove setup-managed Impeccable resources without affecting sibling agent tooling.
function Remove-ImpeccableResources {
    $paths = @(
        (Join-Path $env:USERPROFILE ".claude\skills\impeccable"),
        (Join-Path $env:USERPROFILE ".agents\skills\impeccable"),
        (Join-Path $env:USERPROFILE ".cursor\skills\impeccable"),
        (Join-Path $env:USERPROFILE ".gemini\skills\impeccable"),
        (Join-Path $env:USERPROFILE ".pi\agent\skills\impeccable"),
        (Join-Path $env:USERPROFILE ".cursor\agents\impeccable-manual-edit-applier.md"),
        (Join-Path $env:USERPROFILE ".cursor\agents\impeccable-asset-producer.md"),
        (Join-Path $env:USERPROFILE ".cursor\agents\impeccable-documenter.md"),
        (Join-Path $env:USERPROFILE ".cursor\agents\impeccable-finish-reviewer.md")
    )
    $removed = $false
    $failed = @()

    foreach ($path in $paths) {
        if ($script:PiProfileMutationsBlocked -and $path -eq (Join-Path $env:USERPROFILE '.pi/agent/skills/impeccable')) { continue }
        $item = Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        if ($null -eq $item) {
            continue
        }

        try {
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                Remove-Item -LiteralPath $path -Force -ErrorAction Stop
            }
            elseif ($item.PSIsContainer) {
                Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
            }
            else {
                Remove-Item -LiteralPath $path -Force -ErrorAction Stop
            }
            $removed = $true
        }
        catch {
            $failed += $path
        }
    }

    if ($failed.Count -gt 0) {
        Write-Warning "Failed to remove legacy Impeccable resources: $($failed -join ', ')"
    }
    elseif ($removed) {
        Write-Success "Legacy Impeccable resources removed."
    }
    else {
        Write-Debug "No legacy Impeccable resources found."
    }
}

# Remove stale Pi installs from Bun-managed global locations.
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

# Validate and repair npm's effective user configuration before setup mutates
# any npm-owned package tree. npm performs registry-scoped auth migration while
# all command output stays out of the setup transcript.
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

# Function to install/update Pi coding agent
function Install-PiCli {
    $script:PiRuntimePreflightPassed = $false
    $newPackage = "@earendil-works/pi-coding-agent"
    $oldPackage = "@mariozechner/pi-coding-agent"
    $localPrefix = Join-Path $env:USERPROFILE ".local"
    # npm places Windows global command shims directly in the prefix directory.
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

        # Remove old npm-package ownership before installing so npm can claim the canonical shim.
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

# Native Go auth only. -CheckCatalog reads installed metadata without credentials.
# Keep the embedded Node body identical in all six setup scripts.
function Set-PiOpenCodeGoProvider {
    param([switch]$CheckCatalog)
    $operations = 'preflight|home|pi-package|pi-dependency|go-catalog|environment-file|active-profile|models-json|auth-lock|lock-dependency|auth-preflight|profile-create|lock-acquire|auth-read|auth-write|auth-cleanup|lock-release'
    $reasons = 'acl-timeout|acl-unavailable|acl-unsafe|catalog-incompatible|concurrent-metadata-change|duplicate-json-key|file-changed|go-provider-overridden|invalid-credential|invalid-json|invalid-json-object|invalid-key-format|invalid-mode|invalid-providers|linked-directory|linked-or-nonregular-file|lock-compromised|lock-unavailable|lock-unverified|lock-version-unsupported|missing-directory|node-incompatible|oversized-metadata|pi-dependency-unavailable|pi-package-unavailable|unexpected-dependency|unowned-auth-file|unowned-home|unsafe-file-permissions|unsafe-json-number|unsafe-lock|unsafe-lock-dependency|unsafe-path|unsafe-profile|untrusted-directory|operation-failed|EACCES|EPERM|EROFS|ENOSPC|EDQUOT|ENOENT|ENOTDIR|EISDIR|ELOOP|EEXIST|EIO|ELOCKED|ECOMPROMISED|MODULE_NOT_FOUND|ERR_PACKAGE_PATH_NOT_EXPORTED'
    $script:PiOpenCodeGoChanged = $false
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
function directoryChain(directory, missing = false, installed = false) {
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
        if (!windows && (![0, uid].includes(stat.uid) || ((stat.mode & (installed ? 0o002 : 0o022)) && !stickyRoot))) fail('untrusted-directory');
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
    const model = catalog['openai-responses']?.[id];
    if (matches.length !== 1 || matches[0] !== model || model.provider !== 'opencode-go' ||
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
    directoryChain(profile, true);
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
    directoryChain(profile);
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
        directoryChain(profile);
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
            directoryChain(profile);
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
        # Windows PowerShell 5.1 drops empty native arguments; pass the full default.
        $active = if ($env:PI_CODING_AGENT_DIR) { $env:PI_CODING_AGENT_DIR } else { Join-Path $env:USERPROFILE '.pi/agent' }
        # Only code and nonsecret paths cross stdin/argv; the key stays in Node memory.
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
            'missing-key' { Write-Warning "Pi Go authentication not supplied: add OPENCODE_GO_API_KEY to ~/.env.local. Existing credentials were preserved; the Muse profile can still be configured." }
            'updated' { $script:PiOpenCodeGoChanged = $true; Write-Success "Pi Go credential synchronized in the active Pi profile." }
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

# Force Pi defaults: GPT-6 Astra (OpenAI Codex) with xhigh thinking on all machines.
# Chezmoi owns settings.json long-term; this seeds fresh machines and repairs drift.
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

# Read a KEY=VALUE pair from ~/.env.local (strips optional export/quotes).
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

# Paseo Desktop uses Electron userData, not the standalone daemon's PASEO_HOME.
function Get-PaseoReleaseChannel {
    $channel = Get-EnvLocalValue "PASEO_CHANNEL"
    if ([string]::IsNullOrEmpty($channel)) { $channel = "beta" }
    if ($channel -cnotin @("beta", "stable")) {
        throw "Invalid PASEO_CHANNEL. Use beta or stable."
    }
    return $channel
}

function Test-PaseoDesktopRunning {
    # Do not edit a running app's cached settings or stop its bundled daemon.
    return @((Get-Process -ErrorAction Stop) | Where-Object { $_.ProcessName -ieq "Paseo" }).Count -gt 0
}

function Set-PaseoDesktopChannel {
    $channel = Get-PaseoReleaseChannel
    $tempPath = $null
    try {
        $directory = $env:PASEO_ELECTRON_USER_DATA_DIR
        if (-not $directory) {
            if (-not $env:APPDATA) { throw "APPDATA is unavailable." }
            $directory = Join-Path $env:APPDATA "Paseo"
        }
        if (-not [System.IO.Path]::IsPathRooted($directory)) { throw "The user-data path must be absolute." }
        if ((Test-EnvLocalFlag "HEADLESS") -and -not (Test-Path -LiteralPath $directory)) {
            Write-Debug "No Paseo Desktop profile on this headless machine; skipping client channel setup."
            return $true
        }
        $settingsPath = Join-Path $directory "desktop-settings.json"
        $parent = $directory
        while ($parent) {
            $item = Get-Item -LiteralPath $parent -Force -ErrorAction SilentlyContinue
            if ($item -and (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -or -not $item.PSIsContainer)) {
                Write-Warning "Unsafe Paseo Desktop directory. Linked or non-directory paths are not changed."
                return $false
            }
            $parent = Split-Path -Parent $parent
        }
        $item = Get-Item -LiteralPath $settingsPath -Force -ErrorAction SilentlyContinue
        if ($item -and (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -or $item.PSIsContainer)) {
            Write-Warning "Unsafe Paseo Desktop settings path. Leaving it unchanged."
            return $false
        }
        $exists = $null -ne $item
        if ($exists) {
            $raw = Get-Content -LiteralPath $settingsPath -Raw -ErrorAction Stop
            $document = $raw | ConvertFrom-Json -ErrorAction Stop
            if ($document -isnot [PSCustomObject] -or -not $raw.TrimStart().StartsWith('{') -or
                $document.version -ne 1 -or $document.version -is [string] -or
                $document.settings -isnot [PSCustomObject] -or
                ($document.PSObject.Properties['migrations'] -and $document.migrations -isnot [PSCustomObject])) {
                Write-Warning "Invalid or unsupported Paseo Desktop settings. Leaving the file unchanged."
                return $false
            }
            if ($document.settings.releaseChannel -ceq $channel -and
                $document.migrations.legacyRendererSettingsImported -is [bool] -and $document.migrations.legacyRendererSettingsImported) {
                Write-Debug "Paseo Desktop release channel is already $channel."
                return $true
            }
        } else {
            $document = [PSCustomObject]@{ version = 1; settings = [PSCustomObject]@{}; migrations = [PSCustomObject]@{} }
        }
        if (Test-PaseoDesktopRunning) {
            Write-Warning "Close Paseo Desktop and rerun setup to change its release channel. Setup does not stop the app or its daemon."
            return $false
        }
        $document.settings | Add-Member -NotePropertyName releaseChannel -NotePropertyValue $channel -Force
        if (-not $document.PSObject.Properties['migrations']) {
            $document | Add-Member -NotePropertyName migrations -NotePropertyValue ([PSCustomObject]@{})
        }
        # Match upstream's channel patch so a legacy renderer cannot restore stable.
        $document.migrations | Add-Member -NotePropertyName legacyRendererSettingsImported -NotePropertyValue $true -Force
        $json = $document | ConvertTo-Json -Depth 100 -WarningAction Stop -ErrorAction Stop
        [System.IO.Directory]::CreateDirectory($directory) | Out-Null
        $tempPath = Join-Path $directory ("desktop-settings.json.tmp." + [guid]::NewGuid())
        [System.IO.File]::WriteAllText($tempPath, $json + "`n", [System.Text.UTF8Encoding]::new($false))
        if ($exists) {
            [System.IO.File]::Replace($tempPath, $settingsPath, [NullString]::Value)
        } else {
            [System.IO.File]::Move($tempPath, $settingsPath)
        }
        Write-Success "Paseo Desktop release channel set to $channel. Open Desktop and check for updates in Settings > About."
        return $true
    } catch {
        # JSON errors can include private settings. Never log the raw exception.
        Write-Warning "Could not select the Paseo Desktop release channel. Make sure that the app is closed and its settings are valid and writable."
        return $false
    } finally {
        if ($tempPath -and (Test-Path -LiteralPath $tempPath)) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
    }
}

# Remove the retired Synthetic provider without touching other providers or auth.json.
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
        # Parser errors can contain credentials from the file. Do not print them.
        Write-Warning "Failed to remove the Synthetic provider from $modelsPath."
        return $false
    }
}

# Seed the z.ai provider block (GLM Coding Plan) into Pi's models.json.
# The API key comes from ZAI_API_KEY in ~/.env.local; it is never stored in
# this repository. Existing z.ai keys are preserved. Seeding follows key
# presence: any machine with the key gets the provider, and only work
# machines are warned when the key is missing.
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

# Function to set or remove JSON properties on a PSCustomObject
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

# Function to remove the tintinweb Pi subagents extension (idempotent, non-fatal)
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

    # Fallback when the pi CLI is unavailable: strip both package sources
    # directly from settings.json.
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

# Pi prose retirement. The embedded program matches all five Bash scripts.
# Secure only managed Pi directory boundaries; metadata remains with its validators.
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
        if (!managed && (stat.mode & 0o022) && !stickyRoot) fail('unsafe-ancestor');
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
    function unchanged() {
        for (const [file, before] of plan) {
            const after = inspect(file, managed.has(file));
            if (Boolean(before) !== Boolean(after) || before && (before.dev !== after.dev || before.ino !== after.ino || before.mode !== after.mode)) fail('directory-changed');
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
                if (!expected || expected.dev !== pinned.dev || expected.ino !== pinned.ino || expected.mode !== pinned.mode) fail('directory-changed');
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
            if (!opened.isDirectory() || opened.uid !== uid || before.ino !== opened.ino || before.dev !== opened.dev) fail('directory-changed');
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
# End Pi prose retirement.

# Function to remove retired Pi RPIV packages (ask-user-question and todo)
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

    # Fallback when the pi CLI is unavailable: strip both package sources
    # directly from settings.json.
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

# Repair only the active profile's managed adapter metadata; npm owns lockfiles.
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
        # Forward only controlled diagnostics, never arbitrary Node output.
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

# Function to install/update Pi MCP adapter extension
function Setup-PiMcpAdapter {
    # 2.33.0 uses remote preview dependencies rejected by managed npm policy.
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

# Function to install/update Pi Claude bridge extension
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

# Function to remove legacy Pi Ask User and install/update the Pi companion packages
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

# Keep shared skills canonical for Pi and suppress stale direct/package collisions.
function Set-PiSkillOwnership {
    if ($script:PiProfileMutationsBlocked) { return $true }
    return (Invoke-MattPocockSkillPolicy -Mode ownership)
}

# Configure pi-autoresearch without overriding Pi transcript search.
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

# Function to remove Pi goal/autoresearch package sources from settings when disabled
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

# Function to install/update Pi goal and autoresearch extensions
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

# Shared policy for full-suite inventory, safe retirement, and Pi ownership.
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
        'resolving-merge-conflicts', 'setup-matt-pocock-skills', 'tdd', 'to-spec', 'to-tickets',
        'triage', 'wayfinder', 'wizard', 'claude-handoff', 'implement-spec', 'loop-me', 'retro',
        'setup-ts-deep-modules', 'writing-beats', 'writing-fragments', 'writing-shape',
        'git-guardrails-claude-code', 'migrate-to-shoehorn', 'scaffold-exercises', 'setup-pre-commit',
        'grill-me', 'grilling', 'handoff', 'teach', 'to-questionnaire', 'wait-what', 'writing-for-agents'
    ];
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
        const inventory = unique([...known, ...(manifest?.skills || []), ...tracked]);
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

# Install all upstream categories, including experimental skills, for four agents.
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
        # Resolve npm's policy before isolating the native CLI's global targets.
        # Keep cwd and all other npm configuration unchanged.
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
        # Environment names are case-sensitive on Unix PowerShell, unlike Windows.
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


# Remove legacy Compound Engineering resources without affecting unrelated Windows agent tooling.
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

        # The Pi plugin installer leaves its install manifest behind. The
        # manifest is part of the legacy installation and must be removed too.
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

    # Get installed packages
    $installedPackages = @()
    try {
        # Export the list to a temporary JSON file to handle large outputs
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

    # Install missing packages
    foreach ($package in $wingetPackages) {
        if ($package -eq "Notion.ntn" -and $env:PROCESSOR_ARCHITECTURE -ne "AMD64") {
            Write-Warning "Notion CLI supports Windows x64 only; skipping on $env:PROCESSOR_ARCHITECTURE."
            continue
        }

        $isInstalled = $false
        
        # First check our cached list
        if ($installedPackages -contains $package) {
            $isInstalled = $true
        }
        else {
            # Fallback to direct check if cached list failed
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
        # else {
        #     Write-Host "$warnIcon $package is already installed." -ForegroundColor Yellow
        # }
    }
}

function Install-WingetUpdates {
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

# Function to setup ~/Code directory
# Report whether the machine has a reboot pending. Informational only; never
# affects the run's exit status. Checks the standard pending-reboot registry
# locations and reports which of them triggered.
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

    # Create ~/Code directory if it doesn't exist
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
    # Ensure profiles, defaults, and font objects exist
    if (-not $settings.profiles) {
        $settings | Add-Member -MemberType NoteProperty -Name profiles -Value @{}
    }
    if (-not $settings.profiles.defaults) {
        $settings.profiles | Add-Member -MemberType NoteProperty -Name defaults -Value @{}
    }
    if (-not $settings.profiles.defaults.font) {
        $settings.profiles.defaults | Add-Member -MemberType NoteProperty -Name font -Value @{}
    }

    # Set the font face
    $settings.profiles.defaults.font.face = "JetBrainsMono Nerd Font Mono"

    $settings | ConvertTo-Json -Depth 10 | Set-Content -Path $settingsPath
    Write-Host "$success Windows Terminal settings updated." -ForegroundColor Green
}



# Logging uses .NET multipart support available in Windows PowerShell 5.1 as
# well as PowerShell 7. It must not depend on tools installed by setup.
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
    # Inspect ancestors without resolving links into another tree. Missing
    # components are allowed only when preparing our own log directory/files.
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
    # Do not forward a transcript to a redirect destination. Keep normal proxy
    # and certificate validation behavior; never install a validation callback.
    $handler.AllowAutoRedirect = $false
    return [Net.Http.HttpClient]::new($handler)
}

function Send-SetupLogRequest {
    param([string]$LogPath, [string]$Hostname, [ValidateRange(1, 30)][int]$TimeoutSeconds)
    $file = $client = $request = $response = $null
    $originalProtocol = [Net.ServicePointManager]::SecurityProtocol
    try {
        Assert-SetupLogPath $LogPath
        # Refuse a file still open for writing, including a running transcript.
        $file = [IO.File]::Open($LogPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        $client = New-SetupLogHttpClient
        $client.Timeout = [TimeSpan]::FromSeconds($TimeoutSeconds)
        # Old .NET installations can select TLS 1.0 explicitly. Add TLS 1.2
        # only in that case, preserve SystemDefault, and restore caller state.
        if ($PSVersionTable.PSVersion.Major -le 5 -and [int]$originalProtocol -ne 0) {
            [Net.ServicePointManager]::SecurityProtocol = $originalProtocol -bor [Net.SecurityProtocolType]::Tls12
        }
        $uri = 'https://logs.scowalt.com/upload?hostname=' + [Uri]::EscapeDataString($Hostname)
        $request = [Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::Post, $uri)
        $request.Content = [Net.Http.MultipartFormDataContent]::new()
        $request.Content.Add([Net.Http.StreamContent]::new($file), 'file', [IO.Path]::GetFileName($LogPath))
        $response = $client.SendAsync($request, [Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
        # Only status is needed. Never print or parse an untrusted response body.
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
        # The HttpClient assembly may not have loaded if opening the file failed.
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
        # Keep the state file as an exclusive lease throughout all attempts.
        # An uploaded record stays on disk, avoiding a close/delete/reopen race.
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
        # Raw exceptions can contain server bodies, proxy URLs or secrets.
        # Invalid/linked/locked metadata is preserved for manual review.
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
        # Enumerate lazily, with a 60-second budget shared by at most three logs.
        foreach ($path in [IO.Directory]::EnumerateFiles($directory, '*.log.upload.json')) {
            $remaining = [int][Math]::Floor(60 - $watch.Elapsed.TotalSeconds)
            if ($count -ge 3 -or $remaining -lt 1) { break }
            $stream = $null
            try {
                Assert-SetupLogPath $path
                $stream = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
                $state = Read-SetupLogUploadState $stream
            }
            catch { continue } # Leave malformed, linked or busy state untouched.
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

function Invoke-WindowsSetupTasks {
    $piSetupFailed = $false
    $piOpenCodeGoReady = $false
    $script:PiProfileMutationsBlocked = $false
    $paseoPlainSetupFailed = $false
    $mattPocockSetupFailed = $false
    $simpleEnglishSetupFailed = $false
    $showMeSetupFailed = $false
    $prLensSetupFailed = $false
    $windowsIcon = [char]0xf17a  # Windows logo
    Write-Host "`n$windowsIcon Windows Development Environment Setup" -ForegroundColor White -BackgroundColor DarkBlue
    Write-Host "Version 154 | Last changed: Handle legacy PID permissions during Plain retirement"

    Assert-HeadlessPaseoUnsupported
    $null = Get-PaseoReleaseChannel

    # Create placeholder token files early
    New-TokenPlaceholders

    Write-Section "Package Installation"
    Install-WingetPackages
    Install-SecretsManager
    Install-GcloudCli

    Write-Section "SSH Configuration"
    Test-GitHubSSHKey # this needs to be run before chezmoi to get access to dotfiles

    if ($env:USERNAME -eq "scowalt") {
        Write-Section "Code Directory Setup"
        Setup-CodeDirectory

        Write-Section "Dotfiles Management"
        Install-Chezmoi
        Update-Chezmoi
    }

    Write-Section "Terminal Configuration"
    Set-StarshipInit
    Set-SfwWrappers
    Set-WindowsTerminalConfiguration
    
    Write-Section "Additional Development Tools"
    if (-not (Set-PaseoDesktopChannel)) { throw "Paseo Desktop channel setup failed." }
    Install-GiteaClient
    Install-SocketFirewall
    Install-ClaudeCode
    Install-GeminiCli
    Install-CodexCli
    Install-PortlessCli
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
        # Re-pin the adapter before any operation resolves the shared npm tree.
        if ($piOpenCodeGoReady -and (Prepare-PiMcpAdapter)) {
            if (-not (Setup-PiMcpAdapter)) { $piSetupFailed = $true }
            if (-not (Remove-PiSubagents)) { $piSetupFailed = $true }
            if (-not (Remove-PiRpivPackages)) { $piSetupFailed = $true }
            if (-not (Setup-PiClaudeBridge)) { $piSetupFailed = $true }
            if (-not (Setup-PiCompanionPackages)) { $piSetupFailed = $true }
            if (-not (Setup-PiGoalAutoresearch)) { $piSetupFailed = $true }
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
    if ($piOpenCodeGoReady) {
        if (-not (Set-PaseoMuseProfile)) { $piSetupFailed = $true }
    }
    else {
        Write-Warning "Muse profile setup deferred because Pi OpenCode Go setup is unavailable."
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
    Remove-ImpeccableResources
    Remove-CompoundEngineeringResources
    Install-TursoCli

    if (-not (Remove-PaseoPlain)) {
        $paseoPlainSetupFailed = $true
    }

    Write-Section "System Updates"
    Install-WingetUpdates
    Install-WindowsUpdates # this should always be LAST since it may prompt a system reboot

    Test-PendingReboot

    if ($paseoPlainSetupFailed) {
        throw "Paseo Plain installation or update failed."
    }
    if ($piSetupFailed) {
        throw "Required Pi coding agent setup failed."
    }
    if ($mattPocockSetupFailed) {
        throw "Required Matt Pocock skill setup failed."
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

    Write-Host "`n$sparkles Setup complete!" -ForegroundColor Green -BackgroundColor DarkGreen
}

# Main setup function to call all necessary steps
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

# Run the main setup function
Initialize-WindowsEnvironment
