#!/bin/bash

# Define colors
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
GRAY='\033[0;90m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Print functions for readability
print_section() { printf "\n${BOLD}=== %s ===${NC}\n\n" "$1"; }
print_message() { printf "${CYAN} %s${NC}\n" "$1"; }
print_success() { printf "${GREEN} %s${NC}\n" "$1"; }
print_warning() { printf "${YELLOW} %s${NC}\n" "$1"; }
print_debug() { printf "${GRAY}  %s${NC}\n" "$1"; }
print_error() { printf "${RED} %s${NC}\n" "$1"; }

# Check if running on Raspberry Pi OS
check_raspberry_pi() {
    print_message "Detecting Raspberry Pi hardware or OS…"

    local is_pi=false

    # 1) Look for Raspberry Pi OS IDs
    if [ -f /etc/os-release ]; then
        # shellcheck source=/dev/null
        . /etc/os-release
        if [[ "$ID" =~ ^(raspbian|raspios)$ ]] || [[ "$PRETTY_NAME" =~ Raspberry\ Pi ]]; then
            is_pi=true
        fi
    fi

    # 2) Hardware check via device‑tree model
    if [ "$is_pi" = false ] && [ -r /proc/device-tree/model ]; then
        if grep -q "Raspberry Pi" /proc/device-tree/model 2>/dev/null; then
            is_pi=true
        fi
    fi

    # 3) Fallback to /proc/cpuinfo (older kernels)
    if [ "$is_pi" = false ] && grep -q "Raspberry Pi" /proc/cpuinfo 2>/dev/null; then
        is_pi=true
    fi

    if [ "$is_pi" = true ]; then
        print_success "Raspberry Pi hardware/OS detected."
    else
        print_warning "Could not confirm Raspberry Pi. Continuing anyway…"
    fi
}


# Update dependencies with Raspberry Pi specific optimizations
update_dependencies() {
    print_message "Updating package lists (this may take a while on Raspberry Pi)..."
    sudo apt update
    
    print_message "Upgrading packages (this may take a while)..."
    sudo apt upgrade -y
    
    print_message "Removing unnecessary packages..."
    sudo apt autoremove -y
    
    print_success "Package lists updated."
}

# Update and install core dependencies with Raspberry Pi considerations
update_and_install_core() {
    print_message "Checking and installing core packages as needed..."

    # Define an array of required packages
    local packages=("git" "curl" "fish" "tmux" "fonts-firacode" "gh" "build-essential" "libssl-dev" "zlib1g-dev" "libbz2-dev" "libreadline-dev" "libsqlite3-dev" "wget" "unzip" "llvm" "libncurses5-dev" "libncursesw5-dev" "xz-utils" "tk-dev" "libffi-dev" "liblzma-dev")
    local to_install=()

    # Check each package and add missing ones to the to_install array
    for package in "${packages[@]}"; do
        if ! dpkg -s "$package" &> /dev/null; then
            to_install+=("$package")
        else
            print_debug "$package is already installed."
        fi
    done

    # Install any packages that are not yet installed
    if [ "${#to_install[@]}" -gt 0 ]; then
        print_message "Installing missing packages: ${to_install[*]}"
        sudo apt update -qq > /dev/null
        sudo apt install -qq -y "${to_install[@]}"
        print_success "Missing core packages installed."
    else
        print_success "All core packages are already installed."
    fi
}

