# CLAUDE.md

This file provides guidance to AI coding agents working with code in this repository.

## Repository Overview

This repository contains idempotent machine setup scripts for automating the configuration of fresh development environments across different operating systems. The scripts are designed to be run multiple times safely and install a consistent set of development tools.

## Agent skills

### Issue tracker

Track issues and specs in GitHub Issues for scowalt/machine-setup-scripts.
Before creating, reading, or updating tickets, read `docs/agents/issue-tracker.md`.

### Triage labels

Use the five default triage roles.
Before triaging, read `docs/agents/triage-labels.md`.

### Domain docs

Single-context: root `GLOSSARY.md` and `docs/adr/`.
Before exploring domain behavior, read `docs/agents/domain.md`.

## Documentation boundaries

Domain vocabulary lives in [GLOSSARY.md](GLOSSARY.md). Skills now read and write only `GLOSSARY.md` / `GLOSSARY-MAP.md`. For older domain documents, migrate with `git mv CONTEXT.md GLOSSARY.md` and, if present, `git mv CONTEXT-MAP.md GLOSSARY-MAP.md`; likewise use `git mv CONTEXT-FORMAT.md GLOSSARY-FORMAT.md` for a convention-specific format helper.

Keep `README.md` a short, first-person introduction for humans: Scott's motivation, representative capabilities, compact commands for all six platforms, and the opinionated-script/interruption warning. Prefer a few hundred words; it is not an operator manual, exhaustive inventory, implementation spec, or change log. Routine tool changes belong in code and behavioral tests, not new README sections or prose-enforcing assertions.

Record only consequential, non-obvious trade-offs in concise [ADRs](docs/adr/), grounded in existing evidence; discard repetitive mechanics rather than relocating the README into replacement manuals. Preserve incident/research records and their uncertainty. When removing documentation, repair active agent pointers to current code, contracts, or decision records rather than leaving references to vanished sections.

## Ordinary setup and fixture containment

The non-disruptive default is rolled back: all six ordinary entry points provision/update without a maintenance switch and can interrupt ongoing work. Preserve pre-existing trust/recovery/platform gates and component-scoped deferrals. Keep data-only dotenv policy in `lib/setup-policy.{bash,ps1}` and regenerate with `tools/embed-setup-policy.py`; literal credentials and controlled unsupported-syntax failures remain required. For scheduling/default/log-path changes, read [the rollback scope and evidence](docs/research/2026-09-30-setup-rollback.md). The earlier non-disruptive plan is historical, not current policy. Never run live setup to validate development changes.

For any behavioral fixture execution or source-loader change, read `docs/research/2026-09-29-fixture-execution-audit.md` and the linked incident record first. Use its sanitized `env -i` runner with explicit existing tools, mandatory kernel filter/self-test, private stdio/roots and sequential suites. Definitions-only imports and mocks precede intentional helper/caller execution; never source or evaluate a stripped whole setup file. Copy native fixture runtimes rather than link writable prefixes to real installations. If containment/preflight fails or a real effect appears, stop and report—no uncontained fallback. Run the setup-default and extraction/containment contracts plus the audited affected matrix. Keep incident uncertainty, optional skips and native-platform/continuity limitations explicit; passing offline fixtures is not rollout evidence.

## Key Scripts

