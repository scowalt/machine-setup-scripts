"""Inert package-manager tests: extract only retirement functions, never source setup."""
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def function(script, name):
    text = (ROOT / script).read_text()
    match = re.search(r'(?m)^' + re.escape(name) + r'\(\) \{\n.*?^\}', text, re.S | re.M)
    if not match:
        raise AssertionError(f'{script}: missing {name}')
    return match.group()


class Apt(unittest.TestCase):
    def run_case(self, script='ubuntu.sh', status='absent', plan='Remv infisical [1]\n', fail_remove=False, stale_postcheck=False, inventory_unavailable=False):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp) / 'apt'
            root.mkdir(mode=0o700)
            (root / 'sources.list.d').mkdir(mode=0o700)
            source = root / 'sources.list.d' / 'shared.list'
            source.write_text('deb https://example.org/stable stable main\n'
                              'deb https://dl.cloudsmith.io/public/infisical/infisical-cli/deb/ubuntu stable main\n')
            source.chmod(0o644)
            original = function(script, 'retire_infisical_apt_sources')
            self.assertIn(' /etc/apt <<', original)
            script_text = original.replace(' /etc/apt <<', f' {root} <<')
            self.assertNotIn(' /etc/apt <<', script_text)
            self.assertIn(f' {root} <<', script_text)
            script_text += '\n' + function(script, 'retire_infisical_apt')
            harness = f'''can_sudo() {{ return 0; }}
print_error() {{ :; }}
print_warning() {{ :; }}
print_debug() {{ :; }}
sudo() {{
    if [[ "$1" == /usr/bin/python3 ]]; then "$@"; return; fi
    if [[ "$*" == *'-s remove infisical'* ]]; then printf '%b' {plan!r}; return; fi
    if [[ "$*" == *'dpkg --no-triggers --remove infisical'* ]]; then
        {'return 1' if fail_remove else f'printf removed > {root}/removed'}; return
    fi
    # No actual apt-get removal, purge, or other package action is permitted.
    return 1
}}
dpkg-query() {{
    if [[ "$*" == *' dpkg' ]]; then
        if [[ {str(inventory_unavailable).lower()} == true ]]; then return 1; fi
        printf 'install ok installed'; return
    fi
    if [[ -f {root}/removed ]] && [[ {str(not stale_postcheck).lower()} == true ]]; then return 1; fi
    if [[ {status!r} == 'absent' ]]; then return 1; fi
    printf '%s' {status!r}
}}
{script_text}
retire_infisical_apt || exit 1
# An inert apt update fails if the retired source is still present.
if grep -q 'dl.cloudsmith.io/public/infisical/infisical-cli/' {root}/sources.list.d/shared.list; then exit 42; fi
'''
            result = subprocess.run(['bash', '-c', harness], capture_output=True, text=True)
            return result.returncode, source.read_text(), (root / 'removed').exists()

    def test_stale_source_before_update_cli_absent(self):
        for script in ('ubuntu.sh', 'pi.sh', 'wsl.sh'):
            code, source, removed = self.run_case(script)
            self.assertEqual(code, 0, script)
            self.assertEqual(source, 'deb https://example.org/stable stable main\n')
            self.assertFalse(removed)

    def test_unavailable_inventory_fails_closed(self):
        code, source, removed = self.run_case(inventory_unavailable=True)
        self.assertNotEqual(code, 0)
        self.assertFalse(removed)

    def test_exact_package_removed(self):
        realistic = ('Reading package lists...\nBuilding dependency tree...\n'
                     'Reading state information...\nThe following packages will be REMOVED:\n'
                     '  infisical\n0 upgraded, 0 newly installed, 1 to remove and 0 not upgraded.\n'
                     'Remv infisical [1]\n')
        code, source, removed = self.run_case(status='install ok installed', plan=realistic)
        self.assertEqual(code, 0)
        self.assertTrue(removed)

    def test_native_apt_autoremove_advisory_does_not_block_targeted_removal(self):
        # Captured from isolated /usr/bin/apt-get -s with disposable APT Dir,
        # Dir::State::status, caches and logs; no host package state was used.
        captured = ('Reading package lists...\nBuilding dependency tree...\n'
                    'Reading state information...\n'
                    'The following package was automatically installed and is no longer required:\n'
                    '  unrelated-auto-package\n'
                    "Use 'apt autoremove' to remove it.\n"
                    'The following packages will be REMOVED:\n'
                    '  infisical\n'
                    '0 upgraded, 0 newly installed, 1 to remove and 0 not upgraded.\n'
                    'Remv infisical [1.0]\n')
        for script in ('ubuntu.sh', 'pi.sh', 'wsl.sh'):
            with self.subTest(script=script):
                code, _, removed = self.run_case(script=script, status='install ok installed', plan=captured)
                self.assertEqual(code, 0)
                self.assertTrue(removed)

    def test_benign_progress_and_plural_advisory(self):
        plan = ('Reading package lists...\nSolving dependencies...\nBuilding dependency tree...\n'
                'Reading state information...\n'
                'The following packages were automatically installed and are no longer required:\n'
                '  unrelated-auto-package another-unused-package\n'
                "Use 'apt autoremove' to remove them.\n"
                'The following packages will be REMOVED:\n  infisical\n'
                '0 upgraded, 0 newly installed, 1 to remove and 0 not upgraded.\n'
                'Remv infisical [1.0]\n')
        code, _, removed = self.run_case(status='install ok installed', plan=plan)
        self.assertEqual(code, 0)
        self.assertTrue(removed)

    def test_advisory_cannot_hide_unrelated_package_action(self):
        for action in ('  Inst unrelated [1]', 'Remv unrelated [2]', 'Conf unrelated (2 fixture)',
                       '  unrelated-auto-package\nInst unrelated [1]'):
            with self.subTest(action=action):
                plan = ('Reading package lists...\n'
                        'The following package was automatically installed and is no longer required:\n'
                        f'{action}\nUse \'apt autoremove\' to remove it.\n'
                        'The following packages will be REMOVED:\n  infisical\n'
                        '0 upgraded, 0 newly installed, 1 to remove and 0 not upgraded.\n'
                        'Remv infisical [1.0]\n')
                code, _, removed = self.run_case(status='install ok installed', plan=plan)
                self.assertNotEqual(code, 0)
                self.assertFalse(removed)

    def test_advisory_and_summary_fail_closed(self):
        cases = (
            'The following package was automatically installed and is no longer required:\n'
            '  unrelated-auto-package\nRemv infisical [1.0]\n',  # missing footer
            'The following package was automatically installed and is no longer required:\n'
            '  unrelated-auto-package\nUse \'apt autoremove\' to remove it.\n'
            '2 upgraded, 0 newly installed, 1 to remove and 0 not upgraded.\nRemv infisical [1.0]\n',
            'The following package was automatically installed and is no longer required:\n'
            '  unrelated-auto-package\nUse \'apt autoremove\' to remove it.\n'
            '0 upgraded, 0 newly installed, 2 to remove and 0 not upgraded.\nRemv infisical [1.0]\n',
        )
        for plan in cases:
            with self.subTest(plan=plan):
                code, _, removed = self.run_case(status='install ok installed', plan=plan)
                self.assertNotEqual(code, 0)
                self.assertFalse(removed)

    def test_other_removal_refused(self):
        code, source, removed = self.run_case(status='install ok installed', plan='Remv infisical [1]\nRemv unrelated [2]\n')
        self.assertNotEqual(code, 0)
        self.assertFalse(removed)

    def test_unrelated_apt_actions_are_refused(self):
        for action in ('Inst unrelated [1] (2 fixture)', 'Conf unrelated (2 fixture)',
                       'Purg unrelated [1]', 'Surprise unrelated'):
            with self.subTest(action=action):
                code, _, removed = self.run_case(status='install ok installed',
                                                 plan=f'Remv infisical [1]\n{action}\n')
                self.assertNotEqual(code, 0)
                self.assertFalse(removed)

    def test_failed_removal_propagates(self):
        code, _, _ = self.run_case(status='install ok installed', fail_remove=True)
        self.assertNotEqual(code, 0)
        code, _, _ = self.run_case(status='install ok installed', stale_postcheck=True)
        self.assertNotEqual(code, 0)


