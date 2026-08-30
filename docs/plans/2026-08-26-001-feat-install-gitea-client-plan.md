---
title: "feat: Install the Gitea client on work machines"
type: feat
status: completed
date: 2026-08-26
---

<!-- markdownlint-disable MD025 -->

# feat: Install the Gitea client on work machines

## Summary

Install and update the official Tea workstation client on each work machine.
Use the existing `WORK_MACHINE=1` classification and support all six setup scripts.

## Requirements

- R1. `mac.sh`, `ubuntu.sh`, `wsl.sh`, `pi.sh`, `bazzite.sh`, and `win.ps1` must manage the `tea` command.
- R2. `WORK_MACHINE=1` must be the only Tea-management condition.
- R3. A non-work-machine run must not install, update, or remove Tea.
- R4. Homebrew must install and update Tea on each supported platform and architecture.
- R5. An official Gitea binary must cover Windows and architectures that Homebrew does not support.
- R6. Each setup run must install the latest stable Tea release.
- R7. A standalone download must pass its published SHA-256 verification before installation.
- R8. An installation, update, or command verification error must stop setup.
- R9. A different `tea` executable earlier on `PATH` must stop setup with remediation information.
- R10. The scripts must not remove the conflicting executable.
- R11. The repository must not provide an opt-out flag for Tea on work machines.
- R12. Authentication must remain a manual, per-machine action.
- R13. Homebrew can provide Bash, Zsh, and Fish completion. The setup scripts must not manage other completion files.

## Scope Boundaries

- Install the Tea workstation client, not the `gitea` server command.
- Do not run `tea login add` from a setup script.
- Do not read, write, print, or synchronize a Gitea token.
- Do not configure Tea as a Git credential helper.
- Do not edit a shell profile for Tea completion.
- Do not switch to a standalone binary after a Homebrew error.
- If a machine is no longer a work machine, do not remove Tea.

## Installation Matrix

| Setup script | Installation source |
| --- | --- |
| `mac.sh` | Homebrew formula `tea` |
| `ubuntu.sh` | Homebrew formula `tea` |
| `wsl.sh` | Homebrew formula `tea` |
| `bazzite.sh` | Homebrew formula `tea` |
| `pi.sh` | Homebrew on supported targets, otherwise the official binary |
| `win.ps1` | Official Windows binary |

Homebrew remains the installation owner on every supported Homebrew target.
If a Homebrew operation fails, the setup run fails without a source change.

## Implementation Units

### U1. Add Tea to the Bash setup scripts

**Files:**

- Modify `mac.sh`.
- Modify `ubuntu.sh`.
- Modify `wsl.sh`.
- Modify `pi.sh`.
- Modify `bazzite.sh`.

**Work:**

- Add an `install_gitea_client` function to each script.
- If `WORK_MACHINE=1` is not active, return without changes.
- Use `brew install tea` for a new Homebrew installation.
- Use Homebrew to update an existing managed installation.
- If Homebrew does not support the target, use the official binary.
- Get the latest stable release from the official Gitea release API for a direct installation.
- Download the executable and its SHA-256 file to a temporary directory.
- Verify the SHA-256 value before the script installs the executable.
- Verify that the managed executable returns a Tea version.
- If bare `tea` resolves to a different executable on the original `PATH`, fail.
- Show the conflicting path without deleting it.
- Remove temporary files after success or error.

### U2. Add Tea to the Windows setup script

**File:** Modify `win.ps1`.

**Work:**

- Add an `Install-GiteaClient` function.
- If `WORK_MACHINE=1` is not active, return without changes.
- Get the latest stable release from the official Gitea release API.
- Select the official Windows binary for the current architecture.
- Download the executable and its SHA-256 file to a temporary directory.
- Verify the binary with `Get-FileHash -Algorithm SHA256`.
- Install the executable with the existing user-local binary pattern.
- Add its directory to the user `PATH` with the existing repository pattern.
- Verify that the managed executable returns a Tea version.
- If bare `tea` resolves to a different executable on the original `PATH`, fail.
- Show the conflicting path without deleting it.
- Remove temporary files after success or error.

### U3. Connect the functions, documentation, and tests

**Files:**

- Modify all six setup scripts.
- Modify `README.md`.
- Add `tests/gitea-client-installation-contract.sh`.

**Work:**

- Call the new function from the development-tools section of each script.
- Propagate each Tea error so that the setup run fails.
- Increment each setup script version.
- Use one consistent last-changed message in all six scripts.
- Document that `WORK_MACHINE=1` makes Tea a managed tool.
- Document `tea login add` as the manual authentication step.
- Warn that Tea stores an application token in its local configuration.
- Add contract tests for platform coverage, the work-machine guard, hard errors, source selection, and manual authentication.
- Add contract tests that prohibit an opt-out flag and authentication automation.

## Acceptance Criteria

- [x] Each work-machine setup script installs or updates Tea.
- [x] Each non-work-machine setup script leaves Tea unchanged.
- [x] Homebrew supplies Tea on each target that the formula supports.
- [x] Windows and unsupported Homebrew targets use an official binary.
- [x] A standalone installation verifies the published SHA-256 value.
- [x] A Homebrew error does not trigger a standalone installation.
- [x] A Tea installation or version error stops setup.
- [x] A conflicting `tea` command stops setup and identifies its path.
- [x] Setup does not remove a conflicting installation.
- [x] Setup does not authenticate Tea or manage tokens.
- [x] The README documents the manual authentication step.
- [x] Homebrew-provided completion requires no repository changes.
- [x] Bash syntax validation passes for the five shell scripts.
- [x] If PowerShell is available, PowerShell parsing passes for `win.ps1`.
- [x] The new contract test passes.
- [x] Markdown validation passes for the changed documentation.

## Decision Record

The planning session resolved all design questions. This change does not need an ADR because the installation choices are easy to reverse.

## References

- Tea product page: <https://about.gitea.com/products/tea/>
- Tea source and documentation: <https://gitea.com/gitea/tea>
- Homebrew Tea formula: <https://formulae.brew.sh/formula/tea>
- Official Tea downloads: <https://dl.gitea.com/tea/>
- Gitea latest-release API: <https://docs.gitea.com/api/operations/repo-get-latest-release/>
