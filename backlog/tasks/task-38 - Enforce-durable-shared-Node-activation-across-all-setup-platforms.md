---
id: TASK-38
title: Enforce durable shared Node activation across all setup platforms
status: Done
assignee:
  - '@pi'
created_date: '2026-09-18 17:33'
updated_date: '2026-09-18 19:54'
labels:
  - setup
  - skills
  - bug
dependencies: []
references:
  - ubuntu.sh
  - wsl.sh
  - pi.sh
  - bazzite.sh
  - win.ps1
  - tests/shared-node-runtime-powershell.ps1
documentation:
  - README.md
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Every successful machine setup run must converge the managed shell environment to the shared mise Node runtime, automatically correcting setup-managed legacy activation that can shadow it. Cover macOS, Ubuntu, WSL, Raspberry Pi, Bazzite, and Windows, not a one-off Mac repair. The observed macOS failure leaves fnm Node ahead of mise and blocks the complete Matt Pocock suite including ask-matt. Setup owns convergence and verification; Chezmoi continues to own shell configuration. Preserve intentional HOME/project overrides and npm security, and fail clearly rather than bypass unsafe or incompatible selections. Development uses temporary fixtures only; rollout occurs on each machine’s next setup run.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 All six setup entry points apply the managed shell migration before dependent Node operations and verify the resulting ordinary fresh-shell selection, rather than relying on the calling shell PATH or leaving known setup-managed legacy activation for manual repair.
- [x] #2 Fresh fish on Bash platforms and fresh native PowerShell on Windows select the ordinary mise-managed Node and usable npm after setup, including legacy fnm/Homebrew/system PATH precedence and early/repeated mise activation cases applicable to each platform.
- [x] #3 A repeated successful setup run cannot restore the managed activation conflict; compatible global selections and intentional HOME/project pins are preserved. Unsupported or unsafe overrides remain explicit failures rather than silently overwritten.
- [x] #4 The full managed Matt Pocock suite, including ask-matt, reaches installation and passes validation after runtime convergence; the runtime gate still rejects genuinely unsupported or mismatched environments and failures remain reflected in the final setup result.
- [x] #5 Chezmoi exclusively owns shell configuration. Preserve runtime installations unless a narrowly scoped migration is explicitly approved, environment files, credentials, npm/Socket Firewall policy, skill opt-outs, and unrelated shell behavior. No live or remote machine changes during development.
- [x] #6 Offline regression fixtures exercise all six setup wrappers, fresh-shell and repeated-run behavior, rendered dotfiles, and available real mise/fish and PowerShell coverage. Affected suites and lint pass, documentation records the setup guarantee and limits, and each modified setup script has an incremented version.
- [x] #7 Chezmoi-managed Bash and Zsh login profiles no longer reactivate fnm and use ordinary mise selection, so switching away from the managed default shell cannot reintroduce the managed legacy activation.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Extend the reproduced Mac failure into an all-platform setup convergence contract: trace dotfiles application, inherited PATH handling, runtime selection, and dependent skill/Pi operations in all six entry points. Use temporary homes and inert tools only.
2. Coordinate setup and isolated dotfiles changes so each run applies the authoritative mise activation and automatically retires conflicting setup-managed legacy activation before dependent installs. Keep all shell configuration in Chezmoi; do not weaken the runtime identity gate, bypass npm policy, or delete arbitrary runtime installations.
3. Verify the actual resulting fresh fish/PowerShell environment independently of the parent setup PATH. Preserve compatible global selections and intentional project/HOME pins; report controlled actionable failures for unsupported overrides or failed migration. Prevent subsequent setup/dotfiles runs from restoring the conflict.
4. Add offline regression tests across all six wrappers for legacy precedence, early/repeated activation, inherited environments, clean and repeated setup, full ask-matt installation, and genuine runtime failures. Exercise rendered dotfiles and available native runtime/shell fixtures, documenting remaining native-platform verification limits.
5. Update documentation and affected script versions; run shared-runtime, managed-suite, ownership, reliability and affected dependent contracts plus lint. No live setup, remote rollout, installed-skill execution, or model requests. Await approval of this expanded all-platform plan before implementation.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Read-only evidence: September 18 MacBook setup logs report fresh-fish runtime failure and skip the entire Pocock suite. User output resolves node through fnm while mise which node points into ~/.local/share/mise/installs/node/24. Both Node versions are compatible; binary identity differs. Current remote dotfiles fish template initializes fnm and then mise.
A temporary native mise/fish probe reproduces the mismatch: activation once after legacy PATH insertion passes the extracted macOS check; early mise activation followed by legacy PATH insertion and repeated mise activation leaves legacy Node selected and fails (exit 1). This demonstrates an activation-order failure mode, not yet proof of the exact early hook on the Mac. No implementation or live settings changed. Tools available: Python, Node, fish, mise, chezmoi, ShellCheck, gh, Backlog, and an isolated PowerShell runtime.

User clarified that machine setup must prevent recurrence on every machine, not merely repair the Mac through a dotfiles change. Expanded acceptance criteria and plan to all six setup entry points, automatic managed-activation migration, repeated-run convergence, and fresh-shell verification. The guarantee applies to successful setup runs and managed configuration; it cannot prevent later arbitrary user/environment changes, and intentionally incompatible HOME/project overrides remain preserved and blocked.

User approved the expanded all-platform plan and explicitly authorized updates in ~/Code/dotfiles. Starting regression-first implementation; live profiles and remote machines remain out of scope.

