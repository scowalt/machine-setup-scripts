# Machine setup scripts

Idempotent scripts I use to set up my machines.

## Setup logs

Setup writes a local log under `~/.local/log/machine-setup` and uploads it to `logs.scowalt.com` after success or a detected fatal error. Bash scripts make one best-effort upload attempt. If an upload fails, setup preserves its result and prints the local log path.

The Windows uploader supports Windows PowerShell 5.1 and PowerShell 7 without an extra installed tool. It closes the transcript, the file that records console output, before uploading. Each run uses a unique log filename. Temporary network failures and HTTP 408, 429, or 5xx responses receive up to three attempts, with 2-second and 4-second delays. Requests use a timeout of at most 30 seconds within a 96-second upload budget. Other HTTP errors, certificate failures, and local file errors do not trigger immediate retries.

Windows stores upload status in a neighboring `<log filename>.upload.json` file. This file records the failure category or HTTP status, attempt count, and original hostname, but not raw server responses or credentials. The console also shows the failure category and PowerShell version. If an upload fails, read this status file and keep the local log for diagnosis.

At the start of a later Windows setup run, setup retries up to three pending logs within a shared 60-second budget. Only logs marked by this uploader qualify. Setup leaves unmarked historical logs, malformed status files, linked paths, and files in use untouched. Successful uploads change the status to `uploaded`, so later runs skip them. Setup keeps both the log and its status file. If the server accepts an upload but its response is lost, a retry can create a duplicate collector entry.

A forced process exit, power loss, or reboot can prevent transcript closure and upload. Setup does not automatically upload an active transcript or a partial file from a failed transcript start. If transcript closure fails, use the printed local log path for manual recovery. These protections do not guarantee delivery when the network or collector remains unavailable.

Run `bash tests/windows-log-upload-contract.sh` for the uploader contracts. Set `PWSH_BIN` to include the isolated PowerShell fixtures. On Windows, run `powershell.exe -NoProfile -File tests/windows-log-upload-powershell.ps1` and `pwsh -NoProfile -File tests/windows-log-upload-powershell.ps1` to test both hosts. Tests use temporary homes and an in-memory HTTP handler. They do not run setup or send logs to the collector. Linux PowerShell tests do not prove native Windows PowerShell 5.1 behavior.

## AI Coding Agents

Every setup script installs or updates the main AI development tools. The supported systems are macOS, Ubuntu, WSL, Raspberry Pi, Bazzite, and Windows. The tools include Claude Code CLI and Codex CLI, Notion CLI (`ntn`), Gemini CLI, and Pi.

Setup removes the tintinweb Pi subagents extension when it is present. It also removes the legacy `pi-ask-user` package and the retired `@juicesharp/rpiv-ask-user-question` and `@juicesharp/rpiv-todo` packages when they are present. Setup installs the Pi MCP adapter, Pi Claude bridge, `pi-web-access`, and the Pi goal/autoresearch extensions.

All machines default Pi to GPT-6 Astra (`openai-codex/gpt-6-astra`) with `xhigh` thinking, including work machines. Setup removes the retired Synthetic provider from Pi's `models.json` and preserves other providers and local credentials. z.ai remains optional when a key exists. On a new machine, use `/login` in Pi to connect your ChatGPT subscription.

Before Pi profile changes, setup secures `~/.pi`, `~/.pi/agent`, and the profile selected by `PI_CODING_AGENT_DIR`. Unix directories use owner-only permissions (`0700`). Windows directories use private native access controls. Setup first checks both profiles and their ancestors. It changes only account-owned, real profile directories inside HOME and safely creates missing profile directories. It does not change HOME, unrelated ancestors, profile contents, or credential permissions. Linked paths, foreign ownership, unsafe ancestors, and outside-HOME profiles block later Pi mutations and dependent daemon setup. The trusted Linux `/home` system alias remains supported. Creating a missing Unix profile requires `/usr/bin/python3` with descriptor-relative directory operations. If this support is absent, setup fails safely without path-based creation.

Setup removes the retired `pi-prose` package on each machine's next run, including previously user-selected copies. It cleans the default global Pi profile and the profile selected by `PI_CODING_AGENT_DIR`. Cleanup removes the Pi package declarations, direct npm dependency declarations, matching lockfile records, and installed package directory. It does not change project-local packages, unrelated packages, credentials, or existing custom prose files, including empty or malformed `prose/config.json` files.

Cleanup runs after dotfiles application and before Pi package operations. It does not run npm or Pi, resolve dependencies, or change npm security policy. A linked package is unlinked without deleting its source. Linked profile directories, package stores, JSON metadata, and unverified package contents require manual review. Cleanup validates both profiles before writing, but individual file replacements are not one transaction. A failed write or removal stops Pi package operations. Unrelated work continues, logs finish, and setup returns a failure.

