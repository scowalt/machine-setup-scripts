---
id: TASK-47
title: Preserve BB-safe directory modes through Ubuntu dotfiles setup
status: Done
assignee:
  - '@pi'
created_date: '2026-09-28 02:27'
updated_date: '2026-09-28 02:58'
labels:
  - setup
  - bb
  - chezmoi
dependencies: []
references:
  - ubuntu.sh
  - tests/test_bb_directory_preflight.py
  - tests/bb-server-contract.sh
  - 'https://logs.scowalt.com/logs/devinabox/2026-09-28-02-22-02-421.log'
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Confirmed on devinabox: manual removal of group-write permission is undone earlier in the next setup run. Ubuntu calls chezmoi update --force (which applies by default) and chezmoi apply --force before BB. With inherited umask 0002 and no configured Chezmoi umask, native Chezmoi v2.70.0 changes existing 0755 .config/systemd directories back to 0775. Reproduced twice using an inert temporary source/HOME and the real extracted BB preflight. Source directory mode is not the cause. Fix the setup/Chezmoi interaction, not the BB safety gate or a repeated manual chmod.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 On BB_SERVER=1 Ubuntu runs, directory-applying Chezmoi operations do not reintroduce inherited group/world write permissions before BB, including initialization, update-and-apply, and full apply.
- [x] #2 Keep the restriction scoped to relevant Chezmoi subprocesses; preserve stricter caller masks, the caller shell umask, existing environment/profile files, explicit Chezmoi configuration overrides, unrelated services, credentials and BB safety checks. Non-opted-in behavior remains unchanged.
- [x] #3 Native Chezmoi fixtures with inert temporary source/HOME demonstrate repeated chmod-then-apply convergence followed by successful real BB directory preflight, including source-mode independence, stricter masks, and conflicting explicit umask remaining blocked without config rewriting. Exercise setup call-site wiring with inert Git/network commands.
- [x] #4 Update Ubuntu version/documentation as needed and pass syntax, ShellCheck, BB and affected dotfile/runtime/setup regression contracts. No live setup, source checkout update, permission repair, service mutation or model requests during development.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Approved by the user: implement TASK-47 using the established native-apply and setup call-site seams.

1. Add an isolated native failing regression for 0755 -> chezmoi apply under 0002 -> 0775 -> real BB directory preflight rejection. Use only an inert source, temporary HOME/config/cache/state, and scrubbed environment.
2. On Ubuntu BB_SERVER=1 only, add umask go-w inside a subprocess wrapper for all three init --apply branches, update-and-apply, and the main full apply. Preserve caller/stricter masks, native config precedence, non-opted-in behavior, existing failures, and BB ownership/link/mode checks; do not change shared Node helpers or live state.
3. Cover all actual call sites and argument preservation with inert commands; exercise native repeated apply, existing unsafe/new directories, source mode independence, stricter masks, opt-out and explicit configuration conflicts. Preserve unrelated content/modes and config in fixtures.
4. Wire into the BB contract, bump Ubuntu version, document the scope and explicit/standalone Chezmoi caveats, run BB and affected dotfile/runtime/setup regressions plus lint, then self-review and report without committing/pushing or running live setup.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Authenticated collector logs match devinabox local runs 2026-09-27-221332.log and 2026-09-27-222114.log, both Ubuntu version 271. Both show the Chezmoi update before the mode-775 BB error. Live read-only metadata showed all three directory ctimes at 22:21:26 during the latter run (started 22:21:14). Current process umask is 0002; the native account Chezmoi config has no top-level umask. Only this allowlisted value was printed; no credentials/config content exposed.
- Ran /usr/bin/python3 /tmp/bb-chezmoi-permission-repro.py with native Chezmoi v2.70.0 (6624b49786a9f039f05b4d929c35fd4f4bf17337). Manual 0755 -> native apply under 0002 -> 0775 for .config, .config/systemd, and .config/systemd/user, followed by the exact current BB diagnostic and exit 1. Repeated twice with the same result. No real HOME changes.
- Controlled matrix: changing only source modes to 0755 still produces 0775; changing only process umask to 0022 gives 0755 and BB exit 0 across repeated runs; 0077 yields 0700 and exit 0. Explicit config umask 0002 overrides process 0022 and stays blocked; explicit config 0022 under process 0002 passes. This isolates inherited process umask as the actual cause on this host, not source modes or another installer.
- Verified Bash subshell umask go-w maps 0002 -> 0022, preserves 0022/0077, and leaves the caller mask unchanged. Native chezmoi update --help confirms --apply defaults true. Production code and live directories/services are untouched; implementation requires approval of the plan.

