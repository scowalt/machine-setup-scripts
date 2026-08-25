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
$script:SetupLogFile = $null
$script:SetupTranscriptStarted = $false
try {
    $setupOriginalClaude = Get-Command claude -ErrorAction SilentlyContinue
    if ($setupOriginalClaude) {
        $script:SetupOriginalClaudeCommand = $setupOriginalClaude.Source
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

# Machine/setup guards
# HEADLESS=1
# WORK_MACHINE=1
# BAN_PI_MCP_ADAPTER=1
# BAN_PI_GOAL_AUTORESEARCH=1
# BAN_MATT_POCOCK_SKILLS=1
# ZAI_API_KEY=<your z.ai API key>
# BAN_CLAUDE_CODE=1
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
    if (Test-EnvLocalFlag "BAN_CLAUDE_CODE") {
        Write-Debug "BAN_CLAUDE_CODE=1, skipping Claude Code CLI setup."
        return
    }

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

    $miseEnv = & mise env -C $env:USERPROFILE -s pwsh $runtime 2>$null
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

# Check whether the active Node.js runtime can run the current skills CLI.
function Test-SkillsCliNodeRuntimeReady {
    if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
        return $false
    }

    & node -e 'const [major, minor] = process.versions.node.split(".").map(Number); process.exit(major > 22 || (major === 22 && minor >= 20) ? 0 : 1)' *> $null
    return ($LASTEXITCODE -eq 0)
}

# Ensure the skills CLI runs on its required Node.js version.
function Enable-SkillsCliNodeRuntime {
    $runtime = "node@24"

    if (Test-SkillsCliNodeRuntimeReady) {
        $nodeVersion = (& node --version 2>$null | Out-String).Trim()
        Write-Debug "Node.js $nodeVersion is ready for the skills CLI."
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
        Write-Warning "Node.js >=22.20 is required for the skills CLI, but mise is not available to install it."
        Write-Debug "Install mise, then run: mise use -g -y $runtime"
        return $false
    }

    Write-Message "Ensuring Node.js 24 runtime for the skills CLI..."
    & mise use -g -y $runtime *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Failed to install/configure $runtime with mise."
        return $false
    }

    $miseEnv = & mise env -C $env:USERPROFILE -s pwsh $runtime 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Failed to activate $runtime with mise."
        return $false
    }

    $miseEnv | Out-String | Invoke-Expression

    if (Test-SkillsCliNodeRuntimeReady) {
        $nodeVersion = (& node --version 2>$null | Out-String).Trim()
        Write-Success "Node.js $nodeVersion is ready for the skills CLI."
        return $true
    }

    Write-Warning "Node.js >=22.20 is still not active after installing $runtime."
    return $false
}

