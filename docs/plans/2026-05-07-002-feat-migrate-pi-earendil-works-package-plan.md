---
title: "feat: Migrate Pi installs to @earendil-works package namespace"
type: feat
status: completed
date: 2026-05-07
---

<!-- markdownlint-disable MD025 -->

# feat: Migrate Pi installs to @earendil-works package namespace

## Overview

Pi's upstream packages have moved from the `@mariozechner` npm namespace to the `@earendil-works` namespace. Update every machine setup path that installs Pi so fresh installs and reruns use:

```bash
bun install -g @earendil-works/pi-coding-agent
```

instead of:

```bash
bun install -g @mariozechner/pi-coding-agent
```

Also migrate existing machines by removing the old global package after the new package is installed and verified.

## Confirmation

The install path has changed for Bun global installs because the npm package scope changed.

Current local machine:

```bash
which pi
# /home/scowalt/.bun/bin/pi

readlink -f $(which pi)
# /home/scowalt/.bun/install/global/node_modules/@mariozechner/pi-coding-agent/dist/cli.js

pi --version
# 0.73.0
```

NPM registry findings:

- New package: `@earendil-works/pi-coding-agent@0.74.0`
- New repository: `https://github.com/earendil-works/pi-mono.git`
- New binary declaration: `{ "pi": "dist/cli.js" }`
- Old package: `@mariozechner/pi-coding-agent@0.73.1`
- Old package deprecation: `please use @earendil-works/pi-coding-agent instead going forward`

Related core packages also moved and old packages are deprecated:

- `@mariozechner/pi-ai` → `@earendil-works/pi-ai`
- `@mariozechner/pi-agent-core` → `@earendil-works/pi-agent-core`
- `@mariozechner/pi-tui` → `@earendil-works/pi-tui`
- `@mariozechner/pi-coding-agent` → `@earendil-works/pi-coding-agent`

Expected post-migration `pi` symlink target:

```text
~/.bun/install/global/node_modules/@earendil-works/pi-coding-agent/dist/cli.js
```

## Scope

### In scope

- Update Pi install commands in all setup scripts:
  - `mac.sh`
  - `ubuntu.sh`
  - `wsl.sh`
  - `pi.sh`
  - `omarchy.sh`
  - `bazzite.sh`
  - `win.ps1`
- Add an idempotent cleanup step for the old `@mariozechner/pi-coding-agent` global package.
- Update setup-script debug/help text.
- Update setup-script version banners.
- Update repository docs that describe the Pi install package.
- Validate the current machine migration manually after implementation.

### Out of scope

- Renaming third-party Pi extension packages such as `npm:pi-goal`, `npm:pi-autoresearch`, `npm:pi-web-access`, or `npm:@tintinweb/pi-subagents`; those package sources have not moved as part of this change.
- Editing historical completed plan files solely to replace old package names, unless they are copied as active guidance.
- Modifying Pi upstream packages or third-party package peer dependencies.

## Proposed Solution

### 1. Update Pi install function in every script

In each Bash script's `install_pi_cli()`:

1. Keep the existing Bun availability check.
2. Change debug text from:

   ```bash
   bun install -g @mariozechner/pi-coding-agent
   ```

   to:

   ```bash
   bun install -g @earendil-works/pi-coding-agent
   ```

3. Change the install command to:

   ```bash
   bun install -g @earendil-works/pi-coding-agent
   ```

4. After successful install, remove the old package if present:

   ```bash
   if bun pm ls -g 2>/dev/null | grep -q "@mariozechner/pi-coding-agent"; then
       bun remove -g @mariozechner/pi-coding-agent || print_warning "Failed to remove old @mariozechner Pi package."
   fi
   ```

5. Verify `pi` still resolves and no longer points at the old namespace:

   ```bash
   local _pi_target=""
   _pi_target=$(readlink -f "$(command -v pi)" 2>/dev/null || true)
   if [[ "${_pi_target}" == *"@mariozechner/pi-coding-agent"* ]]; then
       print_warning "Pi still points to old @mariozechner install path: ${_pi_target}"
   fi
   ```

6. If removing the old package removes or changes the `pi` shim unexpectedly, reinstall `@earendil-works/pi-coding-agent` once more and warn if validation still fails.

PowerShell `Install-PiCli` should mirror the same behavior with:

```powershell
bun install -g @earendil-works/pi-coding-agent
bun remove -g @mariozechner/pi-coding-agent
(Get-Command pi).Source
```

Use warnings instead of aborting if old-package cleanup fails after the new package is installed.

### 2. Current-machine migration command

After updating scripts, migrate the current machine manually:

```bash
bun install -g @earendil-works/pi-coding-agent
bun remove -g @mariozechner/pi-coding-agent || true
bun install -g @earendil-works/pi-coding-agent
pi --version
readlink -f "$(command -v pi)"
```

Expected:

- `pi --version` reports `0.74.0` or newer.
- `readlink -f "$(command -v pi)"` contains `@earendil-works/pi-coding-agent`.
- `bun pm ls -g` no longer lists `@mariozechner/pi-coding-agent`.

### 3. Documentation updates

Update active docs and project guidance that state the Pi install package:

- `CLAUDE.md` common tools / troubleshooting references if needed.
- `README.md` only if it mentions the package name directly.
- Any active setup docs that copy the install command.

