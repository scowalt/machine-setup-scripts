---
id: TASK-44
title: Verify macOS CLT readiness and preserve setup failures
status: Done
assignee:
  - '@pi'
created_date: '2026-09-26 18:35'
updated_date: '2026-09-26 19:02'
labels: []
dependencies: []
references:
  - mac.sh
  - tests/test_homebrew_results.py
  - tests/setup-reliability-contract.sh
  - 'https://logs.scowalt.com/logs/scott-macbook-m3/2026-09-18-17-22-26-584.log'
  - 'https://logs.scowalt.com/logs/scott-macbook-m3/2026-09-18-20-12-11-356.log'
  - 'https://github.com/Homebrew/brew/blob/main/Library/Homebrew/cmd/doctor.rb'
  - >-
    https://github.com/Homebrew/brew/blob/main/Library/Homebrew/extend/os/mac/diagnostic.rb
documentation:
  - 'https://docs.brew.sh/Manpage'
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The September 26 centralized log audit found both September 18 scott-macbook-m3 runs reporting Command Line Tools as up to date before Homebrew rejected them for macOS 27. Extracted inert fixtures against current main also confirmed that failed softwareupdate queries and failed CLT installations are reported as success. Correct CLT readiness and final-result reporting without deleting installed toolchains or changing unrelated Paseo checks.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 CLT readiness is verified against the running macOS and selected toolchain, including supported full Xcode selections; absent offers or an existing xcode-select path alone never prove compatibility.
- [x] #2 Failed update queries, installation attempts, cleanup or readiness verification produce a nonzero final setup result with truthful diagnostics, while unaffected work and log finalization still run.
- [x] #3 Existing developer tools and the selected developer directory are preserved; no destructive replacement, forced selection or security relaxation is used. Initial headless installation remains supported, and incompatible or unverified existing installations receive safe manual remediation guidance.
- [x] #4 Extracted helper and actual caller/finalization fixtures cover success, unavailable or malformed metadata, incompatible toolchains, query/install failures and cleanup. All validation uses temporary homes and mocked platform commands, never live setup, macOS updates or remote machines.
- [x] #5 mac.sh receives a version increment, relevant documentation is updated, and CLT fixtures, setup reliability, Homebrew result regressions, affected reboot checks and ShellCheck pass with native macOS verification limits documented.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Confirm the native Apple/Homebrew compatibility rules for the running macOS, CLT receipts, selected compiler/SDK and full Xcode. Keep compatibility unknown distinct from compatible, rather than adding an unsupported version guess.
2. Add failing, extracted-function fixtures for the audited false-positive readiness result and failed query/install status masking, plus the actual setup caller and final-log seam. Mock every platform, privilege and filesystem mutation command.
3. Implement non-destructive CLT readiness and installation handling: preserve installed tools and developer selection, retain command and cleanup failures, verify successful installations, and provide manual remediation for unsupported or unverifiable existing tools. Aggregate failure into the final setup result while continuing unaffected work.
4. Extend edge-case tests for full Xcode, no update offered, malformed/missing metadata, failed install/cleanup and earlier errors. Update README and increment mac.sh from version 243.
5. Run CLT fixtures, bash tests/setup-reliability-contract.sh, python3 tests/test_homebrew_results.py, affected pending-reboot/weekly contracts, bash syntax and ShellCheck. Self-review the diff and document that native macOS behavior has not been exercised on this Linux host. No live setup, remote changes, toolchain deletion, forced reselection or Paseo changes.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Started from current upstream main a044f55 on fix/macos-clt-readiness. Confirmed softwareupdate status is discarded, successful xcode-select plus no matching update text is treated as readiness, installer failures are followed by success messages, and the CLT caller does not aggregate failures. Existing audit fixtures reproduced false success with inert commands. Bash, Python, ShellCheck and Backlog CLI are available. Awaiting implementation-plan approval before source or test changes.

User approved implementation on 2026-09-26: "Implement your plan in a sub-agent on the current workspace." Handing TASK-44 to the configured Paseo Implementor profile in the same workspace and branch. The earlier audit-only delegation prohibition does not apply to this explicitly authorized implementation handoff. No further plan approval is needed unless compatibility research exposes a material scope or safety change. No source/tests have been edited yet.

