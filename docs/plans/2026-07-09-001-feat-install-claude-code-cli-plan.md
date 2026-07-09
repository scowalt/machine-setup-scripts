---
title: "feat: Install and update Claude Code CLI from setup scripts"
type: feat
status: completed
date: 2026-07-09
deepened: 2026-07-09
---

<!-- markdownlint-disable MD025 -->

# feat: Install and update Claude Code CLI from setup scripts

## Summary

Add Claude Code CLI installation/update support to every machine setup script so fresh machines and reruns provide the `claude` command needed for Fable access. Use Anthropic's native installer rather than npm/Bun, keep setup idempotent and non-fatal, add a default-on opt-out guard, and update docs/version banners so future changes preserve the install path.

---

## Problem Frame

The current setup scripts install/update several AI coding tools, but they no longer install Claude Code CLI. That leaves Fable access as a manual post-setup step and makes reruns unable to repair or update an existing Claude Code install.

---

## Requirements

- R1. All supported machine setup entry points install Claude Code CLI when the native platform/architecture is supported.
- R2. Rerunning a setup script updates or refreshes an existing Claude Code CLI install rather than only checking for presence.
- R3. The install path must not depend on global npm, Bun, or a mise-managed Node runtime.
- R4. Claude Code install/update failures must warn and continue so optional AI tooling does not abort the rest of machine setup.
- R5. Repository scripts must not author shell profile edits; if Anthropic's upstream installer performs shell integration, implementation should record that as an upstream side effect and avoid adding any additional profile edits.
- R6. The scripts must avoid interactive auth/login automation; Fable login or account selection remains a user action after the CLI exists.
- R7. README and agent guidance must describe Claude Code as a setup-managed AI tool and discourage npm-based installs for this repo.
- R8. Every modified setup script must increment its version banner and use a concise Claude Code last-changed description.
- R9. Users must be able to skip Claude Code installation with `BAN_CLAUDE_CODE=1` while the default remains install/update everywhere.
- R10. Installer/update execution must use official HTTPS URLs, temporary files/child processes where needed, absolute native binary paths for verification, sanitized logging, and warning-level failure handling.

---

## Scope Boundaries

- Do not configure Claude Code credentials, Fable account selection, workspace trust, MCP servers, permissions, or Claude settings.
- Do not add RTK integration for Claude Code unless a supported RTK integration is discovered separately.
- Do not remove legacy npm/Bun/Homebrew/WinGet Claude Code installs in this change; prefer the native binary and warn about shadowing instead.
- Do not add or edit shell profile files from these setup scripts; dotfiles remain managed by chezmoi. Upstream installer shell integration, if observed, should be documented rather than duplicated.
- Do not gate the install behind `WORK_MACHINE=1`; Claude Code should be setup-managed like Gemini, Codex, Pi, and RTK. The only planned gate is the explicit default-off `BAN_CLAUDE_CODE=1` opt-out.

### Deferred to Follow-Up Work

- Legacy package cleanup: remove old global npm/Bun/Homebrew/WinGet Claude Code packages only after observing real-world shadowing behavior and choosing a safe cleanup strategy.
- Stronger provenance verification: if high-assurance supply-chain controls are needed later, add GPG manifest-signature verification around Anthropic's release manifest rather than relying only on the native installer's built-in checksum verification.

---

## Context & Research

### Relevant Code and Patterns

- `mac.sh`, `ubuntu.sh`, `wsl.sh`, `pi.sh`, `omarchy.sh`, and `bazzite.sh` already group AI coding tools near `install_gemini_cli`, `install_codex_cli`, `install_rtk_cli`, and `install_pi_cli`.
- `win.ps1` groups the same tools in `Initialize-WindowsEnvironment` under `Additional Development Tools`.
- Codex and Pi are closer patterns than Gemini because they install/update on rerun instead of skipping when a command already exists.
- RTK and Pi show the validation posture to follow: verify that the resolved command is the expected tool, warn on optional-tool failure, and continue machine setup.
- Every setup script creates or documents `~/.env.local` / `%USERPROFILE%\.env.local` guards. Add `BAN_CLAUDE_CODE=1` to those placeholders and docs.
- `README.md` and `CLAUDE.md` list setup-managed AI agents but currently omit Claude Code CLI.

