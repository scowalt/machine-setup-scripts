---
id: TASK-53
title: Converge BB preparation without manual service permission cleanup
status: Done
assignee:
  - '@pi'
created_date: '2026-09-28 21:21'
updated_date: '2026-09-28 23:05'
labels: []
dependencies: []
references:
  - ubuntu.sh
  - tests/test_bb_service_trust.py
  - tests/test_bb_machine_preparation.py
  - tests/paseo-non-management-contract.sh
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Resolve Arcane-style BB preparation failures from safely inspectable group-writable service references without adopting or chmodding unrelated services/projects. Preserve private preparation ownership, unknown-writer failures, scoped Chezmoi eligibility, bounded diagnostics and parent-before-descendant inspection. The initial protected-process Paseo work was superseded during integration by upstream TASK-52: preserve its complete non-management policy instead of restoring inventory or a sudo reader. User authorizes publication to remote main, not live Arcane setup or repairs.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Repeated setup can prepare its private BB copy in the Arcane service-reference scenario through a documented, evidence-backed policy while preserving unrelated service files, targets, ownership and running services.
- [x] #2 The same isolated fixtures exercise all observed blockers together, repeated runs, positive and negative ownership cases, changed process/path identities, and final failure aggregation without live setup or service operations.
- [x] #3 Shared helper copies, platform gates and setup versioning remain consistent; documentation explains owned configuration convergence, preserved unrelated state and any remaining safety prerequisites.
- [x] #4 Preserve upstream Paseo non-management: no setup-owned Paseo inventory, sudo reader, lifecycle action or profile mutation is reintroduced.
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

Native draft promotion resolves the concurrent task ID collision: this implementation is now TASK-53; upstream TASK-52 remains the Paseo non-management change. Merge policy preserves upstream scoped Chezmoi eligibility, bounded multi-error/path/mode diagnostics, and parent-before-descendant service link traversal while adding the read-only BB permission proof and stable snapshots. The superseded Paseo implementation remains only in the parent commit history.

Integrated upstream 84edeea without reviving retired Paseo management. BB retains upstream scoped dotfiles eligibility, safe path/mode diagnostics, the eight-blocker/4096-byte protocol and parent-before-descendant link resolution. Added link/listing/FIFO race cases to verify the merged snapshots. Integrated preparation contract passes (28 preparation, 16 dotfiles, 3 permissions, 8 trust groups plus PowerShell). Updated old blanket-rejection fixtures to retain explicit unsafe world-write failures and positive private-group preservation. Upstream Windows non-management fixture failed unchanged under portable PowerShell: stub discovery missed inline-parameter functions, then engine caches polluted the account snapshot. Fixed only that fixture discovery/cache isolation; non-management and headless contracts now pass. No Windows production change beyond upstream.

Integrated full pre-push hooks passed in 738.35 seconds with portable PowerShell available (all tests/*.sh, Markdownlint and ShellCheck). Final review added a red-to-green shared-group ancestor fixture: verify group/ACL permissions before probing descendants, cache only successful proofs and recheck the full set before package changes. The final 8-group service trust suite plus upstream unsafe-ancestor and five-copy-equality tests pass after that guard. The actual push will run the full hooks again on the final merge commit, without bypass. Native Arcane rollout and optional external dotfiles integrations are not claimed.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
## Summary

```text
BB service reference
  prove ancestor permissions before descending
  private boundary OR exclusive primary group + ACL proof
  bounded read + stable reference checks
  maintain only the setup-owned BB copy
```

Merge with upstream 84edeea without reviving retired Paseo management. Preserve its scoped Chezmoi eligibility, safe relative-path/mode diagnostics, bounded multi-error reporting and link traversal. Leave unrelated service contents/modes unchanged, while shared groups, uncertain ACLs, world write, stale identities and actual BB references remain blockers. No sudo is added by the final tree.

## Evidence

- **Before:** Repeated Arcane-shaped linked 0775/0664 service fixtures failed; a merged shared-group boundary initially allowed a descendant probe before permission proof.
  **After:** Repeated safe preparation preserves all service files, while shared-group/FIFO/link/listing/protocol races fail before package work and unsafe descendants are not probed.
- Integrated BB contract: 28 preparation, 16 dotfiles, 3 permission and 8 trust groups, plus PowerShell guidance. Paseo non-management and headless callers pass with portable PowerShell. Full configured pre-push hooks passed in 738.35 seconds; final eager-proof reruns pass, and publishing retains mandatory hooks.
- Correct the upstream Windows non-management fixture to discover inline-parameter functions and isolate PowerShell runtime caches outside the preserved account snapshot. Production Windows source remains unchanged from upstream.

## Merge Danger

**Door:** two-way

No migration, unrelated chmod, enrollment or daemon lifecycle operation. Reversion restores stricter read-only preparation refusals.

**Blast Radius:** setup

Five shared Bash preparation helpers and their regression tests. Unsafe/unverifiable boundaries remain fatal. Native Arcane/macOS/Windows rollout remains unverified; optional cross-repository/native integration skips are retained. No live machine changes are included.
<!-- SECTION:FINAL_SUMMARY:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 Review preservation, native privilege boundaries, shared helper equality and fixture-versus-rollout limitations; update documentation and final summary.
- [x] #2 Affected BB, non-management, runtime/headless and PowerShell contracts pass, plus full configured pre-push hooks, syntax and diff checks.
<!-- DOD:END -->
