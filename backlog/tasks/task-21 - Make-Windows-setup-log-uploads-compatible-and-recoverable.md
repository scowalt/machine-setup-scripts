---
id: TASK-21
title: Make Windows setup log uploads compatible and recoverable
status: Done
assignee:
  - '@pi'
created_date: '2026-09-12 14:38'
updated_date: '2026-09-12 15:10'
labels: []
dependencies: []
references:
  - win.ps1
  - tests/setup-reliability-powershell.ps1
  - README.md
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Windows setup can fail and then lose its only opportunity to upload the diagnostic log. Investigate and harden the uploader without running live setup or changing the log collector. An isolated PowerShell fixture reproduces unsupported -Form parameter binding with a Windows PowerShell 5.1-style command and abandonment after a transient HTTP failure; the actual user failure is not yet confirmed.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The uploader supports Windows PowerShell 5.1 and PowerShell 7 without requiring installation of another tool, while preserving the collector multipart contract and TLS certificate verification.
- [x] #2 Transient upload failures receive bounded retries and timeouts; permanent HTTP failures and local errors stop with an actionable reason instead of repeated requests.
- [x] #3 The setup result and local transcript survive upload failures. Uploading waits for transcript closure, and upload diagnostics include safe error categories or HTTP status without credentials or raw server response bodies.
- [x] #4 Logs marked as pending by the new uploader can be retried on a later setup run with bounded work. Existing unmarked logs and unrelated files are not uploaded or deleted automatically, and linked paths are rejected.
- [x] #5 Offline regression fixtures exercise extracted production functions for compatibility, transient and permanent errors, pending-log recovery, and preservation of the original setup exception. Document the behavior and increment the Windows script version.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Add a focused offline PowerShell fixture that extracts only logging functions. Preserve the current passing exception/transcript checks and reproduce missing legacy parameters and one-shot transient failure before changing production code. Do not run full setup or upload fixtures to the real collector.
2. Replace the PowerShell-7-only multipart call with a byte-preserving transport available in Windows PowerShell 5.1 and PowerShell 7, without requiring curl or changing collector authentication/TLS policy. Confirm the exact transport seam and test multipart filenames and Unicode log bytes.
3. Add at most three attempts with finite request timeouts and short capped delays for transient network failures and HTTP 408/429/5xx only. Report and persist allowlisted failure category/status, attempt counts, and local recovery path; never dump raw HTTP bodies, headers, environment values, or credentials. Keep the original setup result authoritative and close the transcript before reading.
4. Record pending state only for logs handled by the new uploader. Retry at most three marked, closed logs on the next run with a fixed overall work limit; validate regular files under the managed log directory, reject links, and never scan/upload unmarked historical logs or delete the source transcripts. Remove pending state only after confirmed success. Document possible duplicate collector entries when a response is lost and that hard process termination/reboots cannot guarantee final upload.
5. Update README.md, increment win.ps1 Version 142 to 143 with a matching change description, and run parser checks plus the focused fixtures on the available Linux PowerShell 7.6.6. Run applicable reliability contracts, distinguish the known TASK-19 failure from regressions, and report that native Windows PowerShell 5.1 verification is unavailable unless a Windows test environment is supplied.
Await user approval before implementation.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Read win.ps1 logging functions and existing fixtures. Current uploader makes one Invoke-RestMethod -Form request with TimeoutSec 10 and suppresses the upload exception details. Microsoft Windows PowerShell 5.1 documentation confirms that Invoke-RestMethod lacks -Form.
- Ran /tmp/pi-shared-runtime-pwsh.2SlAPL/pwsh -NoLogo -NoProfile -File /tmp/windows-log-diagnosis.kG04se/repro.ps1 -ScriptPath "$PWD/win.ps1". Fixture extracts five functions via the PowerShell AST, uses a temporary USERPROFILE, real transcription, and mocked HTTP with no network traffic. Original setup exception, upload invocation, and exception presence in the uploaded transcript all PASS. Delivery after a transient failure FAILS with one attempt. Legacy parameter binding FAILS with zero HTTP calls.
- Ranked hypotheses: legacy parameter incompatibility, transient network/10-second timeout with no retry, transcript lock/flush failure. The first two reproduce in offline simulations; the ordinary transcript-close path passes. No claim that either simulated trigger is the exact user incident.
- Authenticated collector reads through Doppler and curl succeeded. Inspected only Windows-transcript classification of the latest upload per listed hostname; none matched a Windows transcript. Python urllib received HTTP 403, while authenticated curl worked. No credentials or downloaded log bodies were written to files or printed. No live POST, collector mutation, or Windows machine access.
- Existing TASK-19 records an unrelated failure before logging tests in the broad PowerShell reliability suite. Focused logging coverage should not depend on that suite reaching its tail.
- No production code or repository tests changed yet. Waiting for plan approval.

User approved the plan. Starting implementation with isolated regression coverage; no live setup or collector uploads.

