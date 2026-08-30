#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "${repo_root}"

bash_setup_scripts=(mac.sh ubuntu.sh wsl.sh pi.sh bazzite.sh)
all_setup_scripts=(mac.sh ubuntu.sh wsl.sh pi.sh bazzite.sh win.ps1)
source_without_main='s/^main "\$@"$/:/'

fail() {
    printf '✗ %s\n' "$1" >&2
    exit 1
}

assert_not_contains() {
    local file="$1"
    local pattern="$2"
    local description="$3"

    if grep -Eiq "${pattern}" "${file}"; then
        fail "${file}: unexpectedly contains ${description}"
    fi
}

assert_contains() {
    local file="$1"
    local pattern="$2"
    local description="$3"

    grep -Eq "${pattern}" "${file}" || fail "${file}: missing ${description}"
}

for file in "${bash_setup_scripts[@]}"; do
    assert_contains "${file}" '^remove_rtk_resources\(\)' 'retired RTK cleanup interface'
    assert_contains "${file}" '^[[:space:]]+remove_rtk_resources[[:space:]]+\|\|[[:space:]]+return 1$' 'strict RTK cleanup call'
    assert_not_contains "${file}" 'install_rtk_cli|setup_rtk_integrations|BAN_RTK|RTK_INSTALL_DIR' 'active RTK installation support'

    apply_line=$(grep -En 'chezmoi apply|apply_chezmoi_config' "${file}" | tail -n 1 | cut -d: -f1)
    cleanup_line=$(grep -En '^[[:space:]]+remove_rtk_resources[[:space:]]+\|\|[[:space:]]+return 1$' "${file}" | tail -n 1 | cut -d: -f1)
    [[ -n "${apply_line}" && -n "${cleanup_line}" && "${apply_line}" -lt "${cleanup_line}" ]] || fail "${file}: RTK cleanup does not run after dotfiles"
done

assert_contains win.ps1 '^function Remove-RtkResources' 'PowerShell retired RTK cleanup interface'
assert_contains win.ps1 '^[[:space:]]+Remove-RtkResources$' 'strict PowerShell RTK cleanup call'
assert_not_contains win.ps1 'Install-RtkCli|Setup-RtkIntegrations|BAN_RTK|api\.github\.com/repos/rtk-ai' 'active PowerShell RTK installation support'
windows_dotfiles_line=$(grep -En '^[[:space:]]+Update-Chezmoi$' win.ps1 | tail -n 1 | cut -d: -f1)
windows_cleanup_line=$(grep -En '^[[:space:]]+Remove-RtkResources$' win.ps1 | tail -n 1 | cut -d: -f1)
[[ "${windows_dotfiles_line}" -lt "${windows_cleanup_line}" ]] || fail 'win.ps1: RTK cleanup does not run after dotfiles'

for file in "${all_setup_scripts[@]}"; do
    assert_not_contains "${file}" 'raw\.githubusercontent\.com/rtk-ai/rtk|rtk telemetry (enable|disable)' 'RTK download or telemetry setup'
done

run_cleanup_fixture() {
    local file="$1"
    local test_root=""

    test_root=$(mktemp -d)
    SETUP_SCRIPT="${repo_root}/${file}" SOURCE_WITHOUT_MAIN="${source_without_main}" TEST_ROOT="${test_root}" bash -c '
        set -euo pipefail
        home="${TEST_ROOT}/home"
        custom_claude="${TEST_ROOT}/custom-claude"
        custom_codex="${TEST_ROOT}/custom-codex"
        custom_pi="${TEST_ROOT}/custom-pi"
        xdg_config="${TEST_ROOT}/xdg-config"
        xdg_data="${TEST_ROOT}/xdg-data"
        project="${TEST_ROOT}/project"
        calls="${TEST_ROOT}/upstream-calls"

        mkdir -p \
            "${home}/.local/bin" \
            "${home}/.claude/hooks" \
            "${home}/.codex" \
            "${home}/.gemini/hooks" \
            "${home}/.config/opencode/plugins" \
            "${home}/.config/rtk" \
            "${home}/.local/share/rtk/tee" \
            "${home}/.pi/agent" \
            "${custom_claude}/hooks" \
            "${custom_codex}" \
            "${custom_pi}" \
            "${xdg_config}/rtk" \
            "${xdg_data}/rtk" \
            "${project}/.rtk"

        cat > "${home}/.local/bin/rtk" <<RTK_BINARY
#!/usr/bin/env bash
case "\$1" in
    gain) exit 0 ;;
    --help) printf "%s\\n" "Rust Token Killer token-optimized" ;;
    init) printf "%s\\n" "\$*" >> "${calls}"; exit 7 ;;
    *) exit 7 ;;
