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
    "Cloudflare.cloudflared"
)

# Define Nerd Font symbols using Unicode code points
$arrow = [char]0xf0a9      # Arrow icon for actions
$success = [char]0xf00c    # Checkmark icon for success
$warnIcon = [char]0xf071   # Warning icon for warnings
$failIcon = [char]0xf00d   # Cross icon for errors
$sparkles = [char]0x2728   # Sparkles for completion

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

# Machine/setup guards
# WORK_MACHINE=1
# BAN_COMPOUND_PLUGIN=1
# BAN_PI_SUBAGENTS=1
# BAN_PI_GOAL_AUTORESEARCH=1
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

function Install-Chezmoi {
    if (-not (Get-Command chezmoi -ErrorAction SilentlyContinue)) {
        Write-Host "$failIcon Failed to install chezmoi." -ForegroundColor Red
        exit 1
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
        exit 1
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

# Function to install/update Codex CLI (OpenAI's AI coding agent)
function Install-CodexCli {
    Write-Host "$arrow Installing/updating Codex CLI..." -ForegroundColor Cyan

    # Ensure bun is available
    $bunPath = "$env:USERPROFILE\.bun\bin"
    if (Test-Path $bunPath) {
        $env:PATH = "$bunPath;$env:PATH"
    }

    if (-not (Get-Command bun -ErrorAction SilentlyContinue)) {
        Write-Host "$warnIcon Bun not found. Cannot install Codex CLI." -ForegroundColor Yellow
        Write-Host "  Install Bun first, then run: bun install -g @openai/codex" -ForegroundColor DarkGray
        return
    }

    try {
        bun install -g @openai/codex
        if ($?) {
            Write-Host "$success Codex CLI installed/updated." -ForegroundColor Green
        }
        else {
            Write-Host "$failIcon Failed to install Codex CLI." -ForegroundColor Red
        }
    }
    catch {
        Write-Host "$failIcon Failed to install Codex CLI: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Check whether the active Node.js runtime can run current Pi packages.
function Test-PiNodeRuntimeReady {
    if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
        return $false
    }

    & node -e 'const [major, minor] = process.versions.node.split(".").map(Number); process.exit(major > 20 || (major === 20 && minor >= 6) ? 0 : 1)' *> $null
    return ($LASTEXITCODE -eq 0)
}

# Ensure Pi runs with a Node.js version new enough for current @earendil-works packages.
function Enable-PiNodeRuntime {
    $runtime = "node@24"

    if (Test-PiNodeRuntimeReady) {
        $nodeVersion = (& node --version 2>$null | Out-String).Trim()
        Write-Debug "Node.js $nodeVersion is ready for Pi."
        return $true
    }

    $pathCandidates = @(
        [Environment]::GetEnvironmentVariable("Path", "User"),
        [Environment]::GetEnvironmentVariable("Path", "Machine"),
        (Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links"),
        (Join-Path $env:USERPROFILE ".local\bin")
    ) | Where-Object { $_ -and $_.Trim() -ne "" }
    $env:PATH = (($pathCandidates + @($env:PATH)) -join ";")

    if (-not (Get-Command mise -ErrorAction SilentlyContinue)) {
        Write-Warning "Node.js >=20.6 is required for Pi, but mise is not available to install it."
        Write-Debug "Install mise, then run: mise use -g -y $runtime"
        return $false
    }

    Write-Message "Ensuring Node.js 24 runtime for Pi..."
    & mise use -g -y $runtime *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Failed to install/configure $runtime with mise."
        return $false
    }

    $miseEnv = & mise env -s pwsh $runtime 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Failed to activate $runtime with mise."
        return $false
    }

    $miseEnv | Out-String | Invoke-Expression

    if (Test-PiNodeRuntimeReady) {
        $nodeVersion = (& node --version 2>$null | Out-String).Trim()
        Write-Success "Node.js $nodeVersion is ready for Pi."
        return $true
    }

    Write-Warning "Node.js >=20.6 is still not active after installing $runtime."
    return $false
}

# Function to install/update Pi coding agent
function Install-PiCli {
    $newPackage = "@earendil-works/pi-coding-agent"
    $oldPackage = "@mariozechner/pi-coding-agent"

    Write-Host "$arrow Installing/updating Pi coding agent..." -ForegroundColor Cyan

    # Ensure bun is available
    $bunPath = "$env:USERPROFILE\.bun\bin"
    if (Test-Path $bunPath) {
        $env:PATH = "$bunPath;$env:PATH"
    }

    if (-not (Get-Command bun -ErrorAction SilentlyContinue)) {
        Write-Host "$warnIcon Bun not found. Cannot install Pi coding agent." -ForegroundColor Yellow
        Write-Host "  Install Bun first, then run: bun install -g $newPackage" -ForegroundColor DarkGray
        return $false
    }

    try {
        if (-not (Enable-PiNodeRuntime)) {
            Write-Warning "Skipping Pi installation and extension setup because the Pi Node.js runtime is not ready."
            return $false
        }

        & bun install -g $newPackage
        if ($LASTEXITCODE -ne 0) {
            Write-Host "$failIcon Failed to install Pi coding agent." -ForegroundColor Red
            return $false
        }

        $globalPackages = & bun pm ls -g 2>$null | Out-String
        if ($globalPackages.Contains($oldPackage)) {
            Write-Host "$arrow Removing deprecated Pi package $oldPackage..." -ForegroundColor Cyan
            & bun remove -g $oldPackage
            if ($LASTEXITCODE -eq 0) {
                Write-Host "$success Deprecated Pi package removed." -ForegroundColor Green
            }
            else {
                Write-Host "$warnIcon Failed to remove old $oldPackage package." -ForegroundColor Yellow
            }
        }

        $piCommand = Get-Command pi -ErrorAction SilentlyContinue
        $piTarget = ""
        $needsReinstall = $false
        if ($piCommand) {
            $piTarget = $piCommand.Source
        }

        if (-not $piCommand) {
            Write-Host "$warnIcon Pi command was not found after migration. Reinstalling $newPackage." -ForegroundColor Yellow
            $needsReinstall = $true
        }
        elseif ($piTarget.Contains($oldPackage)) {
            Write-Host "$warnIcon Pi still points to old @mariozechner install path: $piTarget" -ForegroundColor Yellow
            Write-Host "$arrow Reinstalling $newPackage to refresh the Pi shim..." -ForegroundColor Cyan
            $needsReinstall = $true
        }

        if ($needsReinstall) {
            & bun install -g $newPackage
            if ($LASTEXITCODE -ne 0) {
                Write-Host "$warnIcon Failed to reinstall $newPackage after cleanup." -ForegroundColor Yellow
            }
        }

        $globalPackages = & bun pm ls -g 2>$null | Out-String
        $piCommand = Get-Command pi -ErrorAction SilentlyContinue
        $piTarget = ""
        if ($piCommand) {
            $piTarget = $piCommand.Source
        }

        if (-not $globalPackages.Contains($newPackage)) {
            Write-Host "$warnIcon Pi migration incomplete: $newPackage is not listed in Bun global packages." -ForegroundColor Yellow
            return $false
        }

        if ($globalPackages.Contains($oldPackage)) {
            Write-Host "$warnIcon Pi migration incomplete: deprecated $oldPackage is still listed in Bun global packages." -ForegroundColor Yellow
            return $false
        }

        if (-not $piCommand) {
            Write-Host "$warnIcon Pi migration incomplete: pi command is not available after installing $newPackage." -ForegroundColor Yellow
            return $false
        }

        if ($piTarget.Contains($oldPackage)) {
            Write-Host "$warnIcon Pi migration incomplete: pi still points to old @mariozechner install path after reinstall: $piTarget" -ForegroundColor Yellow
            return $false
        }

        Write-Host "$success Pi coding agent installed/updated." -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "$failIcon Failed to install Pi coding agent: $($_.Exception.Message)" -ForegroundColor Red
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

# Function to update Pi settings for the tintinweb subagents extension
function Update-PiSubagentsSettings {
    param([ValidateSet("Install", "Remove")][string]$Mode = "Install")

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

        if ($Mode -eq "Remove") {
            if ($source -ne "npm:pi-subagents" -and $source -ne "npm:@tintinweb/pi-subagents") {
                $filteredPackages += $package
            }
        }
        else {
            if ($source -ne "npm:pi-subagents") {
                $filteredPackages += $package
            }
        }
    }

    if ($Mode -eq "Remove") {
        if ($filteredPackages.Count -eq 0) {
            Remove-JsonProperty -Object $settings -Name "packages"
        }
        else {
            Set-JsonProperty -Object $settings -Name "packages" -Value ([object[]]$filteredPackages)
        }
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

# Function to install/update tintinweb Pi subagents extension
function Setup-PiSubagents {
    $package = "npm:@tintinweb/pi-subagents"

    # Ensure bun is available
    $bunPath = "$env:USERPROFILE\.bun\bin"
    if (Test-Path $bunPath) {
        $env:PATH = "$bunPath;$env:PATH"
    }

    if (Test-EnvLocalFlag "BAN_PI_SUBAGENTS") {
        if (Update-PiSubagentsSettings -Mode "Remove") {
            Write-Success "Pi subagents extension disabled in Pi settings."
        }
        return
    }

    if (-not (Get-Command bun -ErrorAction SilentlyContinue)) {
        Write-Warning "Bun not found. Cannot install Pi subagents."
        Write-Debug "Install Bun first, then run: pi install npm:@tintinweb/pi-subagents"
        return
    }

    if (-not (Get-Command pi -ErrorAction SilentlyContinue)) {
        Write-Warning "Pi coding agent not found. Cannot install Pi subagents."
        return
    }

    if (-not (Update-PiSubagentsSettings -Mode "Install")) {
        return
    }

    Write-Message "Installing/updating tintinweb Pi subagents..."
    $output = & pi install $package 2>&1
    if ($LASTEXITCODE -eq 0) {
        $listOutput = & pi list 2>&1
        $listText = ($listOutput | Out-String)
        $hasPackage = $listText.Contains($package)
        $hasLegacyPackage = $listText -match '(^|\s)npm:pi-subagents(\s|$)'

        if ($LASTEXITCODE -eq 0 -and $hasPackage -and -not $hasLegacyPackage) {
            Write-Success "tintinweb Pi subagents installed/updated."
        }
        else {
            Write-Warning "Pi subagents install completed, but package validation was inconclusive: $listText"
        }
    }
    else {
        Write-Warning "Failed to install tintinweb Pi subagents: $output"
    }
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
        if (Remove-PiGoalAutoresearchSettings) {
            Write-Success "Pi goal/autoresearch extensions disabled in Pi settings."
        }
        return
    }

    if (-not (Get-Command pi -ErrorAction SilentlyContinue)) {
        Write-Warning "Pi coding agent not found. Cannot install Pi goal/autoresearch extensions."
        return
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

    if ($LASTEXITCODE -eq 0 -and $hasGoal -and $hasAutoresearch) {
        Write-Success "Pi goal/autoresearch extensions are active."
    }
    elseif (-not $hadFailure) {
        Write-Warning "Pi goal/autoresearch install completed, but package validation was inconclusive: $listText"
    }
}


# Function to remove Claude-only AskUserQuestion references from Compound Engineering files installed for Pi
function Sanitize-PiCompoundEngineeringForPi {
    param([string]$AgentDir)

    if (-not $AgentDir) {
        if ($env:PI_CODING_AGENT_DIR) {
            $AgentDir = $env:PI_CODING_AGENT_DIR
        }
        else {
            $AgentDir = Join-Path $env:USERPROFILE ".pi\agent"
        }
    }

    $paths = @()
    $skillsDir = Join-Path $AgentDir "skills"
    if (Test-Path $skillsDir) {
        $paths += Get-ChildItem -Path $skillsDir -Recurse -File -Filter "*.md"
    }

    $agentsPath = Join-Path $AgentDir "AGENTS.md"
    if (Test-Path $agentsPath) {
        $paths += Get-Item $agentsPath
    }

    if (@($paths).Count -eq 0) {
        return
    }

    foreach ($path in $paths) {
        $text = Get-Content -Path $path.FullName -Raw
        if ($null -eq $text) {
            continue
        }

        $original = $text
        $text = $text -replace '(?m)^[ \t]*-[ \t]*AskUserQuestion\r?\n', ''
        $text = $text -replace '`AskUserQuestion` in Claude Code with `ToolSearch select:AskUserQuestion` pre-loaded if needed,\s*', ''
        $text = $text -replace '`AskUserQuestion` in Claude Code — call `ToolSearch` with `select:AskUserQuestion`[^;]*;\s*', ''
        $text = $text -replace '`AskUserQuestion` in Claude Code \(call `ToolSearch` with `select:AskUserQuestion`[^)]*\),\s*', ''
        $text = $text -replace '`AskUserQuestion` in Claude Code,\s*', ''
        $text = $text -replace '`AskUserQuestion` in Claude Code\s*', ''
        $text = $text -replace '\s*\*\*Claude Code only:\*\* if `AskUserQuestion`[^\r\n.]*\.[ \t]*', ' '
        $text = $text -replace '\s*In Claude Code,? call `ToolSearch` with `select:AskUserQuestion`[^\r\n.]*\.[ \t]*', ' '
        $text = $text -replace '\s*In Claude Code,? the tool should already be loaded[^\r\n.]*`ToolSearch`[^\r\n.]*\.[ \t]*', ' '
        $text = $text -replace '\s*In Claude Code the tool should already be loaded[^\r\n.]*`ToolSearch`[^\r\n.]*\.[ \t]*', ' '
        $text = $text -replace '\s*In Claude Code[^\r\n.]*`select:AskUserQuestion`[^\r\n.]*\.[ \t]*', ' '
        $text = $text -replace '\s*At the start of Interactive-mode work[^\r\n.]*`select:AskUserQuestion`[^\r\n.]*\.[ \t]*', ' '
        $text = $text -replace '\s*Load it \*\*once[^\r\n.]*\.[ \t]*', ' '
        $text = $text -replace '`ToolSearch` returns no match, the tool call explicitly fails, or', 'the tool call is unavailable, errors, or'
        $text = $text -replace 'Only when `ToolSearch` explicitly returns no match or the tool call errors — or on a platform with no blocking question tool —', 'Only when no blocking question tool exists or the tool call errors,'
        $text = $text -replace 'A pending schema load is not a fallback trigger; call `ToolSearch` first per the pre-load rule\. ', ''
        $text = $text -replace 'A pending schema load is not a fallback trigger\. ', ''
        $text = $text -replace ' — not because a schema load is required', ''
        $text = $text -replace 'no `AskUserQuestion` menu', 'no formal question menu'
        $text = $text -replace '`AskUserQuestion` menu', 'formal question menu'
        $text = $text -replace 'AskUserQuestion', 'blocking question tool'

        if ($text -ne $original) {
            Set-Content -Path $path.FullName -Value $text -Encoding UTF8 -NoNewline
        }
    }

    $remaining = $false
    foreach ($path in $paths) {
        if (Select-String -Path $path.FullName -Pattern "AskUserQuestion" -Quiet) {
            $remaining = $true
            break
        }
    }

    if ($remaining) {
        Write-Warning "Compound Engineering Pi files still mention AskUserQuestion after sanitizing."
    }
    else {
        Write-Success "Compound Engineering Pi files sanitized for Pi."
    }
}

# Function to install Compound Engineering prompts/skills for Pi
function Setup-PiCompoundEngineering {
    if (Test-EnvLocalFlag "WORK_MACHINE") {
        Write-Debug "WORK_MACHINE=1, skipping Compound Engineering for Pi."
        return
    }

    if (Test-EnvLocalFlag "BAN_COMPOUND_PLUGIN") {
        Write-Debug "BAN_COMPOUND_PLUGIN=1, skipping Compound Engineering for Pi."
        return
    }

    # Ensure bun is available
    $bunPath = "$env:USERPROFILE\.bun\bin"
    if (Test-Path $bunPath) {
        $env:PATH = "$bunPath;$env:PATH"
    }

    if (-not (Get-Command bun -ErrorAction SilentlyContinue)) {
        Write-Host "$warnIcon Bun not found. Cannot install Compound Engineering for Pi." -ForegroundColor Yellow
        Write-Host "  Install Bun first, then run: bunx @every-env/compound-plugin install compound-engineering --to pi" -ForegroundColor DarkGray
        return
    }

    if (-not (Get-Command bunx -ErrorAction SilentlyContinue)) {
        Write-Host "$warnIcon bunx not found. Cannot install Compound Engineering for Pi." -ForegroundColor Yellow
        return
    }

    if (-not (Get-Command pi -ErrorAction SilentlyContinue)) {
        Write-Host "$warnIcon Pi coding agent not found. Cannot install Compound Engineering for Pi." -ForegroundColor Yellow
        return
    }

    Write-Host "$arrow Installing/updating Compound Engineering for Pi..." -ForegroundColor Cyan
    $output = & bunx "@every-env/compound-plugin" install compound-engineering --to pi 2>&1
    if ($LASTEXITCODE -eq 0) {
        $agentDir = Join-Path $env:USERPROFILE ".pi\agent"
        $extensionPath = Join-Path $agentDir "extensions\compound-engineering-compat.ts"
        $agentsPath = Join-Path $agentDir "AGENTS.md"
        $hasAgentsBlock = (Test-Path $agentsPath) -and (Select-String -Path $agentsPath -Pattern "BEGIN COMPOUND PI TOOL MAP" -Quiet)

        if ((Test-Path $extensionPath) -or $hasAgentsBlock) {
            Write-Host "$success Compound Engineering installed for Pi." -ForegroundColor Green
        }
        else {
            Write-Host "$warnIcon Compound Engineering Pi install completed, but expected artifacts were not found." -ForegroundColor Yellow
        }
        Sanitize-PiCompoundEngineeringForPi -AgentDir $agentDir
    }
    else {
        Write-Host "$warnIcon Failed to install Compound Engineering for Pi: $output" -ForegroundColor Yellow
    }
}

# Function to install Claude Code using official installer
function Install-ClaudeCode {
    # Uninstall any existing npm/bun versions to clean up
    if (Get-Command npm -ErrorAction SilentlyContinue) {
        $npmList = npm list -g @anthropic-ai/claude-code 2>$null
        if ($npmList -match "@anthropic-ai/claude-code") {
            Write-Host "$arrow Removing npm-based Claude Code installation..." -ForegroundColor Cyan
            npm uninstall -g @anthropic-ai/claude-code 2>$null
        }
    }

    if (Get-Command bun -ErrorAction SilentlyContinue) {
        $bunList = bun pm ls -g 2>$null
        if ($bunList -match "@anthropic-ai/claude-code") {
            Write-Host "$arrow Removing bun-based Claude Code installation..." -ForegroundColor Cyan
            bun remove -g @anthropic-ai/claude-code 2>$null
        }
    }

    # Clean up stale lock files
    $lockPath = Join-Path $env:LOCALAPPDATA "claude\locks"
    if (Test-Path $lockPath) {
        Remove-Item $lockPath -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Skip if native version already installed
    $nativePath = Join-Path $env:USERPROFILE ".local\bin\claude.exe"
    if (Test-Path $nativePath) {
        Write-Debug "Claude Code is already installed (native)."
        return
    }

    Write-Host "$arrow Installing Claude Code via official installer..." -ForegroundColor Cyan
    try {
        irm https://claude.ai/install.ps1 | iex
        Write-Host "$success Claude Code installed." -ForegroundColor Green
    }
    catch {
        Write-Host "$failIcon Failed to install Claude Code: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Setup-CompoundPlugin {
    if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
        Write-Debug "Claude Code not found. Skipping Compound plugin setup."
        return
    }

    if (Test-EnvLocalFlag "BAN_COMPOUND_PLUGIN") {
        $pluginList = claude plugin list 2>$null
        if ($pluginList -match "compound-engineering") {
            Write-Host "$arrow BAN_COMPOUND_PLUGIN=1, uninstalling Compound Engineering plugin..." -ForegroundColor Cyan
            $output = claude plugin uninstall compound-engineering@compound-engineering-plugin 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Host "$success Compound Engineering plugin uninstalled." -ForegroundColor Green
            }
            else {
                Write-Host "$warnIcon Failed to uninstall Compound Engineering plugin: $output" -ForegroundColor Yellow
            }
        }
        else {
            Write-Debug "BAN_COMPOUND_PLUGIN=1, Compound Engineering not installed."
        }
        return
    }

    # Ensure marketplace is registered (idempotent, needed for updates too)
    $output = claude plugin marketplace add EveryInc/compound-engineering-plugin 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "$warnIcon Failed to register Compound Engineering marketplace: $output" -ForegroundColor Yellow
    }

    # Update if already installed, install if not
    $pluginList = claude plugin list 2>$null
    if ($pluginList -match "compound-engineering") {
        Write-Host "$arrow Updating Compound Engineering plugin..." -ForegroundColor Cyan
        $output = claude plugin update compound-engineering@compound-engineering-plugin 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "$success Compound Engineering plugin updated." -ForegroundColor Green
        }
        else {
            Write-Host "$warnIcon Failed to update Compound Engineering plugin: $output" -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "$arrow Installing Compound Engineering plugin..." -ForegroundColor Cyan
        $output = claude plugin install compound-engineering --scope user 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "$success Compound Engineering plugin installed." -ForegroundColor Green
        }
        else {
            Write-Host "$warnIcon Failed to install Compound Engineering plugin: $output" -ForegroundColor Yellow
        }
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

# Function to upgrade global npm packages
function Update-NpmGlobalPackages {
    # Try to initialize mise if available (provides npm if Node.js is installed)
    if (Get-Command mise -ErrorAction SilentlyContinue) {
        mise activate pwsh | Out-String | Invoke-Expression
    }

    # Make sure npm is available
    if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
        Write-Host "$warnIcon npm not found. Skipping global package upgrade." -ForegroundColor Yellow
        return
    }

    Write-Host "$arrow Upgrading global npm packages..." -ForegroundColor Cyan
    try {
        npm update -g
        if ($?) {
            Write-Host "$success Global npm packages upgraded." -ForegroundColor Green
        }
        else {
            Write-Host "$warnIcon Failed to upgrade some global npm packages." -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "$warnIcon Failed to upgrade global npm packages: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# Function to setup ~/Code directory
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



function Upload-Log {
    if ($logFile -and (Test-Path $logFile)) {
        try {
            Write-Debug "Uploading log to logs.scowalt.com..."
            Invoke-RestMethod -Uri "https://logs.scowalt.com/upload?hostname=$env:COMPUTERNAME" `
                -Method Post -Form @{ file = Get-Item $logFile } `
                -TimeoutSec 10 -ErrorAction SilentlyContinue | Out-Null
        } catch {}
    }
}

# Main setup function to call all necessary steps
function Initialize-WindowsEnvironment {
    $windowsIcon = [char]0xf17a  # Windows logo
    Write-Host "`n$windowsIcon Windows Development Environment Setup" -ForegroundColor White -BackgroundColor DarkBlue
    Write-Host "Version 93 | Last changed: Ensure Pi Node runtime and final log upload" -ForegroundColor DarkGray

    # Log this run
    $logDir = Join-Path $env:USERPROFILE ".local\log\machine-setup"
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    }
    $logFile = Join-Path $logDir "$(Get-Date -Format 'yyyy-MM-dd-HHmmss').log"
    Start-Transcript -Path $logFile -Append
    Write-Debug "Logging to $logFile"

    # Create placeholder token files early
    New-TokenPlaceholders

    Write-Section "Package Installation"
    Install-WingetPackages
    Install-SecretsManager

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
    Install-SocketFirewall
    Install-ClaudeCode
    Setup-CompoundPlugin

    Install-GeminiCli
    Install-CodexCli
    if (Install-PiCli) {
        Setup-PiSubagents
        Setup-PiGoalAutoresearch
        Setup-PiCompoundEngineering
    }
    else {
        Write-Warning "Skipping Pi extension setup because Pi migration failed."
    }
    Install-TursoCli

    Write-Section "System Updates"
    Install-WingetUpdates
    Update-NpmGlobalPackages
    Install-WindowsUpdates # this should always be LAST since it may prompt a system reboot

    $logFile = Get-ChildItem "$env:USERPROFILE\.local\log\machine-setup" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    Write-Host "Run log saved to: $($logFile.FullName)" -ForegroundColor DarkGray
    Write-Host "`n$sparkles Setup complete!" -ForegroundColor Green -BackgroundColor DarkGreen
    Stop-Transcript
    Upload-Log
}

# Run the main setup function
Initialize-WindowsEnvironment