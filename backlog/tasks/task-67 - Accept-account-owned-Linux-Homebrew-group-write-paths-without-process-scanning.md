---
id: TASK-67
title: Accept account-owned Linux Homebrew group-write paths without process scanning
status: In Progress
assignee:
  - '@implement-spec-coordinator'
created_date: '2026-10-02 13:49'
updated_date: '2026-10-02 14:31'
labels:
  - ready-for-agent
dependencies: []
references:
  - lib/opencode-cli.cjs
  - lib/opencode-cli.bash
  - lib/opencode-cli.ps1
  - tools/embed-opencode-cli.py
  - tests/opencode-cli.test.cjs
  - tests/fixtures/opencode-homebrew-proof.py
  - tests/test_opencode_cli_callers.py
  - tests/opencode-cli-contract.sh
  - tests/run-fixture-matrix.py
  - 'https://github.com/scowalt/machine-setup-scripts/commit/2502c3f'
  - 'https://github.com/scowalt/machine-setup-scripts/commit/e169f8d'
  - 'https://github.com/scowalt/machine-setup-scripts/commit/4bb7feb'
documentation:
  - docs/adr/0004-keep-opencode-migration-command-only.md
  - docs/research/2026-09-29-fixture-execution-audit.md
  - docs/research/2026-09-29-fixture-containment-incident.md
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Problem Statement

OpenCode CLI setup can fail on an otherwise ordinary, busy single-user Linux machine with `operation=homebrew-preflight, reason=brew-process-churn`. The latest examined devinabox upload contains this failure from Ubuntu setup version 290. The diagnostic directs the operator to README preflight guidance that no longer exists.

The installer currently treats group-writable Linux Homebrew paths as untrusted unless it can prove that the writable group is effectively exclusive to the setup account. The proof enumerates account databases and effective group memberships, examines ACLs, and compares complete system-wide process/thread membership snapshots. Processes starting or exiting can invalidate those snapshots even when they are unrelated to Homebrew. Three retries do not reliably solve that problem.

Scott runs these scripts on single-human-user machines; additional accounts are service accounts. Requiring proof of group exclusivity imposes an availability and maintenance cost disproportionate to that deployment model. The operator should not have to quiet unrelated workloads, change normal Homebrew permissions, or diagnose process churn to install a verified CLI.

## Solution

Accept account-owned, group-writable paths within the already recognized Linux Homebrew installation boundary without requiring an exclusive-group proof. Remove the associated account-database, live-process, and ACL privacy-proof prerequisite rather than adding more retries or an override switch.

Retain independent safeguards: expected ownership, rejection of world-writable paths, recognized command locations and links, official artifact identity, stable filesystem evidence, user pins, newer-release preservation, command-only migration, data preservation, and rollback. This is a deliberately scoped trust-model change for OpenCode's Linux Homebrew migration, not a repository-wide removal of permission checks.

The policy applies consistently to supported Linux setup entry points using this shared installer. It does not attempt to detect whether a machine has only one human user. Group membership, including membership held by service accounts, is no longer a prerequisite for accepting an otherwise eligible account-owned Linux Homebrew path.

## User Stories

