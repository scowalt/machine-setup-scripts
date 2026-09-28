---
id: TASK-48
title: Prepare non-server machines for manual BB enrollment
status: Done
assignee:
  - '@pi-task48'
created_date: '2026-09-28 03:44'
updated_date: '2026-09-28 15:02'
labels:
  - setup
  - bb
dependencies: []
references:
  - mac.sh
  - ubuntu.sh
  - pi.sh
  - bazzite.sh
  - wsl.sh
  - win.ps1
  - tests/bb-server-contract.sh
  - README.md
  - CONTEXT.md
documentation:
  - 'https://github.com/get-bb/bb/blob/main/docs/platform-support.md'
  - 'https://github.com/get-bb/bb/blob/main/docs/multiple-devices.md'
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Approved design: install and maintain BB execution-machine preparation software on supported non-main-server machines, including work machines. Each machine will be manually enrolled by the user with one selected independent BB main server over private Tailscale. This task changes repository scripts and documentation only; the user will run setup and pair machines later.

Preparation is distinct from enrollment: success means the CLI and daemon software are installed and verified, not that a daemon is running or a machine appears on a server. Upstream manual enrollment owns the paired installation and startup service. Native Windows is unsupported by BB; Windows execution uses WSL2. Preserve the existing WSL HEADLESS=1 rejection and install during normal supported WSL2 runs.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Supported macOS, Ubuntu, Raspberry Pi, Bazzite and WSL2 non-server setup runs install or update stable official BB preparation software by default on personal and work machines, using the shared Node runtime. Unsupported platform or runtime conditions are reported accurately rather than claiming readiness.
- [x] #2 Preparation verifies the CLI, daemon artifacts and necessary native dependencies without enrollment, daemon/server startup, provider authentication or inference. An unpaired but verified installation is a successful preparation result and prints the manual next step.
- [x] #3 The new preparation path preserves existing BB main-server installations, services, state and package ownership even if BB_SERVER is unset or 0. Existing opted-in Ubuntu server behavior and its process-over-env semantics remain intact; no automatic role conversion occurs.
- [x] #4 Reruns preserve manual pairings, machine identity, credentials, server URLs, server-managed daemon versions and startup services. No re-enrollment, daemon restart, service replacement or new Tailscale route is part of preparation; unverified/unmanaged conflicting installations are not taken over.
- [x] #5 Native npm security policy, shared-runtime/project selection, shell profiles, existing environment files, unrelated packages and user data remain intact. Failed required installation or verification makes setup incomplete while unrelated work and log finalization continue.
- [x] #6 WSL2 installation follows the existing script gates: normal WSL2 runs prepare BB, HEADLESS=1 retains the current unsupported early failure. Native Windows setup explains the supported WSL2 path without installing BB natively or provisioning/enrolling WSL on the user behalf.
- [x] #7 README documents one selected server per execution machine, manual pairing using private Tailscale access, no service before pairing, separate upstream paired-installation ownership, rerun behavior and platform limits. Glossary terms remain distinct. Update modified setup-script versions and relevant agent guidance.
- [x] #8 Isolated extracted-helper fixtures cover initial installation, repeated runs and stable updates, BB server exclusions including unset/0, existing paired/custom installations, npm policy and native verification failures, shared-runtime prefix changes, platform/headless/work gates and final failure aggregation. Tests never run live setup, enroll machines, start real BB services, mutate Tailscale or make model requests.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Add a shared, identical Bash preparation helper and wire it into the five Bash scripts after the shared runtime is ready, independently of unrelated Pi/Paseo mutation gates. Retain existing HEADLESS/platform gates and Ubuntu BB_SERVER selection. Native Windows gets WSL2 guidance only.
2. Preflight local BB roles and package ownership before mutation. Skip the new path for verified main-server installations even when the flag is absent, preserve enrolled/private and custom installations, and refuse ambiguous package ownership instead of adopting or updating a running server/daemon.
3. Install/update the setup-owned stable bb-app preparation copy with native npm and command-scoped native-addon allowances only when compatible with effective security policy. Verify actual CLI/daemon files and native modules without launching BB; support safe reruns and compatible shared-runtime prefix changes. Do not touch ~/.bb or ~/.bb-machines enrollment/service state.
4. Add extracted-helper tests with temporary homes and inert package/lifecycle commands for first install, update, partial failure/recovery, main-server and paired-daemon preservation, conflicting ownership, npm policy, runtime transitions, platform/headless/work gates and final error aggregation. Assert that no enrollment, server/daemon launch or network/service mutation is invoked.
5. Update README, glossary as needed, relevant agent guidance and each changed script version. Run ShellCheck, Bash syntax, BB preparation/server contracts and affected reliability/runtime/headless regressions; use available PowerShell fixtures for Windows guidance and report unavailable/native verification separately. Self-review preservation and scope before closing the task.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- User approved the installation-only specification after two design rounds, including work machines, one selected main server per machine, private Tailscale, manual pairing, normal WSL2 preparation, native Windows guidance, unchanged WSL HEADLESS=1 rejection and preservation of paired daemon versions/services.
- Read-only verification used installed BB 0.44.0 package metadata, README, host-daemon launcher, manual machine installer and the upstream platform-support reference. Unenrolled launcher exits instead of running; native enrollment installer normally installs a private server-matched package and launchd/systemd service. Native Windows is excluded by the package OS list.
- Available: backlog, Node/npm, Python, ShellCheck and Bash. pwsh is not on PATH; optional fixture paths will be checked before verification. No setup, enrollment, BB lifecycle or Tailscale mutation has run.
- Implementation plan recorded for user review. Only glossary and task metadata changed so far; runtime implementation is awaiting plan approval.

