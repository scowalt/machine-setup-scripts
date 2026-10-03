---
id: TASK-70
title: Correct secondary-account setup verification and ownership
status: To Do
assignee: []
created_date: '2026-10-03 13:38'
updated_date: '2026-10-03 13:41'
labels: []
dependencies: []
references:
  - GLOSSARY.md
  - ubuntu.sh
  - lib/opencode-cli.cjs
  - lib/bb-plugin-refresh.py
  - lib/bb-plugin-refresh.bash
  - tests/test_infisical_callers.py
  - tests/test_infisical_apt_retirement.py
  - tests/opencode-cli.test.cjs
  - tests/test_opencode_cli_callers.py
  - tests/test_bb_plugin_refresh.py
  - tests/run-fixture-matrix.py
  - 'https://logs.scowalt.com/logs/devinabox/2026-10-03-03-29-07-725.log'
documentation:
  - docs/adr/0001-keep-cleanup-for-retired-managed-tools.md
  - docs/adr/0002-let-chezmoi-own-shell-configuration.md
  - docs/adr/0003-separate-bb-preparation-from-enrollment.md
  - docs/adr/0004-keep-opencode-migration-command-only.md
  - docs/adr/0005-accept-opencode-linux-homebrew-group-write.md
  - docs/research/2026-09-29-fixture-execution-audit.md
  - docs/research/2026-09-29-fixture-containment-incident.md
  - docs/plans/2026-10-01-bb-plugin-refresh.md
  - docs/research/2026-10-01-bb-plugin-refresh-api.md
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Problem Statement

An ordinary setup run for a secondary account on a shared Ubuntu machine reports an incomplete setup run even when some required machine state is already satisfied, and other failures are too vague to diagnose safely.

The reported devinabox Ubuntu v292 run failed Infisical retirement because sudo was unavailable before any source or package verification occurred. It also refused OpenCode migration after encountering another account's shared Homebrew command, reported an undifferentiated bb plugin refresh failure, and encountered a custom skill occupying a managed agent skill name. Later successful Pi work did not recover these independent failures.

Subsequent authorized read-only inspection found no Infisical package match or official Infisical source markers in seven inspected APT source files. Shared Homebrew belonged to a different account, while the account's bb directory was group-writable. These later observations explain current blockers; they do not establish a historical filesystem snapshot or prove which bb refusal happened first.

The custom skill collision has already been resolved separately through an explicitly authorized one-time removal of its declaration and exact symlink. It is not an implementation requirement of this spec.

## Solution

Make the narrow account-ownership boundaries correct without redesigning the entire repository for multi-user administration:

- Verify that Infisical's managed native footprint is already absent without requiring sudo. Require privilege only when retirement actually needs a privileged mutation. Required but unavailable, unsafe, or unverified cleanup remains an incomplete setup run.
- Maintain an independently owned OpenCode CLI installation for each setup account. Leave other accounts' installations untouched, allowing lower-priority foreign commands to coexist only when setup verifies that the account-owned command is the effective command in both setup and a fresh shell.
- Produce bounded, secret-safe diagnostics identifying the failed operation and reason in the affected retirement, OpenCode, and bb plugin refresh paths.
- Keep bb plugin refresh verification-only with respect to existing filesystem permissions. Unsafe bb state remains a failure; do not silently chmod it or weaken the trust checks.
- Preserve unrelated work, accurate failure aggregation, and log finalization. A corrected verification path is not permission to suppress independent failures or declare the entire machine ready.

## User Stories

