---
id: TASK-17
title: Ensure Pi uses a supported shared Node runtime after setup
status: Done
assignee:
  - '@pi'
created_date: '2026-09-10 21:08'
updated_date: '2026-09-11 18:47'
labels: []
dependencies: []
documentation:
  - docs/plans/2026-09-11-001-fix-pi-shared-node-runtime-plan.md
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Arcane launches Pi with /usr/bin/node v18.19.1 and fails because node:fs lacks globSync. Current Pi 0.85.1 requires Node >=22.19.0, but setup accepts >=20.6 and verifies only its current process. Ensure the normal user shell uses a supported shared mise-managed Node after setup. Scott explicitly dropped runtime isolation and support for launching Pi while a project selects an unsupported Node version. Preserve project pins and chezmoi ownership of shell configuration.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 All six scripts establish or verify a supported shared global mise Node selection and validate ordinary fresh-shell HOME resolution, without treating inherited modern Node or an explicit runtime override as proof of durable selection.
- [x] #2 Preserve a global Node selection compatible with the managed tools. If missing or unsupported, select supported LTS using Node24 where official binaries are supported and compatible prebuilt Node22 on Linux ARMv7. Do not compile or use unofficial builds on unsupported platforms.
- [x] #3 Pi readiness requires Node >=22.19.0, callable fs.globSync, and available npm. Earlier skills runtime selection satisfies its >=22.20 requirement without undoing shared-runtime preservation or ARMv7 policy.
- [x] #4 Preserve system Node, project runtime pins, conflicting HOME overrides, unrelated mise configuration, Pi user data and npmCommand choices, unrelated executables, and environment files. Report an incompatible HOME override instead of rewriting it.
- [x] #5 Keep canonical npm Pi installation and normal Pi update/package commands under the supported shared runtime. Do not add Pi-specific runtimes, custom launchers, private npm layouts, or npmCommand adapters. Pi under an explicitly unsupported project runtime is outside the guarantee.
- [x] #6 Coordinate chezmoi-owned PowerShell mise activation in the dotfiles repository while preserving unrelated profile content. Setup scripts do not write profiles. Existing fish activation remains unchanged unless tests establish a defect.
- [x] #7 Runtime installation, activation, or validation failure is reported before any Pi npm installation, uninstallation, or package-repair deletion. Full rollback of later npm package or extension updates is outside this task.
- [x] #8 Offline tests extract relevant functions and use isolated homes to cover stale and transient runtimes, durable selection, fresh-shell selection, repeated runs, HOME/project overrides, ARMv7 fallback, failures, and preservation boundaries. No live setup, dotfiles application, daemon restart, remote rollout, or model request occurs during development.
- [x] #9 Update modified setup script versions and documentation, run relevant regression checks and ShellCheck, review the setup and dotfiles diffs, and explicitly report native-platform and unavailable-test limits.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Add isolated failing fixtures for the inherited-Node/global-selection bug and runtime boundaries using extracted functions only.
2. Repair shared global mise selection in all six scripts; preserve compatible selections and pins; align skills helper and official ARMv7 Node22 fallback; do not use source-build fallbacks.
3. Validate effective HOME resolution and fresh normal shell startup without forced runtime versions or inherited mise activation. Preserve conflicting overrides and report failure.
4. In a separate dotfiles worktree, add chezmoi-owned PowerShell mise activation while preserving unrelated profile content. Do not apply live dotfiles.
5. Ensure runtime readiness precedes all Pi npm mutations; keep canonical npm install and normal update behavior unchanged.
6. Update versions/docs and run relevant offline tests, ShellCheck, and available PowerShell fixtures. Review both repositories and document test/platform limits.
Final design: docs/plans/2026-09-11-001-fix-pi-shared-node-runtime-plan.md. Decisions are settled; present this consolidated plan for final confirmation before implementation.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Confirmed exact fs.globSync import failure with /usr/bin/node v18.19.1. Identical import succeeds under Node v24.20.0.
- Actual installed Pi 0.85.1 --version fails with the reported SyntaxError under minimal system PATH and succeeds with managed Node 24; temporary HOME and offline environment used.
- Installed Pi declares engines.node >=22.19.0 and has an env-node shebang. All six setup runtime guards currently accept >=20.6.
- Extracted ensure_pi_node_runtime returns success when Node 24 is merely inherited on PATH without creating a global mise config. Its fallback evaluates mise only within setup; neither path binds the npm launcher to that runtime.
- No SSH, live setup, package installation, or model requests performed. Implementation awaits required plan approval.