### Institutional Learnings

- `docs/plans/2026-03-23-001-feat-replace-fnm-pyenv-with-mise-beta-plan.md` explicitly warns that Claude Code should avoid npm because global Node/npm is not guaranteed after the mise migration.
- `docs/plans/2026-05-07-002-feat-migrate-pi-earendil-works-package-plan.md` provides the closest migration pattern: install/verify the preferred CLI path first, then treat cleanup as non-fatal or deferred.
- `docs/plans/2026-05-04-001-feat-install-tintinweb-pi-subagents-plan.md` reinforces that AI-agent setup failures should not fail the whole machine setup.

### External References

- Anthropic Claude Code install docs: `https://code.claude.com/docs/en/install`
- Anthropic Claude Code quickstart: `https://code.claude.com/docs/en/quickstart`
- Claude Code user FAQ: `https://support.claude.com/en/articles/14554922-claude-code-user-faq`
- Native Unix installer: `https://claude.ai/install.sh`
- Native Windows PowerShell installer: `https://claude.ai/install.ps1`

Key external findings:

- Native install is the recommended path.
- macOS, Linux, and WSL use the native shell installer; Windows PowerShell uses the native PowerShell installer.
- Native installs place the launcher under the user's local bin area (`~/.local/bin/claude` on Unix-like systems; `%USERPROFILE%\.local\bin\claude.exe` on Windows) and auto-update in the background.
- A manual `claude update` is available for immediate update attempts.
- The native install scripts download release metadata from `downloads.claude.ai`, verify SHA256 checksums from the manifest before installing the downloaded binary, and reject unsupported OS/architecture combinations.
- The native installer runs a Claude Code `install` subcommand that may perform launcher/shell-integration setup. Treat any shell integration as upstream behavior; do not add repo-authored profile edits.
- npm install is still available but requires Node.js 22+ for the package and is not the preferred fit for these setup scripts.

---

## Key Technical Decisions

- **Use the native Claude Code installer everywhere:** This matches Anthropic's current recommendation and avoids the repo's known global npm/runtime risk after the mise migration.
- **Download installer scripts to temporary files before execution:** Avoid `curl | bash` / `irm | iex` in the repo scripts so failures can be captured, temporary files removed, and Windows installer `exit` calls isolated from `win.ps1`.
- **Run Windows installation in a child PowerShell process:** Anthropic's PowerShell installer can call `exit`; a child process lets setup convert non-zero exits into `Write-Warning` instead of aborting all Windows setup.
- **Use official latest-channel native install by default:** Fresh installs should request/latest default behavior for Fable compatibility. Existing native installs should run the native update command by absolute path and respect user-managed channel settings unless the install is broken.
- **Prefer native provenance over generic `claude` presence:** A bare `command -v claude` / `Get-Command claude` is insufficient because it may find an npm, Bun, Homebrew, WinGet, stale, or shadowed install.
- **Capture original command resolution before PATH mutation:** Detect and report shadowing based on the user's original/persistent PATH, then use absolute native paths for install/update/version checks.
- **Verify the native path is not an obvious shim:** Treat symlinks or launchers pointing into `node_modules`, Bun global installs, Homebrew casks/formulae, or other package-manager locations as non-native and rerun the native installer.
- **Warn, do not clean up, on shadowing:** If another `claude` command remains ahead of the native binary in the user's normal PATH, warn that bare `claude` is not safe for Fable login until PATH/package cleanup is done, and show the native absolute path.
- **Sanitize installer/update execution:** Minimize inherited secrets for installer/update subprocesses and avoid logging raw installer output that could contain environment-sensitive details.
- **Do not automate auth:** The success condition is a working CLI binary, not a logged-in Fable session.

