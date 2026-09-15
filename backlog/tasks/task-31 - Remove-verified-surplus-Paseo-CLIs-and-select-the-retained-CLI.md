---
id: TASK-31
title: Remove verified surplus Paseo CLIs and select the retained CLI
status: Done
assignee:
  - '@pi'
created_date: '2026-09-14 23:56'
updated_date: '2026-09-15 01:59'
labels:
  - bug
  - setup
  - paseo
dependencies: []
references:
  - ubuntu.sh
  - tests/test_paseo_plain_setup.py
  - tests/headless-paseo-daemon-contract.sh
  - CONTEXT.md
  - 'https://logs.scowalt.com/logs/arcane/2026-09-14-23-12-59-427.log'
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Arcane selects npm/mise Paseo CLI 0.4.0 on PATH while its setup-managed Bun daemon runs 0.8.0. Plain fails before its compatibility check because the old CLI rejects plugin settings. The user approved cleaning verified redundant global installations only after validating the retained CLI, plus explicit validated CLI selection so cleanup or unrelated setup failures cannot leave Plain using a shadowing executable.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Define surplus installations by verified official @getpaseo/cli package identity and known user-global package-manager footprint, not age, version, or PATH absence alone. Validate a retained CLI before any removal. Preserve unrelated unscoped paseo, Desktop bundles, project/source/custom installations, other packages, and all PASEO_HOME data.
- [x] #2 Remove only verified surplus copies and their verified package-manager command entries during eligible future setup runs. Preserve existing native Linux headless gates, macOS canary, Windows/WSL headless rejection, beta/stable selection, and custom-home ownership constraints. Uncertain or unsafe candidates remain unchanged with controlled diagnostics.
- [x] #3 Plain explicitly uses a validated retained CLI rather than blindly trusting PATH, including when Go failure skips managed-daemon installation. Verify compatibility before configuration-sensitive status calls, preserve correct local-home and endpoint selection, and never start another daemon or change plugin source/preferences as selection recovery.
- [x] #4 Before removal, account for running processes and running or stopped service references. Coordinate restart only for a proven setup-managed local service, verify a stopped interval before removing code in use, and restore its owner after failure. Defer Desktop, custom/unknown owners, and setup inside the affected daemon. Never remove an installation still referenced by a preserved service.
- [x] #5 Offline temporary fixtures prove Arcane-style CLI shadowing, idempotent cleanup, retained CLI failure, metadata/link attacks, source/data preservation, process/service reference protection, restart failure recovery, channel/platform gates, and Plain selection when Go fails. No live setup, daemon changes, model requests, SSH rollout, or fleet cleanup during development.
- [x] #6 Keep shared helpers identical across applicable scripts, increment affected setup versions, document cleanup boundaries and diagnostics, and pass affected Plain/native fixture isolation, headless, Muse, release-channel, Go/wiring, and runtime contracts and lint with available PowerShell coverage.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Add isolated fixtures that reproduce old npm/mise CLI shadowing a retained Bun CLI, including the path where Go failure skips managed-daemon installation. Cover unknown candidates, unsafe metadata, protected sources/data, and active/stopped service references before implementation.
2. Introduce a verified retained-CLI selection boundary for Plain and eligible headless setup. Check package identity, trusted paths, release compatibility, and the correct local home without trusting PATH order or starting another daemon. Keep the embedded Plain installer identical across all six scripts.
3. Add bounded surplus discovery for known account-owned global package-manager layouts, including default npm/mise Node and Bun layouts. Do not recursively search HOME or remove custom/project/Desktop/system installations. Prune only after retained-CLI validation and ownership preflight, within existing standalone-daemon platform/HEADLESS gates. Reuse the stronger managed-service ownership/stopped-interval/restoration checks for any necessary restart, and defer unsafe or self-hosted changes.
4. Update applicable versions and documentation. Run cleanup/selection fixtures plus Plain, Git-isolation, headless, Muse, release-channel/system-HOME, Go/wiring, shared-runtime, and available PowerShell contracts, then lint and self-review. Record limits. No live cleanup, remote inventory, daemon operations, model requests, or publication. Implementation awaits approval of this plan.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
User approved verified-surplus removal, protected installation/data boundaries, restricted service restarts, and explicit validated CLI selection. Read-only code review confirmed no current general Paseo duplicate cleanup. Managed standalone installs use Bun under native Linux headless/macOS canary gates. Plain independently selects the first executable on PATH and runs configuration-sensitive status before version checks, so deletion alone cannot ensure correct selection.

User approved implementation. Beginning offline retained-CLI/cleanup regression fixtures while TASK-30 runs in parallel. No live setup, remote cleanup, or model requests in fixtures.

