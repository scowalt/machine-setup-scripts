---
id: TASK-49
title: Install bb desktop on headed supported machines
status: Done
assignee:
  - '@thr_yvgind9msw'
created_date: '2026-09-28 15:26'
updated_date: '2026-09-28 15:26'
labels: []
dependencies: []
references:
  - 'https://github.com/get-bb/bb#download-the-desktop-app'
  - 'https://github.com/get-bb/bb/releases/tag/desktop-v0.44.0'
  - README.md
  - CONTEXT.md
documentation:
  - docs/plans/2026-09-28-001-feat-bb-desktop-headed-machines.md
  - docs/research/2026-09-28-bb-desktop-linux-sandbox.md
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Add the native bb agentic IDE desktop app to the desired state of headed personal and work machines. Use official stable releases on Apple Silicon macOS and native Linux x64 (Ubuntu/Bazzite; Linux desktop is alpha). Unsupported platforms receive an explicit skip, not a browser/server substitute. Keep installation separate from bb server deployment and user configuration.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Use the existing exact HEADLESS=1 exclusion, independent of graphical-session detection and WORK_MACHINE; headless runs leave desktop installations untouched.
- [x] #2 Install official stable bb desktop artifacts on Apple Silicon macOS and native Linux x64 Ubuntu/Bazzite with normal application-menu integration; explicitly skip Windows, WSL, Intel macOS, and Raspberry Pi/Linux ARM without fallback installation.
- [x] #3 Idempotently install/update on setup reruns without downgrading newer installations; defer replacement while the desktop app is running and do not stop it.
- [x] #4 Do not launch the app, enable autostart, authenticate providers, alter connections/user state, mutate existing BB_SERVER deployments, or add shell configuration.
- [x] #5 Validate releases and installed artifacts, preserve existing installations on failed/unsafe updates, and aggregate real installation/verification failures into the final failed setup result without bypassing unrelated work or log finalization.
- [x] #6 Cover all platform/headless gates, idempotency, newer/running installations, unsafe paths, download/verification failure, preserved user/server state, and caller failure propagation using extracted helpers and inert temporary fixtures; update documentation and modified script versions.
- [x] #7 On eligible Linux, verified artifact/menu installation may succeed while GUI/sandbox launch compatibility remains unverified, with an explicit warning. Do not veto installation using the global AppArmor flag or a generic unshare probe, launch bb to test compatibility, or change security policy; actual artifact/safety/installation verification failures remain fatal.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Wire an explicit bb desktop step into all six setup entry points with the accepted headed/platform gates and existing result aggregation.
2. Resolve and verify official stable artifacts, stage safely, and install macOS bundles/Linux AppImages with application-menu integration.
3. Preserve newer/custom/nightly/running installations, bb user/server state, npm policy, and shell configuration; fail closed on unsafe or unverifiable changes.
4. Add inert extracted-helper fixtures for release integrity, eligibility, idempotency, deferral, rollback, safety, and caller outcomes.
5. Update README and script versions; run desktop/server/reliability/Homebrew/headless contracts and lint. Native GUI checks remain rollout work.
Detailed plan: docs/plans/2026-09-28-001-feat-bb-desktop-headed-machines.md. User authorized implementation in a BB child thread; parent review follows.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- User approved the initial four recommendations: exact HEADLESS gate, official supported targets including Linux alpha, stable install/update with newer/running protection, and installation-only behavior.
- Confirmed official desktop-latest 0.44.0 assets and published SHA-256 digests; no native Windows, Intel macOS, or Linux ARM desktop artifact. macOS packaging minimum is 13.0.0.
- Desktop bundles a local runtime and uses normal bb data by default; never launch it for setup verification. Existing server lifecycle/configuration remains outside scope.
- Recorded headed-machine vocabulary in CONTEXT.md and prepared the detailed implementation plan. No setup script changes or live installations performed.
- Bash, Python, Node, curl, ShellCheck, Homebrew, Bun, and Chezmoi are available. No pwsh/PWSH_BIN found; native macOS/Windows/GUI validation remains unproven.

User requested implementation in a BB subagent. Delegating to one native child thread in the current worktree so it sees the uncommitted task/plan; child is sole implementation writer, parent reviews afterward.