1. As a single-user Linux machine owner, I want OpenCode setup to accept ordinary account-owned, group-writable Homebrew directories, so that normal Homebrew permissions do not block installation.
2. As a machine owner running background workloads, I want unrelated process starts and exits not to affect OpenCode setup, so that installation does not depend on a quiet system.
3. As a machine owner with service accounts, I want their presence or group membership not to trigger an exclusivity requirement, so that my supported deployment model works without special exceptions.
4. As an operator, I want the installer to stop enumerating live process and thread memberships for this check, so that transient procfs races cannot cause this refusal.
5. As an operator, I want this migration not to depend on account-database or effective-group enumeration, so that identity-provider differences do not block an otherwise eligible installation solely for group privacy.
6. As an operator, I want removal of the privacy proof to remove its native proof-runtime and ACL-query prerequisites too, so that a retired check does not leave hidden dependencies behind.
7. As an operator, I want the simpler policy to be the default rather than a bypass flag, so that I do not have to configure every machine individually.
8. As a machine owner, I want setup to leave Homebrew permissions and group memberships unchanged, so that installation does not rewrite my account or package-manager configuration.
9. As a machine owner, I want foreign-owned paths and unsafe root-owned group-writable boundaries to remain rejected, so that accepting group write does not discard ownership checks.
10. As a machine owner, I want world-writable paths to remain rejected, so that this change does not trust installations writable by every local account.
11. As a machine owner, I want unexpected links, custom prefixes, and changed filesystem identities to remain conflicts, so that setup does not operate on a substituted or unrelated command.
12. As an OpenCode user, I want official artifact identity verified before any native version probe, so that relaxing group privacy does not permit execution of an unidentified binary.
13. As an OpenCode user, I want pins, custom copies, unsupported installations, and newer releases preserved under existing policy, so that setup does not override intentional choices.
14. As an OpenCode user, I want a verified replacement staged before command promotion, so that a failed download or probe does not destroy my working command.
15. As an OpenCode user, I want migration to change only identified command entries, so that legacy package stores and registrations remain available for recovery.
16. As an OpenCode user, I want credentials, configuration, sessions, projects, and shell configuration preserved, so that this installation-policy change has no application-data side effects.
17. As an operator, I want filesystem evidence rechecked at migration and recovery boundaries, so that concurrent command or metadata changes still block unsafe publication or restoration.
18. As an operator, I want failed promotion to restore the prior verified command when safe, so that this simplification does not weaken recovery.
19. As an operator, I want uncertain rollback to retain recovery artifacts and report recovery required, so that setup does not claim success or discard evidence.
20. As an operator, I want remaining failures to have controlled, actionable diagnostics without stale README directions, so that I can understand real blockers without exposing secrets.
21. As an operator, I want unrelated setup work and log finalization to continue after genuine OpenCode failures, so that failures remain visible without suppressing independent work.
22. As a user of multiple supported platforms, I want generated installers to stay synchronized while preserving macOS, Windows, headless, and architecture gates, so that a Linux-specific change does not alter other platform policies.
23. As a maintainer, I want regression tests to exercise the real installer and migration behavior, so that acceptance is not inferred from a shallow mocked proof result.
24. As a maintainer, I want tests to assert that process inspection and privacy-proof dependencies are not invoked, so that a future refactor cannot silently restore the same source of flakiness.
25. As a maintainer, I want existing artifact, ownership, conflict, and rollback regressions retained, so that removing one restriction does not accidentally remove unrelated protection.
26. As a machine owner, I want the residual service-account tampering risk documented honestly, so that the simpler trust model is an explicit trade-off rather than a claim that single-user machines have no security boundaries.
27. As a maintainer, I want development validation to remain contained and offline, so that proving this policy does not execute setup or touch real installations.

## Implementation Decisions

- Change only the OpenCode CLI shared installer's Linux Homebrew permission policy and its generated integrations. An eligible group-writable boundary must remain owned by the setup account and inside the existing recognized Linux Homebrew prefix. Do not expand recognized prefixes or relax root/foreign ownership and world-write rules.
- Remove the exclusive-primary-group requirement, native account and initgroups enumeration, live process/thread snapshots, procfs race retries, and the ACL privacy proof bundled with that exception. Do not replace them with cached membership checks, a smaller process scan, retry tuning, automatic permission repair, or single-user detection.
- This removes an OpenCode Homebrew privacy-proof prerequisite, not independent credential protections, Windows ACL validation, or other components' service/account trust policies.
- Preserve local filesystem snapshots and their revalidation. Ownership, mode, link target, receipt, artifact, and command identity changes must continue to produce the appropriate failure or recovery outcome. A group or mode changing during migration remains changed filesystem evidence even though group exclusivity is no longer proved.
- Preserve the shared installer's public installation entry and result contract. Successful installation, current/newer results, migration, unsupported results, controlled failures, and recovery-required outcomes retain their existing semantics.
- Delete proof-only implementation, retry behavior, dependencies, and obsolete diagnostic reasons where no longer used. Keep diagnostics still needed for filesystem changes and independent policy failures. Update the strict Bash and PowerShell diagnostic handling together; unknown, malformed, or forged helper output must remain a generic failure without raw output disclosure.
- Replace stale preflight/retry guidance with concise instructions appropriate to the remaining checks. Do not enlarge the human README into an operator manual or require README wording through tests.
- Preserve command-only migration as established by the existing decision record: verify official bytes, stage a replacement, quarantine only identified command entries, retain package stores and registrations, and preserve recovery artifacts on uncertain rollback.
- Keep platform selection, stable-major policy, version-output verification, pins, custom/newer-copy handling, Homebrew readiness, generic-upgrade exclusions, failure aggregation, and log finalization unchanged.
- Regenerate all six standalone entry points from the canonical shared policy and wrappers. Increment modified setup-script versions and update concise change descriptions using the repository's existing conventions.
- Record the consequential threat-model trade-off in a concise decision record and repair affected active agent guidance. Preserve historical task and research evidence, including its uncertainty; do not rewrite the earlier proof and retry work as though it never existed.
- Add no new environment variable, command-line flag, service, package-manager operation, network endpoint, or application configuration.

