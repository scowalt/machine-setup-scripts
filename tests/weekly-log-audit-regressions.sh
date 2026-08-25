#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "${repo_root}"

bash_setup_scripts=(mac.sh ubuntu.sh wsl.sh pi.sh bazzite.sh)
apt_setup_scripts=(ubuntu.sh wsl.sh pi.sh)
dotfiles_setup_scripts=(mac.sh ubuntu.sh wsl.sh pi.sh bazzite.sh)
matt_setup_scripts=(mac.sh ubuntu.sh wsl.sh pi.sh bazzite.sh)
source_without_main='s/^main "\$@"$/:/'

fail() {
    printf '✗ %s\n' "$1" >&2
    exit 1
}

assert_contains() {
    local file=$1
    local pattern=$2
    local description=$3

    grep -Eq "${pattern}" "${file}" || fail "${file}: missing ${description}"
}

assert_not_contains() {
    local file=$1
    local pattern=$2
    local description=$3

    if grep -Eq "${pattern}" "${file}"; then
        fail "${file}: unexpectedly contains ${description}"
    fi
}

# macOS must converge on the canonical Tailscale cask token and remove every
# formula version before reporting a successful migration.
tailscale_tmp=$(mktemp -d)
tailscale_output=$(SETUP_SCRIPT="${repo_root}/mac.sh" SOURCE_WITHOUT_MAIN="${source_without_main}" \
    CALL_LOG="${tailscale_tmp}/calls" bash -c '
        source <(sed "${SOURCE_WITHOUT_MAIN}" "${SETUP_SCRIPT}")
        formula_installed=1
        cask_installed=0
        brew() {
            printf "%s\n" "$*" >> "${CALL_LOG}"
            case "$*" in
                "list --formula tailscale") [[ "${formula_installed}" -eq 1 ]] ;;
                "services stop tailscale") return 0 ;;
                "uninstall --formula --force tailscale") formula_installed=0 ;;
                "list --cask tailscale-app") [[ "${cask_installed}" -eq 1 ]] ;;
                "install --cask tailscale-app") cask_installed=1 ;;
                *) return 90 ;;
            esac
        }
        pgrep() { return 0; }
        setup_tailscale
        setup_tailscale
    ')
[[ "$(grep -c '^uninstall --formula --force tailscale$' "${tailscale_tmp}/calls" || true)" -eq 1 ]] || fail 'mac.sh: Tailscale formula migration was not one-time and forceful'
[[ "$(grep -c '^install --cask tailscale-app$' "${tailscale_tmp}/calls" || true)" -eq 1 ]] || fail 'mac.sh: canonical Tailscale cask installation was not idempotent'
grep -q 'Tailscale cask installed' <<< "${tailscale_output}" || fail 'mac.sh: successful canonical Tailscale cask install was not reported'
rm -rf "${tailscale_tmp}"

# Setup owns explicit package installers; it must not blanket-update npm (and
# npm itself) after validating Pi. npm configuration is repaired before Pi
# performs its first npm mutation.
for file in "${bash_setup_scripts[@]}"; do
    assert_not_contains "${file}" 'npm update -g' 'blanket global npm update'
    assert_contains "${file}" '^ensure_npm_configuration\(\)' 'npm configuration preflight helper'
    assert_contains "${file}" 'ensure_npm_configuration.*\|\|.*return 1' 'fatal npm configuration preflight before Pi mutation'
    npm_preflight_line=$(grep -nF '    ensure_npm_configuration || return 1' "${file}" | cut -d: -f1)
    npm_mutation_line=$(grep -n 'npm uninstall -g --prefix' "${file}" | head -n 1 | cut -d: -f1)
    [[ "${npm_preflight_line}" -lt "${npm_mutation_line}" ]] || fail "${file}: npm mutation occurs before configuration preflight"