- **mac.sh** - macOS setup using Homebrew. For CLT/bootstrap or caller changes, read [the operation-results decision](docs/adr/0007-use-operation-results-instead-of-clt-compatibility-gates.md), `install_xcode_cli_tools`, `run_setup_tasks` and `tests/test_macos_clt.py`. Attempt ordinary work without a compiler/SDK compatibility gate or automatic repair of existing CLT; preserve first-time bootstrap and existing toolchain selection. Actual operation and required-result failures stay nonzero through unrelated work, reboot reporting and log finalization; retain ownership, credential and transaction safeguards. Run CLT, Homebrew-result, reliability, reboot, weekly and affected caller contracts through the audited contained runner. Native Apple behavior requires separately authorized Mac evidence; never run live updates to validate a change.
- **bb desktop** - Exact `HEADLESS=1` skips without mutation; headed personal/work Apple Silicon macOS and native Ubuntu/Bazzite x64 use official stable native artifacts (Linux alpha). Preserve unsupported/custom/nightly/newer copies, defer verified running apps, and fail on uncertain identity/ownership. Keep embedded shared policy identical and aggregate failures. Never execute the app for validation or change CLI/server/user state. Run `bash tests/bb-desktop-contract.sh` with inert extracted helpers. For desktop prerequisites/recovery changes, read `bb_desktop_payload` in `mac.sh` and `tests/test_bb_desktop.py`. For macOS parent ownership, staging or rollback changes, read [the native Applications trust decision](docs/adr/0006-accept-native-macos-applications-for-bb-desktop.md). Native signature/menu/GUI checks belong to rollout. Linux uses the approved install-only contract: verified installation/current/newer results succeed with an explicit unverified GUI/sandbox compatibility warning. Keep real artifact/runtime/safety failures fatal; neither inspect AppArmor policy nor run a generic namespace probe to decide success. Read `docs/research/2026-09-28-bb-desktop-linux-sandbox.md` when changing that compatibility policy.
- **Ubuntu bb server** - `BB_SERVER=1` opts native Ubuntu into a stable independent bb main server; no hostname allowlist. Unset/0 preserves installation/lifecycle state; independent plugin refresh may target a verified local main server. Preserve provider credentials, npm policy, bb data and unrelated routes. Keep stopped updates, native config locks, and readiness-gated foreground Serve at the saved endpoint. Run `bash tests/bb-server-contract.sh` after changes with inert lifecycle fixtures; real boot, remote tailnet browser/WebSocket and local execution checks belong to rollout. For prerequisites and service changes, read `setup_bb_server` and its helpers in `ubuntu.sh`, plus `tests/bb-server-contract.sh`.
- **BB machine preparation** - The five Bash scripts install a separate setup-owned stable npm copy for later manual enrollment on personal/work machines; Windows explains WSL2 only. Keep shared helpers identical. Preserve all existing server/enrollment state and services even without `BB_SERVER=1`; defer known roles without claiming readiness and reject unmanaged command conflicts. Keep preparation independent of Pi gates, pin effective npm config paths before changing prefix, preserve native policy precedence and shared Node, and aggregate failures. Read-only service-reference checks preserve unrelated trusted links/empty files/masks; preparation-owned paths remain link-rejecting. Linux group-write exceptions require a private ancestor or the native exclusive-primary-group/ACL proof, including NSS initgroups policy. Preserve parent-before-descendant link traversal, bounded diagnostics and stable snapshots; reject shared/stale foreign memberships, unknown identity sources, world write and changed references. Converge setup's copy without chmodding unrelated services/projects. Preserve exact `HEADLESS=1` semantics. No BB lifecycle, pairing, provider auth or Tailscale commands in this path. Run `bash tests/bb-machine-preparation-contract.sh` plus the BB server, reliability, runtime and headless contracts with temporary extracted fixtures only. For ownership/enrollment changes, read [the preparation decision](docs/adr/0003-separate-bb-preparation-from-enrollment.md), `setup_bb_machine` and its helpers in `ubuntu.sh`, and the upstream [enrollment instructions](https://github.com/get-bb/bb/blob/main/docs/multiple-devices.md).
- **BB plugin refresh** - Before changing discovery, peer identity, native source/update verification or caller wiring, read `docs/plans/2026-10-01-bb-plugin-refresh.md` and `docs/research/2026-10-01-bb-plugin-refresh-api.md`. Keep `lib/bb-plugin-refresh.{py,bash}` embedded identically with `tools/embed-bb-plugin-refresh.py`. Refresh is independent of Pi/preparation and Ubuntu lifecycle opt-out, but retains native server-readiness/platform/trust gates. Native stopped/safe-mode deferrals preserve earlier failures; unavailable/rollback/unverified outcomes fail through log finalization. Never start BB solely for refresh, use inherited CLI/URL as identity, or edit plugin stores. Run the new targeted fixture and the audited affected matrix only under mandatory containment; native BB/app/plugin execution is rollout work, not development validation.
- **ubuntu.sh** - Ubuntu Linux setup with user management
- **win.ps1** - Windows setup using WinGet and PowerShell
- **wsl.sh** - Windows Subsystem for Linux setup
- **pi.sh** - Raspberry Pi specific setup with ARM optimizations
- **bazzite.sh** - Bazzite OS setup using Homebrew (Lenovo Legion Go)

## Common Development Tasks

### Running Setup Scripts Locally

These commands provision/update normally and can interrupt active work. Arrange an appropriate window before running them. Never run live setup to validate a code change.

```bash
# macOS
./mac.sh

# Ubuntu/WSL/Pi/Bazzite
sudo ./ubuntu.sh  # or ./wsl.sh, ./pi.sh, ./bazzite.sh

# Windows (PowerShell as Administrator)
./win.ps1
```

### Remote Execution

