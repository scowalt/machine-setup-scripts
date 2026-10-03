---
id: TASK-69
title: Remove completed Infisical retirement from setup
status: In Progress
assignee:
  - '@pi'
created_date: '2026-10-03 03:49'
updated_date: '2026-10-03 13:37'
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
  - docs/adr/0001-keep-cleanup-for-retired-managed-tools.md
  - docs/plans/2026-09-23-001-retire-infisical.md
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Problem Statement

Infisical has already been uninstalled everywhere, according to the machine owner. Machine setup nevertheless retains Infisical-specific inventory, removal, repository cleanup, warnings, failure bookkeeping, and update deferrals across all six supported platforms. This completed migration adds maintenance burden and can make an otherwise valid setup run incomplete for a tool the owner no longer uses.

The request is to remove that obsolete retirement machinery, not to reinstall Infisical, replace it, perform another fleet cleanup, or change unrelated setup policies.

## Solution

Stop managing Infisical during future setup runs on macOS, Ubuntu, WSL, Raspberry Pi, Bazzite, and Windows. Treat it as an unmanaged legacy tool: its presence is neither required nor prohibited by the desired machine state.

Remove only Infisical-specific operations and the update gates that depend on them. Ordinary provisioning and updates continue under their existing independent platform, trust, readiness, and component policies. Preserve personal-machine Doppler behavior, the absence of a replacement secrets manager on work machines, and existing failure reporting and log finalization.

## User Stories

1. As the machine owner, I want completed Infisical retirement removed from setup, so that future runs no longer repeat an unnecessary migration.
2. As the machine owner, I want this change applied to all six supported platforms, so that the desired machine state is consistent across my machines.
3. As a personal-machine user, I want setup to stop querying Infisical installation state, so that an unused tool cannot create an additional setup prerequisite.
4. As a work machine user, I want the same removal of Infisical-specific behavior, so that classification does not retain obsolete cleanup.
5. As a macOS user, I want Infisical Homebrew retirement removed, so that setup no longer requires its inventory or removal verification.
6. As a secondary macOS account user, I want Infisical cleanup removed without gaining main-user provisioning, so that existing account boundaries remain intact.
7. As a Bazzite user, I want Homebrew updates freed from the Infisical retirement gate, so that completed cleanup no longer controls unrelated updates.
8. As an Ubuntu user, I want ordinary package repair and APT updates freed from Infisical-specific prerequisites, so that their existing workflow can proceed.
9. As a Raspberry Pi user, I want dependency updates freed from the Infisical retirement gate, so that setup continues normal provisioning.
10. As a WSL user, I want obsolete Infisical cleanup removed before core provisioning, so that this migration no longer affects the setup result.
11. As a Windows user, I want Infisical registry inventory and targeted WinGet removal eliminated, so that setup no longer inspects obsolete registrations.
12. As a Windows user, I want WinGet and Windows updates freed from Infisical-specific deferrals, so that their independent existing policies determine whether they run.
13. As a user on a machine without Infisical, I want repeated setup runs to remain free of Infisical-specific work, so that the completed migration stays completed.
14. As the machine owner, I want any later manually installed Infisical copy left unmanaged, so that setup does not impose a permanent removal policy for this tool.
15. As the machine owner, I want Infisical installation and replacement-source setup to remain absent, so that removing retirement does not restore active support.
16. As a personal-machine user, I want Doppler installation, presence checks, and trust behavior preserved, so that this cleanup does not change my existing secrets-manager workflow.
17. As a work machine user, I want no replacement secrets manager installed and existing Doppler state preserved by this change, so that removing retirement does not introduce a different policy.
18. As a macOS user, I want macOS developer-tool readiness and Homebrew trust gates preserved, so that removing an obsolete gate does not bypass valid safeguards.
19. As an OpenCode CLI user, I want existing command-ownership and generic-upgrade protections preserved, so that unrelated installation safety is unchanged.
20. As the machine owner, I want existing required-operation failures retained through unrelated work and log finalization, so that an incomplete setup run is not reported as successful.
21. As the machine owner, I want existing pending reboot reporting and update ordering preserved, so that the cleanup does not change reboot-related behavior.
22. As the machine owner, I want credentials, environment files, managed dotfiles, project data, and hosted secrets unaffected by this change, so that removing code does not become another migration.
23. As a maintainer, I want obsolete retirement-only tests removed and shared regressions adapted, so that tests enforce current behavior rather than a completed migration.
24. As a maintainer, I want historical plans and incident evidence preserved with obsolete policy clearly identified, so that future agents can distinguish past decisions from current requirements.
25. As a maintainer, I want changed setup versions incremented, so that later logs identify the removal accurately.
26. As the machine owner, I want validation confined to temporary, inert, contained fixtures, so that developing this change does not modify installed software or contact remote systems.

