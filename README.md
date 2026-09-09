# Machine setup scripts

Idempotent scripts I use to set up my machines.

## Setup logs

Every setup run writes a local log under `~/.local/log/machine-setup` and makes one best-effort upload to `logs.scowalt.com` after either success or a detected fatal error. If the upload fails, the setup result is preserved and the script prints the local log path for manual recovery.

## AI Coding Agents

Every setup script installs or updates the main AI development tools. The supported systems are macOS, Ubuntu, WSL, Raspberry Pi, Bazzite, and Windows. The tools include Claude Code CLI and Codex CLI, Notion CLI (`ntn`), Gemini CLI, and Pi.

Setup removes the tintinweb Pi subagents extension when it is present. It also removes the legacy `pi-ask-user` package and the retired `@juicesharp/rpiv-ask-user-question` and `@juicesharp/rpiv-todo` packages when they are present. Setup installs the Pi MCP adapter, Pi Claude bridge, `pi-web-access`, and the Pi goal/autoresearch extensions.

All machines default Pi to GPT-6 Astra (`openai-codex/gpt-6-astra`) with `xhigh` thinking, including work machines. Setup removes the retired Synthetic provider from Pi's `models.json` and preserves other providers and local credentials. z.ai remains optional when a key exists. On a new machine, use `/login` in Pi to connect your ChatGPT subscription.

Setup does not reinstall `pi-prose` or create `prose/config.json`. Existing custom prose files remain unchanged. The dotfiles repository no longer manages this package or its initial default. Setup does not uninstall a user-selected copy.

Setup installs the managed Matt Pocock engineering skills on personal and work machines. Pi and Codex share the canonical copies in `~/.agents/skills`. Work machines also install Google Cloud CLI.

Set `WORK_MACHINE=1` in `~/.env.local` for work machines. Set `BAN_PI_MCP_ADAPTER=1` to keep the Pi MCP adapter inactive. Set `BAN_PI_GOAL_AUTORESEARCH=1` to keep the Pi goal/autoresearch extensions inactive.

Set `BAN_MATT_POCOCK_SKILLS=1` to remove the managed Matt Pocock skills and keep them inactive. The older `BAN_MATT_POCKOCK_SKILLS=1` spelling also works.