done
assert_not_contains win.ps1 'npm update -g' 'blanket global npm update'
assert_contains win.ps1 '^function Repair-NpmConfiguration' 'PowerShell npm configuration preflight helper'
assert_contains win.ps1 'if \(-not \(Repair-NpmConfiguration\)\)' 'PowerShell npm preflight before Pi mutation'

# Pi setup failure must be observable at the entry point and cannot end with a
# green success banner.
for file in mac.sh ubuntu.sh wsl.sh pi.sh; do
    assert_contains "${file}" 'Setup completed with errors' 'degraded completion warning'
done
assert_contains win.ps1 'Required Pi coding agent setup failed' 'fatal required Pi failure'

# Matt Pocock's current inventory replaced diagnose with diagnosing-bugs and
# retired zoom-out. Legacy copies remain explicitly tracked for safe cleanup.
for file in "${matt_setup_scripts[@]}"; do
    assert_contains "${file}" '^[[:space:]]*diagnosing-bugs([[:space:]\\]*$)?' 'current diagnosing-bugs skill'
    assert_contains "${file}" '^matt_pocock_obsolete_skills\(\)' 'obsolete Matt Pocock skill inventory'
    assert_contains "${file}" '^setup_matt_pocock_skills\(\)' 'Pi and Codex Matt Pocock installer'
    assert_contains "${file}" '.*--agent pi --agent codex --copy --yes' 'Pi and Codex skills CLI targets'
    assert_contains "${file}" '^[[:space:]]*diagnose([[:space:]\\]*$)?' 'legacy diagnose cleanup entry'
    assert_contains "${file}" '^[[:space:]]*zoom-out([[:space:]\\]*$)?' 'legacy zoom-out cleanup entry'
    if sed -n '/^matt_pocock_skills_disabled()/,/^}/p' "${file}" | grep -q 'WORK_MACHINE'; then
        fail "${file}: WORK_MACHINE still disables Matt Pocock skills"
    fi
    if sed -n '/^setup_matt_pocock_skills()/,/^}/p' "${file}" | grep -Eq 'command -v pi|ensure_pi_node_runtime'; then
        fail "${file}: Matt Pocock setup still depends on the Pi executable"
    fi
done
assert_contains win.ps1 '"diagnosing-bugs"' 'current PowerShell diagnosing-bugs skill'
assert_contains win.ps1 '^function Setup-MattPocockSkills' 'PowerShell Pi and Codex Matt Pocock installer'
assert_contains win.ps1 '"--agent", "codex"' 'PowerShell Codex target'
# shellcheck disable=SC2016 # Preserve literal PowerShell variable syntax.
assert_contains win.ps1 '\$obsoleteSkills[[:space:]]*=' 'PowerShell obsolete skill inventory'
if sed -n '/^function Test-MattPocockSkillsDisabled/,/^}/p' win.ps1 | grep -q 'WORK_MACHINE'; then
    fail 'win.ps1: WORK_MACHINE still disables Matt Pocock skills'
fi
if sed -n '/^function Setup-MattPocockSkills/,/^}/p' win.ps1 | grep -Eq 'Get-Command pi|Enable-PiNodeRuntime'; then
    fail 'win.ps1: Matt Pocock setup still depends on the Pi executable'
fi

