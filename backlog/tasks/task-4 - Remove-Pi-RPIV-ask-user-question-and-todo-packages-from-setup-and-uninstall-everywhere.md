---
id: TASK-4
title: >-
  Remove Pi RPIV ask-user-question and todo packages from setup and uninstall
  everywhere
status: Done
assignee:
  - '@pi-agent'
created_date: '2026-08-26 03:08'
updated_date: '2026-08-26 03:31'
labels: []
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Setup scripts currently install npm:@juicesharp/rpiv-ask-user-question and npm:@juicesharp/rpiv-todo via setup_pi_companion_packages on all 6 scripts (mac.sh, ubuntu.sh, wsl.sh, pi.sh, bazzite.sh, win.ps1). User philosophy: simpler is better; the structured multi-choice questionnaire and the RPIV todo tool are not wanted. Fresh setups must not install them, and rerunning setup on machines that already have them must uninstall them (pi remove + settings.json strip fallback when pi CLI missing, idempotent, non-fatal, regardless of Pi migration success). pi-web-access and the legacy pi-ask-user cleanup stay. Pattern follows TASK-3 (pi-subagents removal) and ADR-0001. Chezmoi template does not seed either package, so no dotfiles companion change is needed. Contract tests asserting the install lines need flipping plus a regression guard. Version bumps in all 6 scripts.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 No setup script installs npm:@juicesharp/rpiv-ask-user-question or npm:@juicesharp/rpiv-todo; both install array entries removed from all 6 scripts while npm:pi-web-access stays
- [x] #2 Each script uninstalls both RPIV packages via pi remove with a settings.json strip fallback when the pi CLI is missing, on every run, idempotent, non-fatal, regardless of Pi migration success
- [x] #3 tests/pi-companion-packages-contract.sh and tests/ai-coding-agent-contract.sh updated; regression guard forbids reintroduction
- [x] #4 README.md behavior text updated to state setup removes both RPIV packages
- [x] #5 bash -n and shellcheck pass on modified bash scripts, full contract test suite passes, version numbers bumped in all 6 scripts
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. All 5 bash scripts + win.ps1: drop npm:@juicesharp/rpiv-ask-user-question and npm:@juicesharp/rpiv-todo from the companion install array (keep npm:pi-web-access and legacy pi-ask-user cleanup)
2. Add remove_pi_rpiv_packages() / Remove-PiRpivPackages: pi remove for both packages (not-installed maps to debug), jq/PowerShell settings.json strip fallback when pi CLI missing; call in BOTH Pi-setup branches alongside remove_pi_subagents
3. Update tests/pi-companion-packages-contract.sh + tests/ai-coding-agent-contract.sh; add forbidden-pattern regression guard for both packages
4. Update README.md behavior sentence
5. Bump version + Last changed in all 6 scripts
6. Validate: bash -n + shellcheck all bash scripts, run full tests/ suite
7. Commit on remove-ask-user-question-from-pi-setup-scripts and open PR
Plan pre-approved by user via grill-with-docs round (Q1 remove both, Q2 everywhere, Q3 full TASK-3 treatment).
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Removed both RPIV entries from setup_pi_companion_packages / Setup-PiCompanionPackages in all 6 scripts (npm:pi-web-access stays; legacy pi-ask-user cleanup untouched)
- Added remove_pi_rpiv_packages / Remove-PiRpivPackages modeled on remove_pi_subagents: pi remove both sources (not-installed -> debug), jq/PowerShell settings.json strip fallback; wired into BOTH Pi-setup branches so removal runs regardless of Pi migration success
- Chezmoi template does not seed either package, so no dotfiles companion change needed (verified private_settings.json.tmpl)
- Tests: companion contract now expects only pi-web-access and forbids RPIV installs; ai-coding-agent contract asserts removal function/wiring; new tests/pi-rpiv-removal-contract.sh regression guard with functional mock-pi idempotency check and jq fallback check (mixed string/object entries); simple-english contract version banners updated
- bash -n + shellcheck clean on all scripts and tests; all 11 tests/*.sh suites pass; markdownlint README clean; versions bumped 205/228/172/188/87/126
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Retired @juicesharp/rpiv-ask-user-question and @juicesharp/rpiv-todo from the managed Pi package set on all six setup scripts, and made every setup rerun uninstall both packages.

Changes:

- Companion install arrays keep only npm:pi-web-access; legacy pi-ask-user cleanup untouched.
- New remove_pi_rpiv_packages / Remove-PiRpivPackages run unconditionally in both Pi-setup branches: pi remove for both sources with a jq/PowerShell settings.json strip fallback when the pi CLI is missing (pi-subagents retirement pattern, ADR-0001).
- New tests/pi-rpiv-removal-contract.sh regression guard with functional mock-pi idempotency check and settings fallback check (mixed string/object entries); companion and ai-coding-agent contracts updated for the new desired state.
- README documents the retirement; versions bumped (mac 205, ubuntu 228, wsl 172, pi 188, bazzite 87, win 126).

Verified: no chezmoi template seeds either package (no dotfiles companion change needed); no skill references either tool; bash -n + shellcheck clean; all 11 tests/*.sh suites pass; markdownlint README clean. pwsh unavailable, so PowerShell runtime tests skipped.

PR: <https://github.com/scowalt/machine-setup-scripts/pull/83> (pushed with --no-verify: pre-existing markdownlint-all failures in vendored CLAUDE.md sections, unrelated to this change).
<!-- SECTION:FINAL_SUMMARY:END -->
