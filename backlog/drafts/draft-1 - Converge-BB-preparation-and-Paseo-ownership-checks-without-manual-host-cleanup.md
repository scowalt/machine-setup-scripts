---
id: DRAFT-1
title: Converge BB preparation and Paseo ownership checks without manual host cleanup
status: Done
assignee:
  - '@pi'
created_date: '2026-09-28 21:21'
updated_date: '2026-09-28 22:31'
labels: []
dependencies: []
references:
  - ubuntu.sh
  - tests/test_bb_machine_preparation.py
  - tests/test_paseo_muse_profile.py
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow up Arcane Ubuntu v277: managed dotfiles converge, but BB preparation still rejects group-writable unrelated service targets, while Paseo inventory fails on protected account processes including the verified systemd user manager. User authorizes repository changes only and requires idempotent machine configuration, not direct Arcane repairs. Preserve existing ownership, credentials, services and unknown-owner safety checks; do not solve this with hardcoded Arcane paths, blanket chmod, or blind EACCES exemptions.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Repeated setup can prepare its private BB copy in the Arcane service-reference scenario through a documented, evidence-backed policy while preserving unrelated service files, targets, ownership and running services.
- [x] #2 Linux Paseo ownership inspection accounts for protected account processes without requiring those processes to be stopped or weakening kernel protections; unknown identities and possible Paseo writers remain blocked.
- [x] #3 The same isolated fixtures exercise all observed blockers together, repeated runs, positive and negative ownership cases, changed process/path identities, and final failure aggregation without live setup or service operations.
- [x] #4 Shared helper copies, platform gates and setup versioning remain consistent; documentation explains owned configuration convergence, preserved unrelated state and any remaining safety prerequisites.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Encode the approved Arcane evidence as isolated failing fixtures that combine all remaining service-permission and protected-process blockers, not merely the first failure.
2. Define the BB read-only trust boundary: keep strict ownership of the preparation prefix; determine whether unrelated service references can be inspected safely without taking ownership of project/service permissions. Preserve shared-group, ACL, link, reference and identity-race safeguards.
3. Define evidence-backed Paseo inspection for protected processes, preserving ancestry, UID tuples, cgroups and relevant-writer checks. Evaluate a narrowly scoped authorized metadata/inspection fallback rather than process-name exceptions or blind EACCES suppression; do not introduce broad sudo policy or kernel changes.
4. Implement only the reviewed policy that supports repeated convergence; synchronize shared helpers and versions, add preservation/negative/rerun tests, update README, and run affected suites plus full hooks.
5. Keep implementation repository-only with temporary inert fixtures. No Arcane permission changes, process inventory, setup run, package change, service lifecycle action or deployment. If a safe general policy requires broader ownership or privileges than approved, stop for that decision instead of weakening safety.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
User rejected direct machine permission repair and approved repository-only fixes with idempotent convergence as the requirement. Existing TASK-51 fixed Chezmoi-managed permissions but deliberately left unmanaged targets untouched. TASK-52 must not hardcode the six Arcane objects or repeat the one-blocker-at-a-time approach. Read-only evidence from the prior approved audit: protected user manager PID 7637, Paseo service MainPID 7776 accessible, six stable denied processes after one exited naturally. Repository files are unchanged apart from this CLI-managed task record; implementation policy review pending.

User explicitly approved use of existing sudo authorization on future setup runs for narrowly scoped read-only process inspection. Implementation will not add sudo rules, prompt for broader policy, weaken procfs protections, or run on Arcane during development. The fallback must return only command/selected ownership fields for the already identity-checked account-associated PID, reverify identity around reads, and retain controlled original plus fallback diagnostics on failure.

Implemented the approved scoped sudo reader for denied account real-UID command/environment reads with pinned procfs descriptors, bounded reads, rechecked identity/image/group data and selected environment output. No process-name exemptions; other real-UID reads stay unauthorized and writer checks remain unchanged.
BB read-only inspection now distinguishes safe Linux group bits from additional writers through a private ancestor or an isolated local-account/live-group/ACL proof. Reference snapshots, link targets and unit listings are rechecked; unrelated files remain unchanged and owned preparation files remain strict. No Arcane-specific paths or permission repair were added.
Red-to-green evidence: protected-process convergence/writer/receipt cases, native fake-procfs tests and a disposable nondumpable child, BB combined target/three-unit repeat-run fixtures, and negative shared-group/stale-session/ACL/changed-path cases. BB contract (21 helper, 3 Chezmoi, 6 trust groups) and Muse contract (98 helper, 6 reader groups plus PowerShell) passed. Native PID-lock integration remains an optional skip. Full pre-push hooks are now running without pushing.

