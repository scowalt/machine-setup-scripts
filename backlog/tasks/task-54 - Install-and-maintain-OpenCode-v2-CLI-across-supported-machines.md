---
id: TASK-54
title: Install and maintain OpenCode v2 CLI across supported machines
status: Done
assignee:
  - '@pi-agent'
created_date: '2026-09-28 21:18'
updated_date: '2026-09-29 00:00'
labels: []
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Reintroduce the OpenCode CLI as a managed tool distinct from the existing Pi OpenCode Go provider. Approved scope: CLI/TUI-only installation on personal and work machines across all six entry points; headless installation on supported macOS/native Linux runs; latest stable 2.x updates; safe migration of positively identified official v1 installations; installation-only scope. Explicit user-approved exception: Windows/WSL HEADLESS=1 runs retain the existing whole-setup early rejection and are exempt from OpenCode installation. Do not move the rejection or add pre-rejection provisioning.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Setup selects the latest stable 2.x release, verifies the installed version, and neither silently advances to v3 nor downgrades a newer existing release.
- [x] #2 Positively identified official v1 installations migrate automatically while preserving credentials, configuration, sessions, and projects; custom or uncertain installations remain untouched with a reported conflict.
- [x] #3 Setup does not launch the TUI, enable a service, authenticate, select a model, install OpenCode-specific skills, change shell configuration, or alter existing Pi Go credentials, Muse profiles, and Pi defaults as part of OpenCode CLI installation.
- [x] #4 Required installation, migration, and verification failures reach the final failed setup result while unrelated work and log finalization continue.
- [x] #5 Documentation and retirement assertions reflect the new policy, modified scripts have incremented versions, and isolated fixture contracts plus affected regressions and lint pass without running live setup or making model requests.
- [x] #6 All six setup entry points install or update the official OpenCode CLI on supported native architectures on personal and work machines, including supported headless macOS/native Linux runs. Windows/WSL HEADLESS=1 retain the existing whole-setup early rejection and are exempt from installation. Unsupported native architectures warn and skip without source compilation.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Add isolated fixtures for release selection, native architecture/CPU variants, fresh/repeated installation, v1 migration, newer/custom copies, unsafe paths, and failure propagation. All downloads, package managers, and version probes are inert test fixtures; never source full setup scripts or run the real application.
2. Add identical shared Bash installation policy and an equivalent native PowerShell implementation. Resolve official stable 2.x metadata with strict package/version validation, stage the matching official native artifact, validate its contents and integrity where published, and verify only --version in an isolated environment before promotion. Prefer per-user native binaries in the existing user-local command directory; do not execute npm lifecycle scripts or change npm security/shell policy.
3. Preflight recognized legacy standalone/Homebrew/npm/Bun installations and command resolution before mutation. Migrate only verified official copies, stage the replacement before removing the old package, preserve all application data, and retain/recover the previous working binary on failed promotion. Preserve pinned, custom, linked/unsafe, newer-major and uncertain installations; report blockers without claiming successful migration. Do not kill running applications or manage services.
4. Wire the helper into all six entry points independently of Pi, Go, Muse and work-machine gates on otherwise supported setup runs. Preserve the existing Windows/WSL whole-setup early HEADLESS=1 rejection verbatim; those runs are explicitly exempt from OpenCode installation. Native Linux and macOS headless runs remain in scope without adding a new OpenCode headless gate. Respect actual macOS download/extraction prerequisites and gate any Homebrew-dependent migration on CLT readiness. Aggregate required failures while allowing independent work and log finalization.
5. Replace obsolete CLI-retirement test assertions without restoring OpenCode credential/model/skill management; update README, CLAUDE guidance and terminology, and increment all modified script versions. Keep Go credential and Muse helper payloads unchanged.
6. Run the new fixture contracts and affected AI-agent, setup-reliability, weekly, shared-runtime, headless, model-default, Pi Go/Muse/wiring, CLT/Homebrew-result contracts, ShellCheck and Markdown lint. Use PWSH_BIN if available; otherwise explicitly report unexecuted PowerShell/native Windows coverage. Review the complete diff and mark acceptance criteria only with evidence.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- User confirmed all five scope recommendations: CLI only, all six personal/work/headless entry points where supported, latest stable 2.x without downgrades/automatic v3, verified official v1 migration, and no new authentication/configuration/integrations.
- Recorded the resolved OpenCode CLI versus Go subscription terminology in CONTEXT.md; no ADR is needed for this reversible managed-tool addition.
- Official sources checked: <https://opencode.ai/v2/docs> , <https://opencode.ai/v2/docs/migrate-v1> , <https://opencode.ai/v2/install> . V1 and v2 share the opencode command and config locations; package-managed v1 needs migration, plugins/server APIs have breaking changes.
- The official latest CLI metadata endpoint <https://opencode.ai/update/api/latest/cli/npm> currently advertises @opencode/cli 2.0.18. Documentation examples still link 2.0.6; do not hard-code their displayed version. Installer supports --no-modify-path but otherwise writes shell configuration and installs legacy opencode2 shims; avoid blindly executing it against the live account.
- Prior TASK-7 used passive abandonment, leaving official Homebrew, Bun opencode-ai and ~/.opencode/bin copies potentially present. ai-coding-agent-contract.sh currently forbids reinstalling the CLI, so replace that assertion with the newly approved bounded policy.
- ShellCheck, Python and Node are available. No pwsh executable was found on PATH. Implementation plan recorded; waiting for user approval before installer/test code changes.