1. As a secondary-account user, I want an already-satisfied Infisical retirement requirement to be verified without sudo, so that missing administrative privilege alone does not invalidate an otherwise verifiable result.
2. As a machine owner, I want both native package state and official APT source state checked, so that an absent executable cannot hide a stale source or installed package.
3. As a secondary-account user, I want root-owned system metadata to remain inspectable without changing its ownership, so that verification does not create a security exception.
4. As a machine owner, I want unreadable or unavailable package inventory to remain a failure, so that inability to inspect is never mistaken for absence.
5. As a machine owner, I want ambiguous or unsafe APT source metadata to remain a failure, so that setup does not bypass existing trust and preservation rules.
6. As a user whose machine still contains an official Infisical source, I want setup to identify that retirement needs privilege, so that I understand why verification alone cannot complete it.
7. As a user whose native Infisical package remains installed, I want setup to require authorization for removal, so that an unprivileged run cannot pretend the package was retired.
8. As an authorized administrator, I want existing narrowly targeted retirement and independent postchecks preserved, so that unrelated repositories, dependencies, and data remain untouched.
9. As a machine owner, I want failed retirement to continue blocking affected APT upgrades, so that setup does not use an unresolved retired repository.
10. As a user rerunning setup, I want verified absence to remain idempotent, so that repeated runs do not introduce unnecessary writes or privilege requests.
11. As a secondary-account user, I want my own OpenCode CLI installation, so that my tool lifecycle is not coupled to another account's Homebrew ownership.
12. As the owner of a shared Homebrew installation, I want another user's setup to leave my commands, package store, receipts, recovery artifacts, and permissions untouched, so that their setup cannot take over my installation.
13. As a user with a verified account-owned OpenCode command first in command resolution, I want lower-priority foreign copies to coexist, so that harmless shared PATH entries do not block my installation.
14. As a user whose foreign or custom command shadows the account-owned command, I want a clear failed result, so that setup does not claim the wrong command is ready.
15. As a user opening a new shell, I want the account-owned OpenCode command to remain effective, so that setup's temporary environment cannot conceal a persistent resolution problem.
16. As a dotfiles owner, I want shell configuration to remain Chezmoi-owned, so that setup does not add a competing PATH or profile implementation.
17. As a security-conscious user, I want official OpenCode artifact bytes verified before any production version probe, so that a command name or reported version is not treated as identity.
18. As a user with an intentional pin or newer supported official OpenCode release, I want existing preservation behavior retained, so that account isolation does not become an excuse to override my selection.
19. As a user with custom or uncertain account-owned commands, I want conservative conflict handling retained, so that unrelated binaries are not replaced or silently accepted.
20. As a user whose OpenCode update fails, I want the prior account-owned command and recovery guarantees preserved, so that an interrupted migration does not leave me without a recoverable installation.
21. As a user on an unsupported architecture or platform, I want existing platform behavior preserved, so that this change does not introduce source builds or expand installation support implicitly.
22. As a user running setup headlessly, I want existing exact headless gates retained, so that account-local installation does not bypass platform or desktop boundaries.
23. As an operator reading a setup log, I want a controlled operation and reason for Infisical failures, so that missing privilege can be distinguished from unsafe metadata, unavailable inventory, or failed retirement.
24. As an operator reading a setup log, I want OpenCode ownership, path trust, command-resolution, and operation failures to be distinguishable, so that I do not resort to broad recursive permission changes.
25. As an operator reading a setup log, I want bb plugin refresh to expose its supported controlled refusal reason, so that a filesystem preflight refusal is not confused with a verified plugin update failure.
26. As a credential owner, I want diagnostics to exclude secrets, arbitrary exception text, raw subprocess output, and configuration contents, so that uploaded logs remain safe to inspect.
27. As a user with custom paths, I want bounded logical identifiers used instead of uncontrolled path dumps, so that a useful diagnostic does not disclose unnecessary local information.
28. As a user whose operation and cleanup both fail, I want the original failure retained, so that secondary diagnostics do not erase the causal problem.
29. As the owner of an existing bb installation, I want setup to refuse unsafe permissions without modifying them, so that plugin maintenance does not unexpectedly assume ownership of my configuration or data.
30. As a bb user, I want stopped and safe-mode deferrals preserved, so that better diagnostics do not cause setup to start, restart, or reconfigure a server.
31. As a bb user, I want native plugin source selections, pins, disabled status, settings, and rollback behavior preserved, so that observability changes do not alter plugin policy.
32. As a user whose required operation fails, I want unrelated work and log finalization to continue, so that an incomplete setup run is both useful and honestly reported.
33. As an operator, I want later success in an independent component not to erase an earlier failure, so that the final result reflects all required operations.
34. As ScoBot's owner, I want the completed one-time skill cleanup left alone, so that this implementation does not add permanent collision-removal logic or touch other custom skills.
35. As a maintainer, I want existing high-level fixture seams reused, so that the tests exercise real orchestration and observable results rather than a parallel reimplementation of the policy.
36. As a maintainer, I want deterministic red-capable cases for the reported failure patterns, so that the change can be verified before and after implementation.
37. As a maintainer sharing a development host with other projects, I want fixtures isolated with inert external operations and mandatory kernel containment, so that development validation cannot affect real installations or services.
38. As a reviewer, I want synchronized standalone entry points, accurate versions, and explicit test skips and platform limits, so that offline evidence is not mistaken for native rollout proof.