# Successful skill provisioning removes only obsolete setup-managed names and
# converges on a second run for Pi and Codex.
for file in "${matt_setup_scripts[@]}"; do
    matt_tmp=$(mktemp -d)
    default_pi_skills="${matt_tmp}/home/.pi/agent/skills"
    codex_skills="${matt_tmp}/home/.agents/skills"
    custom_pi_skills="${matt_tmp}/custom-pi/skills"
    codex_home="${matt_tmp}/codex-home"
    mkdir -p "${default_pi_skills}" "${codex_skills}" "${custom_pi_skills}" "${matt_tmp}/obsolete-target"
    touch "${matt_tmp}/obsolete-target/sentinel"
    for skills_dir in "${default_pi_skills}" "${codex_skills}" "${custom_pi_skills}"; do
        mkdir -p "${skills_dir}/keep-me" "${skills_dir}/diagnose"
        touch "${skills_dir}/keep-me/SKILL.md" "${skills_dir}/diagnose/SKILL.md"
        ln -s "${matt_tmp}/obsolete-target" "${skills_dir}/zoom-out"
    done

    SETUP_SCRIPT="${repo_root}/${file}" SOURCE_WITHOUT_MAIN="${source_without_main}" \
        HOME="${matt_tmp}/home" CODEX_HOME="${codex_home}" PI_CODING_AGENT_DIR="${matt_tmp}/custom-pi" \
        WORK_MACHINE=1 CALL_LOG="${matt_tmp}/calls" bash -c '
            source <(sed "${SOURCE_WITHOUT_MAIN}" "${SETUP_SCRIPT}")
            ensure_skills_cli_node_runtime() { return 0; }
            npx() {
                printf "%s\n" "$*" >> "${CALL_LOG}"
                local skill skills_dir
                for skills_dir in "${HOME}/.pi/agent/skills" "${HOME}/.agents/skills"; do
                    for skill in setup-matt-pocock-skills diagnosing-bugs tdd improve-codebase-architecture grill-with-docs; do
                        mkdir -p "${skills_dir}/${skill}"
                        printf "%s\n" "---" "name: ${skill}" "---" > "${skills_dir}/${skill}/SKILL.md"
                    done
                done
            }
            setup_matt_pocock_skills > /dev/null
            setup_matt_pocock_skills > /dev/null
        '
    expected_args='--yes skills@latest add mattpocock/skills --global --agent pi --agent codex --copy --yes --skill setup-matt-pocock-skills --skill diagnosing-bugs --skill tdd --skill improve-codebase-architecture --skill grill-with-docs'
    call_count=$(wc -l < "${matt_tmp}/calls")
    [[ "${call_count}" -eq 2 ]] || fail "${file}: installer did not update on both setup runs"
    if grep -Fvx -- "${expected_args}" "${matt_tmp}/calls" > /dev/null; then
        fail "${file}: installer used unexpected arguments"
    fi
    for skills_dir in "${default_pi_skills}" "${codex_skills}" "${custom_pi_skills}"; do
        for skill in setup-matt-pocock-skills diagnosing-bugs tdd improve-codebase-architecture grill-with-docs; do
            [[ -f "${skills_dir}/${skill}/SKILL.md" ]] || fail "${file}: missing ${skill} in ${skills_dir}"
            [[ ! -L "${skills_dir}/${skill}" ]] || fail "${file}: ${skill} is a symlink in ${skills_dir}"
        done
        [[ -f "${skills_dir}/keep-me/SKILL.md" ]] || fail "${file}: setup removed a sibling skill from ${skills_dir}"
        [[ ! -e "${skills_dir}/diagnose" && ! -L "${skills_dir}/zoom-out" ]] || fail "${file}: obsolete Matt Pocock skills survived in ${skills_dir}"
    done
    [[ ! -e "${codex_home}/skills/setup-matt-pocock-skills" ]] || fail "${file}: installer used CODEX_HOME instead of the canonical shared path"
    [[ -f "${matt_tmp}/obsolete-target/sentinel" ]] || fail "${file}: obsolete skill cleanup followed a symlink target"
    rm -rf "${matt_tmp}"
done

