---
id: TASK-39
title: Keep Backlog MCP repo-local and retire global setup references
status: Done
assignee:
  - '@pi'
created_date: '2026-09-18 20:26'
updated_date: '2026-09-18 21:39'
labels: []
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Make Backlog an explicit per-repository integration, not a machine-wide setup default. Remove dotfiles Backlog MCP references and stop deploying its repository task directory into HOME. Also retire existing global Backlog MCP registrations without deleting repo task data or unrelated MCP servers.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The six setup scripts and dotfiles do not install or enable Backlog MCP globally; dotfiles does not deploy its repository backlog directory.
- [x] #2 Existing global Backlog MCP registrations are safely removed on subsequent setup/dotfiles application, preserving unrelated servers, settings, credentials, and repository-local data.
- [x] #3 The dotfiles repository Backlog MCP registration is removed; other repositories remain explicit per-repository opt-ins.
- [x] #4 Isolated regression fixtures cover cleanup, repeated runs, preservation, and unsafe metadata; relevant lint and tests pass.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Verify the supported global MCP configuration locations and distinguish global registrations from project-scoped records, including explicitly selected agent profiles. Do not invoke MCP servers or inspect/output credentials.
2. Remove the dotfiles repository Backlog MCP declaration and exclude its repository backlog directory from Chezmoi deployment. Preserve existing task data, the setup repository opt-in, the Backlog CLI, and all unrelated MCP integrations.
3. Add safe, idempotent retirement of existing global Backlog MCP registrations to the six setup scripts after dotfiles application. Preserve unrelated settings and project-scoped records; reject unsafe or malformed metadata with controlled diagnostics. Do not apply live dotfiles or run live setup during development.
4. Add temporary-home fixtures for supported formats, absent entries, repeated runs, preservation, explicit profile selection, and unsafe metadata. Verify dotfiles cannot recreate a global Backlog integration, bump each changed setup version, update documentation, and run relevant tests and lint before review.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- Audited both repositories: the six setup scripts contain no Backlog installation, and the managed global dotfiles templates contain no Backlog server declaration. Both repositories have a repo-local .mcp.json with a hard-coded Backlog executable and cwd.
- Read-only chezmoi managed inspection confirms dotfiles currently deploys backlog/config.yml and repository backlog directories into HOME.
- Read-only standard global-config inventory found no Backlog-named server entries on this machine. No live settings, credentials, or task data were changed.
- User confirmed cleanup of existing global registrations is in scope. Implementation plan recorded; awaiting approval before source edits.

- User approved implementation by requesting a paseo-handoff to implement this task. No further plan approval is needed for the recorded scope.
- Handing off to the configured Implementor profile in the existing meek-turtle workspace; implementation has not started. Dotfiles edits are explicitly in scope at /home/scowalt/Code/dotfiles. Preserve existing repo-local task history and avoid live setup/apply.

- Implementation resumed in the approved workspace. Verified Node v24.20.0 is available; PowerShell is unavailable, so native Windows fixture execution will be reported as skipped.

- Implemented an identical fail-closed retirement helper in all five Bash setup scripts and the PowerShell entry point. It runs after dotfiles management, removes named or command-verified Backlog registrations from supported global JSON/Pi/Claude/Gemini/shared MCP files and Codex TOML profiles, supports selected profile overrides, and preserves project files and task data.
- Removed dotfiles/.mcp.json, added backlog to .chezmoiignore, and documented repository-local policy and migration boundaries in both repositories. The machine-setup repository .mcp.json remains unchanged.
- Added temporary-HOME fixtures covering JSON and TOML cleanup, aliases, repeated runs, unrelated settings/credentials, selected profiles, project/task preservation, symlinks, and duplicate-key metadata. Verified all embedded JavaScript copies match.
- Verification passed: backlog MCP contract with and without BACKLOG_DOTFILES_SOURCE, shellcheck on all changed Bash scripts and the contract, bash syntax checks, Python compilation, diff checks, and four available dotfiles unittest suites (19 passed, 1 skipped). pytest was unavailable as a module, so the dotfiles unittest files were run directly. PowerShell was unavailable; native Windows execution/ACL behavior remains unverified.