Regression-first changes now pass for rendered fish on darwin/Linux, native early/repeated mise activation, and the PowerShell cached-activation fixture. Setup now attempts one targeted Chezmoi profile repair and independently re-verifies the fresh shell instead of requiring manual profile repair. A native integration fixture exercises all five Bash setup helpers with real mise/fish/Chezmoi and inert full-suite staging: it first reproduces the mismatched Node, then installs ask-matt and every baseline skill twice; a stale source remains blocked. Targeted applies preserve unrelated files/scripts.
Inspection also found managed fnm startup in Bash and Zsh login profiles. Extending the same approved legacy-activation retirement there prevents those managed shells from reintroducing conflicting state; no runtime installation removal is planned.

Independent review found three substantive gaps: healthy-but-unmigrated profiles could pass a one-shot runtime check, brewed-only Bash logins lacked Homebrew discovery, and fnm-style project pins were not enabled in mise. Reproduced each with isolated fixtures. Added a process-local activation revision checked by setup (inherited evidence is cleared), native additive Node idiomatic-file support, and clean-login Homebrew discovery.
Fixing the test filesystem relocation to keep literal Homebrew prefixes space-free also exposed native mise PATH restoration on a later cd hook. Setup now owns activate_aggressive=true so mise-selected tool directories stay ahead of competing paths across hooks, while ordinary project version selection remains authoritative. Native integration covers .node-version/.nvmrc project selection and cd transitions, incompatible HOME .mise.toml preservation, and stale sources that otherwise have a healthy Node. Native mise global-config precedence over idiomatic files directly at HOME is retained rather than reimplemented.

Implementation and review complete. All six helpers enforce native PATH precedence and effective Node-pin policy, require a fresh process-local activation revision, and do one targeted Chezmoi repair before independent re-verification. Dotfiles retire managed fnm startup in fish/Bash/Zsh and refresh normal mise activation in all managed shells. Bash discovers all standard Homebrew prefixes without inherited PATH and suppresses BASH_ENV only in the Homebrew child, preserving caller Socket Firewall wrappers.
Both review axes now report no remaining material findings. Review-driven regressions cover healthy-but-unmigrated profiles, legacy project pins, cd-hook precedence, incompatible effective environment overrides, Homebrew Bash-entry-point recursion, and PowerShell legacy native-argument quote loss. Readiness predicates and JSON transport now pass the complete PowerShell fixture in both Standard/default and Legacy modes (1409 assertions each).
Final verification: all 31 shell contract suites plus weekly regressions pass with available PowerShell, native inert skills CLI, and dotfiles integration enabled. Dotfiles suites pass (37 tests total; two native-Windows-only cases skipped). Native fish/Bash/Zsh fixtures pass; the Zsh binary was extracted into a temporary directory from Ubuntu packages, not installed on the host. ShellCheck, native syntax checks, Markdownlint and git diff --check pass. Final setup test logs: /tmp/setup-convergence-verified.FS3fo5.
Native macOS/Windows/ARM startup and optional integration-module environments retain documented verification limits. No live setup, live dotfiles application, installed-skill execution, remote machine mutation, commit, push, or deployment occurred.

User requested publication to remote main for both repositories. Confirmed both worktrees are based on their current origin/main commits, both main branches are unprotected, and push permission is available. Publish dotfiles first, then setup, using ordinary fast-forward pushes with hooks enabled; do not run live setup.

Published dotfiles to remote main with an ordinary fast-forward push: cdd91d4aca529fe471112508018b1af72da29555. Its pre-commit hook and staged Gitleaks scan passed. Preparing the paired setup commit against unchanged origin/main, with its full pre-push validation enabled.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Enforce durable shared Node activation across every supported setup platform, fixing fnm/mise precedence that blocked the full Matt Pocock suite, including ask-matt.

Changes:

- All six scripts configure native mise precedence and additive legacy project-pin support; validate the effective fresh-shell policies, activation revision, Node identity and npm; and automatically attempt a bounded, targeted Chezmoi repair when needed.
- Preserve compatible runtimes, normal project/HOME precedence, existing installations, credentials, environment files and npm/Socket Firewall protections. Stale sources, failed repairs and incompatible explicit overrides remain setup failures.
- Updated ~/Code/dotfiles on fix/shared-node-activation: remove managed fnm startup; refresh fish/Bash/Zsh/PowerShell activation; handle clean Homebrew discovery without recursive BASH_ENV loading.
- Added native temporary-home repair-to-full-suite fixtures, repeated-run and failure coverage, and quote-safe Windows readiness checks tested with legacy PowerShell argument handling. Updated documentation and every setup version.

Validation:

- All 31 setup contract suites plus weekly regressions pass.
- Native mise/fish/Chezmoi integration verifies all five Bash paths reach inert ask-matt/full-suite installation; PowerShell default and Legacy modes each pass 1409 assertions.
- All dotfiles suites, ShellCheck, syntax, Markdownlint and whitespace checks pass. Both standards and spec review findings are resolved.

Coordinated publication targets remote main in both repositories, with dotfiles delivered first. No live or fleet setup is part of publication. Native Windows/macOS/ARM execution remains separately verifiable.

Companion dotfiles commit: scowalt/dotfiles@cdd91d4aca529fe471112508018b1af72da29555 (published to main before the setup change).
<!-- SECTION:FINAL_SUMMARY:END -->