Implementation owned by BB child thr_yvgind9msw in the shared worktree. Approved plan accepted; no new approval gate. Beginning upstream/artifact and caller integration review.

Implemented embedded shared Bash gating and supported-platform Python installer, plus inert desktop fixtures. Linux identifies installed bytes through official release digests (bounded immutable-release catalogue), uses extract-and-run menu integration without a bb CLI shim, and fails rather than weakening namespace/AppArmor policy. macOS verifies bundle identity, signing team and notarized Gatekeeper assessment without launch. Staged rollback preserves prior app/menu; uncertain inspection fails, verified running apps defer. Initial 31-case desktop suite passes; requested broader regressions and native-test availability checks pending.

- Completed 40 inert extracted-helper fixtures, passing with both the default Python and native /usr/bin/python3. Coverage includes all entry-point/headless/work/architecture gates (including Rosetta), metadata/redirect/integrity checks, updates/idempotency/newer/self-updated bytes, process ownership/deferral, unsafe links/FIFOs/hardlinks/metadata, Bazzite HOME and XDG alias handling, rollback, menu integration, unchanged state sentinels, and actual extracted Bash caller aggregation/log finalization.
- Passed: bash tests/bb-desktop-contract.sh; PYTHONDONTWRITEBYTECODE=1 /usr/bin/python3 tests/test_bb_desktop.py; bash tests/bb-server-contract.sh; bash tests/setup-reliability-contract.sh; python3 tests/test_homebrew_results.py; PATH="/usr/bin:/bin:${PATH}" bash tests/headless-paseo-daemon-contract.sh; Bash syntax and ShellCheck on all five modified setup scripts plus the new contract; bunx --no-install markdownlint-cli README.md CLAUDE.md CONTEXT.md docs/plans/2026-09-28-001-feat-bb-desktop-headed-machines.md; git diff --check.
- The bare headless Paseo contract initially failed because inherited mise jq shim configuration is untrusted under a temporary HOME. Confirmed the cause and reran successfully with existing native /usr/bin tools first; no host configuration was changed.
- PWSH_BIN/pwsh/powershell remain unavailable, including bounded executable discovery. Added Windows parsing/wrapper fixtures but did not execute them; static Windows wiring coverage passes. Native macOS signature/notarization/menu and Linux GUI/sandbox/server-coexistence checks remain rollout-only.
- Safety decisions for review: Linux uses extract-and-run (no FUSE dependency), requires glibc 2.35+ and working user namespaces, and refuses restricted AppArmor policy rather than changing it. Unknown installed AppImage digests after the bounded 500-record catalogue fail closed. Root-owned/shared-writable system Applications copies are preserved and require manual reconciliation. Interrupted rollback retains a recovery lock/backup; ordinary failures clean staging.
- All six setup versions incremented; README and concise repository guidance updated. Parent planning files preserved. No live setup, real desktop installation/launch, service changes, remote/fleet operations, model requests, commits, pushes, or PRs.

Parent review: independently reran bash tests/bb-desktop-contract.sh (40 pass, PowerShell skip) and git diff --check. Reproduced an uncovered Linux inventory failure using only a temporary synthetic /proc fixture: a same-UID unrelated process with Name=unrelated, executable=/usr/bin/unrelated, and a PermissionError reading environ makes running() fail. The implementation currently opens environ for every same-UID process before determining relevance. Sending back to the existing implementation child to narrow inspection safely and add coverage. Also requesting a source-backed assessment of the blanket AppArmor restriction gate and its effect on default Ubuntu desktop eligibility. AC 5/6 reopened pending review fixes.

Parent follow-up: reproduced the unrelated-environment PermissionError with a single inert synthetic-proc regression. Investigating executable-first candidate filtering, custom AppImage temp directories, inherited APPIMAGE values, and native AppArmor policy evidence. AC 5/6 remain open while the follow-up is verified.