# ----------------------[ 1Password CLI ]-------------------------
install_1password_cli() {
    if command -v op >/dev/null; then
        print_debug "1Password CLI already installed."
        return
    fi

    print_message "Installing 1Password CLI…"

    # Make sure gnupg is available for key import
    sudo apt install -y gnupg >/dev/null

    # Import signing key
    curl -sS https://downloads.1password.com/linux/keys/1password.asc \
      | sudo gpg --dearmor --output /usr/share/keyrings/1password-archive-keyring.gpg

    # Figure out repo path for the current CPU architecture
    local dpkg_arch
    dpkg_arch="$(dpkg --print-architecture)"       # arm64, armhf, amd64…
    local repo_arch="$dpkg_arch"
    [[ "$dpkg_arch" == "armhf" ]] && repo_arch="arm"   # 32‑bit Pi

    # Add repo
    echo \
"deb [arch=$dpkg_arch signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] \
https://downloads.1password.com/linux/debian/${repo_arch} stable main" \
        | sudo tee /etc/apt/sources.list.d/1password-cli.list >/dev/null

    # Add debsig‑verify policy (required for future updates)
    sudo mkdir -p /etc/debsig/policies/AC2D62742012EA22/
    curl -sS https://downloads.1password.com/linux/debsig/1password.pol \
      | sudo tee /etc/debsig/policies/AC2D62742012EA22/1password.pol >/dev/null
    curl -sS https://downloads.1password.com/linux/keys/1password.asc \
      | sudo tee /etc/debsig/keys/AC2D62742012EA22.asc >/dev/null

    # Install package
    sudo apt update -qq
    sudo apt install -y 1password-cli

    print_success "1Password CLI installed."
}

setup_ssh_key() {
    print_message "Checking for existing SSH key…"

    mkdir -p ~/.ssh && chmod 700 ~/.ssh

    # Generate a key if none exists
    if [ ! -f ~/.ssh/id_rsa.pub ]; then
        print_warning "No SSH key found. Generating a new one…"
        ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N "" -C "$USER@$(hostname)"
        print_success "SSH key generated."
        print_message "Public key (add this to GitHub if you haven't already):"
        cat ~/.ssh/id_rsa.pub
    else
        print_success "SSH key already present."
    fi
}

verify_github_key() {
    local github_user="${GITHUB_USERNAME:-scowalt}"   # change default if you like
    local keys_url="https://github.com/${github_user}.keys"

    print_message "Verifying that your public key is registered with GitHub user '${github_user}'…"

    # Pull remote keys (fail hard if the request itself fails)
    local remote_keys
    if ! remote_keys="$(curl -fsSL "$keys_url")"; then
        print_error "Failed to download keys from ${keys_url}"
        exit 1
    fi

    # Pick the second field (base64 blob) from the local key
    local local_key_value
    local_key_value=$(awk '{print $2}' ~/.ssh/id_rsa.pub)

    # Search the list returned by GitHub
    if echo "$remote_keys" | awk '{print $2}' | grep -qx "$local_key_value"; then
        print_success "Local key is recognized by GitHub."
    else
        print_error "Your public key is NOT registered with GitHub!"
        print_message "Add this key to https://github.com/settings/keys, then rerun the script:"
        cat ~/.ssh/id_rsa.pub
        exit 1
    fi
}

# Add GitHub to known hosts to avoid prompts
add_github_to_known_hosts() {
    print_message "Ensuring GitHub is in known hosts..."
    local known_hosts_file=~/.ssh/known_hosts
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    touch "$known_hosts_file"
    chmod 600 "$known_hosts_file"

    if ! ssh-keygen -F github.com &>/dev/null; then
        print_message "Adding GitHub's SSH key to known_hosts..."
        if ! ssh-keyscan github.com >> "$known_hosts_file" 2>/dev/null; then
            print_error "Failed to add GitHub's SSH key to known_hosts."
            exit 1
        fi
        print_success "GitHub's SSH key added."
    else
        print_debug "GitHub's SSH key already exists in known_hosts."
    fi
}

# Install Starship with Raspberry Pi considerations
# NOTE: Uses official install script with ARM architecture detection for Raspberry Pi
# DO NOT standardize - ARM detection and Pi-specific optimizations are critical
# Different from other platforms due to ARM compatibility requirements
install_starship() {
    if ! command -v starship &> /dev/null; then
        print_message "Installing Starship prompt (this may take a while on Raspberry Pi)..."
        
        # Check architecture for compatibility
        local arch
        arch=$(uname -m)
        if [[ "$arch" == "armv"* || "$arch" == "aarch64" ]]; then
            print_message "Detected ARM architecture: $arch"
            if curl -sS https://starship.rs/install.sh | sh -s -- -y; then
                print_success "Starship installed."
            else
                print_error "Failed to install Starship."
                return 1
            fi
        else
            print_error "Unsupported architecture: $arch. Starship might not work correctly."
            print_message "Attempting installation anyway..."
            if curl -sS https://starship.rs/install.sh | sh -s -- -y; then
                print_success "Starship installed despite architecture warning."
            else
                print_error "Failed to install Starship."
                return 1
            fi
        fi
    else
        print_debug "Starship is already installed."
    fi
}