# Install/update Simple English for every supported AI coding harness.
function Install-SimpleEnglishSkill {
    if (-not (Enable-SkillsCliNodeRuntime)) {
        return $false
    }

    if (-not (Get-Command npx -ErrorAction SilentlyContinue)) {
        Write-Warning "npx is not available; cannot install the Simple English skill."
        return $false
    }

    $installArguments = @(
        "--yes",
        "skills@latest",
        "add",
        "AminBlg/SimpleEnglish",
        "--global",
        "--agent", "claude-code",
        "--agent", "codex",
        "--agent", "gemini-cli",
        "--skill", "simple-english",
        "--copy",
        "--yes"
    )

    Write-Message "Installing/updating Simple English across AI harnesses..."
    $global:LASTEXITCODE = 0
    $installOutput = & npx @installArguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Failed to install/update the Simple English skill."
        if ($installOutput) { Write-Debug ($installOutput | Out-String) }
        return $false
    }

    $claudeDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $env:USERPROFILE ".claude" }
    # Codex and Gemini CLI both discover the skills CLI's shared user copy.
    $skillFiles = @(
        (Join-Path $claudeDir "skills\simple-english\SKILL.md"),
        (Join-Path $env:USERPROFILE ".agents\skills\simple-english\SKILL.md")
    )

    foreach ($skillFile in $skillFiles) {
        if (-not (Test-Path -LiteralPath $skillFile -PathType Leaf)) {
            Write-Warning "Simple English validation failed: missing $skillFile."
            return $false
        }
    }

    Write-Success "Simple English installed/updated for Claude Code, Codex, Gemini CLI, and Pi through the shared skill path."
    if ($installOutput) { Write-Debug ($installOutput | Out-String) }
    return $true
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

    if (-not (Test-Path $localPrefix)) {
        New-Item -ItemType Directory -Force -Path $localPrefix | Out-Null
    }
    $env:PATH = "$localPrefix;$env:PATH"

    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if (-not ($userPath -split ';' | Where-Object { $_ -eq $localPrefix })) {
        [Environment]::SetEnvironmentVariable("Path", "$localPrefix;$userPath", "User")
    }

    try {
        if (-not (Enable-PiNodeRuntime)) {
            Write-Warning "Skipping Pi installation and extension setup because the Pi Node.js runtime is not ready."
            return $false
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
        Write-Host "$success Pi coding agent $piVersion installed/updated at $canonicalPi." -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "$failIcon Failed to install Pi coding agent: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Force Pi defaults: Kimi K3 (Synthetic), or GLM-5.3 (z.ai GLM Coding Plan)
# on work machines that have a z.ai API key.
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
        $defaultDesc = "Kimi K3 (Synthetic)"
        if ((Test-EnvLocalFlag "WORK_MACHINE") -and (Test-PiZaiKeyAvailable)) {
            Set-JsonProperty -Object $settings -Name "defaultProvider" -Value "zai"
            Set-JsonProperty -Object $settings -Name "defaultModel" -Value "glm-5.3"
            $defaultDesc = "GLM-5.3 (z.ai)"
        }
        else {
            Set-JsonProperty -Object $settings -Name "defaultProvider" -Value "synthetic"
            Set-JsonProperty -Object $settings -Name "defaultModel" -Value "hf:moonshotai/Kimi-K3"
        }
        Set-JsonProperty -Object $settings -Name "defaultThinkingLevel" -Value "high"
        $settings | ConvertTo-Json -Depth 20 | Set-Content -Path $settingsPath -Encoding UTF8
        Write-Host "$success Pi default model set to $defaultDesc with high thinking." -ForegroundColor Green
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

# Seed the Synthetic provider block (Kimi K3) into Pi's models.json.
# The API key comes from SYNTHETIC_API_KEY in ~/.env.local; it is never
# stored in this repository. Existing synthetic keys are preserved.
function Seed-PiSyntheticModels {
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
        if ($models.providers.PSObject.Properties.Name -contains "synthetic") {
            $existingKey = $models.providers.synthetic.apiKey
        }
        if (-not [string]::IsNullOrWhiteSpace($existingKey)) {
            Write-Debug "Synthetic provider with an API key already configured in $modelsPath."
            return $true
        }

        $apiKey = Get-EnvLocalValue "SYNTHETIC_API_KEY"
        if ([string]::IsNullOrWhiteSpace($apiKey)) {
            Write-Warning "SYNTHETIC_API_KEY not set in ~/.env.local. Kimi K3 (Synthetic) is the Pi default but has no API key yet; add the key and rerun setup."
            return $false
        }

        $syntheticProvider = [PSCustomObject]@{
            baseUrl = "https://api.synthetic.new/v1"
            api     = "openai-completions"
            apiKey  = $apiKey
            compat  = [PSCustomObject]@{
                supportsDeveloperRole = $false
                supportsStore         = $false
                maxTokensField        = "max_tokens"
                supportsStrictMode    = $false
                deferredToolsMode     = "kimi"
            }
            models  = @(
                [PSCustomObject]@{
                    id               = "hf:moonshotai/Kimi-K3"
                    name             = "Kimi K3 (Synthetic)"
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
                    input            = @("text", "image")
                    contextWindow    = 512000
                    maxTokens        = 131072
                    cost             = [PSCustomObject]@{ input = 0; output = 0; cacheRead = 0; cacheWrite = 0 }
                    compat           = [PSCustomObject]@{
                        supportsReasoningEffort                     = $true
                        thinkingFormat                              = "openai"
                        requiresReasoningContentOnAssistantMessages = $true
                    }
                }
            )
        }

        if ($models.providers.PSObject.Properties.Name -contains "synthetic") {
            $models.providers.synthetic = $syntheticProvider
        }
        else {
            $models.providers | Add-Member -NotePropertyName "synthetic" -NotePropertyValue $syntheticProvider
        }

        $models | ConvertTo-Json -Depth 20 | Set-Content -Path $modelsPath -Encoding UTF8
        Write-Host "$success Synthetic provider (Kimi K3) seeded in $modelsPath." -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "$failIcon Failed to seed Synthetic provider in $modelsPath : $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Check whether a z.ai API key is available from ~/.env.local or from an
# existing z.ai provider block in Pi's models.json.
function Test-PiZaiKeyAvailable {
    if (-not [string]::IsNullOrWhiteSpace((Get-EnvLocalValue "ZAI_API_KEY"))) {
        return $true
    }

    if ($env:PI_CODING_AGENT_DIR) {
        $agentDir = $env:PI_CODING_AGENT_DIR
    }
    else {
        $agentDir = Join-Path $env:USERPROFILE ".pi\agent"
    }
    $modelsPath = Join-Path $agentDir "models.json"
    if (Test-Path $modelsPath) {
        try {
            $existingModels = Get-Content -Path $modelsPath -Raw | ConvertFrom-Json
            if ($existingModels.providers -and ($existingModels.providers.PSObject.Properties.Name -contains "zai")) {
                $existingKey = $existingModels.providers.zai.apiKey
                if (-not [string]::IsNullOrWhiteSpace($existingKey)) {
                    return $true
                }
            }
        }
        catch {
            Write-Debug "Could not parse Pi models at $modelsPath while checking for a z.ai key."
        }
    }
    return $false
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
                Write-Warning "ZAI_API_KEY not set in ~/.env.local. Work machines default Pi to GLM-5.3 (z.ai) but there is no API key yet; add the key and rerun setup."
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
            }
        }
        return
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
        return
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
        return
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
    }
}

