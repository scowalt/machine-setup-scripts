# NOTE: starship installed via WinGet for Windows ecosystem integration
# DO NOT change to other methods - WinGet provides automatic updates and system integration
$wingetPackages = (
    "tailscale.tailscale",
    "Readdle.Spark",
    "Google.Chrome",
    "TheBrowserCompany.Arc",
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
    "Anysphere.Cursor",
    "Oven-sh.Bun",
    "Beeper.Beeper",
    "Flow-Launcher.Flow-Launcher",
    "gerardog.gsudo",
    "GnuWin32.Which",
    "strayge.tray-monitor",
    "DEVCOM.JetBrainsMonoNerdFont",
    "Infisical.CLI",
    "git-town.git-town"
)

# Define Nerd Font symbols using Unicode code points
$arrow = [char]0xf0a9      # Arrow icon for actions
$success = [char]0xf00c    # Checkmark icon for success
$warnIcon = [char]0xf071   # Warning icon for warnings
$failIcon = [char]0xf00d   # Cross icon for errors

function Install-Chezmoi {
    if (-not (Get-Command chezmoi -ErrorAction SilentlyContinue)) {
        Write-Host "$failIcon Failed to install chezmoi." -ForegroundColor Red
        exit 1
    }
    else {
        Write-Host "$warnIcon chezmoi is already installed." -ForegroundColor Yellow
    }

    # Initialize chezmoi if not already initialized
    $chezmoiConfigPath = "$HOME\AppData\Local\chezmoi"
    if (-not (Test-Path $chezmoiConfigPath)) {
        Write-Host "$arrow Initializing chezmoi with scowalt/dotfiles..." -ForegroundColor Cyan
        chezmoi init --apply scowalt/dotfiles --ssh
        Write-Host "$success chezmoi initialized with scowalt/dotfiles." -ForegroundColor Green
    }
    else {
        Write-Host "$warnIcon chezmoi is already initialized." -ForegroundColor Yellow
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
        Write-Host "$warnIcon chezmoi configuration already exists." -ForegroundColor Yellow
    }

    Write-Host "$arrow Applying chezmoi dotfiles..." -ForegroundColor Cyan
    chezmoi apply
    Write-Host "$success chezmoi dotfiles applied." -ForegroundColor Green
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
            Write-Host "$warnIcon git-town PowerShell completions already configured." -ForegroundColor Yellow
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
        Write-Host "$warnIcon Starship initialization command is already in PowerShell profile." -ForegroundColor Yellow
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
    Write-Host "$arrow Starting Windows setup v19" -ForegroundColor Cyan
    Install-WingetPackages
    Test-GitHubSSHKey # this needs to be run before chezmoi to get access to dotfiles
    Install-Chezmoi
    Set-GitTownCompletions
    Set-StarshipInit
    Set-WindowsTerminalConfiguration
    Install-WingetUpdates

    Install-WindowsUpdates # this should always be LAST since it may prompt a system reboot
    Write-Host "$success Done" -ForegroundColor Green
}

# Run the main setup function
Initialize-WindowsEnvironment