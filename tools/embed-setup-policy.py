#!/usr/bin/env python3
"""Embed the standalone scheduling layer without loading any setup entry point."""
from pathlib import Path
import argparse

ROOT = Path(__file__).resolve().parents[1]
BASH = ('mac.sh', 'ubuntu.sh', 'pi.sh', 'bazzite.sh', 'wsl.sh')
# Public mutation boundaries with indirect callers. The maintenance caller owns
# every other existing stage; safe_tasks never delegates to that caller.
BASH_GUARDS = (
    'run_setup_tasks', 'ensure_shared_node_runtime', 'bb_package_preflight',
    'setup_bb_server', 'setup_bb_machine', 'prepare_pi_profile_permissions',
    'retire_global_backlog_mcp', 'setup_matt_pocock_skills',
    'install_managed_agent_skill', 'with_bb_dotfiles_umask',
    'setup_dns64_for_ipv6_only', 'setup_tailscale', 'setup_tailscale_ssh',
    'setup_unattended_upgrades', 'create_env_local',
)
PS_GUARDS = (
    'Invoke-WindowsSetupTasks', 'Enable-SharedNodeRuntime',
    'Prepare-PiProfilePermissions', 'Remove-GlobalBacklogMcp',
    'Setup-MattPocockSkills', 'New-TokenPlaceholders',
)


def embed(check=False):
    stale = []
    for name in (*BASH, 'win.ps1'):
        target = ROOT / name
        text = target.read_text()
        is_ps = name.endswith('.ps1')
        policy = (ROOT / 'lib' / ('setup-policy.ps1' if is_ps else 'setup-policy.bash')).read_text().rstrip()
        begin = '# BEGIN SETUP NON-DISRUPTION POLICY'
        end = '# END SETUP NON-DISRUPTION POLICY'
        block = begin + '\n' + policy + '\n' + end
        if begin in text:
            first = text.index(begin)
            last = text.index(end, first) + len(end)
            updated = text[:first] + block + text[last:]
        else:
            marker = '# Create consolidated environment file' if is_ps else 'SETUP_ORIGINAL_PATH='
            index = text.index(marker)
            updated = text[:index] + block + '\n\n' + text[index:]
        for function in (PS_GUARDS if is_ps else BASH_GUARDS):
            header = f'function {function} {{\n' if is_ps else f'{function}() {{\n'
            guard = (f"    Assert-SetupMaintenance '{function}'\n" if is_ps else
                     f"    setup_require_maintenance '{function}' || return $?\n")
            if header in updated and header + guard not in updated:
                updated = updated.replace(header, header + guard, 1)
        if updated != text:
            stale.append(name)
            if not check:
                target.write_text(updated)
    if check and stale:
        raise SystemExit('Stale setup policy: ' + ', '.join(stale))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    embed(parser.parse_args().check)
