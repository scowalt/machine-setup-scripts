# bb desktop on headed machines

## Status

Task: TASK-49 (renumbered from TASK-48 when integrating remote main's independently allocated enrollment task). Implementation and parent review are complete. The user approved the scope recommendations, implementation in a BB subagent, and the Linux install-only success clarification below on 2026-09-28 ("Your spec is fine"). All 64 desktop fixtures pass on both available Python interpreters, and affected regressions and lint pass. PowerShell execution was unavailable; native macOS/Linux desktop rollout checks remain separate from this implementation.

## Approved scope

- Headed means the existing setup flag is not exactly `HEADLESS=1`; an SSH session or missing display environment does not change eligibility.
- Include personal and work machines.
- Install the official stable desktop release on Apple Silicon macOS and native Linux x64 Ubuntu/Bazzite. The Linux desktop remains upstream alpha.
- Explicitly skip unsupported Windows, WSL, Intel macOS, and Raspberry Pi/Linux ARM desktop installations. Do not substitute a browser shortcut, npm application server, or source build.
- Install/update on setup reruns, preserve newer installations, and defer replacement while the desktop app runs. Never stop it to update.
- Provide normal application-menu integration without launching the app, enabling autostart, authenticating providers, changing saved connections, or modifying existing bb server deployments.
- Leave existing installations untouched on headless runs; changing the flag is not an uninstall request.
- On eligible Linux, verified artifact/menu installation and current/newer preservation count as successful with an explicit warning that native GUI/sandbox launch compatibility remains unverified. Do not inspect global AppArmor policy or use a generic namespace probe as an installation veto. Actual artifact, runtime-baseline, safety and installation-verification failures remain fatal; security policy and the no-launch boundary stay unchanged.

## Upstream evidence

Checked on 2026-09-28:

- [Upstream README](https://github.com/get-bb/bb#download-the-desktop-app) identifies Apple Silicon macOS and Linux x64 AppImage as the desktop targets. Windows is a WSL server/browser workflow, not a native desktop target.
- [Desktop packaging configuration](https://github.com/get-bb/bb/blob/main/apps/desktop/electron-builder.config.json) identifies the stable application as `bb`, bundle ID `dev.bb.desktop`, and macOS minimum version 13.0.0.
- [Desktop documentation](https://github.com/get-bb/bb/blob/main/apps/desktop/README.md) documents Linux FUSE/extract-and-run behavior, native update ownership, signed/notarized macOS releases, and the unsigned Linux artifact.
- The [stable desktop feed](https://github.com/get-bb/bb/releases/tag/desktop-latest) currently contains 0.44.0 macOS arm64 DMG/ZIP and Linux x86_64 AppImage assets, with SHA-256 digests in GitHub release metadata. The implementation must resolve the current release rather than hard-code 0.44.0.
- Desktop is not a remote-only client: it bundles the bb runtime, normally uses `~/.bb`, and can attach to an existing compatible server. Installation must not execute it, probe it by launching it, or alter runtime ownership.

## Implementation plan

1. Add an explicit bb desktop step to all six setup entry points after their existing account/environment initialization. Keep eligible installation independent of optional Pi, Paseo, and bb server setup. Unsupported targets report why they are skipped; existing Windows/WSL headless rejection remains unchanged. Do not change flag loading semantics or existing environment files.
2. Implement standalone embedded helpers, keeping shared Bash policy identical wherever copied. Resolve only stable official release metadata and architecture-matched artifacts. Validate metadata, asset identity, transport destinations, and published digests before promotion. Stage privately and bound network operations. Do not weaken npm policy or install the npm bb server as part of desktop setup.
3. On macOS, stage and validate the official application bundle, its identity/version, and Apple signature/notarization before replacing a verified installation in a standard Applications location. On Linux, use an account-owned application location outside `~/.bb` and a desktop-menu entry; preserve the Bazzite system HOME alias. Keep the required glibc runtime baseline and use extract-and-run to avoid a FUSE dependency. Warn after a verified Linux installation/current/newer result that GUI/sandbox compatibility is untested, without inspecting or changing security policy or executing a launch/namespace probe.
4. Inspect installed identity/version rather than trusting filenames or a stale setup receipt, including installations updated by bb itself. Reuse verified standard installations when safe; preserve custom/nightly installations and refuse ambiguous destination ownership. Reject linked or malformed managed metadata/destinations, recheck running-app status before replacement, and preserve the prior installation on failed updates. Do not add a `bb` command that shadows the existing CLI.
5. Treat a verified running-app deferral as a clearly reported warning, not a successful update. Unsupported/headless skips are intentional. Actual download, integrity, safety, installation, or verification failures contribute to the final nonzero setup result while unrelated work and log finalization continue. Unknown running/ownership status is a safety failure, not an assumed safe deferral.
6. Add extracted-helper, inert-fixture coverage for eligibility across all scripts, personal/work flags, platform/architecture checks, release parsing, integrity rejection, first install, reruns, newer/self-updated versions, running-app deferral, path/ownership failures, rollback, caller result propagation, menu integration, and untouched server/user state. Test that desktop verification never launches bb or mutates live services. Include restricted/unknown AppArmor state, opaque per-app policy and absent/failing namespace-probe commands: none determines installation success, and only exact validated Linux success results receive the compatibility warning.
7. Update README with the support matrix, installation/update/deferral behavior, Linux alpha/prerequisite cautions, and manual first-launch/server-selection guidance. Correct the existing claim that all non-server machines use a browser only. Increment every modified setup script version and run lint plus affected regression contracts.

## Verification

- New `tests/bb-desktop-contract.sh` and focused Python fixtures; use temporary HOME trees, staged inert artifacts, and mocked platform/network commands only.
- `bash tests/bb-server-contract.sh` to protect the separate Ubuntu server contract.
- `bash tests/setup-reliability-contract.sh` and `python3 tests/test_homebrew_results.py` for result aggregation and macOS update behavior.
- `bash tests/headless-paseo-daemon-contract.sh` to protect existing eligibility/rejection paths.
- Bash syntax checks, ShellCheck on changed shell files, and Markdown lint on changed documentation.
- PowerShell parsing/wrapper fixtures when a compatible executable is available. `pwsh` and `PWSH_BIN` were unavailable during planning; native Windows behavior cannot be claimed from static checks alone.
- Native macOS installation/signature checks and native Linux menu/AppImage GUI launch remain explicit rollout verification. Do not run live setup, install/launch desktop, stop services, mutate fleet machines, or issue model requests during development.

## Boundaries

This change manages application installation, not bb configuration, remote access, login startup, telemetry preferences, plugins, provider credentials, or server lifecycle. It adds no opt-out beyond the agreed headless/platform rules and no new release-channel control. No ADR is needed: this is a reversible installation policy rather than a new hard-to-reverse architecture.
