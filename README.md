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

## Pi context configuration

Dotfiles own Pi's model context overrides and per-model compaction budgets as well as model selection. In particular, `openai-codex/gpt-6-astra` uses an 872,000-token window with a 128,000-token response reserve (compaction above 744,000). Setup's retired-provider cleanup and optional z.ai seeding preserve the existing `openai-codex.modelOverrides` and `compaction.modelOverrides` instead of replacing them. Custom global profiles retain their existing configuration; setup does not seed this override outside Chezmoi's managed profile.

Run `bash tests/pi-model-defaults-contract.sh` to verify preservation across repeated setup helpers, personal/work settings, default/custom profiles, and optional z.ai credentials. The suite uses temporary homes and extracted helpers, not live setup. PowerShell coverage runs when `pwsh` is installed; running it on Linux does not establish native Windows ACL behavior. Dotfiles separately tests rendering, repeated applies, and Pi's native compaction threshold.

For contributors: [agent guidance](CLAUDE.md) and [design decisions](docs/adr/).
