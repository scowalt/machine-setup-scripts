# Machine setup scripts

Idempotent scripts I use to set up my machines.

## AI Coding Agents

The personal-machine setup scripts install/update Gemini CLI, Codex CLI, Pi, RTK, tintinweb Pi subagents, Pi goal/autoresearch extensions, Matt Pocock Pi skills, and Compound Engineering resources for supported agents. Work machines also install RTK and Google Cloud CLI. Set `WORK_MACHINE=1` in `~/.env.local` for work machines. Set `BAN_RTK=1` to skip RTK setup. Set `BAN_COMPOUND_PLUGIN=1` to skip Compound Engineering setup. Set `BAN_PI_SUBAGENTS=1` to keep the tintinweb Pi subagents extension inactive. Set `BAN_PI_GOAL_AUTORESEARCH=1` to keep the Pi goal/autoresearch extensions inactive. Set `BAN_MATT_POCOCK_SKILLS=1` to keep Matt Pocock Pi skills inactive.

## Headless Paseo daemon

Set `HEADLESS=1` only when provisioning a machine that must remain remotely operable after logout or reboot. On native Linux setup scripts (`ubuntu.sh`, `omarchy.sh`, `pi.sh`, and `bazzite.sh`), this installs `@getpaseo/cli`, creates a managed `paseo.service` systemd user service with lingering enabled, starts it, and verifies local daemon health before setup succeeds.

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

## Arch Linux / Omarchy

```bash
curl -sL https://scripts.scowalt.com/setup/omarchy.sh | bash
```

## Bazzite

```bash
curl -sL https://scripts.scowalt.com/setup/bazzite.sh | bash
```
