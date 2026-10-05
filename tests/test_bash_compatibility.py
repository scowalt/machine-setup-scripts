from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

from extract_setup_fixture import validate_function

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ('mac.sh', 'ubuntu.sh', 'wsl.sh', 'pi.sh', 'bazzite.sh')
BASH32 = shutil.which('bash3.2') or ('/bin/bash' if sys.platform == 'darwin' else None)
HELPERS = (
    ('install_opencode_cli', 'OPENCODE_CLI_JS', 'opencode-cli:installed'),
    ('configure_pi_opencode_go', 'PI_OPENCODE_GO_JS', 'unchanged'),
    ('retire_global_backlog_mcp', 'BACKLOG_MCP_RETIREMENT_JS', 'absent'),
    ('prepare_pi_profile_permissions', 'PI_PROFILE_PERMISSIONS_JS', 'prepared'),
    ('remove_pi_prose', 'PI_PROSE_RETIREMENT_JS', 'absent'),
)


def helper(source, name, delimiter):
    block = re.search(rf'^{name}\(\) \{{\n.*?^{delimiter}\n.*?^\}}\n', source, re.M | re.S)[0]
    validate_function(block)
    payload = block.split("<<'" + delimiter + "'\n", 1)[1].split('\n' + delimiter + '\n', 1)[0] + '\n'
    return block, payload.encode()


class Compatibility(unittest.TestCase):
    def check_syntax(self, shell):
        for name in SCRIPTS:
            file = ROOT / name
            for piped in (False, True):
                with self.subTest(shell=shell, script=name, piped=piped):
                    result = subprocess.run(
                        [shell, '--noprofile', '--norc', '-n', *([] if piped else [str(file)])],
                        input=file.read_bytes() if piped else None,
                        stdin=None if piped else subprocess.DEVNULL,
                        capture_output=True, timeout=10,
                        env={'PATH': '/usr/bin:/bin', 'LANG': 'C'},
                    )
                    self.assertEqual(result.returncode, 0, result.stderr.decode())

    def test_host_bash_parses_full_entry_points_from_file_and_stdin(self):
        self.check_syntax('/bin/bash')

    @unittest.skipUnless(BASH32, 'Bash 3.2 unavailable: supply existing bash3.2 via --tool-path; native macOS unverified')
    def test_bash32_parses_full_entry_points_from_file_and_stdin(self):
        version = subprocess.run([BASH32, '--version'], stdin=subprocess.DEVNULL,
                                 capture_output=True, text=True, timeout=10,
                                 env={'PATH': '/usr/bin:/bin', 'LANG': 'C'})
        self.assertEqual(version.returncode, 0, version.stderr)
        self.assertRegex(version.stdout, r'GNU bash, version 3\.2\.')
        self.check_syntax(BASH32)

    def test_literal_stdin_status_capture_and_caller_stdin_restoration(self):
        for shell in dict.fromkeys(['/bin/bash', *([BASH32] if BASH32 else [])]):
            for name in SCRIPTS:
                source = (ROOT / name).read_text()
                for function, delimiter, success in HELPERS:
                    block, payload = helper(source, function, delimiter)
                    for reply, status, expected in ((success, 0, 0), (success, 17, 1), ('invalid-result', 0, 1)):
                        with self.subTest(shell=shell, script=name, helper=function, status=status, reply=reply):
                            self.check_wrapper(shell, block, payload, function, reply, status, expected)

    def check_wrapper(self, shell, block, payload, function, reply, status, expected):
        with tempfile.TemporaryDirectory(prefix='bash-compatibility-') as temp:
            home = Path(temp)
            (home / '.pi/agent').mkdir(parents=True)
            node = home / 'node'
            node.write_text(f'''#!{sys.executable}
import os
from pathlib import Path
import sys
if sys.argv[1] == '-e':
    raise SystemExit(0)
Path(os.environ['HOME'], 'received').write_bytes(sys.stdin.buffer.read())
print(os.environ['MOCK_RESULT'])
raise SystemExit(int(os.environ['MOCK_STATUS']))
''')
            node.chmod(0o700)
            mocks = '''set -eu
print_error() { printf 'error:%s\n' "$*"; }
print_warning() { printf 'warning:%s\n' "$*"; }
print_success() { printf 'success:%s\n' "$*"; }
print_debug() { :; }
ensure_shared_node_runtime() { return 0; }
macos_existing_prerequisites() { return 0; }
uname() { printf 'x86_64\n'; }
'''
            call = f'''
status=0
{function} || status=$?
IFS= read -r remaining || exit 91
[[ "${{remaining}}" == caller-input ]] || exit 92
exit "${{status}}"
'''
            result = subprocess.run([shell, '--noprofile', '--norc', '-c', mocks + block + call],
                                    input='caller-input\n', capture_output=True, text=True, cwd=home, timeout=10,
                                    env={'PATH': temp + ':/usr/bin:/bin', 'HOME': temp,
                                         'TMPDIR': temp, 'LANG': 'C',
                                         'MOCK_RESULT': reply, 'MOCK_STATUS': str(status)})
            self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
            self.assertEqual((home / 'received').read_bytes(), payload)


if __name__ == '__main__':
    unittest.main()
