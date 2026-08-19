---
id: TASK-2
title: Add z.ai GLM Coding Plan provider to Pi setup with work-machine default
status: Done
assignee:
  - '@pi'
created_date: '2026-08-19 17:39'
updated_date: '2026-08-19 17:58'
labels: []
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Seed a z.ai provider (GLM Coding Plan, https://api.z.ai/api/coding/paas/v4; models glm-5.3, glm-5-turbo, glm-4.7) into Pi's models.json whenever ZAI_API_KEY is present in ~/.env.local. On WORK_MACHINE=1 machines with that key, force Pi default to zai/glm-5.3 instead of synthetic/Kimi K3. Mirror the existing Synthetic/Kimi pattern across all 5 bash setup scripts and win.ps1, plus the chezmoi dotfiles templates so chezmoi apply does not clobber the provider.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 seed_pi_zai_models (bash) and Seed-PiZaiModels (win.ps1) seed the z.ai provider from ZAI_API_KEY in ~/.env.local, preserving existing keys; missing key warns only on work machines
- [x] #2 configure_pi_defaults/Set-PiDefaults force defaultProvider=zai and defaultModel=glm-5.3 at high thinking on WORK_MACHINE=1 machines with a z.ai key; otherwise keep synthetic/Kimi K3
- [x] #3 ZAI_API_KEY added to the ~/.env.local placeholder in all scripts; all scripts wired to call the new seed function after the synthetic seed
- [x] #4 New contract test covers z.ai seeding/default across all scripts; existing Synthetic contract test and shellcheck pass
- [x] #5 Chezmoi templates (private_models.json.tmpl, private_settings.json.tmpl) include the z.ai provider and work-machine default under the same key-presence gating; templates render valid JSON
- [x] #6 Version numbers bumped and CLAUDE.md documents the new behavior
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Add pi_zai_key_available + seed_pi_zai_models and branch configure_pi_defaults in all 5 bash scripts (identical blocks); bump versions; add ZAI_API_KEY placeholder
2. Mirror in win.ps1 (Test-PiZaiKeyAvailable, Seed-PiZaiModels, Set-PiDefaults branch)
3. New tests/pi-zai-provider-contract.sh; run all contract tests + shellcheck
4. Update CLAUDE.md Pi paragraph
5. Update chezmoi templates in dotfiles repo, validate render, commit+push
6. Commit this branch, push, open PR
<!-- SECTION:PLAN:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Seeded a z.ai GLM Coding Plan provider (https://api.z.ai/api/coding/paas/v4 with glm-5.3/glm-5-turbo/glm-4.7) into Pi's models.json wherever ZAI_API_KEY exists in ~/.env.local, and made WORK_MACHINE=1 machines with that key default Pi to zai/glm-5.3 at high thinking (others keep synthetic/Kimi K3). Mirrored across all 5 bash scripts + win.ps1 and the chezmoi dotfiles templates (key-presence gated, committed to scowalt/dotfiles main). Added tests/pi-zai-provider-contract.sh; all contract tests + shellcheck pass; functional smoke test of the real functions passed 29/29 assertions across 6 machine/key scenarios. Scripts version-bumped, CLAUDE.md updated. PR: https://github.com/scowalt/machine-setup-scripts/pull/73
<!-- SECTION:FINAL_SUMMARY:END -->
