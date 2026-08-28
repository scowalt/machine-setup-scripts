---
id: TASK-7
title: Remove opencode from machine setup scripts
status: Done
assignee:
  - '@pi-agent'
created_date: '2026-08-28 16:40'
updated_date: '2026-08-28 17:20'
labels: []
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
opencode support went nowhere; retire it via passive abandonment. Scripts stop installing, updating, validating, or mentioning opencode entirely. Existing installations on machines become unmanaged leftovers; no cleanup code is added (unlike prior active retirements). Decision recorded here instead of an ADR because abandonment is trivially reversible.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 mac.sh, ubuntu.sh, wsl.sh, and bazzite.sh contain no opencode references except the permanent RTK cleanup path
- [x] #2 install_opencode and validate_opencode_keys functions and their main-wiring calls are deleted
- [x] #3 BAN_OPENCODE opt-out is removed from scripts and docs
- [x] #4 Skills installs drop --agent opencode and ~/.config/opencode/skills management
- [x] #5 pi.sh and win.ps1 are unchanged
- [x] #6 Contract tests updated and passing
- [x] #7 README.md and CLAUDE.md contain no opencode mentions
- [x] #8 Version numbers bumped on the four changed scripts
- [x] #9 shellcheck passes on modified scripts
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Delete install_opencode, validate_opencode_keys, and wiring from mac/ubuntu/wsl/bazzite.sh
2. Drop --agent opencode and ~/.config/opencode/skills from Simple English and Matt Pocock skills installs
3. Remove BAN_OPENCODE everywhere
4. Update ai-coding-agent, simple-english-skill, weekly-log-audit contract tests
5. Remove opencode mentions from README.md and CLAUDE.md
6. Bump versions on the four changed scripts
7. shellcheck + run contract tests
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Decision (confirmed with user): passive abandonment, not active uninstall. No cleanup code for opencode artifacts; existing installs become unmanaged leftovers. No ADR: abandonment is easily reversible, so it fails the hard-to-reverse criterion. No abandonment notice, no BAN_OPENCODE legacy handling. RTK cleanup path in ~/.config/opencode/plugins stays per ADR 0001.

- Deleted active setup, key validation, opt-out handling, skills targets, and documentation from macOS, Ubuntu, WSL, and Bazzite.
- Preserved the permanent RTK plugin cleanup path. pi.sh and win.ps1 remain unchanged.
- Passive abandonment preserved: existing opencode binaries, data, configuration, and skill copies remain untouched and unmanaged.
- Self-review removed the product name from persistent version banners to honor the zero-mentions design.
- Verification passed: shellcheck on all modified shell files; every `tests/*.sh` contract; `bunx markdownlint-cli *.md`; `git diff --check`.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Removed opencode from the managed machine state through passive abandonment. Existing installations remain untouched and become unmanaged.

Changes:

- Deleted installation, update, smoke-test, provider-key validation, and `BAN_OPENCODE` handling from macOS, Ubuntu, WSL, and Bazzite.
- Removed opencode from Simple English and Matt Pocock skill targets and managed paths.
- Removed opencode documentation from `README.md` and `CLAUDE.md`.
- Updated contract coverage to prevent setup support from returning.
- Preserved the permanent RTK plugin cleanup path. `pi.sh` and `win.ps1` remain unchanged.
- Bumped versions for the four changed setup scripts.

Tests:

- `shellcheck mac.sh ubuntu.sh wsl.sh bazzite.sh tests/ai-coding-agent-contract.sh tests/gitea-client-installation-contract.sh tests/simple-english-skill-contract.sh tests/weekly-log-audit-regressions.sh`
- `for test in tests/*.sh; do bash "$test"; done`
- `bunx markdownlint-cli "*.md"`
- `git diff --check`
<!-- SECTION:FINAL_SUMMARY:END -->
