---
id: TASK-66
title: Expose controlled Ubuntu BB server failure diagnostics
status: Done
assignee:
  - '@bb-logging-thr_r53w3qjamd'
created_date: '2026-10-01 17:03'
updated_date: '2026-10-02 03:59'
labels:
  - setup
  - bb
  - ubuntu
  - diagnostics
dependencies: []
references:
  - ubuntu.sh
  - tests/bb-server-contract.sh
  - tests/test_bb_directory_preflight.py
  - tests/run-fixture-matrix.py
documentation:
  - docs/research/2026-09-29-fixture-execution-audit.md
  - docs/research/2026-09-29-fixture-containment-incident.md
  - docs/research/2026-09-30-setup-rollback.md
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Ubuntu setup v287 on scott-beelink-ubuntu reported only the aggregate BB server failure at collector log line 307. The failed predicate is not yet known. Add precise, secret-safe operation/check diagnostics across the existing BB server failure paths without speculative repairs or operational policy changes. Remote diagnostics are owned by a separate agent; this task is repository-only logging and regression coverage.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Previously silent failures in setup_bb_server and the server-specific helpers it calls produce controlled operation/check labels and safe reasons that identify the failed boundary in the setup log, including preflight, installation, service/configuration operations, readiness, ownership promotion and restoration failures.
- [x] #2 Diagnostic output never includes raw subprocess stderr or exceptions, credentials/config contents or uncontrolled paths; command-substitution success values remain intact, repeated readiness probes do not spam the log, and an original failure remains visible when restoration also fails.
- [x] #3 Existing success/skip and failure statuses, ownership/security predicates, npm/runtime policy, data/configuration preservation, mutation ordering, service lifecycle/restoration attempts and final failure aggregation/log finalization remain unchanged; messages do not claim preservation or stopped state beyond verified evidence.
- [x] #4 Extracted-helper and real-caller fixtures with inert commands and temporary homes cover failure labels, adversarial secret/path output, no-mutation preflight, unchanged update/restoration ordering, success, and continuation/finalization; no live setup, remote checks, installs or BB/Tailscale operations occur.
- [x] #5 Production edits are Ubuntu-only, ubuntu.sh version/last-change is incremented, and contained BB server/default/extraction plus affected reliability/headless/shared-runtime regression suites and Bash syntax/ShellCheck pass, with skips and native rollout limitations recorded.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Approval gate: planning only. Do not edit production/tests or execute behavioral fixtures until parent relays USER approval. No remote/live checks; diagnostics belong to thr_64mctwwfaz.

1. Audit all failure exits in setup_bb_server and its server-only helpers against ubuntu.sh v287. Map silent/overbroad boundaries across command discovery, metadata/ownership, saved endpoint, systemd prerequisites, npm/runtime/package checks, lingering, stopped updates, native config merge, file writes, service activation, readiness, owner promotion and restoration. Existing checked predicates and command order are the behavioral baseline; the reported root cause remains unknown.
2. Add focused controlled operation/check labels and fixed safe reasons, with only allowlisted logical locations where needed. Keep command-substitution stdout clean, suppress rather than expose raw command errors, and never log arbitrary paths, values, JSON, credentials, exceptions or general tracing. Distinguish command failure from rejected/unverified results only where existing evidence supports it. Preserve the primary failure before restoration; report restoration failures separately. Report bounded terminal readiness failures rather than one message per polling attempt. Correct blanket preserved/stopped claims that are not guaranteed after partial mutation, without changing rollback behavior. Do not refactor the lifecycle or alter generated service/guard behavior beyond logging.
3. Add focused definitions-only extracted-helper and real-caller regression fixtures (likely tests/test_bb_server_diagnostics.py plus BB contract wiring; adapt existing directory output assertions only as necessary). Inject failures through preflight, nested npm checks, configuration writes/locks, service operations, readiness and restoration. Assert nonzero status, exact controlled labels, absence of secret/path/stderr sentinels, no mutation before failed preflight, unchanged success/update/restore ordering, original-plus-restore failure visibility, unrelated-work continuation and log finalization. Use real helper logic where safe, all external effects mocked before invocation, private roots and inert native fixtures only. No stripped-whole-source evaluation, live BB/apps/services or optional installed-code integrations.
4. Limit production change to ubuntu.sh and increment 287 to 288 with concise last-change text. No README expansion or operational fixes; changes to other platforms or policy require parent review. No fixture-runner/kernel-filter relaxation or unrelated loader refactor.
5. Validate sequentially through env -i PATH=/usr/bin:/bin /usr/bin/python3 -I tests/run-fixture-matrix.py with the explicit existing native Node binary, available PowerShell binary and a private executable directory selecting only audited existing mise/Chezmoi tools where needed. Require compiler/filter self-test, private stdio/roots and no inherited optional integration controls. Run tests/test_fixture_containment.py and tests/setup-default-contract.sh, focused diagnostics and tests/bb-server-contract.sh, then tests/setup-reliability-contract.sh, tests/headless-contract.sh, tests/shared-node-runtime-contract.sh and tests/bb-machine-preparation-contract.sh; add affected weekly/Paseo/Go caller regressions only if final diff warrants them. Run Bash syntax, ShellCheck on modified Bash and git diff --check. Stop and report any containment refusal or unexpected real effect without fallback; do not install tools.
6. Self-review complete diff for unchanged predicates, statuses, mutation/restore ordering and secret safety. Record actual commands, retained private artifacts, results/skips and native reboot/tailnet/browser/session-continuity limitations via Backlog CLI. Deliver focused uncommitted changes and evidence to parent; no commit/push/PR or live rollout.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Read GLOSSARY.md, repository guidance, Ubuntu BB server helper/caller code and complete BB server contract; reviewed directory fixtures, definitions-only extractor, sanitized runner, fixture audit/incident and rollback evidence. Existing related tasks TASK-45/TASK-46/TASK-51 are Done and narrower/different, so created focused TASK-65.
Source findings: many silent direct failure exits; npm preflight collapses multiple checks into one broad error; several restore failures are ignored; current config/aggregate failure wording overstates preservation and ingress state. This is source evidence, not a diagnosis of the reported machine.
Existing tools found without executing fixtures: /usr/bin/python3, /usr/bin/cc, /usr/bin/bash, /usr/bin/shellcheck, /usr/bin/git, /usr/bin/fish, /usr/bin/jq, /home/scowalt/.local/share/mise/installs/node/24/bin/node, /home/scowalt/.local/bin/mise, /home/scowalt/.local/bin/chezmoi, /tmp/pi-shared-runtime-pwsh.2SlAPL/pwsh. Tool selection still requires the mandatory contained preflight after approval.
No production/test edits or behavioral execution performed. Waiting for parent to obtain and relay USER plan approval.

