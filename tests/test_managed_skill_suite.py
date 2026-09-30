"""Full-suite/retirement contracts: extracted helpers, inert CLI, temporary homes only."""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
SCRIPTS = ['mac.sh', 'ubuntu.sh', 'wsl.sh', 'pi.sh', 'bazzite.sh', 'win.ps1']
PWSH = os.environ.get('PWSH_BIN') or shutil.which('pwsh')
NODE = shutil.which('node')
KNOWN = json.loads((ROOT / 'tests/fixtures/matt-pocock-skills.json').read_text())['skills']


def embedded(script):
    text = (ROOT / script).read_text()
    if script == 'win.ps1':
        return text.split("    $helper = @'\n", 1)[1].split("\n'@", 1)[0]
    return text.split("<<'MANAGED_SKILL_POLICY_JS'\n", 1)[1].split('\nMANAGED_SKILL_POLICY_JS', 1)[0]


def functions(script):
    text = (ROOT / script).read_text()
    if script == 'win.ps1':
        names = ['Invoke-MattPocockSkillPolicy', 'Remove-MattPocockSkills', 'Setup-MattPocockSkills',
                 'Test-MattPocockSkillsDisabled', 'Test-EnvLocalFlag', 'Set-PiSkillOwnership', 'Remove-PrLensSkill',
                 'Remove-SimpleEnglishSkill', 'Remove-ShowMeSkill']
        pattern = lambda name: r'^function ' + name + r' \{.*?^\}'
    else:
        names = ['matt_pocock_skill_policy', 'matt_pocock_skills', 'matt_pocock_skills_disabled',
                 'remove_matt_pocock_skills', 'remove_obsolete_matt_pocock_skills', 'setup_matt_pocock_skills',
                 'configure_pi_skill_ownership', 'remove_pr_lens_skill', 'remove_simple_english_skill',
                 'remove_show_me_skill']
        pattern = lambda name: r'^' + name + r'\(\) \{.*?^\}'
    return '\n\n'.join(re.search(pattern(name), text, re.M | re.S)[0] for name in names)


