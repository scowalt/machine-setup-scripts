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

$script:SetupOriginalPath = $env:PATH
$script:SetupOriginalClaudeCommand = $null
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
# WORK_MACHINE=1
# BAN_COMPOUND_PLUGIN=1
# BAN_PI_SUBAGENTS=1
# BAN_PI_MCP_ADAPTER=1
# BAN_PI_GOAL_AUTORESEARCH=1
# BAN_MATT_POCOCK_SKILLS=1
# BAN_RTK=1
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

    if ($updateExitCode -eq 0) {
        Write-Success "Google Cloud CLI components updated."
    }
    elseif ($updateText -match "component manager is disabled|managed by an external package manager") {
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


# Check whether the installed rtk is Rust Token Killer, not the unrelated Rust Type Kit.
function Test-RtkCliReady {
    $rtkCommand = Get-Command rtk -ErrorAction SilentlyContinue
    if (-not $rtkCommand) {
        return $false
    }

    try {
        & $rtkCommand.Source gain *> $null
        return ($LASTEXITCODE -eq 0)
    }
    catch {
        return $false
    }
}

function Add-RtkToPath {
    param([Parameter(Mandatory=$true)][string]$RtkDir)

    if ($env:PATH -notlike "*$RtkDir*") {
        $env:PATH = "$RtkDir;$env:PATH"
    }

    $currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    if ($currentPath -notlike "*$RtkDir*") {
        if ([string]::IsNullOrWhiteSpace($currentPath)) {
            [Environment]::SetEnvironmentVariable("PATH", $RtkDir, "User")
        }
        else {
            [Environment]::SetEnvironmentVariable("PATH", "$currentPath;$RtkDir", "User")
        }
        Write-Success "Added RTK CLI to PATH."
    }
}

# Function to install RTK (Rust Token Killer) for token-optimized agent command output.
function Install-RtkCli {
    if (Test-EnvLocalFlag "BAN_RTK") {
        Write-Debug "BAN_RTK=1, skipping RTK setup."
        return
    }

    $rtkDir = Join-Path $env:LOCALAPPDATA "rtk\bin"
    if (Test-Path $rtkDir) {
        Add-RtkToPath -RtkDir $rtkDir
    }

    $hadRtk = Test-RtkCliReady
    if ($hadRtk) {
        Write-Message "Updating RTK CLI..."
    }
    elseif (Get-Command rtk -ErrorAction SilentlyContinue) {
        Write-Warning "An rtk command exists, but it does not look like Rust Token Killer. Installing the rtk-ai binary to a user-local directory."
    }
    else {
        Write-Message "Installing RTK CLI..."
    }

    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("rtk-" + [System.Guid]::NewGuid().ToString())
    try {
        New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
        $release = Invoke-RestMethod -Uri "https://api.github.com/repos/rtk-ai/rtk/releases/latest"
        $asset = $release.assets | Where-Object { $_.name -eq "rtk-x86_64-pc-windows-msvc.zip" } | Select-Object -First 1
        if (-not $asset) {
            throw "Could not find Windows RTK release asset."
        }

        $zipPath = Join-Path $tempDir "rtk.zip"
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zipPath
        Expand-Archive -Path $zipPath -DestinationPath $tempDir -Force

        $rtkExe = Get-ChildItem -Path $tempDir -Filter "rtk.exe" -Recurse | Select-Object -First 1
        if (-not $rtkExe) {
            throw "Downloaded RTK archive did not contain rtk.exe."
        }

        New-Item -ItemType Directory -Force -Path $rtkDir | Out-Null
        Copy-Item -Path $rtkExe.FullName -Destination (Join-Path $rtkDir "rtk.exe") -Force
        Add-RtkToPath -RtkDir $rtkDir

        if (Test-RtkCliReady) {
            Write-Success "RTK CLI installed/updated."
        }
        else {
            Write-Warning "RTK installed, but 'rtk gain' did not verify the expected binary."
        }
    }
    catch {
        if ($hadRtk) {
            Write-Warning "Failed to update RTK CLI; existing install remains available: $($_.Exception.Message)"
        }
        else {
            Write-Warning "Failed to install RTK CLI: $($_.Exception.Message)"
        }
    }
    finally {
        if (Test-Path $tempDir) {
            Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# Configure RTK integrations for installed AI agents. Non-fatal by design.
function Setup-RtkIntegrations {
    if (Test-EnvLocalFlag "BAN_RTK") {
        Write-Debug "BAN_RTK=1, skipping RTK integrations."
        return
    }

    if (-not (Test-RtkCliReady)) {
        Write-Warning "RTK CLI is not available; skipping RTK integrations."
        return
    }

    # Automated setup should not prompt for telemetry consent. Users can opt in later with `rtk telemetry enable`.
    & rtk telemetry disable *> $null

    if (Get-Command gemini -ErrorAction SilentlyContinue) {
        Write-Debug "Native Windows RTK Gemini hook setup is Unix-shell based; use WSL for transparent Gemini rewrites."
    }
    else {
        Write-Debug "Gemini CLI not installed; skipping RTK Gemini integration."
    }

    if (Get-Command codex -ErrorAction SilentlyContinue) {
        Write-Message "Configuring RTK for Codex CLI..."
        $output = & rtk init -g --codex 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Success "RTK configured for Codex CLI."
        }
        else {
            Write-Warning "Failed to configure RTK for Codex CLI."
            if ($output) { Write-Debug ($output | Out-String) }
        }
    }
    else {
        Write-Debug "Codex CLI not installed; skipping RTK Codex integration."
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
        & npm install -g --ignore-scripts --prefix $localPrefix "$newPackage@latest"
        if ($LASTEXITCODE -ne 0) {
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
        Write-Host "$success Pi coding agent $piVersion installed/updated at $canonicalPi." -ForegroundColor Green
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

    if (Test-EnvLocalFlag "BAN_PI_SUBAGENTS") {
        if (Update-PiSubagentsSettings -Mode "Remove") {
            Write-Success "Pi subagents extension disabled in Pi settings."
        }
        return
    }

    if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
        Write-Warning "npm not found. Cannot install Pi subagents."
        Write-Debug "Install Node.js/npm, then run: pi install npm:@tintinweb/pi-subagents"
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


function Test-MattPocockPiSkillsDisabled {
    return ((Test-EnvLocalFlag "WORK_MACHINE") -or (Test-EnvLocalFlag "BAN_MATT_POCOCK_SKILLS") -or (Test-EnvLocalFlag "BAN_MATT_POCKOCK_SKILLS"))
}

# Function to remove Matt Pocock skill copies from Pi when disabled
function Remove-MattPocockPiSkills {
    $skills = @(
        "setup-matt-pocock-skills",
        "diagnose",
        "tdd",
        "improve-codebase-architecture",
        "zoom-out",
        "grill-with-docs"
    )

    $defaultAgentDir = Join-Path $env:USERPROFILE ".pi\agent"
    if ($env:PI_CODING_AGENT_DIR) {
        $activeAgentDir = $env:PI_CODING_AGENT_DIR
    }
    else {
        $activeAgentDir = $defaultAgentDir
    }

    $skillsDirs = @((Join-Path $defaultAgentDir "skills"))
    if ($activeAgentDir -ne $defaultAgentDir) {
        $skillsDirs += (Join-Path $activeAgentDir "skills")
    }

    $removed = $false
    $failed = @()
    foreach ($skillsDir in $skillsDirs) {
        foreach ($skill in $skills) {
            $skillPath = Join-Path $skillsDir $skill
            if (Test-Path $skillPath) {
                try {
                    Remove-Item -Path $skillPath -Recurse -Force -ErrorAction Stop
                    if (Test-Path $skillPath) {
                        $failed += $skill
                    }
                    else {
                        $removed = $true
                    }
                }
                catch {
                    $failed += $skill
                }
            }
        }
    }

    if ($failed.Count -gt 0) {
        Write-Warning "Failed to remove Matt Pocock Pi skills: $($failed -join ', ')"
    }
    elseif ($removed) {
        Write-Success "Matt Pocock Pi skills disabled."
    }
    else {
        Write-Debug "Matt Pocock Pi skills disabled; no installed copies found."
    }
}

# Function to install/update Matt Pocock engineering skills for Pi
function Setup-MattPocockPiSkills {
    $skills = @(
        "setup-matt-pocock-skills",
        "diagnose",
        "tdd",
        "improve-codebase-architecture",
        "zoom-out",
        "grill-with-docs"
    )

    if (Test-MattPocockPiSkillsDisabled) {
        if (Test-EnvLocalFlag "WORK_MACHINE") {
            Write-Debug "WORK_MACHINE=1, skipping Matt Pocock Pi skills."
        }
        Remove-MattPocockPiSkills
        return
    }

    if (-not (Get-Command pi -ErrorAction SilentlyContinue)) {
        Write-Warning "Pi coding agent not found. Cannot install Matt Pocock Pi skills."
        return
    }

    if (-not (Enable-PiNodeRuntime)) {
        Write-Warning "Skipping Matt Pocock Pi skills because the Pi Node.js runtime is not ready."
        return
    }

    if (-not (Get-Command npx -ErrorAction SilentlyContinue)) {
        Write-Warning "npx not found. Cannot install Matt Pocock Pi skills."
        Write-Debug "Install Node.js >=20.6, then run: npx --yes skills@latest add mattpocock/skills --global --agent pi --copy"
        return
    }

    $defaultAgentDir = Join-Path $env:USERPROFILE ".pi\agent"
    if ($env:PI_CODING_AGENT_DIR) {
        $agentDir = $env:PI_CODING_AGENT_DIR
    }
    else {
        $agentDir = $defaultAgentDir
    }

    $defaultSkillsDir = Join-Path $defaultAgentDir "skills"
    $skillsDir = Join-Path $agentDir "skills"
    $npxArgs = @("--yes", "skills@latest", "add", "mattpocock/skills", "--global", "--agent", "pi", "--copy", "-y")
    foreach ($skill in $skills) {
        $npxArgs += @("--skill", $skill)
    }

    Write-Message "Installing/updating Matt Pocock Pi skills..."
    $output = & npx @npxArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Failed to install Matt Pocock Pi skills: $output"
        return
    }

    $syncFailed = @()
    if ($agentDir -ne $defaultAgentDir) {
        New-Item -ItemType Directory -Force -Path $skillsDir | Out-Null
        foreach ($skill in $skills) {
            $sourcePath = Join-Path $defaultSkillsDir $skill
            $destPath = Join-Path $skillsDir $skill
            if (Test-Path $sourcePath) {
                try {
                    if (Test-Path $destPath) {
                        Remove-Item -Path $destPath -Recurse -Force -ErrorAction Stop
                    }
                    Copy-Item -Path $sourcePath -Destination $destPath -Recurse -Force -ErrorAction Stop
                }
                catch {
                    $syncFailed += $skill
                }
            }
            else {
                $syncFailed += $skill
            }
        }
    }

    $missing = @()
    foreach ($skill in $skills) {
        $skillFile = Join-Path (Join-Path $skillsDir $skill) "SKILL.md"
        if (-not (Test-Path $skillFile)) {
            $missing += $skill
        }
    }

    if ($syncFailed.Count -gt 0) {
        Write-Warning "Matt Pocock Pi skills installed, but failed to sync to active Pi dir ${agentDir}: $($syncFailed -join ', ')"
    }
    elseif ($missing.Count -eq 0) {
        Write-Success "Matt Pocock Pi skills installed/updated."
    }
    else {
        Write-Warning "Matt Pocock Pi skills install completed, but missing expected skills: $($missing -join ', ')"
    }
}


# Function to remove unsupported AskUserQuestion references from Compound Engineering files installed for Pi
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
        $text = $text -replace '`AskUserQuestion` in [^,;.]* with `ToolSearch select:AskUserQuestion` pre-loaded if needed,\s*', ''
        $text = $text -replace '`AskUserQuestion` in [^,;.]* — call `ToolSearch` with `select:AskUserQuestion`[^;]*;\s*', ''
        $text = $text -replace '`AskUserQuestion` in [^,;.]* \(call `ToolSearch` with `select:AskUserQuestion`[^)]*\),\s*', ''
        $text = $text -replace '`AskUserQuestion` in [^,;.]*,\s*', ''
        $text = $text -replace '`AskUserQuestion` in [^,;.]*\s*', ''
        $text = $text -replace '\s*\*\*[^*]* only:\*\* if `AskUserQuestion`[^\r\n.]*\.[ \t]*', ' '
        $text = $text -replace '\s*In [^,\r\n.]*,? call `ToolSearch` with `select:AskUserQuestion`[^\r\n.]*\.[ \t]*', ' '
        $text = $text -replace '\s*In [^,\r\n.]*,? the tool should already be loaded[^\r\n.]*`ToolSearch`[^\r\n.]*\.[ \t]*', ' '
        $text = $text -replace '\s*In [^\r\n.]* the tool should already be loaded[^\r\n.]*`ToolSearch`[^\r\n.]*\.[ \t]*', ' '
        $text = $text -replace '\s*In [^\r\n.]*`select:AskUserQuestion`[^\r\n.]*\.[ \t]*', ' '
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
    Write-Host "Version 100 | Last changed: Canonicalize Pi and install MCP adapter" -ForegroundColor DarkGray

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
    Install-RtkCli
    Setup-RtkIntegrations
    if (Test-MattPocockPiSkillsDisabled) {
        Setup-MattPocockPiSkills
    }
    if (Install-PiCli) {
        Setup-PiSubagents
        Setup-PiMcpAdapter
        Setup-PiGoalAutoresearch
        if (-not (Test-MattPocockPiSkillsDisabled)) {
            Setup-MattPocockPiSkills
        }
        Setup-PiCompoundEngineering
    }
    else {
        if (Test-EnvLocalFlag "BAN_PI_SUBAGENTS") {
            Setup-PiSubagents
        }
        if (Test-EnvLocalFlag "BAN_PI_MCP_ADAPTER") {
            Setup-PiMcpAdapter
        }
        if (Test-EnvLocalFlag "BAN_PI_GOAL_AUTORESEARCH") {
            Setup-PiGoalAutoresearch
        }
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