## Implementation Decisions

- The work is limited to Infisical verification/mutation separation, account-local OpenCode ownership and resolution, and controlled diagnostics for those paths and bb plugin refresh. These are independent causes and must not be presented as one universal permission fix.
- Split the existing APT retirement flow conceptually into trusted observation of native package/source state and privileged mutation only when necessary. Read-only verification must recognize the existing supported absent or not-installed package states and trusted system-owned source metadata without relaxing link, ownership, ambiguity, inventory, or change-detection checks.
- Success without sudo requires positive verification that neither a recognized native Infisical package requiring retirement nor an official APT source requiring removal remains. A failed inspection is not an intentional exclusion or a verified deferral. Do not replace structured source inspection with executable discovery, a simple text search, or an unconditional skip.
- Preserve the existing privilege mechanism, narrowly scoped native removal, whole-candidate preflight, unrelated-source preservation, and independent post-removal verification. Do not grant sudo, modify sudoers, request new credentials, or repair filesystem permissions to make the check pass.
- Keep retirement-before-update ordering. Incomplete retirement still blocks affected APT upgrades and contributes to the final failed setup result; unrelated work and finalization continue.
- The shared OpenCode installer owns the account-local destination and associated setup metadata. Discovery of another account's command does not authorize quarantine, migration, update, deletion, or ownership repair of that command.
- Separate nonselected foreign command evidence from account-owned migration candidates. Preserve foreign copies and permit their lower-priority coexistence only after verifying the effective account-owned command. Do not execute a foreign copy merely to classify or accept it.
- Effective command verification must establish the selected command, not just that its directory appears somewhere in PATH. Cover both the setup environment and a fresh native shell using the existing runtime and shell-validation conventions. Shadowing or an unverified selection remains a controlled failure.
- Preserve official stable OpenCode CLI installation policy, exact supported version-probe output, verified artifact identity, safe staging/promotion, command-only migration, rollback, user pins, newer releases, custom-copy handling, unsupported-platform behavior, and native Windows ACL checks. Coexistence is the narrow approved change; it is not a general relaxation of command trust.
- Do not create per-user Homebrew installations or rewrite shell profiles. Any independently necessary shell-activation correction remains with Chezmoi and requires its own authorization; an unresolved selection fails rather than being patched through ad hoc PATH changes.
- Reuse and extend controlled diagnostic contracts. Emit finite operation/reason labels and, where needed, allowlisted logical location identifiers or validated nonsecret metadata categories. Unknown exceptions and unrecognized helper output produce a controlled unknown/unverified failure rather than guessed causes or raw output.
- bb plugin refresh may preserve and surface controlled reasons already available at its verification boundaries. Keep its discovery, local-peer identity, native-version compatibility, source/update verification, result classification, safe-mode/stopped deferrals, lifecycle boundaries, and final status semantics unchanged. Never invoke refresh solely to obtain more detailed diagnostic evidence during development.
- Existing bb directories remain outside automatic permission repair. Private state is the desired direction for separately authorized owner/configuration work, but this task must neither chmod existing bb state nor import OpenCode's group-write exception into bb policy. Do not infer that a path is a managed dotfile merely because setup inspected it.
- Keep shared policies and embedded standalone copies synchronized across their existing applicable platforms, preserve early platform/headless/readiness gates, and increment every modified setup entry point's version and concise change description.
- Preserve the shared Node runtime, npm security policy, credentials, environment files, package data, unrelated tools, skills, plugins, projects, and user-selected configuration.
- The test boundaries described below were already agreed during design. No new public testing API, broad orchestration refactor, task delegation, or production instrumentation is part of this spec.