Reproduced the exact Plain failure with an extracted installer and a shadowing CLI: daemon status: exit-1. Added metadata-verified CLI selection, with known Bun/explicit selection protected from incompatible fallback. All 40 Plain fixtures pass with portable PowerShell.
Added 15 temporary cleanup fixtures, including native npm --offline --ignore-scripts removal, candidate preflight, retained CLI failure, idempotence, stopped service/wrapper references, system masked units, unknown running processes, and custom/project/Desktop preservation. Cleanup is called only after existing eligible managed-service convergence and health validation. It performs no independent restart and defers all still-referenced installations.

Safety review found and reproduced blockers beyond the first suite: npm string-form bin normalization could remove an unrelated cli command; Bun cache hardlinks were rejected; the trusted /home alias was rejected by symlink mode; global user service paths and linked drop-ins were missed; pathless native Paseo process titles always deferred cleanup. Added failing fixtures then fixed each. Cleanup now uses native systemd unit-path discovery, rejects ambiguous bin footprints, accepts installed cache hardlinks without touching credential validation, validates retained service ownership before exempting native titles, and rechecks metadata after external reference probes.
23 cleanup fixtures and 43 Plain fixtures pass. Added actual extracted main-flow coverage showing Go failure still reaches the verified Plain CLI, and actual headless-function coverage showing CLI/restart/health failures never invoke cleanup. The full 31 Bash suites passed before these final review fixes and will run again after integration.

Final review hardened runtime provenance: cleanup checks candidate references in cwd/environment before exemptions, fully matches the wrapper exec line, treats the verified Node binary as an executable boundary, and supports the actual CLI -> supervisor -> worker tree with per-process validation. Added Linux and mocked Darwin positive/negative fixtures; 29 cleanup tests now pass.
The managed wrapper exports PASEO_SETUP_CLI bound to its exec path. A read-only verify-owner mode reuses the stronger Muse ownership checks before any headless install/update, including unchanged profiles, so the provenance wrapper upgrade cannot bypass Desktop/unknown/custom/self-hosted safety. Exact old/new wrapper formats remain supported for migration. Muse and headless/provenance suites pass. One final full sweep found only a WSL explicit-sync source-pattern mismatch; restoring the existing default sync call fixes it, and AI/Muse reruns pass.

Final review confirmed the missing-PID owner-verification blocker is resolved. Native service state now prevents approval of active renamed owners and hidden cgroup leftovers when PID metadata is absent. Cleanup introduces no independent restart: provenance-wrapper migration uses the existing guarded owning-service update/recovery flow; cleanup never runs after failed convergence or removes a still-referenced installation. All 31 Bash suites and explicit PowerShell channel/model/Telegram suites passed with optional native fixture modules. No remaining blocker in the reviewed path. No live cleanup, deployment, or commits.

Final lint exposed why the WSL caller used explicit sync: its shared helper has a mode argument but WSL has no verify-owner caller, so ShellCheck flags an implicit-only call. Restored explicit sync and taught the AI ordering assertion to accept that equivalent form. Rechecking lint and affected fixtures before closing again.

The WSL explicit-sync lint correction and matching static ordering assertion pass. Final ShellCheck covers all modified Bash scripts and contracts; Markdown lint, whitespace, AI-agent, Go wiring, and native-module Muse reruns pass. TASK-31 is complete with the documented platform limits.

Also scanned full contents of all changed and new files (2.64 MB). Gitleaks identified one unchanged baseline false positive at bazzite.sh:26-27: two empty variable initializers. Verified those lines against HEAD and rescanned with a HEAD-generated baseline; no new leaks remain. No scanner exclusions or unrelated code changes were added.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Prevent stale Paseo CLIs from shadowing the retained CLI and remove only verified surplus installations.

- Plain inspects package identity, paths, and compatibility before status calls. Prefer a validated or managed Bun CLI over PATH, including after Go failure. Preserve incompatible managed release selection without falling back to an older copy.
- After eligible managed-service convergence and health checks, inspect known account-owned npm/mise installations and remove only verified unreferenced copies through offline native npm with lifecycle scripts disabled. Preserve custom/project/Desktop/system installations, unrelated packages, and all daemon/plugin data.
- Verify native service ownership before updates even when profiles are unchanged. Bind wrapper launch provenance to the executed CLI and inspect the actual CLI/supervisor/worker tree, runtime references, and active/stopped service definitions. Defer uncertain, linked, custom, self-hosted, or in-use cases. Cleanup adds no independent restart and retains surplus code after failed service recovery.
- Preserve platform/channel/canary gates, native HOME aliases, Bun cache hardlinks, and strict command footprints. Update versions, glossary, documentation, and tests.

Validation: 29 cleanup fixtures, 43 Plain fixtures, native migration/Git isolation, Muse and headless/provenance fixtures pass. All 31 Bash contracts and explicit PowerShell channel/model/Telegram suites pass. Lint, whitespace, secret scan, and independent safety review pass.

Limits: macOS ownership behavior is mocked, not live-tested. No native Windows provisioning or cleanup rollout occurred. Changes remain local and uncommitted.
<!-- SECTION:FINAL_SUMMARY:END -->
