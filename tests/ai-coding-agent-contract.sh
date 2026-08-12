#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "${repo_root}"

bash_setup_scripts=(mac.sh ubuntu.sh wsl.sh pi.sh bazzite.sh)

fail() {
    printf '✗ %s\n' "$1" >&2
    exit 1
}

assert_contains() {
    local file=$1
    local pattern=$2
    local description=$3

    if ! grep -Eq "${pattern}" "${file}"; then
        fail "${file}: missing ${description} (${pattern})"
    fi
}

first_line_matching() {
    local file=$1
    local pattern=$2

    grep -nE "${pattern}" "${file}" | head -n 1 | cut -d: -f1 || true
}

assert_order() {
    local file=$1
    local first_pattern=$2
    local second_pattern=$3
    local description=$4
    local first_line
    local second_line

    first_line=$(first_line_matching "${file}" "${first_pattern}")
    second_line=$(first_line_matching "${file}" "${second_pattern}")
    [[ -n "${first_line}" && -n "${second_line}" ]] || fail "${file}: cannot check order for ${description}"
    [[ "${first_line}" -lt "${second_line}" ]] || fail "${file}: wrong order for ${description}"
}

for file in "${bash_setup_scripts[@]}"; do
    bash -n "${file}"
    assert_contains "${file}" '^install_claude_code\(\)' 'Claude Code installer function'
    assert_contains "${file}" '^install_codex_cli\(\)' 'Codex CLI installer function'
    assert_contains "${file}" '^[[:space:]]+install_claude_code$' 'Claude Code main wiring'
    assert_contains "${file}" '^[[:space:]]+install_codex_cli([[:space:]]+\|\|[[:space:]]+return 1)?$' 'Codex CLI main wiring'
    assert_contains "${file}" 'https://claude\.ai/install\.sh' 'Claude Code native installer download'
    assert_contains "${file}" 'brew (install|upgrade) --cask codex' 'native Codex Homebrew cask install'
    assert_contains "${file}" 'bun remove -g @openai/codex' 'legacy Bun Codex cleanup'
    assert_contains "${file}" 'codex.* --version 2>/dev/null' 'Codex CLI no-Node smoke test'
    assert_contains "${file}" '^setup_pi_claude_bridge\(\)' 'Pi Claude bridge setup function'
    assert_contains "${file}" 'npm:pi-claude-bridge' 'Pi Claude bridge package source'
    assert_contains "${file}" '^[[:space:]]+setup_pi_claude_bridge$' 'Pi Claude bridge main wiring'
    assert_order "${file}" '^[[:space:]]+install_codex_cli([[:space:]]+\|\|[[:space:]]+return 1)?$' '^[[:space:]]+setup_rtk_integrations$' 'Codex CLI installed before RTK integration'
    assert_order "${file}" '^[[:space:]]+if install_pi_cli; then$' '^[[:space:]]+setup_pi_claude_bridge$' 'Pi installed before Pi Claude bridge'
    assert_contains "${file}" '^install_impeccable_skill\(\)' 'Impeccable installer function'
    assert_contains "${file}" 'npx --yes impeccable@latest install --scope=global --providers=claude,codex,cursor,gemini,pi --force --yes --no-hooks' 'provider-specific global Impeccable install'
    assert_contains "${file}" 'BAN_IMPECCABLE' 'Impeccable opt-out'
    assert_contains "${file}" '\.agents/skills/impeccable/SKILL\.md' 'Codex Impeccable verification path'
    assert_contains "${file}" '\.pi/agent/skills/impeccable/SKILL\.md' 'Pi Impeccable verification path'
    assert_contains "${file}" '^[[:space:]]+install_impeccable_skill$' 'Impeccable main wiring'
    assert_order "${file}" '^[[:space:]]+if install_pi_cli; then$' '^[[:space:]]+install_impeccable_skill$' 'Node-backed Pi setup runs before Impeccable'
done

assert_contains win.ps1 'function Install-ClaudeCode' 'Claude Code installer function'
assert_contains win.ps1 'function Install-CodexCli' 'Codex CLI installer function'
assert_contains win.ps1 '^[[:space:]]+Install-ClaudeCode$' 'Claude Code main wiring'
assert_contains win.ps1 '^[[:space:]]+Install-CodexCli$' 'Codex CLI main wiring'
assert_contains win.ps1 'https://claude\.ai/install\.ps1' 'Claude Code native installer download'
assert_contains win.ps1 'github\.com/openai/codex/releases/latest/download/' 'Codex CLI native release download'
assert_contains win.ps1 'codex-.*pc-windows-msvc\.exe\.zip' 'Codex Windows release asset'
assert_contains win.ps1 'bun remove -g .@openai/codex.' 'legacy Bun Codex cleanup'
assert_contains win.ps1 'codexExe --version' 'Codex CLI no-Node smoke test'
assert_contains win.ps1 'function Setup-PiClaudeBridge' 'Pi Claude bridge setup function'
assert_contains win.ps1 'npm:pi-claude-bridge' 'Pi Claude bridge package source'
assert_contains win.ps1 '^[[:space:]]+Setup-PiClaudeBridge$' 'Pi Claude bridge main wiring'
assert_order win.ps1 '^[[:space:]]+Install-CodexCli$' '^[[:space:]]+Setup-RtkIntegrations$' 'Codex CLI installed before RTK integration'
assert_order win.ps1 '^[[:space:]]+if \(Install-PiCli\) \{$' '^[[:space:]]+Setup-PiClaudeBridge$' 'Pi installed before Pi Claude bridge'
assert_contains win.ps1 'function Install-ImpeccableSkill' 'Impeccable installer function'
assert_contains win.ps1 'npx --yes impeccable@latest install --scope=global --providers=claude,codex,cursor,gemini,pi --force --yes --no-hooks' 'provider-specific global Impeccable install'
assert_contains win.ps1 'BAN_IMPECCABLE' 'Impeccable opt-out'
assert_contains win.ps1 '\.agents\\skills\\impeccable\\SKILL\.md' 'Codex Impeccable verification path'
assert_contains win.ps1 '\.pi\\agent\\skills\\impeccable\\SKILL\.md' 'Pi Impeccable verification path'
assert_contains win.ps1 '^[[:space:]]+Install-ImpeccableSkill$' 'Impeccable main wiring'
assert_order win.ps1 '^[[:space:]]+if \(Install-PiCli\) \{$' '^[[:space:]]+Install-ImpeccableSkill$' 'Node-backed Pi setup runs before Impeccable'

assert_contains README.md 'macOS, Ubuntu, WSL, Raspberry Pi, Bazzite, and Windows' 'all-machine AI coding agent statement'
assert_contains README.md 'Claude Code CLI and Codex CLI' 'Claude/Codex README contract'
assert_contains README.md 'Pi Claude bridge' 'Pi Claude bridge README contract'
assert_contains README.md 'Impeccable design skill' 'Impeccable README contract'

printf '✓ AI coding agent installation contract checks passed\n'
