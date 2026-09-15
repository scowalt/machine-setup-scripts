---
id: TASK-30
title: Secure managed Pi profile directories before setup mutations
status: Done
assignee:
  - '@pi'
created_date: '2026-09-14 23:56'
updated_date: '2026-09-15 01:52'
labels:
  - bug
  - setup
  - security
dependencies: []
references:
  - ubuntu.sh
  - win.ps1
  - tests/test_pi_opencode_go_setup.py
  - 'https://logs.scowalt.com/logs/arcane/2026-09-14-23-12-59-427.log'
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Arcane Ubuntu v252 rejected its account-owned ~/.pi/agent directory at mode 0775 with active-profile: untrusted-directory. Setup creates profile directories with ordinary mkdir but later requires non-writable credential boundaries. The user approved repairing verified profile directory permissions on future setup runs, without weakening credential checks or changing live machines during development.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 All six scripts secure the default ~/.pi and ~/.pi/agent directories and any explicitly selected active profile inside account HOME before managed Pi profile mutations after dotfiles. Unix profile directories become 0700 and Windows uses equivalent private native ACLs. Missing required directories are created safely and reruns are idempotent.
- [x] #2 Preflight all affected boundaries before changes. Reject linked, foreign-owned, malformed, or outside-HOME targets without following links, changing HOME or arbitrary ancestors, recursively changing profile contents, rewriting credentials, or weakening existing JSON and credential validation. Preserve the trusted Linux system HOME alias.
- [x] #3 Permission failure blocks unsafe later Pi profile/package and dependent Muse/daemon operations while unrelated setup work continues and final setup status reports failure with controlled secret-free diagnostics.
- [x] #4 Offline fixtures reproduce the Arcane 0775 failure and prove successful repair, creation, reruns, default/custom profile scope, safety rejection, content preservation, and downstream failure handling. Extract functions only and cover available PowerShell wrappers without live setup or real credential access.
- [x] #5 Update affected setup versions, documentation, and shared helper copies. Relevant permissions, Go, prose, package maintenance, shared runtime, model, AI-agent, and wiring contracts and lint pass, with platform limitations stated.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Add failing extracted-function fixtures for the observed 0775 profile and for creation, reruns, two-profile preflight, links, foreign ownership, unsafe ancestors, outside-HOME overrides, and available Windows ACL boundaries. Use temporary homes and fixture credentials only.
2. Add a shared directory-only preparation helper to all six scripts. Preflight both profiles, preserve the trusted HOME alias, create or secure only approved directories, and keep existing metadata/content validation intact. Wire it after dotfiles and before Pi profile mutations, with downstream failure aggregation.
3. Update affected banners, documentation, and fixture expectations. Run Pi directory, Go, prose, package, shared-runtime, model, AI-agent, and wiring contracts with the available portable PowerShell runtime, then lint and self-review.
4. Record evidence and remaining native-platform limits. No live setup, remote permission repair, credentials access, daemon changes, or publication. Implementation awaits approval of this plan.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
User approved the permission/ownership/restart spec and explicit Paseo CLI selection. Read-only investigation confirmed profile creation and later security validation use different permission standards. Bash, Node, Python, ShellCheck, Backlog, and /tmp/pi-shared-runtime-pwsh.2SlAPL/pwsh are available. Only glossary and task metadata changed so far.

User approved implementation. Delegated TASK-30 to a coding subagent in the shared workspace. Main agent owns TASK-31 and final version/documentation/integration review.

TASK-30 implementation approved and delegated. First red: python3 tests/test_pi_profile_permissions.py fails because the extracted PI_PROFILE_PERMISSIONS helper is absent. Fixture reproduces account-owned 0775 default boundaries and requires directory-only repair with HOME, auth bytes/metadata, and installed dependency permissions unchanged. Version/document integration remains with main agent.

Green: nine directory-preparation tests pass, including all six shared copies, temporary 0775 repair, custom leaf creation, all-profile preflight rejection, foreign ownership/unsafe ancestors, metadata preservation, trusted Linux home alias, and Bash/portable PowerShell wrapper failure redaction. Wiring fixtures now cover permission failure blocking prose/Pi/Go/Muse/daemon while unrelated Matt Pocock work continues. Package-maintenance suite passes (22 tests, two optional registry/dotfiles probes skipped), including all six final setup failure/log-finalization tails. Existing prose and Go embedded helpers are unchanged. Earlier RTK/Attention-kind and later legacy skill cleanups now skip only their Pi footprint after failure.

