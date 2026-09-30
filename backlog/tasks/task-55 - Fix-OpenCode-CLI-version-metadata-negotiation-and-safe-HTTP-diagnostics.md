---
id: TASK-55
title: Fix OpenCode CLI version metadata negotiation and safe HTTP diagnostics
status: Done
assignee:
  - '@openai-codex'
created_date: '2026-09-29 17:08'
updated_date: '2026-09-29 17:25'
labels: []
dependencies: []
references:
  - lib/opencode-cli.cjs
  - tests/opencode-cli.test.cjs
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Version-specific npm metadata rejects the abbreviated package-index media type with HTTP 406. Fix request selection without increasing whole-index responses or weakening installer safety, and expose only controlled download-stage/status diagnostics.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Scoped/unscoped version metadata uses JSON; package indexes remain abbreviated and artifact/latest requests remain appropriate, with existing safety boundaries preserved.
- [x] #2 Deterministic offline tests exercise the real HTTP helper and inert installation flow, fail before the fix, and pass afterward; saved metadata replay passes.
- [x] #3 Core and Bash/PowerShell wrappers report only allowlisted operation and HTTP status on download failure and reject untrusted diagnostics while preserving recovery/finalization behavior.
- [x] #4 All six embeddings and setup versions are updated; relevant documentation and required offline contracts/lint are verified with skips recorded.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Reproduce the saved public metadata replay and add header-sensitive offline tests through the actual HTTP helper and inert install/artifact callers.
2. Select Accept by endpoint shape, retaining abbreviated indexes; add a small allowlisted download operation/status protocol with strict Bash/PowerShell validation.
3. Regenerate all six embeddings, bump changed versioned scripts, and document safe diagnostics.
4. Run the saved replay, OpenCode tests, embedding check, shellcheck and required affected offline regressions; record skips/native-rollout limits and self-review the diff.
Scope already explicitly approved by the user through the parent; no additional agents, live setup/network/application execution, commits or unrelated edits.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Confirmed clean HEAD 2502c3f. Saved replay failed before changes: abbreviated Accept -> HTTP 406; download error. Parent diagnosis accepted; no repeat live network investigation needed.

- Regression red before core changes: Node suite 43 passed, 12 failed, one optional skip. Seven header-sensitive helper/artifact/install regressions failed with download; the diagnostic assertions additionally detected the missing serializer. Bash/PowerShell caller regressions rejected the missing controlled diagnostics.
- Endpoint-based Accept selection preserves abbreviated indexes, selects JSON for version/latest metadata and octet-stream for tarballs (including encoded scoped names). Typed download errors carry allowlisted operation/status only; wrappers reject malformed/multiline/untrusted output and preserve rollback guidance.
- Saved public replay now succeeds: application/json -> HTTP 200, native-package metadata retrieved. All six standalone embeddings regenerated and setup/helper/test versions bumped.
- Initial green full contract: 56 Node tests + all 7 caller tests pass with existing PWSH and installed cmd-shim. ShellCheck passes for lib wrapper and all five Bash entry points. AI-agent, reliability (including PowerShell), weekly, headless, shared runtime (including both PowerShell modes), Pi Go (including installed lock/catalog), Go wiring, Paseo, reboot, CLT and Homebrew results pass. Final self-review/entrypoint regression rerun pending.

- Final red/green evidence: the complete current Node regression suite against a temporary copy of HEAD original core reports 44 passed / 13 failed / zero skipped; against the fixed core it reports 57 passed / zero failed / zero skipped. All 7 Bash/PowerShell caller contracts pass. Added actual CLI entrypoint coverage for safe package-version/HTTP-406 output and nonzero status.
- Final self-review: git diff --check and embedding --check pass. Verified that all six entry points differ only in generated OpenCode blocks and version banners; no unrelated caller/lifecycle changes. Removed generated Python bytecode from the worktree.
- Optional skips only: weekly managed-skill suite skips two MANAGED_SKILLS_CLI offline native fixtures and one PI_SKILLS_DOTFILES_SOURCE fixture; shared runtime skips one PI_RUNTIME_DOTFILES_SOURCE convergence fixture; Paseo skips one PASEO_UNMANAGED_DOTFILES_SOURCE source contract. Existing PWSH_BIN, cmd-shim and installed Pi lock/catalog fixtures were enabled. No dependencies installed.
- Evidence logs are under /tmp/opencode-fix-tests, including final-original-core-red.log, final-contract.log and each regression suite log. No live setup, live network downloads, OpenCode/skill execution, fleet or credential changes. Native Windows ACL/filesystem, Apple/ARM and real machine installation remain rollout-only; not claimed verified.

Parent review completed: inspected shared core/wrapper/test/documentation diffs, confirmed all six entry points change only generated policy and incremented version banners, independently reran embedding and whitespace checks, ShellCheck, saved HTTP replay (200/pass), and the OpenCode contract (56 Node pass/1 optional shim skip; 5 caller pass/2 optional PowerShell skips in parent environment). Reviewed child evidence for all 57 Node and 7 caller tests passing with optional prerequisites enabled. No blocking findings; changes remain uncommitted and native rollout remains unverified.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Fixed OpenCode CLI installation failing on npm version metadata with HTTP 406.

Changes:

- Select JSON for version/latest metadata, preserve abbreviated package indexes, and request binary tarballs with an appropriate media type, including scoped and encoded package shapes.
- Emit only typed, allowlisted download operation/status diagnostics; Bash and PowerShell reject malformed output without leaking raw errors, bodies, headers, URLs or paths. Recovery handling and aggregated failures remain unchanged.
- Regenerated all six standalone entry points, incremented setup/wrapper/test versions and documented the diagnostics.

Validation:

- Final tests against the original core: 44 passed / 13 failed. Fixed core: 57 Node tests and all 7 caller tests pass, including PowerShell and optional installed npm shim coverage. Original saved HTTP replay changes from 406/failure to 200/success.
- Embedding check, ShellCheck, diff whitespace check, AI-agent, setup reliability (PowerShell included), weekly, headless, shared runtime (both PowerShell argument modes), Pi Go/native lock/catalog, Go wiring, Paseo, reboot, macOS CLT and Homebrew-result contracts pass. Optional cross-repository/native-skill fixture skips are documented in notes.

No application execution, live installation verification, network downloads or credential/fleet changes. Native rollout remains separate. Changes are uncommitted for parent review.
<!-- SECTION:FINAL_SUMMARY:END -->
