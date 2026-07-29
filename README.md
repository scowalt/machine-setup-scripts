# Machine setup scripts

Idempotent scripts I use to set up my machines.

## AI Coding Agents

Every machine setup script (macOS, Ubuntu, WSL, Raspberry Pi, Bazzite, and Windows) installs/updates Claude Code CLI and Codex CLI, Notion CLI (`ntn`), Gemini CLI, Pi, RTK, tintinweb Pi subagents, Pi MCP adapter, Pi Claude bridge, and Pi goal/autoresearch extensions. Personal machines also install Matt Pocock Pi skills; work machines also install Google Cloud CLI. Set `WORK_MACHINE=1` in `~/.env.local` for work machines. Set `BAN_CLAUDE_CODE=1` to skip Claude Code CLI setup. Set `BAN_RTK=1` to skip RTK setup. Set `BAN_PI_SUBAGENTS=1` to keep the tintinweb Pi subagents extension inactive. Set `BAN_PI_MCP_ADAPTER=1` to keep the Pi MCP adapter inactive. Set `BAN_PI_GOAL_AUTORESEARCH=1` to keep the Pi goal/autoresearch extensions inactive. Set `BAN_MATT_POCOCK_SKILLS=1` to keep Matt Pocock Pi skills inactive.

Claude Code is installed with Anthropic's native installer rather than npm/Bun. Setup only ensures the `claude` CLI exists; run Claude Code's normal login/account flow before using Fable. If setup warns that another `claude` command shadows the native binary, resolve PATH/package shadowing or use the native path shown in the warning before authenticating.

Notion CLI is installed with Notion's native installer on macOS and Linux and with WinGet on Windows. The native installer supports x64 and ARM64, while the Windows package supports x64 only; unsupported architectures warn and continue setup. Setup does not authenticate Notion CLI or configure shell completions. Run `ntn login` manually when you are ready to connect a workspace.

## Connectivity tools

Every machine setup script installs Portless CLI for Tailscale HTTPS tunnel helpers.

## Headless Paseo daemon

Set `HEADLESS=1` only when provisioning a machine that must remain remotely operable after logout or reboot. On native Linux setup scripts (`ubuntu.sh`, `pi.sh`, and `bazzite.sh`), this installs `@getpaseo/cli`, creates a managed `paseo.service` systemd user service with lingering enabled, starts it, and verifies local daemon health before setup succeeds. Ubuntu only configures unrestricted passwordless sudo when `HEADLESS_PASSWORDLESS_SUDO=1` is also set.

`HEADLESS=1` is an exact-match provisioning trigger, not an off switch. Unset values, `HEADLESS=0`, and `HEADLESS=true` do not install or mutate Paseo service state. To disable a previously configured machine, manually stop/disable the managed service and use Paseo's normal unpairing/removal flow.

macOS `HEADLESS=1` currently fails unless `PASEO_MACOS_HEADLESS_CANARY=1` is also set for an approved no-login canary run. WSL and native Windows fail early with a clear unsupported message because they cannot yet guarantee a true no-login Paseo daemon after host reboot.

Setup preserves Paseo's relay-based connection model, does not open inbound ports, and does not run or print pairing material. After the daemon is running, pair manually with Paseo's normal pairing flow.

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

## Bazzite

```bash
curl -sL https://scripts.scowalt.com/setup/bazzite.sh | bash
```