esac
RTK_BINARY
        chmod +x "${home}/.local/bin/rtk"

        printf "%s\n" legacy > "${home}/.claude/RTK.md"
        printf "%s\n" legacy > "${home}/.claude/hooks/rtk-rewrite.sh"
        printf "%s\n" hash > "${home}/.claude/hooks/.rtk-hook.sha256"
        cat > "${home}/.claude/CLAUDE.md" <<CLAUDE_FILE
# Keep

@RTK.md

## Keep
CLAUDE_FILE
        cat > "${home}/.claude/settings.json" <<CLAUDE_SETTINGS
{"model":"keep","hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"rtk hook claude"}]},{"matcher":"Keep","hooks":[{"type":"command","command":"keep hook"}]}]}}
CLAUDE_SETTINGS

        printf "%s\n" legacy > "${custom_claude}/RTK.md"
        cat > "${custom_claude}/CLAUDE.md" <<CUSTOM_CLAUDE
# Keep

<!-- rtk-instructions v2 -->
managed text
<!-- /rtk-instructions -->

@RTK.md
CUSTOM_CLAUDE

        printf "%s\n" legacy > "${home}/.codex/RTK.md"
        printf "# Keep\\n\\n@%s/.codex/RTK.md\\n" "${home}" > "${home}/.codex/AGENTS.md"
        printf "%s\n" legacy > "${custom_codex}/RTK.md"
        printf "# Keep\\n\\n@%s/RTK.md\\n" "${custom_codex}" > "${custom_codex}/AGENTS.md"

        cat > "${home}/.gemini/GEMINI.md" <<\GEMINI_FILE
# RTK - Rust Token Killer

**Usage**: Token-optimized CLI proxy (cuts up to 90% of bash output)

## Meta Commands (always use rtk directly)

```bash
rtk gain
rtk proxy git status
```

## Installation Verification

```bash
rtk --version
which rtk
```

## Hook-Based Usage

All other commands are automatically rewritten by the Claude Code hook.
Example: `git status` → `rtk git status`
Refer to CLAUDE.md for full command reference.
GEMINI_FILE
        printf "#!/bin/bash\\nexec rtk hook gemini\\n" > "${home}/.gemini/hooks/rtk-hook-gemini.sh"
        printf "%s\n" hash > "${home}/.gemini/hooks/.rtk-hook.sha256"
        cat > "${home}/.gemini/settings.json" <<GEMINI_SETTINGS
{"theme":"keep","hooks":{"BeforeTool":[{"matcher":"run_shell_command","hooks":[{"type":"command","command":"${home}/.gemini/hooks/rtk-hook-gemini.sh"}]},{"matcher":"keep","hooks":[{"type":"command","command":"keep hook"}]}]}}
GEMINI_SETTINGS

        printf "%s\n" plugin > "${home}/.config/opencode/plugins/rtk.ts"
        printf "%s\n" config > "${home}/.config/rtk/config.toml"
        printf "%s\n" log > "${home}/.local/share/rtk/tee/log"
        printf "%s\n" config > "${xdg_config}/rtk/config.toml"
        printf "%s\n" data > "${xdg_data}/rtk/history.db"
        printf "%s\n" keep > "${project}/.rtk/filters.toml"
        printf "%s\n" "BAN_RTK=1" > "${home}/.env.local"

        write_pi_file() {
            local path="$1"
            cat > "${path}" <<\PI_FILE
# Global

## RTK token-optimized commands

- RTK (`rtk-ai/rtk`) is installed by the machine setup scripts when available. Prefer `rtk <command>` for noisy shell commands with supported filters (`git`, `gh`, tests, build/lint tools, package managers, file/search commands) unless full raw output is required.
- Bypass RTK for one command with `RTK_DISABLED=1 <command>` or by running the raw command directly when exact output formatting matters.

## Keep

Keep this.
PI_FILE
        }
        write_pi_file "${home}/.pi/agent/AGENTS.md"
        write_pi_file "${custom_pi}/AGENTS.md"

        export HOME="${home}"
        export CLAUDE_CONFIG_DIR="${custom_claude}"
        export CODEX_HOME="${custom_codex}"
        export PI_CODING_AGENT_DIR="${custom_pi}"
        export XDG_CONFIG_HOME="${xdg_config}"
        export XDG_DATA_HOME="${xdg_data}"
        source <(sed "${SOURCE_WITHOUT_MAIN}" "${SETUP_SCRIPT}")

        remove_rtk_resources
        remove_rtk_resources

        for removed_path in \
            "${home}/.local/bin/rtk" \
            "${home}/.claude/RTK.md" \
            "${home}/.codex/RTK.md" \
            "${home}/.gemini/GEMINI.md" \
            "${home}/.config/opencode/plugins/rtk.ts" \
            "${home}/.config/rtk" \
            "${home}/.local/share/rtk" \
            "${custom_claude}/RTK.md" \
            "${custom_codex}/RTK.md" \
            "${xdg_config}/rtk" \
            "${xdg_data}/rtk"; do
            [[ ! -e "${removed_path}" ]] || { printf "left RTK path: %s\\n" "${removed_path}" >&2; exit 91; }
        done

        ! grep -Eiq "rtk|Rust Token Killer" "${home}/.pi/agent/AGENTS.md"
        ! grep -Eiq "rtk|Rust Token Killer" "${custom_pi}/AGENTS.md"
        grep -q "Keep this" "${home}/.pi/agent/AGENTS.md"
        grep -q "Keep this" "${custom_pi}/AGENTS.md"
        ! grep -Eiq "rtk-instructions|@RTK.md" "${custom_claude}/CLAUDE.md"
        jq -e ".model == \"keep\" and (.hooks.PreToolUse | length == 1) and .hooks.PreToolUse[0].matcher == \"Keep\"" "${home}/.claude/settings.json" > /dev/null
        jq -e ".theme == \"keep\" and (.hooks.BeforeTool | length == 1) and .hooks.BeforeTool[0].matcher == \"keep\"" "${home}/.gemini/settings.json" > /dev/null
        [[ -e "${project}/.rtk/filters.toml" ]]
        grep -q "^BAN_RTK=1$" "${home}/.env.local"
        [[ $(wc -l < "${calls}") -eq 3 ]]
    ' || fail "${file}: RTK fixture cleanup failed"
    rm -rf "${test_root}"
}

