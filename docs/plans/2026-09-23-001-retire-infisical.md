# Retire Infisical from machine setup

## Status

Implemented in the current worktree and tracked as Backlog TASK-43. The user approved the retirement scope, safety policy, and implementation plan on September 23, 2026. After Windows research, the user also approved including the actual official WinGet identity `infisical.infisical` alongside the former setup literal `Infisical.CLI`, using verified native installation records and WinGet removal without adding PowerShell 7 or another module. See [Windows inventory research](2026-09-23-002-winget-retirement-inventory.md) for historical evidence. Offline fixtures pass; native Windows registry redirection, ACLs, and WinGet removal remain unverified on a Windows host.

This uses the existing **retired managed tool**, **managed footprint**, and **incomplete setup run** vocabulary in `CONTEXT.md`. It follows the preservation boundary in [Keep cleanup for retired managed tools](../adr/0001-keep-cleanup-for-retired-managed-tools.md). No new domain term or ADR is needed.

## Why

The uploaded `scott-beelink-ubuntu/2026-09-23-13-06-19-721.log` identifies its local run as `2026-09-23-090536.log`, using Ubuntu setup version 264. Its initial `apt-get update` fails because the configured Infisical Cloudsmith source returns HTTP 404. System upgrades are skipped, and the run correctly finishes as incomplete.

