---
id: TASK-19
title: Fix the existing PowerShell PR Lens ownership reliability failure
status: To Do
assignee: []
created_date: '2026-09-11 18:58'
labels: []
dependencies: []
references:
  - tests/setup-reliability-powershell.ps1
  - win.ps1
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The optional PowerShell reliability suite fails on Linux with PowerShell 7.6.6 at tests/setup-reliability-powershell.ps1:453: PR Lens direct-copy exclusion missing or repeated. This reproduces on unmodified main commit 6477413 as well as the Bazzite home-alias branch. The two relevant files, win.ps1 and tests/setup-reliability-powershell.ps1, are unchanged by the home-alias fix. Diagnose this separately without weakening production ownership checks or running full setup.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The PR Lens ownership fixture passes on Linux PowerShell, with a regression test for the diagnosed failure.
- [ ] #2 Identical managed copies are removed, user-modified copies are preserved and excluded once, and canonical shared copies remain active.
- [ ] #3 Validation uses isolated fixtures without live setup, skill installation, diagram uploads, or changes to user profiles.
<!-- AC:END -->