class Wiring(unittest.TestCase):
    def test_all_platforms_retire_before_updates_and_do_not_reinstall(self):
        for script in ('ubuntu.sh', 'pi.sh', 'wsl.sh', 'mac.sh', 'bazzite.sh'):
            text = (ROOT / script).read_text()
            caller = text[text.index('run_setup_tasks() {'):]
            retirement = 'retire_infisical_apt' if script in ('ubuntu.sh', 'pi.sh', 'wsl.sh') else 'retire_infisical_brew'
            self.assertIn(retirement, caller)
            self.assertNotIn('install_infisical', text)
            self.assertNotIn('brew install infisical/', text)
            self.assertNotIn('infisical/infisical-cli/setup.deb.sh', text)
            if script in ('ubuntu.sh', 'pi.sh'):
                self.assertLess(caller.index(retirement), caller.index('update_dependencies'))
            elif script == 'wsl.sh':
                self.assertLess(caller.index(retirement), caller.index('update_and_install_core'))
            else:
                self.assertLess(caller.index(retirement), caller.index('update_brew'))
            self.assertIn('"${WORK_MACHINE:-}" != "1"', function(script, 'install_secrets_manager'))
            self.assertNotIn('install_infisical', function(script, 'install_secrets_manager'))
            if script in ('mac.sh', 'bazzite.sh'):
                self.assertIn('Skipping Homebrew upgrades until Infisical retirement is verified', caller)
        windows = (ROOT / 'win.ps1').read_text()
        caller = windows[windows.index('function Invoke-WindowsSetupTasks {'):]
        self.assertLess(caller.index('Remove-InfisicalCli'), caller.index('Install-WingetPackages'))
        self.assertIn('if ($infisicalRetirementFailed)', caller)
        self.assertIn('Skipping WinGet upgrades until Infisical retirement is verified', caller)
        self.assertNotIn('winget install -e --id "Infisical.CLI"', windows)
        self.assertNotIn('Get-WinGetPackage', windows)
        self.assertIn("'infisical.infisical'", windows)
        self.assertIn('RegistryKey]::OpenBaseKey', windows)
        self.assertIn('winget uninstall --product-code $record.Code --exact --source winget --scope $record.Scope --silent --preserve', windows)