## Testing Decisions

- The user approved two existing test seams: the shared real installer/migration fixtures as the primary seam, and extracted Bash/PowerShell callers for diagnostics and orchestration. No new production testing interface is needed.
- A good regression asserts externally observable results and preservation: an otherwise eligible migration succeeds, the verified replacement is reachable, the original package store and application data remain unchanged, and genuine unsafe conditions still fail with appropriate recovery. Avoid assertions about implementation function names, retry counts, or explanatory prose.
- Extend the existing virtual Homebrew filesystem and inert artifact/probe fixtures through the actual installation entry. Use the historically observed group-writable directory and receipt layout, including repeated/current runs and migration. Artifact retrieval and application probes remain inert; only the shared policy is real.
- Demonstrate the new acceptance expectation fails on the existing policy before changing it. Cover ordinary process churn, disappearing processes/threads, shared or stale service-user group memberships, identity-enumeration restrictions, ACL-proof unavailability, and an unavailable native proof interpreter as conditions that must no longer block solely through the removed privacy proof. These are synthetic states, never host inventory.
- Assert forbidden privacy-proof execution at the external-command boundary while allowing only the existing inert version probe. Removing host inventory is itself an observable requirement; a test must not simply mock the proof as successful. If the old native proof fixture is retained temporarily for red evidence, all of its filesystem/account/procfs access remains redirected to temporary state.
- Retain negative coverage for foreign ownership, root-owned group-writable boundaries, world write, unexpected links, malformed metadata, custom commands, pins, artifact mismatch, changed command/receipt/path evidence, staging/promotion failures, and unsafe rollback. Keep pre-mutation, pre-publication, and recovery revalidation exercised through real migration scenarios.
- Use the existing extracted caller fixtures across all six entry points to verify controlled remaining diagnostics, suppression of arbitrary stdout/stderr and forged replies, failure aggregation, independent work, and final log completion. Retired churn diagnostics must not remain a supported misleading policy outcome; test protocol behavior rather than exact guidance prose.
- Run the setup-default and extraction/containment contracts, the OpenCode contract, and the audited affected matrix: AI-agent, reliability, weekly, headless, shared-runtime, Pi Go/wiring, Paseo non-management, reboot, and CLT/Homebrew contracts. Check generated-source equality, modified script versions, syntax, ShellCheck, and whitespace.
- Execute behavioral fixtures only with the existing sanitized environment runner, explicit installed tools, mandatory unchanged kernel filter/self-test, private stdio and roots, and sequential suites. Install mocks before intentional helper/caller execution; never evaluate a stripped whole setup file. Stop on containment failure or unexpected real effects without an uncontained fallback.
- Use available existing PowerShell for wrapper fixtures. Record unavailable optional integrations and native Windows/macOS/ARM coverage explicitly. Offline fixtures do not establish native rollout success or resolve historical fixture-incident uncertainty.

## Out of Scope

- Removing ownership or world-write checks, official-byte verification, safe archive/URL handling, command identity checks, pins, rollback, or data preservation.
- Relaxing standalone/npm/Bun command-path policy, macOS Homebrew permission policy, Windows ACL policy, Pi profile/credential permissions, or BB preparation/server/service trust checks.
- Automatic chmod/chown, ACL edits, account/group changes, stopping workloads, package uninstalls, dependency installation, or changing existing Homebrew registrations.
- Running live setup, collecting native host process inventories, modifying fleet machines, executing OpenCode or installed skills/extensions, authenticating, or making model requests during development.
- Changing OpenCode Go credentials, Pi defaults, shell configuration, platform/headless behavior, or package-manager upgrade ownership.
- Adding more proof retries, a bypass toggle, automatic detection of single-user machines, or a broad security-policy rewrite.
- Expanding the README into a replacement operations manual or rewriting historical incident/research records.

## Further Notes

The history is defensive hardening, not a recorded response to a demonstrated compromise:

- September 28, 2026, commit 2502c3f introduced the OpenCode v2 installer with group-writable-path rejection.
- September 29, 2026, commit e169f8d (TASK-56) added the native private-group proof after normal Homebrew permissions blocked migration on scott-beelink-ubuntu.
- September 30, 2026, commit 4bb7feb (TASK-59) added bounded procfs retries. The present report exhausts them.

The original failure was matched in the latest examined devinabox upload and reproduced as an intentional refusal in isolated fixtures. Which native process activity caused that particular run remains unknown and is not required to implement this deliberate policy change. No claim is made that the machine's permissions are unsafe or that it is compromised.