# Both supported ban spellings remove only managed names from Pi and Codex.
for file in "${matt_setup_scripts[@]}"; do
    for ban_name in BAN_MATT_POCOCK_SKILLS BAN_MATT_POCKOCK_SKILLS; do
        matt_tmp=$(mktemp -d)
        default_pi_skills="${matt_tmp}/home/.pi/agent/skills"
        codex_skills="${matt_tmp}/home/.agents/skills"
        custom_pi_skills="${matt_tmp}/custom-pi/skills"
        mkdir -p "${default_pi_skills}" "${codex_skills}" "${custom_pi_skills}" "${matt_tmp}/managed-target"
        touch "${matt_tmp}/managed-target/sentinel"
        for skills_dir in "${default_pi_skills}" "${codex_skills}" "${custom_pi_skills}"; do
            mkdir -p "${skills_dir}/keep-me"
            touch "${skills_dir}/keep-me/SKILL.md"
            for skill in setup-matt-pocock-skills diagnosing-bugs improve-codebase-architecture grill-with-docs diagnose zoom-out; do
                mkdir -p "${skills_dir}/${skill}"
                touch "${skills_dir}/${skill}/SKILL.md"
            done
            ln -s "${matt_tmp}/managed-target" "${skills_dir}/tdd"
        done

        # shellcheck disable=SC2016 # Expand these variables in the child shell.
        env "${ban_name}=1" SETUP_SCRIPT="${repo_root}/${file}" SOURCE_WITHOUT_MAIN="${source_without_main}" \
            HOME="${matt_tmp}/home" PI_CODING_AGENT_DIR="${matt_tmp}/custom-pi" CALL_LOG="${matt_tmp}/calls" bash -c '
                source <(sed "${SOURCE_WITHOUT_MAIN}" "${SETUP_SCRIPT}")
                npx() { printf "%s\n" unexpected >> "${CALL_LOG}"; return 90; }
                ensure_skills_cli_node_runtime() { return 90; }
                setup_matt_pocock_skills > /dev/null
                setup_matt_pocock_skills > /dev/null
            '

        for skills_dir in "${default_pi_skills}" "${codex_skills}" "${custom_pi_skills}"; do
            for skill in setup-matt-pocock-skills diagnosing-bugs tdd improve-codebase-architecture grill-with-docs diagnose zoom-out; do
                [[ ! -e "${skills_dir}/${skill}" && ! -L "${skills_dir}/${skill}" ]] || fail "${file}: ${ban_name} left ${skill} in ${skills_dir}"
            done
            [[ -f "${skills_dir}/keep-me/SKILL.md" ]] || fail "${file}: ${ban_name} removed a sibling skill"
        done
        [[ -f "${matt_tmp}/managed-target/sentinel" ]] || fail "${file}: ${ban_name} cleanup followed a symlink target"
        [[ ! -e "${matt_tmp}/calls" ]] || fail "${file}: ${ban_name} still ran the installer"
        rm -rf "${matt_tmp}"
    done
done

# Ubuntu tmux service setup must reach a lingering user manager even when the
# ordinary login-session D-Bus path is unavailable.
tmux_tmp=$(mktemp -d)
mkdir -p "${tmux_tmp}/home/.config/systemd/user"
touch "${tmux_tmp}/home/.config/systemd/user/tmux.service"
tmux_output=$(SETUP_SCRIPT="${repo_root}/ubuntu.sh" SOURCE_WITHOUT_MAIN="${source_without_main}" \
    HOME="${tmux_tmp}/home" CALL_LOG="${tmux_tmp}/calls" bash -c '
        source <(sed "${SOURCE_WITHOUT_MAIN}" "${SETUP_SCRIPT}")
        service_active=0
        id() { [[ "$1" == "-u" ]] && printf "%s\n" 1001; }
        whoami() { printf "%s\n" tester; }
        systemctl() {
            if [[ "$1" == "--user" ]]; then
                return 1
            fi
            [[ "$1" == "--machine=tester@" && "$2" == "--user" ]] || return 90
            shift 2
            printf "%s\n" "$*" >> "${CALL_LOG}"
            case "$1" in
                daemon-reload|enable) return 0 ;;
                is-enabled) return 0 ;;
                is-active) [[ "${service_active}" -eq 1 ]] ;;
                start) service_active=1 ;;
                restart) return 91 ;;
            esac
        }
        enable_tmux_service
    ')
