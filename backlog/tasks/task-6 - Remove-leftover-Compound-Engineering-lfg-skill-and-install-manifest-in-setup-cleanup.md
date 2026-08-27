---
id: TASK-6
title: >-
  Remove leftover Compound Engineering lfg skill and install manifest in setup
  cleanup
status: Done
assignee:
  - '@scowalt'
created_date: '2026-08-27 19:07'
updated_date: '2026-08-27 19:07'
labels: []
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up to TASK-1. The Pi compound-engineering plugin installed the lfg skill without the ce- prefix, and the installer's manifest directory (~/.pi/agent/compound-engineering) was never removed, so both survived the legacy cleanup added by TASK-1. Setup cleanup must remove them on all platforms.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 lfg is in the Compound Engineering skill removal list in mac.sh, ubuntu.sh, wsl.sh, pi.sh, bazzite.sh, and win.ps1
- [x] #2 remove_compound_engineering_resources / Remove-CompoundEngineeringResources also removes the agent-dir compound-engineering install manifest with the existing symlink/path safety conventions
- [x] #3 Contract tests cover lfg removal, manifest removal, idempotency, and sibling preservation
- [x] #4 Script version numbers and pinned version-banner contract expectations are updated
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Pi compound cleanup missed two installer leftovers: the unprefixed lfg skill and the installer's manifest directory (~/.pi/agent/compound-engineering). Root cause: removal matched only ce- prefixed skill names, and nothing removed the manifest dir. Added lfg to the skill removal list (compound_pi_skill_names / $compoundSkillPattern) and added manifest-dir removal with the existing symlink/path safety conventions in all five bash setup scripts and win.ps1. Extended tests/ai-coding-agent-contract.sh with static assertions plus a functional test (fake HOME: lfg, ce-plan, ce-agent, manifest, plugin repo, shared-skill symlink; cleanup run twice; siblings and external symlink targets preserved). Updated pinned version banners in simple-english and gitea contract tests; bumped all six script versions. Verified: bash -n, shellcheck (severity=style, enable=all), all 16 contract tests pass.
<!-- SECTION:FINAL_SUMMARY:END -->
