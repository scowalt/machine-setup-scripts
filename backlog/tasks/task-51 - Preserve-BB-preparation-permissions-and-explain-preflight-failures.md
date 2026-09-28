---
id: TASK-51
title: Preserve BB preparation permissions and explain preflight failures
status: Done
assignee:
  - '@pi'
created_date: '2026-09-28 19:17'
updated_date: '2026-09-28 20:26'
labels: []
dependencies: []
references:
  - ubuntu.sh
  - tests/test_bb_dotfiles_umask.py
  - tests/test_bb_machine_preparation.py
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Arcane setup failed before BB package changes because service directories were 0775 and several service files were 0664. The existing Chezmoi permission guard only covered BB_SERVER=1; native temporary fixtures reproduce those unsafe managed modes without the guard. Extend the command-scoped protection to preparation and surface controlled preflight diagnostics without weakening ownership checks or modifying unmanaged services. User approved this repository-only fix; no live rollout is authorized.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 All five Bash setup scripts restrict group/world write bits for full Chezmoi init/update/apply operations, including BB preparation with BB_SERVER unset/0, while preserving stricter caller masks, native explicit config precedence and command failures.
- [x] #2 Identical preparation helpers report controlled operation/location/reason diagnostics for directory, service-reference, process, runtime and artifact failures without leaking credentials, raw errors or arbitrary process/service contents; unknown output fails closed.
- [x] #3 Unsafe or unmanaged paths and services remain untouched and blocked; existing role deferrals, npm policy, manual enrollment ownership, headless gates and failure aggregation are preserved.
- [x] #4 Isolated native Chezmoi and extracted-caller fixtures reproduce Arcane writable modes, verify convergence of managed paths and repeated preparation, preserve unmanaged paths, and cover unsafe metadata plus diagnostic secrecy.
- [x] #5 README explains managed-mode convergence and manual recovery for remaining unsafe locations; modified setup-script versions are incremented.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Lock down the approved Arcane regression with native Chezmoi fixtures and extracted preparation callers in temporary homes, including unmanaged writable service files.
2. Share an additive command-scoped umask wrapper across all five Bash full-apply callers; preserve native config precedence, existing failures, targeted runtime repairs and caller umask.
3. Add controlled stage/location/reason diagnostics to the identical preparation helper and strict Bash result validation, without relaxing safety checks or invoking BB.
4. Update README and script versions; run affected contracts/lint, review preservation and log aggregation, and document manual-only recovery plus native rollout limits.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
User approved the proposed repository fix in this thread. Diagnosis used authenticated collector log arcane/2026-09-28-18-49-16-056.log, read-only remote metadata/preflight (first failure: systemd directory chain), and isolated real-helper replays. Temporary fixtures prove either 0775 directory or 0664 unrelated unit independently blocks preparation; no Arcane mutation occurred. Implementation plan shared; proceeding under that approval.

- Reproduced the managed 0664/0775 convergence failure before patching through native Chezmoi and all five extracted callers. Identical unconditional command-scoped go-w wrappers now cover full init/update/apply; stricter masks, caller mask and explicit native config remain intact. Targeted runtime repair callers are unchanged.
- Added strict allowlisted preparation terminal diagnostics with stage/location/reason. Unknown or status-inconsistent output fails closed without echoing raw output; no safety check was weakened. Existing-role deferrals remain before runtime/npm.
- Preparation contract passed (20 helper groups, 3 cross-platform caller/native-Chezmoi groups, PowerShell guidance). BB server, setup reliability, Homebrew results and macOS CLT fixtures passed. Bash syntax/ShellCheck passed before final review.
- Native fixtures preserve unmanaged 0664 service files and block them with service-inventory diagnostics. Explicit Chezmoi umask 002 is not overridden. Remaining unmanaged/explicit-policy blockers require manual review; no Arcane setup, permissions or lifecycle changes were made.

- Final verification passed: preparation contract (20 helper groups + 3 cross-platform/native-Chezmoi groups + PowerShell guidance), BB server contract, setup reliability, Homebrew results, macOS CLT, shared Node runtime (18 Python cases and both 1409-assertion PowerShell modes), headless Paseo, AI-agent, PowerShell setup reliability, weekly regressions, pending reboot, Bash syntax, ShellCheck, README markdownlint and git diff --check.
- Tightened final fixtures to require exactly one native command with unchanged argv per call, identical wrappers, and unchanged unmanaged file bytes/modes across apply. Reran all three permission integration groups successfully.
- Optional integrations skipped: PI_RUNTIME_DOTFILES_SOURCE; managed-skills native discovery/snapshot and render/setup without MANAGED_SKILLS_CLI/PI_SKILLS_DOTFILES_SOURCE. Native macOS/WSL/ARM installation and actual Arcane rerun remain rollout checks, not fixture claims. PowerShell used /tmp/pi-shared-runtime-pwsh.2SlAPL/pwsh.
- Self-review confirmed shared preparation payload/wrapper equality, no relaxed safety predicates, no automatic chmod/chown, no changed npm policy or server/enrollment lifecycle, preserved caller masks and explicit native config. Version bumps are +1 in all five Bash setup scripts. Only repository files and temporary fixtures changed during implementation; no commit, push or deployment.

User authorized merging this change into remote main. Fetched origin/main and confirmed it exactly matches the implementation base; preparing an attributed commit and normal fast-forward push with repository hooks enabled. This does not authorize running setup on Arcane.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Fixed the BB preparation dotfiles permission regression across all five Bash setup scripts. Full Chezmoi init/update/apply now receives the same additive go-w mask as BB server setup, preventing ordinary managed paths from reverting to 0775/0664 before preparation. Stricter caller masks and explicit Chezmoi configuration retain their precedence.

Added allowlisted operation/location/reason diagnostics with fail-closed terminal-output validation. Existing safety checks, unrelated services, BB ownership, npm policy and enrollment state are preserved. Unmanaged writable paths remain blocked for private manual review rather than being recursively repaired. README documents recovery; all five script versions were incremented.

Verification: native Chezmoi regression fixtures reproduced the failure before the patch and now pass repeated preparation using inert artifacts; secret-safety, unmanaged-path preservation and real caller/argv fixtures pass. Preparation/server, reliability/PowerShell, runtime, headless, AI-agent, CLT/Homebrew, weekly and reboot suites plus lint/diff checks passed. Optional external-source/native-skill integrations were skipped where unconfigured. No Arcane changes, deployment, commit or push; actual native rollout remains unverified.
<!-- SECTION:FINAL_SUMMARY:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 Run affected preparation/server, reliability, shared runtime and headless contracts, available PowerShell fixtures, Bash syntax, ShellCheck and diff checks.
- [x] #2 Review scope, preservation and fixture-versus-live evidence; record limitations and final summary.
<!-- DOD:END -->