install_tailscale() {
    if ! command -v tailscale &>/dev/null; then
        print_message "Installing Tailscale…"
        # Official install script (adds repo + installs package) :contentReference[oaicite:0]{index=0}
        curl -fsSL https://tailscale.com/install.sh | sudo sh
        sudo systemctl enable --now tailscaled
        print_success "Tailscale installed and service started."

        # Optional immediate login
        read -rp "Run 'tailscale up' now to authenticate? (y/n): " ts_up
        if [[ "$ts_up" =~ ^[Yy]$ ]]; then
            print_message "Bringing interface up…"
            sudo tailscale up       # add --authkey=... if you prefer key‑based auth
        else
            print_warning "Skip for now; run 'sudo tailscale up' later to log in."
        fi
    else
        print_debug "Tailscale already installed."
    fi
}

# Install chezmoi with Raspberry Pi considerations
install_chezmoi() {
    if ! command -v chezmoi &> /dev/null; then
        print_message "Installing chezmoi (this may take a while on Raspberry Pi)..."
        if sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/bin"; then
            # Add ~/bin to PATH if not already present
            if ! grep -q "PATH=\$HOME/bin" ~/.bashrc; then
                echo "export PATH=\$HOME/bin:\$PATH" >> ~/.bashrc
                # Source bashrc in the current session to make chezmoi available
                export PATH=$HOME/bin:$PATH
            fi
            print_success "chezmoi installed."
        else
            print_error "Failed to install chezmoi."
            return 1
        fi
    else
        print_debug "chezmoi is already installed."
    fi
}

# Initialize chezmoi with Raspberry Pi optimizations
initialize_chezmoi() {
    # If chezmoi isn't on PATH, fall back to ~/bin/chezmoi
    if ! command -v chezmoi >/dev/null; then
        if [ -x "$HOME/bin/chezmoi" ]; then
            local chezmoi_cmd="$HOME/bin/chezmoi"
        else
            print_error "chezmoi not found. Install chezmoi first."
            return 1
        fi
    else
        local chezmoi_cmd="chezmoi"
    fi

    local chez_src="$HOME/.local/share/chezmoi"

    # ---------- NEW: re‑try if the repo directory exists but is empty ----------
    if [ -d "$chez_src" ] && [ -z "$(ls -A "$chez_src")" ]; then
        print_warning "chezmoi directory exists but is empty – retrying initialization…"
        rm -rf "$chez_src"
    fi
    # --------------------------------------------------------------------------

    if [ ! -d "$chez_src" ]; then
        print_message "Initializing chezmoi with scowalt/dotfiles…"
        if $chezmoi_cmd init --apply scowalt/dotfiles --ssh; then
            print_success "chezmoi initialized via SSH."
        else
            print_error "SSH clone failed. Retrying with HTTPS…"
            if $chezmoi_cmd init --apply https://github.com/scowalt/dotfiles.git; then
                print_success "chezmoi initialized via HTTPS."
            else
                print_error "chezmoi initialization still failed. Check your git credentials."
                return 1
            fi
        fi
    else
        print_debug "chezmoi already initialized."
        $chezmoi_cmd update
        print_success "chezmoi repository updated."
    fi
}

