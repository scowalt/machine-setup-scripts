---
id: TASK-67
title: Explain BB service drop-in preflight refusals
status: Done
assignee:
  - '@pi'
created_date: '2026-10-02 13:39'
updated_date: '2026-10-02 14:33'
labels: []
dependencies: []
references:
  - ubuntu.sh
  - tests/bb-server-contract.sh
  - tests/test_bb_directory_preflight.py
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The Beelink setup log reported only a generic BB failure because existing managed-service drop-ins are rejected silently. Add actionable, non-secret diagnostics without changing the refusal policy or live machine state.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Existing app or ingress service drop-in paths, including empty directories and links, fail with a controlled diagnostic identifying the affected managed unit and override boundary; no override contents or arbitrary paths are disclosed.
- [x] #2 Loaded systemd drop-ins also fail with a controlled diagnostic while preserving existing unit identity and rejection checks.
- [x] #3 Regression fixtures exercise real preflight/caller behavior with inert commands and temporary state, demonstrate red before green, and verify refusal, preservation, continuation and error aggregation.
- [x] #4 Affected contracts pass under mandatory fixture containment; Bash syntax and ShellCheck pass, and the Ubuntu script version is incremented.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Approved diagnostic-only plan (user approval in thr_gkcbxeis63):

1. Promote the minimal silent-drop-in reproduction into temporary-state regression coverage for both managed units and loaded overrides, including preservation and real caller aggregation.
2. Add controlled diagnostics at the existing rejection boundaries without accepting, removing, inspecting or mutating overrides. Increment Ubuntu setup version.
3. Run red/green fixtures, extraction/containment, setup-default, BB-server and affected reliability/headless contracts sequentially under the mandatory sanitized kernel-filter runner; run Bash syntax and ShellCheck.
4. Review the diff, document test evidence and limitations, and leave live services/configuration untouched.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
User approved the diagnostic-only repository fix. Prior read-only diagnosis and private scratch fixtures established that even an empty app-service drop-in directory returns 1 silently. The two live overrides add TMPDIR and a required .env.local reference; no referenced environment file was read. Current work must preserve refusal, not accept or remove overrides.

Implemented controlled messages at the existing local drop-in-path and loaded DropInPaths refusals. Messages identify only setup-owned unit names and a literal $HOME-relative path; no systemd-returned paths or override contents are printed. Nonzero refusal, linked/empty/file-path rejection and unit identity checks remain unchanged. Ubuntu version is 290.

Added tests/test_bb_service_preflight.py and wired it into bb-server-contract.sh. It independently validates ten real definitions, installs inert helpers/commands before execution, checks inherited kernel denial, and exercises both managed units, populated/empty/file/linked/dangling paths, loaded external overrides, clean/invalid unit metadata, repeated results, unchanged snapshots and the real main/run_setup_tasks continuation/finalization path. No production instrumentation remains.

Red evidence: /tmp/setup-fixture-matrix-m15lhjnl (16 missing-diagnostic assertions; clean and identity controls passed). The earlier /tmp/setup-fixture-matrix-bn3v2f9t also exposed a fixture trace hidden by production stderr suppression; repaired only its private event descriptor before the second red run. No containment failure or real effect occurred. Targeted green: /tmp/setup-fixture-matrix-r7hhj2ub (5 methods). Original unchanged scratch fixture replay against patched source: /tmp/bb-dropin-green-replay.hRFOwq/setup-fixture-matrix-fgw7dqno (2 methods, green; original red artifacts retained).

Sequential contained matrix: /tmp/setup-fixture-matrix-pccih3c_ passed all 8 entries: extraction/containment, setup-default, BB-server, setup-reliability, BB-machine-preparation, headless, shared-node-runtime and weekly regressions. Used env -i, explicit existing Node 24.20.0 and Linux PowerShell, private copied Chezmoi tool, unchanged mandatory filter/self-test and private stdio/roots. Bash syntax, ShellCheck and git diff --check passed.

Limitations: native mise activation/inventory skipped because mise was absent from the explicit fixture PATH; cross-repository runtime/dotfile integration was not enabled. Weekly managed-skill fixtures skipped 2 optional installed CLI probes and 1 dotfiles render probe. No native Windows/macOS, live BB continuity or rollout claim; no setup/service/configuration changes on Beelink.

Publication authorized. Remote main advanced to 3dc99ea (TASK-66 broader controlled BB diagnostics). Rebase preserves that implementation, its controlled preflight labels, corrected aggregate wording, and all unrelated upstream checks. Added our unit-specific drop-in detail alongside the existing local refusal label; loaded-override failures retain the upstream unit label. Ubuntu is now 291; BB-server contract version 2. Expanded our fixture to load the real upstream diagnostic helper, assert preserved labels and use its updated caller message. Prior v290 validation remains pre-integration evidence. No policy, lifecycle or remote-state changes.

Integrated publication validation passed 9/9 sequential contained entries: /tmp/setup-fixture-matrix-serlk9p3 (extraction/containment, setup-default, focused 5-method service preflight, BB-server including upstream 16-method diagnostics) and /tmp/setup-fixture-matrix-gdvwaor_ (reliability, BB preparation, headless, shared runtime, weekly). Mandatory compiler/kernel/FD preflights passed. Explicit tools and optional-skip limitations are unchanged from the pre-integration matrix. No containment failures, unexpected real effects or live rollout.

Final integration review preserves every upstream production change outside bb_unit_preflight, the local drop-in guard and Ubuntu version banner. Local and loaded rejection still return nonzero, original controlled upstream labels remain visible, unit/override detail is added without raw values, and the generic caller wording from TASK-66 is preserved. ShellCheck over all platform Bash scripts and the modified contract, Bash syntax, Markdownlint over root documents and this CLI-managed task, and whitespace checks pass. Publication uses command-local LEFTHOOK=0 to avoid the uncontained legacy fixture hook and bunx resolution; equivalent explicit contained suites plus installed lint and redacted staged-secret checks are used instead. Git/remote configuration is unchanged.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Explain BB service drop-in preflight refusals without weakening the safety policy, integrated atop remote main 3dc99ea and its broader TASK-66 diagnostics. Ubuntu setup is version 291; the BB-server contract is version 2.

- Identify the affected app/ingress unit and local drop-in boundary or loaded-systemd-override condition; preserve overrides and nonzero failure without exposing contents or returned paths. Retain the upstream controlled failure labels and corrected aggregate wording.
- Add real-helper and full ordinary-caller regressions for both services, populated/empty/file/linked/dangling paths, loaded overrides, no mutation, independent work and log finalization.
- Verified red-to-green fixtures, original reproduction replay and 9 integrated contained contract entries (including upstream diagnostics). ShellCheck, Bash syntax, Markdownlint, whitespace and staged secret checks pass. Optional native mise and installed-CLI/cross-repository integration probes remain skipped.

Diagnostic-only: overrides still block managed BB setup. No remote state was changed and no live setup or service restart was performed. User authorized publication to remote main without force.
<!-- SECTION:FINAL_SUMMARY:END -->
