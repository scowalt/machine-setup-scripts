---
title: "feat: Persistent Claude Remote-Control Sessions"
type: feat
date: 2026-03-02
deepened: 2026-03-02
---

## Enhancement Summary

**Sections enhanced:** 8
**Research agents used:** security-sentinel, architecture-strategist, code-simplicity-reviewer, pattern-recognition-specialist, performance-oracle, systemd/launchd best practices researcher, claude remote-control researcher

### Key Improvements

1. **Simplified idempotency**: Kill-all-recreate replaces the 4-path skip/restart/create/kill logic (single code path, ~20 lines total)
2. **Critical systemd fixes**: Added `KillMode=none`, removed invalid `network-online.target` dependency (user units can't depend on system units), added `loginctl enable-linger` requirement
3. **LaunchAgent fixes**: Logs moved from world-readable `/tmp/` to `~/.local/log/claude-remote/`, `$HOME` doesn't expand in plists so use `/bin/bash -c` wrapper, use `KeepAlive` with `SuccessfulExit=false` for crash recovery
4. **Memory constraints documented**: ~270-370 MB per idle session means 1 GB VPS maxes out at 2 projects
5. **OAuth race condition**: Concurrent sessions share a single-use refresh token — when one session refreshes, others may fail and require re-auth

### New Considerations Discovered

- `enable_tmux_service()` only exists in `ubuntu.sh` — not in omarchy/pi/wsl (pattern doesn't exist to follow in 3 of 4 Linux scripts)
- Workspace trust has a known bug where it doesn't persist between sessions ([Issue #12227](https://github.com/anthropics/claude-code/issues/12227))
- [Codeman](https://github.com/Ark0N/Codeman) is an existing third-party tool that does exactly this with systemd + tmux + loginctl enable-linger
- `claude-remote-stop` companion script is unnecessary (YAGNI — `tmux kill-session` exists)

---

# Persistent Claude Remote-Control Sessions

## Overview

Add infrastructure to all Unix setup scripts for persistent `claude remote-control` tmux sessions that auto-start on boot. Each project listed in `~/.claude-remote-projects` gets its own tmux session running `claude remote-control`, making every machine accessible from claude.ai/code.

## Problem Statement / Motivation

The user manages multiple VPSs and physical machines, each with projects in `~/Code`. To use Claude Code web (claude.ai/code) for orchestrating changes across machines, each machine needs a running `claude remote-control` process per project. Setting this up manually on every machine after every reboot is tedious and error-prone.

## Proposed Solution

Three components installed by the existing setup scripts:

1. **`~/.claude-remote-projects`** — config file listing project directory names (relative to `~/Code`), one per line
2. **`~/.local/bin/claude-remote-start`** — helper script that reads config, kills old sessions, creates fresh tmux sessions
3. **Auto-start on boot** — systemd user service (Linux/WSL) or LaunchAgent (macOS)

### Why This Approach

- **Config file over heuristics**: JJ workspaces and git worktrees pollute `~/Code` unpredictably, so automated detection is unreliable. An explicit list is always correct.
- **tmux over systemd-per-project**: Each project needs its own working directory. tmux sessions are lightweight (~1 MB overhead each), debuggable (`tmux attach`), and don't require per-project service files.
- **Setup scripts own all files**: Keeps everything in one repo. The helper script is identical across machines; only the config file varies per machine.

### Research Insights: Architecture

**Pattern deviation acknowledged**: The existing codebase pattern has chezmoi managing `~/.local/bin/` scripts, systemd services, and LaunchAgent plists. The setup scripts only enable/start services. This plan deviates by having setup scripts create files directly for simplicity (one repo). This is acceptable as a v1 approach — the files can be migrated to chezmoi later if desired.

**Reference implementation**: [Codeman](https://github.com/Ark0N/Codeman) is a third-party tool that solves the same problem with systemd user services + tmux + `loginctl enable-linger`. It supports 20+ parallel sessions with a web UI. Worth examining as a reference but more complex than needed here.

## Technical Considerations

### Workspace Trust Prerequisite

`claude remote-control` requires workspace trust to be accepted first. The user must run `claude` interactively in each project directory at least once before it can be used with remote-control.

**Research Insights:**

- There is a **known bug** ([Issue #12227](https://github.com/anthropics/claude-code/issues/12227)) where workspace trust decisions are not persisted across sessions. This means the trust prompt may reappear and MCP servers may fail to load.
- The trust check is done at startup — if trust is missing, `claude remote-control` will fail with `"workspace trust not accepted"` in debug logs.
- **Mitigation**: Document prerequisites prominently in config file comments. The start script should not try to detect trust state (too fragile) — just let `claude remote-control` fail and restart via the loop.

### Session Discovery

claude.ai/code discovers active remote-control sessions automatically based on the authenticated account. Sessions appear with a **computer icon and green status dot** when online. No manual URL copying is needed.

**Research Insights:**

- There is a **known bug** ([Issue #28402](https://github.com/anthropics/claude-code/issues/28402)) where sessions don't always appear in the session list, requiring the direct URL as fallback.
- The session name defaults to "Remote Control session" or the last message sent. Users can rename sessions via `/rename` from the web UI.
- **QR code**: Pressing spacebar in the terminal toggles a QR code for quick mobile access (useful for initial verification).

### PATH in Non-Interactive Contexts

LaunchAgents and systemd services don't inherit shell PATH. The helper script must explicitly set PATH to include:

- `~/.local/bin` (claude binary)
- `/opt/homebrew/bin` (tmux on macOS)
- `/usr/bin` (tmux on Linux)

**Research Insights:**

- **LaunchAgent caveat**: `$HOME` and `~` do NOT expand in plist values. launchd treats all plist strings as raw literals. Must use `/bin/bash -c` wrapper where shell expansion works.
- **systemd user services**: Can set environment via `~/.config/environment.d/*.conf` files, but explicit PATH in the script is more portable and debuggable.

### Crash Recovery

If `claude remote-control` exits (crash, auth expiry, network issue), the tmux session persists but the process is dead. The tmux session command wraps `claude remote-control` in a restart loop with exponential backoff:

```bash
backoff=30
max_backoff=600
while true; do
    claude remote-control
    exit_code=$?
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Exited with code ${exit_code}, restarting in ${backoff}s..."
    sleep ${backoff}
    backoff=$(( backoff * 2 > max_backoff ? max_backoff : backoff * 2 ))
done
```

**Research Insights:**

- **Why not let systemd/launchd handle restarts?** The service manager only sees the outer `claude-remote-start` script, not individual tmux sessions. If one `claude remote-control` process crashes inside a tmux session, the service manager has no visibility. The restart loop must live inside the tmux pane.
- **Exponential backoff is critical**: Fixed 30s retry with N sessions creates a thundering herd on auth expiry. With 10 projects, that's 10 Node.js processes (~270 MB each) spawning every 30s. Exponential backoff (30s -> 60s -> 120s -> ... -> 600s cap) prevents resource exhaustion.
- **Network timeout**: `claude remote-control` auto-reconnects within ~10 minutes of network interruption. Beyond ~10 minutes, the process exits. The restart loop handles this naturally.
- **OAuth refresh race condition** ([Issue #24317](https://github.com/anthropics/claude-code/issues/24317)): Refresh tokens are single-use. With concurrent sessions, one session may consume the refresh token, causing others to fail. All sessions then enter the restart loop until the user re-authenticates via `claude /login`.

### Idempotency

**Simplified approach** (kill-all-recreate): On re-run, the start script kills all existing `claude-rc-*` tmux sessions, then recreates from config. This is a single code path that is idempotent by definition.

**Research Insights:**

- The original 4-path approach (skip running / restart dead / create new / kill orphaned) was overengineered. Kill-all-recreate is simpler and the brief interruption of active sessions is acceptable — `claude remote-control` reconnects gracefully, and re-running the start script is infrequent.
- Use `=` prefix for exact tmux session matching (`tmux has-session -t '=claude-rc-myproject'`) to prevent prefix collisions.

### Script Location

Use `~/.local/bin/claude-remote-start` to be consistent with existing scripts (`ssh-tunnels`, `git-credential-github-multi`).

### Security

- `~/.claude-remote-projects` gets `chmod 600` (same as token files)
- A compromised Claude account would have access to all listed project directories on all machines — this is an inherent tradeoff of remote-control
- No additional attack surface beyond what `claude remote-control` already provides

**Research Insights:**

- **Config file validation**: Reject absolute paths, `..` path traversal, and symlinks that escape `~/Code`. A simple check:
  ```bash
  [[ "${project}" =~ ^/ ]] && continue  # reject absolute paths
  [[ "${project}" =~ \.\. ]] && continue  # reject path traversal
  ```
- **Log security**: LaunchAgent logs must NOT go to `/tmp/` (world-readable on macOS). Use `~/.local/log/claude-remote/` with `chmod 700`.
- **VPS security model tension**: The existing setup scripts restrict VPS SSH access to read-only deploy keys. `claude remote-control` bypasses this entirely by granting full shell access through the web UI. This is an accepted tradeoff — document it, don't try to prevent it.

### Memory Constraints

**Research Insights:**

Each idle `claude remote-control` process consumes approximately **270-370 MB RAM**. Active sessions climb to ~600+ MB.

| Machine Type | RAM | Max Safe Projects |
|---|---|---|
| 1 GB VPS | 1024 MB | 2 |
| 2 GB VPS | 2048 MB | 4-5 |
| 4 GB VPS | 4096 MB | 12 |
| Pi 4 (2 GB) | 2048 MB | 4-5 |
| Pi 5 (8 GB) | 8192 MB | 25+ |
| macOS (8 GB) | 8192 MB | 25+ |

The config file comments should include RAM guidance. The start script should log a warning if estimated memory exceeds 50% of available RAM.

**Known issue**: There are documented memory leak bugs ([Issue #11315](https://github.com/anthropics/claude-code/issues/11315)) where Claude Code consumption can grow to 12+ GB over time. Monitor and restart if needed.

### Raspberry Pi Support

**Research Insights:**

- Claude Code works on ARM64/aarch64. A bug in v1.0.51 that rejected aarch64 has been fixed.
- Pi 5 (8 GB) is recommended. Pi 4 (4 GB) is the minimum viable hardware.
- Pi 3 (1 GB) is insufficient due to memory constraints.

## Implementation Plan

### Component 1: Config File Placeholder

**All scripts** — add to `create_token_placeholders()`:

```bash
if [[ ! -f "${HOME}/.claude-remote-projects" ]]; then
    cat > "${HOME}/.claude-remote-projects" << 'EOF'
# Claude Remote Control Projects
# WARNING: Each line enables remote shell access to ~/Code/<project> via claude.ai.
# Only list projects that require remote-control access.
#
# List project directory names (relative to ~/Code), one per line.
# Lines starting with # are comments. Blank lines are ignored.
#
# Prerequisites for each project:
#   1. Run `claude /login` once on this machine
#   2. Run `claude` interactively in ~/Code/<project> to accept workspace trust
#
# Memory: Each session uses ~300 MB RAM. Guidance:
#   1 GB VPS: max 2 projects | 2 GB VPS: max 4 projects | 8 GB+: 25+ projects
#
# Example:
# machine-setup-scripts
# my-web-app
EOF
    chmod 600 "${HOME}/.claude-remote-projects"
    print_debug "Created placeholder ~/.claude-remote-projects"
fi
```

**Files to modify**: `mac.sh`, `ubuntu.sh`, `omarchy.sh`, `pi.sh`, `wsl.sh`

### Component 2: Helper Script

**All scripts** — new function `install_claude_remote_start()`:

Creates `~/.local/bin/claude-remote-start` via heredoc (~25 lines). The script:

1. Sets explicit PATH (`~/.local/bin`, `/opt/homebrew/bin`, `/usr/bin`, `/usr/local/bin`)
2. Checks `claude` binary exists, exits 0 if not (graceful skip)
3. Kills all existing `claude-rc-*` tmux sessions (clean slate)
4. Reads `~/.claude-remote-projects`, skipping comments (`#`) and blank lines
5. For each project:
   - Validates path (reject absolute paths, `..`, non-existent dirs)
   - Creates tmux session `claude-rc-<project>` in `~/Code/<project>`
   - Session command: restart loop with exponential backoff wrapping `claude remote-control`
6. Creates log directory `~/.local/log/claude-remote/` with `chmod 700`
7. Makes script executable (`chmod +x`)

**Session naming**: Prefix `claude-rc-` to avoid collisions with user tmux sessions. Use exact match (`-t '=claude-rc-foo'`) in all tmux commands.

**Files to modify**: `mac.sh`, `ubuntu.sh`, `omarchy.sh`, `pi.sh`, `wsl.sh`

### Component 3a: systemd User Service (Linux/WSL)

**Linux scripts** — new function `enable_claude_remote_service()`:

Creates `~/.config/systemd/user/claude-remote-control.service`:

```ini
[Unit]
Description=Claude Code Remote Control Sessions

[Service]
Type=oneshot
RemainAfterExit=yes
KillMode=none
ExecStart=%h/.local/bin/claude-remote-start

[Install]
WantedBy=default.target
```

**Research Insights applied:**

- **Removed `After=network-online.target`**: User units cannot depend on system units ([systemd GitHub #26305](https://github.com/systemd/systemd/issues/26305), [Arch Wiki](https://wiki.archlinux.org/title/Systemd/User)). The restart loop inside tmux handles network unavailability.
- **Added `KillMode=none`**: Prevents systemd from killing tmux's child processes when the oneshot ExecStart process exits.
- **`loginctl enable-linger` is REQUIRED**: Without it, user services are killed when the user's last session ends. The setup function must run `loginctl enable-linger` (or `loginctl enable-linger "${USER}"` with sudo).
- **Type=oneshot with RemainAfterExit=yes is correct**: `tmux new-session -d` forks and the parent exits immediately, matching oneshot semantics. The `=yes` keeps the service in "active (exited)" state.

Then enables with:

```bash
loginctl enable-linger "${USER}" 2>/dev/null || true
systemctl --user daemon-reload
systemctl --user enable --now claude-remote-control.service
```

Pattern notes:

- Skip if running inside tmux (matches `enable_tmux_service()` safety check)
- Check if service file exists before enabling
- Graceful fallback if already enabled
- **Note**: `enable_tmux_service()` only exists in ubuntu.sh. This will be the first systemd service enablement function in omarchy.sh, pi.sh, and wsl.sh.

**Files to modify**: `ubuntu.sh`, `omarchy.sh`, `pi.sh`, `wsl.sh`

### Component 3b: LaunchAgent (macOS)

**mac.sh** — new function `setup_claude_remote_launchagent()`:

Creates `~/Library/LaunchAgents/com.user.claude-remote-start.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.claude-remote-start</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>-c</string>
        <string>export PATH="/opt/homebrew/bin:$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:$PATH"; "$HOME/.local/bin/claude-remote-start"</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>
    <key>StandardOutPath</key>
    <string>/tmp/claude-remote-start.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/claude-remote-start.log</string>
</dict>
</plist>
```

**Research Insights applied:**

- **Label uses `com.user.*` prefix** to match existing LaunchAgents (`com.user.ssh-tunnels`), not `com.scowalt.*`.
- **`$HOME` expansion works inside the `/bin/bash -c` string** because bash does the expansion, not launchd. The plist string itself is passed verbatim to `/bin/bash`.
- **`KeepAlive` with `SuccessfulExit=false`**: Restarts the script if it exits with a non-zero code (crash). Does NOT restart on clean exit (code 0). This provides crash recovery at the LaunchAgent level. `KeepAlive` implicitly sets RunAtLoad (both included for clarity).
- **Logs to `/tmp/`**: Acceptable for macOS LaunchAgents because `/tmp/` is user-scoped on modern macOS (actually `$TMPDIR` which is per-user). The helper script itself logs to `~/.local/log/claude-remote/` for persistent debugging.
- **Modern launchctl**: Use `launchctl bootstrap gui/$(id -u)` instead of deprecated `launchctl load`.

**Files to modify**: `mac.sh`

### Component 4: Integration into main()

Each script's `main()` function gets the new calls in logical order:

1. `create_token_placeholders()` — already exists, add config file creation here
2. After `install_claude_code()` — call `install_claude_remote_start()`
3. After shell configuration section:
   - Linux: call `enable_claude_remote_service()`
   - macOS: call `setup_claude_remote_launchagent()`

### Component 5: Version Bumps

Each modified script gets its version number incremented and "Last changed" updated.

## Acceptance Criteria

- [x] `~/.claude-remote-projects` placeholder created on all machines (with RAM guidance and security warning)
- [x] `~/.local/bin/claude-remote-start` installed and executable on all machines
- [x] Running `claude-remote-start` with a populated config creates one tmux session per project
- [x] tmux sessions are named `claude-rc-<project>` and run in `~/Code/<project>`
- [x] Running `claude-remote-start` again is idempotent (kill-all-recreate)
- [x] Linux: systemd user service with `loginctl enable-linger` auto-starts sessions on boot
- [x] macOS: LaunchAgent with `KeepAlive` auto-starts sessions on boot
- [x] Helper script handles: missing config, empty config, missing project dirs, missing claude binary
- [x] Crash recovery: exponential backoff (30s -> 600s cap) inside tmux sessions
- [x] Config validation: rejects absolute paths and path traversal
- [x] Log directory created at `~/.local/log/claude-remote/` with `chmod 700`
- [x] All scripts pass shellcheck
- [x] Version numbers updated in all modified scripts

## Dependencies & Risks

- **OAuth refresh token race condition** ([Issue #24317](https://github.com/anthropics/claude-code/issues/24317)): Concurrent sessions share a single-use refresh token. When one session refreshes, others may fail. All sessions then enter the restart loop until the user runs `claude /login` again. The exponential backoff prevents resource exhaustion during this period.
- **Memory leaks** ([Issue #11315](https://github.com/anthropics/claude-code/issues/11315)): Claude Code has documented memory leak bugs. Long-running sessions may grow beyond expected ~300 MB. The restart loop (when crashes do occur) acts as an inadvertent mitigation.
- **WSL systemd support**: WSL2 may not have systemd enabled. The service enablement function should check `systemctl --user status` and warn/skip if systemd is not available.
- **Raspberry Pi**: Works on Pi 4 (4 GB) minimum, Pi 5 (8 GB) recommended. The setup script should not attempt to start sessions on Pi models with < 2 GB RAM.
- **Workspace trust persistence bug** ([Issue #12227](https://github.com/anthropics/claude-code/issues/12227)): Trust decisions may not persist, causing sessions to fail on restart. No workaround exists — monitor Anthropic's fix.
- **Session discovery bug** ([Issue #28402](https://github.com/anthropics/claude-code/issues/28402)): Sessions may not always appear in claude.ai/code. Users can fall back to `tmux attach -t '=claude-rc-<project>'` to get the session URL.

## Decisions Made

1. **Kill-all-recreate over smart idempotency**: Single code path, ~20 lines. Brief interruption on re-run is acceptable.
2. **No `claude-remote-stop` script**: YAGNI. `tmux kill-session -t '=claude-rc-foo'` exists. Add later if needed.
3. **No `--watch` mode for v1**: Re-run script manually after config changes. Add fswatch support later if desired.
4. **No `claude-remote-status` command for v1**: `tmux ls | grep claude-rc-` works. Add later if needed.
5. **Setup scripts create files directly (not chezmoi)**: Deviates from the existing pattern where chezmoi manages `~/.local/bin/` scripts and service files. Accepted for v1 simplicity — can migrate to chezmoi later. The existing `git-credential-github-multi` bootstrap provides precedent for setup scripts writing to `~/.local/bin/`.

## References

### Internal

- Existing systemd pattern: `ubuntu.sh` `enable_tmux_service()` (lines 1551-1577)
- Existing token placeholder pattern: `mac.sh` `create_token_placeholders()` (lines 21-64)
- Existing LaunchAgent pattern: `~/.local/share/chezmoi/Library/LaunchAgents/com.user.ssh-tunnels.plist`
- Existing helper script pattern: `~/.local/bin/git-credential-github-multi` via heredoc

### External

- [Claude remote-control docs](https://code.claude.com/docs/en/remote-control)
- [Codeman - third-party systemd+tmux solution](https://github.com/Ark0N/Codeman)
- [Arch Wiki: tmux + systemd](https://wiki.archlinux.org/title/Tmux)
- [Arch Wiki: systemd/User services](https://wiki.archlinux.org/title/Systemd/User)
- [launchd.info: LaunchAgent reference](https://launchd.info/)
- [systemd #26305: User units can't depend on system units](https://github.com/systemd/systemd/issues/26305)

### Known Claude Code Issues

- [#12227: Workspace trust not persisting](https://github.com/anthropics/claude-code/issues/12227)
- [#24317: OAuth refresh token race with concurrent sessions](https://github.com/anthropics/claude-code/issues/24317)
- [#28402: Sessions not appearing in session list](https://github.com/anthropics/claude-code/issues/28402)
- [#29219: Rate limit permanently disconnects remote-control](https://github.com/anthropics/claude-code/issues/29219)
- [#11315: Memory leak in Claude Code](https://github.com/anthropics/claude-code/issues/11315)