Implementation ready for main integration; TASK-30 remains In Progress. AC1 native Windows execution and AC5 versions/docs/final integration are left for main review. No banners, docs, TASK-31 functions, credentials, live setup, Pi execution, or remote machines were changed by this worker.

Final permission suite: PWSH_BIN=/tmp/pi-shared-runtime-pwsh.2SlAPL/pwsh bash tests/pi-profile-permissions-contract.sh — 15 tests pass, one native-Windows-only ACL fixture skipped on Linux. Portable PowerShell parses the embedded native ACL script and compiles its C# interop without invoking Windows APIs. Windows uses SetKernelObjectSecurity on a checked directory handle, not Set-Acl, because Set-Acl can propagate permission changes into credential/dependency descendants. Only missing approved leaf directories are created; custom ancestors must already exist and be safe.

Passed with the same PWSH_BIN: bash tests/pi-opencode-go-contract.sh (22 tests, two optional native-lock/catalog cases skipped); bash tests/pi-prose-contract.sh (22 + companion tests); bash tests/pi-package-maintenance-contract.sh (22, two optional registry/dotfiles probes skipped); bash tests/shared-node-runtime-contract.sh (16 + isolated real mise + 959 PowerShell assertions); bash tests/opencode-go-wiring-contract.sh (3 multi-platform scenarios); bash tests/paseo-muse-profile-contract.sh (55, one optional native-PID module skipped, plus PowerShell/ACL policy fixtures); bash tests/ai-coding-agent-contract.sh; bash tests/pi-model-defaults-contract.sh; bash tests/pi-skill-ownership-contract.sh; bash tests/attention-span-removal-contract.sh; bash tests/rtk-removal-contract.sh; bash tests/headless-paseo-daemon-contract.sh; bash tests/paseo-release-channel-contract.sh. Ran portable PowerShell directly for pi-model-defaults-powershell.ps1, attention-span-removal-powershell.ps1, and paseo-release-channel-powershell.ps1 because some shell wrappers ignore PWSH_BIN.

ShellCheck passed on all five setup Bash scripts and tests/pi-profile-permissions-contract.sh; git diff --check passed. Verified existing embedded prose/Go engines against HEAD: unchanged in all six. Native Windows/macOS/ARM OS behavior remains unexecuted on this Linux host.

Current anchors (may shift during main integration): helper/call mac.sh:6324/8423, ubuntu.sh:6400/8777, wsl.sh:4257/6525, pi.sh:6761/8625, bazzite.sh:6334/8102, win.ps1:4444/6484. Dedicated tests: tests/test_pi_profile_permissions.py and tests/pi-profile-permissions-contract.sh. Minimal fixture alignment: tests/test_opencode_go_wiring.py, tests/test_pi_package_maintenance.py, tests/test_shared_node_runtime.py.

Integration review reopened AC2/AC4: path-based creation can follow a swapped ancestor, and Windows ACL identity needs volume/file ID rather than timestamp. Added red regressions: ancestor swap creates outside/agent with the current helper; portable Windows structure fixture rejects Directory.CreateDirectory and missing pinned native/stable-ID operations. Repair remains limited to TASK-30 helpers/tests; main owns versions/docs/TASK-31.

Integration blockers repaired, pending main review; AC2/AC4 remain unchecked for that review. Red evidence: the old path-based mkdir created outside/agent after a .pi ancestor swap, and the Windows structure fixture rejected recursive Directory.CreateDirectory/missing rooted handles. Green: PWSH_BIN=/tmp/pi-shared-runtime-pwsh.2SlAPL/pwsh bash tests/pi-profile-permissions-contract.sh now runs 21 tests successfully with two native-Windows-only tests skipped.

POSIX creation now passes a verified parent directory descriptor to isolated /usr/bin/python3 (-I -S, empty environment). The stdlib uses os.mkdir(..., dir_fd=3) and os.open(..., dir_fd=3, O_NOFOLLOW); created identity is checked against the path before continuing. There is no path-based or recursive fallback. Capability is probed before any chmod when a required directory is missing. Missing /usr/bin/python3 or dir_fd/no-follow support produces controlled directory-create-unavailable and blocks Pi mutations; existing-directory repair does not require Python. Parent-swap, disappearance, unavailable-capability, and ordinary profile-name fixtures pass. Main owns documenting this capability requirement.