# Function to remove Pi MCP adapter package source from settings when disabled
function Remove-PiMcpAdapterSettings {
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

        if ($source -ne "npm:pi-mcp-adapter") {
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

# Function to install/update Pi MCP adapter extension
function Setup-PiMcpAdapter {
    $package = "npm:pi-mcp-adapter"

    if (Test-EnvLocalFlag "BAN_PI_MCP_ADAPTER") {
        if (Remove-PiMcpAdapterSettings) {
            Write-Success "Pi MCP adapter extension disabled in Pi settings."
        }
        return
    }

    if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
        Write-Warning "npm not found. Cannot install Pi MCP adapter."
        Write-Debug "Install Node.js/npm, then run: pi install npm:pi-mcp-adapter"
        return
    }

    if (-not (Get-Command pi -ErrorAction SilentlyContinue)) {
        Write-Warning "Pi coding agent not found. Cannot install Pi MCP adapter."
        return
    }

    Write-Message "Installing/updating Pi MCP adapter..."
    $output = & pi install $package 2>&1
    if ($LASTEXITCODE -eq 0) {
        $listOutput = & pi list 2>&1
        $listText = ($listOutput | Out-String)
        if ($LASTEXITCODE -eq 0 -and $listText.Contains($package)) {
            Write-Success "Pi MCP adapter installed/updated."
        }
        else {
            Write-Warning "Pi MCP adapter install completed, but package validation was inconclusive: $listText"
        }
    }
    else {
        Write-Warning "Failed to install Pi MCP adapter: $output"
    }
}

# Function to install/update Pi Claude bridge extension
function Setup-PiClaudeBridge {
    $package = "npm:pi-claude-bridge"

    if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
        Write-Warning "npm not found. Cannot install Pi Claude bridge."
        Write-Debug "Install Node.js/npm, then run: pi install npm:pi-claude-bridge"
        return
    }

    if (-not (Get-Command pi -ErrorAction SilentlyContinue)) {
        Write-Warning "Pi coding agent not found. Cannot install Pi Claude bridge."
        return
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
        }
    }
    else {
        Write-Warning "Failed to install Pi Claude bridge: $output"
    }
}