- Pre-push review reproduced release-blocking TOML data loss and identified metadata-safety/config-path coverage gaps. Reopened for regression-first repair; dotfiles repository is explicitly out of scope for this repair.

- Release-blocking repair: added regression-first coverage for array-of-tables preservation, multiline strings, malformed/duplicate TOML, quoted keys, nested alias env tables, inline/dotted unsupported layouts, semantic preservation, selected config paths, hardlinks, oversized files, linked HOME, unsafe ancestors, all-or-nothing preflight, mode/inode preservation, and Bash/PowerShell wrapper failure propagation with NODE_OPTIONS/NODE_PATH isolation.
- Replaced unvalidated TOML regex mutation with Python tomllib validation before and after a syntax-preserving span edit. The candidate semantic tree must equal the original with only selected mcp_servers entries removed; inline/dotted layouts and missing parser fail closed before all writes.
- POSIX reads/writes now use bounded O_NOFOLLOW/O_NONBLOCK descriptors held through preflight, validate ownership and group/world writeability, pin/recheck ancestor and file identities, reject arbitrary linked HOME, and update the verified inode in place to preserve mode and ACL metadata.
- Corrected supported global path inventory from installed Pi adapter/Gemini sources: shared/Pi globals, Claude/Claude Desktop, Cursor, Windsurf, Codex JSON/TOML, and direct GEMINI_CLI_HOME/settings.json; project-relative imports remain untouched. Dotfiles repository remained clean at pushed ae11e69.
- Verification passed: focused contract with actual PowerShell 7.6.6 wrapper, ShellCheck, syntax/compile/diff checks, setup reliability contract, shared Node tests (18 passed, 1 skipped), and PowerShell shared Node fixtures (1409 assertions).
- BLOCKER: native Windows secure mutation is not defensible yet. The helper deliberately returns windows-safety-unavailable before reading/writing any existing candidate because native ACL and stable-handle validation are not implemented/tested. TASK-39 remains In Progress and AC #2/#4 remain unchecked; do not ship as complete until Windows support is implemented or scope is explicitly changed.

- Publishing requested by user. Dotfiles independently re-tested (model, skills, AskClaude, 16 PowerShell fixtures plus 2 native-Windows skips, isolated managed-target check), committed and pushed to remote main at ae11e69f15e7eb5a1d58db1552814a50a4316fcb. No live dotfiles apply.
- Pre-push review reproduced TOML deletion of unrelated array tables and multiline strings, and mutation of malformed TOML in the original implementation. Setup publication paused for preservation fixes; native Windows mutation is currently blocked pending a safe design.
- Existing setup contract sweep passed all suites except stale explicit version-banner expectations in simple-english-skill-contract.sh; those expectations and its contract version were updated, and the suite now passes. Additional shared-runtime, Go wiring, Pi profiles/packages/prose contracts passed with available PowerShell on Linux. Native Windows remains unverified.

- Bounded POSIX follow-up completed. TOML parser now uses root-owned `/usr/bin/python3 -I -S` with fixed cwd/environment; cwd/PYTHONPATH sitecustomize and tomllib shadow sentinels prove no startup code executes. Missing/untrusted parser remains controlled failure.
- Logical HOME is inspected before realpath and the only permitted linked boundary is the exact root-owned `/home` -> `/var/home` Bazzite alias; simulated identity fixtures cover accepted/rejected aliases.
- Snapshot identity now includes link count, size, mtime, and ctime. Every descriptor is bounded-reread and byte-compared before writes and before each mutation; ancestors/files are revalidated each time. Deterministic same-inode swap fixture proves no selected file is overwritten. Writes loop through short writes and write-phase diagnostics no longer promise unchanged files after I/O failure.
- Identification permits ordinary owned nonlinked 0775 directories/0664 files to produce an absent no-op. Positive removals still require non-group/world-writable candidate files and mutation boundaries; unsafe selected registrations refuse without changes.
- JSON retirement now rejects unsupported unsafe/nonfinite numbers before mutation, preserving 9007199254740993 and 1e400 byte-for-byte instead of normalizing them. Added regressions. Preserved the user-authored tests/simple-english-skill-contract.sh version/banner update unchanged.
- POSIX verification passed: focused Backlog contract with actual Linux PowerShell wrapper, ShellCheck, Bash/Python syntax and diff checks, setup reliability, and Simple English/banner contract. Dotfiles repository remains clean.
- SPECIFIC WINDOWS CODE BLOCKER: the current embedded program is not yet separated into a pure planRetirement(records) protocol, and the existing PiDirectoryAcl native child exposes directory-only handles (its Read rejects non-directories and it has no PinFile/ReadBytes/WriteAll transaction). Implementing the advisor design requires a new native file-handle C# transaction plus planner IPC and Windows-only fixtures; reusing the current path-based Node backend would violate the required ACL/share-mode guarantees. No Windows mutation design was changed in this bounded pass; windows-safety-unavailable remains fail-closed. TASK-39 stays In Progress.