# Configure chezmoi for auto commit, push, and pull
configure_chezmoi_git() {
    local chezmoi_config=~/.config/chezmoi/chezmoi.toml
    if [ ! -f "$chezmoi_config" ]; then
        print_message "Configuring chezmoi with auto-commit, auto-push, and auto-pull..."
        mkdir -p ~/.config/chezmoi
        cat <<EOF > "$chezmoi_config"
[git]
autoCommit = true
autoPush = true
autoPull = true
EOF
        print_success "chezmoi configuration set."
    else
        print_debug "chezmoi configuration already exists."
    fi
}

# Set Fish as the default shell if it isn't already
set_fish_as_default_shell() {
    if [ "$(getent passwd "$USER" | cut -d: -f7)" != "/usr/bin/fish" ]; then
        print_message "Setting Fish as the default shell..."
        if ! grep -Fxq "/usr/bin/fish" /etc/shells; then
            echo "/usr/bin/fish" | sudo tee -a /etc/shells > /dev/null
        fi
        sudo chsh -s /usr/bin/fish "$USER"
        print_success "Fish shell set as default. Please log out and back in for changes to take effect."
    else
        print_debug "Fish shell is already the default shell."
    fi
}

# Install tmux plugins with Raspberry Pi optimizations
install_tmux_plugins() {
    local plugin_dir=~/.tmux/plugins
    mkdir -p "$plugin_dir"
    
    if [ ! -d "$plugin_dir/tpm" ]; then
        print_message "Installing tmux plugin manager..."
        git clone -q https://github.com/tmux-plugins/tpm "$plugin_dir/tpm"
        print_success "tmux plugin manager installed."
    else
        print_debug "tmux plugin manager already installed."
        # Update TPM
        (cd "$plugin_dir/tpm" && git pull -q origin master)
        print_success "tmux plugin manager updated."
    fi

    for plugin in tmux-resurrect tmux-continuum; do
        if [ ! -d "$plugin_dir/$plugin" ]; then
            print_message "Installing $plugin..."
            git clone -q https://github.com/tmux-plugins/$plugin "$plugin_dir/$plugin"
            print_success "$plugin installed."
        else
            print_debug "$plugin already installed."
            # Update plugin
            (cd "$plugin_dir/$plugin" && git pull -q origin master)
            print_success "$plugin updated."
        fi
    done

    # Check if tmux is running
    if tmux info &> /dev/null; then
        print_message "Reloading tmux configuration..."
        tmux source-file ~/.tmux.conf
    else
        print_warning "tmux not running; configuration will be loaded on next start."
    fi
    
    print_message "Installing tmux plugins..."
    "$plugin_dir/tpm/bin/install_plugins" > /dev/null 2>&1
    "$plugin_dir/tpm/bin/update_plugins" all > /dev/null 2>&1
    print_success "tmux plugins installed and updated."
}

# Apply chezmoi configuration
apply_chezmoi_config() {
    print_message "Applying chezmoi configuration…"

    # Locate executable
    local chezmoi_cmd
    if command -v chezmoi >/dev/null;      then chezmoi_cmd="chezmoi"
    elif [ -x "$HOME/bin/chezmoi" ];       then chezmoi_cmd="$HOME/bin/chezmoi"
    else
        print_error "chezmoi not found."
        exit 1
    fi

    # Run verbosely; bail if anything returns non‑zero
    if ! $chezmoi_cmd apply --verbose; then
        print_error "chezmoi apply failed – fix the dotfiles, then rerun the script."
        exit 1
    fi

    print_success "chezmoi configuration applied."
}


# Setup a small swap file if memory is limited
setup_swap() {
    local total_mem
    total_mem=$(free -m | awk '/^Mem:/{print $2}')
    
    if [ "$total_mem" -lt 2048 ]; then
        print_message "Limited RAM detected ($total_mem MB). Setting up swap file..."
        
        # Check if swap is already configured
        if [ "$(swapon --show | wc -l)" -gt 0 ]; then
            print_debug "Swap already configured."
            swapon --show
            return
        fi
        
        # Create a 1GB swap file
        sudo fallocate -l 1G /swapfile
        sudo chmod 600 /swapfile
        sudo mkswap /swapfile
        sudo swapon /swapfile
        
        # Make swap permanent
        if ! grep -q "/swapfile" /etc/fstab; then
            echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab > /dev/null
        fi
        
        # Adjust swappiness
        echo 'vm.swappiness=10' | sudo tee -a /etc/sysctl.conf > /dev/null
        sudo sysctl vm.swappiness=10
        
        print_success "Swap file configured."
    else
        print_message "Sufficient RAM detected ($total_mem MB). Skipping swap setup."
    fi
}

