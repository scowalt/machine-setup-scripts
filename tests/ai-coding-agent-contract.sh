#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "${repo_root}"

bash_setup_scripts=(mac.sh ubuntu.sh wsl.sh pi.sh bazzite.sh)
linux_codex_scripts=(ubuntu.sh wsl.sh pi.sh bazzite.sh)
opencode_scripts=(mac.sh ubuntu.sh wsl.sh bazzite.sh)

fail() {
    printf '✗ %s\n' "$1" >&2
    exit 1
}

assert_contains() {
    local file=$1
    local pattern=$2
    local description=$3

    if ! grep -Eq -- "${pattern}" "${file}"; then
        fail "${file}: missing ${description} (${pattern})"
    fi
}

assert_not_contains() {
    local file=$1
    local pattern=$2
    local description=$3

    if grep -Eq -- "${pattern}" "${file}"; then
        fail "${file}: unexpectedly contains ${description} (${pattern})"
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
    assert_contains "${file}" 'bun remove -g @openai/codex' 'legacy Bun Codex cleanup'
    assert_contains "${file}" '(codex|native_path).* --version 2>/dev/null' 'Codex CLI no-Node smoke test'
    assert_contains "${file}" '^setup_pi_claude_bridge\(\)' 'Pi Claude bridge setup function'
    assert_contains "${file}" 'npm:pi-claude-bridge' 'Pi Claude bridge package source'
    assert_contains "${file}" '^[[:space:]]+setup_pi_claude_bridge$' 'Pi Claude bridge main wiring'
    assert_order "${file}" '^[[:space:]]+install_codex_cli([[:space:]]+\|\|[[:space:]]+return 1)?$' '^[[:space:]]+setup_rtk_integrations$' 'Codex CLI installed before RTK integration'
    assert_order "${file}" '^[[:space:]]+if install_pi_cli; then$' '^[[:space:]]+setup_pi_claude_bridge$' 'Pi installed before Pi Claude bridge'
    assert_contains "${file}" '^setup_pi_mcp_adapter\(\)' 'Pi MCP adapter setup function'
    assert_contains "${file}" 'npm:pi-mcp-adapter' 'Pi MCP adapter package source'
    assert_contains "${file}" '^[[:space:]]+setup_pi_mcp_adapter$' 'Pi MCP adapter main wiring'
    assert_contains "${file}" '^setup_pi_companion_packages\(\)' 'Pi companion package setup function'
    assert_contains "${file}" 'npm:pi-ask-user' 'legacy Pi Ask User package source'
    assert_contains "${file}" 'pi remove "\$\{_legacy_package\}"' 'legacy Pi Ask User package removal'
    assert_contains "${file}" 'npm:@juicesharp/rpiv-ask-user-question' 'RPIV Ask User Question package source'
    assert_contains "${file}" 'npm:pi-web-access' 'Pi Web Access package source'
    assert_contains "${file}" 'npm:@juicesharp/rpiv-todo' 'RPIV Todo package source'
    assert_contains "${file}" '^[[:space:]]+setup_pi_companion_packages$' 'Pi companion package main wiring'
    assert_order "${file}" '^[[:space:]]+setup_pi_claude_bridge$' '^[[:space:]]+setup_pi_companion_packages$' 'Pi companion package setup after Pi Claude bridge'
    assert_contains "${file}" '^remove_impeccable_resources\(\)' 'legacy Impeccable cleanup function'
    assert_contains "${file}" '^[[:space:]]+remove_impeccable_resources$' 'legacy Impeccable cleanup wiring'
    assert_order "${file}" '^[[:space:]]+if install_pi_cli; then$' '^[[:space:]]+remove_impeccable_resources$' 'Pi setup runs before legacy Impeccable cleanup'
    assert_not_contains "${file}" 'install_impeccable_skill|impeccable@latest install' 'Impeccable installer'
    assert_not_contains "${file}" 'BAN_IMPECCABLE' 'retired Impeccable opt-out'
    for path in \
        '.claude/skills/impeccable' \
        '.agents/skills/impeccable' \
        '.cursor/skills/impeccable' \
        '.gemini/skills/impeccable' \
        '.pi/agent/skills/impeccable' \
        '.cursor/agents/impeccable-manual-edit-applier.md' \
        '.cursor/agents/impeccable-asset-producer.md' \
        '.cursor/agents/impeccable-documenter.md' \
        '.cursor/agents/impeccable-finish-reviewer.md'; do
        assert_contains "${file}" "${path}" "legacy Impeccable cleanup path ${path}"
    done
done

for file in "${opencode_scripts[@]}"; do
    assert_contains "${file}" '^install_opencode\(\)' 'opencode installer function'
    assert_contains "${file}" '^validate_opencode_keys\(\)' 'opencode key validation function'
    assert_contains "${file}" '^[[:space:]]+install_opencode([[:space:]]+\|\|[[:space:]]+return 1)?$' 'opencode main wiring'
    assert_contains "${file}" '^[[:space:]]+validate_opencode_keys$' 'opencode key validation wiring'
    assert_contains "${file}" 'BAN_OPENCODE' 'opencode opt-out'
    assert_contains "${file}" 'bun remove -g opencode-ai' 'legacy Bun opencode package cleanup'
    assert_contains "${file}" 'brew install anomalyco/tap/opencode' 'opencode Homebrew formula install'
    assert_contains "${file}" 'brew upgrade opencode' 'opencode Homebrew formula upgrade'
    assert_contains "${file}" 'https://opencode\.ai/install' 'official opencode installer download'
    assert_contains "${file}" '--no-modify-path' 'opencode installer keeps chezmoi shell files untouched'
    assert_contains "${file}" 'rtk init -g --opencode' 'RTK opencode integration'
    assert_contains "${file}" '--agent opencode' 'skills CLI opencode target'
    assert_contains "${file}" '\.config/opencode/skills' 'opencode skill directory management'
    assert_order "${file}" '^[[:space:]]+install_opencode([[:space:]]+\|\|[[:space:]]+return 1)?$' '^[[:space:]]+setup_rtk_integrations$' 'opencode installed before RTK integration'
done
assert_not_contains pi.sh 'install_opencode|BAN_OPENCODE' 'opencode setup'
assert_not_contains win.ps1 'opencode|OpenCode' 'opencode setup'

assert_contains README.md 'anomalyco/tap/opencode' 'opencode Homebrew formula documentation'
assert_contains README.md 'BAN_OPENCODE' 'opencode opt-out documentation'

assert_contains mac.sh 'brew (install|upgrade) --cask codex' 'native Codex Homebrew cask install'
for file in "${linux_codex_scripts[@]}"; do
    assert_contains "${file}" 'https://chatgpt\.com/codex/install\.sh' 'official Codex standalone installer download'
    assert_contains "${file}" 'CODEX_NON_INTERACTIVE=1' 'non-interactive Codex standalone install'
    assert_contains "${file}" 'native_path="\$\{HOME\}/\.local/bin/codex"' 'per-user Codex executable path'
    assert_not_contains "${file}" 'brew (install|upgrade) --cask codex' 'shared Homebrew Codex installation'
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
assert_contains win.ps1 'function Setup-PiMcpAdapter' 'Pi MCP adapter setup function'
assert_contains win.ps1 'npm:pi-mcp-adapter' 'Pi MCP adapter package source'
assert_contains win.ps1 '^[[:space:]]+Setup-PiMcpAdapter$' 'Pi MCP adapter main wiring'
assert_contains win.ps1 'function Setup-PiCompanionPackages' 'Pi companion package setup function'
assert_contains win.ps1 'npm:pi-ask-user' 'legacy Pi Ask User package source'
assert_contains win.ps1 '& pi remove [$]legacyPackage' 'legacy Pi Ask User package removal'
assert_contains win.ps1 'npm:@juicesharp/rpiv-ask-user-question' 'RPIV Ask User Question package source'
assert_contains win.ps1 'npm:pi-web-access' 'Pi Web Access package source'
assert_contains win.ps1 'npm:@juicesharp/rpiv-todo' 'RPIV Todo package source'
assert_contains win.ps1 '^[[:space:]]+Setup-PiCompanionPackages$' 'Pi companion package main wiring'
assert_order win.ps1 '^[[:space:]]+Setup-PiClaudeBridge$' '^[[:space:]]+Setup-PiCompanionPackages$' 'Pi companion package setup after Pi Claude bridge'
assert_contains win.ps1 'function Remove-ImpeccableResources' 'legacy Impeccable cleanup function'
assert_contains win.ps1 '^[[:space:]]+Remove-ImpeccableResources$' 'legacy Impeccable cleanup wiring'
assert_order win.ps1 '^[[:space:]]+if \(Install-PiCli\) \{$' '^[[:space:]]+Remove-ImpeccableResources$' 'Pi setup runs before legacy Impeccable cleanup'
assert_not_contains win.ps1 'Install-ImpeccableSkill|impeccable@latest install' 'Impeccable installer'
assert_not_contains win.ps1 'BAN_IMPECCABLE' 'retired Impeccable opt-out'
for path in \
    '\.claude\\skills\\impeccable' \
    '\.agents\\skills\\impeccable' \
    '\.cursor\\skills\\impeccable' \
    '\.gemini\\skills\\impeccable' \
    '\.pi\\agent\\skills\\impeccable' \
    '\.cursor\\agents\\impeccable-manual-edit-applier\.md' \
    '\.cursor\\agents\\impeccable-asset-producer\.md' \
    '\.cursor\\agents\\impeccable-documenter\.md' \
    '\.cursor\\agents\\impeccable-finish-reviewer\.md'; do
    assert_contains win.ps1 "${path}" "legacy Impeccable cleanup path ${path}"
done

assert_contains README.md 'macOS, Ubuntu, WSL, Raspberry Pi, Bazzite, and Windows' 'all-machine AI coding agent statement'
assert_contains README.md 'Claude Code CLI and Codex CLI' 'Claude/Codex README contract'
assert_contains README.md "OpenAI's standalone installer" 'per-user Linux Codex installer documentation'
assert_contains README.md '\.local/bin' 'Paseo-compatible Codex path documentation'
assert_contains README.md 'Pi Claude bridge' 'Pi Claude bridge README contract'
assert_contains README.md '@juicesharp/rpiv-ask-user-question' 'RPIV Ask User Question README contract'
assert_contains README.md 'pi-web-access' 'Pi Web Access README contract'
assert_contains README.md '@juicesharp/rpiv-todo' 'RPIV Todo README contract'
assert_contains README.md 'removes legacy global Impeccable skill copies' 'legacy Impeccable cleanup documentation'
assert_not_contains README.md 'Impeccable design skill|BAN_IMPECCABLE' 'retired Impeccable setup documentation'
assert_not_contains CLAUDE.md 'BAN_IMPECCABLE' 'retired Impeccable setup guidance'

source_without_main='s/^main "\$@"$/:/'
for file in "${bash_setup_scripts[@]}"; do
    cleanup_test_root=$(mktemp -d)
    cleanup_home="${cleanup_test_root}/home"
    symlink_target="${cleanup_test_root}/symlink-target"
    mkdir -p \
        "${cleanup_home}/.claude/skills" \
        "${cleanup_home}/.agents/skills/impeccable" \
        "${cleanup_home}/.agents/skills/keep-me" \
        "${cleanup_home}/.cursor/skills/impeccable" \
        "${cleanup_home}/.gemini/skills/impeccable" \
        "${cleanup_home}/.pi/agent/skills/impeccable" \
        "${cleanup_home}/.cursor/agents" \
        "${symlink_target}"
    touch \
        "${cleanup_home}/.agents/skills/impeccable/SKILL.md" \
        "${cleanup_home}/.agents/skills/keep-me/SKILL.md" \
        "${cleanup_home}/.cursor/skills/impeccable/SKILL.md" \
        "${cleanup_home}/.gemini/skills/impeccable/SKILL.md" \
        "${cleanup_home}/.pi/agent/skills/impeccable/SKILL.md" \
        "${cleanup_home}/.cursor/agents/impeccable-manual-edit-applier.md" \
        "${cleanup_home}/.cursor/agents/impeccable-asset-producer.md" \
        "${cleanup_home}/.cursor/agents/impeccable-documenter.md" \
        "${cleanup_home}/.cursor/agents/impeccable-finish-reviewer.md" \
        "${cleanup_home}/.cursor/agents/keep-me.md" \
        "${symlink_target}/sentinel"
    ln -s "${symlink_target}" "${cleanup_home}/.claude/skills/impeccable"

    SETUP_SCRIPT="${repo_root}/${file}" SOURCE_WITHOUT_MAIN="${source_without_main}" HOME="${cleanup_home}" bash -c '
        source <(sed "${SOURCE_WITHOUT_MAIN}" "${SETUP_SCRIPT}")
        remove_impeccable_resources
        remove_impeccable_resources
    '

    for path in \
        "${cleanup_home}/.claude/skills/impeccable" \
        "${cleanup_home}/.agents/skills/impeccable" \
        "${cleanup_home}/.cursor/skills/impeccable" \
        "${cleanup_home}/.gemini/skills/impeccable" \
        "${cleanup_home}/.pi/agent/skills/impeccable" \
        "${cleanup_home}/.cursor/agents/impeccable-manual-edit-applier.md" \
        "${cleanup_home}/.cursor/agents/impeccable-asset-producer.md" \
        "${cleanup_home}/.cursor/agents/impeccable-documenter.md" \
        "${cleanup_home}/.cursor/agents/impeccable-finish-reviewer.md"; do
        [[ ! -e "${path}" && ! -L "${path}" ]] || fail "${file}: legacy Impeccable cleanup left ${path}"
    done
    [[ -f "${cleanup_home}/.agents/skills/keep-me/SKILL.md" ]] || fail "${file}: cleanup removed a sibling skill"
    [[ -f "${cleanup_home}/.cursor/agents/keep-me.md" ]] || fail "${file}: cleanup removed a sibling Cursor agent"
    [[ -f "${symlink_target}/sentinel" ]] || fail "${file}: cleanup followed the Impeccable symlink target"
    rm -rf "${cleanup_test_root}"
done

printf '✓ AI coding agent contract checks passed\n'