- Planning interview requested by Scott. Existing acceptance criteria and launcher implementation plan are provisional, not approved; settle desired runtime isolation and platform scope first, then installation mechanism and failure/update behavior. No implementation until shared understanding is explicitly confirmed.
- Delegated read-only research into upstream standalone installer/runtime support, npm and Pi self-update bin ownership, existing Paseo consumers, and child-process runtime effects. User decisions will determine the final contract.

- Read-only installer/update research completed. Official Pi installers still depend on PATH-selected Node; separate Bun release archives bundle a runtime but lack ARM32 builds and built-in self-update.
- Simple replacement of the npm-owned canonical Pi bin is not update-safe: npm upgrades may overwrite the wrapper or reject it with EEXIST. Candidate designs must separate ownership or explicitly account for self-update.
- Important correction to provisional step 3: prepending the Pi runtime directory to child PATH changes agent-run project commands too. An absolute Node executable can isolate Pi startup while preserving caller PATH, but Pi package installation/self-update need a separately considered npm runtime. Do not assume child-PATH changes are approved.
- Existing dependencies: Paseo daemon setup calls ensure_pi_node_runtime; Paseo Plain Windows discovery expects a package next to the npm pi.cmd shim. Both need regression review if layout changes.
- Awaiting Q1 (Pi runtime versus shell/project runtime) and Q2 (platform scope). Installation/update durability and runtime lifecycle questions follow once their prerequisites are settled.

- Scott accepted both initial recommendations: separate Pi runtime from project runtime, without replacing system Node or changing project runtime selection; apply the same behavior across all six scripts, future setup runs only.
- Added the agreed Pi runtime and Project runtime terms to CONTEXT.md. No installer code changed.
- Revised task scope and removed premature launcher/PATH assumptions. Next interview frontier: self-update/package-management guarantees and failed-update behavior.

- Scott accepted Q3 and Q4 recommendations: retain normal Pi self-update/package commands with old caller Node, and stage/test replacements so failed setup updates preserve working Pi and report failure. This rollback guarantee covers setup-managed updates, not an unverified promise about upstream pi update internals.
- Additional read-only source investigation is checking npmCommand integration and custom settings, staged private-prefix self-update compatibility, Windows discovery, and Node ARM32 availability. No implementation started.

- Follow-up source research: a fixed --prefix in npmCommand is unsafe for Git-extension dependency installation because those calls use checkout cwd and no explicit prefix. A managed npm command must distinguish global operations from local prefixes/cwd and scope modern-Node PATH to npm children only.
- Pi self-update reads global npmCommand; extension operations accept trusted project overrides. Preserving arbitrary custom npmCommand choices cannot also guarantee that every custom command uses compatible Node. This requires a conflict policy.
- Dotfiles coordination is a newly identified scope dependency: the current chezmoi Pi settings template does not preserve npmCommand, so a setup-only setting can disappear on later chezmoi apply. Ask Scott before extending work into dotfiles.
- Node24 has no official Linux armv7l binary; Node22 includes armv7l and meets Pi >=22.19.0. Mise can fall back to compiling Node24, so automatic compilation must not be assumed. ARMv6 and unsupported binary environments need an explicit failure policy.
- Staged private npm prefixes can separate npm bin ownership from the public launcher. Ordinary pi update mutates the active prefix in place and is not transactionally protected by setup staging. Candidate npm validation must bind to the candidate prefix; concurrent setup/self-update needs consistency protection.
- Verification caveat: PI_OFFLINE skips real extension updates and latest-Pi lookup, so it cannot prove real self-update. Keep offline deterministic fixture evidence distinct from an explicitly bounded integration test.
- Q5 runtime-update cadence remains unanswered. Subsequent user decisions include dotfiles/npmCommand ownership and conflicts, and official Node22 fallback on ARMv7 with explicit unsupported-platform handling.