Windows now pins verified ancestors root-first with write/delete sharing excluded, reads ACL/owner data through handles, captures volume + file-ID high/low, and compares stable identity before DACL changes. Missing leaves use NtCreateFile rooted at the pinned parent with FILE_CREATE (no recursive ancestor creation), obtaining the new directory handle atomically. Existing directory DACL changes still use non-propagating SetKernelObjectSecurity, with no child ACL walk. Pins release in finally. The native script is piped through a small encoded bootstrap to avoid the Windows command-line length limit. Portable PowerShell parses and compiles the new native program; added same-creation-time substitution, pinned-parent rename/deletion, disposed-parent creation, and junction-rejection fixtures are Windows-only and have NOT run on this Linux host.

Actual extracted cleanup behavior now covers RTK, Attention-kind, Matt Pocock removal, Bash obsolete-Matt removal, and Compound cleanup across all six wrappers. A real unsafe-custom-ancestor preflight rejects the default/custom transaction. With blocking enabled, both profiles retain all sentinel files while unrelated managed artifacts are removed. An unblocked temporary-fixture control must change both profiles, proving the tests exercise the real guards rather than no-op mocks. Only logging and the Windows registry PATH persistence boundary are inert; no real registry/user-environment writes.

Re-ran successfully with the same PWSH_BIN: pi-opencode-go, pi-prose, pi-package-maintenance, shared-node-runtime, opencode-go-wiring, ai-coding-agent, attention-span-removal, rtk-removal, and pi-skill-ownership contract scripts. Shared runtime includes isolated real mise and 959 PowerShell assertions. ShellCheck passed on all five Bash scripts plus the new wrapper; git diff --check passed. Existing Go/prose engines still match HEAD byte-for-byte in all six scripts. No banners/docs/TASK-31 edits, commits, live setup, real credentials, Pi sessions, or daemon operations in this revision.

Review anchors: ubuntu.sh:6540 (mkdirat program), :6569 (inherited descriptor child), :6644 (native Windows program), :6710 (stable identity), :6756 (rooted leaf creation). tests/test_pi_profile_permissions.py:223 (POSIX races), :279 (capability failure), :290 (portable native structure), :368 (real mixed-cleanup guards), :527 (native Windows race fixtures). Line numbers may shift during main integration.

Integrated the reviewed race fixes and documentation. Unix creation uses an inherited verified parent descriptor through isolated OS Python rather than path-based mkdir. Windows uses rooted native creation and stable volume/file IDs. New behavioral cleanup fixtures preserve rejected default/custom profiles while unrelated cleanup continues. The permission suite reports 19 passed and 2 native-Windows skips; affected full-suite checks and lint are passing. Native Windows remains an explicit verification limit.

Final integration passed all 31 Bash contract suites with available portable PowerShell and native Go/Paseo fixture modules. Explicit PowerShell release-channel, model-default, and Telegram suites also passed. ShellCheck, Markdown lint, whitespace checks, and secret scan passed. Review findings were fixed with regression fixtures. Native Windows ACL operations remain unrun, and Unix creation fails safely without supported OS Python. No live machine cleanup or setup ran.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Secure managed Pi profile directories before setup writes.

- Add identical directory-only preparation helpers across all six scripts. Preflight default and active profiles, apply 0700/private native Windows ACLs only to verified account-owned profile directories, and preserve HOME, file contents, credentials, and unrelated ancestors.
- Use descriptor-relative Unix creation and pinned Windows native handles with stable file identity. Reject unsafe paths without following links or recursively changing permissions.
- Block later Pi mutations and dependent Muse/daemon work on permission failure while unrelated cleanup continues. Update versions, documentation, and offline fixtures.

Validation: 19 permission tests pass with 2 native-Windows skips. All 31 Bash contract suites pass, including affected Go/prose/package/runtime/model/wiring contracts with available PowerShell and native fixture modules. Explicit PowerShell channel/model/Telegram suites, ShellCheck, Markdown lint, whitespace checks, and secret scan pass.

Limits: Native Windows ACL behavior needs Windows verification. Unix creation requires supported /usr/bin/python3 and fails closed otherwise. Changes are local and uncommitted; no live setup or remote permission changes.
<!-- SECTION:FINAL_SUMMARY:END -->