- User approved implementation by explicitly requesting a BB subagent in this conversation. The recorded plan is now authorized; prior awaiting-approval wording is historical. Parent will delegate one implementation owner into the existing environment/worktree and review the resulting diff and tests. No live rollout, enrollment or service changes are authorized.

Implementation owner started in the existing shared worktree with the approved plan; no further approval requested. Repository-only extracted fixtures; status remains In Progress for parent review.

Implemented identical installation-only helpers in all five Bash scripts, Windows WSL2 guidance, version bumps and README/agent guidance. Preparation uses its own private npm prefix under ~/.local/share/setup-bb-machine with no global BB bins or shell changes, avoiding upstream enrollment fallback ownership. Existing BB state/services/overrides defer without readiness claims; unmanaged commands and ambiguous running BB processes fail closed. Server opt-in implementation is unchanged. Inert native-npm tarball tests caught and fixed the need to pre-create prefix/lib/node_modules; addon rebuilds handle later shared Node changes. New fixtures and final regression verification are in progress; no live setup/enrollment/lifecycle/Tailscale or remote changes.

Final verification passed: bash -n and ShellCheck on all five changed Bash setup scripts and tests/bb-machine-preparation-contract.sh; new preparation contract (14 Python groups plus PowerShell guidance/HEADLESS fixture); bb-server-contract.sh; setup-reliability-contract.sh; test_homebrew_results.py; shared-node-runtime-contract.sh (18 Python cases, native mise inventory, PowerShell 1409 assertions); headless-paseo-daemon-contract.sh; ai-coding-agent-contract.sh; setup-reliability-powershell.ps1; README/CONTEXT markdownlint; git diff --check. PWSH_BIN=/tmp/pi-shared-runtime-pwsh.2SlAPL/pwsh (7.6.6). Headless tests needed a temporary PATH entry pointing jq at /usr/bin/jq because the inherited mise shim fails under fixture HOME; no product change was needed.
Skipped: optional shared runtime/dotfiles convergence fixture because PI_RUNTIME_DOTFILES_SOURCE was unset. Native macOS/WSL2/ARM BB installation and manual pairing remain rollout-only, not exercised. Full CLAUDE.md markdownlint still reports 58 pre-existing issues; checked HEAD baseline with the same linter/config and confirmed the same count. No new Markdown issues.
Self-review: existing main-server implementation/selection untouched except the separate non-server branch; known server/enrollment state freezes prep before runtime/npm, including BB_SERVER unset/0. Fixture snapshots prove paired identity/config/private package/service bytes unchanged; custom running processes and stopped user-service references block mutation. Native npm uses offline bundled inert fixtures, and all BB entry artifacts throw if executed. Only read-only process/service inspection is added; no BB lifecycle, authentication, enrollment, Tailscale, remote or real package changes were executed. Existing CONTEXT.md task edits preserved. No commits/pushes/PRs. Ready for parent review; intentionally remains In Progress.

- Parent independently passed preparation contract (14 groups plus PowerShell), existing BB server contract, Bash syntax, ShellCheck and git diff --check. Source/dynamic review found two blockers: explicit --prefix changes npm default globalconfig, silently dropping original-prefix ignore-scripts/registry policy; WSL prep permits only HEADLESS unset/0 rather than preserving the existing exact HEADLESS=1 gate. Both reproduced in temporary fixtures. Existing native-npm test pins its own --globalconfig, hiding the first problem.
- Also reproduced first-install failure with an ordinary unrelated user-service symlink to an account-owned harmless unit; read-only preflight currently requires every service/plist to be a nonempty regular leaf. Requested narrow preservation-friendly handling without following unsafe targets or rewriting services. No live changes occurred. Reopened affected checks for the same implementation child to repair; parent verification remains pending.

Addressing parent review in the same worktree: adding native default-globalconfig regression fixtures, exact-match WSL HEADLESS cases, and unrelated/actual linked user-service reference fixtures before patching. Scope remains installation-only; no live operations or new threads.

Parent-review fixes completed in the same worktree. First reproduced all three exact failures with new isolated tests: original-prefix ignore-scripts=true was bypassed, HEADLESS=true/false were incorrectly rejected, and an unrelated linked unit blocked first install. Those regressions now pass.