- Scott explicitly dropped the requirement that Pi work while a project selects unsupported Node. Shared shell/project/Pi Node is the desired design; private runtime architecture was unnecessary for the reported bug.
- Removed the provisional Pi runtime/Project runtime glossary distinction from CONTEXT.md. With that removal, the glossary has no changes from the original repository.
- Withdrawn private-prefix/launcher/npmCommand architecture and its associated dotfiles setting change. All-six-platform scope remains accepted.
- Requested read-only investigation of the smaller shared-runtime fix and current chezmoi activation templates. Runtime update cadence Q5 was not answered; do not treat it as accepted. Prior failed-setup retention requirement is retained pending an explicit scope clarification, not silently discarded.

- Shared-runtime investigation confirms the standard fish chezmoi template already activates mise after adding its standard paths. No fish-template change is currently justified. Successful mise use -g is durable; the defect is skipping global selection on inherited Node and validating an explicit forced runtime rather than normal HOME resolution.
- Possible arcane mechanisms remain unverified: inherited modern Node (for example Paseo service PATH) hides absent/old global selection; a higher-priority HOME mise configuration overrides the global selection; or activation/dotfiles were unavailable. Do not present one as arcane-specific fact without evidence.
- Small repair: discover mise; verify compatible durable global selection regardless of inherited PATH; require >=22.19+callable fs.globSync and npm; verify ordinary HOME resolution without explicit runtime override; leave project and conflicting HOME pins untouched and report conflicts; retain canonical npm Pi layout.
- Windows gap: inspected chezmoi source has no PowerShell mise activation. All-six-platform durability needs approved chezmoi-owned activation or shared mise-shims PATH integration. Do not write shell profiles from setup.
- ARMv7 Node22 fallback must also account for earlier skills runtime helper (minimum22.20 and same early return/current node24 fallback). Avoid incidental source compilation.
- Proposed simplified failure boundary, NOT yet approved: runtime provisioning/validation failure must occur before any Pi npm mutation or repair deletion, preserving current package/bin. Full rollback of subsequent in-place npm package update remains separate scope and cannot be silently substituted for prior Q4.
- Revised Q5 now asks to preserve compatible shared global Node and select supported LTS only if missing/too old; awaiting Scott response.

- Scott accepted the revised shared-Node policy: retain a supported global selection instead of upgrading it on every setup run; select supported LTS only if absent/unsupported. The private-runtime update policy is abandoned.
- Remaining decision frontier: permission for coordinated Windows shell activation in chezmoi/dotfiles, explicit scope of failed-update retention (runtime preflight versus transactional npm rollback), and official Node22 fallback on ARMv7 without source compilation.

- Scott accepted Q6-Q8: include chezmoi-owned PowerShell activation in dotfiles; narrow failure protection to runtime preparation/validation before Pi mutations (no full npm rollback); use official prebuilt Node22 on Linux ARMv7 and reject unsupported platforms without source compilation.
- Final decision frontier is empty. Wrote the consolidated simplified plan and synchronized all acceptance criteria, superseding earlier private-runtime and transactional-update proposals.
- Added only Shared Node runtime to CONTEXT.md as the accepted glossary term. No setup scripts or live dotfiles changed.
- Verified Python, Node, fish, and ShellCheck availability; pwsh is absent. Confirmed the inspected dotfiles source belongs to scowalt/dotfiles. Final implementation confirmation remains pending.

Scott approved the consolidated plan and explicitly requested implementation. Starting isolated regression tests and setup/dotfiles changes.

