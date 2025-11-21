# NOTE: starship installed via WinGet for Windows ecosystem integration
# DO NOT change to other methods - WinGet provides automatic updates and system integration
$wingetPackages = (
    "tailscale.tailscale",
    "Readdle.Spark",
    "Google.Chrome",
    "Schniz.fnm",
    "twpayne.chezmoi",
    "Git.Git",
    "Tyrrrz.LightBulb",
    "Microsoft.VisualStudioCode",
    "Microsoft.PowerToys",
    "File-New-Project.EarTrumpet",
    "AgileBits.1Password",
    "Starship.Starship",
    "mulaRahul.Keyviz",
    "GitHub.cli",
    "Oven-sh.Bun",
    "Beeper.Beeper",
    "Flow-Launcher.Flow-Launcher",
    "gerardog.gsudo",
    "strayge.tray-monitor",
    "DEVCOM.JetBrainsMonoNerdFont",
    "nektos.act"
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
        chezmoi init --apply scowalt/dotfiles --ssh
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
    chezmoi apply
    Write-Host "$success chezmoi dotfiles applied." -ForegroundColor Green
}

# Function to update chezmoi dotfiles repository to latest version
function Update-Chezmoi {
    $chezmoiConfigPath = "$HOME\AppData\Local\chezmoi"
    if (Test-Path $chezmoiConfigPath) {
        Write-Host "$arrow Updating chezmoi dotfiles repository..." -ForegroundColor Cyan
        $updateOutput = chezmoi update 2>&1
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

# Function to install git-town by downloading binary directly (not available via winget)
function Install-GitTown {
    if (-not (Get-Command git-town -ErrorAction SilentlyContinue)) {
        Write-Host "$arrow Installing git-town via direct binary download..." -ForegroundColor Cyan
        
        # Create directory for git-town if it doesn't exist
        $gitTownPath = "$env:LOCALAPPDATA\git-town"
        if (-not (Test-Path $gitTownPath)) {
            New-Item -ItemType Directory -Force -Path $gitTownPath
        }
        
        # Download the latest Windows binary
        $downloadUrl = "https://github.com/git-town/git-town/releases/latest/download/git-town_windows_intel_64.exe"
        $binaryPath = "$gitTownPath\git-town.exe"
        
        try {
            Write-Host "$arrow Downloading git-town binary..." -ForegroundColor Cyan
            Invoke-WebRequest -Uri $downloadUrl -OutFile $binaryPath
            
            # Add to PATH if not already there
            $currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
            if ($currentPath -notlike "*$gitTownPath*") {
                [Environment]::SetEnvironmentVariable("PATH", "$currentPath;$gitTownPath", "User")
                Write-Host "$success Added git-town to PATH." -ForegroundColor Green
            }
            
            Write-Host "$success git-town installed." -ForegroundColor Green
        }
        catch {
            Write-Host "$failIcon Failed to download git-town: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    else {
        Write-Debug "git-town is already installed."
    }
}

# Function to configure git-town completions
function Set-GitTownCompletions {
    if (Get-Command git-town -ErrorAction SilentlyContinue) {
        Write-Host "$arrow Configuring git-town completions..." -ForegroundColor Cyan
        
        # Set up PowerShell completions for git-town
        $profileDir = Split-Path $PROFILE
        if (-not (Test-Path $profileDir)) {
            New-Item -ItemType Directory -Force -Path $profileDir
        }
        
        $gitTownCompletionCommand = 'git town completion powershell | Out-String | Invoke-Expression'
        $escapedPattern = [regex]::Escape($gitTownCompletionCommand)
        
        if (-not (Select-String -Path $PROFILE -Pattern $escapedPattern -Quiet)) {
            Add-Content -Path $PROFILE -Value "`n$gitTownCompletionCommand"
            Write-Host "$success git-town PowerShell completions configured." -ForegroundColor Green
        }
        else {
            Write-Debug "git-town PowerShell completions already configured."
        }
    }
    else {
        Write-Host "$warnIcon git-town not found, skipping completion setup." -ForegroundColor Yellow
    }
}

# Function to add Starship initialization to PowerShell profile
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

# Function to install Infisical CLI via Scoop
function Install-Infisical {
    if (-not (Get-Command infisical -ErrorAction SilentlyContinue)) {
        Write-Host "$arrow Installing Infisical CLI via Scoop..." -ForegroundColor Cyan
        
        # Check if Scoop is installed
        if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
            Write-Host "$arrow Installing Scoop package manager..." -ForegroundColor Cyan
            Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
            Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
            Write-Host "$success Scoop installed." -ForegroundColor Green
        }
        
        # Install Infisical via Scoop
        scoop install infisical
        if ($?) {
            Write-Host "$success Infisical CLI installed." -ForegroundColor Green
        }
        else {
            Write-Host "$failIcon Failed to install Infisical CLI." -ForegroundColor Red
        }
    }
    else {
        Write-Debug "Infisical CLI is already installed."
    }
}

# Function to install pyenv-win for Python version management
function Install-PyenvWin {
    $pyenvPath = "$env:USERPROFILE\.pyenv"
    
    if (-not (Test-Path "$pyenvPath\pyenv-win\bin\pyenv.bat")) {
        Write-Host "$arrow Installing pyenv-win..." -ForegroundColor Cyan
        
        # Clone pyenv-win repository
        if (Get-Command git -ErrorAction SilentlyContinue) {
            git clone https://github.com/pyenv-win/pyenv-win.git "$pyenvPath"
            
            # Add pyenv to PATH
            $currentUserPath = [Environment]::GetEnvironmentVariable("PATH", "User")
            $pyenvBinPath = "$pyenvPath\pyenv-win\bin"
            $pyenvShimsPath = "$pyenvPath\pyenv-win\shims"
            
            if ($currentUserPath -notlike "*$pyenvBinPath*") {
                [Environment]::SetEnvironmentVariable("PATH", "$pyenvBinPath;$pyenvShimsPath;$currentUserPath", "User")
                Write-Host "$success Added pyenv to PATH." -ForegroundColor Green
            }
            
            # Add PYENV_HOME environment variable
            [Environment]::SetEnvironmentVariable("PYENV_HOME", "$pyenvPath\pyenv-win", "User")
            [Environment]::SetEnvironmentVariable("PYENV", "$pyenvPath\pyenv-win", "User")
            
            Write-Host "$success pyenv-win installed. PowerShell profile configuration will be managed by chezmoi." -ForegroundColor Green
        }
        else {
            Write-Host "$failIcon Git is required to install pyenv-win. Please install Git first." -ForegroundColor Red
        }
    }
    else {
        Write-Debug "pyenv-win is already installed."
    }
}

# Function to setup Node.js using fnm
function Setup-Nodejs {
    Write-Host "$arrow Setting up Node.js with fnm..." -ForegroundColor Cyan
    
    # Initialize fnm for current session
    if (Get-Command fnm -ErrorAction SilentlyContinue) {
        fnm env --use-on-cd | Out-String | Invoke-Expression
    }
    else {
        Write-Host "$warnIcon fnm command not available. Skipping Node.js setup." -ForegroundColor Yellow
        return
    }
    
    # Check if any Node.js version is installed
    $installedVersions = fnm list 2>$null
    if ($installedVersions) {
        Write-Debug "Node.js version already installed."
        
        # Check if a default/global version is set
        try {
            $currentVersion = fnm current 2>$null
            if ($currentVersion) {
                Write-Debug "Global Node.js version already set: $currentVersion"
            }
            else {
                Write-Host "$arrow No global Node.js version set. Setting the first installed version as default..." -ForegroundColor Cyan
                $firstVersion = ($installedVersions | Select-Object -First 1) -replace '\*?\s*', ''
                if ($firstVersion) {
                    fnm default $firstVersion
                    Write-Host "$success Set $firstVersion as default Node.js version." -ForegroundColor Green
                }
            }
        }
        catch {
            # fnm current may fail if no version is set
            Write-Host "$arrow No global Node.js version set. Setting the first installed version as default..." -ForegroundColor Cyan
            $firstVersion = ($installedVersions | Select-Object -First 1) -replace '\*?\s*', ''
            if ($firstVersion) {
                fnm default $firstVersion
                Write-Host "$success Set $firstVersion as default Node.js version." -ForegroundColor Green
            }
        }
    }
    else {
        Write-Host "$arrow No Node.js version installed. Installing latest LTS..." -ForegroundColor Cyan
        fnm install --lts
        if ($?) {
            Write-Host "$success Installed latest LTS Node.js." -ForegroundColor Green
            # Set it as default
            $currentVersion = fnm current
            fnm default $currentVersion
            Write-Host "$success Set $currentVersion as default Node.js version." -ForegroundColor Green
        }
        else {
            Write-Host "$failIcon Failed to install Node.js." -ForegroundColor Red
        }
    }
}

# Function to install Claude Code via npm
function Install-ClaudeCode {
    if (Get-Command claude -ErrorAction SilentlyContinue) {
        Write-Debug "Claude Code is already installed."
        return
    }
    
    Write-Host "$arrow Installing Claude Code..." -ForegroundColor Cyan
    
    # Try to initialize fnm if available
    if (Get-Command fnm -ErrorAction SilentlyContinue) {
        # Initialize fnm for the current PowerShell session
        fnm env --use-on-cd | Out-String | Invoke-Expression
    }
    
    # Make sure npm is available
    if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
        Write-Host "$warnIcon npm not found. Make sure fnm is installed and Node.js is set up." -ForegroundColor Yellow
        Write-Host "$arrow You may need to install Claude Code manually after setting up Node.js:" -ForegroundColor Cyan
        Write-Host "  npm install -g @anthropic-ai/claude-code" -ForegroundColor Cyan
        return
    }
    
    # Install Claude Code globally via npm
    try {
        npm install -g @anthropic-ai/claude-code
        if ($?) {
            Write-Host "$success Claude Code installed." -ForegroundColor Green
        }
        else {
            Write-Host "$failIcon Failed to install Claude Code." -ForegroundColor Red
        }
    }
    catch {
        Write-Host "$failIcon Failed to install Claude Code: $($_.Exception.Message)" -ForegroundColor Red
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
    # Try to initialize fnm if available
    if (Get-Command fnm -ErrorAction SilentlyContinue) {
        fnm env --use-on-cd | Out-String | Invoke-Expression
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

# Main setup function to call all necessary steps
function Initialize-WindowsEnvironment {
    $windowsIcon = [char]0xf17a  # Windows logo
    Write-Host "`n$windowsIcon Windows Development Environment Setup" -ForegroundColor White -BackgroundColor DarkBlue
    Write-Host "Version 34 | Last changed: Add chezmoi update step" -ForegroundColor DarkGray
    
    Write-Section "Package Installation"
    Install-WingetPackages
    
    Write-Section "SSH Configuration"
    Test-GitHubSSHKey # this needs to be run before chezmoi to get access to dotfiles
    
    Write-Section "Dotfiles Management"
    Install-Chezmoi
    Update-Chezmoi
    
    Write-Section "Development Tools"
    Install-GitTown
    Set-GitTownCompletions
    Install-PyenvWin
    Install-Infisical
    
    Write-Section "Terminal Configuration"
    Set-StarshipInit
    Set-WindowsTerminalConfiguration
    
    Write-Section "Additional Development Tools"
    Setup-Nodejs
    Install-ClaudeCode
    
    Write-Section "System Updates"
    Install-WingetUpdates
    Update-NpmGlobalPackages
    Install-WindowsUpdates # this should always be LAST since it may prompt a system reboot

    Write-Host "`n$sparkles Setup complete!" -ForegroundColor Green -BackgroundColor DarkGreen
}

# Run the main setup function
Initialize-WindowsEnvironment