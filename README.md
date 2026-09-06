# Machine setup scripts

Idempotent scripts I use to set up my machines.

## Setup logs

Every setup run writes a local log under `~/.local/log/machine-setup` and makes one best-effort upload to `logs.scowalt.com` after either success or a detected fatal error. If the upload fails, the setup result is preserved and the script prints the local log path for manual recovery.

## AI Coding Agents

Every setup script installs or updates the main AI development tools. The supported systems are macOS, Ubuntu, WSL, Raspberry Pi, Bazzite, and Windows. The tools include Claude Code CLI and Codex CLI, Notion CLI (`ntn`), Gemini CLI, and Pi.

Setup removes the tintinweb Pi subagents extension when it is present. It also removes the legacy `pi-ask-user` package and the retired `@juicesharp/rpiv-ask-user-question` and `@juicesharp/rpiv-todo` packages when they are present. Setup installs the Pi MCP adapter, Pi Claude bridge, `pi-web-access`, `pi-prose`, and the Pi goal/autoresearch extensions.

All machines default Pi to GPT-6 Astra (`openai-codex/gpt-6-astra`) with `xhigh` thinking, including work machines. Setup removes the retired Synthetic provider from Pi's `models.json` and preserves other providers and local credentials. z.ai remains optional when a key exists. On a new machine, use `/login` in Pi to connect your ChatGPT subscription.

Each idempotent setup run requests unpinned `npm:pi-prose`, so Pi installs or updates the latest release. Setup creates `prose/config.json` with the `matter-of-fact` user default only when the file does not exist. Setup does not change an existing pi-prose user configuration. Pi still honors explicit session, command-line, and project style choices.

Setup installs the managed Matt Pocock engineering skills on personal and work machines. Pi and Codex share the canonical copies in `~/.agents/skills`. Work machines also install Google Cloud CLI.

Set `WORK_MACHINE=1` in `~/.env.local` for work machines. Set `BAN_PI_MCP_ADAPTER=1` to keep the Pi MCP adapter inactive. Set `BAN_PI_GOAL_AUTORESEARCH=1` to keep the Pi goal/autoresearch extensions inactive.

Set `BAN_MATT_POCOCK_SKILLS=1` to remove the managed Matt Pocock skills and keep them inactive. The older `BAN_MATT_POCKOCK_SKILLS=1` spelling also works.

Every setup run installs the latest [Simple English](https://github.com/AminBlg/SimpleEnglish) and [HumanLayer `show-me`](https://github.com/humanlayer/skills) skills globally for Claude Code, Codex, Gemini CLI, and Pi. The installations are non-interactive and use copied files for cross-platform compatibility. Codex, Gemini CLI, and Pi discover the canonical shared copies in `~/.agents/skills`. Claude Code uses harness-specific copies. `CLAUDE_CONFIG_DIR` selects a custom Claude Code location when it is set. `PI_CODING_AGENT_DIR` selects the Pi settings location and obsolete-copy exclusions. Simple English and `show-me` are required on personal and work machines and have no setup opt-out.

Claude Code is installed with Anthropic's native installer rather than npm/Bun. Setup installs or updates Claude Code on supported machines, with no opt-out. Setup ignores `BAN_CLAUDE_CODE`, including values in existing `.env.local` files. Those files remain unchanged. Run Claude Code's normal login/account flow before using Fable or the Pi Claude bridge. If setup warns that another `claude` command shadows the native binary, resolve PATH/package shadowing or use the native path shown in the warning before authenticating.

Codex CLI is installed per user with OpenAI's standalone installer on Ubuntu, WSL, Raspberry Pi, and Bazzite, from Homebrew's native `codex` cask on macOS, and from OpenAI's native GitHub release binary on Windows. The per-user Linux install keeps `codex` in `~/.local/bin`, so headless Paseo can use it without trusting another user's shared Homebrew prefix. Setup removes the older Bun package and smoke-tests the binary with Node stripped from PATH.

Setup removes legacy global Impeccable skill copies and Cursor subagent files that earlier versions installed. It leaves project-scoped Impeccable data and hooks untouched.

Notion CLI is installed with Notion's native installer on macOS and Linux and with WinGet on Windows. The native installer supports x64 and ARM64, while the Windows package supports x64 only; unsupported architectures warn and continue setup. Setup does not authenticate Notion CLI or configure shell completions. Run `ntn login` manually when you are ready to connect a workspace.

## Telegram alert credentials

New `~/.env.local` files include commented `TELEGRAM_ALERTS_BOT_TOKEN` and `TELEGRAM_ALERTS_CHAT_ID` entries.
Existing files remain unchanged. Add the two entries manually on existing machines.

The [dotfiles Telegram guide](https://github.com/scowalt/dotfiles/blob/main/dot_config/agent-docs/telegram-alerts.md) covers bot creation, chat discovery, and direct requests.
Chezmoi installs the guide at `~/.config/agent-docs/telegram-alerts.md` alongside global guidance for Claude Code, Codex, and Pi.
Agents send alerts directly through Telegram. Setup does not send alerts, distribute tokens, or install a notification helper.
Keep real values local and out of Git. Work-machine alerts require Scott's explicit permission.

Run `bash tests/telegram-alerts-contract.sh` for offline tests of the environment templates.

## Work-machine Gitea client

On work machines, `WORK_MACHINE=1` makes Tea (`tea`) a managed tool. Setup installs or updates the latest stable Tea release.

Homebrew supplies Tea on supported systems. Windows and unsupported Raspberry Pi architectures use an official Gitea binary and its published SHA-256 checksum. Homebrew supplies Bash, Zsh, and Fish completions. Setup does not install other completion files.

Setup does not authenticate Tea. It does not read, print, or synchronize Gitea tokens. Run `tea login add` once on each work machine.

Tea stores the application token in its local configuration. Do not add this configuration to synchronized dotfiles.

## Connectivity tools

Every machine setup script installs Portless CLI for Tailscale HTTPS tunnel helpers.

## Headless Paseo daemon

Set `HEADLESS=1` only when provisioning a machine that must remain remotely operable after logout or reboot. On native Linux setup scripts (`ubuntu.sh`, `pi.sh`, and `bazzite.sh`), this installs `@getpaseo/cli`, creates a managed `paseo.service` systemd user service with lingering enabled, starts it, and verifies local daemon health before setup succeeds. Ubuntu only configures unrestricted passwordless sudo when `HEADLESS_PASSWORDLESS_SUDO=1` is also set.

The service uses the IPv4 loopback address and port from `daemon.listen`. Each user on a multi-user machine must use a different port. If another process uses the configured port, setup stops before it starts the service.

`HEADLESS=1` is an exact-match provisioning trigger, not an off switch. Unset values, `HEADLESS=0`, and `HEADLESS=true` do not install or mutate Paseo service state. To disable a previously configured machine, manually stop/disable the managed service and use Paseo's normal unpairing/removal flow.

macOS `HEADLESS=1` skips the headless Paseo daemon with a warning unless `PASEO_MACOS_HEADLESS_CANARY=1` is also set for an approved no-login canary run; the rest of setup continues. WSL and native Windows fail early with a clear unsupported message because they cannot yet guarantee a true no-login Paseo daemon after host reboot.

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