## Implementation Decisions

- Modify the six existing standalone setup entry points; do not introduce a new production module, interface, feature flag, migration command, or compatibility shim.
- Delete the Infisical APT source-rewriting and package-retirement helpers, Homebrew retirement helpers, and Windows portable-registration, source-verification, and removal helpers. Remove their call sites, retirement state variables, warnings, terminal failure checks, and update deferrals.
- Restore only the control flow previously conditional on successful Infisical retirement. On Ubuntu this includes the existing package-repair and dependency-update sequence; on Raspberry Pi the existing dependency updates; on macOS and Bazzite the existing Homebrew update flow; on Windows the existing WinGet and Windows update flow. WSL loses its retirement call and associated error contribution without adding new update behavior.
- Preserve every independent existing gate, including account scope, exact headless behavior, platform restrictions, macOS developer-tool readiness, Homebrew trust, OpenCode command preservation, and component-specific deferrals. Removing an Infisical gate must not make all updates unconditional.
- Keep existing error aggregation, unrelated-work continuation, pending reboot reporting, and log finalization semantics. Remove only Infisical's contribution to an incomplete setup run; do not redesign unrelated error handling.
- Leave existing secrets-manager selection intact: personal-machine Doppler behavior remains, work machines receive no replacement, and this change introduces no Doppler cleanup.
- Infisical is now an unmanaged legacy tool rather than a retired managed tool with a required-absent managed footprint. This is a bounded exception to continuing retired-tool cleanup, supported by the owner's confirmation that retirement is complete. Do not generalize it to other retired managed tools or alter their cleanup policies.
- Non-management means no Infisical-specific inspection or mutation. It does not introduce an exclusion from ordinary generic package-manager operations. If a stale repository or manual package is later present, normal package-manager behavior and existing error handling apply; setup does not automatically repair or remove it specially.
- Remove obsolete retirement-only fixtures, retaining useful shared behavior coverage through the approved caller boundary. Update version banners and affected contracts. Mark the original Infisical retirement plan superseded with a concise current-policy note while preserving historical implementation, research, and incident evidence. Do not expand the human README into a migration record.
- Keep the task's existing code and documentation references as navigation aids; the behavioral contract does not depend on particular helper names or source layout.

## Testing Decisions

- The user approved reusing the highest existing practical seam: each platform's extracted real setup task caller and logging wrapper, with dependency effects replaced before invocation. Keep one conceptual orchestration boundary across platforms rather than introducing production test interfaces or testing deleted helper internals.
- A good test verifies observable command requests, preserved fixture state, continuation, final status, and log finalization. It must not depend on exact helper names, statement layout, or incidental diagnostic wording. Static review supplements behavioral tests by confirming obsolete code is actually removed.
- Test all six platform orchestrators with synthetic Infisical absence and residual/custom-state scenarios. Exercise personal and work machine classifications, and the existing main/secondary macOS account paths. Assert no Infisical-specific installation, inventory, source cleanup, uninstall, or warning; absence of Infisical metadata must not become a prerequisite. Residual synthetic state must not receive targeted cleanup.
- Verify ordinary eligible update phases are reached without a retirement prerequisite. Separately verify representative existing readiness, trust, account, headless, and OpenCode deferrals still block the work they own. Do not require updates in scenarios where unrelated policy intentionally defers them.
- Inject existing required-operation failures and verify they remain failures through later successful work and finalization. Confirm successful eligible runs do not acquire an Infisical-derived failure and pending reboot reporting retains its existing place in the workflow.
- Preserve behavioral coverage for personal-only Doppler provisioning and no work-machine replacement. Exercise the existing secrets-manager branch within the caller fixture where practical, with only its external effects made inert.
- Prior art is the existing ordinary-setup wrapper, Infisical caller, Homebrew-result, macOS CLT, reliability, pending-reboot, and unmanaged-tool contracts. Adapt useful caller assertions, remove obsolete retirement-helper assertions, and reuse the established extraction and PowerShell AST-loading infrastructure.
- Run setup-default and extraction/containment contracts, the affected caller/CLT/Homebrew/reliability/reboot contracts, and the audited affected orchestration matrix, including relevant headless, BB, Pi, runtime, OpenCode, and weekly regressions. Run Bash syntax checks, ShellCheck on modified shell scripts, PowerShell parsing with an existing runtime, and whitespace checks.
- Behavioral execution must use the sanitized sequential runner with mandatory kernel filter/self-test, private standard I/O, explicit existing native tools, and temporary homes/configuration. Use definitions-only or validated AST imports, install mocks before intentional caller execution, and copy native fixture runtimes rather than exposing writable links to real installations. Never evaluate a stripped whole setup script.
- No real package manager, registry mutation, source cleanup, service lifecycle, upload, application, skill, or live setup invocation is permitted for validation. Stop and report if containment/preflight fails or an unexpected real effect appears; never fall back to uncontained execution.
- Report optional skips and native Windows, macOS, WSL, Bazzite, ARM, and continuity limitations explicitly. Linux PowerShell and inert package-manager fixtures are offline regression evidence, not native rollout evidence.