User approved implementation on the recorded plan and explicitly requested execution in a subagent. Delegating to one BB workflow worker in the current worktree; no live setup, application execution, machine changes, commits, or pushes authorized.

- Implementation preflight reconfirmed the official 2.0.18 update schema and platform registry metadata without downloading or running a native application. Registry publishes SHA-512 integrity and exact native package URLs; Windows ARM64 is present. The v1 npm postinstall copies/hard-links native binaries, so package name/version alone is not sufficient identity evidence.
- Safety review is checking how existing all-package upgrades interact with preserved OpenCode installations and how the Windows/WSL early headless rejection interacts with the approved all-headless CLI scope. No setup/app/lifecycle commands have run; no implementation code has changed yet.

- BLOCKED before implementation on a consequential headless-policy conflict: AC #1 requires OpenCode installation on all six entry points with HEADLESS=1, while the repository explicitly preserves Windows/WSL early HEADLESS=1 rejection. wsl.sh:8290 returns before env placeholders, account checks, prerequisites, and tool installation; win.ps1:8256 throws before placeholders and package installation. README.md:346 documents that whole-setup early failure, and tests/headless-paseo-daemon-contract.sh:876-882 asserts the pre-placeholder ordering. The approved plan does not resolve whether an OpenCode-only provisioning exception may run before this rejection. Moving/reinterpreting the guard silently would change existing headless provisioning semantics; leaving it unchanged prevents the new all-headless requirement from being reached.
- Smallest input needed: explicitly choose either (A) permit only OpenCode CLI installation before the existing Windows/WSL rejection, with no Paseo service support and an overall unsupported setup result, or (B) exempt rejected Windows/WSL HEADLESS=1 runs from AC #1. Option A also requires independent account/prerequisite preflight because WSL currently rejects before ensure_not_root/core tools. No change to the plan approval process is requested; this is one policy exception.
- Isolated evidence: extracted the actual WSL environment guard and entrypoint prefix into an inert temporary-HOME Bash fixture; HEADLESS=1 returned 1 before a sentinel mutation. Static inspection confirms the equivalent Windows throw/order. git diff --check passed. No pwsh/PWSH_BIN is available, so Windows execution was not claimed. No production code/docs/tests were changed, no acceptance criteria checked, and no full regression suite run because implementation stopped at the policy boundary. The original CONTEXT.md edit and TASK-52 record are preserved. No real setup, native application, authentication, model request, package manager mutation, commit, or push was performed.