- Follow-up process regression fixed and verified: executable-first relevance filtering no longer opens unrelated same-UID environments, including native-looking titles and inherited APPIMAGE on child tools. Exact AppImage controllers need no environment read. Relevant unknown executable/environment evidence, candidate ownership conflicts, PID/UID/executable changes and malformed evidence still fail closed. Custom TMPDIR mounted/extracted paths are recognized. Self-review additionally covered ordinary R/S scheduling changes and exited candidates so neither becomes a false ownership failure/deferral. Shared payload copies and three changed script versions updated (mac 246, Ubuntu 274, Bazzite 126).
- Desktop suite increased from 40 to 60 tests. The exact parent reproduction was observed red before the fix, then green. New integration coverage exercises real extracted inventory through both installation and update, with only synthetic proc trees. Both default Python and /usr/bin/python3 pass all 60 cases.
- Re-ran and passed: bash tests/bb-desktop-contract.sh; PYTHONDONTWRITEBYTECODE=1 /usr/bin/python3 tests/test_bb_desktop.py; bash tests/bb-server-contract.sh; bash tests/setup-reliability-contract.sh; python3 tests/test_homebrew_results.py; PATH="/usr/bin:/bin:${PATH}" bash tests/headless-paseo-daemon-contract.sh; Bash syntax and ShellCheck on all modified Bash scripts/new contract; Markdown lint including the new research note; git diff --check. PowerShell remains unavailable and its execution fixtures report a skip. No live process inventory, desktop launch, security-policy change or service operation was used.
- Source-backed AppArmor assessment: Ubuntu 24.04 enables the restriction by default but per-app profiles can grant different permissions. The flag cannot prove bb is denied; generic unshare success/failure is also not bb-context/Chromium sandbox evidence. Extract-and-run addresses FUSE only. Details, primary citations and the supported-configuration matrix are in docs/research/2026-09-28-bb-desktop-linux-sandbox.md.
- Compatibility is NOT declared solved. The conservative guard remains provisionally, now explicitly labeled sandbox-compatibility-unverified rather than a proven prerequisite failure. It still prevents installation on default Ubuntu 24.04 and can reject an already permitted per-app policy. AC 2 reopened and AC 5/6 left open pending the success-contract decision, despite the process fix regression passing. Recommended decision: permit verified install-only success with a clear unverified-launch compatibility warning, removing these proxy vetoes without policy changes; otherwise narrow/condition the runnable-desktop promise and authorize a separate native prerequisite/verification path. No implicit AppArmor exceptions, sysctl changes, setuid helpers or --no-sandbox fallback were added.

User approved Q5 ("Your spec is fine"): verified Linux installation counts as successful with an explicit warning that native GUI/sandbox launch compatibility is unverified. This authorizes removal of the provisional global-AppArmor/generic-unshare veto, not any security-policy change or app launch. Added acceptance criterion for the clarified success contract; delegating final implementation to the same BB child.

Implementing the approved Q5/AC 7 install-only contract. Added red-capable inert tests for AppArmor flag/per-app policy independence, missing/failing namespace probes, unknown sandbox state and controlled Linux success warnings; observed them fail on the provisional implementation before removing the veto. Runtime-baseline, integrity, identity, process-safety and promotion checks remain unchanged. Shared helper copies and documentation are updated; final full regression run follows.

- Approved install-only contract implemented: removed global AppArmor/sysctl inspection and the generic unshare command entirely from all supported desktop payloads. The glibc baseline and all existing artifact/identity/path/ownership/process/rollback checks remain intact.
- Shared wrappers accept only exact installed/current/newer-preserved results with zero helper status before emitting the controlled Linux warning: installation is verified, GUI/sandbox launch compatibility is unverified, and no launch/security-policy change was performed. Running-app deferral remains a separate warning; macOS and headless/unsupported reporting remain accurate. Extra/multiple terminal helper output and inconsistent status still fail closed.
- Inert suite now has 64 passing tests on both interpreters. Added regression evidence for flag=1 and opaque existing per-app policy without inspection/mutation, missing/failing unshare without invocation, unknown sandbox state, retained real integrity failure under restricted policy, all successful Linux outcomes, macOS/skip/deferral warning exclusions and strict extra-output rejection. All prior process-inventory and genuine failure regressions remain.
- Passed exact commands: bash tests/bb-desktop-contract.sh; PYTHONDONTWRITEBYTECODE=1 /usr/bin/python3 tests/test_bb_desktop.py; bash tests/bb-server-contract.sh; bash tests/setup-reliability-contract.sh; python3 tests/test_homebrew_results.py; PATH="/usr/bin:/bin:${PATH}" bash tests/headless-paseo-daemon-contract.sh; bash -n and shellcheck for mac.sh ubuntu.sh bazzite.sh wsl.sh pi.sh tests/bb-desktop-contract.sh; bunx --no-install markdownlint-cli README.md CLAUDE.md CONTEXT.md docs/plans/2026-09-28-001-feat-bb-desktop-headed-machines.md docs/research/2026-09-28-bb-desktop-linux-sandbox.md; git diff --check.
- Updated all shared copies and newly changed Bash versions (mac 247, Ubuntu 275, Bazzite 127, WSL 209, Pi 226). README, approved plan, primary-source research note and CLAUDE.md now consistently record the approved decision, with no unresolved-decision claim. Earlier notes describing the provisional blocker are historical and superseded by this approval/implementation.
- PowerShell remains unavailable; its execution/parsing fixture was honestly skipped. Native macOS signature/menu and Linux GUI/sandbox/server-coexistence checks remain rollout-only. No real setup, desktop/native launch probe, live process inventory, policy/service mutation, fleet operation, additional agent, commit, push or PR was performed. All seven ACs are supported by implementation/fixture evidence; task intentionally remains In Progress for parent review.