Do not churn old completed plan docs unless a current reader would reasonably copy commands from them.

### 4. Version bumps

Increment each modified setup script version and update last-changed text, for example:

- `mac.sh`: `160` → `161`
- `ubuntu.sh`: `174` → `175`
- `wsl.sh`: `130` → `131`
- `pi.sh`: `139` → `140`
- `omarchy.sh`: `144` → `145`
- `bazzite.sh`: `38` → `39`
- `win.ps1`: `91` → `92`

Use last-changed text like `Migrate Pi to @earendil-works package`.

## System-Wide Impact

### Interaction Graph

1. User runs a setup script.
2. Script installs/updates Bun.
3. Script installs Pi from `@earendil-works/pi-coding-agent`.
4. Script removes the deprecated `@mariozechner/pi-coding-agent` package when present.
5. Existing Pi extension setup continues using `pi install npm:<extension>` commands.
6. Future Pi startup loads the same settings and packages, but the `pi` binary and core package imports resolve from the new namespace.

### Error & Failure Propagation

- Missing Bun: keep existing warning and skip Pi installation.
- New package install failure: keep existing error behavior for Pi install.
- Old package cleanup failure: warn and continue, because a working new Pi install is more important than cleanup.
- `pi` shim points to old package after migration: warn, reinstall new package once, then warn again if unresolved.
- Third-party package peer dependency warnings may still mention `@mariozechner/*` until those packages republish; that should not block the setup migration.

### State Lifecycle Risks

- Removing the old global package can remove the shared `~/.bun/bin/pi` shim if Bun associates it with the old package. Mitigation: reinstall `@earendil-works/pi-coding-agent` after cleanup if `pi` is missing or points at the old path.
- Machines with only the old package and no network access may temporarily lose Pi if cleanup runs before successful install. Mitigation: install and verify the new package before cleanup.
- Scripts should not mutate Pi settings for this change; package settings like `npm:pi-goal` remain separate from the Pi CLI package.

## Acceptance Criteria

- [ ] All Bash setup scripts install `@earendil-works/pi-coding-agent` instead of `@mariozechner/pi-coding-agent`.
- [ ] `win.ps1` installs `@earendil-works/pi-coding-agent` instead of `@mariozechner/pi-coding-agent`.
- [ ] All setup scripts attempt to remove deprecated `@mariozechner/pi-coding-agent` after a successful new install.
- [ ] Cleanup is idempotent when the old package is absent.
- [ ] Validation warns if `pi` still points to an `@mariozechner` install path.
- [ ] Version banners are incremented for every modified script.
- [ ] Current machine is migrated and `readlink -f $(command -v pi)` points under `@earendil-works/pi-coding-agent`.
- [ ] Existing Pi extensions still appear in `pi list` after migration:
  - `npm:@tintinweb/pi-subagents`
  - `npm:pi-web-access`
  - `npm:pi-goal`
  - `npm:pi-autoresearch`
- [ ] `bash -n mac.sh ubuntu.sh wsl.sh pi.sh omarchy.sh bazzite.sh` passes.
- [ ] ShellCheck error-level validation passes.
- [ ] Markdownlint passes for updated docs.
- [ ] `git diff --check` passes.

## Validation Plan

```bash
cd /home/scowalt/Code/machine-setup-scripts
bash -n mac.sh ubuntu.sh wsl.sh pi.sh omarchy.sh bazzite.sh
bunx shellcheck --severity=error mac.sh ubuntu.sh wsl.sh pi.sh omarchy.sh bazzite.sh
bunx shellcheck --exclude=SC2312,SC2250,SC2024,SC2154 mac.sh ubuntu.sh wsl.sh pi.sh omarchy.sh bazzite.sh
bunx markdownlint-cli README.md docs/plans/2026-05-07-002-feat-migrate-pi-earendil-works-package-plan.md
git diff --check
```

PowerShell parser validation when available:

```powershell
pwsh -NoProfile -Command "$tokens = $null; $errors = $null; [System.Management.Automation.Language.Parser]::ParseFile('win.ps1', [ref]$tokens, [ref]$errors) | Out-Null; if ($errors.Count) { $errors; exit 1 }"
```

Manual current-machine validation:

```bash
bun pm ls -g | grep -E '@(mariozechner|earendil-works)/pi-coding-agent' || true
pi --version
readlink -f "$(command -v pi)"
pi list
```

Expected post-migration:

- `bun pm ls -g` includes `@earendil-works/pi-coding-agent`.
- `bun pm ls -g` does not include `@mariozechner/pi-coding-agent`.
- `readlink -f "$(command -v pi)"` contains `@earendil-works/pi-coding-agent`.
- `pi list` still includes the existing user packages.

## Sources & References

- NPM: `@earendil-works/pi-coding-agent@0.74.0`
- NPM: `@mariozechner/pi-coding-agent@0.73.1` deprecation notice
- NPM: `@earendil-works/pi-ai@0.74.0`
- NPM: `@earendil-works/pi-agent-core@0.74.0`
- NPM: `@earendil-works/pi-tui@0.74.0`
- Current local `pi` symlink: `/home/scowalt/.bun/install/global/node_modules/@mariozechner/pi-coding-agent/dist/cli.js`
- Existing install functions: `install_pi_cli` / `Install-PiCli` in setup scripts