- BLOCKER RESOLVED by explicit user confirmation: preserve Windows/WSL whole-setup early HEADLESS=1 rejection and exempt these rejected runs from OpenCode installation. All six scripts still install on supported runs, including supported native Linux/macOS headless runs. No OpenCode-only pre-rejection provisioning and no change to Paseo headless policy.
- Updated description, acceptance criteria and plan with the approved exception; the replaced platform criterion is now AC #6 (other criteria renumbered). Cleared the stale blocked final summary; restarting one implementation worker under the existing approval.

Implementation resumed under the approved Windows/WSL exemption. Designing artifact-hash identity checks before any native version probe, transactional command promotion/recovery, and explicit protection from later generic package upgrades. No live setup or application execution will be used.

Implemented the shared artifact-verification core and generated standalone Bash/PowerShell wrappers, independent caller aggregation, conservative x64 baseline/native ARM64 selection, and Windows/WSL guard preservation. Isolated core fixtures currently pass 29 cases. Migration is deliberately command-only: stage/verify the native replacement, quarantine only identified command entries, and retain legacy package stores/registrations plus recovery backups rather than run package-manager lifecycle hooks. Homebrew blanket upgrades temporarily preserve retained opencode formulae with an owned pin; user pins remain unchanged. This retention/recovery behavior will be documented explicitly. No application, full setup, authentication or model calls have run.

Self-review added atomic no-clobber publication, an exclusive promotion lock, recovery journals, partial-move rollback tests, exact Windows npm shim matching, native-byte checks for modern postinstall hardlinks, duplicate-key rejection for pin metadata, and isolated real-probe environment coverage. The new contract now passes 41 Node fixtures and 4 extracted Bash/caller tests; 2 PowerShell tests are present but skipped because no existing pwsh/PWSH_BIN is available. Documentation explains retained registrations, manual recovery, platform/runtime prerequisites and the headless exemption. Initial regression failures were traced to the inherited mise jq shim trying to read an untrusted config under fixture HOME; all five affected suites passed when a temporary PATH entry selected the already-installed /usr/bin/jq (no machine tooling/config changes). ShellCheck, cached Markdownlint and git diff --check pass.

Final self-review tightened two preservation boundaries before completion: project/custom-prefix commands are now rejected even when their bytes match an official artifact, and early/final APT blanket upgrades defer for distro-owned or unverified OpenCode commands. Windows blanket WinGet upgrades also defer after unresolved CLI installation/ownership. Added real caller/ownership fixtures, Rosetta legacy-x64 identity coverage, and documented these boundaries. New contracts now pass 43 inert Node cases and 5 extracted Bash/caller tests; 2 optional PowerShell tests remain skipped. The original CLI glossary addition, Windows/WSL early headless guards, permanent RTK path, and Go/Muse payloads are preserved.

Final evidence: all 26 requested/affected contract commands passed on the final implementation (results: /tmp/task52-complete-zjpmomfq/results.json). The OpenCode suite passed 43 inert Node cases and 5 extracted Bash/caller tests; its 2 optional PowerShell tests skipped because pwsh/PWSH_BIN is unavailable. This includes standalone/Homebrew/npm/Bun command migration, native Windows shim emulation, Rosetta/libc selection, pin/custom/project preservation, staged verification, rollback, generic-update protection and retained headless rejection. Final generator equality, Node syntax checks, ShellCheck of every modified Bash script/helper, Markdownlint (including the task record), and git diff --check passed. Self-review confirmed Go/Muse Bash payloads byte-identical to HEAD and no unrelated production changes outside installer wiring, versions and generic-upgrade preservation. No live setup/application execution, machine provisioning, authentication, model requests, commits, pushes or PRs occurred.