---

## Open Questions

### Resolved During Planning

- **Should this be work-machine-only?** No. The user confirmed all relevant setup scripts; install Claude Code alongside the other AI coding agents.
- **Should there be an opt-out?** Yes. Add `BAN_CLAUDE_CODE=1` as a default-off guard because this installs a third-party AI agent with local-code access.
- **Should the plan use npm/Bun?** No. Native install avoids global runtime assumptions and is recommended by current Claude Code docs.
- **Should the plan use Homebrew or WinGet where available?** No for v1. Those package-manager installs require separate update flows and may track delayed channels; the native install gives one cross-platform behavior and background updates.
- **Should setup use direct shell pipelines for installer execution?** No. Download to temporary files and execute with captured output/exit handling.
- **Should setup verify Fable auth?** No. Auth can require browser/account interaction and should remain manual.

### Deferred to Implementation

- **Exact native-provenance predicate:** Decide the simplest reliable per-platform check for rejecting package-manager shims while avoiding brittle assumptions about Anthropic's launcher internals.
- **Installer shell-integration observation:** Record whether the upstream installer edits shell integration on the tested platform and keep repo-authored scripts from duplicating that work.
- **Exact warning copy for shadowed commands:** Choose wording during implementation based on the command-source details available on each platform.

---

## High-Level Technical Design

> *This illustrates the intended approach and is directional guidance for review, not implementation specification. The implementing agent should treat it as context, not code to reproduce.*

### Support matrix

| Script | Native installer target | Supported platform/architecture rule | Skip behavior |
| --- | --- | --- | --- |
| `mac.sh` | `https://claude.ai/install.sh` | Darwin on x64 or arm64; installer handles Rosetta by selecting arm64 when appropriate | Warn and continue for unsupported `uname`/arch |
| `ubuntu.sh` | `https://claude.ai/install.sh` | Linux x64 or arm64/aarch64; glibc or musl handled by installer | Warn and continue for unsupported arch |
| `wsl.sh` | `https://claude.ai/install.sh` | Linux x64 or arm64/aarch64 inside WSL | Warn and continue for unsupported arch |
| `pi.sh` | `https://claude.ai/install.sh` | Linux arm64/aarch64 only for Raspberry Pi; 32-bit ARM is unsupported | Warn and continue on 32-bit Pi |
| `omarchy.sh` | `https://claude.ai/install.sh` | Linux x64 or arm64/aarch64 | Warn and continue for unsupported arch |
| `bazzite.sh` | `https://claude.ai/install.sh` | Linux x64 or arm64/aarch64 | Warn and continue for unsupported arch |
| `win.ps1` | `https://claude.ai/install.ps1` | 64-bit Windows x64 or ARM64 | Warn and continue for 32-bit/unsupported process |

### Install/update state matrix

Use the same conceptual state machine in Bash and PowerShell:

| Detected state | Action | Terminal result |
| --- | --- | --- |
| `BAN_CLAUDE_CODE=1` set | Skip with debug message | Setup continues without Claude Code |
| Unsupported platform or architecture | Warn and skip | Setup continues without Claude Code |
| Original PATH resolves non-native `claude` | Record the source before PATH mutation; continue native install/verification by absolute path | Native install can proceed; user gets shadowing warning |
| Native path missing or provenance unclear | Download official installer to a temp file and run it with captured output, minimized environment, and latest/default channel | Installed or warning on failure |
| Native path present and version works | Run non-fatal update by absolute native path; capture before/after version when practical | Updated/refreshed or existing install retained with warning |
| Native path present but broken | Re-run native installer; verify version by absolute path | Repaired or warning on failure |
| Native install works but bare `claude` is shadowed | Warn not to use bare `claude` for Fable login until PATH/package cleanup is resolved; show native absolute path | CLI available, but readiness message is qualified |
| CLI installed but not authenticated | Do nothing beyond install verification | User runs Claude Code login/account flow manually for Fable |