Parent relayed explicit USER approval: "logging plan approved". Proceeding within recorded Ubuntu-only diagnostic/test scope. Separate remote diagnosis was blocked before authenticated commands by missing trusted SSH host key; the failing BB predicate and service health remain unknown.

- Implemented Ubuntu-only fixed/allowlisted check diagnostics, detailed npm prerequisite failures, terminal readiness labels, separate restoration failures, and controlled native-config phase output. Raw helper errors remain suppressed; original config failures survive cleanup. Corrected misleading blanket preservation/stopped-state wording and bumped Ubuntu to 288.
- Added extracted-helper/caller fault-injection and secret/path-sentinel fixtures, plus inert actual log-finalization/transport coverage; no generated guard contents or service policy changed. Directory fixtures now deliberately exit at their next-gate sentinel rather than trigger unrelated failure handling.
- Initial contained cohort passed: /tmp/setup-fixture-matrix-0vpdcbsx (extraction/containment, ordinary defaults, then 13 diagnostic methods). Expanded audited cohort passed 5/5: /tmp/setup-fixture-matrix-uhyte3aq (BB server, reliability, headless, shared runtime, BB preparation). Further diagnostic coverage was added afterward, so final focused and affected validation is pending. Mandatory compiler/filter self-tests succeeded; no containment refusal or unexpected real effect observed. No live/remote checks, tools installed, commit or push.

Final-source validation passed 10/10 sequential entries under the unchanged mandatory compiler/kernel/FD containment: /tmp/setup-fixture-matrix-kyu4kmx7. Focused diagnostics: 16 unittest methods, zero skips, plus failure-injection subcases. BB contract also passed its 10 directory and 16 native/caller dotfile methods and existing generated-command/lifecycle/npm/native-lock fixtures. Bash syntax, ShellCheck for ubuntu.sh/tests/bb-server-contract.sh, Python AST parse and git diff --check passed.

Exact final command:
env -i PATH=/usr/bin:/bin /usr/bin/python3 -I tests/run-fixture-matrix.py --node /home/scowalt/.local/share/mise/installs/node/24/bin/node --pwsh /tmp/pi-shared-runtime-pwsh.2SlAPL/pwsh --tool-path /usr/bin:/bin:/tmp/task65-fixture-tools-RmZtxA --timeout 300 tests/test_fixture_containment.py tests/setup-default-contract.sh tests/bb-server-contract.sh tests/setup-reliability-contract.sh tests/headless-contract.sh tests/shared-node-runtime-contract.sh tests/bb-machine-preparation-contract.sh tests/weekly-log-audit-regressions.sh tests/paseo-non-management-contract.sh tests/opencode-go-wiring-contract.sh

The private tool directory contains only executable links selecting existing mise and Chezmoi; no runtime prefix links or tool installations. Final artifact root is 0700; logs/results are 0600. Compiler/filter self-test passed and recorded AF_INET/AF_INET6 denial. No containment refusal or unexpected real effect observed; this is not a syscall-wide filesystem/process effects audit. Earlier evidence remains retained at /tmp/setup-fixture-matrix-0vpdcbsx, /tmp/setup-fixture-matrix-uhyte3aq and /tmp/setup-fixture-matrix-a0aph3hp.