User approved implementation of TASK-47. Beginning with native failing regression coverage, then the narrowly scoped Chezmoi invocation fix; no live changes or publishing authorized.

- Added tests/test_bb_dotfiles_umask.py. Before the implementation it reproduced the exact mode-775 BB diagnostic on both native apply attempts (2 failed subtests). After wrapping the full-apply call, the same regression passed.
- Added the scoped with_bb_dotfiles_umask wrapper to all five directory-applying call sites. The shared Node files-only apply remains untouched. Ubuntu banner is 272. Added a controlled diagnostic reminder for explicit Chezmoi umask overrides.
- Eight test methods now pass, including 125 call-site/selection/mask combinations and real native apply with preserved unrelated files/modes/config. Native conflicting umask 002 remains rejected; 077 stays private. Git/clone/update boundaries are inert; native execution is confined to full apply against the synthetic source. Broader regression checks pending.

- Complete BB contract passed, including all 10 preflight tests and all 8 new test methods with native Chezmoi enabled. Bash syntax and ShellCheck passed for ubuntu.sh and the modified contract. Setup reliability, shared Node runtime, weekly log audit/dotfile initialization, headless Paseo, Go wiring, and Telegram contracts all passed. Optional PowerShell and unavailable dotfiles/integration cases reported skips. Broader runs used a temporary PATH with resolved Python/system jq; no host configuration changed.
- Also verified the no-Chezmoi test path: mocked call-site tests pass and native subcases explicitly skip instead of attempting an installation. README documents this and the explicit-config/standalone-apply limitations. Self-review found no production changes outside the approved Ubuntu call sites, diagnostic, and version banner; shared helpers and BB checks remain intact.

- Final follow-up checks also passed: Attention-kind retirement, RTK retirement, Pi profile permissions, and Pi prose retirement, including their ordering checks around the wrapped full apply. Markdownlint and git diff --check passed after formatting the task plan via CLI. No debug instrumentation, live setup/service mutations, or commits/pushes were performed.

User authorized committing TASK-47 and publishing it to remote main. Preserve the implementation scope and live-state isolation; integrate any newer remote commits normally and run repository hooks without bypassing them.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
## Summary

```text
BB_SERVER=1 on Ubuntu
  Chezmoi init / update-and-apply / full apply
    subprocess umask: add go-w, retain stricter restrictions
  BB directory preflight: unchanged safety checks
```

Ubuntu version 272 prevents the earlier dotfile apply from undoing BB-safe directory modes. The cause was Chezmoi deriving target permissions from inherited umask 0002, not a failed manual chmod. All five directory-applying call sites use the scoped wrapper. Caller masks, opt-out behavior, native overrides, command failures, shared Node helpers, and existing data remain preserved. Added override guidance, README documentation, and tests/test_bb_dotfiles_umask.py to the BB contract.

## Evidence

- **Before:** The new native regression failed twice: corrected 0755 directories became 0775, producing the exact BB preflight error.
  **After:** The same regression passes; all 8 test methods pass, including 125 call-site/selection/mask combinations, repeated native apply, source-mode independence, stricter masks, explicit overrides and unrelated-state preservation. The existing 10 directory-preflight tests also pass.
- Passed: BB, setup reliability, shared Node runtime, weekly log audit/dotfile initialization, headless Paseo, Go wiring, Telegram, Attention-kind retirement, RTK retirement, Pi profile permissions and Pi prose contracts; Bash syntax, ShellCheck, Markdownlint and whitespace checks.
- Native Chezmoi v2.70.0 ran against synthetic source/HOME/config/cache/state only. Clone/update/Git operations were inert recordings. Optional PowerShell and unavailable integration cases skipped; the no-Chezmoi path also correctly passes mocked tests and skips native subcases.

## Merge Danger

**Door:** Two-way

The code policy is reversible; managed paths retain their reconciled modes until another apply or deliberate permission change. No contents are deleted by this change.

**Blast Radius:** Permissions

Only BB-enabled Ubuntu Chezmoi subprocesses get the additional write restriction on managed target modes. Explicit native umask overrides still win and unsafe results remain blocked. Standalone Chezmoi runs are unchanged. No live permissions/services were changed; live deployment and subsequent BB prerequisites remain unverified.
<!-- SECTION:FINAL_SUMMARY:END -->