# ----------------------[ SSH *server* helper ]-------------------
enable_ssh_server() {
    # Install server package if missing
    if ! dpkg -s openssh-server &>/dev/null; then
        print_message "Installing OpenSSH server…"
        sudo apt install -y openssh-server
    else
        print_debug "OpenSSH server already installed."
    fi

    # Enable and start the service now and on boot
    sudo systemctl enable --now ssh
    print_success "OpenSSH server enabled and running."
}

# ----------------------[ ssh‑agent helper ]----------------------
ensure_ssh_agent() {
    print_message "Making sure ssh‑agent is running and key is loaded…"

    # If a key is already listed, we're done.
    if ssh-add -l >/dev/null 2>&1; then
        print_success "ssh‑agent already running with a key loaded."
        return
    fi

    # Otherwise start (or reuse) an agent.
    if [ -z "$SSH_AUTH_SOCK" ] || ! ssh-add -l >/dev/null 2>&1; then
        print_warning "Starting a new ssh‑agent instance…"
        eval "$(ssh-agent -s)" >/dev/null
    fi

    # Add the default key
    if ssh-add ~/.ssh/id_rsa >/dev/null 2>&1; then
        print_success "SSH key added to agent."
    else
        print_error "Could not add ~/.ssh/id_rsa to ssh‑agent. Check permissions."
        exit 1
    fi

    # Persist agent environment for future shells ----------------
    echo "export SSH_AUTH_SOCK=$SSH_AUTH_SOCK" >  ~/.ssh-agent-env
    echo "export SSH_AGENT_PID=$SSH_AGENT_PID" >> ~/.ssh-agent-env

    # Source for future Bash sessions
    if ! grep -q 'ssh-agent-env' ~/.bashrc 2>/dev/null; then
        echo '[ -f ~/.ssh-agent-env ] && source ~/.ssh-agent-env >/dev/null' >> ~/.bashrc
    fi

    # Source for future Fish sessions
    if [ -d ~/.config/fish/conf.d ]; then
        cat <<EOF > ~/.config/fish/conf.d/ssh-agent.fish
# auto‑generated by setup script
if test -f ~/.ssh-agent-env
    source ~/.ssh-agent-env ^/dev/null
end
EOF
    fi
    # ------------------------------------------------------------
}

# Install git-town by downloading binary directly
install_git_town() {
    if command -v git-town &> /dev/null; then
        print_debug "git-town is already installed."
        return
    fi

    print_message "Installing git-town via direct binary download..."
    
    # Detect architecture
    local arch
    arch=$(uname -m)
    local git_town_arch
    
    case "$arch" in
        x86_64)
            git_town_arch="linux_intel_64"
            ;;
        aarch64)
            git_town_arch="linux_arm_64"
            ;;
        armv7l)
            git_town_arch="linux_arm_32"
            ;;
        *)
            print_error "Unsupported architecture: $arch"
            return 1
            ;;
    esac
    
    # Create local bin directory if it doesn't exist
    local bin_dir="$HOME/.local/bin"
    mkdir -p "$bin_dir"
    
    # Download the latest binary
    local download_url="https://github.com/git-town/git-town/releases/latest/download/git-town_${git_town_arch}.tar.gz"
    local temp_dir
    temp_dir=$(mktemp -d)
    
    print_message "Downloading git-town binary for $arch architecture..."
    if curl -sL "$download_url" | tar -xz -C "$temp_dir"; then
        # Move binary to local bin
        if mv "$temp_dir/git-town" "$bin_dir/git-town"; then
            chmod +x "$bin_dir/git-town"
            print_success "git-town installed to $bin_dir/git-town"
            
            # Add to PATH if not already present
            if ! echo "$PATH" | grep -q "$bin_dir"; then
                print_message "Adding $bin_dir to PATH in ~/.bashrc"
                echo "export PATH=\$HOME/.local/bin:\$PATH" >> ~/.bashrc
                export PATH="$bin_dir:$PATH"
            fi
        else
            print_error "Failed to move git-town binary."
            rm -rf "$temp_dir"
            return 1
        fi
    else
        print_error "Failed to download git-town."
        rm -rf "$temp_dir"
        return 1
    fi
    
    rm -rf "$temp_dir"
}