---

## Implementation Units

### U1. Add Bash Claude Code install/update helper

**Goal:** Add an idempotent native Claude Code install/update function to every Unix-like setup script.

**Requirements:** R1, R2, R3, R4, R5, R6, R9, R10

**Dependencies:** None

**Files:**

- Modify: `mac.sh`
- Modify: `ubuntu.sh`
- Modify: `wsl.sh`
- Modify: `pi.sh`
- Modify: `omarchy.sh`
- Modify: `bazzite.sh`
- Validate: `mac.sh`, `ubuntu.sh`, `wsl.sh`, `pi.sh`, `omarchy.sh`, `bazzite.sh` via Bash syntax and ShellCheck

**Approach:**

- Add a new `install_claude_code` helper near the existing AI CLI helpers, but leave call-site wiring to U3.
- Respect `BAN_CLAUDE_CODE=1` from the process environment or sourced `~/.env.local` and skip with debug output.
- Capture original `claude` candidates before mutating PATH so shadowing warnings reflect the user's normal shell resolution.
- Check supported OS/CPU architecture before attempting install, with special attention to Raspberry Pi 32-bit variants.
- Use absolute native path checks for install/update/version verification instead of relying on bare `claude`.
- Reject obviously non-native launchers at the native path when they point into npm/Bun/Homebrew/package-manager locations; rerun the native installer in that case.
- Download `https://claude.ai/install.sh` to a temporary file, execute it without sudo/admin escalation, capture exit status, and remove the temp file.
- Rely on Anthropic's installer checksum verification for the downloaded Claude binary; if the installer reports checksum/provenance failure, warn and continue.
- For existing native installs, run a non-fatal immediate update attempt by absolute native path, capture before/after version when practical, and re-run version verification.
- Run installer/update subprocesses with known setup secrets unset or minimized, and log summarized failure messages instead of raw command output.
- If a non-native `claude` remains ahead of the native binary in the original/future PATH, warn rather than deleting it.

**Patterns to follow:**

- `install_codex_cli` for install/update-on-rerun behavior.
- `install_rtk_cli` for current-process PATH setup and non-fatal validation warnings, adjusted to use absolute Claude paths for sensitive checks.
- `install_pi_cli` for checking that a command resolves to the expected installed tool family.

**Test scenarios:**

- Happy path: no `claude` exists, native installer succeeds, and the helper logs success after absolute-path version verification.
- Happy path: native `claude` already exists, update attempt succeeds, and the helper logs installed/updated with a before/after or retained-version note.
- Edge case: `BAN_CLAUDE_CODE=1` is set; the helper skips without invoking network calls.
- Edge case: `claude` exists from a non-native location while the native binary is missing; the helper installs native Claude Code and warns if PATH shadowing remains.
- Edge case: `~/.local/bin` is not initially in PATH; the helper still verifies the native binary by absolute path during the same setup run.
- Edge case: native path exists but points to a package-manager shim; the helper treats it as non-native and reruns the native installer.
- Edge case: Raspberry Pi reports an unsupported 32-bit architecture; the helper warns and skips without failing setup.
- Error path: installer download/checksum/install fails or returns a non-zero exit; setup logs a warning and continues to later AI tooling.
- Error path: `claude update` fails for an existing native install; setup keeps the existing binary, logs a warning, and continues.
- Security path: setup secrets from `~/.env.local` are not printed in Claude installer/update logs.

**Verification:**

- Each Bash script has exactly one Claude Code helper, and call-site wiring is handled only in U3.
- Bash syntax validation passes for all modified shell scripts.
- ShellCheck passes or any warnings are intentionally justified.
- Grep confirms no active `npm install -g @anthropic-ai/claude-code` path was introduced.
- Grep confirms the repo scripts do not use `curl | bash` for Claude Code installation.

