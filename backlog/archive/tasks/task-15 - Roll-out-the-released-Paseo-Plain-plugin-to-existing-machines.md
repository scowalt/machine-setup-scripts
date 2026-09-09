---
id: TASK-15
title: Roll out the released Paseo Plain plugin to existing machines
status: To Do
assignee: []
created_date: '2026-09-09 13:40'
updated_date: '2026-09-09 13:46'
labels: []
dependencies:
  - TASK-14
references:
  - >-
    /home/scowalt/Code/paseo-plain/backlog/tasks/task-3 -
    Prepare-Paseo-Plain-for-public-Git-installation.md
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
After the public release and setup integration are approved and validated, apply only the plugin installation/update steps to existing machines. Do not rerun full machine setup, remotely restart daemons, publish private fleet details, or trigger real model work without separate approval.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A private inventory accounts for every in-scope personal and work machine, daemon identity/home/owner, client and daemon compatibility, plugin trust state, and supported worker runtime.
- [ ] #2 The release succeeds first on devinabox and one Mac daemon, then on other supported hosts, with source/commit, running state, original-text fallback, and preserved configuration recorded.
- [ ] #3 Windows, WSL, ARM, offline machines, and missing credentials are verified on the relevant platform or remain explicit named blockers; no claim that all machines are complete while any target is unresolved.
- [ ] #4 No authentication data or cached conversation content is copied between hosts; no unrelated services/plugins/agents are changed; no model call occurs except a separately approved synthetic test.
- [ ] #5 A tested recovery path and concise per-host completion/pending report are available, with actual client confirmation distinguished from offline tests.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Scott removed this work from scope: no inventory of existing machines and no one-time fleet rollout. Only future machine-setup-script runs should install the plugin.
<!-- SECTION:NOTES:END -->
