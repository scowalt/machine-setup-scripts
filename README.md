# Machine setup scripts

I use several operating systems and don’t want to rebuild my development environment by hand on every machine. These scripts keep my machines equipped with familiar tools; my dotfiles handle their configuration.

## What they do

I use them for both new machines and updates to existing ones. They bring together the pieces of my development environment, with platform-specific choices rather than an identical package list everywhere:

- Everyday tools such as Git, GitHub CLI, fish, and tmux.
- Language runtimes and package managers, including a shared Node.js runtime managed by mise.
- AI coding tools such as Claude Code, Codex, and Pi, along with agent skills.
- Connectivity tools such as Tailscale and Portless.
- My [dotfiles](https://github.com/scowalt/dotfiles), applied through Chezmoi so my shell and tool configuration follow me between machines.

The scripts cover macOS, Ubuntu, WSL, Raspberry Pi, Bazzite, and Windows. Some tools and setup steps differ between personal, work, and headless machines.

## Run it

**These are opinionated personal scripts, not a general-purpose installer.** Review the script for your platform before running it. Setup installs and updates software, applies my dotfiles, and can interrupt running work—including services and connectivity. Choose a suitable window and protect ongoing work first.

### macOS

```bash
curl -sL https://scripts.scowalt.com/setup/mac.sh | bash
```

### Ubuntu

```bash
curl -sL https://scripts.scowalt.com/setup/ubuntu.sh | bash
```

### WSL

```bash
curl -sL https://scripts.scowalt.com/setup/wsl.sh | bash
```

### Raspberry Pi

```bash
curl -sL https://scripts.scowalt.com/setup/pi.sh | bash
```

### Bazzite

```bash
curl -sL https://scripts.scowalt.com/setup/bazzite.sh | bash
```

### Windows

```powershell
iwr -useb https://scripts.scowalt.com/setup/win.ps1 | iex
```

For contributors: [agent guidance](CLAUDE.md) and [design decisions](docs/adr/).