Five optional skipped executions: shared-runtime external-dotfiles convergence (1), managed-skill installed native discovery/snapshot and external-dotfiles rendering in weekly regression (3), Paseo external-dotfiles source contract (1). Available Linux PowerShell fixtures ran, including both shared-runtime modes with 1409 assertions each; native Windows ACL/PS5.1 and native Mac/ARM/WSL behavior remain separate. No optional installed-code/live integration was enabled.

Self-review: the generated BB_GUARD heredoc is byte-identical to HEAD; app/ingress unit-render expressions are unchanged. Static normalization of the BB helper block, version banner and aggregate diagnostic proves all other Ubuntu production code unchanged. Reviewed unchanged predicates, command arguments, short-circuit order, stopped-update/restore order, safe primary-plus-restore diagnostics and failure aggregation. Tests verify actual stderr capture into the real finalized log via inert upload-copy, native config partial-write honesty, first failure preservation across unlock errors and original nonzero helper exit status (17).

Only ubuntu.sh, tests/test_bb_server_diagnostics.py, tests/bb-server-contract.sh, tests/test_bb_directory_preflight.py and this CLI-managed task changed. No README/agent-guide/other-platform/kernel-runner changes. Original Beelink failure predicate and current service health remain unknown; native reboot, logout, tailnet UI/WebSocket and session continuity need separate authorized rollout. No remote checks, live setup, real BB/Tailscale lifecycle, commit/push/PR or rollout.

Publication authorized by user: get these changes onto remote main. Remote main advanced to d078a4c (BB plugin refresh and Bash 3.2 helper transport fixes). Preserved those commits and their caller wiring. CLI demote/promote renumbered this branch-local TASK-65 to TASK-66 without altering upstream unrelated TASK-65. Resolved the sole version-banner conflict as Ubuntu 290; the earlier v288 test evidence remains pre-integration evidence. Rerunning affected contained validation before committing/pushing; legacy uncontained hooks will be disabled per-command in favor of explicit contained tests and lint/security checks.

Integrated-source publication validation passed 12/12 sequential entries at /tmp/setup-fixture-matrix-pjsi081h with unchanged mandatory kernel/FD self-test. Exact runner prefix: env -i PATH=/usr/bin:/bin /usr/bin/python3 -I tests/run-fixture-matrix.py --node /home/scowalt/.local/share/mise/installs/node/24/bin/node --pwsh /tmp/pi-shared-runtime-pwsh.2SlAPL/pwsh --tool-path /usr/bin:/bin:/tmp/task66-fixture-tools-a9MASO --timeout 300. Suites: extraction/containment, ordinary defaults, Bash compatibility, BB plugin refresh, BB server (16 diagnostic methods), reliability, headless, shared runtime, BB preparation, weekly, Paseo non-management, Go wiring. The tool directory selects existing mise/Chezmoi and copies an existing Linux Bash 3.2 executable; no tools installed. Five optional integrations remain skipped; Bash 3.2 compatibility ran without skips. No containment refusal or unexpected real effect observed; native rollout remains unverified. Static comparison proves the diagnostics block is identical to the earlier tested source and all upstream production changes/plugin wiring are preserved. Remote main remains d078a4c at the final fetch. Publication uses command-local LEFTHOOK=0 rather than uncontained fixtures or bunx tool resolution; explicit system ShellCheck, syntax, whitespace and redacted staged secret scans replace those hook commands. Trusted installed Markdownlint remains unavailable; task Markdown manually reviewed.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Ubuntu BB server setup now reports controlled failed-check labels instead of silent returns or only a generic incomplete-setup message. Production changes are limited to ubuntu.sh, version 290, integrated atop remote main d078a4c. This task was branch-local TASK-65 and was renumbered TASK-66 via Backlog CLI to preserve upstream's unrelated TASK-65.

- Fixed allowlisted diagnostics cover commands, endpoints/units/metadata, npm policy/ownership, lingering, stopped updates, native config phases, service operations, terminal readiness, ownership promotion and restoration. Raw command errors, credentials and arbitrary paths are not exposed by the new diagnostics.
- Original config failures and exit status survive cleanup; restoration failures are separately reported. Messages no longer overstate configuration preservation or stopped ingress after partial operations.
- Existing predicates, lifecycle ordering, generated guards/units and failure finalization are unchanged. Upstream BB plugin refresh and Bash 3.2 transport fixes are retained.
- Added 16 focused diagnostic methods with inert helpers/callers, fault injection, secrecy sentinels and finalized-log capture.

Validation: all 12 integrated-source contained entries passed at /tmp/setup-fixture-matrix-pjsi081h, including BB plugin refresh and Bash 3.2 compatibility, plus ShellCheck/syntax/whitespace and production-scope checks. Five optional integrations remain skipped. Native rollout and the original SSH-blocked machine failure remain unverified. User authorized a non-force push to remote main; no live setup or machine changes are part of publication.
<!-- SECTION:FINAL_SUMMARY:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 Receive relayed user plan approval before production/test edits or behavioral execution.
- [x] #2 Self-review the complete diff for scope, secret safety, unchanged predicates/statuses and lifecycle ordering; leave changes uncommitted and report evidence to parent.
<!-- DOD:END -->