---

### U2. Add Windows Claude Code install/update helper

**Goal:** Add equivalent native Claude Code install/update behavior to `win.ps1`.

**Requirements:** R1, R2, R3, R4, R5, R6, R9, R10

**Dependencies:** None

**Files:**

- Modify: `win.ps1`
- Validate: `win.ps1` with PowerShell parser/static validation where available

**Approach:**

- Add `Install-ClaudeCode` near `Install-GeminiCli` and `Install-CodexCli`, but leave call-site wiring to U3.
- Respect `BAN_CLAUDE_CODE=1` from the process environment or `%USERPROFILE%\.env.local` and skip with debug output.
- Capture original `claude` command candidates before changing the current process PATH.
- Prefer the native executable under `%USERPROFILE%\.local\bin` for install/update/version checks.
- Download `https://claude.ai/install.ps1` to a temporary file and run it in a child PowerShell process with `NoProfile` and captured output/exit code so upstream `exit` calls cannot abort `win.ps1`.
- Rely on Anthropic's installer checksum verification for the downloaded Claude binary and optionally verify the installed executable's Authenticode signature when practical.
- Add the native bin directory to the current PowerShell process PATH only after candidate capture, and update the Windows user PATH using the existing user-local CLI pattern if needed.
- For existing native installs, run a non-fatal immediate update attempt by absolute native executable path and verify the executable still reports a version.
- Run installer/update subprocesses with known setup secrets unset or minimized, and log summarized failure messages instead of raw command output.
- Warn if another `claude` command shadows the native executable; if shadowing remains, do not present bare `claude` as ready for Fable login.

**Patterns to follow:**

- `Install-CodexCli` for update-on-rerun behavior and try/catch logging.
- `Install-RtkCli` for verifying the resolved CLI is the expected tool.
- `Install-TursoCli` for user PATH management without profile edits.

**Test scenarios:**

- Happy path: no `claude.exe` exists, native PowerShell installer succeeds in the child process, and version verification passes.
- Happy path: native `claude.exe` exists, update attempt succeeds, and setup logs installed/updated.
- Edge case: `BAN_CLAUDE_CODE=1` is set; the function skips without invoking network calls.
- Edge case: user PATH lacks `%USERPROFILE%\.local\bin`; the current run can still verify Claude Code, and future shells can resolve it if user PATH was updated.
- Edge case: `Get-Command -All claude` or `where.exe claude` reveals a non-native command ahead of the native executable; setup warns about shadowing without deleting anything.
- Error path: installer child process fails because of network, execution policy, checksum, or upstream error; setup logs a warning and continues.
- Error path: update fails for an existing native install; setup keeps the existing binary and continues.
- Regression: upstream installer `exit` cannot terminate `Initialize-WindowsEnvironment` because it runs in a child process.

**Verification:**

- `win.ps1` parses successfully.
- The function does not add Claude Code to `$wingetPackages` or introduce npm-based installation.
- Failure handling stays warning-level and does not abort the full setup.
- Grep confirms the repo script does not use `irm ... | iex` for Claude Code installation.

---

### U3. Wire Claude Code into setup flow, guards, and documentation

**Goal:** Call the new helper from each setup script and update repository-facing docs, env placeholders, and version banners.

**Requirements:** R1, R2, R7, R8, R9

**Dependencies:** U1, U2

**Files:**

- Modify: `mac.sh`
- Modify: `ubuntu.sh`
- Modify: `wsl.sh`
- Modify: `pi.sh`
- Modify: `omarchy.sh`
- Modify: `bazzite.sh`
- Modify: `win.ps1`
- Modify: `README.md`
- Modify: `CLAUDE.md`
- Validate: `README.md`, `CLAUDE.md`, and this plan with markdownlint-compatible formatting

**Approach:**