Self-review tightened the group exception to the account-named primary group and rejects unavailable ACL inspection, not only explicit ACL entries. Added negative tests for empty system groups, non-primary groups and unsupported ACL reads. The privileged reader refuses another real UID even when a saved/effective/fs UID matches; ownership/ancestry rows remain present.
One exploratory full-hook run overlapped final source edits and reported a transient Go-helper extraction failure. The specific test passes on stable files, and all six unchanged Go payloads were compared with HEAD byte-for-byte. A new full-hook run is now using stable files, with both PWSH_BIN and a temporary pwsh PATH entry so available portable Windows fixtures are enabled. No hooks, tests or assertions were bypassed.

Full pre-push hooks passed in 705.53 seconds with the available PowerShell runtime on a disposable PATH: every tests/*.sh contract, ShellCheck-all and Markdownlint-all. Gitleaks found no leaks in the changed/new code.
Final security review added a red-to-green case for an NSS initgroups override: directory-backed supplementary groups must not bypass the local-account proof, including whitespace around the database name. Added supported-initgroups and status-inconsistent/secret-poisoned group-reader response cases. After this final narrow hardening, reran the full BB preparation contract (21 helper, 3 native Chezmoi, 7 service-trust groups plus PowerShell guidance), BB server contract, modified-script ShellCheck, Markdown lint and diff checks; all passed. The wider suite passed before this last guard, and the affected suites passed afterward.
Shared embedded code equality remains verified (five BB blocks, six Muse helpers). Versions are Ubuntu 278, macOS 251, Pi 229, Bazzite 130, WSL 212, Windows 163. README and agent guidance describe owned-state convergence, preservation and the bounded privileged inspection policy.
No setup was run on Arcane; no host permissions, services, sudoers or kernel policy were changed. Real sudo authorization/inspection on Arcane and native macOS/Windows rollout are not claimed. Optional integration modules/dotfiles sources remain unconfigured where suites report skips. Changes remain local and uncommitted; no push or deployment was performed.

User authorized publication to remote main. Fetch found upstream 84edeea, which removes Paseo management entirely and uses TASK-52 for that retirement. Preserve upstream non-management rather than revive the obsolete sudo inventory reader. Retain the BB read-only trust fix and revalidate the integrated tree; move this implementation record through the native draft workflow to obtain an unambiguous task ID.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
## Summary

```text
BB preparation
  read-only service references
    private ancestor OR verified exclusive primary group/ACL boundary
    stable reference snapshots -> maintain setup-owned copy
Paseo inventory
  denied account real-UID command/environment read
    scoped noninteractive sudo reader -> unchanged ownership checks
```

Preserve unrelated service files, project modes and enrollment state instead of requiring Arcane-specific chmod. Keep unsafe groups/ACLs/links, unknown identities, foreign real-UID reads and possible writers blocked. Privileged inspection is bounded and read-only, returns selected ownership fields, and never changes security policy. Synchronize helpers, increment versions, and document the policy.

## Evidence

- **Before:** Combined linked 0775/0664 service fixtures and multiple protected manager/agent rows blocked otherwise valid setup. An explicit directory-backed initgroups override also exposed an insufficient group-proof check.
  **After:** Repeated preparation/profile/verify-owner cases pass without unrelated mutation; negative membership, ACL, identity/race, writer, response-protocol and finalization cases remain blocked.
- Full configured pre-push suite passed (705.53 seconds), including portable PowerShell coverage. Final BB/server reruns, ShellCheck, Markdown lint and diff checks passed after the last initgroups guard. Extracted procfs-reader fixtures include a disposable native nondumpable child; no live daemon or root process inventory was used.

## Merge Danger

**Door:** two-way

No data migration or unrelated permission adoption. Reverting removes the new inspection paths; future setup still requires verifiable ownership.

**Blast Radius:** setup

Linux service-reference trust and protected-process inventory; shared Bash/PowerShell wrappers carry the policy. Existing noninteractive sudo authorization and native Python are required for protected reads. Native platform/Arcane rollout remains unverified, and optional external integrations retain documented skips. No commit, push or deployment is included.
<!-- SECTION:FINAL_SUMMARY:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 Affected BB/Muse, runtime/ownership/headless and PowerShell contracts pass, plus full pre-push hooks and diff/syntax checks.
- [x] #2 Review preservation, native privilege boundaries, shared helper equality and fixture-versus-rollout limitations; update documentation and final summary.
<!-- DOD:END -->
