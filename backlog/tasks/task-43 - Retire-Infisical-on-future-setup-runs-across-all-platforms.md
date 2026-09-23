---
id: TASK-43
title: Retire Infisical on future setup runs across all platforms
status: Done
assignee:
  - '@pi'
created_date: '2026-09-23 13:28'
updated_date: '2026-09-23 22:12'
labels: []
dependencies: []
references:
  - ubuntu.sh
  - pi.sh
  - wsl.sh
  - mac.sh
  - bazzite.sh
  - win.ps1
documentation:
  - docs/plans/2026-09-23-001-retire-infisical.md
  - docs/plans/2026-09-23-002-winget-retirement-inventory.md
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Infisical is no longer needed on any machine. Its retired Cloudsmith APT repository now breaks Ubuntu package-list updates. Apply the user-approved retirement policy through future setup runs only, without migrating repositories or replacing Infisical on work machines. Preserve credentials, project data, custom installations, and personal-machine Doppler behavior; keep the separate Paseo process-inventory failure out of scope.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 All six setup scripts stop installing Infisical and idempotently remove verified installations in the recognized native package-manager footprint on both personal and work machines.
- [x] #2 Infisical-specific APT sources are safely retired before package-list updates, including stale-source-only machines; unrelated repository entries, shared keys, taps, packages, and dependencies are preserved.
- [x] #3 Custom or unrecognized installations are preserved and reported for manual cleanup; credentials, login state, environment files, shell configuration, project files, and hosted secrets remain unchanged.
- [x] #4 Work machines receive no replacement secrets manager; personal-machine Doppler behavior and existing work-machine Doppler installations remain unchanged.
- [x] #5 Failed or unverified managed cleanup and failed postchecks produce an incomplete nonzero setup result after safe unrelated work and log finalization, without privilege or permission bypasses.
- [x] #6 Version banners and documentation reflect retirement, and isolated helper/caller regression tests, affected reliability/Homebrew suites, ShellCheck, and available PowerShell coverage pass with platform limitations documented; no live setup or fleet changes occur.
- [x] #7 Windows retirement covers verified official native registrations for both Infisical.CLI and infisical.infisical using existing PowerShell 5.1/native installation records and targeted WinGet removal, without installing a runtime or module; readable absent records are a no-op, unsupported or unverified records fail safely, portable data is explicitly preserved, and independent postchecks retain removal failures.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Approved by the user on 2026-09-23 with an explicit implementation handoff in the current workspace/worktree.

1. Add failing extracted-helper/caller fixtures for stale Infisical APT sources, including an already-absent CLI.
2. Implement verified, idempotent native retirement for APT, Homebrew, and WinGet with preservation and post-removal checks.
3. Wire retirement before relevant updates in all six scripts; remove installation paths, preserve personal Doppler behavior, and add no work-machine replacement.
4. Preserve cleanup failure through unrelated work and final log/status handling.
5. Update versions/docs/contracts; run isolated retirement, reliability/Homebrew, ShellCheck, and available PowerShell fixtures; report native platform limits.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
User approved retirement, no replacement on work machines, next-setup-only rollout, preservation/reporting of custom installations, and failed-result aggregation for unsafe or failed managed cleanup. Recorded scope in docs/plans/2026-09-23-001-retire-infisical.md. Bash, Python, Node, ShellCheck and Backlog are available; pwsh is not on PATH and PWSH_BIN is unset. No live machine changes or implementation performed.

User explicitly requested: implement in the current workspace / worktree using paseo-handoff. Implementation approval is complete; do not request another approval of this plan. Handoff uses the configured Implementor profile in workspace wks_1e98e6d0b4bdb623. Planning artifacts are uncommitted; setup scripts are still unchanged.

Initial implementation handoff returned after inspection without code changes or tests and without identifying a concrete implementation blocker. Continuing the same agent with staged fixture-first work; incomplete work-in-progress is permitted, but no live cleanup or weakened safety guarantees. Missing PowerShell runtime remains a verification limitation rather than a blocker to all implementation.