grep -q '^daemon-reload$' "${tmux_tmp}/calls" || fail 'ubuntu.sh: tmux daemon reload did not use the user-manager fallback'
grep -q '^enable tmux.service$' "${tmux_tmp}/calls" || fail 'ubuntu.sh: tmux enable did not use the user-manager fallback'
grep -q '^start tmux.service$' "${tmux_tmp}/calls" || fail 'ubuntu.sh: tmux start did not use the user-manager fallback'
if grep -q '^restart ' "${tmux_tmp}/calls"; then
    fail 'ubuntu.sh: tmux fallback restarted an existing service'
fi
grep -q 'tmux service started' <<< "${tmux_output}" || fail 'ubuntu.sh: tmux fallback success was not reported'
rm -rf "${tmux_tmp}"

# Formatted Tailscale preference JSON must be idempotent, and a mutation is not
# successful until the resulting RunSSH state verifies as true.
for file in ubuntu.sh pi.sh; do
    tailscale_pref_tmp=$(mktemp -d)
    tailscale_pref_output=$(SETUP_SCRIPT="${repo_root}/${file}" SOURCE_WITHOUT_MAIN="${source_without_main}" \
        CALL_LOG="${tailscale_pref_tmp}/calls" bash -c '
            source <(sed "${SOURCE_WITHOUT_MAIN}" "${SETUP_SCRIPT}")
            TAILSCALE_ENABLED=true
            tailscale() {
                if [[ "$1 $2" == "debug prefs" ]]; then
                    printf "{\n  \"RunSSH\": %s\n}\n" "${TAILSCALE_ENABLED}"
                elif [[ "$1 $2" == "set --ssh" ]]; then
                    printf "%s\n" mutation >> "${CALL_LOG}"
                    TAILSCALE_ENABLED=true
                fi
            }
            sudo() { shift; tailscale "$@"; }
            setup_tailscale_ssh
        ')
    [[ ! -e "${tailscale_pref_tmp}/calls" ]] || fail "${file}: formatted true RunSSH preference triggered a mutation"
    grep -q 'Tailscale SSH is already enabled' <<< "${tailscale_pref_output}" || fail "${file}: formatted true RunSSH preference was not recognized"

    tailscale_pref_output=$(SETUP_SCRIPT="${repo_root}/${file}" SOURCE_WITHOUT_MAIN="${source_without_main}" \
        CALL_LOG="${tailscale_pref_tmp}/calls" bash -c '
            source <(sed "${SOURCE_WITHOUT_MAIN}" "${SETUP_SCRIPT}")
            TAILSCALE_ENABLED=false
            can_sudo() { return 0; }
            tailscale() {
                if [[ "$1 $2" == "debug prefs" ]]; then
                    printf "{\n  \"RunSSH\": %s\n}\n" "${TAILSCALE_ENABLED}"
                elif [[ "$1 $2" == "set --ssh" ]]; then
                    printf "%s\n" mutation >> "${CALL_LOG}"
                    TAILSCALE_ENABLED=true
                fi
            }
            sudo() { shift; tailscale "$@"; }
            setup_tailscale_ssh
        ')
    mutation_count=$(grep -c '^mutation$' "${tailscale_pref_tmp}/calls" || true)
    [[ "${mutation_count}" -eq 1 ]] || fail "${file}: disabled RunSSH was not mutated exactly once"
    grep -q 'Tailscale SSH enabled' <<< "${tailscale_pref_output}" || fail "${file}: verified RunSSH mutation lacked success"
    rm -rf "${tailscale_pref_tmp}"
done

# A successful `tailscale set` is still a failure if the preference does not
# actually change.
if SETUP_SCRIPT="${repo_root}/ubuntu.sh" SOURCE_WITHOUT_MAIN="${source_without_main}" bash -c '
    source <(sed "${SOURCE_WITHOUT_MAIN}" "${SETUP_SCRIPT}")
    can_sudo() { return 0; }
    tailscale() {
        [[ "$1 $2" == "debug prefs" ]] && printf "%s\n" "{ \"RunSSH\": false }"
        return 0
    }
    sudo() { shift; tailscale "$@"; }
    setup_tailscale_ssh
' > /tmp/tailscale-unverified.out 2>&1; then
    fail 'ubuntu.sh: unverified Tailscale SSH mutation returned success'
fi
grep -q 'RunSSH is still disabled' /tmp/tailscale-unverified.out || fail 'ubuntu.sh: unverified Tailscale SSH mutation lacked diagnosis'
rm -f /tmp/tailscale-unverified.out

# Reconcile the chezmoi remote in both directions and restore the deploy-key
# alias after the final apply that can overwrite ~/.ssh/config.
dotfiles_tmp=$(mktemp -d)
mkdir -p "${dotfiles_tmp}/home/.local/share/chezmoi/.git" "${dotfiles_tmp}/home/.ssh"
touch "${dotfiles_tmp}/home/.ssh/id_rsa" "${dotfiles_tmp}/home/.ssh/id_rsa.pub"
dotfiles_output=$(SETUP_SCRIPT="${repo_root}/ubuntu.sh" SOURCE_WITHOUT_MAIN="${source_without_main}" \
    HOME="${dotfiles_tmp}/home" bash -c '
        source <(sed "${SOURCE_WITHOUT_MAIN}" "${SETUP_SCRIPT}")
        remote="git@github-dotfiles:scowalt/dotfiles.git"
        has_verified_ssh_key() { return 0; }
        ssh() { printf "%s\n" "Hi scowalt! You have successfully authenticated"; }
        git() {
            if [[ "$*" == *"remote get-url origin" ]]; then
                printf "%s\n" "${remote}"
            elif [[ "$*" == *"remote set-url origin git@github.com:scowalt/dotfiles.git" ]]; then
                remote="git@github.com:scowalt/dotfiles.git"
            else
                return 90
            fi
        }
        fix_chezmoi_remote_for_deploy_key
        printf "remote=%s\n" "${remote}"
    ')
grep -q '^remote=git@github.com:scowalt/dotfiles.git$' <<< "${dotfiles_output}" || fail 'ubuntu.sh: personal SSH key did not restore the direct chezmoi remote'
rm -rf "${dotfiles_tmp}"

# Comments and similarly prefixed hosts must not masquerade as the actual SSH
# alias restored after chezmoi applies dotfiles.
alias_tmp=$(mktemp -d)
mkdir -p "${alias_tmp}/home/.ssh"
printf '%s\n' '# Host github-dotfiles' 'Host github-dotfiles-old' > "${alias_tmp}/home/.ssh/config"
SETUP_SCRIPT="${repo_root}/ubuntu.sh" SOURCE_WITHOUT_MAIN="${source_without_main}" HOME="${alias_tmp}/home" bash -c '
    source <(sed "${SOURCE_WITHOUT_MAIN}" "${SETUP_SCRIPT}")
    bootstrap_ssh_config > /dev/null
'
awk 'tolower($1) == "host" { for (i=2; i<=NF; i++) if ($i == "github-dotfiles") found=1 } END { exit !found }' "${alias_tmp}/home/.ssh/config" || fail 'ubuntu.sh: exact github-dotfiles alias was not restored'
rm -rf "${alias_tmp}"

# Initial cloning must use the exact access method that was verified rather
# than inferring credentials again from username or public-key registration.
for file in "${dotfiles_setup_scripts[@]}"; do
    for method in ssh token deploy; do
        init_tmp=$(mktemp -d)
        mkdir -p "${init_tmp}/home"
        SETUP_SCRIPT="${repo_root}/${file}" SOURCE_WITHOUT_MAIN="${source_without_main}" \
            HOME="${init_tmp}/home" METHOD="${method}" CALL_LOG="${init_tmp}/calls" bash -c '
                source <(sed "${SOURCE_WITHOUT_MAIN}" "${SETUP_SCRIPT}")
                DOTFILES_ACCESS_METHOD="${METHOD}"
                chezmoi() { printf "%s\n" "$*" > "${CALL_LOG}"; }
                initialize_chezmoi > /dev/null
            '
        case "${method}" in
            ssh)
                grep -q '^init --apply --force scowalt/dotfiles --ssh$' "${init_tmp}/calls" || fail "${file}: verified SSH method was not used for initial clone"
                ;;
            token)
                grep -q '^init --apply --force https://github.com/scowalt/dotfiles.git$' "${init_tmp}/calls" || fail "${file}: verified token method was not used for initial clone"
                ;;
            deploy)
                grep -q '^init --apply --force git@github-dotfiles:scowalt/dotfiles.git$' "${init_tmp}/calls" || fail "${file}: verified deploy-key method was not used for initial clone"
                ;;
            *)
                fail "Unexpected dotfiles access method in regression test: ${method}"
                ;;
        esac
        rm -rf "${init_tmp}"
    done
    assert_contains "${file}" 'if ! initialize_chezmoi; then' 'propagated chezmoi initialization failure'