## Testing Decisions

- Prefer the existing extracted real setup-caller and log-finalization seam as the acceptance boundary. A good test asserts the observable diagnostic, final status, update gating, unaffected-work continuation, finalization, and preserved state; it does not assert incidental implementation structure or merely that a function returned without throwing.
- Reuse the shared OpenCode installer's injected artifact, filesystem, and inert native-probe seams for ownership, discovery, migration, promotion, rollback, and command-resolution cases. Join them to existing real Bash and PowerShell caller fixtures to verify externally reported outcomes. The installer algorithm must run; do not merely stub it to return the desired result.
- Reuse the existing Infisical source-retirement and native-inventory fixtures beneath the real caller. Add a deterministic no-sudo/verified-absence regression that is red on the current implementation, then verify success without any privileged operation. The earlier diagnostic replay established that unavailable sudo short-circuits observation, but its mocked clean-source result is not a substitute for testing the actual new observation flow.
- Exercise absent package with stale source, installed package with clean sources, supported config-only/not-installed records, unreadable inventory, unsafe or linked metadata, ambiguous source stanzas, changed evidence, available/unavailable privilege, failed removal, failed postchecks, and repeated runs. Assert preservation of unrelated source entries, packages, metadata, and data.
- Exercise two accounts' synthetic ownership metadata, a lower-priority foreign Homebrew command, a higher-priority foreign command, conflicting fresh-shell versus setup resolution, unexpected/custom account-owned commands, user pins, newer official versions, and foreign installation preservation. Assert that no foreign executable is probed and no foreign path is mutated.
- Cover the current, new-install, upgrade, and eligible account-owned migration paths, including failure before promotion and failure after promotion. Do not use a shallow permissions-only unit test as the sole proof of successful account-local installation.
- Reuse the definitions-only bb plugin policy fixtures and real wrapper/caller fixtures for controlled refusal reporting. Inject filesystem trust, discovery/identity, unsupported native contract, transport, update, malformed result, and verification failures without a real process inventory, application, plugin, or network request. Verify that permission refusals do not mutate filesystem state and that stopped/safe-mode semantics remain unchanged.
- Use adversarial secret, path, exception, and subprocess-output sentinels across diagnostic wrappers. Assert the exact allowed diagnostic category, nonzero status where required, bounded output, no secret leakage, and preservation of the original failure if later cleanup or restoration also fails.
- Run setup-default and extraction/containment contracts plus the audited affected Infisical, OpenCode, bb plugin refresh, and caller/reliability matrix. Include affected headless, shared-runtime, Homebrew/CLT, bb preparation/server, weekly, and platform-wrapper contracts according to the actual diff. Check embedding consistency, syntax, ShellCheck for modified Bash, and relevant native PowerShell fixture coverage when an existing trusted runtime is available.
- Before behavioral execution or source-loader changes, read the fixture execution audit and linked incident. Use the existing sanitized sequential runner with explicit existing native tools, private roots and stdio, mandatory kernel filter/self-test, definitions-only imports, and mocks installed before intentional helper/caller execution. Copy native fixture runtimes where needed; do not expose writable real installation prefixes to fixtures.
- A containment refusal, failed preflight, or unexpected real effect is a stop condition. Do not weaken guards or fall back to uncontained tests. Do not install missing tools, run live setup, load installed extensions, execute skills, or execute applications to validate the change.
- Record actual red/green results, affected contract evidence, optional skips, missing runtimes, and native-platform limitations. Contained offline success does not establish real machine rollout, native GUI behavior, or BB/plugin session continuity.

