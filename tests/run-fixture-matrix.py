#!/usr/bin/env python3
"""Linux-only, opt-in fixture runner with kernel-enforced outbound denial.

Never fall back to an uncontained command. This is not a filesystem/process
sandbox: fixtures must still extract real helpers, mock effects, and use temp
roots. Optional live app/extension/catalog integration controls are NOT inherited.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]


def environment(home, path, sandbox=None, pwsh=None):
    """Construct before launching even the dynamically linked compiler/launcher."""
    env = {
        'PATH': path, 'HOME': str(home), 'USERPROFILE': str(home),
        'USER': 'scowalt', 'LOGNAME': 'scowalt', 'USERNAME': 'scowalt',
        'XDG_CONFIG_HOME': str(home / '.config'), 'XDG_DATA_HOME': str(home / '.local/share'),
        'XDG_CACHE_HOME': str(home / '.cache'), 'XDG_STATE_HOME': str(home / '.state'),
        'APPDATA': str(home / 'appdata'), 'LOCALAPPDATA': str(home / 'localappdata'),
        'TMPDIR': str(home / 'tmp'), 'TMP': str(home / 'tmp'), 'TEMP': str(home / 'tmp'),
        'SHELL': '/bin/bash', 'LANG': 'C.UTF-8', 'TERM': 'dumb',
        'NPM_CONFIG_USERCONFIG': str(home / '.npmrc'),
        'NPM_CONFIG_GLOBALCONFIG': str(home / 'global.npmrc'),
        'PYTHONDONTWRITEBYTECODE': '1', 'POWERSHELL_TELEMETRY_OPTOUT': '1',
        'DOTNET_CLI_TELEMETRY_OPTOUT': '1', 'DOTNET_NOLOGO': '1',
        'DO_NOT_TRACK': '1', 'BUN_TELEMETRY_DISABLE': '1', 'CI': '1', 'MISE_OFFLINE': 'true',
        'MISE_AUTO_INSTALL': 'false', 'MISE_NODE_COMPILE': 'false',
        'GIT_CONFIG_NOSYSTEM': '1', 'GIT_CONFIG_GLOBAL': '/dev/null',
        'GIT_CONFIG_COUNT': '1', 'GIT_CONFIG_KEY_0': 'core.hooksPath',
        'GIT_CONFIG_VALUE_0': '/dev/null',
    }
    if sandbox:
        env['FIXTURE_NETWORK_SANDBOX'] = str(sandbox)
    if pwsh:
        env['PWSH_BIN'] = str(pwsh)
    return env


def prepare_home(path):
    path.mkdir(mode=0o700)
    (path / 'tmp').mkdir(mode=0o700)
    for name in ('.npmrc', 'global.npmrc'):
        (path / name).touch(mode=0o600)
    return path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--node', required=True, type=Path, help='Existing native Node binary, not a mise shim')
    parser.add_argument('--pwsh', type=Path, help='Existing PowerShell binary; never downloaded')
    parser.add_argument('--tool-path', default='/usr/bin:/bin', help='Explicit audited executable directories; no inherited PATH')
    parser.add_argument('--timeout', type=int, default=300)
    parser.add_argument('--artifact-parent', type=Path, default=Path('/tmp'))
    parser.add_argument('tests', nargs='+', help='Explicit tests/*.sh or tests/test_*.py paths; no arbitrary command')
    args = parser.parse_args()
    # Private fixture descendants too, not only the top-level suite HOME. Tests
    # exercising other masks set them explicitly inside their isolated process.
    os.umask(0o077)
    if os.uname().sysname != 'Linux':
        parser.error('kernel sandbox requires Linux; no uncontained fallback')
    node = args.node.resolve(strict=True)
    pwsh = args.pwsh.resolve(strict=True) if args.pwsh else None
    scripts = []
    for name in args.tests:
        script = (ROOT / name).resolve(strict=True)
        if script.parent != ROOT / 'tests' or script.suffix not in ('.sh', '.py'):
            parser.error('only repository fixture scripts are allowed')
        if script.name in ('run-fixture-matrix.py', 'extract_setup_fixture.py', 'setup_policy_fixture.py'):
            parser.error('helper is not a behavioral suite')
        scripts.append(script)
    tool_paths = args.tool_path.split(os.pathsep)
    if any(not p or not Path(p).is_absolute() for p in tool_paths):
        parser.error('tool directories must be explicit absolute paths')
    path = os.pathsep.join([str(node.parent), *([str(pwsh.parent)] if pwsh else []), *tool_paths])
    root = Path(tempfile.mkdtemp(prefix='setup-fixture-matrix-', dir=args.artifact_parent))
    root.chmod(0o700)
    build_home = prepare_home(root / 'build-home')
    clean = environment(build_home, '/usr/bin:/bin')
    sandbox = root / 'fixture-no-network'
    print(f'Private fixture artifacts: {root}', flush=True)
    preflights = (
        ('compiler', ['/usr/bin/cc', '-O2', '-Wall', '-Wextra', '-Werror',
                      str(ROOT / 'tests/fixture-no-network.c'), '-o', str(sandbox)], 120),
        ('sandbox-self-test', [str(sandbox), '--self-test'], 15),
    )
    for stage, command, timeout in preflights:
        diagnostic = root / (stage + '.log')
        try:
            # Private from creation; never inherit socket-backed harness stdio,
            # even for compilation or mandatory kernel-filter verification.
            fd = os.open(diagnostic, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
            with os.fdopen(fd, 'w') as output:
                result = subprocess.run(command, env=clean, cwd=build_home,
                                        stdin=subprocess.DEVNULL, stdout=output,
                                        stderr=subprocess.STDOUT, close_fds=True, timeout=timeout)
        except (OSError, subprocess.TimeoutExpired) as error:
            reason = 'timeout' if isinstance(error, subprocess.TimeoutExpired) else 'launch-or-diagnostic-error'
            print(f'Fixture preflight refused: {stage}; {reason}; diagnostics: {diagnostic}', flush=True)
            return 125
        if result.returncode:
            print(f'Fixture preflight refused: {stage}; exit {result.returncode}; diagnostics: {diagnostic}', flush=True)
            return 125
    results = []
    for script in scripts:
        home = prepare_home(root / (script.stem + '-home'))
        env = environment(home, path, sandbox, pwsh)
        command = ['/bin/bash', str(script)] if script.suffix == '.sh' else ['/usr/bin/python3', str(script)]
        started = time.monotonic()
        logfile = root / (script.stem + '.log')
        with logfile.open('x') as output:
            logfile.chmod(0o600)
            child = subprocess.Popen([str(sandbox), '--', *command], env=env, cwd=ROOT,
                                     stdin=subprocess.DEVNULL, stdout=output, stderr=subprocess.STDOUT,
                                     close_fds=True, start_new_session=True)
            try:
                status = child.wait(timeout=args.timeout)
            except subprocess.TimeoutExpired:
                # Only the new fixture process group, never an existing server.
                import signal
                os.killpg(child.pid, signal.SIGKILL)
                child.wait()
                status = 124
        result = {'test': str(script.relative_to(ROOT)), 'status': status,
                  'seconds': round(time.monotonic() - started, 1)}
        results.append(result)
        record = root / 'results.json'
        record.write_text(json.dumps(results, indent=2) + '\n')
        record.chmod(0o600)
        print(f"{result['test']}: {status} ({result['seconds']}s)", flush=True)
        if status == 125:
            raise SystemExit('Sandbox/child launch refused; no fallback or remaining suites run')
    return int(any(r['status'] for r in results))


if __name__ == '__main__':
    raise SystemExit(main())