User explicitly requested completing the Windows implementation. Implementing a pinned native Windows file transaction and isolated planner, rather than weakening ACL/path validation or shipping a blanket failure. Existing publication authorization remains in effect; dotfiles is already on remote main.

- Implemented native Windows retirement instead of the blanket failure: same-handle file reads/writes, root-first ancestor pins, native identity/DACL snapshots, controlled phase errors, reparse/hardlink/Win32-alias rejection, and all-candidate mutation preflight. Ordinary Backlog-free metadata produces an absent no-op. Windows PowerShell 5.1-compatible code and native-only fixtures are included.
- The Windows pure planner receives snapshots only through captured pipes and uses Bun from fixed WinGet/native installation boundaries, never a PATH/project executable. Its environment is cleared, cwd and empty config are fixed, dotenv/startup hooks and installs are disabled, output is bounded, and the child is timed out. Real production C# IPC and Bun parsing were exercised on Linux; native C# compiles.
- Replaced JSON reserialization with source-span deletion, preserving exact unrelated numeric values and encodings. Added scoped Codex/editor JSON map variants. Added verified system/Homebrew/pyenv/mise Python fallback so an older OS Python does not unnecessarily break TOML retirement; isolated imports and unchanged runtime selections remain required.
- Focused contract passed: POSIX preservation/refusal fixtures, six Windows planner tests including real production pipe code/environment poisoning, PowerShell wrapper, C# compilation and script AST, dotfiles integration, setup reliability, updated version banners, ShellCheck, Bash syntax, and diff checks. Full existing contract sweep had passed apart from banner expectations, which are now fixed and passing. Native Win32 ACL/handle fixtures are provided but explicitly skipped on this Linux host; no native Windows execution is claimed. No live setup/apply/metadata cleanup ran.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Kept Backlog MCP explicitly repository-local and implemented safe retirement of supported global registrations across all six setup scripts.

Changes:

- Removed dotfiles repo MCP opt-in and excluded its backlog data from Chezmoi deployment; already published as dotfiles ae11e69.
- Added shared JSON/TOML retirement policy preserving project records, unrelated servers, exact JSON values, credentials, CLI installations, and task data.
- Added native Windows pinned-handle/ACL transaction and isolated built-in Bun planner, plus verified compatible Python fallback on POSIX. Unsafe/unsupported metadata produces controlled failure rather than unsafe cleanup.
- Updated setup versions, documentation, regression and version-banner fixtures.

Verification:

- Backlog retirement contract with PowerShell and dotfiles integration; six Bun planner/production IPC tests.
- ShellCheck, Bash syntax, native C# compilation, PowerShell AST, setup reliability and managed-skill/banner contracts.
- Existing contract sweep passed with the stale version-banner expectations repaired.

Limitations:

- Native Windows ACL, reparse, and sharing behavior needs execution of tests/backlog-mcp-windows.ps1 on Windows; Linux fixtures do not prove those native APIs.
- Multi-file write failures are reported without claiming rollback; unsupported TOML registration layouts require manual review.
- No live machine cleanup or remote fleet changes were performed.
<!-- SECTION:FINAL_SUMMARY:END -->
