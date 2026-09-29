"""Explicit maintenance authorization for inert, extracted legacy fixtures only.

Never import into setup. This does not run setup, modify trust checks, or stub the
policy open. The default-policy suite exercises refusal and state isolation.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def bash_maintenance():
    return ((ROOT / 'lib/setup-policy.bash').read_text() +
            '\nunset BB_THREAD_ID BB_ENVIRONMENT_ID BB_TERMINAL_ID\n'
            'setup_policy_init --maintenance || exit 98\n')


def powershell_maintenance():
    return ((ROOT / 'lib/setup-policy.ps1').read_text() +
            '\n$env:BB_THREAD_ID=$null; $env:BB_ENVIRONMENT_ID=$null; $env:BB_TERMINAL_ID=$null\n'
            'Initialize-SetupPolicy -Maintenance\n')