# Configure git-town completions
configure_git_town() {
    if command -v git-town &> /dev/null; then
        print_message "Configuring git-town completions..."
        
        # Set up Fish shell completions for git-town
        if [ -d ~/.config/fish/completions ]; then
            if ! [ -f ~/.config/fish/completions/git-town.fish ]; then
                git town completion fish > ~/.config/fish/completions/git-town.fish
                print_success "git-town Fish completions configured."
            else
                print_debug "git-town Fish completions already configured."
            fi
        fi
        
        # Set up Bash completions for git-town
        local bash_completion_dir="/etc/bash_completion.d"
        if [ -d "$bash_completion_dir" ]; then
            if ! [ -f "$bash_completion_dir/git-town" ]; then
                git town completion bash | sudo tee "$bash_completion_dir/git-town" > /dev/null
                print_success "git-town Bash completions configured."
            else
                print_debug "git-town Bash completions already configured."
            fi
        fi
    else
        print_warning "git-town not found, skipping completion setup."
    fi
}

# ----------------------[ Fast Node Manager ]--------------------
install_fnm() {
    if command -v fnm >/dev/null; then
        print_debug "fnm already installed."
        return
    fi

    print_message "Installing fnm (Fast Node Manager)…"
    if curl -fsSL https://fnm.vercel.app/install | bash -s -- --skip-shell; then
        print_success "fnm installed. Shell configuration will be managed by chezmoi."
    else
        print_error "Failed to install fnm."
        return 1
    fi
}

# Setup Node.js using fnm
setup_nodejs() {
    print_message "Setting up Node.js with fnm..."
    
    # Initialize fnm for current session
    if [ -s "$HOME/.local/share/fnm/fnm" ]; then
        export PATH="$HOME/.local/share/fnm:$PATH"
        eval "$(fnm env --use-on-cd)"
    else
        print_warning "fnm not found in expected location. Skipping Node.js setup."
        return
    fi
    
    # Check if fnm is now available
    if ! command -v fnm &> /dev/null; then
        print_warning "fnm command not available. Skipping Node.js setup."
        return
    fi
    
    # Check if any Node.js version is installed
    if fnm list | grep -q .; then
        print_debug "Node.js version already installed."
        
        # Check if a default/global version is set
        local current_version
        current_version=$(fnm current 2>/dev/null || echo "none")
        if [ "$current_version" != "none" ] && [ -n "$current_version" ]; then
            print_debug "Global Node.js version already set: $current_version"
        else
            print_message "No global Node.js version set. Setting the first installed version as default..."
            local first_version
            first_version=$(fnm list | grep -v "system" | head -n1 | awk '{print $2}')
            if [ -n "$first_version" ]; then
                fnm default "$first_version"
                print_success "Set $first_version as default Node.js version."
            fi
        fi
    else
        print_message "No Node.js version installed. Installing latest LTS..."
        print_warning "Note: Compiling Node.js on Raspberry Pi can take 10-20 minutes."
        if fnm install --lts; then
            print_success "Installed latest LTS Node.js."
            # Set it as default
            fnm default "$(fnm current)"
            print_success "Set $(fnm current) as default Node.js version."
        else
            print_error "Failed to install Node.js."
            return 1
        fi
    fi
}

# NOTE: Claude Code is not installed on Raspberry Pi
# Primary development is not expected to happen on Pi devices
# Claude Code can be manually installed via npm if needed:
# npm install -g @anthropic-ai/claude-code