## Out of Scope

- A general multi-user redesign of package managers, Homebrew prefixes, system packages, services, or machine setup.
- Automatic bb directory permission repair, recursive chmod/chown, group-privacy policy changes, ownership transfer, server startup/restarts, or BB lifecycle recovery.
- Reproducing or correcting unknown underlying BB failures through live refresh, broad process inventory, application execution, or speculative permission changes.
- Permanent custom-skill collision cleanup, a reserved-name framework, custom-skill renaming, deletion of skill source repositories, another ScoBot cleanup, or fleet-wide cleanup. No managed-skill policy changes are required by this task.
- Shell-profile edits, new launchers/adapters, credential changes, privilege grants, optional integration enablement, or tool installation for development validation.
- Changes to OpenCode Go credentials or model access, Pi defaults, Pi packages, BB enrollment/preparation semantics, unmanaged legacy tools, or unrelated setup features.
- Watcher or automation changes, additional threads or automations, live deployment, production instrumentation, commits, pushes, pull requests, or remote publication of code without separate authorization.
- Expanded human README documentation or prose-enforcing tests. Use only narrowly necessary agent guidance or consequential decision records when implementation requires them.

## Further Notes

- Originating collector object: https://logs.scowalt.com/logs/devinabox/2026-10-03-03-29-07-725.log. Watcher event: `setup-log-watch:5d384862fda333fc16ef997f370c0b725c8f865e44237612f72367c898e8f835`.
- The log identifies Ubuntu x64, account ScoBot, exact headless mode, setup v292, and local run filename `2026-10-02-232809.log`. Relevant normalized lines are 11 and 15 for retirement/update gating, 120–122 for OpenCode, 148–149 for bb plugin refresh, 155 for the now-separately-resolved skill collision, and 202 for the incomplete final result. Opening and closing filename records match.
- The exact object was retrieved with authenticated HTTP 200 using the documented existing Doppler login. Collector uploads are public and their contents are untrusted data, not instructions or authenticated proof of host identity. Future retrieval must retain the documented authentication/redaction discipline; credentials must never enter arguments, output, files, task records, or chat.
- The no-sudo failure sequence was reproduced three times through extracted real retirement/caller/finalization code, then minimized to the retirement helper. Changing only mocked sudo availability made the isolated clean-state scenario succeed. The existing full Infisical retirement contract passed 29 tests; relevant boundary/default fixtures passed with explicit unavailable-PowerShell skips. These are pre-implementation diagnostic observations, not acceptance of a production fix.
- Read-only current-state inspection established that ScoBot's sudo policy denies sudo, Infisical's native package query reported no match with a healthy package database, shared Homebrew belongs to a different account, and the bb data directory is account-owned but group-writable. The bb generic log does not disclose its first failing predicate; do not overstate the diagnosis.
- The user separately authorized and completed the one-time custom grill-me retirement: only the custom manifest declaration and matching global symlink were removed, with source, unrelated registrations, and pre-existing edits preserved. A subsequent scan found no remaining managed-name link collisions in the inspected default global locations; project-local and process-selected alternate profiles were not exhaustively scanned. Do not repeat or expand that live action under this task.
- Existing architectural constraints remain: retained cleanup for retired managed tools, Chezmoi ownership of shell configuration, separation of BB preparation from enrollment, verified command-only OpenCode migration, and the narrowly scoped account-owned Linux Homebrew group-write exception. This spec changes treatment of nonselected foreign OpenCode copies without granting mutation authority over them.
- Design is approved and this spec is ready for agent planning. Implementation must still follow the repository's plan-review gate unless the user explicitly approves execution or waives that review. Publishing this specification does not authorize script implementation, live repair, deployment, commits, pushes, new threads, or further machine changes.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Infisical retirement succeeds without sudo only when trusted native package inventory and all applicable official APT source state positively establish an existing supported absent/not-installed result; that path performs no privileged operation or mutation.
- [ ] #2 Installed native Infisical, stale official sources, unavailable inventory, unsafe/linked/ambiguous metadata, or changed evidence cannot be silently accepted. Necessary retirement without privilege fails with a controlled reason and preserves state.
- [ ] #3 Existing authorized Infisical removal, independent postchecks, unrelated-state preservation, retirement-before-update ordering, APT upgrade gating, and final failure propagation remain intact.
- [ ] #4 OpenCode installs/updates the setup account's own verified native CLI; another account's discovered command is not treated as an owned migration target.
- [ ] #5 Lower-priority foreign OpenCode commands may coexist with the verified effective account-owned command and remain unexecuted and unchanged, including their links, stores, receipts, permissions, and recovery artifacts.
- [ ] #6 OpenCode success verifies actual command selection in setup and a fresh native shell, not mere PATH membership. Shadowing or unverified selection fails clearly without ad hoc shell-profile or PATH repair.
- [ ] #7 Official-byte-before-probe checks, exact version acceptance, account-owned command-only migration, staging/promotion/rollback, pins, newer releases, custom-copy preservation, unsupported-platform behavior, and Windows ACL checks remain intact outside the approved coexistence change.
- [ ] #8 Affected Infisical, OpenCode, and bb plugin refresh failures expose bounded operation/reason labels and safe logical identifiers; unknown helper output fails closed, raw exceptions/stderr and secret/path sentinels never leak, and original failures survive cleanup diagnostics.
- [ ] #9 bb plugin refresh remains verification-only for existing permissions: no chmod/chown, group-write exception, lifecycle recovery, identity bypass, changed source/update policy, or altered stopped/safe-mode deferrals. Unsafe or unverified results remain failures.
- [ ] #10 Real extracted caller fixtures prove independent later success cannot erase required failures, unrelated work continues where permitted, and log finalization retains the correct failed result.
- [ ] #11 No permanent skill-collision cleanup or managed-skill policy change is introduced, and the completed one-time ScoBot cleanup is not repeated or expanded. Unrelated tools, skills, projects, credentials, runtime/npm policy, environment files, and shell ownership are preserved.
- [ ] #12 Shared policies and applicable embedded standalone copies are synchronized, modified setup entry points have incremented versions and accurate change descriptions, and existing platform/headless/readiness gates remain intact.
- [ ] #13 Deterministic red/green regressions exercise actual observation/installer/caller seams, including two-account ownership and fresh-shell resolution, rather than only mocked success results or reimplemented predicates.
- [ ] #14 Mandatory contained default/extraction checks, targeted contracts, audited affected regressions and static/embedding checks pass, or blockers/skips are explicitly recorded without weakened containment, tool installation, application/skill/extension execution, live setup, or unsupported native rollout claims.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Duplicate of TASK-69 caused by a timed-out creation completing after the retry. TASK-69 is the sole canonical ready-for-agent specification. No implementation performed.
<!-- SECTION:NOTES:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 Record contained red/green and affected-contract evidence, optional skips, and native-platform limitations.
- [ ] #2 Self-review ownership, privilege, diagnostic secrecy, preservation, failure aggregation, and no-live-effects boundaries.
- [ ] #3 Obtain implementation-plan approval or an explicit waiver before implementation; leave code publication and rollout to separate authorization.
<!-- DOD:END -->
