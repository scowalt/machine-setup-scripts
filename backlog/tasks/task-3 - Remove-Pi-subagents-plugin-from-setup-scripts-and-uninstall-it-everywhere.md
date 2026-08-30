---
id: TASK-3
title: Remove Pi subagents plugin from setup scripts and uninstall it everywhere
status: Done
assignee:
  - '@pi-agent'
created_date: '2026-08-25 17:32'
updated_date: '2026-08-25 18:17'
labels: []
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Setup scripts currently install the tintinweb Pi subagents extension (npm:@tintinweb/pi-subagents) on every Pi install across mac.sh, ubuntu.sh, pi.sh, wsl.sh, bazzite.sh, and win.ps1 (opt-out: BAN_PI_SUBAGENTS). This plugin is no longer wanted anywhere: fresh setups must not install it, and rerunning setup on machines that already have it must uninstall it (strip from Pi settings.json and remove installed files, idempotently and non-fatally). The chezmoi dotfiles template (private_dot_pi/agent/private_settings.json.tmpl) must also stop re-adding the package so the removal survives chezmoi apply; stale AGENTS.md reference to the legacy pi-subagents package gets cleaned up too. Contract tests referencing the subagents block (headless-paseo-daemon-contract.sh awk marker, pi-synthetic-defaults-contract.sh order assertion) need updating plus a regression guard against reintroduction. Version bumps in all modified scripts.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 No setup script installs or updates npm:@tintinweb/pi-subagents or legacy npm:pi-subagents; BAN_PI_SUBAGENTS flag, install functions, and settings helper are removed from all 6 scripts
- [x] #2 Each script removes both package sources from Pi settings.json and uninstalls files (pi remove, with jq/PowerShell settings fallback when pi CLI missing) on every run — idempotent, non-fatal, and regardless of Pi migration success
- [x] #3 tests/headless-paseo-daemon-contract.sh and tests/pi-synthetic-defaults-contract.sh updated with stable markers; forbidden-pattern regression guard added
- [x] #4 Chezmoi dotfiles template no longer injects the subagents package and the stale AGENTS.md pi-subagents reference is removed; changes committed and pushed to scowalt/dotfiles
- [x] #5 bash -n and shellcheck pass on modified bash scripts, full contract test suite passes, version numbers bumped in all 6 scripts
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Bash scripts (pi.sh, ubuntu.sh, mac.sh, wsl.sh, bazzite.sh) — identical pattern: delete update_pi_subagents_settings() + setup_pi_subagents(), add remove_pi_subagents() that runs 'pi remove npm:@tintinweb/pi-subagents' and 'pi remove npm:pi-subagents' when pi CLI exists (non-fatal), else strips both sources from settings.json via jq with the same jq program as today. Call it in BOTH branches of the Pi extensions section (after seed_pi_zai_models, and in the else branch replacing the BAN conditional). Remove '# BAN_PI_SUBAGENTS=1' header doc. 2. win.ps1 — same shape: replace Update-PiSubagentsSettings/Setup-PiSubagents with Remove-PiSubagents (pi remove when pi exists, else PowerShell settings strip), remove BAN_PI_SUBAGENTS env-local checks, call in both branches. 3. Tests — headless-paseo-daemon-contract.sh: swap awk end marker to a stable anchor (the '# Remove Pi subagents' comment that follows the paseo block); pi-synthetic-defaults-contract.sh: order assertion now checks configure_pi_defaults before remove_pi_subagents; add assert_not_contains for '@tintinweb/pi-subagents' install paths. 4. Chezmoi repo (~/.local/share/chezmoi, pushed to scowalt/dotfiles): drop the package line from private_settings.json.tmpl and remove the stale pi-subagents bullet/command from AGENTS.md. 5. Bump version + 'Last changed' in all 6 scripts. 6. Validate: bash -n + shellcheck all bash scripts, run full tests/ suite locally, chezmoi diff to confirm template renders without the package.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Decision (user-approved via ask_user): also fix the chezmoi dotfiles template in the same pass and push to scowalt/dotfiles, so chezmoi apply stops reverting the uninstall. BAN_PI_SUBAGENTS removed entirely (nothing left to opt out of). Uninstall = pi remove for both sources + settings.json strip fallback when pi CLI absent; runs unconditionally on every setup pass.

Started implementation on branch remove-pi-subagents-plugin-setup-scripts. Beginning with the 5 bash scripts.

Plan approved by user. Implementation delegated to paseo agent 05991341-a41d-4f14-ad89-5cc17cf320dc (pi / synthetic Kimi K3 / max thinking) running in workspace wks_e3f5b885ef6acff2 (this worktree, branch remove-pi-subagents-plugin-setup-scripts) with the full step-by-step plan, exact edit locations, validation commands, and commit/PR instructions.

Bash scripts done (pi.sh, ubuntu.sh, mac.sh, wsl.sh, bazzite.sh): replaced update_pi_subagents_settings+setup_pi_subagents with remove_pi_subagents (pi remove for both sources, jq settings-strip fallback when pi CLI missing, non-fatal), wired into both Pi-extensions branches, removed BAN_PI_SUBAGENTS header docs, bumped versions.

Verified pi CLI behavior: 'pi remove' exits 1 with 'No matching package found' when the package is absent, so that output maps to print_debug (not installed) and other failures map to print_warning.

win.ps1 done: Remove-PiSubagents replaces Update-PiSubagentsSettings+Setup-PiSubagents (pi remove for both sources, PowerShell settings-strip fallback), BAN_PI_SUBAGENTS removed, wired in both Main branches. Tests: headless awk marker retargeted to new function comment, synthetic-defaults order assert uses remove_pi_subagents, new tests/pi-subagents-removal-contract.sh regression guard (forbids pi install lines, BAN flag, legacy functions; requires 2 unconditional call sites per script). All 10 bash test suites pass; shellcheck clean on all 5 scripts + tests. Sandboxed functional test verified: success/not-installed/debug/failure-warn paths, jq fallback strips string and object package entries, deletes empty packages key, exit 0 throughout.

Chezmoi companion change completed and pushed to scowalt/dotfiles: fdd7fbf. private_settings.json.tmpl renders without npm:@tintinweb/pi-subagents; AGENTS.md no longer requires or installs legacy pi-subagents. Updated live README behavior text to say setup removes the extension and deleted the obsolete BAN_PI_SUBAGENTS documentation.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Removed the tintinweb Pi subagents extension from all six machine setup scripts and made every setup rerun uninstall both the current and legacy package sources.

Changes:

- Replaced the install/settings helpers with unconditional, non-fatal removal in both Pi migration branches.
- Used `pi remove` for both package sources, with jq and PowerShell settings fallbacks when the Pi CLI is unavailable.
- Removed `BAN_PI_SUBAGENTS`, updated live README behavior, and bumped all six script versions.
- Updated contract markers/order assertions and added a regression guard against reinstalling the extension.
- Updated and pushed the companion dotfiles change as scowalt/dotfiles commit `fdd7fbf`.

Tests:

- `bash -n` on all five Bash setup scripts
- `shellcheck` on setup scripts and all Bash contract tests
- All ten `tests/*.sh` contract suites
- `bunx markdownlint-cli README.md`
- Sandboxed removal tests for success, already-absent, failure, mixed string/object settings entries, and empty package-array deletion

PowerShell runtime tests were skipped because `pwsh` is not installed on this machine.
<!-- SECTION:FINAL_SUMMARY:END -->