# Function to remove legacy Pi Ask User and install/update Pi companion packages
function Setup-PiCompanionPackages {
    $legacyPackage = "npm:pi-ask-user"
    $packages = @(
        "npm:@juicesharp/rpiv-ask-user-question"
        "npm:pi-web-access"
        "npm:@juicesharp/rpiv-todo"
    )

    if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
        Write-Warning "npm not found. Cannot install Pi companion packages."
        Write-Debug "Install Node.js/npm, then install these Pi packages manually: $($packages -join ', ')"
        return
    }

    if (-not (Get-Command pi -ErrorAction SilentlyContinue)) {
        Write-Warning "Pi coding agent not found. Cannot install Pi companion packages."
        return
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
            }
        }
    }
    else {
        Write-Warning "Cannot inspect Pi packages before legacy cleanup: $listText"
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
            }
        }
        else {
            Write-Warning "Failed to install Pi package ${package}: $output"
        }
    }
}

# Return true only when two ordinary directories have identical file trees.
function Test-DirectoryTreeEqual {
    param(
        [Parameter(Mandatory = $true)][string]$Left,
        [Parameter(Mandatory = $true)][string]$Right
    )

    $leftItem = Get-Item -LiteralPath $Left -Force -ErrorAction SilentlyContinue
    $rightItem = Get-Item -LiteralPath $Right -Force -ErrorAction SilentlyContinue
    if ($null -eq $leftItem -or $null -eq $rightItem -or -not $leftItem.PSIsContainer -or -not $rightItem.PSIsContainer) { return $false }
    if ((($leftItem.Attributes -bor $rightItem.Attributes) -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { return $false }

    $leftFiles = @(Get-ChildItem -LiteralPath $Left -Recurse -Force -ErrorAction SilentlyContinue)
    $rightFiles = @(Get-ChildItem -LiteralPath $Right -Recurse -Force -ErrorAction SilentlyContinue)
    if (@($leftFiles | Where-Object { ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0 }).Count -gt 0) { return $false }
    if (@($rightFiles | Where-Object { ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0 }).Count -gt 0) { return $false }

    $leftLeafFiles = @($leftFiles | Where-Object { -not $_.PSIsContainer })
    $rightLeafFiles = @($rightFiles | Where-Object { -not $_.PSIsContainer })
    if ($leftLeafFiles.Count -ne $rightLeafFiles.Count) { return $false }

    foreach ($leftFile in $leftLeafFiles) {
        $relativePath = $leftFile.FullName.Substring($leftItem.FullName.Length).TrimStart('\', '/')
        $rightFile = Join-Path $Right $relativePath
        if (-not (Test-Path -LiteralPath $rightFile -PathType Leaf)) { return $false }
        if ((Get-FileHash -LiteralPath $leftFile.FullName -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $rightFile -Algorithm SHA256).Hash) { return $false }
    }
    return $true
}

# Keep shared skills canonical for Pi and suppress stale direct/package collisions.
function Set-PiSkillOwnership {
    $defaultAgentDir = Join-Path $env:USERPROFILE ".pi\agent"
    $activeAgentDir = if ($env:PI_CODING_AGENT_DIR) { $env:PI_CODING_AGENT_DIR } else { $defaultAgentDir }
    $canonicalDir = Join-Path $env:USERPROFILE ".agents\skills"
    $agentDirs = @($defaultAgentDir)
    if ($activeAgentDir -ne $defaultAgentDir) { $agentDirs += $activeAgentDir }
    $sharedSkills = @(
        "simple-english", "setup-matt-pocock-skills", "diagnosing-bugs", "tdd",
        "improve-codebase-architecture", "grill-with-docs", "grilling", "domain-modeling", "codebase-design"
    )
    $managedExclusions = @(
        "!$(Join-Path $canonicalDir 'pi-goal-writer')/**",
        "!$(Join-Path $canonicalDir 'autoresearch-create')/**",
        "!$(Join-Path $canonicalDir 'autoresearch-finalize')/**",
        "!$(Join-Path $canonicalDir 'autoresearch-hooks')/**"
    )

    foreach ($agentDir in $agentDirs) {
        foreach ($skill in $sharedSkills) {
            $duplicate = Join-Path $agentDir "skills\$skill"
            $canonical = Join-Path $canonicalDir $skill
            $managedExclusions += "!$duplicate/**"
            if ((Test-DirectoryTreeEqual -Left $canonical -Right $duplicate) -and (Remove-MattPocockSkillPath -Path $duplicate)) {
                Write-Debug "Removed obsolete duplicate Pi skill: $duplicate"
            }
        }
    }

    New-Item -ItemType Directory -Force -Path $activeAgentDir | Out-Null
    $settingsPath = Join-Path $activeAgentDir "settings.json"
    $settingsJson = if (Test-Path $settingsPath) { Get-Content -LiteralPath $settingsPath -Raw } else { "{}" }
    try { $settings = $settingsJson | ConvertFrom-Json } catch {
        Write-Warning "Failed to parse Pi settings at $settingsPath. Leaving settings unchanged."
        return $false
    }
    if ($null -eq $settings) { $settings = New-Object PSObject }
    $skills = if ($settings.PSObject.Properties["skills"] -and $settings.skills -is [array]) { @($settings.skills) } else { @() }
    foreach ($exclusion in $managedExclusions) {
        if ($skills -notcontains $exclusion) { $skills += $exclusion }
    }
    Set-JsonProperty -Object $settings -Name "skills" -Value ([object[]]$skills)
    try { $settings | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $settingsPath -Encoding UTF8 } catch {
        Write-Warning "Failed to configure Pi skill ownership at $settingsPath."
        return $false
    }
    Write-Success "Pi skill ownership configured without removing shared harness copies."
    return $true
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

    if (-not (Set-PiAutoresearchShortcut)) {
        throw "Required pi-autoresearch shortcut setup failed."
    }
}


function Test-MattPocockSkillsDisabled {
    return ((Test-EnvLocalFlag "BAN_MATT_POCOCK_SKILLS") -or (Test-EnvLocalFlag "BAN_MATT_POCKOCK_SKILLS"))
}

function Remove-MattPocockSkillPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    try {
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    }
    catch [System.Management.Automation.ItemNotFoundException] {
        return $true
    }
    catch {
        return $false
    }

    try {
        $isReparsePoint = ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0
        if ($isReparsePoint -or -not $item.PSIsContainer) {
            Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
        }
        else {
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
        }
        try {
            Get-Item -LiteralPath $Path -Force -ErrorAction Stop | Out-Null
            return $false
        }
        catch [System.Management.Automation.ItemNotFoundException] {
            return $true
        }
        catch {
            return $false
        }
    }
    catch {
        return $false
    }
}

# Remove setup-managed Matt Pocock skills without following symlink targets.
function Remove-MattPocockSkills {
    $skills = @(
        "setup-matt-pocock-skills",
        "diagnosing-bugs",
        "tdd",
        "improve-codebase-architecture",
        "grill-with-docs",
        "grilling",
        "domain-modeling",
        "codebase-design"
    )
    $obsoleteSkills = @("diagnose", "zoom-out")
    $skills += $obsoleteSkills

    $defaultAgentDir = Join-Path $env:USERPROFILE ".pi\agent"
    if ($env:PI_CODING_AGENT_DIR) {
        $activeAgentDir = $env:PI_CODING_AGENT_DIR
    }
    else {
        $activeAgentDir = $defaultAgentDir
    }

    $skillsDirs = @(
        (Join-Path $defaultAgentDir "skills"),
        (Join-Path $env:USERPROFILE ".agents\skills")
    )
    if ($activeAgentDir -ne $defaultAgentDir) {
        $skillsDirs += (Join-Path $activeAgentDir "skills")
    }

    $removed = $false
    $failed = @()
    foreach ($skillsDir in $skillsDirs) {
        foreach ($skill in $skills) {
            $skillPath = Join-Path $skillsDir $skill
            try {
                Get-Item -LiteralPath $skillPath -Force -ErrorAction Stop | Out-Null
            }
            catch [System.Management.Automation.ItemNotFoundException] {
                continue
            }
            catch {
                $failed += $skill
                continue
            }

            if (Remove-MattPocockSkillPath -Path $skillPath) {
                $removed = $true
            }
            else {
                $failed += $skill
            }
        }
    }

    if ($failed.Count -gt 0) {
        Write-Warning "Failed to remove Matt Pocock skills: $($failed -join ', ')"
        return $false
    }
    if ($removed) {
        Write-Success "Matt Pocock skills disabled."
    }
    else {
        Write-Debug "Matt Pocock skills disabled; no installed copies found."
    }
    return $true
}

# Install/update Matt Pocock engineering skills in the shared Codex/Pi path.
function Setup-MattPocockSkills {
    $skills = @(
        "setup-matt-pocock-skills",
        "diagnosing-bugs",
        "tdd",
        "improve-codebase-architecture",
        "grill-with-docs",
        "grilling",
        "domain-modeling",
        "codebase-design"
    )
    $obsoleteSkills = @("diagnose", "zoom-out")

    if (Test-MattPocockSkillsDisabled) {
        return (Remove-MattPocockSkills)
    }

    if (-not (Enable-SkillsCliNodeRuntime)) {
        Write-Warning "Cannot install Matt Pocock skills because the skills CLI runtime is not ready."
        return $false
    }

    if (-not (Get-Command npx -ErrorAction SilentlyContinue)) {
        Write-Warning "npx is not available; cannot install Matt Pocock skills."
        Write-Debug "Install Node.js >=22.20, then run: npx --yes skills@latest add mattpocock/skills --global --agent codex --copy --yes"
        return $false
    }

    $codexSkillsDir = Join-Path $env:USERPROFILE ".agents\skills"
    $npxArgs = @(
        "--yes", "skills@latest", "add", "mattpocock/skills",
        "--global",
        "--agent", "codex",
        "--copy",
        "--yes"
    )
    foreach ($skill in $skills) {
        $npxArgs += @("--skill", $skill)
    }

    Write-Message "Installing/updating Matt Pocock skills for Pi and Codex through the shared skill path..."
    $global:LASTEXITCODE = 0
    $output = & npx @npxArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Failed to install Matt Pocock skills."
        if ($output) { Write-Debug ($output | Out-String) }
        return $false
    }

    $missing = @()
    $managedSkillsDirs = @($codexSkillsDir)
    foreach ($managedSkillsDir in $managedSkillsDirs) {
        foreach ($skill in $skills) {
            $skillDir = Join-Path $managedSkillsDir $skill
            $skillFile = Join-Path $skillDir "SKILL.md"
            $skillDirItem = Get-Item -LiteralPath $skillDir -Force -ErrorAction SilentlyContinue
            $skillFileItem = Get-Item -LiteralPath $skillFile -Force -ErrorAction SilentlyContinue
            $skillDirIsLink = $null -ne $skillDirItem -and (($skillDirItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
            $skillFileIsLink = $null -ne $skillFileItem -and (($skillFileItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
            if ($null -eq $skillFileItem -or $skillFileItem.PSIsContainer -or $skillDirIsLink -or $skillFileIsLink) {
                $missing += $skillDir
            }
        }
    }

    if ($missing.Count -gt 0) {
        Write-Warning "Matt Pocock skills are missing required files: $($missing -join ', ')"
        return $false
    }

    $obsoleteCleanupFailed = @()
    foreach ($managedSkillsDir in $managedSkillsDirs) {
        foreach ($obsoleteSkill in $obsoleteSkills) {
            $obsoletePath = Join-Path $managedSkillsDir $obsoleteSkill
            if (-not (Remove-MattPocockSkillPath -Path $obsoletePath)) {
                $obsoleteCleanupFailed += $obsoletePath
            }
        }
    }
    if ($obsoleteCleanupFailed.Count -gt 0) {
        Write-Warning "Failed to remove obsolete Matt Pocock skills: $($obsoleteCleanupFailed -join ', ')"
        return $false
    }

    Write-Success "Matt Pocock skills installed/updated for Pi and Codex through the shared skill path."
    if ($output) { Write-Debug ($output | Out-String) }
    return $true
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
    $compoundSkillPattern = '^(ce-agent-native-architecture|ce-agent-native-audit|ce-brainstorm|ce-clean-gone-branches|ce-code-review|ce-commit|ce-commit-push-pr|ce-compound|ce-compound-refresh|ce-debug|ce-demo-reel|ce-dhh-rails-style|ce-doc-review|ce-frontend-design|ce-gemini-imagegen|ce-ideate|ce-optimize|ce-plan|ce-polish-beta|ce-product-pulse|ce-proof|ce-release-notes|ce-report-bug|ce-resolve-pr-feedback|ce-riffrec-feedback-analysis|ce-sessions|ce-setup|ce-simplify-code|ce-slack-research|ce-strategy|ce-test-browser|ce-test-xcode|ce-work|ce-work-beta|ce-worktree)$'
    $compoundAgentPattern = '^(ce-adversarial-document-reviewer|ce-adversarial-reviewer|ce-agent-native-reviewer|ce-ankane-readme-writer|ce-api-contract-reviewer|ce-architecture-strategist|ce-best-practices-researcher|ce-code-simplicity-reviewer|ce-coherence-reviewer|ce-correctness-reviewer|ce-data-integrity-guardian|ce-data-migration-expert|ce-data-migrations-reviewer|ce-deployment-verification-agent|ce-design-implementation-reviewer|ce-design-iterator|ce-design-lens-reviewer|ce-dhh-rails-reviewer|ce-feasibility-reviewer|ce-figma-design-sync|ce-framework-docs-researcher|ce-git-history-analyzer|ce-issue-intelligence-analyst|ce-julik-frontend-races-reviewer|ce-kieran-python-reviewer|ce-kieran-rails-reviewer|ce-kieran-typescript-reviewer|ce-learnings-researcher|ce-maintainability-reviewer|ce-pattern-recognition-specialist|ce-performance-oracle|ce-performance-reviewer|ce-pr-comment-resolver|ce-previous-comments-reviewer|ce-product-lens-reviewer|ce-project-standards-reviewer|ce-reliability-reviewer|ce-repo-research-analyst|ce-schema-drift-detector|ce-scope-guardian-reviewer|ce-security-lens-reviewer|ce-security-reviewer|ce-security-sentinel|ce-session-historian|ce-slack-researcher|ce-spec-flow-analyzer|ce-swift-ios-reviewer|ce-testing-reviewer|ce-web-researcher)$'
    $compoundRepo = Join-Path $profileRoot ".local\share\compound-engineering-plugin"
    $sharedSkillsDir = Join-Path $profileRoot ".agents\skills"
    $removed = $false
    $failed = @()

    foreach ($candidate in @($defaultAgentDir, $env:PI_CODING_AGENT_DIR)) {
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
    if ($script:SetupLogFile -and (Test-Path $script:SetupLogFile)) {
        try {
            Write-Debug "Uploading log to logs.scowalt.com..."
            Invoke-RestMethod -Uri "https://logs.scowalt.com/upload?hostname=$env:COMPUTERNAME" `
                -Method Post -Form @{ file = Get-Item $script:SetupLogFile } `
                -TimeoutSec 10 -ErrorAction Stop | Out-Null
        }
        catch {
            Write-Warning "Failed to upload setup log. Local log remains at $script:SetupLogFile."
        }
    }
}

function Complete-SetupLog {
    if (-not $script:SetupLogFile) {
        return
    }

    Write-Host "Run log saved to: $script:SetupLogFile" -ForegroundColor DarkGray
    if ($script:SetupTranscriptStarted) {
        try {
            Stop-Transcript -ErrorAction Stop | Out-Null
        }
        catch {
            Write-Warning "Failed to stop the setup transcript cleanly: $($_.Exception.Message)"
        }
        finally {
            $script:SetupTranscriptStarted = $false
        }
    }

    Upload-Log
}

function Invoke-WindowsSetupTasks {
    $piSetupFailed = $false
    $mattPocockSetupFailed = $false
    $simpleEnglishSetupFailed = $false
    $windowsIcon = [char]0xf17a  # Windows logo
    Write-Host "`n$windowsIcon Windows Development Environment Setup" -ForegroundColor White -BackgroundColor DarkBlue
    Write-Host "Version 125 | Last changed: Prevent duplicate Pi skills and shortcuts" -ForegroundColor DarkGray

    Assert-HeadlessPaseoUnsupported

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
    Install-SocketFirewall
    Install-ClaudeCode
    Install-GeminiCli
    Install-CodexCli
    Install-PortlessCli
    Remove-RtkResources
    if (-not (Setup-MattPocockSkills)) {
        $mattPocockSetupFailed = $true
    }
    if (Install-PiCli) {
        Set-PiDefaults
        Seed-PiSyntheticModels
        Seed-PiZaiModels
        Remove-PiSubagents
        Setup-PiMcpAdapter
        Setup-PiClaudeBridge
        Setup-PiCompanionPackages
        Setup-PiGoalAutoresearch
    }
    else {
        Remove-PiSubagents
        if (Test-EnvLocalFlag "BAN_PI_MCP_ADAPTER") {
            Setup-PiMcpAdapter
        }
        if (Test-EnvLocalFlag "BAN_PI_GOAL_AUTORESEARCH") {
            Setup-PiGoalAutoresearch
        }
        Write-Warning "Skipping Pi extension setup because Pi migration failed."
        $piSetupFailed = $true
    }
    if (-not (Install-SimpleEnglishSkill)) {
        $simpleEnglishSetupFailed = $true
    }
    if (-not (Set-PiSkillOwnership)) {
        $piSetupFailed = $true
    }
    Remove-ImpeccableResources
    Remove-CompoundEngineeringResources
    Install-TursoCli

    Write-Section "System Updates"
    Install-WingetUpdates
    Install-WindowsUpdates # this should always be LAST since it may prompt a system reboot

    if ($piSetupFailed) {
        throw "Required Pi coding agent setup failed."
    }
    if ($mattPocockSetupFailed) {
        throw "Required Matt Pocock skill setup failed."
    }
    if ($simpleEnglishSetupFailed) {
        throw "Required Simple English skill setup failed."
    }

    Write-Host "`n$sparkles Setup complete!" -ForegroundColor Green -BackgroundColor DarkGreen
}

# Main setup function to call all necessary steps
function Initialize-WindowsEnvironment {
    $logDir = Join-Path $env:USERPROFILE ".local\log\machine-setup"
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    }
    $script:SetupLogFile = Join-Path $logDir "$(Get-Date -Format 'yyyy-MM-dd-HHmmss').log"
    Start-Transcript -Path $script:SetupLogFile -Append -ErrorAction Stop | Out-Null
    $script:SetupTranscriptStarted = $true
    Write-Debug "Logging to $script:SetupLogFile"

    $setupError = $null
    try {
        Invoke-WindowsSetupTasks
    }
    catch {
        $setupError = $_
    }

    Complete-SetupLog
    if ($null -ne $setupError) {
        throw $setupError
    }
}

# Run the main setup function
Initialize-WindowsEnvironment