Parent final review complete: verified exact Linux success-token warning behavior, absence of AppArmor/namespace proxy vetoes, preservation of actual failure checks, shared-copy consistency, and the executable-first process regression fix. Independently passed bash tests/bb-desktop-contract.sh (64 cases), PYTHONDONTWRITEBYTECODE=1 /usr/bin/python3 tests/test_bb_desktop.py (64), bash tests/bb-server-contract.sh, bash tests/setup-reliability-contract.sh, python3 tests/test_homebrew_results.py, PATH="/usr/bin:/bin:${PATH}" bash tests/headless-paseo-daemon-contract.sh, Bash syntax, ShellCheck, Markdown lint and git diff --check. No remaining implementation review blocker. PowerShell execution/parsing remains skipped for unavailable tooling; native macOS/Linux desktop GUI/signing/sandbox/coexistence verification remains an explicit rollout limitation under the approved install-only scope. Nothing was deployed or committed.

Publishing integration: remote main independently allocated TASK-48 to BB machine preparation. Recreated this desktop task as TASK-49 using Backlog CLI, preserving its seven criteria, plan, implementation history and final summary. Earlier TASK-48 references in historical notes refer to this desktop task before migration; the enrollment task on remote main is unchanged. Rebased onto 069b271, preserving both features and all call sites. Final versions: macOS 248, Ubuntu 276, Bazzite 128, WSL 210, Pi 227, Windows 162. Merged desktop (64), preparation (17), server, reliability, Homebrew and headless contracts, syntax, ShellCheck, Markdown lint and whitespace checks pass. Full push hooks and remote publication remain to be verified; no live rollout.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Added official stable bb desktop installation/update for headed personal and work machines on Apple Silicon macOS and native Ubuntu/Bazzite x64. All six setup scripts include exact headless/platform gates; unsupported Windows, WSL, Intel macOS and Raspberry Pi/Linux ARM receive explicit skips.

Changes:

- Verify official release metadata, artifact digests and installed identity/version; additionally validate macOS signing/notarization. Preserve newer/custom/nightly/running installations with private staging, rollback and failure aggregation. Do not launch bb or change server, provider, shell or security configuration.
- Linux process inspection excludes verified unrelated executables before environment reads. Per user approval, verified Linux installation succeeds with an explicit unverified GUI/sandbox compatibility warning, without AppArmor inspection or generic namespace probes.
- Update versions, README, glossary, repository guidance, approved plan and source-backed Linux compatibility findings.

Verification:

- Parent review complete. All 64 desktop fixtures pass on both Python interpreters; bb server, setup reliability, Homebrew and headless Paseo regressions pass, as do Bash syntax, ShellCheck, Markdown lint and whitespace checks.
- PowerShell execution/parsing skipped because no executable is available. Native macOS signing/menu and Linux GUI/sandbox/server coexistence remain rollout checks; installation success does not claim native launch compatibility. No live installation, service/policy change, commit or PR.
<!-- SECTION:FINAL_SUMMARY:END -->