- Call Claude Code installation in the same AI tools section as Gemini, Codex, RTK, and Pi.
- Insert the call immediately before `install_gemini_cli` / `Install-GeminiCli` in every setup script so ordering is consistent and Claude Code runs before the other Bun-installed AI CLIs.
- Add `BAN_CLAUDE_CODE=1` to `.env.local` placeholder/comment blocks in all scripts that create them.
- Increment each setup script's version banner and use a consistent last-changed message such as `Install/update Claude Code CLI`.
- Update `README.md` so the AI Coding Agents section names Claude Code CLI, documents `BAN_CLAUDE_CODE=1`, and clarifies that Fable/auth still requires normal Claude Code login.
- Update `CLAUDE.md` common-tool guidance so future agents know Claude Code is setup-managed via native installer, not npm.
- Include shadowing-safe guidance in docs: if setup warns that bare `claude` is shadowed, use the native absolute path or clean up PATH/packages before logging in for Fable.

**Patterns to follow:**

- Existing version banner format in each script.
- Existing `.env.local` placeholder style for `BAN_RTK`, `BAN_COMPOUND_PLUGIN`, and related guards.
- `README.md` AI Coding Agents paragraph style.
- `CLAUDE.md` instruction that setup scripts install tools but do not configure shells.

**Test scenarios:**

- Integration: each setup script reaches Claude Code immediately before Gemini/Codex/Pi and continues if Claude Code warns.
- Integration: docs mention Claude Code exactly where other setup-managed AI agents are listed.
- Edge case: `BAN_CLAUDE_CODE=1` appears in env placeholder text and is documented in README.
- Edge case: work-machine and personal-machine runs both call the helper unless `BAN_CLAUDE_CODE=1` is set.
- Safety: docs do not imply Fable auth is complete merely because the CLI is installed.

**Verification:**

- All seven version banners are incremented by one.
- README and CLAUDE guidance no longer imply Claude Code is manual or npm-installed.
- Markdown linting passes for modified Markdown files.

---

### U4. Validate cross-platform behavior and guard against regressions

**Goal:** Prove the change is syntactically safe and preserves setup-script conventions without requiring live installs on every platform.

**Requirements:** R1, R2, R3, R4, R5, R8, R9, R10

**Dependencies:** U1, U2, U3

**Files:**

- Validate: `mac.sh`
- Validate: `ubuntu.sh`
- Validate: `wsl.sh`
- Validate: `pi.sh`
- Validate: `omarchy.sh`
- Validate: `bazzite.sh`
- Validate: `win.ps1`
- Validate: `README.md`
- Validate: `CLAUDE.md`

**Approach:**

- Run static validation for all changed Bash scripts and PowerShell syntax validation when the tool is available.
- Run repository markdown validation for edited Markdown files.
- Review the diff for accidental repo-authored shell profile edits, npm-based Claude Code installs, direct installer pipelines, raw secret-bearing logs, and failure paths that abort setup.
- If live validation is done on the current platform, treat it as supplemental; do not block the implementation on access to every OS.

**Patterns to follow:**

- Existing repository quality guidance in `CLAUDE.md` and `.shellcheckrc`.
- Current script convention that optional agent tooling warns and continues.

**Test scenarios:**

- Static: all modified Bash scripts parse successfully.
- Static: ShellCheck does not report new actionable issues from the Claude Code helper.
- Static: `win.ps1` parses where PowerShell is available.
- Static: grep confirms the active code path contains exact official native installer URLs and does not contain active npm installation for `@anthropic-ai/claude-code`.
- Static: grep confirms the active code path does not pipe the Claude installer directly into a shell.
- Static: grep confirms `BAN_CLAUDE_CODE` appears in env placeholders and docs.
- Regression: no shell profile files are created or modified by the repository scripts.
- Regression: no `WORK_MACHINE` gate prevents personal machines from installing Claude Code by default.
- Security: failure logs are summarized and do not dump raw environment or full installer output.

**Verification:**

- Validation output is recorded in the implementation notes or final summary.
- Any unavailable platform-specific validation is explicitly noted rather than silently skipped.

