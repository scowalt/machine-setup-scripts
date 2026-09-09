#!/usr/bin/env bash
# Version 2 | Last changed: Stop restoring Pi prose
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "${repo_root}"

fail() { printf '✗ %s\n' "$1" >&2; exit 1; }

for file in mac.sh ubuntu.sh wsl.sh pi.sh bazzite.sh win.ps1; do
    if grep -Eq 'pi-prose|pi_prose|PiProse|matter-of-fact' "${file}"; then
        fail "${file}: Pi prose installation or default automation remains"
    fi
    [[ "${file}" == win.ps1 ]] && continue
    bash -n "${file}"
    test_root=$(mktemp -d)
    SETUP_SCRIPT="${repo_root}/${file}" HOME="${test_root}/home" \
        PI_CODING_AGENT_DIR="${test_root}/custom-agent" bash -c '
            source <(sed '\''s/^main "\$@"$/:/'\'' "${SETUP_SCRIPT}")
            npm() { :; }
            pi() { printf "npm:pi-web-access\n"; }
            setup_pi_companion_packages > /dev/null
            [[ ! -e "${HOME}/.pi/agent/prose" ]]
            [[ ! -e "${PI_CODING_AGENT_DIR}/prose" ]]
            for agent_dir in "${HOME}/.pi/agent" "${PI_CODING_AGENT_DIR}"; do
                mkdir -p "${agent_dir}/prose"
                printf "custom style\n" > "${agent_dir}/prose/custom.md"
                for payload in '\''{"default":"custom"}'\'' '\''{}'\'' '\''{broken'\''; do
                    printf "%s\n" "${payload}" > "${agent_dir}/prose/config.json"
                    cp "${agent_dir}/prose/config.json" "${agent_dir}/before.json"
                    setup_pi_companion_packages > /dev/null
                    cmp "${agent_dir}/before.json" "${agent_dir}/prose/config.json"
                    grep -Fxq "custom style" "${agent_dir}/prose/custom.md"
                done
            done
        '
    rm -rf "${test_root}"
done

grep -Fq 'Setup does not reinstall' README.md || fail 'README.md: missing no-restoration policy'
grep -Fq 'Preserve existing custom prose files' CLAUDE.md || fail 'CLAUDE.md: missing preservation policy'
printf '✓ Setup leaves removed Pi prose and custom prose files alone\n'