## Out of Scope

- Running setup, uninstalling software, checking the real fleet, or independently verifying the owner's completed-uninstall statement.
- Reinstalling Infisical, migrating to its replacement repository, introducing a replacement secrets manager, or adding a permanent Infisical ban or opt-out.
- Editing credentials, login state, existing environment files, shell configuration, project data, hosted secrets, or real package-manager sources and registrations.
- Changing retirement policies for other tools, altering generic package update selection to exempt Infisical, redesigning logging or failure handling, or restoring the historical non-disruptive default.
- Changing BB, Pi, OpenCode, managed skills, shared runtime, service, enrollment, or dotfile behavior beyond preserving their existing caller gates.
- Remote cleanup, collector investigation, account/API calls, live rollout, or claims that historical fixture-incidence uncertainty has been resolved.

## Further Notes

- The machine owner's statement that Infisical is already uninstalled everywhere is the basis for removing retirement; this work does not claim an independent inventory or absence proof.
- The user explicitly approved the extracted caller/logging-wrapper testing boundary and requested publication of this specification with the ready-for-agent label.
- This specification replaces the current Infisical retirement requirement only. Existing historical records remain valid descriptions of what was implemented and tested at the time.
- Ordinary setup remains potentially disruptive. Removing the obsolete Infisical gate does not make live setup a development-validation method or authorize fleet execution.
- Publication prepares TASK-69 for implementation. No setup code has changed and no behavioral fixture or live setup has run during specification work.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 All six entry points contain no Infisical-specific retirement, inventory, repository cleanup, warnings, or failure gates; Infisical installation is not reintroduced.
- [ ] #2 Normal APT, Homebrew, WinGet and Windows updates retain unrelated trust/readiness/OpenCode gates, error aggregation and log finalization; personal Doppler and work-machine behavior remain unchanged.
- [ ] #3 Obsolete retirement fixtures are removed or replaced with non-management coverage; affected shared contracts and script versions are updated, while historical evidence is preserved and superseded policy is clearly marked.
- [ ] #4 ShellCheck, syntax and affected audited contracts pass using mandatory contained offline fixtures, with explicit optional/native coverage limitations; no live setup or fleet changes occur.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Remove Infisical-only helper blocks, callers, status flags and upgrade deferrals from all six setup scripts; preserve independent readiness/trust/OpenCode gates, failure aggregation, finalization and secrets-manager behavior. Bump each setup version.
2. Delete obsolete retirement-only fixtures and add compact non-management coverage; adapt reliability, Homebrew and macOS CLT fixtures to the restored update flow. Mark the old Infisical plan superseded without rewriting historical incident/research evidence.
3. Review extracted caller boundaries and run syntax/ShellCheck plus setup-default, containment, affected caller/CLT/Homebrew/reliability/reboot and other audited affected contracts sequentially through the sanitized mandatory-filter runner, using existing native tools only. Report optional/native limitations and stop on containment failure or real effects.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Inspected all-platform retirement references, original TASK-43 plan and cleanup ADR, fixture audit/incident and ordinary-setup rollback requirements. Existing Python, C compiler, Node, ShellCheck, mise, Chezmoi, Bun and /tmp/pi-shared-runtime-pwsh.2SlAPL/pwsh are available. No setup code changed and no fixtures/live setup run. Awaiting user approval of the removal plan as required by repository workflow.

The user approved the existing extracted real caller/logging-wrapper testing boundary. Published the full seven-section specification in this task and applied ready-for-agent. Returned the planning task to To Do for implementation; existing acceptance criteria remain unchecked. Infisical is an unmanaged legacy tool under this bounded change; other retirement policies and ordinary generic updates remain unchanged. This turn publishes the spec only, with no setup code changes or fixture execution.

Implementation requested via implement-spec. TASK-69 is the sole unblocked ticket; use one implementation worktree, a dedicated integration branch, a merger worker, and independent standards/spec review. The published plan and approved test seam remain the implementation contract. No live setup or fleet activity is authorized.
<!-- SECTION:NOTES:END -->