A service account is still a security boundary. If a compromised service can write the accepted Homebrew paths, it could tamper with the installation; official-byte checks at a point in time do not eliminate every concurrent-write race. This scope accepts that residual risk instead of attempting to prove group privacy during setup. It does not grant service accounts new write access.

Scott confirmed the proposed scope and the two existing test seams in this conversation. This task is ready for an agent to implement under the repository's normal implementation-plan approval process. Creating this spec does not authorize live rollout, commits, pushes, or removal of unrelated safeguards.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 On supported Linux runs, the real shared installer accepts otherwise eligible account-owned, group-writable Homebrew paths without requiring exclusive group membership, account/NSS/initgroups enumeration, process/thread inventory, an ACL privacy proof, or the retired native proof runtime; no opt-in or single-user detector is introduced.
- [ ] #2 Busy-system and service-account fixture states no longer cause group-privacy or process-churn refusal. Existing recognized-prefix, ownership, root-owned group-write, world-write, link, metadata, and filesystem-change safeguards remain enforced without modifying permissions or account state.
- [ ] #3 Official artifact verification before execution, stable-major/version behavior, pins, custom/unsupported/newer-copy preservation, staging, command-only migration, package-store/data preservation, and safe rollback/recovery outcomes remain covered through real installer fixtures.
- [ ] #4 Proof-only implementation and obsolete diagnostic outcomes are removed; remaining Bash/PowerShell diagnostics stay strictly validated and secret-safe, no longer direct operators to nonexistent preflight guidance, and genuine failures still reach independent work and log finalization.
- [ ] #5 All six generated entry points match the shared source, modified setup scripts have incremented versions, and macOS/Windows/headless/architecture/readiness and unrelated component permission policies retain their existing behavior.
- [ ] #6 The approved primary installer/migration and secondary extracted-caller seams include red-before-change evidence for the new acceptance behavior, passing positive/negative/recovery regressions, and an assertion that the retired privacy-proof external operations are not invoked.
- [ ] #7 Setup-default, extraction/containment, OpenCode, and the audited affected regression matrix pass under mandatory sanitized sequential containment; embedding, syntax, ShellCheck, and whitespace checks pass, with optional/native gaps and historical incident uncertainty explicitly recorded.
- [ ] #8 A concise decision record and affected active agent guidance explain the scoped single-user trust model and residual service-account write-access risk; historical evidence is preserved and the README remains a short human introduction.
- [ ] #9 Development performs no live setup, native host inventory, application/skill execution, fleet changes, permission/account/ACL repair, or changes to credentials and unrelated data.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Approval gate: planning only until the user approves this plan. TASK-67 is one atomic ticket with no discovered blocking dependencies. Do not create branches/worktrees, edit code/tests, execute tests, or commit before approval. Baseline is 3dc99ea14ff861d2371f4264e77ebac5c0027d4c; keep the shared coordination branch and its CLI-managed, initially untracked TASK-67 intact.

1. After approval, establish local integration branch task-67/opencode-homebrew-integration at the pinned baseline in a separate owned worktree, carrying only the CLI-managed ticket/plan into its bookkeeping checkpoint without changing the shared worktree branch or discarding unrelated files. Delegate this single ticket to one background implementer on task-67/opencode-homebrew-implementation in its own isolated worktree based on that integration tip. Confirm ancestry before work; if unexpected state exists, preserve it and stop rather than reset away work. Coordinator owns Backlog updates through the CLI. No push, PR, main merge, live rollout or extra tickets.

2. Implement with the tdd skill in vertical red/green slices at exactly the two approved seams: real shared install/migration and extracted Bash/PowerShell callers. First add an observed 0775 directory/0664 receipt migration acceptance case with synthetic persistent process churn and capture its failure on the old policy under containment. If temporarily using the old native proof fixture for red evidence, retain all existing account/procfs/filesystem redirection. Do not replace the proof with a success stub or invoke host inventory.

3. Narrowly remove the Linux Homebrew group-privacy proof, native interpreter validation, account/NSS/initgroups/process/thread/ACL enumeration, retries and proof-only reasons from lib/opencode-cli.cjs. Retain account ownership within the existing recognized prefix, independent root/foreign/world-write and link checks, and filesystem fingerprints/revalidation. Expand real migration coverage one slice at a time for busy/disappearing processes, shared/stale service groups, identity/ACL unavailability and missing proof interpreter. For final fixtures forbid retired privacy operations at the external-command and synthetic-system-access boundaries, permit only inert verified version probes, and remove the obsolete native proof fixture once red evidence is recorded.