class ManagedSkills(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='managed-suite-')
        self.root = Path(self.tmp.name)
        self.home = self.root / 'home'
        self.home.mkdir()
        (self.home / '.test-owned').touch()
        self.env = {k: v for k, v in os.environ.items() if k not in (
            'HOME', 'USERPROFILE', 'PI_CODING_AGENT_DIR', 'CLAUDE_CONFIG_DIR', 'CODEX_HOME', 'XDG_STATE_HOME',
            'BAN_MATT_POCOCK_SKILLS', 'BAN_MATT_POCKOCK_SKILLS', 'NODE_OPTIONS', 'NODE_PATH', 'WORK_MACHINE')}
        self.env.update(HOME=str(self.home), USERPROFILE=str(self.home), SKILL_TEST_HOME=str(self.home),
                        SKILL_TEST_CALLS=str(self.root / 'calls'), SKILL_TEST_PYTHON=sys.executable,
                        SKILL_TEST_MOCK=str(ROOT / 'tests/mock_managed_skills.py'),
                        SKILL_TEST_STAGES=str(self.root / 'stages'), TMPDIR=str(self.root),
                        TMP=str(self.root), TEMP=str(self.root), XDG_CACHE_HOME=str(self.root / 'cache'),
                        XDG_CONFIG_HOME=str(self.root / 'config'), XDG_DATA_HOME=str(self.root / 'data'))
        self.shared = self.home / '.agents/skills'
        self.default_pi = self.home / '.pi/agent'
        self.custom_pi = self.home / 'custom pi'
        self.env.update(PI_CODING_AGENT_DIR=str(self.custom_pi), CLAUDE_CONFIG_DIR=str(self.home / 'custom claude'),
                        CODEX_HOME=str(self.home / 'custom codex'))

    def tearDown(self):
        self.tmp.cleanup()

    def put(self, file, data='keep'):
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_text(data)
        return file

    def snapshot(self):
        state = {}
        def visit(file):
            st = file.lstat()
            state[str(file)] = (st.st_ino, st.st_mode, st.st_mtime_ns,
                                os.readlink(file) if file.is_symlink() else hashlib.sha256(file.read_bytes()).hexdigest() if file.is_file() else None)
            if file.is_dir() and not file.is_symlink():
                for child in file.iterdir():
                    visit(child)
        visit(self.home)
        return state

    def policy(self, mode, success=True, blocked=False, script='mac.sh', argument=''):
        helper = self.root / 'policy.cjs'
        helper.write_text(embedded(script))
        proc = subprocess.run([NODE, str(helper), str(self.home), self.env.get('PI_CODING_AGENT_DIR', ''),
                               '1' if blocked else '0', mode, str(argument)], env=self.env, text=True, capture_output=True, timeout=30)
        self.assertEqual(proc.returncode == 0, success, proc.stdout + proc.stderr)
        self.assertNotIn('PRIVATE-SENTINEL', proc.stdout + proc.stderr)
        return proc

    def wrapper(self, script, operation='install', success=True, blocked=False):
        if script == 'win.ps1' and not PWSH:
            self.skipTest('Set PWSH_BIN for PowerShell wrapper coverage')
        if script == 'win.ps1':
            action = {'install': 'Setup-MattPocockSkills', 'ownership': 'Set-PiSkillOwnership',
                      'retire': 'Remove-PrLensSkill', 'retire-simple': 'Remove-SimpleEnglishSkill',
                      'retire-show': 'Remove-ShowMeSkill'}[operation]
            fixture = self.root / 'fixture.ps1'
            fixture.write_text("$ErrorActionPreference='Stop'\n" + functions(script) + '\n' + r'''
function Write-Message($Message) { }
function Write-Warning($Message) { [Console]::Error.WriteLine($Message) }
function Write-Success($Message) { }
function Enable-SkillsCliNodeRuntime { return $env:SKILL_TEST_MODE -ne 'bad-runtime' }
function npm {
    param([string]$Command, [string]$Action, [string]$Key)
    if ($Command -ne 'config' -or $Action -ne 'get' -or $Key -notin @('userconfig','globalconfig')) { throw 'unexpected npm call' }
    $global:LASTEXITCODE = 0
    if ($env:SKILL_TEST_MODE -eq 'failed-npm-config') { $global:LASTEXITCODE = 1; return }
    Join-Path $env:SKILL_TEST_HOME ($Key + '.npmrc')
}
function npx {
    param([Parameter(ValueFromRemainingArguments=$true)][object[]]$Arguments)
    # Unix PowerShell expands native '*' arguments. Pass the captured argv as
    # JSON so this mock models Windows npx.cmd without Unix glob expansion.
    $env:SKILL_TEST_ARGS = ConvertTo-Json -InputObject @($Arguments) -Compress
    try { & $env:SKILL_TEST_PYTHON $env:SKILL_TEST_MOCK }
    finally { $env:SKILL_TEST_ARGS = $null }
}
''' + '\n$trackedEnvironment = [System.Collections.Generic.Dictionary[string,object]]::new([System.StringComparer]::Ordinal)\n'
                               + 'foreach ($key in @("HOME","USERPROFILE","CLAUDE_CONFIG_DIR","CODEX_HOME","PI_CODING_AGENT_DIR",'
                               + '"XDG_STATE_HOME","XDG_CONFIG_HOME","XDG_CACHE_HOME","XDG_DATA_HOME",'
                               + '"npm_config_userconfig","npm_config_globalconfig","NPM_CONFIG_USERCONFIG","NPM_CONFIG_GLOBALCONFIG")) '
                               + '{ $trackedEnvironment[$key] = [Environment]::GetEnvironmentVariable($key) }\n'
                               + f'$script:PiProfileMutationsBlocked=${str(blocked).lower()}\n$result = {action}\n'
                               + 'foreach ($key in $trackedEnvironment.Keys) { if ([Environment]::GetEnvironmentVariable($key) -cne '
                               + '$trackedEnvironment[$key]) { throw "Environment was not restored: $key" } }\n'
                               + 'if (-not $result) { exit 1 }\n')
            command = [PWSH, '-NoProfile', '-NonInteractive', '-File', str(fixture)]
        else:
            action = {'install': 'setup_matt_pocock_skills', 'ownership': 'configure_pi_skill_ownership',
                      'retire': 'remove_pr_lens_skill', 'retire-simple': 'remove_simple_english_skill',
                      'retire-show': 'remove_show_me_skill'}[operation]
            fixture = self.root / 'fixture.sh'
            fixture.write_text('set -eu\n' + functions(script) + '\n' + r'''
print_message() { :; }
print_success() { :; }
print_warning() { printf '%s\n' "$1" >&2; }
ensure_skills_cli_node_runtime() { [[ "${SKILL_TEST_MODE:-}" != bad-runtime ]]; }
npm() {
    [[ "$1 $2" == 'config get' && ( "$3" == userconfig || "$3" == globalconfig ) ]] || return 90
    [[ "${SKILL_TEST_MODE:-}" != failed-npm-config ]] || return 1
    printf '%s/%s.npmrc\n' "${SKILL_TEST_HOME}" "$3"
}
npx() { "${SKILL_TEST_PYTHON}" "${SKILL_TEST_MOCK}" "$@"; }
''' + f'\nPI_PROFILE_MUTATIONS_BLOCKED={int(blocked)}\n{action}\n')
            command = ['bash', str(fixture)]
        proc = subprocess.run(command, env=self.env, text=True, capture_output=True, timeout=30)
        self.assertEqual(proc.returncode == 0, success, script + ': ' + proc.stdout + proc.stderr)
        self.assertNotIn('PRIVATE-SENTINEL', proc.stdout + proc.stderr)
        self.assertNotIn('Environment was not restored', proc.stdout + proc.stderr)
        if Path(self.env['SKILL_TEST_STAGES']).exists():
            for stage in Path(self.env['SKILL_TEST_STAGES']).read_text().splitlines():
                self.assertFalse(os.path.lexists(stage), 'staging HOME was not removed')
        return proc

    def all_dirs(self):
        return [self.shared, self.home / '.claude/skills', Path(self.env['CLAUDE_CONFIG_DIR']) / 'skills',
                self.home / '.codex/skills', Path(self.env['CODEX_HOME']) / 'skills', self.home / '.gemini/skills',
                self.home / '.cursor/skills', self.default_pi / 'skills', self.custom_pi / 'skills']

    def test_embedded_copies_and_wiring(self):
        baseline = embedded('mac.sh')
        for script in SCRIPTS:
            self.assertEqual(embedded(script), baseline, script)
            text = (ROOT / script).read_text()
            self.assertNotIn('setup_pr_lens_skill', text)
            self.assertNotIn('Install-PrLensSkill', text)
            self.assertNotIn('coldteadotai/pr-lens', text)
            self.assertNotIn('setup_simple_english_skill', text)
            self.assertNotIn('Install-SimpleEnglishSkill', text)
            self.assertNotIn('AminBlg/SimpleEnglish', text)
            self.assertNotIn('setup_show_me_skill', text)
            self.assertNotIn('Install-ShowMeSkill', text)
            self.assertNotIn('humanlayer/skills', text)
            if script != 'win.ps1':
                self.assertRegex(text, r'remove_show_me_skill(?:; then| \|\| _setup_had_errors=1)')
                self.assertRegex(text, r'remove_simple_english_skill(?:; then| \|\| _setup_had_errors=1)')
                self.assertRegex(text, r'remove_pr_lens_skill(?:; then| \|\| _setup_had_errors=1)')
                self.assertRegex(text, r'setup_matt_pocock_skills(?:; then| \|\| _setup_had_errors=1)')
                self.assertIn("--skill '*' --full-depth --copy --yes --json", text)
            else:
                self.assertIn('Required PR Lens skill removal failed.', text)
                self.assertIn('if (-not (Remove-PrLensSkill))', text)
                self.assertIn('Required Simple English skill removal failed.', text)
                self.assertIn('if (-not (Remove-SimpleEnglishSkill))', text)
                self.assertIn('Required show-me skill removal failed.', text)
                self.assertIn('if (-not (Remove-ShowMeSkill))', text)
        powershell = functions('win.ps1')
        self.assertNotIn('$IsWindows', powershell)  # Absent on Windows PowerShell 5.1.
        self.assertIn('[Environment]::OSVersion.Platform', powershell)
        self.assertNotIn('Remove-Item -LiteralPath $stage -Recurse', powershell)
        self.assertEqual(len(KNOWN), 37)
        for name in KNOWN:
            self.assertIn("'" + name + "'", baseline)

    def test_every_wrapper_updates_all_categories_and_future_skills_on_personal_and_work(self):
        for script in SCRIPTS:
            if script == 'win.ps1' and not PWSH:
                continue
            for work in ('0', '1'):
                with self.subTest(script=script, work=work):
                    self.env['WORK_MACHINE'] = work
                    for _ in range(2):
                        self.wrapper(script)
                    inventory = json.loads((self.home / '.agents/.setup-matt-pocock-skills.json').read_text())
                    self.assertEqual(set(inventory['skills']), set(KNOWN + ['new-upstream-skill']))
                    for base in (self.shared, Path(self.env['CLAUDE_CONFIG_DIR']) / 'skills'):
                        for name in inventory['skills']:
                            self.assertGreater((base / name / 'SKILL.md').stat().st_size, 0)
                            self.assertEqual((base / name / 'references/guide.md').read_text(), 'Upstream fixture: do not execute.\n')
                    self.assertFalse((self.custom_pi / 'skills/tdd').exists())
                    self.assertFalse((Path(self.env['CODEX_HOME']) / 'skills/tdd').exists())

    def test_default_claude_and_xdg_state_paths(self):
        self.env.pop('CLAUDE_CONFIG_DIR')
        self.env['XDG_STATE_HOME'] = str(self.home / 'state')
        self.wrapper('mac.sh')
        self.assertTrue((self.home / '.claude/skills/retro/SKILL.md').is_file())
        self.assertTrue((self.home / 'state/skills/.skill-lock.json').is_file())
        self.env['BAN_MATT_POCOCK_SKILLS'] = '1'
        self.wrapper('mac.sh')
        self.assertFalse((self.shared / 'new-upstream-skill').exists())
        self.assertEqual(json.loads((self.home / 'state/skills/.skill-lock.json').read_text())['skills'], {})

    def test_both_optouts_remove_all_global_copies_and_future_inventory_offline(self):
        for script in ('mac.sh', 'win.ps1'):
            if script == 'win.ps1' and not PWSH:
                continue
            for ban in ('BAN_MATT_POCOCK_SKILLS', 'BAN_MATT_POCKOCK_SKILLS'):
                with self.subTest(script=script, ban=ban):
                    self.wrapper(script)
                    for base in self.all_dirs():
                        for name in KNOWN + ['new-upstream-skill', 'diagnose', 'zoom-out']:
                            self.put(base / name / 'SKILL.md')
                        self.put(base / 'keep-me/SKILL.md')
                    calls = Path(self.env['SKILL_TEST_CALLS']).read_text()
                    self.env[ban] = '1'
                    self.env['SKILL_TEST_MODE'] = 'bad-runtime'
                    self.wrapper(script)
                    self.wrapper(script)
                    self.env.pop(ban)
                    self.env.pop('SKILL_TEST_MODE')
                    self.assertEqual(Path(self.env['SKILL_TEST_CALLS']).read_text(), calls)
                    for base in self.all_dirs():
                        self.assertEqual(list(p.name for p in base.iterdir()), ['keep-me'])

    def test_retirement_covers_all_profiles_links_and_both_lock_paths(self):
        target = self.put(self.home / 'sentinel/SKILL.md', 'PRIVATE-SENTINEL').parent
        for script in SCRIPTS:
            if script == 'win.ps1' and not PWSH:
                continue
            with self.subTest(script=script):
                for base in self.all_dirs():
                    self.put(base / 'pr-lens/references/config.md', 'modified by user')
                    self.put(base / 'keep-me/SKILL.md')
                shutil.rmtree(self.shared / 'pr-lens')
                (self.shared / 'pr-lens').symlink_to(target, target_is_directory=True)
                self.put(self.custom_pi / 'skills/pr-lens.md')
                self.env['XDG_STATE_HOME'] = str(self.home / 'state')
                locks = [self.home / '.agents/.skill-lock.json', self.home / 'state/skills/.skill-lock.json']
                for lock in locks:
                    self.put(lock, json.dumps({'version': 3, 'skills': {'pr-lens': {'source': 'coldteadotai/pr-lens'}, 'keep': {'source': 'other/repo'}}, 'dismissed': {'keep': True}}))
                self.wrapper(script, 'retire')
                self.wrapper(script, 'retire')
                for base in self.all_dirs():
                    self.assertFalse(os.path.lexists(base / 'pr-lens'))
                    self.assertTrue((base / 'keep-me/SKILL.md').is_file())
                self.assertFalse((self.custom_pi / 'skills/pr-lens.md').exists())
                self.assertEqual((target / 'SKILL.md').read_text(), 'PRIVATE-SENTINEL')
                for lock in locks:
                    self.assertEqual(json.loads(lock.read_text()), {'version': 3, 'skills': {'keep': {'source': 'other/repo'}}, 'dismissed': {'keep': True}})

    def test_simple_english_retirement_preserves_other_skills_and_unrelated_data(self):
        target = self.put(self.home / 'sentinel/SKILL.md', 'PRIVATE-SENTINEL').parent
        project = self.put(self.home / 'project/.agents/skills/simple-english/SKILL.md', 'project copy')
        env_file = self.put(self.home / '.env.local', 'PRIVATE-SENTINEL existing environment')
        self.env['XDG_STATE_HOME'] = str(self.home / 'state')
        locks = [self.home / '.agents/.skill-lock.json', self.home / 'state/skills/.skill-lock.json']
        preserved_entries = {'show-me': {'source': 'humanlayer/skills'}, 'tdd': {'source': 'mattpocock/skills'},
                             'pr-lens': {'source': 'coldteadotai/pr-lens'}}
        for script in SCRIPTS:
            if script == 'win.ps1' and not PWSH:
                continue
            for work in ('0', '1'):
                with self.subTest(script=script, work=work):
                    self.env['WORK_MACHINE'] = work
                    for base in self.all_dirs():
                        self.put(base / 'simple-english/SKILL.md', 'user-modified copy')
                        self.put(base / 'show-me/SKILL.md', 'keep show-me')
                        self.put(base / 'tdd/SKILL.md', 'keep tdd')
                    shutil.rmtree(self.shared / 'simple-english')
                    (self.shared / 'simple-english').symlink_to(target, target_is_directory=True)
                    for profile in (self.default_pi, self.custom_pi):
                        self.put(profile / 'skills/simple-english.md', 'flat skill')
                    for lock in locks:
                        self.put(lock, json.dumps({'version': 3, 'skills': {**preserved_entries,
                            'simple-english': {'source': 'AminBlg/SimpleEnglish'}}, 'dismissed': {'keep': True}}))
                    self.wrapper(script, 'retire-simple')
                    self.wrapper(script, 'retire-simple')
                    for base in self.all_dirs():
                        self.assertFalse(os.path.lexists(base / 'simple-english'))
                        self.assertEqual((base / 'show-me/SKILL.md').read_text(), 'keep show-me')
                        self.assertEqual((base / 'tdd/SKILL.md').read_text(), 'keep tdd')
                    for profile in (self.default_pi, self.custom_pi):
                        self.assertFalse((profile / 'skills/simple-english.md').exists())
                    for lock in locks:
                        self.assertEqual(json.loads(lock.read_text()), {'version': 3, 'skills': preserved_entries, 'dismissed': {'keep': True}})
        self.assertEqual((target / 'SKILL.md').read_text(), 'PRIVATE-SENTINEL')
        self.assertEqual(env_file.read_text(), 'PRIVATE-SENTINEL existing environment')
        self.assertEqual(project.read_text(), 'project copy')
        self.assertFalse(Path(self.env['SKILL_TEST_CALLS']).exists())

    def test_simple_english_retirement_rejects_unsafe_paths_and_respects_blocked_profiles(self):
        keep = self.put(self.shared / 'simple-english/SKILL.md')
        for profile in (self.default_pi, self.custom_pi):
            self.put(profile / 'skills/simple-english/SKILL.md')
            self.put(profile / 'settings.json', 'PRIVATE-SENTINEL malformed')
        target = self.put(self.home / 'sentinel/simple-english/SKILL.md', 'PRIVATE-SENTINEL').parent.parent
        linked = self.home / '.gemini/skills'
        linked.parent.mkdir()
        linked.symlink_to(target, target_is_directory=True)
        self.policy('remove-simple-english', success=False)
        self.assertTrue(keep.is_file())
        self.assertTrue((target / 'simple-english/SKILL.md').exists())
        linked.unlink()
        lock = self.put(self.home / '.agents/.skill-lock.json', 'PRIVATE-SENTINEL malformed')
        self.policy('remove-simple-english', success=False)
        self.assertTrue(keep.is_file())
        lock.unlink()
        lock_target = self.put(self.home / 'lock-target.json', '{"version":3,"skills":{}}')
        lock.symlink_to(lock_target)
        self.policy('remove-simple-english', success=False)
        self.assertTrue(keep.is_file())
        lock.unlink()
        for script in ('mac.sh', 'win.ps1'):
            if script == 'win.ps1' and not PWSH:
                continue
            self.put(keep)
            self.wrapper(script, 'retire-simple', blocked=True, success=False)
            self.assertFalse(keep.exists())
        for profile in (self.default_pi, self.custom_pi):
            self.assertTrue((profile / 'skills/simple-english/SKILL.md').exists())
            self.assertEqual((profile / 'settings.json').read_text(), 'PRIVATE-SENTINEL malformed')

    def test_all_three_retirements_preserve_full_suite_on_personal_and_work_machines(self):
        retired = {'simple-english': ('retire-simple', 'AminBlg/SimpleEnglish'),
                   'show-me': ('retire-show', 'humanlayer/skills'),
                   'pr-lens': ('retire', 'coldteadotai/pr-lens')}
        sentinel = self.put(self.home / 'sentinel/SKILL.md', 'PRIVATE-SENTINEL')
        project = self.put(self.home / 'project/.agents/skills/show-me/SKILL.md', 'project copy')
        env_file = self.put(self.home / '.env.local', 'PRIVATE-SENTINEL existing environment')
        self.env['XDG_STATE_HOME'] = str(self.home / 'state')
        locks = [self.home / '.agents/.skill-lock.json', self.home / 'state/skills/.skill-lock.json']
        for script in SCRIPTS:
            if script == 'win.ps1' and not PWSH:
                continue
            for work in ('0', '1'):
                with self.subTest(script=script, work=work):
                    self.env['WORK_MACHINE'] = work
                    self.wrapper(script)
                    calls = Path(self.env['SKILL_TEST_CALLS']).read_bytes()
                    for base in self.all_dirs():
                        for skill in retired:
                            self.put(base / skill / 'SKILL.md', 'user-modified retired skill')
                        self.put(base / 'keep-me/SKILL.md', 'keep unrelated skill')
                    shutil.rmtree(self.shared / 'show-me')
                    (self.shared / 'show-me').symlink_to(sentinel.parent, target_is_directory=True)
                    for profile in (self.default_pi, self.custom_pi):
                        for skill in retired:
                            # Also cover dangling direct Markdown links without following targets.
                            (profile / 'skills' / (skill + '.md')).symlink_to(self.home / 'missing-target.md')
                    expected_locks = {}
                    for lock in locks:
                        data = json.loads(lock.read_text()) if lock.exists() else {
                            'version': 3, 'skills': {'keep': {'source': 'other/repo'}}, 'dismissed': {'keep': True}}
                        expected_locks[lock] = json.loads(json.dumps(data))
                        data['skills'].update({skill: {'source': source} for skill, (_, source) in retired.items()})
                        self.put(lock, json.dumps(data))
                    # Retirement does not need a skills CLI runtime or permission to install skills.
                    self.env['SKILL_TEST_MODE'] = 'bad-runtime'
                    for _ in range(2):
                        for operation, _source in retired.values():
                            self.wrapper(script, operation)
                    self.env.pop('SKILL_TEST_MODE')
                    self.wrapper(script, 'ownership')
                    for base in self.all_dirs():
                        for skill in retired:
                            self.assertFalse(os.path.lexists(base / skill))
                        self.assertEqual((base / 'keep-me/SKILL.md').read_text(), 'keep unrelated skill')
                    for profile in (self.default_pi, self.custom_pi):
                        for skill in retired:
                            self.assertFalse(os.path.lexists(profile / 'skills' / (skill + '.md')))
                            self.assertNotIn(skill, (profile / 'settings.json').read_text())
                    for lock in locks:
                        self.assertEqual(json.loads(lock.read_text()), expected_locks[lock])
                    for base in (self.shared, Path(self.env['CLAUDE_CONFIG_DIR']) / 'skills'):
                        for name in KNOWN + ['new-upstream-skill']:
                            self.assertGreater((base / name / 'SKILL.md').stat().st_size, 0)
                            self.assertEqual((base / name / 'references/guide.md').read_text(), 'Upstream fixture: do not execute.\n')
                    self.assertEqual(Path(self.env['SKILL_TEST_CALLS']).read_bytes(), calls)
        self.assertEqual(sentinel.read_text(), 'PRIVATE-SENTINEL')
        self.assertEqual(project.read_text(), 'project copy')
        self.assertEqual(env_file.read_text(), 'PRIVATE-SENTINEL existing environment')

    def test_show_me_retirement_rejects_unsafe_paths_and_respects_blocked_profiles(self):
        keep = self.put(self.shared / 'show-me/SKILL.md')
        for profile in (self.default_pi, self.custom_pi):
            self.put(profile / 'skills/show-me/SKILL.md')
            self.put(profile / 'settings.json', 'PRIVATE-SENTINEL malformed')
        target = self.put(self.home / 'sentinel/show-me/SKILL.md', 'PRIVATE-SENTINEL').parent.parent
        linked = self.home / '.gemini/skills'
        linked.parent.mkdir()
        linked.symlink_to(target, target_is_directory=True)
        self.policy('remove-show-me', success=False)
        self.assertTrue(keep.is_file())
        self.assertTrue((target / 'show-me/SKILL.md').exists())
        linked.unlink()
        lock = self.put(self.home / '.agents/.skill-lock.json', 'PRIVATE-SENTINEL malformed')
        self.policy('remove-show-me', success=False)
        self.assertTrue(keep.is_file())
        lock.unlink()
        lock_target = self.put(self.home / 'lock-target.json', '{"version":3,"skills":{}}')
        lock.symlink_to(lock_target)
        self.policy('remove-show-me', success=False)
        self.assertTrue(keep.is_file())
        lock.unlink()
        for script in SCRIPTS:
            if script == 'win.ps1' and not PWSH:
                continue
            self.put(keep)
            self.wrapper(script, 'retire-show', blocked=True, success=False)
            self.assertFalse(keep.exists())
        for profile in (self.default_pi, self.custom_pi):
            self.assertTrue((profile / 'skills/show-me/SKILL.md').exists())
            self.assertEqual((profile / 'settings.json').read_text(), 'PRIVATE-SENTINEL malformed')

    def test_retirement_preflight_rejects_linked_ancestors_before_any_removal(self):
        keep = self.put(self.shared / 'pr-lens/SKILL.md')
        target = self.put(self.home / 'sentinel/pr-lens/SKILL.md', 'PRIVATE-SENTINEL').parent.parent
        (self.home / '.gemini').mkdir()
        (self.home / '.gemini/skills').symlink_to(target, target_is_directory=True)
        self.policy('remove-pr-lens', success=False)
        self.assertTrue(keep.is_file())
        self.assertTrue((target / 'pr-lens/SKILL.md').is_file())

    def test_retirement_rejects_malformed_and_linked_metadata(self):
        keep = self.put(self.shared / 'pr-lens/SKILL.md')
        lock = self.put(self.home / '.agents/.skill-lock.json', 'PRIVATE-SENTINEL malformed')
        self.policy('remove-pr-lens', success=False)
        self.assertTrue(keep.is_file())
        lock.unlink()
        target = self.put(self.home / 'sentinel.json', '{"version":3,"skills":{}}')
        lock.symlink_to(target)
        self.policy('remove-pr-lens', success=False)
        self.assertTrue(keep.is_file())
        self.assertEqual(target.read_text(), '{"version":3,"skills":{}}')

    def test_failures_never_accept_old_or_partial_installations(self):
        for script in ('mac.sh', 'win.ps1'):
            if script == 'win.ps1' and not PWSH:
                continue
            for mode in ('failed-command', 'partial-report', 'failed-result', 'skipped-result', 'missing-agent',
                         'wrong-source', 'duplicate-name', 'unsafe-name', 'invalid-json', 'bad-runtime', 'failed-npm-config'):
                with self.subTest(script=script, mode=mode):
                    self.env.pop('SKILL_TEST_MODE', None)
                    self.wrapper(script)
                    before = (self.home / '.agents/.setup-matt-pocock-skills.json').read_bytes()
                    self.env['SKILL_TEST_MODE'] = mode
                    self.wrapper(script, success=False)
                    self.assertEqual((self.home / '.agents/.setup-matt-pocock-skills.json').read_bytes(), before)

    def test_incomplete_or_invalid_snapshot_cannot_mutate_any_destination(self):
        modes = ('failed-command', 'partial-report', 'omit-future-report', 'unreported-directory',
                 'different-copy', 'invalid-lock', 'missing-lock', 'wrong-lock-source', 'extra-lock-entry')
        for script in ('mac.sh', 'win.ps1'):
            if script == 'win.ps1' and not PWSH:
                continue
            self.env.pop('SKILL_TEST_MODE', None)
            self.wrapper(script)
            before = self.snapshot()
            for mode in modes:
                with self.subTest(script=script, mode=mode):
                    self.env['SKILL_TEST_MODE'] = mode
                    self.wrapper(script, success=False)
                    self.assertEqual(self.snapshot(), before)

    def test_stage_disposal_unlinks_external_links_without_following_targets(self):
        target = self.put(self.home / 'external/SKILL.md', 'PRIVATE-SENTINEL').parent
        stage = Path(self.policy('stage').stdout.strip())
        (stage / 'linked-directory').symlink_to(target, target_is_directory=True)
        (stage / 'linked-file').symlink_to(target / 'SKILL.md')
        before = self.snapshot()
        self.policy('dispose', argument=stage)
        self.assertFalse(stage.exists())
        self.assertEqual(self.snapshot(), before)
        # A swapped root must also be unlinked, never recursively followed.
        stage = Path(self.policy('stage').stdout.strip())
        stage.rmdir(); stage.symlink_to(target, target_is_directory=True)
        self.policy('dispose', argument=stage)
        self.assertFalse(os.path.lexists(stage))
        self.assertEqual(self.snapshot(), before)
        self.policy('dispose', argument=target, success=False)
        self.assertEqual(self.snapshot(), before)

    def test_disposal_is_independent_of_changed_global_metadata(self):
        stage = Path(self.policy('stage').stdout.strip())
        self.put(stage / '.agents/skills/tdd/SKILL.md', 'inert')
        self.put(self.home / '.agents/.skill-lock.json', 'PRIVATE-SENTINEL malformed')
        before = self.snapshot()
        self.policy('dispose', argument=stage)
        self.assertFalse(stage.exists())
        self.assertEqual(self.snapshot(), before)

    def test_promotion_preserves_unrelated_lock_data_and_effective_npm_configuration(self):
        self.env['XDG_STATE_HOME'] = str(self.home / 'state')
        self.env['npm_config_userconfig'] = str(self.home / 'userconfig.npmrc')
        self.env['NPM_CONFIG_USERCONFIG'] = str(self.home / 'unused-uppercase.npmrc')
        self.env['npm_config_globalconfig'] = str(self.home / 'globalconfig.npmrc')
        self.env['NPM_CONFIG_GLOBALCONFIG'] = str(self.home / 'unused-global-uppercase.npmrc')
        configs = [self.put(self.home / name, 'PRIVATE-SENTINEL preserve npm policy') for name in
                   ('userconfig.npmrc', 'globalconfig.npmrc', 'unused-uppercase.npmrc', 'unused-global-uppercase.npmrc')]
        legacy = self.put(self.home / '.agents/.skill-lock.json', json.dumps({'version': 3, 'skills': {
            'unrelated': {'source': 'other/repo'}, 'tdd': {'source': 'mattpocock/skills'}}}))
        before = legacy.read_bytes()
        selected = self.home / 'state/skills/.skill-lock.json'
        for script in ('mac.sh', 'win.ps1'):
            if script == 'win.ps1' and not PWSH:
                continue
            self.put(selected, json.dumps({'version': 3, 'skills': {'unrelated': {'source': 'other/repo'},
                                           'tdd': {'source': 'mattpocock/skills', 'installedAt': 'original-install-time'}},
                                           'dismissed': {'keep': True}, 'custom': 'preserve'}))
            self.wrapper(script)
            data = json.loads(selected.read_text())
            self.assertEqual(data['skills']['unrelated'], {'source': 'other/repo'})
            self.assertEqual(data['skills']['tdd']['installedAt'], 'original-install-time')
            self.assertEqual(data['dismissed'], {'keep': True})
            self.assertEqual(data['custom'], 'preserve')
            self.assertEqual(data['skills']['new-upstream-skill']['source'], 'mattpocock/skills')
            self.assertEqual(legacy.read_bytes(), before)
            for config in configs:
                self.assertEqual(config.read_text(), 'PRIVATE-SENTINEL preserve npm policy')

    def test_all_reported_skills_validate_both_copies_and_nested_links(self):
        for script in ('mac.sh', 'win.ps1'):
            if script == 'win.ps1' and not PWSH:
                continue
            for mode in ('missing-file', 'empty-file', 'linked-file', 'linked-references', 'directory-file'):
                for copy in ('0', '1'):
                    with self.subTest(script=script, mode=mode, copy=copy):
                        for base in (self.shared, Path(self.env['CLAUDE_CONFIG_DIR']) / 'skills'):
                            shutil.rmtree(base, ignore_errors=True)
                        self.env['SKILL_TEST_MODE'] = mode
                        self.env['SKILL_TEST_COPY'] = copy
                        self.wrapper(script, success=False)

    def test_ownership_uses_future_inventory_and_preserves_modified_copies(self):
        for script in ('mac.sh', 'win.ps1'):
            if script == 'win.ps1' and not PWSH:
                continue
            self.wrapper(script)
            for profile in (self.default_pi, self.custom_pi):
                for name in ('new-upstream-skill', 'retro'):
                    dest = profile / 'skills' / name
                    shutil.rmtree(dest, ignore_errors=True)
                    dest.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copytree(self.shared / name, dest)
                self.put(profile / 'skills/retro/references/guide.md', 'user modified')
                self.put(profile / 'settings.json', '{"theme":"keep","skills":["custom"]}')
            self.wrapper(script, 'ownership')
            self.wrapper(script, 'ownership')
            for profile in (self.default_pi, self.custom_pi):
                self.assertFalse((profile / 'skills/new-upstream-skill').exists())
                self.assertEqual((profile / 'skills/retro/references/guide.md').read_text(), 'user modified')
                settings = json.loads((profile / 'settings.json').read_text())
                self.assertEqual(settings['theme'], 'keep')
                self.assertEqual(settings['skills'].count('!' + str(profile / 'skills/retro') + '/**'), 1)
                self.assertNotIn('!' + str(self.shared / 'retro') + '/**', settings['skills'])
                self.assertIn('custom', settings['skills'])

    def test_blocked_profiles_are_untouched_and_unrelated_cleanup_continues(self):
        for profile in (self.default_pi, self.custom_pi):
            self.put(profile / 'settings.json', 'PRIVATE-SENTINEL malformed')
            self.put(profile / 'skills/pr-lens/SKILL.md')
            self.put(profile / 'skills/tdd/SKILL.md')
        self.put(self.shared / 'pr-lens/SKILL.md')
        self.put(self.shared / 'tdd/SKILL.md')
        self.policy('remove-pr-lens', blocked=True, success=False)
        self.policy('remove-matt', blocked=True)
        for script in ('mac.sh', 'win.ps1'):
            if script != 'win.ps1' or PWSH:
                self.wrapper(script, 'ownership', blocked=True)
        for profile in (self.default_pi, self.custom_pi):
            self.assertEqual((profile / 'settings.json').read_text(), 'PRIVATE-SENTINEL malformed')
            self.assertTrue((profile / 'skills/pr-lens/SKILL.md').exists())
            self.assertTrue((profile / 'skills/tdd/SKILL.md').exists())
        self.assertFalse((self.shared / 'pr-lens').exists())
        self.assertFalse((self.shared / 'tdd').exists())

    @unittest.skipUnless(sys.platform == 'linux', 'Linux-only trusted system alias')
    def test_trusted_system_home_alias_with_temporary_filesystem(self):
        root = self.root / 'system'
        real_home = root / 'var/home/account'
        real_home.mkdir(parents=True)
        alias = root / 'home'
        alias.symlink_to('var/home', target_is_directory=True)
        system_paths = [root, alias, root / 'var', root / 'var/home']
        for directory in (root, root / 'var', root / 'var/home'):
            directory.chmod(0o755)
        # Map only the helper's literal system paths. No real /home tree is used.
        code = embedded('bazzite.sh')
        for literal in ('/var/home', '/home', '/var', '/'):
            code = code.replace(repr(literal), json.dumps(str(root / literal.lstrip('/'))))
        helper = self.put(self.root / 'alias-policy.cjs', code)
        shim = self.put(self.root / 'root-uid.cjs', '''
const fs = require('node:fs');
const original = fs.lstatSync;
const roots = JSON.parse(process.env.FIXTURE_ROOTS);
fs.lstatSync = (file, ...args) => {
    const value = original(file, ...args);
    if (roots.includes(file)) value.uid = process.env.UNTRUSTED_ROOT === file ? 12345 : 0;
    return value;
};
''')
        env = {**self.env, 'FIXTURE_ROOTS': json.dumps([str(p) for p in system_paths])}
        env.pop('CLAUDE_CONFIG_DIR', None)
        env.pop('CODEX_HOME', None)
        command = [NODE, '--require', str(shim), str(helper), str(alias / 'account'), '', '0', 'names']
        def run(ok, **extra):
            result = subprocess.run(command, env={**env, **extra}, capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode == 0, ok, result.stderr)
        run(True)
        for file in system_paths:
            run(False, UNTRUSTED_ROOT=str(file))
        for directory in (root, root / 'var', root / 'var/home'):
            directory.chmod(0o775)
            run(False)
            directory.chmod(0o755)
        alias.unlink()
        alias.symlink_to(root / 'var/home', target_is_directory=True)
        run(True)
        alias.unlink()
        alias.symlink_to('var/../var/home', target_is_directory=True)
        run(False)

    def test_optout_removes_leaf_links_without_following_targets_or_touching_projects(self):
        target = self.put(self.home / 'sentinel/keep', 'PRIVATE-SENTINEL').parent
        project = self.put(self.home / 'project/.agents/skills/tdd/SKILL.md', 'project')
        self.shared.mkdir(parents=True)
        (self.shared / 'tdd').symlink_to(target, target_is_directory=True)
        (self.shared / 'diagnose').symlink_to(self.home / 'missing', target_is_directory=True)
        self.put(self.shared / 'retro/references/guide.md')
        (self.shared / 'retro/linked-dir').symlink_to(target, target_is_directory=True)
        self.policy('remove-matt')
        self.policy('remove-matt')
        self.assertFalse(os.path.lexists(self.shared / 'tdd'))
        self.assertFalse(os.path.lexists(self.shared / 'diagnose'))
        self.assertFalse((self.shared / 'retro').exists())
        self.assertEqual((target / 'keep').read_text(), 'PRIVATE-SENTINEL')
        self.assertEqual(project.read_text(), 'project')

    @unittest.skipUnless(os.environ.get('MANAGED_SKILLS_CLI'), 'Set MANAGED_SKILLS_CLI for offline native discovery coverage')
    def test_native_cli_discovers_all_categories_and_emits_expected_json(self):
        source = self.home / 'upstream-fixture'
        categories = ['engineering'] * 18 + ['in-progress'] * 8 + ['misc'] * 4 + ['productivity'] * 7
        for name, category in zip(KNOWN, categories):
            self.put(source / 'skills' / category / name / 'SKILL.md', f'---\nname: {name}\ndescription: Inert skill fixture.\n---\nNever execute.\n')
            self.put(source / 'skills' / category / name / 'references/guide.md', 'reference')
        self.put(source / '.claude-plugin/plugin.json', json.dumps({'name': 'fixture', 'skills': ['./skills/engineering/tdd']}))
        blocker = self.put(self.home / 'block-network.cjs', '''
const deny = () => { throw new Error('NETWORK_OR_CHILD_PROCESS_FORBIDDEN'); };
globalThis.fetch = deny;
for (const module of ['node:http', 'node:https']) {
    const api = require(module); api.request = deny; api.get = deny;
}
const net = require('node:net'); net.connect = deny; net.createConnection = deny;
const cp = require('node:child_process');
for (const method of ['spawn', 'spawnSync', 'exec', 'execSync', 'execFile', 'execFileSync']) cp[method] = deny;
require('node:module').syncBuiltinESMExports();
''')
        env = {k: v for k, v in self.env.items() if not k.startswith('GIT_')}
        env.update(XDG_CONFIG_HOME=str(self.home / '.config'), XDG_CACHE_HOME=str(self.home / '.cache'),
                   XDG_DATA_HOME=str(self.home / '.local/share'), DISABLE_TELEMETRY='1')
        discovery = subprocess.run([NODE, '--require', str(blocker), os.environ['MANAGED_SKILLS_CLI'],
                                    'add', str(source), '--list', '--full-depth', '--yes', '--json'],
                                   env=env, text=True, capture_output=True, timeout=60)
        self.assertNotEqual(discovery.returncode, 0)
        self.assertIn('cannot be combined with --list', json.loads(discovery.stdout)[0]['error'])
        self.assertFalse(self.shared.exists())
        result = subprocess.run([NODE, '--require', str(blocker), os.environ['MANAGED_SKILLS_CLI'],
                                 'add', str(source), '--global', '--agent', 'claude-code', '--agent', 'codex',
                                 '--agent', 'gemini-cli', '--skill', '*', '--full-depth', '--copy', '--yes', '--json'],
                                env=env, text=True, capture_output=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        report = json.loads(result.stdout)
        self.assertEqual({entry['name'] for entry in report}, set(KNOWN))
        for entry in report:
            self.assertEqual(entry['status'], 'installed')
            self.assertEqual(entry['mode'], 'copy')
            self.assertEqual(entry['scope'], 'global')
            self.assertEqual(set(entry['agents']), {'Claude Code', 'Codex', 'Gemini CLI'})
        for name, category in zip(KNOWN, categories):
            for base in (self.shared, Path(self.env['CLAUDE_CONFIG_DIR']) / 'skills'):
                self.assertEqual((base / name / 'SKILL.md').read_bytes(), (source / 'skills' / category / name / 'SKILL.md').read_bytes())
                self.assertEqual((base / name / 'references/guide.md').read_text(), 'reference')
        self.assertFalse((self.home / '.gemini/skills').exists())
        self.assertFalse((self.custom_pi / 'skills').exists())

    @unittest.skipUnless(os.environ.get('MANAGED_SKILLS_CLI'), 'Set MANAGED_SKILLS_CLI for offline native snapshot coverage')
    def test_native_snapshot_promotes_without_reselecting_a_changed_upstream(self):
        source = self.root / 'upstream'
        names = KNOWN + ['new-upstream-skill']
        for name in names:
            self.put(source / 'skills/in-progress' / name / 'SKILL.md',
                     f'---\nname: {name}\ndescription: Inert fixture.\n---\nNever execute.\n')
            self.put(source / 'skills/in-progress' / name / 'references/guide.md', 'snapshot content')
        hooks = self.root / 'empty-hooks'
        hooks.mkdir()
        config = self.put(self.root / 'gitconfig',
                          f'[core]\n\thooksPath = {hooks}\n[url "{source.as_uri()}"]\n'
                          '\tinsteadOf = https://github.com/mattpocock/skills.git\n')
        # Clear every inherited Git control, then add only fixture-owned values.
        env = {k: v for k, v in self.env.items() if not k.startswith('GIT_') and k not in ('GH_TOKEN', 'GITHUB_TOKEN')}
        env.update(GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_GLOBAL=str(config), GIT_TEMPLATE_DIR=str(hooks),
                   GIT_TERMINAL_PROMPT='0', GIT_ALLOW_PROTOCOL='file', DISABLE_TELEMETRY='1')
        def git(*args):
            return subprocess.run(['git', '-C', str(source), '-c', 'user.name=Fixture',
                                   '-c', 'user.email=fixture@example.invalid', '-c', 'commit.gpgsign=false', *args],
                                  env=env, check=True, text=True, capture_output=True, timeout=30).stdout.strip()
        git('init')
        self.assertEqual(Path(git('rev-parse', '--show-toplevel')).resolve(), source.resolve())
        git('add', '.')
        git('commit', '-m', 'Inert snapshot')
        blocker = self.put(self.root / 'offline-native.cjs', '''
const deny = () => { throw new Error('NETWORK_OR_CHILD_PROCESS_FORBIDDEN'); };
globalThis.fetch = deny;
for (const name of ['node:http', 'node:https']) {
    const api = require(name); api.request = deny; api.get = deny;
}
const net = require('node:net'); net.connect = deny; net.createConnection = deny;
const cp = require('node:child_process'), spawn = cp.spawn;
for (const method of ['spawn', 'spawnSync', 'exec', 'execSync', 'execFile', 'execFileSync']) cp[method] = deny;
cp.spawn = (command, args, options) => {
    // Native simple-git may only clone the inert repository. Even if URL rewriting
    // fails, file-only transport prevents a network request or credential lookup.
    if (command !== 'git' || !args.includes('clone') || !args.includes('https://github.com/mattpocock/skills.git')) deny();
    return spawn(command, args, {...options, env: {...options.env, GIT_ALLOW_PROTOCOL: 'file'}});
};
require('node:module').syncBuiltinESMExports();
''')
        stage = Path(self.policy('stage').stdout.strip())
        env.update(HOME=str(stage), USERPROFILE=str(stage), CLAUDE_CONFIG_DIR=str(stage / '.claude'),
                   CODEX_HOME=str(stage / '.codex'), XDG_STATE_HOME=str(stage / '.state'))
        try:
            result = subprocess.run([NODE, '--require', str(blocker), os.environ['MANAGED_SKILLS_CLI'],
                                     'add', 'mattpocock/skills', '--global', '--agent', 'claude-code', '--agent', 'codex',
                                     '--agent', 'gemini-cli', '--skill', '*', '--full-depth', '--copy', '--yes', '--json'],
                                    env=env, text=True, capture_output=True, timeout=60)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            report = json.loads(result.stdout)
            self.assertEqual({entry['name'] for entry in report}, set(names))
            self.assertTrue(all(entry['source'] == 'mattpocock/skills' for entry in report))
            self.put(stage / 'report.json', result.stdout)
            target = self.put(self.home / 'sentinel/SKILL.md', 'PRIVATE-SENTINEL').parent
            for base in (self.shared, Path(self.env['CLAUDE_CONFIG_DIR']) / 'skills'):
                self.put(base / 'tdd/SKILL.md', 'previous copy')
                (base / 'omarchy').symlink_to(self.home / 'missing', target_is_directory=True)
            collision = self.shared / 'new-upstream-skill'
            collision.symlink_to(target, target_is_directory=True)
            before = self.snapshot()
            self.policy('promote', argument=stage, success=False)
            self.assertEqual(self.snapshot(), before)
            collision.unlink()
            # Advancing the source after discovery cannot introduce an unchecked
            # destination name or change the bytes of the promoted snapshot.
            self.put(source / 'skills/in-progress/another-future-name/SKILL.md',
                     '---\nname: another-future-name\ndescription: New fixture.\n---\nNever execute.\n')
            self.put(source / 'skills/in-progress/tdd/references/guide.md', 'changed upstream')
            git('add', '.')
            git('commit', '-m', 'Advance inert source after staging')
            self.policy('promote', argument=stage)
            for base in (self.shared, Path(self.env['CLAUDE_CONFIG_DIR']) / 'skills'):
                self.assertTrue((base / 'omarchy').is_symlink())
                self.assertFalse((base / 'another-future-name').exists())
                for name in names:
                    self.assertEqual((base / name / 'references/guide.md').read_text(), 'snapshot content')
            data = json.loads((self.home / '.agents/.skill-lock.json').read_text())
            self.assertEqual(set(data['skills']), set(names))
            self.assertEqual(data['skills']['new-upstream-skill']['sourceType'], 'github')
            self.assertEqual((target / 'SKILL.md').read_text(), 'PRIVATE-SENTINEL')
        finally:
            shutil.rmtree(stage)

    @unittest.skipUnless(os.environ.get('PI_SKILLS_DOTFILES_SOURCE'), 'Set PI_SKILLS_DOTFILES_SOURCE for render/setup coverage')
    def test_dotfiles_render_preserves_future_skill_exclusions(self):
        source = Path(os.environ['PI_SKILLS_DOTFILES_SOURCE'])
        template = source / 'private_dot_pi/agent/private_settings.json.tmpl'
        empty_source = self.home / 'empty-source'
        empty_source.mkdir()
        config = self.put(self.home / 'chezmoi.json', '{}')
        for platform in ('linux', 'darwin', 'windows'):
            for _ in range(2):
                self.wrapper('mac.sh')
                self.wrapper('mac.sh', 'ownership')
                result = subprocess.run([
                    'chezmoi', '--config', str(config), '--source', str(empty_source),
                    '--destination', str(self.home), '--cache', str(self.home / 'cache'),
                    '--persistent-state', str(self.home / 'state.boltdb'),
                    '--override-data', json.dumps({'chezmoi': {'homeDir': str(self.home), 'os': platform}}),
                    'execute-template', '--file', str(template),
                ], env=self.env, capture_output=True, text=True, check=True, timeout=30)
                settings = json.loads(result.stdout)
                self.assertEqual(settings['skills'].count('!' + str(self.default_pi / 'skills/new-upstream-skill') + '/**'), 1)
                self.assertNotIn('pr-lens', result.stdout)
                self.assertNotIn('simple-english', result.stdout)
                self.assertNotIn('show-me', result.stdout)
                self.assertIn('npm:pi-claude-bridge', settings['packages'])
                self.put(self.default_pi / 'settings.json', result.stdout)
                self.assertTrue((self.shared / 'new-upstream-skill/SKILL.md').is_file())

    def test_ownership_rejects_linked_shared_root_and_malformed_settings_before_removal(self):
        for profile in (self.default_pi, self.custom_pi):
            self.put(profile / 'skills/tdd/SKILL.md', 'matching')
        self.put(self.shared / 'tdd/SKILL.md', 'matching')
        settings = self.put(self.custom_pi / 'settings.json', 'PRIVATE-SENTINEL malformed')
        self.policy('ownership', success=False)
        self.assertTrue((self.default_pi / 'skills/tdd/SKILL.md').exists())
        settings.write_text('{}')
        target = self.home / 'linked-shared'
        self.shared.rename(target)
        self.shared.symlink_to(target, target_is_directory=True)
        self.policy('ownership', success=False)
        self.assertTrue((self.default_pi / 'skills/tdd/SKILL.md').exists())

    def test_unrelated_live_and_dangling_links_survive_installation(self):
        for script in SCRIPTS:
            if script == 'win.ps1' and not PWSH:
                continue
            for live in (False, True):
                with self.subTest(script=script, live=live):
                    target = self.home / ('sentinel' if live else 'missing')
                    if live:
                        self.put(target / 'SKILL.md', 'PRIVATE-SENTINEL')
                    links = []
                    for base in (self.shared, Path(self.env['CLAUDE_CONFIG_DIR']) / 'skills'):
                        base.mkdir(parents=True, exist_ok=True)
                        link = base / 'omarchy'
                        link.unlink(missing_ok=True)
                        link.symlink_to(target, target_is_directory=True)
                        links.append((link, link.lstat().st_ino, os.readlink(link)))
                    self.wrapper(script)
                    for link, inode, value in links:
                        self.assertTrue(link.is_symlink())
                        self.assertEqual(link.lstat().st_ino, inode)
                        self.assertEqual(os.readlink(link), value)
                        link.unlink()
                    if live:
                        self.assertEqual((target / 'SKILL.md').read_text(), 'PRIVATE-SENTINEL')
                    else:
                        self.assertFalse(target.exists())
                    self.assertTrue((self.shared / 'new-upstream-skill/SKILL.md').is_file())

    def test_future_selected_name_links_block_before_destination_mutation(self):
        target = self.put(self.home / 'sentinel/SKILL.md', 'PRIVATE-SENTINEL').parent
        keep = self.put(self.shared / 'tdd/SKILL.md', 'previous installation')
        for script in SCRIPTS:
            if script == 'win.ps1' and not PWSH:
                continue
            for base in (self.shared, Path(self.env['CLAUDE_CONFIG_DIR']) / 'skills'):
                for live in (False, True):
                    with self.subTest(script=script, base=base, live=live):
                        base.mkdir(parents=True, exist_ok=True)
                        link = base / 'new-upstream-skill'
                        link.symlink_to(target if live else self.home / 'missing', target_is_directory=True)
                        inode, value = link.lstat().st_ino, os.readlink(link)
                        self.wrapper(script, success=False)
                        self.assertEqual(link.lstat().st_ino, inode)
                        self.assertEqual(os.readlink(link), value)
                        self.assertEqual(keep.read_text(), 'previous installation')
                        self.assertEqual((target / 'SKILL.md').read_text(), 'PRIVATE-SENTINEL')
                        self.assertFalse((self.home / '.agents/.setup-matt-pocock-skills.json').exists())
                        link.unlink()

    def test_future_selected_name_nested_links_block_before_any_destination_mutation(self):
        target = self.put(self.home / 'sentinel/keep', 'PRIVATE-SENTINEL').parent
        self.put(self.shared / 'tdd/SKILL.md', 'previous installation')
        for script in SCRIPTS:
            if script == 'win.ps1' and not PWSH:
                continue
            for base in (self.shared, Path(self.env['CLAUDE_CONFIG_DIR']) / 'skills'):
                for live in (False, True):
                    with self.subTest(script=script, base=base, live=live):
                        skill = base / 'new-upstream-skill'
                        self.put(skill / 'SKILL.md', 'previous future skill')
                        link = skill / 'references'
                        link.unlink(missing_ok=True)
                        link.symlink_to(target if live else self.home / 'missing', target_is_directory=True)
                        before = self.snapshot()
                        self.wrapper(script, success=False)
                        self.assertEqual(self.snapshot(), before)
                        link.unlink()

    def test_install_preflight_stops_before_cli_on_unsafe_metadata_and_paths(self):
        for script in ('mac.sh', 'win.ps1'):
            if script == 'win.ps1' and not PWSH:
                continue
            lock = self.put(self.home / '.agents/.skill-lock.json', 'PRIVATE-SENTINEL malformed')
            self.wrapper(script, success=False)
            self.assertFalse(Path(self.env['SKILL_TEST_CALLS']).exists())
            lock.unlink()
            target = self.put(self.home / 'sentinel/SKILL.md', 'PRIVATE-SENTINEL').parent
            self.shared.mkdir(exist_ok=True)
            (self.shared / 'tdd').symlink_to(target, target_is_directory=True)
            self.wrapper(script, success=False)
            self.assertFalse(Path(self.env['SKILL_TEST_CALLS']).exists())
            (self.shared / 'tdd').unlink()


if __name__ == '__main__':
    unittest.main()
