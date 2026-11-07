#!/usr/bin/env python3
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SYSTEM_PATH = '/usr/bin:/bin'
TOOLS = {'node': 'SETUP_TEST_NODE', 'pwsh': 'PWSH_BIN',
         'mise': 'SETUP_TEST_MISE', 'chezmoi': 'SETUP_TEST_CHEZMOI',
         'bun': 'SETUP_TEST_BUN'}
DIRECT_SUITES = ('test_fixture_containment.py', 'test_run_contracts.py',
                 'test_macos_clt.py', 'test_homebrew_results.py',
                 'test_managed_skill_suite.py')
DEDICATED_JOBS = {'tests/impeccable-skill-contract.sh': 5, 'tests/pi-package-maintenance-contract.sh': 3,
                  'tests/bb-server-contract.sh': 4, 'tests/opencode-cli-contract.sh': 2,
                  'tests/pi-visual-explainer-contract.sh': 2, 'tests/impeccable-callers-contract.sh': 3,
                  'tests/bb-machine-preparation-contract.sh': 3, 'tests/shared-node-runtime-contract.sh': 1,
                  'tests/setup-reliability-contract.sh': 1, 'tests/pi-opencode-go-contract.sh': 1,
                  'tests/weekly-log-audit-regressions.sh': 1, 'tests/bb-desktop-contract.sh': 1,
                  'tests/test_managed_skill_suite.py': 1}
BATCHES = 4
BATCH_SECONDS = {'tests/backlog-mcp-retirement-contract.sh': 30, 'tests/pi-profile-permissions-contract.sh': 28,
                 'tests/test_fixture_containment.py': 23, 'tests/headless-contract.sh': 22,
                 'tests/infisical-non-management-contract.sh': 21, 'tests/bb-pi-trust-contract.sh': 19,
                 'tests/simple-english-skill-contract.sh': 16, 'tests/attention-span-removal-contract.sh': 13,
                 'tests/directory-trust-integration-contract.sh': 13, 'tests/bb-plugin-refresh-contract.sh': 9,
                 'tests/opencode-go-wiring-contract.sh': 9, 'tests/ai-coding-agent-contract.sh': 8,
                 'tests/bash-compatibility-contract.sh': 8, 'tests/pi-prose-contract.sh': 7,
                 'tests/rtk-removal-contract.sh': 7, 'tests/windows-log-upload-contract.sh': 7,
                 'tests/gitea-client-installation-contract.sh': 6, 'tests/pi-model-defaults-contract.sh': 6,
                 'tests/pi-rpiv-removal-contract.sh': 6, 'tests/pi-skill-ownership-contract.sh': 6}
UNMEASURED_SECONDS = 2


def native_tool(name, value):
    selected = value or shutil.which(name, path=SYSTEM_PATH)
    if not selected or not Path(selected).is_absolute():
        raise ValueError(f'{name}: set {TOOLS[name]} to an existing absolute native executable (not a shim)')
    try:
        path = Path(selected).resolve(strict=True)
        if not path.is_file() or not os.access(path, os.X_OK):
            raise ValueError
        with path.open('rb') as source:
            if source.read(4) != b'\x7fELF':
                raise ValueError
    except (OSError, ValueError, RuntimeError):
        raise ValueError(f'{name}: {TOOLS[name]} must select an executable Linux ELF binary, not a shim') from None
    return path


def suites():
    shell = sorted(ROOT.joinpath('tests').glob('*.sh'))
    if not shell:
        raise ValueError('no shell contracts found; refusing an empty contract run')
    selected = [ROOT / 'tests' / name for name in DIRECT_SUITES] + shell
    if any(p.is_symlink() or not p.is_file() for p in selected):
        raise ValueError('contract inventory contains a missing or linked entry')
    inventory = [str(p.relative_to(ROOT)) for p in selected]
    if not set(DEDICATED_JOBS) <= set(inventory):
        raise ValueError('dedicated job suite missing from the contract inventory')
    if not set(BATCH_SECONDS) <= set(inventory) - set(DEDICATED_JOBS):
        raise ValueError('measured batch suite missing from the batched inventory')
    return inventory


def batches(inventory):
    batched = [suite for suite in inventory if suite not in DEDICATED_JOBS]
    groups = [[] for _ in range(BATCHES)]
    seconds = [0] * BATCHES
    for suite in sorted(batched, key=lambda suite: -BATCH_SECONDS.get(suite, UNMEASURED_SECONDS)):
        index = seconds.index(min(seconds))
        groups[index].append(suite)
        seconds[index] += BATCH_SECONDS.get(suite, UNMEASURED_SECONDS)
    return {f'batch:{index}/{BATCHES}': sorted(group, key=batched.index) for index, group in enumerate(groups, 1)}


def jobs(inventory):
    dedicated = [suite if count == 1 else f'{suite}:{index}/{count}'
                 for suite, count in DEDICATED_JOBS.items() for index in range(1, count + 1)]
    return dedicated + list(batches(inventory))


def main(argv=None):
    parser = argparse.ArgumentParser(description='Version 6: run the contract inventory, or selected suites, suite:i/n shards or batch:i/n groups from it, with bounded 900-second suite deadlines through mandatory containment.\n\nInvoked by the Contracts workflow under env -i and Python isolated mode. Tool arguments\nselect existing native executables only; never invoke a shim/package manager to find or\ninstall them. See --help for explicit selections when system tools are absent.\n')
    for name, variable in TOOLS.items():
        parser.add_argument('--' + name, default='', help=f'native {name}; override: {variable}; default: {SYSTEM_PATH}')
    parser.add_argument('--list', action='store_true', help='print the CI jobs as a JSON array and exit: slow suites alone or split into shards, the rest in batches')
    parser.add_argument('suite', nargs='*', help='inventory entries to run; default: all')
    args = parser.parse_args(argv)
    try:
        inventory = suites()
    except ValueError as error:
        parser.error(str(error))
    if args.list:
        print(json.dumps(jobs(inventory)))
        return 0
    unknown = [suite for suite in args.suite if suite not in inventory + jobs(inventory)]
    if unknown:
        parser.error('not in the contract inventory: ' + ', '.join(unknown))
    selected = [suite for entry in args.suite for suite in batches(inventory).get(entry, [entry])] or inventory
    if os.uname().sysname != 'Linux':
        parser.error('Linux kernel containment required; use a Linux validation host, never run fixtures directly')
    try:
        tools = {name: native_tool(name, getattr(args, name)) for name in TOOLS}
    except ValueError as error:
        parser.error(str(error))
    with tempfile.TemporaryDirectory(prefix='setup-contract-tools-', dir='/tmp') as directory:
        tool_dir = Path(directory)
        for name in ('mise', 'chezmoi', 'bun'):
            (tool_dir / name).symlink_to(tools[name])
        command = ['/usr/bin/python3', '-I', str(ROOT / 'tests/run-fixture-matrix.py'),
                   '--node', str(tools['node']), '--pwsh', str(tools['pwsh']),
                   '--tool-path', SYSTEM_PATH + ':' + directory, '--timeout', '900', *selected]
        try:
            return subprocess.call(command, cwd=ROOT, env={'PATH': SYSTEM_PATH},
                                   stdin=subprocess.DEVNULL, close_fds=True)
        except OSError:
            print('Contained contract runner could not start; check /usr/bin/python3 and existing native tools.', flush=True)
            return 125


if __name__ == '__main__':
    raise SystemExit(main())