[Infisical's migration notice](https://infisical.com/docs/cli/cloudsmith-migration) says Cloudsmith stopped serving the CLI repository on September 16, 2026. The user no longer needs Infisical on any machine, so migrating to the replacement repository is not the desired outcome.

The same run separately reports `Paseo Muse diagnostic: inventory-environ: EACCES.` That investigation is outside this change; removing Infisical will not resolve that independent safety block.

## Approved outcome

- Every platform's future setup runs retire Infisical on personal and work machines. Retirement does not depend on the current `WORK_MACHINE` value or on finding `infisical` on PATH.
- Stop installing or updating Infisical through setup. Remove verified existing installations and Infisical-specific package sources within the known managed footprint.
- Run APT source retirement before package-list updates so the dead repository cannot keep blocking unrelated system updates. A stale repository must be handled even when the CLI is already absent.
- Work machines receive no replacement secrets manager. Preserve existing personal-machine Doppler behavior and any existing work-machine Doppler installation.
- Retain idempotent retirement on later setup runs, rather than providing only a one-time migration.
- Roll out through each machine's next setup run only. No immediate host cleanup, remote fleet operation, or deployment is authorized.

## Removal and preservation boundaries

The approved recognized installation footprint is:

| Platforms | Managed installation mechanism |
| --- | --- |
| Ubuntu, WSL, Raspberry Pi | APT package `infisical` and the Infisical repository |
| macOS, Bazzite | Homebrew formula `infisical/get-cli/infisical` and its dedicated tap |
| Windows | Verified official WinGet registrations for `Infisical.CLI` and `infisical.infisical` |

Use verified native package-manager identities for removal; an executable's name or PATH location alone is not deletion authority. Do not recursively search HOME or delete an arbitrary binary named `infisical`.

Preserve manually downloaded binaries, custom installations, and installations outside the recognized footprint. Report manual cleanup needed when one is detected; do not claim that every possible Infisical copy is absent. This exception does not excuse a failed or unverified cleanup of the managed footprint.

Preserve credentials, login state, `.env.local`, project files, and unrelated configuration. Do not revoke tokens, call Infisical account APIs, remove hosted secrets, or edit shell startup files.

Remove only attributable Infisical package-source entries. Preserve unrelated entries in shared repository files, shared signing keys, unrelated taps, dependencies, and other packages. Dedicated tap/key cleanup must not remove resources still used elsewhere. Reject unsafe or ambiguous metadata rather than guessing ownership, following linked configuration paths, or deleting whole shared files.

Do not migrate to the replacement Infisical repository, install a replacement CLI, force dependency removal, or perform broad purge/autoremove cleanup as part of retirement. Do not add a new privilege-escalation mechanism or weaken permissions to make removal succeed.

## Approved Windows inventory direction

- Use bounded, read-only native portable-installation records accessible from existing Windows PowerShell 5.1/.NET, not an unprovisioned `Get-WinGetPackage` cmdlet. Do not add a runtime or module.
- Include both approved package IDs. Validate the exact native registration, official source identity, installer type, account/machine scope, registry value types, and relevant registry views. Do not infer authority from display names, PATH, or arbitrary uninstall strings. Do not enumerate other users or broadly scan the registry/filesystem.
- A fully readable absent set of the recognized native records is an idempotent no-op even when the optional inventory module is absent. Unreadable, malformed, conflicting, or unsupported relevant records remain incomplete rather than being mistaken for absence. Preserve and report custom/unrecognized installations.
- Preflight all candidates before removal. For an authorized native record, verify the configured official WinGet source and invoke native WinGet removal targeted to its verified identity and scope. Explicitly preserve portable-package data; do not use force, purge, broad version selection, source reset, or registry-command execution.
- Require successful native removal and an independent native-record postcheck. Preserve failure even if a subsequent inventory is empty. Do not accept localized list output, a list exit code, or an empty export as independent proof of absence: WinGet can downgrade source-search failures to warnings.
- Exercise the interface with isolated native-record/command fixtures. Linux PowerShell mocks do not prove real Windows registry, installer, or privilege behavior; report that limitation.

## Failure behavior

A failed uninstall, failed post-removal verification, or unsafe/unverified managed repository cleanup makes the setup run incomplete. Continue unrelated work where safe, retain the failure through later successful steps, and finalize/upload the log with a nonzero result.

Distinguish verified absence from unavailable package inventory. Report actionable, secret-free diagnostics and any preserved custom installation that needs manual attention. Never log credentials or environment contents.

If repository cleanup cannot be completed safely, do not conceal or reinterpret a later APT failure as success.

## Approved implementation plan

1. Add extracted-function and caller-level fixtures reproducing the stale Infisical source failure, including the CLI-already-absent case. Use temporary filesystem roots and inert package-manager commands.
2. Add idempotent native retirement for the recognized APT, Homebrew, and WinGet installations and associated source configuration. Preflight ownership and preservation boundaries, verify removal, and report controlled failures.
3. Wire retirement into all six scripts before relevant package update phases. Remove Infisical installation branches and obsolete trust enrollment while preserving personal-machine Doppler behavior and installing no work-machine replacement.
4. Aggregate retirement failures through each platform's final setup result and log finalization. Preserve independent work, including existing Paseo safety checks.
5. Update setup version banners, README behavior, and affected contracts. Run targeted retirement tests, relevant reliability and Homebrew result tests, ShellCheck, and available PowerShell fixtures. Review the final diff against this spec.

## Verification

Tests must use extracted helpers, temporary fixtures, and mocked package-manager/lifecycle commands. Never execute full setup scripts, perform a live uninstall, modify real APT/Homebrew/WinGet state, restart a daemon, or operate on a remote machine to validate this change.

Required cases:

- Both machine classifications across all six platforms retire Infisical without reinstalling it.
- No Infisical installation or source is an idempotent no-op; repeated retirement remains safe.
- The CLI is absent but the old APT source remains: source retirement happens before update and unrelated sources survive.
- A verified installed package is removed through its native manager, and its absence is verified.
- Personal-machine Doppler behavior is unchanged; work machines install no replacement and preserve existing Doppler.
- Custom binaries, credentials, project files, environment files, unrelated packages, and shared source/key data remain unchanged.
- Linked, malformed, ambiguous, or unverifiable managed metadata fails safely without destructive fallback.
- Uninstall failures, missing privileges, unavailable inventory, and failed postchecks propagate to a nonzero final result after unrelated work and log finalization.
- No new Infisical repository, network account action, daemon lifecycle action, or live package mutation occurs in tests.

Use `bash tests/setup-reliability-contract.sh` and `python3 tests/test_homebrew_results.py` for affected Homebrew/result wiring, plus the new retirement contract and relevant existing platform fixtures. ShellCheck every modified Bash script. PowerShell is not currently on PATH and `PWSH_BIN` is unset; locate an existing test runtime if available, otherwise report Windows wrapper coverage as blocked. Linux PowerShell fixtures do not establish native Windows uninstall behavior.
