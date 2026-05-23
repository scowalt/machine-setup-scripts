# Machine setup scripts

Idempotent scripts I use to set up my machines.

## AI Coding Agents

The personal-machine setup scripts install/update Gemini CLI, Codex CLI, Pi, RTK, tintinweb Pi subagents, Pi goal/autoresearch extensions, Matt Pocock Pi skills, and Compound Engineering resources for supported agents. Work machines also install RTK and Google Cloud CLI. Set `WORK_MACHINE=1` in `~/.env.local` for work machines. Set `BAN_RTK=1` to skip RTK setup. Set `BAN_COMPOUND_PLUGIN=1` to skip Compound Engineering setup. Set `BAN_PI_SUBAGENTS=1` to keep the tintinweb Pi subagents extension inactive. Set `BAN_PI_GOAL_AUTORESEARCH=1` to keep the Pi goal/autoresearch extensions inactive. Set `BAN_MATT_POCOCK_SKILLS=1` to keep Matt Pocock Pi skills inactive.

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