Added an offline extracted-helper APT source test (shared .list, repeat run, mixed Deb822, linked candidate, preflight). Red phase: helper absent; implementing it next.

- Added extracted APT source tests (red before helper, now green), native APT/Homebrew mocked removal contracts, and safe pre-update calls on Ubuntu/Pi/WSL. Removed obsolete install branches in all six scripts; added native Homebrew and Windows retirement with final error aggregation. Reliability/Homebrew suites and ShellCheck pass so far. Continuing safety review, documentation and platform contracts; no live cleanup was performed.

- Safety review: APT preflights root-owned no-follow source trees/files, exact official URLs, mixed Deb822 refusal, stable inode rechecks, mode/owner preservation and xattr refusal; confirms exact package removal simulation before native remove. Windows uses typed Get-WinGetPackage exact-ID/source inventory and skips upgrades/reboot-capable updates after failure. Homebrew skips upgrades on failed retirement. Added repeat, symlink, mixed sources, xattr, failure/postcheck and Linux PowerShell WinGet mocks. Native Windows remains unverified; installed typed inventory cmdlet is required (absence fails closed). No live package managers touched.

Orchestrator verification: existing 23 retirement/Homebrew tests pass, but isolated review probes reproduced three gaps: (1) a mixed Deb822 URIs continuation containing the official Infisical URL returns success with the stale URL intact; (2) an occupied `.infisical-retirement-PID-sources.list` is deleted when O_EXCL fails; (3) APT plans with one Remv infisical plus Inst/Conf unrelated are accepted and invoke removal. Vendor installer uses <https://artifacts-cli.infisical.com/deb> (no trailing slash), which the new /deb/ matcher also misses. Windows now unconditionally requires Get-WinGetPackage despite no Microsoft.WinGet.Client provisioning in setup, risking failures on otherwise supported WinGet-only machines. Reopened affected criteria and cleared completion summary pending remediation; no live package operation performed.

- Reproduced review defects with failing extracted-helper tests (folded/mixed Deb822 URI, occupied temp deletion, replacement /deb URL, Inst/Conf/unknown simulated package actions). Implemented folded URI validation, exact replacement URL, owned temp cleanup and stable recheck, and a conservative APT simulation parser. Actual removal now uses targeted dpkg --no-triggers --remove infisical, which cannot re-plan unrelated removals. Linux retirement tests currently green (21); investigating native WinGet CLI inventory and expanding caller/log fixtures next.

