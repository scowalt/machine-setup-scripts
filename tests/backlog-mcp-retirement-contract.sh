#!/usr/bin/env bash
# Version 2 | Last changed: Verify native Windows Backlog retirement and isolated planner IPC
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "${repo_root}"

python3 tests/test_backlog_mcp_retirement.py
python3 tests/test_backlog_windows_planner.py

# Execute the real Bash wrapper, not only its embedded program. A controlled
# parser failure must propagate to the caller so setup can aggregate it.
wrapper_root=$(mktemp -d)
trap 'rm -rf "${wrapper_root}"' EXIT
mkdir -p "${wrapper_root}/home/.codex"
chmod 700 "${wrapper_root}/home"
printf '%s\n' '[mcp_servers.backlog]' 'invalid = [' > "${wrapper_root}/home/.codex/config.toml"
awk '/^retire_global_backlog_mcp\(\)/ { copy=1 } copy { print } /^# End global Backlog MCP retirement\./ { exit }' mac.sh > "${wrapper_root}/wrapper.sh"
if HOME="${wrapper_root}/home" NODE_OPTIONS='--require=/does/not/exist' NODE_PATH='/does/not/exist' bash -c '
    ensure_shared_node_runtime() { return 0; }
    print_error() { :; }; print_success() { :; }; print_debug() { :; }
    source "$1"
    retire_global_backlog_mcp
' _ "${wrapper_root}/wrapper.sh"; then
    printf 'Bash wrapper swallowed a required retirement failure\n' >&2
    exit 1
fi

if [[ -n "${PWSH_BIN:-}" ]]; then
    {
        cat <<'POWERSHELL_STUBS'
Set-Variable -Name HOME -Value $env:BACKLOG_FIXTURE_HOME -Scope Script -Force
foreach ($name in @('PI_CODING_AGENT_DIR','CLAUDE_CONFIG_DIR','CODEX_HOME','GEMINI_CLI_HOME')) {
    [Environment]::SetEnvironmentVariable($name, $null, 'Process')
}
function Enable-SharedNodeRuntime { return $true }
function Write-Success { param($Message) }
function Write-Debug { param($Message) }
POWERSHELL_STUBS
        awk '/^function Invoke-BacklogMcpWindowsRetirement / { copy=1 } copy { print } /^# End global Backlog MCP retirement\./ { exit }' win.ps1
        printf '%s\n' 'if (Remove-GlobalBacklogMcp) { exit 1 } else { exit 0 }'
    } > "${wrapper_root}/wrapper.ps1"
    HOME="${wrapper_root}/home" BACKLOG_FIXTURE_HOME="${wrapper_root}/home" NODE_OPTIONS='--require=/does/not/exist' NODE_PATH='/does/not/exist' \
        "${PWSH_BIN}" -NoProfile -File "${wrapper_root}/wrapper.ps1"
    "${PWSH_BIN}" -NoProfile -File tests/backlog-mcp-windows.ps1
fi

for script in mac.sh ubuntu.sh wsl.sh pi.sh bazzite.sh; do
    grep -Fq 'retire_global_backlog_mcp' "${script}"
    grep -Fq 'Last changed: Retire global Backlog MCP registrations' "${script}"
done
grep -Fq 'Remove-GlobalBacklogMcp' win.ps1
grep -Fq 'Last changed: Retire global Backlog MCP registrations' win.ps1

if [[ -n "${BACKLOG_DOTFILES_SOURCE:-}" ]]; then
    [[ ! -e "${BACKLOG_DOTFILES_SOURCE}/.mcp.json" ]]
    grep -Eq '^backlog/?$' "${BACKLOG_DOTFILES_SOURCE}/.chezmoiignore"
    if rg -n --glob '!backlog/**' --glob '!README.md' 'mcpServers[^[:cntrl:]]*backlog|"backlog"[[:space:]]*:' "${BACKLOG_DOTFILES_SOURCE}"; then
        printf 'dotfiles still declares Backlog MCP outside repository task history\n' >&2
        exit 1
    fi
    rendered="${wrapper_root}/rendered"
    mkdir "${rendered}"
    chezmoi managed --source "${BACKLOG_DOTFILES_SOURCE}" --destination "${rendered}" --path-style relative > "${rendered}/managed"
    if grep -Eq '^backlog(/|$)' "${rendered}/managed"; then
        printf 'dotfiles still deploys repository backlog data\n' >&2
        exit 1
    fi
fi

printf '✓ Backlog MCP stays repository-local and dotfiles cannot recreate it globally\n'