---

## System-Wide Impact

- **Interaction graph:** The change adds a new AI CLI install/update step to each setup script; it does not change dotfiles, SSH, package manager setup, or Pi extension setup behavior.
- **Error propagation:** Claude Code failures should be warning-level and should not prevent later setup steps from running.
- **State lifecycle risks:** Existing machines may have multiple `claude` installs; the native binary should be preferred, but cleanup is deferred to avoid deleting user-managed packages.
- **API surface parity:** Bash and PowerShell scripts should expose the same user-visible behavior: install if absent, update if present, skip when opted out, warn if unsupported or shadowed.
- **Integration coverage:** Static checks prove syntax; one live run on the current platform can prove the native install path, but cross-platform behavior relies on the support matrix and platform-specific review.
- **Unchanged invariants:** Authentication, Fable account access, workspace trust, and Claude settings remain outside setup-script automation.

---

## Risks & Dependencies

| Risk | Mitigation |
| --- | --- |
| Native installer download or upstream failure interrupts setup | Download to temp files, isolate Windows installer in a child process, capture failure, warn, and continue |
| Installer execution inherits exported setup secrets | Minimize or unset known setup secrets for installer/update subprocesses and avoid raw output logging |
| Existing npm/Bun/Homebrew/WinGet `claude` shadows the native binary | Capture original candidates before PATH mutation, verify by absolute native path, and warn that bare `claude` is not ready for Fable login while shadowed |
| Native path is a package-manager shim rather than Anthropic's launcher | Add a pragmatic provenance check and rerun the native installer when the path points into known package-manager locations |
| Raspberry Pi 32-bit or another unsupported architecture cannot run Claude Code | Detect unsupported architecture and skip with a warning |
| Native installer behavior changes or edits shell profiles | Avoid repo-authored shell edits; document observed upstream behavior during implementation |
| `claude update` behaves differently across install sources | Use the absolute native binary path for update attempts, capture version before/after when practical, and keep failures non-fatal |
| Windows PATH changes are not visible in the current shell | Add native bin to current process PATH after candidate capture and use existing user PATH update pattern if needed |
| Fable access still requires login | Document that setup installs the CLI only; user runs Claude Code login/account flow afterward |
| Some machines should not install Claude Code | Provide `BAN_CLAUDE_CODE=1` as a documented opt-out while defaulting to install/update |

---

## Documentation / Operational Notes

- README should say the setup scripts install/update Claude Code CLI along with Gemini, Codex, Pi, and RTK.
- README should document `BAN_CLAUDE_CODE=1` and the fact that Fable/auth still requires normal Claude Code login.
- CLAUDE guidance should mention native Claude Code installation and the no-npm rationale so future setup changes do not reintroduce global npm dependency.
- User-facing success messages should avoid implying Fable auth is complete; they should only claim the CLI was installed/updated.
- User-facing shadowing warnings should explicitly say not to authenticate with bare `claude` until the shadowing is resolved, and should show the native absolute path.

---

## Sources & References

- Related code: `mac.sh`
- Related code: `ubuntu.sh`
- Related code: `wsl.sh`
- Related code: `pi.sh`
- Related code: `omarchy.sh`
- Related code: `bazzite.sh`
- Related code: `win.ps1`
- Related docs: `README.md`
- Related docs: `CLAUDE.md`
- Institutional context: `docs/plans/2026-03-23-001-feat-replace-fnm-pyenv-with-mise-beta-plan.md`
- Institutional context: `docs/plans/2026-05-07-002-feat-migrate-pi-earendil-works-package-plan.md`
- External docs: `https://code.claude.com/docs/en/install`
- External docs: `https://code.claude.com/docs/en/quickstart`
- External FAQ: `https://support.claude.com/en/articles/14554922-claude-code-user-faq`
- External installer: `https://claude.ai/install.sh`
- External installer: `https://claude.ai/install.ps1`