Scripts are hosted at `https://scripts.scowalt.com/setup/` for remote execution via curl/wget as shown in [README's Run it section](README.md#run-it).

### Repository Management

Use `git` and `gh` CLI tools to manage this repository:

- `gh pr create` - Create pull requests via GitHub CLI
- `gh pr merge` - Merge pull requests

## Investigating Setup Logs

Use `https://logs.scowalt.com` as the canonical source for setup logs, even when the requested file is absent locally.
Read access requires an `Authorization: Bearer <token>` header. An unauthenticated `401` does not prove that the collector is broken.

1. Retrieve `SETUP_LOG_AUTH_TOKEN` from Doppler project `mission-control`, configuration `dev`, using the existing Doppler login.
2. List uploads with authenticated `GET /logs`, or list one machine with `GET /logs/:hostname`.
3. Retrieve candidates with authenticated `GET /logs/:hostname/:filename`.
4. Match the requested local filename against the `Logging to` or `Run log saved to` line inside each candidate.

Collector filenames use UTC upload timestamps, not local run filenames. Allow for timezone differences when selecting candidates.

Use this pattern to list logs without putting the token in process arguments or shell traces:

```bash
(
    set +x
    set -o pipefail
    token=$(doppler secrets get SETUP_LOG_AUTH_TOKEN --project mission-control --config dev --plain) || exit 1
    [[ -n "${token}" ]] || exit 1
    printf 'Authorization: Bearer %s\n' "${token}" |
        curl --fail --silent --show-error --max-time 20 --header @- 'https://logs.scowalt.com/logs'
)
```

Keep the token out of output, files, commits, and chat. Redact secrets before displaying downloaded log content.
If access still fails, report whether Doppler retrieval or the authenticated HTTP request failed, including the status without credentials.
Try this authenticated path before asking the user to attach a log. Do not remove authentication, rotate secrets, or redeploy the collector to fix an omitted request token.

## Architecture and Patterns

### Script Structure

All scripts follow a consistent pattern:

1. Color function definitions (cyan/green/yellow/red output)
2. SSH key verification with GitHub
3. Tool installation checks (idempotent)
4. Package manager setup
5. Individual tool installations
6. Configuration steps (dotfiles, shell setup)

### Key Design Principles

- **Idempotency**: Scripts check for existing installations before proceeding
- **Error Handling**: Failed installations are logged but don't stop execution
- **Homebrew results**: macOS command failures, failed verification, unresolved unpinned updates and trust-skipped work must reach the final nonzero result without bypassing log finalization. Preserve user pins; tmux cleanup owns only setup's temporary pin. Run `bash tests/setup-reliability-contract.sh` and `python3 tests/test_homebrew_results.py` for changes.
- **User Feedback**: Color-coded output for status messages
- **Platform-Specific**: Each script optimized for its target OS
- **Dotfile Management**: Shell configurations are managed by chezmoi - scripts should only install tools, not configure shells. For installer profile edits or activation repairs, read [the shell-ownership decision](docs/adr/0002-let-chezmoi-own-shell-configuration.md).

### Common Tools Installed

- Version Control: git, gh (GitHub CLI)
- Shell: fish (with completions), tmux
- Node.js: shared mise runtime. Pi requires >=22.19 and `fs.globSync`; the skills CLI requires >=22.20. Preserve a compatible global selection even when setup inherits another Node. If needed, provision Node 24 or official Node 22 binaries on Linux ARMv7 without compilation. Validate ordinary HOME selection and fresh-shell activation before Pi package mutations. Preserve project pins and conflicting HOME overrides. Chezmoi owns shell activation and retires managed fnm startup. All six scripts enable Node idiomatic project pins additively and native `activate_aggressive` PATH precedence, require the process-local activation revision plus runtime/policy checks, and repair failure through one targeted Chezmoi apply before independently rechecking. Preserve unrelated files/scripts, runtime installations, native config precedence, intentional overrides, and npm security. Keep Bash helpers identical and repair failures blocking dependent setup. Do not add private Pi runtimes, launchers, or npm adapters. Run `bash tests/shared-node-runtime-contract.sh`; set `PI_RUNTIME_DOTFILES_SOURCE` for native repair-to-skills integration and `PWSH_BIN` for PowerShell fixtures.
- Python: pyenv (Python version management)
- Security: 1Password CLI, Tailscale
- Dotfiles: Chezmoi (with auto-sync)
- Terminal: Starship prompt
- CI/CD: act (local GitHub Actions)
- AI agents and developer CLIs: Notion CLI (`ntn`), Claude Code CLI, Gemini CLI, Codex CLI, Pi coding agent
- Agent skills/plugins: The full Matt Pocock suite is the managed global skill suite for Claude Code, Codex, Gemini CLI, and Pi.
- Retired skills: Setup removes global `pr-lens`, `simple-english`, and `show-me` copies on each machine's next setup run, including user-modified copies and update records. Cover shared, default, and explicitly selected Claude, Codex, and Pi locations, plus default Gemini CLI and Cursor locations. Unlink skill links without following targets. Reject linked ancestors and malformed metadata, and preserve the trusted Bazzite HOME alias. Preserve unrelated skills, credentials, project files, hooks, and hosted diagrams. Blocked Pi profiles stay untouched and produce a failed retirement result. Keep the full Matt Pocock suite. Do not install or invoke any retired skill, run fleet cleanup, or upload diagrams during development.
- Matt Pocock skills: All six scripts request the full `mattpocock/skills` repository with `--skill '*' --full-depth --copy --yes --json`. Include engineering, productivity, misc, and experimental in-progress skills on personal and work machines. Target Claude Code, Codex, and Gemini CLI through the native skills CLI. Pi discovers the shared copy without `--agent pi`. Validate the complete JSON result and both copies, including nonempty regular `SKILL.md` files and rejection of linked artifacts. The reviewed 37-skill baseline includes `pr`, not upstream-retired `resolving-merge-conflicts`; it is a validation floor, not an installation allowlist. Retain historical ownership in inventory, offline opt-out cleanup and Pi exclusions even without prior inventory. Ordinary installation preserves historical copies except existing identical-Pi-duplicate removal. Accept new upstream names, and review retired baseline names rather than silently accepting an incomplete suite. Preserve the shared Node runtime and both opt-outs. Do not execute installed skills, install the Claude plugin bundle, or configure project hooks.
- Full-suite installation uses one native CLI run in a disposable HOME, with every agent/XDG target redirected there and effective npm configuration preserved. Validate both complete copies, the exact JSON selection, and native source records before checking every selected real destination, including future upstream names. Promote that same verified snapshot without another fetch or selection. Preserve unrelated live/dangling skill links; keep rejecting actual target links and nested linked artifacts. Merge only the selected native update records, preserving unrelated metadata. Dispose of staging through bounded Node unlink traversal, not recursive PowerShell removal that can follow junctions. Keep caller environment restoration compatible with Windows PowerShell 5.1, which lacks `$IsWindows`. Use temporary inert native CLI/Git fixtures, isolate inherited Git controls and hooks, and never execute skills.
- Skill paths: Codex, Gemini CLI, and Pi share canonical managed agent skills in `~/.agents/skills`. Claude Code uses copied files in its selected profile. Keep the shared embedded managed-skill policy identical in all six scripts. Persist the skill-name inventory at `~/.agents/.setup-matt-pocock-skills.json` and use it for offline cleanup and Pi duplicate exclusions. Dotfiles retain exclusions for the baseline and this inventory. Remove identical direct Pi duplicates, preserve and exclude modified duplicates, and preserve intentional shared copies. Run `python3 tests/test_managed_skill_suite.py`, the ownership and managed-agent skill contracts (the latter retains the `simple-english-skill-contract.sh` filename), weekly regressions, and PowerShell reliability fixtures with `PWSH_BIN`. Extract helpers and use temporary homes, never live setup or skill execution.
- Skill maintenance: Setup validates installed files. It removes legacy Impeccable skill copies and Cursor subagent files. It does not change project data or hooks.
- Notion CLI: Setup uses the native installer on macOS and Linux. Setup uses WinGet on Windows. Setup does not run `ntn login` or install shell completions.
- Claude Code CLI: Setup uses the Anthropic native installer instead of npm or Bun. Thus, the CLI does not require a global Node runtime. Setup installs or updates the CLI on supported machines, with no opt-out. Setup ignores `BAN_CLAUDE_CODE` and preserves existing `.env.local` files.
- Work machines: Setup installs Google Cloud CLI. Setup updates its components when the component manager is available.
- Opt-outs: Set `BAN_MATT_POCOCK_SKILLS=1` to remove the managed Matt Pocock skills and keep them inactive. The older `BAN_MATT_POCKOCK_SKILLS=1` spelling also works. `WORK_MACHINE=1` does not disable these skills. PR Lens, Simple English, and `show-me` removal have no opt-out.
- If Claude Code setup warns that another `claude` command shadows the native binary, do not authenticate Fable with bare `claude` until PATH/package cleanup is done; use the native path printed by the script.
- Pi defaults to GPT-6 Astra (`gpt-6-astra`) through the built-in `openai-codex` provider with `xhigh` thinking on all machines, including work machines. Setup also sets its per-model thinking default to `xhigh` so an older override cannot lower it. Chezmoi owns the same defaults through `private_settings.json.tmpl`. Pi uses its existing OpenAI Codex login, not a new key in `models.json`. Setup removes the retired Synthetic provider from `models.json` but preserves other providers, `auth.json`, and existing `~/.env.local` files. Machines with `ZAI_API_KEY` still get the optional z.ai GLM Coding Plan provider at `https://api.z.ai/api/coding/paas/v4`. Its models are `glm-5.3`, `glm-5-turbo`, and `glm-4.7`. GLM-5.3 supports `low`/`high`/`max` reasoning, so its `thinkingLevelMap` leaves `minimal`/`medium`/`xhigh` unmapped. Missing z.ai keys produce warnings only on work machines and never change the default model. Pi uses package-managed goal/autoresearch skills. The autoresearch dashboard uses `Ctrl+Shift+R` so `Ctrl+Shift+F` remains Pi transcript search.
- Pi output style: `pi-prose` is retired. Every setup run must remove it from the default and explicitly configured global Pi profiles, including previously user-selected copies. Remove its Pi package declarations, direct npm dependency declarations, matching lockfile records, and installed package directory. Preserve existing custom prose files, including empty or malformed configurations. Preserve unrelated packages, credentials, and project data. Do not reinstall the package or seed a prose default. Dotfiles must not list the package or manage its initial configuration.
- Pi prose retirement: Keep the embedded Node cleanup identical in all six scripts. Run it after dotfiles application and before Pi package operations. Do not invoke npm or Pi, run lifecycle scripts, resolve dependencies, or relax npm security policy to remove the package. Resolve only the trusted account HOME boundary. Reject linked profile/store directories and JSON metadata. Unlink a linked package without following its target. Preflight both profiles and stop Pi package operations on malformed, unverified, or failed cleanup. Continue unrelated work and finish logs with a failed setup result. Preserve cached shared dependencies and custom prose files. Run `bash tests/pi-prose-contract.sh` with `PWSH_BIN` set for Windows wrapper coverage. Use only extracted functions and temporary fixtures, never live setup or remote cleanup.

### OpenCode v2 CLI

- Maintain official stable 2.x CLI/TUI installation separately from Pi Go. Native Linux/macOS headless runs are included; Windows/WSL whole-setup `HEADLESS=1` rejection remains before provisioning and is exempt. Preserve newer releases, pins, custom/uncertain copies and unsupported architectures without source builds. Keep shared policy in `lib/opencode-cli.{cjs,bash,ps1}` and regenerate all six standalone entry points with `python3 tools/embed-opencode-cli.py`.
- Match official artifact bytes before executing even `--version`; accept only the exact expected bare version or official `opencode v<version>` line from a successful isolated probe. Stage and verify before command promotion, and retain/restore the prior command on failure. Migration quarantines identified commands only; package stores/registrations and application data stay intact. Preserve the bounded version-discovery conflict behavior, exact npm wrapper evidence, safe archives/URLs, ownership checks, native Windows ACL checks and generic-upgrade exclusions; compiler compatibility does not gate native migration. Before changing these boundaries, read [the command-only migration decision](docs/adr/0004-keep-opencode-migration-command-only.md), `lib/opencode-cli.cjs` and `tests/opencode-cli.test.cjs`.
- For Linux Homebrew permission or migration changes, read [the scoped group-write decision](docs/adr/0005-accept-opencode-linux-homebrew-group-write.md). Accept account-owned group write only within the recognized Linux Homebrew prefix, without NSS/initgroups/process/ACL privacy proof or a native proof interpreter. Preserve root/foreign/world-write rejection and filesystem revalidation, including changed group/mode evidence; service-account write access remains an accepted tampering risk. BB, credential and other platform policies stay independent. Exercise the real migration fixtures with privacy-proof external operations forbidden.
- Installation/version checks only: preserve shell configuration, credentials, Pi/Go defaults and all agent/skill/plugin configuration. Aggregate failures through log finalization. Run `bash tests/opencode-cli-contract.sh` and affected AI-agent, reliability, weekly, headless, runtime, Pi Go/wiring, Paseo non-management and CLT/Homebrew contracts. Use temporary extracted fixtures and inert native probes; native rollout is separate. `PWSH_BIN` and optional installed `OPENCODE_TEST_CMD_SHIM` add fixture coverage without application execution.

### OpenCode Go for Pi

- All six scripts add Go access for Pi on personal and work machines, including the built-in Muse Spark 1.3 Contributor model with native xhigh reasoning. Preserve GPT-6 Astra defaults. The separate OpenCode CLI installer above does not configure Go credentials or substitute paid Zen.
- Read the setup-specific `OPENCODE_GO_API_KEY` from the account's `~/.env.local` without executing the file in the credential helper. A nonempty value replaces only the active Pi profile's `opencode-go` credential in private `auth.json`. Missing input preserves it. Keep other credentials, existing environment files, `models.json`, project data, and other global Pi profiles unchanged. Do not export shared `OPENCODE_API_KEY`, which Pi recognizes for both Go and Zen.
- Coordinate auth writes with Pi's native credential lock. Reject malformed or linked metadata, protect local secret permissions and Windows ACLs, and never print keys or arbitrary exception output. Keep the embedded credential helper identical in all six scripts. Use the installed built-in Go catalog and native `xhigh` mapping without an inference request. Accept legacy and exact `chat:`-prefixed Muse keys only in `openai-responses`, with one semantic ID match; typed entries require `type: chat`, and any explicit non-chat type fails. Reject explicit active `opencode-go` model/provider overrides without rewriting them. Trust the already-installed Pi code under its normal npm umask, but require private credentials and non-writable credential directory boundaries. Set `PI_GO_LOCK_MODULE` to Pi's installed `proper-lockfile/index.js` for the additional offline native-lock/catalog fixtures. Failed Go validation blocks later Pi package operations; continue unrelated work and report the failed result. Go diagnostics must carry a controlled operation label and allowlisted reason or native error code through every Bash/PowerShell wrapper. Reject unrecognized helper output and never echo raw stderr, arbitrary exceptions, credentials, or custom paths. Preserve the failing operation across cleanup, and report unknown causes without guessing.
- Contributor prompts and responses can be retained and used for training. The user accepts availability on work machines. Account subscription, training consent, and the disabled Go **Use balance** option remain user responsibilities. The Go endpoint alone cannot guarantee subscription-only billing. Setup must not buy access, change account settings, or make model requests.
- Run `bash tests/pi-opencode-go-contract.sh` and `bash tests/opencode-go-wiring-contract.sh`, with `PWSH_BIN` for PowerShell wrappers, plus affected AI-agent, model-default, headless, shared-runtime, and Telegram contracts. Extract only tested functions and use temporary homes/inert commands. Never run live setup or fleet changes during development.

### Pi profile permissions

- All six scripts prepare the default and explicitly selected Pi profile directories after dotfiles and before Pi mutations. Keep the embedded permission helper identical. Preflight both profiles, repair only account-owned real directories inside HOME to `0700` or equivalent private native Windows ACLs, and preserve HOME, unrelated ancestors, file contents, and credential permissions. Do not recurse or follow linked profiles. Preserve the trusted Linux system HOME alias. Permission failure blocks later Pi mutations, while unrelated work continues. Unix leaf creation uses isolated `/usr/bin/python3` descriptor-relative operations and fails closed when unavailable. Windows creation and ACL changes use pinned native handles and stable volume/file identity.
- Run `tests/pi-profile-permissions-contract.sh` and affected Go/package/runtime suites with available `PWSH_BIN`. Use only extracted helpers and temporary fixtures. Native Windows ACL behavior still needs Windows verification.

### Pi package maintenance and Codex profiles

- Pin `pi-mcp-adapter` to `2.32.1` in all six scripts. Version `2.33.0` introduces remote preview dependencies that managed npm policy rejects. Do not relax npm restrictions to install it.
- Keep the embedded adapter recovery code identical. Repair only the active global profile's adapter sources and direct npm dependency entries before other package operations. Preserve source filters, unrelated data, other profiles, and npm configuration. Let npm update its own lockfiles. Opt-out removes declarations without installing the adapter. Reject malformed or linked managed metadata before changes.
- Dotfiles must retain the pinned adapter in the default global Pi package list unless `BAN_PI_MCP_ADAPTER=1`. Setup verifies its nonempty regular `index.ts` and enabled package resource selection. Preserve filters and report disabled, duplicate, or unverified declarations as failures. Do not execute live extensions to validate setup: they can start MCP servers. The optional registry probe loads the real adapter in an isolated HOME with network calls blocked. Set `PI_ADAPTER_DOTFILES_SOURCE` for repeated render/setup fixtures.
- Required Pi package helpers must return failure on failed installs, removals, or validation. Callers aggregate failures and finish logs after unaffected work. Existing registrations cannot prove a failed update succeeded. Retirement and metadata safety failures must block further Pi package operations.
- Run `bash tests/pi-package-maintenance-contract.sh`, with `PWSH_BIN` for Windows wrapper coverage. The optional registry probe requires `PI_PACKAGE_NPM_CLI` and `PI_PACKAGE_CLI` JavaScript entry points. It uses temporary homes, disables lifecycle scripts, and retains remote URL restrictions.
- On Linux, Codex's native installer gets a disposable `HOME`, an explicit real `CODEX_INSTALL_DIR`, and the account's `CODEX_HOME`. Do not let the installer edit Chezmoi-managed profiles. Preserve the trusted tool PATH and Node-free binary smoke test. Run `bash tests/codex-profile-isolation-contract.sh`.

### Unmanaged legacy Paseo and headless boundaries

- Preserve existing Paseo installations, services, configuration, credentials, plugins, data, recovery files and existing environment files. Setup no longer manages or contacts Paseo; add neither lifecycle/validation/cleanup operations nor automatic migration to BB. Independent Pi OpenCode Go and full upstream skill suites remain managed; do not filter skills by mentions of Paseo.
- Dotfiles source no longer distributes the GitHub-token helper or service drop-in. Preserve already-deployed artifacts: no deletion rules or live apply as part of this removal.
- Preserve early exact `HEADLESS=1` rejection on Windows/WSL with generic no-login diagnostics, BB's independent WSL boundary, native Linux headless platform restrictions, Ubuntu's separate passwordless-sudo opt-in, macOS headless effects and BB desktop skips. Other flag values do not enable headless mode.
- Run `bash tests/paseo-non-management-contract.sh` and `bash tests/headless-contract.sh`, plus BB/Pi/runtime/reliability contracts after orchestration changes. Fixtures extract callers and use temporary state/inert commands; never run live setup, daemon inventory, apps or skills. Set `PASEO_UNMANAGED_DOTFILES_SOURCE` for the read-only cross-repository source contract and `PWSH_BIN` for PowerShell fixtures.

### Telegram alerts

- New environment files include commented `TELEGRAM_ALERTS_BOT_TOKEN` and `TELEGRAM_ALERTS_CHAT_ID` entries.
- Preserve existing `~/.env.local` files. Never print, commit, or distribute real alert credentials.
- Dotfiles own the global agent policy and `~/.config/agent-docs/telegram-alerts.md` request guide.
- Agents call Telegram directly. Do not add a notification helper, service, or shell-profile change to setup scripts.
- Work-machine alerts require Scott's explicit permission. Credentials alone do not grant permission.
- Run `bash tests/telegram-alerts-contract.sh` after environment-template changes.

### Important Notes

- Scripts require SSH keys to be registered with GitHub before running
- Ubuntu script enforces creation of 'scowalt' user
- All scripts configure fish as the default shell
- Chezmoi manages dotfiles with automatic git operations
- **IMPORTANT**: Do not add shell configuration (bashrc, zshrc, fish config, PowerShell profiles) in setup scripts - these are managed by chezmoi and will be overridden

## GitHub SSH Key Security Model

The setup scripts automatically detect whether a machine is physical or a VPS to enforce security best practices:

### Physical Machines (Local Access)

- **Detection**: No virtualization detected, no cloud-init present, or explicitly identified as Raspberry Pi/macOS/WSL
- **SSH Access**: Full write access via SSH authentication keys (`~/.ssh/id_rsa`)
- **Security Rationale**: Physical machines are in your possession and pose minimal risk if compromised
- **Examples**: Laptops, desktops, Raspberry Pi devices, WSL on Windows

### VPS/Cloud Machines (Remote Access)

- **Detection**: Virtualization detected (systemd-detect-virt), cloud-init present, or cloud provider IP address
- **SSH Access**: Read-only access via deploy keys (`~/.ssh/dotfiles-deploy-key`)
- **Write Access**: Optional via fine-grained tokens manually configured in `~/.env.local`
- **Security Rationale**: VPS compromise should not grant attackers write access to all your GitHub repositories
- **Examples**: DigitalOcean droplets, AWS EC2 instances, Linode VPS, Vultr servers, Hetzner cloud

### Detection Algorithm

The scripts use a weighted scoring system with multiple heuristic signals:

1. **Virtualization (3 points)**: `systemd-detect-virt` output, DMI product/vendor strings
2. **Cloud-init (2 points)**: Presence of `/etc/cloud/cloud.cfg`
3. **IP Analysis (2 points)**: Cloud provider detection via ipinfo.io
4. **Special Cases**: Raspberry Pi always detected as physical (ARM + device tree)

**Threshold**: 3+ points = VPS, otherwise physical

**Override**: Set `MACHINE_TYPE=physical` or `MACHINE_TYPE=vps` environment variable to manually override detection

### Debugging Detection

Enable debug output to see detection decisions:

```bash
DEBUG=1 ./ubuntu.sh
```

This will show:

- VPS score
- Which signals were detected
- Final decision (vps or physical)

### Migration Strategy

**Existing VPS machines with SSH auth keys**:

- Keys continue to work (not automatically removed)
- Manually remove from GitHub after confirming deploy key works
- Future runs of setup scripts will use deploy keys instead

## Nerd Font Symbols

### What are Nerd Fonts?

Nerd Fonts are patched fonts that include thousands of icons from popular icon sets (Font Awesome, Devicons, Octicons, etc.). These scripts use Nerd Font symbols extensively for visual feedback in terminal output.

### Working with Nerd Font Symbols as an LLM

**IMPORTANT UPDATE**: AI coding agents can successfully edit files containing Nerd Font symbols and preserve them correctly. The symbols are essential to the visual design.

#### How to handle them

1. **When editing**: Nerd Font symbols will be preserved automatically when using the Edit tool
2. **To add new ones**: Use Unicode characters directly in your edits:
   - Arrow: → (U+2192)
   - Checkmark: ✓ (U+2713)
   - Warning: ⚠ (U+26A0)
   - Cross/Error: ✗ (U+2717)
   - Sparkles: ✨ (U+2728)
   - Apple: 🍎 (U+1F34E)
   - Penguin: 🐧 (U+1F427)
   - Strawberry: 🍓 (U+1F353)
   - Window: 🪟 (U+1FA9F)

#### Common symbols used in these scripts

- Success indicators: ✓ (checkmark)
- Error indicators: ✗ (cross)
- Warning indicators: ⚠ (warning sign)
- Action indicators: → (arrow)
- Special icons: 🍎 (Apple emoji for macOS)

#### Example

```bash
print_success() { printf "${GREEN}✓ %s${NC}\n" "$1"; }  # The ✓ is a Nerd Font symbol
```

**Remember**: These symbols are part of the user experience design. They make terminal output more readable and visually appealing.

## Logging Conventions

### Print Functions (Bash Scripts)

All bash scripts use consistent logging functions with Nerd Font symbols:

```bash
print_section()  # Bold section headers with === borders
print_message()  # Cyan messages with → arrow
print_success()  # Green messages with ✓ checkmark  
print_warning()  # Yellow messages with ⚠ warning sign
print_error()    # Red messages with ✗ cross
print_debug()    # Gray messages with subtle indent
```

### When to Use Each Level

- **print_section**: Major stages of the setup process
- **print_message**: General information and actions being taken
- **print_success**: Successful completions
- **print_warning**: ONLY for actual warnings (not for "already installed")
- **print_error**: Failures that stop execution
- **print_debug**: Informational messages like "already installed" or "already configured"

### PowerShell Equivalents

```powershell
Write-Section   # White on dark blue background
Write-Message   # Cyan with arrow symbol
Write-Success   # Green with checkmark
Write-Warning   # Yellow with warning icon
Write-Error     # Red with cross icon
Write-Debug     # Dark gray with indent
```

### Visual Structure

Scripts are organized into clear sections with:

1. Emoji header showing platform (🍎 macOS, 🐧 Linux, 🍓 Pi, 🪟 Windows)
2. Version and last change info in gray
3. Logical sections for different setup stages
4. Sparkle emoji (✨) for completion message

## Important Implementation Notes

### Tool Installation Order

When installing tools that depend on package managers or shell configuration:

1. **Install package managers first** (Homebrew, fnm, pyenv)
2. **Apply dotfiles configuration** (chezmoi apply)
3. **Configure shell** (set default shell, install plugins)
4. **Install tools that require the configured environment**

This is critical because tools like fnm are initialized in shell configuration files deployed by chezmoi. Installing npm packages before the shell is configured will fail.

### Platform-Specific Considerations

#### Raspberry Pi Color Output

On Raspberry Pi, `printf` with format specifiers may not render ANSI color codes correctly. Use `echo -e` instead:

```bash
# May show raw escape codes on Pi
printf "\n%s🍓 Raspberry Pi Setup%s\n" "${BOLD}" "${NC}"

# Works correctly on Pi
echo -e "\n${BOLD}🍓 Raspberry Pi Setup${NC}"
```

#### Windows Unicode Support

Newer Unicode characters (like 🪟 window emoji from Unicode 13.0) may not display correctly in all Windows terminals. Use Nerd Font symbols instead:

```powershell
# May show as ?????? in some terminals
Write-Host "🪟 Windows Setup"

# More compatible approach
$windowsIcon = [char]0xf17a  # Windows logo from Nerd Fonts
Write-Host "$windowsIcon Windows Setup"
```

### Shell Integration Best Practices

When setup scripts need to use tools installed during the setup process:

1. **Source the appropriate initialization** for the current shell session
2. **Provide fallback instructions** if the tool isn't available
3. **Check tool availability** before attempting to use it

Example pattern for runtime-dependent installs:

```bash
# Try to initialize fnm for current session
if [ -f ~/.config/fish/config.fish ]; then
    eval "$(fnm env --use-on-cd)"
fi

# Check if npm is now available before installing Node-based tools
if ! command -v npm &> /dev/null; then
    print_warning "npm not found. Install Node-based tools after fnm is ready."
    return
fi
```

### Node.js and fnm Management

#### Key Learnings from Implementation

1. **fnm Installation with Chezmoi**: When using fnm with chezmoi-managed dotfiles:
   - Use `--skip-shell` flag during fnm installation to prevent it from modifying shell configs
   - Let chezmoi handle all shell configuration including fnm initialization

2. **Node.js Version Detection**: fnm behavior can be tricky:
   - `fnm current` returns exit code 0 even when no version is set (outputs "none")
   - `fnm list` may show only "* system" when no Node.js versions are installed
   - Always check the actual output content, not just exit codes

3. **Parsing fnm list Output**: The output format varies:
   - With versions: `* v20.11.0 default`
   - Without versions: `* system`
   - Use regex to specifically look for version numbers: `grep -E "^[[:space:]]*\*?[[:space:]]*v[0-9]"`

4. **Automatic Node.js Installation**: The scripts now:
   - Check if any real Node.js versions exist (not just system)
   - Install LTS automatically if none found
   - Set the first available version as default if none is set
   - Re-initialize fnm environment after setting default

5. **PATH Considerations**:
   - fnm installs to different locations on different platforms
   - Ubuntu/Pi: `~/.local/share/fnm`
   - macOS/WSL (via Homebrew): Managed by brew
   - Always use full path to fnm binary during initialization: `"$HOME"/.local/share/fnm/fnm`

#### Common Issues and Solutions

- **"fnm: command not found"**: PATH not set correctly, use full path to binary
- **"none" as current version**: No default set, need to run `fnm default <version>`
- **Only "system" in fnm list**: No Node.js versions installed, need to run `fnm install --lts`
- **npm not found after fnm install**: Need to re-source fnm env after installing Node.js

### pyenv Installation Handling

The pyenv installer will fail if `~/.pyenv` directory already exists. The scripts now handle this by:

1. Checking if the directory exists when `pyenv` command is not found
2. Attempting to fix PATH by adding `$HOME/.pyenv/bin`
3. If pyenv is found after PATH fix, continue normally
4. If not found, warn user that manual intervention may be required

This prevents the confusing situation where pyenv is partially installed but not functional.

### Interactive Prompts with curl|bash

When scripts are executed via `curl | bash`, stdin is the script content itself, not the terminal. This means `read` commands will get EOF immediately instead of waiting for user input.

**Solution**: Read from `/dev/tty` explicitly:

```bash
# Won't work with curl|bash - gets EOF immediately
read -r

# Works correctly - reads from terminal
read -r < /dev/tty

# For reading into a variable
read -r response < /dev/tty
```

This applies to any interactive prompt in the scripts (e.g., deploy key setup confirmation).

### SSH Commands Consuming stdin with curl|bash

When running scripts via `curl | bash`, SSH commands can consume the remaining script content from stdin, causing the script to exit prematurely with code 0.

**Problem**: `ssh -T git@github.com` reads from stdin by default. When stdin is the script content (via curl pipe), SSH consumes it, leaving nothing for bash to execute.

**Solution**: Redirect stdin from `/dev/null`:

```bash
# Will consume script content and cause early exit
ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"

# Fixed - prevents ssh from reading stdin
ssh -T git@github.com < /dev/null 2>&1 | grep -q "successfully authenticated"
```

**Symptoms of this bug**:

- Script exits with code 0 (success) but doesn't complete
- EXIT trap shows `$LINENO` as 1 (context reset)
- Happens consistently at the same point (first SSH command)

This fix has been applied to all SSH authentication checks in all setup scripts.

### Chezmoi Initialization Validation

Simply checking if `~/.local/share/chezmoi` exists is not sufficient to determine if chezmoi is properly initialized. The directory might exist but be empty or corrupted (missing `.git`).

**Solution**: Check for the `.git` subdirectory:

```bash
local chez_src="${HOME}/.local/share/chezmoi"

# Check if directory exists but is not a valid git repo
if [[ -d "${chez_src}" ]] && [[ ! -d "${chez_src}/.git" ]]; then
    print_warning "chezmoi directory exists but is not a git repository. Reinitializing..."
    rm -rf "${chez_src}"
fi
```

This prevents the "fatal: not a git repository" error during `chezmoi update`.

### Deploy Key Setup for Non-Main Users

The scripts support running dotfiles setup for users other than the main user (scowalt) via SSH deploy keys. This is more reliable than requiring personal access tokens.

**Architecture**:

1. **Deploy key generation**: `~/.ssh/dotfiles-deploy-key` (ed25519)
2. **SSH config alias**: `github-dotfiles` host that uses the deploy key
3. **Chezmoi initialization**: Uses `git@github-dotfiles:scowalt/dotfiles.git` instead of the default SSH URL

**How it works**:

```bash
# SSH config (~/.ssh/config) set up by bootstrap_ssh_config()
Host github-dotfiles
    HostName github.com
    User git
    IdentityFile ~/.ssh/dotfiles-deploy-key
    IdentitiesOnly yes

# Chezmoi init for non-main users
chezmoi init --apply --force "git@github-dotfiles:scowalt/dotfiles.git"
```

**User flow**:

1. Script detects no SSH/token access to dotfiles repo
2. Generates deploy key and displays public key
3. User adds deploy key to GitHub repo settings (read-only)
4. Script tests the key with retry loop
5. Chezmoi initializes using the `github-dotfiles` alias

## Development Practices

### Code Quality Tools

This repository uses automated tools to maintain code quality:

- **Shellcheck**: Validates all shell scripts for common issues and best practices
- **Markdownlint**: Ensures consistent markdown formatting
  - Configuration: `.markdownlint.json`
  - MD013 (line length) is disabled to allow long lines in documentation
- **Lefthook**: Manages git hooks for pre-commit and pre-push validation
  - Runs via `bunx` (preferred over `npx`)

#### ShellCheck Configuration

This repository is configured for maximum error detection with shellcheck:

**Configuration File**: `.shellcheckrc`

- `severity=style` - Catches all issues including style suggestions
- `enable=all` - Enables all optional checks
- `external-sources=true` - Follows external source files
- `check-sourced=true` - Validates sourced scripts
- `shell=bash` - Uses bash dialect by default

**Automated Validation**:

- **Pre-commit hook**: Validates staged shell scripts before commit
- **Pre-push hook**: Validates all shell scripts before push
- **Manual validation**: Simply run `shellcheck script.sh` - the `.shellcheckrc` handles all settings automatically

**Shell Script Standards**:

- Use `[[ ]]` for test conditions instead of `[ ]`
- Always brace variable references: `"${variable}"` not `"$variable"`
- Use `read -r` to prevent backslash mangling
- Separate command substitution for complex pipelines to avoid masking return values
- Quote all variable expansions to prevent word splitting

### Contained pre-push contracts

The contract hook uses `tools/run-pre-push-contracts.py` and the audited fixture runner above. It requires Linux, `/usr/bin/python3`, a C compiler and existing native Node, PowerShell, mise, Chezmoi and Bun executables. Discovery is limited to `/usr/bin:/bin`; when needed, supply absolute native paths through `SETUP_TEST_NODE`, `PWSH_BIN`, `SETUP_TEST_MISE`, `SETUP_TEST_CHEZMOI` and `SETUP_TEST_BUN` to `git push`. Shims and missing tools fail closed; no tools are installed. The hook runs every `tests/*.sh` contract plus direct containment, hook-dispatch, CLT, Homebrew-result and managed-skill regressions. Optional live integrations remain disabled. Use `env -i PATH=/usr/bin:/bin /usr/bin/python3 -I tools/run-pre-push-contracts.py --help` for the equivalent explicit-tool invocation.

### Commit Guidelines

- Always run shellcheck on modified shell scripts before committing
- **IMPORTANT**: Update script version numbers whenever making changes to any script
- Use descriptive commit messages that explain the "why" not just the "what"
- Include the robot emoji and AI attribution for AI-assisted commits

### Version Number Management

**Critical Rule**: Whenever you modify any setup script, you MUST update its version number.

Each script has a version number in its header that follows this pattern:

```bash
# Bash scripts (mac.sh, ubuntu.sh, wsl.sh, pi.sh, bazzite.sh)
echo -e "${GRAY}Version XX | Last changed: Description of change${NC}"
```

```powershell
# PowerShell scripts (win.ps1)
Write-Host "Version XX | Last changed: Description of change" -ForegroundColor DarkGray
```

**Steps for updating versions:**

1. Increment the version number by 1
2. Update the "Last changed" description to match your commit message
3. Keep it concise (one line describing the change)
