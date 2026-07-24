# Machine setup scripts

Idempotent scripts I use to set up my machines.

## AI Coding Agents

The setup scripts install/update Claude Code CLI, Gemini CLI, Codex CLI, Pi, RTK, tintinweb Pi subagents, Pi MCP adapter, and Pi goal/autoresearch extensions. Personal machines also install Matt Pocock Pi skills; work machines also install Google Cloud CLI. Set `WORK_MACHINE=1` in `~/.env.local` for work machines. Set `BAN_CLAUDE_CODE=1` to skip Claude Code CLI setup. Set `BAN_RTK=1` to skip RTK setup. Set `BAN_PI_SUBAGENTS=1` to keep the tintinweb Pi subagents extension inactive. Set `BAN_PI_MCP_ADAPTER=1` to keep the Pi MCP adapter inactive. Set `BAN_PI_GOAL_AUTORESEARCH=1` to keep the Pi goal/autoresearch extensions inactive. Set `BAN_MATT_POCOCK_SKILLS=1` to keep Matt Pocock Pi skills inactive.

Claude Code is installed with Anthropic's native installer rather than npm/Bun. Setup only ensures the `claude` CLI exists; run Claude Code's normal login/account flow before using Fable. If setup warns that another `claude` command shadows the native binary, resolve PATH/package shadowing or use the native path shown in the warning before authenticating.

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