class Brew(unittest.TestCase):
    def run_case(self, script, installed=True, fail=False, stale_postcheck=False):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            if installed:
                (root / 'formula').write_text('infisical/get-cli/infisical\nother/tap/tool\n')
            else:
                (root / 'formula').write_text('other/tap/tool\n')
            harness = f'''print_error() {{ :; }}
print_warning() {{ :; }}
brew() {{
  if [[ "$1" == list ]]; then cat {root}/formula; return; fi
  if [[ "$1" == uninstall ]]; then
    {'return 1' if fail else (':' if stale_postcheck else f"printf 'other/tap/tool\\n' > {root}/formula")}; return
  fi
  return 1
}}
{function(script, 'retire_infisical_brew')}
retire_infisical_brew
'''
            result = subprocess.run(['bash', '-c', harness], capture_output=True, text=True)
            return result.returncode, (root / 'formula').read_text()

    def test_installed_absent_and_failure(self):
        for script in ('mac.sh', 'bazzite.sh'):
            self.assertEqual(self.run_case(script)[0], 0)
            self.assertEqual(self.run_case(script, installed=False)[0], 0)
            self.assertNotEqual(self.run_case(script, fail=True)[0], 0)
            self.assertNotEqual(self.run_case(script, stale_postcheck=True)[0], 0)
            self.assertNotIn('brew untap', function(script, 'retire_infisical_brew'))


if __name__ == '__main__':
    unittest.main()