Implemented the shared-runtime helpers in all five Bash scripts, synchronized copies, and bumped versions. New regression fixtures caught and fixed real mise --global source filtering under a HOME override. Fresh fixture fish activates actual read-only installed Node after setup exits. Node readiness, ARMv7 fallback, compatible/missing selection preservation, repeat runs, HOME/project pins, and preflight package/cleanup guards now have offline tests. All existing Bash contracts passed except the Windows banner assertion while Windows implementation remains in progress. ShellCheck passes; no live setup or dotfiles application performed.

- Completed Windows runtime selection/validation and guarded its failure-branch cleanup. Portable PowerShell fixture passes 959 assertions plus a real-mise global inventory check. The Windows implementation review identified installed-but-incompatible versus absent runtime handling; Bash now matches that distinction with a regression test.
- Completed chezmoi-owned PowerShell activation in sibling tender-dolphin-dotfiles worktree (branch fix/pi-shared-node-runtime). The managed block preserves unrelated profile bytes, encoding and line endings; unsafe linked/malformed/signed paths fail conservatively. No live apply occurred.
- Final verification: all 23 Bash contract scripts pass with PWSH_BIN set; 16 new Python runtime tests pass, including real mise/fish and an explicitly supplied real Pi --version smoke in an isolated HOME; 959 PowerShell assertions pass; 30 Paseo Plain tests and the explicitly supplied native Git-isolation fixture pass; ShellCheck, Markdownlint and whitespace checks pass. Dotfiles: 14 profile fixtures and 2 existing model tests pass, 2 Windows-only profile tests skipped.
- Existing tests/setup-reliability-powershell.ps1 fails on Linux at line453 (PR Lens path assertion). Reproduced identical failure using unmodified HEAD:win.ps1 in a temporary baseline tree. No change to that unrelated suite. Other existing PowerShell suites pass.
- Native Windows/5.1, macOS, and ARM machine execution remains unverified. No arcane connection, live setup/dotfiles apply, fleet rollout, daemon restart, or model request. Changes remain local and uncommitted in both worktrees.

- Scott requested merge into remote main. Revalidated ShellCheck, the 16 shared-runtime Python cases, 959 PowerShell assertions and real-mise fixtures, dotfiles profile/model fixtures, Markdownlint, and whitespace checks before publication.
- Dotfiles dependency merged by fast-forward to scowalt/dotfiles main at fdccbd475af4df1b3a51cdae9813e1afca2417bd; verified with git ls-remote. Publishing the setup changes next. No forced push or live machine setup.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Pi now uses a supported shared mise Node runtime after setup, rather than treating setup's inherited Node PATH as proof of a durable default.

Changes:

- Updated all six setup scripts and version banners. Preserve compatible global selections, repair missing/unsupported defaults, use official Node22 binaries on ARMv7, and prevent source-build fallback.
- Validate Node/API/npm compatibility and fresh-shell HOME resolution. Preserve project/HOME pins and stop before Pi package mutations when runtime preparation fails. Keep canonical npm installation and normal Pi updates without custom launchers.
- Added chezmoi-owned PowerShell activation in the separate dotfiles worktree, preserving unrelated profile content.

Verification:

- All 23 Bash contracts, 16 shared-runtime Python tests, 959 PowerShell assertions, real mise/fish/Pi version fixtures, 30 Paseo Plain tests, native Git isolation, ShellCheck, Markdownlint, and whitespace checks passed.
- Dotfiles: 14 profile fixtures and 2 model tests passed; 2 native Windows tests skipped.

Limits:

- An existing PowerShell reliability suite fails the same PR Lens path assertion on Linux against both current changes and unmodified HEAD. Native Windows/5.1, macOS, and ARM execution remains unverified.
- No live machines or dotfiles changed. Deploy both repositories for Windows activation; open a fresh shell after setup. Full npm-update rollback is outside scope.
<!-- SECTION:FINAL_SUMMARY:END -->