# Install act for running GitHub Actions locally
install_act() {
    if ! command -v act &> /dev/null; then
        print_message "Installing act (GitHub Actions runner)..."
        # Use the official install script
        if ! (curl -s https://raw.githubusercontent.com/nektos/act/master/install.sh | sudo bash); then
            print_error "Failed to install act."
            exit 1
        fi
        print_success "act installed."
    else
        print_debug "act is already installed."
    fi
}

# Install Infisical CLI
install_infisical() {
    if command -v infisical &> /dev/null; then
        print_debug "Infisical CLI is already installed."
        return
    fi

    print_message "Installing Infisical CLI..."
    if ! (curl -1sLf 'https://artifacts-cli.infisical.com/setup.deb.sh' | sudo -E bash); then
        print_error "Failed to add Infisical repository."
        exit 1
    fi
    sudo apt update -qq
    if ! sudo apt install -y infisical; then
        print_error "Failed to install Infisical CLI. Please review the output above."
        exit 1
    fi
    print_success "Infisical CLI installed."
}

# Install pyenv for Python version management with Raspberry Pi optimizations
install_pyenv() {
    if ! command -v pyenv &> /dev/null; then
        # Check if ~/.pyenv exists but pyenv command is not available
        if [ -d "$HOME/.pyenv" ]; then
            print_warning "pyenv directory exists but command not found. Trying to fix PATH..."
            export PYENV_ROOT="$HOME/.pyenv"
            export PATH="$PYENV_ROOT/bin:$PATH"
            if command -v pyenv &> /dev/null; then
                print_success "pyenv found after fixing PATH."
                # Still show memory warning for Pi
                local total_mem
                total_mem=$(free -m | awk '/^Mem:/{print $2}')
                if [ "$total_mem" -lt 1024 ]; then
                    print_warning "Limited RAM detected. Python compilation may be slow or fail."
                    print_message "Consider using pre-built Python packages or increasing swap."
                fi
                return
            else
                print_error "pyenv directory exists but binary not found. Manual intervention may be required."
                return 1
            fi
        fi
        
        print_message "Installing pyenv (this may take a while on Raspberry Pi)..."
        # Use the official install script
        if curl -L https://github.com/pyenv/pyenv-installer/raw/master/bin/pyenv-installer | bash; then
            print_success "pyenv installed. Shell configuration will be managed by chezmoi."
        else
            print_error "Failed to install pyenv."
            return 1
        fi
        
        # Check available memory for warning about Python compilation
        local total_mem
    total_mem=$(free -m | awk '/^Mem:/{print $2}')
        if [ "$total_mem" -lt 1024 ]; then
            print_warning "Low memory detected. Python compilation may take a very long time."
            print_message "Consider using system Python instead if compilation fails."
        fi
    else
        print_debug "pyenv is already installed."
    fi
}

# Main execution
echo -e "\n${BOLD}🍓 Raspberry Pi Development Environment Setup${NC}"
echo -e "${GRAY}Version 20 | Last changed: Fix fnm version parsing with awk${NC}"

print_section "System Detection & Setup"
check_raspberry_pi
setup_swap

print_section "System Updates"
update_dependencies
update_and_install_core

print_section "Development Tools"
install_1password_cli
install_fnm
setup_nodejs
install_pyenv
install_infisical

print_section "Network & SSH"
enable_ssh_server
install_tailscale         
setup_ssh_key
verify_github_key
add_github_to_known_hosts
ensure_ssh_agent

print_section "Terminal & Shell"
install_starship
install_git_town
configure_git_town

print_section "Dotfiles Management"
install_chezmoi
initialize_chezmoi
configure_chezmoi_git
apply_chezmoi_config

print_section "Shell Configuration"
set_fish_as_default_shell
install_act
install_tmux_plugins

echo -e "\n${GREEN}${BOLD}✨ Setup complete! Please log out and log back in for all changes to take effect.${NC}\n"