- npm: capture native --global userconfig/globalconfig before any --prefix, then supply only those paths to every policy probe/install/rebuild. Value precedence remains native and config/path failures precede ownership reservation. The native offline fixture no longer injects a test globalconfig; it uses ordinary HOME/original-prefix resolution. It proves default-global denial blocks without a prep tree, and inspects actual install/rebuild argv through native @npmcli/config for original registry, allow-git/allow-remote restrictions, a synthetic auth-preserved boolean (never token output), user/environment value overrides and explicit config-path overrides.
- WSL: platform detection is separate from the exact HEADLESS=1 guard. Unset/empty/0/true/false pass the helper and existing early runner gate; 1 still fails. Windows guidance/no-login rejection remains unchanged.
- Services: read-only reference inspection accepts trusted account/root-owned regular targets behind ordinary service links (including Homebrew-style opt ancestor links), zero-length registrations and native /dev/null masks. It never rewrites links or targets; direct or linked preparation references, dangling/unreadable targets, unsafe ownership/modes and FIFOs still block. Preparation-owned artifact/metadata link checks are unchanged. Fixtures snapshot service links, targets and prepared files across allowed and blocked reruns.
Shared helpers remain identical. Bumped all five changed Bash versions again; updated README and agent guidance. No server implementation, native Windows install behavior, real lifecycle, auth, enrollment, Tailscale, remote or live package state changed.
Verification rerun: preparation contract now 17 Python test groups plus PowerShell; bb-server-contract.sh; setup-reliability-contract.sh; test_homebrew_results.py; shared-node-runtime-contract.sh; headless-paseo-daemon-contract.sh; ai-coding-agent-contract.sh; setup-reliability-powershell.ps1; Bash syntax and ShellCheck on the five Bash scripts/new shell contract; README/CONTEXT markdownlint; git diff --check. All passed. Used PWSH_BIN=/tmp/pi-shared-runtime-pwsh.2SlAPL/pwsh and a temporary native-jq PATH entry for headless fixtures. Optional dotfiles convergence remains skipped without PI_RUNTIME_DOTFILES_SOURCE. CLAUDE.md lint remains 58 baseline issues, now compared by normalized diagnostic text against HEAD with no new issues. Native platform installation/manual pairing remain rollout-only. AC5/6/8 rechecked against this evidence; final-review DoD remains open for parent, and status remains In Progress.

- Parent final review accepted all three corrections: original npm user/global config paths are captured before the destination prefix changes and exercised through native offline policy/auth/registry precedence fixtures; WSL uses the existing exact HEADLESS=1 semantics; read-only service inspection accepts ordinary trusted links, empty registrations and /dev/null masks but blocks actual preparation references/unsafe targets without mutation. Shared helpers are identical; main-server management and manual enrollment ownership remain separate.
- Parent independently passed final preparation contract (17 groups + PowerShell), BB server contract, Bash syntax, ShellCheck, setup reliability, Homebrew results, shared Node runtime (including 1409-assertion PowerShell runs in both argument modes), PowerShell setup reliability and git diff --check. Parent also passed unaffected headless and AI-agent contracts during review; child reran them after the corrections. Optional dotfiles convergence remains skipped without PI_RUNTIME_DOTFILES_SOURCE. Native platform installation/enrollment remains user rollout verification; no live setup, lifecycle, auth, Tailscale or remote changes, commits or pushes.
- Final parent verification complete; TASK-48 marked Done for repository implementation, not deployed fleet state.

User requested merging the reviewed implementation into remote main. Fetched origin/main and confirmed it exactly matches the implementation base; preparing a normal attributed commit and non-force push with repository hooks enabled. No deployment is included.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Implemented installation-only BB machine preparation in all five Bash setup scripts, including work machines; native Windows explains the supported WSL2 path. The user retains manual enrollment with one chosen server over private Tailscale.

Changes:

- Identical helpers install a separately owned stable npm copy, verify real CLI/daemon artifacts and native dependencies without starting BB, and support idempotent retries and shared-runtime changes.
- Preserve existing main servers, paired private packages, credentials and services. Original npm configuration and security policy stay effective despite the separate installation prefix.
- Preserve exact WSL HEADLESS=1 rejection and unrelated trusted service links/masks. Failures aggregate independently of Pi/Paseo gates.
- Added 17-group extracted/native-offline preparation fixtures plus PowerShell guidance coverage; updated documentation, glossary and setup-script versions.

Verification:

- Parent independently passed preparation/server contracts, Bash syntax/ShellCheck, reliability, shared-runtime/PowerShell and Homebrew tests, plus headless/AI-agent regressions during review. Child confirmed final Markdown validation; CLAUDE.md retains 58 baseline diagnostics. git diff --check passed.
- Optional dotfiles convergence skipped without its source path. Native macOS/WSL2/ARM installation and actual manual pairing remain rollout checks. No live-machine changes or commits.
<!-- SECTION:FINAL_SUMMARY:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 Run Bash syntax checks and ShellCheck on modified shell files, the new BB preparation contract, existing BB server contract and affected setup-reliability/shared-runtime/headless contracts; run PowerShell fixtures if available and document skipped/native-only verification.
- [x] #2 Review the final diff for scope, idempotency, secret safety, main-server and paired-daemon preservation, and accurate fixture-versus-live claims.
<!-- DOD:END -->