Dotfiles no longer declare this package or seed its initial configuration. The [matching dotfiles change](https://github.com/scowalt/dotfiles/pull/19) prevents later chezmoi applies from restoring the declaration. Already-running Pi sessions need a restart to unload the extension. Separate adapter recovery handles the npm 12 restriction described below. Setup does not contact other machines.

Setup installs the full [Matt Pocock skill suite](https://github.com/mattpocock/skills) on personal and work machines. Claude Code, Codex, Gemini CLI, and Pi receive the same suite. Codex, Gemini CLI, and Pi share the copies in `~/.agents/skills`. Claude Code uses its own copied files. Work machines also install Google Cloud CLI.

Set `WORK_MACHINE=1` in `~/.env.local` for work machines. Set `BAN_PI_MCP_ADAPTER=1` to keep the Pi MCP adapter inactive. Set `BAN_PI_GOAL_AUTORESEARCH=1` to keep the Pi goal/autoresearch extensions inactive.

Set `BAN_MATT_POCOCK_SKILLS=1` to remove the managed Matt Pocock skills and keep them inactive. The older `BAN_MATT_POCKOCK_SKILLS=1` spelling also works.

Setup removes the retired PR Lens, Simple English, and HumanLayer `show-me` skills on each machine's next setup run. Removal applies to personal and work machines and has no opt-out. The full Matt Pocock suite remains the managed skill suite.

Codex, Gemini CLI, and Pi discover the canonical shared copies in `~/.agents/skills`. Claude Code uses harness-specific copies. If `CLAUDE_CONFIG_DIR` is set, it selects a custom Claude Code location. `PI_CODING_AGENT_DIR` selects the Pi settings location and obsolete-copy exclusions.

Claude Code is installed with Anthropic's native installer rather than npm/Bun. Setup installs or updates Claude Code on supported machines, with no opt-out. Setup ignores `BAN_CLAUDE_CODE`, including values in existing `.env.local` files. Those files remain unchanged. Run Claude Code's normal login/account flow before using Fable or the Pi Claude bridge. If setup warns that another `claude` command shadows the native binary, resolve PATH/package shadowing or use the native path shown in the warning before authenticating.

Codex CLI is installed per user with OpenAI's standalone installer on Ubuntu, WSL, Raspberry Pi, and Bazzite, from Homebrew's native `codex` cask on macOS, and from OpenAI's native GitHub release binary on Windows. The per-user Linux install keeps `codex` in `~/.local/bin`, so headless Paseo can use it without trusting another user's shared Homebrew prefix. Setup removes the older Bun package and smoke-tests the binary with Node stripped from PATH.

On Linux, setup gives the Codex installer a temporary `HOME`. Explicit `CODEX_INSTALL_DIR` and `CODEX_HOME` values keep the binary and data in the account. Existing `CODEX_HOME` choices remain in use. Installer profile changes stay in the temporary home, which setup removes afterward. Chezmoi alone manages the real shell profiles. Run `bash tests/codex-profile-isolation-contract.sh` for isolated regression tests.

Setup removes legacy global Impeccable skill copies and Cursor subagent files that earlier versions installed. It leaves project-scoped Impeccable data and hooks untouched.

Notion CLI is installed with Notion's native installer on macOS and Linux and with WinGet on Windows. The native installer supports x64 and ARM64, while the Windows package supports x64 only; unsupported architectures warn and continue setup. Setup does not authenticate Notion CLI or configure shell completions. Run `ntn login` manually when you are ready to connect a workspace.

## OpenCode Go and the Muse Contributor profile

All six scripts add OpenCode Go access for Pi on personal and work machines. Setup uses Pi's built-in Go provider, not the retired OpenCode CLI. GPT-6 Astra remains the default.

Add your existing Go subscription key to `~/.env.local` on each machine:

```dotenv
OPENCODE_GO_API_KEY=your-go-api-key
```

Use a plain, single-line API-key value, not a shell command or variable reference. New environment files contain a commented example. Existing files remain unchanged, so add the entry yourself before rerunning setup. Keep the file private to your account. On Unix, use `chmod 600 ~/.env.local` before setup. Do not put real keys in Git, commands, or shared logs.

Setup reads this dedicated entry and copies a nonempty key into the `opencode-go` entry in Pi's private `auth.json`. This local copy lets headless Paseo authenticate without loading the whole environment file. `PI_CODING_AGENT_DIR` selects the active Pi directory, or setup uses `~/.pi/agent`. Paseo must launch Pi with the same directory. No other global or project Pi profile receives the key.

A changed key replaces the stored Go credential on the next setup run. A missing or empty entry preserves the stored credential. Go credential setup preserves other credentials and does not add a Zen credential or change `models.json`. Pi itself recognizes the shared `OPENCODE_API_KEY` variable for both Zen and Go, but this setup uses `OPENCODE_GO_API_KEY` only. Do not rename it to the shared variable.

Setup adds a Paseo profile named `Muse 1.3 Contributor`. It selects Pi, model `opencode-go/muse-spark-1.3-contributor`, and native `xhigh` reasoning. The profile is a selectable alternative, not a new default. It lives in `<PASEO_HOME>/config.json` under `daemon.agentProfiles`, or in `~/.paseo/config.json` when no override exists. This is separate from Electron's `desktop-settings.json` and from Pi's global profile directory.

A custom `PASEO_HOME` must be an existing, private, account-owned directory below HOME, without linked paths. Use an absolute path without `..` segments. Empty, relative, outside-HOME, and HOME-itself overrides defer synchronization. A running managed daemon and its service manager must select the same home. After custom-home synchronization, setup skips the later managed-daemon installer because that installer assumes the default home. Keep the custom owner's launch environment and update that owner separately.

Later runs recreate a deleted managed profile and restore its provider, model, and reasoning level. Other profiles and optional customizations remain unchanged. Setup can add the profile before you supply a key, with a warning that authentication is missing. If Pi installation or Go validation fails, subsequent Pi package operations, profile setup, and managed-daemon setup are deferred.

### Go setup failure diagnostics

Go failures report the operation and a safe reason, for example `Pi Go setup failed: environment-file: unsafe-file-permissions.` This identifies the failed check without printing keys, file contents, custom paths, or arbitrary exception text. Unknown exceptions report `operation-failed` with the operation name, not an assumed cause.

| Operation or reason | What to review locally |
| --- | --- |
| `home` or `active-profile` | Account ownership, directory permissions, and linked ancestors. |
| `environment-file` | The account's `~/.env.local`, its permissions, and the literal `OPENCODE_GO_API_KEY` format. |
| `models-json` | The active Pi profile's `models.json`. Keep explicit provider overrides until you review them. |
| `auth-preflight` or `auth-read` | The active profile's `auth.json`, its permissions, and its JSON structure. Do not print credential contents. |
| `pi-package`, `pi-dependency`, or `go-catalog` | Installed Pi package metadata and the built-in Go Muse Contributor model. |
| `auth-lock`, `lock-dependency`, `lock-acquire`, or `lock-release` | Pi's credential lock and installed lock dependency. Do not delete a lock held by a running process. |
| `auth-write` or `auth-cleanup` | Private credential storage. For example, `ENOSPC` reports a space failure and `EACCES` reports denied access. |

For permission failures, inspect the named boundary before changing anything. Do not make credentials public or bypass linked-path protections to continue setup. If the helper exits without a recognized diagnostic, setup reports `helper-exit-N: diagnostic-unavailable`, where `N` is its exit status. `helper-execution: diagnostic-unavailable` means PowerShell did not complete the helper invocation. `invalid-helper-result` means a successful helper exit produced an unrecognized result. These fallback messages do not establish the underlying cause.

### Subscription and data policy

The [Go Contributor offering](https://opencode.ai/docs/go/#privacy) permits Meta to retain prompts and responses and use them for model training. It has geographic restrictions and requires account-level training consent. This profile is available on work machines too, so follow your employer's data policy when selecting it.

Maintain an active Go subscription and keep **Use balance** disabled in the OpenCode console. With that option enabled, the Go service can spend Zen balance after subscription limits are reached. Selecting the Go provider alone does not guarantee subscription-only billing. Setup does not purchase subscriptions, enable consent, change billing settings, test account entitlement, or fall back to the paid Zen model.

### Daemon updates and recovery

Run setup from a terminal outside the Paseo daemon that it must restart. Restarts interrupt active agent turns, tools, and Paseo terminals. Saved sessions can be resumed, but a restart does not preserve uninterrupted work. Do not edit Paseo configuration during setup. Setup reserves `paseo.pid` to block daemon startup, but external editors can ignore this protection.

When a profile change needs a stopped daemon, setup can stop and start its identified, setup-managed local service. A changed Go credential also needs a refresh of Paseo's cached model list. Setup keeps unchanged runs nondisruptive and attempts to restore the service even if the profile write fails. Native Linux headless support and the macOS canary gate remain unchanged. Windows and WSL do not gain managed headless daemons, and WSL does not change Windows-host profiles.

If setup cannot safely control the owning daemon, it leaves the profile unchanged and reports a deferred update. This includes a running Desktop-managed daemon, uncertain ownership or home selection, service drop-ins or environment files (including Chezmoi's GitHub-token drop-in), and setup running inside the daemon. Pause and stop the local daemon through its owner, close Desktop if applicable, and rerun setup from an outside terminal. Do not start a second daemon to bypass the warning.

On native Linux with `HEADLESS=1` and the default Paseo home, setup can repair the known group-write permission problem. It first verifies the running setup-managed service, its process, and its exact wrapper and service definition. It can then remove group-write permission from `~/.paseo/paseo.pid` and the three directories `~/.config`, `~/.config/systemd`, and `~/.config/systemd/user`. PID repair requires an already private `~/.paseo`. All candidates are checked before any repair, and each change uses a verified open file handle. Setup does not recurse, change owners, alter file contents, or change HOME. World-writable paths, linked paths, foreign owners, stopped or unverified services, and custom homes need manual review.

Managed daemon wrappers set `umask 077`, which makes newly created PID files private even when the account uses `umask 002`. After a Muse restart through an older wrapper, setup waits briefly for the complete native PID, verifies its owner again, and secures that new PID before the later daemon update. A timeout fails setup instead of claiming a verified restore. The later update installs the restrictive wrapper through the existing service lifecycle. The read-only ownership check never repairs permissions. If a permission failure remains, inspect the reported boundaries; merely stopping Paseo may not fix it. Do not use recursive `chmod` or `chown` as recovery.

Malformed configuration and linked managed paths require manual review rather than replacement. An explicit `opencode-go` provider override in the active Pi `models.json` also blocks this addition instead of silently changing its endpoint or reasoning policy. Review that override yourself before rerunning setup. Keep existing custom home overrides aligned with the actual daemon and Pi launch configuration. Setup does not change remote hosts or shell profiles.

Run `bash tests/pi-opencode-go-contract.sh`, `bash tests/paseo-muse-profile-contract.sh`, and `bash tests/opencode-go-wiring-contract.sh` for offline fixtures. Set `PWSH_BIN` to include PowerShell wrapper coverage. Tests use temporary homes and mocked daemon controls, not live setup or model requests. These tests do not prove account acceptance or native Windows, macOS, or ARM behavior. For an additional offline native-lock and catalog check, set `PI_GO_LOCK_MODULE` to the installed Pi dependency's `proper-lockfile/index.js`. Set `PASEO_MUSE_PID_LOCK_MODULE` to Paseo 0.8.0's `dist/src/server/pid-lock.js` to test native daemon-start exclusion and PID creation under both permissive and restrictive umasks. These probes use only temporary fixtures and do not start a daemon.

## Pi package maintenance

Setup pins `pi-mcp-adapter` to `2.32.1`. Version `2.33.0` depends on preview packages from `pkg.pr.new`, which the managed npm policy rejects with `EALLOWREMOTE`. The compatible version uses registry dependencies. Setup does not relax npm security restrictions.

Before other Pi package operations, setup repairs the adapter declarations in the active global profile. `PI_CODING_AGENT_DIR` selects that profile, or setup uses `~/.pi/agent`. Setup changes only matching adapter sources and direct dependency entries in `npm/package.json`. It preserves source filters, unrelated packages, credentials, other profiles, and project data. npm updates its own lockfiles during installation.

Dotfiles also declare `npm:pi-mcp-adapter@2.32.1`, enabled by default on personal and work machines. Later chezmoi applies retain the registration. The dotfiles template omits the adapter if the environment or `~/.env.local` sets `BAN_PI_MCP_ADAPTER=1`.

Setup checks the installed version, exact dependency, package registration, declared extension, and nonempty regular `index.ts` file. It accepts default resource loading and explicit entry-point selections. Disabled, duplicate, or unverified filtered declarations return failure without a success message. Setup preserves filters rather than silently enabling a user-disabled extension. It does not guess complex glob behavior. If a filter needs review, use `pi config` in the active global profile to explicitly enable `index.ts`. An exact `+index.ts` selection can retain other filters. Project overrides remain unchanged.

After setup, restart Pi or run `/reload` to load the adapter into an existing session. `/mcp` shows the available servers. Setup does not start MCP servers, authenticate them, or prove their connectivity. The isolated test described below loads the real package without network or model calls.

With `BAN_PI_MCP_ADAPTER=1`, setup removes matching adapter declarations instead of installing the package. Malformed files, linked metadata, and linked managed directories stop Pi package operations for manual review. Setup records required package failures, continues unrelated work, and finishes logs with a failed result. Old registrations do not turn failed updates into success.

Run `bash tests/pi-package-maintenance-contract.sh` for temporary-home fixtures. Set `PWSH_BIN` for PowerShell coverage. The optional registry probe needs JavaScript entry points for npm 12+ and Pi:

```bash
PI_PACKAGE_NPM_CLI=/absolute/path/to/npm/bin/npm-cli.js \
PI_PACKAGE_CLI=/absolute/path/to/pi/dist/cli.js \
  bash tests/pi-package-maintenance-contract.sh
```

This probe downloads public packages only into a temporary home. It disables lifecycle scripts and prohibits remote dependency URLs. It tests clean installation, affected-store recovery, repeated runs, and adapter removal. It also uses Pi's SDK to load `2.32.1` and assert registration of `mcp`, `mcpScript`, and `/mcp`. Disabled resources must stay unloaded. The load fixture blocks network calls and uses no model credentials. Linux PowerShell fixtures do not prove native Windows provisioning.

Set `PI_ADAPTER_DOTFILES_SOURCE=/absolute/path/to/dotfiles` when running the contract suite to test repeated template rendering followed by setup. This fixture also tests that later dotfiles updates retain the Claude Bridge registration from setup. It covers personal and work machines, including the MCP adapter opt-out. The fixture uses temporary homes and mocked Pi commands. It never applies live dotfiles, loads extensions, or makes model requests.

All six setup scripts already run `pi install npm:pi-claude-bridge`. The dotfiles Pi package list must also include `npm:pi-claude-bridge`, or a later chezmoi apply can remove its registration. Installed files alone do not enable the `claude-bridge` provider. If Pi reports `Unknown provider "claude-bridge"`, run `pi install npm:pi-claude-bridge`, then restart Pi or run `/reload`.

### AskClaude is disabled; Claude Bridge remains available

`AskClaude` is the bridge's delegation tool, not a separate package. Every setup run sets `askClaude.enabled=false` in `claude-bridge.json` in both the default global Pi profile (`~/.pi/agent`) and the profile selected by `PI_CODING_AGENT_DIR`. This applies to personal and work machines. Setup keeps installing/registering `pi-claude-bridge`, so Claude/Fable model access, Claude Code itself, authentication, provider options, and other configuration remain available. Only the delegation tool is disabled, including when it has a customized tool name.

The helper runs after dotfiles and Pi profile permission preparation, before Pi package operations. It preflights both profiles and merges only that setting. Linked paths, hardlinked/non-regular files, oversized files, or malformed JSON are rejected rather than overwritten. Failure blocks subsequent Pi package/profile operations, continues unrelated work, and records a failed setup result. Fix the unsafe path or invalid configuration and rerun setup; do not delete credentials or uninstall the bridge.

Dotfiles manage the same setting in the default global profile through a preserving template, so subsequent chezmoi applies retain provider/custom options and keep AskClaude disabled. Setup handles the explicitly selected custom profile. The rollout takes effect on each machine's next setup run; restart Pi or run `/reload` afterward to remove the tool from an existing session. No fleet-wide live cleanup is required.

This is a managed **global setting**, not a security boundary: project-local `.pi/claude-bridge.json` can override it. Setup and dotfiles do not modify project configuration or arbitrary unselected profiles.

Run `bash tests/pi-askclaude-contract.sh`. Set `PWSH_BIN` for extracted PowerShell wrapper fixtures and `PI_ADAPTER_DOTFILES_SOURCE=/absolute/path/to/dotfiles` for repeated dotfiles/setup coverage. Tests use temporary homes without loading live extensions or making model requests. Linux-hosted PowerShell coverage does not replace native Windows ACL verification.

## Shared Node runtime for Pi

Pi uses the same mise-managed Node as your shell and project tools. Current Pi needs Node >=22.19 and `fs.globSync`. The managed skills CLI needs >=22.20, so setup selects a shared runtime that satisfies both.

Setup preserves a compatible global mise selection. If that selection is missing or too old, setup selects Node 24 on supported platforms or prebuilt Node 22 on Linux ARMv7. Setup does not compile Node or use unofficial builds as a fallback. System Node and project runtime pins remain unchanged.

All six scripts test a fresh shell at HOME without setup's temporary Node PATH. Setup enables Node's `.node-version`/`.nvmrc` support with mise's additive global setting and sets `activate_aggressive=true`, keeping mise-selected tool directories ahead of competing paths across directory/prompt hooks. Other enabled idiomatic tools and runtime selections remain intact.

Chezmoi owns activation in fish and Windows PowerShell. Its profiles refresh the ordinary mise selection after earlier hooks or PATH changes, including non-interactive shells. Fish, Bash, and Zsh dotfiles stop initializing fnm; Bash also discovers native Homebrew prefixes without an inherited Homebrew PATH. Existing runtime installations are preserved. Setup requires the current profile's process-local activation revision as well as runtime identity and effective PATH/Node-pin policies, so a coincidentally healthy legacy profile cannot skip migration.

If the fresh-shell check fails, setup automatically reapplies only the managed fish profile, or the Windows known-folder-aware PowerShell updater, and checks a new shell again. This bounded repair does not run unrelated Chezmoi scripts, rewrite profiles itself, weaken the runtime identity check, or bypass npm/Socket Firewall policy. The normal dotfiles update must obtain the matching dotfiles changes; a stale source, unavailable Chezmoi, failed apply, or ineffective repair remains a setup failure, not a successful skipped skill install.

A successful setup run guarantees the managed fresh-shell runtime, not the environment of already-open terminals or later manual changes. Intentional HOME/project pins remain unchanged and mise's native precedence applies: project `.node-version`, `.nvmrc`, and `.mise.toml` selections work; a HOME `.mise.toml` overrides the global default, whereas explicit global tools can outrank idiomatic files directly at HOME. Unsupported HOME selections, multiple global versions, explicit conflicting PATH/idiomatic-file policy overrides, and custom hooks still require review rather than destructive cleanup.

If runtime installation or validation fails, setup leaves the existing Pi package and command untouched. This protection does not roll back a later failed npm package update. Pi retains its normal npm installation and update commands, without a custom launcher or separate runtime.

After setup, open a new terminal and run `node --version` and `pi --version`. An already-open shell can retain its previous environment. If a project explicitly selects an unsupported Node version, switch to a supported version before running Pi there.

Run `bash tests/shared-node-runtime-contract.sh` for isolated fixtures. Set `PI_RUNTIME_DOTFILES_SOURCE=/absolute/path/to/dotfiles` for native mise/fish/Chezmoi integration across all five Bash wrappers: it reproduces legacy Node precedence, verifies targeted repair and repeated full-suite installation including `ask-matt`, and proves stale sources remain blocked. Set `PWSH_BIN` to a PowerShell executable to include its fixtures in both default and legacy native-argument modes. The latter catches PowerShell 5.1 quote loss without claiming native Windows coverage. On Windows, run `pwsh -NoProfile -File tests/shared-node-runtime-powershell.ps1` directly. Tests do not run full setup, change live dotfiles, contact arcane, or make model requests. Linux fixtures do not prove native Windows, macOS, or ARM behavior.

## Full Matt Pocock suite and retired skills

All six scripts install every skill that the upstream skills CLI discovers in `mattpocock/skills`. Setup uses `--skill '*' --full-depth`, not a fixed installation list. The current baseline contains 37 skills across engineering, productivity, misc, and in-progress categories. This includes eight experimental skills, as approved. Setup also installs newly added upstream skills on later runs.

Setup keeps upstream files unchanged and does not execute skill instructions. It does not run `/setup-matt-pocock-skills`, create project hooks, install the Claude plugin bundle, or make model requests. Some skills describe Claude-specific commands or require other tools when invoked. Installation alone does not prove that each workflow works in every agent or on every platform.

Setup first runs the native skills CLI in a disposable HOME, with its global agent paths isolated and the effective npm configuration preserved. This single native installation supplies both the complete skill selection and the files to install. Setup validates it, checks every selected destination—including new upstream names—and copies that exact snapshot into the real managed profiles. It does not fetch or select skills again during this copy. Unrelated skill links, including dangling links, remain untouched. A link at a selected destination or inside that skill still blocks installation before any selected destination changes.

Setup checks the skills CLI JSON result and every reported copy. Both copies must contain a nonempty regular `SKILL.md`, with no linked files or directories inside the skill. Missing baseline skills, partial results, and failed updates produce setup failures. If upstream retires or renames a baseline skill, the baseline needs review. Setup keeps the installed names in `~/.agents/.setup-matt-pocock-skills.json` for offline cleanup and duplicate-copy exclusions in Pi. It merges only the selected native update records into the active global skills lockfile and preserves unrelated records and preferences. Disposable files are removed without following linked targets.

Both `BAN_MATT_POCOCK_SKILLS=1` and `BAN_MATT_POCKOCK_SKILLS=1` remain supported. Either value removes the managed global copies without invoking the skills CLI. Cleanup includes names from the local inventory and upstream update records. `WORK_MACHINE=1` does not disable the suite. Existing `~/.env.local` files remain unchanged.

Setup removes PR Lens, Simple English, and HumanLayer `show-me` instead of installing them. Removal includes shared copies and global Claude Code, Codex, Gemini CLI, Cursor, and Pi copies. It also covers explicitly selected Claude, Codex, and Pi locations. User-modified global copies of all three retired skills are removed too.

Setup removes their `pr-lens`, `simple-english`, and `show-me` update records from `~/.agents/.skill-lock.json` and the selected `XDG_STATE_HOME/skills/.skill-lock.json`. The full Matt Pocock suite, project skills, other skills, hooks, credentials, diagrams, and hosted content remain unchanged.

Cleanup checks all target paths before removal. It unlinks skill links without following their targets and refuses linked ancestor directories or malformed metadata. The trusted Bazzite `/home` alias remains supported. A rejected Pi profile stays untouched, and retired-skill removal reports failure if those profiles cannot be checked. Missing Node or unsafe installation paths also produce failures, while unrelated setup work continues.

Pi uses the shared suite rather than a second direct copy. Setup removes identical direct duplicates and preserves modified duplicates with exclusions in Pi settings. The matching dotfiles template uses the complete baseline and local inventory so later applies retain these exclusions. Dotfiles do not install skills or restore any retired skill.

Each machine receives these changes on its next setup run. No remote rollout occurs. Restart an existing agent session to refresh its loaded skills.

Run `python3 tests/test_managed_skill_suite.py`, `bash tests/pi-skill-ownership-contract.sh`, and `bash tests/simple-english-skill-contract.sh` for isolated fixtures. Set `PWSH_BIN` to include PowerShell wrapper coverage. These tests use temporary homes and mocked installers, never live setup, skill execution, or uploads. Linux PowerShell fixtures do not prove native Windows ACL behavior.

Set `PI_SKILLS_DOTFILES_SOURCE` to a dotfiles checkout to test repeated setup and template rendering together. Set `MANAGED_SKILLS_CLI` to an installed `skills/dist/cli.mjs` entry point for the optional native CLI fixture. That fixture installs only inert local files into a temporary home, with network access and child processes blocked. It checks full-tree discovery, copied files, and the JSON report format.

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

Each machine adopts the channel on its next setup run. These changes do not update remote machines automatically. Managed daemons retain the headless limits below and restart when their package, managed service, or managed Muse profile requires it. Non-headless runs do not install a standalone daemon.

For Desktop clients, setup selects the update channel on macOS, native Linux, and Windows. It does not install or replace the Desktop app, launch a client, or start a bundled daemon. If Desktop is not installed, get it from the [Paseo download page](https://paseo.sh/download?channel=beta).

Close Desktop before setup changes its channel. Setup refuses to edit settings cached by a running app, because the app can overwrite external changes. After setup, open Desktop and select **Settings → About → Check** to download the selected update. Let Desktop complete the update to upgrade its bundled daemon too. If Desktop already uses the selected channel, setup leaves the file unchanged, even while the app runs.

Setup changes `settings.releaseChannel` and marks the legacy renderer import complete in `desktop-settings.json`. This prevents an older channel preference from replacing the selected channel. Setup preserves other settings and migration flags. It rejects malformed files, unknown document versions, linked paths, and paths that are not regular files or directories.

Linux permits one system link: `/home` pointing exactly to `var/home` or `/var/home`, as on Bazzite. The link and `/`, `/var`, and `/var/home` must belong to root. Those directories must be real directories without group or world write permission. Links within user homes, Desktop profiles, and settings files remain unsupported. Run setup normally on Bazzite. No terminal change or path override is required.

Desktop uses these user-data paths, separate from the standalone daemon's `PASEO_HOME`:

- macOS: `~/Library/Application Support/Paseo/desktop-settings.json`.
- Linux: `${XDG_CONFIG_HOME:-~/.config}/Paseo/desktop-settings.json`.
- Windows: `%APPDATA%\Paseo\desktop-settings.json`.

Setup honors `PASEO_ELECTRON_USER_DATA_DIR` when it contains an absolute path. Non-headless runs seed an absent Desktop profile on supported platforms. Headless runs change only existing Desktop profiles. WSL does not modify Windows client files. Run `win.ps1` on the Windows host and set its channel there.

The v0.8 beta has Desktop builds for macOS and Windows on x64 and ARM64, and Linux on x64. Linux ARM machines, including Raspberry Pi, can use the daemon with a supported remote client or browser. Setup does not seed an absent Linux ARM Desktop profile. It can change an existing profile for a custom Desktop build. The daemon-served web client follows the daemon package. The hosted web app has no setting managed by these scripts.

For Android betas, install the APK manually from [GitHub releases](https://github.com/getpaseo/paseo/releases). iOS and the mobile app stores have no beta channel. These scripts do not manage mobile installations.

To return to stable, set `PASEO_CHANNEL=stable` and rerun setup with Desktop closed. Managed daemons install the current npm `latest` version, which can be older than the beta. Desktop waits for a newer stable release and does not automatically downgrade. Back up Paseo data before downgrading a daemon. Changing the channel does not undo data migrations.

See [Paseo update instructions](https://paseo.sh/docs/updates.md). The client document format matches [the v0.8 beta Desktop settings store](https://github.com/getpaseo/paseo/blob/4eab53e24e1b57c74b00945aa48a89d68ed755e3/packages/desktop/src/settings/desktop-settings.ts). Tests use temporary fixtures and do not install, update, or start Paseo. Run `bash tests/paseo-release-channel-contract.sh` and `pwsh -NoProfile -File tests/paseo-release-channel-powershell.ps1` for channel coverage.

## Paseo Plain retirement

All six setup scripts remove the `paseo-plain` plugin on each machine's next setup run. They no longer install, update, or migrate it. Removal includes disabled installations, custom repositories, pinned revisions, and directory registrations under that exact ID. Other plugin IDs are untouched. Setup does not inventory or contact other machines.

Removal uses the selected local daemon's native plugin command. It preserves other plugins, global plugin enablement, credentials, projects, external source directories, `<PASEO_HOME>/plugin-data/paseo-plain` (preferences and cached rewrites), and existing recovery backups. Native removal deletes the managed checkout and `plugin-settings/paseo-plain`; setup first copies those native settings into a private `setup-recovery/paseo-plain-retirement/plugin-settings` backup. It never reinstalls the plugin. Saved data and backups are retained, not automatically purged.

The helper selects `PASEO_HOME`, or `~/.paseo` when unset. Explicit overrides must be absolute directories below the account HOME; empty, relative, HOME-itself, outside-HOME, and linked paths are rejected. The trusted Linux `/home` → `/var/home` system alias remains supported. Missing homes or registrations are an offline no-op. Malformed/linked metadata, shared deletion targets, and unfinished migrations require review instead of automatic removal.

Removal requires Node.js >=22.19 and a reachable local Paseo 0.8.x daemon with a metadata-verified compatible CLI. The explicitly validated CLI or existing Bun global CLI takes precedence over PATH. An incompatible verified managed release does not fall back to an older PATH installation. Pi and enabled plugins are **not** prerequisites. The helper uses an explicit loopback `--host`, ignores inherited `PASEO_HOST`, and does not enable plugins, start/restart a daemon, change release channels, or make model requests.

Legacy POSIX daemons can have an account-owned `paseo.pid` with mode `0664`, created under an older launch umask. Retirement may **read** that exact mode only when the PID is a regular, single-link file inside a private account-owned Paseo home, with trusted non-writable ancestors (root-owned sticky temporary directories are permitted). It leaves all permissions unchanged. Other metadata still rejects group/world write access. PID links, foreign ownership, other writable modes, nonlocal endpoints, or changed PID/home identity remain blocked. Bounded, nonblocking, no-follow reads and rechecks before CLI commands protect this exception; native heartbeat timestamps are allowed to change.

This read-only PID rule is independent of managed-daemon permission recovery. Retirement can therefore proceed when that separate step defers for process inspection or service drop-ins, without taking over the service or hiding the earlier setup error. A blocked PID check reports a controlled `pid preflight` operation and reason for private review, not a request for blanket `chmod` or a daemon restart.

If removal is blocked, setup reports a failed result while continuing unrelated work. Start the intended compatible local daemon and rerun setup, or remove `paseo-plain` from that daemon's **Settings > Plugins**. Do not enable plugins just for removal. Existing headless/platform restrictions remain unchanged; WSL does not manage the Windows host's daemon. Run the appropriate setup separately on each machine/account and selected Paseo home.

Diagnostics contain controlled operation/reason labels, such as `Paseo Plain removal failure: plugin remove: exit-1.`, not raw command output, exception text, credentials, or preferences. A timeout does not prove that the daemon stopped working: inspect plugin status before retrying. Do not edit plugin settings concurrently with removal.

### Paseo Plain migration recovery

Existing `setup-recovery/paseo-plain-release-to-main` backups remain untouched. An unfinished `state.json` blocks retirement until reviewed. Preserve the backup, confirm any previous operation has finished, and remove the plugin through the intended daemon's Settings rather than resuming the retired release-to-main migration. Never overwrite the entire daemon configuration or source registry with plugin-specific backup records.

An existing retirement backup also blocks another destructive attempt while native settings remain. Inspect the intended local daemon and compare the saved settings first. Once no operation is pending, preserve/archive that retirement backup before retrying. Do not move any recovery directory still used as a directory source by another plugin. If removal already finished, a rerun is a no-op and keeps the backup. Retirement never restores the plugin or overwrites newer settings.

### Retirement tests

Run `bash tests/paseo-plain-setup-contract.sh`. Fixtures extract helpers instead of sourcing full setup scripts; they use temporary homes and inert CLIs. Set `PWSH_BIN` for PowerShell wrapper coverage. Native Windows ACL behavior still requires Windows verification.

The optional native source/configuration-manager fixture needs an installed Paseo 0.8 module:

```bash
PASEO_TEST_PLUGIN_SERVICE_MODULE=/absolute/path/to/server/plugins/index.js \
  node tests/paseo-plain-native-retirement.mjs
```

It uses Paseo's real PID writer under a legacy `002` umask and verifies removal without changing the resulting `0664` PID. Coverage includes an active directory plugin with no managed store or native settings, disabled plugins/global switch, preserved external sources/data, native-settings backups, and idempotent reruns. Plugin execution and CLI transport are simulated: no listener, authentication, or model request is used. Git is file-only with isolated configuration/hooks. The contract wrapper also verifies that poisoned Git variables cannot mutate the caller's repository.

## Headless Paseo daemon

Set `HEADLESS=1` only when provisioning a machine that must remain remotely operable after logout or reboot. On native Linux setup scripts (`ubuntu.sh`, `pi.sh`, and `bazzite.sh`), this installs `@getpaseo/cli`, creates a managed `paseo.service` systemd user service with lingering enabled, starts it, and verifies local daemon health before setup succeeds. Ubuntu only configures unrestricted passwordless sudo when `HEADLESS_PASSWORDLESS_SUDO=1` is also set.

The service uses the IPv4 loopback address and port from `daemon.listen`. Each user on a multi-user machine must use a different port. If another process uses the configured port, setup stops before it starts the service.

`HEADLESS=1` is an exact-match provisioning trigger, not an off switch. Unset values, `HEADLESS=0`, and `HEADLESS=true` do not install or mutate Paseo service state. To disable a previously configured machine, manually stop/disable the managed service and use Paseo's normal unpairing/removal flow.

macOS `HEADLESS=1` skips the headless Paseo daemon with a warning unless `PASEO_MACOS_HEADLESS_CANARY=1` is also set for an approved no-login canary run; the rest of setup continues. WSL and native Windows fail early with a clear unsupported message because they cannot yet guarantee a true no-login Paseo daemon after host reboot.

Setup preserves Paseo's relay-based connection model, does not open inbound ports, and does not run or print pairing material. After the daemon is running, pair manually with Paseo's normal pairing flow.

### Surplus Paseo CLI installations

A surplus installation is a verified redundant global Paseo CLI. After eligible headless setup validates the retained Bun CLI and the managed daemon's health, cleanup checks known account-owned npm locations. These locations are `~/.local/lib/node_modules/@getpaseo/cli` and the global npm stores in `~/.local/share/mise/installs/node/<version>`. Version or absence from PATH alone does not authorize removal. Custom prefixes, source and project installations, Desktop bundles, unrelated packages, and all `PASEO_HOME` data remain unchanged.

Cleanup uses native npm removal with offline mode and lifecycle scripts disabled. It checks all candidates before the first removal and checks running processes and service references before each removal. A reference from a stopped service also prevents removal. Cleanup adds no daemon restart or stop operation. It runs after the existing managed-service update and preserves any installation still in use or with uncertain ownership. The managed wrapper records its CLI launch path in `PASEO_SETUP_CLI`. A wrapper update uses the existing managed-service restart flow only after read-only ownership checks reject Desktop, custom, and self-hosted owners. Cleanup checks process launch origin, working directories, and runtime environment references before removing another CLI. Custom daemon homes and incomplete process or service inspection defer cleanup with a controlled reason.

The existing native Linux headless and macOS canary gates apply to cleanup. Windows and WSL do not gain a managed headless installer or destructive CLI cleanup. When cleanup defers, review the local service references before manually removing an installation. Do not remove daemon state or plugin recovery files to repair CLI selection.

Run `bash tests/pi-profile-permissions-contract.sh` and `bash tests/paseo-cli-cleanup-contract.sh` for the new offline fixtures. The cleanup suite exercises native npm only against a temporary prefix. Use `PWSH_BIN` for available PowerShell wrapper coverage. Portable PowerShell does not prove native Windows ACL behavior.

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