4. Preserve and exercise official-byte-before-probe identity, current/newer/pinned/custom/unsupported behavior, package-store/application-data and permission preservation, staging and command-only quarantine. Replace proof-coupled negative tests with independent filesystem negatives and real migration changes to ownership/group/mode/path/link/receipt/command evidence before mutation, publication and recovery. Retain safe restoration and uncertain-rollback artifacts/lock outcomes. No relaxation of standalone/npm/Bun, macOS, Windows ACLs, BB, Pi or other policies.

5. Update strict Bash and PowerShell diagnostics together: remaining allowlisted failures stay controlled, obsolete privacy/churn replies become generic failures, forged/malformed/stdout/stderr content remains suppressed, and stale README preflight/retry/recovery directions are removed in favor of concise actionable guidance. Exercise real extracted caller failure aggregation, independent work and finalization across all six entry points. Regenerate with tools/embed-opencode-cli.py and increment modified script versions. Add one concise ADR for the scoped single-user trust trade-off/residual service-account tampering risk and repair affected CLAUDE.md guidance; preserve README brevity and historical research/incident records. Load domain-modeling and writing-for-agents when making those edits.

6. Before behavioral execution, inspect affected fixture loaders/callers and install mocks before intentional execution. Use only env -i PATH=/usr/bin:/bin /usr/bin/python3 -I tests/run-fixture-matrix.py with explicit existing Node and PowerShell, audited tool paths, mandatory unchanged compiler/kernel-filter self-test, private roots/stdio and sequential suites. Run extraction/containment plus setup-default first, then red/green OpenCode fixtures, then the audited affected matrix: AI-agent, reliability, weekly, headless, shared-runtime, Pi Go/wiring, Paseo non-management, pending-reboot, macOS CLT and Homebrew results. Include Bash-compatibility coverage for modified embedded wrappers. Check generated equality, version increments, Bash/Node/Python/PowerShell syntax, modified-shell ShellCheck and git diff --check. Copy fixture runtime prefixes rather than expose writable links to real installations. Record commands, revision, red/green logs, results, skips and native gaps in private artifacts with a concise evidence pointer. Stop on any containment/preflight failure or unexpected real effect: no retry that weakens guards, no uncontained fallback or dependency installation.

7. Implementer merges the integration tip into its branch and reports commits/evidence. A separate merger subagent merges into the isolated integration worktree. Run code-review with parallel Standards and Spec reviewers against fixed point 3dc99ea14ff861d2371f4264e77ebac5c0027d4c and TASK-67; resolve findings with one isolated implementer and revalidate affected contained suites. All local commits require prior safe static checks and AI attribution/robot emoji; do not invoke hooks that download tools or execute fixtures outside containment. After review and final integration evidence, update ACs/final summary/status via Backlog CLI only, and mark Done only for satisfied evidence. Remove only owned clean implementer/review-fix worktrees, retain integration branch/commits and evidence, and report cleanup plus explicit skips/native limitations.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Planning review (2026-10-02): coordinator @thread:thr_4t8uv96kkj read the implement-spec, TDD (including tests/mocking), and code-review skills; TASK-67 and all attached current code/documentation references; linked fixture incident and rollback evidence; local commit history 2502c3f/e169f8d/4bb7feb. No extra ticket/dependency discovered. Shared checkout remains on bb/add-development-tools-to-the-machine-setup-thr_k9q9k953pw at 3dc99ea with only this task untracked. No code/test edits, tests, branching or commits performed.
Tool prerequisites inspected without execution: existing Node /home/scowalt/.local/share/mise/installs/node/24.20.0/bin/node; /usr/bin/python3, /usr/bin/cc, Bash, Git and ShellCheck; existing PowerShell /tmp/pi-shared-runtime-pwsh.2SlAPL/pwsh under a private 0700 root (not on PATH). Existing mise, Chezmoi and Bun are available for a new private audited tool-link directory if required; do not reuse or broaden an inherited user PATH. Native execution/readiness and kernel self-test remain unverified until plan approval. Optional live integrations stay disabled. No trusted Markdownlint command found; report that omission/manual Markdown review, never fetch tooling. Repository hooks use bunx and a raw test loop, so any later local commit must avoid those uncontained/download hooks and cite equivalent permitted checks. docs/agents/issue-tracker.md is absent; the user explicitly supplies Backlog CLI and TASK-67, so tracker bootstrap is not added to scope. Awaiting user implementation-plan approval.

User approved the recorded implementation plan via parent @thread:thr_k9q9k953pw. Proceeding with isolated local branches/worktrees and delegated implementation, merge and review; all prior scope and containment constraints remain active.
<!-- SECTION:NOTES:END -->