for file in "${bash_setup_scripts[@]}"; do
    run_cleanup_fixture "${file}"
done

# Mixed shared content must stop cleanup without deleting the file.
mixed_root=$(mktemp -d)
mkdir -p "${mixed_root}/home/.gemini"
cat > "${mixed_root}/home/.gemini/GEMINI.md" <<'MIXED_GEMINI'
# RTK - Rust Token Killer

## Personal instructions

Keep this user text.
MIXED_GEMINI
SETUP_SCRIPT="${repo_root}/ubuntu.sh" SOURCE_WITHOUT_MAIN="${source_without_main}" TEST_ROOT="${mixed_root}" bash -c '
    set -euo pipefail
    export HOME="${TEST_ROOT}/home"
    source <(sed "${SOURCE_WITHOUT_MAIN}" "${SETUP_SCRIPT}")
    if remove_rtk_resources; then
        exit 90
    fi
    grep -q "Keep this user text" "${HOME}/.gemini/GEMINI.md"
' || fail 'ubuntu.sh: mixed Gemini content was not preserved with a strict failure'
rm -rf "${mixed_root}"

# A user file without RTK text stays in place while the generated hook is removed.
user_gemini_root=$(mktemp -d)
mkdir -p "${user_gemini_root}/home/.gemini/hooks"
printf '# Personal instructions\n\nKeep this user text.\n' > "${user_gemini_root}/home/.gemini/GEMINI.md"
printf '#!/bin/bash\nexec rtk hook gemini\n' > "${user_gemini_root}/home/.gemini/hooks/rtk-hook-gemini.sh"
SETUP_SCRIPT="${repo_root}/ubuntu.sh" SOURCE_WITHOUT_MAIN="${source_without_main}" TEST_ROOT="${user_gemini_root}" bash -c '
    set -euo pipefail
    export HOME="${TEST_ROOT}/home"
    source <(sed "${SOURCE_WITHOUT_MAIN}" "${SETUP_SCRIPT}")
    remove_rtk_resources
    grep -q "Keep this user text" "${HOME}/.gemini/GEMINI.md"
    [[ ! -e "${HOME}/.gemini/hooks/rtk-hook-gemini.sh" ]]
' || fail 'ubuntu.sh: unrelated Gemini instructions were not preserved'
rm -rf "${user_gemini_root}"

# An unrelated executable at the historical binary path stays in place.
foreign_root=$(mktemp -d)
mkdir -p "${foreign_root}/home/.local/bin"
cat > "${foreign_root}/home/.local/bin/rtk" <<'FOREIGN_RTK'
#!/usr/bin/env bash
printf '%s\n' 'Rust Type Kit'
exit 1
FOREIGN_RTK
chmod +x "${foreign_root}/home/.local/bin/rtk"
SETUP_SCRIPT="${repo_root}/ubuntu.sh" SOURCE_WITHOUT_MAIN="${source_without_main}" TEST_ROOT="${foreign_root}" bash -c '
    set -euo pipefail
    export HOME="${TEST_ROOT}/home"
    source <(sed "${SOURCE_WITHOUT_MAIN}" "${SETUP_SCRIPT}")
    remove_rtk_resources
    [[ -x "${HOME}/.local/bin/rtk" ]]
' || fail 'ubuntu.sh: unrelated rtk executable was removed'
rm -rf "${foreign_root}"

printf '✓ RTK retirement contract checks passed\n'
