"""Extract the real retirement/update/final-result caller seams, never full setup."""
from pathlib import Path
import re
import subprocess
import unittest
from tests.setup_policy_fixture import bash_maintenance

ROOT = Path(__file__).resolve().parents[1]


def named_function(text, name):
    match = re.search(r'^' + name + r'\(\) \{\n.*?^\}', text, re.M | re.S)
    if not match:
        raise AssertionError(f'{name} not found')
    return match.group()


class BashCallers(unittest.TestCase):
    def test_personal_doppler_only_and_no_work_replacement(self):
        for name in ('ubuntu.sh', 'pi.sh', 'wsl.sh', 'mac.sh', 'bazzite.sh'):
            with self.subTest(script=name):
                source = (ROOT / name).read_text()
                install = named_function(source, 'install_secrets_manager')
                script = f'''print_error() {{ :; }}
print_warning() {{ :; }}
print_debug() {{ :; }}
print_message() {{ :; }}
print_success() {{ :; }}
install_doppler() {{ printf 'doppler\\n'; }}
ensure_brew_item_trusted() {{ return 0; }}
ensure_brew_formula_trusted() {{ return 0; }}
brew() {{ printf 'doppler\\n'; }}
command() {{ if [[ "$2" == doppler ]]; then return 1; fi; builtin command "$@"; }}
{install}
install_secrets_manager
'''
                for work, expected in (('1', ''), ('0', 'doppler')):
                    result = subprocess.run(['bash', '-c', script], env={'PATH': '/usr/bin:/bin', 'WORK_MACHINE': work},
                                            capture_output=True, text=True)
                    self.assertEqual(result.returncode, 0, (name, work, result.stderr))
                    self.assertEqual(result.stdout.strip(), expected)

    def test_failed_retirement_finalizes_after_unrelated_work(self):
        for name in ('ubuntu.sh', 'pi.sh', 'wsl.sh', 'bazzite.sh'):
            with self.subTest(script=name):
                text = (ROOT / name).read_text()
                real = named_function(text, 'run_setup_tasks')
                marker = 'if ! retire_infisical_brew; then' if name == 'bazzite.sh' else 'if ! retire_infisical_apt; then'
                stop = 'install_core_packages || return 1' if name == 'bazzite.sh' else 'update_and_install_core'
                self.assertIn(marker, real)
                first = real[real.index(marker):real.index(stop, real.index(marker))]
                # Exercise the actual final-result branch and main log boundary.
                tail = real[real.rindex('    check_pending_reboot\n'):]
                main = named_function(text, 'main')
                harness = f'''set -u
GREEN='' BOLD='' NC=''
print_section() {{ :; }}
print_warning() {{ printf 'warning:%s\\n' "$*"; }}
start_setup_log() {{ printf 'log-started\\n'; }}
finish_setup_log() {{ printf 'log-finalized=%s\\n' "$1"; return "$1"; }}
retire_infisical_apt() {{ return 1; }}
retire_infisical_brew() {{ return 1; }}
fix_dpkg_and_broken_dependencies() {{ printf 'fix-dpkg\\n'; }}
update_dependencies() {{ printf 'upgrade\\n'; }}
update_brew() {{ printf 'upgrade\\n'; }}
print_message() {{ :; }}
check_pending_reboot() {{ printf 'unrelated-work-complete\\n'; }}
update_packages() {{ :; }}
run_setup_tasks() {{
  local _setup_had_errors=0 _infisical_retirement_ok=1 _infisical_retirement_failed=0
  {first}
  printf 'unrelated-stage\\n'
  {tail}
{bash_maintenance()}
{main}
main --maintenance
'''
                # The extracted seam must run only inert local functions.
                for work in ('0', '1'):
                    result = subprocess.run(['bash', '-c', harness],
                                            env={'PATH': '/usr/bin:/bin', 'WORK_MACHINE': work},
                                            capture_output=True, text=True)
                    self.assertEqual(result.returncode, 1, (name, work, result.stderr, result.stdout))
                    self.assertIn('log-finalized=1', result.stdout)
                    self.assertIn('unrelated-work-complete', result.stdout)
                    self.assertNotIn('\nupgrade\n', result.stdout)


if __name__ == '__main__':
    unittest.main()