- Review fixes: demonstrated nine red regressions, then passed 23 isolated retirement/caller tests. Deb822 folded URIs (both orders/multiple lines/duplicate fields) now fail safely or remove only exclusively official stanzas. Replacement /deb and /deb/ exact host recognized. Occupied temp inode preserved; pre-rename identity rechecked. APT simulation now rejects Inst/Conf/unknown actions, and targeted dpkg --no-triggers --remove infisical prevents apt-get replanning unrelated package removals. Caller-level extracted run_setup_tasks/main seams exercise failure-to-log on Ubuntu/Pi/WSL/Bazzite, both WORK_MACHINE values, plus Windows extracted initializer/catch/finally with inert transcript and real secrets-manager classification. Linux PowerShell WinGet mock also rejects malformed metadata. Tests: 23 Python retirement/caller, 8 Homebrew, setup-reliability with PWSH_BIN, inert PowerShell retirement fixture, ShellCheck five scripts, bash -n, git diff --check all pass. No live setup/package state touched.
- BLOCKED (#1/#6): Stock winget does not have a complete machine-readable installed inventory: Microsoft export docs say unmatched installed apps are omitted (with warning), and list is human table only; optional Get-WinGetPackage is not provisioned, and Microsoft WinGet issues report Windows PowerShell 5.1 runtime incompatibility. Thus default WinGet-only absent-machine currently fails closed even without Infisical; task cannot be marked Done. Need a supported PS5.1 WinGet-installed inventory API with verified absence, or explicit approval to add a compatible narrowly scoped prerequisite/change Windows host requirements. Preserving current fail-closed Windows path; README/plan document limitation.

- Added red-to-green xattr race regression: source xattr acquired between preflight and replacement was previously erased. Recheck now binds device/inode/size/mtime/ctime/mode/owner/nlink and xattrs; changed temporary-path symlink replacement is retained rather than unlinked. 25 Python offline tests now cover these races. Windows remains deliberately incomplete on default WinGet-only hosts: Microsoft export docs (<https://learn.microsoft.com/en-us/windows/package-manager/winget/export>) explicitly omit apps not matched to a source; list docs show no machine-readable inventory (<https://learn.microsoft.com/en-us/windows/package-manager/winget/list>); WinGet issue <https://github.com/microsoft/winget-cli/issues/3842> reports Get-WinGetPackage Windows PowerShell 5.1 type-load failure. Neither an empty JSON export nor localized list output proves absence. Need decision on a verified Windows PowerShell 5.1-compatible native inventory or a narrowly scoped prerequisite/host migration; no silent fallback or Done status.

Review follow-up: 33 Python retirement/caller/Homebrew tests pass. An isolated native APT simulation using only a temporary status database/config (no network, scripts or live package state) produced an ordinary unused-auto-package advisory before Remv infisical; the current strict prose allowlist rejects this safe removal. Sending that compatibility regression to Implementor while a separate Planner/Orchestrator researches primary WinGet exact-ID/source query and native exit-code semantics, avoiding a premature new-runtime/manual-only design choice.

- APT compatibility slice (Windows code untouched): first reproduced the user-provided exact isolated apt-get -s autoremove-advisory stdout as a red extracted-wrapper regression on Ubuntu/Pi/WSL, plus a red newer Solving dependencies/plural-advisory case. Added a bounded advisory state that accepts only native singular/plural advisory headers, indented package-name tokens and matching apt autoremove footer; no autoremove is executed. Neutral Solving dependencies progress is accepted. Every other action/unknown line still fails before targeted dpkg --no-triggers --remove. Added malicious Inst/Conf/Remv-in-advisory, missing footer, mismatched summary cases. 29 extracted retirement/caller tests, 8 Homebrew result tests, reliability contract with PWSH_BIN, Linux PowerShell mock, ShellCheck five scripts, bash -n and git diff --check passed. Copies of APT wrapper synchronized. Task remains In Progress pending independent Windows inventory design; no live package state touched.

Primary-source Windows research completed in docs/plans/2026-09-23-002-winget-retirement-inventory.md. Exact list/export results cannot alone prove absence because native WinGet tolerates source-search failures. A bounded PS5.1-native portable registry inventory plus native WinGet removal is a candidate that avoids a new runtime/module. Official manifests identify infisical.infisical, whereas prior setup/spec use Infisical.CLI; requesting explicit confirmation before expanding the recognized Windows identity set. No Windows changes or live native validation were made by the researcher.

User approved the recommendation to include infisical.infisical alongside Infisical.CLI and use verified native records plus native WinGet removal, without adding PowerShell 7 or another module. Updated approved spec with bounded native-record inventory, source/identity/scope validation, portable --preserve semantics, independent postcheck, and native Windows verification limits. Sending the existing Implementor the research-backed direction; no further approval is needed for this scope.

- Implemented approved Windows portable-record path without PowerShell 7/module: read-only exact native HKCU shared, HKLM 64/32 logical uninstall keys for both approved IDs; validate REG_SZ identity/source/portable/uninstall-string fields; all candidates preflighted. Verified official winget source JSON only before native uninstall by exact product-code/scope with --preserve, then independent record postcheck; absent inventory succeeds offline. New isolated in-memory registry + inert WinGet fixture first failed on old module gate, now covers both IDs, no-op/rerun, user/machine views, ambiguous/corrupt/custom registrations, substituted/bad source, signed no-applications HRESULT and other errors, lingering/unreadable postcheck, and caller log boundary. No registry or native WinGet action ran. Native Windows registry redirection and uninstall still require on-Windows verification; finishing review/test matrix.

- Final review: Windows portable record adapter uses RegistryKey.OpenBaseKey/OpenSubKey (read-only), exact HKCU shared/HKLM 64/HKLM 32 logical paths for both approved product codes, REG_SZ native ID/source/type/uninstall-string fields, complete preflight before writes, official source export JSON tuple, native product-code/scope uninstall with --preserve, immediate exit-status capture and independent inventory postchecks. No optional module/runtime or localized table parser. Fixture covers WinGet-only absent success, both IDs and scopes/views, conflict/malformed/source substitution, native failure/HRESULT, timeout exception, lingering and unreadable postchecks, native caller log and work/personal behavior; native Windows registry and WinGet behavior cannot be verified from Linux. Full checks: 29 retirement/caller Python, 8 Homebrew Python, setup reliability with Linux pwsh, isolated PowerShell registry/WinGet fixtures, ShellCheck all five Bash scripts, bash -n and git diff --check passed. No live setup, registry writes, WinGet uninstall or fleet change.

Final orchestrator review independently passed 37 Python retirement/caller/Homebrew tests, setup reliability with /tmp/pi-shared-runtime-pwsh.2SlAPL/pwsh, extracted PowerShell fixtures, ShellCheck all five Bash scripts, Bash syntax and diff checks. Checked native Microsoft source to confirm compact single-line source-export JSON and portable REG_SZ fields/uninstall-string format. One packaging follow-up: existing pre-push discovers only tests/*.sh, so add a shell contract entry point for the new Python/PowerShell fixtures. Update the approved plan status, which still says In Progress. No new behavioral scope or live mutation is needed.

- Packaging follow-up: added tests/infisical-retirement-contract.sh (Version 1) so lefthook pre-push tests/*.sh executes all three extracted Python retirement modules and, when available, inert PowerShell registry/WinGet caller fixtures. Explicit skip without PowerShell and failure for an invalid supplied PWSH_BIN. README recommends entry point; approved plan status now says implemented with native Windows verification limitation. PWSH_BIN=/tmp/pi-shared-runtime-pwsh.2SlAPL/pwsh bash tests/infisical-retirement-contract.sh passed (29 Python tests and PowerShell fixture); PATH=/usr/bin:/bin PWSH_BIN= bash tests/infisical-retirement-contract.sh passed with explicit PowerShell skip; shellcheck and bash -n on runner and git diff --check passed. No live setup or package mutation.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Retired Infisical on future setup runs across Ubuntu, Pi, WSL, macOS, Bazzite and Windows. APT sources are preflighted and retired before updates; exact package removal refuses unrelated simulated actions and uses targeted dpkg removal. Homebrew removes only its verified formula. Windows uses read-only native portable registrations for the approved Infisical.CLI and infisical.infisical IDs, validates official source metadata and calls targeted WinGet uninstall with explicit --preserve; readable absence succeeds without a PowerShell module. Work machines get no replacement, personal Doppler remains, unsafe or failed cleanup reaches the final nonzero result/log.

Tests: 29 isolated Python retirement/caller tests; 8 Homebrew tests; setup reliability with Linux PowerShell; inert PowerShell native-registry/WinGet and caller fixtures; ShellCheck, Bash syntax, git diff check. No live setup/package/registry operation. Native Windows registry mapping, ACLs, source export and WinGet uninstall still need Windows verification; Linux PowerShell mocks do not establish native behavior. Unknown manual or nonportable installations are preserved for review.

Packaging: added Version 1 tests/infisical-retirement-contract.sh to the existing tests/*.sh pre-push suite, with explicit PowerShell skip and PWSH_BIN fixture support. Updated README and plan status. Runner passed with Linux PowerShell and with explicit skip when unavailable; ShellCheck, Bash syntax and diff checks passed. Native Windows execution remains unverified.
<!-- SECTION:FINAL_SUMMARY:END -->
