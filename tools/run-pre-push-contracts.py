#!/usr/bin/env python3
"""Version 1: run the complete pre-push contract set through mandatory containment.

Invoked by lefthook under env -i and Python isolated mode. Tool arguments select
existing native executables only; never invoke a shim/package manager to find or
install them. See --help for explicit selections when system tools are absent.
"""
import argparse
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
# The audited direct suites supplement (never replace/filter) tests/*.sh.
DIRECT_SUITES = ('test_fixture_containment.py', 'test_pre_push_contracts.py',
                 'test_macos_clt.py', 'test_homebrew_results.py',
                 'test_managed_skill_suite.py')


def native_tool(name, value):
    """Resolve a bounded explicit/system path without running user startup code."""
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
        raise ValueError('no shell contracts found; refusing an empty hook run')
    selected = [ROOT / 'tests' / name for name in DIRECT_SUITES] + shell
    if any(p.is_symlink() or not p.is_file() for p in selected):
        raise ValueError('contract inventory contains a missing or linked entry')
    return [str(p.relative_to(ROOT)) for p in selected]


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    for name, variable in TOOLS.items():
        parser.add_argument('--' + name, default='', help=f'native {name}; hook override: {variable}; default: {SYSTEM_PATH}')
    args = parser.parse_args(argv)
    if os.uname().sysname != 'Linux':
        parser.error('Linux kernel containment required; use a Linux validation host, never run fixtures directly')
    try:
        tools = {name: native_tool(name, getattr(args, name)) for name in TOOLS}
        selected = suites()
    except ValueError as error:
        parser.error(str(error))
    # Expose only these three selected executables, not their entire user PATH.
    # Node/npm and PowerShell retain adjacent runtime assets as required by the
    # existing runner; fixtures copy native runtimes before writable-prefix use.
    with tempfile.TemporaryDirectory(prefix='setup-hook-tools-', dir='/tmp') as directory:
        tool_dir = Path(directory)
        for name in ('mise', 'chezmoi', 'bun'):
            (tool_dir / name).symlink_to(tools[name])
        command = ['/usr/bin/python3', '-I', str(ROOT / 'tests/run-fixture-matrix.py'),
                   '--node', str(tools['node']), '--pwsh', str(tools['pwsh']),
                   '--tool-path', SYSTEM_PATH + ':' + directory, *selected]
        # No credentials, agent controls, Git overrides, preload/Python startup
        # controls or optional live-probe flags reach the runner. It creates its
        # own private homes/configs/stdio and compiler + kernel self-test gate.
        try:
            return subprocess.call(command, cwd=ROOT, env={'PATH': SYSTEM_PATH},
                                   stdin=subprocess.DEVNULL, close_fds=True)
        except OSError:
            print('Contained contract runner could not start; check /usr/bin/python3 and existing native tools.', flush=True)
            return 125


if __name__ == '__main__':
    raise SystemExit(main())
