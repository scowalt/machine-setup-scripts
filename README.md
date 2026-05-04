# Machine setup scripts

Idempotent scripts I use to set up my machines.

## AI Coding Agents

The personal-machine setup scripts install/update Claude Code, Gemini CLI, Codex CLI, Pi, tintinweb Pi subagents, and Compound Engineering resources for supported agents. Set `WORK_MACHINE=1` in `~/.env.local` for work machines. Set `BAN_COMPOUND_PLUGIN=1` to skip Compound Engineering setup. Set `BAN_PI_SUBAGENTS=1` to keep the tintinweb Pi subagents extension inactive.

## Windows

```powershell
iwr -useb https://scripts.scowalt.com/setup/win.ps1 | iex
```

## WSL

```bash
curl -sL https://scripts.scowalt.com/setup/wsl.sh | bash
```

## MacOS

```bash
curl -sL https://scripts.scowalt.com/setup/mac.sh | bash
```

## Ubuntu

```bash
curl -sL https://scripts.scowalt.com/setup/ubuntu.sh | bash
```

## Raspberry Pi

```bash
curl -sL https://scripts.scowalt.com/setup/pi.sh | bash
```

## Arch Linux / Omarchy

```bash
curl -sL https://scripts.scowalt.com/setup/omarchy.sh | bash
```

## Bazzite

```bash
curl -sL https://scripts.scowalt.com/setup/bazzite.sh | bash
```
