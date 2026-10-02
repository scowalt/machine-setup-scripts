---
id: TASK-60
title: Make the README a concise human introduction
status: Done
assignee:
  - '@codex'
created_date: '2026-10-01 13:54'
updated_date: '2026-10-02 04:01'
labels: []
dependencies: []
references:
  - README.md
  - CLAUDE.md
  - docs/adr/0001-keep-cleanup-for-retired-managed-tools.md
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Replace the accumulated operational and implementation reference with a first-person explanation of why these personal machine setup scripts exist, representative capabilities, and compact platform run commands. Preserve only consequential decision rationale in ADRs, prevent future README bloat through agent guidance, and remove prose-enforcing test assertions without changing setup behavior.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 README explains the personal motivation and representative capabilities in approachable prose, with all six platform commands and a clear opinionated-script/interruption warning.
- [x] #2 Detailed implementation, recovery, historical and test narration is removed from the README; consequential non-obvious decisions are captured in concise ADRs where justified, without relocating every paragraph or inventing rationale.
- [x] #3 Repository agent guidance defines the README boundary and no longer directs maintainers to removed README sections; existing incident/research records remain intact.
- [x] #4 Tests no longer require detailed README prose; setup code and behavioral assertions remain unchanged.
- [x] #5 Affected documentation and tests pass applicable static validation; any behavioral execution follows the audited containment runner and limitations are recorded.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Rewrite README as a short first-person project introduction: motivation, representative capabilities, platform commands, and a brief safety warning.
2. Preserve a small number of consequential, evidenced decisions in concise ADRs; leave historical incident/research records intact and discard repetitive mechanics rather than creating replacement manuals.
3. Update CLAUDE.md with the human-facing README boundary and repair its references to removed README sections.
4. Remove README-prose assertions only from affected tests, preserving behavioral assertions and all setup scripts.
5. Validate Markdown/link references, shell/Python syntax and modified-shell lint; review the diff for unchanged setup behavior. Use the documented containment procedure for any behavioral runs and report limitations.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Grilling complete: user approved the personal why/overview framing and compact run commands, delegated ADR selection, and explicitly approved removing README-prose tests. Awaiting confirmation of the consolidated implementation plan.

User approved the consolidated plan and explicitly requested implementation in a subagent. Delegating implementation in the current shared worktree; no additional plan approval is needed.

- Read the approved task, repository instructions, complete README, and writing-for-agents/domain-modeling ADR guidance. Baseline README: 10,330 words. Found README-prose checks in seven test files; source-scan exclusions will remain intact.
- Editorial selection: retain concise ADRs for Chezmoi shell ownership, BB preparation versus enrollment, and verified command-only OpenCode migration. Existing rollback, fixture incident/audit, and Linux desktop research already retain their decisions and will not be duplicated or changed. No glossary additions.
- Validation will be static only (syntax, ShellCheck, Markdown/link review, and exact diff preservation checks); no setup helpers or behavioral fixture loaders will run. Existing executable diagnostics that say See README are outside the approved untouched-entrypoint/library boundary and will be reported for parent review.