Final transport hardening explicitly requires TLS certificate verification even if the inherited Node environment disables its default, with inert real-HTTP-helper fixtures for TLS options, redirects, foreign URLs and response bounds. Re-ran all 26 contract commands after this change: every command passed (latest results: /tmp/task52-verified-db9qsbp_/results.json). Final OpenCode counts are 44 Node cases and 5 Bash/caller tests passed, with 2 optional PowerShell tests skipped.

Parent verification confirmed the completed workflow and inspected its 26-command results manifest. Independently reran bash tests/opencode-cli-contract.sh: 43 Node tests passed, the optional installed cmd-shim test skipped without OPENCODE_TEST_CMD_SHIM, 5 Python caller tests passed and 2 PowerShell tests skipped without PWSH_BIN. Generator equality and git diff --check passed. No live application or setup was executed. Changes remain uncommitted.

- Publication integration: rebased the OpenCode change onto origin/main 2917a69, preserving the newer Paseo non-management policy, generic Windows/WSL HEADLESS=1 guards, and BB process/service-reference permission safeguards. Resolved only overlapping documentation, installer wiring and version banners; advanced all six versions beyond main. Updated the OpenCode headless fixture to the renamed generic guards.
- Task ID collision resolved entirely through Backlog CLI demote/promote: the OpenCode record is now TASK-54; upstream TASK-52 (Paseo non-management) and TASK-53 are untouched. Earlier TASK-52 references in this record are historical identifiers for the OpenCode work.
- Rebased-state verification: all 35 tests/*.sh contract suites passed; Python discovery ran 383 tests with 22 expected optional/native skips and no failures. Generator equality, Node syntax, ShellCheck, Markdownlint and git diff --check passed. Test PATH selected existing /usr/bin/jq via a thread-storage link to avoid the inherited mise shim; no machine configuration changed. PowerShell/native rollout remains unverified. User authorized publishing to remote main; preparing a normal fast-forward push without force.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Implemented official stable OpenCode v2 CLI/TUI maintenance across all six setup entry points. Native Linux/macOS headless runs remain supported; Windows/WSL retain their approved early HEADLESS=1 rejection without pre-guard provisioning.

Changes:

- Added shared artifact-verification policy with identical generated standalone copies, native platform/baseline selection, strict stable-major checks, SHA-512/archive validation and isolated version-only probes.
- Added reversible, identity-proven command migration from known v1 standalone/Homebrew/npm/Bun locations. Retained package stores/registrations and recovery backups; preserved pins, newer versions, custom/project commands and application data.
- Aggregated required failures, respected macOS readiness, and protected retained copies from blanket APT/Homebrew/WinGet upgrades. Updated documentation, retirement assertions, fixture contracts and script versions.
- Rebased onto current main while preserving Paseo non-management and newer BB safety safeguards. Adapted tests to generic headless guards and renumbered the OpenCode record to TASK-54 through the Backlog CLI; concurrent upstream tasks remain untouched.

Verification:

- All 35 shell contract suites passed on the integrated tree. Python discovery ran 383 tests with 22 expected optional/native skips and no failures.
- The OpenCode suite passed 43 Node fixtures and 5 Bash/caller tests; optional native cmd-shim and two PowerShell cases skipped without supplied tools. The earlier implementation run also passed the optional cmd-shim fixture.
- Generator equality, Node syntax, ShellCheck, Markdownlint, gitleaks and git diff --check passed. Used isolated fixtures and inert probes; no live setup, application, model or authentication operations.

Limitations:

- PowerShell/native Windows ACL and filesystem behavior, native macOS and ARM rollout remain unverified.
- Migration intentionally retains legacy package registrations. Unrecognized/custom/system prefixes require manual review, and external upgrades can recreate conflicting shims.
- Tests selected existing /usr/bin/jq via a temporary PATH entry to avoid the inherited mise shim; no machine configuration changed.
<!-- SECTION:FINAL_SUMMARY:END -->