done

for file in "${dotfiles_setup_scripts[@]}"; do
    if [[ "${file}" == "pi.sh" ]]; then
        apply_line=$(grep -n 'apply_chezmoi_config' "${file}" | tail -n 1 | cut -d: -f1)
    else
        apply_line=$(grep -n 'chezmoi apply --force' "${file}" | tail -n 1 | cut -d: -f1)
    fi
    bootstrap_line=$(grep -n '^[[:space:]]*bootstrap_ssh_config$' "${file}" | tail -n 1 | cut -d: -f1)
    [[ -n "${apply_line}" && -n "${bootstrap_line}" && "${bootstrap_line}" -gt "${apply_line}" ]] || fail "${file}: github-dotfiles alias is not restored after the final chezmoi apply"
done

# Safe apt upgrades may add dependencies but not remove packages, and residual
# kept-back packages must be surfaced instead of an unconditional success.
for file in "${apt_setup_scripts[@]}"; do
    assert_contains "${file}" 'upgrade --with-new-pkgs' 'safe apt upgrade with new dependencies'
    assert_not_contains "${file}" '(dist-upgrade|full-upgrade)' 'package-removing apt upgrade policy'
done

apt_tmp=$(mktemp -d)
apt_output=$(SETUP_SCRIPT="${repo_root}/ubuntu.sh" SOURCE_WITHOUT_MAIN="${source_without_main}" \
    CALL_LOG="${apt_tmp}/calls" bash -c '
        source <(sed "${SOURCE_WITHOUT_MAIN}" "${SETUP_SCRIPT}")
        can_sudo() { return 0; }
        dpkg() { return 0; }
        apt-mark() { [[ "$1" == "showhold" ]] && return 0; }
        sudo() {
            printf "%s\n" "$*" >> "${CALL_LOG}"
            if [[ "$*" == *"upgrade --with-new-pkgs"* ]]; then
                printf "%s\n" \
                    "The following upgrades have been deferred due to phasing:" \
                    "  python3-software-properties" \
                    "The following packages have been kept back:" \
                    "  linux-generic linux-image-generic" \
                    "0 upgraded, 0 newly installed, 0 to remove and 3 not upgraded."
            fi
            return 0
        }
        update_dependencies
    ')
grep -q 'Packages remain kept back after upgrade: python3-software-properties linux-generic linux-image-generic' <<< "${apt_output}" || fail 'ubuntu.sh: residual phased/kept-back packages lacked an actionable warning'
if grep -q 'System packages updated' <<< "${apt_output}"; then
    fail 'ubuntu.sh: residual kept-back packages were reported as a complete update'
fi
grep -q 'apt-mark unhold tmux' "${apt_tmp}/calls" || fail 'ubuntu.sh: tmux was not unheld after apt upgrade'
rm -rf "${apt_tmp}"

printf '✓ Weekly log audit regression checks passed\n'