Every setup run installs the latest [Simple English](https://github.com/AminBlg/SimpleEnglish), [HumanLayer `show-me`](https://github.com/humanlayer/skills), and [PR Lens](https://github.com/coldteadotai/pr-lens) skills. The skills are available globally to Claude Code, Codex, Gemini CLI, and Pi. The installations are non-interactive and use copied files for cross-platform compatibility. Simple English, `show-me`, and PR Lens are required on personal and work machines and have no setup opt-out.

Codex, Gemini CLI, and Pi discover the canonical shared copies in `~/.agents/skills`. Claude Code uses harness-specific copies. If `CLAUDE_CONFIG_DIR` is set, it selects a custom Claude Code location. `PI_CODING_AGENT_DIR` selects the Pi settings location and obsolete-copy exclusions.

Claude Code is installed with Anthropic's native installer rather than npm/Bun. Setup installs or updates Claude Code on supported machines, with no opt-out. Setup ignores `BAN_CLAUDE_CODE`, including values in existing `.env.local` files. Those files remain unchanged. Run Claude Code's normal login/account flow before using Fable or the Pi Claude bridge. If setup warns that another `claude` command shadows the native binary, resolve PATH/package shadowing or use the native path shown in the warning before authenticating.

Codex CLI is installed per user with OpenAI's standalone installer on Ubuntu, WSL, Raspberry Pi, and Bazzite, from Homebrew's native `codex` cask on macOS, and from OpenAI's native GitHub release binary on Windows. The per-user Linux install keeps `codex` in `~/.local/bin`, so headless Paseo can use it without trusting another user's shared Homebrew prefix. Setup removes the older Bun package and smoke-tests the binary with Node stripped from PATH.

Setup removes legacy global Impeccable skill copies and Cursor subagent files that earlier versions installed. It leaves project-scoped Impeccable data and hooks untouched.

Notion CLI is installed with Notion's native installer on macOS and Linux and with WinGet on Windows. The native installer supports x64 and ARM64, while the Windows package supports x64 only; unsupported architectures warn and continue setup. Setup does not authenticate Notion CLI or configure shell completions. Run `ntn login` manually when you are ready to connect a workspace.

## PR Lens skill

PR Lens draws code changes or system structure as architecture and data-flow diagrams. Each machine receives the latest upstream `pr-lens` skill from `coldteadotai/pr-lens` on its next setup run. This rollout does not remotely install anything on existing machines.

Setup keeps upstream skill contents unchanged. Default hosted uploads remain enabled, including on work machines, with no added approval gate or local-only policy. The upstream standalone workflow uses `canvas push` to upload the whole graph JSON. Anyone with the hosted view link can read the diagram without a login. CLI 0.4.0 also prints a secret edit link. Keep that edit link out of shared logs and commits.

Setup installs the skill only, not the PR Lens GitHub App or a global PR Lens CLI. It does not require diagrams on every PR, add hooks or provider credentials, or change dotfiles policies or shell profiles. Setup and its offline tests do not render diagrams, upload graphs, or post PR content. Setup requires five nonempty regular files in both managed copies: `SKILL.md`, `LICENSE`, `references/graph-document.md`, `references/config.md`, and `references/example.graph.json`. Missing or empty files and linked files or directories fail validation, including linked `references` directories. Pi ownership removes identical obsolete direct copies and excludes user-modified copies without deleting them.

Runtime limits are separate from skill installation:

- The skill invokes `npx @coldtea/pr-lens-cli@latest` on demand. CLI 0.4.0 needs Node.js >=20.11. The setup skill installer already requires Node.js >=22.20 and can provision Node.js 24 through mise.
- Agent-authored graphs need no extra provider key. The optional `analyze` command needs a provider key.
- The `render` command produces local output but can update the project `.gitignore`. Setup does not run it.
- PR attachment with `gh --attach` needs GitHub CLI >=2.99, write-level permissions, and a suitable token and host. Some setup platforms use older distro versions. This rollout does not upgrade `gh`.
- Native Windows and Linux ARM64 viability comes from source inspection, not runtime smoke tests. ARM32 runtime readiness remains unverified. Skill installation does not guarantee every native runtime workflow works.

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

## Paseo release channels

Setup defaults to the Paseo beta channel on personal and work machines. `PASEO_CHANNEL=beta` selects `@getpaseo/cli@beta` for managed daemons and Beta for Desktop updates. `PASEO_CHANNEL=stable` selects `@getpaseo/cli@latest` and Stable for Desktop updates. Other values stop Paseo setup before it changes packages or client files.

Set `PASEO_CHANNEL` in the process environment or `~/.env.local`. A nonempty process value takes priority. Setup adds only a commented example to new environment files and preserves existing files.

Each machine adopts the channel on its next setup run. These changes do not update remote machines automatically. Managed daemons retain the headless limits below and restart when their package or managed service changes. Non-headless runs do not install a standalone daemon.

For Desktop clients, setup selects the update channel on macOS, native Linux, and Windows. It does not install or replace the Desktop app, launch a client, or start a bundled daemon. If Desktop is not installed, get it from the [Paseo download page](https://paseo.sh/download?channel=beta).

Close Desktop before setup changes its channel. Setup refuses to edit settings cached by a running app, because the app can overwrite external changes. After setup, open Desktop and select **Settings → About → Check** to download the selected update. Let Desktop complete the update to upgrade its bundled daemon too. If Desktop already uses the selected channel, setup leaves the file unchanged, even while the app runs.

Setup changes `settings.releaseChannel` and marks the legacy renderer import complete in `desktop-settings.json`. This prevents an older channel preference from replacing the selected channel. Setup preserves other settings and migration flags. It rejects malformed files, unknown document versions, linked paths, and paths that are not regular files or directories.

Desktop uses these user-data paths, separate from the standalone daemon's `PASEO_HOME`:

- macOS: `~/Library/Application Support/Paseo/desktop-settings.json`.
- Linux: `${XDG_CONFIG_HOME:-~/.config}/Paseo/desktop-settings.json`.
- Windows: `%APPDATA%\Paseo\desktop-settings.json`.

Setup honors `PASEO_ELECTRON_USER_DATA_DIR` when it contains an absolute path. Non-headless runs seed an absent Desktop profile on supported platforms. Headless runs change only existing Desktop profiles. WSL does not modify Windows client files. Run `win.ps1` on the Windows host and set its channel there.

The v0.8 beta has Desktop builds for macOS and Windows on x64 and ARM64, and Linux on x64. Linux ARM machines, including Raspberry Pi, can use the daemon with a supported remote client or browser. Setup does not seed an absent Linux ARM Desktop profile. It can change an existing profile for a custom Desktop build. The daemon-served web client follows the daemon package. The hosted web app has no setting managed by these scripts.

For Android betas, install the APK manually from [GitHub releases](https://github.com/getpaseo/paseo/releases). iOS and the mobile app stores have no beta channel. These scripts do not manage mobile installations.

To return to stable, set `PASEO_CHANNEL=stable` and rerun setup with Desktop closed. Managed daemons install the current npm `latest` version, which can be older than the beta. Desktop waits for a newer stable release and does not automatically downgrade. Back up Paseo data before downgrading a daemon. Changing the channel does not undo data migrations.

See [Paseo update instructions](https://paseo.sh/docs/updates.md). The client document format matches [the v0.8 beta Desktop settings store](https://github.com/getpaseo/paseo/blob/4eab53e24e1b57c74b00945aa48a89d68ed755e3/packages/desktop/src/settings/desktop-settings.ts). Tests use temporary fixtures and do not install, update, or start Paseo. Run `bash tests/paseo-release-channel-contract.sh` and `pwsh -NoProfile -File tests/paseo-release-channel-powershell.ps1` for channel coverage.

## Paseo Plain plugin

Future setup runs install [Paseo Plain](https://github.com/scowalt/paseo-plain) for the local daemon when Paseo CLI/daemon 0.8.x, Node.js >=22.19, Pi, and enabled Paseo plugins are available. The six standalone setup scripts share the same installer logic. Setup does not inventory or contact other machines.

Setup installs `main` through Paseo's Git installer. Later runs update matching Git-managed `paseo-plain` installations to the latest `main` commit. No GitHub release or version tag is required. Directory installations, other repositories or branches, pinned revisions, and disabled installations remain unchanged. Ordinary failed updates do not trigger a remove/reinstall cycle.

Existing setup-managed `release` installations move to `main` on their next setup run. Paseo 0.8 requires a one-time remove/add operation under the same plugin ID. Setup verifies the source record and makes private recovery copies before removal. It preserves live rewrite preferences and cache, and restores Paseo-owned settings before adding `main`. Only the plugin is briefly interrupted. The migration does not restart the daemon. Do not change the plugin or its settings during migration. Paseo 0.8 does not make the entire migration atomic.

New installations initialize manual rewrite controls once. Existing voice, model, display, timeout, disabled choices, configuration files, and cached rewrites remain unchanged. Setup does not copy credentials or make a model request. The plugin uses the daemon user's existing Pi login when the user explicitly requests a rewrite.

If prerequisites are missing, setup reports that installation is deferred. Start a compatible local daemon and enable trusted plugins in **Paseo Settings > Plugins**, then rerun setup. Plugins run without isolation and can access the daemon's files, processes, credentials, and network. The plugin installer does not enable the global switch or start another daemon. It follows the separate `PASEO_CHANNEL` policy above. If you select stable and that release lacks the required plugin API, plugin installation remains deferred.

The installer uses `PASEO_HOME`, or `~/.paseo` when the variable is unset or empty, and requires a loopback TCP daemon endpoint. Existing headless support restrictions still apply. Plugin CI uses fake workers; actual model access, client appearance, and ARM/WSL runtime behavior need separate verification. The plugin restricts Windows storage through NTFS permissions and keeps rewriting off if private storage cannot be prepared.

Run `python3 tests/test_paseo_plain_setup.py` for isolated installer regressions. Tests extract only installer functions and use temporary homes and fake CLIs. They do not source full provisioning entry points. The POSIX fixture also tests the PowerShell wrapper when `PWSH_BIN` points to PowerShell. Pre-push hooks run these tests through `tests/paseo-plain-setup-contract.sh`.

The native source-manager test requires an installed Paseo 0.8 server module:

```bash
PASEO_TEST_PLUGIN_SERVICE_MODULE=/absolute/path/to/server/plugins/index.js \
  node tests/paseo-plain-native-migration.mjs
```

This test uses the actual source and configuration managers with temporary homes and local Git repositories. Plugin execution and CLI transport are simulated. No listener, authenticated session, or model is used. It verifies migration, reruns, native deletion behavior, and failed builds. Git configuration and inherited hook variables are isolated. The pre-push wrapper also tests that poisoned Git variables cannot change a caller repository, its index, or its configuration. Native Windows provisioning and successful Windows backup permissions still need separate verification.

### Paseo Plain migration recovery

Recovery files remain private under `<PASEO_HOME>/setup-recovery/paseo-plain-release-to-main`, including after success. `state.json` records progress. `RECOVERY.md` explains recovery. The directory contains the old checkout, plugin-specific registration and source records, rewrite preferences/cache, and any Paseo-owned settings. Backup copies of cached rewrites do not expire automatically. After a verified `main` migration, you can delete the backup if no installed source uses it.

A failure, timeout, or incomplete journal stops further automatic changes. Setup does not assume that a failed CLI request stopped work in the daemon. It does not remove a potentially completed new installation or overwrite newer settings to retry. Do not repeatedly rerun setup while a migration needs review.

1. Make sure that any pending Paseo operation finishes before recovery. Inspect the same local daemon with an explicit `--host` and `paseo plugin ls --json`.
2. If `main` is already running, compare the preserved settings and cache before changing anything. Do not remove that installation merely because the CLI timed out.
3. If the plugin is absent and the backup contains `plugin-settings`, restore it only to an absent `<PASEO_HOME>/plugin-settings/paseo-plain` directory. Do this before activation and preserve private permissions. Do not overwrite a destination that reappeared or newer live rewrite preferences/cache.
4. If the plugin is absent, the backup `checkout` directory can restore the old code with `paseo plugin install`. Use `--id paseo-plain` and the same explicit `--host`. This creates a directory installation, not an automatically updated Git installation.
5. Never restore the plugin records over the complete daemon `config.json` or `plugins/sources.json`. Those files also contain unrelated state.
6. If a recovered directory is the installed source, keep it at that path. Moving the recovery directory would break that installation.
7. If the installed path is outside the recovery directory, verify its source and settings and confirm that no operation remains pending. Then archive the recovery directory before retrying setup. Keep the old `release` branch and tags until they are no longer needed for recovery.

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
