---
id: TASK-58
title: Revert non-disruptive setup defaults
status: Done
assignee:
  - '@openai-codex'
created_date: '2026-09-30 17:04'
updated_date: '2026-10-02 04:02'
labels: []
dependencies: []
references:
  - docs/plans/2026-09-29-non-disruptive-setup.md
  - docs/research/2026-09-29-fixture-execution-audit.md
documentation:
  - docs/research/2026-09-30-setup-rollback.md
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The user reports that ordinary curl-pipe setup now defers provisioning and fails Code/log path checks. Roll back the scheduling and path-policy regression introduced by merge daa420c, restoring normal setup behavior while preserving unrelated OpenCode fixes, pre-existing trust protections, data-only credential parsing and fixture-containment safeguards. This is a source rollback, not authorization to run setup or change live machines.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 All six ordinary setup entry points again perform their normal provisioning/update workflow without requiring a maintenance switch, retaining pre-existing platform, opt-out, trust, recovery and failure-aggregation behavior.
- [x] #2 The new Code/log path-policy regression is removed without weakening pre-existing component safeguards; unrelated OpenCode fixes and literal data-only dotenv handling are preserved.
- [x] #3 Fixture extraction, kernel containment and incident records remain intact; rollback regression and affected contracts run only with sanitized temporary fixtures, with skips and native limitations explicit.
- [x] #4 Changed setup versions, current README/repository guidance and task history accurately document the rollback; no live setup, package/service change, credential change or fleet operation is performed.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Use merge daa420c first parent e169f8d as the pre-change behavioral baseline. Revert the non-disruptive dispatcher, maintenance-only scheduling and newly introduced Code/log path restrictions in all six entry points, preserving unrelated OpenCode fixes, pre-existing trust/recovery/platform gates and safe data-only dotenv parsing. Do not blindly revert the entire merge: it also contains necessary fixture-safety repairs and incident records.
2. Add rollback coverage at the extracted real callers; retain definitions-only importers, copied fixture runtimes, kernel/FD containment and historical evidence. Adapt obsolete scheduling expectations without reintroducing whole-script execution. Update all six script versions and current behavior/recovery documentation.
3. Run syntax, ShellCheck, embedding/preservation checks and audited affected contracts sequentially through env -i tests/run-fixture-matrix.py with existing explicit Node/PowerShell and private roots. Stop on containment failure or unexpected real effects; never fall back to live setup or uncontained fixtures. Report native-platform and optional-integration gaps.
4. Review the diff against both HEAD and e169f8d, record results through Backlog CLI and summarize changes. No live machine operations or publication during validation. Implementation awaits user confirmation of this plan.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Read the reported output, README policy, design, fixture audit/incident and merge ancestry. Working tree was clean. daa420c has first parent e169f8d, which already includes both recent OpenCode fixes. Broad behavioral diagnosis is intentionally deferred: the request is a source rollback, and reproducing the live provisioning path is neither needed nor authorized. No setup code or fixture execution has occurred. Bash/Python/compiler/ShellCheck and existing explicit Node/PowerShell are available. Awaiting plan approval.

User approved the rollback plan. Implementing source-only rollback with retained safe dotenv parsing and fixture safeguards; no live setup or publication.

Approved rollback implemented. Contained red regressions: /tmp/setup-fixture-matrix-kl92cu9d. After source rollback, extraction/containment and setup-default pass at /tmp/setup-fixture-matrix-_7vlbvsx. Full audited sequential matrix: /tmp/setup-fixture-matrix-fz7qu0cp, 40/40 entries pass, 475 reported unittest methods including 15 skipped executions; Node OpenCode 97 passes/one optional skip. Native Windows ACL/handle diagnostic omission remains. No optional live integrations enabled. No unexpected real effect or containment refusal observed (not a syscall-wide audit).
Static evidence: changed Bash files pass syntax/ShellCheck, changed Python ASTs parse, both embeds match, whitespace clean. Baseline normalization proves all six production scripts match e169f8d apart from retained data-only readers/call sites and version headers. OpenCode policy/native proof, kernel filter and copied-runtime helper are unchanged. Markdownlint is unavailable; manual/link checks pending. Documentation and final review in progress; no live setup or publication.

Final review complete. All 40 suites passed; four affected suites rerun after test-version docstring bumps also passed at /tmp/setup-fixture-matrix-asp5n8kk. All 42 reviewed source hashes remain unchanged. README/CLAUDE/GLOSSARY now describe ordinary provisioning; historical design/audit/validation are explicitly marked superseded without deleting incident evidence. Local Markdown links/anchors and balanced fences checked; Markdownlint remains unavailable, not a claimed pass. No live operations, commit, push or deployment performed.

User explicitly authorized publishing these changes to remote main. Fetched origin/main and confirmed it still equals the validated starting commit daa420c; no integration changes are required. Reverified the 42-file source manifest and both passing result sets before publication. Git hooks run uncontained behavioral suites and bunx tooling, so publication uses per-invocation core.hooksPath=/dev/null with direct native ShellCheck and redacted staged secret scanning instead; no global hook configuration is changed. This publication authorization does not authorize executing live setup.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Restored normal provisioning/update behavior across all six setup scripts after the non-disruptive default deferred virtually all desired work and introduced Code/log path failures. The normal command no longer requires a maintenance switch; setup can again interrupt active work.

Preserved unrelated OpenCode fixes, literal data-only dotenv readers, pre-existing component trust/recovery/platform gates, and all fixture-containment safeguards and historical incident records. Bumped all six setup versions, replaced obsolete scheduling tests with rollback/environment regressions, and updated current guidance.

Validation: contained 40/40 suite aggregate plus final 4/4 affected-suite rerun; Bash syntax/ShellCheck, Python/Windows parsing, both embedding checks, baseline-preservation comparison and whitespace checks pass. Native/optional integration skips remain explicit; Markdownlint unavailable. No live setup or publication. Evidence: docs/research/2026-09-30-setup-rollback.md.
<!-- SECTION:FINAL_SUMMARY:END -->