- Implemented the uploader with .NET HttpClient/MultipartFormDataContent and raw file streaming, preserving the existing POST endpoint and multipart field. No PowerShell-7-only web parameters, curl dependency, redirect forwarding, or TLS verification bypass. Windows PowerShell 5.1 explicitly selected legacy TLS protocols gain TLS 1.2 for the request only, then caller state is restored.
- Added bounded transient retries (three attempts, up to 30 seconds each, 2/4-second backoff, 96-second request-loop budget), safe status/category output, and per-log upload metadata. The next run processes at most three marked pending logs within a shared 60-second budget. Uploaded records remain as completed state rather than being deleted, preventing close/delete/reopen races; an exclusive state-file lease prevents concurrent uploads. This is a refinement of the plan: pending state is cleared by changing it to uploaded, while both files remain for diagnosis.
- Added unique run filenames, ancestor/link checks, malformed-state preservation, open-writer protection, transcript-closure gating, and finalization exception isolation. Partial transcript-start failures and failed transcript closure never become automatic recovery candidates. Existing unmarked historical logs are not uploaded automatically.
- Added tests/windows-log-upload-contract.sh and its standalone PowerShell fixture. It extracts production functions, uses real transcript and .NET multipart/cancellation code with an in-memory handler, and does not run full setup or send network requests. Replaced the old Form-only mocks in the broad reliability suite with the standalone fixture.
- Demonstrated red before production edits: the fixture failed with "Log must upload even with PowerShell 5.1-style web cmdlets". It now passes under Linux PowerShell 7.6.6. Mutation checks also fail at the intended assertions when transient retries, next-run recovery, or partial-transcript gating are independently removed.
- Validation passed: PWSH_BIN=/tmp/pi-shared-runtime-pwsh.2SlAPL/pwsh bash tests/windows-log-upload-contract.sh; bash tests/setup-reliability-contract.sh; bash tests/pending-reboot-contract.sh; bash tests/headless-paseo-daemon-contract.sh; shellcheck and bash -n for the new wrapper; bunx markdownlint-cli README.md; git diff --check.
- The direct broad PowerShell reliability suite still fails at tests/setup-reliability-powershell.ps1:453, the known unrelated TASK-19 PR Lens fixture. No unrelated production behavior was changed to work around it. Native Windows PowerShell 5.1/7 execution remains unavailable; README includes both Windows test commands and the Linux-validation limit.
- An independent read-only Claude review was unavailable due to its OAuth authentication error; completed a self-review instead. A whole-tree gitleaks scan flags an unchanged bazzite.sh location (lines 26-27); a redacted scan of all five changed/new implementation, test, and documentation files found no leaks. No credential values or downloaded production log bodies were displayed or saved.
- Updated README upload/recovery/troubleshooting behavior and bumped win.ps1 to Version 143. No live setup, collector writes, remote machine changes, commits, or deployments.

- Final self-review added explicit numeric schema/type checks and rejection of unknown metadata fields, plus empty/oversized/invalid-host fixtures and a guard proving recovery cannot create a marker for an unmarked log. The final focused suite, Bash reliability suite, ShellCheck, Markdownlint, and whitespace checks pass. Removed the original temporary diagnostic prototype; the permanent fixture now covers its failure paths.

Scott requested publication of all changes to remote main. Fetched origin/main and confirmed it matches the implementation base. Reran the focused PowerShell logging contracts, ShellCheck, Markdownlint, and whitespace checks successfully before committing. Publication will use a normal fast-forward push with repository hooks enabled.

The normal pre-push hook blocked publication at tests/simple-english-skill-contract.sh:203 because its version-banner assertion was still pinned to Windows Version 142. Updated only that expected banner to the required Version 143 and the new description; no skill behavior or validation was weakened. The failed push did not update remote main.

The updated skill contract, ShellCheck for both changed shell tests, and whitespace checks pass. The publication commit now also includes the version-banner contract update. Retrying the normal pre-push suite without bypassing hooks.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Made Windows setup log uploads compatible and recoverable so an installation failure does not also erase the opportunity to diagnose it.

Changes:

- Replaced Invoke-RestMethod -Form with byte-preserving .NET multipart uploads available to Windows PowerShell 5.1 and PowerShell 7. Kept the collector endpoint, TLS verification, and original setup result.
- Added bounded retries for temporary failures, safe HTTP/error-category diagnostics, and persistent per-log status. Later runs retry up to three marked pending logs within a shared time budget.
- Preserved source logs, rejected linked/malformed/unrecognized paths and metadata, used exclusive upload-state leases, and prevented uploads of active or partial-start transcripts.
- Updated README.md and win.ps1 Version 143. Added standalone offline fixtures and replaced the older Form-only reliability mocks.

Validation:

- PASS: focused Windows logging contracts on Linux PowerShell 7.6.6, including actual .NET multipart and cancellation paths through an in-memory HTTP handler.
- PASS: mutation tests for removal of retries, next-run recovery, and partial-transcript protection.
- PASS: Bash setup reliability, pending-reboot, and headless-Paseo contracts; ShellCheck; Markdownlint; whitespace checks; redacted leak scan of changed implementation/test/documentation files.
- Existing limitation: the broad PowerShell reliability suite stops at the unrelated TASK-19 PR Lens assertion at line 453. A whole-tree leak scan also flags an unchanged bazzite.sh location.

Limits:

- Native Windows PowerShell 5.1/7 execution was not available. README includes both native test commands.
- A response lost after server acceptance can produce duplicate uploads. Hard process termination or failed transcript closure requires local recovery.
- No live setup, collector upload, or remote machine rollout was performed. Scott authorized publishing these repository changes to remote main.
<!-- SECTION:FINAL_SUMMARY:END -->