Implementor paused before source changes because Homebrew Ruby compatibility APIs are private. Orchestrator found the supported public interface: the brew manpage documents doctor --list-checks and named diagnostic_check arguments. Current doctor.rb dispatches explicitly requested checks and returns failure when they report findings. The macOS check_if_supported_sdk_available diagnostic produces the exact audited "does not support macOS" error; fatal toolchain diagnostics also cover missing developer tools, CLT/Xcode minimum versions, Xcode license and Xcode needing CLT. Resume using discovery plus targeted public CLI checks, not direct Ruby API calls, an invented version matrix, blanket brew doctor, or unconditional failure of healthy installations. Where Homebrew is initially absent, distinguish bootstrap/tool availability from compatibility and perform the required Homebrew validation once it is available. Missing required diagnostics must be reported as unverified, never silently omitted. This resolves the research blocker within the approved plan.

Implemented non-destructive CLT bootstrap and public Homebrew targeted doctor validation in mac.sh v244, including secondary-user PATH ordering and aggregated failures. Added inert extracted-helper fixtures plus main finalization seam and README guidance. Linux-only checks: CLT fixtures, setup reliability, Homebrew results, pending reboot, weekly regressions, bash -n, ShellCheck and git diff --check passed. Native macOS verification outstanding.

Orchestrator review found a fresh-install regression: the new anchored label parser accepts "Label: Command Line Tools..." and "*Command Line Tools..." but rejects the standard modern "* Label: Command Line Tools for Xcode-27.0" output. An inert extracted-helper probe returned status 1 with "Could not find Command Line Tools package". AC3 unchecked until bootstrap is restored. Test review also found missing full-Xcode/fresh-bootstrap/caller integration coverage, a vacuous no-up-to-date assertion because print_debug is stubbed to discard output, required diagnostic names derived circularly from implementation, and a finalization test that replaces run_setup_tasks instead of driving the CLT failure through its actual caller. Returning to implementor; do not mark Done yet.

Revision: reproduced modern * Label: CLT parsing failure red, then fixed anchored parsing for modern/bare/legacy labels. Sentinel now uses exclusive no-follow creation and inode-checked cleanup; existing sentinels fail closed. Replaced circular fixture discovery with independent required checks, controlled minimal environment, logged bounded calls and failure cases. CLT fixtures, setup reliability, Homebrew results, pending reboot, weekly regressions, syntax, ShellCheck and diff-check pass. Caller test still does not exercise actual run_setup_tasks end-to-end; native macOS verification remains pending. TASK-44 stays In Progress.

Orchestrator follow-up: the remaining caller-coverage gap is implementation work, not a user-policy blocker. Continue with a full extracted run_setup_tasks/main fixture and strict inert dependencies; Bash permits defining /opt/homebrew/bin/brew as a function, so the secondary-user absolute command can be mocked without touching the real path. Also exercise the actual embedded Perl sentinel code against a relocated temporary path rather than merely stubbing its result. Native macOS verification remains a documented limit, not a reason to omit the approved Linux fixture coverage. Restored original task code/log references alongside the public Homebrew sources.

Completed entire extracted run_setup_tasks/main caller fixture for both primary and secondary users with controlled HOME/PATH, logged inert unrelated work, real CLT helpers, bootstrap ordering, failed query/install/cleanup/doctor, earlier retirement failure, reboot and exactly-once finalization. Verified exact modern installer label and selected Xcode. Ran embedded Perl create/cleanup snippets on temporary sentinel: exclusive create, regular/link refusal, inode replacement refusal and successful cleanup. No sudo or live platform operation. Updated setup reliability script header to v3. All requested mocked Linux regressions, syntax, ShellCheck and diff-check pass. Native macOS execution remains an explicit limitation.

Final orchestrator review completed. Independently reran 7 CLT tests (including real extracted primary/secondary callers and real Perl temporary-sentinel checks), 8 Homebrew-result tests, setup reliability, pending reboot, weekly regressions (29 tests, 3 skipped), Bash syntax, ShellCheck and git diff --check; all executed checks passed. Confirmed modern label regression is covered and source changes remain scoped to macOS CLT/readiness plus docs/test wiring. Changes remain uncommitted; no live setup, remote change or native macOS validation performed.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Verified macOS developer-tool readiness via Homebrew public targeted doctor checks instead of xcode-select/no-offer heuristics. CLT bootstrap remains headless and non-destructive; native installer labels and failure status are preserved, with exclusive inode-checked sentinel cleanup. Primary and secondary setup paths aggregate failures and finalize logs. README explains Apple remediation. Tests: CLT extracted helper/caller and temporary native Perl fixtures, setup reliability, Homebrew results, pending-reboot, weekly regressions, Bash syntax, ShellCheck and diff-check pass on Linux. Native macOS validation remains outstanding.
<!-- SECTION:FINAL_SUMMARY:END -->