- Replaced README with a 266-word human introduction (10,330 words before), preserving all six exact remote command lines. Verified representative tool/runtime/dotfiles claims against setup sources.
- Added three concise ADRs (86/96/97 words): Chezmoi shell ownership avoids competing installer edits; separate BB preparation protects enrollment ownership and avoids global CLI fallback/shadowing; verified command-only OpenCode migration preserves recovery/data without uninstall hooks. No ADR for the reversible README editorial policy.
- CLAUDE.md now enforces the human README boundary and routes removed-section pointers to code/contracts or existing records. Repaired one historical plan link with a commit-pinned README permalink; all research/incident records and GLOSSARY.md remain unchanged.
- Removed 26 README prose assertion cases across seven test files, including the optional dotfiles README check. Kept source-scan exclusions and existing CLAUDE/GLOSSARY checks. Shell contract version comments updated; all six setup entry points and implementation libraries remain unchanged.
- Static checks passed: bash --noprofile --norc -n and /usr/bin/shellcheck on all six modified shell contracts; /usr/bin/python3 -I ast.parse on tests/test_paseo_non_management.py; CommonMark parsing/closed fences/local links for all six changed/new documentation files (17 local links); exact comparison of all six README commands to HEAD; historical permalink object/heading checked locally.
- One-off static preservation checks passed: shell statements identical after removing README checks/comments and unrolling the documentation-only CLAUDE loop; Python AST identical except its one README assertion; 22 protected files byte-identical to HEAD (entry points, lib, tools, fixture extractor/runner, research, glossary, existing ADR). git diff --check passed.
- Limitations: no behavioral fixtures, setup helpers, source loaders, apps/extensions/skills, native rollout, external URL requests, secrets/log retrieval or system changes executed. markdownlint was unavailable; used existing system markdown-it parsing, link checks and manual formatting review instead, not a claimed markdownlint pass. Existing BB/OpenCode executable diagnostics still say See README; untouched per approved code boundary, flagged for parent review.

- Publication requested by user. origin/main was fetched and remains the original base 4bb7febcf926d819dbc3c3550534f4692fa112f8; no integration conflict.
- Publication validation: sanitized env -i tests/run-fixture-matrix.py with explicit existing Node 24.20.0 and /usr/bin:/bin passed all 9 affected/default/containment suite entries. Mandatory kernel filter/self-test passed. Private evidence: /tmp/setup-fixture-matrix-lqh_0mh4. PowerShell and optional cross-repository cases reported skips; no native rollout claim.
- Re-ran system ShellCheck on all five Bash setup entry points plus six modified shell contracts, six Bash syntax checks, Python AST syntax and git diff --check: passed.
- Existing Git hooks use uncaged fixture execution and bunx tool resolution. Publication uses command-scoped LEFTHOOK=0 after manual safe validation, without changing hook configuration. Markdownlint remains unavailable: cached CLI fails dependency resolution and cached packages have unsafe writable files; no cache permissions or dependencies changed. Staged secret scanning will run separately.

Staged gitleaks protect --staged --no-banner --redact passed (no leaks); staged diff whitespace check passed. Publication is a non-force fast-forward of remote main; no production setup code changes.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Made README a concise, first-person introduction: 10,330 → 266 words, with representative capabilities, all six original run commands, and the personal-script/interruption warning.

Preserved three consequential ownership/trust decisions in short ADRs (Chezmoi shell configuration, BB preparation versus enrollment, verified command-only OpenCode migration). Updated CLAUDE.md documentation boundaries and removed-section pointers, and pinned one historical plan reference to its original README in Git history. Existing research/incident records, glossary, setup scripts and implementation libraries are unchanged.

Removed 26 README-prose assertion cases from seven test files without changing behavioral assertions, fixture loaders, or source-scan exclusions.

Validation: six shell syntax checks and ShellCheck passed; modified Python AST parsed; CommonMark/fence/local-link checks passed for six documentation files; all six run commands match HEAD exactly; static statement/AST comparisons preserve non-README tests; 22 protected files match HEAD byte-for-byte; git diff --check passed.

Limitations: markdownlint unavailable (existing system Markdown parser and manual review used instead); external URLs not fetched; behavioral/native suites and rollout were not run. Existing executable BB/OpenCode diagnostics referencing README were deliberately left untouched under the approved code boundary and are flagged for parent review. Changes remain uncommitted; no push or PR.

Publication validation: the audited sanitized runner subsequently passed 9/9 affected/default/containment suite entries, with mandatory kernel denial self-test. PowerShell and optional dotfiles cases skipped; no native-platform evidence. System ShellCheck also passed for all Bash setup entry points and modified contracts. Prior static-only limitation now applies only to the implementation stage. Markdownlint is still unavailable; unsafe/uncontained hooks will be suppressed only for these Git commands, with safe checks run manually.
<!-- SECTION:FINAL_SUMMARY:END -->
